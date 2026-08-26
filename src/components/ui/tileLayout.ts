// Design-system TILE-FIELD layout logic — pure (no React), beside EntryTile.tsx exactly as
// tableLayout.ts sits beside Table.tsx and screenLayout.ts beside Screen.tsx: the react-refresh
// rule keeps component files component-only, and the grid is a recipe a test can read.
//
// ── ONE FIELD, TWO SPELLINGS, ONE TABLE ────────────────────────────────────────────────────────
// A field of tiles has to be said twice — once in CSS (the grid's own columns) and once in
// JavaScript (a picker that unfolds a panel must know where a ROW ENDS, or the fold lands
// mid-row and shoves the tiles beside the pressed one out of the way). Those two spellings ARE
// the same fact, so they are read off ONE table below and can never disagree.
//
// It was two authorities until 2026-08-26: `goodTileGridClass()` said 2 / 3 / 4 in Tailwind
// classes while `useTileCols()` — hand-written inside features/command/ArgPickers.tsx for the
// harbour tiles — said 2 / 3 through its own matchMedia. Two answers to "how many tiles stand in
// one row", differing above 1280px, which is docs/NO_SPAGHETTI.md §1 question 3 exactly: they
// could disagree, so they were two authorities even while nobody had looked.
//
// THE CLASS STRINGS ARE LITERALS ON PURPOSE. Tailwind scans source text, so `grid-cols-${n}` would
// generate nothing; the literal rides in the table beside the number it draws.

export interface TileFieldStep {
  /** Viewport width, in px, at or above which this many tiles stand in one row. */
  readonly minWidth: number
  readonly cols: number
  /** The Tailwind spelling of the same number. A literal, so the scanner can see it. */
  readonly className: string
}

/** THE FIELD OF TILES. Two columns on a phone — MEASURED at 390px (docs/UI_DIRECTION.md §1): a
 *  card body is ~326px inside its padding, so two tiles get ~159px each (158px on the running
 *  build), which holds the longest good name ("Wool Cloth", "Black Pepper") wrapped at most once;
 *  three would crush the figures to fragments. `sm` is Tailwind's 640px and `xl` its 1280px —
 *  the numbers here and the prefixes beside them are the same breakpoints. */
export const TILE_FIELD: readonly TileFieldStep[] = [
  { minWidth: 0, cols: 2, className: 'grid-cols-2' },
  { minWidth: 640, cols: 3, className: 'sm:grid-cols-3' },
  { minWidth: 1280, cols: 4, className: 'xl:grid-cols-4' },
]

/** The field's CSS. `items-stretch` so a short tile in a row of tall ones still fills its cell and
 *  the whole tile stays tappable. */
export function tileFieldClass(extra = ''): string {
  return ['grid items-stretch gap-2', ...TILE_FIELD.map((s) => s.className), extra]
    .filter(Boolean)
    .join(' ')
}

/** The same number in JavaScript, for the callers that must know where a row ENDS (see the header).
 *  Reads the table top-down, so a viewport wider than every step keeps the last. */
export function tileFieldCols(viewportWidth: number): number {
  let cols = TILE_FIELD[0].cols
  for (const step of TILE_FIELD) if (viewportWidth >= step.minWidth) cols = step.cols
  return cols
}
