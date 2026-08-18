// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WATER BETWEEN THE PORTS — the whole leg graph, taken from the sea itself.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The routing rule lives in ./sea-grid.mjs: the sea is a 0.25° raster and a route is the shortest
// A* path through water cells. This file applies it to the 214 real harbours and writes the graph.
//
//   pass 1  each port keeps its K nearest neighbours BY SEA          → the coastal chain
//   pass 2  connectivity: the shortest link between separated halves → the ocean crossings
//   pass 3  a leg wherever the chain forces an absurd detour         → the trade roads
//
// Distances are SAILED distances, not straight lines: Lisbon to Cádiz is 248 nm here because Cape
// St Vincent is in the way. The chain asserts every stored distance is >= the great circle between
// the same two coordinates, which this satisfies by construction.
//
// Run: node scripts/build-sea-routes.mjs        Writes: data/sea-routes.json
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { CHANNELS, buildSeaGrid, findSeaRoute, gcNm } from './sea-grid.mjs'

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', 'data')

const K_NEAREST = 6            // neighbours each port keeps
const CANDIDATE_NM = 1300      // straight-line radius inside which a pair is a "neighbour"
const SEARCH_LIMIT_NM = 3000   // give up on a neighbour search past this; pass 2 has no limit
const DETOUR_LIMIT = 2.5       // pass 3 opens a leg when the graph is this much worse than the sea

const ports = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8')).ports
const seas = JSON.parse(readFileSync(join(DATA, 'seas.json'), 'utf8')).seas
const seaById = new Map(seas.map((s) => [s.id, s]))
for (const p of ports) {
  if (!seaById.has(p.sea)) throw new Error(`port ${p.id} names sea "${p.sea}", which is not in seas.json`)
}

const t0 = Date.now()
const water = buildSeaGrid()
console.log(`sea grid           ${water.reduce((s, v) => s + v, 0).toLocaleString()} water cells of ${water.length.toLocaleString()} (${Date.now() - t0} ms)`)

const pairKey = (a, b) => (a < b ? `${a} ${b}` : `${b} ${a}`)
const routes = new Map()
let searches = 0
function routeOf(a, b, limitNm) {
  const k = pairKey(a.id, b.id)
  if (!routes.has(k)) {
    searches++
    routes.set(k, findSeaRoute(water, a, b, { limitNm }))
  }
  return routes.get(k)
}

// ── pass 1: the coastal chain ─────────────────────────────────────────────────────────────────
const candidates = []
for (let i = 0; i < ports.length; i++) {
  for (let j = i + 1; j < ports.length; j++) {
    const gc = gcNm(ports[i].lat, ports[i].lon, ports[j].lat, ports[j].lon)
    if (gc <= CANDIDATE_NM) candidates.push({ a: ports[i], b: ports[j], gc })
  }
}
// Ordered by the SAILED distance, so "nearest" means nearest BY SEA: a town 60 nm away across a
// peninsula is not a neighbour, and the port two days down the coast is.
for (const c of candidates) {
  const r = routeOf(c.a, c.b, SEARCH_LIMIT_NM)
  c.nm = r ? r.nm : Infinity
}
candidates.sort((x, y) => x.nm - y.nm)

const kept = new Map()
const degree = new Map(ports.map((p) => [p.id, 0]))
function keep(a, b, nm, why) {
  const k = pairKey(a.id, b.id)
  if (kept.has(k)) return false
  kept.set(k, { a, b, nm, why })
  degree.set(a.id, degree.get(a.id) + 1)
  degree.set(b.id, degree.get(b.id) + 1)
  return true
}

for (const c of candidates) {
  if (!Number.isFinite(c.nm)) continue
  if (degree.get(c.a.id) >= K_NEAREST && degree.get(c.b.id) >= K_NEAREST) continue
  keep(c.a, c.b, c.nm, 'coastal')
}
console.log(`pass 1             ${kept.size} legs from ${candidates.length} candidates within ${CANDIDATE_NM} nm`)

// ── pass 2: connectivity ──────────────────────────────────────────────────────────────────────
function components() {
  const parent = new Map(ports.map((p) => [p.id, p.id]))
  const find = (x) => {
    while (parent.get(x) !== x) {
      parent.set(x, parent.get(parent.get(x)))
      x = parent.get(x)
    }
    return x
  }
  for (const { a, b } of kept.values()) {
    const ra = find(a.id)
    const rb = find(b.id)
    if (ra !== rb) parent.set(ra, rb)
  }
  const groups = new Map()
  for (const p of ports) {
    const r = find(p.id)
    if (!groups.has(r)) groups.set(r, [])
    groups.get(r).push(p)
  }
  return [...groups.values()].sort((x, y) => y.length - x.length)
}

const crossings = []
for (let guard = 0; guard < 64; guard++) {
  const groups = components()
  if (groups.length === 1) break
  const main = new Set(groups[0].map((p) => p.id))
  let best = null
  for (const p of ports) {
    if (!main.has(p.id)) continue
    for (const q of ports) {
      if (main.has(q.id)) continue
      // The straight line bounds any sea route, so a pair already worse than the best cannot win.
      if (best && gcNm(p.lat, p.lon, q.lat, q.lon) >= best.nm) continue
      const r = routeOf(p, q, Infinity)
      if (!r || (best && r.nm >= best.nm)) continue
      best = { a: p, b: q, nm: r.nm }
    }
  }
  if (!best) {
    console.error('UNREACHABLE — no water joins the main component to:')
    for (const g of groups.slice(1)) console.error('   ', g.map((p) => p.name).join(', '))
    break
  }
  keep(best.a, best.b, best.nm, 'ocean crossing')
  crossings.push(best)
}

// ── pass 3: the trade roads ───────────────────────────────────────────────────────────────────
// A nearest-neighbour graph is a coastal chain, which is right, but it can leave a pair that is
// open water in reality as an absurd detour on the graph. Where the chain is more than
// DETOUR_LIMIT times the sea distance, the leg is opened. Every one is printed.
function shortestFrom(sourceId, adjacency) {
  const dist = new Map([[sourceId, 0]])
  const seen = new Set()
  for (;;) {
    let node = null
    let nodeD = Infinity
    for (const [id, d] of dist) if (!seen.has(id) && d < nodeD) { node = id; nodeD = d }
    if (node === null) break
    seen.add(node)
    for (const [next, nm] of adjacency.get(node) ?? []) {
      if (nodeD + nm < (dist.get(next) ?? Infinity)) dist.set(next, nodeD + nm)
    }
  }
  return dist
}
function adjacencyOf() {
  const adj = new Map(ports.map((p) => [p.id, []]))
  for (const { a, b, nm } of kept.values()) {
    adj.get(a.id).push([b.id, nm])
    adj.get(b.id).push([a.id, nm])
  }
  return adj
}

const shortcuts = []
for (let round = 0; round < 4; round++) {
  const adj = adjacencyOf()
  const distances = new Map(ports.map((p) => [p.id, shortestFrom(p.id, adj)]))
  let added = 0
  for (const c of candidates) {
    if (!Number.isFinite(c.nm)) continue
    if (kept.has(pairKey(c.a.id, c.b.id))) continue
    const overGraph = distances.get(c.a.id).get(c.b.id) ?? Infinity
    if (overGraph <= c.nm * DETOUR_LIMIT) continue
    if (keep(c.a, c.b, c.nm, 'shortcut')) {
      shortcuts.push({ a: c.a, b: c.b, nm: c.nm, was: overGraph })
      added++
    }
  }
  if (added === 0) break
}

// ── hazard, derived from the water the leg crosses, never authored per edge ───────────────────
const PIRATE_SEAS = new Set([
  'mediterranean-sea', 'strait-of-malacca', 'caribbean-sea', 'gulf-of-guinea',
  'south-china-sea', 'gulf-of-aden', 'red-sea', 'persian-gulf', 'arabian-sea',
])
const OPEN_OCEANS = new Set([
  'north-atlantic', 'south-atlantic', 'indian-ocean', 'north-pacific', 'south-pacific',
  'arctic-ocean', 'barents-sea', 'norwegian-sea',
])
function hazardOf(a, b, nm) {
  let h = 1.0
  if (PIRATE_SEAS.has(a.sea) || PIRATE_SEAS.has(b.sea)) h += 0.25
  if (OPEN_OCEANS.has(a.sea) || OPEN_OCEANS.has(b.sea)) h += 0.1
  if (nm > 1000) h += 0.2      // days out of sight of land
  if (nm < 150) h -= 0.2       // a coastal hop, in sight of shelter
  if (a.sea === b.sea && nm < 400) h -= 0.1
  return Math.round(Math.min(2, Math.max(0.6, h)) * 1000) / 1000
}

const legs = [...kept.values()]
  .map(({ a, b, nm, why }) => {
    const [from, to] = a.id < b.id ? [a, b] : [b, a]
    const gc = gcNm(a.lat, a.lon, b.lat, b.lon)
    const sailed = Math.ceil(nm * 10) / 10
    const detour = sailed / gc
    return {
      from: from.id,
      to: to.id,
      nm: sailed,
      gc_nm: Math.round(gc * 10) / 10,
      hazard_mult: hazardOf(a, b, sailed),
      why,
      note:
        why === 'ocean crossing'
          ? `${Math.round(sailed)} nm of open ocean — the only water joining these coasts`
          : detour > 1.15
            ? `${Math.round(sailed)} nm sailed against ${Math.round(gc)} nm straight: the coast is in the way`
            : `${Math.round(sailed)} nm of open water`,
    }
  })
  .sort((x, y) => (x.from === y.from ? x.to.localeCompare(y.to) : x.from.localeCompare(y.from)))

for (const l of legs) {
  if (l.nm < l.gc_nm) throw new Error(`leg ${l.from}-${l.to}: ${l.nm} nm is under the great circle ${l.gc_nm} nm`)
}

// ── report ────────────────────────────────────────────────────────────────────────────────────
const finalGroups = components()
const degrees = [...degree.values()]
const detours = legs.map((l) => l.nm / l.gc_nm)

console.log(`ports              ${ports.length}`)
console.log(`legs               ${legs.length}   (${searches} route searches, ${((Date.now() - t0) / 1000).toFixed(1)} s total)`)
console.log(`components         ${finalGroups.length}${finalGroups.length === 1 ? ' (connected)' : ' — NOT CONNECTED'}`)
console.log(`degree             min ${Math.min(...degrees)}, mean ${(degrees.reduce((s, d) => s + d, 0) / degrees.length).toFixed(1)}, max ${Math.max(...degrees)}`)
console.log(`sailed vs straight mean ${(detours.reduce((s, d) => s + d, 0) / detours.length).toFixed(2)}x, worst ${Math.max(...detours).toFixed(2)}x`)
console.log(`longest leg        ${Math.max(...legs.map((l) => l.nm))} nm`)
console.log(`ocean crossings    ${crossings.length}`)
for (const c of crossings) console.log(`   ${c.a.name} — ${c.b.name}  ${Math.round(c.nm)} nm`)
console.log(`trade roads opened ${shortcuts.length} (the chain was over ${DETOUR_LIMIT}x the sea distance)`)
for (const s of shortcuts.slice(0, 8)) {
  console.log(`   ${s.a.name} — ${s.b.name}  ${Math.round(s.nm)} nm, was ${Math.round(s.was)} nm round the coast`)
}
if (shortcuts.length > 8) console.log(`   … and ${shortcuts.length - 8} more`)

// NEGATIVE CONTROLS. There is no canal in 1550, so these must come out as the long way round —
// printed every run, because a generator that quietly digs Suez is worse than one that fails.
const control = (fromId, toId, expectOverNm) => {
  const a = ports.find((p) => p.id === fromId)
  const b = ports.find((p) => p.id === toId)
  if (!a || !b) return `${fromId}/${toId}: not in the dataset`
  const r = findSeaRoute(water, a, b)
  const straight = Math.round(gcNm(a.lat, a.lon, b.lat, b.lon))
  const ok = r && r.nm > expectOverNm
  return `${a.name} → ${b.name}: ${r ? Math.round(r.nm) + ' nm by sea' : 'no route'} against ${straight} nm straight — ${ok ? 'the long way round ✓' : 'SOMETHING DUG A CANAL ✗'}`
}
console.log('controls           ' + control('alexandria', 'aden', 8000))
console.log('                   ' + control('veracruz', 'acapulco', 8000))

writeFileSync(
  join(DATA, 'sea-routes.json'),
  JSON.stringify(
    {
      $doc: '../docs/WORLD_DATA.md',
      note:
        'GENERATED by scripts/build-sea-routes.mjs — do not hand-edit. Distances are SAILED distances: '
        + 'the shortest path through water on a 0.25° raster of the Natural Earth land polygons, so a leg '
        + 'rounds capes instead of crossing them. The chain asserts every one is >= the great circle.',
      generator: 'scripts/build-sea-routes.mjs',
      knobs: { K_NEAREST, CANDIDATE_NM, SEARCH_LIMIT_NM, DETOUR_LIMIT, CELL_DEG: 0.25 },
      channels: CHANNELS.map((c) => ({ id: c.id, name: c.name })),
      count: legs.length,
      connected: finalGroups.length === 1,
      legs,
    },
    null,
    1,
  ) + '\n',
)
console.log(`\nwrote data/sea-routes.json — ${legs.length} legs`)
