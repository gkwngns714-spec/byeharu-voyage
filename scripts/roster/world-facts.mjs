// Dump the world facts the 0105 roster generator reasons over, from the applied 0001-0102 chain.
// Not part of the build: a scratch read, kept because the numbers in the receipt came from it.
import { readFile, writeFile, stat } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import path from 'node:path'
import os from 'node:os'
import { applyChain, migrationFiles, MIGRATIONS_DIR, PREAMBLE_PATH, REPO_ROOT } from '../db/apply-chain.mjs'
const { PGlite } = await import('@electric-sql/pglite')
const STOP = '20260818000105'
const chainFiles = (await migrationFiles()).filter((f) => f < STOP)
const fp = createHash('md5')
fp.update(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of chainFiles) fp.update(f).update(await readFile(path.join(MIGRATIONS_DIR, f), 'utf8'))
const CACHE = path.join(os.tmpdir(), `byeharu-npc-chain-${fp.digest('hex').slice(0, 16)}.tar`)
let db
if (await stat(CACHE).then(() => true, () => false)) {
  console.log('cache hit', CACHE)
  db = await PGlite.create({ loadDataDir: new Blob([await readFile(CACHE)], { type: 'application/x-tar' }) })
} else {
  console.log(`applying ${chainFiles.length} migrations (0001-${chainFiles.at(-1).slice(10, 14)}) …`)
  const t0 = Date.now()
  const r = await applyChain({ quiet: true, log: () => {}, stopBefore: STOP })
  db = r.db
  const bytes = Buffer.from(new Uint8Array(await (await db.dumpDataDir('none')).arrayBuffer()))
  await writeFile(CACHE, bytes)
  console.log(`applied + cached in ${((Date.now() - t0) / 1000).toFixed(0)}s -> ${CACHE} (${(bytes.length / 1e6).toFixed(0)} MB)`)
}
const rows = async (sql) => (await db.query(sql)).rows
const out = {}
out.ports = await rows(`select p.code, p.name, p.kind, p.lat::float8 lat, p.lon::float8 lon,
   p.max_draft::float8 max_draft, p.crew_pool::float8 crew_pool, p.size_tier, p.culture, p.tax_rate::float8 tax_rate,
   p.dev_commerce::float8 dev_commerce, p.dev_industry::float8 dev_industry,
   n.code nation, r.code region, r.name region_name,
   sr.roadstead_lat::float8 rlat, sr.roadstead_lon::float8 rlon
  from public.ports p
  left join public.nations n on n.id = p.nation_id
  left join public.regions r on r.id = p.region_id
  left join public.sea_reaches sr on sr.port_id = p.id
  order by p.code`)
out.nations = await rows(`select code, name, capital_port_code from public.nations order by code`)
out.classes = await rows(`select code, name, family, hold::float8 hold, crew_required, crew_max, draft::float8 draft, speed_kn::float8 kn, tier, build_cost::float8 build_cost from public.ship_classes order by tier, code`)
out.specialties = await rows(`select p.code port, g.code good from public.port_specialties ps join public.ports p on p.id = ps.port_id join public.goods g on g.id = ps.good_id order by p.code, g.code`)
out.raster = (await rows(`select cols, rows, cell_deg::float8 cell_deg, bits_per_cell, replace(encode(cells, 'base64'), e'\n', '') as cells_base64 from public.sea_raster where id = 1`))[0]
out.regions = await rows(`select code, name from public.regions order by code`)
out.port_goods = await rows(`select p.code port, g.code good, pg.affinity::float8 affinity from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id order by p.code, g.code`)
out.goods = await rows(`select code, name, category, base_value::float8 base_value, bulk::float8 bulk, culture_mask from public.goods order by code`)
out.config = await rows(`select key, value from public.world_config order by key`)
out.officers = await rows(`select o.code, o.name, o.specialty, o.bonus_pct::float8 bonus, o.wage_ducats::float8 wage, n.code nation, p.code home from public.officers o left join public.nations n on n.id=o.nation_id left join public.ports p on p.id=o.home_port_id order by o.code`)
const dest = process.argv[2] || path.join(REPO_ROOT, 'scripts', 'roster', '.world-facts.json')
await writeFile(dest, JSON.stringify(out, null, 1))
console.log('wrote', dest)
console.log('ports', out.ports.length, 'harbours', out.ports.filter(p=>p.kind==='HARBOUR').length, 'nations', out.nations.length, 'classes', out.classes.length, 'port_goods', out.port_goods.length, 'goods', out.goods.length)
process.exit(0)
