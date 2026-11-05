import { useLiveRead } from './liveRead'
import { ok, worldTownHall } from '../lib/rpc'
import type { Refusal, TownHallView } from '../lib/rpc'

// THE ONE CLIENT READING OF `world.town_hall(port)` (0122/0123/0144).
//
// Written inside CityTownHall.tsx on 2026-10-15 and taken out of it on 2026-10-20, when the city
// panel's Info tab (owner row 174) became a SECOND caller: who holds a city, its purse and its
// influence are one served block, and two faces asking it must ask it the same way or they will
// drift in what a refusal means.
//
// LIVE LIKE STATS (owner, 2026-11-05: *"the HQ, city hall, population and gold change, can it be live
// like stats?"*): the read rides `useLiveRead` (src/live/liveRead.ts), so the purse and the people move
// on screen every second without leaving the page. Every caller of one port shares ONE timer and ONE ask
// in flight (the City page's HQ header, the hall panel and the Info tab are three callers): a mounted
// page asks ONCE a second, never once per face. A remount draws the last answer at once (`keep`).

/** The served answer or the served refusal, folded into one value (useOrderPreview's shape). */
interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

export function useTownHall(portId: string | null) {
  return useLiveRead<Served<TownHallView>>(
    portId === null ? null : `hall:${portId}`,
    async () => {
      const r = await worldTownHall(portId as string)
      return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
    },
    '',
    true,
  )
}
