import type { GoodRarity } from '../../lib/rpc'
import type { IconName } from './icons'

// RARITY TIERS — the pure half of the tier rendering (the icons.ts / Icon.tsx split, applied again):
// the ordered scale, the player's word, and the tier→(shape, colour-token) table, with no React,
// so the name→appearance contract is data a test can read. `RarityMark` (Rarity.tsx) is the one
// component that draws it. See Rarity.tsx for what the concept is and where it may be consumed.

/** Ascending, for filter chips and legends. `satisfies` keeps it honest against the served union. */
export const RARITY_TIERS = ['common', 'uncommon', 'rare', 'exotic'] as const satisfies readonly GoodRarity[]

/** The player's word for a tier — the one reading, like `categoryLabel` for categories. */
export function rarityLabel(rarity: string): string {
  return rarity
}

// Completeness both ways: Record refuses to build if GoodRarity gains a tier this table misses.
export const RARITY_TIER_LOOK: Record<GoodRarity, { icon: IconName; tone: string }> = {
  common: { icon: 'rarityCommon', tone: 'text-rarity-common' },
  uncommon: { icon: 'rarityUncommon', tone: 'text-rarity-uncommon' },
  rare: { icon: 'rarityRare', tone: 'text-rarity-rare' },
  exotic: { icon: 'rarityExotic', tone: 'text-rarity-exotic' },
}
