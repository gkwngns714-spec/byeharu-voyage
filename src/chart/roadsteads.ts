// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROADSTEAD, AS INK — where the helper line runs, and where the hollow circle goes.
//
// ── THE CONCEPT (docs/DESIGN_ROADSTEAD.md §1.1) ────────────────────────────────────────────────
// THE ROADSTEAD: the one point of open water a port is reached from. It is NOT an "anchorage" —
// `PortRole = 'anchorage' | …` (./chartModel.ts) already means *one of your fleets lies in this
// port*, and `FleetView.anchor` is a fleet's held sea point. A second meaning for that word inside
// this module is the defect `docs/NO_SPAGHETTI.md` §7B exists to prevent, so the word is not used.
//
// ── WHERE IT LIVES, AND WHY HERE ───────────────────────────────────────────────────────────────
// Beside ./route.ts and ./labels.ts, for the same reason both of them exist: the DECISION about
// what appears on the paper is data, and the layer that renders it is a thin map from that data to
// SVG. It is also the only shape this harness can prove — Playwright compiles JSX in anything a
// spec imports with its own component-testing pragma, so `renderToStaticMarkup` of an app
// component throws (measured 2026-08-25, tests/waters.panel.spec.ts:19-22). A rule that can only
// be proved by rendering is a rule nobody proves.
//
// ── NOTHING HERE COMPUTES A ROADSTEAD ──────────────────────────────────────────────────────────
// Both numbers arrive SERVED, on `MapPort` (see ./mapTypes.ts). The client owns exactly one snap —
// `snapToNav`, for a TAPPED point of open water, in `src/domain/passage` — and a second one on this
// side of the wire would make the line drawn, the course proposed and the endpoint the server
// verifies three answers to one question. `tests/duplication.spec.ts` holds `snapToNav` to one
// importer in `src/` and none under `src/chart/**`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type Point } from '../lib/geo'
import { GLYPH } from './glyphs'
import type { MapPort } from './mapTypes'
import { toPolylineD } from './svgPath'

/** One port's roads, ready for two SVG elements. */
export interface RoadsteadMark {
  /** The port it belongs to — the same `code` `PortsLayer` stamps on its mark. */
  readonly code: string
  /** The dotted helper line, quay → roads, through the chart's one path builder. */
  readonly lineD: string
  /** The roads themselves, projected — where the hollow circle goes. */
  readonly at: Point
  /** How far off the quay they lie, in nautical miles. SERVED; printed by nobody here. */
  readonly nm: number
}

/**
 * WHICH PORTS SHOW THEIR ROADS, AT THIS ZOOM.
 *
 * `ports` is the VISIBLE set (`visiblePorts`) — the same list `PortsLayer` is handed, so a line can
 * never run out of a mark that was not drawn (./chartModel.ts's header: *"a port you can tap but
 * cannot see, or a name floating over a mark that was never drawn, are both the same bug"*).
 *
 * TWO REASONS A PORT DRAWS NOTHING, and neither is a fallback:
 *
 *   1. `roadsteadNm === 0` — the port stands on sailable water and IS its own roadstead
 *      (DESIGN_ROADSTEAD §2.4). Drawing nothing is the CORRECT picture of a zero-length line, not
 *      a degraded one, and the decision is made from the SERVED number rather than from a client
 *      comparison of two floats (§7C: a conditional may choose between two acceptable outcomes).
 *   2. The projected separation is under `GLYPH.roadsteadMinPx`. A line shorter than the mark it
 *      leaves is noise, and zoom is this chart's precision control (./glyphs.ts:96-99).
 */
export function roadsteadMarks(
  ports: readonly MapPort[],
  /** Chart units per CSS pixel — the threshold is in pixels, like every other size on this chart. */
  unitsPerPx: number,
): RoadsteadMark[] {
  const out: RoadsteadMark[] = []
  for (const port of ports) {
    if (port.roadsteadNm === 0) continue
    const quay = project(port)
    const roads = project(port.roadstead)
    const separationPx = Math.hypot(roads.x - quay.x, roads.y - quay.y) / unitsPerPx
    if (separationPx < GLYPH.roadsteadMinPx) continue
    out.push({ code: port.code, lineD: toPolylineD([quay, roads]), at: roads, nm: port.roadsteadNm })
  }
  return out
}
