import { Card, StatCell } from '../../components/ui'
import { formatDucats } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsBonus, StatsFlowLine } from '../../lib/rpc'
import { bonusBook } from './statsFaces'

// THE BONUS MONEY (owner, 2026-11-05: "in report, or stats, bonus fees should also be monitored too"; 0311). The world's on Stats, a city's on its
// page: the budget held open now, and over the last 24 h the budget set, the bonus paid out and the budget returned. Set = paid + returned + what is
// still held, to the ducat (0311's self-assert). Budget set and returned are the flow lines the caller already holds; held and paid are served.
export function BonusCard({ flows, bonus }: { flows: readonly StatsFlowLine[]; bonus: StatsBonus }) {
  const t = useT()
  const b = bonusBook(flows, bonus)
  return (
    <Card title={t('stats.bonus')} data-testid="stats-bonus">
      <div className="flex flex-col gap-1">
        <StatCell look="line" label={t('stats.bonusHeld')} value={b.held} format={formatDucats} data-testid="stats-bonus-held" />
        <StatCell look="line" label={t('stats.bonusBudget')} value={b.budget} format={formatDucats} data-testid="stats-bonus-budget" />
        <StatCell look="line" label={t('stats.bonusPaid')} value={b.paid} format={formatDucats} data-testid="stats-bonus-paid" />
        <StatCell look="line" label={t('stats.bonusBack')} value={b.returned} format={formatDucats} data-testid="stats-bonus-returned" />
      </div>
    </Card>
  )
}
