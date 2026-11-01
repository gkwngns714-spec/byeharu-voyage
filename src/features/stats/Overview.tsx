import { useState } from 'react'
import {
  Empty,
  FilterBar,
  Figure,
  Hint,
  ListPanel,
  Note,
  RankBars,
  Segmented,
  SignedBars,
  Skeleton,
  StackedBar,
  StatCell,
  StatRun,
  deltaTone,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsOverview, type StatsHolders, type StatsNow, type StatsOverview, type StatsPeriod } from '../../lib/rpc'
import { STATS_BARS, flowRanks, toSeries, trendOf } from './statsFaces'
import { MoneyLogControls, MoneyRows } from './MoneyLog'
import { loadMoveFilter, saveMoveFilter, sliceMoves, useMoneyFeed, type MoveFilter } from './moneyFeed'
import { useLiveRead } from './statsLive'
import { Block } from './StatsBlock'
import { StatsChart } from './StatsChart'
import { useChartSpan } from '../../store/chartSpan'
import { ALL } from './statsFilters'
import { WatchSection } from './Watch'

// OVERVIEW — the world's money, ALL ON THE FACE (owner, 2026-11-01, row 260: *"everything is folded in stats this
// is soo wrong. make it compact showing everything possible."*). It was five summary rows and 21 pages behind
// them. It is now three blocks of figures, each with its small chart beside or under it, over ONE list panel:
//
//   WHO HOLDS IT   one stacked bar, the four holders' figures with their trend beside each, the purse line
//   MONEY FLOWS    printed, burned, moved, trades; the net of each count, what was sold to and bought from cities
//   ECONOMY WATCH  the seven figures the closed economy is judged by (Watch.tsx)
//   THE PANEL      the money log (every move, as it happens) — or the day's money by kind
//
// What moved, and where (docs/dev-log/2026-11-01-unfold-stats.md §1): the old hero figure is the band's
// `World money` (one home), its "today" is the Money flows figure; the per-holder share bars are the stacked
// bar. Nothing else left the face. Every read is exactly what it was — asked every second (statsLive.ts).

const HOURS = 24
type View = 'moves' | 'kinds'

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

  const above = (
    <>
      <Block
        title={t('stats.byHolder')}
        aside={
          <StatsChart
            look="line"
            title={t('stats.purseSeries')}
            points={totals}
            format={formatDucats}
            label={t('stats.purseSeries')}
            tone="accent"
          />
        }
        data-testid="stats-money"
      >
        <StackedBar parts={holders} format={formatDucats} label={t('stats.byHolder')} legend={false} />
        <div className="mt-1 grid grid-cols-[repeat(auto-fit,minmax(9.5rem,1fr))] gap-x-4 gap-y-1">
          {holders.map((x) => (
            <StatCell
              key={x.id}
              label={x.label}
              value={x.value}
              format={formatDucats}
              size="body"
              trend={trendOf(v.series, (p) => p[x.id as 'players' | 'merchants' | 'cities' | 'set_aside'])}
              trendBeside
              data-testid="stats-holder"
            />
          ))}
        </div>
      </Block>

      <Block
        title={t('stats.newMoney')}
        figure={<Figure value={formatDucatsDelta(newMoney ?? 0)} tone={deltaTone(newMoney ?? 0)} />}
        data-testid="stats-new-money"
      >
        <StatRun>
          <StatCell inline label={t('stats.printed')} value={day?.minted ?? 0} format={formatDucatsDelta} size="body" tone="success" />
          <StatCell inline label={t('stats.burned')} value={-(day?.removed ?? 0)} format={formatDucatsDelta} size="body" tone="danger" />
          <StatCell inline label={t('stats.moved')} value={day?.moved ?? 0} format={formatDucats} size="body" />
          <StatCell inline label={t('stats.trades')} value={day?.trades ?? 0} format={formatInt} size="body" />
        </StatRun>
        <div className="mt-1 grid grid-cols-3 gap-x-3">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">{t('stats.netShort')}</span>
            <SignedBars
              bars={v.series.slice(-STATS_BARS).map((p) => ({ id: p.at, value: p.minted - p.removed }))}
              label={t('stats.netBars')}
              height="h-7 lg:h-10"
              className="mt-1"
            />
          </div>
          <StatsChart
            title={t('stats.soldCities')}
            points={toSeries(v.series, (p) => p.sold)}
            format={formatDucats}
            label={t('stats.soldSeries')}
            tone="info"
          />
          <StatsChart
            title={t('stats.boughtCities')}
            points={toSeries(v.series, (p) => p.bought)}
            format={formatDucats}
            label={t('stats.boughtSeries')}
            tone="accent"
          />
        </div>
      </Block>

      <WatchSection watch={live?.watch} />
    </>
  )

  return (
    <ListPanel
      above={above}
      face={{ 'data-testid': 'stats-overview', 'data-span': v.span ?? '' }}
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
      data-testid={view === 'moves' ? 'money-log' : 'stats-flows'}
    >
      {view === 'moves' ? (
        feed.view === null ? (
          feed.loading ? <Skeleton className="my-1 h-10 w-full" /> : <Empty className="my-1">{t('feed.none')}</Empty>
        ) : (
          <MoneyRows rows={moves?.rows ?? []} />
        )
      ) : (
        <Kinds day={day} period={v.period} side={side} />
      )}
    </ListPanel>
  )
}

const SIDES = [ALL, 'minted', 'removed', 'moved'] as const

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
      <Hint className="pt-1">
        {heading} · {formatInt(flows.length)}
      </Hint>
      <RankBars rows={flowRanks(flows)} format={formatDucatsDelta} />
    </div>
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
