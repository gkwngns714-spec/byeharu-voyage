import { useMemo } from 'react'
import { orderTrips } from '../domain/order'
import { daysAt, type PlanLeg } from '../domain/passage'
import { routeOfFleet } from '../domain/route'
import { formatVoyageDays, instantMs, realMsToVoyageDays } from '../lib/format'
import { pathLengthNm } from '../lib/geo'
import type { FleetView } from '../lib/rpc'
import { useSailLegs } from './useSailLegs'
import { useWorld } from './worldStore'

// THE WHOLE PATH OF A PRESSED SHIP (owner row 225: *"i want to see the full paths when i press my ship, not the
// current going city"*) — the same route data Trade draws (domain/order `orderTrips`, domain/passage `sailLegs`,
// the standing route's baked courses), gathered for the Map: the leg she is on (the chart's own track draws it),
// then every queued stop after it in order, and the loop of a standing route she runs. Nothing is drawn or priced
// here: it hands back the courses (for `plannedD`) and the stops (numbered, with each leg's days).

export interface ShipPath {
  /** The courses to draw as the planned path, in order. */
  courses: readonly (readonly { lat: number; lon: number }[])[]
  /** One per stop: where the leg ends, its number and the days of that leg. */
  stops: readonly { at: { lat: number; lon: number }; n: number; days: string | null }[]
}

const NONE: ShipPath = { courses: [], stops: [] }

const toLatLon = (path: readonly (readonly [number, number])[]) => path.map(([lat, lon]) => ({ lat, lon }))

export function useShipPath(fleet: FleetView | null, nowMs: number): ShipPath {
  const portByCode = useWorld((s) => s.portByCode)
  const book = useWorld((s) => s.routes)
  const queueKey = fleet ? fleet.queue.map((o) => `${o.id}:${o.status}`).join(',') : ''

  // the harbours the live queue calls at, in order (the Trade page's reading of the same queue)
  const stops = useMemo(
    () =>
      fleet
        ? orderTrips(fleet, (c) => c in portByCode, () => false)
            .flatMap((t) => t.stops)
            .filter((c, i, all) => c !== all[i - 1])
        : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the queue's identity is its key
    [fleet?.id, queueKey, fleet?.status, fleet?.port, portByCode],
  )

  // THE CURRENT LEG is the one she is sailing: the chart's own track already draws it from her live position, so the
  // legs here start from where it ends. A voyage to a harbour not in the queue is the first stop all the same.
  const now = fleet?.voyage?.to ?? null
  const calls = useMemo(() => (now && stops[0] !== now ? [now, ...stops] : stops), [now, stops])
  const rest = now ? calls.slice(1) : calls
  const after = useMemo<FleetView | null>(
    () => (fleet && now ? { ...fleet, status: 'DOCKED', port: now, voyage: null } : fleet),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- held by what decides where she starts
    [fleet?.id, fleet?.version, now],
  )
  const legs = useSailLegs(after, rest)

  const route = fleet ? routeOfFleet(book, fleet.id) : null

  return useMemo(() => {
    if (!fleet) return NONE
    const speed = fleet.speed_kn
    const dayWords = (nm: number) => (speed > 0 ? formatVoyageDays(daysAt(nm, speed)) : null)
    const out: ShipPath['stops'][number][] = []
    const courses: ShipPath['courses'][number][] = []
    let n = 0
    if (!route && now) {
      const eta = instantMs(fleet.voyage?.eta)
      const end = fleet.voyage?.course[fleet.voyage.course.length - 1]
      if (end) out.push({ at: { lat: end[0], lon: end[1] }, n: ++n, days: eta !== null ? formatVoyageDays(realMsToVoyageDays(Math.max(0, eta - nowMs))) : null })
    }
    for (const leg of route ? [] : (legs as readonly PlanLeg[])) {
      if (leg.path.length < 2) continue
      courses.push(toLatLon(leg.path))
      const end = leg.path[leg.path.length - 1]
      out.push({ at: { lat: end[0], lon: end[1] }, n: ++n, days: dayWords(leg.nm) })
    }
    // A STANDING ROUTE is a loop: its whole lap, each stop numbered, replaces the one-off queue's path.
    if (route && route.stops.length > 0) {
      const k = route.stops.length
      const lap = route.stops.map((s) => toLatLon(s.course))
      return {
        courses: lap.filter((c) => c.length >= 2),
        stops: route.stops.flatMap((s, i) => {
          const into = lap[(i + k - 1) % k]
          return s.course.length >= 2 ? [{ at: lap[i][0], n: i + 1, days: dayWords(pathLengthNm(into)) }] : []
        }),
      }
    }
    return out.length > 0 ? { courses, stops: out } : NONE
  }, [fleet, legs, route, now, nowMs])
}
