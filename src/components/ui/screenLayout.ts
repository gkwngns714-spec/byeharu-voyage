// Design-system layout logic — pure (no React) so the width contract is testable and
// react-refresh keeps Sheet.tsx and Tray.tsx component-only. (`screenBodyClass` stood here for the
// deprecated `Screen` scaffold and went with it, 2026-10-14.)

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
 *  title stands over the column it titles, not over the whole glass.
 *
 *  `fill` (2026-11-01, the unfold slice) makes the body a flex column that takes the glass the header
 *  leaves, with 8 px under it instead of 24: a screen whose job is ONE list (a `ListPanel`) gives that
 *  list the rest of the height instead of letting the tab scroll. Every other caller keeps the old string. */
export function sheetBodyClass(fill = false): string {
  return fill
    ? `flex min-h-0 flex-1 flex-col px-gutter pb-2 ${sheetColumnClass()}`
    : `px-gutter pb-6 ${sheetColumnClass()}`
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PAGE — cards on the whole glass (2026-11-02, owner row 267)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better.
// right now everything is on left, too packed. this was a mistake."* The wide glass above reserves the right
// 27.5 rem of every sheet for a tray that is shut almost always, and the unfold slice packed what was left. The
// PAGE is the other shape, and it is the pattern every screen takes in its turn (Stats first; docs/dev-log/
// 2026-11-02-stats-design.md): a centred container up to PAGE_REM on a 12-column grid, its blocks CARDS with
// room around them. It is opt-in — `Sheet layout="page"` — and nothing above changes: a screen that does not
// ask for it is exactly what it was.
//
//   container   centred, at most PAGE_REM (90 rem = 1,440 px); side margins 16 px on a phone, 24 px from `sm`,
//               48 px from `xl` (1,280) — so at 1,280 the cards span 1,184 px (92 % of the glass), at 1,440
//               1,344 px (93 %), and nothing is reserved at the right
//   grid        one column below `md` (768); from `md` twelve columns with 20-24 px gutters; a card takes
//               `CARD_SPAN` of them: a QUARTER (a stat) is 6 of 12 from `md` and 3 from `xl`, a THIRD (a card of
//               figures) 6 then 4 — two across at 1,024, three across at 1,280 and 1,440 — so no figure card
//               is wider than 560 px at any glass (432 px at 1,440), and a row of a list inside one is
//               content-sized, never stretched across the page (the 2026-09-13 complaint, "too much blank
//               space", must not come back)
//   tray        a docked tray is a slide-over, flush with the right edge (index.css), never a column
//
// The literal strings below are for Tailwind's scanner (it cannot see a class built from a number); the
// numbers they encode are stated once, here, and tests/wide.layout.spec.ts parses them.

/** The page container's greatest width, in rem. 90 rem = 1,440 px. */
export const PAGE_REM = 90

/** The page container: centred, at most PAGE_REM, margins 16 · 24 (`sm`) · 48 (`xl`) px. */
export function pageColumnClass(): string {
  // 90rem = PAGE_REM · px-4 = 16 · sm:px-6 = 24 · xl:px-12 = 48
  return 'mx-auto w-full max-w-[90rem] px-4 sm:px-6 xl:px-12'
}

/** The page's body under its title: the container, with air under the last card. */
export function pageBodyClass(): string {
  return `${pageColumnClass()} pb-8 pt-2 lg:pb-12`
}

/** THE 12-COLUMN GRID cards stand on: one column below `md`; from `md` twelve, 20 px gutters (24 from `lg`). */
export function pageGridClass(): string {
  return 'grid grid-cols-1 gap-4 sm:gap-5 md:grid-cols-12 lg:gap-6'
}

/** How much of the grid a card takes. `quarter` is a stat card (6/12 from `md`, 3/12 from `xl`: 2 then 4 across);
 *  `third` a card of figures (6/12 then 4/12: 2 then 3 across); `half` is 6/12 at every width from `md`;
 *  `side` a tall card beside a zone (12/12, then 4/12), `zone` the block of cards it stands beside (12/12, then
 *  8/12: a `CardZone`, two cards across); `full` the whole width — a list or a toolbar, whose rows lay
 *  themselves out in columns and are never wider than 35 rem. */
export type CardSpan = 'quarter' | 'third' | 'half' | 'side' | 'zone' | 'full'

const CARD_SPAN: Record<CardSpan, string> = {
  quarter: 'md:col-span-6 xl:col-span-3',
  third: 'md:col-span-6 xl:col-span-4',
  half: 'md:col-span-6',
  side: 'md:col-span-12 xl:col-span-4',
  zone: 'md:col-span-12 xl:col-span-8',
  full: 'md:col-span-12',
}

/** The grid classes of a card's span. */
export function cardSpanClass(span: CardSpan): string {
  return CARD_SPAN[span]
}

/** The docked Tray from `lg`: a side panel between the status strip (top-8) and the nav
 *  (bottom-14), TRAY_REM wide, its right edge where the centred pair's right edge is —
 *  `max(0, 50% − PAIR_REM/2)` from the glass's right — so it stands exactly in the space
 *  `sheetBodyClass` leaves. Square top corners, rounded on the side that faces the column. */
export function trayDockWideClass(): string {
  // 37.75rem = PAIR_REM / 2 · 26rem = TRAY_REM
  return 'lg:inset-auto lg:top-8 lg:bottom-14 lg:right-[max(0px,calc(50%-37.75rem))] lg:w-[26rem] lg:h-auto lg:rounded-t-none lg:rounded-l-sheet'
}

/** THE MAP'S SLIDE-IN PANEL (owner, 2026-10-15: *"when i click location or a ship, i don't want a
 *  page to pop up randomly. instead i want the page to slide on the right side, and show info"*).
 *  Pinned to the glass's right edge, between the top bar (top-8) and the nav (bottom-14), and it
 *  slides in (index.css `bv-slide-in-right`). `Tray mode="side"` is its one user.
 *
 *  ── NARROW: THE PANEL IS THE GLASS (2026-10-16) ──────────────────────────────────────────────
 *  From `lg` (WIDE_QUERY, the one breakpoint this file turns on) it is 39rem (TRAY_REM × 1.5)
 *  wide and the chart's corner chrome steps left to stand beside it (`chromeAsideSideTrayClass`).
 *  Below `lg` there is no room for a panel AND a usable chart beside it: at 390 px the old 92vw
 *  panel left the corner chrome a 31 px strip, and the fleets list rendered invisible inside it.
 *  So below `lg` the panel covers the whole width, over the map, with its ✕ at the top right, and
 *  the chrome underneath keeps its full width — closing the panel gives the corners back intact,
 *  never squeezed. The same break `traySideNextClass` already used for "no room for two". */
export function traySideEdgeClass(): string {
  // 39rem = TRAY_REM × 1.5 (owner, 2026-10-15: "give more room, about 50% more")
  return 'fixed top-8 bottom-14 right-0 w-full lg:w-[39rem] lg:rounded-l-sheet bv-slide-in-right'
}

/** THE SECOND PANEL, SLID OUT FROM THE FIRST (owner, 2026-10-15: *"i want it to show by sliding
 *  further, a new slide from the sliding panel"*): a ship opened from a fleet's or a merchant's
 *  panel stands to that panel's LEFT, 26rem (TRAY_REM) wide, one layer below it so it comes out
 *  from under its edge. Below `lg` there is no room for two side by side, so it covers the first
 *  — the whole width, as the first does there (`traySideEdgeClass`). */
export function traySideNextClass(): string {
  // 39rem = traySideEdgeClass's width · 26rem = TRAY_REM
  return 'fixed top-8 bottom-14 right-0 w-full lg:right-[39rem] lg:w-[26rem] lg:rounded-l-sheet bv-slide-in-right lg:bv-slide-out-left'
}

/** The chart's corner chrome beside that panel — its right edge where the panel's left edge is.
 *  Only from `lg`: below it the panel covers the glass (`traySideEdgeClass`) and the chrome stays
 *  full width underneath rather than being squeezed into nothing. */
export function chromeAsideSideTrayClass(): string {
  // 39rem, as traySideEdgeClass · 65rem = 39rem + the second panel's 26rem (traySideNextClass),
  // while one stands — read off the page, since the second panel is opened inside the first.
  return 'lg:right-[39rem] lg:[body:has([data-testid=map-ship-panel])_&]:right-[65rem]'
}

/**
 * THE RIGHT EDGE A CHART'S CORNER CHROME KEEPS WHILE A SIDE TRAY STANDS BESIDE IT — the mirror of
 * `trayDockWideClass`, built from the same two numbers so the two can never drift apart.
 *
 * A full-bleed picture with a floating side panel puts its top-RIGHT corner under that panel: at
 * 1280 the merchant sheet covered the Regions toggle completely (2026-10-08, the owner's reading of
 * `docs/npc-traders/merchant-sheet-1280.png`). A corner that cannot be reached is the defect
 * `cornerSlots.ts` exists to prevent, so the chrome layer moves instead of the panel. Only from
 * `lg`, where a tray IS a side panel; below it the tray is at the bottom edge and a top corner is
 * clear anyway.
 */
export function chromeAsideTrayClass(): string {
  // 26rem = TRAY_REM · 37.75rem = PAIR_REM / 2 — the tray's own left edge, measured from the right.
  return 'lg:right-[calc(26rem+max(0px,50%-37.75rem))]'
}
