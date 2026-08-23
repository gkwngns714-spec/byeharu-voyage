// Measures the SERVER side inside PGlite: does the raster fit, and what does it cost to prove a
// submitted path never touches land? `node scripts/proto/bench-verify.mjs`
import { loadPGlite } from './pglite-loader.mjs'
const PGlite = await loadPGlite()
import { readFileSync } from 'node:fs'
import { buildNavGrid, findPath, COLS, ROWS, CELL_DEG } from './pathfind.mjs'

const nav = buildNavGrid()
const db = await new PGlite()
await db.exec(readFileSync(new URL('./raster.sql', import.meta.url), 'utf8'))
await db.exec(readFileSync(new URL('./verify.sql', import.meta.url), 'utf8'))
await db.query(
  `insert into sea.raster (id, cols, rows, cell_deg, cells) values (1, $1, $2, $3, $4)`,
  [COLS, ROWS, CELL_DEG, nav])

// ── How big is the sea, as a thing you have to ship? ──────────────────────────────────────────
const packed = new Uint8Array(Math.ceil(nav.length / 8))
for (let i = 0; i < nav.length; i++) if (nav[i]) packed[i >> 3] |= 1 << (i & 7)
const b64 = Buffer.from(packed).toString('base64')
const sz = await db.query('select pg_column_size(cells) sz from sea.raster')
console.log('── the raster as a shippable artefact ───────────────────────────────────────')
console.log(`  raw, one byte per cell        : ${(nav.length / 1024).toFixed(0)} KiB`)
console.log(`  bit-packed                    : ${(packed.length / 1024).toFixed(0)} KiB`)
console.log(`  bit-packed, base64 (migration): ${(b64.length / 1024).toFixed(0)} KiB of SQL text`)
console.log(`  stored in Postgres (TOAST)    : ${(sz.rows[0].sz / 1024).toFixed(1)} KiB`)

const scratch = { g: new Float64Array(COLS * ROWS), prev: new Int32Array(COLS * ROWS),
                  seen: new Int32Array(COLS * ROWS), stamp: 0 }
const P = {
  LIS: { lat: 38.71, lon: -9.14 }, CAD: { lat: 36.53, lon: -6.29 },
  NAG: { lat: 32.74, lon: 129.87 }, CAL: { lat: 11.25, lon: 75.78 },
  SSA: { lat: -12.97, lon: -38.51 }, AMS: { lat: 52.37, lon: 4.90 },
  VEN: { lat: 45.44, lon: 12.34 }, BCN: { lat: 41.38, lon: 2.18 },
}

console.log('\n── proving a path never touches land, in plpgsql, inside PGlite ─────────────')
console.log('route                  | points |  nm(js) | nm(sql) | navigable | verify ms')
console.log('-----------------------+--------+---------+---------+-----------+----------')
for (const [name, a, b] of [['Lisboa → Cádiz', 'LIS', 'CAD'], ['Lisboa → Amsterdam', 'LIS', 'AMS'],
                            ['Lisboa → Salvador', 'LIS', 'SSA'], ['Amsterdam → Venice', 'AMS', 'VEN'],
                            ['Lisboa → Calicut', 'LIS', 'CAL'], ['Lisboa → Nagasaki', 'LIS', 'NAG']]) {
  const r = findPath(nav, P[a], P[b], scratch)
  const json = JSON.stringify(r.path)
  const REP = 20
  const t = performance.now()
  let ok, nmSql
  for (let i = 0; i < REP; i++) {
    const q = await db.query(
      `select sea.path_is_navigable($1::jsonb, 40, 40) ok, sea.path_nm($1::jsonb) nm`, [json])
    ok = q.rows[0].ok; nmSql = q.rows[0].nm
  }
  const ms = (performance.now() - t) / REP
  console.log(`${name.padEnd(22)} | ${r.path.length.toString().padStart(6)} | ${Math.round(r.nm).toString().padStart(7)} | ${Math.round(nmSql).toString().padStart(7)} | ${String(ok).padStart(9)} | ${ms.toFixed(1).padStart(8)}`)
}

// ── THE ANTI-PROOF. A guard that cannot catch a fleet crossing land is not a guard. ───────────
console.log('\n── non-vacuity: the guard must REFUSE a line across land ────────────────────')
const bad = [
  ['Lisboa → Barcelona straight across Iberia', [[38.71, -9.14], [41.38, 2.18]]],
  ['Alexandria → Aden straight through Arabia', [[31.20, 29.92], [12.79, 45.03]]],
  ['Veracruz → Acapulco straight across Mexico', [[19.19, -96.14], [16.85, -99.90]]],
  ['Lisboa → Nagasaki great circle over Asia', [[38.71, -9.14], [32.74, 129.87]]],
]
for (const [name, path] of bad) {
  const q = await db.query(`select sea.path_is_navigable($1::jsonb, 40, 40) ok`, [JSON.stringify(path)])
  console.log(`  ${String(q.rows[0].ok === false ? 'REFUSED' : '*** ACCEPTED ***').padEnd(16)} ${name}`)
}
const good = findPath(nav, P.LIS, P.BCN, scratch)
const q2 = await db.query(`select sea.path_is_navigable($1::jsonb, 40, 40) ok`, [JSON.stringify(good.path)])
console.log(`  ${String(q2.rows[0].ok ? 'ACCEPTED' : '*** REFUSED ***').padEnd(16)} the real Lisboa → Barcelona, ${Math.round(good.nm)} nm round Gibraltar (${good.path.length} points)`)

// ── And the defect the stored graph has today, priced ─────────────────────────────────────────
console.log('\n── the 782 stored legs, re-measured against the ice-closed raster ───────────')
const routes = JSON.parse(readFileSync(new URL('../../data/sea-routes.json', import.meta.url), 'utf8'))
const ports = JSON.parse(readFileSync(new URL('../../data/ports.json', import.meta.url), 'utf8'))
const byId = new Map((Array.isArray(ports) ? ports : ports.ports).map((p) => [p.id ?? p.code, p]))
let worse = 0, gone = 0, checked = 0, sumRatio = 0, maxRatio = 0, maxLeg = null
for (const leg of routes.legs) {
  const a = byId.get(leg.from), b = byId.get(leg.to)
  if (!a || !b) continue
  const r = findPath(nav, a, b, scratch)
  checked++
  if (!r) { gone++; continue }
  const ratio = r.nm / leg.nm
  sumRatio += ratio
  if (ratio > 1.10) worse++
  if (ratio > maxRatio) { maxRatio = ratio; maxLeg = `${leg.from}→${leg.to} stored ${leg.nm} nm, true ${Math.round(r.nm)} nm` }
}
console.log(`  ${checked} legs re-measured; ${gone} have NO ice-free route at all`)
console.log(`  ${worse} are more than 10% longer than stored (mean ratio ${(sumRatio / (checked - gone)).toFixed(3)})`)
console.log(`  worst: x${maxRatio.toFixed(2)} — ${maxLeg}`)

await db.close()
