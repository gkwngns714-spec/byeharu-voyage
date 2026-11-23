// THE PLAN BEING MADE (docs/COMMAND_DESK.md §3.5, §6) — one good, one city to buy it at (or what is on
// board), one city to sell it at, how many, and the two limits. A draft, like the order draft and the
// route editor's: session storage — it survives a reload and dies with the tab. Since owner row 229 the
// Buy / Sell panel makes one-ended trips: Sail & buy (buyAt only) and Sail & sell (sellAt only). The order
// lines a plan queues are composed in `src/domain/plan` (0480: moved out of planLines.ts) — the grammar's own text — and nowhere else.
// ("Make it a route", the route editor's seed, went with the two-ended trade card, 2026-10-26.)

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import type { PlanDraft } from '../../../domain/plan'

export interface DeskPlanState {
  plan: PlanDraft | null
  open: (plan: PlanDraft) => void
  set: (patch: Partial<PlanDraft>) => void
  close: () => void
}

export const useDeskPlan = create<DeskPlanState>()(
  persist(
    (set) => ({
      plan: null,
      open: (plan) => set({ plan }),
      set: (patch) => set((s) => (s.plan ? { plan: { ...s.plan, ...patch } } : s)),
      close: () => set({ plan: null }),
    }),
    {
      name: 'byeharu-voyage.desk-plan.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ plan: s.plan }),
      // A byte with a field missing reads as NONE, never as `undefined`.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<DeskPlanState>
        return { ...current, plan: p.plan ?? null }
      },
    },
  ),
)
