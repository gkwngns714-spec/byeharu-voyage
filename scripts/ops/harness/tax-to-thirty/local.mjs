// local.mjs: the chain's world up to a version, from a prefix cache. LOCAL ONLY (PGlite); not in CI; everything is rolled back.
//   BV_CACHE_DIR=<a private dir> node scripts/ops/harness/tax-to-thirty/local.mjs <up to version> ["<sql>" | <file.sql> ...]
// With BV_CACHE_DIR the snapshots are read from and written to that private directory (seed it with one snapshot copied from
// node_modules/.cache/byeharu-chain-prefix/preamble). Without it the shared cache is read and NOTHING is written or pruned there.
// Prints the receipts of the migrations applied in this run, then the rows of each SQL given (a .sql file may hold several
// statements; a prod check's own transaction lines are dropped).
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const upTo = process.argv[2]
const priv = process.env.BV_CACHE_DIR
const files = []
for (const name of await migrationFiles()) {
  if (name.slice(0, 14) > upTo) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: priv ?? PREFIX_CACHE_DIR, log: () => {},
  required: true, snapshots: Boolean(priv) })
console.log(`restored ${out.restored}/${files.length}`)
for (const r of out.applied.slice(out.restored)) for (const n of r.notices) if (/self-assert ok/.test(n)) console.log('RECEIPT', r.name.slice(10, 14), n)
await out.db.exec('begin')
for (const q of process.argv.slice(3)) {
  if (q.endsWith('.sql')) {
    const sql = (await readFile(q, 'utf8')).replace(/^(begin transaction read only|rollback);\s*$/gm, '')
    const res = await out.db.exec(sql, { onNotice: (n) => console.log('NOTICE', n.message) })
    console.log(JSON.stringify(res.at(-1)?.rows ?? []))
  } else console.log(JSON.stringify((await out.db.query(q)).rows))
}
await out.db.exec('rollback')
await out.db.close()
