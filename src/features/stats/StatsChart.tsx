import { useState, type ComponentProps } from 'react'
import { SeriesChart, SpanPicker, Tray, type TrayDetent } from '../../components/ui'
import { useChartSpan } from '../../store/chartSpan'

// A STATS CHART THAT OPENS LARGE (owner row 232, 2026-10-26: "i want to see in large graph, like sell and buy, for stats
// chart to when tapped. it needs data that saves for months too").
//
// The tab's small line is a press target. Pressing it opens the SAME `Tray` the Buy / Sell good page opens its price
// chart in (TradePanel.tsx: the bottom tray on a phone, the side pane on a wide glass), holding the SAME `SpanPicker`
// (1d · 1w · 1m · 1y · All, the one `useChartSpan` for every chart) over the SAME `SeriesChart`, drawn large. One chart
// component, one picker, one tray: no second chart system. The tray is `position: fixed`, so pressing never moves
// the page under it (the desk's law). The span reaches the server through the face's read (0246: world.stats_* take a
// span), so the small line and the large one are always the same series.

const BIG = { width: 640, height: 280 }

export function StatsChart({ title, ...chart }: { title: string } & ComponentProps<typeof SeriesChart>) {
  const [detent, setDetent] = useState<TrayDetent>('closed')
  const { span, setSpan } = useChartSpan()
  return (
    <>
      <button type="button" onClick={() => setDetent('full')} className="block w-full min-w-0 text-left" data-testid="stats-chart-tap">
        <SeriesChart {...chart} />
      </button>
      {detent !== 'closed' && (
        <Tray detent={detent} onDetentChange={setDetent} title={title} data-testid="stats-big-chart">
          <SpanPicker value={span} onChange={setSpan} />
          <SeriesChart {...chart} size={BIG} className="mt-3" />
        </Tray>
      )}
    </>
  )
}
