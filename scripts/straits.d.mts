// Types for straits.mjs, hand-written so a spec may import the list of real straits.

/** A real strait, a harbour on each side of it, the box of water the course between them must run through
 *  ([south, north, west, east]) and how far over the straight line between the two roadsteads it may be. */
export interface StraitPass {
  /** The charted channel (scripts/sea-grid.mjs) that opens it, when one does. */
  id?: string
  name: string
  a: string
  b: string
  box: [number, number, number, number]
  within: number
}

export declare const STRAIT_PASSES: StraitPass[]

/** Does a course run through a box? Sampled every nautical mile. */
export declare function courseInBox(
  course: readonly (readonly [number, number])[],
  box: readonly [number, number, number, number],
  gcNm: (lat1: number, lon1: number, lat2: number, lon2: number) => number,
): boolean
