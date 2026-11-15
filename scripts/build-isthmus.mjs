#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-isthmus.mjs — AN APPROACH IS NOT A CANAL (owner row 352, migration 0441)
//
//   node scripts/build-isthmus.mjs [world-image.tar.gz] [--prod prod-courses.json]
//
// The owner, 2026-11-15: no ship crosses land, ever, and it must not happen again. 0440 took every
// stored course off the drawn land and left ONE case: Panama City to Portobelo, whose roadsteads lie
// 46 nm apart across the isthmus. voyage.path_refusal skipped every sample within 25 nm of each end
// of a course unread (its "approach allowance"), so the straight line between them had no sample
// left to read. 0441 changes the rule (the migration's header says how). This generator:
//
//   1. reads every stored course of the chain's world and of production's export
//      (scripts/ops/harness/no-land/prod-courses.sql, read only), and finds the ones the new rule
//      refuses (a raster land sample inside the old allowance) or that run over drawn land (a route
//      saved by a browser tab that had not reloaded since 0440);
//   2. re-sails each with the course author's own functions (src/lib/sea: refineCourse, and when the
//      old course cannot be mended, findPath then refineCourse), as scripts/build-land-channels.mjs did;
//   3. writes supabase/migrations/20260818000441_*.sql (scripts/isthmus.sql.mjs is its template), and
//      the prod checks and the forward rollback under scripts/ops/harness/isthmus/.
//
// The image is the chain BEFORE this migration (0440 applied). No prod load: it reads files.
// THEN: node scripts/ops/harness/isthmus/prod-shaped.mjs <image> courses.json legs.json loads production's own
// lanes, route stops and frozen legs into the image, applies the migration (its self-asserts run on prod's
// shape) and audits what it leaves.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// THE PAIR TABLE (0442): a migration this writes calls public.sea_leg_asks_keep() after it re-sails (the template's step), so no lane is left
// crossing a sea its pair's row does not hold and no moved roadstead is left in a sea its own row does not name. Then RE-RUN
// scripts/build-sea-legs.mjs and scripts/build-sea-legs-migration.mjs: the world guard holds public.sea_leg_asks equal to data/sea-legs.json.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { openImage, readWorldCourses, newestImage, truthLand, crossingsOf, readMask, flatAllowanceIsWater } from './db/audit-land-crossings.mjs'
import { gcNm } from './lib/drawn-land.mjs'
import { navFromServed, findPath, floodFrom, floodPathTo, snapToNav, cellLat, cellLon } from '../src/lib/sea/index.ts'
import { refineCourse, courseIsWater } from '../src/lib/sea/refine.ts'
import { coastLand } from '../src/lib/sea/coastMask.ts'
import { migrationSql, HUNKS, CUTOFF_HUNK } from './isthmus.sql.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const MIGRATION_NAME = process.env.MIGRATION_NAME ?? '20260818000441_an_approach_is_not_a_canal.sql'
const MIGRATION = path.join(ROOT, 'supabase', 'migrations', MIGRATION_NAME)
const HARNESS = path.join(ROOT, 'scripts', 'ops', 'harness', 'isthmus')
const md5 = (s) => createHash('md5').update(s).digest('hex')
const jsonbText = (course) => `[${course.map(([a, b]) => `[${a}, ${b}]`).join(', ')}]`

const argv = process.argv.slice(2)
const flagValue = (f) => (argv.indexOf(f) >= 0 ? argv[argv.indexOf(f) + 1] : null)
const prodFile = flagValue('--prod')
const file = argv.find((a, i) => !a.startsWith('--') && argv[i - 1] !== '--prod') ?? (await newestImage())
console.log(`isthmus: world image ${path.basename(file)}${prodFile ? `, and prod's courses from ${path.basename(prodFile)}` : ''}`)
const db = await openImage(file)
const world = await readWorldCourses(db)
const joinNm = Number((await db.query(`select public.wc_num('course_join_nm')::float8 as v`)).rows[0].v)
const head = (await db.query(`select max(version) as v from supabase_migrations.schema_migrations`).catch(() => ({ rows: [{ v: null }] }))).rows[0].v
const probe = (await db.query(`select '[[1.5,-2.25],[3,4.125]]'::jsonb::text as t`)).rows[0].t
if (probe !== jsonbText([[1.5, -2.25], [3, 4.125]])) throw new Error(`jsonb text rule: ${probe}`)
const reachRows = (await db.query(`select p.code, sr.reaches from public.sea_reaches sr join public.ports p on p.id = sr.port_id order by p.code`)).rows
await db.close()

const nav = navFromServed(world.raster)
const truth = truthLand(nav)
const land = coastLand(readMask(), nav)
const wet = (lat, lon) => nav.cells[Math.min(nav.rows - 1, Math.max(0, Math.floor((90 - lat) / nav.cellDeg))) * nav.cols + (((Math.floor((lon + 180) / nav.cellDeg) % nav.cols) + nav.cols) % nav.cols)] !== 0
const harbours = world.ports.filter((p) => Number.isFinite(p.rlat))
const dry = harbours.filter((p) => !wet(p.rlat, p.rlon)).map((p) => p.code)
if (dry.length) throw new Error(`roadsteads in a raster land cell: ${dry.join(' ')}: the rule "a roadstead has no approach" needs every one on water`)
console.log(`  ${harbours.length} harbours, every roadstead in a raster water cell (chain head ${head ?? '?'})`)

// ── 1. THE COURSES: the chain's, and production's ───────────────────────────────────────────────
const texts = new Map()
for (const c of world.npc) texts.set(c.text, c.course)
for (const r of world.routes) texts.set(r.text, r.course)
for (const c of world.coast) texts.set(c.text, c.course)
let prod = null
if (prodFile) {
  prod = Object.values(JSON.parse(readFileSync(prodFile, 'utf8')).rows[0])[0]
  if (prod.raster_md5 !== md5(world.raster.cells_base64.replace(/\s+/g, ''))) throw new Error('prod serves another raster than the image')
  for (const [code, lat, lon] of prod.roads) {
    const p = harbours.find((x) => x.code === code)
    if (!p || p.rlat !== Number(lat) || p.rlon !== Number(lon)) throw new Error(`prod's roadstead of ${code} is not the image's`)
  }
  for (const [, , text] of [...prod.npc, ...prod.coast]) texts.set(text, JSON.parse(text))
  for (const [, , text] of prod.stops) texts.set(text, JSON.parse(text))
}
const reversedText = (text) => `[${(text.match(/\[[^[\]]+\]/g) ?? []).reverse().join(', ')}]`
const len = (c) => c.reduce((s, p, i) => (i ? s + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : s), 0)
const landNm = (c) => crossingsOf(truth, c).reduce((s, x) => s + x.nm, 0)
/** The roadstead a course end belongs to: the point itself when it is one; else the nearest within the join
 *  (a route saved by a tab that still held the roadsteads as they were before 0440 moved them). */
const roadOf = (p) => {
  let best = null
  for (const h of harbours) {
    const d = gcNm(p[0], p[1], h.rlat, h.rlon)
    if (d === 0) return [h.rlat, h.rlon]
    if (d <= joinNm && (!best || d < best.d)) best = { d, at: [h.rlat, h.rlon] }
  }
  return best ? best.at : [p[0], p[1]]
}
const geomKey = (c) => c.map((p) => `${Number(p[0])},${Number(p[1])}`).join(';')
const sailed = new Map()
const fixes = []
const why = { refused: 0, land: 0, both: 0, ends: 0 }
let fresh = 0
let addNm = 0
let baseNm = 0
for (const [text, course] of texts) {
  const gk = geomKey(course)
  const rk = geomKey([...course].reverse())
  const again = sailed.get(gk) ?? (sailed.has(rk) ? [...sailed.get(rk)].reverse() : null)
  if (again) {
    const newText = jsonbText(again)
    if (newText !== text) fixes.push({ old: md5(text), course: newText, oldText: text })
    continue
  }
  const refused = !courseIsWater(nav, course)
  const crossed = crossingsOf(truth, course).length > 0
  if (!refused && !crossed) {
    sailed.set(gk, course)
    continue
  }
  if (refused && crossed) why.both++
  else if (refused) why.refused++
  else why.land++
  const start = roadOf(course[0])
  const end = roadOf(course[course.length - 1])
  if (start[0] !== course[0][0] || start[1] !== course[0][1] || end[0] !== course[course.length - 1][0] || end[1] !== course[course.length - 1][1]) why.ends++
  const ended = [start, ...course.slice(1, -1), end]
  const good = (t) => courseIsWater(nav, t) && landNm(t) === 0
  const tries = []
  const r = refineCourse(nav, land, ended)
  tries.push(r.changed ? r.path : ended)
  if (!good(tries[0])) {
    const found = findPath(nav, { lat: start[0], lon: start[1] }, { lat: end[0], lon: end[1] })
    if (found) {
      const p = [start, ...found.path.slice(1, -1), end]
      const rr = refineCourse(nav, land, p)
      tries.push(rr.changed ? rr.path : p)
    }
  }
  const ok = tries.filter(good)
  if (!ok.length) throw new Error(`no course by sea that the rule accepts and that is off the drawn land: ${text.slice(0, 200)}`)
  ok.sort((x, y) => len(x) - len(y))
  const pick = ok[0]
  if (pick !== tries[0]) fresh++
  sailed.set(gk, pick)
  const newText = jsonbText(pick)
  if (newText === text) throw new Error(`a refused course came back as it was: ${text.slice(0, 120)}`)
  addNm += len(pick) - len(course)
  baseNm += len(course)
  fixes.push({ old: md5(text), course: newText, oldText: text })
}
// EVERY REPLACED COURSE BACKWARDS TOO (0440's rule): the world copies its courses at run time, forwards or
// backwards (public.npc_rehome, public.npc_feasible_legs), so a row written after the export is caught.
const have = new Set(fixes.map((f) => f.old))
for (const f of [...fixes]) {
  const back = reversedText(f.oldText)
  if (back === f.oldText || texts.has(back) || have.has(md5(back))) continue
  fixes.push({ old: md5(back), course: jsonbText(JSON.parse(f.course).reverse()), oldText: back, backwards: true })
  have.add(md5(back))
}
fixes.sort((x, y) => (x.old < y.old ? -1 : 1))
for (const f of fixes) {
  const c = JSON.parse(f.course)
  if (!courseIsWater(nav, c) || landNm(c) > 0) throw new Error(`a new course is refused or on the land: ${f.course.slice(0, 160)}`)
  if (!flatAllowanceIsWater(nav, c)) throw new Error(`a new course is refused by the rule as it stood: ${f.course.slice(0, 160)}`)
}
const fixed = new Map(fixes.map((f) => [f.old, f]))
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
      head: prod.head,
    }
  : null
const longer = ((addNm / Math.max(baseNm, 1)) * 100).toFixed(2)
console.log(
  `  courses: ${texts.size} distinct; ${why.refused + why.both} refused by the new rule (${why.both} of them also over drawn land), ${why.land} over drawn land only; ` +
    `${why.ends} with an end off its roadstead; ${fixes.length} re-sailed (${fixes.filter((f) => f.backwards).length} backwards entries, ${fresh} from a fresh search); ${longer}% longer`,
)
console.log(`  the chain's world: lanes ${lanes}/${world.npc.length}, route stops ${stops}/${world.routes.length}, coast courses ${coast}/${world.coast.length}`)
if (prodCounts) console.log(`  prod (${prodCounts.at}, head ${prodCounts.head}): lanes ${prodCounts.lanes}/${prodCounts.npc}, route stops ${prodCounts.stops}/${prodCounts.routes}, coast ${prodCounts.coast}/${prod.coast.length}`)

// ── 2. THE REACH TABLE, MEASURED AND NOT WRITTEN (public.sea_reaches.reaches: the distance the quay quotes) ──────
// The quay quotes the search's own distance, roads to roads (0076). Where the search's course changes with the rule
// (its straightener may no longer skip 21 nm at each end), the sailed distance moves off the quote. This measures
// by how much: each pair by one flood, straightened by the rule as it stood and as it stands. The figures go into
// the migration's header and the dev-log. They are NOT written to the table: a new reach re-prices every market
// row that holds a haul (world.haul_rows(); the world guard refuses the image otherwise), which is its own slice.
const reachOf = new Map(reachRows.map((r) => [r.code, r.reaches]))
const diag = nav.cellDeg * 60 * Math.SQRT2
const lenOf = (c) => c.reduce((t, p, i) => (i ? t + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : t), 0)
/** The flood's course to a point, straightened by the rule as it stood (every sample within the cell diagonal of an end unread). */
const oldCourse = (flood, from, to) => {
  const b = snapToNav(nav, to.lat, to.lon)
  const chain = []
  for (let n = b.row * nav.cols + b.col; n !== -1; n = flood.prev[n]) chain.push(n)
  chain.reverse()
  const pts = [[from.lat, from.lon], ...chain.map((n) => [cellLat(nav, (n / nav.cols) | 0), cellLon(nav, n % nav.cols)]), [to.lat, to.lon]]
  const out = [pts[0]]
  let i = 0
  while (i < pts.length - 1) {
    let j = pts.length - 1
    for (; j > i + 1; j--) if (flatAllowanceIsWater(nav, [pts[i], pts[j]], i === 0 ? diag : 0, j === pts.length - 1 ? diag : 0)) break
    out.push(pts[j])
    i = j
  }
  return out
}
const reachFix = new Map() // code -> { other: nm }
let reachPairs = 0
let reachMax = { d: 0 }
let reachSum = 0
let ruleSum = 0
let ruleMax = { d: 0 }
let ruleOver = 0
for (let i = 0; i < harbours.length; i++) {
  const a = harbours[i]
  const ra = { lat: a.rlat, lon: a.rlon }
  const flood = floodFrom(nav, ra)
  if (!flood || flood.source.snapNm !== 0) throw new Error(`${a.code}: its roadstead does not stand on sailable water`)
  for (let j = i + 1; j < harbours.length; j++) {
    const b = harbours[j]
    const rb = { lat: b.rlat, lon: b.rlon }
    if (ra.lat === rb.lat && ra.lon === rb.lon) continue
    const now = floodPathTo(flood, ra, rb)
    if (!now) throw new Error(`${a.code} to ${b.code}: no way by sea`)
    if (!courseIsWater(nav, now.path)) throw new Error(`${a.code} to ${b.code}: the search's own course is refused by the rule`)
    const was = lenOf(oldCourse(flood, ra, rb))
    if (Math.abs(now.nm - was) < 0.05) continue
    const nm = Number(now.nm.toFixed(1))
    const stored = Number(reachOf.get(a.code)[b.code])
    if (nm === stored) continue
    for (const [x, y] of [[a.code, b.code], [b.code, a.code]]) {
      if (!reachFix.has(x)) reachFix.set(x, {})
      reachFix.get(x)[y] = nm
    }
    reachPairs++
    reachSum += nm - stored
    ruleSum += now.nm - was
    if ((now.nm - was) / was > 0.005) ruleOver++
    if (Math.abs(now.nm - was) > Math.abs(ruleMax.d)) ruleMax = { d: Number((now.nm - was).toFixed(1)), k: `${a.code}-${b.code}`, was: Number(was.toFixed(1)), nm }
    if (Math.abs(nm - stored) > Math.abs(reachMax.d)) reachMax = { d: nm - stored, k: `${a.code}-${b.code}`, was: stored, nm }
  }
  if (i % 50 === 0) console.log(`  reaches: ${i + 1}/${harbours.length} floods`)
}
const reach = {
  pairs: reachPairs,
  rows: [...reachFix.entries()].sort((x, y) => (x[0] < y[0] ? -1 : 1)).map(([code, add]) => ({ code, add, was: Object.fromEntries(Object.keys(add).sort().map((k) => [k, Number(reachOf.get(code)[k])])) })),
  meanNm: reachPairs ? (reachSum / reachPairs).toFixed(2) : '0',
  max: reachMax,
  ruleMeanNm: reachPairs ? (ruleSum / reachPairs).toFixed(2) : '0',
  ruleMax,
  ruleOver,
}
console.log(`  reaches: ${reach.pairs} pair(s) whose search course changed with the rule, in ${reach.rows.length} row(s); against the stored figure: mean ${reach.meanNm} nm, largest ${reachMax.k} ${reachMax.was} -> ${reachMax.nm}; by the rule alone: mean ${reach.ruleMeanNm} nm, ${ruleOver} over half a per cent, largest ${ruleMax.k} ${ruleMax.was} -> ${ruleMax.nm}`)

// ── 3. THE CONTROLS the self-assert holds ───────────────────────────────────────────────────────
const P = (code) => harbours.find((p) => p.code === code)
const pan = P('PAN')
const prt = P('PRT')
const canal = [[pan.rlat, pan.rlon], [prt.rlat, prt.rlon]]
if (!flatAllowanceIsWater(nav, canal)) throw new Error('the Panama control was refused before: it proves nothing')
if (courseIsWater(nav, canal)) throw new Error('the Panama control is still accepted')
const bySea = findPath(nav, { lat: pan.rlat, lon: pan.rlon }, { lat: prt.rlat, lon: prt.rlon })
if (!bySea) throw new Error('no way by sea from Panama City to Portobelo')
const bySeaCourse = refineCourse(nav, land, bySea.path).path
if (!courseIsWater(nav, bySeaCourse) || landNm(bySeaCourse) > 0) throw new Error('the course by sea from Panama City to Portobelo is refused or on the land')
console.log(`  Panama City to Portobelo: the straight line (${len(canal).toFixed(1)} nm) is refused; the course by sea is ${Math.round(len(bySeaCourse))} nm in ${bySeaCourse.length} points`)

const sql = migrationSql({ name: MIGRATION_NAME, fixes, texts: texts.size, why, fresh, longer, lanes, npc: world.npc.length, stops, routes: world.routes.length, coast, coasts: world.coast.length, prodCounts, joinNm, reach, harbours: harbours.length, canalNm: len(canal).toFixed(1), bySeaNm: Math.round(len(bySeaCourse)) })
writeFileSync(MIGRATION, sql)
console.log(`wrote ${path.relative(ROOT, MIGRATION)} (${fixes.length} course(s); ${Math.round(sql.length / 1024)} KB)`)

// ── 4. THE PROD CHECKS AND THE FORWARD ROLLBACK ────────────────────────────────────────────────
mkdirSync(HARNESS, { recursive: true })
const oldMd5s = fixes.map((f) => `('${f.old}')`).join(', ')
const newMd5s = [...new Set(fixes.map((f) => md5(f.course)))].map((m) => `('${m}')`).join(', ')
writeFileSync(
  path.join(HARNESS, 'before.sql'),
  `-- before.sql: READ ONLY on prod, one statement, BEFORE 0441 is pushed (generated by scripts/build-isthmus.mjs: do not edit by hand).
-- Want head 20260818000440, hunks_fit ${HUNKS.length + 1} (every hunk's old text occurs once in the deployed body), canal_open true (the straight
-- line from Panama City's roads to Portobelo's is accepted today: the fault).${prodCounts ? `
-- At the export (${prodCounts.at}): lanes_replaced ${prodCounts.lanes} of ${prodCounts.npc}, stops_replaced ${prodCounts.stops} (rows written since may add a few).` : ''}
-- Calls only pg_get_functiondef and voyage.path_refusal (STABLE), once.
begin transaction read only;
with f(m) as (values ${oldMd5s}),
h(fn, old) as (values
${[...HUNKS, CUTOFF_HUNK].map((h) => `  ('${h.fn}', $h$${h.old}$h$)`).join(',\n')})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'hunks_fit', (select count(*) from h where (length(replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', '')) - length(replace(replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', ''), h.old, ''))) / length(h.old) = 1),
  'canal_open', (select voyage.path_refusal(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)),
                                            a.roadstead_lat, a.roadstead_lon, b.roadstead_lat, b.roadstead_lon, ${joinNm}, 25, 25) is null
                   from public.sea_reaches a join public.ports pa on pa.id = a.port_id and pa.code = 'PAN',
                        public.sea_reaches b join public.ports pb on pb.id = b.port_id and pb.code = 'PRT'),
  'lanes_total', (select count(*) from public.npc_courses),
  'lanes_replaced', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from f)),
  'coast_replaced', (select count(*) from public.npc_coast_courses c where md5(c.course::text) in (select m from f)),
  'stops_replaced', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from f)));
rollback;
`,
)
writeFileSync(
  path.join(HARNESS, 'after.sql'),
  `-- after.sql: READ ONLY on prod, one statement, AFTER 0441 (generated by scripts/build-isthmus.mjs: do not edit by hand).
-- Want head 20260818000441, lanes_old 0, coast_old 0, stops_old 0, canal_refused true (E_LAND), by_sea_ok true (the stored course the
-- rule accepts: one re-sailed lane, judged as cmd.do_sail judges it), rule_in 1.
-- Then, the same day: export prod's courses and legs (scripts/ops/harness/no-land/prod-courses.sql, prod-legs.sql) and run
--   node scripts/db/audit-land-crossings.mjs <image> --prod courses.json --legs legs.json
-- which now also lists every stored course the server's law refuses. Want 0.
begin transaction read only;
with o(m) as (values ${oldMd5s}), n(m) as (values ${newMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_old', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from o)),
  'coast_old', (select count(*) from public.npc_coast_courses c where md5(c.course::text) in (select m from o)),
  'stops_old', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from o)),
  'lanes_new', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from n)),
  'rule_in', (select count(*) from pg_proc p where p.oid = 'voyage.path_refusal(jsonb,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure
                and pg_get_functiondef(p.oid) like '%0441 AN APPROACH IS THE LAND AN END STANDS IN%'),
  'canal_refused', (select voyage.path_refusal(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)),
                                               a.roadstead_lat, a.roadstead_lon, b.roadstead_lat, b.roadstead_lon, ${joinNm}, 25, 25)
                      from public.sea_reaches a join public.ports pa on pa.id = a.port_id and pa.code = 'PAN',
                           public.sea_reaches b join public.ports pb on pb.id = b.port_id and pb.code = 'PRT'),
  'by_sea_ok', (select voyage.path_refusal(c.course, (c.course -> 0 ->> 0)::numeric, (c.course -> 0 ->> 1)::numeric,
                                           (c.course -> -1 ->> 0)::numeric, (c.course -> -1 ->> 1)::numeric, ${joinNm}, 25, 25) is null
                  from public.npc_courses c where md5(c.course::text) in (select m from n) order by c.from_port, c.to_port limit 1));
rollback;
`,
)

// one new course may stand for several old texts (51.45 and 51.4500): the rollback takes the first, as 0440's does
const seenNew = new Set()
const backOnce = fixes.filter((f) => !f.backwards && !seenNew.has(md5(f.course)) && seenNew.add(md5(f.course))).map((f) => `    ('${md5(f.course)}', '${f.oldText}')`)

writeFileSync(
  path.join(HARNESS, 'rollback-0441.sql'),
  `-- rollback-0441.sql: the FORWARD rollback of 0441 (generated by scripts/build-isthmus.mjs: do not edit by hand). Cut it as the next
-- migration if the owner wants it undone: the rule's hunks come back out (voyage.path_refusal skips the allowance unread again, and
-- Panama City to Portobelo is a canal again), and the re-sailed courses go back. (Frozen cargo and patrol legs keep their pieces: a
-- circuit is rebuilt by public.cargo_circuit_build when its ships are home.) The courses must go back LAST: the old rule accepts both sets.
do $$
declare
  v_def text;
  v_n int;
  v_cut text;
begin
  -- every hunk of voyage.path_refusal comes out of the text first, and the body is replaced once
  v_def := replace(pg_get_functiondef('${HUNKS[0].fn}'::regprocedure), E'\\r', '');
${HUNKS.map(
  (h) =>
    `  v_n := (length(v_def) - length(replace(v_def, $h$${h.new}$h$, ''))) / length($h$${h.new}$h$);\n` +
    `  if v_n <> 1 then raise exception 'rollback-0441: a 0441 hunk of ${h.fn} occurs % time(s)', v_n; end if;\n` +
    `  v_def := replace(v_def, $h$${h.new}$h$, $h$${h.old}$h$);`,
).join('\n')}
  execute v_def;
  -- the land guard's cut-off line carries the instant 0441 applied: found by its own words, taken out whole
  v_def := replace(pg_get_functiondef('${CUTOFF_HUNK.fn}'::regprocedure), E'\\r', '');
  v_cut := substring(v_def from $re$    -- 0441 AN APPROACH IS NOT A CANAL\\..*?end if;\\n$re$);
  if v_cut is null then raise exception 'rollback-0441: the cut-off hunk of ${CUTOFF_HUNK.fn} is not there'; end if;
  execute replace(v_def, v_cut, '');
end
$$;
create function pg_temp.back_0441() returns table (new_md5 text, course jsonb) language sql immutable as $b$
  select v.m, v.c::jsonb from (values
${backOnce.join(',\n')}
  ) as v(m, c)
$b$;
update public.npc_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0441() b where md5(c.course::text) = b.new_md5;
update public.npc_coast_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0441() b where md5(c.course::text) = b.new_md5;
update public.standing_route_stops s set course = b.course,
       course_nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0441() b where md5(s.course::text) = b.new_md5;
`,
)
console.log(`wrote ${path.relative(ROOT, HARNESS)}/before.sql, after.sql, rollback-0441.sql`)
