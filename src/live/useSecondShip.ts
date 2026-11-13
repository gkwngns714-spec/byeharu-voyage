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
function counted(view: BuildingYardView | null): SecondShip | null {
  const hull = view?.hulls.filter((h) => h.buildable).reduce<BuildingYardView['hulls'][number] | null>((a, h) => (a === null || h.ducats < a.ducats ? h : a), null)
  if (!hull) return null
  const plan = yardPlan(hull, undefined, {})
  return plan.of > 0 ? { ready: plan.ready, of: plan.of } : null
}

export function useSecondShip(): SecondShip | null {
  const company = useWorld((s) => s.player?.id ?? null)
  const one = useWorld((s) => s.player?.ships === 1)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
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

  return pick?.count ?? null
}
