// ═══════════════════════════════════════════════════════════════════════════════════════════════
// measure-purse-bound.mjs — 0129: does a merchant's lap-start plan reach the quay as a parcel she
// can pay for? Before (the bound off) and after (0129 as shipped), on the applied chain's market.
//
// For the first N merchant routes (roster order), each set up at a lap start (docked at her stop
// 0, empty hold, no open lap) with her purse set to P (prod's medians: 3,993 d. for the merchants
// whose BUYs were refused, 2,000 and 20,000 around it), npc_plan(now, route) plans her loop, the
// stop-0 lines are rendered (cmd.standing_route_lines) and every rendered BUY is EXECUTED through
// cmd.do_buy, in order. Counted: ballast (no BUY rendered), BUY lines bought / refused for funds /
// refused otherwise, ducats laid out, and the plan's own leg profit. Everything rolls back.
//   before = npc_buy_purse_pct 1e9 (the budget never binds: the planner and the lines as 0128)
//   after  = npc_buy_purse_pct 90  (0129)
// What it cannot model, stated: production's own prices, stock and caps, other merchants moving
// the market between laps, and the stops after stop 0.
//
// Usage: node scripts/db/measure-purse-bound.mjs [--routes 60]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import path from 'node:path'
import { applyWithPrefixCache } from './prefix-cache.mjs'
import { BROWSER_VARIANT, IMAGE_CACHE_DIR, chainAndFingerprint } from './build-image.mjs'

const argv = process.argv.slice(2)
const N = Number(argv.includes('--routes') ? argv[argv.indexOf('--routes') + 1] : '60')
const { files } = await chainAndFingerprint()
const { db, restored, applied } = await applyWithPrefixCache({
  variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: console.log,
})
console.log(`chain: ${applied.length} migration(s), ${restored} restored from the prefix cache`)
const q = async (s, p = []) => (await db.query(s, p)).rows
const one = async (s, p = []) => (await q(s, p))[0]

await db.exec(`begin`)
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled','standing_routes_enabled')`)
const routes = await q(`select nf.route_id, nf.fleet_id, nf.player_id, sr.name from public.npc_fleets nf
                          join public.standing_routes sr on sr.id = nf.route_id
                          join public.fleets f on f.id = nf.fleet_id
                         where f.status not in ('ADRIFT','UNABLE_TO_SAIL') order by nf.roster_ord limit $1`, [N])
for (const purse of [2000, 3993, 20000]) {
  for (const s of [{ tag: 'before (bound off)', pct: 1e9 }, { tag: 'after  (0129)     ', pct: 90 }]) {
    let ballast = 0, bought = 0, funds = 0, other = 0, spent = 0, profit = 0, ms = 0
    const otherCodes = {}
    for (const r of routes) {
      await db.exec(`savepoint one`)
      await db.query(`update public.world_config set value = to_jsonb($1::numeric) where key = 'npc_buy_purse_pct'`, [s.pct])
      await db.query(`update public.standing_routes set fleet_id = $2, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null where id = $1`, [r.route_id, r.fleet_id])
      await db.query(`update public.voyages set status = 'ARRIVED' where fleet_id = $1 and status = 'SAILING'`, [r.fleet_id])
      await db.query(`update public.fleets set status = 'DOCKED', lat = null, lon = null, port_id = (select port_id from public.standing_route_stops where route_id = $1 and ord = 0) where id = $2`, [r.route_id, r.fleet_id])
      await db.query(`update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = $1`, [r.fleet_id])
      await db.query(`select public.credit($1, 'MEASURE_0129', ($2::bigint - (select ducats from public.players where id = $1)))`, [r.player_id, purse])
      const t = performance.now()
      const x = (await one(`select public.npc_plan(now(), $1) as j`, [r.route_id])).j
      ms += performance.now() - t
      if (x.failed) console.log('  plan failed:', r.name, JSON.stringify(x.notes))
      const lines = (await one(`select cmd.standing_route_lines($1, 0, $2) as l`, [r.route_id, r.fleet_id])).l
      const buys = lines.filter((l) => l.startsWith('BUY '))
      if (buys.length === 0) ballast++
      for (const l of buys) {
        await db.exec(`savepoint buy`)
        try {
          const p = (await one(`select cmd.parse($1, $2, $3) as p`, [r.player_id, r.fleet_id, l])).p
          const res = (await one(`select cmd.do_buy($1, $2::jsonb) as r`, [r.fleet_id, JSON.stringify(p.args ?? p)])).r
          bought++
          spent += Number(res?.total ?? 0)
          await db.exec(`release savepoint buy`)
        } catch (e) {
          await db.exec(`rollback to savepoint buy`)
          const code = String(e.message).split(':')[0]
          if (code === 'E_INSUFFICIENT_FUNDS') funds++
          else { other++; otherCodes[code] = (otherCodes[code] ?? 0) + 1 }
        }
      }
      // the plan's leg profit for her chosen loop, re-priced for the record (read-only)
      const pr = await one(`select coalesce(sum((public.npc_leg_lines($1, s0.port_id, s1.port_id,
                                (select coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) from public.ships sh where sh.fleet_id = $2) + public.fleet_free_hold($2),
                                0, greatest(coalesce(voyage.fleet_speed($2), 0), 0.1))->>'profit')::numeric), 0) as p
                              from public.standing_route_stops s0
                              join public.standing_route_stops s1 on s1.route_id = s0.route_id
                               and s1.ord = (s0.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = s0.route_id)
                             where s0.route_id = $1`, [r.route_id, r.fleet_id])
      profit += Number(pr.p)
      await db.exec(`rollback to savepoint one`)
    }
    console.log(`purse ${String(purse).padStart(6)} ${s.tag}: ${routes.length} routes — ballast at stop 0 ${ballast} (${(100 * ballast / routes.length).toFixed(0)} %); ` +
      `BUY lines bought ${bought}, refused for funds ${funds}, refused otherwise ${other} ${JSON.stringify(otherCodes)}; ` +
      `laid out ${Math.round(spent)} d.; planned loop profit ${Math.round(profit)} d.; plan mean ${(ms / routes.length).toFixed(0)} ms`)
  }
}
await db.exec(`rollback`)
await db.close()
process.exit(0)
