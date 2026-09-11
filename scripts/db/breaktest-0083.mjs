// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0083.mjs — watch every guard in migration 0083 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0083 exactly once, then runs MUTATED copies of 0083
// inside begin/rollback and records the REAL red message each of its asserts produces. Each name
// says which assert actually fires first — read the message, not the label, when in doubt. A mutation
// that applies cleanly is reported as GREEN!! and fails the run — that is a guard that would never
// have caught anything.
//
//   node scripts/db/breaktest-0083.mjs               # every mutation
//   node scripts/db/breaktest-0083.mjs --clean       # apply 0083 unmutated, print its receipt
//   node scripts/db/breaktest-0083.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Each mutation is the DEFECT the guard exists to stop, written as the one-line edit a tired
// author would make: a per-line handler that swallows a refusal and carries on (the manifest is
// no longer one order), the duplicate-good refusal dropped, the net summed the wrong way, a
// preview that forgets to roll back, a quote that moves the money while explaining it, a
// haggle_saved that is always zero, a line index off by one, a re-raise that loses the figures,
// buys run before sells, the 3-argument spread left standing, XP invented, a door left open, a
// catalogue row forgotten.
//
// Shape copied from scripts/db/breaktest-0081.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000083_a_manifest_is_one_order.sql'
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
console.log(`chain applied up to (not including) 0083 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0083 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0083: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the world" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── (h) ATOMICITY — the reason the file exists ──────────────────────────────────────────────
  ['(h) a per-line handler swallows the refusal and carries on — the manifest is no longer one order',
    "        v_r := cmd.do_buy(p_fleet, jsonb_build_object('good', v_good.id::text, 'qty', v_qty));\n        v_bought := v_bought + (v_r->>'total')::bigint;",
    "        begin\n          v_r := cmd.do_buy(p_fleet, jsonb_build_object('good', v_good.id::text, 'qty', v_qty));\n        exception when others then\n          continue;\n        end;\n        v_bought := v_bought + (v_r->>'total')::bigint;"],
  ['(f) the version is never bumped — a landed manifest leaves the fleet where it was and E_STALE can never fire',
    "    update public.fleets set version = version + 1\n     where id = p_fleet and (p_expected_version is null or version = p_expected_version);\n    if not found then",
    "    if not found then"],
  ['(h) the guarded bump is hoisted OUTSIDE the savepoint — a refused manifest still moves the fleet',
    "  begin\n    -- THE VERSION GUARD, checked and bumped under ONE row lock: a second call carrying the same\n    -- expected version waits on this row and then finds the predicate false (DESIGN F.3, \"two\n    -- devices cannot double-issue\" — here, two taps cannot double-trade).\n    update public.fleets set version = version + 1\n     where id = p_fleet and (p_expected_version is null or version = p_expected_version);\n",
    "  update public.fleets set version = version + 1\n   where id = p_fleet and (p_expected_version is null or version = p_expected_version);\n  begin\n"],
  ['(h)/(j) the line index is off by one',
    "    raise exception using message = v_msg, errcode = v_state, detail = coalesce(v_det, ''), hint = v_i::text;",
    "    raise exception using message = v_msg, errcode = v_state, detail = coalesce(v_det, ''), hint = (v_i + 1)::text;"],
  ['(h) the re-raise loses the DETAIL — the refusal reaches the client without its figures',
    "    raise exception using message = v_msg, errcode = v_state, detail = coalesce(v_det, ''), hint = v_i::text;",
    "    raise exception using message = v_msg, errcode = v_state, hint = v_i::text;"],

  // ── (j) ONE LINE PER GOOD ───────────────────────────────────────────────────────────────────
  ['(j) the duplicate-good refusal is dropped',
    "      if v_good.code = any(v_seen) then\n        perform cmd.refuse('E_MANIFEST_DUPLICATE', format('%s appears twice; one line per good', v_good.name));\n      end if;",
    "      if false then\n        perform cmd.refuse('E_MANIFEST_DUPLICATE', format('%s appears twice; one line per good', v_good.name));\n      end if;"],
  ['(j) an empty manifest is a receipt of nothing instead of a refusal',
    "      perform cmd.refuse('E_MANIFEST_EMPTY', 'the manifest has no lines');",
    "      null;"],

  // ── (f) THE RECEIPT IS THE LEDGER ───────────────────────────────────────────────────────────
  ['(f) net is summed the wrong way round',
    "'bought', v_bought, 'sold', v_sold, 'net', v_sold - v_bought),",
    "'bought', v_bought, 'sold', v_sold, 'net', v_sold + v_bought),"],
  ['(f) buys run before sells — the sale no longer funds the purchase',
    "                order by (lower(btrim(e.value->>'side')) = 'buy'), e.ordinality loop\n      v_i    := v_l.idx;",
    "                order by (lower(btrim(e.value->>'side')) = 'sell'), e.ordinality loop\n      v_i    := v_l.idx;"],
  ['(f) purse.after is computed instead of read, with the sign wrong',
    "    'purse', jsonb_build_object('before', v_purse0, 'after', v_purse1),",
    "    'purse', jsonb_build_object('before', v_purse0, 'after', v_purse0 + v_bought - v_sold),"],

  // ── (d) THE PREVIEW ─────────────────────────────────────────────────────────────────────────
  ['(d) the preview forgets to roll back — a dry run that moves the money',
    "    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_manifest(p_fleet, p_lines));\n    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';",
    "    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_manifest(p_fleet, p_lines));\n    return v_out;"],

  // ── (b) THE NO-OP ───────────────────────────────────────────────────────────────────────────
  ['(b) the quote moves the money while explaining it — a ducat per step',
    "      v_total := v_total + v_unit * v_n;\n      -- 0083: the same unit price in its parts",
    "      v_total := v_total + v_unit * v_n + 1;\n      -- 0083: the same unit price in its parts"],
  ['(a) the 3-argument spread_effective is left standing beside the 4-argument one',
    "select pg_temp.recut('world.spread_effective(uuid,uuid,uuid)'::regprocedure, true,",
    "select pg_temp.recut('world.spread_effective(uuid,uuid,uuid)'::regprocedure, false,"],

  // ── (i) THE BREAKDOWN ───────────────────────────────────────────────────────────────────────
  ['(i) haggle_saved is always zero — the bargain never reaches the receipt',
    "      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;",
    "      v_hag_t := v_hag_t + 0;"],
  ['(i) tax_total is the spread and spread_total is the tax — the chit lies about who took what',
    "      v_tax_t := v_tax_t + v_mid * v_tax * v_n;\n      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;\n      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;",
    "      v_tax_t := v_tax_t + v_mid * v_tax * v_n * 2;\n      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n * 0;\n      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;"],

  // ── (g) XP ──────────────────────────────────────────────────────────────────────────────────
  ['(g) trading.delta is invented rather than read from player_progress',
    "      'delta',         (v_prog1->'trading'->>'points')::int - (v_prog0->'trading'->>'points')::int,",
    "      'delta',         0,"],

  // ── (h)/(f) THE DOUBLE-TAP AND THE LOCKS ────────────────────────────────────────────────────
  ['(f) the version guard loses its predicate — the same tap twice trades twice',
    "     where id = p_fleet and (p_expected_version is null or version = p_expected_version);",
    "     where id = p_fleet;"],
  ['(j2) the up-front lock on the quay rows is removed (ordering is asserted structurally, not by a race)',
    "    perform 1 from public.port_goods pg\n      where pg.port_id = f.port_id and pg.good_id = any(v_ids)\n      order by pg.good_id\n      for update;",
    "    perform 1;"],
  ['(j2) a lock collision is not mapped to E_BUSY',
    "  if p_sqlstate in ('40P01', '55P03') then",
    "  if false then"],
  ['(j) half a tun is accepted — fractional lines sell for a rounding gain or burn cargo for nothing',
    "         or v_qty <= 0 or v_qty <> floor(v_qty) then",
    "         or v_qty <= 0 then"],

  // ── (k) PARITY ──────────────────────────────────────────────────────────────────────────────
  // Whitespace only, inside a recut RESULT hunk: the body still runs and answers the same figures,
  // so every behavioural assert stays green and ONLY the byte-for-byte parity of (k) can see it.
  ['(k) a recut result hunk gains two spaces — behaviour identical, parity broken',
    "                            'spread_total', q.spread_total, 'haggle_saved', q.haggle_saved);$h$);\n\nselect pg_temp.recut('cmd.do_sell(uuid,jsonb)'",
    "                            'spread_total', q.spread_total,  'haggle_saved', q.haggle_saved);$h$);\n\nselect pg_temp.recut('cmd.do_sell(uuid,jsonb)'"],
  ['(f) do_sell is cut with a hunk the parity template does not declare — the event loses its profit, and (f) reds first, before (k) would',
    "      'basis', v_basis, 'cost', v_cost, 'profit', v_profit,\n      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,\n      'haggle_saved', q.haggle_saved)));$h$,",
    "      'basis', v_basis, 'cost', v_cost,\n      'mid_total', q.mid_total, 'tax_total', q.tax_total, 'spread_total', q.spread_total,\n      'haggle_saved', q.haggle_saved)));$h$,"],

  // ── (l) POSTURE, both halves ────────────────────────────────────────────────────────────────
  poke('(l) the one body is handed to the browser',
    'grant execute on function cmd.run_manifest(uuid, jsonb) to authenticated;'),
  poke('(l) anon is handed the committing door',
    'grant execute on function cmd.trade_basket(uuid, jsonb, int) to anon;'),
  poke('(l) world.quote is handed back to the client (0018 §4 undone)',
    'grant execute on function world.quote(uuid, uuid, numeric, text, numeric, uuid) to authenticated;'),
  ['(k) the catalogue row for trade_basket is forgotten — the catalogue parity in (k) reds first; the client_executable_writers check in (l) would list it next',
    "      ('cmd',         'trade_basket',        'uuid, jsonb, int'),\n",
    ''],
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
    // A FUNCTION, not a string: String.replace reads `$$` in a replacement string as one `$`
    // (breaktest-0081 measured the syntax error that produced).
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
