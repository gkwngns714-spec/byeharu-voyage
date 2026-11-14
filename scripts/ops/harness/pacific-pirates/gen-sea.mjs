// gen-sea.mjs: THE WATER OF THE FIVE HUBS OF 0409, measured by the game's own grid and pathfinder (scripts/sea-grid.mjs, src/lib/sea), as
// scripts/build-sea-migration.mjs measures a new place (ADDS_PLACES_ONLY): the roadstead rule, one flood a hub, a course to and from each haunt.
// LOCAL ONLY. Input: a read-only dump of prod's places and roadsteads (ports.json: code, kind, lat, lon, rlat, rlon, sea, nation, ice).
//   node scripts/ops/harness/pacific-pirates/gen-sea.mjs <ports.json> <out.json>
import { readFileSync, writeFileSync } from 'node:fs'
import { buildSeaCarve, COLS, ROWS, CELL_DEG } from '../../../sea-grid.mjs'
import { findPath, floodFrom, floodPathTo, snapToNav, gcNm, cellLat, cellLon } from '../../../../src/lib/sea/index.ts'
export const HUBS = [
  { code: 'MWY', name: 'Midway', lat: 28.21, lon: -177.37, haunts: 6 },
  { code: 'PTC', name: 'Pitcairn', lat: -25.07, lon: -130.1, haunts: 8 },
  { code: 'TDC', name: 'Tristan', lat: -37.07, lon: -12.31, haunts: 8 },
  { code: 'FLO', name: 'Flores', lat: 39.45, lon: -31.13, haunts: 10 },
  { code: 'DGA', name: 'Diego Garcia', lat: -7.31, lon: 72.41, haunts: 8 },
]
const [, , IN, OUT] = process.argv
const ports = JSON.parse(readFileSync(IN, 'utf8'))
const { water: cells, carved } = buildSeaCarve()
const nav = { cols: COLS, rows: ROWS, cellDeg: CELL_DEG, cells }
const carvedCells = new Set(); for (const [, idxs] of carved) for (const k of idxs) carvedCells.add(k)
const r3 = (x) => Number(x.toFixed(3))
const out = { hubs: [] }
const roads = new Map(ports.filter((p) => p.rlat != null).map((p) => [p.code, { lat: p.rlat, lon: p.rlon }]))
for (const h of HUBS) {
  if (ports.some((p) => p.code === h.code)) throw new Error(`${h.code} exists`)
  const s = snapToNav(nav, h.lat, h.lon)
  if (!s) throw new Error(`${h.code}: no water`)
  if (carvedCells.has(s.row * COLS + s.col)) throw new Error(`${h.code}: carved cell`)
  const road = s.snapNm === 0 ? { lat: r3(h.lat), lon: r3(h.lon) } : { lat: r3(cellLat(nav, s.row)), lon: r3(cellLon(nav, s.col)) }
  h.road = road; h.snap = Number(s.snapNm.toFixed(2)); roads.set(h.code, road)
}
for (const h of HUBS) {
  const flood = floodFrom(nav, h.road)
  if (!flood || flood.source.snapNm !== 0) throw new Error(`${h.code}: roadstead not on water`)
  const reaches = {}
  for (const [code, r] of roads) {
    if (code === h.code) continue
    const x = floodPathTo(flood, h.road, r)
    if (!x) throw new Error(`${h.code}->${code}: unreachable`)
    if (x.nm < gcNm(h.road.lat, h.road.lon, r.lat, r.lon) - 0.5) throw new Error(`${h.code}->${code}: under the great circle`)
    reaches[code] = Number(x.nm.toFixed(1))
  }
  const near = ports.filter((p) => p.kind === 'HARBOUR' && !p.ice && p.nation !== 'PIR' && reaches[p.code] != null)
    .sort((a, b) => reaches[a.code] - reaches[b.code] || a.code.localeCompare(b.code)).slice(0, h.haunts)
  const courses = []
  for (const b of near) for (const [f, t] of [[h.code, b.code], [b.code, h.code]]) {
    const p = findPath(nav, roads.get(f), roads.get(t))
    if (!p || p.path.length < 2) throw new Error(`${f}->${t}: no course`)
    courses.push({ from: f, to: t, course: JSON.stringify(p.path.map(([la, lo]) => [Number(la.toFixed(4)), Number(lo.toFixed(4))])), nm: reaches[b.code] })
  }
  out.hubs.push({ code: h.code, name: h.name, lat: h.lat, lon: h.lon, snap: h.snap, rlat: h.road.lat, rlon: h.road.lon, reaches, haunts: near.map((b) => `${b.code}:${reaches[b.code]}:${b.sea}`), courses })
  console.log(h.code, 'road', h.road, 'snap', h.snap, 'keys', Object.keys(reaches).length, near.map((b) => `${b.code}:${reaches[b.code]}:${b.sea}`).join(' '))
}
// the hubs reach each other too (symmetric by rounding from the lower code, as the generator does)
for (const a of out.hubs) for (const b of out.hubs) if (a.code < b.code) b.reaches[a.code] = a.reaches[b.code]
writeFileSync(OUT, JSON.stringify(out))
