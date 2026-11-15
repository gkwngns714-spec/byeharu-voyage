// A scratch reader on the chain's cached world (local only, never prod): node scripts/ops/harness/battle-stats/q.mjs <file.sql> [...]
// Each file is one statement (or one DO block), run in a transaction that is rolled back. Notices are printed.
import { readFile } from 'node:fs/promises'
import { applyChainCached } from '../../../db/apply-chain.mjs'
const chain = await applyChainCached({ log: (m) => { if (/self-assert|FAIL|ERROR/i.test(String(m)) && /0450/.test(String(m))) console.log(String(m).slice(0, 1500)) } })
const db = chain.db
console.log(`world: ${chain.applied.length} files, ${chain.restored} restored`)
for (const n of chain.notices ?? []) if (/0450/.test(String(n))) console.log(String(n).slice(0, 1500))
for (const f of process.argv.slice(2)) {
  const sql = await readFile(f, 'utf8')
  await db.exec('begin')
  try {
    const r = await db.query(sql, [], { onNotice: (n) => console.log('NOTICE:', n.message) })
    for (const row of r.rows) console.log(Object.values(row).length === 1 ? Object.values(row)[0] : JSON.stringify(row))
  } catch (e) { console.log('ERROR:', e.message) }
  await db.exec('rollback')
}
await db.close()
