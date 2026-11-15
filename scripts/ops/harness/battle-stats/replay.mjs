// 0450 REPLAY (local only, never prod): the frozen RAID sheets read from prod by prod-sheets.sql, re-fought by public.tick_fight on the chain's
// cached world (0450 applied) under the OLD run rule and the NEW one, the same seeds (the battles' ids) and the same dice in every arm.
//   node scripts/ops/harness/battle-stats/replay.mjs <sheets.json>
// Prod's own fight knobs are laid over the local ones first (rolled back). Each hull gets what 0450 freezes at the open (`lv`, `crew_need`) from
// the read's `cards`. The OLD arm is 0450's rollback knobs, which its self-assert proves is the old chance to the digit. The local world's secret
// is not prod's, so a fight here is not prod's own roll of the dice; the read's `out` (what prod fought) is printed beside the arms.
import { readFile } from 'node:fs/promises'
import { applyChainCached } from '../../../db/apply-chain.mjs'

const file = process.argv[2]
if (!file) throw new Error('usage: replay.mjs <sheets.json>')
const raw = JSON.parse(await readFile(file, 'utf8'))
const read = (raw.rows ?? raw)[0].r
const battles = read.battles ?? []
const { db } = await applyChainCached({ log: () => {} })

const ARMS = {
  'OLD (0432: floor 0.10, cap 0.80, base 0.15, no level, state or tries)': { raid_flee_floor: 0.1, raid_flee_max: 0.8, raid_flee_base: 0.15, flee_per_level: 0, flee_hurt_max: 0, flee_per_try: 0 },
  'NEW (0450: floor 0.03, cap 0.45, base 0.10, level 0.03, hurt 0.20, try 0.05)': {},
  'softer A (floor 0.05, cap 0.45, base 0.15, level 0.02, try 0.03)': { raid_flee_floor: 0.05, raid_flee_base: 0.15, flee_per_level: 0.02, flee_per_try: 0.03 },
  'softer B (floor 0.08, cap 0.60, base 0.20, level 0.02, try 0.03)': { raid_flee_floor: 0.08, raid_flee_max: 0.6, raid_flee_base: 0.2, flee_per_level: 0.02, flee_per_try: 0.03 },
  'harder (floor 0.01, cap 0.30, base 0.05)': { raid_flee_floor: 0.01, raid_flee_max: 0.3, raid_flee_base: 0.05 },
}
const withCard = (b, key) => (b[key] ?? []).map((h) => ({ ...h, ...(b.cards?.[h.id] ? { lv: b.cards[h.id].lv, crew_need: b.cards[h.id].crew_need } : {}) }))
const tally = (rows, f) => rows.reduce((m, r) => ((m[f(r)] = (m[f(r)] ?? 0) + 1), m), {})
const show = (m) => ['PLUNDERED', 'DRIVEN_OFF', 'EVADED', 'RANSOM'].map((k) => `${k} ${m[k] ?? 0}`).join(' / ')

console.log(`sheets: ${battles.length} closed tick RAIDs, prod ${read.at} (head ${read.head}); levels_bite ${read.knobs.levels_bite}`)
console.log(`as prod fought them:        ${show(tally(battles, (b) => b.out))}   | opened FLEE ${battles.filter((b) => b.ai?.a === 'FLEE').length}: ${show(tally(battles.filter((b) => b.ai?.a === 'FLEE'), (b) => b.out))}`)
for (const [name, knobs] of Object.entries(ARMS)) {
  await db.exec('begin')
  for (const [k, v] of Object.entries(read.knobs)) await db.query('update public.world_config set value = $1::jsonb where key = $2 and key not like $3', [JSON.stringify(v), k, 'raid_flee_%'])
  for (const [k, v] of Object.entries(knobs)) await db.query('update public.world_config set value = $1::jsonb where key = $2', [JSON.stringify(v), k])
  const out = []
  for (const b of battles) {
    const opts = { a_ai: b.ai?.a ?? 'FIGHT', b_ai: b.ai?.b ?? 'FIGHT', ...(b.a_flee != null ? { a_flee: b.a_flee } : {}), ...(Array.isArray(b.acts) ? { acts: b.acts } : {}) }
    const r = await db.query('select public.tick_fight($1::uuid, $2::jsonb, $3::jsonb, $4::jsonb) as tl', [b.id, JSON.stringify(withCard(b, 'a')), JSON.stringify(withCard(b, 'b')), JSON.stringify(opts)])
    const tl = r.rows[0].tl
    const rolls = tl.e.filter((e) => e[2] === 'X' && e[1] === 0)
    out.push({ flee: opts.a_ai === 'FLEE', kind: b.def_kind, out: tl.out, fled: !!tl.r.fled, rolls: rolls.length, first: tl.rc?.a?.[0]?.[1] ?? null, n: tl.n })
  }
  await db.exec('rollback')
  const fl = out.filter((o) => o.flee)
  const first = fl.map((o) => o.first).filter((x) => x != null).sort((a, b) => a - b)
  console.log(`\n${name}`)
  console.log(`  all ${out.length}:          ${show(tally(out, (o) => o.out))}`)
  console.log(`  opened FLEE ${fl.length}:    ${show(tally(fl, (o) => o.out))}   | got away by running ${fl.filter((o) => o.fled).length} of ${fl.length}; rolls a fight ${(fl.reduce((n, o) => n + o.rolls, 0) / Math.max(1, fl.length)).toFixed(1)}; chance at the open min ${first[0]} / median ${first[Math.floor(first.length / 2)]} / max ${first[first.length - 1]} %`)
  console.log(`  opened FIGHT ${out.length - fl.length}:   ${show(tally(out.filter((o) => !o.flee), (o) => o.out))}`)
}
await db.close()
