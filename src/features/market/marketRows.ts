// THE ARRANGEMENT OF THE MARKET TABLE — pure, no React, and NO ARITHMETIC ABOUT PRICE.
//
// ── WHY THERE IS NO PRICE CODE IN THIS FOLDER ANY MORE ──────────────────────────────────────────
// `features/market/prices.ts` used to derive mid/ask/bid, %NBR and the buy/hold/sell band on this
// side of the wire. It is deleted. `world.market(port)` now returns `buy`, `sell`, `mid`,
// `pct_nbr`, `stock_band`, `available` and `advice`, derived inside the transaction that owns the
// row — and the server's number is the one the money moves on. Two authorities for a price is the
// one thing this project forbids; the client's job is to PRINT the price, not to have an opinion
// about it. Nothing in this file computes, adjusts or re-derives a served number. It arranges
// rows, and that is all.
//
// ── §E.4: %NBR IS A LOCAL PRICE INDEX, AND THAT IS ALL IT EVER WAS ──────────────────────────────
// It is this port's mid as a percentage of the ports within the neighbourhood radius that trade the
// good. Below the buy band it is cheap HERE; above the sell band it is dear HERE. THE TABLE IS CUT
// INTO THOSE THREE BLOCKS, BUY FIRST, so a player who knows nothing sees the cheap rows without
// scrolling. That ordering is the tutorial, and it is the reason this module exists rather than a
// `.sort()` call buried in the screen.
//
// WHAT IT IS NOT — AND THIS COST A PLAYER REAL MONEY. A price index cannot predict a profit: it
// contains neither port's tax, neither port's spread, nor the price impact of the order itself.
// Migration 0019's header records the measurement — salt reads 109.6 at Porto, a SELL by this
// screen's own bands, and carrying it there from Lisboa LOSES 77 ducats. The trade is named by
// `world.trade_routes`, in ducats, priced through the same quote the money moves at. This file
// arranges the index; it never presents it as advice.
//
// THE THREE NUMBERS ARE THE SERVER'S. 90, 110 and 600 were declared here as well as in the chain
// until 0019 — two authorities for one number, and a caption that could quietly stop describing the
// computation behind it. They arrive in `world.snapshot().config` now and this module prints what
// it is handed.

import type { MarketGood, SnapshotConfig } from '../../lib/rpc'

/**
 * The four blocks the table is cut into. Three are §E.4's bands, read straight off the server's
 * `advice`. The fourth is not a band at all: `available: false` means the port's culture will not
 * trade the good AT ALL (§B.4 — wine in a Maghrebi port), which is a fact about the port and can
 * never be advice to buy it.
 */
export type MarketBlock = 'buy' | 'sell' | 'hold' | 'unavailable'

export function blockOf(good: MarketGood): MarketBlock {
  return good.available ? good.advice : 'unavailable'
}

/** BUY at the top, always. The player who knows nothing must land on the rows that pay. */
export const BLOCK_ORDER: readonly MarketBlock[] = ['buy', 'sell', 'hold', 'unavailable']

/** The heading over each block, in the server's own thresholds. */
export function blockLabel(block: MarketBlock, config: SnapshotConfig): string {
  switch (block) {
    case 'buy':
      return `CHEAP HERE  (< ${config.advice_buy_below}%)`
    case 'sell':
      return `DEAR HERE  (> ${config.advice_sell_above}%)`
    case 'hold':
      return 'about the local average'
    case 'unavailable':
      return 'not traded here'
  }
}

export type SortKey = 'nbr' | 'name' | 'price' | 'stock'
export type MarketFilter = 'all' | 'buy' | 'sell'

/** The six-cell block meter of §E.4, drawn from the server's 0..6 `stock_band`. A port under a
 *  third of its target is shaded rather than filled: a shortage should not look like a stock. */
export function stockBar(band: number, cells = 6): string {
  const filled = Math.max(0, Math.min(cells, Math.round(band)))
  const short = filled <= 2
  return (short ? '▓' : '█').repeat(filled) + '░'.repeat(cells - filled)
}

/** A null %NBR means the port has no neighbour that trades the good — it has nothing to be a
 *  percentage OF, and 100 would be a lie. Sorted as if it were 100 so it does not head the table. */
function nbr(good: MarketGood): number {
  return good.pct_nbr ?? 100
}

function compare(key: SortKey, direction: 1 | -1): (a: MarketGood, b: MarketGood) => number {
  switch (key) {
    case 'nbr':
      return (a, b) => (nbr(a) - nbr(b)) * direction
    case 'name':
      return (a, b) => a.name.localeCompare(b.name)
    case 'price':
      return (a, b) => b.mid - a.mid
    case 'stock':
      return (a, b) => b.stock_band - a.stock_band || b.stock - a.stock
  }
}

/** %NBR runs cheapest-first in the BUY block and dearest-first in the SELL block: in both cases
 *  the best row in the block is its first row. Every other sort key is one direction everywhere. */
function directionFor(block: MarketBlock): 1 | -1 {
  return block === 'sell' ? -1 : 1
}

export interface MarketBlockView {
  block: MarketBlock
  label: string
  rows: MarketGood[]
}

/**
 * The whole arrangement in one call: filter, cut into blocks, sort inside each, drop the empties.
 * The screen renders what this returns and decides nothing about order.
 */
export function marketBlocks(
  goods: readonly MarketGood[],
  sort: SortKey,
  filter: MarketFilter,
  config: SnapshotConfig,
): MarketBlockView[] {
  const kept =
    filter === 'all' ? [...goods] : goods.filter((g) => g.available && g.advice === filter)

  return BLOCK_ORDER.map((block) => ({
    block,
    label: blockLabel(block, config),
    rows: kept.filter((g) => blockOf(g) === block).sort(compare(sort, directionFor(block))),
  })).filter((b) => b.rows.length > 0)
}

// `routesByGood` USED TO BE HERE, and it is now `src/domain/trade`. The Command tab's unfolded good
// row names the same destination from the same read, a screen may never import another screen
// (tests/sections.spec.ts), and copying it would have been the second author docs/NO_SPAGHETTI.md §2
// forbids. So it moved out rather than being borrowed, and MarketScreen imports the section.

/**
 * WHICH ORDER A TAP ON THIS ROW MEANS. The server advises `buy` / `hold` / `sell`; a tap has to
 * become one of two verbs, and "hold" resolves to BUY because the row is still an opportunity to
 * take a position rather than a reason to do nothing.
 *
 * It is here because the screen spelt the ternary twice — once for the hand-off and once for the
 * row's title — and the two would have had to be corrected together. One reading of the advice.
 */
export function verbFor(good: MarketGood): 'BUY' | 'SELL' {
  return good.advice === 'sell' ? 'SELL' : 'BUY'
}

/** How many rows the table is showing, for the count badge. */
export function countRows(blocks: readonly MarketBlockView[]): number {
  return blocks.reduce((n, b) => n + b.rows.length, 0)
}
