import type { TradeRoute, TradeRoutes } from '../../lib/rpc'

/**
 * THE COMPARISON, INDEXED BY GOOD CODE, so a row can find its own destination in one lookup rather
 * than scanning the list per row.
 *
 * It is a plain re-keying of what the server sent and it computes NOTHING: a row that is not in the
 * answer prints nothing, because "the quay found no port in reach that pays more for this" and "the
 * quay was never asked" both look like an absent row and neither is a number. Which of the two it
 * is, is the CALLER's to know — it holds the `TradeRoutes` and therefore knows whether the read has
 * landed at all.
 *
 * ── WHY IT IS A SECTION AND NOT THE MARKET TAB'S ───────────────────────────────────────────────
 * It was `features/market/marketRows.ts:132`, which made MARKET the owner of a question COMMAND
 * also asks: the unfolded good row on the order composer names the same destination, from the same
 * read. A screen may never import another screen (tests/sections.spec.ts), and the two moves that
 * are NOT a fix are copying it and re-exporting it (docs/NO_SPAGHETTI.md §2) — so it moved. The
 * market's copy is deleted; there is one.
 */
export function routesByGood(routes: TradeRoutes | undefined): Record<string, TradeRoute> {
  const out: Record<string, TradeRoute> = {}
  for (const r of routes?.routes ?? []) out[r.code] = r
  return out
}
