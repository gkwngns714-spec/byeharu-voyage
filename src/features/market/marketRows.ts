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
// ── §E.4: %NBR IS THE COLUMN THE GAME IS PLAYED FROM ────────────────────────────────────────────
// It is this port's mid as a percentage of the ports within 600 nm that trade the good. Below 90
// you buy; above 110 you sell; the rest is your judgement. THE TABLE IS SORTED INTO THOSE THREE
// BLOCKS, BUY FIRST — so a player who knows nothing sees the two rows that pay without scrolling.
// That ordering is the tutorial, and it is the reason this module exists rather than a `.sort()`
// call buried in the screen.
//
// The two thresholds below are the WORDS ON THE BLOCK HEADINGS, not a second derivation: the block
// a row lands in comes from the server's `advice`, never from comparing `pct_nbr` here. They are
// the same 90/110 the chain uses (migration 0009, `world.market`), printed so the player can see
// what the heading means.

import type { MarketGood } from '../../lib/rpc'

export const ADVICE_BUY_BELOW = 90
export const ADVICE_SELL_ABOVE = 110

/** §E.4's header: prices are read against the ports within this radius. Server-side constant,
 *  reprinted here as a caption. */
export const NEIGHBOUR_RADIUS_NM = 600

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

export const BLOCK_LABEL: Record<MarketBlock, string> = {
  buy: `BUY  (< ${ADVICE_BUY_BELOW}%)`,
  sell: `SELL (> ${ADVICE_SELL_ABOVE}%)`,
  hold: 'hold',
  unavailable: 'not traded here',
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
): MarketBlockView[] {
  const kept =
    filter === 'all' ? [...goods] : goods.filter((g) => g.available && g.advice === filter)

  return BLOCK_ORDER.map((block) => ({
    block,
    label: BLOCK_LABEL[block],
    rows: kept.filter((g) => blockOf(g) === block).sort(compare(sort, directionFor(block))),
  })).filter((b) => b.rows.length > 0)
}

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
