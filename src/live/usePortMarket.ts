// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PRICES ON A QUAY — read on demand, re-read on the world's beat, and honest when refused.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `world.market(port)` is cached per port in the store and prices step every drift slot (row 64:
// the 15-minute clock on the TopBar). A read keyed on "is it cached yet" is read ONCE and never
// again, so a distant quay's prices went stale forever and a REFUSED read — which leaves
// `markets[portId]` undefined (worldStore.loadMarket) — was a grey block forever. That was the
// defect the adversarial review of the Quay Ledger (owner row 76) found on 2026-09-11: the
// deleted MarketScreen re-asked on every `readAt` and kept a "Try again"; PORT's own effect did
// neither. This hook is the ONE spelling for both states of the fold — a quay with a fleet
// alongside and a quay being read — keyed on (port, last read), exactly as `useInn` and
// `useBuyCapacity` key theirs.
//
// A refusal is reported beside the cached view, never instead of it: a quay that WAS read keeps
// its last prices on screen while a re-read fails, which is a truthful, lesser answer.

import { useCallback, useEffect, useState } from 'react'
import type { MarketView, Refusal } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface PortMarketState {
  /** The store's cached view for this port, or undefined until the first read lands. */
  market: MarketView | undefined
  /** The refusal of the LAST read of this port, or null when it landed. */
  refusal: Refusal | null
  /** Ask again, now. */
  retry: () => void
}

export function usePortMarket(
  /** The harbour, or null for a sea place (0036: open water keeps no book) and while unknown. */
  portId: string | null,
): PortMarketState {
  const market = useWorld((s) => (portId ? s.markets[portId] : undefined))
  const loadMarket = useWorld((s) => s.loadMarket)
  const readAt = useWorld((s) => s.readAt)
  const [refused, setRefused] = useState<{ portId: string; refusal: Refusal | null } | null>(null)

  const read = useCallback(
    (id: string) => {
      void loadMarket(id).then(() => {
        const state = useWorld.getState()
        setRefused(state.markets[id] ? null : { portId: id, refusal: state.refusal })
      })
    },
    [loadMarket],
  )
  useEffect(() => {
    if (portId && readAt !== null) read(portId)
  }, [portId, readAt, read])

  return {
    market,
    refusal: refused !== null && refused.portId === portId ? refused.refusal : null,
    retry: () => {
      if (portId) read(portId)
    },
  }
}
