import { useState } from 'react'
import {
  Bar,
  DetailPage,
  Empty,
  FilterBar,
  Hint,
  Note,
  RankBars,
  SignedBars,
  StackedBar,
  StatCell,
  SummaryRow,
  deltaTone,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsOverview, type StatsNow, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { STATS_BARS, flowRanks, sharePct, toSeries, trendOf } from './statsFaces'
import { MoneyLog } from './MoneyLog'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL } from './statsFilters'
import { WatchSection } from './Watch'

// OVERVIEW — the world's money. THE COMPACT SCREEN (owner, 2026-10-31): one summary row per block,
// its key figure on the line, a press opens the block's full-screen page (DetailPage). Nothing is
// unfolded in place and nothing is removed — every former block lives whole on its page.

const HOURS = 24

export function OverviewFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const { span } = useChartSpan()
  const read = useLiveRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS, span), span)
  const v = read.view
  const [page, setPage] = useState<'money' | 'new' | null>(null)

  if (read.loading && !v) return <Waiting />
  if (!v) return <Note tone="danger">{t('stats.worldFailed')}</Note>
  if (!v.holders || !v.period) {
    return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>
  }
  const h = v.holders
  const day = v.day
  const holders = [
    { id: 'players', label: t('stats.players'), value: h.players, tone: 'accent' as const },
    { id: 'merchants', label: t('stats.merchantsHolder'), value: h.merchants, tone: 'info' as const },
    { id: 'cities', label: t('stats.citiesHolder'), value: h.cities, tone: 'success' as const },
    { id: 'set_aside', label: t('stats.setAside'), value: h.set_aside, tone: 'neutral' as const },
  ]
  const newMoney = day === null ? null : day.minted - day.removed
  const totals = toSeries(v.series, (p) => p.players + p.merchants + p.cities + p.set_aside)

  return (
    <div data-testid="stats-overview" data-span={v.span ?? ''}>
      <div className="mt-2 flex flex-col gap-2">
        <SummaryRow title={t('stats.money')} figure={formatDucats(h.total)} word={t('common.open')} onClick={() => setPage('money')} data-testid="stats-money" />
        <MoneyLog />
        <SummaryRow title={t('stats.newMoney')} figure={formatDucatsDelta(newMoney ?? 0)} word={t('common.open')} onClick={() => setPage('new')} data-testid="stats-new-money" />
        <WatchSection watch={live?.watch} />
        <FlowsByKind day={day} period={v.period} />
      </div>

      {page === 'money' && (
        <DetailPage title={t('stats.money')} figure={formatDucats(h.total)} onClose={() => setPage(null)} data-testid="stats-money-page">
          <StatCell
            label={t('stats.everyPurse')}
            value={h.total}
            format={formatDucats}
            size="hero"
            delta={newMoney === null ? undefined : { text: t('stats.today', { amount: formatDucatsDelta(newMoney) }), tone: deltaTone(newMoney) }}
          />
          <StackedBar parts={holders} format={formatDucats} label={t('stats.byHolder')} legend={false} className="mt-3" />
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
                <Bar pct={sharePct(x.value, h.total)} tone={x.tone} label={t('stats.shareOf', { who: x.label })} className="mt-1" />
              </StatCell>
            ))}
          </div>
          <StatsChart title={t('stats.purseSeries')} points={totals} format={formatDucats} label={t('stats.purseSeries')} tone="accent" className="mt-4" empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>} />
        </DetailPage>
      )}

      {page === 'new' && (
        <DetailPage title={t('stats.newMoney')} figure={formatDucatsDelta(newMoney ?? 0)} onClose={() => setPage(null)} data-testid="stats-new-money-page">
          <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
            <StatCell label={t('stats.printed')} value={day?.minted ?? 0} format={formatDucatsDelta} size="body" tone="success" />
            <StatCell label={t('stats.burned')} value={-(day?.removed ?? 0)} format={formatDucatsDelta} size="body" tone="danger" />
            <StatCell label={t('stats.moved')} value={day?.moved ?? 0} format={formatDucats} size="body" />
            <StatCell label={t('stats.trades')} value={day?.trades ?? 0} format={formatInt} size="body" />
          </div>
          <SignedBars bars={v.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.minted - p.removed }))} label={t('stats.netBars')} height="h-20" className="mt-4" />
          <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.soldCities')}</span>
              <StatsChart title={t('stats.soldCities')} points={toSeries(v.series, (p) => p.sold)} format={formatDucats} label={t('stats.soldSeries')} tone="info" empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>} />
            </div>
            <div className="min-w-0">
              <span className="block text-t-caption text-ink-faint">{t('stats.boughtCities')}</span>
              <StatsChart title={t('stats.boughtCities')} points={toSeries(v.series, (p) => p.bought)} format={formatDucats} label={t('stats.boughtSeries')} tone="accent" empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>} />
            </div>
          </div>
        </DetailPage>
      )}
    </div>
  )
}

const SIDES = [ALL, 'minted', 'removed', 'moved'] as const

/** The two periods' money by kind under one filter of its side (0244, owner row 228). The filter is
 *  a tile grid on the compact screen; each period is a summary row that opens its own page. */
function FlowsByKind({ day, period }: { day: StatsPeriod | null; period: StatsPeriod | null }) {
  const t = useT()
  const [choice, choose] = useFilterChoice('stats.overview', { side: ALL })
  const side = oneOf(choice.side, SIDES, ALL)
  if ((day?.flows.length ?? 0) === 0 && (period?.flows.length ?? 0) === 0) return null
  return (
    <>
      <FilterBar
        className="mt-2"
        data-testid="stats-flows-filters"
        chips={{
          label: t('stats.filterLabel'),
          options: SIDES.map((id) => ({
            id,
            label: t(id === ALL ? 'stats.all' : id === 'minted' ? 'stats.flowNew' : id === 'removed' ? 'stats.flowBurned' : 'stats.flowMoved'),
          })),
          value: side,
          onChange: (id) => choose({ side: id }),
        }}
      />
      <Flows heading={t('stats.lastDay')} period={day} side={side} testid="stats-flows-day" />
      <Flows heading={t('stats.sinceCount')} period={period} side={side} testid="stats-flows-period" />
    </>
  )
}

/** A period of money by kind: a summary row with the kind count; its page holds the ranked bars. */
function Flows({ heading, period, side, testid }: { heading: string; period: StatsPeriod | null; side: string; testid: string }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  if (!period || period.flows.length === 0) return null
  const flows = side === ALL ? period.flows : period.flows.filter((f) => f.side === side)
  if (flows.length === 0) return null
  return (
    <>
      <SummaryRow title={heading} figure={formatInt(flows.length)} word={t('common.open')} onClick={() => setOpen(true)} data-testid={testid} />
      {open && (
        <DetailPage title={heading} figure={formatInt(flows.length)} onClose={() => setOpen(false)} data-testid={`${testid}-page`}>
          <RankBars rows={flowRanks(flows)} format={formatDucatsDelta} />
        </DetailPage>
      )}
    </>
  )
}

function Waiting() {
  return (
    <div className="space-y-3" data-testid="stats-waiting">
      <div className="h-24 w-full animate-pulse rounded-tile bg-surface" />
      <div className="h-32 w-full animate-pulse rounded-tile bg-surface" />
      <div className="h-12 w-2/3 animate-pulse rounded-tile bg-surface" />
    </div>
  )
}
