// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0081.mjs — watch every guard in migration 0081 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0081 exactly once, then runs MUTATED copies of 0081
// inside begin/rollback and records the REAL red message each of its asserts produces. A mutation
// that applies cleanly is reported as GREEN!! and fails the run — that is a guard that would never
// have caught anything.
//
//   node scripts/db/breaktest-0081.mjs               # every mutation
//   node scripts/db/breaktest-0081.mjs --clean       # apply 0081 unmutated, print its receipt
//   node scripts/db/breaktest-0081.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Each mutation is the DEFECT the guard exists to stop, written as the one-line edit a tired
// author would make: a blend that averages the two prices instead of the two parcels, a reader
// that treats "not on record" as zero, a BUY that forgets to pass the price, a SELL that realises
// profit against nothing, a mover that equalises one hull, an unload that keeps the key, a shed
// that loses the cost, a wire that serves an empty map, a grant that opens a door.
//
// Shape copied from scripts/db/breaktest-0076.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000081_the_hold_knows_what_it_cost.sql'
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
console.log(`chain applied up to (not including) 0081 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0081 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0081: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the world" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── (b) THE BLEND ───────────────────────────────────────────────────────────────────────────
  ['(b) the blend averages the two PRICES instead of the two PARCELS',
    '           else (p_qty0 * p_basis0 + p_qty1 * p_basis1) / (p_qty0 + p_qty1)',
    '           else (p_basis0 + p_basis1) / 2'],
  ['(b) the blend forgets an unknown — a priced parcel joining an unpriced one is called known',
    '           when p_basis0 is null or p_basis1 is null then null',
    '           when p_basis1 is null then null when p_basis0 is null then p_basis1'],

  // ── (c) THE READER ──────────────────────────────────────────────────────────────────────────
  ['(c) the reader reads only the flagship — the second hull is not part of the hold',
    "     and coalesce((s.cargo->>p_good_code)::numeric, 0) > 0\n$$;\ncomment on function public.fleet_cargo_basis(uuid, text) is",
    "     and s.is_flagship\n$$;\ncomment on function public.fleet_cargo_basis(uuid, text) is"],
  ['(c)/(i) "not on record" is read as ZERO — the number the owner would be shown for cargo nobody priced',
    "                                    or jsonb_typeof(s.cargo_basis->p_good_code) <> 'number') > 0 then null",
    "                                    or jsonb_typeof(s.cargo_basis->p_good_code) <> 'number') > 0 then 0"],

  // ── (c) THE MOVER ───────────────────────────────────────────────────────────────────────────
  ['(c) BUY forgets to pass the price — the tuns come aboard at no cost',
    '  v_loaded := public.fleet_load(p_fleet, g.code, q.units, q.total::numeric / q.units);$h$);',
    '  v_loaded := public.fleet_load(p_fleet, g.code, q.units, null);$h$);'],
  ['(c) the mover equalises ONE hull — the second hull keeps no figure and the fleet reads nothing',
    "       and coalesce((cargo->>p_good_code)::numeric, 0) > 0;\n  end if;\n  return v_loaded;\nend$h$);",
    "       and is_flagship;\n  end if;\n  return v_loaded;\nend$h$);"],
  ['(j) the 3-argument fleet_load is left standing beside the 4-argument one',
    "select pg_temp.recut('public.fleet_load(uuid,text,numeric)'::regprocedure, true,",
    "select pg_temp.recut('public.fleet_load(uuid,text,numeric)'::regprocedure, false,"],

  // ── (e)/(f) THE SALE ────────────────────────────────────────────────────────────────────────
  ['(e)/(f) the profit is realised against NOTHING — a sale reports 0 profit whatever it cost',
    '  v_profit := q.total - v_cost;\n  perform public.fleet_unload(p_fleet, g.code, q.units);$h$,',
    '  v_profit := 0;\n  perform public.fleet_unload(p_fleet, g.code, q.units);$h$,'],
  ['(e)/(f) the cost is off by a ducat — round(basis x tuns) + 1',
    '  v_cost   := round(v_basis * q.units)::bigint;\n  v_profit := q.total - v_cost;',
    '  v_cost   := round(v_basis * q.units)::bigint + 1;\n  v_profit := q.total - v_cost;'],
  ['(f) the basis is read AFTER the tuns leave — a sale of everything realises against nothing',
    "  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);\n  v_cost   := round(v_basis * q.units)::bigint;\n  v_profit := q.total - v_cost;\n  perform public.fleet_unload(p_fleet, g.code, q.units);$h$,",
    "  perform public.fleet_unload(p_fleet, g.code, q.units);\n  v_basis  := public.fleet_cargo_basis(p_fleet, g.code);\n  v_cost   := round(v_basis * q.units)::bigint;\n  v_profit := q.total - v_cost;$h$,"],

  // ── (h) THE KEY LEAVES WITH THE LAST TUN ────────────────────────────────────────────────────
  ['(h) unload keeps the key after the last tun — a stale figure waits for the next parcel',
    '             cargo_basis = case when r.have - v_take <= 0 then cargo_basis - p_good_code\n                                else cargo_basis end',
    '             cargo_basis = case when r.have - v_take <= 0 then cargo_basis\n                                else cargo_basis end'],

  // ── (g) THE SHED ────────────────────────────────────────────────────────────────────────────
  ['(g) STORE puts the goods ashore without their cost',
    '  values (f.player_id, f.port_id, g.id, v_qty, v_basis)',
    '  values (f.player_id, f.port_id, g.id, v_qty, null)'],
  ['(g) TAKE brings the goods back at no price',
    '  v_took := public.fleet_load(p_fleet, g.code, v_qty, v_basis);$h$);',
    '  v_took := public.fleet_load(p_fleet, g.code, v_qty, null);$h$);'],

  // ── (d) THE WIRE ────────────────────────────────────────────────────────────────────────────
  ['(d) world.fleets() serves an empty map to every fleet',
    "    'cargo_basis', public.fleet_cargo_basis_map(f.id),$h$);",
    "    'cargo_basis', '{}'::jsonb,$h$);"],

  // ── (l) POSTURE, both halves ────────────────────────────────────────────────────────────────
  poke('(l) the one reading is handed to the browser',
    'grant execute on function public.fleet_cargo_basis(uuid, text) to authenticated;'),
  poke('(l) a client role is granted a write on ships',
    'grant update on public.ships to authenticated;'),
  poke('(l) world.fleets() loses its door on the way through',
    'revoke execute on function world.fleets() from authenticated;'),
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
    // A FUNCTION, not a string: String.replace reads `$$` in a replacement string as one `$`,
    // and a hunk that ends a `language sql` body carries exactly that. Measured: the (c) reader
    // mutation came back as a SYNTAX ERROR — red for the wrong reason — until this line changed.
    mutated = mutated.replace(hunks[i], () => hunks[i + 1])
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
