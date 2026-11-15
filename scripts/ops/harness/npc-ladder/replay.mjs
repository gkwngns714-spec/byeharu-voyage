// 0451 REPLAY (local only, never prod): the frozen RAID sheets read from prod by sheets.sql, re-fought by public.tick_fight on the chain's cached
// world with the pirates' hulls AS THEY WERE and AS THE LADDER MAKES THEM, the same seeds (the battles' ids) and the same dice in both arms.
//   node scripts/ops/harness/npc-ladder/replay.mjs <sheets.json>
// What changes on a sheet: a raid by one of the eight Dread fleets has her lead ship (galeoncete or korsan) replaced by a kalyon; a raid by one
// of 0339's ships (ord under 1000) is fought by her rung's hulls (a Raider: one brigantin; Consorts: two xebec; a Corsair: as she was). A new
// hull has her class's figures at npc_ship_level (accuracy and sighting by the level knobs, as the frozen xebecs show), her full complement,
// and the share of health the hull she replaces had. Every other raid is the same sheet in both arms. Prod's own fight knobs are laid over the
// local ones first (rolled back). The local world's secret is not prod's, so a fight here is not prod's own roll of the dice; the read's `out`
// (what prod fought) is printed beside the arms.
import { readFile } from 'node:fs/promises'
import { applyChainCached } from '../../../db/apply-chain.mjs'

const file = process.argv[2]
if (!file) throw new Error('usage: replay.mjs <sheets.json>')
const raw = JSON.parse(await readFile(file, 'utf8'))
const read = raw.battles ? raw : (raw.rows ?? raw)[0].r
const battles = (read.battles ?? []).filter((b) => b.att)
const { db } = await applyChainCached({ log: () => {} })

const lv = Number(read.knobs.npc_ship_level ?? 5)
const accPer = Number(read.knobs.ship_level_accuracy_per_level ?? 1.5)
const sightPer = Number(read.knobs.ship_level_sighting_per_level ?? 0.15)
const cls = Object.fromEntries((await db.query(`select code, tier, durability, crew_required, attack, accuracy, reach, armour, sighting from public.ship_classes where code in ('brigantin', 'xebec', 'kalyon')`)).rows.map((r) => [r.code, r]))
const DREAD = new Set((await db.query(`select h.ord from public.pirate_roster_hulls h where h.class = 'kalyon'`)).rows.map((r) => r.ord))
const rule = async (ord) => (await db.query(`select public.npc_rung_rule('PIRATE', $1, null) as r`, [ord])).rows[0].r
let k = 0
const hull = (code, like, name) => {
  const c = cls[code]
  const share = like && Number(like.maxd) > 0 ? Math.min(1, Number(like.hull) / Number(like.maxd)) : 1
  k += 1
  return { id: `00000000-0451-4000-8000-${String(k).padStart(12, '0')}`, name, tier: c.tier, hull: Math.floor(c.durability * share), maxd: c.durability, crew: c.crew_required,
    attack: Number(c.attack), accuracy: Number(c.accuracy) + (lv - 1) * accPer, reach: Number(c.reach), armour: Number(c.armour), sighting: Number(c.sighting) + (lv - 1) * sightPer,
    boarder_pct: 0, boarder: null, gunner: null, gear: [] }
}
const kinds = {}
for (const b of battles) {
  const ord = b.att.ord
  if (DREAD.has(ord)) { b.how = 'Dread (lead -> kalyon)'; b.nb = [hull('kalyon', b.b[0], b.b[0].name), ...b.b.slice(1)] }
  else if (ord < 1000) {
    const r = await rule(ord)
    if (r === 1) { b.how = "0339's ship -> Raider (brigantin)"; b.nb = [hull('brigantin', b.b[0], b.b[0].name)] }
    else if (r === 3) { b.how = "0339's ship -> Consorts (2 xebec)"; b.nb = [b.b[0], hull('xebec', b.b[0], b.b[0].name + ' 2')] }
    else { b.how = "0339's ship, a Corsair still (xebec)"; b.nb = b.b }
  } else { b.how = 'a roster fleet, as she was'; b.nb = b.b }
  kinds[b.how] = (kinds[b.how] ?? 0) + 1
}
const tally = (rows, f) => rows.reduce((m, r) => ((m[f(r)] = (m[f(r)] ?? 0) + 1), m), {})
const show = (m) => ['PLUNDERED', 'RANSOM', 'DRIVEN_OFF', 'EVADED'].map((x) => `${x} ${m[x] ?? 0}`).join(' / ')

console.log(`sheets: ${battles.length} closed tick RAIDs with a pirate fleet on the attacking side, prod ${read.at} (head ${read.head})`)
console.log(`as prod fought them:   ${show(tally(battles, (b) => b.out))}`)
await db.exec('begin')
for (const [key, v] of Object.entries(read.knobs)) await db.query('update public.world_config set value = $1::jsonb where key = $2', [JSON.stringify(v), key])
const fight = async (b, side) => {
  const opts = { a_ai: b.ai?.a ?? 'FIGHT', b_ai: b.ai?.b ?? 'FIGHT', ...(b.a_flee != null ? { a_flee: b.a_flee } : {}), ...(Array.isArray(b.acts) ? { acts: b.acts } : {}) }
  const r = await db.query('select public.tick_fight($1::uuid, $2::jsonb, $3::jsonb, $4::jsonb) as tl', [b.id, JSON.stringify(b.a), JSON.stringify(side), JSON.stringify(opts)])
  const tl = r.rows[0].tl
  const left = (tl.r?.b ?? []).reduce((n, h) => n + Number(h.hull ?? 0), 0)
  return { out: tl.out, n: tl.n, wrecked: (tl.r?.b ?? []).length > 0 && left <= 0 }
}
for (const b of battles) { b.o = await fight(b, b.b); b.x = b.nb === b.b ? b.o : await fight(b, b.nb) }
await db.exec('rollback')
console.log(`OLD hulls, re-fought:  ${show(tally(battles, (b) => b.o.out))}`)
console.log(`NEW hulls (0451):      ${show(tally(battles, (b) => b.x.out))}`)
console.log('')
for (const how of Object.keys(kinds).sort()) {
  const rows = battles.filter((b) => b.how === how)
  console.log(`${how}: ${rows.length} raid(s)`)
  console.log(`   old ${show(tally(rows, (b) => b.o.out))}`)
  console.log(`   new ${show(tally(rows, (b) => b.x.out))}   | outcome changed in ${rows.filter((b) => b.o.out !== b.x.out).length}`)
}
const secs = (rows, f) => (rows.reduce((n, b) => n + f(b).n, 0) / Math.max(1, rows.length) * 0.6).toFixed(0)
console.log(`\nmean length: old ${secs(battles, (b) => b.o)} s, new ${secs(battles, (b) => b.x)} s`)
await db.close()
