// THE DRAWN SIDEWAYS-SCROLL — pure (no React), the one spelling of "this box scrolls to the
// right, and you can SEE that it does".
//
// The recipe was written for tables (tableLayout.ts, whose header carries the measurements: three
// tables shipped with 31-101px of figures off the edge and NO visible sign of it, because
// Chromium's overlay scrollbar paints nothing at rest). The fix there — a classic scrollbar,
// thin and always present, styled through the ::-webkit-scrollbar pseudo-elements and NOT through
// `scrollbar-width: thin` (the standard property wins in Chromium and selects the overlay
// scrollbar, which is the invisible one) — is not a fact about tables. It is the affordance ANY
// in-panel sideways scroll owes the player: a scroll nobody can see is a feature that does not
// exist, and this project has shipped that defect once already.
//
// So the recipe lives here, once, and tables (scrollTableClass) and the compendium's filter
// strips compose it. A surface that hand-rolls its own ::-webkit-scrollbar rules is the silent
// copy docs/NO_SPAGHETTI.md §2 forbids.

/** The wrapper classes for a box that scrolls sideways inside its panel: contained overscroll and
 *  a drawn, thin, permanent scrollbar. The box itself supplies `overflow-x-auto` and its layout. */
export function hScrollClass(): string {
  return [
    'overscroll-x-contain',
    '[&::-webkit-scrollbar]:h-1.5',
    '[&::-webkit-scrollbar-track]:rounded [&::-webkit-scrollbar-track]:bg-surface-2',
    '[&::-webkit-scrollbar-thumb]:rounded [&::-webkit-scrollbar-thumb]:bg-edge',
  ].join(' ')
}

/** The one-line hint under a NON-TABLE sideways scroll, printed only while the box is really
 *  clipped (useClipped). Tables keep their own words (TABLE_SCROLL_HINT names the table); this is
 *  the generic sentence for a strip of controls. One authority for the words, same as the
 *  table's. */
export const HSCROLL_HINT = 'Swipe for the rest.'
