// PRICE FORMATION — one authority, pure, no React. DESIGN.md G.1 transcribed exactly:
//
//   mid = base_value
//       x affinity                                  -- structural, authored: 0.25 .. 3.00
//       x (stock_target / max(stock, 1)) ^ 0.5      -- elasticity 0.5
//       x (1 + drift)                               -- stochastic, +/-0.25
//       x (1 + season_mod)                          -- -0.30 .. +0.30
//       x (1 - 0.004 x dev_commerce)                -- developed ports trade cheaper
//   mid = clamp(mid, 0.35 x base_value, 3.50 x base_value)
//
//   ask (you pay)     = mid x (1 + tax_rate + spread/2) x (1 - purchasing_bonus)
//   bid (you receive) = mid x (1 - spread/2) x (1 + sales_bonus) x (1 - tax_rate)
//   spread            = 0.06 - 0.002 x dev_commerce   (floor 0.02)
//
// V0 has no officers (K.1), so purchasing_bonus = sales_bonus = 0. The terms stay named in the
// signature rather than deleted — a term removed from a formula is a fork waiting to happen.
//
// SERVER AUTHORITY. G.7 rule 7: "the client never computes a price it then submits." Everything
// here is DISPLAY and the live CMD check line. When cmd.issue() lands, the price the player is
// charged is derived inside the transaction from the row it just locked, and if the two ever
// disagree the server is right and this file is the bug.
//
// %NBR — THE COLUMN THE GAME IS PLAYED FROM (E.4). It is this port's mid as a percentage of the
// mean mid across ports within NEIGHBOUR_RADIUS_NM. Below 90 you buy, above 110 you sell, and
// "the rest is your judgement". Ports that cannot trade the good at all (culture, B.4) are
// excluded from the mean rather than counted as zero: a port that refuses wine has no opinion
// about the price of wine.

import type { Culture, Good, GoodCode, Port, PortCode, PortGood } from '../../fixtures/types'
import { gcDistanceNm } from '../command/geo'

/** E.4's header: "prices vs ports within 600 nm". */
export const NEIGHBOUR_RADIUS_NM = 600

/** E.4's two thresholds — the entire read of the market table. */
export const BUY_BAND_MAX = 90
export const SELL_BAND_MIN = 110

/** G.7 rule 1 — daily volume cap per (player, port, good). */
export const DAILY_CAP_FRACTION = 0.35

export function isAvailable(good: Good, culture: Culture): boolean {
  return !good.forbiddenCultures.includes(culture)
}

/** G.1 — spread = 0.06 - 0.002 x dev_commerce, floored at 0.02. */
export function spreadOf(port: Port): number {
  return Math.max(0.02, 0.06 - 0.002 * port.devCommerce)
}

/** The tax the PLAYER actually pays: the Mayor's rate less their reputation relief (H.3, I.3). */
export function effectiveTaxRate(port: Port, taxRelief: number): number {
  return Math.max(0, port.marketTaxRate - taxRelief)
}

/** G.1's mid. Returns null when the port's culture refuses the good. */
export function midPrice(good: Good, port: Port, row: PortGood): number | null {
  if (!isAvailable(good, port.culture)) return null
  const elasticity = Math.sqrt(row.stockTarget / Math.max(row.stock, 1))
  const raw =
    good.baseValue *
    row.affinity *
    elasticity *
    (1 + row.drift) *
    (1 + row.seasonMod) *
    (1 - 0.004 * port.devCommerce)
  return Math.min(3.5 * good.baseValue, Math.max(0.35 * good.baseValue, raw))
}

export function askPrice(mid: number, port: Port, taxRelief: number, purchasingBonus = 0): number {
  return mid * (1 + effectiveTaxRate(port, taxRelief) + spreadOf(port) / 2) * (1 - purchasingBonus)
}

export function bidPrice(mid: number, port: Port, taxRelief: number, salesBonus = 0): number {
  return mid * (1 - spreadOf(port) / 2) * (1 + salesBonus) * (1 - effectiveTaxRate(port, taxRelief))
}

/** G.2 — stock/target, the number the stock band renders. 1.0 is a healthy port. */
export function stockRatio(row: PortGood): number {
  return row.stockTarget <= 0 ? 0 : row.stock / row.stockTarget
}

/** The six-cell block bar of E.4: full cells for stock, shaded for a shortage. */
export function stockBand(row: PortGood, cells = 6): string {
  const ratio = stockRatio(row)
  const filled = Math.max(0, Math.min(cells, Math.round(ratio * cells)))
  const short = ratio < 0.35
  return (short ? '▓' : '█').repeat(Math.max(short ? 1 : 0, filled)) + '░'.repeat(cells - Math.max(short ? 1 : 0, filled))
}

export interface PriceIndex {
  ports: Map<PortCode, Port>
  goods: Map<GoodCode, Good>
  rows: Map<string, PortGood>
  /** port -> the ports within NEIGHBOUR_RADIUS_NM of it. Computed once. */
  neighbours: Map<PortCode, readonly PortCode[]>
}

export function rowKey(port: PortCode, good: GoodCode): string {
  return `${port}:${good}`
}

export function buildPriceIndex(
  ports: readonly Port[],
  goods: readonly Good[],
  portGoods: readonly PortGood[],
): PriceIndex {
  const neighbours = new Map<PortCode, readonly PortCode[]>()
  for (const a of ports) {
    neighbours.set(
      a.code,
      ports
        .filter((b) => b.code !== a.code && gcDistanceNm(a.lat, a.lon, b.lat, b.lon) <= NEIGHBOUR_RADIUS_NM)
        .map((b) => b.code),
    )
  }
  return {
    ports: new Map(ports.map((p) => [p.code, p])),
    goods: new Map(goods.map((g) => [g.code, g])),
    rows: new Map(portGoods.map((r) => [rowKey(r.port, r.good), r])),
    neighbours,
  }
}

export function midAt(index: PriceIndex, port: PortCode, good: GoodCode): number | null {
  const p = index.ports.get(port)
  const g = index.goods.get(good)
  const row = index.rows.get(rowKey(port, good))
  if (!p || !g || !row) return null
  return midPrice(g, p, row)
}

/** THE %NBR DERIVATION. Returns null when the good is untraded here, or when no neighbour within
 *  600 nm trades it (a lone port has nothing to be a percentage OF, and 100% would be a lie). */
export function nbrPercent(index: PriceIndex, port: PortCode, good: GoodCode): number | null {
  const here = midAt(index, port, good)
  if (here === null) return null
  const around = (index.neighbours.get(port) ?? [])
    .map((code) => midAt(index, code, good))
    .filter((v): v is number => v !== null)
  if (around.length === 0) return null
  const mean = around.reduce((a, b) => a + b, 0) / around.length
  if (mean <= 0) return null
  return (here / mean) * 100
}

export type PriceBand = 'buy' | 'sell' | 'hold'

export function bandOf(nbr: number | null): PriceBand {
  if (nbr === null) return 'hold'
  if (nbr < BUY_BAND_MAX) return 'buy'
  if (nbr > SELL_BAND_MIN) return 'sell'
  return 'hold'
}

/** One rendered row of the MARKET table. */
export interface MarketRow {
  good: Good
  row: PortGood
  mid: number
  ask: number
  bid: number
  nbr: number | null
  band: PriceBand
  stockRatio: number
  stockBand: string
  /** G.7 rule 1 — what the player may still move today. */
  dailyCap: number
  history7: readonly number[]
  event?: PortGood['event']
}

export function buildMarketRows(
  index: PriceIndex,
  port: PortCode,
  taxRelief: number,
): readonly MarketRow[] {
  const p = index.ports.get(port)
  if (!p) return []
  const out: MarketRow[] = []
  for (const good of index.goods.values()) {
    const row = index.rows.get(rowKey(port, good.code))
    if (!row) continue
    const mid = midPrice(good, p, row)
    if (mid === null) continue
    const nbr = nbrPercent(index, port, good.code)
    out.push({
      good,
      row,
      mid,
      ask: askPrice(mid, p, taxRelief),
      bid: bidPrice(mid, p, taxRelief),
      nbr,
      band: bandOf(nbr),
      stockRatio: stockRatio(row),
      stockBand: stockBand(row),
      dailyCap: Math.round(DAILY_CAP_FRACTION * row.stockTarget),
      history7: row.history7 ?? [],
      event: row.event,
    })
  }
  return out
}

/** G.2 — orders execute in 10-tun steps, each repricing, so a large order pays a worse average.
 *  "buying raises the price you are still buying at." This is the estimate the CMD check line
 *  shows; the server does the same walk inside the transaction and its answer is the real one. */
export const STEP_TUNS = 10

export function steppedBuyCost(
  good: Good,
  port: Port,
  row: PortGood,
  tuns: number,
  taxRelief: number,
): { total: number; average: number; filled: number } {
  let stock = row.stock
  let total = 0
  let filled = 0
  let left = tuns
  while (left > 0 && stock > 1) {
    const step = Math.min(STEP_TUNS, left)
    const mid = midPrice(good, port, { ...row, stock })
    if (mid === null) break
    total += askPrice(mid, port, taxRelief) * step
    stock -= step
    filled += step
    left -= step
  }
  return { total, average: filled > 0 ? total / filled : 0, filled }
}

export function steppedSellRevenue(
  good: Good,
  port: Port,
  row: PortGood,
  tuns: number,
  taxRelief: number,
): { total: number; average: number } {
  let stock = row.stock
  let total = 0
  let left = tuns
  while (left > 0) {
    const step = Math.min(STEP_TUNS, left)
    const mid = midPrice(good, port, { ...row, stock })
    if (mid === null) break
    total += bidPrice(mid, port, taxRelief) * step
    stock += step
    left -= step
  }
  return { total, average: tuns > 0 ? total / tuns : 0 }
}
