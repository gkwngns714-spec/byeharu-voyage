// mkworld.mjs <chain-image.tar.gz> <out.tar.gz> — the merchants-on world at the chain's head: routes on,
// prod's npc_fleet_max, the traders' switch lit (the roster put to sea), dumped. setup.mjs then lays prod's
// state over it.
import { readFile, writeFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import { PGlite } from '@electric-sql/pglite'
const [img, out] = process.argv.slice(2)
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)
const st = JSON.parse((await readFile('.arrwork/prod-state.json', 'utf8')))
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(img))], { type: 'application/x-tar' }) })
log('head', (await db.query(`select max(name) n from app_local.chain_files`).catch(() => ({ rows: [{}] }))).rows[0])
await db.query(`update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled'`)
await db.query(`update public.world_config set value = $1::jsonb where key = 'npc_fleet_max'`, [JSON.stringify(st.wc.npc_fleet_max)])
const t0 = Date.now()
const sw = await db.query(`select public.npc_traders_switch(true) j`)
log('switch', Date.now() - t0, 'ms', JSON.stringify(sw.rows[0].j).slice(0, 400))
log('npc_fleets', (await db.query(`select count(*)::int n from public.npc_fleets`)).rows[0].n)
await db.query('checkpoint')
await writeFile(out, Buffer.from(await (await db.dumpDataDir('gzip')).arrayBuffer()))
log('wrote', out)
process.exit(0)
