import { Hint, StackedBar, StatCell } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsFleetTally } from '../../lib/rpc'
import { FLEET_STATES } from './fleetStates'

// THE ONE DRAWING OF A KIND'S COUNT (0448; fleetStates.ts has the why): the Ships, Merchants, Navy, Pirates and Cargo faces all show it through this.

/** A kind's count as every face shows it: its fleets and its ships, each under its own word, then the FLEETS by state (the caption says so).
 *  Every number is the server's; before the first count they read 0. */
export function FleetStates({ tally, label, 'data-testid': testid }: { tally: Partial<StatsFleetTally>; label: string; 'data-testid': string }) {
  const t = useT()
  return (
    <>
      <div className="grid grid-cols-2 gap-x-4">
        <StatCell look="stacked" label={t('stats.fleetsWord')} value={tally.fleets ?? 0} format={formatInt} />
        <StatCell look="stacked" label={t('stats.shipsWord')} value={tally.ships ?? 0} format={formatInt} />
      </div>
      <Hint className="mt-4">{t('stats.byFleet')}</Hint>
      <StackedBar
        parts={FLEET_STATES.map((s) => ({ id: s.id, label: t(s.word), value: tally[s.id] ?? 0, tone: s.tone }))}
        format={formatInt}
        label={label}
        className="mt-2"
        data-testid={testid}
      />
    </>
  )
}
