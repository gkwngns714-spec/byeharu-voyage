// THE SPECS SAIL LIKE PLAYERS SAIL (0039): they PROPOSE a course over the served raster and the
// server verifies and measures it. This fixture is the one place the rpc specs get that proposal
// from — the same `src/lib/sea` search and the same `domain/passage` reading the app itself uses,
// so a spec cannot quietly grow a second pathfinder.

import { navFromServed, type SeaNav } from '../src/lib/sea'
import { proposeCourse, sailTarget } from '../src/domain/passage'
import { expectOk, worldSeaRaster, type SnapshotPort } from '../src/lib/rpc'

let nav: SeaNav | null = null

/** The served raster, unpacked once per spec file. */
export async function seaNav(): Promise<SeaNav> {
  if (!nav) nav = navFromServed(expectOk(await worldSeaRaster()))
  return nav
}

/** A proposed course between two coordinates, or a loud throw — a spec that meant to sail must
 *  never quietly sail nothing. */
export function courseBetween(
  grid: SeaNav,
  from: { lat: number; lon: number },
  to: { lat: number; lon: number },
): [number, number][] {
  const path = proposeCourse(grid, from, to)
  if (!path) throw new Error(`no sea course from ${from.lat},${from.lon} to ${to.lat},${to.lon}`)
  return path
}

/**
 * A proposed course between two HARBOURS — roads to roads (0076).
 *
 * The one place a spec turns a port into a course end, and it does it the way the app does: through
 * `domain/passage`'s `sailTarget`, which answers with the port's SERVED roadstead. A spec that
 * sailed quay to quay would be refused `E_OFF_COURSE` by `cmd.do_sail` for any port snapping
 * further than the 15 nm join tolerance — Lisbon is 23.30 nm out — and it would be refused for the
 * right reason, so weakening the server is not the fix. This is.
 */
export function courseBetweenPorts(
  grid: SeaNav,
  from: SnapshotPort,
  to: SnapshotPort,
): [number, number][] {
  const byCode = { [from.code]: from, [to.code]: to }
  const a = sailTarget({ dest: from.code }, byCode)
  const b = sailTarget({ dest: to.code }, byCode)
  if (!a || !b) throw new Error(`no roadstead for ${from.code} or ${to.code}`)
  return courseBetween(grid, a, b)
}
