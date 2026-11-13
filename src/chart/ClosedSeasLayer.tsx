import { CHART_HEIGHT, CHART_WIDTH } from '../lib/geo'

// THE CLOSED SEAS, SHADED — a veil over every cell of water the fleet in hand may not enter (design C3).
//
// WHICH cells is the server's answer twice over: the zone of each cell is its zone raster (world.sea_zone_map) and
// the closed zones are the sea rule's own verdicts (world.sea_conditions). This file only colours them: one pixel a
// cell, stretched over the chart by the view's own viewBox, so a pan or a zoom moves the picture and never repaints
// it. Land cells are in no zone, so the veil never covers a coast. Drawn under every mark.

/** One copy of the veil, over the whole sheet. `count` is how many seas it shades (a spec reads it). */
export function ClosedSeasLayer({ url, count }: { url: string; count: number }) {
  return (
    <image
      href={url}
      x={-CHART_WIDTH / 2}
      y={-CHART_HEIGHT / 2}
      width={CHART_WIDTH}
      height={CHART_HEIGHT}
      preserveAspectRatio="none"
      data-testid="map-closed-seas"
      data-closed={count}
      style={{ pointerEvents: 'none' }}
    />
  )
}
