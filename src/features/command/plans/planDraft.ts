// THE PLAN BEING MADE (docs/COMMAND_DESK.md §3.5, §6) — one good, one city to buy it at (or what is on
// board), one city to sell it at, how many, and the two limits. A draft, like the order draft and the
// route editor's: session storage — it survives a reload and dies with the tab.
//
// IT HANDS OFF, IT DOES NOT DUPLICATE. "Make it a route" writes the route editor's OWN draft shape
// (`RouteStopDraft`, standingRouteDraft.ts) into `routeSeed`; while it stands, the route fold stands
// open on a NEW route drafted from it, and the editor's close spends it. No field of a route is held
// here twice. The order lines a plan queues are composed in `planLines.ts` — the grammar's own text —
// and nowhere else.
//
// Lives in features/command (not src/store) because its hand-off is the route editor's type, and the
// route editor is this screen's.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import type { RouteStopDraft } from '../standingRouteDraft'

export interface PlanDraft {
  /** The good's CODE. */
  good: string
  /** Port CODE to buy at; null when the plan sells what is already on board. */
  buyAt: string | null
  /** Port CODE to sell at. */
  sellAt: string | null
  /** Units to buy; null = as many as fit (ALL). */
  units: number | null
  /** The most to pay a unit (BUY … AT <= max); null = any price. */
  max: number | null
  /** The least to take a unit (SELL … AT >= min); null = any price. */
  min: number | null
}

export interface DeskPlanState {
  plan: PlanDraft | null
  open: (plan: PlanDraft) => void
  set: (patch: Partial<PlanDraft>) => void
  close: () => void
  /** "Make it a route": the route editor's draft, waiting for the fold to open on it. */
  routeSeed: RouteStopDraft[] | null
  seedRoute: (stops: RouteStopDraft[]) => void
  /** The fold's editor closed (saved or not): the seed is spent. */
  clearSeed: () => void
}

export const useDeskPlan = create<DeskPlanState>()(
  persist(
    (set) => ({
      plan: null,
      open: (plan) => set({ plan }),
      set: (patch) => set((s) => (s.plan ? { plan: { ...s.plan, ...patch } } : s)),
      close: () => set({ plan: null }),
      routeSeed: null,
      seedRoute: (stops) => set({ routeSeed: stops, plan: null }),
      clearSeed: () => set({ routeSeed: null }),
    }),
    {
      name: 'byeharu-voyage.desk-plan.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ plan: s.plan, routeSeed: s.routeSeed }),
      // A byte with a field missing reads as NONE, never as `undefined`: a seed that is not null opens
      // the route editor (measured 2026-10-18 — an absent `routeSeed` stood the fold open on a new route).
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<DeskPlanState>
        return { ...current, plan: p.plan ?? null, routeSeed: p.routeSeed ?? null }
      },
    },
  ),
)
