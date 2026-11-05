import { worldCargoShipCard, type CargoShipCard } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// ONE CARGO SHIP'S CARD (0310): `useMerchantCard`'s doorway for her. Read at a tap and while it is open.
export function useCargoShipCard(fleetId: string | null): CargoShipCard | null {
  return useServedRead<CargoShipCard>(fleetId, () => worldCargoShipCard(fleetId ?? ''), { name: 'worldCargoShipCard' }).view
}
