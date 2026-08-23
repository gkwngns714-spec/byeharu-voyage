// WHAT `cmd.preview()` SAID A SAIL WOULD BE — the ONE reading of that estimate.
//
// `cmd.preview()` runs the real verb in a subtransaction and rolls it back, so the estimate is not
// a guess: it is what the order just did. Its shape is the verb's own — `cmd.do_sail` returns
// `{voyage_id, total_nm, voyage_days}` (migration 0019:522) — and every figure in it is SAILED,
// over the authored leg graph, which is the entire reason a screen may never work one out itself.
// `docs/DEV_LOG.md` records the defect that made this a rule: a picker printed Seville at 169 nm
// against the server's 286 and then SORTED the list by it.
//
// ── WHY IT IS A SECTION AND NOT A COMPONENT (2026-08-23) ───────────────────────────────────────
// Two screens read this one estimate now: COMMAND draws the full readout under the composer, and
// MAP prints the passage beside "Sail here" when a harbour is tapped. Two readers is fine; two
// READINGS is not — a rename of `total_nm` would otherwise have to be found in two files, which is
// question 2 of `docs/NO_SPAGHETTI.md` §1. So the KEYS live here, once, and what each screen does
// with the two numbers — a `StatRow` under the composer, a corner-panel line on the chart — stays
// each screen's own chrome, which is legitimately different.
//
// ONLY SAIL. The other verbs' estimates have exactly one reader each (PreviewPanel), and folding a
// thing that is not duplicated would be inventing a home rather than finding one.

import { num } from '../../lib/json'

export interface SailEstimate {
  /** The SAILED distance, in nautical miles, over the route the voyage will really take. */
  nm: number | null
  /** Voyage-days — game time, not the real-world wait. Divide by `config.time_compression` for
   *  that, and take the compression from the SERVER's snapshot, never from a constant. */
  days: number | null
}

/** Read a SAIL estimate. Every field is nullable: a server that returned none says so, and a
 *  screen prints a shorter block rather than a fabricated number. */
export function sailEstimate(estimate: Record<string, unknown> | undefined): SailEstimate {
  return { nm: num(estimate, 'total_nm'), days: num(estimate, 'voyage_days') }
}
