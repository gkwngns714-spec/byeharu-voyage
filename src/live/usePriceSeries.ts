// A GOOD'S PRICE AT A CITY OVER THE CHOSEN SPAN — one silent read per (port, good, span), kept by the
// store (0226, owner rows 189 and 205).
//
// `world.price_series(port, good, span)` decorates a price that is true without it, so a failed read is
// silent (worldStore.loadSeries) and the row says "No data yet". Every chart in the game — the COMMAND
// desk's good page and its trade fold, PORT's price tray, the quay's trade tray — opens over this one
// reading, and every one of them offers the same five spans (`SpanPicker`) from the one store
// (`useChartSpan`): a press selects the span, the store asks for that span if it has not, and the chart
// draws what came back. Until 2026-10-26 this was `usePortHistory`, one read per PORT keyed by good code
// over a twelve-hour record with one side; the shape is the design system's `PriceTrend`, declared
// beside the rows that draw it. Each field is a served reference or a primitive, so the store never hands
// back a fresh literal (worldStore rule 4).

import { useEffect } from 'react'
import type { PriceTrend } from '../components/ui'
import { useChartSpan } from '../store/chartSpan'
import { seriesKey, useWorld } from './worldStore'

/** Ensures the pair's series for the chosen span is asked for once, and returns the trend for ONE good
 *  at ONE city. A null port or good asks nothing and reads as "not landed". */
export function usePriceSeries(portId: string | null, goodId: string | null): PriceTrend {
  const span = useChartSpan((s) => s.span)
  const setSpan = useChartSpan((s) => s.setSpan)
  const key = portId && goodId ? seriesKey(portId, goodId, span) : null
  const known = useWorld((s) => (key ? s.series[key] !== undefined : true))
  const loadSeries = useWorld((s) => s.loadSeries)
  useEffect(() => {
    if (portId && goodId && !known) void loadSeries(portId, goodId, span)
  }, [portId, goodId, span, known, loadSeries])
  const series = useWorld((s) => (key ? s.series[key] : undefined))
  return { series, span, setSpan }
}
