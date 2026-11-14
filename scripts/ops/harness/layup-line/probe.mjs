// probe.mjs: 0405's OWN SELF-ASSERT ON A WORLD THAT HAS A LINE. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/layup-line/probe.mjs
//
// The cached world's merchants are dark, so the file's probe finds nobody there. Prod has a line of about two hundred. This applies the file three
// times, each in a rolled-back transaction, on the cached world at the head before it: as it is (dark: no probe), with the merchants lit and nobody
// laid up (the probe stages one), and with 30 laid up, 20 of them due (the probe takes the one waiting longest, as on prod). Prints each notice.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const NAME = '20260818000405'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const sql = (await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', '')
const lit = `update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null from public.npc_fleets nf where nf.route_id = sr.id;`
const line = `${lit}
with l as (select ro.fleet_id, ro.route_id, row_number() over (order by ro.k) as i from public.npc_tend_roster() ro
             join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED' order by ro.k limit 30),
     a as (update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - make_interval(mins => case when l.i <= 20 then 30 + l.i::int else 2 end) from l where l.route_id = sr.id returning 1)
update public.npc_fleets nf set asked_at = null from l where l.fleet_id = nf.fleet_id;`
let bad = 0
for (const [name, scene] of [['dark, as cached', ''], ['lit, nobody laid up', lit], ['lit, a line of 30 (20 due)', line]]) {
  await db.exec('begin')
  const t = Date.now()
  try {
    await db.exec(scene)
    await db.exec(sql, { onNotice: (n) => { if (n.message.includes('self-assert')) console.log(`  ${n.message}`) } })
    console.log(`${name}: applied in ${Date.now() - t} ms`)
  } catch (e) { bad++; console.log(`${name}: ERROR ${e.message}`) }
  await db.exec('rollback')
}
await db.close()
process.exit(bad ? 1 : 0)
