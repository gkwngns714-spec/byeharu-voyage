// sim.mjs: THE PLANNER WITH AND WITHOUT THE DOCK FEE, on the cached world. LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/plan-fees/sim.mjs [--limit=N] [--purse=N] [--fixture]
//
// Restores the cached world at the head before 0406 (never from zero; the cache is only read), applies 0406, then runs sim-scene.sql TWICE, each in its
// own rolled-back transaction: BEFORE (the fee knobs at 0 while planning: 0406's self-assert proves that plan is the pre-image's) and AFTER (prod's knobs:
// port_fee_base 250, port_fee_pct 0.005). In both the economy is closed and the purses lit, every merchant is planned alone at her lap start by the real
// planner, and the loop she wrote is then priced with prod's fee. One row an arm. --fixture installs the proofs' market (prices that pay) first.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const NAME = '20260818000406'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
console.log(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
if (process.argv.includes('--fixture')) {
  await (await import('../../../db/proof-courses.mjs')).installProofCourses(db)
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  console.log('market fixture installed')
}
await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''))
console.log(`applied ${mine}`)
const scene = (await readFile(new URL('./sim-scene.sql', import.meta.url), 'utf8')).replaceAll('\r', '').replace('/*LIMIT*/', arg('limit') ? `limit ${Number(arg('limit'))}` : '')
  .replace('/*PURSE*/', arg('purse') ? `update public.players set ducats = ${Number(arg('purse'))} where is_npc and id in (select player_id from public.npc_houses);` : '')
let bad = 0
for (const [name, base, pct] of [['BEFORE (fee 0 while planning)', 0, 0], ['AFTER (prod knobs: 250 + 0.5 %)', 250, 0.005]]) {
  await db.exec('begin')
  const t = Date.now()
  try {
    const res = await db.exec(scene.replace('/*BASE*/', String(base)).replace('/*PCT*/', String(pct)), { onNotice: (n) => console.log('  ', n.message) })
    console.log(`${name}: ${Date.now() - t} ms`)
    console.log('  ', JSON.stringify(res.findLast((r) => r.rows?.length)?.rows?.[0]))
  } catch (e) { bad++; console.log(`${name}: ERROR ${e.message} ${e.where ?? ''}`) }
  await db.exec('rollback')
}
await db.close()
process.exit(bad ? 1 : 0)
