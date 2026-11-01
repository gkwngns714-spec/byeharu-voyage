import { useState, type ReactNode } from 'react'
import {
  Bar,
  Counter,
  DetailPage,
  Empty,
  FilterBar,
  Hint,
  Note,
  RankBars,
  StackedBar,
  SummaryRow,
  deltaTone,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsOverview, type StatsNow, type StatsOverview, type StatsPeriod, type StatsWatch } from '../../lib/rpc'
import { flowRanks, sharePct, toSeries } from './statsFaces'
import { MoneyLog } from './MoneyLog'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL } from './statsFilters'

// OVERVIEW — the world's money, ON THE FACE (owner, 2026-11-01: *"everything is folded in stats this
// is soo wrong. make it compact showing everything possible"*). The blocks that used to open
// full-screen pages (the world's purses, the new money, the economy watch) now stand inline as compact
// grids: one caption line per figure, charts at sparkline scale. Only the two ranked "money by kind"
// lists still open a page — they are unbounded per-period lists, and their measured size is in the
// dev-log. Nothing here folds: there is no chevron and no closed state on this face.

const HOURS = 24

/** One compact fact: its word above, its figure below — the smallest complete cell on the tab. */
function Cell({ label, children, testid }: { label: ReactNode; children: ReactNode; testid?: string }) {
  return (
    <div className="min-w-0" data-testid={testid}>
      <span className="block truncate text-t-caption text-ink-faint">{label}</span>
      <span className="block truncate text-t-body tabular-nums">{children}</span>
    </div>
  )
}

export function OverviewFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const { span } = useChartSpan()
  const read = useLiveRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS, span), span)
  const v = read.view

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
      {/* ── WORLD MONEY — every purse on the face ─────────────────────────────────────────── */}
      <section className="mt-2" data-testid="stats-money">
        <div className="flex items-baseline justify-between gap-2">
          <span className="text-t-caption text-ink-faint">{t('stats.money')}</span>
          <span className="flex items-baseline gap-2">
            <Counter value={h.total} format={formatDucats} size="body" />
            <span className="text-t-caption text-ink-faint">·</span>
            <Counter value={newMoney ?? 0} format={formatDucatsDelta} size="body" tone={deltaTone(newMoney ?? 0)} />
          </span>
        </div>
        <StackedBar parts={holders} format={formatDucats} label={t('stats.byHolder')} legend={false} className="mt-1" />
        <div className="mt-1 grid grid-cols-4 gap-x-3">
          {holders.map((x) => (
            <Cell key={x.id} label={x.label} testid="stats-holder">
              <Counter value={x.value} format={formatDucats} size="body" />
              <Bar pct={sharePct(x.value, h.total)} tone={x.tone} label={t('stats.shareOf', { who: x.label })} className="mt-0.5" />
            </Cell>
          ))}
        </div>
        <StatsChart title={t('stats.purseSeries')} points={totals} format={formatDucats} label={t('stats.purseSeries')} tone="accent" className="mt-1" empty={<Hint className="mt-1">{t('stats.lineSoon')}</Hint>} />
      </section>

      {/* ── NEW MONEY — printed · burned · moved · trades, the net on the money line above ── */}
      <section className="mt-2" data-testid="stats-new-money">
        <div className="grid grid-cols-4 gap-x-3">
          <Cell label={t('stats.printed')}>
            <Counter value={Number(day?.minted ?? 0)} format={formatDucatsDelta} size="body" tone="success" />
          </Cell>
          <Cell label={t('stats.burned')}>
            <Counter value={-(day?.removed ?? 0)} format={formatDucatsDelta} size="body" tone="danger" />
          </Cell>
          <Cell label={t('stats.moved')}>
            <Counter value={day?.moved ?? 0} format={formatDucats} size="body" />
          </Cell>
          <Cell label={t('stats.trades')}>
            <Counter value={day?.trades ?? 0} format={formatInt} size="body" />
          </Cell>
        </div>
      </section>

      {/* ── THE ECONOMY WATCH — seven figures, no page ───────────────────────────────────── */}
      <WatchInline watch={live?.watch} />

      {/* ── THE MONEY LOG — the latest moves on the face, the live feed behind its row ───── */}
      <MoneyLog />

      {/* ── MONEY BY KIND — two UNBOUNDED lists; their pages are the measured exception ──── */}
      <FlowsByKind day={day} period={v.period} />
    </div>
  )
}

const SIDES = [ALL, 'minted', 'removed', 'moved'] as const

/** The economy watch (0229): its seven figures in two compact rows. It used to be one summary row
 *  opening a page; the figures fit at caption scale, so they stand here. */
function WatchInline({ watch }: { watch: StatsWatch | null | undefined }) {
  const t = useT()
  if (!watch) return null
  const text = (n: number | undefined) => (n === undefined ? '—' : formatInt(n))
  const swing =
    watch.swing_p50 === undefined || watch.swing_p50 === null || watch.swing_p90 === undefined || watch.swing_p90 === null
      ? '—'
      : `${formatPct(watch.swing_p50, 1)} / ${formatPct(watch.swing_p90, 1)}`
  // ONE WRAPPING FACTS LINE (the live band's own density): seven labelled figures, caption scale.
  const facts: { label: string; value: ReactNode }[] = [
    { label: t('watch.newMoney'), value: <Counter value={watch.new_slot ?? 0} format={formatDucatsDelta} size="body" tone={deltaTone(watch.new_slot ?? 0)} /> },
    { label: t('watch.totalDay'), value: <Counter value={watch.total_delta_day ?? 0} format={formatDucatsDelta} size="body" tone={deltaTone(watch.total_delta_day ?? 0)} /> },
    { label: t('watch.underReserve'), value: text(watch.under_reserve) },
    { label: t('watch.broke'), value: text(watch.broke) },
    { label: t('watch.underThin', { n: formatInt(watch.thin ?? 10_000) }), value: text(watch.under_thin) },
    { label: t('watch.gifts'), value: watch.gifts_ducats === undefined ? '—' : `${formatInt(watch.gifts ?? 0)} · ${formatDucats(watch.gifts_ducats)}` },
    { label: t('watch.swing'), value: swing },
  ]
  return (
    <section className="mt-2 flex flex-wrap items-baseline gap-x-3 gap-y-0.5 text-t-caption text-ink-faint" data-testid="stats-watch">
      {facts.map((f) => (
        <span key={f.label} className="whitespace-nowrap">
          {f.label} <span className="tabular-nums text-ink">{f.value}</span>
        </span>
      ))}
    </section>
  )
}

/** The two periods' money by kind (0244, owner row 228). Each period is a ranked list of the day's
 *  kinds — unbounded by the world's activity, so its row opens a page; the side filter lives INSIDE
 *  that page (owner, 2026-11-01: the face shows figures, not controls). */
function FlowsByKind({ day, period }: { day: StatsPeriod | null; period: StatsPeriod | null }) {
  const t = useT()
  if ((day?.flows.length ?? 0) === 0 && (period?.flows.length ?? 0) === 0) return null
  return (
    <>
      <Flows heading={t('stats.lastDay')} period={day} testid="stats-flows-day" />
      <Flows heading={t('stats.sinceCount')} period={period} testid="stats-flows-period" />
    </>
  )
}

function Flows({ heading, period, testid }: { heading: string; period: StatsPeriod | null; testid: string }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const [choice, choose] = useFilterChoice(`stats:${testid}`, { side: ALL })
  const side = oneOf(choice.side, SIDES, ALL)
  if (!period || period.flows.length === 0) return null
  const flows = side === ALL ? period.flows : period.flows.filter((f) => f.side === side)
  return (
    <>
      <SummaryRow title={heading} figure={formatInt(period.flows.length)} word={t('common.open')} onClick={() => setOpen(true)} data-testid={testid} />
      {open && (
        <DetailPage title={heading} figure={formatInt(period.flows.length)} onClose={() => setOpen(false)} data-testid={`${testid}-page`}>
          <FilterBar
            className="mb-2"
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
          {flows.length === 0 ? <Empty data-testid="stats-no-match">{t('stats.noMatch')}</Empty> : <RankBars rows={flowRanks(flows)} format={formatDucatsDelta} />}
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
