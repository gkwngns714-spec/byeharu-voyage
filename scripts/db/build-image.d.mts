// Types for build-image.mjs — hand-written, for the same reason chainSource.node.d.mts is: the
// builder is plain JavaScript so that reading a directory and spawning PostgreSQL never drags
// Node's ambient globals into the scope of a spec (see tsconfig.test.json's note), while the
// spec and vite.config.ts still get a checked surface to call.

export interface WorldImageReceipt {
  /** The fingerprint stamped inside the image, read back from app_local.chain. */
  fingerprint: string | null
  /** How many migration names that stamp names. */
  files: number
  /** Rows in public.ports — harbours AND the sea places 0036 put in the same table. */
  ports: number
  /** Of those, the ones a fleet can dock at. */
  harbours: number
  goods: number
  /** Rows in public.port_goods, which must be exactly `harbours * goods`. */
  market: number
}

export interface EnsuredWorldImage {
  /** Absolute path of the cached tarball. */
  file: string
  /** `fingerprintChain(files)` of the chain it was built from — and its file name. */
  fingerprint: string
  bytes: Uint8Array
  /** False when a cached image for this chain was reused. */
  built: boolean
  migrations: number
}

/** Where the image is served from, under the site base. Re-exported from src/lib/db/worldImage.ts. */
export declare const WORLD_IMAGE_DIR: string
/** `world-<fingerprint>.tar.gz`. Re-exported from src/lib/db/worldImage.ts. */
export declare function worldImageFileName(fingerprint: string): string

/** Absolute path of the between-builds cache. Under node_modules/.cache; never committed. */
export declare const IMAGE_CACHE_DIR: string
export declare const REPO_ROOT: string

/** The chain as the browser sees it, and its fingerprint. */
export declare function chainAndFingerprint(): Promise<{
  files: { name: string; sql: string }[]
  fingerprint: string
}>

/** Apply the chain to a fresh PostgreSQL and hand back a compressed data directory. */
export declare function buildWorldImage(options?: { log?: (...args: unknown[]) => void }): Promise<{
  bytes: Uint8Array
  tarBytes: number
  dumpedBytes: number
  fingerprint: string
  applyMs: number
  ms: number
  migrations: number
  receipts: number
}>

/**
 * Restore the tarball and certify it: the fingerprint inside it must be `fingerprint`, the world
 * in it must equal data/*.json (world-guard), and §K.1's opening must be playable in it.
 * THROWS on any disagreement.
 */
export declare function certifyWorldImage(
  bytes: Uint8Array,
  options?: { fingerprint?: string; log?: (...args: unknown[]) => void },
): Promise<WorldImageReceipt>

/** Rebuild a dumped tar keeping only the write-ahead-log segments in [first, last]. */
export declare function dropSurplusWal(tar: Uint8Array, first: string, last: string): Uint8Array

/** The image for the chain in this repository, built if the cache has none. */
export declare function ensureWorldImage(options?: {
  log?: (...args: unknown[]) => void
  cacheDir?: string
  force?: boolean
}): Promise<EnsuredWorldImage>

export declare function clearWorldImageCache(cacheDir?: string): Promise<void>
