import { Figure, Row } from '../../components/ui'
import { formatFixed, formatInt } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { fleetCrew } from '../../domain/fleet'
import { useT } from '../../lib/i18n'

// THE STORES — one line (owner row 203, 2026-10-25: *"what is this 'keep supply at'? this is useless"*).
//
// Supplies are AUTOMATIC since 0225: every SAIL buys what its leg needs through `public.supply_need`
// (the same rule the sail door judges by), so there is nothing here for a player to set. What is left
// is what she has — the served days of stores (`endurance_days`, 0016's one range figure) — and the
// crew they are sized against. The keep-level stepper, its book of presets and the hint about
// topping up at every port went with the standing order (docs/COMMAND_REDESIGN.md R1).

export function FleetStores({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const crew = fleetCrew(fleet)
  return (
    <>
      {/* BARE FIGURES, THE UNIT ON THE FIGURE: `Figure` sets the unit small and dim beside the value. */}
      <Row
        label={t('fleets.supplies')}
        value={<Figure value={formatFixed(fleet.endurance_days, 1)} unit={t('fleets.unitDays')} />}
        data-testid="fleet-stores-days"
      />
      <Row
        label={t('fleets.crew')}
        value={
          <Figure
            value={`${formatInt(crew.aboard)}/${formatInt(crew.max)}`}
            unit={t('fleets.onBoard')}
            tone={crew.short > 0 ? 'danger' : 'ink'}
          />
        }
        hairline={false}
      />
    </>
  )
}
