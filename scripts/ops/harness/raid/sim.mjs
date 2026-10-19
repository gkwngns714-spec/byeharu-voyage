// sim.mjs <image> <candidates.json> [seeds] — replay production's REAL raids (prod-raids.json: every PIRATES day,
// its fleet's hulls read read-only from prod with world.ship_stats, its recorded raider strength) through
// voyage.fight_resolve, dark table vs fight, for each candidate {name, sql?: file with a replacement body, knobs: {}}.
// Every raid is replayed `seeds` times (seed 0 = its own voyage id; others a derived id), so the shares are not one roll.
import { readFile } from 'node:fs/promises'
import { readFileSync } from 'node:fs'
import { gunzipSync } from 'node:zlib'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
const require = createRequire('C:/Users/gkwng/dev/bv-raid/package.json')
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href)
const [image, candArg, seedsArg = '20'] = process.argv.slice(2)
const SEEDS = Number(seedsArg)
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
const q = async (s, p = []) => (await db.query(s, p)).rows
const ex = JSON.parse(readFileSync('prod-raids.json', 'utf8'))
const F = new Map(ex.fleets.map((f) => [f.id, f]))
const PROD_KNOBS = { armour_turns_pct: 0.5, fight_raider_class: 'xebec', fight_ranges: [['LONG', 0.6], ['LONG', 0.6], ['LONG', 0.6], ['MEDIUM', 0.8], ['MEDIUM', 0.8], ['CLOSE', 1.0]],
  fight_damage_per_attack: 0.7, fight_raider_break: 0.15, fight_evade_per_sighting: 0.03, fight_evade_max: 0.30, fight_standoff_ratio: 2.0, fight_hand_value: 0.15, fight_board_bands: [1.2, 0.7, 0.3] }
const setKnobs = async (k) => { for (const [key, v] of Object.entries(k)) await q(`insert into public.world_config (key, value, description) values ($2, $1::jsonb, 'sim') on conflict (key) do update set value = excluded.value`, [JSON.stringify(v), key]) }
const xc = (await q(`select * from public.ship_classes where code = 'xebec'`))[0]
const BASE = { EVADED: 0, DRIVEN_OFF: 0.02, RANSOM: 0, PLUNDERED: 0.10, STRIPPED: 0.30 }
const crewLost = (ships, o) => ships.reduce((a, s) => a + (s.crew - Math.floor(s.crew * (1 - BASE[o]) + 1e-9)), 0)
const table = (e, r) => { const x = r <= 0 ? 99 : e / r; return x >= 2 ? 'EVADED' : x >= 1.2 ? 'DRIVEN_OFF' : x >= 0.7 ? 'RANSOM' : x >= 0.3 ? 'PLUNDERED' : 'STRIPPED' }
const shipsOf = (f, mod) => f.ships.map((s) => { const o = { id: s.id, name: s.name, tier: s.tier, hull: Number(s.hull), maxd: s.maxd, crew: s.crew,
  attack: Number(s.st.attack), accuracy: Number(s.st.accuracy), reach: Number(s.st.reach), armour: Number(s.st.armour), sighting: Number(s.st.sighting), gear: s.gear }
  return mod ? mod(o) : o })
const raids = ex.raids.filter((r) => F.has(r.fleet))
const sizeOf = (f) => { const c = f.ships.reduce((a, s) => a + s.crew, 0); return f.ships.length > 1 ? 'c multi' : c <= 12 ? 'a single <=12 crew' : 'b single >12 crew' }
await db.exec(`create temp table fx (k int, voyage uuid, day int, r numeric, e numeric, ships jsonb)`)
const seedId = (v, s) => s === 0 ? v : v.slice(0, 24) + ((parseInt(v.slice(24), 16) + s * 7919 * 104729) % 2 ** 48).toString(16).padStart(12, '0')
async function run(list) {
  await db.exec('truncate fx')
  for (let i = 0; i < list.length; i += 1000) await db.query(`insert into fx select * from jsonb_to_recordset($1::jsonb) as x(k int, voyage uuid, day int, r numeric, e numeric, ships jsonb)`,
    [JSON.stringify(list.slice(i, i + 1000).map((x, j) => ({ k: i + j, voyage: x.voyage, day: x.day, r: x.R, e: x.e, ships: x.ships })))])
  return (await q(`select k, j->>'outcome' o, (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(j->'hull_lost') h) hl, (j->>'rounds_fought')::int rf
                     from (select k, voyage.fight_resolve(voyage, day, r, e, ships) j from fx) z order by k`))
}
function agg(rows) {
  const n = rows.length, c = {}; let cl = 0, hl = 0
  for (const r of rows) { c[r.o] = (c[r.o] || 0) + 1; cl += r.crew ? r.crewLost / r.crew : 0; hl += r.hl / r.maxd }
  const p = (x) => +(x / n * 100).toFixed(1)
  return { n, won: p((c.EVADED || 0) + (c.DRIVEN_OFF || 0)), lost: p((c.PLUNDERED || 0) + (c.STRIPPED || 0)), crew: +(cl / n * 100).toFixed(2), hull: +(hl / n * 100).toFixed(2),
    shares: Object.fromEntries(['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED', 'STRIPPED'].map((k) => [k, p(c[k] || 0)])) }
}
const fmt = (a) => `n ${String(a.n).padStart(5)} won ${String(a.won).padStart(5)} lost ${String(a.lost).padStart(5)} crew ${String(a.crew).padStart(6)} hull ${String(a.hull).padStart(6)}  E/D/R/P/S ${Object.values(a.shares).join('/')}`
const darkRows = raids.map((r) => { const f = F.get(r.fleet); const sh = shipsOf(f); const o = table(Number(f.escort_dark), Number(r.raider))
  return { r, f, o, crewLost: crewLost(sh, o), crew: sh.reduce((a, s) => a + s.crew, 0), hl: ({ DRIVEN_OFF: 0.05, PLUNDERED: 0.20 }[o] || 0) * sh.reduce((a, s) => a + s.hull, 0), maxd: sh.reduce((a, s) => a + s.maxd, 0) } })
const recMatch = raids.filter((r) => !r.lit).filter((r) => table(Number(F.get(r.fleet).escort_dark), Number(r.raider)) === r.outcome).length
console.log(`xebec: attack ${xc.attack} acc ${xc.accuracy} reach ${xc.reach} armour ${xc.armour} sight ${xc.sighting} crew ${xc.crew_required} dur ${xc.durability} tier ${xc.tier}`)
console.log(`raids ${raids.length} (dark ${raids.filter((r) => !r.lit).length}, lit ${raids.filter((r) => r.lit).length}); dark table on today's dark escort = recorded outcome on ${recMatch} dark days; seeds ${SEEDS}`)
const bySize = (rows) => { const m = {}; for (const x of rows) (m[sizeOf(x.f)] ||= []).push(x); return Object.entries(m).sort() }
const pad = (s) => ('    ' + s).padEnd(23)
console.log('DARK (table)           ' + fmt(agg(darkRows)))
for (const [k, l] of bySize(darkRows)) console.log(pad(k) + fmt(agg(l)))
const cands = JSON.parse(candArg.trim().startsWith('[') ? candArg : readFileSync(candArg, 'utf8'))
const origBody = (await q(`select pg_get_functiondef('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)'::regprocedure) d`))[0].d
async function fightRows(list, seeds, mod) {
  const items = []
  for (const x of list) for (let s = 0; s < seeds; s++) { const f = F.get(x.fleet); items.push({ x, f, sh: shipsOf(f, mod), voyage: seedId(x.voyage, s), day: x.day, R: Number(x.raider), e: Number(f.escort_lit) }) }
  const res = await run(items.map((i) => ({ voyage: i.voyage, day: i.day, R: i.R, e: i.e, ships: i.sh })))
  return items.map((i, k) => ({ r: i.x, f: i.f, o: res[k].o, rf: res[k].rf, crewLost: crewLost(i.sh, res[k].o), crew: i.sh.reduce((a, s) => a + s.crew, 0), hl: Number(res[k].hl), maxd: i.sh.reduce((a, s) => a + s.maxd, 0) }))
}
for (const c of cands) {
  await db.exec(origBody); await setKnobs(PROD_KNOBS); if (c.knobs) await setKnobs(c.knobs)
  if (c.sql) await db.exec(readFileSync(c.sql, 'utf8').replace(/\r/g, ''))
  if (c.knobs) await setKnobs(c.knobs)
  const t = Date.now(); const rows = await fightRows(raids, SEEDS)
  console.log(`\n=== ${c.name} (${Date.now() - t} ms, ${rows.length} fights)`)
  console.log('LIT  (fight)           ' + fmt(agg(rows)))
  for (const [k, l] of bySize(rows)) console.log(pad(k) + fmt(agg(l)))
  const dl = agg(darkRows), lt = agg(rows)
  console.log(`    BOUNDS: lost ${lt.lost} <= ${(dl.lost + 5).toFixed(1)} ${lt.lost <= dl.lost + 5 ? 'HOLDS' : 'BROKEN'}; crew ${lt.crew} <= ${(dl.crew + 1).toFixed(2)} ${lt.crew <= dl.crew + 1 ? 'HOLDS' : 'BROKEN'}`)
  // the after-check, resampled: a lit window of 16 raids drawn from this mix (each one seed of its fight) against a dark
  // window of 19 drawn from the same mix (the table) — how often would each bound hold, by the chance of the mix alone?
  {
    let rs = 12345; const rnd = () => { rs = (rs * 48271) % 2147483647; return rs / 2147483647 }
    const per = new Map(); for (const x of rows) { const k = x.r.voyage + ':' + x.r.day; if (!per.has(k)) per.set(k, []); per.get(k).push(x) }
    const keys = raids.map((r) => r.voyage + ':' + r.day); let okL = 0, okC = 0, okB = 0; const N = 4000
    const win = (n, pick) => Array.from({ length: n }, pick)
    for (let t = 0; t < N; t++) {
      const a = agg(win(16, () => { const l = per.get(keys[Math.floor(rnd() * keys.length)]); return l[Math.floor(rnd() * l.length)] }))
      const d = agg(win(19, () => darkRows[Math.floor(rnd() * darkRows.length)]))
      const L = a.lost <= d.lost + 5, C = a.crew <= d.crew + 1; okL += L; okC += C; okB += L && C
    }
    // PAIRED: the same 16 raids, lit (one seed) against the dark table on THOSE raids
    const dk = new Map(darkRows.map((x) => [x.r.voyage + ':' + x.r.day, x])); let pL = 0, pC = 0, pB = 0
    for (let t = 0; t < N; t++) { const ks = win(16, () => keys[Math.floor(rnd() * keys.length)]); const a = agg(ks.map((k) => { const l = per.get(k); return l[Math.floor(rnd() * l.length)] })), d = agg(ks.map((k) => dk.get(k)))
      const L = a.lost <= d.lost + 5, C = a.crew <= d.crew + 1; pL += L; pC += C; pB += L && C }
    console.log(`    PAIRED AFTER-CHECK (the same 16 raids, lit vs the dark table on them, ${N}x): lost holds ${(pL / N * 100).toFixed(1)}%, crew ${(pC / N * 100).toFixed(1)}%, both ${(pB / N * 100).toFixed(1)}%`)
    let o = 0
    for (let t = 0; t < N; t++) { const a = agg(win(16, () => darkRows[Math.floor(rnd() * darkRows.length)])), d = agg(win(19, () => darkRows[Math.floor(rnd() * darkRows.length)])); o += a.lost <= d.lost + 5 && a.crew <= d.crew + 1 }
    console.log(`    AFTER-CHECK RESAMPLED (16 lit vs 19 dark from this mix, ${N}x): lost holds ${(okL / N * 100).toFixed(1)}%, crew ${(okC / N * 100).toFixed(1)}%, both ${(okB / N * 100).toFixed(1)}%  [dark table vs itself: both ${(o / N * 100).toFixed(1)}%]`)
  }
  if (c.bands) {
    for (const [nm, key, vals] of (c.bandset === 'crew' ? [['crew', 'crew', [6, 12, 20, 30]]] : [['reach', 'reach', [5, 15, 25, 40, 60]], ['accuracy', 'accuracy', [20, 40, 60, 80]], ['attack x', 'attack', [0, 0.5, 1, 2]]])) {
      const out = []
      for (const v of vals) { const rr = await fightRows(raids, Math.max(4, SEEDS >> 1), (o) => ({ ...o, [key]: key === 'attack' ? o.attack * v : v })); const a = agg(rr); const sm = agg(rr.filter((x) => sizeOf(x.f).startsWith('a'))); out.push(`${v}: won ${a.won} (small ${sm.won}) lost ${a.lost} crew ${a.crew} (small ${sm.crew})`) }
      console.log(`    every hull's ${nm.padEnd(8)} -> ${out.join(' | ')}`)
    }
  }
}
process.exit(0)
