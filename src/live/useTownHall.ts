import { useServedRead } from './useServedRead'
import { ok, worldTownHall } from '../lib/rpc'
import type { Refusal, TownHallView } from '../lib/rpc'

// THE ONE CLIENT READING OF `world.town_hall(port)` (0122/0123/0144).
//
// Written inside CityTownHall.tsx on 2026-10-15 and taken out of it on 2026-10-20, when the city
// panel's Info tab (owner row 174) became a SECOND caller: who holds a city, its purse and its
// influence are one served block, and two faces asking it must ask it the same way or they will
// drift in what a refusal means. The read rides the world's beat and keeps its last answer while
// the next is on the wire (useServedRead's rule).

/** The served answer or the served refusal, folded into one value (useOrderPreview's shape). */
interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

export function useTownHall(portId: string | null) {
  return useServedRead<Served<TownHallView>>(portId, async () => {
    const r = await worldTownHall(portId as string)
    return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
  })
}
