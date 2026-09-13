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
// SAIL, AND SINCE 0081 SELL. The other verbs' estimates have exactly one reader each
// (`features/port/orderCheck.tsx`), and folding a thing that is not duplicated would be
// inventing a home rather than finding one. SELL gained a second reader on 2026-09-09: the trade
// tray (through `src/live/useTrade.ts`) previews the real sale to print what it will realise —
// the owner's row 74, *"by selling them i would like to see the profits of this trade"* — and
// COMMAND's check line already read the same estimate's `qty` / `total` / `avg_price`. So the
// keys of a sale live here now, once. SINCE SLICE 3 (2026-09-13) two more served keys are read
// here — `avg_price` and `haggle_saved` (0083) — because the haggle thread stakes them on both
// sides, and a thread that read them by hand would be the second reading this file exists to end.

import { num } from '../../lib/json'

export interface SaleEstimate {
  /** Tuns the quay would take, at this quantity. */
  qty: number | null
  /** The ducats the purse would receive — `world.quote`'s stepped total, the figure the sale pays. */
  total: number | null
  /** What those tuns COST her, per tun — the served average (0081). Null when the hold does not
   *  know, which is not zero: a screen prints nothing for it. */
  basis: number | null
  /** `round(basis × qty)`, the server's own arithmetic. */
  cost: number | null
  /** `total − cost`, realised by `cmd.do_sell` against the basis — the profit the owner asked to
   *  see. Null exactly when `basis` is. Never computed on this side of the wire. */
  profit: number | null
  /** The served figure PER UNIT for this quantity — `world.quote`'s `avg_price`, the stepped
   *  book's own average, on both sides (0007). This is the ONLY figure a screen may show as "what
   *  he names" once a bargain is open: `world.market`'s buy/sell never reflect one (0022 refused
   *  to move the published price), and `cmd.preview` is the one authority that does. */
  avg_price: number | null
  /** What today's open bargain took off THIS lot, in ducats — `world.quote`'s `haggle_saved`
   *  (0083), accumulated per step inside the same walk that priced it. 0 with no bargain. */
  haggle_saved: number | null
}

/** Read a trade estimate — `cmd.do_sell`'s (or `cmd.do_buy`'s) own result, run and rolled back by
 *  `cmd.preview`. A buy leaves `basis`, `cost` and `profit` null and fills the rest. */
export function saleEstimate(estimate: Record<string, unknown> | undefined): SaleEstimate {
  return {
    qty: num(estimate, 'qty'),
    total: num(estimate, 'total'),
    basis: num(estimate, 'basis'),
    cost: num(estimate, 'cost'),
    profit: num(estimate, 'profit'),
    avg_price: num(estimate, 'avg_price'),
    haggle_saved: num(estimate, 'haggle_saved'),
  }
}

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
