// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A DRY RUN'S ANSWER, KEPT STANDING — the estimate, or the refusal, as ONE served value
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `useServedRead` clears its view on a refusal, because for the shed or the inn a refusal means
// there is nothing to draw. For a DRY RUN the refusal IS what to draw: the basket prints the
// server's sentence under the line it refused (`refusal.line`, result.ts), and a delivery prints
// why the request cannot be met (E_CONTRACT_SHORT with its two figures). So both outcomes are
// folded into one served value and handed to `useServedRead` as `ok` — nothing is swallowed; the
// refusal crosses the boundary as data (worldStore's rule 2) and stands on screen while the next
// ask of the same subject is on the wire.
//
// WRITTEN ONCE, 2026-09-14. `useManifestPreview` (slice 2) carried this fold inline; the request
// board's dry run (slice 4, 0087) wanted the same fold for `cmd.preview_fulfil` — written a
// second time → it becomes a function (docs/NO_SPAGHETTI.md §1). Both hooks are one line of
// subject and one line of ask on this.

import type { ManifestPreview, ManifestReceipt, Refusal, RpcResult } from '../lib/rpc'
import { ok } from '../lib/rpc'
import { useServedRead } from './useServedRead'

export interface PreviewRead {
  /** The receipt the commit would produce, as of the last read. Null until the first answer
   *  lands, or when the server refused. */
  estimate: ManifestReceipt | null
  /** Why the server would refuse, or null. */
  refusal: Refusal | null
  /** True while an ask is on the wire — the first one, or a re-ask on the world's beat. */
  loading: boolean
}

/** What the server said: an estimate, or a refusal. */
interface Priced {
  estimate: ManifestReceipt | null
  refusal: Refusal | null
}

/**
 * @param subject  ONE string naming what is previewed, or null for "nothing to ask". A new
 *                 subject shows nothing of the old one; a re-read of the same subject keeps the
 *                 last answer and marks it `loading`.
 * @param ask      The dry-run RPC — read through a ref by useServedRead, so a fresh closure per
 *                 render is fine.
 */
export function usePreviewRead(subject: string | null, ask: () => Promise<RpcResult<ManifestPreview>>): PreviewRead {
  const read = useServedRead<Priced>(subject, async () => {
    const r = await ask()
    return ok<Priced>(r.ok ? { estimate: r.value.estimate, refusal: null } : { estimate: null, refusal: r.refusal })
  })
  return { estimate: read.view?.estimate ?? null, refusal: read.view?.refusal ?? null, loading: read.loading }
}
