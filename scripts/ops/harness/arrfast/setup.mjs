// setup.mjs — lapsim.mjs's prod-shaped world (knobs, stocks, purses, treasuries, loops, every merchant docked at stop 0 empty), then the kickoff.
import { readFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import { readFileSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'
// (this machine, 2026-10-19: the state is .arrwork/prod-state.json from q_state.sql, read-only on prod)
export const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)
export async function open(image, migs) {
  const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
  for (const m of migs) {
    const notices = []; const t0 = Date.now()
    await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) })
    log('applied', m.split('/').pop(), Date.now() - t0, 'ms'); for (const n of notices) if (/self-assert|0182/.test(n)) log('NOTICE', n.slice(0, 3000))
  }
  return db
}
export async function setup(db, kick = true) {
  const q = async (sql, p) => (await db.query(sql, p)).rows
  const st = JSON.parse(readFileSync('.arrwork/prod-state.json', 'utf8'))
  const wc = st.wc
  await db.exec(`select public.city_treasury_switch(true)`)
  await db.query(`create temp table wcx(k text, v jsonb)`)
  for (const [k, v] of Object.entries(wc)) await db.query(`insert into wcx values ($1, $2)`, [k, JSON.stringify(v)])
  log('knobs set', (await q(`with u as (update public.world_config w set value = x.v from wcx x where x.k = w.key and w.value is distinct from x.v returning 1) select count(*) n from u`))[0].n)
  await db.query(`create temp table ps(p text, g text, s numeric)`)
  for (const [p, g, s] of st.stock) await db.query(`insert into ps values ($1,$2,$3)`, [p, g, s])
  await q(`update public.port_goods pg set stock = ps.s from ps, public.ports p, public.goods g where p.code=ps.p and g.code=ps.g and pg.port_id=p.id and pg.good_id=g.id`)
  await db.query(`create temp table pp(c text, d bigint)`)
  for (const [c, d] of st.purse) await db.query(`insert into pp values ($1,$2)`, [c, d])
  await q(`select count(public.credit(pl.id, 'SIM', pp.d - pl.ducats)) n from pp join public.players pl on pl.company_name = pp.c and pl.is_npc where pp.d <> pl.ducats`)
  await db.query(`create temp table pt(p text, d bigint)`)
  for (const [p, d] of st.treasury) await db.query(`insert into pt values ($1,$2)`, [p, d])
  await q(`select count(public.treasury_post(p.id, 'SIM', pt.d - public.treasury_balance(p.id), null, null, true)) n from pt join public.ports p on p.code = pt.p where pt.d <> public.treasury_balance(p.id)`)
  await db.query(`create temp table lp(house text, fleet text, stops jsonb)`)
  for (const [h, f, stops] of st.loops2) await db.query(`insert into lp values ($1, $2, $3)`, [h, f, JSON.stringify(stops)])
  const saved = await q(`select count(*) filter (where (cmd.standing_route_save_for(nf.player_id, nf.route_id, null,
       (select jsonb_agg(jsonb_build_object('port', x->>0, 'course', x->1, 'repair', false, 'crew_up', true,
                                            'lines', jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true))) order by o)
          from jsonb_array_elements(lp.stops) with ordinality t(x, o)), null, null, 0)->>'ok')::boolean) ok, count(*) n
    from lp join public.players pl on pl.company_name = lp.house and pl.is_npc join public.fleets f on f.name = lp.fleet and f.player_id = pl.id join public.npc_fleets nf on nf.fleet_id = f.id`)
  log('loops saved', JSON.stringify(saved[0]))
  // prod's lap counts (q_lapno.sql), so the review laps (lap_no % npc_route_review_laps) fall as on prod
  { const t = readFileSync('.arrwork/lapno.json', 'utf8'); const ln = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)).rows[0].j
    await db.query(`create temp table ln(house text, fleet text, n int)`)
    for (const [h, f, n] of ln) await db.query(`insert into ln values ($1, $2, $3)`, [h, f, n])
    log('lap_no set', JSON.stringify((await q(`with u as (update public.standing_routes sr set lap_no = ln.n from ln join public.players pl on pl.company_name = ln.house and pl.is_npc
        join public.fleets f on f.name = ln.fleet and f.player_id = pl.id join public.npc_fleets nf on nf.fleet_id = f.id where sr.id = nf.route_id returning 1) select count(*) n from u`))[0])) }
  await db.exec(`
    -- (this machine's image comes from npc_traders_switch(true): its merchants are at sea; end those voyages)
    update public.voyages v set status = 'ABORTED' from public.npc_fleets nf where nf.fleet_id = v.fleet_id and v.status = 'SAILING';
    update public.orders o set status = 'cancelled' from public.npc_fleets nf where nf.fleet_id = o.fleet_id and o.status in ('pending', 'active', 'failed');
    update public.ships s set cargo = '{}'::jsonb from public.npc_fleets nf where nf.fleet_id = s.fleet_id;
    update public.fleets f set status = 'DOCKED', port_id = s0.port_id, lat = null, lon = null
      from public.npc_fleets nf join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0 where nf.fleet_id = f.id;
    update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null,
           updated_at = now() - interval '1 hour' from public.npc_fleets nf where nf.route_id = sr.id;`)
  if (!kick) return q
  const t0 = Date.now()
  const kicked = await q(`select count(cmd.advance(nf.fleet_id, now())) n from public.npc_fleets nf`)
  log('kickoff', kicked[0].n, 'fleets in', Date.now() - t0, 'ms')
  return q
}
export const shapeSql = `select json_build_object(
   'sailing', (select count(*) from public.fleets f join public.npc_fleets nf on nf.fleet_id=f.id where f.status='SAILING'),
   'paused', (select json_object_agg(coalesce(r, '-'), c) from (select sr.paused_reason r, count(*) c from public.standing_routes sr join public.npc_fleets nf on nf.route_id=sr.id group by 1) z)) j`
