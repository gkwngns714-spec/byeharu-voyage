// HOW A HISTORY GRAPH GROUPS ITS DAYS (0316, owner row 289: "i want to be able to see them by days, weeks, months").
//
// ONE period for every history graph, as `useChartSpan` is one span for every chart: a choice about reading, not a fact about a good. Session storage, like the span.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { HISTORY_PERIODS, type HistoryPeriod } from '../lib/rpc'

export interface HistoryPeriodState {
  period: HistoryPeriod
  setPeriod: (period: HistoryPeriod) => void
}

export const useHistoryPeriod = create<HistoryPeriodState>()(
  persist(
    (set) => ({
      period: 'day',
      setPeriod: (period) => set({ period: HISTORY_PERIODS.includes(period) ? period : 'day' }),
    }),
    {
      name: 'byeharu-voyage.history-period.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ period: s.period }),
    },
  ),
)
