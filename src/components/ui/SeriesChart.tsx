import { useMemo, useState, type PointerEvent, type ReactNode } from 'react'
import { nearestDot, seriesChartModel, type SeriesPoint } from './seriesChartModel'

// ONE FIGURE OVER TIME — the small-multiple line the Stats tab is made of (seriesChartModel.ts says why
// one series, one axis). Thin line (1.5), a faint wash to the floor, three y figures in the caption
// voice, the x axis in "how long ago", and a HOVER LAYER: a rule at the nearest point with its value,
// because a chart on a screen is an instrument, not a picture. The caller formats the value (lib/format
// owns the formatting; this owns the shape) and names the tone: accent for yours, success / danger for
// gain / loss, info for a neutral quantity that moves, muted for a context line.

export type SeriesTone = 'accent' | 'success' | 'danger' | 'info' | 'muted'

const STROKE: Record<SeriesTone, string> = {
  accent: 'stroke-accent',
  success: 'stroke-success',
  danger: 'stroke-danger',
  info: 'stroke-info',
  muted: 'stroke-ink-muted',
}
const FILL: Record<SeriesTone, string> = {
  accent: 'fill-accent-soft',
  success: 'fill-success-soft',
  danger: 'fill-danger-soft',
  info: 'fill-info-soft',
  muted: 'fill-surface-2',
}

export function SeriesChart({
  points,
  format,
  label,
  tone = 'accent',
  size,
  empty = null,
  className = '',
}: {
  /** Served instants and values; any order. Fewer than two and `empty` is drawn in its place. */
  points: readonly SeriesPoint[]
  /** How a value reads (formatDucats, formatInt…). */
  format: (v: number) => string
  /** Announced to assistive tech, which cannot see a line. */
  label: string
  tone?: SeriesTone
  size?: { width: number; height: number }
  /** WHAT STANDS WHERE THE LINE WOULD BE while the record is too short to draw one (2026-10-20,
   *  owner request 188). A chart that renders NOTHING is read as a missing feature — the tab's
   *  first hour has one row per figure, and the owner's words that day were "no charts". A caller
   *  that can say why ("the line starts with the next count") passes that line here; a caller that
   *  cannot leaves it null, which is the old behaviour exactly. */
  empty?: ReactNode
  className?: string
}) {
  const model = useMemo(() => seriesChartModel(points, size), [points, size])
  const [hover, setHover] = useState<number | null>(null)
  if (!model) return <>{empty}</>
  const { plot } = model
  const floor = plot.y + plot.h
  const dot = hover === null ? null : nearestDot(model, hover)

  const onMove = (e: PointerEvent<SVGSVGElement>) => {
    const box = e.currentTarget.getBoundingClientRect()
    setHover(((e.clientX - box.left) / box.width) * model.width)
  }

  return (
    <div className={`relative w-full ${className}`} data-testid="series-chart">
      <svg
        viewBox={`0 0 ${model.width} ${model.height}`}
        className="block h-auto w-full touch-pan-y"
        role="img"
        aria-label={label}
        onPointerMove={onMove}
        onPointerLeave={() => setHover(null)}
      >
        {model.yTicks.map((t, i) => (
          <line key={i} x1={plot.x} x2={plot.x + plot.w} y1={t.y} y2={t.y} className="stroke-edge" strokeWidth={1} />
        ))}
        <path d={model.area} className={FILL[tone]} stroke="none" />
        <path d={model.line} fill="none" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" className={STROKE[tone]} />
        {model.xTicks.map((t, i) => (
          <text
            key={t.label + i}
            x={t.x}
            y={model.height - 4}
            textAnchor={i === 0 ? 'start' : i === model.xTicks.length - 1 ? 'end' : 'middle'}
            className="fill-ink-faint text-t-caption tabular-nums"
          >
            {t.label}
          </text>
        ))}
        {dot && (
          <g data-testid="series-chart-hover">
            <line x1={dot.x} x2={dot.x} y1={plot.y} y2={floor} className="stroke-ink-faint" strokeWidth={1} />
            <circle cx={dot.x} cy={dot.y} r={3.5} className={`${FILL[tone]} ${STROKE[tone]}`} strokeWidth={1.5} />
          </g>
        )}
      </svg>
      {/* the three y figures and the hovered value live in HTML, so they wear the type scale */}
      <div
        className="pointer-events-none absolute right-2 flex flex-col justify-between text-right"
        style={{ top: `${(plot.y / model.height) * 100}%`, height: `${(plot.h / model.height) * 100}%` }}
      >
        <span className="text-t-caption tabular-nums text-ink-faint">{format(model.yTicks[2].value)}</span>
        <span className="text-t-caption tabular-nums text-ink-faint">{format(model.yTicks[0].value)}</span>
      </div>
      {dot && (
        <div className="pointer-events-none absolute left-2 top-1 rounded-control bg-surface-2 px-2 py-0.5 text-t-caption tabular-nums text-ink">
          {format(dot.value)} · {new Date(dot.atMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </div>
      )}
    </div>
  )
}

export type { SeriesPoint }
