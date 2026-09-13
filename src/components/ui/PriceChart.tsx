import { useMemo } from 'react'
import { priceChartModel } from './priceChartModel'
import type { PricePoint } from '../../lib/rpc'

// THE PRICE CHART — the sparkline, unfolded: the same served line with an axis under it and a
// scale beside it. docs/QUAY_LEDGER.md §3 F ("the 48-slot price history drawn with an axis") and
// Appendix A B (owner row 76, slice 3).
//
// It PAINTS `priceChartModel` and decides nothing. Every number on it is served or derived from
// what was served — the y labels are the record's own min, midpoint and max; the x labels are
// hours before now, derived from the points and `slot_seconds`; the three marks are the lowest,
// highest and latest served points. No literal window, no interpolation, no tooltip: at 340 px
// inside a tray the honest instrument is the line, three figures on each axis, and three marks.
//
// COLOUR IS A TOKEN, NEVER A LITERAL (tests/duplication.spec.ts §1): the line and the "now" ring
// are `accent` (yours, may act), the low mark is `danger` and the high mark `success` — §4.4's
// rule that green–red on a chart only ever mean cheap–dear — the fill is `accent-soft`, and the
// axes are `edge` and `ink-faint`. The legend under the plot names the three marks in words so a
// colourblind player and a greyscale screenshot still read them.
//
// `Sparkline` stays the FOLDED form (PriceRows.tsx toggles between the two); this is not a second
// sparkline and it does not replace it.

export function PriceChart({
  points,
  slotSeconds,
  nowMs,
  label,
}: {
  /** The served points for ONE good at ONE port, oldest first. */
  points: readonly PricePoint[]
  /** `PriceHistory.slot_seconds`, so the axis can be labelled without knowing the cadence. */
  slotSeconds: number
  /** The instant the axis ends at — the moment the chart was opened. */
  nowMs: number
  /** Announced to assistive tech, which cannot see a line. */
  label: string
}) {
  const model = useMemo(() => priceChartModel(points, slotSeconds, nowMs), [points, slotSeconds, nowMs])
  if (!model) return null
  const { plot } = model
  const floor = plot.y + plot.h

  return (
    <div className="mt-1 w-full" data-testid="price-chart">
      <svg
        viewBox={`0 0 ${model.width} ${model.height}`}
        className="block h-auto w-full"
        role="img"
        aria-label={label}
      >
        {/* the y axis: three served figures, and a hairline at each */}
        {model.yTicks.map((t) => (
          <g key={t.label}>
            <line x1={plot.x} x2={plot.x + plot.w} y1={t.y} y2={t.y} className="stroke-edge" strokeWidth={1} />
            <text
              x={plot.x - 6}
              y={t.y}
              textAnchor="end"
              dominantBaseline="middle"
              className="fill-ink-faint text-t-caption tabular-nums"
              data-testid="price-chart-y"
            >
              {t.label}
            </text>
          </g>
        ))}
        {/* the x axis: the floor, and hours before now */}
        <line x1={plot.x} x2={plot.x + plot.w} y1={floor} y2={floor} className="stroke-edge" strokeWidth={1} />
        {model.xTicks.map((t, i) => (
          <text
            key={t.label}
            x={t.x}
            y={model.height - 4}
            textAnchor={i === 0 ? 'start' : i === model.xTicks.length - 1 ? 'end' : 'middle'}
            className="fill-ink-faint text-t-caption tabular-nums"
            data-testid="price-chart-x"
          >
            {t.label}
          </text>
        ))}
        {/* the line, and the ground under it */}
        <path d={model.area} className="fill-accent-soft" stroke="none" />
        <path
          d={model.line}
          fill="none"
          strokeWidth={1.5}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="stroke-accent"
        />
        {/* the three marks: low, high, now */}
        <circle cx={model.low.x} cy={model.low.y} r={3.5} className="fill-danger" data-testid="price-chart-low" />
        <circle cx={model.high.x} cy={model.high.y} r={3.5} className="fill-success" data-testid="price-chart-high" />
        <circle
          cx={model.now.x}
          cy={model.now.y}
          r={4.5}
          fill="none"
          strokeWidth={2}
          className="stroke-accent"
          data-testid="price-chart-now"
        />
      </svg>
      <p className="mt-1 flex gap-4 text-t-caption text-ink-faint" data-testid="price-chart-legend">
        <span className="inline-flex items-center gap-1">
          <span className="inline-block h-2 w-2 rounded-chip bg-danger" aria-hidden />
          low
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="inline-block h-2 w-2 rounded-chip border-2 border-accent" aria-hidden />
          now
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="inline-block h-2 w-2 rounded-chip bg-success" aria-hidden />
          high
        </span>
      </p>
    </div>
  )
}
