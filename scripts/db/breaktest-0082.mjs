// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0082.mjs — watch every guard in migration 0082 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0082 exactly once, then runs MUTATED copies of 0082
// inside begin/rollback and records the REAL red message each of its asserts produces. A mutation
// that applies cleanly is reported as GREEN!! and fails the run — that is a guard that would never
// have caught anything.
//
//   node scripts/db/breaktest-0082.mjs               # every mutation
//   node scripts/db/breaktest-0082.mjs --clean       # apply 0082 unmutated, print its receipt
//   node scripts/db/breaktest-0082.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Each mutation is the DEFECT the guard exists to stop, written as the one-line edit a tired
// author would make: a sale that moves the average, a shed that loses the cost, a TAKE that comes
// back at the wrong figure, a ledger replayed backwards, a quantity mismatch waved through, an
// unpriced purchase called free, a same-instant buy-and-sell ordered by luck, a shed placed by
// guesswork, a key on the books overwritten, a write onto one hull, a write past the verdict, a
// figure rounded on the way in, a grant that opens a door, a body that moved.
//
// Shape copied from scripts/db/breaktest-0081.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000082_the_books_are_opened_for_what_is_already_aboard.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
const t0 = Date.now()
for (const f of await migrationFiles()) {
  if (f >= LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log(`chain applied up to (not including) 0082 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0082 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0082: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the world" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── THE ARITHMETIC ──────────────────────────────────────────────────────────────────────────
  ['a SALE moves the average — the basis becomes the sale price',
    "      update hold_0082 set qty = v_hq - e.qty, basis = case when v_hq - e.qty <= 0 then null else basis end\n       where player_id = e.player_id and fleet_name = e.fleet_name and code = e.code;\n\n    elsif e.kind = 'STORED' then",
    "      update hold_0082 set qty = v_hq - e.qty, basis = e.total / e.qty\n       where player_id = e.player_id and fleet_name = e.fleet_name and code = e.code;\n\n    elsif e.kind = 'STORED' then"],
  ['STORE puts the goods ashore without their cost',
    '      insert into shed_0082 values (e.player_id, e.port_code, e.code, e.qty, v_hb)',
    '      insert into shed_0082 values (e.player_id, e.port_code, e.code, e.qty, null)'],
  ["TAKE comes back at the HOLD's figure instead of the shed's",
    'public.blend_basis(v_hq, v_hb, e.qty, v_sb))',
    'public.blend_basis(v_hq, v_hb, e.qty, v_hb))'],
  ['the ledger is replayed BACKWARDS',
    '            order by player_id, created_at, id loop',
    '            order by player_id, created_at desc, id loop'],
  ['the written figure is ROUNDED on the way in',
    'jsonb_object_agg(b.code, b.basis) as keys',
    'jsonb_object_agg(b.code, round(b.basis)) as keys'],

  // ── THE GUARDS ──────────────────────────────────────────────────────────────────────────────
  ['guard 1 — a hold that disagrees with its ledger is opened anyway',
    "              when h.qty is null or h.qty <> c.hold_qty then 'REFUSED'",
    "              when h.qty is null then 'REFUSED'"],
  ['guard 2 — a purchase with no price is called FREE',
    '      if e.total is null or coalesce(e.qty, 0) <= 0 then',
    '      if coalesce(e.qty, 0) <= 0 then',
    '      v_unit := e.total / e.qty;',
    '      v_unit := coalesce(e.total, 0) / e.qty;'],
  ['guard 3 — two arrivals in one instant are placed by picking one',
    '             coalesce(a.n_distinct, 0) > 1 as ambiguous',
    '             false as ambiguous'],
  ['guard 3 — a fleet with no arrival on record is placed at the founding port whatever its name',
    '             coalesce(a.to_code, case when fl.first_name = e2.fleet_name then fo.port_code end) as port_code,',
    '             coalesce(a.to_code, fo.port_code) as port_code,'],
  ['guard 3 — the sheds on the books are never compared with the sheds in the cities',
    '     group by u.player_id, u.port_code, u.code having sum(u.qty) <> 0);',
    '     group by u.player_id, u.port_code, u.code having false);'],
  ['guard 4 — a purchase and a sale in one instant are ordered by luck',
    "  having bool_or(kind in ('BOUGHT', 'TAKEN')) and bool_or(kind in ('SOLD', 'STORED'));",
    '  having false;'],
  ['guard 5 — a key already on the books is overwritten',
    "         case when c.any_key then 'KEPT'",
    "         case when false then 'KEPT'"],

  // ── THE WRITE ───────────────────────────────────────────────────────────────────────────────
  ['the write lands on ONE hull — the fleet is no longer one hold',
    "         where coalesce((s2.cargo->>b.code)::numeric, 0) > 0\n           and not (s2.cargo_basis ? b.code)",
    "         where coalesce((s2.cargo->>b.code)::numeric, 0) > 0\n           and s2.is_flagship\n           and not (s2.cargo_basis ? b.code)"],
  ['the write ignores the verdict — a refused pair with a figure on the books is written too',
    "join books_0082 b on b.fleet_id = s2.fleet_id and b.verdict = 'OPENED'",
    "join books_0082 b on b.fleet_id = s2.fleet_id and b.verdict <> 'KEPT' and b.basis is not null"],
  // The defect this harness FOUND on 2026-09-10 (red for the wrong reason under another mutation):
  // UPDATE ... FROM applies one join row per target row, so a hull carrying two opened goods was
  // opened for only one of them. The owner's flagship carries two. Kept here so it cannot return.
  ['the write is one UPDATE ... FROM per pair — a hull with two opened goods gets ONE of them',
    "update public.ships s\n   set cargo_basis = s.cargo_basis || k.keys\n  from (select s2.id, jsonb_object_agg(b.code, b.basis) as keys\n          from public.ships s2\n          join books_0082 b on b.fleet_id = s2.fleet_id and b.verdict = 'OPENED'\n         where coalesce((s2.cargo->>b.code)::numeric, 0) > 0\n           and not (s2.cargo_basis ? b.code)\n         group by s2.id) k\n where k.id = s.id;",
    "update public.ships s\n   set cargo_basis = jsonb_set(s.cargo_basis, array[b.code], to_jsonb(b.basis), true)\n  from books_0082 b\n where b.verdict = 'OPENED' and s.fleet_id = b.fleet_id\n   and coalesce((s.cargo->>b.code)::numeric, 0) > 0 and not (s.cargo_basis ? b.code);"],

  // ── POSTURE, AND THE BODIES THAT MUST NOT MOVE ──────────────────────────────────────────────
  poke('the one reading is handed to the browser',
    'grant execute on function public.fleet_cargo_basis(uuid, text) to authenticated;'),
  poke('a client role is granted a write on ships',
    'grant update on public.ships to authenticated;'),
  poke("a 0081 body moves under this file's feet",
    'alter function public.fleet_cargo_basis(uuid, text) set search_path = public;'),
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = null
  for (let i = 0; i < hunks.length; i += 2) {
    const n = mutated.split(hunks[i]).length - 1
    if (n !== 1) { missing = `${n} occurrence(s) of hunk ${i / 2 + 1}`; break }
    // A FUNCTION, not a string: String.replace reads `$$` in a replacement string as one `$`
    // (breaktest-0081 measured the consequence — a syntax error, red for the wrong reason).
    mutated = mutated.replace(hunks[i], () => hunks[i + 1])
  }
  if (missing) {
    console.log(`SKIPPED  ${name} — ${missing}, FIX THE SCRIPT`)
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
