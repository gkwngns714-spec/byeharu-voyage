// q.mjs: read-only queries on the cached head world (main's chain up to 0426), in a rolled-back transaction. LOCAL ONLY.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirate-war/q.mjs "<sql>" ...
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const files = []
for (const name of await migrationFiles()) { if (name >= '20260818000429') continue; files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') }) }
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
await db.exec('begin')
for (const q of process.argv.slice(2)) { const r = await db.query(q); console.log(JSON.stringify(r.rows)) }
await db.exec('rollback')
await db.close()
