import { useMemo } from 'react'
import { shutSeas, type SeaNav, type ZoneGrid } from '../lib/sea'
import { readSeaWall, type SeaWall } from '../lib/rpc'
import { useSeaConditions } from './useSeaConditions'
import { useSeaZoneCells } from './useSeas'
import { useWorld } from './worldStore'

// THE WATER A FLEET MAY SAIL (0514): the served grid with the seas shut to her closed, for the course author. Which seas are shut to
// whom is the server's answer alone (world.sea_conditions `fleets[].seas`: public.sea_refusal, the one rule); while the conditions do
// not bite this is the grid itself and nothing more is read. Her way home is the server's too (public.sea_passes): the author falls
// back to the whole water when there is no way round.

const NONE: Record<string, SeaWall> = {}

/** The seas shut to each fleet, by zone code; empty while the conditions do not bite. */
export function useShutSeas(): { bite: boolean; of: (fleetId: string | null | undefined) => Record<string, SeaWall> } {
  const view = useSeaConditions().view
  return useMemo(() => {
    const byFleet = new Map<string, Record<string, SeaWall>>()
    if (view?.bite) {
      for (const f of view.fleets) {
        const walls: Record<string, SeaWall> = {}
        for (const [code, figures] of Object.entries(f.seas ?? {})) {
          const wall = readSeaWall(figures)
          if (wall) walls[code] = wall
        }
        byFleet.set(f.id, walls)
      }
    }
    return { bite: view?.bite === true, of: (id) => (id ? (byFleet.get(id) ?? NONE) : NONE) }
  }, [view])
}

// One grid per set of shut seas (a million bytes each), kept beside the world's grid it was made from.
const GRIDS = new WeakMap<SeaNav, Map<string, SeaNav>>()
function kept(nav: SeaNav, zones: ZoneGrid | null, codes: string[]): SeaNav {
  if (codes.length === 0 || !zones) return nav
  let made = GRIDS.get(nav)
  if (!made) GRIDS.set(nav, (made = new Map()))
  const key = codes.join(' ')
  let got = made.get(key)
  if (!got) made.set(key, (got = shutSeas(nav, zones, codes)))
  return got
}

/** The grid to propose a fleet's course on; null until the world's grid has arrived. */
export function useFleetNav(): (fleetId: string | null | undefined) => SeaNav | null {
  const nav = useWorld((s) => s.seaNav)
  const shut = useShutSeas()
  const zones = useSeaZoneCells(shut.bite)
  return useMemo(() => {
    return (id) => {
      if (!nav) return null
      return kept(nav, zones, Object.keys(shut.of(id)).sort())
    }
  }, [nav, shut, zones])
}
