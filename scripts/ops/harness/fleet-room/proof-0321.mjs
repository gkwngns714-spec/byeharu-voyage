// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
// proof-0321.mjs — A SHIP CHANGES FLEETS (migration 0321): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/fleet-room/proof-0321.mjs [--first=a.sql,b.sql] [--no-mutations]
//
// Restores the cached world at the head before 0321 (never from zero), then applies 0321 to it several times inside a transaction that is rolled back:
//   POSITIVE CONTROL  - the real file alone, then the real file followed by proof 29;
//   DEPLOY ORDER      - with --first, those files are applied first, in that order (0318, 0319 and 0320 from their branches);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 29 run right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { IMAGE_CACHE_DIR, BROWSER_VARIANT, chainAndFingerprint } from '../../../db/build-image.mjs'

const NAME = '20260818000321_a_ship_changes_fleets.sql'
const PROOF = 'scripts/db/proofs/29_fleet_room.sql'
const failures = []
const say = (...a) => console.log(...a)

const files = []
const chain = await chainAndFingerprint()
for (const f of chain.files) if (f.name !== NAME) files.push(f)
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

// One attempt, rolled back. `withProof` runs proof 29 after the file. Answers the error, or null, and the notices.
async function attempt(sql, withProof) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    await db.exec(sql, { onNotice })
    if (withProof) await db.exec(proof, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['the file lights the room', (s) => swap(s, `('fleet_room_bite', 'false'::jsonb,`, `('fleet_room_bite', 'true'::jsonb,`), /0321 self-assert FAIL: the room is not dark/],
  ['the file moves fleet_ship_max', (s) => swap(s, `  -- ── 3. THE READERS ──`, `  update public.world_config set value = '7'::jsonb where key = 'fleet_ship_max';\n  -- ── 3. THE READERS ──`), /0321 self-assert FAIL: a world_config row moved/],
  ['the door is open to anon', (s) => swap(s, `  grant execute on function cmd.move_ship(uuid, uuid, text) to authenticated;`, `  grant execute on function cmd.move_ship(uuid, uuid, text) to authenticated, anon;`), /0321 self-assert FAIL: the grants/],
  ['the door is not registered', (s) => swap(s, `      ('cmd',         'move_ship',             'uuid, uuid, text'),\n`, ''), /0321 self-assert FAIL: the door or the read/],
  ['dark caps read the ladders', (s) => swap(s, `$h$  select case when public.fleet_room_on() then public.fleet_room_caps(p_player)   -- 0321: lit, the ladders; dark, what follows`, `$h$  select case when true then public.fleet_room_caps(p_player)   -- 0321: lit, the ladders; dark, what follows`), /PROOF 29 FAIL/],
  ['the door opens dark', (s) => swap(s, `  if not public.fleet_room_on() then\n    perform cmd.refuse('E_NOT_IN_USE', 'moving ships is not in use yet');\n  end if;\n`, ''), /PROOF 29 FAIL: dark, the core moved a ship/],
  ['the hard top is gone', (s) => swap(s, `'fleet_max', least(public.wc_int('fleet_hard_max'),\n                         public.wc_int('fleet_max')`, `'fleet_max', least(99,\n                         public.wc_int('fleet_max')`), /PROOF 29 FAIL: lit, the fleets pass fleet_hard_max/],
  ['Command does not count', (s) => swap(s, `greatest(public.skill_level(p_player, 'SEAMANSHIP'), public.skill_level(p_player, 'COMMAND'))`, `public.skill_level(p_player, 'SEAMANSHIP')`), /PROOF 29 FAIL: lit, the higher of two skills/],
  ['a merchant gets the hull cap of her room', (s) => swap(s, `$h$  select case when public.fleet_room_on() and not coalesce((select p.is_npc from public.players p where p.id = p_player), true)   -- 0321`, `$h$  select case when public.fleet_room_on()   -- 0321`), /PROOF 29 FAIL: lit, a merchant is not on the flat rules/],
  ['the version does not rise on the target', (s) => swap(s, `   where id in (a.id, b.id);`, `   where id = a.id;`), /PROOF 29 FAIL: a fleet version did not rise/],
  ['the empty mark hits the target too', (s) => swap(s, `case when id = a.id and v_left = 0 then`, `case when v_left = 0 then`), /PROOF 29 FAIL/],
  ['the heir ignores tier', (s) => swap(s, `order by c.tier desc, public.ship_hold_capacity(x.id) desc, x.name, x.id limit 1`, `order by public.ship_hold_capacity(x.id), x.name, x.id limit 1`), /PROOF 29 FAIL/],
  ['port time is not busy on the source', (s) => swap(s, `  if (a.ready_at is not null and a.ready_at > now())\n     or exists`, `  if exists`), /PROOF 29 FAIL: port time/],
  ['another port passes', (s) => swap(s, `    if b.port_id is distinct from a.port_id then\n      perform cmd.refuse('E_NOT_SAME_PORT', format('%s lies in another port', b.name));\n    end if;\n`, ''), /PROOF 29 FAIL/],
  ['an order on the target passes', (s) => swap(s, `    if (b.ready_at is not null and b.ready_at > now())\n       or exists (select 1 from public.orders o where o.fleet_id = b.id and o.status in ('pending', 'active')) then`, `    if (b.ready_at is not null and b.ready_at > now()) then`), /PROOF 29 FAIL: a pending order/],
  ['an empty fleet stays DOCKED', (s) => swap(s, `then 'UNABLE_TO_SAIL' else status end`, `then 'DOCKED' else status end`), /PROOF 29 FAIL: the empty fleet does not lie/],
  ['an empty fleet takes orders', (s) => swap(s, `  if not exists (select 1 from public.ships s where s.fleet_id = v_fleet) then\n`, `  if false then\n`), /PROOF 29 FAIL: an empty fleet took an order/],
  ['an empty fleet is towed', (s) => swap(s, `$h$  if not exists (select 1 from public.ships s where s.fleet_id = f.id) then   -- 0321`, `$h$  if false then   -- 0321`), /PROOF 29 FAIL: an empty fleet was towed/],
  ['an empty fleet keeps her old port', (s) => swap(s, `update public.fleets set status = 'DOCKED', port_id = a.port_id, lat = null, lon = null, ready_at = null where id = b.id;`, `update public.fleets set status = 'DOCKED', lat = null, lon = null, ready_at = null where id = b.id;`), /PROOF 29 FAIL: the empty fleet did not take/],
]

say('\nPOSITIVE CONTROL: the real file alone')
const alone = await attempt(file, false)
if (alone.err) failures.push(`the real file failed: ${alone.err}`)
say('  ', alone.err ?? alone.notes.find((n) => n.includes('0321 self-assert ok')))

say('POSITIVE CONTROL: the real file, then proof 29')
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice('--first='.length).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)
const whole = await attempt(before + '\n' + file, true)
if (whole.err) failures.push(`proof 29 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:'))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(mutate(file), true)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 220)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${MUTATIONS.length} mutations red, the real file and proof 29 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
