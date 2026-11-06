import { worldNavyShipCard, type NavyShipCard } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// ONE NAVY SHIP'S CARD (0331): `useCargoShipCard`'s doorway for her. Read at a tap and while it is open.
export function useNavyShipCard(fleetId: string | null): NavyShipCard | null {
  return useServedRead<NavyShipCard>(fleetId, () => worldNavyShipCard(fleetId ?? ''), { name: 'worldNavyShipCard' }).view
}
