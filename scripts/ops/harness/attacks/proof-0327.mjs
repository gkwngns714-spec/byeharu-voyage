// proof-0327.mjs: A PLAYER ATTACKS (migration 0327): the red-first proof. LOCAL ONLY (PGlite); not in CI.
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/proof-0327.mjs [--no-mutations] [--first=a.sql,b.sql] [--only=text]
// Restores the cached world at the head before 0327 (never from zero), then applies 0327 inside transactions that are rolled back:
//   RED FIRST         - proof 34 on the world WITHOUT the file, which must fail;
//   POSITIVE CONTROL  - the real file alone, then the real file followed by proof 34;
//   DEPLOY ORDER      - with --first, those files first, in that order (0324, read from its branch);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 34 right after it, for the intended reason.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'
import { IMAGE_CACHE_DIR, BROWSER_VARIANT, chainAndFingerprint } from '../../../db/build-image.mjs'

const NAME = '20260818000327_a_player_attacks.sql'
const PROOF = 'scripts/db/proofs/34_a_player_attacks.sql'
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
  return sql.replace(from, () => to)
}

async function attempt(sql, withProof) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  const t = Date.now()
  await db.exec('begin')
  let err = null
  try {
    if (sql) await db.exec(sql, { onNotice })
    if (withProof) await db.exec(proof, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes, ms: Date.now() - t }
}

const MUTATIONS = [
  // the switch
  ['the door forgets the switch', (s) => swap(s, `  if not public.attack_on() then\n    perform cmd.refuse('E_NOT_IN_USE', 'attacks are not in use');\n  end if;\n`, ``), /PROOF 34 FAIL: dark/],
  ['the file lights the switch', (s) => swap(s, `  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`, `  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`), /0327 self-assert FAIL: a world_config row moved/],
  ['dark, the card shows the key', (s) => swap(s, `    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0327: the key is served`, `    || case when true then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0327: the key is served`), /PROOF 34 FAIL: dark, the card/],
  // every refusal
  ['a player may be attacked', (s) => swap(s, `  if v_kind = 'COMPANY' then\n    perform cmd.refuse('E_HUMAN_TARGET', 'no player attacks another player');\n  end if;\n`, ``), /PROOF 34 FAIL: (a player|herself): wanted E_HUMAN_TARGET/],
  ['a merchant may be attacked', (s) => swap(s, `  if v_kind <> 'CARGO_SHIP' then\n    perform cmd.refuse('E_NOT_A_TARGET', 'merchants are not attacked');\n  end if;\n`, ``), /PROOF 34 FAIL: a merchant: wanted E_NOT_A_TARGET/],
  ['her own country may be attacked', (s) => swap(s, `  if c.nation_id is not distinct from (select pl.nation_id from public.players pl where pl.id = p_player) then`, `  if false then`), /PROOF 34 FAIL: her own country: wanted E_YOUR_OWN_COUNTRY/],
  ['a ship in port may be attacked', (s) => swap(s, `  if d.status not in ('SAILING', 'ANCHORED') then`, `  if false then`), /PROOF 34 FAIL: a ship in port: wanted E_TARGET_DOCKED/],
  ['another company\'s fleet may be sent', (s) => swap(s, `  if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = p_player) then\n    perform cmd.refuse('E_NO_SUCH_FLEET'`, `  if false then\n    perform cmd.refuse('E_NO_SUCH_FLEET'`), /PROOF 34 FAIL: the wrong owner: wanted E_NO_SUCH_FLEET/],
  ['a fleet with no guns may attack', (s) => swap(s, `  if v_guns <= 0 then`, `  if false then`), /PROOF 34 FAIL: no guns: wanted E_NO_GUNS/],
  ['a full hold may attack', (s) => swap(s, `  if exists (select 1 from public.ships s where s.fleet_id = p_fleet and public.ship_cargo_tuns(s.id) > 0) then`, `  if false then`), /PROOF 34 FAIL: a hold not empty: wanted E_HOLD_NOT_EMPTY/],
  ['no reach', (s) => swap(s, `  if v_nm > v_reach then`, `  if false then`), /PROOF 34 FAIL: out of reach: wanted E_OUT_OF_REACH/],
  ['the reach is short', (s) => swap(s, `  if v_nm > v_reach then`, `  if v_nm > v_reach - 2 then`), /PROOF 34 FAIL: 239 miles off was refused/],
  ['a stale press runs', (s) => swap(s, `  if p_version is not null and p_version <> a.version then`, `  if false then`), /PROOF 34 FAIL: a stale version/],
  ['a busy attacker may attack', (s) => swap(s, `  if a.status not in ('DOCKED', 'ANCHORED', 'SAILING') or a.busy_until is not null then`, `  if false then`), /PROOF 34 FAIL: a fleet in a battle started another|E_FLEET_BUSY/],
  ['a ship in a battle may be attacked', (s) => swap(s, `  if d.status = 'IN_BATTLE' or d.busy_until is not null then`, `  if false then`), /PROOF 34 FAIL: a ship in a battle took a second|E_FLEET_BUSY/],
  ['two attacks in a lap', (s) => swap(s, `  if c.last_attacked_lap is not distinct from coalesce(c.out_load, 0) then`, `  if false then`), /PROOF 34 FAIL: one lap, two attacks/],
  ['the lap is never marked', (s) => swap(s, `  update public.cargo_ships x set last_attacked_lap = coalesce(x.out_load, 0) where x.fleet_id = p_target;\n`, ``), /PROOF 34 FAIL: one lap, two attacks/],
  ['no cooldown', (s) => swap(s, `  if v_last is not null and v_last > p_now - make_interval(mins => v_wait::int) then`, `  if false then`), /PROOF 34 FAIL: the cooldown did not hold/],
  ['the cooldown never ends', (s) => swap(s, `  if v_last is not null and v_last > p_now - make_interval(mins => v_wait::int) then`, `  if v_last is not null then`), /PROOF 34 FAIL: the cooldown outlived itself/],
  // the opening
  ['the attack costs no regard', (s) => swap(s, `  perform public.regard_add(p_player, c.nation_id, public.wc_num('regard_attack_cargo'), 'ATTACK_CARGO');\n`, ``), /PROOF 34 FAIL: the attack cost/],
  ['the dry run keeps what it did', (s) => swap(s, `    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';\n  exception when others then\n    if sqlerrm = '__PREVIEW_ROLLBACK__' then\n      return v_out;\n    end if;\n    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;\n    get stacked diagnostics v_det = pg_exception_detail;\n    return cmd.refused_envelope(sqlerrm, v_det);\n  end;\nend\n$body$;\n$f$;\n\n  revoke all on function public.attack_word`, `    return v_out;\n  exception when others then\n    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;\n    get stacked diagnostics v_det = pg_exception_detail;\n    return cmd.refused_envelope(sqlerrm, v_det);\n  end;\nend\n$body$;\n$f$;\n\n  revoke all on function public.attack_word`), /PROOF 34 FAIL: the preview wrote something/],
  // the gold
  ['the share is the whole', (s) => swap(s, `case p_outcome when 'PLUNDERED' then floor(greatest(coalesce(p_aboard, 0), 0) * public.wc_num('loot_share'))::bigint`, `case p_outcome when 'PLUNDERED' then greatest(coalesce(p_aboard, 0), 0)`), /0327 self-assert FAIL: public.loot_due/],
  ['no ship cap', (s) => swap(s, `           public.wc_num('loot_per_ship')::bigint,\n`, ``), /0327 self-assert FAIL: public.loot_due/],
  ['no day cap', (s) => swap(s, `           public.wc_num('loot_per_company_day')::bigint - coalesce(p_taken, 0),\n`, ``), /0327 self-assert FAIL: public.loot_due/],
  ['the day cap is read wrong: it never counts', (s) => swap(s, `   where l.player_id = p_player and l.created_at > p_now - interval '24 hours' and l.kind = 'LOOT'`, `   where l.player_id = p_player and l.created_at > p_now - interval '24 hours' and l.kind = 'NOPE'`), /PROOF 34 FAIL: fight \d: wanted/],
  ['the day never comes back', (s) => swap(s, `l.created_at > p_now - interval '24 hours' and l.kind = 'LOOT'`, `l.kind = 'LOOT'`), /PROOF 34 FAIL: the day did not come back/],
  ['the day counts other companies', (s) => swap(s, `   where l.player_id = p_player and l.created_at > p_now - interval '24 hours'`, `   where l.created_at > p_now - interval '24 hours'`), /PROOF 34 FAIL: (fight \d|boarded|she paid off|the new day)/],
  ['the gold is made, not moved: no book row', (s) => swap(s, `  perform public.convoy_book('LOOTED', p_fleet, c.player_id, (select l.port_id from public.convoy_cargo l where l.id = v_load), v_take, v_load);\n`, ``), /PROOF 34 FAIL: (the funds aboard|every purse)/],
  ['the gold vanishes: no credit', (s) => swap(s, `  perform public.credit(p_player, 'LOOT', v_take);\n`, ``), /PROOF 34 FAIL: /],
  ['LOOT mints', (s) => swap(s, `values ('LOOT', 'moved', 'Loot', 50);`, `values ('LOOT', 'minted', 'Loot', 50);`), /0327 self-assert FAIL: LOOT is not a moved kind/],
  ['LOOT is a kind the closed economy refuses', (s) => swap(swap(s, `values ('LOOT', 'moved', 'Loot', 50);`, `values ('LOOT', 'minted', 'Loot', 50);`), `  if (select w.side from public.stats_flow_words w where w.kind = 'LOOT') is distinct from 'moved' then\n    raise exception '0327 self-assert FAIL: LOOT is not a moved kind';\n  end if;\n`, ``), /E_NO_NEW_GOLD/],
  ['the book pays the city too', (s) => swap(s, `$h$  if p_stage <> 'LOOTED' then   -- 0327: looted gold goes to a player, not to a purse: public.loot_take credits her, and no city moves`, `$h$  if true then   -- 0327: looted gold goes to a player, not to a purse: public.loot_take credits her, and no city moves`), /PROOF 34 FAIL|null value|E_/],
  ['the book forgets the live figure', (s) => swap(s, `  perform public.credit(p_player, 'LOOT', v_take);\n`, `  perform public.credit(p_player, 'LOOT', v_take);\n  perform public.stats_live_add(jsonb_build_object('set_aside', v_take));\n`), /PROOF 34 FAIL: the live figure moved/],
  ['the ransom is not a ransom', (s) => swap(s, `when 'RANSOM' then public.ransom_take(p_aboard)`, `when 'RANSOM' then 0`), /0327 self-assert FAIL: public.loot_due/],
  ['the crew of a ship that drove them off are spared', (s) => swap(s, `    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates->>'drove_off')::numeric)) where s.fleet_id = v_d;\n`, ``), /PROOF 34 FAIL: DRIVEN_OFF: wanted hands/],
  ['the attacker loses no hands', (s) => swap(s, `    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_a.fleet_id, s.crew, (v_rates->>'beaten')::numeric)) where s.fleet_id = v_a.fleet_id;\n`, ``), /PROOF 34 FAIL: DRIVEN_OFF: wanted hands/],
  ['a slip costs hands', (s) => swap(s, `  if v_out = 'DRIVEN_OFF' or v_broke then`, `  if v_out in ('DRIVEN_OFF', 'EVADED') or v_broke then`), /PROOF 34 FAIL: SLIPPED: wanted hands/],
  ['a break off costs nothing', (s) => swap(s, `  if v_out = 'DRIVEN_OFF' or v_broke then`, `  if v_out = 'DRIVEN_OFF' then`), /PROOF 34 FAIL: BROKE: wanted hands/],
  ['a boarding costs no hands', (s) => swap(s, `    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates->>'boarded')::numeric)) where s.fleet_id = v_d;\n`, `    null;\n`), /PROOF 34 FAIL: PLUNDERED: wanted hands/],
  ['a sink costs nothing more', (s) => swap(s, `    perform public.regard_add(v_a.player_id, c.nation_id, public.wc_num('regard_sink'), 'SINK_CARGO');\n`, ``), /PROOF 34 FAIL: sinking her cost/],
  ['a wreck keeps sailing', (s) => swap(s, `      perform voyage.npc_wreck(v_d, v_voyage.id, v_voyage.last_settled_day + 1);\n`, `      null;\n`), /PROOF 34 FAIL: lit, a wreck did not lie/],
  ['the wreck goes before the loot', (s) => swap(swap(s, `  if v_out in ('PLUNDERED', 'RANSOM') then\n    v_gold := public.loot_take(v_d, v_a.player_id, v_out, p_now);\n  end if;\n`, ``), `  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);`, `  if v_out in ('PLUNDERED', 'RANSOM') then\n    v_gold := public.loot_take(v_d, v_a.player_id, v_out, p_now);\n  end if;\n  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);`), /PROOF 34 FAIL: lit, the rest did not go home/],
  // the close
  ['the report says nothing of the gold', (s) => swap(s, `$h$'outcome', v_f->>'outcome') || v_rep || v_spoils);$h$`, `$h$'outcome', v_f->>'outcome') || v_rep);$h$`), /hunk .* occurs|does not reverse|PROOF 34 FAIL: the report/],
  ['a probe closes as an attack', (s) => swap(s, `  if b.kind = 'ATTACK' then   -- 0327: gold, hands and the sink, once, under this row's lock`, `  if true then   -- 0327: gold, hands and the sink, once, under this row's lock`), /PROOF 34 FAIL: a probe/],
  ['a door left open to anon', (s) => swap(s, `  revoke all on function cmd.attack(uuid, uuid, integer) from public, anon;\n`, `  grant execute on function cmd.attack(uuid, uuid, integer) to anon;\n`), /0327 self-assert FAIL: a door is wrongly granted/],
  ['a door not in the registry', (s) => swap(s, `      ('cmd',         'preview_attack',        'uuid, uuid'),$h$);`, `      ('cmd',         'preview_attacks',       'uuid, uuid'),$h$);`), /0327 self-assert FAIL: the two doors/],
  ['a server function left open', (s) => swap(s, '  revoke all on function public.loot_take(uuid, uuid, text, timestamptz) from public, anon, authenticated;\n', '  revoke all on function public.loot_take(uuid, uuid, text, timestamptz) from public, anon;\n  grant execute on function public.loot_take(uuid, uuid, text, timestamptz) to authenticated;\n'), /0327 self-assert FAIL: a server-only function/],
  ['a knob moved', (s) => swap(s, `  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`, `  update public.world_config set value = '0.16', updated_at = now() + interval '1 hour' where key = 'fight_raider_break';\n  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`), /0327 self-assert FAIL: a world_config row moved/],
  ['another function moved', (s) => swap(s, `  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`, `  execute replace(pg_get_functiondef('public.armour_soak(numeric,numeric)'::regprocedure), 'declare', '-- moved\ndeclare');\n  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──`), /0327 self-assert FAIL: another function moved/],
]

const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

say('\nRED FIRST: proof 34 on the world without the file')
const red = await attempt('', true)
say('  ', red.err ? `red: ${red.err.slice(0, 160)}` : 'IT PASSED')
if (!red.err) failures.push('proof 34 passed with no file')

const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice('--first='.length).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '').replace(/^﻿/, '')
if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)

say('\nPOSITIVE CONTROL: the real file alone')
const alone = await attempt(before + '\n' + file, false)
if (alone.err) failures.push(`the real file failed: ${alone.err}`)
say('  ', alone.err ?? alone.notes.find((n) => n.includes('0327 self-assert ok')), `${alone.ms} ms`)

say('POSITIVE CONTROL: the real file, then proof 34')
const whole = await attempt(before + '\n' + file, true)
if (whole.err) failures.push(`proof 34 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:'))) say('  ', n)
if (whole.err) say('   ERROR', whole.err.slice(0, 1600))
say('  ', `${whole.ms} ms`)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    if (only && !label.includes(only)) continue
    const r = await attempt(before + '\n' + mutate(file), true)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${MUTATIONS.length} mutations red, the real file and proof 34 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
