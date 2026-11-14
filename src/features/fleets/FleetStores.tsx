import { Figure, Row } from '../../components/ui'
import { formatFixed, formatInt, tonsWord } from '../../lib/format'
import { fleetCrew, fleetStores, fleetStoresSpace, type Hulls } from '../../domain/fleet'
import { useT } from '../../lib/i18n'

// THE STORES — one line (owner row 203, 2026-10-25: *"what is this 'keep supply at'? this is useless"*).
//
// Supplies are AUTOMATIC since 0225: every SAIL buys what its leg needs through `public.supply_need`
// (the same rule the sail door judges by), so there is nothing here for a player to set. What is left
// is what she has — the served days of stores (`endurance_days`, 0016's one range figure) — and the
// crew they are sized against. The keep-level stepper, its book of presets and the hint about
// topping up at every port went with the standing order (docs/COMMAND_REDESIGN.md R1).
//
// ── ONE SHIP'S SUPPLIES (owner, 2026-11-14: *"when i press the ship, show cargo and supplies"*) ─────────────────
// This face now stands on a ship's page, handed `{ ships: [ship] }`: her own water and food in tons (`water_t`, `food_t`, served per
// ship), her own supply room when the server serves one, and her own crew. THE DAYS ARE THE FLEET'S: the server serves one range
// figure for the whole fleet (`FleetView.endurance_days`) and none per ship, so the row says "Whole fleet" and nothing here splits it.

export function FleetStores({ fleet, fleetDays }: { fleet: Hulls; /** `FleetView.endurance_days`: the whole fleet's days, served. */ fleetDays: number }) {
  const t = useT()
  const crew = fleetCrew(fleet)
  // 0345 (owner row 221): lit, each ship carries her supplies in her own stores space — what is in it, of how much.
  const space = fleetStoresSpace(fleet)
  const stores = fleetStores(fleet)
  return (
    <>
      {/* BARE FIGURES, THE UNIT ON THE FIGURE: `Figure` sets the unit small and dim beside the value. */}
      <Row label={t('fleets.water')} value={<Figure value={formatFixed(stores.waterT, 1)} unit={tonsWord(stores.waterT)} />} data-testid="ship-stores-water" />
      <Row label={t('fleets.food')} value={<Figure value={formatFixed(stores.foodT, 1)} unit={tonsWord(stores.foodT)} />} data-testid="ship-stores-food" />
      {space && (
        <Row
          label={t('fleets.storesSpace')}
          value={<Figure value={`${formatInt(space.aboardT)}/${formatInt(space.capT)}`} unit={tonsWord(space.capT)} />}
          data-testid="fleet-stores-space"
        />
      )}
      <Row
        label={t('fleets.wholeFleet')}
        value={<Figure value={formatFixed(fleetDays, 1)} unit={t('fleets.unitDays')} />}
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
