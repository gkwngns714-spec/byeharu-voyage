// ═══════════════════════════════════════════════════════════════════════════════════════════════
// measure-merchants.mjs — docs/NPC_TRADERS.md §12 slice 6, the part a laptop can measure.
//
// On the applied chain (0001-0099, the founded roster), with the switch ON:
//   1. ROWS: drives the roster through the one executor — passages rewound as the cron would see
//      them, tick_arrivals, and tick_reconcile every fifth tick — and counts the merchant rows
//      written to ledger / events / voyage_events / voyages / orders / trade_daily, per closed lap
//      and per simulated hour at sea; then runs npc_compact and counts what is retained.
//   2. TIME: `world.sea_traffic()` ms/call, averaged over 50 calls with the roster at sea, and its
//      `explain analyze` total; `world.npc_fleet_card()` ms/call.
//   3. THE LISBON FRAME: how many merchant hulls (at sea or at their roadsteads) lie inside a
//      390 × 844 portrait frame 12° across on Lisbon, sampled after every tick.
// What it cannot measure, stated: real minutes (the clock is rewound, not waited), production's
// market, CI's lock behaviour. Those are the deploy's soak (DEV_LOG).
//
// Usage: node scripts/db/measure-merchants.mjs [--image path/to/applied.tar] [--ticks 20]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { readFile } from 'node:fs/promises'

const argv = process.argv.slice(2)
const opt = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d)
const TICKS = Number(opt('--ticks', '20'))
const IMAGE = opt('--image', null)

const { PGlite } = await import('@electric-sql/pglite')
let db
if (IMAGE) {
  db = await PGlite.create({ loadDataDir: new Blob([await readFile(IMAGE)], { type: 'application/x-tar' }) })
} else {
  const { applyChain } = await import('./apply-chain.mjs')
  ;({ db } = await applyChain({ quiet: true, log: () => {} }))
}
const q = async (s, p = []) => (await db.query(s, p)).rows
const one = async (s, p = []) => (await q(s, p))[0]

const COUNT = `
  select (select count(*) from public.ledger l join public.players p on p.id = l.player_id and p.is_npc)::int as ledger,
         (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc)::int as events,
         (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
            join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)::int as voyage_events,
         (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id
            join public.players p on p.id = f.player_id and p.is_npc)::int as voyages,
         (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc)::int as orders,
         (select count(*) from public.trade_daily t join public.players p on p.id = t.player_id and p.is_npc)::int as trade_daily`
const total = (r) => Object.values(r).reduce((a, b) => a + Number(b), 0)

await db.exec(`
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'npc_laps_per_game_day';`)
const companies = (await one(`select count(*)::int as n from public.players where is_npc`)).n
const fleets = (await one(`select count(*)::int as n from public.npc_fleets`)).n
console.log(`roster: ${companies} merchant companies, ${fleets} fleets`)
const sw = (await one(`select public.npc_traders_switch(true) as j`)).j
console.log(`switch: started ${sw.tend.started}, planned ${sw.plan?.planned}, laid up ${sw.plan?.laid_up}`)

// THE LISBON FRAME (the same geometry the build step judges)
const lis = await one(`select lat::float8 lat, lon::float8 lon from public.ports where code = 'LIS'`)
const frame = { lat0: lis.lat - 6 * (844 / 390), lat1: lis.lat + 6 * (844 / 390), lon0: lis.lon - 6, lon1: lis.lon + 6 }
const inFrame = async () => {
  const t = (await one(`select world.sea_traffic() as j`)).j
  let n = 0
  for (const f of t.fleets) {
    const p = f.voyage?.position ? [f.voyage.position.lat, f.voyage.position.lon] : f.roadstead
    if (p && p[0] >= frame.lat0 && p[0] <= frame.lat1 && p[1] >= frame.lon0 && p[1] <= frame.lon1) n++
  }
  return n
}

const c0 = await one(COUNT)
const frameSamples = [await inFrame()]
let seaSeconds = 0
for (let k = 1; k <= TICKS; k++) {
  // the sea-time this tick stands for: the longest passage it lands
  const span = await one(`select coalesce(max(extract(epoch from v.eta - v.departed_at)), 0)::float8 as s
                            from public.voyages v join public.fleets f on f.id = v.fleet_id
                            join public.players p on p.id = f.player_id and p.is_npc where v.status = 'SAILING'`)
  seaSeconds += span.s
  await db.exec(`
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where v.fleet_id = f.id and v.status = 'SAILING';
    update public.standing_routes sr set hold_until = now() - interval '1 second'
      from public.players p where p.id = sr.player_id and p.is_npc and sr.hold_until is not null;
    select public.tick_arrivals(now());`)
  if (k % 5 === 0) await q(`select public.tick_reconcile()`)
  frameSamples.push(await inFrame())
}
const c1 = await one(COUNT)
const laps = (await one(`select count(*)::int as n from public.standing_route_laps x join public.npc_fleets nf on nf.route_id = x.route_id where x.closed_at is not null`)).n
const written = total(c1) - total(c0)
console.log(`\n== ROWS over ${TICKS} rewound ticks (+${Math.floor(TICKS / 5)} reconciles)`)
for (const k of Object.keys(c1)) console.log(`   ${k.padEnd(14)} ${String(c0[k]).padStart(7)} -> ${String(c1[k]).padStart(7)}  (+${c1[k] - c0[k]})`)
console.log(`   ${written} merchant rows for ${laps} closed laps = ${(written / Math.max(laps, 1)).toFixed(1)} rows per lap`)
console.log(`   ${(seaSeconds / 3600).toFixed(2)} real hours of sea-time stood for = ${(written / Math.max(seaSeconds / 3600, 0.001)).toFixed(0)} rows per real hour (upper bound: every fleet's leg counted at the tick's longest)`)
const compact = (await one(`select public.npc_compact(now() + interval '7 hours') as j`)).j
const c2 = await one(COUNT)
console.log(`   after npc_compact (window passed): ${total(c2)} retained (${JSON.stringify(c2)}); ${JSON.stringify(compact)}`)

// TIME, with the roster freshly at sea again
await db.exec(`select public.tick_arrivals(now())`)
const atSea = (await one(`select count(*)::int as n from jsonb_array_elements(world.sea_traffic()->'fleets') x where x->'voyage' is not null`)).n
let t0 = performance.now()
for (let i = 0; i < 50; i++) await q(`select world.sea_traffic()`)
const trafficMs = (performance.now() - t0) / 50
const plan = await q(`explain (analyze, format json) select world.sea_traffic()`)
const execMs = plan[0]['QUERY PLAN'][0]['Execution Time']
const anyFleet = (await one(`select fleet_id from public.npc_fleets order by roster_ord limit 1`)).fleet_id
t0 = performance.now()
for (let i = 0; i < 20; i++) await q(`select world.npc_fleet_card($1)`, [anyFleet])
const cardMs = (performance.now() - t0) / 20
const bytes = (await one(`select length(world.sea_traffic()::text)::int as b`)).b
console.log(`\n== TIME (PGlite, single connection, ${atSea} merchant fleets at sea)`)
console.log(`   world.sea_traffic(): ${trafficMs.toFixed(2)} ms/call over 50 calls; explain analyze ${Number(execMs).toFixed(2)} ms; ${bytes} bytes served`)
console.log(`   world.npc_fleet_card(): ${cardMs.toFixed(2)} ms/call over 20 calls`)
console.log(`\n== THE LISBON FRAME (390 × 844, 12° across): merchant hulls inside after each tick: ${frameSamples.join(' ')}`)
console.log(`   mean ${(frameSamples.reduce((a, b) => a + b, 0) / frameSamples.length).toFixed(1)}, min ${Math.min(...frameSamples)}`)
const sizes = await q(`select c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) s from pg_class c
                        where c.relname in ('ledger','events','voyage_events','voyages','orders','trade_daily') order by 1`)
console.log(`\n== TABLE SIZES after the soak (PGlite): ${sizes.map((r) => `${r.relname} ${r.s}`).join(' · ')}`)
await db.close()
process.exit(0)
