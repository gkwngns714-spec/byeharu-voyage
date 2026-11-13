// q.mjs - LOCAL ONLY: restore the cached world (never from zero) and run SQL files in a rolled-back transaction, printing rows and notices.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/more-ships/q.mjs [--before=<migration name prefix>] file.sql [...]
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const args = process.argv.slice(2)
const before = args.find((a) => a.startsWith('--before='))?.slice(9) ?? null
const sqlFiles = args.filter((a) => !a.startsWith('--'))
const files = []
for (const name of await migrationFiles()) {
  if (before && name >= before) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const t0 = Date.now()
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const db = out.db
console.log(`world: head ${files.at(-1).name.slice(0, 18)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied, ${((Date.now() - t0) / 1000).toFixed(1)} s`)
for (const r of out.applied.filter((r) => !r.restored)) console.log(`  applied ${r.name}`)
let bad = 0
for (const f of sqlFiles) {
  const sql = (await readFile(f, 'utf8')).replaceAll('\r', '')
  const t1 = Date.now()
  await db.exec('begin')
  try {
    const res = await db.exec(sql, { onNotice: (n) => console.log('NOTICE:', n.message) })
    for (const r of res) if (r.rows?.length) console.log(JSON.stringify(r.rows, null, 0).replaceAll('},{', '},\n{'))
  } catch (e) {
    bad++
    console.log(`ERROR in ${f}: ${e.message}`)
  }
  try { await db.exec('rollback') } catch { /* aborted */ }
  console.log(`-- ${f}: ${((Date.now() - t1) / 1000).toFixed(1)} s`)
}
await db.close()
process.exitCode = bad ? 1 : 0
