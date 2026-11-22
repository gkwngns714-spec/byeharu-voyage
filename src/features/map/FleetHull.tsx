import { hullTierOf, shipRig, type FleetOnChart, type ShipTier } from '../../chart'

// A FLEET OF YOURS, AS HER FLAGSHIP'S OUTLINE (2026-11-23, docs/design/visual-overhaul-2026-11-23.md slice 4: "your fleets
// are hull silhouettes"). The Map's lists — the Fleets corner and the harbour's Port tab — led each of your fleets with the
// same small anchor or sail glyph; now each wears her flagship seen from the beam, in brass: her hull and as many masts as
// her rig carries (src/chart/shipShapes.ts `shipRig`, the rule the chart and the battle stage draw her by), at the tier her
// served class earns (src/chart/glyphs.ts `hullTierOf`). A row's mark is 24 px tall, where the chart's top-down hull is a
// sliver, so a list draws her side on. Nothing is decided here: a flagship whose class no snapshot has named is drawn as a
// sloop, the smallest claim. Decoration: the row's name says who.

const VIEW_W = 34
const VIEW_H = 24
/** Where her masts stand along her, by how many she has. */
const MAST_X: Readonly<Record<number, readonly number[]>> = { 1: [17], 2: [12.5, 21.5], 3: [9, 17, 25] }

/** Her outline, built once per tier. */
const outlines = new Map<ShipTier, { hull: string; sails: string; masts: string; pennant: string | null }>()
function outlineOf(tier: ShipTier) {
  let o = outlines.get(tier)
  if (o) return o
  const n = Math.min(3, shipRig('yours', tier).masts.length)
  const xs = MAST_X[n]
  // the hull: a raised stern (left), a sheer to a raked bow (right)
  const hull = 'M2 15.5L5.5 15.5L6 17H29.5L32.5 15L29 21.5H7.5Z'
  const tall = tier === 4 ? 14.5 : tier === 3 ? 13 : 12
  let sails = ''
  let masts = ''
  xs.forEach((x, i) => {
    const h = tall - (n > 1 && i === n - 1 ? 2 : 0) - (n === 3 && i === 0 ? 1.5 : 0)
    const top = 17 - h
    const w = n === 1 ? 5.5 : 4.2
    masts += `M${x - 0.5} 17V${top - 1.5}H${x + 0.5}V17Z`
    // a square sail, bellied: two courses on a big ship, one on a small
    sails += `M${x - w} ${top}Q${x} ${top + 1} ${x + w} ${top}L${x + w - 0.6} ${top + h * 0.5}Q${x} ${top + h * 0.5 + 1.2} ${x - w + 0.6} ${top + h * 0.5}Z`
    if (tier >= 2) {
      const t2 = top + h * 0.56
      sails += `M${x - w} ${t2}Q${x} ${t2 + 1} ${x + w} ${t2}L${x + w - 0.6} ${15.5}Q${x} ${16.5} ${x - w + 0.6} ${15.5}Z`
    }
  })
  const main = xs[Math.floor(xs.length / 2)]
  const pennant = tier === 4 ? `M${main + 0.5} ${17 - tall - 1.5}l5 1.2l-5 1.2Z` : null
  o = { hull, sails, masts, pennant }
  outlines.set(tier, o)
  return o
}

export function FleetHull({ fleet, height = 24 }: { fleet: FleetOnChart; height?: number }) {
  const tier = hullTierOf(fleet.fleet.hulls?.[0] ?? null) ?? 1
  const o = outlineOf(tier)
  return (
    <svg
      viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
      width={(height * VIEW_W) / VIEW_H}
      height={height}
      aria-hidden="true"
      className="shrink-0 text-accent"
      data-testid="map-fleet-hull"
      data-tier={tier}
    >
      <path d={o.masts} fill="currentColor" />
      <path d={o.sails} fill="currentColor" fillOpacity={0.55} />
      <path d={o.hull} fill="currentColor" />
      {o.pennant && <path d={o.pennant} fill="currentColor" />}
    </svg>
  )
}
