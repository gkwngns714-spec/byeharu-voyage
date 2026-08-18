// DISTANCE AND ROUTING — one authority, pure, no React.
//
// DESIGN.md B.3: distance between two ports is the great-circle (haversine) figure in nautical
// miles, and the server owns it as voyage.gc_distance_nm(). "The client may compute the same number
// for display only" — that is exactly what this module is, and the comment is the licence.
//
// Great-circle ignores continents, so a great-circle number is NEVER used as a route. A route is
// composed only of AUTHORED LEGS (fixtures/v0.ts LEGS), which is why the router can never draw a
// line through Iberia: it has no edge to draw it on. SAIL resolves by Dijkstra over leg
// distance_nm, honouring VIA waypoints as hard intermediate nodes (B.3).

import type { Leg, Port, PortCode } from '../../fixtures/types'

/** B.3 — mean Earth radius in nautical miles. */
export const EARTH_R_NM = 3440.065

const rad = (deg: number): number => (deg * Math.PI) / 180

/** The haversine of B.3, character for character. */
export function gcDistanceNm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dPhi = rad(lat2 - lat1)
  const dLambda = rad(lon2 - lon1)
  const a =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLambda / 2) ** 2
  return 2 * EARTH_R_NM * Math.asin(Math.sqrt(a))
}

/** An adjacency map built once from the ports and the authored legs. */
export interface LegGraph {
  ports: Map<PortCode, Port>
  /** from -> (to -> distance_nm). Both directions of every authored leg. */
  edges: Map<PortCode, Map<PortCode, number>>
  /** Undirected key "AAA|BBB" (sorted) -> the authored leg, for hazard notes. */
  legs: Map<string, Leg>
}

export function legKey(a: PortCode, b: PortCode): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`
}

export function buildGraph(ports: readonly Port[], legs: readonly Leg[]): LegGraph {
  const portMap = new Map<PortCode, Port>(ports.map((p) => [p.code, p]))
  const edges = new Map<PortCode, Map<PortCode, number>>()
  const legMap = new Map<string, Leg>()
  for (const p of ports) edges.set(p.code, new Map())
  for (const leg of legs) {
    const a = portMap.get(leg.from)
    const b = portMap.get(leg.to)
    if (!a || !b) continue
    const d = gcDistanceNm(a.lat, a.lon, b.lat, b.lon)
    edges.get(leg.from)?.set(leg.to, d)
    edges.get(leg.to)?.set(leg.from, d)
    legMap.set(legKey(leg.from, leg.to), leg)
  }
  return { ports: portMap, edges, legs: legMap }
}

/** Distance between two ports that share an authored leg; null if they do not. */
export function legDistanceNm(graph: LegGraph, a: PortCode, b: PortCode): number | null {
  return graph.edges.get(a)?.get(b) ?? null
}

/** Every port reachable from `from` within `withinNm` of great-circle distance, whether or not a
 *  leg connects them. This is the MARKET tab's neighbour set (G.1 percent-of-neighbours). */
export function portsWithin(
  ports: readonly Port[],
  from: PortCode,
  withinNm: number,
): readonly PortCode[] {
  const origin = ports.find((p) => p.code === from)
  if (!origin) return []
  return ports
    .filter((p) => p.code !== from && gcDistanceNm(origin.lat, origin.lon, p.lat, p.lon) <= withinNm)
    .map((p) => p.code)
}

export interface Route {
  /** Ports in order, origin first, destination last. */
  path: readonly PortCode[]
  /** Sum of the leg distances actually sailed. */
  totalNm: number
  /** path.length - 1. */
  legCount: number
}

/** Dijkstra over the leg graph. Returns null when no path of authored legs exists. */
function shortest(graph: LegGraph, from: PortCode, to: PortCode): Route | null {
  if (from === to) return { path: [from], totalNm: 0, legCount: 0 }
  const dist = new Map<PortCode, number>([[from, 0]])
  const prev = new Map<PortCode, PortCode>()
  const settled = new Set<PortCode>()
  // The V0 graph is 12 nodes; a linear scan for the minimum is cheaper than a heap and has no
  // second implementation to keep correct.
  for (;;) {
    let node: PortCode | null = null
    let best = Infinity
    for (const [code, d] of dist) {
      if (!settled.has(code) && d < best) {
        best = d
        node = code
      }
    }
    if (node === null) return null
    if (node === to) break
    settled.add(node)
    for (const [next, d] of graph.edges.get(node) ?? []) {
      if (settled.has(next)) continue
      const candidate = best + d
      if (candidate < (dist.get(next) ?? Infinity)) {
        dist.set(next, candidate)
        prev.set(next, node)
      }
    }
  }
  const path: PortCode[] = [to]
  let cursor = to
  while (cursor !== from) {
    const p = prev.get(cursor)
    if (!p) return null
    path.unshift(p)
    cursor = p
  }
  return { path, totalNm: dist.get(to) ?? 0, legCount: path.length - 1 }
}

/** SAIL's router: origin, optional hard VIA waypoints, destination. Each segment is a shortest
 *  path; the waypoints are nodes the route MUST pass through, in the order given (B.3). */
export function resolveRoute(
  graph: LegGraph,
  from: PortCode,
  to: PortCode,
  via: readonly PortCode[] = [],
): Route | null {
  const stops: PortCode[] = [from, ...via, to]
  const path: PortCode[] = [from]
  let totalNm = 0
  for (let i = 0; i < stops.length - 1; i += 1) {
    const seg = shortest(graph, stops[i], stops[i + 1])
    if (!seg) return null
    totalNm += seg.totalNm
    path.push(...seg.path.slice(1))
  }
  return { path, totalNm, legCount: path.length - 1 }
}

/** Distance already covered along a route, given how far the fleet has run. */
export function positionOnRoute(
  graph: LegGraph,
  path: readonly PortCode[],
  coveredNm: number,
): { fromPort: PortCode; toPort: PortCode; legCoveredNm: number; legTotalNm: number } | null {
  if (path.length < 2) return null
  let remaining = coveredNm
  for (let i = 0; i < path.length - 1; i += 1) {
    const d = legDistanceNm(graph, path[i], path[i + 1]) ?? 0
    if (remaining <= d || i === path.length - 2) {
      return {
        fromPort: path[i],
        toPort: path[i + 1],
        legCoveredNm: Math.min(remaining, d),
        legTotalNm: d,
      }
    }
    remaining -= d
  }
  return null
}

/** Total length of an already-resolved path. */
export function pathLengthNm(graph: LegGraph, path: readonly PortCode[]): number {
  let total = 0
  for (let i = 0; i < path.length - 1; i += 1) total += legDistanceNm(graph, path[i], path[i + 1]) ?? 0
  return total
}
