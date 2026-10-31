// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DISPATCHER — one registry, two implementations, and no per-call branching anywhere
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The typed surface (index.ts) calls `call('worldMarket', [portId])` and does not know, and must
// never learn, whether that reached PGlite in this tab or PostgREST in Singapore. There is exactly
// ONE place that decides — src/lib/rpc/init.ts — and exactly one place that holds the decision,
// which is this module's `active` variable.
//
// If a screen ever contains `if (hasCloud)`, this design has failed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { RPCS, rpcLabel, type RpcName } from './catalog'
import { fromError, fromPayload, type RpcResult } from './result'

export type BackendKind = 'local' | 'cloud'

export interface RpcBackend {
  readonly kind: BackendKind
  /** A one-line description for the console and the debug panel. */
  readonly describe: string
  /** Call the function, hand back whatever jsonb it returned. May throw; `call()` catches. */
  invoke(name: RpcName, values: readonly unknown[]): Promise<unknown>
}

let active: RpcBackend | null = null

/**
 * THE MUTATION SIGNAL (2026-10-31). `src/lib` is the layer everything else stands on, so this
 * dispatcher may not import the store's resource cache — `tests/sections.spec.ts` is the guard,
 * and it caught exactly that import on this slice's first run. The dispatcher instead ANNOUNCES a
 * verb that changed the world; the cache (which is allowed to import down into lib) subscribes
 * once at module load. One signal, one subscriber, no upward import and no second copy of the
 * catalogue's `mutates` knowledge: the flag still lives on the RPC row.
 */
export type MutationListener = (name: RpcName, invalidates: readonly string[]) => void
let mutationListener: MutationListener | null = null
export function setMutationListener(listener: MutationListener | null): void {
  mutationListener = listener
}

/** Install the backend. Called once, by init.ts — or by a spec, which supplies its own engine. */
export function setBackend(backend: RpcBackend): void {
  active = backend
}

/** Forget it again. Tests only. */
export function clearBackend(): void {
  active = null
}

/** The backend in use, or null before startup has chosen one. */
export function currentBackend(): RpcBackend | null {
  return active
}

export function backendKind(): BackendKind | null {
  return active?.kind ?? null
}

/**
 * THE call path. Every RPC in the surface goes through here, so the refusal contract, the fault
 * mapping and the "what was I calling?" context are written once.
 */
export async function call<T>(name: RpcName, values: readonly unknown[] = []): Promise<RpcResult<T>> {
  const backend = active
  if (!backend) {
    return {
      ok: false,
      refusal: {
        code: 'E_NO_BACKEND',
        sentence:
          'The game has not been connected to a server yet. initRpc() must run before any screen ' +
          'asks for data.',
        fixes: ['(call initRpc() during app boot)'],
        source: 'fault',
      },
    }
  }
  // ONE LINE PER ASK, at debug level, on both backends (2026-09-14). It is how a spec COUNTS the
  // asks a screen makes (tests/trade.ceiling.spec.ts: an open on-board list must make none on the
  // world's beat, an open tray at most one) — a dry run is a real write rolled back, and a hook
  // that re-asked a list every 3 s (owner rows 95-97) was invisible until something printed it.
  console.debug('[rpc]', rpcLabel(name))
  try {
    const result = fromPayload<T>(await backend.invoke(name, values))
    // A VERB THAT CHANGED THE WORLD DROPS THE LIVE ANSWERS (src/store/resourceCache.ts): every
    // finite-lifetime read goes, plus the SESSION entries this verb names in the catalogue. A
    // refusal changed nothing, so it invalidates nothing.
    const spec = RPCS[name]
    if (result.ok && spec.mutates) mutationListener?.(name, spec.invalidates ?? [])
    return result
  } catch (err) {
    const refusal = fromError(err)
    return {
      ok: false,
      refusal: {
        ...refusal,
        detail: [refusal.detail, `${backend.kind} · ${rpcLabel(name)}`].filter(Boolean).join(' · '),
      },
    }
  }
}
