import { test, expect } from '@playwright/test'
import {
  COASTLINE_MIN_SPAN_DEG,
  COASTLINE_TOLERANCE_DEG,
  buildCoastline,
} from '../src/features/map/coastlineBuild'
import { toClosedRingsD, toPolylineD } from '../src/features/map/svgPath'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COASTLINE BUILDER — pure, so it can be proved without a network or a browser.
//
// The real input is data/world-110m.json (177 features, 289 rings, 10,654 points). These specs use
// hand-written miniatures instead: a spec that read the vendored file would need Node's `fs`, and
// tsconfig.test.json deliberately does not grant Node globals to specs. The numbers from the real
// file are measured by running this same function over it and are recorded in coastlineBuild.ts.
//
// What matters here is the CONTRACT: land comes out as closed rings, holes survive, malformed
// GeoJSON is skipped rather than thrown, and the reported sizes are the real ones.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A square with a square hole, as a GeoJSON Polygon — the shape that proves interior rings live. */
const SQUARE_WITH_HOLE = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature',
      properties: { NAME: 'Test', ISO_A2: 'TT' },
      geometry: {
        type: 'Polygon',
        coordinates: [
          [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
            [0, 0],
          ],
          [
            [3, 3],
            [7, 3],
            [7, 7],
            [3, 7],
            [3, 3],
          ],
        ],
      },
    },
  ],
}

test.describe('buildCoastline', () => {
  test('turns polygons into ONE closed path, and keeps interior rings', () => {
    const built = buildCoastline(SQUARE_WITH_HOLE)
    expect(built.rawRingCount).toBe(2)
    expect(built.ringCount).toBe(2) // the hole is a ring in its own right
    expect(built.d.startsWith('M')).toBe(true)
    // Two rings = two subpaths, each closed. `fill-rule: evenodd` on the element makes the second
    // one a hole; the builder's job is only to keep it.
    expect(built.d.match(/M/g)).toHaveLength(2)
    expect(built.d.match(/Z/g)).toHaveLength(2)
  })

  test('reports its own size, and the reported bytes are the real bytes', () => {
    const built = buildCoastline(SQUARE_WITH_HOLE)
    expect(built.pathBytes).toBe(built.d.length)
    expect(built.pointCount).toBeGreaterThan(0)
    expect(built.rawPointCount).toBeGreaterThanOrEqual(built.pointCount)
  })

  test('handles MultiPolygon as well as Polygon', () => {
    const multi = {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: {
            type: 'MultiPolygon',
            coordinates: [
              [
                [
                  [0, 0],
                  [5, 0],
                  [5, 5],
                  [0, 0],
                ],
              ],
              [
                [
                  [20, 20],
                  [30, 20],
                  [30, 30],
                  [20, 20],
                ],
              ],
            ],
          },
        },
      ],
    }
    expect(buildCoastline(multi).ringCount).toBe(2)
  })

  test('drops specks — a ring smaller than the minimum span never reaches the path', () => {
    const speck = COASTLINE_MIN_SPAN_DEG / 4
    const tiny = {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [
              [
                [0, 0],
                [speck, 0],
                [speck, speck],
                [0, 0],
              ],
            ],
          },
        },
      ],
    }
    const built = buildCoastline(tiny)
    expect(built.rawRingCount).toBe(1)
    expect(built.ringCount).toBe(0)
    expect(built.d).toBe('')
  })

  test('simplification moves no point further than the tolerance', () => {
    // A straight edge with a wobble smaller than the tolerance: the wobble must go, the corners
    // must stay.
    const wobble = COASTLINE_TOLERANCE_DEG / 4
    const feature = {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [
              [
                [0, 0],
                [2, wobble],
                [4, 0],
                [6, -wobble],
                [8, 0],
                [8, 8],
                [0, 8],
                [0, 0],
              ],
            ],
          },
        },
      ],
    }
    const built = buildCoastline(feature)
    expect(built.rawPointCount).toBe(8)
    expect(built.pointCount).toBeLessThan(8)
    expect(built.pointCount).toBeGreaterThanOrEqual(4)
  })

  test('malformed input is skipped, never thrown — a broken backdrop may not take the tab down', () => {
    for (const bad of [
      null,
      undefined,
      {},
      { features: 'not an array' },
      { features: [null, {}, { geometry: null }, { geometry: { type: 'Point', coordinates: [1, 2] } }] },
      { features: [{ geometry: { type: 'Polygon', coordinates: [[['a', 'b']]] } }] },
    ]) {
      const built = buildCoastline(bad)
      expect(built.d).toBe('')
      expect(built.ringCount).toBe(0)
    }
  })
})

test.describe('svgPath', () => {
  test('a polyline needs two points; fewer draws nothing', () => {
    expect(toPolylineD([])).toBe('')
    expect(toPolylineD([{ x: 1, y: 2 }])).toBe('')
    expect(toPolylineD([{ x: 1, y: 2 }, { x: 3, y: 4 }])).toBe('M1 2L3 4')
  })

  test('coordinates are trimmed to two decimals, and trailing zeros are dropped', () => {
    expect(toPolylineD([{ x: 1.239, y: -0.001 }, { x: 2.5, y: 3.0 }])).toBe('M1.24 0L2.5 3')
  })

  test('rings are closed, and a degenerate ring is skipped', () => {
    const d = toClosedRingsD([
      [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 1, y: 1 }],
      [{ x: 5, y: 5 }],
    ])
    expect(d).toBe('M0 0L1 0L1 1Z')
  })
})
