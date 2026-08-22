// Chart points → an SVG `d` string. One place, so every line on this map is built the same way
// and the coordinate precision is a single decision.
//
// PRECISION: two decimals of a degree is ~1.1 km. At the tightest zoom the chart allows
// (MIN_SPAN_X = 1.5° across a phone, ~0.004°/px) that is a quarter of a pixel — invisible — and it
// keeps the coastline path string roughly a third the size of full float output.

import type { Point } from '../lib/geo'

const PRECISION = 2

const fixed = (n: number): string => {
  const s = n.toFixed(PRECISION)
  // "-0.00" and "1.50" carry no information; trimming them is free bytes on a 6,000-point path.
  const trimmed = s.replace(/\.?0+$/, '')
  return trimmed === '' || trimmed === '-' || trimmed === '-0' ? '0' : trimmed
}

/** An open polyline: `M x y L x y …`. Returns '' for fewer than two points (an empty `d` renders
 *  nothing, which is the right answer for "there is no line here"). */
export function toPolylineD(points: readonly Point[]): string {
  if (points.length < 2) return ''
  let d = `M${fixed(points[0].x)} ${fixed(points[0].y)}`
  for (let i = 1; i < points.length; i++) d += `L${fixed(points[i].x)} ${fixed(points[i].y)}`
  return d
}

/** Many closed rings in one `d` string — the whole world's land as a single <path> element. */
export function toClosedRingsD(rings: readonly (readonly Point[])[]): string {
  let d = ''
  for (const ring of rings) {
    if (ring.length < 3) continue
    d += toPolylineD(ring) + 'Z'
  }
  return d
}
