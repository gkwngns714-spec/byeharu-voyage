// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof.mjs — apply the chain, then run every proof in a transaction that is thrown away
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHAT GREEN MEANS HERE
//   NOT "psql exited 0". Green means: every PASS marker the proof file DECLARED IN ITS OWN HEADER
//   actually appeared in the output. That distinction is the whole point of this file.
//
//   A proof that stops emitting a marker — because a branch was deleted, because a loop found no
//   rows, because someone commented out the interesting half — still exits 0. It is then a check
//   that cannot fail, which is worse than no check at all, because it reports a safety it never
//   examined. So:
//
//     * a proof declaring ZERO markers FAILS as vacuous;
//     * a declared marker that never appears FAILS;
//     * a marker that appears but was never declared FAILS (the declaration has drifted from the
//       proof, and a stale declaration is how the first two checks get quietly disarmed).
//
// THE DECLARATION
//   Each proof declares its markers in header comments, one per line, before any SQL:
//
//     -- @pass PROOF_NAME_STEP_A   what this specific marker establishes
//
//   and emits them from SQL as:
//
//     raise notice 'PASS: PROOF_NAME_STEP_A — 188 nm, 1.6 voyage-days';
//
// ISOLATION
//   Every proof runs inside BEGIN ... ROLLBACK issued by THIS file, so a proof can insert players,
//   sail fleets and move money without leaving a trace in the applied chain. The rollback is not
//   taken on trust: a per-table row-count digest is taken before and after each proof, and a proof
//   that changed the committed state FAILS even if all its markers appeared. `COMMIT` in a proof
//   body is refused outright, because it would defeat that.
//
// USAGE
//   node scripts/db/proof.mjs                 # every proof in scripts/db/proofs/
//   node scripts/db/proof.mjs offline         # only proofs whose filename contains "offline"
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readdir, readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { applyChain, REPO_ROOT, selfAssertReceipts } from './apply-chain.mjs'

const PROOFS_DIR = path.join(REPO_ROOT, 'scripts', 'db', 'proofs')

const DECLARE_RE = /^\s*--\s*@pass\s+([A-Z][A-Z0-9_]*)\b/
const EMIT_RE = /\bPASS:\s*([A-Z][A-Z0-9_]*)/g

/** The committed-state digest: one row count per ordinary table in public. */
async function digest(db) {
  const tables = await db.query(`
    select c.relname as t
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
     order by c.relname
  `)
  const parts = []
  for (const { t } of tables.rows) {
    const r = await db.query(`select count(*)::int as n from public."${t}"`)
    parts.push(`${t}=${r.rows[0].n}`)
  }
  return parts.join(',')
}

const filter = process.argv.slice(2).find((a) => !a.startsWith('-'))

let files
try {
  files = (await readdir(PROOFS_DIR)).filter((f) => f.endsWith('.sql')).sort()
} catch {
  console.error(`FAIL: ${PROOFS_DIR} does not exist. There are no proofs to run.`)
  process.exit(1)
}
if (filter) files = files.filter((f) => f.includes(filter))

if (files.length === 0) {
  console.error(`FAIL: no proof .sql files matched${filter ? ` "${filter}"` : ''} in ${PROOFS_DIR}.`)
  process.exit(1)
}

let db
try {
  const chain = await applyChain({ quiet: true })
  db = chain.db
  console.log(
    `chain: ${chain.applied.length} migration(s) applied, ` +
      `${selfAssertReceipts(chain.notices)} self-assert receipt(s)`,
  )
  // The same world guard `npm run db:apply` runs: the applied world must EQUAL data/*.json
  // before any proof is allowed to certify anything about it (scripts/db/world-guard.mjs,
  // 2026-08-24 — the day 0003 turned out to have been edited after production applied it).
  const { assertWorldMatchesData } = await import('./world-guard.mjs')
  await assertWorldMatchesData(db, { log: console.log })
  // 0047: the proofs sail like players — they PROPOSE courses and the server verifies them.
  // The proposals are a test fixture (schema `proof`), invisible to the per-proof digest, which
  // reads public tables only. See ./proof-courses.mjs.
  const { installProofCourses } = await import('./proof-courses.mjs')
  await installProofCourses(db)
  // The ONE authority for "hold the market still so a measurement means something": every apply
  // deals a different drift (0010's random() step) and a different stock (a function of the wall
  // clock), and a proof that measures the economy on top of that is a lottery. See
  // ./market-fixture.mjs. Installing it is not using it — proofs 04 and 05 call it; the rest do
  // not, and measure the market this apply happened to build, deliberately.
  const { installMarketFixture } = await import('./market-fixture.mjs')
  await installMarketFixture(db, { log: console.log })
} catch (err) {
  console.error(err.message)
  process.exit(1)
}

console.log(`proofs: ${files.length} file(s) in scripts/db/proofs/`)
console.log('')

let failed = 0
let totalDeclared = 0
let totalSeen = 0

for (const file of files) {
  const full = path.join(PROOFS_DIR, file)
  const sql = await readFile(full, 'utf8')

  if (sql.includes('\r')) {
    console.error(`✗ ${file}\n    FAIL: CRLF in proof file; proofs must be LF-only.`)
    failed += 1
    continue
  }

  const declared = []
  for (const line of sql.split('\n')) {
    const m = DECLARE_RE.exec(line)
    if (m) declared.push(m[1])
  }

  if (declared.length === 0) {
    console.error(`✗ ${file}\n    FAIL: VACUOUS — the file declares no "-- @pass MARKER" lines.`)
    console.error('        A proof that names nothing it proves cannot be shown to have proved it.')
    failed += 1
    continue
  }

  if (/^\s*commit\s*;/im.test(sql)) {
    console.error(`✗ ${file}\n    FAIL: proof contains COMMIT; that defeats the rollback isolation.`)
    failed += 1
    continue
  }

  const before = await digest(db)
  const notices = []
  let error = null

  await db.exec('begin;')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (err) {
    error = err
  } finally {
    try {
      await db.exec('rollback;')
    } catch {
      /* the proof may have aborted the transaction already; rollback is still correct */
    }
  }
  const after = await digest(db)

  const seen = new Set()
  for (const line of notices) {
    EMIT_RE.lastIndex = 0
    let m
    while ((m = EMIT_RE.exec(line)) !== null) seen.add(m[1])
  }

  const missing = declared.filter((d) => !seen.has(d))
  const undeclared = [...seen].filter((s) => !declared.includes(s))
  const leaked = before !== after

  totalDeclared += declared.length
  totalSeen += declared.filter((d) => seen.has(d)).length

  const ok = !error && missing.length === 0 && undeclared.length === 0 && !leaked

  if (ok) {
    console.log(`✓ ${file}  — ${declared.length}/${declared.length} PASS markers`)
    for (const line of notices) if (/PASS:/.test(line)) console.log(`    ${line}`)
  } else {
    failed += 1
    console.error(`✗ ${file}  — ${declared.length - missing.length}/${declared.length} PASS markers`)
    for (const line of notices) console.error(`    ${line}`)
    if (error) {
      console.error(`    SQL ERROR: ${error.message}`)
      if (error.code) console.error(`      sqlstate: ${error.code}`)
      if (error.detail) console.error(`      detail: ${error.detail}`)
      if (error.hint) console.error(`      hint: ${error.hint}`)
      if (error.where) console.error(`      context: ${error.where}`)
    }
    if (missing.length) console.error(`    MISSING PASS MARKER(S): ${missing.join(', ')}`)
    if (undeclared.length) {
      console.error(`    UNDECLARED PASS MARKER(S): ${undeclared.join(', ')}`)
      console.error('      Add a "-- @pass" line for each, or the declaration has drifted.')
    }
    if (leaked) {
      console.error('    COMMITTED-STATE LEAK: row counts changed across the rolled-back proof.')
      console.error(`      before: ${before}`)
      console.error(`      after:  ${after}`)
    }
  }
  console.log('')
}

console.log('═══════════════════════════════════════════════════════════════════════')
if (failed === 0) {
  console.log(`PROOFS PASSED: ${files.length} file(s), ${totalSeen}/${totalDeclared} PASS markers seen`)
  console.log('═══════════════════════════════════════════════════════════════════════')
  await db.close()
  process.exit(0)
} else {
  console.error(`PROOFS FAILED: ${failed} of ${files.length} file(s); ${totalSeen}/${totalDeclared} PASS markers seen`)
  console.error('═══════════════════════════════════════════════════════════════════════')
  await db.close()
  process.exit(1)
}
