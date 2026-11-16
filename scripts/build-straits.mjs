#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-straits.mjs — THE REAL STRAITS ARE OPEN (owner row 352, 0446)
//
//   node scripts/build-straits.mjs <world-image at the head before.tar.gz> [--prod prod-courses.json]
//
// 0440 and 0441 took every course off the drawn land. Two of the things they ended (a course over land
// the raster cannot see, and a course over raster land within 25 nm of a harbour) had been standing in
// for real straits the raster closes. With them gone, Messina to Zakynthos went round Sicily (291 nm to
// 630), Jakarta to Surabaya round Madura, Lubeck to Bergen by the Sound, Banten to Lingga east of Bangka.
// This is scripts/build-land-channels.mjs run again for the channels charted since (scripts/sea-grid.mjs:
// messina, great-belt, bangka, surabaya), as docs/NAVIGATION_PLAN.md section 8 says to:
//
//   1. THE CHARTED CHANNELS. Their cells open in public.sea_raster, take the sea of the water next to
//      them in public.sea_cells, and are listed in voyage.channels. Their drawn land stays land in the
//      coast mask (public/coast/mask.json, re-cut here) and in the audit; a `fairway` channel's own line
//      is water in the mask (scripts/build-coast-mask.mjs).
//   2. THE ROADSTEADS. A harbour whose quay is now nearest a charted cell lies on that channel
//      (voyage.water_roadstead's own rule; Messina, which lay 14 nm off in the Tyrrhenian). One that the
//      rule then puts on drawn land or in a pocket moves as 0440 moved them (voyage.drawn_roadsteads).
//   3. THE COURSES. Every stored course (the image's and production's) that ends at a moved roadstead or
//      crosses drawn land is re-sailed, as 0440 did. AND every stored course that a newly opened strait
//      shortens (the same search and re-sailing, now through the strait, is shorter by more than
//      SHORTER_NM and SHORTER_PCT) takes the shorter course: a lane 0440 sent round Sicily goes back
//      through the strait. Matched by md5(course::text); frozen cargo and patrol legs re-cut.
//
// Writes PART A of supabase/migrations/20260818000446_*.sql (the pair table and the quoted distances are
// PART B, appended by scripts/build-sea-legs-migration.mjs --append), public/coast/mask.json, and the prod
// checks and the forward rollback under scripts/ops/harness/straits/. Reads a world image (no prod load).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { openImage, readWorldCourses, newestImage, truthLand, crossingsOf } from './db/audit-land-crossings.mjs'
import { buildCoastMask, MASK_FILE } from './build-coast-mask.mjs'
import { buildSeaCarve, CHANNELS, COLS, ROWS, cellLat, cellLon, rowOf, colOf } from './sea-grid.mjs'
import { drawnLand, gcNm } from './lib/drawn-land.mjs'
import { navFromServed, findPath, segmentIsWater } from '../src/lib/sea/index.ts'
import { refineCourse, courseIsWater, FINE_PER_DEG } from '../src/lib/sea/refine.ts'
import { coastMaskFrom, coastLand } from '../src/lib/sea/coastMask.ts'
import { migrationSql, PART_B_MARK } from './straits.sql.mjs'
import { STRAIT_PASSES } from './straits.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const MIGRATION_NAME = '20260818000446_the_real_straits_are_open.sql'
const MIGRATION = path.join(ROOT, 'supabase', 'migrations', MIGRATION_NAME)
const HARNESS = path.join(ROOT, 'scripts', 'ops', 'harness', 'straits')
const md5 = (s) => createHash('md5').update(s).digest('hex')
const jsonbText = (course) => `[${course.map(([a, b]) => `[${a}, ${b}]`).join(', ')}]`
const r3 = (x) => Math.round(x * 1000) / 1000
const key = (lat, lon) => `${Number(lat)},${Number(lon)}`

/** A roadstead moves no further than this from where the raster rule put it: a player's stored
 *  route still begins within course_join_nm (15 nm) of the new point. */
const MAX_MOVE_NM = 12
/** The box searched round a roadstead for the open sea, in degrees of latitude either side. */
const BOX_DEG = 0.6
/** A stored course takes the course through a newly opened strait when that is shorter by more than
 *  both of these: the strait is the reason, not the search's noise. */
const SHORTER_NM = 15
const SHORTER_PCT = 0.03

// node scripts/build-straits.mjs <image> [--prod courses.json] — the image is the chain BEFORE this
// migration; --prod adds every course production holds (scripts/ops/harness/no-land/prod-courses.sql, read
// only), so the migration re-sails prod's own rows, which no image has (0203 copied prod's merchant loops
// into the lanes when it was applied; players' routes live only there).
const argv = process.argv.slice(2)
const flagValue = (f) => (argv.indexOf(f) >= 0 ? argv[argv.indexOf(f) + 1] : null)
const prodFile = flagValue('--prod')
const file = argv.find((a, i) => !a.startsWith('--') && argv[i - 1] !== '--prod') ?? (await newestImage())
console.log(`straits: world image ${path.basename(file)}${prodFile ? `, and prod's courses from ${path.basename(prodFile)}` : ''}`)
const db = await openImage(file)
const world = await readWorldCourses(db)
const joinNm = Number((await db.query(`select public.wc_num('course_join_nm')::float8 as v`)).rows[0].v)
const portRows = (
  await db.query(`select p.code, p.lat::text as lat_t, p.lon::text as lon_t, p.lat::float8 as lat, p.lon::float8 as lon,
                         sr.roadstead_lat::float8 as rlat, sr.roadstead_lon::float8 as rlon, sr.snap_nm::float8 as snap, sr.snap_nm::text as snap_t
                    from public.ports p join public.sea_reaches sr on sr.port_id = p.id order by p.code`)
).rows
const probe = (await db.query(`select '[[1.5,-2.25],[3,4.125]]'::jsonb::text as t`)).rows[0].t
if (probe !== jsonbText([[1.5, -2.25], [3, 4.125]])) throw new Error(`jsonb text rule: ${probe}`)

// ── 1. THE RASTER: the served one, and the charted channels opened into it ────────────────────────
const oldNav = navFromServed(world.raster)
const { water: newWater, pre, carved } = buildSeaCarve()
const charted = CHANNELS.filter((c) => c.charted)
const chartedCells = new Map() // cell -> channel id (cells of dry land a charted channel opens)
for (const ch of charted) for (const k of carved.get(ch.id)) chartedCells.set(k, ch.id)
const opened = []
for (let k = 0; k < COLS * ROWS; k++) {
  const was = oldNav.cells[k] !== 0
  const now = newWater[k] !== 0
  if (was && !now) throw new Error(`the raster would CLOSE cell ${k}: this slice only opens charted channels`)
  if (!was && now) {
    if (!chartedCells.has(k)) throw new Error(`cell ${k} opens but no charted channel opened it: the served raster is not buildSeaGrid() less the charted channels`)
    opened.push(k)
  }
}
const bytes = Buffer.from(world.raster.cells_base64.replace(/\s+/g, ''), 'base64')
const bits = world.raster.bits_per_cell
for (const k of opened) {
  const b = k * bits
  bytes[b >> 3] |= 1 << (b & 7)
}
const newRaster = { ...world.raster, cells_base64: bytes.toString('base64') }
const nav = navFromServed(newRaster)
for (const k of opened) if (!nav.cells[k]) throw new Error(`cell ${k}: the packing rule is not the reader's`)
console.log(`  ${opened.length} cell(s) opened: ${opened.map((k) => `${chartedCells.get(k)}@${cellLat((k / COLS) | 0)},${cellLon(k % COLS)}`).join(' ')}`)

// Every channel charted BY THIS SLICE (it opens new cells) runs down drawn water: its polyline, sampled
// every 0.25 nm, is never on the chart's land. A strait carved long ago and now charted keeps its old
// line (voyage.channels holds it); a roadstead its line puts on the land is moved below like any other.
const fineLand = drawnLand('fine')
const opening = new Set(opened.map((k) => chartedCells.get(k)))
for (const ch of charted.filter((c) => opening.has(c.id))) {
  for (let i = 0; i + 1 < ch.points.length; i++) {
    const [a, b] = [ch.points[i], ch.points[i + 1]]
    const n = Math.max(1, Math.ceil(gcNm(a[0], a[1], b[0], b[1]) / 0.25))
    for (let s = 0; s <= n; s++) {
      const la = a[0] + ((b[0] - a[0]) * s) / n
      const lo = a[1] + ((b[1] - a[1]) * s) / n
      if (fineLand.isLand(la, lo)) throw new Error(`${ch.id}: its line touches drawn land at ${la.toFixed(4)},${lo.toFixed(4)}`)
    }
  }
}

// The seas of the opened cells (0040's public.sea_cells): each takes the sea of the nearest water
// cell that already has one, by water, as 0091 joined its opened cells.
const seaRows = new Map()
for (const r of [...new Set(opened.flatMap((k) => [-3, -2, -1, 0, 1, 2, 3].map((d) => ((k / COLS) | 0) + d)))]) {
  const row = (await db.query(`select encode(seas, 'base64') as b from public.sea_cells where row_idx = $1`, [r])).rows[0]
  if (row) seaRows.set(r, Buffer.from(row.b, 'base64'))
}
const seaOf = (k) => seaRows.get((k / COLS) | 0)?.[k % COLS] ?? 0
const seaPatch = []
for (const k of opened) {
  if (seaOf(k)) continue
  const seen = new Set([k])
  let frontier = [k]
  let found = 0
  while (frontier.length && !found) {
    const nextF = []
    for (const c of frontier) {
      const r = (c / COLS) | 0
      for (let dr = -1; dr <= 1 && !found; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          const n = (r + dr) * COLS + ((((c % COLS) + dc) % COLS) + COLS) % COLS
          if (seen.has(n) || !nav.cells[n]) continue
          seen.add(n)
          if (seaOf(n) && !opened.includes(n)) {
            found = seaOf(n)
            break
          }
          nextF.push(n)
        }
      }
    }
    frontier = nextF
  }
  if (!found) throw new Error(`opened cell ${k} joins no named sea by water`)
  seaPatch.push({ row: (k / COLS) | 0, col: k % COLS, sea: found, was: seaOf(k) })
}

// ── 2. THE MASK the course author steers by, cut for the new raster ──────────────────────────────
const maskPayload = buildCoastMask(newRaster, fineLand)
writeFileSync(MASK_FILE, JSON.stringify(maskPayload) + '\n')
const mask = coastMaskFrom(maskPayload)
const land = coastLand(mask, nav)
const truth = truthLand(nav, fineLand)
console.log(`  coast mask: ${Buffer.from(maskPayload.cells, 'base64').length / 4} cell(s) hold drawn land; raster ${maskPayload.raster.md5}`)

// ── 3. THE ROADSTEAD RULE on the new raster, asked of the database itself ────────────────────────
// The raster and the channels go in first (rolled back after), and voyage.water_roadstead answers
// every quay: a quay whose nearest water is now a charted channel's cell lies on that channel.
const channelRows = charted.filter((ch) => opening.has(ch.id)).map((ch) => ({ id: ch.id, name: ch.name, points: JSON.stringify(ch.points), cells: JSON.stringify(carved.get(ch.id)), n: ch.opensLand }))
await db.exec('begin')
await db.exec(`update public.sea_raster set cells = decode('${newRaster.cells_base64}', 'base64') where id = 1`)
for (const c of channelRows) {
  await db.query(`insert into voyage.channels (id, name, points, carved_cells, opens_land) values ($1, $2, $3::jsonb, $4::jsonb, $5)`, [c.id, c.name, c.points, c.cells, c.n])
}
const ruled = new Map(
  (
    await db.query(`select p.code, w.lat::float8 as lat, w.lon::float8 as lon, w.nm::float8 as nm, w.channel
                      from public.ports p join public.sea_reaches sr on sr.port_id = p.id
                     cross join lateral voyage.water_roadstead(p.lat, p.lon) w`)
  ).rows.map((r) => [r.code, r]),
)
await db.exec('rollback')
await db.close()

// ── 4. THE ROADS ON THE WATER ──────────────────────────────────────────────────────────────────
const G = FINE_PER_DEG
/** The course author's fine cell (refine.ts fineSearch): raster water at its centre and drawn water
 *  at all four of its quarter points. */
function passableAt(lat, lon) {
  const rr = Math.min(nav.rows - 1, Math.max(0, Math.floor((90 - lat) / nav.cellDeg)))
  const cc = ((Math.floor((lon + 180) / nav.cellDeg) % nav.cols) + nav.cols) % nav.cols
  if (!nav.cells[rr * nav.cols + cc]) return false
  const q = 1 / (4 * G)
  return !(land.blocked(lat + q, lon - q) || land.blocked(lat + q, lon + q) || land.blocked(lat - q, lon - q) || land.blocked(lat - q, lon + q))
}
/** The open sea round a point: the fine cells of the box, labelled; the sea is every component
 *  that reaches the box's edge (water that leads at least ${BOX_DEG} degrees away). A pocket (an
 *  inner harbour the 1.5-nm grid cannot leave) reaches no edge. */
function seaAround(lat0, lon0) {
  const north = Math.ceil((lat0 + BOX_DEG) * G) / G
  const south = Math.floor((lat0 - BOX_DEG) * G) / G
  const lonM = BOX_DEG / Math.max(0.2, Math.cos((lat0 * Math.PI) / 180))
  const west = Math.floor((lon0 - lonM) * G) / G
  const east = Math.ceil((lon0 + lonM) * G) / G
  const rows = Math.round((north - south) * G)
  const cols = Math.round((east - west) * G)
  const latOf = (r) => north - (r + 0.5) / G
  const lonOf = (c) => west + (c + 0.5) / G
  const pass = new Uint8Array(rows * cols)
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) pass[r * cols + c] = passableAt(latOf(r), lonOf(c)) ? 1 : 0
  const comp = new Int32Array(rows * cols).fill(-1)
  const sizes = []
  const edge = []
  for (let s = 0; s < rows * cols; s++) {
    if (!pass[s] || comp[s] >= 0) continue
    const id = sizes.length
    let size = 0
    let touches = false
    const stack = [s]
    comp[s] = id
    while (stack.length) {
      const k = stack.pop()
      size++
      const r = (k / cols) | 0
      const c = k - r * cols
      if (r === 0 || c === 0 || r === rows - 1 || c === cols - 1) touches = true
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          const nr = r + dr
          const nc = c + dc
          if (nr < 0 || nc < 0 || nr >= rows || nc >= cols) continue
          const n = nr * cols + nc
          if (pass[n] && comp[n] < 0) {
            comp[n] = id
            stack.push(n)
          }
        }
      }
    }
    sizes.push(size)
    edge.push(touches)
  }
  const seas = new Set()
  for (let id = 0; id < sizes.length; id++) if (edge[id]) seas.add(id)
  const cellOf = (lat, lon) => {
    const r = Math.floor((north - lat) * G)
    const c = Math.floor((lon - west) * G)
    return r < 0 || c < 0 || r >= rows || c >= cols ? -1 : r * cols + c
  }
  return { rows, cols, comp, seas, latOf, lonOf, cellOf, isSea: (k) => k >= 0 && seas.has(comp[k]), inSea: (lat, lon) => { const k = cellOf(lat, lon); return k >= 0 && seas.has(comp[k]) } }
}

/** The nearest point of open water to `target(lat, lon)` (a distance), with drawn water all round
 *  it (its eight fine neighbours in the sea) where there is one. */
function nearestWater(around, target) {
  let best = null
  let bestLoose = null
  for (let k = 0; k < around.comp.length; k++) {
    if (!around.isSea(k)) continue
    const r = (k / around.cols) | 0
    const c = k - r * around.cols
    const lat = r3(around.latOf(r))
    const lon = r3(around.lonOf(c))
    if (truth.blocked(lat, lon) || !around.inSea(lat, lon)) continue
    const d = target(lat, lon)
    if (!bestLoose || d < bestLoose.d) bestLoose = { lat, lon, d }
    let clear = r > 0 && c > 0 && r < around.rows - 1 && c < around.cols - 1
    for (let dr = -1; dr <= 1 && clear; dr++) for (let dc = -1; dc <= 1 && clear; dc++) if (!around.isSea((r + dr) * around.cols + c + dc)) clear = false
    if (clear && (!best || d < best.d)) best = { lat, lon, d }
  }
  return best ? { ...best, clear: true } : bestLoose ? { ...bestLoose, clear: false } : null
}

// Harbours that share one raster roadstead (Hormuz and Bandar Abbas) are moved together, to ONE
// point: a course that ends at the shared point is one text, matched by its md5, and must end at
// one new point. The point is the nearest to all their quays together (the least sum of miles).
const tooFar = []
const moves = [] // { code, lat_t, lon_t, from: {lat, lon}, to: {lat, lon, nm}, why }
const finalRoad = new Map() // code -> { lat, lon, nm }
const groups = new Map() // base point -> ports
for (const p of portRows) {
  const base = ruled.get(p.code)
  if (!base || base.lat == null) throw new Error(`${p.code}: voyage.water_roadstead answers no water`)
  const k = key(base.lat, base.lon)
  if (!groups.has(k)) groups.set(k, [])
  groups.get(k).push(p)
}
for (const ports of groups.values()) {
  const base = ruled.get(ports[0].code)
  const onLand = truth.blocked(base.lat, base.lon)
  const around = seaAround(base.lat, base.lon)
  if (!around.seas.size) throw new Error(`${ports.map((p) => p.code).join('/')}: no open sea within ${BOX_DEG} degrees of the roadstead`)
  const pocket = !onLand && !around.inSea(base.lat, base.lon)
  if (!onLand && !pocket) {
    for (const p of ports) finalRoad.set(p.code, { lat: ruled.get(p.code).lat, lon: ruled.get(p.code).lon, nm: ruled.get(p.code).nm, channel: ruled.get(p.code).channel })
    continue
  }
  let to = nearestWater(around, (lat, lon) => ports.reduce((s, p) => s + gcNm(p.lat, p.lon, lat, lon), 0))
  if (!to) throw new Error(`${ports.map((p) => p.code).join('/')}: no drawn water joined to the sea near the roadstead`)
  // A move longer than MAX_MOVE_NM would leave a stored route's first point out of course_join_nm:
  // then the nearest open water to the OLD roadstead is taken instead.
  if (gcNm(base.lat, base.lon, to.lat, to.lon) > MAX_MOVE_NM) to = nearestWater(around, (lat, lon) => gcNm(base.lat, base.lon, lat, lon))
  const moved = gcNm(base.lat, base.lon, to.lat, to.lon)
  if (moved > MAX_MOVE_NM) tooFar.push(`${ports.map((p) => p.code).join('/')} ${moved.toFixed(1)} nm`)
  for (const p of ports) {
    const nm = gcNm(p.lat, p.lon, to.lat, to.lon)
    moves.push({ code: p.code, lat_t: p.lat_t, lon_t: p.lon_t, quay: { lat: p.lat, lon: p.lon }, from: { lat: base.lat, lon: base.lon }, to: { lat: to.lat, lon: to.lon, nm }, moved, why: onLand ? 'land' : 'pocket', clear: to.clear })
    finalRoad.set(p.code, { lat: to.lat, lon: to.lon, nm, channel: null })
  }
}
moves.sort((a, b) => (a.code < b.code ? -1 : 1))
if (tooFar.length) throw new Error(`roadsteads that would move over ${MAX_MOVE_NM} nm: ${tooFar.join(', ')}`)
const changedRoads = portRows.filter((p) => {
  const f = finalRoad.get(p.code)
  return f.lat !== p.rlat || f.lon !== p.rlon
})
console.log(`  roadsteads: ${moves.length} moved onto the water (${moves.filter((m) => m.why === 'land').length} on drawn land, ${moves.filter((m) => m.why === 'pocket').length} in a pocket); ${changedRoads.length} differ from sea_reaches in all`)
for (const m of moves) console.log(`    ${m.code} ${m.why.padEnd(6)} ${m.from.lat},${m.from.lon} -> ${m.to.lat},${m.to.lon}  moved ${m.moved.toFixed(2)} nm, ${m.to.nm.toFixed(2)} nm off the quay${m.clear ? '' : ' (no clear ring)'}`)
for (const p of changedRoads) if (!moves.find((m) => m.code === p.code)) console.log(`    ${p.code} by the raster rule: ${p.rlat},${p.rlon} -> ${finalRoad.get(p.code).lat},${finalRoad.get(p.code).lon} (${finalRoad.get(p.code).channel ?? 'cell'})`)
const leftOnLand = portRows.filter((p) => truth.blocked(finalRoad.get(p.code).lat, finalRoad.get(p.code).lon)).map((p) => p.code)
if (leftOnLand.length) throw new Error(`roadsteads still on drawn land: ${leftOnLand.join(' ')}`)

// The old point of each changed roadstead, and its new one. Roadsteads are not unique: two harbours
// that shared one old point must share the new one, or a course text cannot be mapped.
const pointMap = new Map()
for (const p of changedRoads) {
  const k = key(p.rlat, p.rlon)
  const to = finalRoad.get(p.code)
  const had = pointMap.get(k)
  if (had && (had.lat !== to.lat || had.lon !== to.lon)) throw new Error(`${p.code}: its old roadstead ${k} is shared with a harbour that moves elsewhere`)
  pointMap.set(k, { lat: to.lat, lon: to.lon })
}
for (const p of portRows) {
  if (changedRoads.includes(p)) continue
  if (pointMap.has(key(p.rlat, p.rlon))) throw new Error(`${p.code}: shares the old roadstead ${key(p.rlat, p.rlon)} with a harbour that moves`)
}

// ── 5. THE COURSES ─────────────────────────────────────────────────────────────────────────────
const texts = new Map()
for (const c of world.npc) texts.set(c.text, c.course)
for (const r of world.routes) texts.set(r.text, r.course)
for (const c of world.coast) texts.set(c.text, c.course)
let prod = null
if (prodFile) {
  prod = Object.values(JSON.parse(readFileSync(prodFile, 'utf8')).rows[0])[0]
  // prod must stand where the image stands: the same raster and the same roadsteads, or its courses mean other things
  if (prod.raster_md5 !== md5(world.raster.cells_base64.replace(/\s+/g, ''))) throw new Error('prod serves another raster than the image')
  for (const [code, lat, lon] of prod.roads) {
    const p = portRows.find((x) => x.code === code)
    if (!p || p.rlat !== Number(lat) || p.rlon !== Number(lon)) throw new Error(`prod's roadstead of ${code} is not the image's`)
  }
  for (const [, , text] of [...prod.npc, ...prod.coast]) texts.set(text, JSON.parse(text))
  for (const [, , text] of prod.stops) texts.set(text, JSON.parse(text))
}
/** Postgres's text of a course read backwards, from its own text (each point's numbers kept as written). */
const reversedText = (text) => `[${(text.match(/\[[^[\]]+\]/g) ?? []).reverse().join(', ')}]`
const len = (c) => c.reduce((s, p, i) => (i ? s + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : s), 0)
const landNm = (c) => crossingsOf(truth, c).reduce((s, x) => s + x.nm, 0)
const fixes = []
let before = 0
let after = 0
let fresh = 0
let addNm = 0
let baseNm = 0
const still = []
let shortened = 0
// THROUGH A NEWLY OPENED STRAIT: the course author's own course between the two ends (the search, then the
// re-sailing), when it runs through a cell this slice opens, is clean, and is shorter than `than` by more
// than SHORTER_NM and SHORTER_PCT. Null otherwise.
const openedSet = new Set(opened)
const throughOpened = (c) => {
  for (let i = 0; i + 1 < c.length; i++) {
    const [p, q] = [c[i], c[i + 1]]
    if (Math.abs(q[1] - p[1]) > 180) continue
    const n = Math.max(1, Math.ceil(gcNm(p[0], p[1], q[0], q[1]) / 2))
    for (let t = 0; t <= n; t++) if (openedSet.has(rowOf(p[0] + ((q[0] - p[0]) * t) / n) * COLS + colOf(p[1] + ((q[1] - p[1]) * t) / n))) return true
  }
  return false
}
const straitCourse = (start, end, than) => {
  const found = findPath(nav, { lat: start[0], lon: start[1] }, { lat: end[0], lon: end[1] })
  if (!found) return null
  const path = [start, ...found.path.slice(1, -1), end]
  const rr = refineCourse(nav, land, path)
  const pick = rr.changed ? rr.path : path
  if (!courseIsWater(nav, pick) || landNm(pick) > 0 || !throughOpened(pick)) return null
  return len(pick) < len(than) - Math.max(SHORTER_NM, len(than) * SHORTER_PCT) ? pick : null
}
// ONE GEOMETRY, ONE NEW COURSE. Prod holds the same course under more than one text (51.45 and 51.4500,
// a lane and its return written apart), and a frozen leg's pieces cannot tell them apart: every text of
// one line of points takes the same new course, and its reverse takes that course backwards.
const geomKey = (c) => c.map((p) => `${Number(p[0])},${Number(p[1])}`).join(';')
const sailed = new Map() // geometry -> the course it now sails
for (const [text, course] of texts) {
  const gk = geomKey(course)
  const rk = geomKey([...course].reverse())
  const again = sailed.get(gk) ?? (sailed.has(rk) ? [...sailed.get(rk)].reverse() : null)
  if (again) {
    if (crossingsOf(truth, course).length) before++
    const newText = jsonbText(again)
    if (newText !== text) fixes.push({ old: md5(text), course: newText, oldText: text })
    continue
  }
  const a = pointMap.get(key(course[0][0], course[0][1]))
  const b = pointMap.get(key(course[course.length - 1][0], course[course.length - 1][1]))
  const crossed = crossingsOf(truth, course).length > 0
  if (crossed) before++
  if (!a && !b && !crossed) {
    const through = straitCourse(course[0], course[course.length - 1], course)
    if (!through) {
      sailed.set(gk, course)
      continue
    }
    shortened++
    sailed.set(gk, through)
    addNm += len(through) - len(course)
    baseNm += len(course)
    fixes.push({ old: md5(text), course: jsonbText(through), oldText: text, strait: true })
    continue
  }
  const start = a ? [a.lat, a.lon] : course[0]
  const end = b ? [b.lat, b.lon] : course[course.length - 1]
  const ended = [start, ...course.slice(1, -1), end]
  const tries = []
  const r = refineCourse(nav, land, ended)
  tries.push(r.changed ? r.path : ended)
  if (!courseIsWater(nav, tries[0]) || landNm(tries[0]) > 0) {
    const found = findPath(nav, { lat: start[0], lon: start[1] }, { lat: end[0], lon: end[1] })
    if (found) {
      const path = [start, ...found.path.slice(1, -1), end]
      const rr = refineCourse(nav, land, path)
      tries.push(rr.changed ? rr.path : path)
    }
  }
  const ok = tries.filter((t) => courseIsWater(nav, t))
  if (!ok.length) {
    still.push({ text, why: "refused" })
    sailed.set(gk, course)
    after++
    continue
  }
  ok.sort((x, y) => landNm(x) - landNm(y) || len(x) - len(y))
  let pick = ok[0]
  if (pick !== tries[0]) fresh++
  const through = landNm(pick) > 0 ? null : straitCourse(start, end, pick)
  if (through) {
    pick = through
    shortened++
  }
  if (landNm(pick) > 0) {
    after++
    still.push({ text, why: `${landNm(pick).toFixed(1)} nm`, at: crossingsOf(truth, pick)[0]?.at })
  }
  sailed.set(gk, pick)
  const newText = jsonbText(pick)
  if (newText === text) continue
  addNm += len(pick) - len(course)
  baseNm += len(course)
  fixes.push({ old: md5(text), course: newText, oldText: text })
}
// EVERY REPLACED COURSE BACKWARDS TOO. The world copies its courses at run time (a merchant rehomed sails a
// lane backwards, public.npc_rehome; a loop takes the legs it knows, public.npc_feasible_legs), so a row
// written after the export holds a stored course or the same course read backwards. Both are replaced.
const have = new Set(fixes.map((f) => f.old))
for (const f of [...fixes]) {
  const back = reversedText(f.oldText)
  if (back === f.oldText || texts.has(back) || have.has(md5(back))) continue
  const course = JSON.parse(f.course).reverse()
  fixes.push({ old: md5(back), course: jsonbText(course), oldText: back, backwards: true })
  have.add(md5(back))
}
fixes.sort((x, y) => (x.old < y.old ? -1 : 1))
const fixed = new Set(fixes.map((f) => f.old))
const lanes = world.npc.filter((c) => fixed.has(md5(c.text))).length
const stops = world.routes.filter((r) => fixed.has(md5(r.text))).length
const coast = world.coast.filter((c) => fixed.has(md5(c.text))).length
const prodCounts = prod
  ? {
      lanes: prod.npc.filter(([, , t]) => fixed.has(md5(t))).length,
      npc: prod.npc.length,
      stops: prod.stops.filter(([, , t]) => fixed.has(md5(t))).reduce((s, [, n]) => s + n, 0),
      routes: prod.stops.reduce((s, [, n]) => s + n, 0),
      coast: prod.coast.filter(([, , t]) => fixed.has(md5(t))).length,
      at: prod.at,
    }
  : null
if (prodCounts) console.log(`  prod (${prod.at}): lanes ${prodCounts.lanes}/${prodCounts.npc}, route stops ${prodCounts.stops}/${prodCounts.routes}, coast ${prodCounts.coast}/${prod.coast.length}`)
const longer = ((addNm / Math.max(baseNm, 1)) * 100).toFixed(2)
console.log(
  `  courses: ${texts.size} distinct; ${before} crossed drawn land; ${fixes.length} re-sailed (${fresh} from a fresh search); ${after} still cross; ` +
    `${shortened} take the shorter course through an opened strait; lanes ${lanes}/${world.npc.length}, route stops ${stops}/${world.routes.length}, coast courses ${coast}/${world.coast.length}; ${longer}% longer`,
)
for (const s of still) console.log(`    still: ${s.why} ${s.at ?? ''} ${s.text.slice(0, 120)}`)

// ── 6. THE CONTROLS the self-assert holds ──────────────────────────────────────────────────────
// Each channel this slice opens, sailed down its own line with every sample read (no approach): refused
// by the old raster, water by the new. And each named pair of harbours, one on each side of a strait:
// the course author's course between them runs through the strait's cells and is clean.
const strict = (n, c) => c.every((p, i) => i === 0 || segmentIsWater(n, c[i - 1], p, 0, 0))
const controls = []
for (const ch of charted.filter((c) => opening.has(c.id))) {
  if (!strict(nav, ch.points)) throw new Error(`${ch.id}: its own line is not water on the new raster`)
  if (strict(oldNav, ch.points)) throw new Error(`${ch.id}: its own line was already water on the old raster: it proves nothing`)
  controls.push({ id: ch.id, name: ch.name, course: ch.points })
}
if (!opening.has('messina')) throw new Error("this slice opens no Strait of Messina: the owner's own example has no control")
const roadOf = (code) => {
  const f = finalRoad.get(code)
  if (!f) throw new Error(`no harbour ${code}`)
  return [f.lat, f.lon]
}
const passes = STRAIT_PASSES.filter((p) => opening.has(p.id)).map((p) => {
  const [A, B] = [roadOf(p.a), roadOf(p.b)]
  const found = findPath(nav, { lat: A[0], lon: A[1] }, { lat: B[0], lon: B[1] })
  if (!found) throw new Error(`${p.a} to ${p.b}: no way by sea`)
  const path = [A, ...found.path.slice(1, -1), B]
  const rr = refineCourse(nav, land, path)
  const course = rr.changed ? rr.path : path
  const cells = new Set(carved.get(p.id))
  const inStrait = course.some((q, i) => {
    if (!i) return false
    const o = course[i - 1]
    const n = Math.max(1, Math.ceil(gcNm(o[0], o[1], q[0], q[1]) / 1))
    for (let t = 0; t <= n; t++) if (cells.has(rowOf(o[0] + ((q[0] - o[0]) * t) / n) * COLS + colOf(o[1] + ((q[1] - o[1]) * t) / n))) return true
    return false
  })
  const gc = gcNm(A[0], A[1], B[0], B[1])
  if (!courseIsWater(nav, course) || landNm(course) > 0) throw new Error(`${p.a} to ${p.b}: the course through ${p.id} is not clean`)
  if (!inStrait) throw new Error(`${p.a} to ${p.b}: the course does not run through ${p.id}`)
  if (len(course) > gc * p.within) throw new Error(`${p.a} to ${p.b}: ${len(course).toFixed(1)} nm sailed, over ${p.within} times the ${gc.toFixed(1)} nm straight line`)
  console.log(`  ${p.id}: ${p.a} to ${p.b} ${len(course).toFixed(1)} nm through the strait (straight line ${gc.toFixed(1)} nm)`)
  return { ...p, course: jsonbText(course), nm: len(course), gc }
})

const sql = migrationSql({
  name: MIGRATION_NAME,
  forward: fixes.filter((f) => !f.backwards).length,
  prodAt: prod?.at ?? null,
  prodCounts,
  opened: opened.map((k) => ({ k, row: (k / COLS) | 0, col: k % COLS, lat: cellLat((k / COLS) | 0), lon: cellLon(k % COLS), ch: chartedCells.get(k) })),
  bits,
  seaPatch,
  channelRows,
  moves,
  changed: changedRoads.map((p) => ({ code: p.code, from: { lat: p.rlat, lon: p.rlon, nm: p.snap }, to: finalRoad.get(p.code) })),
  fixes,
  texts: texts.size,
  before,
  after,
  fresh,
  shortened,
  lanes,
  npc: world.npc.length,
  stops,
  routes: world.routes.length,
  coast,
  coasts: world.coast.length,
  longer,
  raster: maskPayload.raster.md5,
  controls,
  passes,
  joinNm,
})
// PART B (the pair table and the quoted distances) is appended by scripts/build-sea-legs-migration.mjs --append.
writeFileSync(MIGRATION, sql + PART_B_MARK + '\n')
console.log(`wrote ${path.relative(ROOT, MIGRATION)} (${fixes.length} course(s), ${moves.length} roadstead(s), ${opened.length} cell(s); ${Math.round(sql.length / 1024)} KB)`)

// ── 7. THE PROD CHECKS AND THE FORWARD ROLLBACK (PART A's; PART B's are scripts/build-sea-legs-migration.mjs's) ──
mkdirSync(HARNESS, { recursive: true })
const oldMd5s = fixes.map((f) => `('${f.old}')`).join(', ')
const newMd5s = fixes.map((f) => `('${md5(f.course)}')`).join(', ')
const ids = channelRows.map((c) => `'${c.id}'`).join(', ')
const roadsWas = changedRoads.map((p) => `('${p.code}', ${p.rlat}, ${p.rlon})`).join(', ') || `('-', 0, 0)`
const roadsNow = changedRoads.map((p) => `('${p.code}', ${finalRoad.get(p.code).lat}, ${finalRoad.get(p.code).lon})`).join(', ') || `('-', 0, 0)`
const sailing = changedRoads.map((p) => `'${p.code}'`).join(', ') || `'-'`
writeFileSync(
  path.join(HARNESS, 'before.sql'),
  `-- before.sql: READ ONLY on prod, one statement, BEFORE 0446 is pushed (generated by scripts/build-straits.mjs: do not edit by hand).
-- Want head 20260818000445, raster_md5 ${md5(world.raster.cells_base64.replace(/\s+/g, ''))}, roads_as_image ${changedRoads.length}, cells_closed ${opened.length}, channels_new 0, keep_fn 1.${prodCounts ? `
-- At the export (${prodCounts.at}): lanes_total ${prodCounts.npc}, lanes_replaced ${prodCounts.lanes}, stops_replaced ${prodCounts.stops} (rows written since may add or drop a few).` : ''}
-- sailing_to_moved: voyages under way to a harbour whose roadstead moves (they finish the course they hold).
begin transaction read only;
with f(m) as (values ${oldMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'raster_md5', (select md5(replace(encode(r.cells, 'base64'), E'\\n', '')) from public.sea_raster r where r.id = 1),
  'lanes_total', (select count(*) from public.npc_courses),
  'lanes_replaced', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from f)),
  'stops_replaced', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from f)),
  'roads_as_image', (select count(*) from public.sea_reaches sr join public.ports p on p.id = sr.port_id
                      where (p.code, sr.roadstead_lat::float8, sr.roadstead_lon::float8) in (${roadsWas})),
  'cells_closed', (select count(*) from (values ${opened.map((k) => `(${k})`).join(', ')}) c(k), public.sea_raster r where r.id = 1 and get_bit(r.cells, c.k * r.bits_per_cell) = 0),
  'channels_new', (select count(*) from voyage.channels c where c.id in (${ids})),
  'keep_fn', (select count(*) from pg_proc p where p.oid = to_regprocedure('public.sea_leg_asks_keep()')),
  'sailing_to_moved', (select count(*) from public.voyages v join public.ports p on p.id = v.dest_port_id where v.status = 'SAILING' and p.code in (${sailing})));
rollback;
`,
)
writeFileSync(
  path.join(HARNESS, 'after.sql'),
  `-- after.sql: READ ONLY on prod, one statement, AFTER 0446 (generated by scripts/build-straits.mjs: do not edit by hand).
-- Want head 20260818000446, lanes_old 0, stops_old 0 (a stop saved by a browser tab that has not reloaded may show: the daily audit lists it),
-- roads_new ${changedRoads.length}, cells_open ${opened.length}, channels_new ${channelRows.length}; lanes_new is ${lanes} on the chain's world${prodCounts ? ` (about ${prodCounts.lanes} on prod)` : ''}.
-- PART B's own check is scripts/ops/harness/straits/after-pairs.sql.
begin transaction read only;
with o(m) as (values ${oldMd5s}), n(m) as (values ${newMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_old', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from o)),
  'stops_old', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from o)),
  'lanes_new', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from n)),
  'roads_new', (select count(*) from public.sea_reaches sr join public.ports p on p.id = sr.port_id
                 where (p.code, sr.roadstead_lat::float8, sr.roadstead_lon::float8) in (${roadsNow})),
  'cells_open', (select count(*) from (values ${opened.map((k) => `(${k})`).join(', ')}) c(k), public.sea_raster r where r.id = 1 and get_bit(r.cells, c.k * r.bits_per_cell) = 1),
  'channels_new', (select count(*) from voyage.channels c where c.id in (${ids})));
rollback;
`,
)
const backCourse = fixes.map((f) => `    ('${md5(f.course)}', '${f.oldText}')`).join(',\n')
writeFileSync(
  path.join(HARNESS, 'rollback-0446.sql'),
  `-- rollback-0446.sql: the FORWARD rollback of 0446 PART A (generated by scripts/build-straits.mjs: do not edit by hand). Cut it as the next
-- migration if the owner wants it undone, WITH scripts/ops/harness/straits/rollback-pairs-0446.sql after it (the pair table and the quoted
-- distances as they were): the courses and the roadsteads go back, the charted cells close and their channels go. scripts/sea-grid.mjs loses
-- the four channels, public/coast/mask.json is cut again (node scripts/build-coast-mask.mjs) and data/sea-legs.json goes back with it.
-- (Cargo legs keep their pieces: a circuit is rebuilt by public.cargo_circuit_build when its ships are home.)
-- A DRAFT that WRITES: it runs on a local PGlite world only while it carries the next line (the guard). To deploy it, strip that line. Owner only.
do $ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $;
create function pg_temp.back_0446() returns table (new_md5 text, course jsonb) language sql immutable as $b$
  select v.m, v.c::jsonb from (values
${backCourse}
  ) as v(m, c)
$b$;
update public.npc_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0446() b where md5(c.course::text) = b.new_md5;
update public.standing_route_stops s set course = b.course,
       course_nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0446() b where md5(s.course::text) = b.new_md5;
update public.npc_coast_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0446() b where md5(c.course::text) = b.new_md5;
${changedRoads.length ? `update public.sea_reaches sr set roadstead_lat = v.lat, roadstead_lon = v.lon, snap_nm = v.nm
  from public.ports p, (values
${changedRoads.map((p) => `    ('${p.code}', ${p.rlat}::numeric, ${p.rlon}::numeric, ${p.snap_t}::numeric)`).join(',\n')}
  ) v(code, lat, lon, nm) where p.id = sr.port_id and p.code = v.code;
` : ''}${moves.length ? `delete from voyage.drawn_roadsteads where code in (${moves.map((m) => `'${m.code}'`).join(', ')});
` : ''}update public.sea_raster set cells = ${opened.reduce((acc, k) => `set_bit(${acc}, ${k * bits}, 0)`, 'cells')} where id = 1;
${opened.map((k) => `update public.sea_zone_cells set zones = set_byte(zones, ${k % COLS}, 0) where row_idx = ${(k / COLS) | 0};`).join('\n')}
${seaPatch.map((s) => `update public.sea_cells set seas = set_byte(seas, ${s.col}, ${s.was}) where row_idx = ${s.row};`).join('\n')}
delete from voyage.channels where id in (${ids});
select public.sea_leg_asks_keep();
`,
)
console.log(`wrote ${path.relative(ROOT, HARNESS)}/before.sql, after.sql, rollback-0446.sql`)
process.exit(0)
