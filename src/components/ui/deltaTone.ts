// THE TONE OF A SIGNED FIGURE — pure, in its own module for trayDetents.ts's reason: a file that
// exports a component and a helper breaks Fast Refresh, and a rule worth reading without a
// browser is a rule worth testing without one.
//
// docs/UI_DIRECTION.md §4.4: green–red only ever mean cheap–dear or gain–loss. A profit, a net to
// purse, a haggle saved: what is above zero is `success`, below it `danger`, and exactly zero is
// plain ink — a zero painted green would say "gain" about nothing. Spelt in TradeTray on 2026-09-11
// and about to be spelt again by the manifest and the receipt, which is docs/NO_SPAGHETTI.md §1's
// threshold ("written a second time → it becomes a function"), so it became this.

import type { FigureTone } from './Figure'

export function deltaTone(n: number): FigureTone {
  return n < 0 ? 'danger' : n > 0 ? 'success' : 'ink'
}
