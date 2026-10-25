import type { LatLon } from '../../lib/geo'
import type { FleetView, PreviewResult, Refusal } from '../../lib/rpc'
import { whereabouts } from '../../domain/fleet'
import { pointToken } from '../../domain/passage'
import { pointLabel } from '../../lib/format'

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

/** A refusal's fix as a real press: a queue act, or an order run in place. */
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
  // In port, at anchor or at sea is `domain/fleet`'s one rule; this only matches the place to `dest`.
  const where = whereabouts(f)
  const lies =
    dest.kind === 'port'
      ? where.kind === 'docked' && where.port === dest.code
      : where.kind === 'anchored' && pointToken(where.at) === key
  const bound =
    where.kind === 'sailing' &&
    (dest.kind === 'port' ? where.to === dest.code : where.point !== null && pointToken(where.point) === key)
  return lies ? 'lies' : bound ? 'bound' : where.kind === 'sailing' ? 'turn' : 'send'
}

export function canGo(standing: Standing): boolean {
  return standing === 'send' || standing === 'turn'
}

