import { Figure, Note, SheetSection, Skeleton } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { formatDucatsDelta } from '../../../lib/format'
import { worldBooks, type Books } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'
import { useT, t as tNow } from '../../../lib/i18n'

// PROFIT — the running total (docs/COMMAND_DESK.md §3.8, D7). The owner, 2026-10-17: *"… for max profit"*.
//
// THE BOOKS ARE world.books (0177): the ledger — the record every coin moves through — summed by game day and kind,
// each kind under the server's one word, each day's net the sum of its lines. The head is today's net and the
// window's; seven bars, one a day, green or red by sign, the zero line their only axis; then each day's lines. The
// bars' heights are the served nets scaled to the tallest — presentation, not arithmetic about money.

//
// THE DESK LAYS IT OUT (DeskFrame.tsx, 2026-10-19): on a wide glass the head and the bars stand in the left
// pane and the day-by-day books in the centre; on a phone, one under the other.

const DAYS = 7
const hint = () => tNow('desk.profitHint')

export function Profit({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const read = useServedRead<Books>('books:7', () => worldBooks(DAYS))
  const b = read.view

  if (read.loading && !b) {
    return layout({
      testid: 'desk-profit',
      sideHint: hint(),
      list: (
        <>
          <Skeleton className="h-[72px] w-full" />
          <Skeleton className="mt-3 h-[96px] w-full" />
        </>
      ),
      main: null,
    })
  }
  if (!b) return layout({ testid: 'desk-profit', list: <Note tone="danger">{t('desk.booksFailed')}</Note>, main: null })

  // oldest → newest across the bar row, a day with nothing in it standing at zero
  const byDay = new Map(b.books.map((d) => [d.game_day, d.net]))
  const bars = Array.from({ length: b.days }, (_, i) => b.game_day - b.days + 1 + i).map((day) => ({
    day,
    net: byDay.get(day) ?? 0,
  }))
  const top = Math.max(1, ...bars.map((x) => Math.abs(x.net)))

  return layout({
    testid: 'desk-profit',
    sideHint: hint(),
    list: (
    <>
      <div className="grid grid-cols-2 gap-4">
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">{t('desk.today')}</span>
          <Figure value={formatDucatsDelta(b.today)} tone={b.today > 0 ? 'success' : b.today < 0 ? 'danger' : 'muted'} size="hero" />
        </div>
        <div className="min-w-0">
          <span className="block text-t-caption text-ink-faint">{t('desk.nDays', { n: b.days })}</span>
          <Figure value={formatDucatsDelta(b.window)} tone={b.window > 0 ? 'success' : b.window < 0 ? 'danger' : 'muted'} size="figure" />
        </div>
      </div>

      {/* SEVEN BARS — one a game day, up for a gain and down for a loss from the one zero line */}
      <div className="mt-4 grid h-24 grid-cols-7 gap-2" role="img" aria-label={t('desk.netByDay')} data-testid="profit-bars">
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
    </>
    ),
    main:
      b.books.length === 0 ? (
        <Note tone="neutral" className="mt-4 lg:mt-0">
          {t('desk.nothingEarned', { n: b.days })}
        </Note>
      ) : (
        b.books.map((d, i) => (
          <SheetSection
            key={d.game_day}
            heading={i === 0 && d.game_day === b.game_day ? t('desk.today') : t('desk.daysAgo', { n: b.game_day - d.game_day })}
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
      ),
  })
}
