// HOW A CITY'S STOCK READS AGAINST ITS NORMAL LEVEL — pure, so StockGauge and the chart's stock line
// say the same thing. Two served figures in (stock, stock_target), a word and a fill out. The band
// around normal is a third either way: within it the price is about where it is centred.

export type StockLevel = 'low' | 'normal' | 'high'

/** Under two thirds of normal reads low; over four thirds reads high. */
export const STOCK_LOW = 2 / 3
export const STOCK_HIGH = 4 / 3

export function stockLevel(stock: number, target: number): StockLevel {
  if (!(target > 0)) return 'normal'
  const r = stock / target
  return r < STOCK_LOW ? 'low' : r > STOCK_HIGH ? 'high' : 'normal'
}

/** The bar's fill, 0–100, on a track of 0 … 2 × normal (normal is the middle). */
export function stockFillPct(stock: number, target: number): number {
  if (!(target > 0)) return 0
  return Math.max(0, Math.min(100, (stock / (2 * target)) * 100))
}
