// throwaway (osn-far-selling): the prod-shaped market (prod's knobs, every market row's state, the city purses)
// laid over the head image, then optional migrations, optional knob sets, then the long-vs-short measurement.
// usage: node _far.mjs <image.tar.gz> <out.json> [--mig file.sql]... [--set key=jsonvalue]... [--sql measure.sql]
import { readFile } from 'node:fs/promises'
import { readFileSync, writeFileSync } from 'node:fs'
import { gunzipSync } from 'node:zlib'
import { PGlite } from '@electric-sql/pglite'
const args = process.argv.slice(2)
const image = args[0], outf = args[1]
const migs = [], sets = [], gucs = []; let msql = '_qm_local.sql', dump = null, skipState = false
for (let i = 2; i < args.length; i++) {
  if (args[i] === '--mig') migs.push(args[++i])
  else if (args[i] === '--set') sets.push(args[++i])
  else if (args[i] === '--sql') msql = args[++i]
  else if (args[i] === '--dump') dump = args[++i]
  else if (args[i] === '--nostate') skipState = true
  else if (args[i] === '--guc') gucs.push(args[++i])
}
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
const q = async (sql, p) => (await db.query(sql, p)).rows
if (!skipState) {
  const st = JSON.parse(readFileSync('.farwork/prod-state.json', 'utf8'))[0].j
  await db.exec(`select public.city_treasury_switch(true)`)
  await db.query(`create temp table wcx(k text, v jsonb)`)
  for (const [k, v] of Object.entries(st.wc)) await db.query(`insert into wcx values ($1, $2)`, [k, JSON.stringify(v)])
  log('knobs set', (await q(`with u as (update public.world_config w set value = x.v from wcx x where x.k = w.key and w.value is distinct from x.v returning 1) select count(*) n from u`))[0].n,
      'missing locally', (await q(`select count(*) n from wcx where k not in (select key from public.world_config)`))[0].n)
  await db.query(`create temp table pr(p text, g text, stock numeric, target numeric, drift numeric, season numeric, glut numeric, lrd int, prod numeric, haul numeric, demand numeric, aff numeric)`)
  const R = st.rows
  for (let i = 0; i < R.length; i += 2000) {
    const chunk = R.slice(i, i + 2000)
    await db.query(`insert into pr select * from jsonb_to_recordset($1::jsonb) as x(p text, g text, stock numeric, target numeric, drift numeric, season numeric, glut numeric, lrd int, prod numeric, haul numeric, demand numeric, aff numeric)`,
      [JSON.stringify(chunk.map((r) => ({ p: r[0], g: r[1], stock: r[2], target: r[3], drift: r[4], season: r[5], glut: r[6], lrd: r[7], prod: r[8], haul: r[9], demand: r[10], aff: r[11] })))])
  }
  const diff = (await q(`select count(*) filter (where pg.haul <> pr.haul) dh, count(*) filter (where pg.demand <> pr.demand) dd, count(*) filter (where pg.affinity <> pr.aff) da,
                                count(*) filter (where pg.stock_target <> pr.target) dt, count(*) n
                           from pr join public.ports p on p.code = pr.p join public.goods g on g.code = pr.g join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id`))[0]
  log('rows matched', JSON.stringify(diff), 'of prod', R.length)
  await q(`update public.port_goods pg set stock = pr.stock, stock_target = pr.target, drift = pr.drift, season_mod = pr.season, glut = pr.glut, last_regen_day = pr.lrd,
                  production_rate = pr.prod, haul = pr.haul, demand = pr.demand, affinity = pr.aff
             from pr, public.ports p, public.goods g where p.code = pr.p and g.code = pr.g and pg.port_id = p.id and pg.good_id = g.id`)
  await db.query(`create temp table pt(p text, d bigint)`)
  for (const [p, d] of st.treasury) await db.query(`insert into pt values ($1,$2)`, [p, d])
  await q(`select count(public.treasury_post(p.id, 'SIM', pt.d - public.treasury_balance(p.id), null, null, true)) n from pt join public.ports p on p.code = pt.p where pt.d <> public.treasury_balance(p.id)`)
  await db.query(`create temp table pd(p text, d int)`)
  for (const [p, d] of st.dev) await db.query(`insert into pd values ($1,$2)`, [p, d])
  await q(`update public.ports p set dev_commerce = pd.d from pd where pd.p = p.code and p.dev_commerce is distinct from pd.d`)
  log('state laid over (prod at', st.at, ')')
}
for (const m of migs) {
  const notices = []; const t0 = Date.now()
  await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) })
  log('applied', m.split(/[\\/]/).pop(), Date.now() - t0, 'ms'); for (const n of notices) if (/self-assert|FAIL/.test(n)) log('NOTICE', n.slice(0, 4000))
}
for (const s of sets) {
  const [k, v] = [s.slice(0, s.indexOf('=')), s.slice(s.indexOf('=') + 1)]
  const n = (await q(`with u as (update public.world_config set value = $2::jsonb where key = $1 returning 1) select count(*) n from u`, [k, v]))[0].n
  log('set', k, '=', v, n ? '' : '(MISSING KEY)')
}
for (const g of gucs) { const [k, v] = [g.slice(0, g.indexOf('=')), g.slice(g.indexOf('=') + 1)]; await q(`select set_config($1, $2, false)`, [k, v]); log('guc', k, v) }
if (dump) { await db.query('checkpoint'); const { writeFile } = await import('node:fs/promises'); await writeFile(dump, Buffer.from(await (await db.dumpDataDir('gzip')).arrayBuffer())); log('dumped', dump) }
const t0 = Date.now()
const rows = await q(readFileSync(msql, 'utf8'))
log('measured in', Date.now() - t0, 'ms')
writeFileSync(outf, JSON.stringify(rows, null, 1))
process.exit(0)
