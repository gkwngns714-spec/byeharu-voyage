// build-sea-legs.mjs: THE SEAS OF EVERY HARBOUR PAIR, FROM THE COURSE A FLEET REALLY SAILS (0403). LOCAL; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/build-sea-legs.mjs --before=0403 [--courses=<file.json>]
//
// Why: public.sea_leg_asks (0215, 0222) was derived from the STRAIGHT line between two roadsteads. The sail door (public.sea_gate) judges the course
// the player's client plots, which goes round the land. Trade's board and the server's pathfinder read the pair table, so they could offer a harbour
// the door then refused, or hide one it would open (docs/SEA_CONDITIONS_AND_REGIONS.md 10.6, "the board and the door").
//
// What it does, with no second author of anything:
//   1. restores the cached world at the head before the named migration (never from zero; the cache is only read);
//   2. plots the course of every ordered pair of harbours, roadstead to roadstead, as THE course author of the browser plots it (src/domain/passage
//      proposeCourse: src/lib/sea findPath over the raster that world serves, then, since 0440, refineCourse off the coast mask public/coast/mask.json).
//      That is the course the browser sends the sail door, so it is the course the pair row must name the seas of;
//   3. asks that world's own public.course_zones (the door's sampler) for the seas of each course;
//   3b. (0442) adds, to a pair's seas, the seas of the course that world REMEMBERS on the pair (public.npc_courses): a row never asks less than a course
//      the world holds (0403's rule, proof 98 ROW_HOLDS_COURSE). A lane is a re-sailed older course, not always the course plotted today;
//   4. writes data/sea-legs.json: the harbours in code order, the distinct sets of seas, and for each harbour one index per harbour;
// Then scripts/build-sea-legs-migration.mjs writes the migration that ships the file (0442 was the first written so), and proof 98's courses.
// RE-RUN IT AFTER ANY MIGRATION THAT RE-SAILS STORED COURSES OR MOVES A ROADSTEAD (scripts/build-land-channels.mjs, scripts/build-isthmus.mjs): 0440 moved
// 69 roadsteads and re-sailed the lanes and left this table as it was; 18 lanes then crossed a sea their row did not hold, and Galle's own row named a
// sea its roadstead had left (0442 is the repair). tests/sea.noLandCrossing.spec.ts and proof 98 hold the table to the courses.
// The migration embeds that file; scripts/db/world-guard.mjs holds public.sea_leg_asks equal to it. RE-RUN THIS whenever a sea box, the sea raster, a
// roadstead or the harbour list changes (public.sea_leg_asks_derive, the straight line, is no longer the table's author).
//
// About 15 minutes: 61,752 searches on 12 threads (3.5 minutes), then 61,752 public.course_zones calls in PGlite (10 minutes).
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { navFromServed, findPath, refineCourse, coastMaskFrom, coastLand } from '../src/lib/sea/index.ts'

if (!isMainThread) {
  const { raster, hs, from, to } = workerData
  const nav = navFromServed(raster)
  // the coast mask the browser's course author steers by (src/domain/passage proposeCourse, since 0440)
  const land = coastLand(coastMaskFrom(JSON.parse(readFileSync(workerData.mask, 'utf8'))), nav)
  for (let i = from; i < to; i++) {
    const row = []
    for (let j = 0; j < hs.length; j++) {
      if (i === j) { row.push(null); continue }
      const r = findPath(nav, { lat: hs[i].lat, lon: hs[i].lon }, { lat: hs[j].lat, lon: hs[j].lon })
      row.push(r ? refineCourse(nav, land, r.path).path : null)
    }
    parentPort.postMessage({ i, row })
  }
  process.exit(0)
}

const { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } = await import('./db/apply-chain.mjs')
const { applyWithPrefixCache } = await import('./db/prefix-cache.mjs')
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const before = arg('before')
if (!before) throw new Error('usage: node scripts/build-sea-legs.mjs --before=<the migration number that will embed the file, e.g. 0403>')
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
const hs = (await db.query(`select p.code, sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon, public.harbour_zone(p.id) as zone
                              from public.ports p join public.sea_reaches sr on sr.port_id = p.id
                             where p.kind = 'HARBOUR' order by p.code collate "C"`)).rows
const n = hs.length

// 2. every ordered pair, plotted as the browser plots it
const threads = Math.max(1, Math.min(12, os.availableParallelism() - 2))
const courses = new Array(n)
let t0 = Date.now()
await Promise.all(Array.from({ length: threads }, (_, w) => new Promise((resolve, reject) => {
  const from = Math.floor((n * w) / threads)
  const to = Math.floor((n * (w + 1)) / threads)
  const wk = new Worker(fileURLToPath(import.meta.url), { workerData: { raster, hs, from, to, mask: path.join(REPO_ROOT, 'public', 'coast', 'mask.json') } })
  wk.on('message', (m) => { courses[m.i] = m.row })
  wk.on('error', reject)
  wk.on('exit', (c) => (c === 0 ? resolve() : reject(new Error(`worker ${w} exit ${c}`))))
})))
console.log(`plotted ${n * (n - 1)} courses of ${n} harbours on ${threads} threads in ${Date.now() - t0} ms`)
if (arg('courses')) await writeFile(arg('courses'), JSON.stringify({ harbours: hs.map((h) => h.code), courses }))

// 3. the door's own sampler names the seas of each course
t0 = Date.now()
const sets = []
const setIdx = new Map()
const idxOf = (zones) => {
  const k = zones.join(' ')
  if (!setIdx.has(k)) { setIdx.set(k, sets.length); sets.push(k) }
  return setIdx.get(k)
}
// 3b. the courses that world remembers, by pair
const remembered = new Map()
for (const r of (await db.query(`select a.code as a, b.code as b, public.course_zones(n.course) as zones
                                   from public.npc_courses n join public.ports a on a.id = n.from_port join public.ports b on b.id = n.to_port`)).rows) remembered.set(`${r.a} ${r.b}`, r.zones)
let rememberedAdds = 0
const legs = []
let unplotted = 0
for (let i = 0; i < n; i++) {
  const pairs = []
  for (let j = 0; j < n; j++) if (i !== j && courses[i][j]) pairs.push({ j, c: courses[i][j] })
  const { rows } = await db.query(
    `select (e->>'j')::int as j, public.course_zones(e->'c') as zones from jsonb_array_elements($1::jsonb) e`, [JSON.stringify(pairs)])
  const row = new Array(n).fill(-1)   // -1: no water course between the two; the migration leaves that row as the straight line made it
  row[i] = idxOf([hs[i].zone])
  for (const r of rows) {
    if (!r.zones.length) throw new Error(`${hs[i].code} to ${hs[r.j].code}: the course crosses no sea`)
    const lane = remembered.get(`${hs[i].code} ${hs[r.j].code}`)
    if (lane && lane.some((z) => !r.zones.includes(z))) {
      rememberedAdds++
      row[r.j] = idxOf([...new Set([...r.zones, ...lane])].sort())
    } else row[r.j] = idxOf(r.zones)
  }
  unplotted += row.filter((x) => x < 0).length
  legs.push(row)
}
console.log(`seas of every course in ${Date.now() - t0} ms: ${sets.length} distinct sets, ${unplotted} pairs with no water course; ${rememberedAdds} of ${remembered.size} remembered courses add a sea to their pair`)

const body = `{\n"note": "Generated by scripts/build-sea-legs.mjs; never hand-edited. legs[i][j] is the index in sets of the seas the plotted course from harbours[i] to harbours[j] crosses (i = j: the harbour's own sea; -1: no water course).",\n`
  + `"harbours": ${JSON.stringify(hs.map((h) => h.code))},\n"sets": ${JSON.stringify(sets)},\n"legs": [\n${legs.map((r) => JSON.stringify(r)).join(',\n')}\n]\n}\n`
await writeFile(path.join(REPO_ROOT, 'data', 'sea-legs.json'), body)
console.log(`wrote data/sea-legs.json, ${body.length} bytes`)
await db.close()
process.exit(0)
