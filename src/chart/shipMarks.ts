// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHICH SHIPS ARE ON THE SHEET — the per-view decision for the fleets, as `portMarks` is for the
// harbours (owner, 2026-10-14: *"show ships when zoomed out"*).
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: THE SHIPS A VIEW DRAWS — every fleet of yours on the glass, and the
//              merchants on the glass thinned to what the glass can hold, at EVERY zoom. A ship is
//              always drawn as a ship (./glyphs.ts `hullPath`); nothing here turns her into a dot.
// WHERE        src/chart, beside `portMarks` in spirit: it reads the model and the view and
//              returns ink decisions, and nothing else may decide which fleet is on the paper.
// SECOND CALLER  `ChartCanvas` is the one caller today, once per copy of the sheet; a spec is the
//              second (tests/map.wrap.spec.ts), which is why it is pure and exported.
// WRONG SHAPE  a density rule that HIDES the merchants at a wide span (the 2026-10-12 "only the
//              major fleets at the globe" rule, retired here) or draws them as embers (row 125's
//              ember, retired with it). The owner wants ships; the thinning below keeps them ships.
//
// ── THE RULE ───────────────────────────────────────────────────────────────────────────────────
// 1. CULLED TO THE WINDOW. Only a ship inside the view (plus the same margin `portMarks` keeps, so
//    a hull half off the glass is still drawn) is on the sheet.
// 2. A SHIP NEVER BLINKS (owner, 2026-10-26: *"ships disappear for a while, then come back"*). The
//    old rule drew one merchant per moving-position cell, so two ships passing each other swapped
//    in and out. Now every merchant in the window is drawn, at every zoom where that is affordable.
//    Only at the widest spans (`THIN_TIERS`, measured: docs/dev-log/2026-10-26-ships-stay.md) are
//    the merchants thinned, and then by a fact about the SHIP alone — `hash(id) % THIN_MOD < n` —
//    so the same ships are kept wherever their neighbours sail. Never a cell contest on position.
//    2026-11-14: the same slot also thins by the GLASS (`THIN_DENSITY`): a phone holding an ocean has no
//    room for every merchant, and the land, your fleets and the battles must be seen first.
// 3. YOURS ARE NEVER THINNED, AND NEITHER IS A CARGO SHIP (0310) OR A NAVY SHIP (0331): she is the thing a player looks for at the
//    widest span. 0326: there may be 500 of her, but only the ones at sea are on the chart (tests/map.cargoload.spec.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, xOnSheet, type ViewBox } from '../lib/geo'
import type { FleetOnChart, TrafficOnChart } from './chartModel'
import { KIND_LOOK, shipKindOf } from './glyphs'

/** Beyond the view's edge, as a fraction of its width and height — the same slack `portMarks`
 *  keeps, so a mark half off the glass is still drawn. */
const MARGIN = 0.06

export interface ShipMarks {
  /** Your fleets at sea or at an open anchor, on this view. A docked fleet is her port's mark. */
  readonly fleets: readonly FleetOnChart[]
  /** The merchants on this view — all of them, or at the widest spans a stable subset. */
  readonly traffic: readonly TrafficOnChart[]
}

export function shipMarks(
  fleets: readonly FleetOnChart[],
  traffic: readonly TrafficOnChart[],
  view: ViewBox,
  /** Chart degrees a CSS pixel on this glass; absent (a spec, a caller with no glass) thins by the span alone. */
  unitsPerPx?: number,
): ShipMarks {
  const padX = view.width * MARGIN
  const padY = view.height * MARGIN
  const minX = view.x - padX
  const maxX = view.x + view.width + padX
  const minY = view.y - padY
  const maxY = view.y + view.height + padY
  const onSheet = (lat: number, lon: number): boolean => {
    const at = project({ lat, lon })
    return at.y >= minY && at.y <= maxY && xOnSheet(at.x, minX, maxX)
  }

  const mine: FleetOnChart[] = []
  for (const f of fleets) if (f.dockedAtCode === null && onSheet(f.at.lat, f.at.lon)) mine.push(f)

  const keep = Math.min(keptOf(view.width), keptAtDensity(unitsPerPx))
  const out: TrafficOnChart[] = []
  for (const t of traffic) {
    if (onSheet(t.at.lat, t.at.lon) && (!KIND_LOOK[shipKindOf(t.merchant)].thin || stableSlot(t.fleet.id) < keep)) out.push(t)
  }
  return { fleets: mine, traffic: out }
}

/** The modulus of the stable thinning slot. */
export const THIN_MOD = 8

/** From this view width (chart degrees) up, only `keep` of every `THIN_MOD` merchants are drawn.
 *  Widest first. Measured, not guessed — see the dev-log. */
export const THIN_TIERS: readonly { readonly fromSpanDeg: number; readonly keep: number }[] = [
  { fromSpanDeg: 250, keep: 6 },
]

/**
 * AND BY THE GLASS (2026-11-14, owner: *"fix the graphics overall, especially map. it is weird"*). The span
 * rule above was measured on a wide glass. A phone holding the same water has a third of the room, and every
 * merchant drawn there buried the land, the capitals, your own fleets and the battles' rings under hulls. So
 * the merchants are also thinned by DENSITY (degrees a pixel), by the same stable slot, so the ones kept are
 * the same ships at every pan and none blinks: all of them on a coast, three in eight once a phone
 * holds 40 degrees, a sea (or a desktop the world), one in eight from a third of a degree a pixel, none from two thirds.
 * Your fleets, and the kinds a player looks for (cargo, navy, pirate), are never in this rule (`thin`).
 */
export const THIN_DENSITY: readonly { readonly fromUnitsPerPx: number; readonly keep: number }[] = [
  { fromUnitsPerPx: 0.66, keep: 0 },
  { fromUnitsPerPx: 0.33, keep: 1 },
  { fromUnitsPerPx: 40 / 390, keep: 3 },
]

function keptAtDensity(unitsPerPx: number | undefined): number {
  if (unitsPerPx === undefined || !Number.isFinite(unitsPerPx)) return THIN_MOD
  for (const t of THIN_DENSITY) if (unitsPerPx >= t.fromUnitsPerPx) return t.keep
  return THIN_MOD
}

function keptOf(spanDeg: number): number {
  for (const t of THIN_TIERS) if (spanDeg >= t.fromSpanDeg) return t.keep
  return THIN_MOD
}

/** A ship's slot in 0..THIN_MOD-1 — FNV-1a of her id, a fact about her and nothing else. */
export function stableSlot(id: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 0x01000193)
  return (h >>> 0) % THIN_MOD
}
