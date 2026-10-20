import { useEffect } from 'react'
import {
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
  type RankRow,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { worldBooks, worldStatsMe, type Books, type StatsMe } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FaceProps } from './StatsScreen'

// ME — your own week beside the world's: what you made (world.books, the same read the desk's Profit face
// prints — one authority for "what did I earn"), your best sales, and where you stand. The leaderboard is
// RANK AND NAME: the server sends no other company's purse, by the owner's default.
//
// THE SEVEN BARS are the desk's own (`SignedBars`): one a game day, up for a gain and down for a loss. The
// same picture in both places, because it is the same question.

const DAYS = 7

export function MeFace({ beat, onServed }: FaceProps) {
  const me = useServedRead<StatsMe>('stats:me', () => worldStatsMe(), { trigger: beat })
  const books = useServedRead<Books>('stats:books', () => worldBooks(DAYS), { trigger: beat })
  const nationByCode = useWorld((s) => s.nationByCode)
  const { nowMs } = useShellState()
  // `stats_me` is your own ledger and your rank, not a count of the world: it carries no age to report.
  useEffect(() => onServed(null), [onServed])
  const v = me.view
  const b = books.view

  if ((me.loading && !v) || (books.loading && !b)) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">Your figures could not be read.</Note>

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
  const sales: RankRow[] = v.best_trades.map((t) => ({
    id: `${t.at}-${t.good}`,
    label: `${t.good} · ${formatInt(t.qty)} units`,
    value: t.profit,
    tone: t.profit >= 0 ? ('success' as const) : ('danger' as const),
    note: `${t.fleet} · ${formatDucats(t.total)} · ${formatRelative(Date.parse(t.at), nowMs)}`,
  }))

  return (
    <div data-testid="stats-me">
      <SheetSection heading="Your week">
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell
            label="Today"
            value={b?.today ?? 0}
            format={formatDucatsDelta}
            text={b === null ? '—' : undefined}
            tone={(b?.today ?? 0) >= 0 ? 'success' : 'danger'}
            size="hero"
          />
          <StatCell
            label="A day, on average"
            value={perDay ?? 0}
            format={formatDucatsDelta}
            text={perDay === null ? '—' : undefined}
            size="body"
            tone={(perDay ?? 0) >= 0 ? 'success' : 'danger'}
          />
          <StatCell label="Sold, 7 days" value={v.sold_7d} format={formatDucats} size="body" />
          <StatCell label="Bought, 7 days" value={v.bought_7d} format={formatDucats} size="body" />
        </div>
        <SignedBars bars={bars} label={`What you earned each of the last ${formatInt(DAYS)} days`} className="mt-4" data-testid="stats-me-bars" />
        <Hint className="mt-2">{`${formatInt(v.trades_7d)} trades in the last 7 days. One bar a game day, from your books.`}</Hint>
      </SheetSection>

      <SheetSection heading="Your best sales, 7 days" surface data-testid="stats-best-trades">
        <RankBars rows={sales} format={formatDucatsDelta} empty="No sales yet. Sell something and it shows here." />
      </SheetSection>

      <SheetSection
        heading="Captains, by purse"
        trailing={<span className="text-t-caption text-ink-faint">{v.leaderboard.you === null ? '' : `you are ${formatInt(v.leaderboard.you)} of ${formatInt(v.leaderboard.players)}`}</span>}
        surface
        data-testid="stats-leaderboard"
      >
        {v.leaderboard.board.map((r, i) => (
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
            hairline={i < v.leaderboard.board.length - 1}
            data-testid={r.is_you ? 'stats-leaderboard-you' : undefined}
          />
        ))}
      </SheetSection>
    </div>
  )
}
