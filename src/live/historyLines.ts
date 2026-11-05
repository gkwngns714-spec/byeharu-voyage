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
}

type T = ReturnType<typeof useT>

export const worldLines = (t: T): HistoryLine<HistoryWorldPoint>[] => [
  { id: 'players', label: t('stats.players'), tone: 'accent', pick: (p) => p.players, format: formatDucats },
  { id: 'merchants', label: t('stats.merchantsHolder'), tone: 'info', pick: (p) => p.merchants, format: formatDucats },
  { id: 'cities', label: t('stats.citiesHolder'), tone: 'success', pick: (p) => p.cities, format: formatDucats },
  { id: 'set_aside', label: t('stats.setAside'), tone: 'muted', pick: (p) => p.set_aside, format: formatDucats },
  { id: 'minted', label: t('stats.histPrinted'), tone: 'success', pick: (p) => p.minted, format: formatDucats },
  { id: 'removed', label: t('stats.histBurned'), tone: 'danger', pick: (p) => p.removed, format: formatDucats },
  { id: 'sold', label: t('stats.soldCities'), tone: 'info', pick: (p) => p.sold, format: formatDucats },
  { id: 'bought', label: t('stats.boughtCities'), tone: 'accent', pick: (p) => p.bought, format: formatDucats },
]

export const cityLines = (t: T): HistoryLine<HistoryCityPoint>[] => [
  { id: 'purse', label: t('town.i_purse'), tone: 'accent', pick: (p) => p.purse, format: formatDucats },
  { id: 'profit', label: t('stats.histProfit'), tone: 'info', pick: (p) => p.profit, format: formatDucatsDelta },
  { id: 'income', label: t('stats.histIncome'), tone: 'success', pick: (p) => p.income, format: formatDucats },
  { id: 'spending', label: t('stats.histSpending'), tone: 'danger', pick: (p) => p.spending, format: formatDucats },
]

export const goodLines = (t: T): HistoryLine<HistoryGoodPoint>[] => [
  { id: 'close', label: t('stats.histPrice'), tone: 'accent', pick: (p) => p.close, format: formatPriceFigure },
  { id: 'sold', label: t('stats.histSold'), tone: 'info', pick: (p) => p.sold, format: formatInt },
  { id: 'bought', label: t('stats.histBought'), tone: 'muted', pick: (p) => p.bought, format: formatInt },
]

export const companyLines = (t: T): HistoryLine<HistoryCompanyPoint>[] => [
  { id: 'earned', label: t('stats.histEarned'), tone: 'success', pick: (p) => p.earned, format: formatDucats },
  { id: 'lost', label: t('stats.histLost'), tone: 'danger', pick: (p) => p.lost, format: formatDucats },
  { id: 'net', label: t('stats.histNet'), tone: 'accent', pick: (p) => p.earned - p.lost, format: formatDucatsDelta },
]
