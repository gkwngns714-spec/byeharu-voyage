// HOW FAR BACK EVERY PRICE CHART LOOKS (0225, owner row 205: "i want to see them in weeks, years even").
//
// ONE span for every chart, not one per chart: the player who presses "1 month" on the good page wants
// a month on the quay's tray too, and a span is a preference about reading, not a fact about a good.
// A store, not a prop chain, because it has four readers on day one (the COMMAND desk's good page, the
// desk's trade fold, PORT's price tray and the quay's trade tray) and each would otherwise carry its own
// copy. The spans themselves are the server's (`PRICE_SPANS`, world.price_series); this file only
// remembers which one is pressed. Session storage, like the desk's good: it survives a reload and dies
// with the tab.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { PRICE_SPANS, type PriceSpan } from '../lib/rpc'

export interface ChartSpanState {
  span: PriceSpan
  setSpan: (span: PriceSpan) => void
}

/** The span a chart opens on: the fine record, one day — the most line there always is. */
export const CHART_SPAN_DEFAULT: PriceSpan = '1d'

export const useChartSpan = create<ChartSpanState>()(
  persist(
    (set) => ({
      span: CHART_SPAN_DEFAULT,
      setSpan: (span) => set({ span: PRICE_SPANS.includes(span) ? span : CHART_SPAN_DEFAULT }),
    }),
    {
      name: 'byeharu-voyage.chart-span.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ span: s.span }),
    },
  ),
)
