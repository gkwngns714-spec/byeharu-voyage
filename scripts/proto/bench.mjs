// Measures the prototype pathfinder. Every number in docs/DESIGN_RESEARCH_NAVIGATION.md that
// concerns cost comes from a run of this file. `node scripts/proto/bench.mjs`
import { buildNavGrid, findPath, COLS, ROWS } from './pathfind.mjs'
import { buildSeaGrid, findSeaRoute } from '../sea-grid.mjs'

const P = {
  LIS: { lat: 38.71, lon: -9.14, n: 'Lisboa' },
  CAD: { lat: 36.53, lon: -6.29, n: 'Cádiz' },
  NAG: { lat: 32.74, lon: 129.87, n: 'Nagasaki' },
  MNL: { lat: 14.60, lon: 120.98, n: 'Manila' },
  ACA: { lat: 16.85, lon: -99.90, n: 'Acapulco' },
  VER: { lat: 19.19, lon: -96.14, n: 'Veracruz' },
  ALX: { lat: 31.20, lon: 29.92, n: 'Alexandria' },
  ADN: { lat: 12.79, lon: 45.03, n: 'Aden' },
  SSA: { lat: -12.97, lon: -38.51, n: 'Salvador' },
  CAL: { lat: 11.25, lon: 75.78, n: 'Calicut' },
  AMS: { lat: 52.37, lon: 4.90, n: 'Amsterdam' },
  VEN: { lat: 45.44, lon: 12.34, n: 'Venice' },
  ANT: { lat: 51.22, lon: 4.40, n: 'Antwerp' },
  HNL: { lat: 21.31, lon: -157.86, n: 'Honolulu' },
  OPEN_ATL: { lat: 20.0, lon: -40.0, n: 'open Atlantic 20N 40W' },
  OPEN_PAC: { lat: 0.0, lon: -150.0, n: 'open Pacific 0N 150W' },
}

const CASES = [
  ['LIS', 'CAD'], ['LIS', 'AMS'], ['LIS', 'SSA'], ['LIS', 'CAL'],
  ['LIS', 'NAG'], ['LIS', 'MNL'], ['VER', 'ACA'], ['ALX', 'ADN'],
  ['AMS', 'VEN'], ['ANT', 'HNL'], ['LIS', 'OPEN_ATL'], ['LIS', 'OPEN_PAC'],
  ['NAG', 'LIS'],
]

let t = performance.now()
const nav = buildNavGrid()
const navMs = performance.now() - t
let sail = 0
for (let i = 0; i < nav.length; i++) sail += nav[i]

t = performance.now()
const old = buildSeaGrid()
const oldMs = performance.now() - t
let oldWater = 0
for (let i = 0; i < old.length; i++) oldWater += old[i]

console.log(`grid ${COLS}x${ROWS} = ${COLS * ROWS} cells`)
console.log(`  sea-grid.mjs (Arctic open): built in ${oldMs.toFixed(0)} ms, ${oldWater} water cells`)
console.log(`  proto navgrid (ice closed): built in ${navMs.toFixed(0)} ms, ${sail} sailable cells`)
console.log('')
console.log('route                          |  proto ms | expanded |  proto nm |   old ms |    old nm')
console.log('-------------------------------+-----------+----------+-----------+----------+----------')

const scratch = { g: new Float64Array(COLS * ROWS), prev: new Int32Array(COLS * ROWS),
                  seen: new Int32Array(COLS * ROWS), stamp: 0 }
let worst = 0
const rows = []
for (const [a, b] of CASES) {
  const r = findPath(nav, P[a], P[b], scratch)
  const t2 = performance.now()
  const o = findSeaRoute(old, P[a], P[b])
  const oms = performance.now() - t2
  const name = `${P[a].n} → ${P[b].n}`
  worst = Math.max(worst, r ? r.ms : 0)
  rows.push({ name, r, o, oms })
  console.log(
    `${name.padEnd(30)} | ${(r ? r.ms.toFixed(0) : 'null').padStart(9)} | ${(r ? r.expanded : 0).toString().padStart(8)} | ` +
    `${(r ? Math.round(r.nm) : '-').toString().padStart(9)} | ${oms.toFixed(0).padStart(8)} | ${(o ? Math.round(o.nm) : 'null').toString().padStart(8)}`)
}
console.log('')
console.log(`WORST proto search: ${worst.toFixed(0)} ms`)

// Repeat the worst case to see the warm cost (the scratch arrays are reused, the grid is resident).
const HOT = 5
t = performance.now()
for (let i = 0; i < HOT; i++) findPath(nav, P.LIS, P.NAG, scratch)
console.log(`Lisboa → Nagasaki, ${HOT} consecutive searches: ${((performance.now() - t) / HOT).toFixed(0)} ms each`)

// The whole 214-port world, every pair, is what a stored graph buys. Price it.
const ports = JSON.parse(
  (await import('node:fs')).readFileSync(new URL('../../data/ports.json', import.meta.url), 'utf8'))
const list = (Array.isArray(ports) ? ports : ports.ports).map((p) => ({ lat: p.lat, lon: p.lon, n: p.id ?? p.code }))
console.log(`\nports in data/ports.json: ${list.length}`)
t = performance.now()
let n = 0
for (let i = 0; i < 40; i++) {
  const from = list[i % list.length]
  const to = list[(i * 37 + 11) % list.length]
  const r = findPath(nav, from, to, scratch)
  if (r) n++
}
console.log(`40 random port pairs: ${((performance.now() - t) / 40).toFixed(0)} ms each (${n}/40 routable)`)

// Verification is the other half of the story: walking a path and checking every sample is water.
const { segmentIsWater } = await import('./pathfind.mjs')
const long = findPath(nav, P.LIS, P.NAG, scratch)
t = performance.now()
for (let rep = 0; rep < 100; rep++) {
  for (let i = 0; i + 1 < long.path.length; i++) {
    segmentIsWater(nav, long.path[i], long.path[i + 1], i === 0 ? 40 : 0,
      i + 2 === long.path.length ? 40 : 0)
  }
}
console.log(`verifying that same ${long.path.length}-point path is all water: ${((performance.now() - t) / 100).toFixed(2)} ms`)

console.log('\n── the Arctic defect, stated as a diff ─────────────────────────────────────')
for (const { name, r, o } of rows) {
  if (!r || !o) continue
  const d = r.nm / o.nm
  if (d > 1.25) console.log(`  ${name}: old ${Math.round(o.nm)} nm vs proto ${Math.round(r.nm)} nm (x${d.toFixed(2)})`)
}
const arctic = findSeaRoute(old, P.LIS, P.NAG)
console.log(`  sea-grid.mjs's Lisboa→Nagasaki reaches ${Math.max(...arctic.path.map((p) => p[0])).toFixed(1)}°N`)
console.log(`  proto's           Lisboa→Nagasaki reaches ${Math.max(...long.path.map((p) => p[0])).toFixed(1)}°N`)
