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

import { rpcLabel, type RpcName } from './catalog'
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
  try {
    return fromPayload<T>(await backend.invoke(name, values))
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
