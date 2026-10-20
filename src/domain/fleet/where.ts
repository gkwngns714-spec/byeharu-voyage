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
// one now ASKS this file. A second pass the same day folded the bare `f.port === code` /
// `f.port ? …` / `f.voyage ? …` tests that decided "docked here" or "at sea" on their own:
// `housePortCode`, PORT's alongside test and its "orders will run there" note, `standingOf`
// (map/sendRules), the send row's mark, the route editor's home stop, MerchantsHere / MAP's
// "lying here" (`isDockedAt`) and worldStore's `afterTrade`.
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
import { getLocale, t } from '../../lib/i18n'

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
    /** Where the server placed her on this leg. Optional for the serve-order reason `dest_point`
     *  is: a read that carries no position simply has no coordinate to offer. */
    readonly position?: { readonly lat: number; readonly lon: number } | null
  } | null
}

export type Whereabouts =
  | {
      readonly kind: 'sailing'
      /** The PORT she is bound for, by code; null when bound for a bare point of water (0039). */
      readonly to: string | null
      readonly point: LatLon | null
      readonly etaMs: number | null
      /**
       * WHERE SHE IS NOW — the SERVED position on her leg (`voyage.position`), the same point the
       * chart draws her at. Null only when the server did not place her.
       *
       * 2026-10-20 (the owner, request 184: *"I want to be able to click on npc name like location,
       * and then point me to that location like for cities."*). A row's "where" was three words and
       * no coordinate, so the map's go-to (src/chart/goTo.ts) could take you to a harbour she lies
       * in and to an anchor she rides at, and did NOTHING for a merchant at sea unless the chart
       * happened to be drawing her — and the sea window is capped, so the merchant in a city's
       * "Incoming" list usually is not drawn. The classification now carries the one coordinate it
       * always had in front of it.
       */
      readonly at: LatLon | null
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
      at: v.position ? { lat: v.position.lat, lon: v.position.lon } : null,
    }
  }
  if (f.port) return { kind: 'docked', port: f.port }
  if (f.anchor) return { kind: 'anchored', at: { lat: f.anchor[0], lon: f.anchor[1] } }
  return { kind: 'unplaced', status: f.status }
}

/**
 * A PIECE OF A "WHERE" SENTENCE — plain words, or the name of a PLACE (a harbour by code, or a
 * point of water) that a screen may draw as a go-to link (src/chart/goTo.ts). The sentence is
 * written ONCE, here, as pieces; `whereLine` is those pieces joined, so the linked line and the
 * plain line can never say different things.
 */
export type WherePiece =
  | string
  | { readonly text: string; readonly port: string }
  | { readonly text: string; readonly at: LatLon }

/** The words of a piece, link or not. */
export function pieceText(p: WherePiece): string {
  return typeof p === 'string' ? p : p.text
}

/** Pieces joined back into the one line. */
export function joinPieces(pieces: readonly WherePiece[]): string {
  return pieces.map(pieceText).join('')
}

/** Where a sailing fleet is bound, as a piece: the harbour, the point of water, or "open sea". */
export function boundForPiece(
  w: { readonly to: string | null; readonly point: LatLon | null },
  portName: (code: string) => string,
): WherePiece {
  if (w.to) return { text: portName(w.to), port: w.to }
  if (w.point) return { text: pointLabel(w.point), at: w.point }
  return t('domain.openSea')
}

/** Where a sailing fleet is bound, by name: the harbour, the point of water, or "open sea". */
export function boundForLabel(
  w: { readonly to: string | null; readonly point: LatLon | null },
  portName: (code: string) => string,
): string {
  return pieceText(boundForPiece(w, portName))
}

/** THE ONE SENTENCE ABOUT WHERE SHE IS, in pieces (see `WherePiece`). */
export function whereParts(w: Whereabouts, portName: (code: string) => string, nowMs?: number): WherePiece[] {
  switch (w.kind) {
    case 'docked':
      return [{ text: portName(w.port), port: w.port }]
    case 'anchored':
      return [t('domain.anchored'), { text: pointLabel(w.at), at: w.at }]
    case 'sailing': {
      // English puts the word before the place (`to Lisbon`); Korean after it (`리스본행`).
      const place = boundForPiece(w, portName)
      const to: WherePiece[] = getLocale() === 'en' ? [t('domain.to'), place] : [place, t('domain.toSuffix')]
      if (nowMs === undefined) return to
      return [...to, ` · ${w.etaMs !== null ? formatRealShort(w.etaMs - nowMs) : '—'}`]
    }
    case 'unplaced':
      return [w.status.toLowerCase()]
  }
}

/**
 * THE ONE LINE ABOUT WHERE SHE IS. With `nowMs`, a sailing fleet's line carries the countdown to
 * the SERVER's arrival instant (`to Cádiz · 4m`); without it, the caller prints its own clock.
 */
export function whereLine(w: Whereabouts, portName: (code: string) => string, nowMs?: number): string {
  return joinPieces(whereParts(w, portName, nowMs))
}

/** Is she lying in THIS harbour — the one "alongside here" test (PORT's read-only gate, a
 *  harbour's merchant list, MAP's "lying here"). Through `whereabouts`, so a SAILING row is never
 *  counted as alongside on the strength of a stale `port`. */
export function isDockedAt(f: WhereFacts, portCode: string): boolean {
  const w = whereabouts(f)
  return w.kind === 'docked' && w.port === portCode
}

/**
 * WHO OF YOURS ACTS FOR A HARBOUR — the fleets lying in it, and the one fleet whose orders and
 * hold a screen about that harbour reads: one alongside first, else the hull the command draft
 * holds, else the first. PORT spelt this inline; the MAP's city panel (2026-10-15) is its second
 * caller, so it lives here once.
 */
export function alongsideAt<F extends WhereFacts & { readonly id: string }>(
  fleets: readonly F[],
  portCode: string,
  draftFleetId: string | null,
): { docked: F[]; acting: F | null } {
  const docked = fleets.filter((f) => isDockedAt(f, portCode))
  const acting = docked[0] ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
  return { docked, acting }
}
