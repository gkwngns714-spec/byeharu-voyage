import type { BestSale } from '../lib/rpc'

// "FROM HERE" (roadmap 2026-11-23, slice 4; X3 folds the Routes tab into it): the best sale per harbour from where her fleet lies,
// read off the board's own cards (world.best_sales, the one read Trade.tsx already asks). No figure is made here: each harbour
// keeps the one card that pays most to it, the served profit and seconds as they came.

/** How many harbours the line names. */
export const FROM_HERE = 3

/** The best paying card per harbour, at most three: the three that pay most, then nearest first (the served time). */
export function fromHere(sales: ReadonlyMap<string, BestSale> | null, n = FROM_HERE): BestSale[] {
  if (!sales) return []
  const best = new Map<string, BestSale>()
  for (const s of sales.values()) {
    // a sale beyond the first hour's near trips (0475 `near` false: the card marks it "Far") is not "from here"
    if (s.port === null || s.profit === null || !s.pays || s.profit <= 0 || s.near === false) continue
    const was = best.get(s.port)
    if (!was || (was.profit ?? 0) < s.profit) best.set(s.port, s)
  }
  const time = (s: BestSale) => s.seconds ?? (s.days ?? 0) * 86_400
  return [...best.values()]
    .sort((a, b) => (b.profit ?? 0) - (a.profit ?? 0) || a.good.localeCompare(b.good))
    .slice(0, n)
    .sort((a, b) => time(a) - time(b) || (a.profit ?? 0) - (b.profit ?? 0))
}
