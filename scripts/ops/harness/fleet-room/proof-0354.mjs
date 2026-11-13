// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// proof-0354.mjs — ROOM IS BOUGHT, AND A FLEET READS ITS TOTALS (migration 0354): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/fleet-room/proof-0354.mjs [--first=a.sql,b.sql] [--no-mutations] [--cost] [--times=N]
//
// Restores the cached world at the head before 0354 (never from zero, the cache only read), then applies 0354 to it several times inside a transaction that is rolled back:
//   RED FIRST         - proof 57 without the file fails (it is not vacuous);
//   POSITIVE CONTROL  - the real file alone, --times times (default 3); then the real file followed by proof 57 and proof 29 (0321's, which shares the caps and the table);
//   DEPLOY ORDER      - with --first, those files are applied first, in that order (0351, 0352, 0353 from their branches);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert or proof 57 for the intended reason;
//   --cost            - cost-0354.sql after the file: world.fleets() with and without the hunks, on houses of 1x1, 2x2 and 5x7.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { IMAGE_CACHE_DIR, BROWSER_VARIANT, chainAndFingerprint } from '../../../db/build-image.mjs'

const NAME = '20260818000354_room_is_bought_and_a_fleet_reads_its_totals.sql'
const PROOF = 'scripts/db/proofs/57_fleet_room_bought.sql'
const PROOF_29 = 'scripts/db/proofs/29_fleet_room.sql'
const COST = 'scripts/ops/harness/fleet-room/cost-0354.sql'
const failures = []
const say = (...a) => console.log(...a)
const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)

const chain = await chainAndFingerprint()
const files = chain.files.filter((f) => f.name < NAME)
const read = async (f) => (await readFile(f, 'utf8')).replaceAll('\r', '')
const file = await read(path.join(MIGRATIONS_DIR, NAME))
const proof = await read(PROOF)
const proof29 = await read(PROOF_29)
const out = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)
const first = (arg('first') ?? '').split(',').filter(Boolean)
const before = (await Promise.all(first.map(read))).join('\n')
if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

// One attempt, rolled back. Answers the error, or null, and the notices.
async function attempt(...sqls) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    for (const s of sqls) await db.exec(s, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['the door opens dark', (s) => swap(s, `  if not public.fleet_room_on() then\n    perform cmd.refuse('E_NOT_IN_USE', 'fleet room is not in use yet');\n  end if;\n`, ''), /0354 self-assert FAIL: dark, the buying door is not shut/],
  ['the gold is booked as another kind', (s) => swap(s, `public.credit(p_player, 'SLOT', -v_price, v_event)`, `public.credit(p_player, 'TOW', -v_price, v_event)`), /0354 self-assert FAIL: lit, buying/],
  ['the gold is given, not taken', (s) => swap(s, `public.credit(p_player, 'SLOT', -v_price, v_event)`, `public.credit(p_player, 'SLOT', v_price, v_event)`), /0354 self-assert FAIL: lit, buying/],
  ['SLOT is registered as moved', (s) => swap(s, `values ('SLOT', 'removed', 'Fleet room', 56)`, `values ('SLOT', 'moved', 'Fleet room', 56)`), /0354 self-assert FAIL: another flow word moved, or SLOT is not a removed kind/],
  ['every step costs the first price', (s) => swap(s, `  v_price := (v_prices ->> v_bought)::bigint;`, `  v_price := (v_prices ->> 0)::bigint;`), /0354 self-assert FAIL: lit, buying  Ship  step 2/],
  ['a buy writes no row', (s) => swap(s, `  on conflict (player_id, kind) do update set steps = h.steps + 1, updated_at = now();`, `  on conflict (player_id, kind) do nothing;`), /0354 self-assert FAIL: lit, buying  Ship  step 2/],
  ['the top is not refused', (s) => swap(s, `  if v_now >= v_top then`, `  if false then`), /0354 self-assert FAIL: lit, (with every price|the top)/],
  // (not a mutation: taking out the door's own short-of-gold test changes nothing a caller can see, because public.credit refuses with the same code and figures and the door's sub-transaction takes the event back)
  ['a merchant may buy', (s) => swap(s, `  if v_npc then\n    perform cmd.refuse('E_NOT_IN_USE', 'a merchant keeps the flat rules and buys no room');\n  end if;\n`, ''), /0354 self-assert FAIL: a merchant bought room/],
  ['the buying door is open to anon', (s) => swap(s, `  grant execute on function cmd.buy_room(text) to authenticated;`, `  grant execute on function cmd.buy_room(text) to authenticated, anon;`), /0354 self-assert FAIL: the grants/],
  ['the core is open to a client', (s) => swap(s, `  revoke all on function public.buy_room_for(uuid, text) from public, anon, authenticated;`, `  revoke all on function public.buy_room_for(uuid, text) from public, anon;\n  grant execute on function public.buy_room_for(uuid, text) to authenticated;`), /0354 self-assert FAIL: the grants/],
  ['a door is not registered', (s) => swap(s, `      ('cmd',         'rename_fleet',          'uuid, text'),\n`, ''), /0354 self-assert FAIL: the read or a door is not in the client registry/],
  ['the file lights the room', (s) => swap(s, `  -- ── 2. F4: THE READS ──`, `  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';\n  -- ── 2. F4: THE READS ──`), /0354 self-assert FAIL: a world_config row moved/],
  ['the file moves a price', (s) => swap(s, `  -- ── 2. F4: THE READS ──`, `  update public.world_config set value = '[1]'::jsonb where key = 'fleet_room_prices';\n  -- ── 2. F4: THE READS ──`), /0354 self-assert FAIL: a world_config row moved/],
  ['the totals sum the class crew, not hers', (s) => swap(s, `    'crew', coalesce(sum((v ->> 'crew')::numeric), 0),`, `    'crew', coalesce(sum((v ->> 'crew_required')::numeric), 0),`), /0354 self-assert FAIL: a fleet's totals are not the sums/],
  ['the slowest ship is the fastest', (s) => swap(s, `order by (x ->> 'speed')::numeric, x ->> 'name' limit 1))`, `order by (x ->> 'speed')::numeric desc, x ->> 'name' desc limit 1))`), /PROOF 57 FAIL: the totals of|0354 self-assert FAIL: a fleet's totals/],
  ['wages are the short-rations figure', (s) => swap(s, `public.fleet_wage(p_fleet, false, coalesce(`, `public.fleet_wage(p_fleet, true, coalesce(`), /0354 self-assert FAIL: a fleet's totals are not the sums/],
  ['the ships are served in another order', (s) => swap(s, `                 order by s.is_flagship desc, s.name), '[]'::jsonb) as ships`, `                 order by s.name desc), '[]'::jsonb) as ships`), /0354 self-assert FAIL: dark, world.fleets\(\) without `totals` is not its pre-image|PROOF 57 FAIL: dark, world.fleets/],
  ['another key of the read moves', (s) => swap(s, `    'totals', public.fleet_totals(f.id, sv.ships),   -- 0354`, `    'totals', public.fleet_totals(f.id, sv.ships), 'wave', 0,   -- 0354`), /0354 self-assert FAIL: dark, world.fleets\(\) without `totals` is not its pre-image/],
  ['a rename takes any name', (s) => swap(s, `    when check_violation then\n      perform cmd.refuse('E_BAD_NAME', 'a fleet is named in 3 to 24 letters');\n`, `    when check_violation then\n      null;\n`), /0354 self-assert FAIL: renaming to/],
  ['a rename reaches another company', (s) => swap(s, `from public.fleets x where x.id = p_fleet and x.player_id = p_player for update;`, `from public.fleets x where x.id = p_fleet for update;`), /0354 self-assert FAIL: renaming to "Roubada 0354"/],
  ['the same name again writes an event', (s) => swap(s, `  if v_name = f.name then`, `  if false then`), /0354 self-assert FAIL: the same name again wrote something/],
  ['the read offers a price at the top', (s) => swap(s, `      'price', case when not v_sfull then (v_sprices ->> v_sb)::bigint end,`, `      'price', (v_sprices ->> 0)::bigint,`), /0354 self-assert FAIL: lit, at the top the read still offers a price/],
  ['the read is volatile', (s) => swap(s, `create function world.house_room()\nreturns jsonb\nlanguage plpgsql\nstable`, `create function world.house_room()\nreturns jsonb\nlanguage plpgsql\nvolatile`), /0354 self-assert FAIL: a read is not STABLE/],
]

say('\nRED FIRST: proof 57 without the file')
const red = await attempt(before, proof)
if (!red.err) failures.push('proof 57 passed without the file: it is vacuous')
say('  ', red.err ? `red as required: ${red.err.slice(0, 160)}` : 'WRONG: it passed')

const times = Number(arg('times') ?? 3)
say(`POSITIVE CONTROL: the real file alone, ${times} time(s)`)
for (let i = 0; i < times; i++) {
  const alone = await attempt(before, file)
  if (alone.err) failures.push(`the real file failed: ${alone.err}`)
  say('  ', alone.err ?? alone.notes.filter((n) => n.startsWith('0354')).join('\n   '))
}

say('POSITIVE CONTROL: the real file, then proof 57, then proof 29')
for (const p of [proof, proof29]) {   // each in its own rolled-back transaction, as scripts/db/proof.mjs runs them: a proof leaves the room lit behind it
  const whole = await attempt(before, file, p)
  if (whole.err) failures.push(`a proof failed: ${whole.err}`)
  for (const n of whole.notes.filter((x) => x.startsWith('PASS:'))) say('  ', n)
  if (whole.err) say('   ERROR', whole.err)
  const want = [...p.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
  const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
  if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)
}

if (process.argv.includes('--cost')) {
  say('\nCOST: world.fleets() with and without the hunks')
  const cost = await attempt(before, file, await read(COST))
  if (cost.err) failures.push(`the cost scene failed: ${cost.err}`)
  for (const n of cost.notes.filter((x) => x.startsWith('COST'))) say('  ', n)
}

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(before, mutate(file), proof)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: proof 57 red without the file, ${process.argv.includes('--no-mutations') ? 'mutations not run' : `${MUTATIONS.length} mutations red`}, the real file and proofs 57 and 29 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
