// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOCAL DATABASE, as the app sees it — one engine, started once
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// BROWSER ENTRY. This module reaches chainSource.ts, which is a Vite transform, so a Node process
// must not import it — specs open their own engine with the Node transport instead. That is the
// only difference between them: same applier, same seed, same call path.
//
// Nothing here decides whether the game runs local or cloud. That decision has exactly one home:
// src/lib/rpc/init.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { loadChain } from './chainSource'
import { openLocalDb, type LocalDb, type OpenLocalDbOptions } from './localDb'
import { fetchWorldImage } from './worldImage'

let booting: Promise<LocalDb> | null = null
let ready: LocalDb | null = null

/**
 * THE ONE PLACE THE PRE-BUILT WORLD IS ASKED FOR, and the reason `import.meta.env` appears in
 * this file and nowhere deeper: the image is served beside the app, so its URL is a fact about
 * how the app is DEPLOYED (`base: '/byeharu-voyage/'`, vite.config.ts), not about the database.
 * openLocalDb() takes it as an option and works without one.
 */
function loadImage(fingerprint: string) {
  return fetchWorldImage(fingerprint, import.meta.env.BASE_URL)
}

/**
 * Start the local engine, or return the boot already in flight.
 *
 * Idempotent on purpose: React 19 in StrictMode mounts twice, and two PGlite instances over one
 * IndexedDB directory is a corrupted world, not a slow one.
 */
export function startLocalDb(options?: Partial<OpenLocalDbOptions>): Promise<LocalDb> {
  booting ??= openLocalDb({ loadChain, loadImage, ...options }).then((db) => {
    ready = db
    return db
  })
  return booting
}

/** The engine if it has finished booting, else null. For code that must not await. */
export function localDbIfReady(): LocalDb | null {
  return ready
}

/** Drop the singleton. Tests and a hard reset only — it does not close the engine. */
export function forgetLocalDb(): void {
  booting = null
  ready = null
}

export { loadChain, chainFiles } from './chainSource'
export { fingerprintChain, describeChain, orderChain, assertChainIsSane } from './chain'
export { fetchWorldImage, worldImageUrl, worldImageFileName, WORLD_IMAGE_DIR } from './worldImage'
export type { WorldImageFetch } from './worldImage'
export { imageRefusal, readStoredChain, recordChain, APP_LOCAL_DDL } from './appLocal'
export type { StoredChain } from './appLocal'
export type { MigrationFile } from './chain'
export { applyChain, MigrationFailure } from './applyChain'
export type { ApplyResult, AppliedMigration, PgExecutor } from './applyChain'
export { bootChannel, createBootChannel, progressFor } from './bootState'
export type { BootState, BootPhase, BootChannel } from './bootState'
export {
  openLocalDb,
  humanMigration,
  LOCAL_AUTH_UID,
  LOCAL_DATA_DIR,
  FOUNDING_COMPANY,
  FOUNDING_NATION,
} from './localDb'
export type { LocalDb, OpenLocalDbOptions } from './localDb'
