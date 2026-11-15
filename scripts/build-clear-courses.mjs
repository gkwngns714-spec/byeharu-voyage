#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-clear-courses.mjs — EVERY STORED LANE, RE-SAILED OFF THE DRAWN LAND (owner row 352)
//
//   node scripts/build-clear-courses.mjs [world-image.tar.gz]
//
// Writes migration 0440 (MIGRATION below). Reads a world image of the applied chain (no prod load):
// every course in public.npc_courses (the merchant, cargo, pirate and navy lanes) and every
// distinct course of public.standing_route_stops, and re-sails each through src/lib/sea/refine.ts
// against the coast mask (public/coast/mask.json, src/lib/sea/coastMask.ts): the same function and
// the same mask the browser's course author uses, so a lane and a player's course are held off the
// same land. A course that crosses no drawn land is left exactly as it is.
//
// The migration names each course it replaces by md5(course::text), never by its text, and gives
// the new course whole; it rewrites every row that holds that exact course, in npc_courses,
// standing_route_stops and the cargo circuits' frozen legs, and remembers the new course's seas.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { openImage, readWorldCourses, newestImage, truthLand, crossingsOf } from './db/audit-land-crossings.mjs'
import { MASK_FILE } from './build-coast-mask.mjs'
import { navFromServed } from '../src/lib/sea/index.ts'
import { refineCourse, courseIsWater } from '../src/lib/sea/refine.ts'
import { coastMaskFrom, coastLand } from '../src/lib/sea/coastMask.ts'
import { drawnLand, gcNm } from './lib/drawn-land.mjs'
import { migrationSql, SOCOTRA } from './clear-courses.sql.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const MIGRATION = path.join(ROOT, 'supabase', 'migrations', '20260818000440_no_course_crosses_the_drawn_land.sql')
const md5 = (s) => createHash('md5').update(s).digest('hex')

/**
 * Postgres's jsonb text of a course (`course::text`): `[[a, b], [c, d]]`, numbers as written. The
 * md5 the migration matches on is of THIS text, so the two must agree to the byte; the world image
 * is asked for its own text (readWorldCourses' `text`), and this is only used for new courses.
 */
const jsonbText = (course) => `[${course.map(([a, b]) => `[${a}, ${b}]`).join(', ')}]`

const file = process.argv[2] ?? (await newestImage())
const db = await openImage(file)
const world = await readWorldCourses(db)
const mask = coastMaskFrom(JSON.parse(readFileSync(MASK_FILE, 'utf8')))
const rasterMd5 = md5(world.raster.cells_base64.replace(/\s+/g, ''))
const maskPayload = JSON.parse(readFileSync(MASK_FILE, 'utf8'))
if (maskPayload.raster.md5 !== rasterMd5) {
  throw new Error(`the coast mask was cut for raster ${maskPayload.raster.md5}, the image serves ${rasterMd5}: run scripts/build-coast-mask.mjs first`)
}
const nav = navFromServed(world.raster)
const land = coastLand(mask, nav)
const truth = truthLand(nav, drawnLand('fine'))

// Every distinct course, keyed by Postgres's own text of it.
const texts = new Map() // text -> course
for (const c of world.npc) texts.set(c.text, c.course)
for (const r of world.routes) texts.set(r.text, r.course)
// Check the text rule once against the database's own (so new courses are keyed right).
const probe = (await db.query(`select '[[1.5,-2.25],[3,4.125]]'::jsonb::text as t`)).rows[0].t
if (probe !== jsonbText([[1.5, -2.25], [3, 4.125]])) throw new Error(`jsonb text rule: ${probe}`)
await db.close()


const len = (c) => c.reduce((s, p, i) => (i ? s + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : s), 0)

const inSocotra = (course) => {
  let n = 0
  for (let i = 0; i + 1 < course.length; i++) {
    const [a, b] = [course[i], course[i + 1]]
    const steps = Math.max(1, Math.ceil(gcNm(a[0], a[1], b[0], b[1])))
    for (let s = 0; s <= steps; s++) {
      const lat = a[0] + ((b[0] - a[0]) * s) / steps
      const lon = a[1] + ((b[1] - a[1]) * s) / steps
      if (lat >= SOCOTRA.south && lat <= SOCOTRA.north && lon >= SOCOTRA.west && lon <= SOCOTRA.east) n++
    }
  }
  return n
}
const fine = drawnLand('fine')
for (let la = SOCOTRA.south; la <= SOCOTRA.north + 1e-9; la += 0.005) {
  for (let lo = SOCOTRA.west; lo <= SOCOTRA.east + 1e-9; lo += 0.005) {
    if (!fine.isLand(la, lo)) throw new Error(`the Socotra control box is not all drawn land at ${la},${lo}`)
  }
}

const fixes = []
let before = 0
let after = 0
let addNm = 0
let baseNm = 0
let control = null
for (const [text, course] of texts) {
  const was = crossingsOf(truth, course).length
  if (was) before++
  const r = refineCourse(nav, land, course)
  if (!r.changed) {
    if (was) after++
    continue
  }
  if (!courseIsWater(nav, r.path)) throw new Error(`refine broke the raster rule on ${text}`)
  if (crossingsOf(truth, r.path).length) after++
  const newText = jsonbText(r.path)
  if (newText === text) continue
  addNm += len(r.path) - len(course)
  baseNm += len(course)
  const fix = { old: md5(text), course: newText }
  fixes.push(fix)
  const crossed = inSocotra(course)
  if (crossed && !inSocotra(r.path) && (!control || crossed > control.crossed)) control = { ...fix, crossed }
}
if (!control) throw new Error("no re-sailed course crossed Socotra: the owner's own example has no control")
fixes.sort((a, b) => (a.old < b.old ? -1 : 1))
const fixed = new Set(fixes.map((f) => f.old))
const lanes = world.npc.filter((c) => fixed.has(md5(c.text))).length
const stops = world.routes.filter((r) => fixed.has(md5(r.text))).length
const longer = ((addNm / Math.max(baseNm, 1)) * 100).toFixed(2)
console.log(
  `clear courses: ${texts.size} distinct course(s); ${before} crossed drawn land; ${fixes.length} re-sailed; ${after} still cross; ` +
    `lanes ${lanes}/${world.npc.length}, route stops ${stops}/${world.routes.length}; the re-sailed ones ${longer}% longer; ` +
    `Socotra control ${control.old} (${control.crossed} nm in the box before)`,
)

const values = fixes.map((f) => `    ('${f.old}', '${f.course}')`).join(',\n')
const sql = migrationSql({
  values, texts: texts.size, before, fixes: fixes.length, after, lanes, npc: world.npc.length, stops, routes: world.routes.length, longer, raster: rasterMd5, control,
})
writeFileSync(MIGRATION, sql)
console.log(`wrote ${path.relative(ROOT, MIGRATION)} (${fixes.length} course(s), ${Math.round(sql.length / 1024)} KB)`)

// ── THE PROD CHECKS AND THE FORWARD ROLLBACK (scripts/ops/harness/no-land/) ─────────────────────
// before.sql / after.sql: ONE read-only statement each, md5s and counts only. rollback-0440.sql puts
// every replaced course back (by the md5 of the new course), should the owner want the old lanes.
const HARNESS = path.join(ROOT, 'scripts', 'ops', 'harness', 'no-land')
mkdirSync(HARNESS, { recursive: true })
const oldMd5s = fixes.map((f) => `('${f.old}')`).join(', ')
const newMd5s = fixes.map((f) => `('${md5(f.course)}')`).join(', ')
const textByMd5 = new Map([...texts.keys()].map((t) => [md5(t), t]))
writeFileSync(
  path.join(HARNESS, 'before.sql'),
  `-- before.sql: READ ONLY on prod, one statement, BEFORE 0440 is pushed (generated by scripts/build-clear-courses.mjs: do not edit by hand).
-- How many live rows hold a course 0440 replaces (want lanes ${lanes} as in the image, the Hadibu control there), and the head.
begin transaction read only;
with f(m) as (values ${oldMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_total', (select count(*) from public.npc_courses),
  'lanes_replaced', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from f)),
  'stops_total', (select count(*) from public.standing_route_stops where course is not null),
  'stops_replaced', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from f)),
  'cargo_legs', (select count(*) from public.cargo_circuit_legs),
  'hadibu_control_present', exists (select 1 from public.npc_courses c where md5(c.course::text) = '${control.old}'),
  'sailing', (select count(*) from public.voyages v where v.status = 'SAILING'));
rollback;
`,
)
writeFileSync(
  path.join(HARNESS, 'after.sql'),
  `-- after.sql: READ ONLY on prod, one statement, AFTER 0440 (generated by scripts/build-clear-courses.mjs: do not edit by hand).
-- Want lanes_old 0 and stops_old 0, lanes_new ${lanes}, and Hadibu -> Kilwa with more than 2 points.
begin transaction read only;
with o(m) as (values ${oldMd5s}), n(m) as (values ${newMd5s})
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes_old', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from o)),
  'stops_old', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from o)),
  'lanes_new', (select count(*) from public.npc_courses c where md5(c.course::text) in (select m from n)),
  'stops_new', (select count(*) from public.standing_route_stops s where md5(s.course::text) in (select m from n)),
  'hadibu_kilwa_points', (select jsonb_array_length(c.course) from public.npc_courses c join public.ports a on a.id = c.from_port
                           join public.ports b on b.id = c.to_port where a.code = 'HAD' and b.code = 'KIL'));
rollback;
`,
)
writeFileSync(
  path.join(HARNESS, 'rollback-0440.sql'),
  `-- rollback-0440.sql: the FORWARD rollback of 0440 (generated by scripts/build-clear-courses.mjs: do not edit by hand). Cut it as the next
-- migration if the owner wants the old lanes back: every lane and route stop holding a re-sailed course takes its old course again.
-- (Cargo legs keep their pieces: a circuit is rebuilt by public.cargo_circuit_build when its ships are home.)
create function pg_temp.back_0440() returns table (new_md5 text, course jsonb) language sql immutable as $b$
  select v.m, v.c::jsonb from (values
${fixes.map((f) => `    ('${md5(f.course)}', '${textByMd5.get(f.old)}')`).join(',\n')}
  ) as v(m, c)
$b$;
update public.npc_courses c set course = b.course,
       nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0440() b where md5(c.course::text) = b.new_md5;
update public.standing_route_stops s set course = b.course,
       course_nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(b.course)) x)
  from pg_temp.back_0440() b where md5(s.course::text) = b.new_md5;
`,
)
console.log(`wrote ${path.relative(ROOT, HARNESS)}/before.sql, after.sql, rollback-0440.sql`)
