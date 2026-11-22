import { worldPirateBounties, type PirateBounties } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// THE NAMED PIRATES (0471): `world.pirate_bounties()`, one read on the world's beat, one cache key, shared by every face that shows a
// bounty (Rank's Bounties, the pirate sheet). Dark the server answers {on: false} and every face draws nothing of it.
export function usePirateBounties(): PirateBounties | null {
  return useServedRead('pirate-bounties', worldPirateBounties, { name: 'worldPirateBounties' }).view
}
