import type { ComponentType } from 'react'
import { Card, FactsLine, Hint, Segmented, SeriesChart, wholePeriods, Skeleton } from '../components/ui'
import { formatPriceFigure, instantMs } from '../lib/format'
import { useT } from '../lib/i18n'
import { serverNow } from '../lib/serverClock'
import { HISTORY_PERIODS, worldHistory, type HistoryGoodPoint, type HistoryPeriod, type HistoryWhat } from '../lib/rpc'
import { useHistoryPeriod } from '../store/historyPeriod'
import type { HistoryLine } from './historyLines'
import { useLiveRead } from './liveRead'

// A RECORD BY DAY, WEEK OR MONTH (0316, owner row 289, 2026-11-05: *"the market data, as well as gold earned data / loss graphs record. i want to be able to see them by days,
// weeks, months"*). ONE card for every such record: Stats (the world, a city, a good, a company, you) and the Report.
//
// ONE READ: world.history, through the one `useLiveRead`; a week and a month are the server's, the client groups nothing. ONE PICKER: Day · Week · Month in the card's title line,
// one period for every record (`useHistoryPeriod`). The period is the read's `refresh`, so a press asks at once and the old line stays until the answer lands.
//
// A PRESS MOVES NOTHING (the owner's UI law, tests/history.periods.spec.ts): every line stands in a box of a fixed height, drawn or not; the picker is three cells that wrap with the
// title, never scroll. Small multiples, one figure a line, as Stats always draws them: `SeriesChart`, no second chart system.

const LINE_H = 120

/** The newest period's open, high, low and close, always one line tall: a good's price is a line on the chart and four figures here. */
export function GoodPrices({ last }: { last: HistoryGoodPoint | undefined }) {
  const t = useT()
  const figure = (v: number | null | undefined) => (v === undefined || v === null ? '—' : formatPriceFigure(v))
  return (
    <FactsLine className="mt-3" data-testid="history-good-prices">
      <span>{t('stats.histOpen')} {figure(last?.open)}</span>
      <span>{t('stats.histHigh')} {figure(last?.high)}</span>
      <span>{t('stats.histLow')} {figure(last?.low)}</span>
      <span>{t('stats.histClose')} {figure(last?.close)}</span>
    </FactsLine>
  )
}

export function HistoryChart<P extends { at: string }>({
  what,
  subject = null,
  title,
  lines,
  under: Under,
  className = '',
  'data-testid': testid,
}: {
  what: HistoryWhat
  subject?: string | null
  title: string
  lines: readonly HistoryLine<P>[]
  /** Drawn under the lines, with the newest period. */
  under?: ComponentType<{ last: P | undefined }>
  className?: string
  'data-testid': string
}) {
  const t = useT()
  const { period, setPeriod } = useHistoryPeriod()
  const read = useLiveRead(`history:${what}:${subject ?? ''}`, () => worldHistory<P>(what, subject, period), period, what !== 'me')
  const word: Record<HistoryPeriod, string> = { day: t('stats.periodDay'), week: t('stats.periodWeek'), month: t('stats.periodMonth') }
  const points = read.view?.points ?? []
  return (
    <Card
      title={title}
      aside={
        <Segmented<HistoryPeriod>
          segments={HISTORY_PERIODS.map((p) => ({ id: p, label: word[p] }))}
          value={period}
          onChange={setPeriod}
          label={t('stats.historyPeriod')}
          columns={3}
        />
      }
      className={className}
      data-testid={testid}
      data-period={read.view?.period ?? ''}
    >
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {lines.map((line) => {
          const every = points.flatMap((p) => {
            const value = line.pick(p)
            const atMs = instantMs(p.at)
            return value === null || atMs === null ? [] : [{ atMs, value }]
          })
          // a SUM's open period is not drawn beside whole ones (it plunges at the right edge): the one rule of every sum, the figures reaching now; a level's newest reading is true
          const drawn = line.flow ? wholePeriods(every, read.view?.period ?? period, serverNow()) : every
          const newest = drawn.at(-1)
          return (
            <div key={line.id} className="min-w-0" data-testid="history-line" data-line={line.id} data-points={drawn.length}>
              <div className="flex min-h-5 items-baseline justify-between gap-2 text-t-caption">
                <span className="min-w-0 break-words text-ink-faint">{line.label}</span>
                {newest !== undefined && <span className="shrink-0 text-ink">{line.format(newest.value)}</span>}
              </div>
              <div className="mt-1" style={{ height: LINE_H }}>
                {read.loading && read.view === null ? (
                  <Skeleton className="h-full w-full" />
                ) : (
                  <SeriesChart
                    points={drawn}
                    format={line.format}
                    label={`${title}: ${line.label}`}
                    tone={line.tone}
                    height={LINE_H}
                    empty={<Hint>{t('stats.lineSoon')}</Hint>}
                  />
                )}
              </div>
            </div>
          )
        })}
      </div>
      {Under && <Under last={points.at(-1)} />}
    </Card>
  )
}
