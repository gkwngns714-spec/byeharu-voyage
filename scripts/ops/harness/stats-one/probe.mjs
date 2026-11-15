// probe.mjs: migration 0448 ON THE CACHED HEAD WORLD (the chain before it), in one rolled-back transaction. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/stats-one/probe.mjs [--pre=scene.sql] [--fix] [scene.sql | NN_proof.sql ...]
// --pre runs a scene BEFORE the file; --fix applies the file (still inside the transaction); then each scene or proof file runs and prints its
// notices and last rows.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const NAME = process.env.BV_NAME ?? '20260818000448'
const files = []
let mine = null
for (const name of await migrationFiles()) {
  if (name.startsWith(NAME)) { mine = name; continue }
  if (name > NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const run = async (f) => {
  const res = await db.exec((await readFile(f, 'utf8')).replaceAll('\r', ''), { onNotice: (n) => console.log(`  [${path.basename(f)}] ${n.message}`) })
  const last = res.at(-1)
  if (last?.rows?.length) for (const r of last.rows) console.log('  ' + JSON.stringify(r))
}
let bad = 0
await db.exec('begin')
try {
  for (const a of process.argv.filter((x) => x.startsWith('--pre='))) await run(a.slice(6))
  if (process.argv.includes('--fix')) {
    const t = Date.now()
    await db.exec((await readFile(path.join(MIGRATIONS_DIR, mine), 'utf8')).replaceAll('\r', ''), { onNotice: (n) => console.log(`  ${n.message}`) })
    console.log(`applied ${mine} in ${Date.now() - t} ms`)
  }
  for (const f of process.argv.slice(2).filter((x) => !x.startsWith('--'))) await run(f)
} catch (e) { bad++; console.log(`ERROR ${e.message}`, e.where ?? '', e.position ?? '', e.internalQuery ? String(e.internalQuery).slice(0, 600) : '') }
await db.exec('rollback')
await db.close()
process.exit(bad ? 1 : 0)
