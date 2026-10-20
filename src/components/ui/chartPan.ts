// ═══════════════════════════════════════════════════════════════════════════════════════════════
// DRAGGING A TIME AXIS — the arithmetic of a pan, pure, so it is proved without a pointer
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-10-20 (request 178): *"And make the chart dragable to see the past prices by
// swiping left?"*
//
// A WINDOW AND AN OFFSET, NOT A FROM AND A TO. The chart's window is chosen by its chips (an hour, a
// day, a week) and the only thing a drag changes is HOW FAR BACK that window sits from the newest
// instant there is anything to draw at. One number of state, clamped to the data, so a drag can never
// leave the chart looking at an empty stretch of axis and a wider window cannot strand the view
// outside the record.
//
// THE CONTENT FOLLOWS THE FINGER — the same rule the map already pans by (`panBy`,
// src/chart/chartView.ts). Dragging the line to the RIGHT brings earlier prices in from the left, as
// it does in every chart and on every map; dragging it left walks back toward now. The owner's words
// were "swiping left", and on a keyboard that reading is literal: ArrowLeft looks back, because the
// axis has the past on its left (`PriceChart`). If he wants the drag itself inverted it is one sign
// in `panByDrag` and nothing else — recorded in docs/dev-log/2026-10-20-prices-both-ways.md §C as
// decided by default.
//
// WHY HERE AND NOT IN `priceChartModel`: the model answers "where does a served point sit on a drawn
// plane". This answers "which stretch of time is on the plane", which is a GESTURE, and the two are
// separately provable — the model takes a window and knows nothing about pointers, this takes pixels
// and knows nothing about paths. `SeriesChart` can take the same pan the day its record is long
// enough to need one; that is why it stands beside the two models rather than inside one of them.

/** The stretch of time there is something to draw in, and how much of it the window shows. */
export interface PanLimits {
  /** The oldest instant anything is drawn at — the record's earliest served point. */
  oldestMs: number
  /** The newest — now, or the last instant of the server's estimate. */
  newestMs: number
  /** How wide the chosen window is. */
  spanMs: number
}

/** The window the chart draws, for an offset back from the newest instant. */
export interface ChartWindow {
  fromMs: number
  toMs: number
}

/** How far back the window may be moved before it runs off the oldest point. Nought when the window
 *  is at least as wide as the data: there is nothing behind it to look at, and nothing to drag. */
export function panBackMs(limits: PanLimits): number {
  return Math.max(0, limits.newestMs - limits.oldestMs - limits.spanMs)
}

/** An offset held inside what there is to look at. */
export function clampPan(offsetMs: number, limits: PanLimits): number {
  if (!Number.isFinite(offsetMs)) return 0
  return Math.min(Math.max(offsetMs, 0), panBackMs(limits))
}

/** The window itself: `spanMs` wide, its right edge `offsetMs` back from the newest instant. */
export function panView(offsetMs: number, limits: PanLimits): ChartWindow {
  const toMs = limits.newestMs - clampPan(offsetMs, limits)
  return { fromMs: toMs - limits.spanMs, toMs }
}

/** A drag of `dxPx` across a plot `widthPx` wide, as the new offset. The content follows the finger:
 *  dx > 0 (dragging right) brings earlier prices in from the left. */
export function panByDrag(offsetMs: number, dxPx: number, widthPx: number, limits: PanLimits): number {
  if (!(widthPx > 0)) return clampPan(offsetMs, limits)
  return clampPan(offsetMs + (dxPx / widthPx) * limits.spanMs, limits)
}

/** One step of the keyboard: a quarter of the window. `back` is ArrowLeft — the past is on the left. */
export function panByKey(offsetMs: number, back: boolean, limits: PanLimits): number {
  return clampPan(offsetMs + (back ? 1 : -1) * limits.spanMs * 0.25, limits)
}
