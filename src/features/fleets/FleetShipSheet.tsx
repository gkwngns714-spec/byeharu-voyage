import { useEffect, useMemo } from 'react'
import { useBackLayer } from '../../components/ui'
import type { FleetView } from '../../lib/rpc'
import { ShipPanel } from '../../live/ShipPanel'
import { useWorld } from '../../live/worldStore'

// ONE SHIP'S WHOLE SHEET, FROM HER FLEET'S PAGE (F5, 2026-11-11; owner row 180: "Show stats of individual ship and also as a fleet"). The sheet is the ONE ship sheet the
// game has (live/ShipPanel: the Map's fleet panel and a merchant's card open the same one); this file only stands it over the fleet's page. One press on the tile's Stats
// opens it, its close gives the fleet's page back exactly as it was (the page is never unmounted), and Escape leaves the sheet first and the page second.
// As on the Map, her cabins can be seated here while her fleet is docked: the same rule (`seating`), the same captains (the company's roster in the world store).

export function FleetShipSheet({ fleet, shipId, onClose }: { fleet: FleetView; shipId: string; onClose: () => void }) {
  const ship = fleet.ships.find((s) => s.id === shipId) ?? null
  const nation = useWorld((s) => s.player?.nation ?? null)
  const roster = useWorld((s) => s.officers)
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const kept = useMemo(() => (roster?.officers ?? []).filter((o) => o.hired), [roster])
  useEffect(() => {
    if (roster === null) void loadOfficers()
  }, [roster, loadOfficers])
  useBackLayer(onClose)
  if (!ship) return null
  return <ShipPanel key={ship.id} ship={ship} nation={nation} overPage onClose={onClose} seating={{ shipId: ship.id, docked: fleet.status === 'DOCKED', captains: kept }} />
}
