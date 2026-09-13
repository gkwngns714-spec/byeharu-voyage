// THE REMEMBERED PRICES OF A QUAY — one silent read per port, cached by the store.
//
// `world.price_history(port)` (0013) decorates a price that is true without it, so a failed read
// is silent (worldStore.loadHistory) and the row says "No price history yet." Both faces of the
// Quay Ledger (owner row 76) — the quay she lies at and a quay she is only reading — open the same
// tray over the same trend, and on 2026-09-11 both carried this effect word for word. One spelling
// now, beside the other per-port reads in this folder.
//
// IT RETURNS THE POINTS AND THEIR CADENCE TOGETHER (slice 3, 2026-09-13): the chart labels its
// axis in hours, and 0013 serves `slot_seconds` on the same payload "so a client can label a time
// axis without knowing the tick cadence". A second hook for the second field would have been a
// second loader (Appendix A's tripwire); the shape is the design system's `PriceTrend`, declared
// below both callers. Each field is its own selector returning a served reference or a primitive,
// so the store never hands back a fresh literal (worldStore rule 4).

import { useEffect } from 'react'
import type { PriceTrend } from '../components/ui'
import { useWorld } from './worldStore'

/** Ensures the port's history is asked for once, and returns the trend for ONE good. */
export function usePortHistory(portId: string, code: string | null): PriceTrend {
  const known = useWorld((s) => s.history[portId] !== undefined)
  const loadHistory = useWorld((s) => s.loadHistory)
  useEffect(() => {
    if (!known) void loadHistory(portId)
  }, [portId, known, loadHistory])
  const points = useWorld((s) => (code ? s.history[portId]?.goods[code] : undefined))
  const slotSeconds = useWorld((s) => s.history[portId]?.slot_seconds ?? null)
  return { points, slotSeconds }
}
