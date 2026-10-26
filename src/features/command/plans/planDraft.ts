// THE PLAN BEING MADE (docs/COMMAND_DESK.md §3.5, §6) — one good, one city to buy it at (or what is on
// board), one city to sell it at, how many, and the two limits. A draft, like the order draft and the
// route editor's: session storage — it survives a reload and dies with the tab. Since owner row 229 the
// Buy / Sell panel makes one-ended trips: Sail & buy (buyAt only) and Sail & sell (sellAt only). The order
// lines a plan queues are composed in `planLines.ts` — the grammar's own text — and nowhere else.
// ("Make it a route", the route editor's seed, went with the two-ended trade card, 2026-10-26.)

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
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
  /** 0213: insure the cargo — ` INSURED` on every laden SAIL line (planLines.ts). Absent on a draft
   *  written before 0213, which reads as not asked. */
  insure?: boolean
}

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
