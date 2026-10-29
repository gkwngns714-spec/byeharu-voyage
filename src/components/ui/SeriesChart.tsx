import { useMemo, useState, type MouseEvent, type PointerEvent, type ReactNode } from 'react'
import { nearestDot, seriesChartModel, type SeriesPoint } from './seriesChartModel'
import { newsMarksModel, type NewsMarkDot } from './newsMarksModel'
import { NewsCard } from './NewsCard'
import { newsHeadline } from '../../lib/i18n/dict/news'
import type { NewsMark } from '../../lib/rpc'
import { useLocale } from '../../lib/i18n'

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
  marks = null,
  onOpenCity,
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
  /** The news markers this chart draws (0279, owner row 216): dots on the time axis at the events'
   *  instants, press → the cause. Null draws none — the chart is exactly what it was. */
  marks?: readonly NewsMark[] | null
  /** Opens a marker's city (the caller's navigation); absent, the card offers no link. */
  onOpenCity?: (portCode: string) => void
  className?: string
}) {
  const locale = useLocale()
  const model = useMemo(() => seriesChartModel(points, size), [points, size])
  const dots = useMemo(
    () => (model && marks && marks.length > 0 ? newsMarksModel(marks, model.plot, model.window) : []),
    [model, marks],
  )
  const [pressed, setPressed] = useState<{ dot: NewsMarkDot; x: number; y: number } | null>(null)
  const shown = pressed !== null && dots.includes(pressed.dot) ? pressed : null
  const [hover, setHover] = useState<number | null>(null)
  if (!model) return <>{empty}</>
  const { plot } = model
  const floor = plot.y + plot.h
  const dot = hover === null ? null : nearestDot(model, hover)

  const onMove = (e: PointerEvent<SVGSVGElement>) => {
    const box = e.currentTarget.getBoundingClientRect()
    setHover(((e.clientX - box.left) / box.width) * model.width)
  }

  // THE FIGURES HAVE THEIR OWN SPACE (2026-10-25, owner row 199: "the gold overlaps with the chart
  // line"). The high and low figures used to be laid OVER the plot's right edge and the hovered
  // reading over its top-left corner, so wherever the line ran high or late it ran through the
  // digits. Now the plot owns its rectangle alone: the reading stands in a header line above it
  // (always one line tall — the newest reading until a finger or pointer picks another, so a hover
  // moves nothing), and the high and low figures stand in a value column to its right. Every chart
  // this one component draws gets it; tests/align.spec.ts holds no text box over `[data-plot]`.
  const reading = dot ?? model.dots[model.dots.length - 1]
  return (
    <div className={`w-full ${className}`} data-testid="series-chart" data-chart>
      <div className="flex h-5 items-center justify-end text-t-caption tabular-nums">
        <span className={dot ? 'text-ink' : 'text-ink-faint'} data-testid="series-chart-reading">
          {format(reading.value)} · {new Date(reading.atMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </span>
      </div>
      <div className="flex items-stretch gap-2">
        <svg
          viewBox={`0 0 ${model.width} ${model.height}`}
          className="block h-auto min-w-0 flex-1 touch-pan-y"
          role="img"
          aria-label={label}
          onPointerMove={onMove}
          onPointerLeave={() => setHover(null)}
        >
          <rect x={plot.x} y={plot.y} width={plot.w} height={plot.h} fill="none" stroke="none" data-plot />
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
          {/* THE NEWS DOTS (0279, owner row 216): the same newsMarksModel geometry the price chart draws.
              No clip here, so a dot outside the window is simply not drawn. A press stops at the dot —
              the small chart's own press target (StatsChart opens the big chart) is left alone. */}
          {dots.filter((d) => d.inWindow).length > 0 && (
            <g data-testid="series-chart-marks">
              {dots
                .filter((d) => d.inWindow)
                .map((d, i) => (
                  <g key={i}>
                    {d.count > 1 && (
                      <text
                        x={d.x}
                        y={d.y - 8}
                        textAnchor="middle"
                        className="fill-ink text-t-caption tabular-nums"
                        data-testid="series-chart-mark-count"
                      >
                        {d.count}
                      </text>
                    )}
                    <circle cx={d.x} cy={d.y} r={d.r} className={d.tone === 'accent' ? 'fill-accent' : 'fill-ink-muted'} />
                    <circle
                      cx={d.x}
                      cy={d.y}
                      r={12}
                      fill="transparent"
                      className="cursor-pointer"
                      onClick={(e: MouseEvent<SVGCircleElement>) => {
                        e.stopPropagation()
                        e.preventDefault()
                        const rect = e.currentTarget.getBoundingClientRect()
                        setPressed(pressed?.dot === d ? null : { dot: d, x: rect.left + rect.width / 2, y: rect.bottom })
                      }}
                      data-testid="series-chart-mark"
                    >
                      <title>{d.items[0] && newsHeadline(d.items[0], locale)}</title>
                    </circle>
                  </g>
                ))}
            </g>
          )}
        </svg>
        {/* the high and low figures, in a column of their own beside the plot, at its top and floor */}
        <div className="relative shrink-0">
          {/* in flow but unseen: it gives the column the width of its wider figure */}
          <span className="invisible flex h-0 flex-col overflow-hidden text-t-caption tabular-nums" aria-hidden>
            <span>{format(model.yTicks[2].value)}</span>
            <span>{format(model.yTicks[0].value)}</span>
          </span>
          <div
            className="absolute inset-x-0 flex flex-col justify-between text-right"
            style={{ top: `${(plot.y / model.height) * 100}%`, height: `${(plot.h / model.height) * 100}%` }}
          >
            <span className="-translate-y-1/2 text-t-caption tabular-nums text-ink-faint">{format(model.yTicks[2].value)}</span>
            <span className="translate-y-1/2 text-t-caption tabular-nums text-ink-faint">{format(model.yTicks[0].value)}</span>
          </div>
        </div>
      </div>
      {shown && (
        <NewsCard
          dot={shown.dot}
          anchor={{ x: shown.x, y: shown.y }}
          nowMs={model.dots[model.dots.length - 1].atMs}
          onClose={() => setPressed(null)}
          onOpenCity={onOpenCity}
        />
      )}
    </div>
  )
}

export type { SeriesPoint }
