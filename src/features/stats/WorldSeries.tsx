import type { ReactNode } from 'react'
import { Card, Counter, Hint } from '../../components/ui'
import type { StatsWorldPoint } from '../../lib/rpc'
import { StatsChart } from './StatsChart'
import { CARD_CHART_H, toSeries } from './statsFaces'
import { useT } from '../../lib/i18n'

// THE GENERAL GRAPH (its read is useWorldSeries.ts) of a list face (owner, 2026-11-05: *"in stats, make the cities tab like merchants"*, *"same for markets, a
// general graph would be nice"*). stats_cities and stats_markets serve no series of their own, but the world read already serves
// one across every city and every good — `world.stats_overview`'s `series`, per count, over the shared span (`useChartSpan`).
// Cities and Markets read THAT, under the Overview's own subject (liveRead: one ask per subject, so the same RPC with the same
// arguments), and draw it the way Merchants draws its two chart cards. Nothing is computed here but what `pick` returns. A card of
// a SUM (sold, bought, trade) is handed the read's WHOLE rows (`wholeRows`), a card of a level (the cities' money) the series as
// served, its live point included: the card draws what it is given.

/** One chart card of a list face: the card's title is its label, the current figure above a 176 px line (Merchants' pattern). */
export function SeriesCard({
  title,
  value,
  format,
  series,
  pick,
  tone,
  ...rest
}: {
  title: string
  value: number
  format: (v: number) => string
  series: readonly StatsWorldPoint[]
  pick: (p: StatsWorldPoint) => number
  tone: 'accent' | 'info'
} & { 'data-testid'?: string }): ReactNode {
  const t = useT()
  return (
    <Card title={title} {...rest}>
      <Counter value={value} format={format} size="figure" />
      <StatsChart
        look="chart"
        title={title}
        points={toSeries(series, pick)}
        format={format}
        label={title}
        tone={tone}
        height={CARD_CHART_H}
        className="mt-3"
        empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
      />
    </Card>
  )
}
