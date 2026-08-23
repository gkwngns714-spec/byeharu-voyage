// What does the FIXED 782-leg graph actually answer, compared with the free water path?
// This is the defect measurement: the graph is not merely coarse, it is WRONG, and by how much.
import { readFileSync } from 'node:fs'
import { buildNavGrid, findPath, COLS, ROWS } from './pathfind.mjs'

const routes = JSON.parse(readFileSync(new URL('../../data/sea-routes.json', import.meta.url), 'utf8'))
const portsRaw = JSON.parse(readFileSync(new URL('../../data/ports.json', import.meta.url), 'utf8'))
const ports = Array.isArray(portsRaw) ? portsRaw : portsRaw.ports
const byId = new Map(ports.map((p) => [p.id ?? p.code, p]))

// ── Dijkstra over the stored leg graph — the same answer voyage.reach_from gives ───────────────
const adj = new Map()
for (const l of routes.legs) {
  if (!adj.has(l.from)) adj.set(l.from, [])
  if (!adj.has(l.to)) adj.set(l.to, [])
  adj.get(l.from).push([l.to, l.nm])
  adj.get(l.to).push([l.from, l.nm])
}
function graphRoute(from, to) {
  const dist = new Map([[from, 0]])
  const prev = new Map()
  const done = new Set()
  for (;;) {
    let u = null, best = Infinity
    for (const [k, v] of dist) if (!done.has(k) && v < best) { best = v; u = k }
    if (u === null) break
    if (u === to) break
    done.add(u)
    for (const [v, nm] of adj.get(u) ?? []) {
      if (done.has(v)) continue
      const alt = best + nm
      if (alt < (dist.get(v) ?? Infinity)) { dist.set(v, alt); prev.set(v, u) }
    }
  }
  if (!dist.has(to)) return null
  const nodes = []
  for (let u = to; u !== undefined; u = prev.get(u)) { nodes.push(u); if (u === from) break }
  nodes.reverse()
  return { nm: dist.get(to), nodes }
}

const nav = buildNavGrid()
const scratch = { g: new Float64Array(COLS * ROWS), prev: new Int32Array(COLS * ROWS),
                  seen: new Int32Array(COLS * ROWS), stamp: 0 }

console.log(`graph: ${routes.legs.length} legs over ${adj.size} ports`)
console.log('\n── what the 782-leg graph says vs what the water says ───────────────────────')
console.log('route                      | graph nm | water nm |  ratio | graph hops | max °N on graph route')
console.log('---------------------------+----------+----------+--------+------------+----------------------')

const PAIRS = [
  ['lisbon', 'nagasaki'], ['lisbon', 'manila'], ['lisbon', 'kozhikode'], ['lisbon', 'salvador'],
  ['lisbon', 'cadiz'], ['amsterdam', 'venice'], ['antwerp', 'macau'], ['seville', 'old-goa'],
  ['veracruz', 'acapulco'], ['alexandria', 'aden'], ['london', 'guangzhou'],
]
let worstRatio = 0, worstName = ''
for (const [a, b] of PAIRS) {
  const pa = byId.get(a), pb = byId.get(b)
  if (!pa || !pb) { console.log(`${(a + ' → ' + b).padEnd(26)} | (no such port id)`); continue }
  const gr = graphRoute(a, b)
  const wr = findPath(nav, pa, pb, scratch)
  if (!gr || !wr) { console.log(`${(a + ' → ' + b).padEnd(26)} | graph ${gr ? Math.round(gr.nm) : 'none'} water ${wr ? Math.round(wr.nm) : 'none'}`); continue }
  const maxLat = Math.max(...gr.nodes.map((n) => byId.get(n).lat))
  const ratio = wr.nm / gr.nm
  if (ratio > worstRatio) { worstRatio = ratio; worstName = `${a} → ${b}` }
  console.log(`${(a + ' → ' + b).padEnd(26)} | ${Math.round(gr.nm).toString().padStart(8)} | ${Math.round(wr.nm).toString().padStart(8)} | ${ratio.toFixed(3).padStart(6)} | ${(gr.nodes.length - 1).toString().padStart(10)} | ${maxLat.toFixed(1)}°N via ${gr.nodes[gr.nodes.map((n) => byId.get(n).lat).indexOf(maxLat)]}`)
}
console.log(`\nworst understatement by the graph: x${worstRatio.toFixed(2)} on ${worstName}`)

// ── which stored legs exist only because the Arctic was open? ─────────────────────────────────
console.log('\n── stored legs with NO ice-free route at all ────────────────────────────────')
let n = 0
for (const l of routes.legs) {
  const a = byId.get(l.from), b = byId.get(l.to)
  if (!a || !b) continue
  if (!findPath(nav, a, b, scratch)) {
    n++
    console.log(`  ${l.from} → ${l.to}  (stored ${l.nm} nm, "${l.why ?? ''}")`)
  }
}
console.log(`  ${n} legs`)

// ── the shape defect: a leg keeps its LENGTH but not its LINE ─────────────────────────────────
console.log('\n── legs whose stored straight line crosses land ─────────────────────────────')
const { segmentIsWater } = await import('./pathfind.mjs')
let crossing = 0, tested = 0
for (const l of routes.legs) {
  const a = byId.get(l.from), b = byId.get(l.to)
  if (!a || !b) continue
  tested++
  if (!segmentIsWater(nav, [a.lat, a.lon], [b.lat, b.lon], 40, 40)) crossing++
}
console.log(`  ${crossing} of ${tested} legs are drawn over land when rendered as a straight line`)
