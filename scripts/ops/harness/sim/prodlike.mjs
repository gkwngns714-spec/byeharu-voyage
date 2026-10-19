// prodlike.mjs <image> <migration> <mode: docked|sail|anchor> — set up the prod-shaped world of lapsim.mjs, then apply the migration; prints its notices.
// (from lapsim.mjs) — a prod-shaped merchant world run forward in REAL time
// (throwaway PGlite): prod's knobs, stocks, merchant and city purses and merchant loops; every merchant docked at her
// stop 0 at a lap start; then the arrivals sweep every 15 s, the market drift every 10 min and one hourly tend
// (tick_reconcile) at the half. Reports the laps that closed, the sweep's cost and where the merchants stand.
process.on('unhandledRejection', (e) => { console.error('ERR', e.message, e.where ?? ''); process.exit(1) })
import { readFile, writeFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
const require = createRequire(process.cwd() + '/package.json')
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href)
const [image, mig, mode] = process.argv.slice(2)
const S = 'C:/Users/gkwng/dev/bv-harness/laps-scratch/'
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
const q = async (sql, p) => (await db.query(sql, p)).rows
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)
const st = (() => { const t = require('fs').readFileSync(S + 'prod-state.json', 'utf8'); return JSON.parse(t.slice(t.indexOf('{'))).rows[0].json_build_object })()
const wc = JSON.parse(require('fs').readFileSync(S + 'prod-wc.json', 'utf8'))
await db.exec(`select public.city_treasury_switch(true)`)
await db.query(`create temp table wcx(k text, v jsonb)`)
for (const [k, v] of Object.entries(wc)) await db.query(`insert into wcx values ($1, $2)`, [k, JSON.stringify(v)])
log('knobs set', (await q(`with u as (update public.world_config w set value = x.v from wcx x where x.k = w.key and w.value is distinct from x.v returning 1) select count(*) n from u`))[0].n)
await db.query(`create temp table ps(p text, g text, s numeric)`)
for (const [p, g, s] of st.stock) await db.query(`insert into ps values ($1,$2,$3)`, [p, g, s])
log('stocks', (await q(`with u as (update public.port_goods pg set stock = ps.s from ps, public.ports p, public.goods g where p.code=ps.p and g.code=ps.g and pg.port_id=p.id and pg.good_id=g.id returning 1) select count(*) n from u`))[0].n)
await db.query(`create temp table pp(c text, d bigint)`)
for (const [c, d] of st.purse) await db.query(`insert into pp values ($1,$2)`, [c, d])
log('purses', (await q(`select count(public.credit(pl.id, 'SIM', pp.d - pl.ducats)) n from pp join public.players pl on pl.company_name = pp.c and pl.is_npc where pp.d <> pl.ducats`))[0].n)
await db.query(`create temp table pt(p text, d bigint)`)
for (const [p, d] of st.treasury) await db.query(`insert into pt values ($1,$2)`, [p, d])
log('treasuries', (await q(`select count(public.treasury_post(p.id, 'SIM', pt.d - public.treasury_balance(p.id), null, null, true)) n from pt join public.ports p on p.code = pt.p where pt.d <> public.treasury_balance(p.id)`))[0].n)
// prod's loops, through THE save door
await db.query(`create temp table lp(fleet text, stops jsonb)`)
for (const [f, stops] of st.loops) await db.query(`insert into lp values ($1, $2)`, [f, JSON.stringify(stops)])
const saved = await q(`select count(*) filter (where (cmd.standing_route_save_for(nf.player_id, nf.route_id, null,
     (select jsonb_agg(jsonb_build_object('port', x->>0, 'course', x->1, 'repair', false, 'crew_up', true,
                                          'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true))) order by o)
        from jsonb_array_elements(lp.stops) with ordinality t(x, o)), null, null, 0)->>'ok')::boolean) ok, count(*) n
  from lp join public.fleets f on f.name = lp.fleet join public.npc_fleets nf on nf.fleet_id = f.id`)
log('loops saved', saved[0])
// every merchant docked at her stop 0, empty, assigned, at a lap start
await db.exec(`
  update public.ships s set cargo = '{}'::jsonb from public.npc_fleets nf where nf.fleet_id = s.fleet_id;
  update public.fleets f set status = 'DOCKED', port_id = s0.port_id, lat = null, lon = null
    from public.npc_fleets nf join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0 where nf.fleet_id = f.id;
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null,
         updated_at = now() - interval '1 hour' from public.npc_fleets nf where nf.route_id = sr.id;`)
if (mode === 'sail') await db.exec(`with v as (insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, eta) select f.id, f.player_id, '[]'::jsonb, 100, '{}'::jsonb, now() + interval '1 hour' from public.fleets f join public.npc_fleets nf on nf.fleet_id=f.id returning fleet_id) update public.fleets f set status='SAILING', port_id=null, lat=null, lon=null from v where v.fleet_id=f.id`)
if (mode === 'anchor') await db.exec(`update public.fleets f set status='ANCHORED', port_id=null, lat=10, lon=10 from public.npc_fleets nf where nf.fleet_id=f.id`)
if (mode === 'laidup') await db.exec(`update public.standing_routes sr set paused_reason='laid_up' from public.npc_fleets nf where nf.route_id=sr.id`)
log('mode', mode, JSON.stringify((await q(`select json_object_agg(status, c) j from (select f.status, count(*) c from public.fleets f join public.npc_fleets nf on nf.fleet_id=f.id group by 1) z`))[0].j))
const notices = []; const t0 = Date.now()
try { await db.exec((await readFile(mig, 'utf8')).split(String.fromCharCode(13)).join(''), { onNotice: (n) => notices.push(n.message) }) }
catch (e) { log('FAILED:', e.message); process.exit(1) }
log('APPLIED in', Date.now() - t0, 'ms'); for (const n of notices) console.log('NOTICE', n)
process.exit(0)
