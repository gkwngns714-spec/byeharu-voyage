import type { BoardSellRow, GoodBoard } from '../../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CHOICE OF WHERE TO SELL (2026-11-22, P1 of docs/design/playable-2026-11-22.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The play-test: a good's card named one city and "Buy & sell" bought, sailed there and sold. The player never chose
// where. The Buy & sell sheet now offers THE BEST THREE PLACES TO SELL, each with its time and profit; the card's sale
// (world.best_sales: the best per day within her purse) stands lit as the default, and another can be pressed before Go.
//
// EVERY FIGURE IS SERVED, AND FROM ONE READ: the three are rows of the trip's own board (world.good_board, from the buy
// city, for the units the sheet holds — useTripBoard.ts), the very read whose row the sheet prints as its profit, time,
// wages and fees. So a row pressed is the same trip to that city at the same units, and the sheet's profit is the row's
// to the coin. Nothing is priced, added or divided here: this only PICKS rows, by the served figures, as CargoBest does.
//
// WHICH THREE (the lead's rule, 2026-11-22 — near-and-quick against far-and-rich):
//   1. the default — the card's sale (the server's best per day);
//   2. the QUICKEST row that still pays, when it is another city;
//   3. the RICHEST row (the most total profit), when it is another city;
//   then the next best by profit per day, to three. Only rows that pay, that she can sail, and whose stores fit beside the
//   units. Where nothing quick pays (every paying city is far), the list shows what exists. The per-day figure only RANKS
//   the fill; it is never printed.
// They stand nearest first, so near-and-quick reads above far-and-rich.

export const SALE_CHOICES = 3

/** A row she could be sent to with this buy: priced, sailable, paying, its stores fitting beside the units. */
function usable(r: BoardSellRow, buyAt: string): boolean {
  return r.port !== buyAt && r.price_each != null && r.sailable === true && r.profit != null && r.profit > 0 && r.supplies?.fits !== false
}

/** The places the Buy & sell sheet offers — rows of the trip's board, nearest first. `open` (the city the sheet sells at now)
 *  is kept whatever it is, so the lit row never vanishes. Fewer than two: there is no choice to offer (null). */
export function saleChoices(board: GoodBoard | null, buyAt: string, open: string, best: string | null): BoardSellRow[] | null {
  if (!board) return null
  const rows = board.sell.filter((r) => usable(r, buyAt))
  const byPort = (p: string | null) => (p === null ? undefined : rows.find((r) => r.port === p))
  const profit = (r: BoardSellRow) => r.profit as number
  const richest = [...rows].sort((x, y) => profit(y) - profit(x) || x.port.localeCompare(y.port))
  const quickest = [...rows].sort((x, y) => (x.days ?? Infinity) - (y.days ?? Infinity) || x.port.localeCompare(y.port))
  const perDay = (r: BoardSellRow) => (r.days != null && r.days > 0 ? profit(r) / r.days : -Infinity)
  const byRate = [...rows].sort((x, y) => perDay(y) - perDay(x) || x.port.localeCompare(y.port))
  const pick: BoardSellRow[] = []
  const add = (r: BoardSellRow | undefined) => {
    if (r && pick.length < SALE_CHOICES && !pick.includes(r)) pick.push(r)
  }
  // the open sale first: whatever city the sheet sells at stays on the list (even one this filter would drop)
  add(byPort(open) ?? board.sell.find((r) => r.port === open && r.profit != null))
  add(byPort(best))
  add(quickest[0])
  add(richest[0])
  for (const r of byRate) add(r)
  if (pick.length < 2) return null
  return pick.sort((x, y) => (x.days ?? Infinity) - (y.days ?? Infinity) || x.port.localeCompare(y.port))
}
