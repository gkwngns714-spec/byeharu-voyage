import type { ChartView } from '../../chart'

// HAS THE PLAYER LEFT THE OPENING FRAME — the one question the minimap's presence is keyed on.
//
// docs/UI_DIRECTION.md §6, MAP: the minimap is shown "only when zoomed". At the opening frame the
// chart already holds what you have — your fleets and the harbours they are using — so an inset
// saying where that frame sits in the world is a second answer to a question the chart has just
// answered. Zoom in, or pan away, and the question is live again; the ⌖ control returns to the
// frame (useChartSurface's `fit` forgets the moves) and the inset goes with it.
//
// Pure, and compared in the chart's own units: `useChartSurface` computes the current view as
// `clampView(movedTo ?? fitView(frameBounds(aspect), aspect), aspect)`, and the screen computes
// the opening view by the same three calls, so this is a comparison of two `ChartView`s and not a
// second idea of where the chart opens. Half a percent of the span is the slack — a rotation that
// re-clamps by a fraction of a degree is not a move.
export function viewLeftFrame(view: ChartView, opening: ChartView): boolean {
  const slack = opening.spanX * 0.005
  return (
    Math.abs(view.spanX - opening.spanX) > slack ||
    Math.abs(view.cx - opening.cx) > slack ||
    Math.abs(view.cy - opening.cy) > slack
  )
}
