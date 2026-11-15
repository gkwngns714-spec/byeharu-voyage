#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-land-channels.mjs — THE STRAITS OPENED AND THE ROADS PUT ON THE WATER (owner row 352, 0440)
//
//   node scripts/build-land-channels.mjs [world-image.tar.gz]
//
// The owner, 2026-11-15: "some ships go pass through land ... fix this properly". 0440 re-sailed
// every course off the drawn land; this slice takes what 0440 listed as left:
//
//   1. THE CHARTED CHANNELS. Water the chart draws (1:10m) that the 0.25-degree raster (1:110m)
//      closes: scripts/sea-grid.mjs CHANNELS entries with `charted: true` (Corfu's two channels, the
//      Tsugaru strait, the Wielingen). Their cells are opened in public.sea_raster, named in
//      public.sea_cells after the water next to them, and listed in voyage.channels; their drawn land
//      stays land in the coast mask (public/coast/mask.json, re-cut here) and in the audit. A strait
//      carved long ago and marked `charted` changes no raster: only its drawn land starts to count.
//   2. THE ROADS ON THE WATER. A harbour's roadstead (public.sea_reaches, voyage.water_roadstead)
//      that lies on the chart's drawn land, or in a pocket of drawn water the open sea cannot reach
//      on the course author's own 1.5-nm grid, moves to THE NEAREST POINT TO THE QUAY that is drawn
//      water with 1.5 nm of drawn water round it and joined to the open sea (decided by default).
//      voyage.drawn_roadsteads holds each such point; voyage.water_roadstead answers it for that
//      quay (one hunk), so the table and the rule stay one answer.
//   3. THE COURSES. Every stored course (public.npc_courses, public.standing_route_stops,
//      public.npc_coast_courses, and the frozen pieces of a cargo circuit or a navy patrol) that ends
//      at a moved roadstead or still crosses drawn land is re-sailed
//      with src/lib/sea/refine.ts on the new raster and mask, from the new roadsteads; when the old
//      course cannot be mended, the course author's own search is run from scratch (findPath, then
//      refine), exactly as the browser proposes a course. Matched by md5(course::text), as 0440.
//
// Writes supabase/migrations/20260818000440_*.sql, public/coast/mask.json, and the prod checks and
// forward rollback under scripts/ops/harness/no-land/. Reads a world image (no prod load).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// THE PAIR TABLE (0442): a migration this writes calls public.sea_leg_asks_keep() after it re-sails (the template's step), so no lane is left
// crossing a sea its pair's row does not hold and no moved roadstead is left in a sea its own row does not name. Then RE-RUN
// scripts/build-sea-legs.mjs and scripts/build-sea-legs-migration.mjs: the world guard holds public.sea_leg_asks equal to data/sea-legs.json.

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
import { migrationSql, unhunkSql, SOCOTRA } from './land-channels.sql.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const MIGRATION_NAME = '20260818000440_no_course_crosses_the_drawn_land.sql'
const MIGRATION = path.join(ROOT, 'supabase', 'migrations', MIGRATION_NAME)
const HARNESS = path.join(ROOT, 'scripts', 'ops', 'harness', 'no-land')
const md5 = (s) => createHash('md5').update(s).digest('hex')
const jsonbText = (course) => `[${course.map(([a, b]) => `[${a}, ${b}]`).join(', ')}]`
const r3 = (x) => Math.round(x * 1000) / 1000
const key = (lat, lon) => `${Number(lat)},${Number(lon)}`

/** A roadstead moves no further than this from where the raster rule put it: a player's stored
 *  route still begins within course_join_nm (15 nm) of the new point. */
const MAX_MOVE_NM = 12
/** The box searched round a roadstead for the open sea, in degrees of latitude either side. */
const BOX_DEG = 0.6

// node scripts/build-land-channels.mjs [image] [--prod courses.json] — the image is the chain BEFORE this
// migration; --prod adds every course production holds (scripts/ops/harness/no-land/prod-courses.sql, read
// only), so the migration re-sails prod's own rows, which no image has (0203 copied prod's merchant loops
// into the lanes when it was applied; players' routes live only there).
const argv = process.argv.slice(2)
const flagValue = (f) => (argv.indexOf(f) >= 0 ? argv[argv.indexOf(f) + 1] : null)
const prodFile = flagValue('--prod')
const file = argv.find((a, i) => !a.startsWith('--') && argv[i - 1] !== '--prod') ?? (await newestImage())
console.log(`land channels: world image ${path.basename(file)}${prodFile ? `, and prod's courses from ${path.basename(prodFile)}` : ''}`)
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
  if (prod.raster_md5 !== md5(world.raster.cells_base64.replace(/s+/g, ''))) throw new Error('prod serves another raster than the image')
  for (const [code, lat, lon] of prod.roads) {
    const p = portRows.find((x) => x.code === code)
    if (!p || p.rlat !== Number(lat) || p.rlon !== Number(lon)) throw new Error(`prod's roadstead of ${code} is not the image's`)
  }
  for (const [, , text] of [...prod.npc, ...prod.coast]) texts.set(text, JSON.parse(text))
  for (const [, , text] of prod.stops) texts.set(text, JSON.parse(text))
}
/** Postgres's text of a course read backwards, from its own text (each point's numbers kept as written). */
const reversedText = (text) => `[${(text.match(/[[^[]]+]/g) ?? []).reverse().join(', ')}]`
const len = (c) => c.reduce((s, p, i) => (i ? s + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : s), 0)
const landNm = (c) => crossingsOf(truth, c).reduce((s, x) => s + x.nm, 0)
const fixes = []
let before = 0
let after = 0
let fresh = 0
let addNm = 0
let baseNm = 0
const still = []
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
    sailed.set(gk, course)
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
  const pick = ok[0]
  if (pick !== tries[0]) fresh++
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
    `lanes ${lanes}/${world.npc.length}, route stops ${stops}/${world.routes.length}, coast courses ${coast}/${world.coast.length}; ${longer}% longer`,
)
for (const s of still) console.log(`    still: ${s.why} ${s.at ?? ''} ${s.text.slice(0, 120)}`)

// ── 6. THE CONTROLS the self-assert holds ──────────────────────────────────────────────────────
// Corfu: a course from the town's new roads north through the channel, refused by the old raster
// and accepted by the new. Hadibu: the owner's harbour, its roads off Socotra's shore.
const corfu = finalRoad.get('COR')
const corfuControl = [[corfu.lat, corfu.lon], [39.7, 19.96], [39.74, 19.975], [39.785, 19.968], [39.83, 19.93], [39.92, 19.85], [39.97, 19.72]]
const strict = (n, c) => c.every((p, i) => i === 0 || segmentIsWater(n, c[i - 1], p, 0, 0))
if (!strict(nav, corfuControl)) throw new Error('the Corfu control is not water on the new raster')
if (strict(oldNav, corfuControl)) throw new Error('the Corfu control was already water on the old raster: it proves nothing')
// THE OWNER'S EXAMPLE: of the replaced courses, the one that ran furthest through solid Socotra (the
// Hadibu to Kilwa lane); its new course must not touch the box.
const inSocotra = (course) => {
  let n = 0
  for (let i = 0; i + 1 < course.length; i++) {
    const [a, b] = [course[i], course[i + 1]]
    const steps = Math.max(1, Math.ceil(gcNm(a[0], a[1], b[0], b[1])))
    for (let k = 0; k <= steps; k++) {
      const la = a[0] + ((b[0] - a[0]) * k) / steps
      const lo = a[1] + ((b[1] - a[1]) * k) / steps
      if (la >= SOCOTRA.south && la <= SOCOTRA.north && lo >= SOCOTRA.west && lo <= SOCOTRA.east) n++
    }
  }
  return n
}
for (let la = SOCOTRA.south; la <= SOCOTRA.north + 1e-9; la += 0.005) {
  for (let lo = SOCOTRA.west; lo <= SOCOTRA.east + 1e-9; lo += 0.005) {
    if (!fineLand.isLand(la, lo)) throw new Error(`the Socotra control box is not all drawn land at ${la},${lo}`)
  }
}
let socotraControl = null
for (const f of fixes) {
  if (f.backwards) continue
  const was = inSocotra(JSON.parse(f.oldText))
  if (was && !inSocotra(JSON.parse(f.course)) && (!socotraControl || was > socotraControl.was)) socotraControl = { old: f.old, oldText: f.oldText, was }
}
if (!socotraControl) throw new Error("no replaced course crossed Socotra: the owner's own example has no control")
const had = moves.find((m) => m.code === 'HAD')
if (!had) throw new Error("Hadibu's roadstead did not move: the owner's own harbour has no control")

const sql = migrationSql({
  name: MIGRATION_NAME,
  forward: fixes.filter((f) => !f.backwards).length,
  prodAt: prod?.at ?? null,
  prodCounts,
  socotra: SOCOTRA,
  socotraControl,
  opened: opened.map((k) => ({ k, row: (k / COLS) | 0, col: k % COLS, lat: cellLat((k / COLS) | 0), lon: cellLon(k % COLS), ch: chartedCells.get(k) })),
  bits,
  seaPatch,
  channelRows,
  chartedOld: charted.filter((c) => !opening.has(c.id)).map((c) => c.id),
  moves,
  changed: changedRoads.map((p) => ({ code: p.code, from: { lat: p.rlat, lon: p.rlon, nm: p.snap }, to: finalRoad.get(p.code) })),
  fixes,
  texts: texts.size,
  before,
  after,
  fresh,
  lanes,
  npc: world.npc.length,
  stops,
  routes: world.routes.length,
  coast,
  coasts: world.coast.length,
  longer,
  raster: maskPayload.raster.md5,
  corfuControl,
  joinNm,
})
writeFileSync(MIGRATION, sql)
console.log(`wrote ${path.relative(ROOT, MIGRATION)} (${fixes.length} course(s), ${moves.length} roadstead(s), ${opened.length} cell(s); ${Math.round(sql.length / 1024)} KB)`)

// ── 7. THE PROD CHECKS AND THE FORWARD ROLLBACK ────────────────────────────────────────────────
mkdirSync(HARNESS, { recursive: true })
const oldMd5s = fixes.map((f) => `('${f.old}')`).join(', ')
const newMd5s = fixes.map((f) => `('${md5(f.course)}')`).join(', ')
const codes = changedRoads.map((p) => `'${p.code}'`).join(', ')
writeFileSync(
  path.join(HARNESS, 'before.sql'),
  `-- before.sql: READ ONLY on prod, one statement, BEFORE 0440 is pushed (generated by scripts/build-land-channels.mjs: do not edit by hand).
-- Want head 20260818000439, roads_as_image ${changedRoads.length}, cells_closed ${opened.length}, channels 29.${prodCounts ? `
-- At the export (${prodCounts.at}): lanes_total ${prodCounts.npc}, lanes_replaced ${prodCounts.lanes}, stops_replaced ${prodCounts.stops} (rows written since may add a few).` : ''}
begin transaction read only;
with f(m) as (values ${oldMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_total', (select count(*) from public.npc_courses),
  'lanes_replaced', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from f)),
  'stops_replaced', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from f)),
  'roads_as_image', (select count(*) from public.sea_reaches sr join public.ports p on p.id = sr.port_id
                      where p.code in (${codes}) and (sr.roadstead_lat::float8, sr.roadstead_lon::float8) in (${changedRoads.map((p) => `(${p.rlat}, ${p.rlon})`).join(', ')})),
  'cells_closed', (select count(*) from (values ${opened.map((k) => `(${k})`).join(', ')}) c(k), public.sea_raster r where r.id = 1 and get_bit(r.cells, c.k * r.bits_per_cell) = 0),
  'channels', (select count(*) from voyage.channels),
  'sailing_from_moved', (select count(*) from public.voyages v join public.ports p on p.id = v.dest_port_id where v.status = 'SAILING' and p.code in (${codes})));
rollback;
`,
)
writeFileSync(
  path.join(HARNESS, 'after.sql'),
  `-- after.sql: READ ONLY on prod, one statement, AFTER 0440 (generated by scripts/build-land-channels.mjs: do not edit by hand).
-- Want lanes_old 0, stops_old 0, lanes_new ${lanes}, roads_new ${changedRoads.length}, cells_open ${opened.length}, drawn_roadsteads ${moves.length}.
begin transaction read only;
with o(m) as (values ${oldMd5s}), n(m) as (values ${newMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_old', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from o)),
  'stops_old', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from o)),
  'lanes_new', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from n)),
  'roads_new', (select count(*) from public.sea_reaches sr join public.ports p on p.id = sr.port_id
                 where (p.code, sr.roadstead_lat::float8, sr.roadstead_lon::float8) in (${changedRoads.map((p) => `('${p.code}', ${finalRoad.get(p.code).lat}, ${finalRoad.get(p.code).lon})`).join(', ')})),
  'cells_open', (select count(*) from (values ${opened.map((k) => `(${k})`).join(', ')}) c(k), public.sea_raster r where r.id = 1 and get_bit(r.cells, c.k * r.bits_per_cell) = 1),
  'drawn_roadsteads', (select count(*) from voyage.drawn_roadsteads));
rollback;
`,
)
const backCourse = fixes.map((f) => `    ('${md5(f.course)}', '${f.oldText}')`).join(',\n')
writeFileSync(
  path.join(HARNESS, 'rollback-0440.sql'),
  `-- rollback-0440.sql: the FORWARD rollback of 0440 (generated by scripts/build-land-channels.mjs: do not edit by hand). Cut it as the next
-- migration if the owner wants it undone: the courses and the roadsteads go back, the charted cells close, the drawn roadsteads go and
-- voyage.water_roadstead loses its 0440 lines. (Cargo legs keep their pieces: a circuit is rebuilt by public.cargo_circuit_build when its ships are home.)
create function pg_temp.back_0440() returns table (new_md5 text, course jsonb) language sql immutable as $b$
  select v.m, v.c::jsonb from (values
${backCourse}
  ) as v(m, c)
$b$;
update public.npc_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0440() b where md5(c.course::text) = b.new_md5;
update public.standing_route_stops s set course = b.course,
       course_nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0440() b where md5(s.course::text) = b.new_md5;
update public.sea_reaches sr set roadstead_lat = v.lat, roadstead_lon = v.lon, snap_nm = v.nm
  from public.ports p, (values
${changedRoads.map((p) => `    ('${p.code}', ${p.rlat}::numeric, ${p.rlon}::numeric, ${p.snap_t}::numeric)`).join(',\n')}
  ) v(code, lat, lon, nm) where p.id = sr.port_id and p.code = v.code;
update public.npc_coast_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0440() b where md5(c.course::text) = b.new_md5;
update public.sea_raster set cells = ${opened.reduce((acc, k) => `set_bit(${acc}, ${k * bits}, 0)`, 'cells')} where id = 1;
${seaPatch.map((s) => `update public.sea_cells set seas = set_byte(seas, ${s.col}, ${s.was}) where row_idx = ${s.row};`).join('\n')}
delete from voyage.channels where id in (${channelRows.map((c) => `'${c.id}'`).join(', ')});
${unhunkSql()}drop table voyage.drawn_roadsteads;
`,
)
console.log(`wrote ${path.relative(ROOT, HARNESS)}/before.sql, after.sql, rollback-0440.sql`)
