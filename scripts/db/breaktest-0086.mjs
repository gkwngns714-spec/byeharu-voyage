// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0086.mjs — watch every guard in migration 0086 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0086 exactly once, then runs MUTATED copies of 0086
// inside begin/rollback and records the REAL red message each of its asserts produces. Each name
// says which assert actually fires first — read the message, not the label, when in doubt. A
// mutation that applies cleanly is reported as GREEN!! and fails the run — that is a guard that
// would never have caught anything.
//
//   node scripts/db/breaktest-0086.mjs               # every mutation
//   node scripts/db/breaktest-0086.mjs --clean       # apply 0086 unmutated, print its receipt
//   node scripts/db/breaktest-0086.mjs --only=<sub>  # one mutation, by a substring of its name
//
// WHAT 0086 CHANGES, so the mutations below are read for what they attack: the wage becomes ONE
// sum (public.crew_wages) that voyage.settle charges and world.crew_cost quotes; DISMISS is a
// verb — in port only, never below a hull's complement, back onto the port's crew_pool, no
// refund, one DISMISSED event; the grammar, the dispatcher and the dry run gain the word; the
// entry point is registered. Each mutation is the DEFECT a guard exists to stop, written as the
// one-line edit a tired author would make: the complement guard dropped or loosened; the at-sea
// gate dropped; a refund slipped in; the pool not returned; the event forgotten; the tick left
// spelling its own arithmetic beside the one sum; the sum rounding differently from the tick;
// a door left open; the entry point forgotten; the dispatcher or the dry run missing the arm.
//
// Shape copied from scripts/db/breaktest-0085.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000086_crew_are_let_go_in_port_and_the_wage_is_one_sum.sql'
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
console.log(`chain applied up to (not including) 0086 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0086 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0086: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the world" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── (g) THE COMPLEMENT GUARD — the reason the verb is safe to give a player ─────────────────
  ['(g) the complement guard is dropped — a fleet can be dismissed below what it needs to sail',
    `  if v_count > v_spare then
    perform cmd.refuse('E_CREW_REQUIRED', 'the ships need the rest of the crew to sail',
      cmd.figures(v_spare, v_count, 'crew'));
  end if;`,
    `  -- (guard dropped)`],
  ['(g) the guard is loosened by one — exactly the complement can be breached',
    `  if v_count > v_spare then`,
    `  if v_count > v_spare + 1 then`],
  ['(g) the surplus is folded per FLEET, not per hull — an over-crewed hull lends to an under-crewed one',
    `  select coalesce(sum(greatest(0, s.crew - c.crew_required)), 0)::int into v_spare`,
    `  select greatest(0, coalesce(sum(s.crew - c.crew_required), 0))::int into v_spare`],
  ['(g) the figures are the wrong way round — the bar would be legible and wrong',
    `      cmd.figures(v_spare, v_count, 'crew'));`,
    `      cmd.figures(v_count - v_spare, v_count, 'crew'));`],

  // ── (h) IN PORT ONLY ────────────────────────────────────────────────────────────────────────
  ['(h) the at-sea gate is dropped — crew can be let go mid-ocean',
    `  if f.status <> 'DOCKED' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and crew are let go in port only', f.name, f.status));
  end if;`,
    `  -- (gate dropped)`],

  // ── (f) NO REFUND, THE POOL, THE RECORD ─────────────────────────────────────────────────────
  ['(f) a refund slips in — the dismissal pays the hire fee back',
    `  perform public.emit_event(f.player_id, 'DISMISSED', jsonb_build_object(
    'fleet', f.name, 'count', v_count, 'crew', v_after));`,
    `  perform public.credit(f.player_id, 'DISMISS', (v_count * public.wc_num('hire_crew_rate'))::bigint,
    public.emit_event(f.player_id, 'DISMISSED', jsonb_build_object(
    'fleet', f.name, 'count', v_count, 'crew', v_after)));`],
  ['(f) the men do not go back on the quay — the pool is not returned',
    `  update public.ports set crew_pool = crew_pool + v_count where id = f.port_id;`,
    `  -- (pool not returned)`],
  ['(f) the event is forgotten — a dismissal leaves no record',
    `  perform public.emit_event(f.player_id, 'DISMISSED', jsonb_build_object(
    'fleet', f.name, 'count', v_count, 'crew', v_after));`,
    `  -- (no record)`],
  ['(f) the crew are not actually taken off the hulls — the event says one thing and the ship another',
    `    update public.ships set crew = crew - least(v_left, r.spare) where id = r.id;`,
    `    update public.ships set crew = crew where id = r.id;`],

  // ── (b)/(a) THE ONE SUM, AND THE TICK READING IT ────────────────────────────────────────────
  // String.replace swaps the FIRST occurrence, which is the recut's own hunk; the self-assert's
  // copy of the same text (its reverse substitution) is left standing, so the two disagree.
  ['(a)/(b) the tick keeps spelling its own arithmetic — the slice of voyage.settle is a no-op',
    `    select public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$);`,
    `    select coalesce(sum(sh.crew), 0) * public.wc_num('wage_per_crew_day')
           * (case when v_short then public.wc_num('short_rations_wage_mult') else 1 end)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$);`],
  ['(b) crew_wages forgets the short-rations multiplier — the quote and the tick disagree on a bad crossing',
    `               * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end))::bigint;`,
    `               * 1)::bigint;`],
  ['(b) crew_wages truncates where the tick rounded — off by one ducat on a half',
    `  return round(p_crew * public.wc_num('wage_per_crew_day')`,
    `  return trunc(p_crew * public.wc_num('wage_per_crew_day') - 0.5`],
  ['(b) crew_wages accepts a negative crew — the guard that stops the class is gone',
    `  if p_crew is null or p_crew < 0 then`,
    `  if p_crew is null then`],
  ['(d) world.crew_cost prices the crew aboard instead of the count asked — the caption would not move',
    `  v_crew := coalesce(p_crew, v_now);`,
    `  v_crew := v_now;`],
  ['(d) world.crew_cost serves the short-rations figure as the full one — the caption reads x1.5 every day',
    `    'per_day', public.crew_wages(v_crew, false),`,
    `    'per_day', public.crew_wages(v_crew, true),`],
  ['(h) the tick is handed a different sum than the quote — settle charges double',
    `    select public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$);`,
    `    select 2 * public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$);`],

  // ── (c) THE GRAMMAR, THE DISPATCHER, THE DRY RUN ────────────────────────────────────────────
  ['(c) the schema forgets the word — DISMISS is parsed but never offered',
    `
    {"verb":"DISMISS","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Let crew go, here in port.",
     "note":"Never below the crew the ships need to sail. Nothing is refunded; their wages stop."},$v1$);`,
    `$v1$);`],
  ['(f) the dispatcher has no arm — a DISMISS order is accepted and runs as nothing',
    `               when 'DISMISS'   then cmd.do_dismiss(o.fleet_id, o.args)$e1$);`,
    `$e1$);`],
  ['(f-i) the dry run has no arm — a previewed DISMISS estimates nothing',
    `               when 'DISMISS'   then cmd.do_dismiss((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);`,
    `$p1$);`],
  ['(c) the parser is not taught the word — "DISMISS 1" is E_PARSE',
    `  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','DISMISS','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g1$,`,
    `  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g1$,`],

  // ── (i) POSTURE, both halves ────────────────────────────────────────────────────────────────
  poke('(i) the verb is handed to the browser', 'grant execute on function cmd.do_dismiss(uuid, jsonb) to authenticated;'),
  poke('(i) the sum is handed to anon', 'grant execute on function public.crew_wages(int, boolean) to anon;'),
  poke('(i) the read is closed to the player who needs it', 'revoke execute on function world.crew_cost(uuid, int) from authenticated;'),
  poke('(i) the read is opened to anon', 'grant execute on function world.crew_cost(uuid, int) to anon;'),
  ['(i) the entry point is forgotten — the catalogue and the server disagree on the doors',
    `
      -- 0086: what a crew of N costs per day at sea — the Inn's caption, for any count.
      ('world',       'crew_cost',           'uuid, int'),$c1$);`,
    `$c1$);`],
  poke('(i) a client role is granted a write on ships', 'grant update on public.ships to authenticated;'),
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
    mutated = mutated.replace(hunks[i], hunks[i + 1])
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
