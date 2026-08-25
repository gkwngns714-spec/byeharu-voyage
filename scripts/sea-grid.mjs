// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA, AS A GRID — and the shortest way through it between any two harbours.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The first version of this generator asked one question of a pair of ports: does the straight
// line between them stay at sea? That is the wrong question, and it showed: Lisbon and Cádiz are
// 188 nm apart and had NO leg between them, because the straight line clips the Algarve. Ships
// went round Cape St Vincent and so should the game.
//
// So the sea is rasterised — the Natural Earth land polygons scan-filled into a 0.25° grid — and a
// route is an A* search over the WATER cells. The result is a path that rounds capes, follows
// coasts and threads gulfs by itself, with no passage authored for any of it. The distance is the
// length of that path, which is exactly what DESIGN §B.3 means by a leg that "MAY EXCEED the
// great-circle figure where the real route detours".
//
// ── WHAT IS STILL AUTHORED, AND WHY ─────────────────────────────────────────────────────────────
// A 0.25° cell is about 15 nm. The Sound is two miles wide, the Bosphorus half of one, and at this
// resolution they are simply land — as are the Malacca narrows, Bab-el-Mandeb, Hormuz and the
// St Lawrence above the estuary. Those are the CHANNELS below: short chains of mid-water points
// whose cells are forced open before the search runs. Each one is a real navigable strait, named,
// and the list is the whole of the game's "you may pass here" authority.
//
// There is deliberately NO Suez and NO Panama — not cut until 1869 and 1914 — so the Mediterranean
// reaches India round the Cape and the Atlantic reaches the Pacific round the Horn. Those are not
// special cases in the code; they are simply channels nobody opened, and the grid does the rest.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', 'data')

export const CELL_DEG = 0.25
export const COLS = Math.round(360 / CELL_DEG)   // 1440
export const ROWS = Math.round(180 / CELL_DEG)   // 720
const NM_PER_RAD = 3440.065
const rad = (d) => (d * Math.PI) / 180

/** Cell centre → lat/lon and back. Row 0 is the north pole end. */
export const cellLat = (row) => 90 - (row + 0.5) * CELL_DEG
export const cellLon = (col) => -180 + (col + 0.5) * CELL_DEG
export const rowOf = (lat) => Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
export const colOf = (lon) => ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS

export function gcNm(lat1, lon1, lat2, lon2) {
  const dLat = rad(lat2 - lat1)
  const dLon = rad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2
  return 2 * NM_PER_RAD * Math.asin(Math.min(1, Math.sqrt(a)))
}

// ── THE CHANNELS — the water the map is too coarse to draw ─────────────────────────────────────
export const CHANNELS = [
  { id: 'danish-straits', name: 'the Danish Straits', points: [[57.6, 10.6], [57.0, 11.3], [56.1, 12.6], [55.6, 12.9], [55.3, 13.5], [55.2, 15.0]] },
  { id: 'turkish-straits', name: 'the Dardanelles and the Bosphorus', points: [[39.9, 25.8], [40.1, 26.2], [40.4, 26.8], [40.7, 28.2], [41.0, 29.0], [41.3, 29.3], [41.6, 30.0]] },
  { id: 'kerch', name: 'the Strait of Kerch', points: [[44.8, 36.4], [45.1, 36.5], [45.4, 36.7]] },
  { id: 'bab-el-mandeb', name: 'the Bab-el-Mandeb', points: [[12.3, 44.0], [12.6, 43.4], [13.2, 42.9], [15.0, 41.5], [17.5, 40.0], [20.0, 38.5], [24.0, 36.0], [27.0, 34.5]] },
  // Without this spur, Suez's nearest raster water is the MEDITERRANEAN, 72 nm north across the
  // isthmus — measured 2026-08-23, when suez->alexandria routed at 261 nm: a Suez Canal, three
  // centuries early. The gulf is 12-17 nm wide, under this raster's resolution, so it is a channel
  // like every other narrow water; the isthmus itself stays land and the two seas stay unjoined.
  { id: 'gulf-of-suez', name: 'the Gulf of Suez', points: [[27.0, 34.5], [27.8, 33.8], [28.5, 33.3], [29.2, 32.9], [29.9, 32.6]] },
  { id: 'hormuz', name: 'the Strait of Hormuz', points: [[24.8, 57.4], [25.8, 56.8], [26.3, 56.5], [26.4, 55.5], [26.4, 54.5], [27.2, 52.0], [28.6, 49.9], [29.6, 48.9], [30.0, 48.6]] },
  { id: 'khambhat', name: 'the Gulf of Khambhat', points: [[20.6, 71.8], [21.0, 72.0], [21.4, 72.3]] },
  { id: 'hooghly', name: 'the Hooghly approach', points: [[20.5, 88.3], [21.2, 88.2], [21.8, 88.1], [22.4, 88.2], [22.9, 88.4]] },
  { id: 'malacca', name: 'the Strait of Malacca', points: [[6.0, 95.6], [5.8, 96.0], [5.4, 96.8], [4.8, 98.0], [4.2, 98.8], [3.0, 100.5], [2.0, 102.0], [1.5, 103.0], [1.3, 103.6], [1.2, 104.3], [1.2, 104.8]] },
  { id: 'sunda', name: 'the Sunda Strait', points: [[-5.2, 105.8], [-5.7, 105.7], [-6.0, 105.6], [-6.4, 105.4], [-7.0, 105.2]] },
  { id: 'seto', name: 'the Kii and Bungo channels', points: [[32.9, 132.4], [33.3, 132.2], [33.7, 132.5], [34.0, 133.0], [34.3, 133.8], [34.5, 134.6], [34.3, 135.0], [33.8, 135.2]] },
  { id: 'white-sea', name: 'the Gorlo of the White Sea', points: [[68.8, 41.5], [67.8, 41.2], [66.8, 41.0], [66.0, 40.4], [65.6, 39.8], [64.9, 39.8]] },
  { id: 'saint-lawrence', name: 'the River of Saint Lawrence', points: [[49.2, -64.5], [49.0, -65.5], [48.8, -66.5], [48.6, -67.6], [48.3, -68.8], [47.9, -69.6], [47.4, -70.2], [46.9, -70.9], [46.8, -71.2]] },
  { id: 'gironde', name: 'the Gironde and the Loire', points: [[45.6, -1.3], [45.4, -1.0], [45.0, -0.7], [44.9, -0.6], [47.2, -2.4], [47.3, -2.1], [47.2, -1.7]] },
  { id: 'thames-scheldt', name: 'the Thames and the Scheldt', points: [[51.5, 1.4], [51.5, 0.8], [51.5, 0.2], [51.5, -0.1], [51.6, 3.4], [51.4, 3.6], [51.3, 4.0], [51.2, 4.4]] },
  // Without this, Bristol's nearest raster water is LYME BAY — 64.8 nm away, on the far side of
  // Devon, in the English Channel (measured 2026-08-25; DEV_LOG D22 logged the same 65 nm snap and
  // flagged the fix for this worktree). The Severn estuary narrows below one cell above Barry, so
  // the whole Bristol Channel east of 4°W scan-fills as land and John Cabot's home port answers
  // the wrong sea from the wrong side of a peninsula. The water is real and was sailed: square
  // riggers worked the channel to King Road and warped seven miles up the Avon to the quay.
  { id: 'severn', name: 'the Bristol Channel and the Avon', points: [[51.4, -4.1], [51.4, -3.6], [51.4, -3.1], [51.5, -2.8], [51.5, -2.7], [51.45, -2.6]] },
  { id: 'elbe-weser', name: 'the Elbe and the Weser', points: [[54.0, 8.2], [53.9, 8.7], [53.7, 9.2], [53.5, 9.9], [53.5, 8.6], [53.2, 8.5]] },
  { id: 'guadalquivir', name: 'the Guadalquivir', points: [[36.8, -6.4], [37.0, -6.3], [37.2, -6.1], [37.4, -6.0]] },
  { id: 'pearl-river', name: 'the Pearl River', points: [[22.0, 114.0], [22.3, 113.8], [22.7, 113.6], [23.1, 113.3]] },
  { id: 'yangtze', name: 'the Yangtze and the Grand Canal mouth', points: [[31.2, 122.4], [31.4, 121.9], [31.5, 121.3], [32.0, 120.4]] },
  { id: 'irrawaddy-sittaung', name: 'the Yangon and Chao Phraya rivers', points: [[16.3, 96.3], [16.6, 96.2], [16.8, 96.2], [13.3, 100.6], [13.6, 100.6], [14.4, 100.6]] },
  { id: 'shatt-al-arab', name: 'the Shatt al-Arab', points: [[29.9, 48.7], [30.2, 48.5], [30.5, 47.9]] },
  { id: 'rio-de-la-plata', name: 'the Río de la Plata', points: [[-35.5, -56.0], [-35.0, -57.0], [-34.7, -58.0], [-34.6, -58.4]] },
  { id: 'amazon-para', name: 'the Pará and the Amazon mouth', points: [[-0.5, -47.5], [-1.0, -48.0], [-1.4, -48.5]] },
  { id: 'gambia-senegal', name: 'the Gambia and Senegal mouths', points: [[13.5, -16.8], [13.4, -16.5], [16.0, -16.6], [16.0, -16.4]] },
  { id: 'baltic-gulfs', name: 'the Gulf of Finland and the Gulf of Riga', points: [[59.5, 22.0], [59.6, 23.5], [59.5, 24.8], [57.8, 22.5], [57.5, 23.5], [56.9, 24.0]] },
]

// ── THE ICE — the water the age of sail could never use ────────────────────────────────────────
// The inverse authority of CHANNELS: named waters CLOSED by hand. The raster models land, not
// pack ice, so without this the Arctic reads as open water and the router discovers the polar
// passages — the first thing the ocean-road pass found (2026-08-23) was Arkhangelsk — Nampo,
// 6,396 nm along the Siberian coast: the Northeast Passage, first actually sailed by
// Nordenskiöld in 1878-79. So these waters are ice, whatever the season:
//   * the Siberian arctic east of Novaya Zemlya — the Kara, Laptev, East Siberian and Chukchi seas;
//   * the Canadian arctic and northern Baffin Bay — the Northwest Passage, probed at its mouth by
//     Frobisher and Davis in the 1570s-80s and not forced until Amundsen in 1903-06;
//   * the Antarctic pack, south of 60°S, the whole way round — see that entry's own note.
// The Barents Sea and the White Sea road to Arkhangelsk stay open (the Muscovy Company sailed them
// from 1553), as do Svalbard's whaling grounds and the Davis Strait up to Nuuk.
//
// A closure names ONE parallel and the longitudes it spans. `latAbove` closes everything poleward
// of that parallel to the NORTH; `latBelow` everything poleward of it to the SOUTH. Exactly one of
// the two, so a closure always has a side. The southern form used to be a `cells.fill(0)` loop of
// its own inside scripts/build-sea-migration.mjs — the same concept said twice, in two files, one
// of them a generator, which is the second authority docs/NO_SPAGHETTI.md forbids. Since
// 2026-08-25 it is an ICE row like any other and the generator reads THIS list for both poles.
export const ICE = [
  { id: 'northeast-passage', name: 'the Siberian arctic', latAbove: 66.5, lonFrom: 60, lonTo: 180 },
  { id: 'northwest-passage', name: 'the Canadian arctic', latAbove: 66.5, lonFrom: -180, lonTo: -60 },
  // 60°S is where the period stops, and the dates are the argument, not the taste. The
  // southernmost land anyone had seen by the end of this game's century was South Georgia (54°S,
  // Antonio de la Roché, 1675); the South Shetlands at 62°S were not sighted until William Smith
  // in 1819, the Antarctic Circle not crossed until Cook in 1773, the continent itself not seen
  // until 1820. Everything the age of sail actually worked lies north of this line and stays open:
  // Cape Horn at 55.98°S and the Drake Passage under it — Veracruz→Acapulco and Buenos Aires→
  // Callao both round it through 55.63°S, measured 2026-08-25, unchanged by this closure; the
  // Roaring Forties and Furious Fifties of the Brouwer route, which Rio de Janeiro→Manila rides
  // at 43.9°S; and the sub-Antarctic sealing and whaling grounds about South Georgia. South of
  // 60°S is pack ice, and no hull in this world was built for it.
  { id: 'antarctic-pack', name: 'the Antarctic pack', latBelow: -60, lonFrom: -180, lonTo: 180 },
]

/** The row span an ICE closure covers, from the side it declares. Exactly one side, or it is not
 *  a closure — a row with neither (or both) would silently close the whole globe or nothing. */
export function iceRowFrom(ice) {
  assertOneSide(ice)
  return ice.latBelow === undefined ? 0 : rowOf(ice.latBelow)
}
export function iceRowTo(ice) {
  assertOneSide(ice)
  return ice.latAbove === undefined ? ROWS - 1 : rowOf(ice.latAbove)
}
function assertOneSide(ice) {
  const north = ice.latAbove !== undefined
  const south = ice.latBelow !== undefined
  if (north === south) {
    throw new Error(`ICE "${ice.id}" must declare exactly one of latAbove / latBelow — it has ${north ? 'both' : 'neither'}`)
  }
}

/** Is this cell inside an authored ice closure? The ONE reading of "closed by hand, not by land",
 *  so a generator can tell an ice cell from a land cell without re-deriving the rule. */
export function inIce(lat, lon) {
  const row = rowOf(lat)
  for (const ice of ICE) {
    if (row < iceRowFrom(ice) || row > iceRowTo(ice)) continue
    if (lon >= ice.lonFrom && lon <= ice.lonTo) return ice
  }
  return null
}

// ── the land, scan-filled into the grid ───────────────────────────────────────────────────────
function landPolygons() {
  const fc = JSON.parse(readFileSync(join(DATA, 'world-110m.json'), 'utf8'))
  const polys = []
  for (const f of fc.features) {
    const g = f.geometry
    if (!g) continue
    if (g.type === 'Polygon') polys.push(g.coordinates)
    else if (g.type === 'MultiPolygon') for (const p of g.coordinates) polys.push(p)
  }
  return polys
}

/**
 * THE GRID. One byte per cell: 1 = water, 0 = land.
 * Built by scan-filling each land polygon with the even-odd rule, so holes (the Caspian, inland
 * seas) come out as water without a second pass.
 */
export function buildSeaGrid() {
  const water = new Uint8Array(COLS * ROWS).fill(1)
  for (const rings of landPolygons()) {
    // Row range this polygon can touch.
    let minLat = 90, maxLat = -90
    for (const ring of rings) for (const [, lat] of ring) {
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    }
    const rowFrom = rowOf(maxLat)
    const rowTo = rowOf(minLat)
    for (let row = rowFrom; row <= rowTo; row++) {
      const lat = cellLat(row)
      const xs = []
      for (const ring of rings) {
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          const [x1, y1] = ring[j]
          const [x2, y2] = ring[i]
          if (y1 > lat !== y2 > lat) xs.push(x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1))
        }
      }
      if (xs.length < 2) continue
      xs.sort((a, b) => a - b)
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const from = colOf(xs[k])
        const to = colOf(xs[k + 1])
        const span = to >= from ? to - from : COLS - from + to
        for (let s = 0; s <= span; s++) water[row * COLS + ((from + s) % COLS)] = 0
      }
    }
  }

  // The ice: authored CLOSED water (see ICE above) — the waters the period could not force, at
  // BOTH poles through the one list. `latAbove` runs from the north edge down to that parallel;
  // `latBelow` runs from that parallel down to the south edge.
  for (const ice of ICE) {
    for (let row = iceRowFrom(ice); row <= iceRowTo(ice); row++) {
      for (let col = 0; col < COLS; col++) {
        const lon = cellLon(col)
        if (lon >= ice.lonFrom && lon <= ice.lonTo) water[row * COLS + col] = 0
      }
    }
  }

  // The channels: force their cells — and the cells between consecutive points — open.
  for (const ch of CHANNELS) {
    for (let i = 0; i < ch.points.length; i++) {
      openCell(water, ch.points[i][0], ch.points[i][1])
      if (i + 1 < ch.points.length) {
        const [la, lo] = ch.points[i]
        const [lb, lb2] = ch.points[i + 1]
        const steps = Math.ceil(gcNm(la, lo, lb, lb2) / 5)
        for (let s = 1; s < steps; s++) {
          openCell(water, la + ((lb - la) * s) / steps, lo + ((lb2 - lo) * s) / steps)
        }
      }
    }
  }
  return water
}

function openCell(water, lat, lon) {
  water[rowOf(lat) * COLS + colOf(lon)] = 1
}

export const isWater = (water, row, col) => water[row * COLS + ((col % COLS) + COLS) % COLS] === 1

/** The nearest water cell to a coordinate, searched outward. Harbours sit ON the coastline, so a
 *  port's own cell is often land at this resolution; that is expected, not an error. */
export function snapToWater(water, lat, lon, maxRings = 8) {
  const r0 = rowOf(lat)
  const c0 = colOf(lon)
  if (isWater(water, r0, c0)) return { row: r0, col: c0, ringsOut: 0 }
  for (let ring = 1; ring <= maxRings; ring++) {
    for (let dr = -ring; dr <= ring; dr++) {
      for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
        const row = r0 + dr
        if (row < 0 || row >= ROWS) continue
        const col = ((c0 + dc) % COLS + COLS) % COLS
        if (isWater(water, row, col)) return { row, col, ringsOut: ring }
      }
    }
  }
  return null
}

// ── A*, over water cells ──────────────────────────────────────────────────────────────────────
const NEIGHBOURS = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]

/**
 * The shortest navigable path between two coordinates, or null if there is none.
 * Returns { nm, path } where path is the simplified polyline (lat/lon pairs) including both ends.
 *
 * The heuristic is the great circle to the goal, which never overestimates, so the first path A*
 * settles on is the shortest one the grid allows.
 */
export function findSeaRoute(water, from, to, opts = {}) {
  const limitNm = opts.limitNm ?? Infinity
  const a = snapToWater(water, from.lat, from.lon)
  const b = snapToWater(water, to.lat, to.lon)
  if (!a || !b) return null
  const start = a.row * COLS + a.col
  const goal = b.row * COLS + b.col
  if (start === goal) {
    const nm = gcNm(from.lat, from.lon, to.lat, to.lon)
    return { nm, path: [[from.lat, from.lon], [to.lat, to.lon]] }
  }

  const goalLat = cellLat(b.row)
  const goalLon = cellLon(b.col)
  const g = new Map([[start, 0]])
  const cameFrom = new Map()
  const open = [[gcNm(cellLat(a.row), cellLon(a.col), goalLat, goalLon), start]]
  const closed = new Set()

  const pop = () => {
    // Binary heap would be tidier; a linear scan over a few thousand entries is fast enough and
    // this runs offline. Kept simple on purpose.
    let bestI = 0
    for (let i = 1; i < open.length; i++) if (open[i][0] < open[bestI][0]) bestI = i
    const [, node] = open[bestI]
    open[bestI] = open[open.length - 1]
    open.pop()
    return node
  }

  while (open.length > 0) {
    const current = pop()
    if (closed.has(current)) continue
    closed.add(current)
    if (current === goal) break
    const row = Math.floor(current / COLS)
    const col = current % COLS
    const lat = cellLat(row)
    const lon = cellLon(col)
    const cost = g.get(current)
    if (cost > limitNm) continue
    for (const [dr, dc] of NEIGHBOURS) {
      const nrow = row + dr
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = ((col + dc) % COLS + COLS) % COLS
      if (!isWater(water, nrow, ncol)) continue
      const next = nrow * COLS + ncol
      if (closed.has(next)) continue
      const step = gcNm(lat, lon, cellLat(nrow), cellLon(ncol))
      const tentative = cost + step
      if (tentative >= (g.get(next) ?? Infinity)) continue
      g.set(next, tentative)
      cameFrom.set(next, current)
      open.push([tentative + gcNm(cellLat(nrow), cellLon(ncol), goalLat, goalLon), next])
    }
  }

  if (!g.has(goal)) return null

  // Walk the path back, then straighten it: the grid's 45° staircase is an artefact of the raster,
  // not of the sea. Line-of-sight simplification replaces runs of cells with the straight leg a
  // ship would actually sail, as long as that straight leg stays in water.
  const cells = []
  for (let node = goal; node !== undefined; node = cameFrom.get(node)) {
    cells.push(node)
    if (node === start) break
  }
  cells.reverse()
  const points = [[from.lat, from.lon], ...cells.map((n) => [cellLat(Math.floor(n / COLS)), cellLon(n % COLS)]), [to.lat, to.lon]]
  const simplified = straighten(water, points)
  let nm = 0
  for (let i = 0; i + 1 < simplified.length; i++) {
    nm += gcNm(simplified[i][0], simplified[i][1], simplified[i + 1][0], simplified[i + 1][1])
  }
  return { nm, path: simplified }
}

/** Is every cell along this straight segment water? The ends are exempt: a harbour is on land. */
function segmentInWater(water, [lat1, lon1], [lat2, lon2], exemptEnds) {
  const nm = gcNm(lat1, lon1, lat2, lon2)
  const steps = Math.max(2, Math.ceil(nm / 8))
  for (let s = 1; s < steps; s++) {
    const f = s / steps
    // Straight in lat/lon is close enough over the short spans this is used on, and it never
    // wraps: the pathfinder's own points are always within a cell or two of each other.
    if (Math.abs(lon2 - lon1) > 180) return false
    const lat = lat1 + (lat2 - lat1) * f
    const lon = lon1 + (lon2 - lon1) * f
    if (exemptEnds && (f * nm < 25 || (1 - f) * nm < 25)) continue
    if (!isWater(water, rowOf(lat), colOf(lon))) return false
  }
  return true
}

function straighten(water, points) {
  const out = [points[0]]
  let i = 0
  while (i < points.length - 1) {
    let j = points.length - 1
    for (; j > i + 1; j--) {
      if (segmentInWater(water, points[i], points[j], i === 0 || j === points.length - 1)) break
    }
    out.push(points[j])
    i = j
  }
  return out
}
