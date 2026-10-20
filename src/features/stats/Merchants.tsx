import { useEffect } from 'react'
import {
  Empty,
  Flag,
  Hint,
  Note,
  RankBars,
  SeriesChart,
  SheetSection,
  Skeleton,
  StackedBar,
  StatCell,
  deltaTone,
  type RankRow,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { worldStatsMerchants, type StatsMerchantHouse, type StatsMerchants } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import type { FaceProps } from './StatsScreen'
import { toSeries } from './statsFaces'
import { servedNow } from './statsPulse'

// MERCHANTS — the companies the world keeps: how many, where their fleets are, what their last day of
// laps earned (lap 2 onwards, 0097's rule), the share that lost, the five best and the five worst.
//
// WHERE THE FLEETS ARE is one stacked bar rather than five numbers in a line (2026-10-20, request 188):
// the question is "is the world sailing or stuck", and that is a composition, not five counts. The tones
// are §4.4's: blue is moving, green is safely in port, amber is being repaired, red cannot sail, grey is
// laid up.

export function MerchantsFace({ beat, onServed }: FaceProps) {
  const read = useServedRead<StatsMerchants>('stats:merchants', () => worldStatsMerchants(), { trigger: beat })
  const v = read.view
  useEffect(() => onServed(servedNow(v)), [v, onServed])
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">The merchants' figures could not be read.</Note>
  if (v.houses === undefined) return <Empty data-testid="stats-empty">No figures yet. The first count is written within fifteen minutes.</Empty>

  const states = [
    { id: 'sailing', label: 'Sailing', value: v.sailing ?? 0, tone: 'info' as const },
    { id: 'docked', label: 'In port', value: v.docked ?? 0, tone: 'success' as const },
    { id: 'repairing', label: 'Repairing', value: v.repairing ?? 0, tone: 'warning' as const },
    { id: 'unable', label: 'Cannot sail', value: v.unable ?? 0, tone: 'danger' as const },
    { id: 'laid_up', label: 'Laid up', value: v.laid_up ?? 0, tone: 'neutral' as const },
  ]
  const houses = (list: readonly StatsMerchantHouse[]): RankRow[] =>
    list.map((h) => ({
      id: h.name,
      label: (
        <span className="flex min-w-0 items-center gap-2">
          {h.nation !== null && <Flag code={h.nation} name={nationNameOf(nationByCode, h.nation)} size="body" />}
          <span className="min-w-0 truncate">{h.name}</span>
        </span>
      ),
      value: h.day,
      tone: h.day >= 0 ? ('success' as const) : ('danger' as const),
      note: `${formatInt(h.laps)} ${h.laps === 1 ? 'lap' : 'laps'} in 24 h`,
    }))

  return (
    <div data-testid="stats-merchants">
      <SheetSection heading={`${formatInt(v.houses)} merchant companies · ${formatInt(v.fleets ?? 0)} fleets`}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell
            label="Earned, last 24 h"
            value={v.profit_day ?? 0}
            format={formatDucatsDelta}
            size="body"
            tone={deltaTone(v.profit_day ?? 0)}
            trend={v.series.map((p) => p.profit_day)}
          />
          <StatCell
            label="Laps that lost"
            value={(v.losing_pct ?? 0) / 100}
            format={(x) => formatPct(x, 1)}
            size="body"
            tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'}
          />
          <StatCell label="Laps closed, 24 h" value={v.laps_day ?? 0} format={formatInt} size="body" />
          <StatCell label="Their purses" value={v.purse ?? 0} format={formatDucats} size="body" trend={v.series.map((p) => p.purse)} />
        </div>
        <StackedBar
          parts={states}
          format={formatInt}
          label="Where the merchants' fleets are right now"
          className="mt-4"
          data-testid="stats-merchant-states"
        />
        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">What they earned in a day, count by count</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.profit_day)}
              format={formatDucats}
              label="What the merchants earned in the last 24 hours, over time"
              tone="info"
              empty={<Hint className="mt-2">The line starts with the next count.</Hint>}
            />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Fleets at sea, count by count</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.sailing)}
              format={formatInt}
              label="How many merchant fleets were at sea, over time"
              tone="accent"
              empty={<Hint className="mt-2">The line starts with the next count.</Hint>}
            />
          </div>
        </div>
        <Hint className="mt-2">A lap counts from its second one: the first lap buys and does not sell yet.</Hint>
      </SheetSection>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <SheetSection heading="Best day" surface data-testid="stats-merchants-top">
          <RankBars rows={houses(v.top ?? [])} format={formatDucatsDelta} empty="No laps closed yet" />
        </SheetSection>
        <SheetSection heading="Worst day" surface data-testid="stats-merchants-bottom">
          <RankBars rows={houses(v.bottom ?? [])} format={formatDucatsDelta} empty="No laps closed yet" />
        </SheetSection>
      </div>
    </div>
  )
}
