// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0060.mjs — watch every guard in migration 0060 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0060 exactly once, then runs MUTATED copies of 0060 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0060.mjs               # every mutation
//   node scripts/db/breaktest-0060.mjs --clean       # apply 0060 unmutated, print its receipt
//   node scripts/db/breaktest-0060.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Shape copied from scripts/db/breaktest-0058.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000060_forty_harbours_stop_sailing_overland.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f >= LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied up to (not including) 0060\n')

// ── the unmutated run: it must be GREEN, and its receipt is the measurement this file reports ──
{
  const notices = []
  await db.exec('begin')
  let red = null
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message)
  }
  await db.exec('rollback').catch(() => {})
  if (red) {
    console.log(`UNMUTATED 0060 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0060: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// Each mutation is [name, find, replace, …] — pairs, applied in order. Every one of them makes a
// statement about the WORLD false, not merely a sentence in the file: a harbour left on its old
// snap, a reading nudged, an allowance handed back.
const MUTATIONS = [
  ['(a3) the worst harbour keeps her old snap — Longyearbyen still buys 67.68 nm of exempt land',
    "    ('LNG', 0.00, ", "    ('LNG', 67.68, "],

  ['(a3) a harbour that was already inside the threshold is moved anyway — Algiers 0.00 -> 5.00',
    "    ('ALG', 0.00, ", "    ('ALG', 5.00, "],

  ['(a3) the file is cut against a sea that never had the defect — the before-count reads 0, not 40',
    'select count(*) into v_n from _0060_before where snap_nm > 20;',
    'select count(*) into v_n from _0060_before where snap_nm > 2000;'],

  ['(a4) the per-harbour ledger disagrees — Tokyo actually lands on 9.84 nm, not the 9.83 the file claims',
    "    ('TOK', 9.83, ", "    ('TOK', 9.84, "],

  ['(c2) a reading between two UNTOUCHED harbours moves 100 nm — a shortcut, not a coast-hug',
    '"HAM":351.5', '"HAM":451.5', '"BRU":351.5', '"BRU":451.5'],

  ['(f) an unmoved ocean road moves — Alexandria->Aden loses 500 nm round the Cape',
    '"ADE":11049.5', '"ADE":10549.5', '"ALE":11049.5', '"ALE":10549.5'],

  ['(g) the old land-exempt allowance is handed back to Longyearbyen — her overland course is legal again',
    "where code = 'LNG') + 25", "where code = 'LNG') + 95"],

  ['(e) the Arctic reopens — Lisbon->Nagasaki falls under the 12,000 nm floor',
    '"NAG":12991.5', '"NAG":7565.0', '"LIS":12991.5', '"LIS":7565.0'],
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) {
      missing = true
      break
    }
    mutated = mutated.split(hunks[i]).join(hunks[i + 1])
  }
  if (missing) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  await db.exec('rollback').catch(() => {})
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red.slice(0, 420)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
