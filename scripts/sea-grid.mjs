// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA, AS A GRID — the water itself, and the authored carve that opens it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The Natural Earth land polygons, scan-filled into a 0.25° grid: one byte per cell, 1 = a keel
// may be here. That is the whole of this module's subject.
//
// **IT NO LONGER ROUTES, AND IT NO LONGER SNAPS.** It used to carry an A* search and its own
// `snapToWater` — 8 rings, the first water cell in scan order — which made this a module with a
// SECOND answer to "where is the water nearest this point", differing from the one 0076 landed
// (`voyage.water_roadstead` in SQL, `snapToNav` on the client: 12 rings, the minimum-distance
// cell). Measured over all 224 harbours the two picked a different cell for 87 of them, the
// scan-order rule always the farther, worst +20.51 nm at Dublin. Its only caller was the spur-leg
// loop in `scripts/build-sea-places.mjs`, whose legs went into `public.legs` — a table 0049
// dropped — so on 2026-09-08 the router MOVED into that retired file rather than being folded or
// deleted. What is left here is one subject with one authority, and the guard that keeps it that
// way is a property, not a call count: this module declares no snap rule.
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
// Each entry declares `opensLand`: how many cells of DRY LAND its carve turns into sea, measured
// against `preCarveGrid()` — the scan-filled land data itself, before any channel runs.
// `assertCarveDeclared` refuses to build the raster when the world disagrees with the number, so a
// channel cannot quietly grow. The number is small for a real strait and large for a canal, but it
// is NOT a threshold and must not be read as one: sorted by it, the St Lawrence (22), the
// Thames-Scheldt (17) and the Gironde (15) are all bigger land carves than either half of the
// river pair that shipped the canal. The number exists to make someone LOOK, not to decide.
export const CHANNELS = [
  { id: 'danish-straits', name: 'the Danish Straits', points: [[57.6, 10.6], [57.0, 11.3], [56.1, 12.6], [55.6, 12.9], [55.3, 13.5], [55.2, 15.0]], opensLand: 8 },
  { id: 'turkish-straits', name: 'the Dardanelles and the Bosphorus', points: [[39.9, 25.8], [40.1, 26.2], [40.4, 26.8], [40.7, 28.2], [41.0, 29.0], [41.3, 29.3], [41.6, 30.0]], opensLand: 4 },
  { id: 'kerch', name: 'the Strait of Kerch', points: [[44.8, 36.4], [45.1, 36.5], [45.4, 36.7]], opensLand: 1 },
  { id: 'bab-el-mandeb', name: 'the Bab-el-Mandeb', points: [[12.3, 44.0], [12.6, 43.4], [13.2, 42.9], [15.0, 41.5], [17.5, 40.0], [20.0, 38.5], [24.0, 36.0], [27.0, 34.5]], opensLand: 2 },
  // Without this spur, Suez's nearest raster water is the MEDITERRANEAN, 72 nm north across the
  // isthmus — measured 2026-08-23, when suez->alexandria routed at 261 nm: a Suez Canal, three
  // centuries early. The gulf is 12-17 nm wide, under this raster's resolution, so it is a channel
  // like every other narrow water; the isthmus itself stays land and the two seas stay unjoined.
  { id: 'gulf-of-suez', name: 'the Gulf of Suez', points: [[27.0, 34.5], [27.8, 33.8], [28.5, 33.3], [29.2, 32.9], [29.9, 32.6]], opensLand: 12 },
  { id: 'hormuz', name: 'the Strait of Hormuz', points: [[24.8, 57.4], [25.8, 56.8], [26.3, 56.5], [26.4, 55.5], [26.4, 54.5], [27.2, 52.0], [28.6, 49.9], [29.6, 48.9], [30.0, 48.6]], opensLand: 3 },
  { id: 'khambhat', name: 'the Gulf of Khambhat', points: [[20.6, 71.8], [21.0, 72.0], [21.4, 72.3]], opensLand: 3 },
  { id: 'hooghly', name: 'the Hooghly approach', points: [[20.5, 88.3], [21.2, 88.2], [21.8, 88.1], [22.4, 88.2], [22.9, 88.4]], opensLand: 5 },
  { id: 'malacca', name: 'the Strait of Malacca', points: [[6.0, 95.6], [5.8, 96.0], [5.4, 96.8], [4.8, 98.0], [4.2, 98.8], [3.0, 100.5], [2.0, 102.0], [1.5, 103.0], [1.3, 103.6], [1.2, 104.3], [1.2, 104.8]], opensLand: 11 },
  { id: 'sunda', name: 'the Sunda Strait', points: [[-5.2, 105.8], [-5.7, 105.7], [-6.0, 105.6], [-6.4, 105.4], [-7.0, 105.2]], opensLand: 4 },
  { id: 'seto', name: 'the Kii and Bungo channels', points: [[32.9, 132.4], [33.3, 132.2], [33.7, 132.5], [34.0, 133.0], [34.3, 133.8], [34.5, 134.6], [34.3, 135.0], [33.8, 135.2]], opensLand: 9 },
  { id: 'white-sea', name: 'the Gorlo of the White Sea', points: [[68.8, 41.5], [67.8, 41.2], [66.8, 41.0], [66.0, 40.4], [65.6, 39.8], [64.9, 39.8]], opensLand: 6 },
  { id: 'saint-lawrence', name: 'the River of Saint Lawrence', points: [[49.2, -64.5], [49.0, -65.5], [48.8, -66.5], [48.6, -67.6], [48.3, -68.8], [47.9, -69.6], [47.4, -70.2], [46.9, -70.9], [46.8, -71.2]], opensLand: 22 },
  { id: 'gironde', name: 'the Gironde and the Loire', points: [[45.6, -1.3], [45.4, -1.0], [45.0, -0.7], [44.9, -0.6], [47.2, -2.4], [47.3, -2.1], [47.2, -1.7]], opensLand: 15 },
  { id: 'thames-scheldt', name: 'the Thames and the Scheldt', points: [[51.5, 1.4], [51.5, 0.8], [51.5, 0.2], [51.5, -0.1], [51.6, 3.4], [51.4, 3.6], [51.3, 4.0], [51.2, 4.4]], opensLand: 17 },
  // Without this, Bristol's nearest raster water is LYME BAY — 64.8 nm away, on the far side of
  // Devon, in the English Channel (measured 2026-08-25; DEV_LOG D22 logged the same 65 nm snap and
  // flagged the fix for this worktree). The Severn estuary narrows below one cell above Barry, so
  // the whole Bristol Channel east of 4°W scan-fills as land and John Cabot's home port answers
  // the wrong sea from the wrong side of a peninsula. The water is real and was sailed: square
  // riggers worked the channel to King Road and warped seven miles up the Avon to the quay.
  { id: 'severn', name: 'the Bristol Channel and the Avon', points: [[51.4, -4.1], [51.4, -3.6], [51.4, -3.1], [51.5, -2.8], [51.5, -2.7], [51.45, -2.6]], opensLand: 5 },
  { id: 'elbe-weser', name: 'the Elbe and the Weser', points: [[54.0, 8.2], [53.9, 8.7], [53.7, 9.2], [53.5, 9.9], [53.5, 8.6], [53.2, 8.5]], opensLand: 14 },
  { id: 'guadalquivir', name: 'the Guadalquivir', points: [[36.8, -6.4], [37.0, -6.3], [37.2, -6.1], [37.4, -6.0]], opensLand: 4 },
  { id: 'pearl-river', name: 'the Pearl River', points: [[22.0, 114.0], [22.3, 113.8], [22.7, 113.6], [23.1, 113.3]], opensLand: 6 },
  { id: 'yangtze', name: 'the Yangtze and the Grand Canal mouth', points: [[31.2, 122.4], [31.4, 121.9], [31.5, 121.3], [32.0, 120.4]], opensLand: 8 },
  // WAS ONE RECORD NAMING TWO RIVERS 330 nm APART, and the jump between them carved a canal
  // through the Tenasserim mountains — 309 real port pairs sold a route across the Malay
  // peninsula, worst Thanlyin -> Ayutthaya at 323 nm against 1,977 nm of real sea. A CHANNELS
  // entry's points must lie along ONE water, in order; these are two waters and are now two
  // records. docs/LAND_CARVE_RECON.md measured it; RECLAIMED below carries the consequence.
  { id: 'yangon', name: 'the Yangon river', points: [[16.3, 96.3], [16.6, 96.2], [16.8, 96.2]], opensLand: 3 },
  { id: 'chao-phraya', name: 'the Chao Phraya', points: [[13.3, 100.6], [13.6, 100.6], [14.4, 100.6]], opensLand: 4 },
  { id: 'shatt-al-arab', name: 'the Shatt al-Arab', points: [[29.9, 48.7], [30.2, 48.5], [30.5, 47.9]], opensLand: 5 },
  { id: 'rio-de-la-plata', name: 'the Río de la Plata', points: [[-35.5, -56.0], [-35.0, -57.0], [-34.7, -58.0], [-34.6, -58.4]], opensLand: 3 },
  { id: 'amazon-para', name: 'the Pará and the Amazon mouth', points: [[-0.5, -47.5], [-1.0, -48.0], [-1.4, -48.5]], opensLand: 5 },
  { id: 'gambia-senegal', name: 'the Gambia and Senegal mouths', points: [[13.5, -16.8], [13.4, -16.5], [16.0, -16.6], [16.0, -16.4]], opensLand: 14 },
  { id: 'baltic-gulfs', name: 'the Gulf of Finland and the Gulf of Riga', points: [[59.5, 22.0], [59.6, 23.5], [59.5, 24.8], [57.8, 22.5], [57.5, 23.5], [56.9, 24.0]], opensLand: 9 },
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

// ── THE RECLAIMED — land that a withdrawn carve had turned into water ─────────────────────────
// THE THIRD KIND OF DISAGREEMENT BETWEEN THE TWO RASTERS, and the reason it needs authoring.
//
// scripts/build-sea-migration.mjs cross-checks the navigable mask against 0040's sea-membership
// raster, and it already answers two of the three ways they can differ:
//
//   * the mask OPENS water 0040 never saw  -> healed, by joining the nearest named sea BY WATER.
//     A new water cell must have a name, and the rule for choosing one already exists.
//   * the mask CLOSES water 0040 names, inside an authored ICE closure -> allowed, and the name is
//     KEPT. Ice is still sea; it is sea nobody may sail. Membership is not the mask's business.
//
// The third way had no answer and threw, which is why the canal repair stopped on 2026-09-06 with
// "sea-membership on water this mask closes OUTSIDE every ICE closure (23 cell(s))". Those cells
// are not a drift and not ice: 0040 was cut from the CARVED grid, so it dutifully named cells that
// were only ever water because a malformed CHANNELS record said so. Withdraw the carve and they
// are land again — and land carries NO sea, so their membership must go to ZERO.
//
// That is the opposite action from ICE on the same fact, which is exactly why it is a separate
// authored list rather than a flag on that one. It is authored, and never inferred, for the reason
// the generator refuses in the first place: silently deleting sea membership is indistinguishable
// from a raster that has quietly lost an ocean. An entry states WHERE, WHY, and HOW MANY cells it
// expects to reclaim; the cells themselves are DERIVED from CHANNELS, so this list can never
// become a second opinion about where the water is.
export const RECLAIMED = [
  {
    id: 'tenasserim',
    name: 'the Tenasserim isthmus',
    why: "0040 was cut when 'irrawaddy-sittaung' still joined the Yangon river to the Chao Phraya, "
      + 'so it named the carved cells as sea. The record is now two records and the mountains are '
      + 'mountains again.',
    latFrom: 13.0, latTo: 17.0, lonFrom: 96.0, lonTo: 101.0,
    expect: 23,
  },
]

/** Is this cell inside an authored reclamation? The mirror of inIce: that one says "closed by hand
 *  and STILL sea", this one says "closed by hand and NOT sea any more". Same shape on purpose, so
 *  a generator reads both the same way and neither re-derives where the water is. */
export function inReclaimed(lat, lon) {
  for (const r of RECLAIMED) {
    if (lat >= r.latFrom && lat <= r.latTo && lon >= r.lonFrom && lon <= r.lonTo) return r
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
 * THE LAND DATA, AS THE GRID SEES IT — scan-fill plus ICE, and NO carve.
 *
 * This is the thing a carve has to be justified against, and until 2026-09-08 nothing in the repo
 * could ask for it: `buildSeaGrid` applied the channels before returning, so by the time anyone
 * held a raster the answer to "was this cell land?" had already been overwritten. That is why
 * `tests/seaCarve.spec.ts` reconstructed its "pre-channel land" by closing every carved cell in
 * the FINISHED raster — which makes every carved cell read as land and turns the count it pins
 * into the carve's own size. See `carveInventory` below for what that cost.
 *
 * One byte per cell: 1 = water, 0 = land. Built by scan-filling each land polygon with the
 * even-odd rule, so holes (the Caspian, inland seas) come out as water without a second pass.
 */
export function preCarveGrid() {
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
  return water
}

/** The cells one channel opens: its own points, and the cells BETWEEN consecutive points. That
 *  "between" is the whole defect surface — it is what let one record naming two rivers 330 nm
 *  apart cut a canal through the Tenasserim mountains. */
function channelCells(ch) {
  const cells = new Set()
  for (let i = 0; i < ch.points.length; i++) {
    const [la, lo] = ch.points[i]
    cells.add(rowOf(la) * COLS + colOf(lo))
    if (i + 1 < ch.points.length) {
      const [lb, lb2] = ch.points[i + 1]
      const steps = Math.ceil(gcNm(la, lo, lb, lb2) / 5)
      for (let s = 1; s < steps; s++) {
        cells.add(rowOf(la + ((lb - la) * s) / steps) * COLS + colOf(lo + ((lb2 - lo) * s) / steps))
      }
    }
  }
  return cells
}

/**
 * THE CARVE, MEASURED AGAINST THE LAND IT OVERWRITES, BY THE ACT OF OVERWRITING IT.
 *
 * Every channel is counted against `pre` — the grid BEFORE any channel ran — and never against the
 * partly-carved grid, because channels share cells (the Bab-el-Mandeb and the Gulf of Suez meet at
 * 27.0N 34.5E) and a running total would hand the shared cell to whichever entry the list happens
 * to reach first. Counted this way the numbers are order-independent, and they are not a
 * re-derivation of the carve: they are what the carve actually did.
 *
 * WHAT THIS ANSWERS, AND WHY IT IS A DIFFERENT NUMBER FROM THE ONE THE REPO USED TO QUOTE. The
 * carve opens 521 cells and always did; of those, **202 are dry land** and the rest were already
 * water — a channel exists to join water the raster is too coarse to draw, so most of its cells
 * are water it merely re-states. Only the land half is a claim about the world. Measured
 * 2026-09-08, and the ranking is not the ranking the old figure gave:
 *
 *   * `bab-el-mandeb` carves 84 cells — the largest carve in the list — and opens **2** of land.
 *   * `hormuz` carves 48 and opens **3**. `malacca` carves 52 and opens **11**.
 *   * `saint-lawrence` carves 33 and opens **22**, which is the largest land carve there is.
 *   * The canal, as shipped, carved 37 and opened **30** — FIRST by a wide margin on this measure,
 *     and only fifth on the old one. The guard that would have caught it is this one.
 */
export function carveInventory() {
  const pre = preCarveGrid()
  const water = Uint8Array.from(pre)
  const opened = new Map()
  for (const ch of CHANNELS) {
    let land = 0
    for (const k of channelCells(ch)) {
      if (pre[k] === 0) land++
      water[k] = 1
    }
    opened.set(ch.id, land)
  }
  return { water, pre, opened }
}

/**
 * THE REFUSAL. A carve that opens land the list does not declare is not emitted.
 *
 * `docs/LAND_CARVE_RECON.md` §5 says why this has to live on the generator side: a course over a
 * carved canal is water by the raster's own account, so every SQL guard passes it and always
 * would. The raster is the thing that is wrong, and only the data it was built FROM can say so.
 *
 * It is the shape RECLAIMED already uses — an authored claim, refused when the world disagrees —
 * and it is deliberately NOT a threshold. No threshold separates a strait from a canal: sorted by
 * land opened, the St Lawrence (22), the Thames-Scheldt (17) and the Gironde (15) all sit above
 * what the canal's two halves open today. A person has to look. What this guarantees is that a
 * person HAS looked at every number in the list, and that the raster cannot be built until they do.
 */
export function assertCarveDeclared(opened) {
  const wrong = []
  for (const ch of CHANNELS) {
    if (typeof ch.opensLand !== 'number') {
      wrong.push(`${ch.id}: declares no opensLand`)
      continue
    }
    const got = opened.get(ch.id)
    if (got !== ch.opensLand) wrong.push(`${ch.id}: opens ${got} cells of land, declares ${ch.opensLand}`)
  }
  if (wrong.length) {
    throw new Error(
      'THE CARVE OPENS LAND IT DOES NOT DECLARE — refusing to build the raster.\n  '
      + wrong.join('\n  ')
      + '\n\nEach CHANNELS entry declares `opensLand`: how many cells of DRY LAND it turns into sea,'
      + '\nmeasured against the scan-filled land data (scripts/sea-grid.mjs preCarveGrid). If you'
      + '\nmoved a point on purpose, LOOK at the new water on a map before you change the number —'
      + '\nthat look is the entire guard. docs/LAND_CARVE_RECON.md §5.',
    )
  }
}

/**
 * THE GRID the game sails on: the land data, with the declared carve opened into it.
 *
 * The refusal is here rather than in each generator on purpose — five generators build this raster
 * (`build-sea-migration`, `build-sea-raster`, `build-sea-places`, `gen-0047`, and the specs), and a
 * guard wired into five callers is a guard four of them can forget. The raster cannot be built with
 * an undeclared carve at all.
 */
export function buildSeaGrid() {
  const { water, opened } = carveInventory()
  assertCarveDeclared(opened)
  return water
}
