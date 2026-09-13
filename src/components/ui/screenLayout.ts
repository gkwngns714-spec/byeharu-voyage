// Design-system Screen scaffold logic — pure (no React) so the width-variant contract is testable
// and react-refresh keeps Screen.tsx component-only.
//
/** The Screen content column: centered, padded, space-y-4 panel rhythm. `wide` = the wider desktop
 *  measure, which the Market tab uses for its seven-column table. */
export function screenBodyClass(wide = false): string {
  return `mx-auto ${wide ? 'max-w-6xl' : 'max-w-3xl'} space-y-4 px-4 py-4 sm:px-6`
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WIDE GLASS — a column you read, and the tray beside it instead of over it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The app is built phone-first (390 px is the viewport every geometry test is pinned to) and until
// 2026-09-13 it had NO rule for a wide window: every `Sheet` stretched to the glass, so on the
// owner's 1,545-px window a Trade row was a name at the left edge, two price cells at the right
// edge and a thousand pixels of nothing between. The owner: *"look. too much blank space."* The
// same day, on the same screen: *"i showed you the pictures and this is not what i've asked for"*
// — the reference (docs/QUAY_LEDGER.md §1) has the goods list on the LEFT and the basket with the
// hold bar on the RIGHT, and the owner had already said so on 2026-08-22: *"When buy, i want all
// the trade goods on left side, and my fleet info on the right side."* A `splitClass()` trio was
// written for that and never called by any screen; it is deleted here, and the rule it was meant to
// carry is these three numbers.
//
// ── THE RULE ───────────────────────────────────────────────────────────────────────────────────
// From `lg` (1024 px), a Sheet's content is a column of at most SHEET_REM, and a docked Tray is a
// SIDE PANEL of TRAY_REM standing to the column's right with GAP_REM between — the pair centred on
// the glass. Below `lg` nothing changes: the column is the glass and the tray rises from the bottom
// edge, exactly as every phone test proves. One breakpoint, one pair of widths, and BOTH the Sheet
// and the Tray read them from here, so the tray's left edge and the column's right edge cannot
// drift apart.
//
// ── WHY THE CLASSES ARE LITERAL STRINGS ────────────────────────────────────────────────────────
// Tailwind scans source for class names and cannot see a name built at runtime from a number, so
// the arbitrary values below are typed out. The numbers they encode are stated once, beside them,
// and `tests/wide.layout.spec.ts` parses the strings and asserts the arithmetic — which is the
// only way a literal class can be held to a constant.

/** The Sheet column's greatest width, in rem. 48 rem = 768 px: a Trade row keeps its name, mark,
 *  tide bar and two cells legible without a gulf between them. */
export const SHEET_REM = 48
/** The side tray's width, in rem. 26 rem = 416 px: a quantity stepper, its chips and a two-column
 *  figure row fit without wrapping. */
export const TRAY_REM = 26
/** Air between the column and the tray. */
export const GAP_REM = 1.5
/** The pair, centred: SHEET + GAP + TRAY. */
export const PAIR_REM = SHEET_REM + GAP_REM + TRAY_REM

/** The one media query the wide glass turns on. `lg` in Tailwind's scale; `useWide()` mirrors it. */
export const WIDE_QUERY = '(min-width: 1024px)'

/** The Sheet's content wrapper: full width on a phone; from `lg`, a centred block of PAIR_REM whose
 *  right TRAY_REM + GAP_REM is left empty for the tray to stand in, so the readable column is
 *  SHEET_REM at most and sits where the tray expects it. */
export function sheetColumnClass(): string {
  // 75.5rem = PAIR_REM · 27.5rem = TRAY_REM + GAP_REM
  return 'lg:mx-auto lg:w-full lg:max-w-[75.5rem] lg:pr-[27.5rem]'
}

/** The Sheet's body — the column, padded. The header takes `sheetColumnClass()` on its own so the
 *  title stands over the column it titles, not over the whole glass. */
export function sheetBodyClass(): string {
  return `px-gutter pb-8 ${sheetColumnClass()}`
}

/** The docked Tray from `lg`: a side panel between the status strip (top-8) and the nav
 *  (bottom-14), TRAY_REM wide, its right edge where the centred pair's right edge is —
 *  `max(0, 50% − PAIR_REM/2)` from the glass's right — so it stands exactly in the space
 *  `sheetBodyClass` leaves. Square top corners, rounded on the side that faces the column. */
export function trayDockWideClass(): string {
  // 37.75rem = PAIR_REM / 2 · 26rem = TRAY_REM
  return 'lg:inset-auto lg:top-8 lg:bottom-14 lg:right-[max(0px,calc(50%-37.75rem))] lg:w-[26rem] lg:h-auto lg:rounded-t-none lg:rounded-l-sheet'
}
