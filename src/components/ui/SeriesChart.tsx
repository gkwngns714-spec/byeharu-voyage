import { useEffect, useMemo, useState, type PointerEvent, type ReactNode } from 'react'
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
  height,
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
  /** A CHART OF A STATED HEIGHT, DRAWN 1 : 1 (2026-11-02, owner row 267 — *"charts get room"*). `size` is a sheet the browser then scales to
   *  the box it finds, so a chart's height was whatever its width made it (a 340 × 120 sheet in a 216-px plot is 76 px tall, and its
   *  captions shrink with it). With `height` (px) the chart is exactly that tall: it measures its own width and draws on a sheet of
   *  that width, so a pixel of the model is a pixel of the glass, the captions stay 12 px, and the plot is never squeezed. Absent,
   *  nothing changes (the price chart and the large view keep `size`). */
  height?: number
  /** WHAT STANDS WHERE THE LINE WOULD BE while the record is too short to draw one (2026-10-20,
   *  owner request 188). A chart that renders NOTHING is read as a missing feature — the tab's
   *  first hour has one row per figure, and the owner's words that day were "no charts". A caller
   *  that can say why ("the line starts with the next count") passes that line here; a caller that
   *  cannot leaves it null, which is the old behaviour exactly. */
  empty?: ReactNode
  className?: string
}) {
  // THE BOX'S OWN WIDTH, for a chart of a stated `height`: measured on the svg (a flex child, so its width is what the card leaves).
  const [node, setNode] = useState<SVGSVGElement | null>(null)
  const [boxW, setBoxW] = useState(0)
  useEffect(() => {
    if (node === null || height === undefined) return
    const read = () => setBoxW(Math.max(120, Math.round(node.getBoundingClientRect().width)))
    read()
    if (typeof ResizeObserver === 'undefined') return
    const watch = new ResizeObserver(read)
    watch.observe(node)
    return () => watch.disconnect()
  }, [node, height])
  const sheet = useMemo(() => (height !== undefined && boxW > 0 ? { width: boxW, height } : size), [height, boxW, size])
  const model = useMemo(() => seriesChartModel(points, sheet), [points, sheet])
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
          ref={setNode}
          viewBox={`0 0 ${model.width} ${model.height}`}
          style={height === undefined ? undefined : { height }}
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
    </div>
  )
}

export type { SeriesPoint }
