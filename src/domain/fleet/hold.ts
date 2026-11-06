import { instantMs } from '../../lib/format'
import type { FleetStatus, VoyageHold } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SHIP HELD BY A BATTLE (0323, docs/WORLD_POWERS.md section 5.2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The server's `voyage.progress_nm` stands her still while a hold runs, and serves the holds of a voyage as frozen facts (`voyage.holds_served`): {from, until}. A client that draws her between reads must
// not sail her through one: the roster places a merchant in time from those facts, and the chart's drift starts its clock when the hold ends. This file is the one reading of them on this side.
// Nothing here decides anything: a voyage with no hold reads 0 and null, and every sum below is then the sum it always was.

/** How many milliseconds of her holds have passed at `atMs`: the part of her passage she did not sail. */
export function heldMs(holds: readonly VoyageHold[] | undefined, atMs: number): number {
  let sum = 0
  for (const h of holds ?? []) {
    const from = instantMs(h.from)
    const until = instantMs(h.until)
    if (from === null || until === null) continue
    sum += Math.max(0, Math.min(atMs, until) - from)
  }
  return sum
}

/** When the last of her holds ends, in ms, or null with none. It may have passed: a reader only ever asks which is later, this or the read. */
export function heldUntilMs(holds: readonly VoyageHold[] | undefined): number | null {
  let last: number | null = null
  for (const h of holds ?? []) {
    const until = instantMs(h.until)
    if (until !== null && (last === null || until > last)) last = until
  }
  return last
}

/** IS SHE IN A BATTLE: in port or at anchor she reads IN_BATTLE; at sea she stays SAILING and `busy_until` is her clock, and nothing else sets it there. */
export function inBattle(fleet: { readonly status: FleetStatus; readonly busy_until?: string | null }): boolean {
  return fleet.status === 'IN_BATTLE' || (fleet.status === 'SAILING' && instantMs(fleet.busy_until ?? null) !== null)
}
