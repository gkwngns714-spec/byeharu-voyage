// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0087.mjs — watch every guard in migration 0087 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0087 exactly once, then runs MUTATED copies of 0087
// inside begin/rollback and records the REAL red message each of its asserts produces. Each name
// says which assert actually fires first — read the message, not the label, when in doubt. A
// mutation that applies cleanly is reported as GREEN!! and fails the run — that is a guard that
// would never have caught anything.
//
//   node scripts/db/breaktest-0087.mjs               # every mutation
//   node scripts/db/breaktest-0087.mjs --clean       # apply 0087 unmutated, print its receipt
//   node scripts/db/breaktest-0087.mjs --only=<sub>  # one mutation, by a substring of its name
//
// WHAT 0087 CHANGES, so the mutations below are read for what they attack: a harbour posts a
// request for a good it does NOT sell, open until a calendar day, paying a premium per unit over
// the posting mid when the WHOLE lot lands. The draw is pure (contract_draw), the wind is one
// writer (tick_contracts: post, back-fill, expire, prune), the delivery is one body (run_fulfil:
// the guards, the sale through cmd.run_manifest, the premium through public.credit as its own
// ledger row, the row marked) under two skins. The task named four guards that must bite — a lot
// not all on board, an expired request, the premium equal to the served figure, a second delivery
// of the same request — and they are the first four below. EVERY mutation here is deterministic:
// a filter is INVERTED rather than dropped where dropping it would only red on a lucky draw.
//
// Shape copied from scripts/db/breaktest-0083.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000087_a_port_asks_for_what_it_does_not_sell.sql'
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
console.log(`chain applied up to (not including) 0087 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0087 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0087: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the world" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── THE FOUR THE SLICE NAMED ────────────────────────────────────────────────────────────────
  ['(e1) the short-cargo guard is dropped — a lot not all on board is delivered anyway',
    '  if v_have < c.qty then\n    perform cmd.refuse(\'E_CONTRACT_SHORT\',',
    '  if false then\n    perform cmd.refuse(\'E_CONTRACT_SHORT\','],
  ['(e4) the EXPIRED guard is dropped — a passed request is judged as open',
    "  if c.status = 'expired' then\n    perform cmd.refuse('E_CONTRACT_EXPIRED',",
    "  if false then\n    perform cmd.refuse('E_CONTRACT_EXPIRED',"],
  ['(e3) the premium paid is not the premium served — one ducat more',
    "  perform public.credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event);",
    "  perform public.credit(f.player_id, 'PREMIUM', c.premium_ducats + 1, v_event);"],
  ['(e4) the DONE guard is dropped — the same request is delivered twice',
    "  if c.status = 'fulfilled' then\n    perform cmd.refuse('E_CONTRACT_DONE',",
    "  if false then\n    perform cmd.refuse('E_CONTRACT_DONE',"],

  // ── THE MONEY ───────────────────────────────────────────────────────────────────────────────
  ['(e3) the premium is never paid — the delivery takes the cargo and pays the sale alone',
    "  perform public.credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event);",
    '  null;'],
  ['(e2) net leaves the premium out',
    "           'net', (v_rcpt->'totals'->>'net')::bigint + c.premium_ducats),",
    "           'net', (v_rcpt->'totals'->>'net')::bigint),"],
  ['(e2) purse.after is the sale\'s figure, not read back after the premium',
    "         'purse', jsonb_build_object('before', v_rcpt->'purse'->'before', 'after', v_purse));",
    "         'purse', jsonb_build_object('before', v_rcpt->'purse'->'before', 'after', (v_rcpt->'purse'->>'after')::bigint));"],
  ['(e3) the FULFILLED event carries the wrong premium',
    "               'premium', c.premium_ducats, 'premium_pct', c.premium_pct,",
    "               'premium', c.premium_ducats + 1, 'premium_pct', c.premium_pct,"],
  ['(e1) the short refusal carries no figures — the tray cannot draw the bar',
    "      cmd.figures(v_have, c.qty, 'units'));",
    '      null);'],

  // ── THE DRAW AND THE WIND ───────────────────────────────────────────────────────────────────
  ['(b) the draw names only goods the port OFFERS — an arbitrage on one quay (inverted, not dropped, so it reds on every draw)',
    '     where not public.port_offers(p_port, g.id)\n       and not public.culture_refuses(p.culture, g.culture_mask)',
    '     where public.port_offers(p_port, g.id)\n       and not public.culture_refuses(p.culture, g.culture_mask)'],
  ['(b) the quantity is one unit off the step',
    '  qty         := v_steps * v_step;',
    '  qty         := v_steps * v_step + 1;'],
  ['(b) the premium is drawn above the band',
    '  premium_pct := round(v_pmin + v_u * (v_pmax - v_pmin), 2);',
    '  premium_pct := round(v_pmax + v_u, 2);'],
  ['(b) premium_per_unit is not mid × pct',
    '      v_per_unit := round(v_mid * v_draw.premium_pct, 2);',
    '      v_per_unit := round(v_mid * v_draw.premium_pct, 2) + 1;'],
  ['(b) a request expires a day late',
    "         round(v_per_unit * v_draw.qty)::bigint, v_d + v_deadline,",
    "         round(v_per_unit * v_draw.qty)::bigint, v_d + v_deadline + 1,"],
  ['(b) the wind re-mints the board — rows deleted and drawn again on every read',
    '  for v_d in (v_day - v_deadline + 1) .. v_day loop',
    "  delete from public.trade_contracts where port_id = p_port and status = 'open';\n  for v_d in (v_day - v_deadline + 1) .. v_day loop"],
  ['(c) passed requests are never marked expired',
    "   where port_id = p_port and status = 'open' and expires_day <= v_day;",
    "   where port_id = p_port and status = 'open' and expires_day < v_day - 1000;"],
  ['(c) nothing is ever pruned',
    "   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;",
    '   where false;'],
  ['(a) the deadline knob is seeded at zero — no board can be posted',
    "  ('contract_deadline_days', to_jsonb(4),",
    "  ('contract_deadline_days', to_jsonb(0),"],

  // ── THE SKINS ───────────────────────────────────────────────────────────────────────────────
  ['(e2) the preview forgets to roll back — a dry run that delivers',
    "    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_fulfil(p_fleet, p_contract));\n    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';",
    "    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_fulfil(p_fleet, p_contract));\n    return v_out;"],
  ['(e4) the version guard loses its predicate — the same tap twice delivers twice',
    '     where id = p_fleet and (p_expected_version is null or version = p_expected_version);',
    '     where id = p_fleet;'],
  ['(e3) the row is never marked fulfilled',
    "     set status = 'fulfilled', fulfilled_by = f.player_id, fulfilled_fleet = p_fleet, fulfilled_at = now()\n   where id = c.id;",
    "     set status = 'fulfilled', fulfilled_by = f.player_id, fulfilled_fleet = p_fleet, fulfilled_at = now()\n   where false;"],

  // ── (f) THE CATALOGUE AND THE POSTURE ──────────────────────────────────────────────────────
  ['(f) the catalogue row for fulfil is forgotten',
    "      ('cmd',         'fulfil',              'uuid, uuid, int'),\n",
    ''],
  ['(f) a recut catalogue hunk gains a space — behaviour identical, parity broken',
    "      ('cmd',         'preview_fulfil',      'uuid, uuid')\n    ) as t(s, f, a)$c1$);",
    "      ('cmd',         'preview_fulfil',       'uuid, uuid')\n    ) as t(s, f, a)$c1$);"],
  poke('(f) the one body is handed to the browser',
    'grant execute on function cmd.run_fulfil(uuid, uuid) to authenticated;'),
  poke('(f) the writer is handed to anon',
    'grant execute on function public.tick_contracts(uuid, timestamptz) to anon;'),
  poke('(f) anon is handed the committing door',
    'grant execute on function cmd.fulfil(uuid, uuid, int) to anon;'),
  poke('(f) a client role may read the board directly',
    'grant select on public.trade_contracts to authenticated;'),
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
    // A FUNCTION, not a string: String.replace reads `$$` in a replacement string as one `$`.
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
