// Design-system Screen scaffold logic — pure (no React) so the width-variant contract is testable
// and react-refresh keeps Screen.tsx component-only.
//
// ── WHAT WAS HERE AND IS NOT, 2026-08-22 ───────────────────────────────────────────────────────
// `screenSplitClass()` and `screenRailClass()` — the desktop two-rail split — were written for a
// layout no screen ever adopted. Every tab shipped without calling either one, while their header
// went on explaining the `empty:hidden` dark-gate posture of a feature that does not exist.
// Deleted rather than kept warm: an unused idiom inside a design system is a second way to lay a
// screen out that nobody has had to keep true, and whoever next wants a split will want it in the
// shape of the screen that needs it. (docs/CORE_REUSE.md's carry-list still describes them; that
// row is now history rather than inventory.)

/** The Screen content column: centered, padded, space-y-4 panel rhythm. `wide` = the wider desktop
 *  measure, which the Market tab uses for its seven-column table. */
export function screenBodyClass(wide = false): string {
  return `mx-auto ${wide ? 'max-w-6xl' : 'max-w-3xl'} space-y-4 px-4 py-4 sm:px-6`
}
