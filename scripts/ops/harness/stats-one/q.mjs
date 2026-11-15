// q.mjs: read-only queries on the cached head world (the chain before BV_BEFORE), in a rolled-back transaction. LOCAL ONLY; not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/stats-one/q.mjs "<sql>" ...
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
const files = []
const BEFORE = process.env.BV_BEFORE ?? '20260818000448'
for (const name of await migrationFiles()) { if (name >= BEFORE) continue; files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') }) }
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
await db.exec('begin')
for (const q of process.argv.slice(2)) { const r = await db.query(q); console.log(JSON.stringify(r.rows)) }
await db.exec('rollback')
await db.close()
