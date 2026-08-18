// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LABEL PLACEMENT — decluttering as a RULE, not as two nudged labels.
//
// THE DEFECT THIS EXISTS TO FIX. Rendered at 390×844 with the sample data, labels were pinned to
// a fixed offset right of their glyph and drawn unconditionally. They overprinted: "Gaivota" and
// "Sevilla" came out as `Gaivotaa illa`, "Marseille" and "Levante" as `MarseiLlevante`, and
// "Napoli" ran off the right edge as `Napol`. At 1280×800 the same code reads perfectly — so this
// is a density problem, and the fix has to be a rule that holds at every width, not a hand-placed
// exception that holds at two.
//
// THE RULE, in three parts:
//
//   1. PRIORITY. Labels are placed in order of how much the player needs them, and a label already
//      placed is never moved for a later one. The order (the coordinator's, mapped onto what this
//      chart actually knows):
//          fleet at sea      > destination port > port your fleet lies in
//        > that fleet's name > port on a route  > every other port
//      A SELECTED thing is placed first and unconditionally: whatever you just tapped is named.
//
//   2. ALTERNATE ANCHORS. Each label tries right, left, above, below — in that order — and then
//      the four diagonals, and takes the first that fits: inside the viewport, clear of every
//      glyph, clear of every label already placed. The four diagonals are not decoration. With the
//      cardinal four alone, MEASURED at 390×844, "Aurora" — the highest-priority label on the
//      chart, a fleet at sea — was boxed in on all four sides by the marks for Lisboa and Sevilla
//      and dropped. Eight positions is what makes the priority table mean anything in a crowd.
//
//   3. DROP. If no side fits, the label is not drawn. It is never drawn badly. The glyph stays
//      exactly where it was and stays tappable, and the detail panel names it — so a dropped label
//      costs a tap, never information.
//
// MEASURING TEXT WITHOUT A DOM. Every label on this chart is set in `font-mono`, and every font in
// that stack is MONOSPACE, so a label's width is `characters × advance × fontSize` exactly — no
// canvas, no measurement pass, and the same answer in a Node test as in a browser. JetBrains Mono's
// advance is 600/1000 em; ADVANCE_EM carries a small margin on top so a fallback face that is a
// touch wider still cannot overlap.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type Point, type ViewBox } from '../../lib/geo'
import type { ChartModel, PortRole } from './chartModel'
import type { MapPort, MapSelection } from './mapTypes'

/** What a label is FOR, which is also how it is coloured. */
export type LabelTone = 'fleet' | 'port-active' | 'port-quiet'

/** Which side of the glyph a label ended up on. Tried in this order: the cardinals the map reads
 *  most naturally, then the diagonals as a last resort before dropping it. */
export const LABEL_SIDES = [
  'right',
  'left',
  'above',
  'below',
  'right-above',
  'right-below',
  'left-above',
  'left-below',
] as const
export type LabelSide = (typeof LABEL_SIDES)[number]

/** A rectangle in chart units. */
export interface Rect {
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

export interface LabelRequest {
  readonly id: string
  readonly text: string
  /** The glyph this label belongs to, in chart units. */
  readonly at: Point
  /** Higher is placed first and never gives way. See LABEL_PRIORITY. */
  readonly priority: number
  readonly tone: LabelTone
  /** Placed even if it collides — used for the selected thing, which must always be named.
   *  It still has to fit inside the viewport; nothing is ever drawn off the edge. */
  readonly force?: boolean
}

export interface PlacedLabel {
  readonly id: string
  readonly text: string
  readonly tone: LabelTone
  readonly side: LabelSide
  /** SVG `x`/`y` for a <text> with dominant-baseline: middle. */
  readonly x: number
  readonly y: number
  readonly anchor: 'start' | 'middle' | 'end'
  /** The box it occupies, in chart units — what the collision rule was decided on, and what a
   *  test can assert against. */
  readonly box: Rect
}

export interface LabelLayoutOptions {
  /** The visible chart rectangle. Nothing is placed outside it. */
  readonly viewBox: ViewBox
  /** Chart units per CSS pixel — every size below is in PIXELS and converted with this, so labels
   *  stay the same size on screen at every zoom. */
  readonly unitsPerPx: number
  readonly fontSizePx?: number
  /** Clearance between a glyph's centre and its label. */
  readonly gapPx?: number
  /** Half the size of the square a glyph is treated as occupying. */
  readonly glyphRadiusPx?: number
  /** Keep-out margin at the viewport edge. */
  readonly edgeInsetPx?: number
}

/**
 * THE PRIORITY TABLE — one place, so "which label wins" is a number you can read rather than a
 * behaviour you have to reverse-engineer from a screenshot.
 */
export const LABEL_PRIORITY = {
  /** Whatever the player just tapped. Placed first, and forced. */
  selected: 1000,
  /** A fleet at sea: the only thing on the chart that is moving. */
  fleetAtSea: 100,
  /** A port a fleet is bound for. */
  destination: 85,
  /** A port one of your fleets lies in. */
  anchorage: 80,
  /** The name of a fleet lying at anchor. */
  fleetDocked: 75,
  /** A port on a fleet's route that is neither its origin's anchorage nor its destination. */
  route: 70,
  /**
   * Everything else. When the chart is crowded, these are what goes.
   *
   * It is a BASE, not a value: a quiet port asks at `quiet + size_tier`, so where two ports matter
   * to you equally the great harbour is named before the roadstead. `size_tier` tops out at 5, so
   * the loudest quiet port scores 15 — still far below `route`, and a port your fleet is actually
   * using can therefore never lose its name to a big port your fleet is nowhere near.
   */
  quiet: 10,
} as const

/** JetBrains Mono's advance is 0.6 em; the extra 6% is headroom for a wider fallback face. */
const ADVANCE_EM = 0.6 * 1.06

const DEFAULTS = { fontSizePx: 10.5, gapPx: 9, glyphRadiusPx: 7, edgeInsetPx: 4 }

function intersects(a: Rect, b: Rect): boolean {
  return (
    a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
  )
}

function containedBy(inner: Rect, outer: Rect): boolean {
  return (
    inner.x >= outer.x &&
    inner.y >= outer.y &&
    inner.x + inner.width <= outer.x + outer.width &&
    inner.y + inner.height <= outer.y + outer.height
  )
}

/** Where a label of this size would sit on each side of a glyph, in the order they are tried. */
function candidates(
  at: Point,
  width: number,
  height: number,
  gap: number,
): { side: LabelSide; x: number; y: number; anchor: PlacedLabel['anchor']; box: Rect }[] {
  const half = height / 2
  const diagonal = gap * 0.7
  return [
    {
      side: 'right',
      x: at.x + gap,
      y: at.y,
      anchor: 'start',
      box: { x: at.x + gap, y: at.y - half, width, height },
    },
    {
      side: 'left',
      x: at.x - gap,
      y: at.y,
      anchor: 'end',
      box: { x: at.x - gap - width, y: at.y - half, width, height },
    },
    {
      side: 'above',
      x: at.x,
      y: at.y - gap - half,
      anchor: 'middle',
      box: { x: at.x - width / 2, y: at.y - gap - height, width, height },
    },
    {
      side: 'below',
      x: at.x,
      y: at.y + gap + half,
      anchor: 'middle',
      box: { x: at.x - width / 2, y: at.y + gap, width, height },
    },
    // The diagonals. The offset is 0.7 × gap on each axis, so the corner clearance works out at
    // very nearly the same distance from the glyph as a cardinal placement.
    {
      side: 'right-above',
      x: at.x + diagonal,
      y: at.y - diagonal - half,
      anchor: 'start',
      box: { x: at.x + diagonal, y: at.y - diagonal - height, width, height },
    },
    {
      side: 'right-below',
      x: at.x + diagonal,
      y: at.y + diagonal + half,
      anchor: 'start',
      box: { x: at.x + diagonal, y: at.y + diagonal, width, height },
    },
    {
      side: 'left-above',
      x: at.x - diagonal,
      y: at.y - diagonal - half,
      anchor: 'end',
      box: { x: at.x - diagonal - width, y: at.y - diagonal - height, width, height },
    },
    {
      side: 'left-below',
      x: at.x - diagonal,
      y: at.y + diagonal + half,
      anchor: 'end',
      box: { x: at.x - diagonal - width, y: at.y + diagonal, width, height },
    },
  ]
}

/**
 * Place as many labels as fit, best first. PURE: same requests + same options → same layout, so a
 * test can assert "no two boxes intersect at 390×844" and mean it.
 */
export function planLabels(
  requests: readonly LabelRequest[],
  options: LabelLayoutOptions,
): PlacedLabel[] {
  const u = options.unitsPerPx
  const fontSize = (options.fontSizePx ?? DEFAULTS.fontSizePx) * u
  const gap = (options.gapPx ?? DEFAULTS.gapPx) * u
  const glyph = (options.glyphRadiusPx ?? DEFAULTS.glyphRadiusPx) * u
  const inset = (options.edgeInsetPx ?? DEFAULTS.edgeInsetPx) * u

  const vb = options.viewBox
  const frame: Rect = {
    x: vb.x + inset,
    y: vb.y + inset,
    width: Math.max(0, vb.width - 2 * inset),
    height: Math.max(0, vb.height - 2 * inset),
  }

  // Every glyph is an obstacle, including glyphs whose own label was dropped: a name may never be
  // printed across another port's mark.
  //
  // EXCEPT ITS OWN. A label belongs to its glyph and is entitled to sit beside it — and the
  // diagonal placements deliberately tuck into the corner, which is inside the glyph's bounding
  // SQUARE while being outside the round mark itself (offset × √2 > radius). Counting a label's
  // own glyph against it is what silently dropped "Aurora" at 390×844 even after the diagonals
  // were added: all eight candidates were rejected, four of them by the fleet's own dot.
  const glyphBoxes: { id: string; rect: Rect }[] = requests.map((r) => ({
    id: r.id,
    rect: { x: r.at.x - glyph, y: r.at.y - glyph, width: 2 * glyph, height: 2 * glyph },
  }))

  // Highest priority first; ties broken by id so the layout is deterministic, not insertion-order
  // dependent (a chart that reshuffles its labels between frames is worse than one that drops them).
  const ordered = [...requests].sort((a, b) => b.priority - a.priority || (a.id < b.id ? -1 : 1))

  const taken: Rect[] = []
  const placed: PlacedLabel[] = []

  for (const request of ordered) {
    const width = request.text.length * ADVANCE_EM * fontSize
    const options_ = candidates(request.at, width, fontSize, gap)

    let chosen: (typeof options_)[number] | null = null
    for (const candidate of options_) {
      if (!containedBy(candidate.box, frame)) continue
      if (!request.force) {
        if (glyphBoxes.some((g) => g.id !== request.id && intersects(candidate.box, g.rect))) continue
        if (taken.some((t) => intersects(candidate.box, t))) continue
      }
      chosen = candidate
      break
    }
    if (!chosen) continue

    taken.push(chosen.box)
    placed.push({
      id: request.id,
      text: request.text,
      tone: request.tone,
      side: chosen.side,
      x: chosen.x,
      y: chosen.y,
      anchor: chosen.anchor,
      box: chosen.box,
    })
  }

  return placed
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT THE CHART ASKS TO HAVE NAMED — the map's domain turned into placement requests.
//
// Separate from planLabels above, which knows only rectangles: this is the only part that knows
// what a fleet or a port is, and it is where LABEL_PRIORITY gets attached to real things.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PORT_PRIORITY: Record<PortRole, number> = {
  destination: LABEL_PRIORITY.destination,
  anchorage: LABEL_PRIORITY.anchorage,
  route: LABEL_PRIORITY.route,
}

/**
 * Every name the chart would like to print, with how badly it wants to print it.
 *
 * `ports` IS THE VISIBLE SET (chartModel.visiblePorts), not the table. That matters now that the
 * table is 214 harbours: asking to name all of them would be ~1,700 candidate placements a frame,
 * almost all of them for ports off the glass, and every one of the survivors would still have to
 * be dropped by the frame test. The set-based rule is unchanged — this just stops it being asked
 * questions whose answer is already known.
 *
 * `showQuietPorts` is the zoom rule of DESIGN §E.5 ("labels ... only for ports the player has
 * visited or has a fleet bound for"): pulled back to the world, a port nothing of yours touches
 * does not even ask. Zoomed in, it asks and usually gets one. Ports your fleets use always ask, at
 * every zoom — they are the reason the tab was opened.
 */
export function mapLabelRequests(
  model: ChartModel,
  ports: readonly MapPort[],
  selection: MapSelection,
  showQuietPorts: boolean,
): LabelRequest[] {
  const requests: LabelRequest[] = []

  for (const port of ports) {
    const role = model.portRoles.get(port.code)
    if (!role && !showQuietPorts) continue
    const selected = selection?.kind === 'port' && selection.code === port.code
    requests.push({
      id: `port:${port.code}`,
      text: port.name,
      at: project(port),
      priority: selected
        ? LABEL_PRIORITY.selected
        : role
          ? PORT_PRIORITY[role]
          : LABEL_PRIORITY.quiet + port.sizeTier,
      tone: role ? 'port-active' : 'port-quiet',
      force: selected,
    })
  }

  for (const fleet of model.fleets) {
    const selected = selection?.kind === 'fleet' && selection.id === fleet.fleet.id
    const atSea = fleet.dockedAtCode === null
    requests.push({
      id: `fleet:${fleet.fleet.id}`,
      text: fleet.fleet.name,
      at: project(fleet.at),
      priority: selected
        ? LABEL_PRIORITY.selected
        : atSea
          ? LABEL_PRIORITY.fleetAtSea
          : LABEL_PRIORITY.fleetDocked,
      tone: 'fleet',
      force: selected,
    })
  }

  return requests
}
