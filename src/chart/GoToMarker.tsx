import { CHART_WIDTH, project, type LatLon, type ViewBox } from '../lib/geo'

// THE GO-TO MARKER (./goTo.ts): a ring that pulses on the place a link named, for a few seconds
// and until the next go-to. Pointer-transparent — it points, it is never pressed — and placed in
// the glass's own pixels from the same viewBox the chart is drawn in, on the copy of the sheet the
// view is showing (the chart is continuous across the antimeridian).
export function GoToMarker({
  at,
  box,
  width,
  height,
}: {
  at: LatLon
  box: ViewBox
  width: number
  height: number
}) {
  if (!(box.width > 0) || !(box.height > 0)) return null
  const p = project(at)
  const x = p.x - CHART_WIDTH * Math.floor((p.x - box.x) / CHART_WIDTH)
  const left = ((x - box.x) / box.width) * width
  const top = ((p.y - box.y) / box.height) * height
  return (
    <div
      aria-hidden
      data-testid="map-goto-marker"
      className="pointer-events-none absolute z-[5] h-0 w-0"
      style={{ left, top }}
    >
      <span className="bv-goto-ring absolute -left-6 -top-6 h-12 w-12 rounded-full border-2 border-accent" />
      <span className="absolute -left-3 -top-3 h-6 w-6 rounded-full border-2 border-accent bg-accent/20 shadow-sheet" />
    </div>
  )
}
