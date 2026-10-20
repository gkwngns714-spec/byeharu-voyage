import { formatClock, instantMs } from '../lib/format'
import { joinPieces, whereabouts, whereParts, type WherePiece } from '../domain/fleet'
import type { TrafficFleet } from '../lib/rpc'
import { t as tNow } from '../lib/i18n'

/**
 * THE ONE LINE beside a merchant's name — at peek on MAP and on her row in PORT. WHERE she is is
 * `domain/fleet`'s one rule and one sentence (`whereabouts` / `whereLine`), the same one a fleet of
 * yours is printed with (`to Kochi · 11m`, `Lisbon`); this adds only her own fact — while she is
 * held for her next lap, when she sails (`Lisbon · sails at 14:32`). Every instant is served.
 */
/**
 * WHAT THIS FUNCTION ACTUALLY READS, and nothing else. It used to ask for a whole `TrafficFleet`,
 * which is a row of fourteen keys to answer a question about a few — and 0111 turned that from
 * untidy into wrong: `world.sea_traffic` gained a `lane` key that `world.port_merchants` does not
 * serve, so `PortMerchant` became `Omit<TrafficFleet, 'lane'>` to stop the type promising a key the
 * server never sends, and the two PORT callers of this function stopped compiling. The fix is not
 * to put the lie back. A reader declares what it reads, and then every row that carries those
 * facts — the map's and the harbour's alike — satisfies it without either side knowing about the
 * other's extra keys. docs/NO_SPAGHETTI.md §3: the narrowest type that can answer the question.
 */
export type MerchantLineFacts = Pick<TrafficFleet, 'status' | 'voyage' | 'port' | 'anchor' | 'next_lap_at'>

export function merchantLine(t: MerchantLineFacts, portName: (code: string) => string, nowMs: number): string {
  return joinPieces(merchantParts(t, portName, nowMs))
}

/** The same line in pieces, so a panel can link the harbour it names (src/chart/goTo.ts). */
export function merchantParts(t: MerchantLineFacts, portName: (code: string) => string, nowMs: number): WherePiece[] {
  const where = whereabouts(t)
  const here = whereParts(where, portName, nowMs)
  if (where.kind === 'sailing') return here
  const next = instantMs(t.next_lap_at)
  return next !== null ? [...here, tNow('town.sailsAt', { time: formatClock(next) })] : here
}
