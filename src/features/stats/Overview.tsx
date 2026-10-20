import { useEffect } from 'react'
import {
  Bar,
  Empty,
  Hint,
  Note,
  RankBars,
  SeriesChart,
  SheetSection,
  SignedBars,
  Skeleton,
  StackedBar,
  StatCell,
  deltaTone,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { worldStatsOverview, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import type { FaceProps } from './StatsScreen'
import { STATS_BARS, flowRanks, sharePct, toSeries, trendOf } from './statsFaces'
import { servedNow } from './statsPulse'

// OVERVIEW — the world's money: who holds it, what was printed, what was burned, what changed hands.
//
// THE SHAPE, top to bottom: the one hero figure (every purse in the world, counting to its new value),
// the four holders as one stacked bar so the composition is read before any digit, the same four as
// small multiples with their own lines (seriesChartModel.ts says why not one plane — players 0.2 M
// against cities 988 M), the world's whole purse as one chart, then the period's money as bars from a
// zero line and the kinds ranked. One accent, green–red only for new money against burned.

const HOURS = 24

export function OverviewFace({ beat, onServed }: FaceProps) {
  const read = useServedRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS), { trigger: beat })
  const v = read.view
  useEffect(() => onServed(servedNow(v)), [v, onServed])

  if (read.loading && !v) return <Waiting />
  if (!v) return <Note tone="danger">The world's figures could not be read.</Note>
  if (!v.holders || !v.period) {
    return <Empty data-testid="stats-empty">No figures yet. The first count is written within fifteen minutes.</Empty>
  }
  const h = v.holders
  const day = v.day
  const holders = [
    { id: 'players', label: 'Players', value: h.players, tone: 'accent' as const },
    { id: 'merchants', label: 'Merchants', value: h.merchants, tone: 'info' as const },
    { id: 'cities', label: 'Cities', value: h.cities, tone: 'success' as const },
    { id: 'set_aside', label: 'Set aside', value: h.set_aside, tone: 'neutral' as const },
  ]
  // What the world is worth MORE than it was: everything printed in the last day, less what burned.
  const newMoney = day === null ? null : day.minted - day.removed
  const totals = toSeries(v.series, (p) => p.players + p.merchants + p.cities + p.set_aside)

  return (
    <div data-testid="stats-overview">
      <SheetSection heading="Money in the world">
        <StatCell
          label={`Every purse in the world · last ${formatInt(v.hours)} hours`}
          value={h.total}
          format={formatDucats}
          size="hero"
          delta={newMoney === null ? undefined : { text: `${formatDucatsDelta(newMoney)} today`, tone: deltaTone(newMoney) }}
        />
        {/* The bar's own legend is OFF because the four cells under it ARE the legend: each one
            names its holder, prints its figure, and carries a share bar in the segment's own tone.
            Colour is never the only channel either way. */}
        <StackedBar
          parts={holders}
          format={formatDucats}
          label="Money in the world, by who holds it"
          legend={false}
          className="mt-3"
        />
        <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          {holders.map((x) => (
            <StatCell
              key={x.id}
              label={x.label}
              value={x.value}
              format={formatDucats}
              size="body"
              trend={trendOf(v.series, (p) => p[x.id as 'players' | 'merchants' | 'cities' | 'set_aside'])}
              data-testid="stats-holder"
            >
              <Bar
                pct={sharePct(x.value, h.total)}
                tone={x.tone}
                label={`${x.label} share of the world's money`}
                className="mt-1"
              />
            </StatCell>
          ))}
        </div>
        <SeriesChart
          points={totals}
          format={formatDucats}
          label={`Every purse in the world, the last ${formatInt(v.hours)} hours`}
          tone="accent"
          className="mt-4"
          empty={<Hint className="mt-3">The line starts with the next count — the world is counted every fifteen minutes.</Hint>}
        />
        <Hint className="mt-2">Set aside is request escrow and dividends nobody has collected yet. Each small line is on its own scale.</Hint>
      </SheetSection>

      <SheetSection heading="New money and money that moved">
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label="Printed, last 24 h" value={day?.minted ?? 0} format={formatDucatsDelta} size="body" tone="success" />
          <StatCell label="Burned, last 24 h" value={-(day?.removed ?? 0)} format={formatDucatsDelta} size="body" tone="danger" />
          <StatCell label="Moved between purses, 24 h" value={day?.moved ?? 0} format={formatDucats} size="body" />
          <StatCell label="Trades, 24 h" value={day?.trades ?? 0} format={formatInt} size="body" />
        </div>
        <SignedBars
          bars={v.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.minted - p.removed }))}
          label="New money less burned money, one bar a count"
          height="h-20"
          className="mt-4"
        />
        <Hint className="mt-2">One bar a count, the latest on the right: up is money the world printed, down is money it burned.</Hint>
        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Sold to the cities, each count</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.sold)}
              format={formatDucats}
              label="What was sold to the cities, each count"
              tone="info"
              empty={<Hint className="mt-2">The line starts with the next count.</Hint>}
            />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Bought from the cities, each count</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.bought)}
              format={formatDucats}
              label="What was bought from the cities, each count"
              tone="accent"
              empty={<Hint className="mt-2">The line starts with the next count.</Hint>}
            />
          </div>
        </div>
      </SheetSection>

      <Flows heading="Last 24 hours, by kind" period={day} testid="stats-flows-day" />
      <Flows heading="Since the last count" period={v.period} testid="stats-flows-period" />
    </div>
  )
}

/** The money of one period, by kind, biggest first — the server's words, the server's sides. */
function Flows({ heading, period, testid }: { heading: string; period: StatsPeriod | null; testid: string }) {
  if (!period || period.flows.length === 0) return null
  return (
    <SheetSection heading={heading} surface data-testid={testid}>
      <RankBars rows={flowRanks(period.flows)} format={formatDucatsDelta} />
    </SheetSection>
  )
}

function Waiting() {
  return (
    <div className="space-y-3" data-testid="stats-waiting">
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-32 w-full" />
      <Skeleton className="h-12 w-2/3" />
    </div>
  )
}
