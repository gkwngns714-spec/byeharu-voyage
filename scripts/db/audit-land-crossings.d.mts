// Types for audit-land-crossings.mjs — hand-written for the same reason market-fixture.d.mts is: a
// spec may import the audit without dragging Node's ambient globals into its scope.

/** The narrow slice of a database this module reads through. */
export interface AuditDb {
  query(sql: string): Promise<{ rows: unknown[] }>
}

export type Course = [number, number][]

export interface ServedRaster {
  cols: number
  rows: number
  cell_deg: number
  bits_per_cell: number
  cells_base64: string
}

export interface WorldCourses {
  raster: ServedRaster
  ports: { code: string; name: string; kind: string; lat: number; lon: number; rlat: number | null; rlon: number | null }[]
  npc: { a: string; b: string; course: Course; text: string }[]
  routes: { route: string; ord: number; to_code: string; from_code: string | null; course: Course; text: string }[]
  /** 0441: public.npc_coast_courses. */
  coast?: { a: string; b: string; course: Course; text: string }[]
}

export interface Crossing {
  kind: 'npc' | 'route' | 'coast' | 'pair'
  /** 'npc A->B', 'route A->B', 'pair A->B' */
  key: string
  /** How many rows hold a course that crosses under this key. */
  rows: number
  runs: number
  landNm: number
  worst: { seg: number; nm: number; at: [number, number] }
}

export interface AuditResult {
  counted: { npc: number; route: number; coast: number; roadstead: number; pair: number }
  crossings: Crossing[]
  /** Harbour codes whose roadstead lies on drawn land. */
  roadsteads: string[]
}

export interface PointLand {
  blocked(lat: number, lon: number): boolean
}

export declare const TOLERANCE_NM: number
export declare const APPROACH_MAX_NM: number
export declare function readWorldCourses(db: AuditDb): Promise<WorldCourses>
export declare function truthLand(nav: unknown, land?: unknown): PointLand
export declare function crossingsOf(truth: PointLand, course: Course, toleranceNm?: number): { seg: number; nm: number; at: [number, number] }[]
export declare function auditWorld(
  world: WorldCourses,
  options?: {
    pairs?: boolean
    raw?: boolean
    pairFilter?: ((a: { code: string }, b: { code: string }) => boolean) | null
    log?: (...args: unknown[]) => void
  },
): AuditResult
