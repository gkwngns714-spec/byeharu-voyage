// proof-0320.mjs: A FIGHT HAS TWO SIDES (migration 0320): the red-first proof. LOCAL ONLY (PGlite); not in CI. Run from the repo root:
//   node scripts/ops/harness/two-sides/proof-0320.mjs
// On mini-world.mjs (what a fight reads, and no more), it applies 0320 several times inside a transaction that is rolled back:
//   MUTATION CONTROLS: deliberate breakages of the file, each required to FAIL its self-assert, or the pure half of proof 28 run right after it, for the intended reason;
//   POSITIVE CONTROL:  the real file followed by the pure half of proof 28, which must pass and print their receipts.
// proof 28's real-fleet half needs the real world: CI.

import { readFile } from 'node:fs/promises'
import { miniWorld } from './mini-world.mjs'

const NAME = 'supabase/migrations/20260818000320_a_fight_has_two_sides.sql'
const file = (await readFile(NAME, 'utf8')).replaceAll('\r', '')
const whole = (await readFile('scripts/db/proofs/28_fight_sides.sql', 'utf8')).replaceAll('\r', '')
const proof = whole.slice(0, whole.indexOf('-- END OF THE PURE PROOF'))
const say = (...a) => console.log(...a)
const failures = []
const db = await miniWorld()

function swap(sql, from, to) {
  const n = sql.split(from).length - 1
  if (n < 1) throw new Error(`mutation target not found: ${from.slice(0, 70)}`)
  return sql.replaceAll(from, to)
}

const MUTATIONS = [
  ['whole hulls: the squadron fires one shot', (s) => swap(s, `'shots', greatest(1, ceil(r_n))::int,`, `'shots', 1,`), /fight\(s\) changed/],
  ['a stream renamed: side a re-rolls', (s) => swap(s, `p_g, p_tag, n))\n                      >=`, `p_g, p_tag || 'x', n))\n                      >=`), /fight\(s\) changed/],
  ['a shot number moves when a hull cannot fire', (s) => swap(s, `    if p_att[i] <= 0 or p_acc[i] <= 0 or p_hull[i] <= 0 then\n      n := n + p_shots[i];\n`, `    if p_att[i] <= 0 or p_acc[i] <= 0 or p_hull[i] <= 0 then\n`), /a fight changed/],
  ['the broadsides do not land together', (s) => swap(s, `a_att, a_acc, a_reach, a_hull, a_shots, v_bb, b_arm, b_hull, b_maxd);\n`, `a_att, a_acc, a_reach, a_hull, a_shots, v_bb, b_arm, b_hull, b_maxd);\n    b_hull[1] := greatest(0, b_hull[1] - v_va.taken[1]);\n`), /fight\(s\) changed/],
  ['the armour of the wrong side', (s) => swap(s, `v_bb, b_arm, b_hull, b_maxd);`, `v_bb, a_arm[1:1], b_hull, b_maxd);`), /fight\(s\) changed/],
  ['the reach bar counts unarmed hulls', (s) => swap(s, `    if a_att[i] > 0 and a_acc[i] > 0 then\n      v_ba := greatest(v_ba, a_reach[i]);\n    end if;\n`, `    v_ba := greatest(v_ba, a_reach[i]);\n`), /fight\(s\) changed|FIGHT|PROOF 28 FAIL/],
  ['the squadron loses a figure: tier is not scaled', (s) => swap(s, `'tier', r_n * c.tier,`, `'tier', c.tier,`), /fight\(s\) changed/],
  ['a word changed in the report', (s) => swap(s, `'They break off and run.'`, `'They break off and flee.'`), /fight\(s\) changed/],
  ['the wrong side named as struck', (s) => swap(s, `jsonb_array_elements(v_a->'struck')`, `jsonb_array_elements(v_b->'struck')`), /fight\(s\) changed/],
  ['the percent read after the hull fell', (s) => swap(s, `        v_pct := greatest(1, round(least(v_vb.taken[i], a_hull[i]) / a_maxd[i] * 100));\n`, `        v_pct := greatest(1, round(v_vb.taken[i] / a_maxd[i] * 100));\n`), /a fight changed/],
  ['side b loses no hull in the answer', (s) => swap(s, `'b', coalesce((select jsonb_object_agg(b_id[k]::text, round(b_hull0[k] - b_hull[k], 2)) from generate_subscripts(b_id, 1) k where b_hull0[k] > b_hull[k]), '{}'::jsonb)),`, `'b', '{}'::jsonb),`), /both sides must lose hull|does not add up/],
  ['a shot on side b always falls on her first hull', (s) => swap(s, `        exit when v_pick < v_sum;\n`, `        exit;\n`), /both sides must lose hull|fight\(s\) changed/],
  ['a volley names a table', (s) => swap(s, `  can := 0; fired := 0; hits := 0; raw := 0; dealt := 0;\n`, `  can := 0; fired := 0; hits := 0; raw := 0; dealt := 0;\n  perform 1 from public.ship_classes;\n`), /names a table/],
  ['the engine reads through a function that is not world_config', (s) => swap(s, `  v_hand   numeric := public.wc_num('fight_hand_value');\n`, `  v_hand   numeric := public.wc_num('fight_hand_value') + coalesce(length(public.wc_text('world_secret')), 0) * 0;\n`), /reads through something/],
  ['raiders built in a second place', (s) => swap(s, `  v_name  text := v_r->>'name';\n`, `  v_name  text := coalesce(v_r->>'name', public.wc_text('fight_raider_class'));\n`), /built in a second place/],
  ['a door left open to clients', (s) => swap(s, `  revoke all on function public.fight_sides(uuid, int, jsonb, jsonb, jsonb) from public, anon, authenticated;\n`, ``), /open to clients/],
  ['the builder left open to clients', (s) => swap(s, `  revoke all on function voyage.raider_hulls(numeric) from public, anon, authenticated;\n`, ``), /open to clients/],
  ['cut against another body', (s) => swap(s, `'8fc074d4f0a09332b321eb55a600c2fc'`, `'00000000f0a09332b321eb55a600c2fc'`), /not the body this file was cut against/],
  ['a knob moved', (s) => swap(s, `  -- ── 5. PARITY`, `  update public.world_config set value = '0.16' where key = 'fight_raider_break';\n  -- ── 5. PARITY`), /a knob moved/],
  ['another function moved', (s) => swap(s, `  -- ── 5. PARITY`, `  execute replace(pg_get_functiondef('public.armour_soak(numeric,numeric)'::regprocedure), 'declare', '-- moved\ndeclare');\n  -- ── 5. PARITY`), /another function moved/],
]

async function attempt(sql) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

const green = await attempt(`${file}\n${proof}`)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`${green.ok ? 'GREEN' : 'FAIL'}  the real file and proof 28's pure half, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n    ') : green.error.slice(0, 1200)}`)

if (green.ok) {
  for (const [what, mutate, why] of MUTATIONS) {
    const r = await attempt(`${mutate(file)}\n${proof}`)
    const good = !r.ok && why.test(r.error)
    if (!good) failures.push(what)
    say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 200)}`)
  }
}

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say('\nall mutations red, the real file green')
