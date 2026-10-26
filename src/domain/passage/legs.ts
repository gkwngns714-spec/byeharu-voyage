// THE LEGS OF A PASSAGE — the course the one course author proposes for each SAIL, shared by the Command desk
// (a plan being made, a queued trip) and the Map (a pressed ship's whole path, owner row 225). Pure.

import { pathLengthNm, type LatLon } from '../../lib/geo'
import type { SeaNav } from '../../lib/sea'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import { proposeCourse, sailOrigin, sailTarget } from './index'

/** One SAIL of the plan (owner row 183, the Plans face's chart and leg list): where it leaves from (a port
 *  CODE, or null when the fleet starts at sea), where it goes, its proposed course and that course's miles. */
export interface PlanLeg {
  from: string | null
  to: string
  path: [number, number][]
  nm: number
}

/** Sailed miles as days at sea at this fleet's speed — the one arithmetic the plan and its words share. */
export function daysAt(nm: number, speedKn: number): number {
  return nm / speedKn / 24
}

/** ONE SAIL'S LEG — the course the one course author proposes from `from` to the harbour `code` (where the plan's
 *  SAIL lines get theirs), its miles, and where it ends. Null when no water joins them. */
export function courseLeg(
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
  from: LatLon | null,
  here: string | null,
  code: string,
): { leg: PlanLeg; at: LatLon } | null {
  const to = sailTarget({ dest: code }, portByCode)
  const course = from && to ? proposeCourse(nav, from, to) : null
  if (!to || !course) return null
  return { leg: { from: here, to: code, path: course, nm: pathLengthNm(course.map(([lat, lon]) => ({ lat, lon }))) }, at: to }
}

/** THE LEGS THROUGH HARBOURS ALREADY CHOSEN — a queued trip's SAILs, in order (owner row 217: press an order, see
 *  its route on the map). The same course author, from where the fleet is now, as `planLines` draws a plan's. The
 *  legs up to the first harbour without water; the server re-verifies every course when its SAIL runs. */
export function sailLegs(
  fleet: FleetView,
  nav: SeaNav,
  portByCode: Record<string, SnapshotPort>,
  codes: readonly string[],
): PlanLeg[] {
  const legs: PlanLeg[] = []
  let here = fleet.status === 'DOCKED' ? fleet.port : null
  let from = sailOrigin(fleet, portByCode)
  for (const code of codes) {
    if (code === here) continue
    const next = courseLeg(nav, portByCode, from, here, code)
    if (!next) break
    legs.push(next.leg)
    from = next.at
    here = code
  }
  return legs
}

