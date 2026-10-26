import { formatInt, formatPriceDelta } from '../../../lib/format'
import type { useT } from '../../../lib/i18n'

// WHAT A PRESS OF THE TRADE PANEL'S BUTTON DID (owner row 229), and the toast's words for it:
// "Bought 10 Pepper −1,230 🪙" · "Sold 10 Pepper +1,230 🪙" · "Sailing to Lisbon". The money is the figure the panel
// was served for the units on the button (cmd.preview); none is worked out here.

export interface TradeDone {
  side: 'buy' | 'sell'
  units: number
  good: string
  /** What the units came to, unsigned, or null when it was not served. */
  total: number | null
  /** A trip queued, to this city (port CODE); null for a trade done where she lies. */
  sailTo: string | null
}

export function doneWords(t: ReturnType<typeof useT>, d: TradeDone, cityName: (c: string) => string): string {
  if (d.sailTo) return t('desk.toastSail', { city: cityName(d.sailTo) })
  const money = d.total === null ? '' : ` ${formatPriceDelta(d.side === 'buy' ? -d.total : d.total)}`
  return t(d.side === 'buy' ? 'desk.toastBought' : 'desk.toastSold', { n: formatInt(d.units), good: d.good }) + money
}
