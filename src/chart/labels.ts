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
//      2b. AND THEN IT STEPS OUT, ON A LEADER (2026-10-20, the owner: *"some cities aren't shown
//      their names in certain zoom points. What is the reason? Any way to see the cities all?
//      Without overlapping?"*). Those eight placements all sit one gap from the mark, so two
//      harbours a few pixels apart have eight boxes between them and one of the names used to
//      go. A name that cannot be set beside its mark is now tried again TWICE FURTHER OUT
//      (`LABEL_RINGS`), and when it is set out there a hairline runs from the mark to the name so
//      the reader can see whose it is — the chart-maker's leader line, and the only honest way to
//      name a cluster. MEASURED on the real 214-harbour table: the Mediterranean coast at a phone's
//      width named 11 of its 14 marks and now names all 14; Iberia 6 of 7 and now 7; the opening
//      desktop frame 19 of 23 and now 20. The ring order is why nothing moves that fitted before:
//      every label tries all eight of its snug placements before any label steps out.
//
//      WHAT THE RINGS CANNOT DO, said plainly because the owner asked whether all the cities can
//      be shown. Pulled back to the WHOLE WORLD they gain nothing, and nothing could: of the 24
//      placements each unnamed great harbour has there, 22 to 24 are already filled by a
//      neighbour's name (measured one by one: Antwerp 23, Barcelona 24, Bordeaux 24, Lisbon 22,
//      Lübeck 23, Marseille 24, Seville 23). Ten great harbours stand in Europe's corner of the
//      globe with names wider than the gaps between their marks. One zoom step in and all of them
//      are named — which is the honest answer to "any way to see the cities all".
//
//      THE LEADER IS HELD TO THE SAME PROMISE AS THE NAME. A hairline drawn through another
//      harbour's mark or across another name is the overlap the owner asked us to remove, one
//      line thinner, so a stepped-out placement is rejected if its leader crosses either.
//
//   3. KEEP OUT. A label may not be placed inside a rectangle the screen has declared opaque —
//      its zoom column, its corner panels. THE DEFECT, measured at 390×844: the chart drew
//      `Saint-Malo` from x=309 while the zoom buttons ran from x=334, so the player read `Sain`;
//      `Nantes` began at x=347, entirely under the column, and the 7 px that escaped past its right
//      edge rendered as a bare `s`. The names were not clipped by the viewport — nothing was, and
//      the edge rule above was doing its job — they were BEHIND AN OPAQUE BUTTON, which is a worse
//      failure than dropping them: half a name cannot be told from another port's whole one, so the
//      reader cannot know whether that is Saint-Malo or Santander.
//
//      The rectangles arrive as a PARAMETER, in chart units. This layer must never learn where a
//      screen puts its buttons (src/chart/index.ts's standing rule) — and it must not, because two
//      screens draw this chart and only one of them has any chrome at all. `useChartSurface`
//      measures them off the `CHART_CHROME` marker the gesture handlers already respect, so
//      "opaque chrome over the chart" is declared ONCE and both the gestures and the names read the
//      same declaration.
//
//   4. DROP. If no side fits on any ring, the label is not drawn. It is never drawn badly. The glyph stays
//      exactly where it was and stays tappable, and the detail panel names it — so a dropped label
//      costs a tap, never information. This is why keep-out binds even a FORCED label: a name
//      printed under a button is not a name that was placed, it is a name that was hidden while the
//      chart believed it had been printed.
//
// MEASURING TEXT WITHOUT A DOM. Every label on this chart is set in `font-mono`, and every font in
// that stack is MONOSPACE, so a label's width is `characters × advance × fontSize` exactly — no
// canvas, no measurement pass, and the same answer in a Node test as in a browser. JetBrains Mono's
// advance is 600/1000 em; ADVANCE_EM carries a small margin on top so a fallback face that is a
// touch wider still cannot overlap.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type Point, type ViewBox } from '../lib/geo'
import type { ChartModel, PortRole } from './chartModel'
import { GREAT_PORT_TIER } from './chartView'
import { GLYPH } from './glyphs'
import type { MapPort, MapSelection } from './mapTypes'

/** What a label is FOR, which is also how it is coloured. `sea` (row 90) is a water's name set on
 *  the water itself — ground, not a place to go, and drawn under every other name. `region`
 *  (row 93) is a region's name on its tint, only while the regions filter is on: ground too. */
export type LabelTone = 'fleet' | 'port-active' | 'port-quiet' | 'sea' | 'region'

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
/** `centre` is the one placement a CENTRED request has (see `LabelRequest.placement`): the
 *  name sits on its anchor, and if that does not fit, it is not drawn. */
export type LabelSide = (typeof LABEL_SIDES)[number] | 'centre'

/**
 * HOW FAR OUT A NAME MAY STEP, in multiples of the gap — the rings of the eight sides above, tried
 * in this order (part 2b of the header). The first is the snug ring every name has always been set
 * on; a name only reaches the second because all eight snug placements were taken, and it then
 * carries a leader back to its mark. Two extra rings and not five: 2.3 and 3.8 gaps out is 21 px
 * and 34 px at the chart's 9 px gap, still inside the mark's own touch reach (glyphs.ts
 * `hitRadius`, 38 px), so a stepped-out name is a name you can still put your thumb on.
 */
export const LABEL_RINGS = [1, 2.3, 3.8] as const

/** A rectangle in chart units. */
export interface Rect {
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

/** The hairline from a mark to a name set away from it, in chart units: from the edge of the
 *  glyph to the nearest point of the name's box. Planned here, drawn by LabelsLayer. */
export interface Leader {
  readonly x1: number
  readonly y1: number
  readonly x2: number
  readonly y2: number
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
  /**
   * ROW 90 — how the label is SET, when it is not the default beside-a-glyph name:
   *   `sizePx`     its own type size, in CSS pixels (a great harbour and an ocean are set larger;
   *                default `fontSizePx`).
   *   `spacingEm`  letter-spacing, in em, added to every glyph's advance so the measured box is
   *                the drawn box (default 0).
   *   `placement`  `'beside'` (default) tries the eight sides of a glyph; `'centred'` has NO
   *                glyph — a sea's name sits on its anchor, and it is that one box or nothing.
   *                A centred request registers no glyph obstacle, because there is no glyph.
   */
  readonly sizePx?: number
  readonly spacingEm?: number
  readonly placement?: 'beside' | 'centred'
  /**
   * ROW 105 — how far a CENTRED name may step off its anchor to be set at all, in lines of its
   * own height: 0 (the default, a sea's name) is that one box or nothing; a region's name asks
   * 3, so it is tried on its anchor, then one line up, one down, two up, two down, three up,
   * three down — still at the region's centre to the eye, and no longer dropped for the one
   * harbour mark that happened to stand under its middle (measured at the world view with the
   * names at the marks' priority: 8 of 25 set; with three lines of give, all 25).
   */
  readonly slackLines?: number
  /**
   * 2026-10-18 (the owner: "beside the name show flag") — the NATION CODE whose flag is drawn
   * at the name's outer end (LabelsLayer.tsx) (a harbour's holder, `usePortFlags`). The planned box is widened by
   * FLAG_ADVANCE_EM so the flag is inside the box the collision rule kept clear.
   */
  readonly flag?: string
}

/** A label's flag, in ems of its own type size: the flag's height (its width is 1.5 × that, the
 *  design system's 3:2 box) and the gap after it, before the name. LabelsLayer draws exactly this
 *  box, flag first. 1.25 em is a 13 px flag beside a 10.5 px name (15 px beside a great harbour's
 *  12 px) — at 0.95 em the owner read a 10 px flag as a blank chip; the gap is ~3.5–4 px. */
export const FLAG_HEIGHT_EM = 1.25
export const FLAG_GAP_EM = 0.33
export const FLAG_ADVANCE_EM = FLAG_HEIGHT_EM * 1.5 + FLAG_GAP_EM

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
  /** How it is set — carried through so the layer draws exactly the box that was planned. */
  readonly sizePx: number
  readonly spacingEm: number
  /** Set when the name stepped out past its snug ring (`LABEL_RINGS`): the hairline back to its
   *  mark, so the reader can see whose name it is. Absent for a name set beside its own glyph. */
  readonly leader?: Leader
  /** The nation code whose flag stands at the name's outer end inside the box (see LabelRequest). */
  readonly flag?: string
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
  /**
   * RECTANGLES A NAME MAY NOT BE PLACED IN, in chart units — the screen's own opaque chrome, handed
   * down. Empty by default, because a chart with nothing over it has nothing to avoid. See the
   * KEEP-OUT note in this file's header for what these are and why they arrive as a parameter.
   */
  readonly keepOut?: readonly Rect[]
  /**
   * HOW FAR OUT A NAME MAY STEP, in multiples of the gap — `LABEL_RINGS` by default, and the only
   * reason it is a parameter is that a spec pins it to `[1]` to prove the rule it used to be: the
   * further rings may only ADD names, never move or lose one that fitted snug (tests/map.labels).
   */
  readonly rings?: readonly number[]
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
  /**
   * A REGION'S NAME (row 93), only while the regions filter is on. ABOVE every quiet harbour's
   * name (`quiet + 5` at most) and below every port of yours: the filter was turned on to read
   * the regions, so a region's name is what the player asked for, and a quiet harbour's name is
   * what gives way — the harbour keeps its mark and its tap. Until row 105 (2026-09-18, *"adjust
   * the name of regions and make it at center of each region"*) this sat at 7, under the
   * quietest harbour, and at the world view seventeen of the twenty-five names were dropped for
   * the great harbours' names standing near their centres (measured: 8 of 25 set).
   */
  region: 20,
  /**
   * A SEA'S NAME (row 90). Below the quietest harbour: it is ground, and ground gives way to
   * every place a player might tap. Placed last, it can only ever fill water no name has claimed.
   */
  sea: 5,
} as const

/** JetBrains Mono's advance is 0.6 em; the extra 6% is headroom for a wider fallback face. */
const ADVANCE_EM = 0.6 * 1.06

const DEFAULTS = { fontSizePx: 10.5, gapPx: 9, glyphRadiusPx: 7, edgeInsetPx: 4 }

/** One frozen empty list, so a chart with no chrome over it does not allocate one per frame. */
const EMPTY_KEEP_OUT: readonly Rect[] = []

function intersects(a: Rect, b: Rect): boolean {
  return (
    a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
  )
}

/**
 * Does a hairline cross a rectangle? Liang–Barsky, the standard segment-against-box clip, kept to
 * the question it is asked: a leader line may not run through another harbour's mark or across
 * another name (part 2b of the header).
 */
function segmentHits(line: Leader, r: Rect): boolean {
  const dx = line.x2 - line.x1
  const dy = line.y2 - line.y1
  let t0 = 0
  let t1 = 1
  for (const [p, q] of [
    [-dx, line.x1 - r.x],
    [dx, r.x + r.width - line.x1],
    [-dy, line.y1 - r.y],
    [dy, r.y + r.height - line.y1],
  ]) {
    if (p === 0) {
      // Parallel to this edge: outside it means the segment can never be inside the box.
      if (q < 0) return false
      continue
    }
    const t = q / p
    if (p < 0) {
      if (t > t1) return false
      if (t > t0) t0 = t
    } else {
      if (t < t0) return false
      if (t < t1) t1 = t
    }
  }
  return true
}

/** Is this point inside the rectangle? */
function holds(r: Rect, x: number, y: number): boolean {
  return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height
}

function containedBy(inner: Rect, outer: Rect): boolean {
  return (
    inner.x >= outer.x &&
    inner.y >= outer.y &&
    inner.x + inner.width <= outer.x + outer.width &&
    inner.y + inner.height <= outer.y + outer.height
  )
}

/** One candidate placement: where the text is set, the box it fills, and — on a stepped-out ring
 *  — that it needs a leader back to its mark. */
interface Candidate {
  side: LabelSide
  x: number
  y: number
  anchor: PlacedLabel['anchor']
  box: Rect
  /** Set on every ring but the snug one: the name is away from its glyph and must be joined to it. */
  stepped?: boolean
}

/**
 * Every placement a label may take, in the order they are tried: the eight sides snug against the
 * glyph, then the same eight on each further ring (`LABEL_RINGS`, header part 2b). A whole ring is
 * exhausted before the next is offered, so a name only steps out when it had nowhere to sit.
 */
function candidates(at: Point, width: number, height: number, gap: number, rings: readonly number[]): Candidate[] {
  const out: Candidate[] = []
  for (const [ring, step] of rings.entries()) {
    for (const candidate of sides(at, width, height, gap * step)) {
      out.push(ring === 0 ? candidate : { ...candidate, stepped: true })
    }
  }
  return out
}

/** Where a label of this size would sit on each side of a glyph, in the order they are tried. */
function sides(at: Point, width: number, height: number, gap: number): Candidate[] {
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
 * test can assert "no two boxes intersect at 390×844", or "none of them lands under the zoom
 * column", and mean it.
 */
export function planLabels(
  requests: readonly LabelRequest[],
  options: LabelLayoutOptions,
): PlacedLabel[] {
  const u = options.unitsPerPx
  const gap = (options.gapPx ?? DEFAULTS.gapPx) * u
  const glyph = (options.glyphRadiusPx ?? DEFAULTS.glyphRadiusPx) * u
  const inset = (options.edgeInsetPx ?? DEFAULTS.edgeInsetPx) * u
  const keepOut = options.keepOut ?? EMPTY_KEEP_OUT

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
  //
  // A CENTRED request has no glyph (row 90: a sea's name sits on water), so it registers none.
  const glyphBoxes: { id: string; rect: Rect }[] = requests
    .filter((r) => r.placement !== 'centred')
    .map((r) => ({
      id: r.id,
      rect: { x: r.at.x - glyph, y: r.at.y - glyph, width: 2 * glyph, height: 2 * glyph },
    }))

  // Highest priority first; ties broken by id so the layout is deterministic, not insertion-order
  // dependent (a chart that reshuffles its labels between frames is worse than one that drops them).
  const ordered = [...requests].sort((a, b) => b.priority - a.priority || (a.id < b.id ? -1 : 1))

  const taken: Rect[] = []
  const placed: PlacedLabel[] = []

  // ── TWO PASSES, AND THE REASON IT IS TWO ──────────────────────────────────────────────────────
  // The snug ring is offered to EVERY label before any label is allowed to step out. Measured on
  // the real table when it was one pass over all three rings: the globe named 29 of its 37 marks
  // where the snug-only rule named 30 — a high-priority name stepping out took the water two
  // lower ones needed, and the chart lost a name by gaining a ring. Two passes make the stepped
  // rings strictly an ADDITION: whatever fitted beside its own mark is placed exactly where it
  // was, and the rings only fill water no snug name wanted — the globe keeps its 30, and the coast
  // views, where the owner was reading names, go to every mark on the glass.
  const stranded: LabelRequest[] = []
  for (const request of ordered) if (!set(request, false)) stranded.push(request)
  for (const request of stranded) set(request, true)

  return placed

  /** Place one label, on its snug ring (`stepOut` false) or on the further rings only (true).
   *  Returns whether it was placed. A CENTRED name (a sea's, a region's) has no rings: it is
   *  tried once, in the first pass, on its anchor with its own give. */
  function set(request: LabelRequest, stepOut: boolean): boolean {
    const centredName = request.placement === 'centred'
    if (centredName && stepOut) return false
    const sizePx = request.sizePx ?? options.fontSizePx ?? DEFAULTS.fontSizePx
    const spacingEm = request.spacingEm ?? 0
    const size = sizePx * u
    const width = request.text.length * (ADVANCE_EM + spacingEm) * size + (request.flag ? FLAG_ADVANCE_EM * size : 0)
    const options_ = centredName
      ? centredNear(request.at, width, size, request.slackLines ?? 0)
      : candidates(request.at, width, size, gap, options.rings ?? LABEL_RINGS).filter(
          (c) => (c.stepped ?? false) === stepOut,
        )

    let chosen: (typeof options_)[number] | null = null
    let leader: Leader | null = null
    for (const candidate of options_) {
      if (!containedBy(candidate.box, frame)) continue
      // Keep-out binds EVERY label, forced ones included: `force` overrides tidiness (two names
      // crowding each other), never visibility. A name under an opaque button is invisible, and a
      // chart that believes it printed a name it did not is worse than one that dropped it.
      if (keepOut.some((k) => intersects(candidate.box, k))) continue
      if (!request.force) {
        if (glyphBoxes.some((g) => g.id !== request.id && intersects(candidate.box, g.rect))) continue
        if (taken.some((t) => intersects(candidate.box, t))) continue
      }
      // A STEPPED-OUT NAME IS JOINED TO ITS MARK, and the join is held to the same promise as the
      // name: a hairline through another harbour's mark or across another name is an overlap too.
      const line = candidate.stepped ? leaderOf(request.at, candidate.box, glyph) : null
      if (line && !request.force) {
        // A MARK STANDING ON TOP OF THIS ONE IS NOT SOMETHING THE LEADER CAN AVOID, and it is the
        // very case the rings are for: two harbours a few pixels apart. A mark whose box swallows
        // the line's own starting point — the edge of this label's glyph — is therefore not counted
        // against it; every other mark, and every name, is.
        if (glyphBoxes.some((g) => g.id !== request.id && !holds(g.rect, line.x1, line.y1) && segmentHits(line, g.rect))) continue
        if (taken.some((t) => segmentHits(line, t))) continue
        if (keepOut.some((k) => segmentHits(line, k))) continue
      }
      chosen = candidate
      leader = line
      break
    }
    if (!chosen) return false

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
      sizePx,
      spacingEm,
      ...(request.flag ? { flag: request.flag } : {}),
      ...(leader ? { leader } : {}),
    })
    return true
  }
}

/** The hairline from a mark to a name set away from it: from the glyph's edge to the nearest point
 *  of the name's box, in chart units. Null when the box is so close that there is no line to draw
 *  (nothing that would be hidden under the mark itself is ever drawn). */
function leaderOf(at: Point, box: Rect, glyph: number): Leader | null {
  const x = Math.min(Math.max(at.x, box.x), box.x + box.width)
  const y = Math.min(Math.max(at.y, box.y), box.y + box.height)
  const dx = x - at.x
  const dy = y - at.y
  const d = Math.sqrt(dx * dx + dy * dy)
  if (d <= glyph) return null
  return { x1: at.x + (dx / d) * glyph, y1: at.y + (dy / d) * glyph, x2: x, y2: y }
}

/** A centred label's placements: on its anchor, then — with `slackLines` of give — one line up,
 *  one down, two up, two down… each still centred on the anchor's x. */
function centredNear(at: Point, width: number, height: number, slackLines: number): Candidate[] {
  const out = [centred(at, width, height)]
  for (let n = 1; n <= slackLines; n++) {
    out.push(centred({ x: at.x, y: at.y - n * height * 1.2 }, width, height))
    out.push(centred({ x: at.x, y: at.y + n * height * 1.2 }, width, height))
  }
  return out
}

/** The one placement a centred label has without give: its box centred on the anchor. */
function centred(at: Point, width: number, height: number): Candidate {
  return {
    side: 'centre',
    x: at.x,
    y: at.y,
    anchor: 'middle',
    box: { x: at.x - width / 2, y: at.y - height / 2, width, height },
  }
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
  /** 0143 (docs/INFLUENCE.md D14): each harbour's holder (a NATION CODE, 2026-10-18) by port
   *  code; its flag is drawn beside the name. Null draws the bare names. */
  flags: ReadonlyMap<string, string> | null = null,
): LabelRequest[] {
  const requests: LabelRequest[] = []

  for (const port of ports) {
    const role = model.portRoles.get(port.code)
    // ROW 90: a GREAT harbour asks for its name at every zoom, the globe included — the world
    // view drew 35 marks and named none of them, which is a picture of nowhere. Everything
    // smaller still waits for `showQuietPorts` (DESIGN §E.5's zoom rule).
    const great = port.sizeTier >= GREAT_PORT_TIER
    if (!role && !showQuietPorts && !great) continue
    const selected = selection?.kind === 'port' && selection.code === port.code
    requests.push({
      id: `port:${port.code}`,
      text: port.name,
      // The flag rides with the name at EVERY zoom, the world view included (the owner, 2026-10-18:
      // "beside the name show flag"); its cost is one <symbol> per nation (./flagSymbolStore.ts).
      ...(flags?.has(port.code) ? { flag: flags.get(port.code) } : {}),
      at: project(port),
      priority: selected
        ? LABEL_PRIORITY.selected
        : role
          ? PORT_PRIORITY[role]
          : LABEL_PRIORITY.quiet + port.sizeTier,
      tone: role ? 'port-active' : 'port-quiet',
      force: selected,
      // The hierarchy the marks carry (glyphs.ts's two ramps) reaches the names too: a great
      // harbour's name is set a size up, so at the opening frame Lisbon reads before Setúbal.
      sizePx: great ? GLYPH.greatLabelSize : undefined,
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
