// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE DECISION — local engine or cloud project, chosen once, at startup
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This is the ONLY module in the client that reads `hasCloud`. Everything downstream calls the
// typed surface and is told nothing. Two consequences worth stating:
//
//   1. Adding a cloud project later changes nothing but this file's answer. The screens, the RPC
//      names, the payload types and the refusal contract are already identical — that is the whole
//      point of DEV_LOG D6 (the same SQL runs in both places).
//   2. A build WITH a cloud project never downloads PGlite: the local engine is behind a dynamic
//      import, so the ~10 MB WebAssembly Postgres is a separate chunk that cloud mode never asks
//      for.
//
// It is deliberately NOT wired to authStore. authStore answers "may this player see the game";
// this answers "where does the game live". They agree today (no cloud → local mode, gate open) but
// they are different questions and folding them together would make a signed-out cloud player fall
// back to a local world, which would be a second, silent save file.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { currentBackend, setBackend, type BackendKind } from './backend'
import { createCloudBackend } from './cloudBackend'

let chosen: Promise<BackendKind> | null = null

/**
 * Choose and install the backend. Idempotent: call it from app boot and again from anywhere that
 * needs to be sure, and it resolves to the same answer without booting a second engine.
 */
export function initRpc(): Promise<BackendKind> {
  chosen ??= choose()
  return chosen
}

/** What was chosen, once it has been. Null before initRpc() resolves. */
export function rpcMode(): BackendKind | null {
  return currentBackend()?.kind ?? null
}

async function choose(): Promise<BackendKind> {
  // Imported dynamically, not at module load: `src/lib/supabase.ts` reads `import.meta.env` while
  // being defined, which is a Vite substitution. Keeping it behind the decision means the RPC
  // surface can be imported — and proved — by a plain Node process that has no Vite in it.
  const { hasCloud, supabase } = await import('../supabase')
  if (hasCloud && supabase) {
    setBackend(createCloudBackend(supabase))
    console.info('[rpc] cloud: Supabase project, PostgREST, schemas world/cmd')
    return 'cloud'
  }
  const [db, local] = await Promise.all([import('../db'), import('./localBackend')])
  const engine = await db.startLocalDb()
  setBackend(local.createLocalBackend(engine))
  console.info(
    `[rpc] local: PGlite in this tab, chain ${engine.fingerprint}, ` +
      `${engine.applied.length} migration(s), ready in ${engine.bootMs} ms`,
  )
  return 'local'
}

/** Tests and a hard reload only. */
export function forgetRpcChoice(): void {
  chosen = null
}
