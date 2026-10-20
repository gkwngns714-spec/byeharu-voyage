import { useEffect } from 'react'
import { Bar, Empty, Figure, Hint, Note, Row, SeriesChart, SheetSection, Skeleton, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { worldStatsOverview, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import type { FaceProps } from './StatsScreen'
import { sharePct, toSeries } from './statsFaces'

// OVERVIEW — the world's money: who holds it, what was printed and what changed hands, how much traded.
// Four holders on their own scales (seriesChartModel.ts says why not one plane), then this period and
// the last day by kind, in the server's words.

const HOURS = 24

export function OverviewFace({ beat, onAge }: FaceProps) {
  const read = useServedRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS), { trigger: beat })
  const v = read.view
  useEffect(() => onAge(v?.age_seconds ?? null), [v, onAge])

  if (read.loading && !v) return <Waiting />
  if (!v) return <Note tone="danger">The world's figures could not be read.</Note>
  if (!v.holders || !v.period) {
    return <Empty data-testid="stats-empty">No figures yet. The first count is written within fifteen minutes.</Empty>
  }
  const h = v.holders
  const holders = [
    { id: 'players', label: 'Players', value: h.players, tone: 'accent' as const },
    { id: 'merchants', label: 'Merchants', value: h.merchants, tone: 'info' as const },
    { id: 'cities', label: 'Cities', value: h.cities, tone: 'success' as const },
    { id: 'set_aside', label: 'Set aside', value: h.set_aside, tone: 'muted' as const },
  ]

  return (
    <div data-testid="stats-overview">
      <SheetSection heading="Money in the world" trailing={<Figure value={formatDucats(h.total)} tone="ink" />}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          {holders.map((x) => (
            <div key={x.id} className="min-w-0" data-testid="stats-holder">
              <span className="block text-t-caption text-ink-faint">{x.label}</span>
              <Figure value={formatDucats(x.value)} size="figure" />
              <Bar pct={sharePct(x.value, h.total)} tone={x.tone === 'muted' ? 'accent' : x.tone} label={`${x.label}' share`} className="mt-1" />
              <SeriesChart
                points={toSeries(v.series, (p) => p[x.id as 'players' | 'merchants' | 'cities' | 'set_aside'])}
                format={formatDucats}
                label={`${x.label}, the last ${v.hours} hours`}
                tone={x.tone}
                className="mt-2"
              />
            </div>
          ))}
        </div>
        <Hint className="mt-2">Each line is on its own scale. Set aside is request escrow and dividends not yet collected.</Hint>
      </SheetSection>

      <SheetSection heading="New money and money that moved">
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <Head label="Printed, last 24 h" value={v.day?.minted ?? 0} tone="success" />
          <Head label="Burned, last 24 h" value={-(v.day?.removed ?? 0)} tone="danger" />
          <Head label="Moved between purses, 24 h" value={v.day?.moved ?? 0} tone="ink" plain />
          <Head label="Trades, 24 h" value={v.day?.trades ?? 0} tone="ink" plain count />
        </div>
        <div className="mt-3 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Printed each quarter hour</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.minted)}
              format={formatDucats}
              label="New money each period"
              tone="success"
            />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Sold to cities each quarter hour</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.sold)}
              format={formatDucats}
              label="Goods sold to cities each period"
              tone="info"
            />
          </div>
        </div>
      </SheetSection>

      <Flows heading="Last 24 hours, by kind" period={v.day} testid="stats-flows-day" />
      <Flows heading="Since the last count" period={v.period} testid="stats-flows-period" />
    </div>
  )
}

function Head({ label, value, tone, plain = false, count = false }: { label: string; value: number; tone: 'success' | 'danger' | 'ink'; plain?: boolean; count?: boolean }) {
  return (
    <div className="min-w-0">
      <span className="block text-t-caption text-ink-faint">{label}</span>
      <Figure
        value={count ? formatInt(value) : plain ? formatDucats(value) : formatDucatsDelta(value)}
        size="figure"
        tone={value === 0 ? 'muted' : tone}
      />
    </div>
  )
}

function Flows({ heading, period, testid }: { heading: string; period: StatsPeriod | null; testid: string }) {
  if (!period || period.flows.length === 0) return null
  return (
    <SheetSection heading={heading} surface data-testid={testid}>
      {period.flows.map((f, i) => (
        <Row
          key={f.kind}
          label={f.word}
          value={<Figure value={formatDucatsDelta(f.ducats)} tone={f.side === 'minted' ? 'success' : f.side === 'removed' ? 'danger' : deltaTone(0)} />}
          hairline={i < period.flows.length - 1}
        >
          <span className="block text-t-caption text-ink-faint">
            {f.side === 'minted' ? 'new money' : f.side === 'removed' ? 'money burned' : 'moved between purses'}
          </span>
        </Row>
      ))}
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
