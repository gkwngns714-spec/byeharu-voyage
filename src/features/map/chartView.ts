// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PAN AND ZOOM — the whole of the map's interaction model, as pure arithmetic.
//
// DESIGN §E.5: "This tab has no interactive elements except pan, zoom and folding the two corner
// panels. There is no command, no drag, no target, no context menu." So this file is the complete
// list of things a gesture on the chart can do. Nothing here returns an action, an order or a
// mutation — every function takes a view and returns a view.
//
// The view is stored as CENTRE + HORIZONTAL SPAN rather than as a viewBox, because the surface
// resizes (phone rotates, window drags) and a centre survives that while a box does not: the
// height is re-derived from the new aspect ratio and the player keeps looking at the same water.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import {
  CHART_HEIGHT,
  CHART_WIDTH,
  WORLD_BOUNDS,
  boundsOf,
  fitToViewBox,
  type GeoBounds,
  type LatLon,
  type ViewBox,
} from '../../lib/geo'

/** Where the chart is looking. `spanX` is the width of the view in chart units (degrees of longitude). */
export interface ChartView {
  readonly cx: number
  readonly cy: number
  readonly spanX: number
}

/** The tightest zoom the chart allows: 1.5° of longitude across the surface, roughly a harbour
 *  approach. Tighter than that and the 110m coastline is visibly a polygon, which would be
 *  promising detail the data does not have. */
export const MIN_SPAN_X = 1.5

/** The loosest: the whole world. */
export const MAX_SPAN_X = CHART_WIDTH

/** One press of + or −. A step this size takes ~7 presses to cross the full zoom range, which is
 *  few enough to be usable and many enough not to lose your place. */
export const ZOOM_STEP = 1.6

/** The viewBox a view describes on a surface of the given pixel aspect ratio (width / height). */
export function viewBoxOf(view: ChartView, aspect: number): ViewBox {
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1
  const width = view.spanX
  const height = width / safeAspect
  return { x: view.cx - width / 2, y: view.cy - height / 2, width, height }
}

/** The view that shows exactly a viewBox. */
export function viewOf(box: ViewBox): ChartView {
  return { cx: box.x + box.width / 2, cy: box.y + box.height / 2, spanX: box.width }
}

/** The view that frames a lat/lon rectangle on a surface of the given aspect — the initial view,
 *  and what the "fit" control returns to. Goes through the ONE projection (`fitToViewBox`). */
export function fitView(bounds: GeoBounds, aspect: number, padding = FIT_PADDING): ChartView {
  return viewOf(fitToViewBox(bounds, aspect, padding))
}

/**
 * Keep a view legal: the span inside [MIN_SPAN_X, MAX_SPAN_X], and the visible box inside the
 * world. An axis whose view is wider than the world is CENTRED on it rather than clamped, so
 * zooming out past the globe parks the world in the middle instead of jamming it against an edge.
 */
export function clampView(view: ChartView, aspect: number): ChartView {
  const spanX = Math.min(MAX_SPAN_X, Math.max(MIN_SPAN_X, view.spanX))
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1
  const spanY = spanX / safeAspect

  const halfX = spanX / 2
  const cx =
    spanX >= CHART_WIDTH
      ? 0
      : Math.min(CHART_WIDTH / 2 - halfX, Math.max(-CHART_WIDTH / 2 + halfX, view.cx))

  const halfY = spanY / 2
  const cy =
    spanY >= CHART_HEIGHT
      ? 0
      : Math.min(CHART_HEIGHT / 2 - halfY, Math.max(-CHART_HEIGHT / 2 + halfY, view.cy))

  return { cx, cy, spanX }
}

/**
 * Zoom by `factor` (>1 closer) about a fixed point on the surface, given as fractions of its width
 * and height. The chart point under the pointer stays under the pointer — the property that makes
 * a pinch feel like it is holding the paper rather than moving it.
 */
export function zoomAt(view: ChartView, aspect: number, factor: number, u: number, v: number): ChartView {
  const before = viewBoxOf(view, aspect)
  const anchorX = before.x + u * before.width
  const anchorY = before.y + v * before.height

  const spanX = Math.min(MAX_SPAN_X, Math.max(MIN_SPAN_X, view.spanX / factor))
  const safeAspect = Number.isFinite(aspect) && aspect > 0 ? aspect : 1
  const spanY = spanX / safeAspect

  const x = anchorX - u * spanX
  const y = anchorY - v * spanY
  return clampView({ cx: x + spanX / 2, cy: y + spanY / 2, spanX }, aspect)
}

/** Drag the chart by a distance in CHART UNITS. Positive dx moves the paper right, so the view
 *  centre moves left — the caller converts pixels to units with `unitsPerPixel`. */
export function panBy(view: ChartView, aspect: number, dxUnits: number, dyUnits: number): ChartView {
  return clampView({ cx: view.cx - dxUnits, cy: view.cy - dyUnits, spanX: view.spanX }, aspect)
}

/** Chart units per CSS pixel at this view — the number that keeps glyphs and labels a constant
 *  size on screen while the paper under them scales. */
export function unitsPerPixel(view: ChartView, pixelWidth: number): number {
  return pixelWidth > 0 ? view.spanX / pixelWidth : 1
}

/**
 * How many degrees of longitude are on screen, which is what decides whether a port NOTHING of
 * yours touches asks for a label. DESIGN §E.5 wants labels only once the chart is zoomed in and
 * only for ports that matter, so the world view stays a clean coastline with a few glyphs on it.
 * Above this span, only the ports your fleets are using are named.
 */
export const LABEL_SPAN_LIMIT = 70

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 214 PORTS ON ONE SHEET — the zoom decides how much of the world is drawn at all.
//
// The world is no longer twelve Iberian harbours; it is 214 of them, from Arkhangelsk to Nagasaki,
// joined by 782 sea lanes. Drawn flat, all of it, all the time, that is not a chart — it is a
// texture. So the sheet gets coarser as you pull back, by ONE rule keyed on ONE column.
//
//   the world   (> 45° across)   the 35 great ports          size_tier 5
//   a sea       (> 12° across)   + the 79 middling ones       size_tier 3
//   a coast     (≤ 12° across)   + all 100 small ones         size_tier 2 — and the sea lanes
//
// The counts are the real ones: migration 0003 seeds 35 ports at tier 5, 79 at tier 3 and 100 at
// tier 2. YOUR ports are exempt at every zoom — an anchorage or a destination is drawn whatever
// size it is, because it is the reason the tab was opened (`visiblePorts`, ./chartModel.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Span (degrees of longitude on screen) → the smallest `size_tier` that earns a mark at it.
 *  Ordered tightest first; the first row whose `maxSpanX` covers the view wins. */
export const PORT_TIER_BANDS: readonly { readonly maxSpanX: number; readonly minTier: number }[] = [
  { maxSpanX: 12, minTier: 1 },
  { maxSpanX: 45, minTier: 3 },
  { maxSpanX: Infinity, minTier: 5 },
]

/** The smallest port drawn at this zoom. */
export function minTierForSpan(spanX: number): number {
  for (const band of PORT_TIER_BANDS) if (spanX <= band.maxSpanX) return band.minTier
  return PORT_TIER_BANDS[PORT_TIER_BANDS.length - 1].minTier
}

/**
 * The span at or below which the sea lanes are drawn.
 *
 * §E.5 asks for a quiet chart, and 782 lanes drawn from orbit is precisely the spiderweb that rule
 * exists to prevent. Close in, where a lane answers "can I actually sail there from here", it is
 * worth a hairline. Above this span the layer is not drawn at all — not faded, not thinned: gone.
 *
 * WHY 16 AND NOT 12. MEASURED, in the browser, on the founding position: one Barca at Lisbon frames
 * `OPENING_MIN_SPAN_DEG` = 12°, which `FIT_PADDING` of 0.12 then opens to 12 × 1.24 = 14.88° on the
 * glass. A limit of 12 therefore put the lanes just out of reach of the OPENING view — a new player
 * saw no water routes at all until they zoomed in a step, on the one screen whose whole question is
 * "where can I go from here". 16 covers the opening frame with room to spare and is still a coast,
 * not a hemisphere. (Only lanes between two DRAWN marks are painted, so this never produces a line
 * running off to a port that has no triangle — see `legWebPath`.)
 */
export const LEG_SPAN_LIMIT = 16

/**
 * THE FLOOR ON THE OPENING FRAME, in degrees of longitude.
 *
 * A brand-new house is one Barca lying at Lisboa (§K.1) — ONE point. Framing one point gives a
 * degenerate box, which `clampView` then opens to MIN_SPAN_X: 1.5°, a harbour approach, on which
 * the player sees their own quay and no water, no neighbour and nowhere to go. 12° is about 700 nm
 * across — Lisboa with Porto, Cádiz, Sevilla and the Straits on one sheet, which is the first
 * voyage the game is asking for. It only ever WIDENS a frame; fleets spread wider keep their own.
 */
export const OPENING_MIN_SPAN_DEG = 12

/**
 * The width below which the chart is treated as a phone rather than a small desktop.
 *
 * Matches Tailwind's `sm` breakpoint, which is where the design system already switches (the nav
 * bar goes from 4×2 to 8×1 at the same point), so the map does not introduce a second idea of
 * "narrow". Below it the fleet list opens folded and the panels shrink to fit their content: a
 * corner panel that covers 60% of a 390×844 screen is not a corner panel.
 */
export const COMPACT_WIDTH_PX = 640

/**
 * How much bigger than its contents a view is allowed to be before the frame is judged wasteful.
 *
 * MEASURED, at 390×844. The ports of a working house are a wide east–west strip and a phone
 * is a tall narrow rectangle, so fitting the strip without distortion forces the view to grow in
 * LATITUDE until the aspect matches — and the screenshot showed the result: a chart running from
 * Norway to Sierra Leone with every port squeezed into a band across the middle and the bottom
 * half empty Sahara. The arithmetic:
 *
 *   all your things (24.4° × 16.3°) on a phone → view 30.2° × 65.4°  = 4.0× over-covered
 *   what is moving  (11.6° ×  9.7°) on a phone → view 14.4° × 31.1°  = 3.2× over-covered
 *   all your things (24.4° × 16.3°) on a desktop → view 32.3° × 20.2° = 1.3× over-covered
 *
 * A limit of 2.2 therefore falls back to the action on a phone (halving the span, so everything is
 * ~2× larger) and changes NOTHING on a desktop, where the wide frame was already right.
 */
export const OVER_COVERAGE_LIMIT = 2.2

/** The padding `fitView` and `openingBounds` agree on. */
export const FIT_PADDING = 0.12

/** How many times larger than `bounds` the fitted view would be, on its worst axis. */
function overCoverage(bounds: GeoBounds, aspect: number): number {
  const box = fitToViewBox(bounds, aspect, FIT_PADDING)
  const contentWidth = Math.max(bounds.maxLon - bounds.minLon, 0.05)
  const contentHeight = Math.max(bounds.maxLat - bounds.minLat, 0.05)
  return Math.max(box.width / contentWidth, box.height / contentHeight)
}

/** Widen a rectangle about its centre until it is at least `minSpan` across (and half that tall,
 *  which is the same ground north–south). Never narrows one. */
function atLeast(bounds: GeoBounds, minSpan: number): GeoBounds {
  const growX = Math.max(0, minSpan - (bounds.maxLon - bounds.minLon)) / 2
  const growY = Math.max(0, minSpan / 2 - (bounds.maxLat - bounds.minLat)) / 2
  return {
    minLon: bounds.minLon - growX,
    maxLon: bounds.maxLon + growX,
    minLat: bounds.minLat - growY,
    maxLat: bounds.maxLat + growY,
  }
}

/**
 * THE OPENING FRAME — WHAT THE PLAYER HAS, not the globe.
 *
 * Everything of yours if the surface can hold it without drowning it in empty water; otherwise
 * just what is moving. Aspect-aware on purpose: the same port set is a good frame on a laptop and a
 * bad one on a phone, and the difference is the shape of the glass, not the data.
 *
 * With 214 ports in the table this is the difference between opening on your own water and opening
 * on the whole Earth. `everything` and `motion` come from ChartModel (focusPoints / motionPoints);
 * `fallback` is used ONLY when there is nothing of yours at all, which is when the globe is in fact
 * the right answer.
 */
export function openingBounds(
  everything: readonly LatLon[],
  motion: readonly LatLon[],
  fallback: readonly LatLon[],
  aspect: number,
): GeoBounds {
  const mine = boundsOf(everything)
  if (!mine) return boundsOf(fallback) ?? WORLD_BOUNDS
  const wide = atLeast(mine, OPENING_MIN_SPAN_DEG)
  if (overCoverage(wide, aspect) <= OVER_COVERAGE_LIMIT) return wide
  const moving = boundsOf(motion)
  return moving ? atLeast(moving, OPENING_MIN_SPAN_DEG) : wide
}
