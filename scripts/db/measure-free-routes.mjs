// ═══════════════════════════════════════════════════════════════════════════════════════════════
// measure-free-routes.mjs — the facts 0120 (a merchant chooses her loop) was cut against.
//
// On a world image (the applied chain, as the browser gets it) or the applied chain itself:
//   1. THE LEG LIBRARY: how many distinct courses the merchant roster already carries between
//      harbours (the only courses the server holds — the pathfinder is the client's), their length
//      distribution and how many harbours have a long haul (>= 2,000 nm) out of them.
//   2. HULLS, HOLDS, PRESETS of the roster.
//   3. TIMINGS, lit, rolled back: world.trade_routes(from, to), world.quote, voyage.path_refusal
//      on a reversed course, and public.npc_plan(now, route) per route — before and after 0120
//      (after: the receipt carries `chosen` and `candidates`).
//
// Usage: node scripts/db/measure-free-routes.mjs [--image path/to/world-*.tar.gz] [--routes 8]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { readFile } from 'node:fs/promises'

const argv = process.argv.slice(2)
const opt = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d)
const IMAGE = opt('--image', null)
const ROUTES = Number(opt('--routes', '8'))

const { PGlite } = await import('@electric-sql/pglite')
let db
if (IMAGE) {
  db = await PGlite.create({ loadDataDir: new Blob([await readFile(IMAGE)], { type: 'application/x-tar' }) })
} else {
  const { applyChainCached } = await import('./apply-chain.mjs')
  ;({ db } = await applyChainCached({ log: () => {} }))
}
const q = async (s, p = []) => (await db.query(s, p)).rows
const one = async (s, p = []) => (await q(s, p))[0]
const ms = async (s, p = [], n = 1) => { const t = performance.now(); for (let i = 0; i < n; i++) await db.query(s, p); return (performance.now() - t) / n }

const LEGS = `
  legs as (
    select distinct s.port_id as from_port,
           (select s2.port_id from public.standing_route_stops s2 where s2.route_id = s.route_id
             and s2.ord = (s.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = s.route_id)) as to_port
      from public.standing_route_stops s join public.standing_routes sr on sr.id = s.route_id
      join public.players p on p.id = sr.player_id and p.is_npc),
  und as (select from_port as a, to_port as b from legs union select to_port, from_port from legs)`

console.log('chain head:', (await q(`select version from supabase_migrations.schema_migrations order by version desc limit 1`).catch(() => [{ version: '(no schema_migrations table: a browser image)' }]))[0].version)
console.log('merchants:', await one(`select (select count(*) from public.players where is_npc)::int as companies,
  (select count(*) from public.npc_fleets)::int as fleets, (select count(route_id) from public.npc_fleets)::int as routed`))
console.log('knobs:', JSON.stringify(Object.fromEntries((await q(`select key, value from public.world_config where key like 'npc_%' or key in ('route_rest_voyage_days','time_compression','standing_route_stop_max','endurance_margin','course_join_nm','route_probe_tuns') order by key`)).map((r) => [r.key, r.value]))))

console.log('library:', await one(`with ${LEGS} select (select count(*) from legs)::int as directed, (select count(*) from und)::int as both_ways,
  (select count(distinct a) from und)::int as harbours`))
console.log('degree (both ways):', await one(`with ${LEGS}, deg as (select a, count(*)::int as d from und group by a)
  select min(d), percentile_cont(0.5) within group (order by d) as med, max(d), avg(d)::numeric(5,1) as avg from deg`))
console.log('leg lengths (nm, sea_reaches):', await one(`with ${LEGS}
  select count(*) filter (where r.nm < 500)::int as under500, count(*) filter (where r.nm >= 500 and r.nm < 2000)::int as b500_2000,
         count(*) filter (where r.nm >= 2000 and r.nm < 5000)::int as b2000_5000, count(*) filter (where r.nm >= 5000)::int as over5000, max(r.nm) as max_nm
    from legs l cross join lateral (select e.nm from voyage.reach_from(l.from_port) e where e.port_id = l.to_port) r`))
console.log('harbours with a long haul (>= 2000 nm) out:', await one(`with ${LEGS}
  select count(distinct u.a)::int as harbours, count(*)::int as legs
    from und u cross join lateral (select e.nm from voyage.reach_from(u.a) e where e.port_id = u.b) r where r.nm >= 2000`))
console.log('hulls by class:', await q(`
  select c.code, count(*)::int as hulls, max(c.speed_kn) as kn, max(c.cargo_tuns) as tuns
    from public.ships s join public.ship_classes c on c.id = s.class_id
    join public.fleets f on f.id = s.fleet_id join public.players p on p.id = f.player_id and p.is_npc
   group by 1 order by 4 desc`).catch((e) => e.message))
console.log('fleet hold (tuns):', await one(`
  with h as (select nf.fleet_id, sum(public.ship_cargo_tuns(s.id)) + public.fleet_free_hold(nf.fleet_id) as hold
               from public.npc_fleets nf join public.ships s on s.fleet_id = nf.fleet_id group by nf.fleet_id)
  select min(hold), percentile_cont(0.5) within group (order by hold) as p50, percentile_cont(0.9) within group (order by hold) as p90, max(hold) from h`))
console.log('preset days:', await one(`
  select min(pr.days), percentile_cont(0.5) within group (order by pr.days) as med, max(pr.days)
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.provision_presets pr on pr.id = f.provision_preset_id`))

await db.exec(`begin`)
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled','standing_routes_enabled')`)
const lis = await one(`select id from public.ports where code = 'LIS'`)
const neigh = await q(`select e.port_id, e.code, e.nm from voyage.reach_from($1) e order by e.nm limit 12`, [lis.id])
console.log(`trade_routes(LIS -> ${neigh[3].code}, 12) ms/call:`, (await ms(`select world.trade_routes($1, null, null, 12, $2)`, [lis.id, neigh[3].port_id], 5)).toFixed(1))
const far = await one(`select e.port_id, e.code, e.nm from voyage.reach_from($1) e where e.code = 'GOA'`, [lis.id])
console.log('trade_routes(LIS -> GOA) ms/call:', (await ms(`select world.trade_routes($1, null, null, 12, $2)`, [lis.id, far.port_id], 5)).toFixed(1),
  'rows:', (await one(`select jsonb_array_length(world.trade_routes($1, null, null, 12, $2)->'routes') as n`, [lis.id, far.port_id])).n)
const g = await one(`select (world.trade_routes($1, null, null, 1, $2)->'routes'->0->>'good_id')::uuid as gid`, [lis.id, neigh[3].port_id])
console.log('world.quote ms/call:', (await ms(`select * from world.quote($1, $2, 40, 'sell', null, null)`, [neigh[3].port_id, g.gid], 10)).toFixed(2))
const r0 = await one(`select nf.route_id from public.npc_fleets nf join public.standing_route_stops s on s.route_id = nf.route_id and s.ord = 0
                       where s.port_id = $1 order by nf.roster_ord limit 1`, [lis.id])
const REV = `
  with s as (select s.course, s.port_id as a, (select s2.port_id from public.standing_route_stops s2 where s2.route_id = s.route_id and s2.ord = 1) as b
               from public.standing_route_stops s where s.route_id = $1 and s.ord = 0),
  rev as (select (select jsonb_agg(x order by i desc) from jsonb_array_elements(s.course) with ordinality t(x, i)) as course, a, b from s)
  select voyage.path_refusal(rev.course, rb.roadstead_lat, rb.roadstead_lon, ra.roadstead_lat, ra.roadstead_lon, public.wc_num('course_join_nm'), 25, 25) as ref
    from rev join public.sea_reaches ra on ra.port_id = rev.a join public.sea_reaches rb on rb.port_id = rev.b`
console.log('path_refusal(reversed course) ms:', (await ms(REV, [r0.route_id], 3)).toFixed(1), await one(REV, [r0.route_id]))
if (await one(`select to_regprocedure('public.npc_known_legs(uuid)') is not null as yes`).then((r) => r.yes)) {
  console.log('npc_known_legs(LIS) ms:', (await ms(`select * from public.npc_known_legs($1)`, [lis.id], 5)).toFixed(1),
    'rows:', (await one(`select count(*)::int as n from public.npc_known_legs($1)`, [lis.id])).n)
}
const routes = await q(`select nf.route_id, nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit $1`, [ROUTES])
let tot = 0, maxMs = 0
const rec = []
for (const r of routes) {
  // AS AT A LAP START: assigned, docked at stop 0, no open lap (the switch ships dark locally).
  await db.exec(`savepoint one`)
  await db.query(`update public.standing_routes set fleet_id = $2, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null where id = $1`, [r.route_id, r.fleet_id])
  await db.query(`update public.fleets set status = 'DOCKED', port_id = (select port_id from public.standing_route_stops where route_id = $1 and ord = 0) where id = $2`, [r.route_id, r.fleet_id])
  const t = performance.now()
  const x = await one(`select public.npc_plan(now(), $1) as j`, [r.route_id])
  const dt = performance.now() - t
  tot += dt; maxMs = Math.max(maxMs, dt)
  rec.push(`${Math.round(dt)}ms ${JSON.stringify({ ...x.j, notes: undefined })}`)
  await db.exec(`rollback to savepoint one`)
}
console.log(`npc_plan(route) at a lap start, ${routes.length} route(s): mean ${(tot / routes.length).toFixed(0)} ms, max ${maxMs.toFixed(0)} ms`)
for (const l of rec) console.log('   ', l)
await db.exec(`rollback`)
await db.close()
process.exit(0)
