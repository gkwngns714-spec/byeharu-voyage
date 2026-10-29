import {
  Bar,
  Empty,
  FilterBar,
  Hint,
  Note,
  RankBars,
  SheetSection,
  SignedBars,
  Skeleton,
  StackedBar,
  StatCell,
  deltaTone,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsOverview, type StatsNow, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { STATS_BARS, flowRanks, seriesWindow, sharePct, toSeries, trendOf } from './statsFaces'
import { MoneyLog } from './MoneyLog'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { useNewsMarks } from '../../live/useNewsMarks'
import { ALL } from './statsFilters'
import { WatchSection } from './Watch'

// OVERVIEW — the world's money: who holds it, what was printed, what was burned, what changed hands.
//
// THE SHAPE, top to bottom: the one hero figure (every purse in the world, counting to its new value),
// the four holders as one stacked bar so the composition is read before any digit, the same four as
// small multiples with their own lines (seriesChartModel.ts says why not one plane — players 0.2 M
// against cities 988 M), the world's whole purse as one chart, then the period's money as bars from a
// zero line and the kinds ranked. One accent, green–red only for new money against burned.
//
// EVERYTHING MOVES EVERY SECOND (0232, owner row 213): the read answers NOW and is asked every second while the face
// is open (useLiveRead). The holders and the hero are the live counters (0224's world.stats_now, served inside the
// read); "the last 24 h" is the count's quarter hours plus the minutes since; "since the last count" is the count in
// progress; every chart's last point is now() — the money line at its live total, the bars and the sold / bought
// lines at the period in progress. Nothing here adds a figure: each is the server's.
//
// THE MONEY LOG (0235, owner row 219) stands beside World money: every money move as it happens (MoneyLog.tsx).

const HOURS = 24

/** `live` is the RIGHT NOW band's answer (world.stats_now), handed down for the economy watch it carries (0229). */
export function OverviewFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const { span } = useChartSpan()   // 0246: one span for every chart; a press re-asks at once, the figures stay on screen
  const read = useLiveRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS, span), span)
  const v = read.view
  // 0279: the world's news dots, read over the window the charts draw (the served series' own instants);
  // one read feeds the three charts the design names (world money, sold, bought).
  const [fromMs, toMs] = seriesWindow(v?.series ?? [])
  const marks = useNewsMarks('world', null, null, fromMs, toMs)

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
  // What the world is worth MORE than it was: everything printed in the last day, less what burned.
  const newMoney = day === null ? null : day.minted - day.removed
  const totals = toSeries(v.series, (p) => p.players + p.merchants + p.cities + p.set_aside)

  return (
    // `relative`: the money log stands in the column's right gutter on the wide glass, beside World money (MoneyLog.tsx)
    <div className="relative" data-testid="stats-overview" data-span={v.span ?? ''}>
      <SheetSection heading={t('stats.money')}>
        <StatCell
          label={t('stats.everyPurse')}
          value={h.total}
          format={formatDucats}
          size="hero"
          delta={newMoney === null ? undefined : { text: t('stats.today', { amount: formatDucatsDelta(newMoney) }), tone: deltaTone(newMoney) }}
        />
        {/* The bar's own legend is OFF because the four cells under it ARE the legend: each one
            names its holder, prints its figure, and carries a share bar in the segment's own tone.
            Colour is never the only channel either way. */}
        <StackedBar
          parts={holders}
          format={formatDucats}
          label={t('stats.byHolder')}
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
                label={t('stats.shareOf', { who: x.label })}
                className="mt-1"
              />
            </StatCell>
          ))}
        </div>
        <StatsChart
          title={t('stats.purseSeries')}
          points={totals}
          format={formatDucats}
          label={t('stats.purseSeries')}
          tone="accent"
          className="mt-4"
          empty={<Hint className="mt-3">{t('stats.lineSoon')}</Hint>}
          marks={marks}
        />
      </SheetSection>
      <MoneyLog />

      <SheetSection heading={t('stats.newMoney')}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label={t('stats.printed')} value={day?.minted ?? 0} format={formatDucatsDelta} size="body" tone="success" />
          <StatCell label={t('stats.burned')} value={-(day?.removed ?? 0)} format={formatDucatsDelta} size="body" tone="danger" />
          <StatCell label={t('stats.moved')} value={day?.moved ?? 0} format={formatDucats} size="body" />
          <StatCell label={t('stats.trades')} value={day?.trades ?? 0} format={formatInt} size="body" />
        </div>
        <SignedBars
          bars={v.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.minted - p.removed }))}
          label={t('stats.netBars')}
          height="h-20"
          className="mt-4"
        />
        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">{t('stats.soldCities')}</span>
            <StatsChart
              title={t('stats.soldCities')}
              points={toSeries(v.series, (p) => p.sold)}
              format={formatDucats}
              label={t('stats.soldSeries')}
              tone="info"
              empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>}
              marks={marks}
            />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">{t('stats.boughtCities')}</span>
            <StatsChart
              title={t('stats.boughtCities')}
              points={toSeries(v.series, (p) => p.bought)}
              format={formatDucats}
              label={t('stats.boughtSeries')}
              tone="accent"
              empty={<Hint className="mt-2">{t('stats.lineSoon')}</Hint>}
              marks={marks}
            />
          </div>
        </div>
      </SheetSection>

      <WatchSection watch={live?.watch} />
      <FlowsByKind day={day} period={v.period} />
    </div>
  )
}

const SIDES = [ALL, 'minted', 'removed', 'moved'] as const

/** The two periods' money by kind under one filter of its side (0244, owner row 228): new, burned or moved. */
function FlowsByKind({ day, period }: { day: StatsPeriod | null; period: StatsPeriod | null }) {
  const t = useT()
  const [choice, choose] = useFilterChoice('stats.overview', { side: ALL })
  const side = oneOf(choice.side, SIDES, ALL)
  if ((day?.flows.length ?? 0) === 0 && (period?.flows.length ?? 0) === 0) return null
  return (
    <>
      <FilterBar
        className="mt-4"
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

/** The money of one period, by kind, biggest first — the server's words, the server's sides. */
function Flows({ heading, period, side, testid }: { heading: string; period: StatsPeriod | null; side: string; testid: string }) {
  if (!period || period.flows.length === 0) return null
  const flows = side === ALL ? period.flows : period.flows.filter((f) => f.side === side)
  if (flows.length === 0) return null
  return (
    <SheetSection heading={heading} surface data-testid={testid}>
      <RankBars rows={flowRanks(flows)} format={formatDucatsDelta} />
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
