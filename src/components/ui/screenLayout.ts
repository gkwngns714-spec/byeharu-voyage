// Design-system Screen scaffold logic — pure (no React) so the width-variant contract is testable
// and react-refresh keeps Screen.tsx component-only.
//
/** The Screen content column: centered, padded, space-y-4 panel rhythm. `wide` = the wider desktop
 *  measure, which the Market tab uses for its seven-column table. */
export function screenBodyClass(wide = false): string {
  return `mx-auto ${wide ? 'max-w-6xl' : 'max-w-3xl'} space-y-4 px-4 py-4 sm:px-6`
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SPLIT — a list you work down, and a panel that watches you do it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The predecessor of this idiom (`screenSplitClass()` / `screenRailClass()`) was deleted on
// 2026-08-22 with no caller ever written, because it had been invented for a desktop layout nobody
// had asked for. It comes back here in the shape of the screen that finally needed it — the owner,
// 2026-08-22: *"When buy, i want all the trade goods on left side, and my fleet info on the right
// side, showing how much room, how much negotiation can be done."* COMMAND's BUY composer is the
// first caller and these three are written against it.
//
// ── WHY FLEX AND NOT GRID (the reasoning docs/CORE_REUSE.md:103 kept when it dropped the code) ──
// A grid states both tracks in one place — `grid-cols-[1fr_20rem]` — which reads well and then
// costs twice:
//   * the rail's width becomes a magic number in the PARENT, so the rail can no longer decide how
//     wide it wants to be, and a second split elsewhere has to restate it;
//   * a grid track does not shrink below its content by default, so a wide child (a table, a long
//     mono order line) silently pushes the whole grid past the viewport instead of scrolling
//     inside its own pane. `min-w-0 flex-1` is the idiom that keeps that contained, and it belongs
//     to the pane, not to the container.
// Flex also collapses to one column with a single `flex-col` → `md:flex-row` switch, so the phone
// layout is the DEFAULT and the split is the enhancement, which is the direction this app is built
// in.
//
// ── WHY `md` (768px) AND NOT `sm` ───────────────────────────────────────────────────────────────
// The rail needs 288–320px to print a figure and its label without wrapping, and a market row on
// the left needs ~360px to keep `buy · sell · %NBR` as three legible columns (ArgPickers.tsx's
// `GoodFigures`). 320 + 16 + 360 = 696px of CONTENT, and the Screen body spends 48px on its own
// padding. At `sm` (640px) the left pane would be ~290px and those three columns would wrap —
// which is precisely the "crushed column" signature `tests/layout.spec.ts` fails a build over. So
// the split opens at `md`, and everything narrower stays the single column that is already proven.
//
// ── THE RAIL IS INFORMATION, NEVER A CONTROL ────────────────────────────────────────────────────
// `md:sticky` keeps the panel beside a long list, and a sticky element TALLER than the viewport
// pins its top and leaves its foot unreachable. That is survivable for figures and would be a
// straight violation of the reach law (CORE_REUSE 1.5, "an action may never live inside a region
// that can scroll or clip it") for a button. So: no actions in the rail. Put them in the main pane,
// which is never sticky, never capped and never scrolled.

/**
 * The split container. One column on a phone; two, top-aligned, from `md` up.
 *
 * ── THE RAIL COMES FIRST IN THE DOM, AND THAT IS NOT AN ACCIDENT ───────────────────────────────
 * MEASURED: with COMMAND's BUY composer offering every good a port trades, the working pane is
 * 11,875px tall at 390px. A rail written after it in the DOM is therefore ELEVEN THOUSAND PIXELS
 * below the list it is meant to be read beside — which is the same defect as hiding it. So the
 * summary is written first (it reads first, on a phone and to a screen reader) and `md:order-last`
 * moves it to the right-hand side once there are two columns to have sides.
 */
export function splitClass(): string {
  return 'flex flex-col gap-4 md:flex-row md:items-start'
}

/** The working pane — the list, the pickers, every control. `min-w-0` so a wide child scrolls
 *  inside its own pane instead of widening the page (see the header). */
export function splitMainClass(): string {
  return 'min-w-0 flex-1'
}

/** The rail — figures only. Above the working pane on a phone, to its right and sticky from `md`. */
export function splitRailClass(): string {
  return 'w-full shrink-0 md:order-last md:sticky md:top-0 md:w-72 lg:w-80'
}
