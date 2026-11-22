import { familyHullShape, hullShapePath, sailPath, shipRig, type ShipFamily, type ShipTier } from '../../chart'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SHIP, DRAWN LARGE (owner, 2026-11-16: *"every pirate ship's graphic is same. the one with stronger ships,
// multiple fleets should have different graphics. this goes to every kinds of ship too"*).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The battle stage and the Codex key draw the SAME family the chart does: her hull is the chart's own silhouette
// for her family and tier (src/chart/glyphs.ts `familyHullShape`), so a pirate frigate on the map is the same
// frigate here, only larger and with what a large picture has room for (src/chart/shipShapes.ts `shipRig`):
//   masts and sails   one, two, three as the tier rises, a flagship's widest
//   pirate            dark sails, the forked stern, a black flag
//   navy              white sails, a stripe of gun ports down each side, an ensign
//   merchant          a round hull, pale sails, a hatch on the larger ones
//   cargo             the tub, with her crates on deck
//   yours             a merchant's hull in the accent, with a long pennant
// Nothing here decides WHO she is: the family and the tier are handed in, read from served facts by the caller
// (src/chart/shipShapes.ts `familyOfSide`, `shipTierOf`). Drawn BOW TO THE RIGHT about the origin, half-length 62 at tier 3, the frame
// the stage has always turned and scaled.

const BG = 'var(--color-bg)'
const INK = 'var(--color-ink)'
const mix = (token: string, pct: number, into = BG) => `color-mix(in srgb, var(${token}) ${pct}%, ${into})`

/** The colours a family is painted in. One row a family; the stage's side tone is the hull's outline, as before. */
const PAINT: Readonly<Record<ShipFamily, { readonly hull: string; readonly deck: string; readonly sail: string; readonly sailEdge: string | null }>> = {
  yours: { hull: mix('--color-accent', 30), deck: mix('--color-accent', 48), sail: mix('--color-accent', 62, INK), sailEdge: null },
  merchant: { hull: mix('--color-merchant', 55), deck: mix('--color-merchant', 62, INK), sail: INK, sailEdge: null },
  cargo: { hull: mix('--color-cargo-hull', 34), deck: mix('--color-cargo-hull', 58), sail: mix('--color-cargo-hull', 22, INK), sailEdge: null },
  navy: { hull: mix('--color-navy-hull', 34), deck: mix('--color-navy-hull', 60), sail: INK, sailEdge: null },
  pirate: { hull: mix('--color-pirate-hull', 28), deck: mix('--color-pirate-hull', 50), sail: `color-mix(in srgb, ${INK} 14%, ${BG})`, sailEdge: 'var(--color-pirate-hull)' },
}

/** How long a tier is drawn, against a frigate: the hull lengthens as the tier rises. */
const LENGTH: readonly number[] = [0.7, 0.85, 1, 1.16]
const FRIGATE_HALF_LENGTH = 62

/** The half-length a tier is drawn at here, bow to stern centre. */
const shipArtHalfLength = (tier: ShipTier) => FRIGATE_HALF_LENGTH * LENGTH[tier - 1]

/**
 * THE SHIP. `tone` is her outline (the stage's side colour; the key's sea), `struck` strikes her colours and
 * fades her sails, `wake` draws the water she leaves.
 */
export function ShipArt({ family, tier, tone = 'var(--color-chart-sea)', struck = false, wake = false }: { family: ShipFamily; tier: ShipTier; tone?: string; struck?: boolean; wake?: boolean }) {
  const l = shipArtHalfLength(tier)
  const rig = shipRig(family, tier)
  const paint = PAINT[family]
  const hull = hullShapePath(familyHullShape(family, tier), l)
  const beam = rig.beam * l
  const stern = rig.stern * l
  // ports and holds are spaced down her waist, between the foremast and the stern
  const waist = (i: number, n: number) => (-0.34 + (0.8 * (i + 0.5)) / n) * l
  return (
    <g data-ship-art={`${family}-${tier}`}>
      {wake && <path d="M -56 -12 Q -96 -10 -138 -26 Q -104 0 -138 26 Q -96 10 -56 12 Z" transform={`scale(${LENGTH[tier - 1]})`} fill={INK} fillOpacity={0.12} />}
      {/* everything below is drawn bow up, as the chart draws her, and turned once */}
      <g transform="rotate(90)">
        <path d={hull} fill={paint.hull} stroke={tone} strokeWidth={3} strokeLinejoin="round" />
        <path d={hull} transform="scale(0.76)" fill={paint.deck} />
        {/* bowsprit */}
        <line x1={0} y1={-l} x2={0} y2={-l * 1.24} stroke={paint.hull} strokeWidth={3} strokeLinecap="round" />
        {/* a hold: a merchant's hatch, a cargo ship's crates (one more a tier) */}
        {Array.from({ length: rig.holds }, (_, i) => {
          const y = family === 'cargo' ? (-0.3 + (1.05 * (i + 0.5)) / rig.holds) * l : 0.2 * l
          const w = beam * (family === 'cargo' ? 0.62 : 0.5)
          const h = Math.min(l * 0.2, (l * 0.8) / Math.max(1, rig.holds))
          return (
            <g key={`h${i}`} data-ship-hold="">
              <rect x={-w} y={y - h / 2} width={w * 2} height={h} rx={2} fill={paint.hull} stroke={INK} strokeOpacity={0.55} strokeWidth={1.5} />
              {family === 'cargo' && <path d={`M${-w} ${y - h / 2}L${w} ${y + h / 2}M${w} ${y - h / 2}L${-w} ${y + h / 2}`} stroke={INK} strokeOpacity={0.4} strokeWidth={1.2} />}
            </g>
          )
        })}
        {/* the navy's stripe of gun ports down each side (a pirate frigate and flagship carry a few) */}
        {rig.ports > 0 && family === 'navy' && (
          <path d={`M${-beam * 0.66} ${-0.36 * l}L${-beam * 0.66} ${0.48 * l}M${beam * 0.66} ${-0.36 * l}L${beam * 0.66} ${0.48 * l}`} stroke={INK} strokeOpacity={0.85} strokeWidth={2.2} />
        )}
        {Array.from({ length: rig.ports }, (_, i) =>
          [-1, 1].map((side) => (
            <rect key={`p${i}${side}`} data-ship-port="" x={side * beam * 0.66 - 2.4} y={waist(i, rig.ports) - 2.4} width={4.8} height={4.8} fill={BG} />
          )),
        )}
        {/* the sails across the yards, bellied forward */}
        {rig.masts.map((m) => (
          <path key={`s${m.y}`} data-ship-sail="" d={sailPath(m.y, m.span, l)} fill={paint.sail} fillOpacity={struck ? 0.35 : 0.94} stroke={paint.sailEdge ?? undefined} strokeWidth={paint.sailEdge ? 1.5 : undefined} />
        ))}
        {rig.masts.map((m) => (
          <circle key={`m${m.y}`} cx={0} cy={m.y * l + 2} r={3} fill={paint.hull} stroke={INK} strokeOpacity={0.5} strokeWidth={1} />
        ))}
        {/* her colours at the stern: struck, they come down */}
        {!struck && <Colours family={family} tone={tone} y={stern} />}
        {/* a flagship flies a pennant from the main as well */}
        {!struck && tier === 4 && <path d={`M0 ${rig.masts[1].y * l + 2}l-5 20l5 -5l5 5Z`} fill={family === 'pirate' ? BG : tone} stroke={family === 'pirate' ? INK : undefined} strokeWidth={1} />}
      </g>
    </g>
  )
}

/** Her colours, streaming astern of `y` (bow up): each family's own cut. */
function Colours({ family, tone, y }: { family: ShipFamily; tone: string; y: number }) {
  if (family === 'pirate') {
    // a black flag, swallow-tailed, a bone cross on it
    return (
      <g data-ship-flag="pirate">
        <path d={`M-9 ${y}L9 ${y}L9 ${y + 22}L0 ${y + 15}L-9 ${y + 22}Z`} fill={BG} stroke={tone} strokeWidth={1.5} strokeLinejoin="round" />
        <path d={`M-5 ${y + 3}L5 ${y + 12}M5 ${y + 3}L-5 ${y + 12}`} stroke={INK} strokeWidth={2} strokeLinecap="round" />
      </g>
    )
  }
  if (family === 'navy') {
    // an ensign: a square flag in her side's colour, a pale cross through it
    return (
      <g data-ship-flag="navy">
        <rect x={-10} y={y} width={20} height={18} fill={tone} />
        <path d={`M0 ${y}L0 ${y + 18}M-10 ${y + 9}L10 ${y + 9}`} stroke={INK} strokeWidth={2.4} />
      </g>
    )
  }
  if (family === 'yours') {
    // a long pennant
    return <path data-ship-flag="yours" d={`M-5 ${y}L5 ${y}L0 ${y + 34}Z`} fill="var(--color-accent)" stroke={tone} strokeWidth={1.2} strokeLinejoin="round" />
  }
  // a merchant's and a cargo ship's: the swallow-tail the stage has always flown
  return <path data-ship-flag={family} d={`M0 ${y}L-6 ${y + 20}L0 ${y + 16}L6 ${y + 20}Z`} fill={tone} />
}

/** One ship as a small picture, bow to the right: the Codex key's tile, and (2026-11-23, the visual overhaul's slice 5) a fleet's and a ship's
 *  picture on the Fleets tab, where `tone` is her outline in the meaning her row already carries. */
export function ShipArtIcon({ family, tier, width = 72, tone, fit = false }: { family: ShipFamily; tier: ShipTier; width?: number; tone?: string; fit?: boolean }) {
  // `fit`: the frame drawn round HER length (the Fleets tab's pictures), so a sloop fills her plate as a flagship does; the key keeps one frame
  // for every tier, where the difference in length is the point.
  const k = fit ? LENGTH[tier - 1] : 1
  const box = fit ? `${-96 * k} ${-48 * k} ${192 * k} ${96 * k}` : '-110 -66 220 132'
  return (
    <svg width={width} height={width * (fit ? 0.5 : 0.6)} viewBox={box} aria-hidden data-testid="ship-art" data-family={family} data-tier={tier}>
      <ShipArt family={family} tier={tier} tone={tone} />
    </svg>
  )
}
