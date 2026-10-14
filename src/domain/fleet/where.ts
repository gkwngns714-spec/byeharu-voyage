// WHERE SHE IS — the one rule, and the one sentence, for "at sea / in port / at anchor".
//
// SPAGHETTI, in the word docs/NO_SPAGHETTI.md §1 asks for. Before 2026-10-14 this question had
// NINE answers on the client, and they already disagreed:
//
//   features/fleets/fleetLine.ts   port → bare point of water → `to X` (point-bound: the point, or "open water")
//   features/map/fleetLine.ts      port → `anchored · point` → `to X · 4m` (point-bound with no point: "—")
//   features/command/CommandScreen `whereOf`: port → `→ X` / `→ sea` → `anchored` (no spot) → status
//   features/map/SendFleetRow      `whereOf`: port → `at sea` → `at anchor · point` → status
//   features/command/Queue         `Sailing → X` / `Sailing → open sea`
//   live/merchantLine.ts           voyage FIRST → `to X` / `to open sea` → port, else "at anchor"
//   chart/liveWorld.ts             voyage FIRST → anchor → port (the chart's own classification)
//   domain/passage `sailOrigin`    port → anchor → voyage's end (where a SAIL departs from)
//   domain/fleet `fleetPortCode`   port → voyage.to (where her next order runs)
//
// Two precedences (port-first and voyage-first), four words for a point-bound destination ("sea",
// "open sea", "open water", the point itself), two for an anchor ("anchored", "at anchor"). Each
// one now ASKS this file.
//
// ── THE RULE ───────────────────────────────────────────────────────────────────────────────────
// The server keeps the three states exclusive — `voyage.depart` sets `port_id = null, lat = null`
// in the same statement that opens the voyage (0047:495), and an open anchor clears `port_id`
// (0047:993) — so the precedence only matters on a payload that is wrong. It is VOYAGE FIRST,
// because a SAILING voyage row is the server's live record of a passage and is what moves her;
// the chart already drew her that way, and the chart is what the player trusts. Then the port,
// then the anchor. A fleet with none of the three is "unplaced" and prints her served status.
//
// ── THE SENTENCE ───────────────────────────────────────────────────────────────────────────────
//   docked     `Lisbon`
//   anchored   `anchored · 33.0°N 15.0°W`
//   sailing    `to Cádiz` / `to 33.0°N 15.0°W` / `to open sea`, and ` · 4m` when a clock is given
//   unplaced   the served status, lower-case (`adrift`)
//
// Pure: no React, no store, no clock (an instant is passed in).

import type { LatLon } from '../../lib/geo'
import { formatRealShort, instantMs, pointLabel } from '../../lib/format'

/** What the rule reads — structural, so `FleetView`, a merchant's `TrafficFleet` and a harbour's
 *  `PortMerchant` all satisfy it without either side knowing about the other's extra keys. */
export interface WhereFacts {
  readonly status: string
  readonly port: string | null
  readonly anchor: readonly [number, number] | null
  readonly voyage: {
    readonly to: string | null
    readonly dest_point?: readonly [number, number] | null
    readonly eta: string
  } | null
}

export type Whereabouts =
  | {
      readonly kind: 'sailing'
      /** The PORT she is bound for, by code; null when bound for a bare point of water (0039). */
      readonly to: string | null
      readonly point: LatLon | null
      readonly etaMs: number | null
    }
  | { readonly kind: 'docked'; readonly port: string }
  | { readonly kind: 'anchored'; readonly at: LatLon }
  | { readonly kind: 'unplaced'; readonly status: string }

/** THE ONE CLASSIFICATION. Every screen, the chart and the merchant line read this. */
export function whereabouts(f: WhereFacts): Whereabouts {
  const v = f.voyage
  if (v) {
    return {
      kind: 'sailing',
      to: v.to,
      point: v.dest_point ? { lat: v.dest_point[0], lon: v.dest_point[1] } : null,
      etaMs: instantMs(v.eta),
    }
  }
  if (f.port) return { kind: 'docked', port: f.port }
  if (f.anchor) return { kind: 'anchored', at: { lat: f.anchor[0], lon: f.anchor[1] } }
  return { kind: 'unplaced', status: f.status }
}

/** Where a sailing fleet is bound, by name: the harbour, the point of water, or "open sea". */
export function boundForLabel(
  w: { readonly to: string | null; readonly point: LatLon | null },
  portName: (code: string) => string,
): string {
  if (w.to) return portName(w.to)
  if (w.point) return pointLabel(w.point)
  return 'open sea'
}

/**
 * THE ONE LINE ABOUT WHERE SHE IS. With `nowMs`, a sailing fleet's line carries the countdown to
 * the SERVER's arrival instant (`to Cádiz · 4m`); without it, the caller prints its own clock.
 */
export function whereLine(w: Whereabouts, portName: (code: string) => string, nowMs?: number): string {
  switch (w.kind) {
    case 'docked':
      return portName(w.port)
    case 'anchored':
      return `anchored · ${pointLabel(w.at)}`
    case 'sailing': {
      const to = `to ${boundForLabel(w, portName)}`
      if (nowMs === undefined) return to
      return `${to} · ${w.etaMs !== null ? formatRealShort(w.etaMs - nowMs) : '—'}`
    }
    case 'unplaced':
      return w.status.toLowerCase()
  }
}
