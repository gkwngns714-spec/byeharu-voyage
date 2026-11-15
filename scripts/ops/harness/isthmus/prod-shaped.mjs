#!/usr/bin/env node
// prod-shaped.mjs — MIGRATION 0441 ON PRODUCTION'S OWN COURSES, in a world image (no prod load).
//
//   node scripts/ops/harness/isthmus/prod-shaped.mjs <image.tar.gz | -> <prod-courses.json> <prod-legs.json> [--rollback]
//
// Production holds lanes, route stops and frozen cargo and patrol legs no world image has. This loads the
// exports of scripts/ops/harness/no-land/prod-courses.sql and prod-legs.sql into an image of the chain at
// 0440 (lanes and coast courses by their ports; each distinct route-stop course and each distinct leg once),
// applies supabase/migrations/20260818000441_*.sql (so its self-asserts run on prod's shape), and audits what
// is left with scripts/db/audit-land-crossings.mjs's own functions: no lane, route stop or coast course the
// server's law refuses, none over the drawn land, no frozen leg over the drawn land. --rollback then applies
// rollback-0441.sql and checks the function bodies and the courses are back as they were.
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { openImage, newestImage, readWorldCourses, auditWorld } from '../../../db/audit-land-crossings.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..')
const [image, coursesFile, legsFile] = process.argv.slice(2)
const unwrap = (f) => Object.values(JSON.parse(readFileSync(f, 'utf8')).rows[0])[0]
const prod = unwrap(coursesFile)
const legs = unwrap(legsFile)
const notices = []
const db = await openImage(image === '-' ? await newestImage() : image)
const run = (sql) => db.exec(sql, { onNotice: (n) => notices.push(n.message) })

// The rows loaded have no circuit, station or route of their own: those three foreign keys are dropped
// inside this transaction, which is rolled back at the end.
await db.exec(`begin;
  alter table public.cargo_circuit_legs drop constraint cargo_circuit_legs_circuit_id_fkey;
  alter table public.navy_patrol_legs drop constraint navy_patrol_legs_station_id_fkey;
  alter table public.standing_route_stops drop constraint standing_route_stops_route_id_fkey;`)
await db.exec('delete from public.npc_courses; delete from public.npc_coast_courses; delete from public.standing_route_stops; delete from public.cargo_circuit_legs; delete from public.navy_patrol_legs;')
const ins = async (sql, rows) => {
  for (let i = 0; i < rows.length; i += 200) await db.query(sql, [JSON.stringify(rows.slice(i, i + 200))])
}
await ins(
  `insert into public.npc_courses (from_port, to_port, course, nm)
   select a.id, b.id, (x ->> 2)::jsonb, 1 from jsonb_array_elements($1::jsonb) x join public.ports a on a.code = x ->> 0 join public.ports b on b.code = x ->> 1`,
  prod.npc,
)
await ins(
  `insert into public.npc_coast_courses (from_port, to_port, course, nm)
   select a.id, b.id, (x ->> 2)::jsonb, 1 from jsonb_array_elements($1::jsonb) x join public.ports a on a.code = x ->> 0 join public.ports b on b.code = x ->> 1`,
  prod.coast,
)
await ins(
  `insert into public.standing_route_stops (route_id, ord, port_id, course)
   select gen_random_uuid(), 0, p.id, (x ->> 2)::jsonb from jsonb_array_elements($1::jsonb) x join public.ports p on p.code = x ->> 0`,
  prod.stops,
)
const anyPort = (await db.query(`select id from public.ports where kind = 'HARBOUR' order by code limit 1`)).rows[0].id
await ins(
  `insert into public.cargo_circuit_legs (circuit_id, ord, to_port, nm, segments)
   select 1000000 + (x ->> 0)::int, 1, '${anyPort}', 1, (x ->> 1)::jsonb from jsonb_array_elements($1::jsonb) x`,
  (legs.cargo ?? []).map(([, t], i) => [i, t]),
)
await ins(
  `insert into public.navy_patrol_legs (station_id, ord, to_port, nm, segments)
   select 1000000 + (x ->> 0)::int, 1, '${anyPort}', 1, (x ->> 1)::jsonb from jsonb_array_elements($1::jsonb) x`,
  (legs.patrol ?? []).map(([, t], i) => [i, t]),
)
const count = async () => (await db.query(`select (select count(*) from public.npc_courses)::int as lanes, (select count(*) from public.standing_route_stops)::int as stops,
  (select count(*) from public.cargo_circuit_legs)::int as cargo, (select count(*) from public.navy_patrol_legs)::int as patrol`)).rows[0]
console.log('prod-shaped: loaded', JSON.stringify(await count()))

const readLegs = async () =>
  (
    await db.query(`select 'cargo' as kind, g.circuit_id::text as id, g.segments::text as text from public.cargo_circuit_legs g
                    union all select 'patrol', n.station_id::text, n.segments::text from public.navy_patrol_legs n`)
  ).rows.map((r) => {
    const out = []
    for (const s of JSON.parse(r.text)) for (const p of [s.a, s.b]) if (!out.length || out[out.length - 1][0] !== Number(p[0]) || out[out.length - 1][1] !== Number(p[1])) out.push([Number(p[0]), Number(p[1])])
    return { kind: r.kind, key: `${r.kind} ${r.id}`, rows: 1, text: r.text, course: out }
  })
const audit = async () => {
  const world = await readWorldCourses(db)
  world.legs = await readLegs()
  const out = auditWorld(world)
  const by = {}
  for (const c of out.crossings) by[c.kind + (c.refused ? ' refused' : ' land')] = (by[c.kind + (c.refused ? ' refused' : ' land')] ?? 0) + 1
  return { n: out.crossings.length, by, counted: out.counted }
}
const snap = async () =>
  (
    await db.query(`select md5(pg_get_functiondef('voyage.path_refusal(jsonb,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure)) || md5(pg_get_functiondef('voyage.assert_paths_water()'::regprocedure)) as fns,
      (select md5(string_agg(md5(course::text), ',' order by from_port, to_port)) from public.npc_courses) as lanes,
      (select md5(string_agg(md5(course::text), ',' order by route_id)) from public.standing_route_stops) as stops,
      (select md5(string_agg(sr.code || sr.reaches::text, ',' order by sr.code)) from public.sea_reaches sr) as reaches`)
  ).rows[0]
const before = await audit()
const pre = await snap()
console.log('prod-shaped: BEFORE 0441', JSON.stringify(before))
const t0 = Date.now()
const dir = path.join(ROOT, 'supabase', 'migrations')
await run(readFileSync(path.join(dir, '20260818000441_an_approach_is_not_a_canal.sql'), 'utf8'))
console.log(`prod-shaped: 0441 applied in ${Math.round((Date.now() - t0) / 100) / 10} s on PGlite; its notices:`)
for (const n of notices) console.log('   ' + n)
const after = await audit()
console.log('prod-shaped: AFTER 0441', JSON.stringify(after))
let bad = after.n > 0
if (process.argv.includes('--rollback')) {
  await run(readFileSync(path.join(ROOT, 'scripts', 'ops', 'harness', 'isthmus', 'rollback-0441.sql'), 'utf8'))
  const post = await snap()
  const same = post.fns === pre.fns && post.lanes === pre.lanes && post.reaches === pre.reaches
  console.log(`prod-shaped: forward rollback applied; function bodies back: ${post.fns === pre.fns}; lanes back: ${post.lanes === pre.lanes}; route stops back: ${post.stops === pre.stops}; quoted distances back: ${post.reaches === pre.reaches}`)
  if (!same) bad = true
}
await db.exec('rollback')
await db.close()
process.exit(bad ? 1 : 0)
