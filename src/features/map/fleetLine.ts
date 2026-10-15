import { joinPieces, whereParts, type Whereabouts, type WherePiece } from '../../domain/fleet'
import type { FleetOnChart, MapPort } from '../../chart'

// THE ONE LINE UNDER A FLEET'S NAME — where she is, or where she is going and when she gets there.
//
// Two readers, one spelling: the fleets corner prints it under every name, and the fleet tray
// prints it beside hers at peek. The WORDS are `domain/fleet`'s `whereLine` — the same sentence
// FLEETS, COMMAND and the merchant line print. This file only hands it what the chart already
// decided: `liveWorld.mapFleetOf` classified her through `whereabouts`, so `fleet.kind` IS that
// answer carried onto the chart, read back here arm for arm (nothing is re-decided).
//
// "When she gets there" is the SERVER's arrival instant (`voyage.eta`) counted down against the
// shell clock — the map does not own a second way to say "4m".
export function fleetLine(f: FleetOnChart, portsByCode: ReadonlyMap<string, MapPort>, nowMs: number): string {
  return joinPieces(fleetParts(f, portsByCode, nowMs))
}

/** The same line in pieces, so a panel can link the harbour it names (src/chart/goTo.ts). */
export function fleetParts(f: FleetOnChart, portsByCode: ReadonlyMap<string, MapPort>, nowMs: number): WherePiece[] {
  return whereParts(whereOnChart(f), (code) => portsByCode.get(code)?.name ?? code, nowMs)
}

function whereOnChart(f: FleetOnChart): Whereabouts {
  switch (f.fleet.kind) {
    case 'docked':
      return { kind: 'docked', port: f.fleet.portCode }
    case 'anchored':
      return { kind: 'anchored', at: f.at }
    case 'sailing':
      return {
        kind: 'sailing',
        to: f.fleet.voyage.destinationCode,
        point: f.fleet.voyage.destPoint,
        etaMs: f.fleet.voyage.etaMs,
      }
  }
}
