import { worldNpcFleetCard, type MerchantCard } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// ONE MERCHANT FLEET'S CARD (0099, docs/NPC_TRADERS.md §8.1) — a doorway onto `useServedRead`,
// keyed by the fleet, re-asked on the world's beat. The card is read at a tap and while it is open,
// never otherwise; the figures on it are the server's (laps summed by `public.route_earnings`).
export function useMerchantCard(fleetId: string | null): { card: MerchantCard | null; loading: boolean } {
  const read = useServedRead<MerchantCard>(fleetId, () => worldNpcFleetCard(fleetId ?? ''))
  return { card: read.view, loading: read.loading }
}
