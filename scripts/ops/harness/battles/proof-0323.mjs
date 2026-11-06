// proof-0323.mjs: A BATTLE TAKES TEN MINUTES (migration 0323): the red-first proof. LOCAL ONLY (PGlite); not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/battles/proof-0323.mjs [--no-mutations] [--first=a.sql,b.sql]
// Restores the cached world at the head before 0323 (never from zero), then applies 0323 several times inside a transaction that is rolled back:
//   RED FIRST         - proof 31 on the world WITHOUT the file, which must fail;
//   POSITIVE CONTROL  - the real file alone, then the real file followed by proof 31;
//   DEPLOY ORDER      - with --first, those files first, in that order (0321, 0322, read from their branches);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 31 right after it, for the intended reason.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { IMAGE_CACHE_DIR, BROWSER_VARIANT, chainAndFingerprint } from '../../../db/build-image.mjs'

const NAME = '20260818000323_a_battle_takes_ten_minutes.sql'
const PROOF = 'scripts/db/proofs/31_battles.sql'
const failures = []
const say = (...a) => console.log(...a)

const chain = await chainAndFingerprint()
const files = chain.files.filter((f) => f.name < NAME.slice(0, 14))
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: path.join(IMAGE_CACHE_DIR, 'prefix'), log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

async function attempt(sql, withProof, pastParity = false) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  const t = Date.now()
  await db.exec('begin')
  let err = null
  try {
    if (sql) await db.exec(sql, { onNotice })
    if (withProof) await db.exec(pastParity ? proof.replace(/-- ── THE DARK PARITY[\s\S]*?(?=-- ── THE REFUSALS)/, '') : proof, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes, ms: Date.now() - t }
}

const MUTATIONS = [
  ['a hold throws her back as a storm does: nothing given back', (s) => swap(s, `- voyage.delay_before_day(p_voyage, v_day) + voyage.hold_unserved(p_voyage, v_day, p_at);$h$)`, `- voyage.delay_before_day(p_voyage, v_day);$h$)`), /PROOF 31 FAIL: (\d+ s into the battle she has moved|she went back)/, true],
  ['the hold gives back too much: she never sails on', (s) => swap(s, `                      * (1 - least(1, greatest(0, extract(epoch`, `                      * (1.01 - least(1, greatest(0, extract(epoch`), /PROOF 31 FAIL: /],
  ['the hold is counted one day late', (s) => swap(s, `jsonb_build_object('delay_hours', v_hours, 'from_day', v.last_settled_day + 1,`, `jsonb_build_object('delay_hours', v_hours, 'from_day', v.last_settled_day + 2,`), /PROOF 31 FAIL: /],
  ['the unserved term counts days it should not', (s) => swap(s, `ve.day_index >= voyage.hold_floor() and (ve.payload->>'from_day')::int <= p_day\n$body$`, `ve.day_index >= voyage.hold_floor()\n$body$`), /PROOF 31 FAIL: (the battle moved what she did before it|she went back)/],
  ['the delay forgets the hold', (s) => swap(s, `  ) + (\n  -- 0323: a hold's row stands above the days and counts from the day she was held on (voyage.hold)\n  select coalesce(sum((ve.payload->>'delay_hours')::numeric), 0)\n    from public.voyage_events ve\n   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor() and (ve.payload->>'from_day')::int <= p_day\n  );$h$),`, `  );$h$),`), /PROOF 31 FAIL: /],
  ['no eta: the hold is not written through recompute_eta', (s) => swap(s, `  perform voyage.recompute_eta(v.id);\n  update public.fleets set busy_until = p_until`, `  update public.fleets set busy_until = p_until`), /PROOF 31 FAIL: /],
  ['open does not settle first', (s) => swap(s, `    perform voyage.settle(v_fleet, p_now);\n  end loop;\n  select * into a from public.fleets where id = p_attacker for update;`, `    null;\n  end loop;\n  select * into a from public.fleets where id = p_attacker for update;`), /PROOF 31 FAIL: /],
  ['a sailing fleet goes IN_BATTLE', (s) => swap(s, `    if (select f.status from public.fleets f where f.id = v_fleet) = 'SAILING' then\n      perform voyage.hold(v_fleet, v_until, p_now);\n    else`, `    if false then\n      perform voyage.hold(v_fleet, v_until, p_now);\n    else`), /fleets_in_battle_lies_still|SAILING/],
  ['a human may be the target', (s) => swap(s, `  if not (select p.is_npc from public.players p where p.id = d.player_id) then\n    raise exception 'E_HUMAN_TARGET`, `  if false then\n    raise exception 'E_HUMAN_TARGET`), /PROOF 31 FAIL: wanted E_HUMAN_TARGET/],
  ['a docked target may be fought', (s) => swap(s, `  if d.status = 'DOCKED' then\n    raise exception 'E_TARGET_DOCKED`, `  if false then\n    raise exception 'E_TARGET_DOCKED`), /PROOF 31 FAIL: wanted E_TARGET_DOCKED/],
  ['open is not dark', (s) => swap(s, `  if not public.attack_on() then\n    raise exception 'E_NOT_YET`, `  if false then\n    raise exception 'E_NOT_YET`), /PROOF 31 FAIL: dark, battle_open answered/],
  ['a fleet can be in two battles', (s) => swap(s, `\n     or a.busy_until is not null or d.busy_until is not null then`, ` then`), /PROOF 31 FAIL: a fleet in a battle opened another/],
  ['a retry fights again: no status test', (s) => swap(s, `  if b.id is null or b.status <> 'FIGHTING' or b.resolves_at > p_now then`, `  if b.id is null or b.resolves_at > p_now then`), /PROOF 31 FAIL: a retry/],
  ['the job does not wait for the clock', (s) => swap(swap(s, `where b.status = 'FIGHTING' and b.resolves_at <= p_now`, `where b.status = 'FIGHTING'`), ` or b.resolves_at > p_now then`, ` then`), /PROOF 31 FAIL: a battle resolved before its time/],
  ['the seed is not the battle', (s) => swap(s, `else public.fight_sides(p_battle, 1, v_a, v_b) end;`, `else public.fight_sides(gen_random_uuid(), 1, v_a, v_b) end;`), /PROOF 31 FAIL: the battle's answer/],
  ['the sides are the wrong way round', (s) => swap(s, `if s.side = 'DEFENDER' then v_a := v_a || v_h; else v_b := v_b || v_h; end if;`, `if s.side = 'ATTACKER' then v_a := v_a || v_h; else v_b := v_b || v_h; end if;`), /PROOF 31 FAIL: the battle's answer/],
  ['the fleets are not freed', (s) => swap(s, `           busy_until = null, version = version + 1\n     where f.id = s.fleet_id;`, `           version = version + 1\n     where f.id = s.fleet_id;`), /PROOF 31 FAIL: a fleet was not freed/],
  ['the queue is not run after', (s) => swap(s, `    if s.status = 'IN_BATTLE' then\n      perform cmd.advance(s.fleet_id, p_now);\n    end if;\n`, ``), /PROOF 31 FAIL: her queue did not run/],
  ['a held fleet may turn', (s) => swap(s, `  if f.busy_until is not null then\n    return jsonb_build_object('ok', false, 'error_code', 'E_FLEET_BUSY',`, `  if false then\n    return jsonb_build_object('ok', false, 'error_code', 'E_FLEET_BUSY',`), /PROOF 31 FAIL: a held fleet was let turn|E_DIVERT_FAILED/],
  ['the report prints the row, not the day', (s) => swap(s, `coalesce((p_payload->>'from_day')::int, p_day))   -- 0323`, `coalesce(null::int, p_day))   -- 0323`), /PROOF 31 FAIL: her report does not name/, true],
  ['the round is told from the wrong deck', (s) => swap(s, `jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a')`, `x`), /PROOF 31 FAIL: the round is not told from the attacker/],
  ['the roster delta forgets a held ship', (s) => swap(s, `\n      -- 0323: a hold moved her eta: she is served again while she is held, or the kept row would place her on the old one\n      or f.busy_until >= p_since;$h$);`, `;$h$);`), /PROOF 31 FAIL: a roster delta/, true],
  ['the view forgets her hold', (s) => swap(s, `\n         || case when v_full ? 'holds' then jsonb_build_object('holds', v_full->'holds') else '{}'::jsonb end;   -- 0323$h$),`, `;$h$),`), /PROOF 31 FAIL: a voyage's views/, true],
  ['a voyage nobody holds gets a key', (s) => swap(s, `  select case when count(*) = 0 then '{}'::jsonb\n`, `  select case when count(*) = 0 then '{"holds": []}'::jsonb\n`), /PROOF 31 FAIL: a voyage nobody holds/],
  ['battles are lit by the file', (s) => swap(s, `('attack_enabled', 'false'::jsonb,`, `('attack_enabled', 'true'::jsonb,`), /0323 self-assert FAIL: new battles are not dark/],
  ['a door left open to clients', (s) => swap(s, `  revoke all on function public.battle_open(text, uuid, uuid, timestamptz) from public, anon, authenticated;\n`, `  grant execute on function public.battle_open(text, uuid, uuid, timestamptz) to anon;\n`), /open to clients/],
  ['a hunk does not reverse: another function moved', (s) => swap(s, `  -- ── 7. THE JOB: its own, not in the beat ──`, `  execute replace(pg_get_functiondef('public.armour_soak(numeric,numeric)'::regprocedure), 'declare', '-- moved\ndeclare');\n  -- ── 7. THE JOB: its own, not in the beat ──`), /another function moved/],
  ['a knob moved', (s) => swap(s, `  -- ── 7. THE JOB: its own, not in the beat ──`, `  update public.world_config set value = '0.16', updated_at = now() + interval '1 hour' where key = 'fight_raider_break';\n  -- ── 7. THE JOB: its own, not in the beat ──`), /a world_config row moved/],
]

const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

say('\nRED FIRST: proof 31 on the world without the file')
const red = await attempt('', true)
say('  ', red.err ? `red: ${red.err.slice(0, 160)}` : 'IT PASSED')
if (!red.err) failures.push('proof 31 passed with no file')

say('\nPOSITIVE CONTROL: the real file alone')
const alone = await attempt(file, false)
if (alone.err) failures.push(`the real file failed: ${alone.err}`)
say('  ', alone.err ?? alone.notes.find((n) => n.includes('0323 self-assert ok')), `${alone.ms} ms`)

say('POSITIVE CONTROL: the real file, then proof 31')
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice('--first='.length).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)
const whole = await attempt(before + '\n' + file, true)
if (whole.err) failures.push(`proof 31 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:'))) say('  ', n)
if (whole.err) say('   ERROR', whole.err.slice(0, 1600))
say('  ', `${whole.ms} ms`)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected, pastParity] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    const r = await attempt(mutate(file), true, pastParity)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${MUTATIONS.length} mutations red, the real file and proof 31 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
