import type { PriceSeries } from '../../../lib/rpc'

// A GOOD'S LAST DAY ON ONE SIDE (owner row 229) — the card's line and its ▲▼, read off the served 1-day record
// (world.price_series, 0226). Pure. BUY reads the city's ask (what she pays), SELL its bid (what she gets). The change
// is the price now against the first point of the day the record serves; nothing is smoothed or guessed.

export interface DayLine {
  /** The side's prices over the day, oldest first (null asks dropped). */
  values: number[]
  /** (now − a day ago) ÷ a day ago, or null below two points. */
  change: number | null
}

export function dayLine(series: PriceSeries | undefined, side: 'buy' | 'sell', now: number | null): DayLine {
  const values = (series?.points ?? [])
    .map((p) => (side === 'buy' ? p.ask : p.bid))
    .filter((v): v is number => v !== null && Number.isFinite(v))
  const first = values[0]
  const change = values.length >= 2 && now !== null && first > 0 ? (now - first) / first : null
  return { values, change }
}
