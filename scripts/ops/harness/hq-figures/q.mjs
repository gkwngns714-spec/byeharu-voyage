// A reader on the chain's cached world (local PGlite only, never prod): node scripts/ops/harness/hq-figures/q.mjs <file.sql> [...]
// Each file is one statement (or one DO block), run in a transaction that is rolled back; notices are printed.
// It RESTORES the longest cached prefix and applies the rest in memory: it writes no snapshot and prunes nothing (snapshots: false),
// so the shared cache is left exactly as it was.
import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

export async function world() {
  const names = (await readdir(MIGRATIONS_DIR)).filter((n) => n.endsWith('.sql')).sort()
  const files = []
  for (const name of names) files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
  const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, snapshots: false, log: (m) => /restored|applying|REFUSED/.test(String(m)) && console.log(String(m).slice(0, 300)) })
  if (out.restored < files.length - 3) throw new Error(`only ${out.restored} of ${files.length} files were cached: refusing a long replay`)
  return out.db
}

if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  const db = await world()
  for (const f of process.argv.slice(2)) {
    const sql = await readFile(f, 'utf8')
    await db.exec('begin')
    try {
      const r = await db.query(sql, [], { onNotice: (n) => console.log('NOTICE:', n.message) })
      for (const row of r.rows) console.log(Object.values(row).length === 1 ? Object.values(row)[0] : JSON.stringify(row))
    } catch (e) {
      console.log('ERROR:', e.message)
    }
    await db.exec('rollback')
  }
  await db.close()
  process.exit(0)
}
