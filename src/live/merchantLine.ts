import { formatClock, formatRealShort } from '../lib/format'
import type { TrafficFleet } from '../lib/rpc'

/**
 * THE ONE LINE beside a merchant's name — at peek on MAP and on her row in PORT. At sea it is
 * `fleetLine`'s wording (`to Kochi · 11m`); in port it is the harbour and, while she is held for
 * her next lap, when she sails (`Lisbon · sails at 14:32`). Every instant is served.
 */
/**
 * WHAT THIS FUNCTION ACTUALLY READS, and nothing else. It used to ask for a whole `TrafficFleet`,
 * which is a row of fourteen keys to answer a question about three — and 0111 turned that from
 * untidy into wrong: `world.sea_traffic` gained a `lane` key that `world.port_merchants` does not
 * serve, so `PortMerchant` became `Omit<TrafficFleet, 'lane'>` to stop the type promising a key the
 * server never sends, and the two PORT callers of this function stopped compiling. The fix is not
 * to put the lie back. A reader declares what it reads, and then every row that carries those three
 * facts — the map's and the harbour's alike — satisfies it without either side knowing about the
 * other's extra keys. docs/NO_SPAGHETTI.md §3: the narrowest type that can answer the question.
 */
export type MerchantLineFacts = Pick<TrafficFleet, 'voyage' | 'port' | 'next_lap_at'>

export function merchantLine(t: MerchantLineFacts, portName: (code: string) => string, nowMs: number): string {
  if (t.voyage) {
    const eta = Date.parse(t.voyage.eta)
    const to = t.voyage.to ? portName(t.voyage.to) : 'open sea'
    return `to ${to} · ${Number.isFinite(eta) ? formatRealShort(eta - nowMs) : '—'}`
  }
  const here = t.port ? portName(t.port) : 'at anchor'
  const next = t.next_lap_at ? Date.parse(t.next_lap_at) : NaN
  return Number.isFinite(next) ? `${here} · sails at ${formatClock(next)}` : here
}
