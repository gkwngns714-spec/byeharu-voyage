// Time each migration separately, so a slow one can be found instead of guessed at.
// Run: node scripts/db/time-chain.mjs [stopAfterPrefix]
import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import path from 'node:path'

const stopAfter = process.argv[2] ?? '9999'
const db = new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const file of await migrationFiles()) {
  const sql = await readFile(path.join(MIGRATIONS_DIR, file), 'utf8')
  const t = Date.now()
  try {
    await db.exec(sql)
  } catch (e) {
    console.log(`${file}  FAILED after ${((Date.now() - t) / 1000).toFixed(1)} s`)
    console.log('   ', e.message)
    process.exit(1)
  }
  console.log(`${file}  ${((Date.now() - t) / 1000).toFixed(1)} s`)
  if (file.slice(10, 14) >= stopAfter) break
}
await db.close()
