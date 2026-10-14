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
//    a hull half off the glass is still drawn) is on the sheet. With 822 merchants sailing and an
//    opening frame 12° wide, that alone is most of the work this layer used to do for nothing.
// 2. THINNED TO ONE PER CELL. The glass is cut into `SHIP_CELL_PX` squares and each cell draws at
//    most one merchant: the one with the most hulls, then the lower id — hers, stable, so a
//    neighbour arriving cannot swap her out (the `berthSlotOf` lesson, ./liveWorld.ts). A cell is
//    the size of the largest hull, so two merchants that would be drawn on top of each other are
//    drawn as one ship, and two that would not are both drawn. At the globe on a phone this is the
//    difference between 822 marks and the few hundred the glass can show as ships.
// 3. YOURS ARE NEVER THINNED. A fleet of yours is the reason the tab was opened; she is on the
//    sheet at every zoom, whatever stands beside her. The merchants give way to her cell.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, xOnSheet, type ViewBox } from '../lib/geo'
import type { FleetOnChart, TrafficOnChart } from './chartModel'
import { GLYPH } from './glyphs'

/** The cell, in CSS px, inside which the merchants are thinned to one — the largest hull's length
 *  bow to stern, so a cell holds exactly one legible ship. */
export const SHIP_CELL_PX = 2 * GLYPH.hullHalfLength.nau

/** Beyond the view's edge, as a fraction of its width and height — the same slack `portMarks`
 *  keeps, so a mark half off the glass is still drawn. */
const MARGIN = 0.06

export interface ShipMarks {
  /** Your fleets at sea or at an open anchor, on this view. A docked fleet is her port's mark. */
  readonly fleets: readonly FleetOnChart[]
  /** The merchants on this view, thinned to one per cell. */
  readonly traffic: readonly TrafficOnChart[]
}

export function shipMarks(
  fleets: readonly FleetOnChart[],
  traffic: readonly TrafficOnChart[],
  view: ViewBox,
  /** Chart units per CSS pixel — the cell is in pixels, like every size on this chart. */
  unitsPerPx: number,
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

  const cell = Number.isFinite(unitsPerPx) && unitsPerPx > 0 ? SHIP_CELL_PX * unitsPerPx : 0
  const cellOf = (x: number, y: number): string =>
    cell > 0 ? `${Math.floor(x / cell)},${Math.floor(y / cell)}` : `${x},${y}`
  const taken = new Set<string>()
  for (const f of mine) {
    const at = project(f.at)
    taken.add(cellOf(at.x, at.y))
  }

  const kept = new Map<string, TrafficOnChart>()
  for (const t of traffic) {
    if (!onSheet(t.at.lat, t.at.lon)) continue
    const at = project(t.at)
    const key = cellOf(at.x, at.y)
    if (taken.has(key)) continue
    const held = kept.get(key)
    if (!held || outranks(t, held)) kept.set(key, t)
  }
  return { fleets: mine, traffic: [...kept.values()] }
}

/** Which of two merchants in one cell is drawn: the one with more hulls, then the lower id — a
 *  fact about her, never about the order the server listed them in. */
function outranks(a: TrafficOnChart, b: TrafficOnChart): boolean {
  const ha = a.fleet.hulls?.length ?? 0
  const hb = b.fleet.hulls?.length ?? 0
  if (ha !== hb) return ha > hb
  return a.fleet.id < b.fleet.id
}
