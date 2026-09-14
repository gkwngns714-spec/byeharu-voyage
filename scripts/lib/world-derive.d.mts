// Types for world-derive.mjs — hand-written for the same reason market-fixture.d.mts is: a spec
// may import the derivation without dragging Node's ambient globals into its scope.
//
// Only what a spec needs is declared: the port rows as the database holds them. The generators
// and the guard use far more of this module, and they are plain .mjs, so nothing here constrains
// them.

/** One port as `deriveWorld()` derives it — the row `public.ports` holds (world-guard.mjs proves
 *  the applied world EQUALS this on every apply). `lat`/`lon` are `round2` of data/ports.json. */
export interface DerivedPort {
  id: string
  code: string
  name: string
  country: string
  lat: number
  lon: number
  sea_code: string
  region_code: string
  size_tier: number
}

export interface DerivedWorld {
  ports: DerivedPort[]
}

/** data/*.json → the world's rows, as the database should hold them. Reads the files off disk. */
export declare function deriveWorld(): DerivedWorld

/** The one rounding the seed applies to a coordinate. */
export declare function round2(n: number): number
