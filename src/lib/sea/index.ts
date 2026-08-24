// src/lib/sea — THE navigable-water grid and the pathfinder over it. Machinery, no game opinion.
//
// The AUTHORITY on what is water is the server's `public.sea_raster` (migration 0038); this
// module unpacks the served copy and searches it. A path found here is a PROPOSAL — the server
// verifies every segment and measures the distance itself (0039). See ./pathfind.ts's header for
// the full §7B reasoning, and docs/NAVIGATION_PLAN.md for the measurements behind the design.
//
// Consumed from THREE runtimes on purpose: the browser (order-time search), Node generator
// scripts (the 0038 distance seed), and the proof harness (the proofs' own proposals) — one
// search, so those three can never disagree about the fastest way through water.

export {
  cellLat,
  cellLon,
  rowOf,
  colOf,
  isWater,
  isWaterAt,
  gcNm,
  SEA_BIT,
  POLAR_BIT,
  packCells,
  unpackCells,
  base64ToBytes,
  navFromServed,
  type SeaNav,
} from './grid.ts'

export {
  snapToNav,
  findPath,
  floodFrom,
  floodPathTo,
  segmentIsWater,
  type FoundPath,
  type SeaPath,
  type LatLonPoint,
  type SearchScratch,
  type Flood,
} from './pathfind.ts'
