// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LANDFALL — a harbour's mark is set on the DRAWN shore, never in the drawn water. PURE.
//
// The owner, 2026-09-14 (OWNER_REQUESTS row 92): *"some cities are in the ocean, not on land
// such as istanbul. I want you to fix it."*
//
// ── WHAT WAS MEASURED (tests/map.landfall.spec.ts prints the table; docs/DEV_LOG.md keeps it) ──
// Every harbour's coordinate is the city's real one (Wikidata P625, WORLD_DATA.md) and every
// city is on land in reality. The chart draws Natural Earth's 110m countries, decimated at 0.2°
// (./coastlineBuild.ts), and at 110m the Bosporus does not exist, the Golden Horn does not exist,
// and a harbour that stands on a river mouth, a spit or a tidal flat can fall a few miles
// outside the polygon the file gives its coast. So a mark drawn at the true coordinate lands in
// drawn water — not because the data is wrong, but because two true things are true at two
// resolutions. The tell that this is the diagnosis and not a data error is the DISTANCE: every
// such harbour lies within a few nautical miles of the drawn shore.
//
// ── §7B, ANSWERED FIRST ────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: WHERE A HARBOUR'S MARK IS SET ON THIS CHART — the served coordinate
//              when the drawn land holds it, otherwise the nearest point of the drawn shore, a
//              hair inside it. A DISPLAY rule about a picture, with a hard cap (`LANDFALL_CAP_NM`)
//              past which a harbour is not "a city the coast file is too coarse for" but an
//              ISLAND THE FILE HAS NO POLYGON FOR — and then the mark stays where the data put it
//              and a speck of land (an islet, GLYPH.isletRadius) is drawn under it, because the
//              alternative, moving Rhodes onto Anatolia, is a lie at the scale a chart is read.
// WHERE        src/chart — it is a fact about the drawn coast, which only the chart holds, and it
//              needs `CoastlineData.rings`, which only the chart builds. Applied ONCE, in
//              ./useBackdrop.ts, the moment the coast arrives, so the mark, the name, the tap
//              target (./hitTest.ts), the roadstead's dotted line (./roadsteads.ts) and a docked
//              fleet's glyph all read ONE moved coordinate off `MapPort` and can never disagree.
// SECOND CALLER  the Map tab and `SmallChart` both go through `useBackdrop`; the spec calls this
//              function directly over the real file. The minimap draws no port marks.
// THE CAP      10 nm, MEASURED: over the real file the widest gap between a mainland harbour's
//              true coordinate and its drawn shore is 8.6 nm (Tripoli 8.58, Matsumae 8.50,
//              Corfu 8.31, Istanbul 7.06), and the nearest an island-with-no-polygon harbour
//              comes to someone else's shore is 14.3 nm (Rhodes, to Anatolia). The cap sits in
//              that gap. At 15 nm Rhodes would have been moved onto Turkey.
// WRONG SHAPE  a nudge applied in PortsLayer alone — the label would then float beside water,
//              the tap would land where the mark is not, and the roadstead line would start at a
//              point nothing is drawn at. Or: replacing the 110m file with a finer coast, under
//              roadstead rings (0076, 0085) and a nav grid (0038) that were all derived from the
//              110m land — the rings would then draw on land. Measured and rejected in the log.
//
// ── 2026-11-14: THE COAST IN HAND ─────────────────────────────────────────────────────────────
// Close in, the chart draws a finer coast from tiles (./fineCoastBuild.ts), and a mark set on the
// 110m shore then stood miles from the shore on the glass (Tainan 8 nm inland, Ceuta 2.5 nm out
// to sea). The rule did not change, its INPUT did: the landfall is run against THE COAST THAT IS
// DRAWN (`ShoreInHand`), by ./useChartShore.ts, in the same render that coast is handed to the
// picture. Against a fine coast a harbour standing INLAND within the cap is brought to the shore
// as well (`fromLand`): a real shore has a real quay, and Lübeck belongs on it. Against the 110m
// world it is not, exactly as before: that shore is a guess 12 nm wide. Beyond the cap either
// way the mark stays where the data put it: Seville, London and Hanoi are river cities.
//
// ── WHAT IT DOES NOT TOUCH ─────────────────────────────────────────────────────────────────────
// `ports.lat/lon` on the server: sailing, the roadsteads, the sea membership and every distance
// are computed there, from the served coordinate, and this file cannot reach any of them. The
// moved point lives on the chart's OWN read model (`MapPort`), whose header says it is the shape
// of a view. `MapPort.roadstead` (served) is not moved: the roads are a fact about the raster.
// A SEA_PLACE is never moved: it is water by definition and its lozenge says so.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { haversineNm, project, unproject, type Point } from '../lib/geo'
import type { CoastlineData } from './coastlineBuild'
import type { MapPort } from './mapTypes'

/**
 * How far a harbour may be moved onto the drawn shore, in nautical miles — see THE CAP in the
 * header: 10 sits between the widest coarseness gap measured (8.6 nm) and the nearest island
 * the file lacks (14.3 nm). Beyond it the mark stays where the data put it and wears an islet.
 */
export const LANDFALL_CAP_NM = 10

/** How far INSIDE the shore the moved mark is set, in chart units (degrees): a hair, so the
 *  mark reads as standing on the shore and the point is unambiguously land for `onDrawnLand`. */
export const LANDFALL_INSET_DEG = 0.005

/**
 * Is this chart point on the drawn land? Even-odd over every body ring, which is exactly the rule
 * the body is filled with (`fill-rule="evenodd"`, CoastlineLayer.tsx): a lake is water, an
 * island in a lake is land. A point exactly on an edge is undefined here, as it is for the fill;
 * `landfallPoint` sets its answer strictly inside so the question never arises.
 */
export function onDrawnLand(rings: readonly (readonly Point[])[], p: Point): boolean {
  let inside = false
  for (const ring of rings) {
    const n = ring.length
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const a = ring[i]
      const b = ring[j]
      if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) inside = !inside
    }
  }
  return inside
}

/** How one landfall is run: against which kind of coast. The 110m world needs neither. */
export interface LandfallRule {
  /** An edge of a ring that is NOT a shore: where a tile of the fine coast was cut. Never landed on. */
  readonly isCut?: (a: Point, b: Point) => boolean
  /** Bring a harbour that stands on drawn land to the shore too, when the shore is within the cap. */
  readonly fromLand?: boolean
}

/** The nearest point of any drawn ring's edge to `p`, in chart units, with the segment's direction. */
function nearestShore(
  rings: readonly (readonly Point[])[],
  p: Point,
  isCut?: (a: Point, b: Point) => boolean,
): { at: Point; dir: Point } | null {
  let best: { at: Point; dir: Point } | null = null
  let bestD2 = Infinity
  for (const ring of rings) {
    const n = ring.length
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const a = ring[j]
      const b = ring[i]
      if (isCut && isCut(a, b)) continue
      const dx = b.x - a.x
      const dy = b.y - a.y
      const len2 = dx * dx + dy * dy
      const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
      const q = { x: a.x + t * dx, y: a.y + t * dy }
      const d2 = (q.x - p.x) ** 2 + (q.y - p.y) ** 2
      if (d2 < bestD2) {
        bestD2 = d2
        best = { at: q, dir: { x: dx, y: dy } }
      }
    }
  }
  return best
}

/** What the landfall decided for one point — the moved point and how far it moved. */
export interface LandfallResult {
  /** Where the mark is set: the served point when it is on drawn land, else the shore. */
  readonly at: Point
  /** Nautical miles from the served point to the shore point; 0 when nothing moved. */
  readonly nm: number
  /** True when the served point was in drawn water and a shore inside the cap was found. */
  readonly moved: boolean
  /** True when the served point was in drawn water and NO shore inside the cap was found: an
   *  island the file has no polygon for (measured: every one of the 28 is). The mark is left
   *  where the data put it and an islet is drawn under it. */
  readonly stranded: boolean
}

/**
 * ONE point's landfall. Pure geometry over the drawn rings: on land → unchanged; in water and a
 * shore within `LANDFALL_CAP_NM` → the nearest shore point, set `LANDFALL_INSET_DEG` inside it
 * (tried along the approach, then either side of the edge, and the first that `onDrawnLand`
 * confirms is taken); in water with no shore in reach → unchanged and `stranded`.
 * With `rule.fromLand` a point ON land is brought to the shore by the same steps when the shore
 * is within the cap; beyond it (a river city) it is unchanged, and never `stranded`.
 */
export function landfallPoint(rings: readonly (readonly Point[])[], p: Point, rule: LandfallRule = {}): LandfallResult {
  if (rings.length === 0) return { at: p, nm: 0, moved: false, stranded: false }
  const onLand = onDrawnLand(rings, p)
  if (onLand && !rule.fromLand) return { at: p, nm: 0, moved: false, stranded: false }
  const shore = nearestShore(rings, p, rule.isCut)
  if (!shore) return { at: p, nm: 0, moved: false, stranded: !onLand }
  const nm = haversineNm(unproject(p), unproject(shore.at))
  if (nm > LANDFALL_CAP_NM) return { at: p, nm, moved: false, stranded: !onLand }
  // Already standing on the shore, to within the hair a moved mark is set inside it.
  if (onLand && Math.hypot(shore.at.x - p.x, shore.at.y - p.y) <= LANDFALL_INSET_DEG) return { at: p, nm, moved: false, stranded: false }

  // Candidates a hair past the shore point: straight on from the water (which is inland for any
  // shore that faces the harbour), then the two normals of the edge.
  const along = { x: shore.at.x - p.x, y: shore.at.y - p.y }
  const alongLen = Math.hypot(along.x, along.y) || 1
  const edgeLen = Math.hypot(shore.dir.x, shore.dir.y) || 1
  const normal = { x: -shore.dir.y / edgeLen, y: shore.dir.x / edgeLen }
  const candidates: Point[] = [
    { x: shore.at.x + (along.x / alongLen) * LANDFALL_INSET_DEG, y: shore.at.y + (along.y / alongLen) * LANDFALL_INSET_DEG },
    { x: shore.at.x + normal.x * LANDFALL_INSET_DEG, y: shore.at.y + normal.y * LANDFALL_INSET_DEG },
    { x: shore.at.x - normal.x * LANDFALL_INSET_DEG, y: shore.at.y - normal.y * LANDFALL_INSET_DEG },
  ]
  for (const c of candidates) {
    if (onDrawnLand(rings, c)) return { at: c, nm, moved: true, stranded: false }
  }
  return { at: p, nm, moved: false, stranded: !onLand }
}

/** What the landfall makes of a port table. */
export interface Landfall {
  /** Every port, HARBOURS in drawn water moved onto the drawn shore; the same list object when
   *  nothing moved, so memoised consumers do not re-render. */
  readonly ports: readonly MapPort[]
  /** The stranded harbours' chart points — islands the coast file has no polygon for. A speck
   *  of land is drawn under each (CoastlineLayer); the mark stays where the data put it. */
  readonly islets: readonly Point[]
}

const NO_ISLETS: readonly Point[] = []

/**
 * THE COAST IN HAND, when it is not the whole world at once: the fine coast is tiles, and only
 * the ones under the sheet are held (./useChartShore.ts builds this from them).
 */
export interface ShoreInHand extends LandfallRule {
  /** The drawn rings a landfall at `p` reads (every ring within the cap of it), or null when this
   *  coast does not hold `p` at all: it is off the sheet, and is set by the world coast instead. */
  readonly ringsNear: (p: Point) => readonly (readonly Point[])[] | null
}

/**
 * THE PORT TABLE, SET ON THE DRAWN SHORE. Every HARBOUR whose served coordinate falls in drawn
 * water is returned with `lat`/`lon` moved by `landfallPoint`; a harbour with no shore inside
 * the cap is returned as it came and listed in `islets`; everything else is returned as it
 * came. With no coast yet (`null`) the list is returned untouched — the marks are drawn at the
 * served coordinate until the shore arrives, and move onto it in the same frame the shore does.
 *
 * `coast` is the coast in hand: the 110m world's rings, or a `ShoreInHand` (the fine tiles). A
 * harbour a `ShoreInHand` does not hold is taken from `elsewhere`, the SAME table already set on
 * the world coast (same order), with its islet if it wears one; so off the sheet nothing moves.
 */
export function landfallPorts(
  ports: readonly MapPort[],
  coast: Pick<CoastlineData, 'rings'> | ShoreInHand | null,
  elsewhere?: Landfall,
): Landfall {
  if (!coast) return { ports, islets: NO_ISLETS }
  const shore: ShoreInHand = 'ringsNear' in coast ? coast : { ringsNear: () => coast.rings }
  if (!('ringsNear' in coast) && coast.rings.length === 0) return { ports, islets: NO_ISLETS }
  let changed = false
  const islets: Point[] = []
  const out = ports.map((port, index) => {
    if (port.kind !== 'HARBOUR') return port
    const at = project(port)
    const rings = shore.ringsNear(at)
    if (!rings) {
      const other = elsewhere?.ports[index]
      if (!other || other.code !== port.code) return port
      if (elsewhere.islets.some((i) => i.x === at.x && i.y === at.y)) islets.push(at)
      if (other !== port) changed = true
      return other
    }
    const result = landfallPoint(rings, at, shore)
    if (result.stranded) islets.push(at)
    if (!result.moved) return port
    changed = true
    const moved = unproject(result.at)
    return { ...port, lat: moved.lat, lon: moved.lon }
  })
  return { ports: changed ? out : ports, islets: islets.length > 0 ? islets : NO_ISLETS }
}
