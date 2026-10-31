import type { ForgeRecipe } from '../lib/rpc'

// ONE GROUP PER PRODUCT TIER, in the served order (the query orders by tier, then name).
//
// Extracted from PortForge.tsx (2026-10-31) so the City page's compact Forge screen can carry the
// same tier counts the opened page shows: the row says "Tier 1 · 24" and the page it opens lists
// exactly those 24. Two folds would be two answers to "how many in this tier"; this is the one.
export function groupsByTier(recipes: readonly ForgeRecipe[]): [number, ForgeRecipe[]][] {
  const groups = new Map<number, ForgeRecipe[]>()
  for (const r of recipes) {
    const group = groups.get(r.tier)
    if (group) group.push(r)
    else groups.set(r.tier, [r])
  }
  return [...groups.entries()]
}
