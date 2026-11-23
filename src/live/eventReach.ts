import { useCallback, useEffect } from 'react'
import { voyageDaysToRealMs } from '../lib/format'
import type { WorldEvent } from '../lib/rpc'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// X8 (docs/design/roadmap-2026-11-23.md §4; the visual overhaul's slice 3): THE DESK SHOWS ONLY THE WORLD EVENTS NEAR HER.
// A famine at a harbour a day's sail away is news, not a trade she can act on this hour; it stood on the Trade desk with the events
// at her own door, and a new player read eight lines of far places before a single good. The desk now keeps the events within
// DESK_EVENT_REACH_MS of real sailing from her place (her port, or under way the city she is bound for); the rest stand on Stats >
// News, where every event is listed (features/stats/News.tsx).
//
// THE ONE DISTANCE KNOB: `DESK_EVENT_REACH_MS`. Infinity puts every event back on the desk (the removal reversed).
//
// THE DISTANCE IS SERVED: the sea miles from her place (`world.reach`, the store's session-long read, the same one the price tray's
// distance row prints) at the fleet's served formation speed (`speed_kn`), turned into real time by the one rate (lib/format,
// `voyageDaysToRealMs`). Until the reach has landed only the events at her own place are near: no far place is guessed to be close.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Two hours of real sailing: the farthest a world event stands from her place and still stands on the Trade desk. */
export const DESK_EVENT_REACH_MS = 2 * 60 * 60 * 1000

/** Real ms to sail `miles` at `knots` (null when either is not a positive figure). */
export function sailMs(miles: number, knots: number): number | null {
  if (!(miles >= 0) || !(knots > 0)) return null
  return voyageDaysToRealMs(miles / (knots * 24))
}

/** Whether an event is near enough for the desk, from `from` (a port CODE) at `knots`. */
export function useNearEvent(from: string | null, knots: number): (e: WorldEvent) => boolean {
  const portByCode = useWorld((s) => s.portByCode)
  const loadReach = useWorld((s) => s.loadReach)
  const fromId = from ? (portByCode[from]?.id ?? null) : null
  const reach = useWorld((s) => (fromId ? s.reaches[fromId] : undefined))
  useEffect(() => {
    if (fromId) void loadReach(fromId)
  }, [fromId, loadReach])
  return useCallback(
    (e: WorldEvent) => {
      if (!Number.isFinite(DESK_EVENT_REACH_MS)) return true
      if (from === null) return false
      if (e.port_code === from) return true
      const miles = reach?.reaches[e.port_code]
      if (miles === undefined) return false
      const ms = sailMs(miles, knots)
      return ms !== null && ms <= DESK_EVENT_REACH_MS
    },
    [from, reach, knots],
  )
}
