// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0093.mjs — watch every guard in migration 0093 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0093 exactly once, then runs MUTATED copies of 0093
// inside begin/rollback and records the REAL red message each assert produces. A mutation that
// applies cleanly is reported as GREEN!! and fails the run.
//
//   node scripts/db/breaktest-0093.mjs               # every mutation
//   node scripts/db/breaktest-0093.mjs --clean       # apply 0093 unmutated, print its receipt
//   node scripts/db/breaktest-0093.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Each mutation puts back ONE defect the review of 0092 found (docs/TRADE_ROUTES.md §13.1), as the
// one-line edit that would re-introduce it. Mutating a NEW hunk's text leaves the parity proof green
// (the hunk table is the one source both the cut and the proof read), so what fires is the
// behaviour assert that exists for that defect. Shape copied from scripts/db/breaktest-0086.mjs.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000093_a_route_is_known_by_its_id_and_waits_behind_its_fleet.sql'
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
console.log(`chain applied up to (not including) 0093 in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`)

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
    console.log(`UNMUTATED 0093 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0093: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

const MUTATIONS = [
  ['MUST 1  the name index is kept — the same generated name is refused again',
    `drop index public.standing_routes_player_name_unique;`, `-- (index kept)`],
  ['SHOULD 2  pause locks the route before the fleet',
    `  perform 1 from public.fleets where id = v_held for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;
  if coalesce(p_paused, true) then`,
    `  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  perform 1 from public.fleets where id = v_held for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;
  if coalesce(p_paused, true) then`],
  ['SHOULD 3  the off-route sentence prints port codes again',
    `$h$        format('%s is not at %s or %s.', f.name, cur.port_name, prv.port_name));$h$),`,
    `$h$        format('%s is not at %s or %s.', f.name, cur.code, prv.code));   -- mutated$h$),`],
  ['SHOULD 3  the reserve sentence prints its bare figure again',
    `$h$        'The company has less than it keeps back.');$h$),`,
    `$h$        format('The company has less than %s kept back.', sr.reserve));   -- mutated$h$),`],
  ['SHOULD 4  a fleet that cannot move reads "in port" again',
    `then 'blocked'   -- 0093: cannot move on by itself`, `then 'in_port'   -- mutated`],
  ['SHOULD 5  the arrival order stands aside even with the player\'s own order queued',
    `     and not exists (select 1 from public.orders o
                      where o.fleet_id = p_fleet and o.status in ('pending', 'failed')) then`,
    `     and true then`],
  ['NIT 7  the skip rule works with the switch off',
    `or o.verb = 'SAIL' or not public.standing_routes_on();   -- 0093: dark = the ordinary halt$h$`,
    `or o.verb = 'SAIL';   -- 0093 mutated$h$`],
  ['NIT 10  taking a route off its fleet leaves the lap open',
    `  if sr.lap_id is not null then
    perform cmd.standing_route_close_lap(sr.id, now());
  end if;`, `  -- (lap left open)`],
  ['(re-cut)  a refused assign releases the old fleet\'s route orders before its checks',
    `  -- EVERY CHECK FIRST.`,
    `  update public.orders set route_lap_id = null
   where fleet_id = sr.fleet_id and status = 'pending' and route_lap_id is not null;
  -- EVERY CHECK FIRST.`],
  ['(parity)  a hunk is changed in the body but not in the table',
    `select pg_temp.recut_0093(fn) from (select distinct fn from hunks_0093) x order by fn;`,
    `select pg_temp.recut_0093(fn) from (select distinct fn from hunks_0093) x order by fn;
do $m$ begin execute replace(pg_get_functiondef('cmd.advance(uuid, timestamptz)'::regprocedure), 'guard > 64', 'guard > 65'); end $m$;`],
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
