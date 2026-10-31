import { useState } from 'react'
import { Figure, Note, Row, Skeleton } from '../components/ui'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'
import { ok, worldCityHistory } from '../lib/rpc'
import type { CityHistoryView, Refusal, SnapshotPort } from '../lib/rpc'
import { formatDate, formatDucats } from '../lib/format'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY'S HISTORY — the sixth tab (owner row 173; 0278, the month)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"There will be a history tab where you can see the last week's investment records
// when pressing a city."* (0278 re-cut the period to the calendar month.)
//
// ONE READ, `world.city_history(port, 8)` (0278): the current month and the past eight, newest
// first, each with its starts / ends / total and its givers {name, merchant, invested, donated,
// total}. The month is a KEY on the server — nothing is deleted, the board sums every month and
// this tab reads them one by one. Nothing here computes a month, a date or a sum: month, starts,
// ends and totals are SERVED; the fold's own open state is chrome, never a figure.
//
// THE FOLD RULE: one fold per month, the current month open, the others closed. Pressing a month's
// row SELECTS it — the row and everything above stay where they are, and what is below moves down
// (the same fold rule the route fold keeps). A month with no giving reads one muted line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The served answer or the served refusal, folded into one value (useTownHall's shape). */
interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

export function CityHistory({ port }: { port: SnapshotPort }) {
  const t = useT()
  const house = useWorld((s) => s.player?.company_name ?? null)
  const read = useServedRead<Served<CityHistoryView>>(port.kind === 'HARBOUR' ? `history:${port.id}` : null, async () => {
    const r = await worldCityHistory(port.id, 8)
    return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
  }, { name: 'worldCityHistory' })
  // WHICH month stands open — DERIVED, never set in an effect: the current month until a press
  // picks another (or folds all); a different city's answer resets to its own current month,
  // because the pick carries the subject it was made for. Chrome, never a figure.
  const [pick, setPick] = useState<{ subject: string; month: number | null } | null>(null)
  const view = read.view?.view ?? null
  const subject = port.kind === 'HARBOUR' ? `history:${port.id}` : null
  const openMonth = view !== null && (!pick || pick.subject !== subject) ? view.month : (pick?.month ?? null)

  if (port.kind !== 'HARBOUR') return <Note tone="neutral">{t('town.noHall')}</Note>
  if (!view) {
    return read.view?.refusal ? (
      <Note tone="danger" code={read.view.refusal.code} figures={read.view.refusal.figures}>
        {read.view.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="mt-3 h-28 w-full" />
    )
  }

  return (
    <div data-testid="map-city-history">
      {view.months.map((w) => {
        const isOpen = openMonth === w.month
        const label = w.current
          ? t('town.thisMonth')
          : w.month === view.month - 1
            ? t('town.lastMonth')
            : t('town.monthOf', { date: formatDate(Date.parse(w.starts), { month: 'long', year: 'numeric', timeZone: 'UTC' }) })
        return (
          <div key={w.month} data-testid="city-history-month">
            <Row
              label={label}
              value={<Figure value={t('town.monthTotal', { amount: formatDucats(w.total) })} />}
              chevron
              tone={isOpen ? 'accent' : 'default'}
              onClick={() => setPick({ subject: subject as string, month: isOpen ? null : w.month })}
            />
            {isOpen && (
              <div className="pb-2">
                {w.investors.length === 0 ? (
                  <Row
                    label={w.current ? t('town.monthNobody') : t('town.monthNobodyPast')}
                    tone="muted"
                    hairline={false}
                    data-testid="city-history-nobody"
                  />
                ) : (
                  w.investors.map((x, i) => (
                    <Row
                      key={`${x.name}:${i}`}
                      label={
                        <span>
                          {x.name}
                          {x.name === house ? ` (${t('town.youMark')})` : ''}
                          <span className="block text-t-caption text-ink-muted">
                            {`${x.merchant ? `${t('town.merchantWord')} · ` : ''}${t('town.invested')} ${formatDucats(x.invested)} · ${t('town.donated')} ${formatDucats(x.donated)}`}
                          </span>
                        </span>
                      }
                      value={<Figure value={formatDucats(x.total)} />}
                      hairline={false}
                      data-testid="city-history-investor"
                    />
                  ))
                )}
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
