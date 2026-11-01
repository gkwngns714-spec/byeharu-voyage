import { useState, type ComponentProps } from 'react'
import { SeriesChart, SpanPicker, Sparkline, Tray, type TrayDetent } from '../../components/ui'
import { useT } from '../../lib/i18n'
import { useChartSpan } from '../../store/chartSpan'

// A STATS CHART THAT OPENS LARGE (owner row 232, 2026-10-26: "i want to see in large graph, like sell and buy, for stats
// chart to when tapped. it needs data that saves for months too").
//
// INLINE IT IS A MINI (owner, 2026-11-01: *"everything is folded in stats… make it compact showing
// everything possible"*): the tab used to print the full `SeriesChart` inline, which is why every
// stats block had to fold — a 100-px chart x several blocks does not fit a phone. The inline render
// is now a 14-px `Sparkline` in a 44-px press row (the press floor still binds); the press opens the
// SAME `Tray` with the SAME `SpanPicker` over the SAME `SeriesChart`, drawn large — one chart system,
// no second one.
const BIG = { width: 640, height: 280 }

export function StatsChart({ title, ...chart }: { title: string } & ComponentProps<typeof SeriesChart>) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('closed')
  const { span, setSpan } = useChartSpan()
  const values = chart.points.map((p) => p.value)
  return (
    <>
      <button type="button" onClick={() => setDetent('full')} className="flex min-h-11 w-full min-w-0 items-center gap-2 text-left" data-testid="stats-chart-tap">
        {values.length >= 2 ? (
          <Sparkline values={values} height={14} className="min-w-0 flex-1" />
        ) : (
          <span className="text-t-caption text-ink-faint">{t('stats.lineSoon')}</span>
        )}
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
