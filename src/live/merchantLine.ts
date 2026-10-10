import { formatClock, formatRealShort } from '../lib/format'
import type { TrafficFleet } from '../lib/rpc'

/**
 * THE ONE LINE beside a merchant's name — at peek on MAP and on her row in PORT. At sea it is
 * `fleetLine`'s wording (`to Kochi · 11m`); in port it is the harbour and, while she is held for
 * her next lap, when she sails (`Lisbon · sails at 14:32`). Every instant is served.
 */
export function merchantLine(t: TrafficFleet, portName: (code: string) => string, nowMs: number): string {
  if (t.voyage) {
    const eta = Date.parse(t.voyage.eta)
    const to = t.voyage.to ? portName(t.voyage.to) : 'open sea'
    return `to ${to} · ${Number.isFinite(eta) ? formatRealShort(eta - nowMs) : '—'}`
  }
  const here = t.port ? portName(t.port) : 'at anchor'
  const next = t.next_lap_at ? Date.parse(t.next_lap_at) : NaN
  return Number.isFinite(next) ? `${here} · sails at ${formatClock(next)}` : here
}
