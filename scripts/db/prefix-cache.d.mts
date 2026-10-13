// Types for prefix-cache.mjs — hand-written, for the same reason build-image.d.mts is: the module
// is plain JavaScript run by Node, while specs still get a checked surface to call.

export interface PrefixFile {
  name: string
  sql: string
}

/** How a world starts before migration 0001. `create` returns a fresh engine with that base applied. */
export interface PrefixVariant {
  name: string
  baseId: string
  create(): Promise<PrefixDb>
}

/** The slice of PGlite this module and its callers use. */
export interface PrefixDb {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>
  exec(sql: string, options?: { onNotice?: (notice: { message?: string }) => void }): Promise<unknown>
  close(): Promise<void>
}

export interface PrefixRecord {
  name: string
  ms: number
  notices: string[]
  receipt: boolean
  /** True when this file's effect came from a restored snapshot rather than running here. */
  restored: boolean
}

export declare const PREFIX_CACHE_FORMAT: number

/** Comments dropped and whitespace collapsed OUTSIDE quoted/dollar-quoted text only. */
export declare function normalizeSql(sql: string): string
/** `keys[k]` = base `baseId` then files[0..k-1]; length files.length + 1. */
export declare function prefixKeys(files: readonly PrefixFile[], baseId: string): string[]
export declare function chainCacheKey(files: readonly PrefixFile[], baseId?: string): string
export declare function snapshotLengths(n: number): Set<number>
export declare function contentLines(pg: PrefixDb, options?: { stableOnly?: boolean }): Promise<string[]>
export declare function contentDigest(pg: PrefixDb, options?: { stableOnly?: boolean }): Promise<string>
export declare function dropSurplusWal(tar: Uint8Array, first: string, last: string): Uint8Array
export declare function variantBaseId(variant: PrefixVariant): Promise<string>

export declare function applyWithPrefixCache(options: {
  variant: PrefixVariant
  files: readonly PrefixFile[]
  cacheDir: string
  log?: (...args: unknown[]) => void
  onProgress?: (step: { name: string; index: number; total: number }) => void
  fresh?: boolean
  snapshots?: boolean
}): Promise<{
  db: PrefixDb
  applied: PrefixRecord[]
  restored: number
  restoredFrom: string | null
  key: string
  receipts: number
  applyMs: number
  restoreMs: number
  snapshotMs: number
  ms: number
}>
