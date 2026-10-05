-- KOReader userpatch: make highlights respect adjacent punctuation (reflowable docs only).
--
-- 1. When a drag-selection is released, extend it over punctuation that is
--    directly attached to it: opening punctuation before the start
--    (e.g. "(phrase" or “Quote) and trailing punctuation after the end
--    (e.g. "fox." or "said,”").
-- 2. Highlight-dialog adjusters, in word mode:
--    ◁▒▒  takes adjacent opening punctuation first instead of jumping to the
--         previous word; a word move also takes the punctuation before it.
--    ▷☓▒  drops only the opening punctuation if the highlight starts with
--         it; otherwise moves to the next word and keeps its opening punctuation.
--    ▒▒▷  takes adjacent trailing punctuation first instead of jumping to the
--         end of the next word; a word move also takes the punctuation after it.
--    ▒☓◁  drops only the trailing punctuation if the highlight ends with it;
--         otherwise moves to the previous word and keeps its trailing punctuation.
-- So one ▷☓▒ / ▒☓◁ tap undoes an unwanted automatic punctuation extension.
-- Character mode (long-press an adjuster) and PDF/paging documents are unchanged.
-- Delete this file to revert.

local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local TRAILING = {
    ["."] = true, [","] = true, [";"] = true, [":"] = true, ["!"] = true, ["?"] = true,
    ["…"] = true, [")"] = true, ["]"] = true, ["}"] = true, ["»"] = true,
    ["”"] = true, ["’"] = true, ['"'] = true, ["'"] = true,
}
local LEADING = {
    ["("] = true, ["["] = true, ["{"] = true, ["«"] = true, ["¿"] = true, ["¡"] = true,
    ["“"] = true, ["‘"] = true, ['"'] = true, ["'"] = true,
}
local MAX_RUN = 4 -- e.g. ?!” or (“

-- Char immediately after xp, and the xpointer just past it
local function charAfter(doc, xp)
    local nxt = doc:getNextVisibleChar(xp)
    if not nxt or doc:compareXPointers(xp, nxt) ~= 1 then return end
    return doc:getTextFromXPointers(xp, nxt), nxt
end

-- Char immediately before xp, and the xpointer just before it
local function charBefore(doc, xp)
    local prev = doc:getPrevVisibleChar(xp)
    if not prev or doc:compareXPointers(prev, xp) ~= 1 then return end
    return doc:getTextFromXPointers(prev, xp), prev
end

-- Move xp forward over a run of chars in set
local function skipForward(doc, xp, set)
    for _ = 1, MAX_RUN do
        local ch, nxt = charAfter(doc, xp)
        if not (ch and set[ch]) then break end
        xp = nxt
    end
    return xp
end

-- Move xp back over a run of chars in set
local function skipBackward(doc, xp, set)
    for _ = 1, MAX_RUN do
        local ch, prev = charBefore(doc, xp)
        if not (ch and set[ch]) then break end
        xp = prev
    end
    return xp
end

local function setEnd(self, highlight, pos1)
    local doc = self.ui.document
    local order = doc:compareXPointers(highlight.pos0, pos1)
    if order == nil or order <= 0 then return end
    highlight.pos1 = pos1
    highlight.text = doc:getTextFromXPointers(highlight.pos0, pos1)
    return true
end

local function setStart(self, highlight, pos0)
    local doc = self.ui.document
    local order = doc:compareXPointers(pos0, highlight.pos1)
    if order == nil or order <= 0 then return end
    highlight.pos0 = pos0
    highlight.page = pos0
    highlight.chapter = self.ui.toc:getTocTitleByPage(pos0)
    highlight.pageno = doc:getPageFromXPointer(pos0)
    highlight.text = doc:getTextFromXPointers(pos0, highlight.pos1)
    return true
end

-- 1. Extend a fresh drag-selection over attached punctuation at both ends
local orig_onHoldRelease = ReaderHighlight.onHoldRelease
ReaderHighlight.onHoldRelease = function(self, ...)
    if self.ui.rolling and not self.clear_id and not self.select_mode and not self.is_word_selection
            and self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local ok, err = pcall(function()
            local doc = self.ui.document
            local st = self.selected_text
            local new_pos0 = skipBackward(doc, st.pos0, LEADING)
            local new_pos1 = skipForward(doc, st.pos1, TRAILING)
            if new_pos0 == st.pos0 and new_pos1 == st.pos1 then return end
            self.selected_text = {
                text = doc:getTextFromXPointers(new_pos0, new_pos1, true), -- also redraws the selection
                pos0 = new_pos0,
                pos1 = new_pos1,
                sboxes = doc:getScreenBoxesFromPositions(new_pos0, new_pos1, true),
            }
            UIManager:setDirty(self.dialog, "ui")
        end)
        if not ok then logger.warn("highlight-punctuation patch: selection extend failed:", err) end
    end
    return orig_onHoldRelease(self, ...)
end

-- 2. Punctuation-aware adjusters (word mode)
local orig_updateHighlightRolling = ReaderHighlight.updateHighlightRolling

local function adjustEnd(self, highlight, direction)
    local doc = self.ui.document
    if direction == 1 then
        -- Punctuation right after the end: take it, don't jump to the next word
        local extended = skipForward(doc, highlight.pos1, TRAILING)
        if extended ~= highlight.pos1 then
            return setEnd(self, highlight, extended)
        end
        local updated = orig_updateHighlightRolling(self, highlight, 1, direction, false)
        if updated then
            setEnd(self, highlight, skipForward(doc, highlight.pos1, TRAILING))
        end
        return updated
    end
    -- Ends with punctuation: drop only the punctuation
    local base = skipBackward(doc, highlight.pos1, TRAILING)
    if base ~= highlight.pos1 then
        return setEnd(self, highlight, base)
    end
    -- Otherwise move back a word, keeping that word's trailing punctuation
    local updated = orig_updateHighlightRolling(self, highlight, 1, direction, false)
    if updated then
        setEnd(self, highlight, skipForward(doc, highlight.pos1, TRAILING))
    end
    return updated
end

local function adjustStart(self, highlight, direction)
    local doc = self.ui.document
    if direction == -1 then
        -- Punctuation right before the start: take it, don't jump to the previous word
        local extended = skipBackward(doc, highlight.pos0, LEADING)
        if extended ~= highlight.pos0 then
            return setStart(self, highlight, extended)
        end
        local updated = orig_updateHighlightRolling(self, highlight, 0, direction, false)
        if updated then
            setStart(self, highlight, skipBackward(doc, highlight.pos0, LEADING))
        end
        return updated
    end
    -- Starts with punctuation: drop only the punctuation
    local base = skipForward(doc, highlight.pos0, LEADING)
    if base ~= highlight.pos0 then
        return setStart(self, highlight, base)
    end
    -- Otherwise move forward a word, keeping that word's opening punctuation
    local updated = orig_updateHighlightRolling(self, highlight, 0, direction, false)
    if updated then
        setStart(self, highlight, skipBackward(doc, highlight.pos0, LEADING))
    end
    return updated
end

ReaderHighlight.updateHighlightRolling = function(self, highlight, side, direction, move_by_char)
    if move_by_char then
        return orig_updateHighlightRolling(self, highlight, side, direction, move_by_char)
    end
    local saved = {
        pos0 = highlight.pos0, pos1 = highlight.pos1, text = highlight.text,
        page = highlight.page, chapter = highlight.chapter, pageno = highlight.pageno,
    }
    local ok, result = pcall(side == 0 and adjustStart or adjustEnd, self, highlight, direction)
    if ok then return result end
    logger.warn("highlight-punctuation patch: adjuster failed, using default:", result)
    for k, v in pairs(saved) do highlight[k] = v end
    return orig_updateHighlightRolling(self, highlight, side, direction, move_by_char)
end
