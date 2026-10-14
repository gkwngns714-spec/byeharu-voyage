import { busyUntilMs, voyageEtaMs } from '../../domain/fleet'
import { formatRealShort } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'

// WHEN SHE IS DUE — the countdown the fleet row and the fleet fold both print. WHERE she is, in
// words, is `domain/fleet`'s `whereLine` (this file used to carry a second spelling of it).
//
// Pure. Every figure is the server's: `port` is a CODE and null at sea, `anchor` is the bare point
// of water she is holding at (0039), `voyage.to` / `voyage.dest_point` is where she is bound, and
// the instant a countdown reads is `eta` or `busy_until`, both ISO strings parsed once in
// domain/fleet. Nothing here settles a voyage: past the instant the word is "due", never "arrived",
// because the next read is what lands her.

/** The countdown — to her arrival, or to the moment a busy fleet comes free. Null when nothing is
 *  counting; "due" once the instant has passed and the server has not yet been asked. */
export function fleetDue(fleet: FleetView, nowMs: number): string | null {
  const at = voyageEtaMs(fleet) ?? busyUntilMs(fleet)
  if (at === null) return null
  return nowMs >= at ? 'due' : formatRealShort(at - nowMs)
}
