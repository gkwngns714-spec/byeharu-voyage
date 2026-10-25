import {
  Empty,
  Flag,
  Hint,
  Note,
  RankBars,
  SeriesChart,
  SectionColumns,
  SheetSection,
  Skeleton,
  StackedBar,
  StatCell,
  deltaTone,
  type RankRow,
  Clip,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsMerchants, type StatsMerchantHouse, type StatsMerchants } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import type { FaceProps } from './StatsScreen'
import { toSeries, withLivePoint } from './statsFaces'

// MERCHANTS — the companies the world keeps: how many, where their fleets are, what their last day of
// laps earned (lap 2 onwards, 0097's rule), the share that lost, the five best and the five worst.
//
// WHERE THE FLEETS ARE is one stacked bar rather than five numbers in a line (2026-10-20, request 188):
// the question is "is the world sailing or stuck", and that is a composition, not five counts. The tones
// are §4.4's: blue is moving, green is safely in port, amber is being repaired, red cannot sail, grey is
// laid up.

export function MerchantsFace({ beat, live }: FaceProps) {
  const t = useT()
  const read = useServedRead<StatsMerchants>('stats:merchants', () => worldStatsMerchants(), { trigger: beat })
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.merchantsFailed')}</Note>
  if (v.houses === undefined) return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>

  const states = [
    { id: 'sailing', label: t('stats.sailing'), value: v.sailing ?? 0, tone: 'info' as const },
    { id: 'docked', label: t('stats.inPort'), value: v.docked ?? 0, tone: 'success' as const },
    { id: 'repairing', label: t('stats.repairing'), value: v.repairing ?? 0, tone: 'warning' as const },
    { id: 'unable', label: t('stats.cannotSail'), value: v.unable ?? 0, tone: 'danger' as const },
    { id: 'laid_up', label: t('stats.laidUp'), value: v.laid_up ?? 0, tone: 'neutral' as const },
  ]
  const houses = (list: readonly StatsMerchantHouse[]): RankRow[] =>
    list.map((h) => ({
      id: h.name,
      label: (
        <span className="flex min-w-0 items-center gap-2">
          {h.nation !== null && <Flag code={h.nation} name={nationNameOf(nationByCode, h.nation)} size="body" />}
          <Clip>{h.name}</Clip>
        </span>
      ),
      value: h.day,
      tone: h.day >= 0 ? ('success' as const) : ('danger' as const),
      note: t('stats.laps', { n: formatInt(h.laps), count: h.laps }),
    }))

  return (
    <div data-testid="stats-merchants">
      <SheetSection heading={t('stats.companiesFleets', { houses: formatInt(v.houses), fleets: formatInt(v.fleets ?? 0) })}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell
            label={t('stats.earned24')}
            value={v.profit_day ?? 0}
            format={formatDucatsDelta}
            size="body"
            tone={deltaTone(v.profit_day ?? 0)}
            trend={v.series.map((p) => p.profit_day)}
          />
          <StatCell
            label={t('stats.lapsLost')}
            value={(v.losing_pct ?? 0) / 100}
            format={(x) => formatPct(x, 1)}
            size="body"
            tone={(v.losing_pct ?? 0) > 50 ? 'danger' : 'ink'}
          />
          <StatCell label={t('stats.lapsClosed')} value={v.laps_day ?? 0} format={formatInt} size="body" />
          {/* 0224: their money and the at-sea line's last point are the live counters; the rest of the face is the count's */}
          <StatCell label={t('stats.theirPurses')} value={live?.merchants ?? v.purse ?? 0} format={formatDucats} size="body" trend={v.series.map((p) => p.purse)} />
        </div>
        <StackedBar
          parts={states}
          format={formatInt}
          label={t('stats.whereFleets')}
          className="mt-4"
          data-testid="stats-merchant-states"
        />
        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">{t('stats.earnedDay')}</span>
            <SeriesChart
              points={toSeries(v.series, (p) => p.profit_day)}
              format={formatDucats}
              label={t('stats.earnedLabel')}
              tone="info"
              empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>}
            />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">{t('stats.atSeaSeries')}</span>
            <SeriesChart
              points={withLivePoint(toSeries(v.series, (p) => p.sailing), live?.at, live?.at_sea_merchants)}
              format={formatInt}
              label={t('stats.atSeaLabel')}
              tone="accent"
              empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>}
            />
          </div>
        </div>
      </SheetSection>
      <SectionColumns count={2}>
        <SheetSection heading={t('stats.bestDay')} surface data-testid="stats-merchants-top">
          <RankBars rows={houses(v.top ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />
        </SheetSection>
        <SheetSection heading={t('stats.worstDay')} surface data-testid="stats-merchants-bottom">
          <RankBars rows={houses(v.bottom ?? [])} format={formatDucatsDelta} empty={t('stats.noLaps')} />
        </SheetSection>
      </SectionColumns>
    </div>
  )
}
