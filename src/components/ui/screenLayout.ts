// Design-system layout logic — pure (no React) so the width contract is testable and
// react-refresh keeps Sheet.tsx and Tray.tsx component-only.
//
// ONE SHAPE FOR A WIDE GLASS: THE PAGE below. (The "wide glass" it replaced — a 48-rem column with a 27.5-rem strip kept clear at
// its right for a tray, `sheetColumnClass`, the pair arithmetic and `trayDockWideClass` — was retired 2026-11-05, the last
// screen having moved to the page or off the Sheet.)

/** The one media query the wide glass turns on. `lg` in Tailwind's scale; `useWide()` mirrors it. */
export const WIDE_QUERY = '(min-width: 1024px)'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PAGE — main and side on the whole glass (2026-11-02, owner row 267)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better.
// right now everything is on left, too packed. this was a mistake."* The wide glass before it reserved the right
// 27.5 rem of every sheet for a tray that is shut almost always, and the unfold slice packed what was left.
// docs/dev-log/2026-11-02-design-past-vs-now.md measured why the past (before #413) felt better: it DOCKED real
// content in that tray column (the Stats Overview's Money log at x=908..1324) and set its figures at 24 and 34 px.
//
// THE PAGE is the shape every screen takes in its turn (Stats first; docs/dev-log/2026-11-02-stats-design.md has the
// measured numbers and what the next screen copies). It is `Sheet layout="page"`; a screen that is not a Sheet
// (the Command desk, the map) docks its trays on the same page-level variables.
//
//   container   centred, the content at most PAGE_REM (80 rem = 1,280 px); side margins 16 px (phone), 24 (768),
//               32 (1,024), 40 (1,280), and past 1,360 px centred — 80 px each side at 1,440
//   gutter      12 px (phone), 16 (768), 20 (1,024), 24 (1,280): between cards, and between main and side
//   split       from `lg` (1,024) the page is MAIN | SIDE: the side column is exactly the tray's width — 352 px at
//               1,024, 384 at 1,280, 416 (26 rem) from 1,440 — so main is 584 · 792 · 840. Below `lg` the page is
//               one column and the side stacks with main (a screen says whether it stands first or last)
//   side        THE TRAY COLUMN, AND IT IS USED: closed, it carries the screen's second block (Overview: the Money
//               log; Markets: the day's figures and the movers); a tray opened from a row slides OVER it — the same x,
//               the same width (`trayDockPageClass`, which reads the same `--page-side` the split does) — so nothing
//               under it moves and the page never has an empty band at its right
//
// The literal strings are for Tailwind's scanner (it cannot see a class built from a number); the numbers they encode
// are stated once, here, and tests/wide.layout.spec.ts parses them.

/** The page's content, at its widest, in rem. 80 rem = 1,280 px. */
export const PAGE_REM = 80
/** The side column at `lg`, `xl` and from 90 rem (1,440), in rem: 22 = 352 px, 24 = 384, 26 = 416 (the tray's width). */
export const SIDE_REM = { lg: 22, xl: 24, wide: 26 } as const

/** THE GUTTER: 12 · 16 · 20 · 24 px at phone · 768 · 1,024 · 1,280. */
export const PAGE_GAP = 'gap-3 md:gap-4 lg:gap-5 xl:gap-6'

/** THE ONE SCROLLING REGION of a titled surface: the Tray's body and the phone desk's. It fills what the title leaves and scrolls itself. */
export const scrollRegionClass = 'bv-scroll min-h-0 flex-1 overflow-y-auto px-gutter pb-2'

/** The page's two custom properties, set ONCE for the whole app (App.tsx) and read by BOTH the split and the docked tray, so the tray's
 *  x and width cannot drift from the side column's: `--page-pad` is the margin at each glass, `--page-side` the side. */
export function pageVarsClass(): string {
  // pad: 1rem = 16 · md 1.5rem = 24 · lg 2rem = 32 · xl 2.5rem = 40. side: 22rem · xl 24rem · 90rem (1,440) 26rem = SIDE_REM
  return '[--page-pad:1rem] md:[--page-pad:1.5rem] lg:[--page-pad:2rem] xl:[--page-pad:2.5rem] [--page-side:22rem] xl:[--page-side:24rem] min-[90rem]:[--page-side:26rem]'
}

/** The page container: centred, content at most PAGE_REM, margins 16 · 24 · 32 · 40 (`--page-pad`). */
export function pageColumnClass(): string {
  // 85rem = PAGE_REM + 2 × the widest margin (2.5rem): the margin is part of the box, the 80 rem is not
  return 'mx-auto w-full max-w-[85rem] px-4 md:px-6 lg:px-8 xl:px-10'
}

/** The page's body under its title: the container, a column of its blocks one gutter apart, air under the last. */
export function pageBodyClass(): string {
  return `${pageColumnClass()} ${PAGE_GAP} flex flex-col pb-8 pt-2 lg:pb-12`
}

/** MAIN | SIDE from `lg`: one column below it. The side is `--page-side` wide (the tray's width). */
export function pageSplitClass(): string {
  return `grid grid-cols-1 ${PAGE_GAP} lg:grid-cols-[minmax(0,1fr)_var(--page-side)] lg:items-start`
}

/** THREE COLUMNS ACROSS from `lg`: one column below it (the HQ's Production: storage, cargo, recipes). */
export function pageThreeClass(): string {
  return `grid grid-cols-1 ${PAGE_GAP} lg:grid-cols-3 lg:items-start`
}

/** The docked Tray over a PAGE, from `lg`: the side column's own x and width, between the status strip (top-8) and the
 *  nav (bottom-14), rounded on every side (the margin shows beside it). Its right edge is the page's right margin —
 *  `max(--page-pad, 50% − PAGE_REM/2)` from the glass's right — and its width is `--page-side`. */
export function trayDockPageClass(): string {
  // 40rem = PAGE_REM / 2
  return 'lg:inset-auto lg:top-8 lg:bottom-14 lg:right-[max(var(--page-pad),calc(50%-40rem))] lg:w-[var(--page-side)] lg:h-auto lg:rounded-sheet'
}

/** THE MAP'S SLIDE-IN PANEL (owner, 2026-10-15: *"when i click location or a ship, i don't want a
 *  page to pop up randomly. instead i want the page to slide on the right side, and show info"*).
 *  Pinned to the glass's right edge, between the top bar (top-8) and the nav (bottom-14), and it
 *  slides in (index.css `bv-slide-in-right`). `Tray mode="side"` is its one user.
 *
 *  ── NARROW: THE PANEL IS THE GLASS (2026-10-16) ──────────────────────────────────────────────
 *  From `lg` (WIDE_QUERY, the one breakpoint this file turns on) it is `--page-side` × 1.5
 *  wide and the chart's corner chrome steps left to stand beside it (`chromeAsideSideTrayClass`).
 *  Below `lg` there is no room for a panel AND a usable chart beside it: at 390 px the old 92vw
 *  panel left the corner chrome a 31 px strip, and the fleets list rendered invisible inside it.
 *  So below `lg` the panel covers the whole width, over the map, with its ✕ at the top right, and
 *  the chrome underneath keeps its full width — closing the panel gives the corners back intact,
 *  never squeezed. The same break `traySideNextClass` already used for "no room for two". */
export function traySideEdgeClass(): string {
  // 39rem = 1.5 × the tray width (owner, 2026-10-15: "give more room, about 50% more")
  // 2026-11-04 (Map redesign, row 267): from `lg` it is `--page-side` wide (the Map's root sets the page vars, `pageVarsClass`).
  // 2026-11-05 (owner: "slide from the edge of the page"): its right edge is the WINDOW's edge (`right-0`, fixed), not the page's
  // right margin — that margin (up to 80 px at 1,440) was the gap. Rounded on the left only. Below `lg` it is the glass, as it was.
  return 'fixed top-8 bottom-14 right-0 w-full lg:w-[var(--page-side)] lg:rounded-l-sheet bv-slide-in-right'
}

/** THE SECOND PANEL, SLID OUT FROM THE FIRST (owner, 2026-10-15: *"i want it to show by sliding
 *  further, a new slide from the sliding panel"*): a ship opened from a fleet's or a merchant's
 *  panel stands to that panel's LEFT, `--page-side` wide, one layer below it so it comes out
 *  from under its edge. Below `lg` there is no room for two side by side, so it covers the first
 *  — the whole width, as the first does there (`traySideEdgeClass`). */
export function traySideNextClass(): string {
  // 39rem = traySideEdgeClass's width · `--page-side`
  // 2026-11-04: from `lg` its right edge is the first panel's left edge — the window's edge + `--page-side` + a 1-rem gap.
  return 'fixed top-8 bottom-14 right-0 w-full lg:right-[calc(var(--page-side)+1rem)] lg:w-[var(--page-side)] lg:rounded-sheet bv-slide-in-right lg:bv-slide-out-left'
}

/** The chart's corner chrome beside that panel — its right edge where the panel's left edge is.
 *  Only from `lg`: below it the panel covers the glass (`traySideEdgeClass`) and the chrome stays
 *  full width underneath rather than being squeezed into nothing. */
export function chromeAsideSideTrayClass(): string {
  // 39rem, as traySideEdgeClass · 65rem = 39rem + the second panel's 26rem (traySideNextClass),
  // while one stands — read off the page, since the second panel is opened inside the first.
  // 2026-11-04: the panel's left edge = `--page-side` + 1 rem from the window's edge (a second panel: + `--page-side` + 1 rem more).
  return 'lg:right-[calc(var(--page-side)+1rem)] lg:[body:has([data-testid=map-ship-panel])_&]:right-[calc(2*var(--page-side)+2rem)]'
}
