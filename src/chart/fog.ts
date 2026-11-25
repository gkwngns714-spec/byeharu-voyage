import { haversineNm, lonLerp, type LatLon } from '../lib/geo'
import type { ChartModel, FleetOnChart } from './chartModel'
import type { MapPort } from './mapTypes'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FOG (0504, owner 2026-11-25): "The MAP itself will be black, and your fleet will provide a radius that
// will show you nearby map ... the location you've visited will show like a grey map, where you can tab on that
// city to not see the info, but to go there ... where your fleets moved and been will be in grey, showing lands
// partly (transparent)."
//
// THREE STATES, ONE RULE EACH, all read here and nowhere else:
//   · IN SIGHT   within `sightNm` (the server's figure, `world.chart().sight_nm`) of one of her fleets NOW. Clear.
//   · CHARTED    a square of her served bitmap (`cells`: the world in 1 degree squares, written by the server once
//                per arrival), or a square within sight of the part of a voyage she has sailed since (the server
//                writes that part when she arrives: until then it is drawn from the course she holds). Grey.
//   · UNSEEN     everything else. Black.
// A CITY is in sight, KNOWN (charted water under it, or in her logbook: `cities`, the server's list of the harbours
// she has made), or unseen. A known city is drawn under the grey and can be pressed to sail there; its information
// is not shown. An unseen city is not on the map at all.
//
// THE SERVER DECIDES NOTHING BY THIS: no door reads the chart, so a destination named from a list still sails.
// PRICES ARE STILL SERVED FOR EVERY HARBOUR (0504's header): this file is what hides them on the map.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export const FOG_ROWS = 180
export const FOG_COLS = 360
export const FOG_BYTES = (FOG_ROWS * FOG_COLS) / 8

/** What the screen holds of the fog while it is lit for her company. Null everywhere means: no fog, the map as it was. */
export interface ChartFog {
  /** How far each of her fleets sees, in nautical miles (the server's). */
  readonly sightNm: number
  /** Her charted squares: the served bitmap with the part of each voyage under way she has already sailed. */
  readonly cells: Uint8Array
  /** The harbours of her logbook (port codes). */
  readonly cities: ReadonlySet<string>
  /** Where each of her fleets is now. */
  readonly eyes: readonly LatLon[]
}

/** The square a point lies in: the server's own numbering (0504: row = floor(90 - lat), col = floor(lon + 180)). */
export function fogCell(lat: number, lon: number): number {
  const row = Math.min(FOG_ROWS - 1, Math.max(0, Math.floor(90 - lat)))
  const col = ((Math.floor(lon + 180) % FOG_COLS) + FOG_COLS) % FOG_COLS
  return row * FOG_COLS + col
}

export function cellSet(cells: Uint8Array, k: number): boolean {
  return ((cells[k >> 3] ?? 0) >> (k & 7)) % 2 === 1
}

/** The served base64 as bytes; an empty chart when it is absent or not the size the server writes. */
export function decodeFogCells(b64: string | null | undefined): Uint8Array {
  const out = new Uint8Array(FOG_BYTES)
  if (!b64) return out
  try {
    const raw = atob(b64)
    if (raw.length !== FOG_BYTES) return out
    for (let i = 0; i < FOG_BYTES; i++) out[i] = raw.charCodeAt(i)
  } catch {
    return out
  }
  return out
}

/** Every square whose centre lies within `nm` of `at`, and the square under it, set in `cells` (in place). */
function paintPoint(cells: Uint8Array, at: LatLon, nm: number): void {
  const own = fogCell(at.lat, at.lon)
  cells[own >> 3] |= 1 << (own & 7)
  if (!(nm > 0)) return
  const row0 = Math.floor(90 - at.lat)
  const col0 = Math.floor(at.lon + 180)
  const dr = Math.ceil(nm / 60) + 1
  for (let r = Math.max(0, row0 - dr); r <= Math.min(FOG_ROWS - 1, row0 + dr); r++) {
    const lat = 89.5 - r
    const perDeg = 60 * Math.cos((lat * Math.PI) / 180)
    const dc = perDeg * 179 <= nm ? 180 : Math.min(180, Math.ceil(nm / perDeg) + 1)
    for (let c = col0 - dc; c <= col0 + dc; c++) {
      const col = ((c % FOG_COLS) + FOG_COLS) % FOG_COLS
      if (haversineNm(at, { lat, lon: -179.5 + col }) <= nm) {
        const k = r * FOG_COLS + col
        cells[k >> 3] |= 1 << (k & 7)
      }
    }
  }
}

/**
 * THE PART OF EACH VOYAGE UNDER WAY SHE HAS SAILED, as text: its course's vertices up to the piece she is on, then
 * where she is to half a degree. A STRING so that it is the same value until she has moved half a degree: the grey
 * is repainted when it changes, not on every frame of her glide. `trailsOf` reads it back.
 */
export function trailsKey(fleets: readonly FleetOnChart[]): string {
  const out: number[][] = []
  for (const f of fleets) {
    const v = f.voyage
    if (!v) continue
    const pts = [...v.course.slice(0, Math.max(1, Math.min(v.course.length, v.segIndex + 1))), { lat: Math.round(f.at.lat * 2) / 2, lon: Math.round(f.at.lon * 2) / 2 }]
    out.push(pts.flatMap((p) => [p.lat, p.lon]))
  }
  return out.length === 0 ? '' : JSON.stringify(out)
}

export function trailsOf(key: string): LatLon[][] {
  if (key === '') return []
  return (JSON.parse(key) as number[][]).map((flat) => {
    const pts: LatLon[] = []
    for (let i = 0; i + 1 < flat.length; i += 2) pts.push({ lat: flat[i], lon: flat[i + 1] })
    return pts
  })
}

/**
 * HER CHARTED SQUARES NOW: the served bitmap and, for each voyage under way, the squares within sight of what she
 * has sailed of it (sampled every third of the radius, at least 20 nm: the server's own step when it writes the
 * voyage at her arrival). A copy; the served bytes are not touched.
 */
export function liveFogCells(served: Uint8Array, trails: readonly (readonly LatLon[])[], sightNm: number): Uint8Array {
  const cells = new Uint8Array(served)
  const step = Math.max(20, sightNm / 3)
  for (const pts of trails) {
    for (let i = 0; i + 1 < pts.length; i++) {
      const a = pts[i]
      const b = pts[i + 1]
      const n = Math.max(1, Math.min(4000, Math.ceil(haversineNm(a, b) / step)))
      for (let j = 0; j <= n; j++) paintPoint(cells, { lat: a.lat + ((b.lat - a.lat) * j) / n, lon: lonLerp(a.lon, b.lon, j / n) }, sightNm)
    }
  }
  return cells
}

export function inSight(fog: ChartFog, at: LatLon): boolean {
  return fog.eyes.some((e) => haversineNm(e, at) <= fog.sightNm)
}

export function charted(fog: ChartFog, at: LatLon): boolean {
  return cellSet(fog.cells, fogCell(at.lat, at.lon))
}

export type FogState = 'sight' | 'known' | 'unseen'

/** A city under the fog (header). */
export function portFogState(fog: ChartFog, port: Pick<MapPort, 'code' | 'lat' | 'lon'>): FogState {
  if (inSight(fog, port)) return 'sight'
  return fog.cities.has(port.code) || charted(fog, port) ? 'known' : 'unseen'
}

/** The codes of the cities on her map (in sight or known), sorted and joined: a key that moves only when one appears. */
export function knownPortsKey(fog: ChartFog, ports: readonly MapPort[]): string {
  return ports
    .filter((p) => portFogState(fog, p) !== 'unseen')
    .map((p) => p.code)
    .sort()
    .join(' ')
}

/** The ports of `key` (`knownPortsKey`), in the list's own order. */
export function fogPorts<P extends MapPort>(ports: readonly P[], key: string): P[] {
  const known = new Set(key === '' ? [] : key.split(' '))
  return ports.filter((p) => known.has(p.code))
}

/** The model with only the merchants in sight: a hull out of sight is not on her map. */
export function fogModel(model: ChartModel, fog: ChartFog): ChartModel {
  return { ...model, traffic: model.traffic.filter((f) => inSight(fog, f.at)) }
}
