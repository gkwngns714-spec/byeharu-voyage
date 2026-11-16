// 0453 REPLAY (local only, never prod): the frozen RAID sheets read from prod by battle-stats/prod-sheets.sql, re-fought by public.tick_fight on the
// chain's cached world (0453 applied) under 0450's rule (chase_enabled false) and the chase, the same seeds (the battles' ids) and the same dice in
// every arm.   node scripts/ops/harness/evasion/replay.mjs <sheets.json>
// Prod's own fight knobs are laid over the local ones first (rolled back). Each hull keeps her whole frozen card (since 0450 a sheet carries speed,
// handling, lv and crew_need) and gets what 0453 freezes at the open: `ev` her card's `lv` for a ship of the world (both sides of a raid on a MERCHANT
// or a CARGO_SHIP; the pirate's side always), 1 for a company's hull (nobody holds Evasion experience before the deploy); `run` 10 x (ev - 1).
// The local world's secret is not prod's, so a fight here is not prod's own roll of the dice; prod's `out` is printed beside the arms.
import { readFile } from 'node:fs/promises'
import { applyChainCached } from '../../../db/apply-chain.mjs'

const file = process.argv[2]
if (!file) throw new Error('usage: replay.mjs <sheets.json>')
const raw = JSON.parse(await readFile(file, 'utf8'))
const read = (raw.rows ?? raw)[0].r
const battles = read.battles ?? []
const { db } = await applyChainCached({ log: () => {} })
if ((await db.query("select count(*)::int as n from public.world_config where key = 'chase_enabled'")).rows[0].n !== 1) throw new Error('the cached world has no 0453')

const ARMS = {
  '0450 (chase_enabled false: the rule on prod now)': { chase_enabled: false },
  'PROPOSED (chase_base 0.15, power 2, floor 0.01, cap 0.50)': {},
  'harder (chase_base 0.10)': { chase_base: 0.1 },
  'softer (chase_base 0.20)': { chase_base: 0.2 },
}
const level = (h, b, side) => {
  const lv = Number(h.lv ?? b.cards?.[h.id]?.lv ?? 1)
  return side === 'a' && b.def_kind === 'COMPANY' ? 1 : lv
}
const sheet = (b, side) =>
  (b[side] ?? []).map((h) => {
    const c = b.cards?.[h.id] ?? {}
    const ev = level(h, b, side)
    return { ...h, lv: h.lv ?? c.lv ?? 1, crew_need: h.crew_need ?? c.crew_need, ev, run: 10 * (ev - 1) }
  })
const tally = (rows, f) => rows.reduce((m, r) => ((m[f(r)] = (m[f(r)] ?? 0) + 1), m), {})
const show = (m) => ['PLUNDERED', 'DRIVEN_OFF', 'EVADED', 'RANSOM'].map((k) => `${k} ${m[k] ?? 0}`).join(' / ')
const per100 = (n, d) => (d ? ((100 * n) / d).toFixed(1) : '-')

const fleeProd = battles.filter((b) => b.ai?.a === 'FLEE')
console.log(`sheets: ${battles.length} closed tick RAIDs, prod ${read.at} (head ${read.head}); levels_bite ${read.knobs.levels_bite}; defenders ${JSON.stringify(tally(battles, (b) => b.def_kind))}`)
console.log(`hulls with speed and handling on the card: ${battles.flatMap((b) => [...(b.a ?? []), ...(b.b ?? [])]).filter((h) => h.speed != null && h.handling != null).length} of ${battles.flatMap((b) => [...(b.a ?? []), ...(b.b ?? [])]).length}`)
console.log(`as prod fought them:        ${show(tally(battles, (b) => b.out))}   | opened FLEE ${fleeProd.length}: ${show(tally(fleeProd, (b) => b.out))}; got away by running ${fleeProd.filter((b) => b.fled === true).length} of ${fleeProd.length} (${per100(fleeProd.filter((b) => b.fled === true).length, fleeProd.length)} per 100)`)
for (const [name, knobs] of Object.entries(ARMS)) {
  await db.exec('begin')
  for (const [k, v] of Object.entries(read.knobs)) await db.query('update public.world_config set value = $1::jsonb where key = $2', [JSON.stringify(v), k])
  for (const [k, v] of Object.entries(knobs)) await db.query('update public.world_config set value = $1::jsonb where key = $2', [JSON.stringify(v), k])
  const out = []
  for (const b of battles) {
    const opts = { a_ai: b.ai?.a ?? 'FIGHT', b_ai: b.ai?.b ?? 'FIGHT', ...(b.a_flee != null ? { a_flee: b.a_flee } : {}), ...(Array.isArray(b.acts) ? { acts: b.acts } : {}) }
    const r = await db.query('select public.tick_fight($1::uuid, $2::jsonb, $3::jsonb, $4::jsonb) as tl', [b.id, JSON.stringify(sheet(b, 'a')), JSON.stringify(sheet(b, 'b')), JSON.stringify(opts)])
    const tl = r.rows[0].tl
    const rolls = tl.e.filter((e) => e[2] === 'X' && e[1] === 0)
    out.push({ flee: opts.a_ai === 'FLEE', cls: b.a?.[0]?.cls ?? '?', out: tl.out, fled: !!tl.r.fled, rolls: rolls.length, first: tl.rc?.a?.[0]?.[1] ?? null, pcts: rolls.map((e) => e[3]) })
  }
  await db.exec('rollback')
  const fl = out.filter((o) => o.flee)
  const first = fl.map((o) => o.first).filter((x) => x != null).sort((a, b) => a - b)
  const all = fl.flatMap((o) => o.pcts).sort((a, b) => a - b)
  const away = fl.filter((o) => o.fled).length
  console.log(`\n${name}`)
  console.log(`  all ${out.length}:          ${show(tally(out, (o) => o.out))}`)
  console.log(`  opened FLEE ${fl.length}:    ${show(tally(fl, (o) => o.out))}   | got away by running ${away} of ${fl.length} (${per100(away, fl.length)} per 100); rolls a fight ${(fl.reduce((n, o) => n + o.rolls, 0) / Math.max(1, fl.length)).toFixed(1)}; chance at the open min ${first[0]} / median ${first[Math.floor(first.length / 2)]} / max ${first[first.length - 1]} %; every roll ${all[0]}..${all[all.length - 1]} %`)
  console.log(`  by her first hull: ${Object.entries(tally(fl, (o) => o.cls)).map(([c, n]) => `${c} ${fl.filter((o) => o.cls === c && o.fled).length}/${n}`).join(', ')}`)
  console.log(`  opened FIGHT ${out.length - fl.length}:   ${show(tally(out.filter((o) => !o.flee), (o) => o.out))}`)
}
await db.close()
