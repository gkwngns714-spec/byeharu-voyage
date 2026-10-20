import { useEffect } from 'react'
import { Figure, Flag, Hint, Note, Row, SheetSection, Skeleton, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { worldBooks, worldStatsMe, type Books, type StatsMe } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FaceProps } from './StatsScreen'

// ME — your own week beside the world's: what you made (world.books, the same read the desk's Profit face
// prints — one authority for "what did I earn"), your best sales, and where you stand. The leaderboard is
// RANK AND NAME: the server sends no other company's purse, by the owner's default.

const DAYS = 7

export function MeFace({ beat, onAge }: FaceProps) {
  const me = useServedRead<StatsMe>('stats:me', () => worldStatsMe(), { trigger: beat })
  const books = useServedRead<Books>('stats:books', () => worldBooks(DAYS), { trigger: beat })
  const nationByCode = useWorld((s) => s.nationByCode)
  const { nowMs } = useShellState()
  useEffect(() => onAge(null), [onAge])
  const v = me.view
  const b = books.view

  if ((me.loading && !v) || (books.loading && !b)) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">Your figures could not be read.</Note>

  const perDay = b ? Math.round(b.window / Math.max(1, b.days)) : null

  return (
    <div data-testid="stats-me">
      <SheetSection heading="Your week">
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Today</span>
            <Figure value={b ? formatDucatsDelta(b.today) : '—'} size="figure" tone={b ? deltaTone(b.today) : 'faint'} />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">A day, on average</span>
            <Figure value={perDay === null ? '—' : formatDucatsDelta(perDay)} size="figure" tone={perDay === null ? 'faint' : deltaTone(perDay)} />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Sold, 7 days</span>
            <Figure value={formatDucats(v.sold_7d)} size="figure" />
          </div>
          <div className="min-w-0">
            <span className="block text-t-caption text-ink-faint">Bought, 7 days</span>
            <Figure value={formatDucats(v.bought_7d)} size="figure" />
          </div>
        </div>
        <Hint className="mt-2">{`${formatInt(v.trades_7d)} trades in the last 7 days. The day figures are game days, from your books.`}</Hint>
      </SheetSection>

      <SheetSection heading="Your best sales, 7 days" surface data-testid="stats-best-trades">
        {v.best_trades.length === 0 ? (
          <Row label="No sales yet. Sell something and it shows here." tone="muted" hairline={false} />
        ) : (
          v.best_trades.map((t, i) => (
            <Row
              key={`${t.at}-${t.good}`}
              label={`${t.good} · ${formatInt(t.qty)} units`}
              value={<Figure value={formatDucatsDelta(t.profit)} tone={deltaTone(t.profit)} />}
              hairline={i < v.best_trades.length - 1}
            >
              <span className="block text-t-caption text-ink-faint">{`${t.fleet} · ${formatDucats(t.total)} · ${formatRelative(Date.parse(t.at), nowMs)}`}</span>
            </Row>
          ))
        )}
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
            mark={<span className="w-6 text-right text-t-caption tabular-nums text-ink-faint">{r.rank}</span>}
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
