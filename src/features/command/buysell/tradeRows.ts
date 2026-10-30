import { buyableHere, listedHere } from '../../../domain/market'
import type { MarketGood } from '../../../lib/rpc'

// THE COMBINED TRADE LIST, PURE (owner 2026-10-30) — the docked city's goods in ONE list, both sides in each row.
// It merges the two sides the mirrored Buy / Sell cards (CityBoard.tsx) drew apart: Buy's rows (the city's ask) and
// Sell's rows (her cargo, at the city's bid) become one row per good, the two prices side by side.

export interface TradeGoodRow {
  code: string
  /** The good's id (the price reads ask by it); null only while the catalogue has not loaded. */
  goodId: string | null
  name: string
  category: string
  units: number
  /** The city's market row for the good, or null. */
  row: MarketGood | null
  /** The city's ASK — what you pay to buy here — or null where it does not sell this. */
  buy: number | null
  /** The city's BID — what you get selling here — or null where it does not buy this. */
  sell: number | null
}

/** The docked city's goods, both sides in one list. Buy first (the goods the city sells), then the rest, by name. */
export function tradeRows(
  market: readonly MarketGood[],
  aboard: Record<string, number>,
  goodByCode: Record<string, { id?: string; name?: string; category?: string }>,
): TradeGoodRow[] {
  const byCode = new Map(market.map((g) => [g.code, g]))
  const out = new Map<string, TradeGoodRow>()
  // goods the city SELLS (you buy): its ask, and its bid where it also buys
  for (const g of market) {
    if (!buyableHere(g)) continue
    const units = aboard[g.code] ?? 0
    out.set(g.code, {
      code: g.code,
      goodId: g.good_id,
      name: g.name,
      category: g.category,
      units,
      row: g,
      buy: g.buy,
      sell: listedHere(g, units) ? g.sell : null,
    })
  }
  // goods ABOARD the city BUYS (you sell): the quay lists them (she lies here with them), so its bid stands
  for (const [code, units] of Object.entries(aboard)) {
    if (units <= 0) continue
    const row = byCode.get(code) ?? null
    const listed = row !== null && listedHere(row, units)
    const sell = listed && row ? row.sell : null
    const existing = out.get(code)
    if (existing) {
      existing.sell = sell
      existing.units = units
      continue
    }
    const good = goodByCode[code]
    out.set(code, {
      code,
      goodId: row?.good_id ?? good?.id ?? null,
      name: row?.name ?? good?.name ?? code,
      category: row?.category ?? good?.category ?? '',
      units,
      row,
      buy: null,
      sell,
    })
  }
  return [...out.values()].sort((a, b) => Number(a.buy === null) - Number(b.buy === null) || a.name.localeCompare(b.name))
}
