// THE ARRANGEMENT OF THE MARKET GOODS — pure, no React, and NO ARITHMETIC ABOUT PRICE.
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

import type { MarketGood } from '../../lib/rpc'
// `buyableHere` moved to domain/market 2026-09-01 — PORT trades through it too now.
// Re-exported so this file stays the one import surface the market screen already uses.
import { buyableHere, type MarketBlock } from '../../domain/market'

export { buyableHere }
export type { MarketBlock }


export function blockOf(good: MarketGood): MarketBlock {
  return buyableHere(good) ? 'traded' : 'unavailable'
}

/** What this city deals in, first. The rest is only here because she is carrying it. */
export const BLOCK_ORDER: readonly MarketBlock[] = ['traded', 'unavailable']

/**
 * The heading over each block. 0071: these used to name the server's advice thresholds — "CHEAP
 * HERE (< 90%)" — which is the comparison that has gone. A heading now states what the block IS.
 */
export function blockLabel(block: MarketBlock): string {
  return block === 'traded' ? 'traded here' : 'not traded here — she is carrying it'
}

export type SortKey = 'name' | 'price' | 'stock'
export type MarketFilter = 'all' | 'traded'

/** The player's word for a sort key. `nbr` is the schema's name for the neighbour index and the
 *  player never reads the schema — the chip used to say `%↑`, which is a glyph you had to already
 *  understand. "nearby" is the word COMMAND's good rows chose for the same figure
 *  (features/command/ArgPickers.tsx), and one figure carries one name across the game. */
export function sortWord(key: SortKey): string {
  // 0071: this existed to translate the schema's `nbr` into the player's word "nearby". The
  // neighbour comparison is gone and every remaining key is already the player's word, so it is
  // the identity — kept as the one place a future key would be translated, rather than deleted
  // and re-invented at the two call sites that read it.
  return key
}

/** The six-cell block meter of §E.4, drawn from the server's 0..6 `stock_band`. A port under a
 *  third of its target is shaded rather than filled: a shortage should not look like a stock. */
export function stockBar(band: number, cells = 6): string {
  const filled = Math.max(0, Math.min(cells, Math.round(band)))
  const short = filled <= 2
  return (short ? '▓' : '█').repeat(filled) + '░'.repeat(cells - filled)
}

function compare(key: SortKey): (a: MarketGood, b: MarketGood) => number {
  switch (key) {
    case 'name':
      return (a, b) => a.name.localeCompare(b.name)
    case 'price':
      return (a, b) => b.mid - a.mid
    case 'stock':
      return (a, b) => b.stock_band - a.stock_band || b.stock - a.stock
  }
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
  const kept = filter === 'all' ? [...goods] : goods.filter((g) => buyableHere(g))

  return BLOCK_ORDER.map((block) => ({
    block,
    label: blockLabel(block),
    rows: kept.filter((g) => blockOf(g) === block).sort(compare(sort)),
  })).filter((b) => b.rows.length > 0)
}

// `routesByGood` USED TO BE HERE, and it is now `src/domain/trade`. The Command tab's unfolded good
// row names the same destination from the same read, a screen may never import another screen
// (tests/sections.spec.ts), and copying it would have been the second author docs/NO_SPAGHETTI.md §2
// forbids. So it moved out rather than being borrowed, and MarketScreen imports the section.

/**
 * WHICH ORDER A TAP ON THIS ROW MEANS. 0071: this used to read the server's advice, which is gone.
 * It now reads the only fact left that decides between the two verbs, and the honest one: a good
 * this quay DEALS in can be bought here, and a good that is in the payload only because she is
 * carrying it can only be sold. That is `buyableHere` (0061), which is already the one authority
 * for the question and is what `blockOf` above sorts by.
 *
 * It stays in one place because the screen spelt the ternary twice — once for the hand-off and
 * once for the row's title — and the two would have had to be corrected together.
 */
export function verbFor(good: MarketGood): 'BUY' | 'SELL' {
  return buyableHere(good) ? 'BUY' : 'SELL'
}

/** How many rows the table is showing, for the count badge. */
export function countRows(blocks: readonly MarketBlockView[]): number {
  return blocks.reduce((n, b) => n + b.rows.length, 0)
}
