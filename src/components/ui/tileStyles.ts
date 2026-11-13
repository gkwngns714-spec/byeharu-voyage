// THE CHOICE GRID'S PURE HALF (owner, 2026-10-31) — the column table and the one cell recipe,
// kept out of TileGrid.tsx so that file exports COMPONENTS ONLY (react-refresh's rule: a file that
// exports a helper beside its components cannot hot-reload). `Segmented` (Chip.tsx) and every
// filter set read the same numbers, so a tab and a filter cannot drift apart.

export type ChoiceColumns = 2 | 3 | 4 | 5 | 6

/** Tailwind cannot see a class built from a number, so the fixed column counts are typed out. */
export const COLUMN_CLASS: Record<ChoiceColumns, string> = {
  2: 'grid-cols-2',
  3: 'grid-cols-3',
  // FOUR AND FIVE ACROSS ON A GLASS UNDER 375 PX: A COLUMN IS NEVER NARROWER THAN ITS WORD (2026-11-14, owner row 318). A fifth of a
  // 320-px glass is 51 px, 35 inside the cell's padding, and 'Production' (72 px) stood over the cells beside it. There the columns
  // are equal wherever every word fits its share; where one does not, it takes what it needs and the rest share what is left, and the
  // cells keep 2 px a side (the words are centred: a roomy cell looks as it did).
  4: 'grid-cols-4 max-[374px]:grid-cols-[repeat(4,minmax(min-content,1fr))] max-[374px]:*:px-0.5!',
  5: 'grid-cols-5 max-[374px]:grid-cols-[repeat(5,minmax(min-content,1fr))] max-[374px]:*:px-0.5!',
  6: 'grid-cols-6',
}

/** The cell's base recipe — layout only. The STATE skin belongs to the caller (a filter washes
 *  accent; a face stands on the segmented track), because those are two different meanings. */
export function tileCellClass(): string {
  // ON A PHONE'S HALF GLASS (`narrow:`, index.css) the cells are a WRAPPING line, not equal columns: three faces at 139 px are 40 px each,
  // and "Requests" is 56 px of words. A cell keeps its words (`flex-auto`: its own width, then the line's spare room), never under the 44-px
  // reach floor, and the line breaks where the next cell does not fit — the rest stands on the next line, as wide as it is.
  return 'flex min-h-11 min-w-0 items-center justify-center rounded-control px-2 py-1 text-center text-t-caption leading-tight transition narrow:min-w-11 narrow:flex-auto narrow:px-1'
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE GRID THAT KEEPS ITS WORDS (2026-11-11, the trade-layout slice)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A set of PROPER NAMES (the Trade desk's cities) cannot use the equal columns above as they are: a cell there may shrink under
// its longest word, so the word is broken inside itself. Measured at 390 px in four columns: a cell left 41 px for a name and
// "Lisbon" stood as "Lisbo / n", "Sanlucar de Barrameda" on four lines.
//
// Here the cells still stand on equal columns (the same width, the same left edges, row after row), and a name wraps only at its
// spaces. A cell whose longest word is wider than a column is as wide as that word (`min-width: min-content`): the one cell is
// wider, no word is ever broken, and nothing is cut. Korean has no spaces inside a name, so `word-break: keep-all` keeps a Korean
// name whole too.
//
// A cell STARTS one rem under its column and grows back to it (`flex: 1 1`, capped at the column), so a full line is exactly the
// equal columns, and a line with one long name still holds its full count while the long cell is up to a rem over (measured:
// 산루카르데바라메다 needs 161 px in a 156-px column, and stood alone on its line before this). Past that the line breaks before
// the next cell.
//
// The column width is one custom property, set on the grid and read by its cells, so a second count from `lg` is one more class.
//
// ONE LINE A NAME, AND A LONG NAME TAKES TWO COLUMNS (2026-11-12, the owner on a phone: *"long words and sentences making new
// messy lines"*). The wrapping line above is the floor: with nothing else it never breaks or cuts a word. But on a phone's three
// columns it left a hole behind a long cell (`산루카르데바라메다` at 390 px: two cells and a gap where three stand), and a name
// with spaces took three lines in one column (`Sanlucar / de / Barrameda`) and made its whole line taller. So `useWordSpans`
// (TileGrid.tsx) measures each cell's one-line width and gives a cell that does not fit ONE column exactly TWO (or the line):
// the name stands on one line and every cell stays on the column lines. Where a wide cell does not fit the rest of a line, the
// cell before it takes that rest, so no hole is left inside the grid. Under 375 px a column is 92 px, so a cell gives its name
// the room it can: 4 px of padding a side, not 8.

/** The column counts a words grid may take. */
export type WordColumns = 2 | 3

/** The column width at every glass: (the line, less the 6-px gaps between the cells) / the count. */
export const WORDS_COLUMN_CLASS: Record<WordColumns, string> = {
  2: '[--tile-w:calc((100%-0.375rem)/2)]',
  3: '[--tile-w:calc((100%-0.75rem)/3)]',
}

/** The column width from `lg` (WIDE_QUERY), where the grid stands in a pane of its own. */
export const WORDS_COLUMN_WIDE_CLASS: Record<WordColumns, string> = {
  2: 'lg:[--tile-w:calc((100%-0.375rem)/2)]',
  3: 'lg:[--tile-w:calc((100%-0.75rem)/3)]',
}

/** THE SAME RULE FOR ONE NAME outside a grid (a best sale's city in a goods card, live/TradeCard.tsx): the box is never narrower
 *  than the name's longest word, and the name turns only at a space. Never `truncate` beside it: a name is printed whole. */
export const KEEP_WORDS_CLASS = 'min-w-min break-keep'

/** The words grid and what it asks of each cell: a column wide, never under its longest word, words never broken. The cell rules
 *  are `!important` because a cell's own recipe (`tileCellClass`) says `min-w-0` at the same weight. */
export function tileWordsGridClass(): string {
  return 'flex flex-wrap gap-1.5 break-keep *:min-w-min! *:max-w-[var(--tile-w)]! *:shrink! *:grow! *:basis-[calc(var(--tile-w)-1rem)]! max-[374px]:*:px-1!'
}

/** A HEAD LINE THAT MAY TURN: words at the left, a control or a figure at the right, and where the glass is too narrow for both the
 *  right one goes under, whole (2026-11-13: the Trade panel's other sale and the City face's heading wrote it twice). */
export const WRAP_ROW_CLASS = 'flex flex-wrap items-center justify-between gap-x-3 gap-y-1'
