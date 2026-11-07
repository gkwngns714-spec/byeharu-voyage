import type { SeriesTone } from '../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPriceFigure } from '../lib/format'
import type { useT } from '../lib/i18n'
import type { HistoryCityPoint, HistoryCompanyPoint, HistoryGoodPoint, HistoryWorldPoint } from '../lib/rpc'

// WHAT EACH RECORD DRAWS (0316): the figures of `HistoryChart`, one table per subject, pure data. The numbers are the server's; a company's net is the two lines above it.

/** One figure of a record: its words, how it reads, and which of the point's fields it draws. Null is a figure this period does not have: no point is drawn for it. */
export interface HistoryLine<P> {
  id: string
  label: string
  tone: SeriesTone
  pick: (p: P) => number | null
  format: (v: number) => string
  /** A SUM over the period (money sold, earned, minted), not a level: the period still open is left out of its line (`wholePeriods`). */
  flow?: true
}

type T = ReturnType<typeof useT>

export const worldLines = (t: T): HistoryLine<HistoryWorldPoint>[] => [
  { id: 'players', label: t('stats.players'), tone: 'accent', pick: (p) => p.players, format: formatDucats },
  { id: 'merchants', label: t('stats.merchantsHolder'), tone: 'info', pick: (p) => p.merchants, format: formatDucats },
  { id: 'cities', label: t('stats.citiesHolder'), tone: 'success', pick: (p) => p.cities, format: formatDucats },
  { id: 'set_aside', label: t('stats.setAside'), tone: 'muted', pick: (p) => p.set_aside, format: formatDucats },
  { id: 'minted', label: t('stats.histPrinted'), tone: 'success', pick: (p) => p.minted, format: formatDucats, flow: true },
  { id: 'removed', label: t('stats.histBurned'), tone: 'danger', pick: (p) => p.removed, format: formatDucats, flow: true },
  { id: 'sold', label: t('stats.soldCities'), tone: 'info', pick: (p) => p.sold, format: formatDucats, flow: true },
  { id: 'bought', label: t('stats.boughtCities'), tone: 'accent', pick: (p) => p.bought, format: formatDucats, flow: true },
]

export const cityLines = (t: T): HistoryLine<HistoryCityPoint>[] => [
  { id: 'purse', label: t('town.i_purse'), tone: 'accent', pick: (p) => p.purse, format: formatDucats },
  { id: 'profit', label: t('stats.histProfit'), tone: 'info', pick: (p) => p.profit, format: formatDucatsDelta, flow: true },
  { id: 'income', label: t('stats.histIncome'), tone: 'success', pick: (p) => p.income, format: formatDucats, flow: true },
  { id: 'spending', label: t('stats.histSpending'), tone: 'danger', pick: (p) => p.spending, format: formatDucats, flow: true },
]

export const goodLines = (t: T): HistoryLine<HistoryGoodPoint>[] => [
  { id: 'close', label: t('stats.histPrice'), tone: 'accent', pick: (p) => p.close, format: formatPriceFigure },
  { id: 'sold', label: t('stats.histSold'), tone: 'info', pick: (p) => p.sold, format: formatInt, flow: true },
  { id: 'bought', label: t('stats.histBought'), tone: 'muted', pick: (p) => p.bought, format: formatInt, flow: true },
]

export const companyLines = (t: T): HistoryLine<HistoryCompanyPoint>[] => [
  { id: 'earned', label: t('stats.histEarned'), tone: 'success', pick: (p) => p.earned, format: formatDucats, flow: true },
  { id: 'lost', label: t('stats.histLost'), tone: 'danger', pick: (p) => p.lost, format: formatDucats, flow: true },
  { id: 'net', label: t('stats.histNet'), tone: 'accent', pick: (p) => p.earned - p.lost, format: formatDucatsDelta, flow: true },
]
