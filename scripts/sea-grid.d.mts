// Types for sea-grid.mjs — hand-written for the same reason market-fixture.d.mts is: a spec may
// import the module without dragging Node's ambient globals into its scope.
//
// Only what a spec needs is declared. The generators use far more of this module, and they are
// plain .mjs, so nothing here constrains them.

/** A named narrow water the 0.25° raster is too coarse to see, forced open by the carve. Its
 *  points must lie along ONE water, IN ORDER: the carve opens every cell BETWEEN CONSECUTIVE
 *  points, so a jump between two unrelated waters is a canal. See tests/seaCarve.spec.ts. */
export interface Channel {
  id: string
  name: string
  points: [number, number][]
  /** How many cells of DRY LAND this carve turns into sea, measured against `preCarveGrid()`.
   *  Authored, never inferred: `assertCarveDeclared` refuses to build the raster when the world
   *  disagrees, so the number can only change when a person changes it. */
  opensLand: number
}

export declare const CHANNELS: Channel[]

export declare const CELL_DEG: number
export declare const COLS: number
export declare const ROWS: number

/** The navigable raster: land scan-filled from Natural Earth, then CHANNELS opened and ICE closed.
 *  One byte per cell, 1 = a keel may be here. THROWS if any channel opens land it does not
 *  declare — see `assertCarveDeclared`. */
export declare function buildSeaGrid(): Uint8Array

/** The land data the raster is built FROM: scan-fill plus ICE, and no carve. This is the only
 *  thing that can answer "was this cell land before a channel opened it", which is the question
 *  the canal of 2026-09-06 was never asked. */
export declare function preCarveGrid(): Uint8Array

/** The carve, measured against the land it overwrites: `opened` maps a channel id to how many
 *  cells of DRY LAND it turns into sea, each counted against the pre-carve grid so that channels
 *  sharing a cell cannot rob one another. */
export declare function carveInventory(): {
  water: Uint8Array
  pre: Uint8Array
  opened: Map<string, number>
}

/** Refuses — throws — when a channel opens land its `opensLand` does not declare. */
export declare function assertCarveDeclared(opened: Map<string, number>): void

/** Great-circle distance in nautical miles. */
export declare function gcNm(lat1: number, lon1: number, lat2: number, lon2: number): number

export declare function rowOf(lat: number): number
export declare function colOf(lon: number): number
export declare function cellLat(row: number): number
export declare function cellLon(col: number): number
