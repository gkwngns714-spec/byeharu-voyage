import { Button, CargoBar, DetailPage, Icon, SectionColumns, SheetSection, ShipPowerLine } from '../../components/ui'
import { formatKnots, formatOfTotal } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { hullFraction, shipHoldFree, shipHoldUsed } from '../../domain/fleet'
import { FleetCargo } from './FleetCargo'
import { FleetStores } from './FleetStores'
import { HullGauge } from './HullGauge'
import { MoveShip } from './MoveShip'
import { useShipMoves } from './useShipMoves'
import { ShipPicture } from '../../live/ShipPicture'
import { properName, useT } from '../../lib/i18n'

// ONE SHIP'S PAGE: HER CARGO AND HER SUPPLIES — the owner, 2026-11-14: *"in fleets, when pressed a fleet, show only ships, then when i
// press the ship, show cargo and supplies."*
//
// The second step. It is the game's one pop-up page (`DetailPage`) over her fleet's page, so its back press (and Escape) gives the
// ships list back exactly as it stood, and its title is her name, whole.
//
// ── EVERY FIGURE IS HER OWN, AND SERVED ────────────────────────────────────────────────────────
// The world read serves cargo and stores PER SHIP (`FleetShip.cargo`, `cargo_tuns`, `water_t`, `food_t`, `stores_cap`, `hold`), so
// nothing on this page is a fleet's figure split by the client. The cargo and supplies faces are the same two the fleet's page drew
// (FleetCargo, FleetStores), handed one hull instead of all of them. The ONE fleet figure here is the days of supplies, which the
// server serves per fleet only; its row says "Whole fleet".
//
// ── WHAT ELSE STANDS HERE ──────────────────────────────────────────────────────────────────────
// The two presses a ship's tile carried: Stats (her whole sheet, live/ShipPanel, mounted over this page by FleetsScreen) and Move
// (MoveShip, drawn only where the server offers a move). They are things done to THIS ship, so they left the fleet's page with her.
// Above them, the tile's Power line (owner row 288), one caption line: it is a ship's reading and the rows do not carry it.
export function FleetShipPage({ fleet, shipId, onOpenStats, onClose }: { fleet: FleetView; shipId: string; onOpenStats: () => void; onClose: () => void }) {
  const ship = fleet.ships.find((s) => s.id === shipId) ?? null
  // she left this fleet (a move) or the world: nothing to show, and the fleet's page is what stands
  if (!ship) return null
  return <ShipPage fleet={fleet} ship={ship} onOpenStats={onOpenStats} onClose={onClose} />
}

function ShipPage({ fleet, ship, onOpenStats, onClose }: { fleet: FleetView; ship: FleetView['ships'][number]; onOpenStats: () => void; onClose: () => void }) {
  const t = useT()
  const moves = useShipMoves(fleet.id)
  const one = { ships: [ship] }
  return (
    <DetailPage title={ship.name} word={properName('hull', ship.class, ship.class)} onClose={onClose} data-testid="fleet-ship-page">
      <div className="flex flex-col pb-4">
        {/* HER PICTURE AND HER FOUR FIGURES FIRST (2026-11-23, the visual overhaul's slice 5: "a ship sheet led by its picture and 3-4 key figures").
            Her picture is the battle stage's own at her served tier (ShipPicture.tsx); under it how sound she is and how full (the two bars her row
            carried), then her hands and her speed as a mark and a number. The lists below spell the hold and the stores out. */}
        <div className="mb-2 flex flex-col items-center gap-4 sm:flex-row sm:items-center" data-testid="fleet-ship-hero">
          <ShipPicture code={ship.class_code} size="hero" tone={ship.is_flagship ? 'var(--color-accent)' : undefined} label={properName('hull', ship.class, ship.class)} data-testid="fleet-ship-picture" />
          <div className="flex w-full min-w-0 flex-col gap-3 text-t-caption text-ink-faint" data-testid="fleet-ship-gauges">
            <HullGauge fraction={hullFraction(ship)} label={t('ui.hullOf', { name: ship.name })} />
            <CargoBar used={shipHoldUsed(ship)} total={ship.hold} free={shipHoldFree(ship)} icon="hold" />
            <span className="flex flex-wrap items-center gap-x-6 gap-y-2 text-t-body text-ink">
              <span className="flex items-center gap-2" title={t('ship.crew')} data-testid="fleet-ship-crew">
                <span role="img" aria-label={t('ship.crew')} className="flex shrink-0">
                  <Icon name="crew" size={18} className="text-ink-muted" />
                </span>
                <span className="tabular-nums font-semibold">{formatOfTotal(ship.crew, ship.crew_max)}</span>
              </span>
              <span className="flex items-center gap-2" title={t('ship.speed')} data-testid="fleet-ship-speed">
                <span role="img" aria-label={t('ship.speed')} className="flex shrink-0">
                  <Icon name="knots" size={18} className="text-ink-muted" />
                </span>
                <span className="tabular-nums font-semibold">{formatKnots(ship.speed)}</span>
              </span>
            </span>
          </div>
        </div>
        <SectionColumns count={2}>
          <SheetSection heading={t('fleets.cargo')} data-testid="fleet-fold-section">
            <FleetCargo fleet={one} />
          </SheetSection>
          <SheetSection heading={t('fleets.supplies')} data-testid="fleet-fold-section">
            <FleetStores fleet={one} fleetDays={fleet.endurance_days} />
          </SheetSection>
        </SectionColumns>
        {/* owner row 288: the five figures a fight reads, the line her tile carried; Stats under it opens the sheet they come from */}
        <ShipPowerLine power={ship} className="mt-6" />
        <div className="mt-3 flex flex-wrap gap-3">
          <Button variant="secondary" className="flex-1" onClick={onOpenStats} data-testid="ship-stats">
            {t('fleets.shipStats')}
          </Button>
          <MoveShip moves={moves} fleet={fleet} ship={ship} />
        </div>
      </div>
    </DetailPage>
  )
}
