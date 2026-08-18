import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import path from 'node:path'

const db = new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f.slice(10, 14) > '0006') break
  await db.exec(await readFile(path.join(MIGRATIONS_DIR, f), 'utf8'))
}
// 0007 without its self-assert block
const sql7 = await readFile(path.join(MIGRATIONS_DIR, (await migrationFiles()).find(f => f.slice(10,14) === '0007')), 'utf8')
await db.exec(sql7.slice(0, sql7.lastIndexOf('-- ── SELF-ASSERT')))

const q = async (s, p) => (await db.query(s, p)).rows
const probe = '00000000-0000-0000-0000-0000000007aa'
const [{ id: lis }] = await q(`select id from public.ports where code='LIS'`)
const best = await q(`
  select l_dest.code, l_dest.name, g.code as good, g.name as gname, l.distance_nm,
         pg_away.affinity - pg_home.affinity as gap
    from public.legs l
    join public.ports l_dest on l_dest.id = case when l.from_port_id = $1 then l.to_port_id else l.from_port_id end
    join public.port_goods pg_home on pg_home.port_id = $1
    join public.port_goods pg_away on pg_away.port_id = l_dest.id and pg_away.good_id = pg_home.good_id
    join public.goods g on g.id = pg_home.good_id
   where (l.from_port_id = $1 or l.to_port_id = $1) and l.distance_nm < 700
     and not (l_dest.culture = any(g.culture_mask))
   order by pg_away.affinity - pg_home.affinity desc limit 5`, [lis])
console.log('top one-leg trades out of Lisboa:')
for (const r of best) console.log(`   ${r.gname} -> ${r.name} (${r.code}) ${r.distance_nm} nm, gap ${Number(r.gap).toFixed(3)}`)

await db.exec(`select public.new_house('${probe}', 'Casa Probe', 'PRT')`)
const [{ id: player }] = await q(`select id from public.players where auth_uid = '${probe}'`)
const [{ id: fleet }] = await q(`select id from public.fleets where player_id = $1`, [player])
const [{ id: destId }] = await q(`select id from public.ports where code = $1`, [best[0].code])
const [{ id: goodId }] = await q(`select id from public.goods where code = $1`, [best[0].good])
await q(`select cmd.do_provision($1, '{"mode":"FULL"}'::jsonb)`, [fleet])
await q(`insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args) values
   ($1,$2,1,'BUY','BUY', jsonb_build_object('good',$3::uuid,'qty',50)),
   ($1,$2,2,'SAIL OUT','SAIL', jsonb_build_object('dest',$4::uuid)),
   ($1,$2,3,'SELL','SELL', jsonb_build_object('good',$3::uuid,'qty_mode','ALL')),
   ($1,$2,4,'SAIL HOME','SAIL', jsonb_build_object('dest',$5::uuid))`, [fleet, player, goodId, destId, lis])
await q(`select cmd.advance($1)`, [fleet])
for (let k = 0; k < 24; k++) {
  const [f] = await q(`select status, port_id from public.fleets where id = $1`, [fleet])
  const voy = await q(`select status, total_nm, jsonb_array_length(path) legs, eta from public.voyages where fleet_id=$1 order by created_at`, [fleet])
  const [sh] = await q(`select water_t, food_t, crew, cargo from public.ships where fleet_id=$1`, [fleet])
  console.log(`round ${k}: fleet ${f.status}; water ${sh.water_t} food ${sh.food_t}; voyages ${voy.map(v => `${v.status} ${v.total_nm}nm`).join(' | ')}`)
  if (f.status !== 'SAILING') break
  await q(`update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where fleet_id=$1 and status='SAILING'`, [fleet])
  await q(`select voyage.settle($1)`, [fleet])
}
const orders = await q(`select seq, status, error_code, error_message from public.orders where fleet_id=$1 order by seq`, [fleet])
console.log('orders:', orders.map(o => `${o.seq}:${o.status}${o.error_code ? ' ' + o.error_code + ' ' + o.error_message : ''}`).join(' | '))
const [pl] = await q(`select ducats from public.players where id=$1`, [player])
const [fl] = await q(`select status, (select code from public.ports where id=port_id) port from public.fleets where id=$1`, [fleet])
console.log('final:', fl.status, fl.port, pl.ducats, 'd.')
await db.close()
