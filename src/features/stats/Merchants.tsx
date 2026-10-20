import { useEffect } from 'react'
import { Empty, Figure, Flag, Hint, Note, Row, SeriesChart, SheetSection, Skeleton, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { worldStatsMerchants, type StatsMerchantHouse, type StatsMerchants } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import type { FaceProps } from './StatsScreen'
import { toSeries } from './statsFaces'

// MERCHANTS — the companies the world keeps: how many, where their fleets are, what their last day of
// laps earned (lap 2 onwards, 0097's rule), the share that lost, the five best and the five worst.

export function MerchantsFace({ beat, onAge }: FaceProps) {
  const read = useServedRead<StatsMerchants>('stats:merchants', () => worldStatsMerchants(), { trigger: beat })
  const v = read.view
  useEffect(() => onAge(v?.age_seconds ?? null), [v, onAge])
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">The merchants' figures could not be read.</Note>
  if (v.houses === undefined) return <Empty data-testid="stats-empty">No figures yet. The first count is written within fifteen minutes.</Empty>

  const states = [
    { label: 'Sailing', value: v.sailing ?? 0 },
    { label: 'In port', value: v.docked ?? 0 },
    { label: 'Repairing', value: v.repairing ?? 0 },
    { label: 'Cannot sail', value: v.unable ?? 0 },
    { label: 'Laid up', value: v.laid_up ?? 0 },
  ]
  const house = (h: StatsMerchantHouse, i: number, n: number) => (
    <Row
      key={h.name}
      mark={h.nation === null ? undefined : <Flag code={h.nation} name={nationNameOf(nationByCode, h.nation)} size="body" />}
      label={h.name}
      value={<Figure value={formatDucatsDelta(h.day)} tone={deltaTone(h.day)} />}
      hairline={i < n - 1}
    >
      <span className="block text-t-caption text-ink-faint">{`${formatInt(h.laps)} ${h.laps === 1 ? 'lap' : 'laps'} in 24 h`}</span>
    </Row>
  )

  return (
    <div data-testid="stats-merchants">
      <SheetSection heading={`${formatInt(v.houses)} merchant companies · ${formatInt(v.fleets ?? 0)} fleets`}>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Earned, last 24 h</span>
            <Figure value={formatDucatsDelta(v.profit_day ?? 0)} size="figure" tone={deltaTone(v.profit_day ?? 0)} />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Laps that lost</span>
            <Figure value={formatPct((v.losing_pct ?? 0) / 100, 1)} size="figure" tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'} />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Laps closed, 24 h</span>
            <Figure value={formatInt(v.laps_day ?? 0)} size="figure" />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Their purses</span>
            <Figure value={formatDucats(v.purse ?? 0)} size="figure" />
          </div>
        </div>
        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1" data-testid="stats-merchant-states">
          {states.map((s) => (
            <span key={s.label} className="text-t-caption text-ink-faint">
              {s.label} <span className="tabular-nums text-ink">{formatInt(s.value)}</span>
            </span>
          ))}
        </div>
        <SeriesChart
          points={toSeries(v.series, (p) => p.profit_day)}
          format={formatDucats}
          label="What the merchants earned in the last 24 hours, over time"
          tone="info"
          className="mt-3"
        />
        <Hint className="mt-2">A lap counts from its second one: the first lap buys and does not sell yet.</Hint>
      </SheetSection>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <SheetSection heading="Best day" surface data-testid="stats-merchants-top">
          {(v.top ?? []).length === 0 ? <Row label="No laps closed yet" tone="muted" hairline={false} /> : (v.top ?? []).map((h, i, a) => house(h, i, a.length))}
        </SheetSection>
        <SheetSection heading="Worst day" surface data-testid="stats-merchants-bottom">
          {(v.bottom ?? []).length === 0 ? <Row label="No laps closed yet" tone="muted" hairline={false} /> : (v.bottom ?? []).map((h, i, a) => house(h, i, a.length))}
        </SheetSection>
      </div>
    </div>
  )
}
