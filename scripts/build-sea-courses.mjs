// build-sea-courses.mjs: A STORED COURSE FOR EVERY HARBOUR PAIR, PLOTTED BY THE BROWSER'S OWN COURSE AUTHOR (0482). LOCAL; not in CI.
//
//   node scripts/build-sea-courses.mjs --into=supabase/migrations/<0482's file> [--before=0482] [--json=<debug out.json>]
//
// Why: the server plots no course. cmd.do_sail refuses a SAIL with no course when the straight line crosses land (E_NO_COURSE), so a
// standing fleet job (0481) could sail only a course already sailed (a merchant lane, a coast course, her own past voyage), and an HQ
// card's trip needed the browser's chart to plot it. 0482 gives the server a stored course for every pair of harbours (public.sea_courses).
//
// What it does, with no second author of anything:
//   1. restores the cached world at the head before the named migration (the prefix cache; never from zero; the cache is only read);
//   2. plots the course of every pair of harbours (the first by code, "C" order, to the second), roadstead to roadstead, as THE course
//      author of the browser plots it (src/domain/passage proposeCourse: src/lib/sea findPath over the raster that world serves, then
//      refineCourse off the coast mask public/coast/mask.json, as src/live/worldStore.ts sets nav.coast). What scripts/build-sea-legs.mjs plots;
//   3. rounds every point to 4 decimals (about 11 m): whole numbers, lat and lon x 10,000;
//   4. holds each to the drawn land with the no-land audit's own reading (scripts/db/audit-land-crossings.mjs crossingsOf over truthLand,
//      and the server's law as src/lib/sea/refine.ts courseRefusedAt mirrors it): a course that crosses is left out and listed (`on_land`);
//   5. packs them: for each harbour, the courses to every harbour after it by code, each as zigzag base-128 varints of the first point and
//      then each point's difference from the one before (lat, lon, lat, lon, ...), concatenated, with the byte offset of each course;
//   6. decodes the packed bytes again and asks that world's own door, voyage.path_refusal (cmd.do_sail's question, with its allowances:
//      course_join_nm, 25 nm at each roadstead), of every course BOTH ways. A pair the door refuses either way is left out (listed);
//   7. writes the seed between the two SEED markers of --into (the migration), with the digest of the harbours, their roadsteads and the
//      raster it was plotted on (the migration refuses another world) and three probe courses in full (its self-assert decodes them).
// About 10 minutes: 32,131 searches on 12 threads (~1.5 minutes), then 64,000 path_refusal calls in PGlite (~7 minutes).
// RE-RUN IT (and ship the table again) after any migration that moves a roadstead or a harbour, or changes the raster or the coast mask.
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { navFromServed, findPath, refineCourse, coastMaskFrom, coastLand, courseRefusedAt } from '../src/lib/sea/index.ts'

/** The rounding every stored point gets: 4 decimals, kept as whole numbers. */
export const SCALE = 10000
export const SEED_BEGIN = '-- ═══ THE SEED: written by scripts/build-sea-courses.mjs, never by hand (BEGIN) ═══'
export const SEED_END = '-- ═══ THE SEED (END) ═══'

/** Zigzag base-128 varints of the first point and each point's difference from the one before. */
export function packCourse(pts) {
  const out = []
  let plat = 0
  let plon = 0
  for (const [lat, lon] of pts) {
    for (const v of [lat - plat, lon - plon]) {
      let z = v >= 0 ? 2 * v : -2 * v - 1
      while (z >= 128) {
        out.push((z % 128) | 128)
        z = Math.floor(z / 128)
      }
      out.push(z)
    }
    plat = lat
    plon = lon
  }
  return out
}

/** The inverse of {@link packCourse}: the whole-number points. */
export function unpackCourse(bytes) {
  const vals = []
  let z = 0
  let mul = 1
  for (const b of bytes) {
    z += (b & 127) * mul
    if (b < 128) {
      vals.push(z % 2 === 0 ? z / 2 : -(z + 1) / 2)
      z = 0
      mul = 1
    } else mul *= 128
  }
  const pts = []
  let lat = 0
  let lon = 0
  for (let k = 0; k + 1 < vals.length; k += 2) {
    lat += vals[k]
    lon += vals[k + 1]
    pts.push([lat, lon])
  }
  return pts
}

if (!isMainThread) {
  const { raster, hs, jobs } = workerData
  const nav = navFromServed(raster)
  // the coast mask the browser's course author steers by (src/domain/passage proposeCourse; src/live/worldStore.ts sets nav.coast so)
  const land = coastLand(coastMaskFrom(JSON.parse(readFileSync(workerData.mask, 'utf8'))), nav)
  const { truthLand, crossingsOf } = await import('./db/audit-land-crossings.mjs')
  const truth = truthLand(nav)
  const out = []
  for (const [i, j] of jobs) {
    const r = findPath(nav, { lat: hs[i].lat, lon: hs[i].lon }, { lat: hs[j].lat, lon: hs[j].lon })
    if (!r) {
      out.push([i, j, null, null])
      continue
    }
    const pts = refineCourse(nav, land, r.path).path.map(([lat, lon]) => [Math.round(lat * SCALE), Math.round(lon * SCALE)])
    const asLatLon = pts.map(([a, b]) => [a / SCALE, b / SCALE])
    const c = crossingsOf(truth, asLatLon)
    const at = courseRefusedAt(nav, asLatLon)
    out.push([i, j, pts, c.length || at ? { runs: c.length, landNm: Math.round(c.reduce((s, x) => s + x.nm, 0) * 10) / 10, refused: !!at } : null])
  }
  parentPort.postMessage(out)
  process.exit(0)
}

const { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } = await import('./db/apply-chain.mjs')
const { applyWithPrefixCache } = await import('./db/prefix-cache.mjs')
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const before = arg('before') ?? '0482'
const into = arg('into')
if (!into) throw new Error('usage: node scripts/build-sea-courses.mjs --into=supabase/migrations/<the migration that embeds the seed> [--before=0482]')
const files = []
for (const name of await migrationFiles()) {
  if (name.slice(10, 14) >= before) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
console.log(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)

const raster = (await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                                       replace(encode(cells, 'base64'), e'\\n', '') as cells_base64 from public.sea_raster where id = 1`)).rows[0]
// THE WORLD PLOTTED ON, digested exactly as the migration's guard and scripts/ops/harness/sea-courses/before-0482.sql digest it
const world = (await db.query(`select count(*)::int as harbours,
         md5(string_agg(p.code || ':' || sr.roadstead_lat::text || ':' || sr.roadstead_lon::text, ',' order by p.code collate "C")) as roadsteads,
         (select md5(r.cells) || ':' || r.cols || 'x' || r.rows || ':' || r.cell_deg from public.sea_raster r where r.id = 1) as raster
    from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR'`)).rows[0]
const hs = (await db.query(`select p.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon
                              from public.ports p join public.sea_reaches sr on sr.port_id = p.id
                             where p.kind = 'HARBOUR' order by p.code collate "C"`)).rows
const n = hs.length
const mask = path.join(REPO_ROOT, 'public', 'coast', 'mask.json')
console.log(`world digest: ${JSON.stringify(world)}`)

// 2-4. every pair, the first by code to the second, plotted and held to the drawn land on worker threads
let t0 = Date.now()
const pairs = []
for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) pairs.push([i, j])
const threads = Math.max(1, Math.min(12, os.availableParallelism() - 2))
const plotted = []
await Promise.all(Array.from({ length: threads }, (_, w) => new Promise((resolve, reject) => {
  const jobs = pairs.filter((_, k) => k % threads === w)
  const wk = new Worker(fileURLToPath(import.meta.url), { workerData: { raster, hs, jobs, mask } })
  wk.on('message', (m) => plotted.push(...m))
  wk.on('error', reject)
  wk.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`worker ${w} exit ${c}`))))
})))
plotted.sort((a, b) => a[0] - b[0] || a[1] - b[1])
const noWater = plotted.filter((p) => !(p[2] && p[2].length >= 2)).map(([i, j]) => `${hs[i].code}-${hs[j].code}`)
const onLand = plotted.filter((p) => p[3]).map(([i, j, , c]) => ({ pair: `${hs[i].code}-${hs[j].code}`, ...c }))
console.log(`plotted ${pairs.length} courses of ${n} harbours in ${Date.now() - t0} ms on ${threads} threads; ${noWater.length} pairs share no water; ${onLand.length} cross the drawn land`)
if (onLand.length) console.log('left out, on the drawn land (fix the coast, docs/NAVIGATION_PLAN.md section 8, then re-run):', onLand.slice(0, 40))

// 5. packed, and 6. decoded again and judged by the door both ways
t0 = Date.now()
const found = plotted.filter((p) => p[2] && p[2].length >= 2 && !p[3]).map(([i, j, pts]) => ({ i, j, bytes: packCourse(pts), plotted: pts }))
for (const c of found) {
  c.pts = unpackCourse(c.bytes)
  if (JSON.stringify(c.pts) !== JSON.stringify(c.plotted)) throw new Error(`${hs[c.i].code}-${hs[c.j].code}: the packed course does not decode to itself`)
}
const JUDGE = `select (e->>'k')::int as k,
       voyage.path_refusal(e->'c', (e->>'olat')::numeric, (e->>'olon')::numeric, (e->>'dlat')::numeric, (e->>'dlon')::numeric,
                           public.wc_num('course_join_nm'), 25, 25) as fwd,
       voyage.path_refusal(e->'r', (e->>'dlat')::numeric, (e->>'dlon')::numeric, (e->>'olat')::numeric, (e->>'olon')::numeric,
                           public.wc_num('course_join_nm'), 25, 25) as back
  from jsonb_array_elements($1::jsonb) e`
const asJson = (pts) => pts.map(([a, b]) => [a / SCALE, b / SCALE])
const refused = []
const keep = []
for (let s = 0; s < found.length; s += 500) {
  const chunk = found.slice(s, s + 500)
  const rows = (await db.query(JUDGE, [JSON.stringify(chunk.map((c, k) => ({
    k, c: asJson(c.pts), r: asJson(c.pts).reverse(), olat: hs[c.i].lat, olon: hs[c.i].lon, dlat: hs[c.j].lat, dlon: hs[c.j].lon,
  })))])).rows
  for (const r of rows) {
    const c = chunk[r.k]
    if (r.fwd || r.back) refused.push({ pair: `${hs[c.i].code}-${hs[c.j].code}`, why: String(r.fwd ?? r.back).slice(0, 80) })
    else keep.push(c)
  }
}
console.log(`judged ${found.length} decoded courses both ways in ${Date.now() - t0} ms: ${keep.length} kept, ${refused.length} refused ${JSON.stringify(refused)}`)

// 7. the seed: one row a harbour (the courses to the harbours after it by code)
const rows = []
let bytes = 0
let points = 0
for (let i = 0; i < n; i++) {
  const mine = keep.filter((c) => c.i === i)
  if (!mine.length) continue
  const offs = [0]
  const buf = []
  for (const c of mine) {
    buf.push(...c.bytes)
    offs.push(buf.length)
    points += c.pts.length
  }
  bytes += buf.length
  rows.push({ at: hs[i].code, tos: mine.map((c) => hs[c.j].code), offs, pts: Buffer.from(buf).toString('base64') })
}
const probeOf = (a, b) => {
  const i = hs.findIndex((h) => h.code === a)
  const j = hs.findIndex((h) => h.code === b)
  const c = keep.find((x) => x.i === Math.min(i, j) && x.j === Math.max(i, j))
  const pts = asJson(c.pts)
  return { from: a, to: b, course: i < j ? pts : pts.reverse() }
}
const probes = [probeOf('LIS', 'SET'), probeOf('LIS', 'HAG'), probeOf('VER', 'LIS')]
const seed = { scale: SCALE, world, courses: keep.length, points, bytes, refused: refused.map((r) => r.pair), no_water: noWater,
  on_land: onLand.map((c) => c.pair), probes, rows }
const body = `${SEED_BEGIN}\n-- ${keep.length} courses, ${points} points, ${bytes} bytes packed; plotted on ${JSON.stringify(world)}\n`
  + `create temp table seed_0482 on commit drop as select $seed$${JSON.stringify(seed)}$seed$::jsonb as doc;\n${SEED_END}`
const file = path.resolve(REPO_ROOT, into)
const text = await readFile(file, 'utf8')
const a = text.indexOf(SEED_BEGIN)
const b = text.indexOf(SEED_END)
if (a < 0 || b < a) throw new Error(`${into} holds no SEED markers`)
await writeFile(file, text.slice(0, a) + body + text.slice(b + SEED_END.length))
console.log(`wrote the seed into ${into}: ${rows.length} harbours, ${keep.length} courses, ${points} points, ${bytes} bytes packed (${body.length} characters)`)
if (arg('json')) await writeFile(arg('json'), JSON.stringify({ harbours: hs.map((h) => h.code), courses: keep.map((c) => [c.i, c.j, ...c.pts.flat()]) }))
await db.close()
process.exit(0)
