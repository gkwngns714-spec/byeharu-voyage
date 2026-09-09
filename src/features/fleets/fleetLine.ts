import { busyUntilMs, voyageEtaMs } from '../../domain/fleet'
import { pointLabel } from '../../domain/passage'
import { formatRealShort } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'

// ONE LINE ABOUT WHERE SHE IS — the words the fleet row and the fleet tray both print.
//
// Pure. Every figure is the server's: `port` is a CODE and null at sea, `anchor` is the bare point
// of water she is holding at (0039), `voyage.to` / `voyage.dest_point` is where she is bound, and
// the instant a countdown reads is `eta` or `busy_until`, both ISO strings parsed once in
// domain/fleet. Nothing here settles a voyage: past the instant the word is "due", never "arrived",
// because the next read is what lands her.

/** Where she is bound, by name — a harbour, a pinpointed point of water, or nothing at all. */
export function fleetBoundFor(
  fleet: FleetView,
  portName: (code: string | null) => string | null,
): string | null {
  const v = fleet.voyage
  if (!v) return null
  if (v.to) return portName(v.to) ?? v.to
  if (v.dest_point) return pointLabel({ lat: v.dest_point[0], lon: v.dest_point[1] })
  return 'open water'
}

/** Where she lies, or where she is going: `Lisbon`, `to Cádiz`, a point of water. */
export function fleetWhere(
  fleet: FleetView,
  portName: (code: string | null) => string | null,
): string | null {
  const here = portName(fleet.port)
  if (here) return here
  if (fleet.anchor) return pointLabel({ lat: fleet.anchor[0], lon: fleet.anchor[1] })
  const bound = fleetBoundFor(fleet, portName)
  return bound ? `to ${bound}` : null
}

/** The countdown — to her arrival, or to the moment a busy fleet comes free. Null when nothing is
 *  counting; "due" once the instant has passed and the server has not yet been asked. */
export function fleetDue(fleet: FleetView, nowMs: number): string | null {
  const at = voyageEtaMs(fleet) ?? busyUntilMs(fleet)
  if (at === null) return null
  return nowMs >= at ? 'due' : formatRealShort(at - nowMs)
}
