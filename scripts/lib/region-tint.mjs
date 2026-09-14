// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REGIONS' TINT — which region each country and each cell of water belongs to, DERIVED.
// The pure builder; scripts/build-region-tint.mjs writes data/region-tint.json from it, and
// tests/map.regions.spec.ts rebuilds it and demands the committed file is byte-identical.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-14 (OWNER_REQUESTS row 92): *"i told you to create regions on map, show it
// using different color of the sea and country, make filter so that i can choose to apply color,
// or return to the current state."*
//
// ── THE FOUR DECISIONS (NO_SPAGHETTI §7B), ANSWERED BEFORE THE CODE ────────────────────────────
//
// 1. WHAT CONCEPT? — "which of the 25 regions a piece of the map belongs to": a country, or a
//    cell of water. ONE partition on screen, the REGIONS of data/regions.json — never a third one
//    beside the seas and the regions (row 59's warning).
//
// 2. WHERE DOES IT LIVE, AND WHY? — a DERIVED file, data/region-tint.json, because the water the
//    game sails is the server's `public.sea_cells` raster (0040: *every water answers its sea*;
//    patched by 0052 and 0079), which is server-private and reachable by no client read. The
//    raster's bytes are in the chain itself — 720 base64 rows in 0040 and the rows the two
//    patches replace — so this builder replays exactly those writes and never re-rasterises: the
//    water the tint covers is the water the game rules by, cell for cell, or the spec fails.
//    The rules a region is chosen by are stated once, below, and read nothing but data/*.json.
//
// 3. WHO IS THE SECOND CALLER? — src/chart/regions.ts reads the file (the only reader); the spec
//    rebuilds it (the only checker). A future "which region is this fleet in" would be a SERVER
//    read composed on voyage.sea_at and ports.region_code — never this file, which is a picture.
//
// 4. WHAT WOULD MAKE IT THE WRONG SHAPE? — a second answer to "which water is this" (a Voronoi
//    over data/seas.json's centroids, which the file itself says are unsurveyed label anchors; a
//    hand-drawn set of blobs). The spec holds the water cells to the chain's bytes.
//
// ── THE RULES, STATED ONCE ─────────────────────────────────────────────────────────────────────
//   country → region   the region most of the country's harbours (data/ports.json) belong to;
//                      ties broken by the region that comes first in data/regions.json. A
//                      country with no harbour has no region and is not tinted. A country split
//                      across regions (the build prints them) is tinted by its majority — v1,
//                      and said so in docs/DEV_LOG.md.
//   water → region     the region of the harbour each water cell is NEAREST TO BY WATER (the
//                      search is described at the code). MEASURED AND REJECTED first: "each sea
//                      takes the region most of its harbours belong to" — on the North Atlantic
//                      that is a three-way tie (atlantic-isles 6, iberia 6, north-america 6)
//                      decided by file order, and it paints the whole Mediterranean one region
//                      while four regions' harbours stand on its shore. The build still prints
//                      that table so the rejection stays a measurement.
//   a region's name    data/regions.json's `name`, anchored at the mean of its harbours' served
//                      coordinates — where the region's shore is, which is where it reads.
//
// ── THE SHAPE OF THE WATER ─────────────────────────────────────────────────────────────────────
// Per region, a list of axis-aligned rectangles of 0.25° cells `[col, row, w, h]` — each row's
// runs, then runs with identical extents on consecutive rows merged vertically. Rectangles, not
// traced polygons, because two neighbouring regions simplified separately would leave slivers
// and cracks between them; rectangles from one grid tile exactly. Painted with
// `shape-rendering: crispEdges` so the tile seams do not show.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

export const COLS = 1440
export const ROWS = 720
export const CELL_DEG = 0.25

/** Replay every write to public.sea_cells in the chain, in order: the raster the game rules by. */
export function replaySeaCells(migrationsDir) {
  const grid = new Uint8Array(ROWS * COLS)
  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()
  const writes = []
  for (const file of files) {
    const sql = readFileSync(join(migrationsDir, file), 'utf8')
    if (!sql.includes('public.sea_cells')) continue
    let n = 0
    // 0040: insert into public.sea_cells (row_idx, seas) values (r, decode('…', 'base64')), …
    const insertRe = /\((\d+), decode\('([A-Za-z0-9+/=]+)', 'base64'\)\)/g
    let m
    while ((m = insertRe.exec(sql))) {
      grid.set(Buffer.from(m[2], 'base64'), Number(m[1]) * COLS)
      n++
    }
    // 0052, 0079: update public.sea_cells set seas = decode('…', 'base64') where row_idx = r;
    const updateRe = /update public\.sea_cells set seas = decode\('([A-Za-z0-9+/=]+)', 'base64'\) where row_idx = (\d+);/g
    while ((m = updateRe.exec(sql))) {
      grid.set(Buffer.from(m[1], 'base64'), Number(m[2]) * COLS)
      n++
    }
    if (n > 0) writes.push({ file, rows: n })
  }
  return { grid, writes }
}

/** ordinal → sea id, read off 0040's own `update public.seas set raster_ordinal = N … where name = '…'`. */
export function readSeaOrdinals(migrationsDir, seas) {
  const file = readdirSync(migrationsDir).find((f) => f.includes('000040_'))
  const sql = readFileSync(join(migrationsDir, file), 'utf8')
  const byName = new Map(seas.map((s) => [s.name, s.id]))
  const re = /update public\.seas set raster_ordinal = (\d+), [^;]*? where name = '((?:[^']|'')*)';/g
  const out = new Map()
  let m
  while ((m = re.exec(sql))) {
    const name = m[2].replace(/''/g, "'")
    const id = byName.get(name)
    if (!id) throw new Error(`0040 names a sea data/seas.json lacks: ${name}`)
    out.set(Number(m[1]), id)
  }
  return out
}

/** The region most of `items` belong to; ties to the earliest region in `order`. */
function majority(items, order) {
  const count = new Map()
  for (const r of items) count.set(r, (count.get(r) ?? 0) + 1)
  let best = null
  for (const r of order) {
    const c = count.get(r) ?? 0
    if (c > 0 && (best === null || c > count.get(best))) best = r
  }
  return { region: best, counts: [...count].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])) }
}

/** Rectangles of one value over the grid: row runs, then vertical merge of identical runs. */
function rectanglesOf(cellRegion, regionIndex) {
  const open = new Map() // key "c0:w" → rect being extended
  const done = []
  for (let r = 0; r < ROWS; r++) {
    const rowRuns = new Map()
    let c = 0
    while (c < COLS) {
      if (cellRegion[r * COLS + c] !== regionIndex) {
        c++
        continue
      }
      const c0 = c
      while (c < COLS && cellRegion[r * COLS + c] === regionIndex) c++
      rowRuns.set(`${c0}:${c - c0}`, [c0, c - c0])
    }
    // Close every open rect this row does not continue; extend the ones it does; open the rest.
    for (const [key, rect] of open) {
      if (rowRuns.has(key)) {
        rect[3]++
        rowRuns.delete(key)
      } else {
        done.push(rect)
        open.delete(key)
      }
    }
    for (const [key, [c0, w]] of rowRuns) open.set(key, [c0, r, w, 1])
  }
  for (const rect of open.values()) done.push(rect)
  done.sort((a, b) => a[1] - b[1] || a[0] - b[0])
  return done
}

/**
 * Build the whole file's content from the repo's data and chain. `root` is the repo root.
 * Returns `{ file, report }` — `file` is what data/region-tint.json holds, `report` the tables
 * the build prints (and the log keeps).
 */
export function buildRegionTint(root) {
  const data = join(root, 'data')
  const migrations = join(root, 'supabase', 'migrations')
  const ports = JSON.parse(readFileSync(join(data, 'ports.json'), 'utf8')).ports
  const regions = JSON.parse(readFileSync(join(data, 'regions.json'), 'utf8')).regions
  const seas = JSON.parse(readFileSync(join(data, 'seas.json'), 'utf8')).seas
  const regionOrder = regions.map((r) => r.id)
  const regionIds = new Set(regionOrder)
  for (const p of ports) {
    if (!regionIds.has(p.region)) throw new Error(`port ${p.id} names a region data/regions.json lacks: ${p.region}`)
  }

  // country → region
  const byCountry = new Map()
  for (const p of ports) (byCountry.get(p.country) ?? byCountry.set(p.country, []).get(p.country)).push(p.region)
  const countries = {}
  const splitCountries = []
  for (const [iso, list] of [...byCountry].sort((a, b) => a[0].localeCompare(b[0]))) {
    const { region, counts } = majority(list, regionOrder)
    countries[iso] = region
    if (counts.length > 1) splitCountries.push({ iso, region, counts })
  }

  // sea → region — MEASURED and NOT used for the water (kept as a report, see the header): on the
  // North Atlantic it is a three-way tie decided by file order, which is no decision at all.
  const bySea = new Map()
  for (const p of ports) (bySea.get(p.sea) ?? bySea.set(p.sea, []).get(p.sea)).push(p.region)
  const seaMajority = []
  for (const s of seas) {
    const list = bySea.get(s.id)
    if (!list) continue
    const { region, counts } = majority(list, regionOrder)
    if (counts.length > 1) seaMajority.push({ sea: s.id, region, counts })
  }

  // THE WATER: every navigable cell of the chain's raster takes the region of the harbour it is
  // nearest to BY WATER — a multi-source breadth-first search from every harbour's water cell,
  // 8-connected, columns wrapping at the antimeridian, rows not. The same method 0040 attaches
  // NE-named water it does not model to a sea, and for the same reason: a seam found by water
  // cannot leak across an isthmus, and where two regions meet mid-ocean the seam is where no
  // player can see it. Ties (two harbours at the same distance) go to the harbour that comes
  // first in data/ports.json, so the file is deterministic.
  const { grid, writes } = replaySeaCells(migrations)
  const ordinals = readSeaOrdinals(migrations, seas)
  let waterCells = 0
  for (let i = 0; i < grid.length; i++) {
    if (grid[i] === 0) continue
    waterCells++
    if (ordinals.get(grid[i]) === undefined) throw new Error(`sea_cells holds ordinal ${grid[i]} that 0040 never named`)
  }
  const cellRegion = new Int16Array(ROWS * COLS).fill(-1)
  const queue = new Int32Array(ROWS * COLS)
  let head = 0
  let tail = 0
  const unseeded = []
  for (const p of ports) {
    // The harbour's own cell when it is water; else the nearest water cell within 8 rings (0040
    // proves every port resolves within 8), nearest ring first, then the earliest cell in scan
    // order within a ring.
    const r0 = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - p.lat) / CELL_DEG)))
    const c0 = ((Math.floor((p.lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
    let seed = -1
    for (let ring = 0; ring <= 8 && seed < 0; ring++) {
      for (let dr = -ring; dr <= ring && seed < 0; dr++) {
        for (let dc = -ring; dc <= ring; dc++) {
          if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
          const r = r0 + dr
          if (r < 0 || r >= ROWS) continue
          const c = (((c0 + dc) % COLS) + COLS) % COLS
          const i = r * COLS + c
          if (grid[i] !== 0) {
            seed = i
            break
          }
        }
      }
    }
    if (seed < 0) {
      unseeded.push(p.id)
      continue
    }
    if (cellRegion[seed] >= 0) continue // an earlier harbour already holds this cell
    cellRegion[seed] = regionOrder.indexOf(p.region)
    queue[tail++] = seed
  }
  while (head < tail) {
    const i = queue[head++]
    const r = Math.floor(i / COLS)
    const c = i - r * COLS
    const region = cellRegion[i]
    for (let dr = -1; dr <= 1; dr++) {
      const rr = r + dr
      if (rr < 0 || rr >= ROWS) continue
      for (let dc = -1; dc <= 1; dc++) {
        if (dr === 0 && dc === 0) continue
        const cc = (c + dc + COLS) % COLS
        const j = rr * COLS + cc
        if (grid[j] === 0 || cellRegion[j] >= 0) continue
        cellRegion[j] = region
        queue[tail++] = j
      }
    }
  }
  let tintedCells = 0
  for (let i = 0; i < cellRegion.length; i++) if (cellRegion[i] >= 0) tintedCells++

  const water = {}
  let rectCount = 0
  regionOrder.forEach((id, index) => {
    const rects = rectanglesOf(cellRegion, index)
    if (rects.length > 0) {
      water[id] = rects
      rectCount += rects.length
    }
  })

  // Which regions touch on the water — what a palette has to keep apart (reported, not stored).
  const touching = new Set()
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const a = cellRegion[r * COLS + c]
      if (a < 0) continue
      const right = cellRegion[r * COLS + ((c + 1) % COLS)]
      const down = r + 1 < ROWS ? cellRegion[(r + 1) * COLS + c] : -1
      for (const b of [right, down]) {
        if (b >= 0 && b !== a) touching.add(a < b ? `${regionOrder[a]}|${regionOrder[b]}` : `${regionOrder[b]}|${regionOrder[a]}`)
      }
    }
  }

  // The names and where they are set.
  const regionRows = regions.map((r) => {
    const mine = ports.filter((p) => p.region === r.id)
    const lat = mine.reduce((s, p) => s + p.lat, 0) / mine.length
    const lon = mine.reduce((s, p) => s + p.lon, 0) / mine.length
    return { id: r.id, name: r.name, at: { lat: Math.round(lat * 100) / 100, lon: Math.round(lon * 100) / 100 }, harbours: mine.length }
  })

  const file = {
    $doc:
      'DERIVED — do not edit. Which region each country and each 0.25° cell of water belongs to, for the ' +
      'chart\'s regions tint (OWNER_REQUESTS row 92). Rebuilt by `node scripts/build-region-tint.mjs`; ' +
      'tests/map.regions.spec.ts fails if this file and the build disagree. The water is the chain\'s own ' +
      'public.sea_cells (0040, patched by 0052 and 0079) — never a Voronoi, never drawn by hand — ' +
      'each cell the region of the harbour nearest to it by water; the countries are keyed by Natural Earth ISO_A2_EH.',
    cellDeg: CELL_DEG,
    cols: COLS,
    rows: ROWS,
    regions: regionRows,
    countries,
    water,
  }
  const report = {
    writes, splitCountries, seaMajority, unseeded, waterCells, tintedCells, rectCount,
    countryCount: Object.keys(countries).length, touching: [...touching].sort(),
  }
  return { file, report }
}

/** The file's text, exactly as committed: one line per rectangle list keeps the diff readable. */
export function regionTintText(file) {
  return JSON.stringify(file, null, 1).replace(/\[\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+),\n\s+(-?\d+)\n\s+\]/g, '[$1,$2,$3,$4]') + '\n'
}
