import { useState, type ComponentProps } from 'react'
import { SeriesChart, SpanPicker, Sparkline, Tray, type TrayDetent } from '../../components/ui'
import { useT } from '../../lib/i18n'
import { useChartSpan } from '../../store/chartSpan'

// A STATS CHART THAT OPENS LARGE (owner row 232, 2026-10-26: "i want to see in large graph, like sell and buy, for stats
// chart to when tapped. it needs data that saves for months too").
//
// The chart is a press target. Pressing it opens the SAME `Tray` the Buy / Sell good page opens its price chart in
// (TradePanel.tsx: the bottom tray on a phone, the side pane on a wide glass), holding the SAME `SpanPicker`
// (1d · 1w · 1m · 1y · All, the one `useChartSpan` for every chart) over the SAME `SeriesChart`, drawn large. One chart
// component, one picker, one tray: no second chart system. The tray is `position: fixed`, so pressing never moves
// the page under it (the desk's law). The span reaches the server through the face's read (0246: world.stats_* take a
// span), so the small line and the large one are always the same series.
//
// ON A FACE IT IS A MINI (owner, 2026-11-01: *"everything is folded in stats… make it compact showing everything
// possible"*). A face used to hold a 128-px `SeriesChart` per chart, which is why every block had to fold. Now the
// face draws the SHAPE — a `Sparkline`, 24 px tall, in a 44-px press target — and the large chart is one press
// away. `mini` carries its caption over the line; `line` is the line alone, for a place that already says what it
// is (a block's own title row). In a page (a city's own page) there is room, so it stays the full chart
// (`chart`). Below two points there is no line to draw: a word says why, as it always did.

const BIG = { width: 640, height: 280 }

export function StatsChart({
  title,
  caption,
  look = 'mini',
  ...chart
}: {
  /** The tray's title: what the large chart is. */
  title: string
  /** What the mini says it is (default: the title). */
  caption?: string
  look?: 'mini' | 'line' | 'chart'
} & ComponentProps<typeof SeriesChart>) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('closed')
  const { span, setSpan } = useChartSpan()
  const { className = '', ...big } = chart
  const drawn = chart.points.length >= 2
  return (
    <>
      <button
        type="button"
        onClick={() => setDetent('full')}
        aria-label={title}
        className={`block min-h-11 min-w-0 text-left ${look === 'line' ? 'flex-1' : 'w-full'} ${className}`}
        data-testid="stats-chart-tap"
      >
        {look === 'chart' ? (
          <SeriesChart {...chart} className="" />
        ) : (
          <>
            {look === 'mini' && <span className="block break-words text-t-caption text-ink-faint">{caption ?? title}</span>}
            {drawn ? (
              <Sparkline values={sortedValues(chart.points)} tone="even" width={120} height={24} className="mt-1 block h-6 w-full lg:h-9" label={chart.label} />
            ) : (
              <span className="mt-1 block text-t-caption text-ink-faint">{t('stats.lineSoon')}</span>
            )}
          </>
        )}
      </button>
      {detent !== 'closed' && (
        <Tray detent={detent} onDetentChange={setDetent} title={title} data-testid="stats-big-chart">
          <SpanPicker value={span} onChange={setSpan} />
          <SeriesChart {...big} size={BIG} className="mt-3" />
        </Tray>
      )}
    </>
  )
}

/** The readings oldest first — a sparkline has no time axis, so it is told the order. */
function sortedValues(points: ComponentProps<typeof SeriesChart>['points']): number[] {
  return [...points].sort((a, b) => a.atMs - b.atMs).map((p) => p.value)
}
