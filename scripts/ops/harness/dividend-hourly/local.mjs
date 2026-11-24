// local.mjs: the chain's world before and after 0495, from the prefix cache. LOCAL ONLY (PGlite); not in CI; everything is rolled back.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/dividend-hourly/local.mjs ["<sql>" | <file.sql> ...]
// Prints: the md5 of the hunked bodies before 0495 and after it (what before-0495.sql / after-0495.sql expect on prod), 0495's own
// receipt, and the rows of any SQL given (run on the world after 0495). A .sql file may hold several statements (rollback-0495.sql;
// before-0495.sql / after-0495.sql, whose own transaction lines are dropped here).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const ME = '20260818000495'
const BODIES = `select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\\r', ''))) as bodies
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('tick_city', 'city_coupons', 'city_coupon_hour', 'dividend_hourly_on', 'real_hour')`
async function world(upTo) {
  const files = []
  for (const name of await migrationFiles()) {
    if (name.slice(0, 14) > upTo) continue
    files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
  }
  return applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {},
    required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
}
const before = await world('20260818000494')
console.log('BEFORE 0495', JSON.stringify((await before.db.query(BODIES)).rows[0].bodies))
await before.db.close()
const after = await world(ME)
console.log('AFTER 0495 ', JSON.stringify((await after.db.query(BODIES)).rows[0].bodies))
for (const r of after.applied) if (r.name.startsWith(ME)) for (const n of r.notices) console.log('RECEIPT', n)
await after.db.exec('begin')
for (const q of process.argv.slice(2)) {
  if (q.endsWith('.sql')) {
    const sql = (await readFile(q, 'utf8')).replace(/^(begin transaction read only|rollback);\s*$/gm, '')
    const res = await after.db.exec(sql, { onNotice: (n) => console.log('NOTICE', n.message) })
    console.log(JSON.stringify(res.at(-1)?.rows ?? []))
  } else console.log(JSON.stringify((await after.db.query(q)).rows))
}
await after.db.exec('rollback')
await after.db.close()
