// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CLOSED-FORM MOVEMENT — DESIGN §D.2, on the client, as a pure function.
//
// §D.2, verbatim: "A fleet's position is a pure function, not a simulated state."
//
//     progress(t) = clamp( (t − departed_at) × TIME_COMPRESSION × v_fleet / 3600 , 0, total_nm )
//
// with `v_fleet` FROZEN AT DEPARTURE into `voyages.speed_profile`. This module is that formula,
// generalised over a multi-leg profile (each leg carries its own frozen `v_fleet`, so the walk is
// leg by leg instead of one multiplication — the shape of the rule is unchanged).
//
// THE RULE THIS FILE EXISTS TO KEEP: THERE IS NO ANIMATION STATE ANYWHERE ON THIS MAP.
// The chart never accumulates a position, never integrates a delta, never holds "where the dot got
// to". It asks this function, every frame, `where is fleet F at wall-clock instant t?` — so:
//   · Tabbing away for ten minutes and back lands the glyph exactly where it belongs, because
//     nothing was counting while the tab was asleep.
//   · A dropped frame, a throttled timer or a laptop lid cannot make the dot drift.
//   · The client's picture and the server's answer are the same arithmetic on the same row, so
//     they cannot disagree — which is the whole reason §D.2 is written the way it is.
//
// AND IT IS STILL ONLY A PICTURE. Arrival, hazards, cargo and money are decided by the server from
// the database clock (§D.2's `tick_arrivals` / `voyage.settle`). A client clock can be wrong or
// deliberately changed, so nothing here may gate an outcome. `arrived` below means "draw it on the
// quay", not "it has arrived".
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { interpolateGreatCircle, type LatLon } from '../../lib/geo'
import type { Voyage } from './mapTypes'

/** DESIGN §D.1: 1 real minute = 8 voyage-hours; 1 voyage-day = 3 real minutes. */
export const TIME_COMPRESSION = 480

/** How the chart reads a voyage at one instant. Every field is derived; none is stored. */
export interface VoyageProgress {
  /** Sum of the frozen leg distances — the authored length of the voyage. */
  readonly totalNm: number
  readonly sailedNm: number
  readonly remainingNm: number
  /** `sailedNm / totalNm`, in [0, 1]. */
  readonly fraction: number
  /** Index of the leg the fleet is on (the last leg once arrived). */
  readonly legIndex: number
  /** How far along THAT leg, in [0, 1]. */
  readonly legFraction: number
  /** Voyage-hours the whole passage takes at the frozen speeds. */
  readonly totalSimHours: number
  /** Arrival instant, epoch ms — `departedAtMs` plus the real-time equivalent of `totalSimHours`. */
  readonly etaMs: number
  /** Real ms until arrival; 0 once the instant has passed. Display only. */
  readonly remainingMs: number
  /** True once the instant has passed: DRAW IT DOCKED. Not an authority on arrival. */
  readonly arrived: boolean
}

/** Voyage-hours a leg takes at its frozen speed. A non-positive speed is bad data, not a divide by
 *  zero: it yields Infinity, so the fleet visibly stalls at that leg instead of teleporting or
 *  becoming NaN. */
function legHours(distanceNm: number, speedKn: number): number {
  return speedKn > 0 ? distanceNm / speedKn : Infinity
}

/**
 * Where a voyage stands at wall-clock instant `nowMs`. PURE: same (voyage, nowMs) → same result,
 * always, with no hidden state and no reference to the current time. tests/map.voyage.spec.ts
 * pins that.
 */
export function voyageProgress(voyage: Voyage, nowMs: number): VoyageProgress {
  const legs = voyage.legs

  // A voyage with no legs has nowhere to be. Report it arrived rather than emit NaN — a degenerate
  // row must draw as a docked fleet, not as a dot in the Atlantic.
  if (legs.length === 0) {
    return {
      totalNm: 0,
      sailedNm: 0,
      remainingNm: 0,
      fraction: 1,
      legIndex: 0,
      legFraction: 1,
      totalSimHours: 0,
      etaMs: voyage.departedAtMs,
      remainingMs: 0,
      arrived: true,
    }
  }

  let totalNm = 0
  let totalSimHours = 0
  for (const leg of legs) {
    totalNm += leg.distanceNm
    totalSimHours += legHours(leg.distanceNm, leg.speedKn)
  }

  const etaMs = voyage.departedAtMs + (totalSimHours * 3_600_000) / TIME_COMPRESSION

  // Elapsed voyage-hours. Clamped at 0 so a clock skew that puts `now` before departure draws the
  // fleet on the quay it left, never behind it.
  const elapsedRealSeconds = Math.max(0, (nowMs - voyage.departedAtMs) / 1000)
  const elapsedSimHours = (elapsedRealSeconds * TIME_COMPRESSION) / 3600

  if (elapsedSimHours >= totalSimHours) {
    return {
      totalNm,
      sailedNm: totalNm,
      remainingNm: 0,
      fraction: 1,
      legIndex: legs.length - 1,
      legFraction: 1,
      totalSimHours,
      etaMs,
      remainingMs: 0,
      arrived: true,
    }
  }

  let hoursLeft = elapsedSimHours
  let sailedNm = 0
  let legIndex = 0
  let legFraction = 0
  for (let i = 0; i < legs.length; i++) {
    const hours = legHours(legs[i].distanceNm, legs[i].speedKn)
    if (hoursLeft < hours) {
      legIndex = i
      legFraction = hours > 0 ? hoursLeft / hours : 0
      sailedNm += legs[i].distanceNm * legFraction
      break
    }
    hoursLeft -= hours
    sailedNm += legs[i].distanceNm
  }

  return {
    totalNm,
    sailedNm,
    remainingNm: Math.max(0, totalNm - sailedNm),
    fraction: totalNm > 0 ? Math.min(1, sailedNm / totalNm) : 1,
    legIndex,
    legFraction,
    totalSimHours,
    etaMs,
    remainingMs: Math.max(0, etaMs - nowMs),
    arrived: false,
  }
}

/**
 * The fleet's position on the drawn track.
 *
 * `path` is the voyage's waypoints in order — `legs.length + 1` coordinates. The chart draws the
 * GREAT CIRCLE between consecutive waypoints, and this places the glyph at the current leg's
 * fraction of that arc. Distance is the authored `distanceNm` (which may exceed the great circle
 * where the real route detours, §B.3); geometry is the arc. Keeping the two separate is what lets
 * a curated detour take its real time without the line being drawn through Africa.
 */
export function voyagePoint(progress: VoyageProgress, path: readonly LatLon[]): LatLon {
  if (path.length === 0) throw new Error('voyagePoint: empty path')
  if (path.length === 1) return path[0]
  const i = Math.min(progress.legIndex, path.length - 2)
  return interpolateGreatCircle(path[i], path[i + 1], progress.legFraction)
}

/** The port a voyage is bound for, or null if it has no legs. */
export function destinationPortCode(voyage: Voyage): string | null {
  return voyage.legs.length > 0 ? voyage.legs[voyage.legs.length - 1].toPort : null
}

/** Every port code a voyage touches, in order: origin, waypoints, destination. */
export function voyagePortCodes(voyage: Voyage): string[] {
  if (voyage.legs.length === 0) return []
  return [voyage.legs[0].fromPort, ...voyage.legs.map((l) => l.toPort)]
}

/**
 * A countdown, in the game's own words. Minimal, no jargon: `4m`, `1h 12m`, `2d 3h`.
 * "now" once the instant has passed — the chart never shows a negative clock.
 */
export function formatEta(remainingMs: number): string {
  if (!(remainingMs > 0)) return 'now'
  const totalMinutes = Math.ceil(remainingMs / 60_000)
  if (totalMinutes < 60) return `${totalMinutes}m`
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  if (hours < 24) return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`
  const days = Math.floor(hours / 24)
  return `${days}d ${hours % 24}h`
}
