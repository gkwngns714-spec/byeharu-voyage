import { useState } from 'react'
import { DetailPage, Figure, Note, Row, SignedBars, Skeleton, SummaryRow } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { formatDucatsDelta } from '../../../lib/format'
import { worldBooks, type Books } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'
import { useT, t as tNow } from '../../../lib/i18n'

// PROFIT — the running total (D7). THE COMPACT SCREEN (owner, 2026-10-31): today and the window
// stand with the seven bars; each day is one summary row with its net, opening the day's own page
// with every line whole. Nothing unfolds in place.

const DAYS = 7
const hint = () => tNow('desk.profitHint')

export function Profit({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const read = useServedRead<Books>('books:7', () => worldBooks(DAYS), { name: 'worldBooks' })
  const b = read.view
  const [day, setDay] = useState<number | null>(null)

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

  const byDay = new Map(b.books.map((d) => [d.game_day, d.net]))
  const bars = Array.from({ length: b.days }, (_, i) => b.game_day - b.days + 1 + i).map((g) => ({
    day: g,
    net: byDay.get(g) ?? 0,
  }))
  const open = b.books.find((d) => d.game_day === day) ?? null
  const titleOf = (d: { game_day: number }) =>
    d.game_day === b.game_day ? t('desk.today') : t('desk.daysAgo', { n: b.game_day - d.game_day })

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
        <SignedBars bars={bars.map((x) => ({ id: String(x.day), value: x.net }))} label={t('desk.netByDay')} className="mt-4" data-testid="profit-bars" />
      </>
    ),
    main: (
      <div className="mt-2 flex flex-col gap-2">
        {b.books.length === 0 ? (
          <Note tone="neutral" className="mt-4 lg:mt-0">
            {t('desk.nothingEarned', { n: b.days })}
          </Note>
        ) : (
          b.books.map((d) => (
            <SummaryRow
              key={d.game_day}
              title={titleOf(d)}
              figure={<Figure value={formatDucatsDelta(d.net)} tone={d.net > 0 ? 'success' : d.net < 0 ? 'danger' : 'muted'} />}
              word={t('common.open')}
              onClick={() => setDay(d.game_day)}
              data-testid="profit-day"
            />
          ))
        )}
        {open !== null && (
          <DetailPage
            title={titleOf(open)}
            figure={<Figure value={formatDucatsDelta(open.net)} tone={open.net > 0 ? 'success' : open.net < 0 ? 'danger' : 'muted'} />}
            onClose={() => setDay(null)}
            data-testid="profit-day-page"
          >
            {open.lines.map((l) => (
              <Row
                key={l.kind}
                label={<span className="text-t-body text-ink">{l.word}</span>}
                value={<Figure value={formatDucatsDelta(l.ducats)} tone={l.ducats >= 0 ? 'success' : 'muted'} />}
              />
            ))}
          </DetailPage>
        )}
      </div>
    ),
  })
}
