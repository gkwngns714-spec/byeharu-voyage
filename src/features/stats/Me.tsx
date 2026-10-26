import {
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
  oneOf,
  useFilterChoice,
  type RankRow,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldBooks, worldStatsMe, type Books, type StatsMe } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import { useLiveRead } from './statsLive'
import { ALL, countriesOf } from './statsFilters'

// ME — your own week beside the world's: what you made (world.books, the same read the desk's Profit face
// prints — one authority for "what did I earn"), your best sales, and where you stand. The leaderboard is
// RANK AND NAME: the server sends no other company's purse, by the owner's default.
//
// THE SEVEN BARS are the desk's own (`SignedBars`): one a game day, up for a gain and down for a loss. The
// same picture in both places, because it is the same question.
//
// EVERY SECOND (0232, owner row 213): both reads are computed from the record at the moment they are asked, and
// are asked again every second while the face is open.

const DAYS = 7
const SALE_SORTS = ['profit', 'newest', 'total'] as const

export function MeFace() {
  const t = useT()
  const me = useLiveRead<StatsMe>('stats:me', () => worldStatsMe())
  const books = useLiveRead<Books>('stats:books', () => worldBooks(DAYS))
  const nationByCode = useWorld((s) => s.nationByCode)
  const { nowMs } = useShellState()
  // 0244 (owner row 228): best sales sorted by profit, newest or size; the board filtered by country (ranks kept)
  const [choice, choose] = useFilterChoice('stats.me', { sales: 'profit', country: ALL })
  const v = me.view
  const b = books.view

  if ((me.loading && !v) || (books.loading && !b)) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.meFailed')}</Note>

  const perDay = b ? Math.round(b.window / Math.max(1, b.days)) : null
  // oldest → newest across the bar row, a day with nothing in it standing at zero (Profit's rule)
  const byDay = new Map((b?.books ?? []).map((d) => [d.game_day, d.net]))
  const bars =
    b === null
      ? []
      : Array.from({ length: b.days }, (_, i) => b.game_day - b.days + 1 + i).map((day) => ({
          id: String(day),
          value: byDay.get(day) ?? 0,
        }))
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

  return (
    <div data-testid="stats-me">
      <SheetSection heading={t('stats.yourWeek')}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell
            label={t('stats.todayLabel')}
            value={b?.today ?? 0}
            format={formatDucatsDelta}
            text={b === null ? '—' : undefined}
            tone={(b?.today ?? 0) >= 0 ? 'success' : 'danger'}
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

      <SheetSection heading={t('stats.bestSales')} surface data-testid="stats-best-trades">
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
      </SheetSection>

      <SheetSection
        heading={t('stats.captainsByPurse')}
        trailing={<span className="text-t-caption text-ink-faint">{v.leaderboard.you === null ? '' : t('stats.youAre', { rank: formatInt(v.leaderboard.you), of: formatInt(v.leaderboard.players) })}</span>}
        surface
        data-testid="stats-leaderboard"
      >
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
      </SheetSection>
    </div>
  )
}
