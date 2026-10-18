import { Figure, Note, SheetSection, Skeleton } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { formatDucatsDelta } from '../../../lib/format'
import { worldBooks, type Books } from '../../../lib/rpc'

// PROFIT — the running total (docs/COMMAND_DESK.md §3.8, D7). The owner, 2026-10-17: *"… for max profit"*.
//
// THE BOOKS ARE world.books (0177): the ledger — the record every coin moves through — summed by game day and kind,
// each kind under the server's one word, each day's net the sum of its lines. The head is today's net and the
// window's; seven bars, one a day, green or red by sign, the zero line their only axis; then each day's lines. The
// bars' heights are the served nets scaled to the tallest — presentation, not arithmetic about money.

const DAYS = 7

export function Profit() {
  const read = useServedRead<Books>('books:7', () => worldBooks(DAYS))
  const b = read.view

  if (read.loading && !b) {
    return (
      <div data-testid="desk-profit">
        <Skeleton className="h-[72px] w-full" />
        <Skeleton className="mt-3 h-[96px] w-full" />
      </div>
    )
  }
  if (!b) return <Note tone="danger">The books could not be read.</Note>

  // oldest → newest across the bar row, a day with nothing in it standing at zero
  const byDay = new Map(b.books.map((d) => [d.game_day, d.net]))
  const bars = Array.from({ length: b.days }, (_, i) => b.game_day - b.days + 1 + i).map((day) => ({
    day,
    net: byDay.get(day) ?? 0,
  }))
  const top = Math.max(1, ...bars.map((x) => Math.abs(x.net)))

  return (
    <div data-testid="desk-profit">
      <div className="grid grid-cols-2 gap-4">
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">Today</span>
          <Figure value={formatDucatsDelta(b.today)} tone={b.today > 0 ? 'success' : b.today < 0 ? 'danger' : 'muted'} size="hero" />
        </div>
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">{b.days} days</span>
          <Figure value={formatDucatsDelta(b.window)} tone={b.window > 0 ? 'success' : b.window < 0 ? 'danger' : 'muted'} size="figure" />
        </div>
      </div>

      {/* SEVEN BARS — one a game day, up for a gain and down for a loss from the one zero line */}
      <div className="mt-4 grid h-24 grid-cols-7 gap-2" role="img" aria-label="Net by day, the last seven days" data-testid="profit-bars">
        {bars.map((x) => (
          <div key={x.day} className="relative h-full">
            <div className="absolute inset-x-0 top-1/2 h-px bg-edge" />
            {x.net !== 0 && (
              <div
                className={`absolute inset-x-0 rounded-t-[3px] ${x.net > 0 ? 'bottom-1/2 bg-success' : 'top-1/2 bg-danger'}`}
                style={{ height: `${(Math.abs(x.net) / top) * 50}%` }}
              />
            )}
          </div>
        ))}
      </div>

      {b.books.length === 0 ? (
        <Note tone="neutral" className="mt-4">
          Nothing earned or spent in the last {b.days} days.
        </Note>
      ) : (
        b.books.map((d, i) => (
          <SheetSection
            key={d.game_day}
            heading={i === 0 && d.game_day === b.game_day ? 'Today' : `${b.game_day - d.game_day} ${b.game_day - d.game_day === 1 ? 'day' : 'days'} ago`}
            trailing={
              <Figure value={formatDucatsDelta(d.net)} tone={d.net > 0 ? 'success' : d.net < 0 ? 'danger' : 'muted'} />
            }
            data-testid="profit-day"
          >
            {d.lines.map((l) => (
              <div key={l.kind} className="flex min-h-11 items-center justify-between gap-3 border-b border-edge py-1">
                <span className="min-w-0 truncate text-t-body text-ink">{l.word}</span>
                <span className={`whitespace-nowrap text-t-body tabular-nums ${l.ducats >= 0 ? 'text-success' : 'text-ink-muted'}`}>
                  {formatDucatsDelta(l.ducats)}
                </span>
              </div>
            ))}
          </SheetSection>
        ))
      )}
    </div>
  )
}
