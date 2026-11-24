import { FilterBar, PAGE_GAP, Hint, ListPanel, Note, RankBars, Skeleton, oneOf, useFilterChoice, type RankRow } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatRelative } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsMe, type StatsMe } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { useLiveRead } from '../../live/liveRead'
import { HistoryChart } from '../../live/HistoryChart'
import { companyLines } from '../../live/historyLines'

// ME — what only you have: your money record and your best sales (owner, 2026-11-01, row 260; 2026-11-02, row 267).
//
// THE PROFIT IS REPORT'S, AND ONLY THERE (2026-11-24, docs/design/simplify-2026-11-24.md S8). This face used to print a "My week" card
// (Today, the day average, sold and bought, a bar a day) from world.report('week'), and its "Today" counted a buy as a loss
// (-16,641 after one buy where HQ > Report said 0): a second, wrong profit. It is gone; the one profit is the Report's.
// THE CAPTAINS' BOARD LIVES ON RANK, AND ONLY THERE (owner, 2026-10-31: "no info duplicate info needed").
// EVERY SECOND (0232, owner row 213): the read is computed from the record at the moment it is asked, and asked again every second.

const SALE_SORTS = ['profit', 'newest', 'total'] as const

export function MeFace() {
  const t = useT()
  const me = useLiveRead<StatsMe>('stats:me', () => worldStatsMe())
  const { nowMs } = useShellState()
  const [choice, choose] = useFilterChoice('stats.me', { sales: 'profit' })
  const v = me.view

  if (me.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.meFailed')}</Note>

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
    <div className={`flex min-w-0 flex-col ${PAGE_GAP}`} data-testid="stats-me">
      <HistoryChart what="me" title={t('stats.yourHistory')} lines={companyLines(t)} data-testid="history-me" />
      <ListPanel
        look="card"
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
    </div>
  )
}
