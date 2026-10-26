import type { MoneyMove } from '../../lib/rpc'

// THE MONEY LOG'S DRIP (owner 223: *"it is not updated every second is it?"*). The arrivals job writes money rows in
// batches of ~60-90 every 15 s, so a log that shows what a read returns sits still and then jumps. A batch is queued
// oldest first and revealed a few rows per second so the queue drains in DRIP_TICKS seconds; a batch landing while
// rows are still queued drains the remainder on the very next tick, then the new batch starts. Pure, so it is tested
// without a clock.

export const DRIP_TICKS = 14

export type Drip = { queue: MoneyMove[]; owed: number; ticks: number }

export const emptyDrip: Drip = { queue: [], owed: 0, ticks: DRIP_TICKS }

const oldestFirst = (a: MoneyMove, b: MoneyMove) => Date.parse(a.at) - Date.parse(b.at) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)

/** Queue a batch (oldest first); what was still queued is owed to the next tick. */
export function enqueue(d: Drip, rows: MoneyMove[]): Drip {
  if (rows.length === 0) return d
  return { queue: [...d.queue, ...[...rows].sort(oldestFirst)], owed: d.queue.length, ticks: DRIP_TICKS }
}

/** One second: the rows to reveal now, and the queue that remains. */
export function step(d: Drip): { released: MoneyMove[]; next: Drip } {
  if (d.queue.length === 0) return { released: [], next: d }
  const n = d.owed > 0 ? d.owed : Math.ceil(d.queue.length / Math.max(1, d.ticks))
  return {
    released: d.queue.slice(0, n),
    next: { queue: d.queue.slice(n), owed: 0, ticks: d.owed > 0 ? DRIP_TICKS : Math.max(1, d.ticks - 1) },
  }
}
