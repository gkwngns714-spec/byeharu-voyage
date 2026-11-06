import { worldShipMoves } from '../../lib/rpc'
import type { ShipMoves } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'

/** 0321: where this fleet's ships may go, asked once for the fleet's page. Null until the first answer; {on: false} while dark. */
export function useShipMoves(fleetId: string): ShipMoves | null {
  return useServedRead<ShipMoves>(`ship-moves:${fleetId}`, () => worldShipMoves(fleetId), { name: 'worldShipMoves', cache: false }).view
}
