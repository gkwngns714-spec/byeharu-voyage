// sim.mjs: THE "NO OPEN LOOP" SIMULATION for 0397 (a merchant sails the seas her hull can hold). LOCAL ONLY; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-merchants/sim.mjs [--limit=N] [--fixture] [--json=<file>] [--scene=<file.sql>]
//
// Restores the cached world at the head before 0397 (never from zero; the cache is only read), applies 0397, then runs sim-scene.sql TWICE, each in its own
// rolled-back transaction: DARK (sea_conditions_bite_npc false) and LIT (true). The scene starts every merchant on her route where she lies and plans each one
// alone at her lap start through the real planner (public.npc_plan), then reads what was written. It prints one table: by hull size, the loops with a leg the
// sea closes before the plan, the fleets moved to another loop, the loops still closed after, the fleets left with no BUY, and the fleets laid up.
// --fixture installs the market fixture of the proofs first (prices that pay); without it the cached world's own market is used.
// --scene runs another scene the same way (twice, dark then lit), printing its notices and its last rows.
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000397'
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const say = (...a) => console.log(...a)
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) mine = name
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored`)
if (process.argv.includes('--fixture')) {
  await (await import('../../../db/market-fixture.mjs')).installMarketFixture(db, { log: () => {} })
  say('market fixture installed')
}
await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''))
say(`applied ${mine}`)
const sceneFile = arg('scene') ?? new URL('./sim-scene.sql', import.meta.url)
const scene = (await readFile(sceneFile, 'utf8')).replaceAll('\r', '').replace('/*LIMIT*/', arg('limit') ? `limit ${Number(arg('limit'))}` : '')
const arms = {}
for (const lit of [false, true]) {
  await db.exec('begin')
  await db.query(`update public.world_config set value = $1::jsonb where key = 'sea_conditions_bite_npc'`, [String(lit)])
  const t = Date.now()
  let rows = null
  try {
    const res = await db.exec(scene, { onNotice: (n) => say('  ', n.message) })
    rows = res.findLast((r) => r.rows?.length)?.rows ?? []
  } catch (e) {
    say(`ERROR ${lit ? 'lit' : 'dark'}: ${e.message} ${e.where ?? ''}`)
  }
  await db.exec('rollback')
  arms[lit ? 'lit' : 'dark'] = rows
  say(`${lit ? 'LIT' : 'DARK'}: ${Date.now() - t} ms`)
  for (const r of rows ?? []) say('  ', JSON.stringify(r))
}
if (arg('json')) await writeFile(arg('json'), JSON.stringify(arms, null, 1))
await db.close()
process.exit(arms.dark && arms.lit ? 0 : 1)
