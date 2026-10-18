// ═══════════════════════════════════════════════════════════════════════════════════════════════
// measure-haul.mjs — 0173: what the distance term does to the world, before (every haul held at 1,
// which is the pre-image's price to the digit — 0173's own self-assert) and after (as shipped), on the
// applied chain's market. Everything rolls back.
//
//   1. THE TABLE: kimchi from its maker to the world's ports, and five goods from other regions — the
//      sailing nm from the nearest maker, the haul, the mid before → after, the bid after, and what
//      100 units fetch sold in one go (the stock walk) after.
//   2. THE MERCHANTS: for the first N merchant routes (roster order), each set up at a lap start (docked
//      at her stop 0, empty hold, no open lap, her purse as found), public.npc_plan plans her loop:
//      plan failures, ballast (no BUY at stop 0), the planned loop profit, the loop's sailed nm, the
//      plan's time — before and after.
//   3. THE COST: world.trade_routes (no fleet) from 30 harbours, timed before and after; world.mid_terms
//      × 2,000 rows timed.
// What it cannot model, stated: production's own stock, purses and merchants moving the market
// between laps; a sweep (the lap-start planner is measured, the arrivals mover does not price).
//
// Usage: node scripts/measure-haul.mjs [--routes 60]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import path from 'node:path'
import { applyWithPrefixCache } from './db/prefix-cache.mjs'
import { BROWSER_VARIANT, IMAGE_CACHE_DIR, chainAndFingerprint } from './db/build-image.mjs'

const argv = process.argv.slice(2)
const N = Number(argv.includes('--routes') ? argv[argv.indexOf('--routes') + 1] : '60')
const { files } = await chainAndFingerprint()
const { db } = await applyWithPrefixCache({
  variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: console.log,
})
const q = async (s, p = []) => (await db.query(s, p)).rows
const one = async (s, p = []) => (await q(s, p))[0]
if (!(await one(`select to_regprocedure('world.haul_rows()') is not null as ok`)).ok) throw new Error('the chain does not reach 0173')

await db.exec(`begin`)
await db.exec(`update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled','standing_routes_enabled')`)

// ── 1. THE TABLE ─────────────────────────────────────────────────────────────────────────────────
const PORTS = ['MOK', 'BUS', 'NAG', 'MAC', 'MAL', 'SUR', 'HOR', 'ADE', 'ZAN', 'ALE', 'VEN', 'GOA', 'LIS', 'CAD', 'AMS', 'LON', 'HAM', 'BER', 'BOS', 'HAV', 'VER', 'RIO', 'ACA']
const GOODS = ['kimchi', 'nutmeg', 'tea', 'tobacco', 'coffee', 'wine']
const table = async () => q(`
  select g.code as good, p.code as port, pg.haul_nm::float8 as nm, pg.haul::float8 as haul,
         pr.mid::float8 as mid, pr.ask::float8 as ask, pr.bid::float8 as bid,
         s.total::float8 as sell100, s.avg_price::float8 as avg100
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id join public.ports p on p.id = pg.port_id
   cross join lateral world.price(pg.port_id, pg.good_id) pr
   cross join lateral world.quote(pg.port_id, pg.good_id, 100, 'sell', null, null) s
   where g.code = any($1) and p.code = any($2)`, [GOODS, PORTS])
await db.exec(`savepoint flat`)
await db.exec(`update public.port_goods set haul = 1 where haul <> 1`)
const before = await table()
await db.exec(`rollback to savepoint flat`)
const after = await table()
const key = (r) => `${r.good}/${r.port}`
const bmap = new Map(before.map((r) => [key(r), r]))
const fmt = (x) => (x == null ? '—' : Math.round(x).toLocaleString('en-US'))
for (const g of GOODS) {
  const rows = after.filter((r) => r.good === g).sort((a, b) => (a.nm ?? 1e9) - (b.nm ?? 1e9))
  console.log(`\n${g}`)
  console.log('| port | nm from nearest maker | haul | mid before | mid after | bid after | 100 sold at once, after (avg) |')
  console.log('|---|---|---|---|---|---|---|')
  for (const r of rows) {
    const b = bmap.get(key(r))
    console.log(`| ${r.port} | ${fmt(r.nm)} | ${r.haul.toFixed(2)} | ${b.mid.toFixed(2)} | ${fmt(r.mid)} | ${fmt(r.bid)} | ${fmt(r.sell100)} (${fmt(r.avg100)}) |`)
  }
}
const lon = await one(`select t.ducats::float8 as ducats, t.reserve::float8 as reserve, public.city_treasury_on() as lit
                         from public.port_treasury t join public.ports p on p.id = t.port_id where p.code = 'LON'`)
console.log(`\nLondon's purse on this chain: ${JSON.stringify(lon ?? null)}`)

// ── 2. THE MERCHANTS ─────────────────────────────────────────────────────────────────────────────
const routes = await q(`select nf.route_id, nf.fleet_id, nf.player_id, sr.name from public.npc_fleets nf
                          join public.standing_routes sr on sr.id = nf.route_id
                          join public.fleets f on f.id = nf.fleet_id
                         where f.status not in ('ADRIFT','UNABLE_TO_SAIL') order by nf.roster_ord limit $1`, [N])
for (const s of [{ tag: 'before (haul 1)', flat: true }, { tag: 'after  (0173)  ', flat: false }]) {
  let failed = 0, ballast = 0, profit = 0, ms = 0, nm = 0, negative = 0
  for (const r of routes) {
    await db.exec(`savepoint one`)
    if (s.flat) await db.exec(`update public.port_goods set haul = 1 where haul <> 1`)
    await db.query(`update public.standing_routes set fleet_id = $2, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null where id = $1`, [r.route_id, r.fleet_id])
    await db.query(`update public.voyages set status = 'ARRIVED' where fleet_id = $1 and status = 'SAILING'`, [r.fleet_id])
    await db.query(`update public.fleets set status = 'DOCKED', lat = null, lon = null, port_id = (select port_id from public.standing_route_stops where route_id = $1 and ord = 0) where id = $2`, [r.route_id, r.fleet_id])
    await db.query(`update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = $1`, [r.fleet_id])
    const t = performance.now()
    const x = (await one(`select public.npc_plan(now(), $1) as j`, [r.route_id])).j
    ms += performance.now() - t
    if (x?.failed) failed++
    const lines = (await one(`select cmd.standing_route_lines($1, 0, $2) as l`, [r.route_id, r.fleet_id])).l
    if (!lines.some((l) => l.startsWith('BUY '))) ballast++
    const pr = await one(`select coalesce(sum((public.npc_leg_lines($1, s0.port_id, s1.port_id,
                              (select coalesce(sum(public.ship_cargo_tuns(sh.id)), 0) from public.ships sh where sh.fleet_id = $2) + public.fleet_free_hold($2),
                              0, greatest(coalesce(voyage.fleet_speed($2), 0), 0.1))->>'profit')::numeric), 0)::float8 as p,
                                (select coalesce(sum(course_nm), 0)::float8 from public.standing_route_stops where route_id = $1) as nm
                            from public.standing_route_stops s0
                            join public.standing_route_stops s1 on s1.route_id = s0.route_id
                             and s1.ord = (s0.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = s0.route_id)
                           where s0.route_id = $1`, [r.route_id, r.fleet_id])
    profit += pr.p
    nm += pr.nm
    if (pr.p < 0) negative++
    await db.exec(`rollback to savepoint one`)
  }
  console.log(`merchants ${s.tag}: ${routes.length} routes — plan failed ${failed}; ballast at stop 0 ${ballast}; ` +
    `loops planned at a loss ${negative}; planned loop profit ${fmt(profit)} d. (mean ${fmt(profit / routes.length)}); ` +
    `mean loop ${fmt(nm / routes.length)} nm; plan mean ${(ms / routes.length).toFixed(0)} ms`)
}

// ── 3. THE COST ──────────────────────────────────────────────────────────────────────────────────
const harbours = await q(`select id from public.ports where kind = 'HARBOUR' order by md5(id::text) limit 30`)
for (const s of [{ tag: 'before (haul 1)', flat: true }, { tag: 'after  (0173)  ', flat: false }]) {
  await db.exec(`savepoint cost`)
  if (s.flat) await db.exec(`update public.port_goods set haul = 1 where haul <> 1`)
  let best = Infinity
  for (let pass = 0; pass < 2; pass++) {
    const t = performance.now()
    for (const h of harbours) await q(`select count(*) from world.trade_routes($1, null, null, 20, null)`, [h.id])
    best = Math.min(best, performance.now() - t)
  }
  const t2 = performance.now()
  await q(`select count(t.*) from (select port_id, good_id from public.port_goods order by md5(port_id::text || good_id::text) limit 2000) x
            cross join lateral world.mid_terms(x.port_id, x.good_id) t`)
  console.log(`cost ${s.tag}: trade_routes × 30 harbours ${best.toFixed(0)} ms (faster of 2); mid_terms × 2,000 ${(performance.now() - t2).toFixed(0)} ms`)
  await db.exec(`rollback to savepoint cost`)
}

await db.exec(`rollback`)
await db.close()
process.exit(0)
