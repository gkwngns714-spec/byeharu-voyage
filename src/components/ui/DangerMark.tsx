import { dangerLabel, dangerPips, dangerTone } from './dangerTiers'

// THE DANGER MARK — the one rendering of a sea's served danger tier (migrations 0040 / 0055).
//
// ── WHAT CONCEPT THIS IS, AND WHERE IT LIVES ────────────────────────────────────────────────────
// One noun phrase: "how a danger tier looks". The tier is DECIDED on the server
// (`seas.danger_level`, authored per sea) and arrives on `VoyageWater.danger`; this file owns only
// its appearance. That makes it a recipe, and a recipe is design-system property even while one
// screen uses it — docs/NO_SPAGHETTI.md §2: the chip was hand-written twelve times because the
// first copy was "just this one screen". Named second callers per §7B: the COMPENDIUM's seas face,
// and the SAIL preview when it starts saying what water an order would cross. All of them draw the
// SAME mark by calling this, never by re-mapping a tier to a colour themselves.
//
// ── FIVE PIPS, THREE TONES, AND WHY THAT IS NOT A HALF-DONE RAMP ───────────────────────────────
// The COUNT carries the whole five-step scale; the TONE carries the meaning, in the colour
// language docs/UI_DIRECTION.md rule 7 fixes for the whole game (green safe, amber caution, red
// danger). Two channels, so a colourblind player and a greyscale screenshot both keep the tier.
// A five-colour ramp would mean two new palette tokens that mean nothing anywhere else, which is a
// second colour language, not a better one.
//
// ── WHAT WOULD MAKE THIS THE WRONG SHAPE ────────────────────────────────────────────────────────
// Anything here deriving a tier — from a hazard rate, a piracy index, a distance. The served
// number is the only input it may read, because migration 0055 keys the per-sea encounter mix on
// that same column: the day the pips and the mix disagree, the picture is lying about the rules.

export function DangerMark({
  tier,
  size = 3,
  className = '',
}: {
  /** The SERVED tier, 1–5 (`seas.danger_level`). */
  tier: number
  /** Pip edge: 3 draws `h-1.5` (6 px), the phone size and the one the map's row indent is
   *  measured against; 2 draws `h-1` (4 px) for a denser table row. */
  size?: 2 | 3
  className?: string
}) {
  const box = size === 2 ? 'h-1 w-1' : 'h-1.5 w-1.5'
  return (
    <span
      className={`inline-flex shrink-0 items-center gap-px ${dangerTone(tier)} ${className}`}
      role="img"
      aria-label={dangerLabel(tier)}
      title={dangerLabel(tier)}
      data-testid="danger-mark"
      data-tier={tier}
    >
      {dangerPips(tier).map((lit, i) => (
        <span
          key={i}
          aria-hidden="true"
          className={`${box} rounded-[1px] ${lit ? 'bg-current' : 'bg-current opacity-20'}`}
        />
      ))}
    </span>
  )
}
