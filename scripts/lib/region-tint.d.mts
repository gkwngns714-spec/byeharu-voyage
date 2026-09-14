// Types for region-tint.mjs — hand-written for the same reason world-derive.d.mts is: a spec may
// import the builder without dragging Node's ambient globals into its scope.

export declare const COLS: number
export declare const ROWS: number
export declare const CELL_DEG: number

/** What data/region-tint.json holds. */
export interface RegionTintFile {
  $doc: string
  cellDeg: number
  cols: number
  rows: number
  regions: { id: string; name: string; at: { lat: number; lon: number }; harbours: number }[]
  /** Natural Earth ISO_A2_EH → region id, for every country with a harbour. */
  countries: Record<string, string>
  /** region id → cell rectangles `[col, row, w, h]`. */
  water: Record<string, [number, number, number, number][]>
}

export interface RegionTintReport {
  writes: { file: string; rows: number }[]
  splitCountries: { iso: string; region: string; counts: [string, number][] }[]
  seaMajority: { sea: string; region: string; counts: [string, number][] }[]
  unseeded: string[]
  waterCells: number
  tintedCells: number
  rectCount: number
  countryCount: number
  touching: string[]
}

/** Build the file's content from the repo at `root`. */
export declare function buildRegionTint(root: string): { file: RegionTintFile; report: RegionTintReport }

/** The file's text exactly as committed. */
export declare function regionTintText(file: RegionTintFile): string
