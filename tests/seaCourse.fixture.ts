// THE SPECS SAIL LIKE PLAYERS SAIL (0039): they PROPOSE a course over the served raster and the
// server verifies and measures it. This fixture is the one place the rpc specs get that proposal
// from — the same `src/lib/sea` search and the same `domain/passage` reading the app itself uses,
// so a spec cannot quietly grow a second pathfinder.

import { navFromServed, type SeaNav } from '../src/lib/sea'
import { proposeCourse } from '../src/domain/passage'
import { expectOk, worldSeaRaster } from '../src/lib/rpc'

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
