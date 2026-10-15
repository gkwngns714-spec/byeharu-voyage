import { instantMs } from '../lib/format'
import { lonLerp } from '../lib/geo'
import type { RosterFleet, RosterVoyage, TrafficFleet } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MERCHANT ROSTER, KEPT HERE AND PLACED IN TIME (0118)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `world.sea_roster` serves every merchant once, then only the fleets whose state moved. Each voyage
// arrives as its FROZEN FACTS — the whole course, each leg's nm, departure and eta — instead of a
// computed position, because computing that position for 822 sailing fleets on every beat
// (`voyage.progress_nm` walks a voyage day by day) made the old window read cost 2–7 s against an
// 8 s timeout.
//
// This file turns a roster row back into the row the chart has always drawn (`TrafficFleet`, the
// `world.sea_traffic` shape: the current segment, re-based to 0, with a position on it). Nothing
// downstream changes. The PLACEMENT is linear in time, from departure to the served eta, along the
// served legs. The eta is the server's and already carries every delay a hazard put on her, so she
// arrives on the instant the server says.

/**
 * One roster row placed at `nowMs`, in the shape the chart draws.
 *
 * 0125 (owner, 2026-10-15: "the merchant npc should also be like me"): SHE IS IN PORT THE MOMENT
 * HER PLACEMENT REACHES THE END OF HER COURSE — the same `placedFrac` that draws her, so she is never
 * drawn at sea while called in port, or the other way round. Bound for a harbour, she is then the
 * row the server serves for a docked merchant: DOCKED in that port, at the roadstead her course ends
 * on (0118: the frozen path ends on the destination's served roadstead), no voyage — and
 * `whereabouts` (domain/fleet/where.ts), the one classifier, reads her as docked with no rule of its
 * own. The server agrees on the instant: `voyage.arrived` (0125) reaches the end of the path exactly
 * at the served eta, and a delay recorded later moves that eta and reaches this roster on its delta.
 * Trading, the lap close and the next departure are still the sweep's (every 15 s).
 */
export function trafficRowAt(f: RosterFleet, nowMs: number): TrafficFleet {
  const v = f.voyage
  if (v && v.to !== null && placedFrac(v, nowMs) === 1) {
    const end = v.course[v.course.length - 1]
    return { ...f, status: 'DOCKED', port: v.to, roadstead: end ?? f.roadstead, anchor: null, voyage: null }
  }
  return { ...f, voyage: v ? voyageAt(v, nowMs) : null }
}

/** How far along her served passage she is at `nowMs`, 0..1 — linear in time from departure to the
 *  served eta. Null for a voyage whose instants are not times. THE one placement rule. */
function placedFrac(v: RosterVoyage, nowMs: number): number | null {
  // Served instants read through the one `instantMs` (null, never NaN, for a byte that is not a time).
  const dep = instantMs(v.departed_at)
  const eta = instantMs(v.eta)
  if (dep === null || eta === null) return null
  return eta > dep ? Math.min(1, Math.max(0, (nowMs - dep) / (eta - dep))) : 1
}

function voyageAt(v: RosterVoyage, nowMs: number): TrafficFleet['voyage'] {
  const legs = v.legs_nm
  const course = v.course
  const frac = placedFrac(v, nowMs)
  if (frac === null || legs.length === 0 || course.length < legs.length + 1) {
    return null
  }
  const total = legs.reduce((a, b) => a + b, 0)
  const done = frac * total
  // THE LEG SHE IS ON — the walk voyage.position makes over the same frozen legs.
  let acc = 0
  let seg = legs.length - 1
  for (let i = 0; i < legs.length; i++) {
    if (done <= acc + legs[i] || i === legs.length - 1) {
      seg = i
      break
    }
    acc += legs[i]
  }
  const segNm = legs[seg]
  const legFrac = segNm > 0 ? Math.min(1, Math.max(0, (done - acc) / segNm)) : 1
  const a = course[seg]
  const b = course[seg + 1]
  return {
    to: v.to,
    dest_point: v.dest_point,
    course: [a, b],
    eta: v.eta,
    departed_at: v.departed_at,
    total_nm: v.total_nm,
    nm_done: done,
    waters: [],
    position: {
      seg_index: 0,
      leg_frac: legFrac,
      nm_done: done,
      total_nm: v.total_nm,
      lat: a[0] + (b[0] - a[0]) * legFrac,
      lon: lonLerp(a[1], b[1], legFrac),
      seg_nm: segNm,
    },
  }
}

/** A delta folded into the kept roster: a served row replaces hers, nobody is dropped. */
export function mergeRoster(
  kept: ReadonlyMap<string, RosterFleet>,
  served: readonly RosterFleet[],
  full: boolean,
): Map<string, RosterFleet> {
  const out = full ? new Map<string, RosterFleet>() : new Map(kept)
  for (const f of served) out.set(f.id, f)
  return out
}

// ── KEPT ACROSS SCREENS AND RELOADS ────────────────────────────────────────────────────────────
// The roster is placed in time from frozen facts, so a kept copy is not a stale picture: painted
// later, every ship is placed at THAT instant. It is therefore kept when MAP is left, and saved so a
// reload or a reopened app paints at once and catches up with one delta. The saved copy is versioned
// and keyed by backend, and it is ignored when its last full read is older than the store's
// full-read interval or its shape version differs.

/** Bump when the saved shape changes. */
const ROSTER_SAVE_VERSION = 1

export interface SavedRoster {
  v: number
  at: string
  fullAtMs: number
  fleets: RosterFleet[]
}

/** Where a backend's roster is saved. */
export function rosterKey(mode: 'local' | 'cloud'): string {
  return `bv.seaRoster.v${ROSTER_SAVE_VERSION}.${mode}`
}

/** A saved roster, or null when there is none, it is malformed, its version differs or it is too old. */
export function readSavedRoster(raw: string | null, nowMs: number, maxAgeMs: number): SavedRoster | null {
  if (!raw) return null
  try {
    const s = JSON.parse(raw) as Partial<SavedRoster>
    if (s.v !== ROSTER_SAVE_VERSION || typeof s.at !== 'string' || typeof s.fullAtMs !== 'number') return null
    if (!Array.isArray(s.fleets) || nowMs - s.fullAtMs > maxAgeMs || instantMs(s.at) === null) return null
    return { v: s.v, at: s.at, fullAtMs: s.fullAtMs, fleets: s.fleets }
  } catch {
    return null
  }
}

/** The text a roster is saved as. */
export function savedRosterText(at: string, fullAtMs: number, roster: ReadonlyMap<string, RosterFleet>): string {
  const s: SavedRoster = { v: ROSTER_SAVE_VERSION, at, fullAtMs, fleets: [...roster.values()] }
  return JSON.stringify(s)
}
