import type { LatLon } from '../../lib/geo'
import type { FleetView, PreviewResult, Refusal } from '../../lib/rpc'
import { pointLabel, pointToken } from '../../domain/passage'

// THE SEND FLOW'S RULES AS DATA — no React, no store, so each one can be read without a browser.
// `useSendFleet.ts` is the one caller; the same split `watersRows.ts` / `WatersAhead.tsx` uses.

/** The place the act is about: a harbour, or a pinpointed spot of open water (0039). */
export type SailDest =
  | { readonly kind: 'port'; readonly code: string; readonly name: string }
  | { readonly kind: 'sea'; readonly at: LatLon }

/**
 * WHERE SHE STANDS RELATIVE TO THIS DESTINATION — the flow's ONE verdict about a fleet, read by
 * the dry runs, by the row, and by the line that says the whole list is dead. There were two of
 * these once and they disagreed (a `sendable` that excluded every fleet at sea, and a row-local
 * `!lies && !bound` that called those same fleets pressable).
 *   send  — lying at a quay or an anchor somewhere else: a real passage, previewed
 *   turn  — already at sea and bound elsewhere: her act is a divert, judged at the helm
 *   lies  — she is already AT this destination
 *   bound — she is already sailing to it
 */
export type Standing = 'send' | 'turn' | 'lies' | 'bound'

/** The server's verdict on one fleet's passage to this place — the dry run's answer, kept whole. */
export type Verdict =
  | { kind: 'ok'; result: PreviewResult }
  | { kind: 'refused'; refusal: Refusal }
  /** The call came back with neither an estimate nor a refusal; the row stops saying "checking". */
  | { kind: 'silent' }

export interface Act {
  fleetId: string
  state: 'busy' | 'sent' | 'refused'
  refusal: Refusal | null
}

/** A refusal's fix as a real press: a queue act, an order run in place, or the composer. */
export interface Fix {
  label: string
  run: () => void
}

export function destName(dest: SailDest): string {
  return dest.kind === 'port' ? dest.name : pointLabel(dest.at)
}

export function destKey(dest: SailDest): string {
  return dest.kind === 'port' ? dest.code : pointToken(dest.at)
}

/** THE ONE INTENT'S ARGS — the same tokens a hand-off would carry and the order line will read. */
export function destArgs(dest: SailDest): Record<string, string> {
  return dest.kind === 'port' ? { dest: dest.code } : { dest_point: pointToken(dest.at) }
}

export function standingOf(dest: SailDest, f: FleetView): Standing {
  const key = destKey(dest)
  const lies =
    dest.kind === 'port'
      ? f.port === dest.code
      : f.anchor != null && pointToken({ lat: f.anchor[0], lon: f.anchor[1] }) === key
  const bound =
    f.voyage != null &&
    (dest.kind === 'port'
      ? f.voyage.to === dest.code
      : f.voyage.dest_point != null &&
        pointToken({ lat: f.voyage.dest_point[0], lon: f.voyage.dest_point[1] }) === key)
  return lies ? 'lies' : bound ? 'bound' : f.voyage != null ? 'turn' : 'send'
}

export function canGo(standing: Standing): boolean {
  return standing === 'send' || standing === 'turn'
}

/** A whole number of days, never less than one — the shape the book's `days` column takes. It
 *  ROUNDS UP, because a target rounded down does not cover the thing it was read from. Not a rule
 *  about provisioning: the server judges every one of these. */
export function atLeastOneDay(days: number): number {
  return Number.isFinite(days) ? Math.max(1, Math.ceil(days)) : 1
}
