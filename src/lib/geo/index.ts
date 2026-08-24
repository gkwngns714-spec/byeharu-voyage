// src/lib/geo — THE ONE geography authority. Projection, great-circle maths, simplification.
// Nothing else in the app may define a second haversine, a second lat/lon→x/y, or a second Earth
// radius; everything that needs geometry imports it from here.
//
// Everything in this folder is PURE: no React, no DOM, no fetch, no clock. That is what lets the
// specs in tests/map*.spec.ts run as plain Node with no browser.

export {
  project,
  unproject,
  boundsToViewBox,
  viewBoxToBounds,
  boundsOf,
  fitToViewBox,
  unwrapLongitudes,
  WORLD_BOUNDS,
  CHART_WIDTH,
  CHART_HEIGHT,
  type LatLon,
  type Point,
  type ViewBox,
  type GeoBounds,
} from './projection.ts'

export {
  EARTH_RADIUS_NM,
  haversineNm,
  interpolateGreatCircle,
  interpolateAlongPath,
  pathLengthNm,
  cumulativeNm,
  densifyGreatCircle,
} from './greatCircle.ts'

export { simplifyPath, boundingSpan } from './simplify.ts'
