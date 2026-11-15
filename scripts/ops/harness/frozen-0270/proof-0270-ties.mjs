// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0270-ties.mjs — FROZEN 0266–0274: the probe's digest must not sort by the uuids the probe drew.
// LOCAL ONLY (PGlite); not in CI. Source of the figures in the PR that added the patches.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   node scripts/ops/harness/frozen-0270/proof-0270-ties.mjs                every check on 0270 (about 4 min)
//   node scripts/ops/harness/frozen-0270/proof-0270-ties.mjs --file=0274    the same on 0274 (the same loop probe)
//   ... --runs=12   applies of the file per case (default 12)
//
// THE DEFECT. Six frozen files (0266, 0269, 0270, 0272, 0273, 0274) compare an OLD body with a NEW one by a text
// digest of the rows each leaves (pg_temp.digest_NNNN). The digest sorts a house's ledger rows and events by
// their JSON text and blanks the uuids AFTERWARDS, on the whole string. A ledger row's text is kind, player_id,
// created_at, ducats_delta, ref_event_id, balance_after — so two rows of one house with one kind and one amount
// are ordered by ref_event_id, a gen_random_uuid() the probe drew, and differ after it (balance_after). Every run
// draws new uuids: the two rows swap at random and two IDENTICAL runs digest differently.
//   main, run 43708858363 (2026-11-15), pglite-gate (merchants), from zero:
//   "0270 self-assert FAIL: the loop leaves different rows: …" — both receipts equal, the 1,200 characters the
//   file prints equal; the ledger leg passed on the same commit.
// Whether a world holds such a pair is the market's dice (what each merchant buys, what her insurance costs).
// This script MAKES one, the same on every machine: both provisioning prices at 0, inside the transaction that is
// rolled back, so the two merchants of one house in 0270's loop (Kamer Amsterdam: Retourvloot, Oostzeevaart) each
// write a PROVISION row of amount 0 at a different balance.
//
// HOW IT RUNS THE FILE. The WHOLE file, in one transaction that is rolled back, on the cached world at the head
// before it (never from zero: it needs the local prefix cache and only reads it; nothing is written to or pruned
// from it). The file prints 1,200 characters of each digest; here the two raises print them whole (the same in
// every case: instrumentation, not part of the patch), so the rows that differ can be read.
//
// WHAT IT CHECKS (any miss exits 1):
//   1. RED FIRST  the file as written, with the tied pair: it fails some of the time with "the loop leaves
//                 different rows", it passes some of the time, and in EVERY failure the two digests hold the SAME
//                 rows in another order (the multisets are equal) — it is the eye, not the bodies;
//   2. THE PATCH  the patched text (sqlToApply, the applier's own path) only adds lines, before the self-assert's
//                 first statement;
//   3. GREEN      the patched text, with the same tied pair: every run passes and prints its receipt;
//   4. MUTANT     the patched assert can still fail: one more event written by the NEW loop is red, for that reason.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { sqlToApply } from '../../../../src/lib/db/frozenAsserts.ts'

const opt = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const N = opt('file') ?? '0270'
const RUNS = Number(opt('runs') ?? 12)
if (!['0270', '0274'].includes(N)) throw new Error('--file is 0270 or 0274 (the two loop probes with two merchants of one house)')
const say = (...a) => console.log(...a)
const failures = []
const expect = (ok, what) => {
  say(`   ${ok ? 'ok  ' : 'FAIL'} ${what}`)
  if (!ok) failures.push(what)
}

const names = await migrationFiles()
const NAME = names.find((f) => f.startsWith(`2026081800${N}_`))
const raw = await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')
const patched = sqlToApply({ name: NAME, sql: raw })

// the two digests whole, in both texts alike
const whole = (sql) => {
  const cut = "left(v_ro->>'digest', 1200), left(v_rn->>'digest', 1200);"
  if (sql.split(cut).length !== 2) throw new Error('the loop raise is not where this script expects it')
  return sql.replace(cut, "v_ro->>'digest', v_rn->>'digest';")
}
const TIE = "update public.world_config set value = to_jsonb(0) where key in ('provision_food_price', 'provision_water_price');"
const MUTANT_AT = `      call pg_temp.reconcile_new_${N}(false);\n`
const mutant = (sql) => {
  if (sql.split(MUTANT_AT).length !== 2) throw new Error('the new loop call is not where this script expects it')
  return sql.replace(
    MUTANT_AT,
    MUTANT_AT + "      perform public.emit_event(s.player_id, 'MUTANT', jsonb_build_object('x', gen_random_uuid()));\n",
  )
}

// THE WORLD BEFORE THE FILE: the longest cached prefix, then the files up to it through the applier. Read only.
const before = []
for (const name of names.filter((f) => f < NAME)) before.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const { db } = await applyWithPrefixCache({
  variant: await preambleVariant(),
  files: before,
  cacheDir: PREFIX_CACHE_DIR,
  log: (m) => say(`   ${m}`),
  required: true,
  snapshots: false,
})

const rowsOf = (digest) => digest.split(/ ## | # |(?<=\}),(?=\{)/)
async function run(sql) {
  const notices = []
  await db.exec('begin')
  try {
    await db.exec(TIE)
    await db.exec(sql, { onNotice: (n) => notices.push(String(n.message ?? n)) })
    return { ok: true, receipt: notices.some((l) => l.startsWith(`${N} self-assert ok:`)) }
  } catch (err) {
    const message = String(err.message)
    const m = /^(\d{4} self-assert FAIL: the loop leaves different rows): (.*) \/ (\{.*)$/s.exec(message)
    if (!m) return { ok: false, message, loop: false }
    const [a, b] = [rowsOf(m[2]), rowsOf(m[3])]
    const moved = a.map((row, i) => (row === b[i] ? null : row)).filter(Boolean)
    return {
      ok: false,
      message,
      loop: true,
      sameRows: JSON.stringify([...a].sort()) === JSON.stringify([...b].sort()),
      moved,
    }
  } finally {
    await db.exec('rollback')
  }
}

say(`\n1. RED FIRST — ${NAME} as written, a tied pair made (${RUNS} applies)`)
const red = []
for (let i = 0; i < RUNS; i += 1) red.push(await run(whole(raw)))
const redFails = red.filter((r) => !r.ok)
say(`   ${redFails.length} of ${RUNS} failed`)
expect(redFails.length > 0, 'the file as written fails some of the time')
expect(redFails.length < RUNS, 'and passes some of the time (the same world, the same text)')
expect(redFails.every((r) => r.loop), 'every failure is "the loop leaves different rows"')
expect(redFails.every((r) => r.sameRows), 'in every failure the two digests hold the SAME rows, in another order')
expect(
  redFails.every((r) => r.moved.every((row) => /^\{"kind": "[A-Z_]+", "player_id": "U", "created_at": "[^"]+", "ducats_delta": -?\d+, "ref_event_id": "U", "balance_after": -?\d+\}$/.test(row))),
  'and every row that moved is a ledger row (kind, amount, the blanked ref_event_id, then its balance)',
)
if (redFails[0]?.moved?.length) say(`   e.g. ${redFails[0].moved.slice(0, 2).join('\n        ')}`)

say('\n2. THE PATCH — sqlToApply on the real file')
const head = `  select * into v_b from before_${N};\n`
expect(patched !== raw && patched.length > raw.length, 'the patched text differs from the file')
expect(
  patched.slice(0, raw.indexOf(head)) === raw.slice(0, raw.indexOf(head)) && patched.endsWith(raw.slice(raw.indexOf(head))),
  "it only adds lines, before the self-assert's first statement",
)
say(`   + ${patched.split('\n').length - raw.split('\n').length} lines`)

say(`\n3. GREEN — the patched text, the same tied pair (${RUNS} applies)`)
const green = []
for (let i = 0; i < RUNS; i += 1) green.push(await run(whole(patched)))
say(`   ${green.filter((r) => !r.ok).length} of ${RUNS} failed`)
expect(green.every((r) => r.ok), 'every apply passes')
expect(green.every((r) => r.receipt), `and prints "${N} self-assert ok:"`)
const firstBad = green.find((r) => !r.ok)
if (firstBad) say(`   ${firstBad.message.slice(0, 600)}`)

say('\n4. MUTANT — the patched text, one more event written by the NEW loop (3 applies)')
const mut = []
for (let i = 0; i < 3; i += 1) mut.push(await run(mutant(whole(patched))))
expect(mut.every((r) => !r.ok && r.loop), 'red every time, with "the loop leaves different rows"')
expect(mut.every((r) => r.sameRows === false), 'and the two digests do NOT hold the same rows')

await db.close()
say('')
if (failures.length) {
  say(`FAILED: ${failures.length} expectation(s)\n  - ${failures.join('\n  - ')}`)
  process.exit(1)
}
say(`PROVEN on ${NAME}: unpatched ${redFails.length}/${RUNS} red by row order alone, patched 0/${RUNS}, mutant red.`)
