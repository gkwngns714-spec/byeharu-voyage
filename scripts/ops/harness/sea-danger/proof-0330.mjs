// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0330.mjs — DANGER IS ONE NUMBER (migration 0330): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/sea-danger/proof-0330.mjs [--first=a.sql,b.sql] [--no-mutations]
//
// Restores the cached world at the head before 0330 (never from zero), then inside transactions that are rolled back runs:
//   RED FIRST         - proof 38 on the world with no file: it must fail;
//   DARK PARITY       - this slice's scene, one fixed voyage through all 51 seas, on the world before the file and after it: every SCENE line must be equal;
//   POSITIVE CONTROL  - the real file followed by proof 38;
//   DEPLOY ORDER      - with --first, those files first, in that order (0329, W12, is read from its branch this way);
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 38 right after it, for the intended reason.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000330_danger_is_one_number.sql'
const PROOF = 'scripts/db/proofs/38_sea_danger.sql'
const SCENES = ['scripts/ops/harness/sea-danger/dark-scene.sql']
const failures = []
const say = (...a) => console.log(...a)

const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const scenes = await Promise.all(SCENES.map(async (s) => (await readFile(s, 'utf8')).replaceAll('\r', '')))
const first = (process.argv.find((a) => a.startsWith('--first=')) ?? '--first=').slice(8).split(',').filter(Boolean)
const before = (await Promise.all(first.map((f) => readFile(f, 'utf8')))).join('\n').replaceAll('\r', '')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false })
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored, ${out.applied.filter((r) => !r.restored).length} applied`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, () => to)
}

async function attempt(...sqls) {
  const notes = []
  const onNotice = (n) => notes.push(n.message)
  await db.exec('begin')
  let err = null
  try {
    for (const sql of sqls) if (sql) await db.exec(sql, { onNotice })
  } catch (e) {
    err = e.message
  }
  try { await db.exec('rollback') } catch { /* already aborted */ }
  return { err, notes }
}

const MUTATIONS = [
  ['a departure freezes nothing', (s) => swap(s, `$h$  values (p_fleet, v_player, voyage.freeze_danger(p_segments, p_at), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left\n$h$),`, `$h$  values (p_fleet, v_player, p_segments, v_total, v_profile, p_at,   -- 0330\n$h$),`), /PROOF 38 FAIL: frozen on the wrong figure/],
  ['a departure freezes the sea as authored', (s) => swap(s, `voyage.sea_danger((e.seg->>'sea_id')::uuid, p_at)) order by e.n`, `voyage.sea_danger((e.seg->>'sea_id')::uuid, null)) order by e.n`), /PROOF 38 FAIL: a voyage leaving under pressure did not freeze it/],
  ['the roll reads the live figure', (s) => swap(s, `$h$    from voyage.sea_mix(v_sea, voyage.leg_danger(v_leg)) m   -- 0330: the danger she departed into, frozen on the leg\n$h$`, `$h$    from voyage.sea_mix(v_sea, voyage.sea_danger(v_sea, now())) m   -- 0330\n$h$`), /PROOF 38 FAIL: pressure after she left moved/],
  ['the raid reads the live figure', (s) => swap(s, `$h$      v_raider := voyage.leg_danger(voyage.leg_at_day(v.id, d)) * 40 * (0.5 + h.magnitude);   -- 0330: the danger she departed into, frozen on the leg\n$h$`, `$h$      v_raider := voyage.sea_danger((voyage.leg_at_day(v.id, d)->>'sea_id')::uuid, now()) * 40 * (0.5 + h.magnitude);\n$h$`), /PROOF 38 FAIL: late and on time differ/],
  ['the quote reads the live figure', (s) => swap(s, `from voyage.sea_mix(x.sea, x.danger) m`, `from voyage.sea_mix(x.sea, voyage.sea_danger(x.sea, now())) m`), /PROOF 38 FAIL: pressure after she left moved/],
  ['the panel reads the live figure', (s) => swap(s, `from voyage.sea_mix(s.id, v_dang[i]) m`, `from voyage.sea_mix(s.id, voyage.sea_danger(s.id, now())) m`), /PROOF 38 FAIL: pressure after she left moved/],
  ['a leg with no figure has none', (s) => swap(s, `select coalesce((p_leg->>'danger')::numeric, voyage.sea_danger((p_leg->>'sea_id')::uuid, null))`, `select (p_leg->>'danger')::numeric`), /no figure|E_NO_SEA_MIX|the leg reads/],
  ['the figure has two places', (s) => swap(s, `from public.sea_pressure sp where sp.sea_id = p_sea and p_at is not null), 0)))), 4), 0)`, `from public.sea_pressure sp where sp.sea_id = p_sea and p_at is not null), 0)))), 2), 0)`), /not its piracy_index to the digit/],
  ['pressure never decays', (s) => swap(s, `sp.value * power(public.wc_num('sea_pressure_decay'), greatest(0, extract(epoch from p_at - sp.updated_at) / 3600))`, `sp.value`), /does not decay/],
  ['pressure grows into the past', (s) => swap(s, `greatest(0, extract(epoch from p_at - sp.updated_at) / 3600)`, `extract(epoch from p_at - sp.updated_at) / 3600`), /grows into the past/],
  ['the figure goes over 1', (s) => swap(s, `round(least(1, greatest(0, s.piracy_index *`, `round(least(9, greatest(0, s.piracy_index *`), /above 1/],
  ['the figure goes under 0', (s) => swap(s, `round(least(1, greatest(0, s.piracy_index *`, `round(least(1, greatest(-9, s.piracy_index *`), /below 0/],
  ['the mix ignores the figure', (s) => swap(s, `  v_p   numeric := p_danger;`, `  v_p   numeric := 0.2;`), /the mix of .* moved/],
  ['the raid arm keeps its old read', (s) => swap(s, `$h$      v_raider := voyage.leg_danger(voyage.leg_at_day(v.id, d)) * 40 * (0.5 + h.magnitude);   -- 0330: the danger she departed into, frozen on the leg\n$h$`, `$h$      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid; -- 0330
$h$`), /a second reader of piracy_index/],
  ['the level never moves', (s) => swap(s, `s.danger_level + voyage.sea_band(voyage.sea_danger(s.id, now())) - voyage.sea_band(voyage.sea_danger(s.id, null))`, `s.danger_level + 0`), /PROOF 38 FAIL: 0\.25 is one band up/],
  ['the level leaves the scale', (s) => swap(s, `least(5, greatest(1, s.danger_level +`, `least(9, greatest(-9, s.danger_level +`), /PROOF 38 FAIL: a level left the scale/],
  ['a client can read the map early', (s) => swap(s, `  revoke all on function world.sea_danger() from public, anon, authenticated;\n`, `  grant execute on function world.sea_danger() to authenticated;\n`), /a client can reach what is new/],
  ['the table is open', (s) => swap(s, `  revoke all on table public.sea_pressure from public, anon, authenticated;\n`, `  grant select on table public.sea_pressure to authenticated;\n`), /a client can reach what is new/],
  ['the old mix stays', (s) => swap(s, `  drop function voyage.sea_mix(uuid);\n`, ``), /another function moved/],
  ['a hunk is off its line', (s) => swap(s, `$h$    from voyage.sea_mix(v_sea) m\n$h$,`, `$h$    from voyage.sea_mix(v_sea)  m\n$h$,`), /occurs 0 time/],
]

// RED FIRST
const red = await attempt(before, proof)
say(`RED FIRST, no file: ${red.err ? 'red: ' + red.err.slice(0, 120) : 'IT PASSED'}`)
if (!red.err) failures.push('proof 38 passed with no file')

// DARK PARITY
const lines = (r) => r.notes.filter((n) => n.startsWith('SCENE: '))
for (const [i, scene] of scenes.entries()) {
  const a = await attempt(before, scene)
  const b = await attempt(before, file, scene)
  if (a.err) failures.push(`scene ${i} before: ${a.err}`)
  if (b.err) failures.push(`scene ${i} after: ${b.err}`)
  say(`DARK PARITY ${SCENES[i]}: ${lines(a).length} scene lines before, ${lines(b).length} after`)
  for (const n of lines(a)) say('  ', n.slice(0, 180))
  if (lines(a).length === 0 || lines(a).length !== lines(b).length) failures.push(`scene ${i} line counts differ`)
  lines(a).forEach((n, j) => {
    if (n !== lines(b)[j]) {
      failures.push(`dark differs in scene ${i} at line ${j}`)
      say('BEFORE', n.slice(0, 1500))
      say('AFTER ', (lines(b)[j] ?? '').slice(0, 1500))
    }
  })
}

// POSITIVE CONTROL
const t0 = Date.now()
const whole = await attempt(before, file, proof)
say(`whole: ${Date.now() - t0} ms`)
if (whole.err) failures.push(`proof 38 failed: ${whole.err}`)
for (const n of whole.notes.filter((x) => /^(PASS:|SIM:|SPEED:)/.test(x) || /self-assert ok/.test(x))) say('  ', n)
if (whole.err) say('   ERROR', whole.err)
const want = [...proof.matchAll(/^--\s*@pass\s+([A-Z0-9_]+)/gm)].map((m) => m[1])
const missing = want.filter((m) => !whole.notes.some((n) => n.startsWith(`PASS: ${m}`)))
if (missing.length) failures.push(`markers missing: ${missing.join(', ')}`)

if (!process.argv.includes('--no-mutations') && failures.length === 0) {
  say('\nMUTATION CONTROLS')
  for (const [label, mutate, expected, how] of MUTATIONS) {
    let hit
    let got
    if (how === 'scene') {
      const a = await attempt(before, scenes[0])
      const b = await attempt(before, mutate(file), scenes[0])
      hit = lines(a).length > 0 && lines(a).some((n, j) => n !== lines(b)[j])
      got = 'the scene did not differ'
    } else {
      const r = await attempt(before, mutate(file), proof)
      hit = r.err && expected.test(r.err)
      got = (r.err ?? 'it passed').slice(0, 260)
    }
    say(`  ${hit ? 'red as required' : 'WRONG'}: ${label}${hit ? '' : ` -- ${got}`}`)
    if (!hit) failures.push(`mutation not caught for the intended reason: ${label}`)
  }
}

await db.close()
const ran = process.argv.includes('--no-mutations') ? 'mutations NOT run' : `${MUTATIONS.length} mutations red`
say(failures.length ? `\nFAILED:\n  ${failures.join('\n  ')}` : `\nALL GREEN: ${ran}, red first, dark parity equal, the real file and proof 38 green, nothing from zero.`)
process.exit(failures.length ? 1 : 0)
