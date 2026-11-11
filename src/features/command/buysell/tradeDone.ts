import { formatInt, moneyWords } from '../../../lib/format'
import type { useT } from '../../../lib/i18n'

// WHAT A PRESS OF THE TRADE PANEL'S BUTTON DID (owner row 229), and the toast's words for it:
// "Bought 10 Pepper −1,230 🪙" · "Sold 10 Pepper +1,230 🪙" · "Sailing to Lisbon". The money is the figure the panel
// was served for the units on the button (cmd.preview); none is worked out here.
//
// EVERY TOAST CARRIES ITS AMOUNT (2026-11-11, the trade-flow slice). A trip queued said only "Sailing to Lisbon"; it says
// what the trip was priced at too, with the figure's own word: the served profit of the sale it ends in ("Profit +1,230" /
// "Loss −1,183"), else what the buy costs ("Cost 856"). A buy done at the quay is a cost, not a loss: unsigned.

export interface TradeDone {
  side: 'buy' | 'sell'
  units: number
  good: string
  /** What the units came to, unsigned, or null when it was not served. */
  total: number | null
  /** A trip queued, to this city (port CODE); null for a trade done where she lies. */
  sailTo: string | null
  /** A trip that ends in a sale: the served profit of that sale (the board's sell row), or null when none was served. */
  profit?: number | null
}

export function doneWords(t: ReturnType<typeof useT>, d: TradeDone, cityName: (c: string) => string): string {
  if (d.sailTo) {
    const sail = t('desk.toastSail', { city: cityName(d.sailTo) })
    if (d.profit != null) return `${sail} · ${moneyWords('profit', d.profit)}`
    if (d.total !== null) return `${sail} · ${moneyWords(d.side === 'buy' ? 'cost' : 'total', d.total)}`
    return sail
  }
  const money = d.total === null ? '' : ` · ${moneyWords(d.side === 'buy' ? 'cost' : 'total', d.total)}`
  return t(d.side === 'buy' ? 'desk.toastBought' : 'desk.toastSold', { n: formatInt(d.units), good: d.good }) + money
}
