// sweep.mjs <world.tar.gz> <out-dir> [migration.sql]... -- --max 600,8,...  — the haul_max sweep (2026-10-20).
// The prod-shaped merchant world (arrfast/setup.mjs: prod's knobs, stocks, purses, treasuries, loops), the
// migrations after it as prod applies them, then for each candidate haul_max IN ITS OWN ROLLED-BACK
// TRANSACTION: the knob, port_goods.haul refilled from world.haul_rows() (the one derivation), bands.sql.
// Run from the repo root; .arrwork/prod-state.json and .arrwork/lapno.json must exist (arrfast/README.md).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { open, setup, log } from '../arrfast/setup.mjs'
const argv = process.argv.slice(2)
const sep = argv.indexOf('--')
const [image, outDir, ...migs] = sep < 0 ? argv : argv.slice(0, sep)
const opts = sep < 0 ? [] : argv.slice(sep + 1)
const maxes = (opts[opts.indexOf('--max') + 1] ?? '600,8').split(',').map(Number)
mkdirSync(outDir, { recursive: true })
const db = await open(image, [])
const q = await setup(db, false)
for (const m of migs) {
  const notices = []; const t0 = Date.now()
  await db.exec(readFileSync(m, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) })
  log('applied', m.split(/[\\/]/).pop(), Date.now() - t0, 'ms'); for (const n of notices) if (/self-assert/.test(n)) log('NOTICE', n.slice(0, 600))
}
const sql = readFileSync(new URL('./bands.sql', import.meta.url), 'utf8')
log('knobs', JSON.stringify((await q(`select json_object_agg(key, value) j from public.world_config where key like 'haul%'`))[0].j))
for (const mx of maxes) {
  const t0 = Date.now()
  await db.exec('begin')
  try {
    await q(`update public.world_config set value = to_jsonb($1::numeric) where key = 'haul_max'`, [mx])
    const moved = (await q(`with u as (update public.port_goods pg set haul = h.haul, haul_nm = h.haul_nm from world.haul_rows() h
                             where h.port_id = pg.port_id and h.good_id = pg.good_id and (pg.haul is distinct from h.haul or pg.haul_nm is distinct from h.haul_nm) returning 1)
                           select count(*) n from u`))[0].n
    const far = (await q(`select max(haul) mx, count(*) filter (where haul > 1) n from public.port_goods`))[0]
    const rows = await q(sql)
    writeFileSync(`${outDir}/max${mx}.json`, JSON.stringify(rows, null, 1))
    log('haul_max', mx, 'rows moved', moved, 'max haul', far.mx, 'far rows', far.n, 'measured in', Date.now() - t0, 'ms')
  } finally {
    await db.exec('rollback')
  }
}
process.exit(0)
