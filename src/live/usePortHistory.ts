// THE REMEMBERED PRICES OF A QUAY — one silent read per port, cached by the store.
//
// `world.price_history(port)` (0013) decorates a price that is true without it, so a failed read
// is silent (worldStore.loadHistory) and the row says "Not remembered here yet." Both faces of the
// Quay Ledger (owner row 76) — the quay she lies at and a quay she is only reading — open the same
// tray over the same trend, and on 2026-09-11 both carried this effect word for word. One spelling
// now, beside the other per-port reads in this folder.

import { useEffect } from 'react'
import type { PricePoint } from '../lib/rpc'
import { useWorld } from './worldStore'

/** Ensures the port's history is asked for once, and returns the points for ONE good — the served
 *  array reference or undefined, never a fresh literal (a selector that returns a new array is a
 *  render loop, worldStore rule 4). */
export function usePortHistory(portId: string, code: string | null): readonly PricePoint[] | undefined {
  const known = useWorld((s) => s.history[portId] !== undefined)
  const loadHistory = useWorld((s) => s.loadHistory)
  useEffect(() => {
    if (!known) void loadHistory(portId)
  }, [portId, known, loadHistory])
  return useWorld((s) => (code ? s.history[portId]?.goods[code] : undefined))
}
