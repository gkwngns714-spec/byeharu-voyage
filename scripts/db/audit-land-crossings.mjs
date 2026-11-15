// ═══════════════════════════════════════════════════════════════════════════════════════════════
// audit-land-crossings.mjs — EVERY COURSE THE WORLD SAILS, HELD TO THE LAND THE CHART DRAWS
// (owner row 352, 2026-11-15: "some ships go pass through land - such as hadibu")
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   node scripts/db/audit-land-crossings.mjs [world-image.tar.gz] [--pairs [--raw]] [--all] [--json out.json]
//                                            [--apply <migration.sql>] [--write-known]
//                                            [--prod prod-courses.json [--legs prod-legs.json]]
//   (--prod: audit PRODUCTION's own courses, exported read-only by scripts/ops/harness/no-land/prod-courses.sql
//   and prod-legs.sql, on this image's raster; fails on anything not in land-crossings.prod-known.json)
//   (--apply: apply a migration not yet in the image first, rolled back after; --write-known: write
//   what is found as scripts/db/land-crossings.known.json, the list tests/sea.noLandCrossing.spec.ts
//   holds the world to. Only ever to SHRINK it: a new crossing is fixed, never listed.)
//   (--raw: the pairs as the search alone proposes them, before re-sailing: the old client's courses)
//
// Reads a WORLD IMAGE (a PGlite data directory of the applied chain: `npm run build` writes one under
// dist/, the prefix cache keeps them under node_modules/.cache/byeharu-world-image/), so it costs
// production nothing. With no image named, the newest cached one is used.
//
// WHAT IS AUDITED — every stored line a ship is drawn on:
//   npc       public.npc_courses: every merchant, cargo, pirate and navy lane (they sail these
//             courses whole; nothing re-plans them)
//   route     public.standing_route_stops.course: every standing route's legs (the merchant
//             companies' loops; a player's own routes in a live world)
//   coast     public.npc_coast_courses: a harbour with no lane to its nearest harbours (0400; 0440)
//   roadstead public.sea_reaches: the point each harbour is reached from (the first and last point
//             of every course to it). One on drawn land draws the harbour's approach over land.
//   pair      (--pairs) the course the browser's course author proposes between every two
//             harbours: the search (src/lib/sea floodFrom/floodPathTo, as findPath) and the
//             re-sailing off the coast mask (src/lib/sea/refine.ts), exactly as
//             src/domain/passage proposeCourse runs them. A SAIL sent with no course tries the
//             straight line under the server's same raster rule, so this covers it too.
//
// THE LAND is the chart's own fine coast (public/coast/fine, scripts/lib/drawn-land.mjs), except a
// cell the game opened ON PURPOSE (land in 1:110m, water in the served raster: a declared channel,
// a river or strait such as the Thames or the Bosphorus; scripts/sea-grid.mjs CHANNELS).
//
// A CROSSING is a run of consecutive samples (every 0.25 nm) on that land longer than TOLERANCE_NM
// (2 nm: the chart's mid-level coast is itself simplified by 0.03 degrees, 1.8 nm). A run that
// begins at a course's first point, or ends at its last, when that point is itself on drawn land,
// and is no longer than APPROACH_MAX_NM, is that harbour's APPROACH (its roadstead is on land;
// listed under `roadstead`), not a crossing.
//
// Exit code 1 when any crossing is found, so the same script is a gate. The CI guard
// (tests/sea.noLandCrossing.spec.ts) runs these same functions on the build's own world.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFile, readdir, writeFile, stat } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { PGlite } from '@electric-sql/pglite'
import { drawnLand, gcNm } from '../lib/drawn-land.mjs'
import { riverCarvedCells, rowOf as gridRow, colOf as gridCol, COLS as GRID_COLS } from '../sea-grid.mjs'
import { navFromServed, floodFrom, floodPathTo } from '../../src/lib/sea/index.ts'
import { segmentLandRuns, refineCourse, LAND_TOLERANCE_NM } from '../../src/lib/sea/refine.ts'
import { coastMaskFrom, coastLand } from '../../src/lib/sea/coastMask.ts'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const CACHE = path.join(ROOT, 'node_modules', '.cache', 'byeharu-world-image')
const MASK_FILE = path.join(ROOT, 'public', 'coast', 'mask.json')
const KNOWN_FILE = path.join(ROOT, 'scripts', 'db', 'land-crossings.known.json')
/** PROD'S known list: what a prod export (--prod) may still show crossing. Empty after 0440; it may only shrink. */
const PROD_KNOWN_FILE = path.join(ROOT, 'scripts', 'db', 'land-crossings.prod-known.json')

/** The pair sample the guard runs: every harbour to an origin in every Nth (by code). */
export const PAIR_SAMPLE_EVERY = 22

export const TOLERANCE_NM = LAND_TOLERANCE_NM

/** The longest run a harbour's own approach may make over the drawn land (its quay or roadstead on
 *  land, the town inland of its water): longer than this from a harbour is a crossing all the same.
 *  Hadibu's quay is on Socotra's north shore; a course from it across the island to the south is
 *  ~20 nm of land and is a crossing, never an approach. */
export const APPROACH_MAX_NM = 6

export async function newestImage() {
  const names = (await readdir(CACHE)).filter((n) => n.endsWith('.tar.gz'))
  const withTime = await Promise.all(names.map(async (n) => ({ n, t: (await stat(path.join(CACHE, n))).mtimeMs })))
  withTime.sort((a, b) => b.t - a.t)
  if (!withTime.length) throw new Error(`audit: no world image in ${CACHE}; run \`npm run build\` or name one`)
  return path.join(CACHE, withTime[0].n)
}

export async function openImage(file) {
  return PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(file))], { type: 'application/x-tar' }) })
}

/**
 * Every stored course of a world, and its served raster. `db` is anything with
 * `query(sql) -> { rows }` (PGlite, or the app's local db's `pg`). `text` is Postgres's own
 * `course::text`, the key a migration matches a course by.
 */
export async function readWorldCourses(db) {
  const raster = (
    await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                           replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                      from public.sea_raster where id = 1`)
  ).rows[0]
  const ports = (
    await db.query(`select p.code, p.name, p.kind, p.lat::float8 as lat, p.lon::float8 as lon,
                           sr.roadstead_lat::float8 as rlat, sr.roadstead_lon::float8 as rlon
                      from public.ports p left join public.sea_reaches sr on sr.port_id = p.id order by p.code`)
  ).rows
  const npc = (
    await db.query(`select a.code as a, b.code as b, c.course, c.course::text as text
                      from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
                     order by a.code, b.code`)
  ).rows
  const routes = (
    await db.query(`select s.route_id::text as route, s.ord, p.code as to_code, s.course, s.course::text as text,
                           (select p0.code from public.standing_route_stops s0 join public.ports p0 on p0.id = s0.port_id
                             where s0.route_id = s.route_id and s0.ord < s.ord order by s0.ord desc limit 1) as from_code
                      from public.standing_route_stops s join public.ports p on p.id = s.port_id
                     where s.course is not null order by s.route_id, s.ord`)
  ).rows
  // 0440: the coast courses (0400: a harbour with no lane, to its nearest harbours along the coast).
  const coast = (
    await db.query(`select a.code as a, b.code as b, c.course, c.course::text as text
                      from public.npc_coast_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
                     order by a.code, b.code`)
  ).rows
  return { raster, ports, npc, routes, coast }
}

/** THE LAND A COURSE IS HELD TO: drawn land, except a cell a RIVER carve opened on purpose (the
 *  Thames, the Bosphorus: the chart draws land over water the game sails). A charted channel's cells
 *  (0440: Corfu, the Wielingen) are held to their drawn land like any other water. */
export function truthLand(nav, land = drawnLand('fine')) {
  const river = riverCarvedCells()
  return {
    blocked: (lat, lon) => {
      if (!land.isLand(lat, lon)) return false
      const k = gridRow(lat) * GRID_COLS + gridCol(lon)
      return !(river.has(k) && nav.cells[k] !== 0)
    },
  }
}

/**
 * The crossings of one course: runs over the tolerance, minus a harbour's own approach (a run
 * from the first point or to the last point when that point is itself on the land). Each:
 * `{ seg, nm, at: [lat, lon] }`.
 */
export function crossingsOf(truth, course, toleranceNm = TOLERANCE_NM) {
  const out = []
  const startOnLand = truth.blocked(course[0][0], course[0][1])
  const endOnLand = truth.blocked(course[course.length - 1][0], course[course.length - 1][1])
  for (let i = 0; i + 1 < course.length; i++) {
    for (const r of segmentLandRuns(truth, course[i], course[i + 1], i)) {
      if (r.nm <= toleranceNm) continue
      if (r.nm <= APPROACH_MAX_NM && i === 0 && r.f0 === 0 && startOnLand) continue
      if (r.nm <= APPROACH_MAX_NM && i === course.length - 2 && r.f1 === 1 && endOnLand) continue
      const [a, b] = [course[i], course[i + 1]]
      const f = (r.f0 + r.f1) / 2
      out.push({ seg: i, nm: Math.round(r.nm * 10) / 10, at: [round3(a[0] + (b[0] - a[0]) * f), round3(a[1] + (b[1] - a[1]) * f)] })
    }
  }
  return out
}
const round3 = (v) => Math.round(v * 1000) / 1000

/** The nearest harbour to a point, for the report. */
export function nearestHarbour(ports, lat, lon) {
  let best = null
  for (const p of ports) {
    if (p.kind !== 'HARBOUR') continue
    const d = gcNm(lat, lon, p.lat, p.lon)
    if (!best || d < best.d) best = { code: p.code, name: p.name, d }
  }
  return best ? `${best.name} (${best.code}) ${Math.round(best.d)} nm` : '?'
}

/**
 * THE LIVE WORLD'S COURSES, from a prod export (scripts/ops/harness/no-land/prod-courses.sql and
 * prod-legs.sql, read only), on the raster and ports of a world image. Prod holds rows no image has
 * (lanes the image never seeded, players' routes, the cargo circuits' and navy patrols' frozen legs),
 * so the audit must be run on prod's own set too. Refuses when prod serves another raster.
 */
export function worldFromExport(base, courses, legs = null) {
  const served = createHash('md5').update(base.raster.cells_base64.replace(/\s+/g, '')).digest('hex')
  if (courses.raster_md5 !== served) throw new Error(`audit: prod serves raster ${courses.raster_md5}, the image ${served}: use an image of prod's chain`)
  const roads = new Map(courses.roads.map(([code, lat, lon]) => [code, { rlat: Number(lat), rlon: Number(lon) }]))
  const ports = base.ports.map((p) => ({ ...p, ...(roads.get(p.code) ?? { rlat: null, rlon: null }) }))
  const h8 = (t) => createHash('md5').update(t).digest('hex').slice(0, 8)
  const one = ([a, b, text]) => ({ a, b, text, course: JSON.parse(text) })
  const piecesToCourse = (text) => {
    const out = []
    for (const s of JSON.parse(text)) {
      for (const p of [s.a, s.b]) {
        const last = out[out.length - 1]
        if (!last || last[0] !== Number(p[0]) || last[1] !== Number(p[1])) out.push([Number(p[0]), Number(p[1])])
      }
    }
    return out
  }
  return {
    raster: base.raster,
    ports,
    npc: courses.npc.map(one),
    coast: (courses.coast ?? []).map(one),
    routes: courses.stops.map(([code, n, text]) => ({ route: null, ord: null, from_code: code, to_code: code, rows: n, text, course: JSON.parse(text) })),
    legs: legs
      ? [
          ...(legs.cargo ?? []).map(([n, text]) => ({ kind: 'cargo', key: `cargo ${h8(text)}`, rows: n, text, course: piecesToCourse(text) })),
          ...(legs.patrol ?? []).map(([n, text]) => ({ kind: 'patrol', key: `patrol ${h8(text)}`, rows: n, text, course: piecesToCourse(text) })),
        ]
      : [],
  }
}

/** The coast mask the browser's course author uses, decoded (for --pairs). */
export function readMask() {
  return coastMaskFrom(JSON.parse(readFileSync(MASK_FILE, 'utf8')))
}

/**
 * THE AUDIT, pure over what readWorldCourses returned. Returns `{ counted, crossings, roadsteads }`:
 * every crossing `{ kind, key, worst }` (key: 'npc A->B', 'route A->B', 'pair A->B'), and every
 * harbour whose roadstead lies on drawn land.
 */
export function auditWorld(world, { pairs = false, raw = false, pairFilter = null, log = () => {} } = {}) {
  const nav = navFromServed(world.raster)
  const truth = truthLand(nav)
  const crossings = []
  const seen = new Map()
  const counted = { npc: 0, route: 0, coast: 0, leg: 0, roadstead: 0, pair: 0 }
  const add = (kind, key, course, rows = 1, text = null) => {
    const c = crossingsOf(truth, course)
    if (!c.length) return
    const id = `${kind} ${key}`
    const had = seen.get(id)
    if (had) {
      had.rows += rows
      return
    }
    const entry = { kind, key: id, rows, text, worst: c.reduce((m, x) => (x.nm > m.nm ? x : m)), runs: c.length, landNm: Math.round(c.reduce((s, x) => s + x.nm, 0) * 10) / 10 }
    seen.set(id, entry)
    crossings.push(entry)
  }
  for (const c of world.npc) {
    counted.npc++
    add('npc', `${c.a}->${c.b}`, c.course)
  }
  for (const r of world.routes) {
    counted.route += r.rows ?? 1
    // a stop's course leaves its own port (s.port_id) for the next stop; a prod export keys it by its text
    add('route', r.route === null ? `${r.from_code} ${createHash('md5').update(r.text).digest('hex').slice(0, 8)}` : `${r.from_code ?? r.to_code}->${r.to_code}`, r.course, r.rows ?? 1, r.route === null ? r.text : null)
  }
  for (const l of world.legs ?? []) {
    counted.leg += l.rows
    add('leg', l.key, l.course, l.rows, l.text)
  }
  for (const c of world.coast ?? []) {
    counted.coast++
    add('coast', `${c.a}->${c.b}`, c.course)
  }
  const harbours = world.ports.filter((p) => Number.isFinite(p.rlat))
  const roadsteads = []
  for (const p of harbours) {
    counted.roadstead++
    if (truth.blocked(p.rlat, p.rlon)) roadsteads.push(p.code)
  }
  if (pairs) {
    const land = coastLand(readMask(), nav)
    const t0 = Date.now()
    for (let i = 0; i < harbours.length; i++) {
      const a = harbours[i]
      const ra = { lat: a.rlat, lon: a.rlon }
      const flood = floodFrom(nav, ra)
      if (!flood) continue
      for (let j = 0; j < harbours.length; j++) {
        if (i === j) continue
        const b = harbours[j]
        if (pairFilter && !pairFilter(a, b)) continue
        const found = floodPathTo(flood, ra, { lat: b.rlat, lon: b.rlon })
        if (!found) continue
        counted.pair++
        add('pair', `${a.code}->${b.code}`, raw ? found.path : refineCourse(nav, land, found.path).path)
      }
      if (i % 50 === 0) log(`  pairs: ${i + 1}/${harbours.length} harbours, ${Math.round((Date.now() - t0) / 1000)} s`)
    }
  }
  return { counted, crossings, roadsteads }
}

// ── CLI ─────────────────────────────────────────────────────────────────────────────────────────
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2)
  const valueOf = (flag) => (args.indexOf(flag) >= 0 ? args[args.indexOf(flag) + 1] : null)
  const jsonOut = valueOf('--json')
  const applySql = valueOf('--apply')
  const prodFile = valueOf('--prod')
  const legsFile = valueOf('--legs')
  const valued = new Set(['--json', '--apply', '--prod', '--legs'].map((f) => args.indexOf(f) + 1).filter((i) => i > 0))
  const file = args.find((a, i) => !a.startsWith('--') && !valued.has(i)) ?? (await newestImage())
  console.log(`audit: world image ${path.basename(file)}; tolerance ${TOLERANCE_NM} nm; land = the chart's fine coast tiles`)
  const db = await openImage(file)
  if (applySql) {
    await db.exec('begin')
    await db.exec(readFileSync(applySql, 'utf8'))
    console.log(`audit: applied ${path.basename(applySql)} (rolled back after)`)
  }
  let world = await readWorldCourses(db)
  await db.close()
  if (prodFile) {
    // the CLI's json: { rows: [ { jsonb_build_object: {...} } ] }
    const unwrap = (f) => Object.values(JSON.parse(readFileSync(f, 'utf8')).rows[0])[0]
    world = worldFromExport(world, unwrap(prodFile), legsFile ? unwrap(legsFile) : null)
    console.log(`audit: PROD's courses from ${path.basename(prodFile)}${legsFile ? ` and ${path.basename(legsFile)}` : ''} on this image's raster`)
  }
  const t0 = Date.now()
  const out = auditWorld(world, { pairs: args.includes('--pairs'), raw: args.includes('--raw'), log: console.log })
  if (args.includes('--write-known')) {
    const codes = world.ports.filter((p) => p.rlat != null).map((p) => p.code).sort()
    const origins = new Set(codes.filter((_, i) => i % PAIR_SAMPLE_EVERY === 0))
    const sample = auditWorld(world, { pairs: true, pairFilter: (a) => origins.has(a.code) })
    const known = {
      note: 'scripts/db/audit-land-crossings.mjs --write-known. Courses and roadsteads still on the drawn land (owner row 352). EMPTY since 0440: a new crossing is fixed (scripts/build-land-channels.mjs), never listed. This list may only shrink.',
      toleranceNm: TOLERANCE_NM,
      crossings: [...new Set(out.crossings.filter((c) => c.kind !== 'pair').map((c) => c.key))].sort(),
      roadsteads: [...out.roadsteads].sort(),
      pairSample: { every: PAIR_SAMPLE_EVERY, pairs: sample.counted.pair, crossing: sample.crossings.filter((c) => c.kind === 'pair').length },
    }
    await writeFile(KNOWN_FILE, `${JSON.stringify(known, null, 1)}\n`)
    console.log(`audit: wrote ${path.relative(ROOT, KNOWN_FILE)} (${known.crossings.length} crossing(s), ${known.roadsteads.length} roadstead(s), pair sample ${known.pairSample.crossing}/${known.pairSample.pairs})`)
  }
  const byKind = {}
  const rows = {}
  for (const c of out.crossings) {
    byKind[c.kind] = (byKind[c.kind] ?? 0) + 1
    rows[c.kind] = (rows[c.kind] ?? 0) + c.rows
  }
  console.log(`audit: checked ${JSON.stringify(out.counted)} in ${Math.round((Date.now() - t0) / 1000)} s`)
  console.log(`audit: ${out.crossings.length} distinct course(s) cross over ${TOLERANCE_NM} nm of drawn land ${JSON.stringify(byKind)}; rows ${JSON.stringify(rows)}`)
  console.log(`audit: ${out.roadsteads.length} roadstead(s) on drawn land: ${out.roadsteads.join(' ')}`)
  const sorted = [...out.crossings].sort((a, b) => b.landNm - a.landNm)
  for (const c of sorted.slice(0, args.includes('--all') ? sorted.length : 40)) {
    const w = c.worst
    console.log(`  ${c.key.padEnd(18)} land ${String(c.landNm).padStart(6)} nm in ${c.runs} run(s); worst ${w.nm} nm at ${w.at.join(',')} near ${nearestHarbour(world.ports, w.at[0], w.at[1])}`)
  }
  if (jsonOut) await writeFile(jsonOut, JSON.stringify(out, null, 1))
  if (prodFile) {
    // THE DAILY PROD CHECK: anything crossing that the prod known list does not hold is NEW, and fails.
    const known = JSON.parse(readFileSync(PROD_KNOWN_FILE, 'utf8'))
    const isNew = out.crossings.filter((c) => !known.crossings.includes(c.key))
    const roadsNew = out.roadsteads.filter((r) => !known.roadsteads.includes(r))
    console.log(`audit: PROD — ${isNew.length} crossing(s) and ${roadsNew.length} roadstead(s) not on ${path.relative(ROOT, PROD_KNOWN_FILE)}${isNew.length ? ': ' + isNew.map((c) => c.key).join(', ') : ''}`)
    process.exit(isNew.length || roadsNew.length ? 1 : 0)
  }
  process.exit(out.crossings.length ? 1 : 0)
}
