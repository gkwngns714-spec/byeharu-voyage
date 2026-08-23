import { Icon } from './Icon'
import type { IconName } from './icons'
import { RARITY_TIER_LOOK, rarityLabel } from './rarityTiers'

// THE RARITY MARK — the one rendering of a good's served rarity tier (0032).
//
// ── WHAT CONCEPT THIS IS, AND WHERE IT LIVES ────────────────────────────────────────────────────
// One noun phrase: "how a rarity tier looks". The tier itself is DECIDED on the server
// (`public.good_rarity`, 0032) and arrives as a field on `SnapshotGood` and `MarketGood`; this
// file owns only its appearance. That makes it a recipe — design-system property even while one
// screen uses it (docs/NO_SPAGHETTI.md §2: the chip was hand-written twelve times because the
// first copy was "just this one screen"). Known second callers, named per §7B: the COMPENDIUM's
// goods face and the good picker on COMMAND; MARKET's rows are plausible after that. All of them
// render the SAME mark by calling this, never by re-mapping tier→colour themselves. The pure
// tier→appearance data lives in ./rarity.ts (the icons.ts / Icon.tsx split).
//
// ── TWO CHANNELS, ALWAYS ────────────────────────────────────────────────────────────────────────
// Every tier is a COLOUR (the --color-rarity-* tokens, measured ≥6:1 on bg-panel — src/index.css
// carries the figures) AND a SHAPE (ring / diamond / faceted gem / four-point star, icons.ts), so
// the tier survives a colourblind player and a greyscale screenshot. `withWord` adds the word
// itself — the compendium column form; the compact form (glyph only) carries the word as its
// accessible name instead, so a screen reader loses nothing when the pixels shrink.
//
// ── WHAT WOULD MAKE THIS THE WRONG SHAPE ────────────────────────────────────────────────────────
// A second tier→colour table anywhere (grep for 'rarity-'), or this component computing a tier
// from producer counts or price — the served word is the only input it may read. A rarity this
// file does not recognise (a server newer than this client) renders as the plain word in the
// ledger's quiet ink: a truthful lesser answer, never a crash and never a guess
// (docs/NO_SPAGHETTI.md §7C mirror rule).

export function RarityMark({
  rarity,
  withWord = false,
  size = 12,
  className = '',
}: {
  /** The SERVED tier. Absent (a server predating 0032) renders an em-dash with the word form,
   *  nothing in compact form — the world did not say, so this mark does not either. */
  rarity: string | null | undefined
  /** True = glyph + word (the compendium column). False = glyph only, word as accessible name. */
  withWord?: boolean
  size?: number
  className?: string
}) {
  if (rarity == null || rarity === '') {
    return withWord ? <span className={`text-ink-faint ${className}`}>{'—'}</span> : null
  }
  const known = (RARITY_TIER_LOOK as Record<string, { icon: IconName; tone: string } | undefined>)[rarity]
  if (known === undefined) {
    // A tier this build has never heard of: print the served word, quietly. Truthful, lesser.
    return (
      <span className={`font-mono text-[10px] uppercase tracking-wider text-ink-muted ${className}`}>
        {rarityLabel(rarity)}
      </span>
    )
  }
  return (
    <span
      className={`inline-flex items-center gap-1 whitespace-nowrap ${known.tone} ${className}`}
      {...(withWord ? {} : { role: 'img', 'aria-label': rarityLabel(rarity), title: rarityLabel(rarity) })}
    >
      <Icon name={known.icon} size={size} className="shrink-0" />
      {withWord && (
        <span className="font-mono text-[10px] uppercase tracking-wider">{rarityLabel(rarity)}</span>
      )}
    </span>
  )
}
