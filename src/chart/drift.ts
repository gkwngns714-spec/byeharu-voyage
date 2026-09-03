// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHERE TO DRAW HER BETWEEN READS — a finer reading of the server's answer, never a second one
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, OWNER_REQUESTS row 50: *"my ship marker should be updated more frequently"*.
//
// ── WHAT WAS MEASURED ──────────────────────────────────────────────────────────────────────────
// A fleet was put to sea on production and her marker sampled every 600 ms for the whole passage:
//
//     0.0s 304,323 | 1.2s 267,332 | 2.1s 267,332 | 3.2s 267,332 | 4.1s 292,341 | 5.1s 292,341
//     6.2s 292,341 | 7.1s 255,350 | 8.1s 255,350 | 9.2s 255,350 | 10.1s 218,359 | …
//
// Six jumps of 25–68 px in twenty seconds, and three seconds frozen between each. That is the read
// cadence made visible (`AppShell.readIntervalMs` → 3 000 ms), and it is the whole complaint: she
// teleports, and never once looks like she is sailing.
//
// ── THE CONSTRAINT, WHICH IS THE DESIGN ────────────────────────────────────────────────────────
// The ledger sets it and it is right: *"the voyage is settled by a FROZEN speed profile and the
// read is the catch-up, so a faster marker must be a finer INTERPOLATION of the same authority,
// never a second mover."*
//
// The chart had a client mover once. `chartModel.ts`'s header records its deletion: positions were
// a function of `nowMs` through a client copy of the closed form, and a copy of a formula is a
// second author of it. THIS IS NOT THAT, and the difference is a property rather than a promise:
//
//   * It cannot leave the segment the server put her on. `legFrac` is clamped to 1 — the far
//     vertex — so the furthest this file can ever draw her is a point the server itself is about
//     to return. It cannot round a corner, skip a leg, or arrive.
//   * It cannot move her backwards. `legFrac` is clamped below by the served value.
//   * It measures nothing. The leg's length arrives on the wire (0075) and the two vertices are
//     the served course's own. `src/lib/geo`'s great-circle helpers are deliberately NOT used:
//     re-measuring a course the server has already measured is exactly the second mover.
//   * It is thrown away on every read. Three seconds later the server's point replaces it whole,
//     so nothing accumulates and no error can compound.
//
// The rate is composed of served figures only — `(totalNm − sailedNm)` over `(etaMs − readAtMs)`.
// Her `speed_kn` is deliberately NOT used: that is a LIVE reading of the hull (0074's fittings can
// move it mid-voyage) while the voyage is settled against the profile frozen at departure. The two
// can disagree; the remaining-miles-over-remaining-time pair cannot, because it is the server's
// own arrival that defines it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../lib/geo'
import type { MapVoyage } from './mapTypes'

/**
 * THE TWO INSTANTS. `readAtMs` is when the world last answered (`worldStore.readAt`) and `nowMs`
 * is the shell's one clock. Their difference is the only elapsed time this file knows about.
 */
export interface Drift {
  readonly nowMs: number
  readonly readAtMs: number | null
}

/**
 * Where to draw her now: the served point, advanced along the leg she is on by the share of that
 * leg the served clock says she has covered since the read — and never past its end.
 *
 * Returns `voyage.at` unchanged whenever anything is missing or nonsensical, which is the honest
 * lesser answer: a marker that steps is what every build drew until 0075.
 */
export function driftedPoint(voyage: MapVoyage, drift: Drift | null): LatLon {
  if (!drift || drift.readAtMs === null) return voyage.at

  const { segNm, segIndex, legFrac, course, totalNm, sailedNm, etaMs } = voyage
  if (segNm === null || !(segNm > 0)) return voyage.at

  const a = course[segIndex]
  const b = course[segIndex + 1]
  if (!a || !b) return voyage.at

  // The pace, in nm per ms, from the two served ends of her remaining passage. `readAtMs` and not
  // `nowMs` is the denominator's anchor on purpose: the remaining miles were true AT THE READ, so
  // the time they have to run must be measured from the same instant or the pace drifts as the
  // read ages.
  const nmLeft = totalNm - sailedNm
  const msLeft = etaMs - drift.readAtMs
  if (!(nmLeft > 0) || !(msLeft > 0)) return voyage.at

  const elapsedMs = drift.nowMs - drift.readAtMs
  if (!(elapsedMs > 0)) return voyage.at

  const advanced = legFrac + ((nmLeft / msLeft) * elapsedMs) / segNm
  // THE CLAMP IS THE LAW. Never behind where the server put her, never past the vertex it will
  // put her on next. Everything this file is allowed to be rests on this line.
  const frac = Math.max(legFrac, Math.min(1, advanced))
  if (!Number.isFinite(frac)) return voyage.at

  // The SAME linear placement `voyage.position` uses (0047:535-536), on the same two vertices —
  // which migration 0075's self-assert re-derives from the served figures to four decimals, so
  // this is not a claim about the server's arithmetic but a measured fact about it.
  return {
    lat: a.lat + (b.lat - a.lat) * frac,
    lon: a.lon + (b.lon - a.lon) * frac,
  }
}
