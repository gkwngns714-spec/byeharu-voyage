// WHAT `cmd.preview()` SAID A STORE OR A TAKE WOULD MOVE — the ONE reading of that estimate.
//
// `cmd.do_store` and `cmd.do_take` (migration 0070) both return `{good, qty, stored_here}`, and
// the dry run returns exactly that, rolled back. `qty` is what would ACTUALLY move: a TAKE moves
// only what fits, because `fleet_load` returns what fitted and the rest stays where it was — so
// a tray that asked for 30 and is told 20 prints the 20, and never works out for itself how many
// tons of a good a hold has room for (the seven-answers defect, tests/duplication.spec.ts).
//
// ── WHERE THIS BELONGS, SAID PLAINLY ──────────────────────────────────────────────────────────
// Beside `saleEstimate` in `estimate.ts`: that file is "the ONE reading of what cmd.preview()
// said", and a third verb's keys belong in it. It is its own file today only because estimate.ts
// is in another slice's hands on the day this was written (2026-09-13, owner row 88); the fold is
// a move of these fourteen lines and nothing else, and `index.ts` already exports it from here so
// the caller does not change when it moves.

import { num } from '../../lib/json'

export interface MoveEstimate {
  /** Units that would actually move — all of them for a STORE the storage can take; for a TAKE,
   *  what fits on board. Null when the dry run did not run (a fleet at sea is queueable). */
  qty: number | null
  /** Units of the good left in THIS port's storage after the move. */
  storedHere: number | null
}

export function moveEstimate(estimate: Record<string, unknown>): MoveEstimate {
  return { qty: num(estimate, 'qty'), storedHere: num(estimate, 'stored_here') }
}
