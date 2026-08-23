// voyage.reach_from's job — "how far is EVERY port from here, by sea" — priced over the water
// grid instead of the leg graph. One Dijkstra from the origin cell settles the whole ocean, so the
// many-destination question costs ONE search, not 223.
import { readFileSync } from 'node:fs'
import { buildNavGrid, snapToNav, COLS, ROWS, CELL_DEG, cellLat, gcNm } from './pathfind.mjs'

const NM_PER_DEG = 60
const NS = CELL_DEG * NM_PER_DEG
const EW = new Float64Array(ROWS)
for (let r = 0; r < ROWS; r++) EW[r] = CELL_DEG * NM_PER_DEG * Math.cos((cellLat(r) * Math.PI) / 180)
const D = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]

class Heap {
  constructor(cap = 1 << 18) { this.pri = new Float64Array(cap); this.node = new Int32Array(cap); this.n = 0 }
  grow() { const p = new Float64Array(this.pri.length * 2), q = new Int32Array(this.node.length * 2)
           p.set(this.pri); q.set(this.node); this.pri = p; this.node = q }
  push(p, v) { if (this.n === this.pri.length) this.grow()
    let i = this.n++; this.pri[i] = p; this.node[i] = v
    while (i > 0) { const a = (i - 1) >> 1; if (this.pri[a] <= this.pri[i]) break
      const tp = this.pri[a], tn = this.node[a]; this.pri[a] = this.pri[i]; this.node[a] = this.node[i]
      this.pri[i] = tp; this.node[i] = tn; i = a } }
  pop() { const top = this.node[0]
    if (--this.n > 0) { this.pri[0] = this.pri[this.n]; this.node[0] = this.node[this.n]
      let i = 0; for (;;) { const l = 2 * i + 1, r = l + 1; let s = i
        if (l < this.n && this.pri[l] < this.pri[s]) s = l
        if (r < this.n && this.pri[r] < this.pri[s]) s = r
        if (s === i) break
        const tp = this.pri[s], tn = this.node[s]; this.pri[s] = this.pri[i]; this.node[s] = this.node[i]
        this.pri[i] = tp; this.node[i] = tn; i = s } }
    return top } }

/** ONE Dijkstra from a cell. Stops when `targets` have all been settled, else floods the sea. */
function reachFrom(nav, start, targets) {
  const N = COLS * ROWS
  const g = new Float64Array(N).fill(Infinity)
  const seen = new Uint8Array(N)
  const want = new Set(targets)
  const got = new Map()
  const heap = new Heap()
  g[start] = 0
  heap.push(0, start)
  let expanded = 0
  while (heap.n > 0 && got.size < want.size) {
    const cur = heap.pop()
    if (seen[cur]) continue
    seen[cur] = 1
    expanded++
    if (want.has(cur)) got.set(cur, g[cur])
    const row = (cur / COLS) | 0, col = cur - row * COLS
    const ew = EW[row], cost = g[cur]
    for (let k = 0; k < 8; k++) {
      const dr = D[k][0], dc = D[k][1]
      const nrow = row + dr
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = ((col + dc) % COLS + COLS) % COLS
      const next = nrow * COLS + ncol
      if (!nav[next] || seen[next]) continue
      const dy = dr === 0 ? 0 : NS
      const dx = dc === 0 ? 0 : (ew + EW[nrow]) / 2
      const step = dx === 0 ? dy : dy === 0 ? dx : Math.sqrt(dx * dx + dy * dy)
      const t = cost + step
      if (t < g[next]) { g[next] = t; heap.push(t, next) }
    }
  }
  return { got, expanded }
}

const nav = buildNavGrid()
const portsRaw = JSON.parse(readFileSync(new URL('../../data/ports.json', import.meta.url), 'utf8'))
const ports = Array.isArray(portsRaw) ? portsRaw : portsRaw.ports
const cellOf = new Map()
let unsnappable = 0
let snapTotal = 0, snapMax = 0, snapMaxPort = ''
for (const p of ports) {
  const s = snapToNav(nav, p.lat, p.lon)
  if (!s) { unsnappable++; continue }
  cellOf.set(p.id, s.row * COLS + s.col)
  snapTotal += s.snapNm
  if (s.snapNm > snapMax) { snapMax = s.snapNm; snapMaxPort = p.id }
}
console.log(`${ports.length} ports; ${unsnappable} could not be snapped to sailable water`)
console.log(`mean water-snap ${(snapTotal / cellOf.size).toFixed(1)} nm, worst ${snapMax.toFixed(0)} nm at ${snapMaxPort}`)

const targets = [...cellOf.values()]
for (const from of ['lisbon', 'amsterdam', 'goa'].map((id) => ports.find((p) => p.id === id)).filter(Boolean)) {
  const t = performance.now()
  const { got, expanded } = reachFrom(nav, cellOf.get(from.id), targets)
  const ms = performance.now() - t
  console.log(`reach_from(${from.id}) over the WATER: ${ms.toFixed(0)} ms, ${expanded} cells expanded, ${got.size}/${targets.length} ports settled`)
}
