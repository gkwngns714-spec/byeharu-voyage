import { Button, CargoBar, DetailPage, FactsLine, SectionColumns, SheetSection, ShipPowerLine } from '../../components/ui'
import type { FleetView } from '../../lib/rpc'
import { hullFraction, shipHoldFree, shipHoldUsed } from '../../domain/fleet'
import { FleetCargo } from './FleetCargo'
import { FleetStores } from './FleetStores'
import { HullGauge } from './HullGauge'
import { MoveShip } from './MoveShip'
import { useShipMoves } from './useShipMoves'
import { useT } from '../../lib/i18n'

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
    <DetailPage title={ship.name} word={ship.class} onClose={onClose} data-testid="fleet-ship-page">
      <div className="flex flex-col pb-4">
        {/* how sound she is and how full, the two figures her row carried, before the lists that spell the second one out */}
        <FactsLine className="mb-1" data-testid="fleet-ship-gauges">
          <HullGauge fraction={hullFraction(ship)} label={t('ui.hullOf', { name: ship.name })} />
          <CargoBar used={shipHoldUsed(ship)} total={ship.hold} free={shipHoldFree(ship)} className="min-w-48 grow basis-full sm:basis-auto" />
        </FactsLine>
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
