import { Card } from '../components/ui'
import { fleetCountMark, hullShapePath, familyHullShape, SHIP_FAMILIES, SHIP_TIERS, type ShipFamily, type ShipTier } from '../chart'
import { useT } from '../lib/i18n'
import { ShipArtIcon } from './battle/ShipArt'

// THE KEY TO THE SHIP PICTURES (2026-11-16, owner: *"the one with stronger ships, multiple fleets should have different
// graphics. this goes to every kinds of ship too"*): on the Codex's Ships face, every family at its four tiers, drawn by
// the one component the battle stage draws them with (./battle/ShipArt.tsx), and the chart's own mark for a fleet of
// one, two, three and four or more (src/chart/shipShapes.ts `fleetCountMark`). It draws; it decides nothing.

const TIER_WORD = { 1: 'ship.tier_sloop', 2: 'ship.tier_brig', 3: 'ship.tier_frigate', 4: 'ship.flagship' } as const satisfies Record<ShipTier, string>
const FAMILY_WORD = {
  yours: 'ship.fam_yours',
  merchant: 'ship.fam_merchant',
  cargo: 'map.cargoShip',
  navy: 'map.navyShip',
  pirate: 'map.pirateShip',
} as const satisfies Record<ShipFamily, string>

/** The chart's mark for a fleet of `ships`, as the chart draws it pulled back (one hull, the rest said astern), four times the size. */
function FleetSizeMark({ ships }: { ships: number }) {
  const l = 5.35
  const more = fleetCountMark(ships, 1, l, l)
  return (
    <svg width={40} height={56} viewBox="-7 -7 14 19.6" aria-hidden data-testid="ships-key-size" data-ships={ships}>
      <path d={hullShapePath(familyHullShape('merchant', 3), l)} className="fill-accent" />
      {more !== null && <path d={more} className="fill-accent" />}
    </svg>
  )
}

export function ShipsKey() {
  const t = useT()
  return (
    <Card title={t('ship.keyTitle')} data-testid="ships-key">
      <div className="flex flex-col gap-2">
        <div className="grid grid-cols-4 gap-1 text-center text-t-caption text-ink-muted">
          {SHIP_TIERS.map((tier) => (
            <span key={tier} className="break-words">
              {t(TIER_WORD[tier])}
            </span>
          ))}
        </div>
        {SHIP_FAMILIES.map((family) => (
          <div key={family} data-testid="ships-key-family" data-family={family}>
            <div className="text-t-caption font-semibold text-ink">{t(FAMILY_WORD[family])}</div>
            <div className="grid grid-cols-4 place-items-center gap-1 rounded-control bg-chart-sea py-1">
              {SHIP_TIERS.map((tier) => (
                <ShipArtIcon key={tier} family={family} tier={tier} width={68} />
              ))}
            </div>
          </div>
        ))}
        <div data-testid="ships-key-sizes">
          <div className="text-t-caption font-semibold text-ink">{t('ship.fleetSize')}</div>
          <div className="grid grid-cols-4 place-items-center gap-1 rounded-control bg-chart-sea py-1">
            {([1, 2, 3, 4] as const).map((ships) => (
              <div key={ships} className="flex flex-col items-center">
                <FleetSizeMark ships={ships} />
                <span className="text-t-caption text-ink-muted">{ships === 4 ? '4+' : ships}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Card>
  )
}
