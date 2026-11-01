import { GOOD_CLASS_BARS, GOOD_CLASS_BAR_HEIGHTS, goodClassLabel, goodClassLook } from './goodClassTiers'

// THE CLASS MARK — the one rendering of a good's served premium class (0294).
//
// ── WHAT CONCEPT THIS IS, AND WHERE IT LIVES ────────────────────────────────────────────────────
// One noun phrase: "how a premium class looks". The class itself is DECIDED on the server
// (`public.good_class`: 1 plus the number of the knob's four base-value edges at or below the good's
// value) and arrives as a number on `SnapshotGood`, `MarketGood` and `TradeRequest`; this file owns
// only its appearance. That makes it a recipe — design-system property from its first caller
// (docs/NO_SPAGHETTI.md §7B). Known second callers, named: `GoodKind` (the one composition of a
// good's identity — the trays, the Market rows, the request board, the Codex) and `CargoRows`
// (a fleet's and a merchant's cargo), then the Forge and the Storage face. All of them render the
// SAME mark by calling this, never by re-mapping class → colour themselves. The pure table lives in
// ./goodClassTiers.ts (the rarityTiers.ts / Rarity.tsx split).
//
// ── NOT THE RARITY MARK, AND SAT BESIDE IT ──────────────────────────────────────────────────────
// Rarity is how few harbours make a good (a ring, a diamond, a gem, a star); class is how much a ton
// of it is worth — a different question with a different shape on purpose: five ascending BARS, a
// meter (▂▃▅▆█, the heights of the block characters), where rarity is a single glyph. Both marks
// stand together (GoodKind), and a glance tells them apart without reading either.
//
// ── TWO CHANNELS, ALWAYS ────────────────────────────────────────────────────────────────────────
// Every class is a COLOUR (the --color-class-* tokens, measured ≥ 4.5 : 1 on the sheet and on the
// inset in both schemes — src/index.css carries the figures) AND a SHAPE (the class is how many of
// the five bars are lit, so a 4 is four-fifths of a meter in any greyscale). Classes 1-3 are the
// game's own quiet inks; 4 and 5 are the only chroma, so a premium good is the loudest mark in a
// list. `withWord` adds the word itself (the tray and tile form); the compact form (the meter alone)
// carries the word as its accessible name and its `title`, so nothing is lost when the pixels shrink
// — and a press on the row opens the tray, which spells it out.
//
// ── WHAT WOULD MAKE THIS THE WRONG SHAPE ────────────────────────────────────────────────────────
// A second class → colour table anywhere (grep for 'class-'), or this component computing a class
// from a price or a base value — the served number is the only input it may read. No class served (a
// server older than 0294) renders NOTHING: the world did not say, so this mark does not either. A
// class this file does not recognise (a server newer than this client) prints its bare number in the
// ledger's quiet ink — a truthful lesser answer, never a crash and never a guess
// (docs/NO_SPAGHETTI.md §7C mirror rule).

export function GoodClassMark({
  goodClass,
  withWord = false,
  size = 8,
  className = '',
}: {
  /** The SERVED class. Absent (a server predating 0294) renders nothing. */
  goodClass: number | null | undefined
  /** True = meter + word (the tray, the tile). False = the meter alone, the word as its accessible name. */
  withWord?: boolean
  /** The meter's height in px (8 = the block characters' own proportions); its width is 1.75 × that. */
  size?: number
  className?: string
}) {
  if (goodClass == null) return null
  const look = goodClassLook(goodClass)
  const label = goodClassLabel(goodClass)
  if (look === undefined) {
    return (
      <span className={`text-t-caption text-ink-muted ${className}`} data-good-class-mark={goodClass}>
        {label}
      </span>
    )
  }
  return (
    <span
      className={`inline-flex items-center gap-1 whitespace-nowrap ${look.tone} ${className}`}
      data-good-class-mark={goodClass}
      {...(withWord ? {} : { role: 'img', 'aria-label': label, title: label })}
    >
      <Meter lit={look.bars} size={size} />
      {withWord && <span>{label}</span>}
    </span>
  )
}

/** Five bars of the block characters' heights (▂▃▅▆█ — 2, 3, 5, 6, 8 of 8), 2 wide and 1 apart, in a
 *  14 × 8 box: the lit ones solid, the rest a faint ghost of the scale, so the meter always shows how
 *  far up it could go. Drawn with currentColor; whole-pixel geometry so it is crisp at 1x and 2x. */
function Meter({ lit, size }: { lit: number; size: number }) {
  return (
    <svg
      viewBox="0 0 14 8"
      width={size * 1.75}
      height={size}
      fill="currentColor"
      shapeRendering="crispEdges"
      aria-hidden="true"
      className="shrink-0"
      data-meter-lit={lit}
    >
      {Array.from({ length: GOOD_CLASS_BARS }, (_, i) => (
        <rect key={i} x={i * 3} y={8 - GOOD_CLASS_BAR_HEIGHTS[i]} width={2} height={GOOD_CLASS_BAR_HEIGHTS[i]} opacity={i < lit ? 1 : 0.22} />
      ))}
    </svg>
  )
}
