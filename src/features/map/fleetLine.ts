import { formatRealShort } from '../../lib/format'
import { pointLabel } from '../../domain/passage'
import type { FleetOnChart, MapPort } from '../../chart'

// THE ONE LINE UNDER A FLEET'S NAME — where she is, or where she is going and when she gets there.
//
// Two readers, one spelling: the fleets corner prints it under every name, and the fleet tray
// prints it beside hers at peek. It was `statusOf`, private to the old top-left panel, and the
// detail panel said the same fact a second way in three `Line`s. A pure function, so the wording
// is one thing a spec can read without mounting anything.
//
// "When she gets there" is the SERVER's arrival instant (`voyage.eta`) counted down against the
// shell clock, through `formatRealShort` — the map does not own a second way to say "4m".
export function fleetLine(f: FleetOnChart, portsByCode: ReadonlyMap<string, MapPort>, nowMs: number): string {
  if (f.dockedAtCode) return portsByCode.get(f.dockedAtCode)?.name ?? f.dockedAtCode
  // 0039: anchored at a bare point of water it is somewhere, going nowhere — say the spot, not a dash.
  if (f.fleet.kind === 'anchored') return `anchored · ${pointLabel(f.at)}`
  const destination = f.destinationCode
    ? (portsByCode.get(f.destinationCode)?.name ?? f.destinationCode)
    : f.voyage?.destPoint
      ? pointLabel(f.voyage.destPoint)
      : '—'
  // A WORD, NOT AN ARROW. `→` was the old spelling; §4.5 bans text glyphs doing an icon's job.
  return `to ${destination} · ${f.voyage ? formatRealShort(f.voyage.etaMs - nowMs) : '—'}`
}
