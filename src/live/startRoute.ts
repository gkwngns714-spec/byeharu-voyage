import { routeName, routePayload, type RouteStopDraft } from './standingRouteDraft'
import { useWorld } from './worldStore'
import type { Refusal } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SAVE A DRAFT AND START IT — the one path from a route draft to a route that runs.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// §7B (docs/NO_SPAGHETTI.md):
//   CONCEPT       "a drafted route becomes a saved route, and that route is put on its fleet":
//                 routePayload → cmd.standing_route_save → cmd.standing_route_assign.
//   LIVES HERE    src/live, beside the draft (standingRouteDraft.ts). Born when the route got its second door
//                 (2026-11-16, the content plan's slice B): the route editor's Start, and the arrival card's
//                 "Repeat as a route", which turns the trip just sailed into a route in one press. Both call this,
//                 so the two doors cannot drift into two ways of making a route.
//   WRONG SHAPE   a rule of the game decided here (whether the route is legal, affordable, too long): every one
//                 is the server's, at save and at assign, and comes back as the Refusal it sent.

export type StartRouteResult =
  | { ok: true; id: string }
  /** No water for the leg that leaves this port (by CODE): nothing was sent. */
  | { ok: false; noCourseFrom: string; id: string | null }
  /** The server refused the save or the start. `id` is the saved route's when only the start was refused. */
  | { ok: false; refusal: Refusal | null; id: string | null }

/**
 * Save `stops` (as route `savedId` when it was saved before, else as a new route) and start it on `fleetId`.
 * `alreadyRunning`: the route being saved is the one this fleet runs; an edit takes effect at its next stop, so
 * nothing is started.
 */
export async function saveAndStartRoute(
  stops: readonly RouteStopDraft[],
  fleetId: string,
  savedId: string | null,
  alreadyRunning = false,
): Promise<StartRouteResult> {
  const { seaNav, portByCode, saveRoute, assignRoute } = useWorld.getState()
  if (!seaNav) return { ok: false, refusal: null, id: savedId }
  const payload = routePayload(stops, seaNav, portByCode)
  if (!payload.ok) return { ok: false, noCourseFrom: payload.noCourseFrom, id: savedId }
  const id = await saveRoute(savedId, routeName(stops, portByCode), payload.stops)
  if (!id) return { ok: false, refusal: useWorld.getState().refusal, id: savedId }
  if (alreadyRunning) return { ok: true, id }
  if (await assignRoute(id, fleetId)) return { ok: true, id }
  return { ok: false, refusal: useWorld.getState().refusal, id }
}
