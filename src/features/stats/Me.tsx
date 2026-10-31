import { useState } from 'react'
import {
  DetailPage,
  Empty,
  FilterBar,
  Figure,
  Flag,
  Hint,
  Note,
  RankBars,
  Row,
  SheetSection,
  SignedBars,
  Skeleton,
  StatCell,
  SummaryRow,
  oneOf,
  useFilterChoice,
  type RankRow,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldReport, worldStatsMe, type Report, type StatsMe } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import { useLiveRead } from './statsLive'
import { ALL, countriesOf } from './statsFilters'

// ME — your own week beside the world's. THE COMPACT SCREEN (owner, 2026-10-31): the week's four
// figures and bars stand; the best sales and the captains' board are summary rows, each opening its
// own full-screen page with its filter and list whole.
//
// WHAT YOU MADE is world.report('week') — the same read the desk's Report face prints (one authority
// for "what did I earn"). Its day axis arrives zero-filled, so the bars are the served days.
// EVERY SECOND (0232, owner row 213): both reads are computed from the record at the moment they are
// asked, and are asked again every second while the face is open.

const DAYS = 7
const SALE_SORTS = ['profit', 'newest', 'total'] as const
type Page = 'sales' | 'board' | null

export function MeFace() {
  const t = useT()
  const me = useLiveRead<StatsMe>('stats:me', () => worldStatsMe())
  const books = useLiveRead<Report>('stats:report', () => worldReport('week'))
  const nationByCode = useWorld((s) => s.nationByCode)
  const { nowMs } = useShellState()
  const [choice, choose] = useFilterChoice('stats.me', { sales: 'profit', country: ALL })
  const [page, setPage] = useState<Page>(null)
  const v = me.view
  const b = books.view

  if ((me.loading && !v) || (books.loading && !b)) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.meFailed')}</Note>

  const perDay = b ? Math.round(b.total / Math.max(1, b.days.length)) : null
  // oldest → newest across the bar row: the report's day axis arrives zero-filled, so it IS the row.
  const today = b?.days.find((d) => d.game_day === b.game_day)?.net ?? 0
  const bars = (b?.days ?? []).map((d) => ({ id: String(d.game_day), value: d.net }))
  const saleSort = oneOf(choice.sales, SALE_SORTS, 'profit')
  const sorted = [...v.best_trades].sort((a, b) =>
    saleSort === 'newest' ? Date.parse(b.at) - Date.parse(a.at) : saleSort === 'total' ? b.total - a.total : b.profit - a.profit,
  )
  const countries = countriesOf(v.leaderboard.board.map((r) => r.nation))
    .map((code) => ({ id: code, label: nationNameOf(nationByCode, code) }))
    .sort((a, b) => a.label.localeCompare(b.label))
  const country = oneOf(choice.country, [ALL, ...countries.map((c) => c.id)], ALL)
  const board = country === ALL ? v.leaderboard.board : v.leaderboard.board.filter((r) => r.nation === country)
  const sales: RankRow[] = sorted.map((s) => ({
    id: `${s.at}-${s.good}`,
    label: t('stats.saleLabel', { good: s.good, n: formatInt(s.qty) }),
    value: s.profit,
    tone: s.profit >= 0 ? ('success' as const) : ('danger' as const),
    note: `${s.fleet} · ${formatDucats(s.total)} · ${formatRelative(Date.parse(s.at), nowMs)}`,
  }))
  const rankWord = v.leaderboard.you === null ? '' : t('stats.youAre', { rank: formatInt(v.leaderboard.you), of: formatInt(v.leaderboard.players) })

  return (
    <div data-testid="stats-me">
      <SheetSection heading={t('stats.yourWeek')}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell
            label={t('stats.todayLabel')}
            value={today}
            format={formatDucatsDelta}
            text={b === null ? '—' : undefined}
            tone={today >= 0 ? 'success' : 'danger'}
            size="hero"
          />
          <StatCell
            label={t('stats.dayAverage')}
            value={perDay ?? 0}
            format={formatDucatsDelta}
            text={perDay === null ? '—' : undefined}
            size="body"
            tone={(perDay ?? 0) >= 0 ? 'success' : 'danger'}
          />
          <StatCell label={t('stats.sold7')} value={v.sold_7d} format={formatDucats} size="body" />
          <StatCell label={t('stats.bought7')} value={v.bought_7d} format={formatDucats} size="body" />
        </div>
        <SignedBars bars={bars} label={t('stats.earnedEach', { n: formatInt(DAYS) })} className="mt-4" data-testid="stats-me-bars" />
        <Hint className="mt-2">{t('stats.trades7', { n: formatInt(v.trades_7d) })}</Hint>
      </SheetSection>

      <div className="mt-2 flex flex-col gap-2">
        <SummaryRow title={t('stats.bestSales')} figure={formatDucatsDelta(sorted[0]?.profit ?? 0)} word={t('common.open')} onClick={() => setPage('sales')} data-testid="stats-best-trades" />
        <SummaryRow title={t('stats.captainsByPurse')} figure={rankWord} word={t('common.open')} onClick={() => setPage('board')} data-testid="stats-leaderboard" />
      </div>

      {page === 'sales' && (
        <DetailPage title={t('stats.bestSales')} figure={formatDucatsDelta(sorted[0]?.profit ?? 0)} onClose={() => setPage(null)} data-testid="stats-best-trades-page">
          {/* THE WINDOW IS A FACT, SAID ONCE (the audit, 2026-10-31): it left the title when the
              title became two plain words, and it must not be lost from the reading. */}
          <Hint className="mb-2">{t('stats.wWeek')}</Hint>
          {v.best_trades.length > 1 && (
            <FilterBar
              className="mb-2"
              data-testid="stats-sales-filters"
              sort={{
                id: 'sales',
                label: t('stats.sortLabel'),
                options: SALE_SORTS.map((id) => ({ id, label: t(id === 'profit' ? 'stats.bestProfit' : id === 'newest' ? 'stats.newest' : 'stats.biggestSale') })),
                value: saleSort,
                onChange: (id) => choose({ sales: id }),
              }}
            />
          )}
          <RankBars rows={sales} format={formatDucatsDelta} empty={t('stats.noSales')} />
        </DetailPage>
      )}

      {page === 'board' && (
        <DetailPage title={t('stats.captainsByPurse')} figure={rankWord} onClose={() => setPage(null)} data-testid="stats-leaderboard-page">
          {countries.length > 1 && (
            <FilterBar
              className="mb-2"
              data-testid="stats-board-filters"
              picks={[
                {
                  id: 'country',
                  label: t('stats.country'),
                  options: [{ id: ALL, label: t('stats.allCountries') }, ...countries],
                  value: country,
                  onChange: (id) => choose({ country: id }),
                },
              ]}
            />
          )}
          {board.length === 0 && <Empty data-testid="stats-no-match">{t('stats.noMatch')}</Empty>}
          {board.map((r, i) => (
            <Row
              key={`${r.rank}-${r.name}`}
              mark={<Figure value={formatInt(r.rank)} tone={r.is_you ? 'accent' : 'faint'} className="w-6 justify-end" />}
              label={
                <span className="flex items-center gap-2">
                  {r.nation !== null && <Flag code={r.nation} name={nationNameOf(nationByCode, r.nation)} size="body" />}
                  <span>{r.name}</span>
                </span>
              }
              tone={r.is_you ? 'accent' : 'default'}
              hairline={i < board.length - 1}
              data-testid={r.is_you ? 'stats-leaderboard-you' : undefined}
            />
          ))}
        </DetailPage>
      )}
    </div>
  )
}
