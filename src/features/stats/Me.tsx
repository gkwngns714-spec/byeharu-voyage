import { Band, Card, FilterBar, Hint, ListPanel, Note, RankBars, SignedBars, Skeleton, StatCell, oneOf, useFilterChoice, type RankRow } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldReport, worldStatsMe, type Report, type StatsMe } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { useLiveRead } from './statsLive'

// ME — your own week beside the world's, ALL ON THE FACE (owner, 2026-11-01, row 260), in cards (2026-11-02, row 267). The
// week is one card — today, the day average, sold and bought, a bar a day — and the best sales are ONE list card beside it,
// with their sort in its header.
//
// THE CAPTAINS' BOARD LIVES ON RANK, AND ONLY THERE (owner, 2026-10-31: *"no info duplicate info
// needed"*). This face used to repeat the whole board — the same ranks, the same names, a second
// country filter — one tab away from the screen whose subject it is. Its read (world.stats_me's
// leaderboard) still arrives; nothing here prints it.
//
// WHAT YOU MADE is world.report('week') — the same read the desk's Report face prints (one authority
// for "what did I earn"). Its day axis arrives zero-filled, so the bars are the served days.
// EVERY SECOND (0232, owner row 213): both reads are computed from the record at the moment they are
// asked, and are asked again every second while the face is open.

const DAYS = 7
const SALE_SORTS = ['profit', 'newest', 'total'] as const

export function MeFace() {
  const t = useT()
  const me = useLiveRead<StatsMe>('stats:me', () => worldStatsMe())
  const books = useLiveRead<Report>('stats:report', () => worldReport('week'))
  const { nowMs } = useShellState()
  const [choice, choose] = useFilterChoice('stats.me', { sales: 'profit' })
  const v = me.view
  const b = books.view

  if ((me.loading && !v) || (books.loading && !b)) return <Skeleton className="h-64 w-full md:col-span-12" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger" className="md:col-span-12">{t('stats.meFailed')}</Note>

  const perDay = b ? Math.round(b.total / Math.max(1, b.days.length)) : null
  // oldest → newest across the bar row: the report's day axis arrives zero-filled, so it IS the row.
  const today = b?.days.find((d) => d.game_day === b.game_day)?.net ?? 0
  const bars = (b?.days ?? []).map((d) => ({ id: String(d.game_day), value: d.net }))
  const saleSort = oneOf(choice.sales, SALE_SORTS, 'profit')
  const sorted = [...v.best_trades].sort((a, b) =>
    saleSort === 'newest' ? Date.parse(b.at) - Date.parse(a.at) : saleSort === 'total' ? b.total - a.total : b.profit - a.profit,
  )
  const sales: RankRow[] = sorted.map((s) => ({
    id: `${s.at}-${s.good}`,
    label: t('stats.saleLabel', { good: s.good, n: formatInt(s.qty) }),
    value: s.profit,
    tone: s.profit >= 0 ? ('success' as const) : ('danger' as const),
    note: `${s.fleet} · ${formatDucats(s.total)} · ${formatRelative(Date.parse(s.at), nowMs)}`,
  }))

  return (
    <Band data-testid="stats-me">
      <Card title={t('stats.yourWeek')} span="third" data-testid="stats-me-week">
        <StatCell
          look="stacked"
          label={t('stats.todayLabel')}
          value={today}
          format={formatDucatsDelta}
          text={b === null ? '—' : undefined}
          tone={today >= 0 ? 'success' : 'danger'}
        />
        <div className="mt-3">
          <StatCell
            look="line"
            label={t('stats.dayAverage')}
            value={perDay ?? 0}
            format={formatDucatsDelta}
            text={perDay === null ? '—' : undefined}
            tone={(perDay ?? 0) >= 0 ? 'success' : 'danger'}
          />
          <StatCell look="line" label={t('stats.sold7')} value={v.sold_7d} format={formatDucats} />
          <StatCell look="line" label={t('stats.bought7')} value={v.bought_7d} format={formatDucats} />
        </div>
        <SignedBars bars={bars} label={t('stats.earnedEach', { n: formatInt(DAYS) })} height="h-24" className="mt-5" data-testid="stats-me-bars" />
        <Hint className="mt-3">{t('stats.trades7', { n: formatInt(v.trades_7d) })}</Hint>
      </Card>

      <ListPanel
        look="card"
        span="zone"
        columns="fit"
        title={t('stats.bestSales')}
        count={formatInt(sales.length)}
        trailing={
          v.best_trades.length > 1 ? (
            <FilterBar
              compact
              data-testid="stats-sales-filters"
              sort={{
                id: 'sales',
                label: t('stats.sortLabel'),
                options: SALE_SORTS.map((id) => ({ id, label: t(id === 'profit' ? 'stats.bestProfit' : id === 'newest' ? 'stats.newest' : 'stats.biggestSale') })),
                value: saleSort,
                onChange: (id) => choose({ sales: id }),
              }}
            />
          ) : undefined
        }
        data-testid="stats-best-trades"
      >
        {/* THE WINDOW IS A FACT, SAID ONCE (the audit, 2026-10-31): it left the title when the title became
            two plain words, and it must not be lost from the reading. */}
        <Hint className="px-2 pb-1 pt-1 md:col-span-full">{t('stats.wWeek')}</Hint>
        <RankBars rows={sales} format={formatDucatsDelta} empty={t('stats.noSales')} className="contents" />
      </ListPanel>
    </Band>
  )
}
