import { worldPirateShipCard, type PirateShipCard } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// ONE PIRATE SHIP'S CARD (0339): `useNavyShipCard`'s doorway for her. Read at a tap and while it is open.
export function usePirateShipCard(fleetId: string | null): PirateShipCard | null {
  return useServedRead<PirateShipCard>(fleetId, () => worldPirateShipCard(fleetId ?? ''), { name: 'worldPirateShipCard' }).view
}
