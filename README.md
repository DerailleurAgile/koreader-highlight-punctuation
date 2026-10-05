# koreader-highlight-punctuation

A [KOReader](https://github.com/koreader/koreader) user patch that makes highlights respect punctuation. Selections pick up punctuation that's directly attached to them, and the highlight start/end adjusters step over punctuation instead of jumping past it.

It addresses [koreader/koreader#13581, "Highlight scroller ignores end punctuation marks"](https://github.com/koreader/koreader/issues/13581).

## The problem

KOReader moves highlight boundaries by **word**, and its rendering engine doesn't count punctuation as part of a word. This causes three annoyances:

1. **Selections stop short of the punctuation.** Your finger covers the end of the selection while you drag, so you guess where to let go. The selection snaps to a word boundary and usually stops just before the period, comma or closing quote. KOReader's built-in "sentence trick" from [#8857](https://github.com/koreader/koreader/issues/8857) only adds punctuation when you save a selection that lines up with a whole sentence or clause. It doesn't help when the selection is a word short.
2. **The adjusters skip the punctuation.** In the highlight dialog, `▒▒▷` (extend the end) jumps from `fox` straight to `fox. The`, taking the next word with it. `▒☓◁` (shrink the end) goes back to `fox`, without the period. You can't land on `fox.` at all.
3. **Opening punctuation has the same problem.** If a highlight starts just after a `(` or `“`, `◁▒▒` (extend the start) jumps over the opening mark to the previous word.

The only workaround so far has been to long-press an adjuster to switch it to character mode, then step through one character at a time.

## What the patch does

It only applies to reflowable documents (EPUB, FB2, HTML and so on). PDFs and other fixed-page documents are unchanged.

### When you finish a selection

When you lift your finger after dragging, the selection extends over punctuation that is **directly attached** to it, with no space in between:

| You select | You get |
|---|---|
| `phrase in parens` from `(phrase in parens)` | `(phrase in parens)` |
| `quick brown fox` from `fox. The` | `quick brown fox.` |
| `she said` from `she said,” and` | `she said,”` |

The selection on screen updates straight away, so what you see is what gets saved.

### The highlight-dialog adjusters (word mode)

| Button | Behaviour |
|---|---|
| `◁▒▒` extend start | Adds an opening mark directly before the start (`(`, `“`, `[` …) on its own. Otherwise moves back one word, together with that word's opening mark. |
| `▷☓▒` shrink start | If the highlight starts with an opening mark, removes only that. Otherwise moves forward one word. |
| `▒▒▷` extend end | Adds trailing punctuation directly after the end (`.`, `,`, `?`, `”`, `)` …) on its own. Otherwise moves forward one word, together with that word's trailing punctuation. |
| `▒☓◁` shrink end | If the highlight ends with punctuation, removes only that. Otherwise moves back one word. |

Example, extending the end: `fox` → `fox.` → `fox. The` → …, and shrinking it: … → `fox. The` → `fox.` → `fox`.

Because each shrink adjuster removes punctuation on its own first, one tap undoes an automatic extension you didn't want. For example, if you meant to start inside the parentheses, tap `▷☓▒` once.

Character mode is unchanged: long-press an adjuster to switch to it, then each tap moves one character.

### Punctuation handled

- **Trailing:** `. , ; : ! ? … ) ] } » ” ’ " '`
- **Opening:** `( [ { « ¿ ¡ “ ‘ " '`

Up to 4 marks in a row are taken, so `?!”` or `(“` work. Straight `"` and `'` count as opening marks before a word and as trailing marks after one.

## Installation

1. Download `2-highlight-punctuation.lua` from the [latest release](../../releases/latest), or from this repository.
2. Connect your device and copy the file into KOReader's `patches` folder. Create the folder if it doesn't exist:
   - Kindle: `koreader/patches/` (on the device, `/mnt/us/koreader/patches/`)
   - Kobo: `.adds/koreader/patches/`
   - Android: `koreader/patches/` in the KOReader data folder
   - Other devices: the `patches` folder next to KOReader's `settings.reader.lua`
3. Restart KOReader.

Keep the file name as it is. The `2-` prefix tells KOReader to load the patch once its interface modules are available. To check that it loaded, look for `Applying patch: ./patches/2-highlight-punctuation.lua` in `crash.log`.

**To uninstall,** delete the file and restart KOReader.

## Compatibility

- Tested on KOReader **v2026.07.1** on a Kindle Paperwhite 3 (7th gen), with EPUB books.
- The patch wraps two KOReader functions, `ReaderHighlight:onHoldRelease()` and `ReaderHighlight:updateHighlightRolling()`, and calls the originals for anything it doesn't handle. If a future KOReader version renames or reworks them, the patch may stop working.
- It gets along with plugins that replace the highlight *menu*, such as Page Scrubber or Reader Menu Redesign, because it changes the selection itself, before any menu appears.

## How it works

- **Finding punctuation:** it reads one character at a time on either side of a boundary, with `document:getNextVisibleChar()` / `getPrevVisibleChar()` and `getTextFromXPointers()`. KOReader's own language-support module uses the same approach (`frontend/languagesupport.lua`). A boundary only moves over characters in the lists above, and it stops at the first space or letter.
- **Selections:** `onHoldRelease` is wrapped so that before KOReader shows the highlight menu (or runs your default highlight action), the selection's `pos0` and `pos1` are moved over any attached punctuation and the selection is redrawn. Single-word taps, which open the dictionary, and multi-part "extended" selections are left alone.
- **Adjusters:** `updateHighlightRolling` is wrapped for word mode. Punctuation is added or removed on its own first. Moving by a whole word is still done by KOReader's original function, and the patch then adjusts the new boundary for that word's own punctuation.
- **Safety:** every change runs inside `pcall`. If anything fails, the patch writes `highlight-punctuation patch: …` to the log, restores the highlight's original position, and falls back to KOReader's normal behaviour instead of crashing the reader.

## License

[AGPL-3.0](LICENSE), the same licence as KOReader.
