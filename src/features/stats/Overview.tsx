import { useState } from 'react'
import {
  Band,
  Button,
  Card,
  CardZone,
  Empty,
  FilterBar,
  Hint,
  ListPanel,
  Note,
  RankBars,
  Segmented,
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
import { worldStatsOverview, type StatsHolders, type StatsNow, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { CARD_CHART_H, STATS_BARS, flowRanks, toSeries, trendOf } from './statsFaces'
import { MoneyLogControls, MoneyRows } from './MoneyLog'
import { loadMoveFilter, saveMoveFilter, sliceMoves, useMoneyFeed, type MoveFilter } from './moneyFeed'
import { useLiveRead } from './statsLive'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL } from './statsFilters'
import { WatchCard } from './Watch'

// OVERVIEW — the world's money, ALL ON THE FACE, in cards (owner, 2026-11-01, row 260: *"everything is folded in stats
// this is soo wrong"*; 2026-11-02, row 267: *"it looks so wrong. The past was better. right now everything is on left,
// too packed"*). Under the live band (LiveNow.tsx):
//
//   WHO HOLDS IT   the stacked bar and the four holders' figures, each with its trend beside it
//   MONEY FLOWS    the net of the day, printed / burned / moved / trades, one bar a count
//   ECONOMY WATCH  the seven figures the closed economy is judged by (Watch.tsx)
//   THREE CHARTS   the world's money, what was sold to cities, what was bought from them — each 160 px tall, each a
//                  press to its large view (StatsChart.tsx)
//   THE MONEY LOG  every move as it happens (or the day's money by kind) — one card, beside the figures from 1,280
//
// The figure cards stand two across in a `CardZone` (the 8 columns beside the log); the log is the tall card at the
// right and shows its first twenty moves, the rest one press away ("Show all") — so it ends where the figures end,
// and no column is left empty under the shorter one. What moved, and where (docs/dev-log/2026-11-01-unfold-stats.md §1):
// the old hero figure is the band's `World money`, its "today" is the Money flows figure. Every read is exactly what
// it was — asked every second (statsLive.ts).

const HOURS = 24
const LOG_FIRST = 15
type View = 'moves' | 'kinds'

export function OverviewFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const { span } = useChartSpan()
  const read = useLiveRead<StatsOverview>('stats:overview', () => worldStatsOverview(HOURS, span), span)
  const v = read.view

  if (read.loading && !v) return <Waiting />
  if (!v) return <Note tone="danger" className="md:col-span-12">{t('stats.worldFailed')}</Note>
  if (!v.holders || !v.period) {
    return <Empty className="md:col-span-12" data-testid="stats-empty">{t('stats.noFigures')}</Empty>
  }
  return <OverviewReady live={live} v={v} holders={v.holders} />
}

/** The face once the world's figures have answered. The money feed is read from here — for as long as the
 *  face stands, whichever view the panel shows — exactly as the money log's row was (it mounted when this
 *  answer did, not before); the drip keeps what it holds across a switch of view. */
function OverviewReady({ live, v, holders: h }: { live: StatsNow | null; v: StatsOverview; holders: StatsHolders }) {
  const t = useT()
  const feed = useMoneyFeed()
  const [view, setView] = useState<View>('moves')
  const [filter, setFilter] = useState<MoveFilter>(loadMoveFilter)
  const [all, setAll] = useState(false)
  const [choice, choose] = useFilterChoice('stats.overview', { side: ALL })
  const day = v.day
  const holders = [
    { id: 'players', label: t('stats.players'), value: h.players, tone: 'accent' as const },
    { id: 'merchants', label: t('stats.merchantsHolder'), value: h.merchants, tone: 'info' as const },
    { id: 'cities', label: t('stats.citiesHolder'), value: h.cities, tone: 'success' as const },
    { id: 'set_aside', label: t('stats.setAside'), value: h.set_aside, tone: 'neutral' as const },
  ]
  const newMoney = day === null ? null : day.minted - day.removed
  const totals = toSeries(v.series, (p) => p.players + p.merchants + p.cities + p.set_aside)
  const side = oneOf(choice.side, SIDES, ALL)

  const moves = feed.view === null ? null : sliceMoves(feed.view, filter)
  const chooseMoves = (f: MoveFilter) => {
    setFilter(f)
    saveMoveFilter(f)
  }
  const logRows = moves?.rows ?? []
  const shownRows = all ? logRows : logRows.slice(0, LOG_FIRST)
  const more = view === 'moves' && !all && logRows.length > LOG_FIRST

  return (
    <Band data-testid="stats-overview" data-span={v.span ?? ''}>
      <CardZone>
        <Card title={t('stats.byHolder')} data-testid="stats-money">
          <StackedBar parts={holders} format={formatDucats} label={t('stats.byHolder')} legend={false} />
          <div className="mt-5 flex flex-col gap-4">
            {holders.map((x) => (
              <StatCell
                key={x.id}
                look="stacked"
                mark={<span className={`h-2.5 w-2.5 shrink-0 rounded-full ${SWATCH[x.tone]}`} aria-hidden="true" />}
                label={x.label}
                value={x.value}
                format={formatDucats}
                trend={trendOf(v.series, (p) => p[x.id as 'players' | 'merchants' | 'cities' | 'set_aside'])}
                data-testid="stats-holder"
              />
            ))}
          </div>
        </Card>

        <Card title={t('stats.newMoney')} data-testid="stats-new-money">
          <StatCell
            look="stacked"
            label={t('stats.netShort')}
            value={newMoney ?? 0}
            format={formatDucatsDelta}
            tone={deltaTone(newMoney ?? 0)}
          />
          <div className="mt-3">
            <StatCell look="line" label={t('stats.printed')} value={day?.minted ?? 0} format={formatDucatsDelta} tone="success" />
            <StatCell look="line" label={t('stats.burned')} value={-(day?.removed ?? 0)} format={formatDucatsDelta} tone="danger" />
            <StatCell look="line" label={t('stats.moved')} value={day?.moved ?? 0} format={formatDucats} />
            <StatCell look="line" label={t('stats.trades')} value={day?.trades ?? 0} format={formatInt} />
          </div>
          <SignedBars
            bars={v.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.minted - p.removed }))}
            label={t('stats.netBars')}
            height="h-24"
            className="mt-5"
          />
          <span className="mt-2 block text-t-caption text-ink-muted">{t('stats.netBars')}</span>
        </Card>

        <WatchCard watch={live?.watch} />

        <Card title={t('stats.purseSeries')} data-testid="stats-chart-world">
          <StatsChart
            look="chart"
            title={t('stats.purseSeries')}
            points={totals}
            format={formatDucats}
            label={t('stats.purseSeries')}
            tone="accent"
            height={CARD_CHART_H}
            empty={<Hint>{t('stats.lineSoon')}</Hint>}
          />
        </Card>
        <Card title={t('stats.soldCities')} data-testid="stats-chart-sold">
          <StatsChart
            look="chart"
            title={t('stats.soldCities')}
            points={toSeries(v.series, (p) => p.sold)}
            format={formatDucats}
            label={t('stats.soldSeries')}
            tone="info"
            height={CARD_CHART_H}
            empty={<Hint>{t('stats.lineSoon')}</Hint>}
          />
        </Card>
        <Card title={t('stats.boughtCities')} data-testid="stats-chart-bought">
          <StatsChart
            look="chart"
            title={t('stats.boughtCities')}
            points={toSeries(v.series, (p) => p.bought)}
            format={formatDucats}
            label={t('stats.boughtSeries')}
            tone="accent"
            height={CARD_CHART_H}
            empty={<Hint>{t('stats.lineSoon')}</Hint>}
          />
        </Card>
      </CardZone>

      <ListPanel
        look="card"
        span="side"
        title={t('feed.heading')}
        controls={
          <>
            <Segmented
              segments={[
                { id: 'moves', label: t('stats.moves') },
                { id: 'kinds', label: t('stats.lastDay') },
              ]}
              value={view}
              onChange={setView}
              label={t('feed.heading')}
              columns={2}
              className="shrink-0"
            />
            {view === 'moves' ? (
              <MoneyLogControls filter={filter} onFilter={chooseMoves} total={moves?.base.length ?? 0} counts={moves?.counts ?? new Map()} />
            ) : (
              <FilterBar
                compact
                data-testid="stats-flows-filters"
                sort={{
                  id: 'side',
                  label: t('stats.filterLabel'),
                  options: SIDES.map((id) => ({
                    id,
                    label: t(id === ALL ? 'stats.all' : id === 'minted' ? 'stats.flowNew' : id === 'removed' ? 'stats.flowBurned' : 'stats.flowMoved'),
                  })),
                  value: side,
                  onChange: (id) => choose({ side: id }),
                }}
              />
            )}
          </>
        }
        footer={
          more ? (
            <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-log-show-all">
              {t('stats.showAll')}
            </Button>
          ) : undefined
        }
        data-testid={view === 'moves' ? 'money-log' : 'stats-flows'}
      >
        {view === 'moves' ? (
          feed.view === null ? (
            feed.loading ? <Skeleton className="my-1 h-10 w-full" /> : <Empty className="my-1">{t('feed.none')}</Empty>
          ) : (
            <MoneyRows rows={shownRows} />
          )
        ) : (
          <Kinds day={day} period={v.period} side={side} />
        )}
      </ListPanel>
    </Band>
  )
}

const SIDES = [ALL, 'minted', 'removed', 'moved'] as const

/** The swatch each holder wears — the stacked bar's own colours, so a part of the bar and its figure are one colour. */
const SWATCH = { accent: 'bg-accent', info: 'bg-info', success: 'bg-success', neutral: 'bg-ink-faint' } as const

/** The two periods' money by kind under one filter of its side (0244, owner row 228): the day's, then the
 *  count's — each a heading and its ranked bars, in the panel. */
function Kinds({ day, period, side }: { day: StatsPeriod | null; period: StatsPeriod | null; side: string }) {
  const t = useT()
  if ((day?.flows.length ?? 0) === 0 && (period?.flows.length ?? 0) === 0) return <Empty className="my-1">{t('stats.noFigures')}</Empty>
  return (
    <>
      <Flows heading={t('stats.lastDay')} period={day} side={side} testid="stats-flows-day" />
      <Flows heading={t('stats.sinceCount')} period={period} side={side} testid="stats-flows-period" />
    </>
  )
}

/** A period of money by kind: its heading and the ranked bars. */
function Flows({ heading, period, side, testid }: { heading: string; period: StatsPeriod | null; side: string; testid: string }) {
  if (!period || period.flows.length === 0) return null
  const flows = side === ALL ? period.flows : period.flows.filter((f) => f.side === side)
  if (flows.length === 0) return null
  return (
    <div data-testid={testid}>
      <Hint className="px-2 pb-1 pt-3">
        {heading} · {formatInt(flows.length)}
      </Hint>
      <RankBars rows={flowRanks(flows)} format={formatDucatsDelta} />
    </div>
  )
}

function Waiting() {
  return (
    <Band data-testid="stats-waiting">
      <Skeleton className="h-64 w-full md:col-span-6 xl:col-span-4" />
      <Skeleton className="h-64 w-full md:col-span-6 xl:col-span-4" />
      <Skeleton className="h-64 w-full md:col-span-12 xl:col-span-4" />
    </Band>
  )
}
