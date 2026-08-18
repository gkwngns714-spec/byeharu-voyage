// ═══════════════════════════════════════════════════════════════════════════════════════════════
// LINE SIMPLIFICATION — Ramer–Douglas–Peucker, iterative (no recursion: a 1,000-point ring must
// not be able to blow the stack on a phone).
//
// WHY IT IS HERE. `data/world-110m.json` is 177 country features, 289 rings, 10,654 points. Drawn
// verbatim that is ~123 KB of SVG path data in one element, and the browser re-rasterises all of
// it on every frame of a pinch-zoom. A pale backdrop coastline does not earn that. Decimating at
// LOAD time (see src/features/map/coastline.ts) keeps `data/` as the single source of truth — no
// second, generated copy of the world to drift out of date — and costs one pass at map open.
//
// The tolerance is in whatever units the points are in; the coastline passes chart units, so a
// tolerance of 0.2 means "no point moved more than 0.2° (~12 nm) from where it was".
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { Point } from './projection'

/** Squared distance from `p` to the SEGMENT ab (not the infinite line — the segment, or a ring's
 *  end points wander). */
function squaredDistanceToSegment(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x
  const dy = b.y - a.y
  if (dx === 0 && dy === 0) return (p.x - a.x) ** 2 + (p.y - a.y) ** 2
  const t = Math.min(1, Math.max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
  return (p.x - (a.x + t * dx)) ** 2 + (p.y - (a.y + t * dy)) ** 2
}

/**
 * Drop every point that sits within `tolerance` of the line its neighbours already describe.
 * The first and last points are always kept, so a closed ring stays closed.
 *
 * `tolerance <= 0` returns the input untouched — "simplify by nothing" is a no-op, not an error.
 */
export function simplifyPath(points: readonly Point[], tolerance: number): Point[] {
  if (points.length < 3 || !(tolerance > 0)) return points.slice()

  const toleranceSq = tolerance * tolerance
  const keep = new Uint8Array(points.length)
  keep[0] = 1
  keep[points.length - 1] = 1

  const stack: number[] = [0, points.length - 1]
  while (stack.length > 0) {
    const end = stack.pop() as number
    const start = stack.pop() as number
    let worst = 0
    let worstIndex = -1
    for (let i = start + 1; i < end; i++) {
      const d = squaredDistanceToSegment(points[i], points[start], points[end])
      if (d > worst) {
        worst = d
        worstIndex = i
      }
    }
    if (worst > toleranceSq && worstIndex > 0) {
      keep[worstIndex] = 1
      stack.push(start, worstIndex, worstIndex, end)
    }
  }

  const out: Point[] = []
  for (let i = 0; i < points.length; i++) if (keep[i] === 1) out.push(points[i])
  return out
}

/** The width and height of a point set's bounding box, in the points' own units. Used to throw
 *  away islands too small to be a single pixel at any zoom the chart offers. */
export function boundingSpan(points: readonly Point[]): { width: number; height: number } {
  let minX = Infinity
  let maxX = -Infinity
  let minY = Infinity
  let maxY = -Infinity
  for (const p of points) {
    if (p.x < minX) minX = p.x
    if (p.x > maxX) maxX = p.x
    if (p.y < minY) minY = p.y
    if (p.y > maxY) maxY = p.y
  }
  if (!Number.isFinite(minX)) return { width: 0, height: 0 }
  return { width: maxX - minX, height: maxY - minY }
}
