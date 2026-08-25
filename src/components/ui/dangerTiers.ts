// DANGER TIERS — the pure half of the tier rendering (the icons.ts / Icon.tsx split, applied
// again, exactly as rarityTiers.ts / Rarity.tsx does it): the scale, the player's word, and the
// tier → (how many pips, which tone) table, with no React, so the contract is data a test reads.
// `DangerMark` (DangerMark.tsx) is the one component that draws it.
//
// THE TIER IS THE SERVER'S. `seas.danger_level` is authored per sea (migration 0040) and arrives
// on `VoyageWater.danger`; migration 0055's per-sea encounter mix is keyed on the SAME column, so
// what a player is shown and what will decide her weather are one number. Nothing here derives a
// tier from a hazard rate, a piracy index or a distance — that would be a second danger scale, and
// the whole point of the column is that there is one.

/** The scale, ascending. 1 is home waters; 5 is deadly. */
export const DANGER_TIERS = [1, 2, 3, 4, 5] as const

/** How many pips a tier fills, out of `DANGER_PIPS`. The count IS the tier — no curve, no bands. */
export const DANGER_PIPS = 5

/**
 * The pips, lit and unlit, for a tier — the mark's whole geometry as data, so the count contract
 * is something a spec reads rather than something it greps out of markup. An unknown tier is
 * clamped into the scale rather than drawing a sixth pip or none at all.
 */
export function dangerPips(tier: number): boolean[] {
  const filled = Math.max(0, Math.min(DANGER_PIPS, Math.round(tier)))
  return Array.from({ length: DANGER_PIPS }, (_, i) => i < filled)
}

/**
 * The player's word for a tier. Short, a NAME rather than a sentence (UI_DIRECTION rule 3), and it
 * is the mark's accessible name — a screen reader gets the word where the eye gets the pips.
 */
export function dangerLabel(tier: number): string {
  switch (tier) {
    case 1:
      return 'home waters'
    case 2:
      return 'quiet'
    case 3:
      return 'unsettled'
    case 4:
      return 'dangerous'
    case 5:
      return 'deadly'
    default:
      // A tier this build has never heard of (a server newer than this client): say the number,
      // quietly. Truthful and lesser, never a crash and never a guess — docs/NO_SPAGHETTI.md §7C's
      // mirror rule, and the same arm RarityMark takes for an unknown rarity.
      return `tier ${tier}`
  }
}

/**
 * THE COLOUR LANGUAGE, unchanged from docs/UI_DIRECTION.md rule 7: green = safe, amber = caution,
 * red = danger. Three tones over five tiers on purpose — inventing a five-step ramp would mean two
 * new palette tokens that mean nothing anywhere else in the game, and the PIP COUNT already
 * carries the full five-step resolution. Two channels, so the tier survives a colourblind player
 * and a greyscale screenshot.
 */
export function dangerTone(tier: number): string {
  if (tier <= 2) return 'text-success'
  if (tier === 3) return 'text-warning'
  return 'text-danger'
}
