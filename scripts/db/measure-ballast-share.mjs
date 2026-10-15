// ═══════════════════════════════════════════════════════════════════════════════════════════════
// measure-ballast-share.mjs — how many merchants would sail EMPTY at their next lap start, before
// and after 0120, on the applied chain's market (lit, every probe rolled back).
//
// For the first N merchant routes (roster order), each set up as at a lap start (assigned, docked
// at her stop 0, no open lap), public.npc_plan(now, route) is run under three settings and the
// receipt's `ballast` (no BUY on any leg) is counted:
//   A  min return 15 %, no choice   (the world as 0118 left it)
//   B  min return  5 %, no choice   (the bar alone)
//   C  min return  5 %, the choice  (0120 as shipped)
// What it cannot model, stated: production's own prices and stock, the other merchants' lines
// moving between laps, and the daily caps a repeated lap meets. Also prints ms per plan.
//
// Usage: node scripts/db/measure-ballast-share.mjs [--routes 60]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { applyChainCached } from './apply-chain.mjs'
const argv = process.argv.slice(2)
const N = Number(argv.includes('--routes') ? argv[argv.indexOf('--routes') + 1] : '60')
const { db } = await applyChainCached({ log: () => {} })
const q = async (s, p = []) => (await db.query(s, p)).rows
const one = async (s, p = []) => (await q(s, p))[0]

await db.exec(`begin`)
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled','standing_routes_enabled')`)
const routes = await q(`select nf.route_id, nf.fleet_id, sr.name from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
                         join public.fleets f on f.id = nf.fleet_id where f.status not in ('ADRIFT','UNABLE_TO_SAIL') order by nf.roster_ord limit $1`, [N])
const settings = [
  { tag: 'A 15 %, no choice', minret: 15, cand: 0 },
  { tag: 'B  5 %, no choice', minret: 5, cand: 0 },
  { tag: 'C  5 %, the choice', minret: 5, cand: 16 },
]
for (const s of settings) {
  let ballast = 0, chosen = 0, cands = 0, ms = 0, maxMs = 0, far = 0
  for (const r of routes) {
    await db.exec(`savepoint one`)
    await db.query(`update public.world_config set value = to_jsonb($1::int) where key = 'npc_min_return_pct'`, [s.minret])
    await db.query(`update public.world_config set value = to_jsonb($1::int) where key = 'npc_route_candidates'`, [s.cand])
    await db.query(`update public.standing_routes set fleet_id = $2, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null where id = $1`, [r.route_id, r.fleet_id])
    await db.query(`update public.fleets set status = 'DOCKED', port_id = (select port_id from public.standing_route_stops where route_id = $1 and ord = 0) where id = $2`, [r.route_id, r.fleet_id])
    const t = performance.now()
    const x = (await one(`select public.npc_plan(now(), $1) as j`, [r.route_id])).j
    const dt = performance.now() - t
    ms += dt; maxMs = Math.max(maxMs, dt)
    if (x.failed) console.log('  failed:', r.name, JSON.stringify(x.notes))
    ballast += x.ballast ?? 0; chosen += x.chosen ?? 0; cands += x.candidates ?? 0
    const mx = await one(`select coalesce(max(r.nm), 0) as nm from public.standing_route_stops s
      cross join lateral (select e.nm from voyage.reach_from(s.port_id) e where e.port_id = (select s2.port_id from public.standing_route_stops s2 where s2.route_id = s.route_id and s2.ord = (s.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = s.route_id))) r
      where s.route_id = $1`, [r.route_id])
    if (Number(mx.nm) >= 2000) far++
    await db.exec(`rollback to savepoint one`)
  }
  console.log(`${s.tag}: ${routes.length} routes — ballast ${ballast} (${(100 * ballast / routes.length).toFixed(0)} %), changed loop ${chosen}, loops priced ${cands}, loops with a leg >= 2000 nm ${far}; plan mean ${(ms / routes.length).toFixed(0)} ms, max ${maxMs.toFixed(0)} ms`)
}
await db.exec(`rollback`)
await db.close()
process.exit(0)
