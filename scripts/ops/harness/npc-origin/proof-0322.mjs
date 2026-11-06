// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0322.mjs — EVERY NPC SHIP HAS AN ORIGIN (migration 0322): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/npc-origin/proof-0322.mjs [--first=a.sql,b.sql] [--no-mutations]
//
// Restores the cached world at the head before 0322 (never from zero), then inside a transaction that is rolled back applies:
//   POSITIVE CONTROL  - the real file followed by proof 30;
//   DEPLOY ORDER      - with --first, those files first, in that order (0321 is read from its branch this way);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 30 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000322_every_npc_ship_has_an_origin.sql'
const PROOF = 'scripts/db/proofs/30_every_npc_ship.sql'
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name.startsWith('20260818000322') || name > NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice(8).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

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
  ['the origin reader takes no cargo ship', (s) => swap(s, `select coalesce((select c.home_port_id from public.cargo_ships c where c.fleet_id = p_fleet),\n                  (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet))`,
    `select (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet)`), /PROOF 30 FAIL: a cargo ship does not read her own home/],
  ['the wreck test ignores the switch', (s) => swap(s, `select case when public.npc_refits_on()\n              then public.fleet_origin(p_fleet) is not null`, `select case when true\n              then public.fleet_origin(p_fleet) is not null`), /PROOF 30 FAIL: dark, a wreck did not sail on/],
  ['a fleet with one hull at 0 is a wreck', (s) => swap(s, `bool_and(s.durability <= 0)`, `bool_or(s.durability <= 0)`), /PROOF 30 FAIL: a hull left and still a wreck/],
  ['a human can be a wreck', (s) => swap(s, `then public.fleet_origin(p_fleet) is not null\n                   and coalesce`, `then coalesce`), /PROOF 30 FAIL: a human is a wreck by this rule/],
  ['a calm day is asked too', (s) => swap(s, `if v_kind in ('STORM', 'PIRATES', 'SHOAL_WATER') and public.npc_wrecked(p_fleet) then`, `if public.npc_wrecked(p_fleet) then`), /PROOF 30 FAIL: a calm day wrecked her/],
  ['PIRATES is left out', (s) => swap(s, `if v_kind in ('STORM', 'PIRATES', 'SHOAL_WATER') and`, `if v_kind in ('STORM', 'SHOAL_WATER') and`), /PROOF 30 FAIL: PIRATES did not put her at her origin/],
  ['she is left where she sank', (s) => swap(s, `set status = 'UNABLE_TO_SAIL', port_id = v_home, lat = null`, `set status = 'UNABLE_TO_SAIL', port_id = (select o.dest_port_id from public.voyages o where o.id = p_voyage), lat = null`), /did not put her at her origin/],
  ['the voyage stays open', (s) => swap(s, `update public.voyages set status = 'ABORTED' where id = p_voyage;\n  end if;\n\n  v_out`, `null;\n  end if;\n\n  v_out`), /voyages_|PROOF 30 FAIL|invariant|fleets_position/],
  ['the hold is kept', (s) => swap(s, `  v_lost := voyage.lose_hold(p_fleet);\n  if p_voyage is not null then`, `  v_lost := '{}'::jsonb;\n  if p_voyage is not null then`), /PROOF 30 FAIL: STORM left goods in her hold/],
  ['the queue is kept', (s) => swap(s, `  perform cmd.clear_for(f.player_id, p_fleet, false);\n  update public.fleets\n     set status = 'UNABLE_TO_SAIL'`, `  update public.fleets\n     set status = 'UNABLE_TO_SAIL'`), /PROOF 30 FAIL: STORM left a queue/],
  ['no claim on a wreck', (s) => swap(s, `v_ins := public.insurance_claim(p_voyage, p_day, v_lost, 'WRECK');`, `v_ins := null;`), /PROOF 30 FAIL: the claim is not the wreck's/],
  ['funds aboard are not returned', (s) => swap(s, `perform public.convoy_book('RETURNED', p_fleet, f.player_id, v_home, v_left, v_load);\n  end if;\n\n  -- (c)`, `null;\n  end if;\n\n  -- (c)`), /PROOF 30 FAIL: her book did not close at home/],
  ['the cargo step patches a wreck', (s) => swap(s, `  if public.npc_wrecked(p_fleet) then   -- 0322: she waits for her city to pay (public.npc_refit_step). Dark: false, and the patch below stands\n    return 'WRECK';\n  end if;\n`, ''), /PROOF 30 FAIL: a wreck patched herself/],
  ['a broke city pays anyway', (s) => swap(s, `if public.city_surplus(v_home) < v_cost then`, `if false then`), /PROOF 30 FAIL/],
  ['the reserve is not read: the balance judges', (s) => swap(s, `if public.city_surplus(v_home) < v_cost then`, `if public.treasury_balance(v_home) < v_cost then`), /PROOF 30 FAIL: a city short of cost and reserve did not wait/],
  ['the wait is worded every hour', (s) => swap(s, ` where w.told_at <= p_now - interval '1 day';`, `;`), /PROOF 30 FAIL: REFIT_WAITING is not once a day/],
  ['the wait is never worded again', (s) => swap(s, ` where w.told_at <= p_now - interval '1 day';`, ` where false;`), /PROOF 30 FAIL: a day on, the wait is not told again/],
  ['the money vanishes: no yard row', (s) => swap(s, `  perform public.treasury_post(v_yard, 'REFIT', v_cost, null, v_ev);\n`, ''), /PROOF 30 FAIL: the refit is not moved/],
  ['she pays herself', (s) => swap(s, `   where y.port_id <> p_port\n   order by coalesce`, `   order by coalesce`), /PROOF 30 FAIL: a city pays itself|the refit is not moved/],
  ['no country first', (s) => swap(s, `order by coalesce(public.port_nation(y.port_id) = public.port_nation(p_port), false) desc, y.nm, y.code`, `order by y.nm, y.code`), /PROOF 30 FAIL: a foreign yard was chosen|never put to the test/],
  ['REFIT mints', (s) => swap(s, `values ('REFIT', 'moved', 'Refits', 49)`, `values ('REFIT', 'minted', 'Refits', 49)`), /0322 self-assert FAIL: REFIT is not a moved kind/],
  ['the hull is restored unpaid', (s) => swap(s, `    return 'WAITING';\n  end if;\n`, `    perform public.fleet_mend(p_fleet);\n    return 'WAITING';\n  end if;\n`), /PROOF 30 FAIL/],
  ['no crew from the quay', (s) => swap(s, `if public.fleet_kind(p_fleet) = 'MERCHANT' then\n    v_short`, `if false then\n    v_short`), /PROOF 30 FAIL: the crew is not the quay's two/],
  ['the cargo ship takes a crew', (s) => swap(s, `if public.fleet_kind(p_fleet) = 'MERCHANT' then\n    v_short`, `if true then\n    v_short`), /PROOF 30 FAIL: she took a crew before W8/],
  ['the floor of the quay is ignored', (s) => swap(s, `v_hands := (public.crew_hire_cost(p_fleet, v_short) ->> 'normal')::int;`, `v_hands := v_short;`), /PROOF 30 FAIL: the crew is not the quay's two/],
  ['no wait after the refit', (s) => swap(s, `set status = 'DOCKED', ready_at = p_now + make_interval(mins => public.wc_int('npc_refit_minutes')), version = version + 1`, `set status = 'DOCKED', version = version + 1`), /PROOF 30 FAIL: she is not held for the wait/],
  ['a stray is skipped', (s) => swap(s, `    perform voyage.npc_wreck(p_fleet);   -- a wreck no settled day brought home\n`, `    return 'NOT_A_WRECK';\n`), /PROOF 30 FAIL: the job did not bring a stray home/],
  ['the tow takes a wreck', (s) => swap(s, `$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null and not public.npc_wrecked(r.fleet_id) then   -- 0322: a wreck is her city's to set afloat (public.npc_refit_step). Dark: false\n`, `$h$      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then   -- 0322: a wreck is her city's to set afloat (public.npc_refit_step). Dark: false\n`), /PROOF 30 FAIL: lit, the tow took a wreck/],
  ['a hunk is not on its line', (s) => swap(s, `$h$    v_resolved := v_resolved + 1;\n  end loop;\n$h$,`, `$h$    v_resolved := v_resolved + 2;\n  end loop;\n$h$,`), /0322 self-assert FAIL: hunk 1 of voyage.settle/],
  ['the ransom pays', (s) => swap(s, `    perform public.convoy_book('RETURNED', p_fleet, f.player_id, v_home, v_left, v_load);\n  end if;\n\n  -- (c)`, `    perform public.convoy_book('RETURNED', p_fleet, f.player_id, v_home, v_left - public.ransom_take(v_left), v_load);\n  end if;\n\n  -- (c)`), /PROOF 30 FAIL/],
]

if (first.length) say(`DEPLOY ORDER: ${first.length} file(s) first`)
const t0 = Date.now()
const whole = await attempt(before + '\n' + file, true)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 30 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => x.startsWith('PASS:') || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected] of MUTATIONS) {
    const r = await attempt(before + '\n' + mutate(file), true)
    const hit = r.err && expected.test(r.err)
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${(r.err ?? 'it passed').slice(0, 260)}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${MUTATIONS.length} mutations red, the real file and proof 30 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
