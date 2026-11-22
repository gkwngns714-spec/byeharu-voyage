// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECOND SHIP, AS A COUNT — "Second ship 1 / 4" on Trade's goal card (S3 of docs/SECOND_SHIP.md, 0363).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// While a company has ONE ship, the first screen says how far its second one is: how many lines of the cheapest hull
// a build yard lays down for her are already in that city's storage. Both figures are the yard sheet's own
// "Ready 1 / 4": the same served read (world.building_yard, through useBuildingYard) folded by the same fold
// (./yardPlan.ts). This file adds no rule of the yard. It decides only WHICH yard the card reads, because the game
// has no home port and her goods are stored city by city:
//   · the yard of the city a fleet of hers lies in, when that city keeps one;
//   · else, or when it holds more of her lines, the yard she was last counted at (kept in this browser, per company),
//     so the figure stands while she is at sea or in a city with no yard, and a visit to a foreign yard with nothing
//     stored there does not set it back to 0.
// Nothing known yet (a new browser, at sea): null, and the card keeps its usual second line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect } from 'react'
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { hasBuilding } from '../domain/port'
import type { BuildingYardView } from '../lib/rpc'
import { useBuildingYard } from './useBuildingYard'
import { useWorld } from './worldStore'
import { yardPlan } from './yardPlan'

export interface SecondShip {
  /** Lines of the hull's recipe already stored at the yard, and how many lines there are. */
  ready: number
  of: number
  /** The port CODE of the yard counted, and whether a fleet of hers lies there now (2026-11-22 play-test: away from it, the card
   *  names its city, and its press cannot open a yard the city she lies in does not keep). */
  port: string | null
  here: boolean
  /** 0465: a hull she has ON ORDER (at this yard, else the first elsewhere), as the yard's own read serves it; null when none. The
   *  card says the order, not "materials 0 / 4": an ordered ship needs no materials. */
  order: { name: string; readyAt: string; ready: boolean } | null
  /** The yard counted, by id, and the cheapest hull it lays down for her (the one counted): what world.hull_quote is asked about. */
  portId: string | null
  hull: string
  /** 0465: the yard takes orders (the served `order` key, yard_order_enabled lit). Then the newcomer's road is the Order, and the card
   *  counts her purse against its price (2026-11-23 play-test) rather than materials she would sail half an hour for. */
  orderOn: boolean
}

/** The yard she was last counted at. A per-browser convenience: without it the card simply waits for her next call at a yard. */
const useCountedYard = create<{ company: string | null; portId: string | null; keep: (company: string, portId: string) => void }>()(
  persist(
    (set) => ({
      company: null,
      portId: null,
      keep: (company, portId) => set({ company, portId }),
    }),
    {
      name: 'byeharu-voyage.second-ship.v1',
      storage: createJSONStorage(() => {
        try {
          return localStorage
        } catch {
          return sessionStorage
        }
      }),
    },
  ),
)

/** The cheapest hull this yard lays down for her now, counted by the sheet's own fold; null when it builds her none. */
function counted(view: BuildingYardView | null): Pick<SecondShip, 'ready' | 'of' | 'order' | 'hull' | 'orderOn'> | null {
  const hull = view?.hulls.filter((h) => h.buildable).reduce<BuildingYardView['hulls'][number] | null>((a, h) => (a === null || h.ducats < a.ducats ? h : a), null)
  if (!hull) return null
  const plan = yardPlan(hull, undefined, {})
  const o = view?.order?.open ?? null
  const away = view?.order?.elsewhere[0] ?? null
  const order = o ? { name: o.name, readyAt: o.ready_at, ready: o.ready } : away ? { name: away.name, readyAt: away.ready_at, ready: away.ready } : null
  return plan.of > 0 ? { ready: plan.ready, of: plan.of, order, hull: hull.class, orderOn: view?.order?.on === true } : null
}

export function useSecondShip(): SecondShip | null {
  const company = useWorld((s) => s.player?.id ?? null)
  const one = useWorld((s) => s.player?.ships === 1)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const portById = useWorld((s) => s.portById)
  const keptAt = useCountedYard((s) => (company !== null && s.company === company ? s.portId : null))
  const keep = useCountedYard((s) => s.keep)

  const lying = one
    ? (fleets
        .map((f) => (f.port ? portByCode[f.port] : undefined))
        .find((p) => p !== undefined && hasBuilding(p, 'building_yard')) ?? null)
    : null
  const hereId = lying?.id ?? null
  const thereId = one && keptAt !== null && keptAt !== hereId ? keptAt : null
  const here = useBuildingYard(hereId)
  const there = useBuildingYard(thereId)
  const a = hereId !== null ? counted(here.view) : null
  const b = thereId !== null ? counted(there.view) : null
  // the kept yard has not answered yet: say nothing rather than a figure that may be set back
  const waiting = thereId !== null && there.view === null && there.loading
  // the yard she lies at wins only when it holds MORE of her lines than the one kept
  const pick = waiting ? null : a !== null && (b === null || a.ready > b.ready) ? { at: hereId, count: a } : b !== null ? { at: thereId, count: b } : null
  const at = pick?.at ?? null

  useEffect(() => {
    if (company !== null && at !== null && at !== keptAt) keep(company, at)
  }, [company, at, keptAt, keep])

  if (!pick) return null
  return {
    ...pick.count,
    port: (pick.at !== null ? portById[pick.at]?.code : null) ?? null,
    portId: pick.at,
    here: pick.at !== null && pick.at === hereId,
  }
}
