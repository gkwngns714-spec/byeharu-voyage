import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react'
import { panBackMs, panByDrag, panByKey, type ChartWindow, type PanLimits } from './chartPan'
import { priceChartModel, type ChartOutlookInput } from './priceChartModel'
import { newsMarksModel, type NewsMarkDot } from './newsMarksModel'
import { NewsCard } from './NewsCard'
import { stockLevel } from './stockLevel'
import { formatInt } from '../../lib/format'
import { newsHeadline } from '../../lib/i18n/dict/news'
import type { NewsMark, PricePoint } from '../../lib/rpc'
import { useLocale, useT } from '../../lib/i18n'

/** A COMPACT chart's height, in px (owner row 226): a modest panel, never a page. ~0.45 of its width, held between
 *  these two — 150 px on a phone, 180 px on a wide column — so the price and the Buy / Sell controls stay in view. */
const COMPACT_MIN_H = 140
const COMPACT_MAX_H = 180

// THE PRICE CHART — the sparkline, unfolded: the same served lines with an axis under them and a
// scale beside them. docs/QUAY_LEDGER.md §3 F ("the price history drawn with an axis") and
// Appendix A B (owner row 76, slice 3).
//
// It PAINTS `priceChartModel` and decides nothing. Every number on it is served or derived from
// what was served — the y labels are the record's own min, midpoint and max; the x labels are
// time before now, derived from the points and `step_seconds`; the three marks are the lowest,
// highest and latest served points of the primary line. No literal window, no interpolation, no
// tooltip: at 340 px inside a tray the honest instrument is the lines, three figures on each axis,
// and three marks.
//
// BOTH SIDES (0226, owner row 189): the city's ASK (what you pay) is the `accent` line and its BID
// (what you get) the `info` line; the PRIMARY one — the ask where the city sells the good, else the
// bid — carries the ground and the marks. On the hourly and daily tiers each side's low…high is a
// faint band under its line. The legend names both sides in the dictionary's words (Cost · Sale, the
// same two the price pair prints), so a city that only buys reads as the one line it has.
//
// COLOUR IS A TOKEN, NEVER A LITERAL (tests/duplication.spec.ts §1): the ask line and the "now" ring
// are `accent` (yours, may act), the bid line is `info`, the low mark is `danger` and the high mark
// `success` — §4.4's rule that green–red on a chart only ever mean cheap–dear — the fill is
// `accent-soft`, and the axes are `edge` and `ink-faint`. The legend under the plot names the marks
// in words so a colourblind player and a greyscale screenshot still read them.
//
// `Sparkline` stays the FOLDED form (PriceRows.tsx toggles between the two); this is not a second
// sparkline and it does not replace it.
//
// ── IT CAN BE DRAGGED (owner request 178, 2026-10-20) ──────────────────────────────────────────
// With `pan`, the plot is a surface: a drag moves the window through the record, the content
// following the finger as it does on the map, and ArrowLeft / ArrowRight walk it a quarter of a
// window at a time (the past is on the left, which is the owner's "swiping left" read literally on a
// keyboard). The arithmetic is `chartPan`'s and is proved without a pointer; this file only turns
// pixels into a call. `touch-pan-y` cedes the VERTICAL axis of a touch drag to the page, exactly as
// the map's embedded surface does, so a thumb going down a tray still scrolls the tray.
//
// EVERYTHING DRAWN IS CLIPPED TO THE PLOT once there is a window, so a point outside it leaves the
// plane at its edge instead of piling up on it (priceChartModel keeps the true x for that reason).
// Without a window nothing is clipped and the chart is what it was.

export function PriceChart({
  points,
  slotSeconds,
  nowMs,
  label,
  outlook = null,
  size,
  stockTarget = null,
  view = null,
  pan = null,
  compact = false,
  marks = null,
  onOpenCity,
}: {
  /** The served points for ONE good at ONE port, oldest first. */
  points: readonly PricePoint[]
  /** `PriceSeries.step_seconds`, so the axis can be labelled without knowing the cadence. */
  slotSeconds: number
  /** The instant the axis ends at — the moment the chart was opened. */
  nowMs: number
  /** Announced to assistive tech, which cannot see a line. */
  label: string
  /** THE SERVER'S ESTIMATE (world.price_outlook), drawn to the right of now — the COMMAND desk's good
   *  page (2026-10-18). Dashed, with its band; the best time a diamond, the arrival a rule. */
  outlook?: ChartOutlookInput | null
  /** A wider plane than a tray's, for a wider column. */
  size?: { width: number; height: number }
  /** The city's normal stock (served, 0183): draws the stock strip under the price — why it moved. */
  stockTarget?: number | null
  /** The stretch of time on the plane (`chartPan`'s `panView`). Null: the record's own span. */
  view?: ChartWindow | null
  /** Make the plot draggable: where the window stands now, how far it may go, and what to call. */
  pan?: { offsetMs: number; limits: PanLimits; onChange: (offsetMs: number) => void } | null
  /** A compact panel (owner row 226, the COMMAND good page): the plane is drawn at the column's own width (so the
   *  labels stay their size and are not magnified with it) and a modest fixed height. Ignored with `size`. */
  compact?: boolean
  /** The news markers this chart draws (0279, owner row 216): dots on the time axis at the events'
   *  instants, press → the cause. Null draws none — the chart is exactly what it was. */
  marks?: readonly NewsMark[] | null
  /** Opens a marker's city (the caller's navigation); absent, the card offers no link. */
  onOpenCity?: (portCode: string) => void
}) {
  const t = useT()
  const locale = useLocale()
  const clip = useId()
  const drag = useRef<{ id: number; x: number; offsetMs: number } | null>(null)
  const box = useRef<HTMLDivElement>(null)
  const [measured, setMeasured] = useState(0)
  // the column's own width, so a compact plane is drawn 1:1 (the ResizeObserver is the external system)
  useEffect(() => {
    const el = box.current
    if (!compact || !el) return
    const ro = new ResizeObserver((e) => setMeasured(e[0]?.contentRect.width ?? 0))
    ro.observe(el)
    setMeasured(el.getBoundingClientRect().width)
    return () => ro.disconnect()
  }, [compact])
  const plane = useMemo(
    () =>
      size ??
      (compact && measured > 0
        ? { width: Math.round(measured), height: Math.round(Math.min(COMPACT_MAX_H, Math.max(COMPACT_MIN_H, measured * 0.45))) }
        : undefined),
    [size, compact, measured],
  )
  const model = useMemo(
    () => priceChartModel(points, slotSeconds, nowMs, outlook, plane, stockTarget, view),
    [points, slotSeconds, nowMs, outlook, plane, stockTarget, view],
  )
  // THE NEWS DOTS (0279): pure geometry beside the series — the series itself never sees them. The
  // pressed dot's card stands while the dot exists; a re-read of the marks drops a dot that is gone.
  const dots = useMemo(
    () => (model && marks && marks.length > 0 ? newsMarksModel(marks, model.plot, model.window) : []),
    [model, marks],
  )
  const [pressed, setPressed] = useState<{ dot: NewsMarkDot; x: number; y: number } | null>(null)
  const shown = pressed !== null && dots.includes(pressed.dot) ? pressed : null
  if (!model) return null
  const { plot } = model
  const floor = plot.y + plot.h
  const clipBottom = model.stock ? model.stock.y + model.stock.h : floor
  const pannable = pan !== null && panBackMs(pan.limits) > 0

  /** The plot's width in CSS pixels: the viewBox is scaled to the box the svg was given. */
  const plotPx = (box: DOMRect) => (model.plot.w / model.width) * box.width

  const onPointerDown = (e: PointerEvent<SVGSVGElement>) => {
    if (!pannable || !pan) return
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { id: e.pointerId, x: e.clientX, offsetMs: pan.offsetMs }
  }
  const onPointerMove = (e: PointerEvent<SVGSVGElement>) => {
    const d = drag.current
    if (!d || !pan || d.id !== e.pointerId) return
    pan.onChange(panByDrag(d.offsetMs, e.clientX - d.x, plotPx(e.currentTarget.getBoundingClientRect()), pan.limits))
  }
  const onPointerEnd = (e: PointerEvent<SVGSVGElement>) => {
    if (drag.current?.id === e.pointerId) drag.current = null
  }
  const onKeyDown = (e: KeyboardEvent<SVGSVGElement>) => {
    if (!pannable || !pan) return
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
    e.preventDefault()
    pan.onChange(panByKey(pan.offsetMs, e.key === 'ArrowLeft', pan.limits))
  }

  return (
    <div ref={box} className="mt-1 w-full" data-testid="price-chart">
      <svg
        viewBox={`0 0 ${model.width} ${model.height}`}
        className={`block h-auto w-full ${pannable ? 'cursor-grab touch-pan-y' : ''}`}
        role="img"
        aria-label={label}
        tabIndex={pannable ? 0 : undefined}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        onKeyDown={onKeyDown}
        data-pannable={pannable ? '' : undefined}
      >
        {view && (
          <clipPath id={clip}>
            {/* the plane itself: a point outside the window leaves at the edge, it does not pile on it */}
            <rect x={plot.x} y={plot.y - 6} width={plot.w} height={clipBottom - plot.y + 12} />
          </clipPath>
        )}
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
        {/* EVERYTHING DRAWN STANDS INSIDE THE PLANE (the clip above) when there is a window */}
        <g clipPath={view ? `url(#${clip})` : undefined}>
          {/* the ground under the primary line, each side's low…high band, then both lines */}
          <path d={model.area} className="fill-accent-soft" stroke="none" />
          {model.bands.ask && <path d={model.bands.ask} className="fill-accent" fillOpacity={0.12} stroke="none" data-testid="price-chart-band-ask" />}
          {model.bands.bid && <path d={model.bands.bid} className="fill-info" fillOpacity={0.12} stroke="none" data-testid="price-chart-band-bid" />}
          {model.sides.bid && (
            <path
              d={model.sides.bid}
              fill="none"
              strokeWidth={1.5}
              strokeLinecap="round"
              strokeLinejoin="round"
              className="stroke-info"
              data-testid="price-chart-bid"
            />
          )}
          {model.sides.ask && (
            <path
              d={model.sides.ask}
              fill="none"
              strokeWidth={1.5}
              strokeLinecap="round"
              strokeLinejoin="round"
              className="stroke-accent"
              data-testid="price-chart-ask"
            />
          )}
          {/* THE ESTIMATE: the band (uncertainty — not yours, not a gain: ink-faint, faint), the dashed
              path from now, now's rule, the arrival's rule and the best time's diamond */}
          {model.outlook && (
            <g data-testid="price-chart-outlook">
              <path
                d={model.outlook.band}
                className="fill-ink-faint"
                fillOpacity={0.14}
                stroke="none"
                data-testid="price-chart-band"
              />
              <line
                x1={model.outlook.nowX}
                x2={model.outlook.nowX}
                y1={plot.y}
                y2={floor}
                className="stroke-edge"
                strokeWidth={1}
              />
              <path
                d={model.outlook.line}
                fill="none"
                strokeWidth={1.75}
                strokeDasharray="4 3"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="stroke-accent"
                strokeOpacity={0.75}
                data-testid="price-chart-estimate"
              />
              {model.outlook.arriveX !== null && (
                <line
                  x1={model.outlook.arriveX}
                  x2={model.outlook.arriveX}
                  y1={plot.y}
                  y2={floor}
                  className="stroke-info"
                  strokeWidth={1}
                  strokeDasharray="2 3"
                  data-testid="price-chart-arrive"
                />
              )}
              {model.outlook.best && (
                <rect
                  x={model.outlook.best.x - 4}
                  y={model.outlook.best.y - 4}
                  width={8}
                  height={8}
                  transform={`rotate(45 ${model.outlook.best.x} ${model.outlook.best.y})`}
                  className="fill-warning"
                  data-testid="price-chart-best"
                />
              )}
            </g>
          )}
          {/* THE STOCK STRIP: the city's stock on the same time axis, its normal level a dashed rule. Low
              stock is why a price stands high; the dot now takes the gauge's tone (StockGauge). */}
          {model.stock && (
            <g data-testid="price-chart-stock">
              <text
                x={plot.x - 6}
                y={model.stock.normalY}
                textAnchor="end"
                dominantBaseline="middle"
                className="fill-ink-faint text-t-caption"
              >
                normal
              </text>
              <line
                x1={plot.x}
                x2={plot.x + plot.w}
                y1={model.stock.y + model.stock.h}
                y2={model.stock.y + model.stock.h}
                className="stroke-edge"
                strokeWidth={1}
              />
              <line
                x1={plot.x}
                x2={plot.x + plot.w}
                y1={model.stock.normalY}
                y2={model.stock.normalY}
                className="stroke-ink-faint"
                strokeWidth={1}
                strokeDasharray="3 3"
              />
              {model.stock.area && <path d={model.stock.area} className="fill-info" fillOpacity={0.14} stroke="none" />}
              {model.stock.line && (
                <path d={model.stock.line} fill="none" strokeWidth={1.5} className="stroke-info" strokeLinejoin="round" />
              )}
              {model.stock.estimate && (
                <path
                  d={model.stock.estimate}
                  fill="none"
                  strokeWidth={1.5}
                  strokeDasharray="4 3"
                  className="stroke-info"
                  strokeOpacity={0.7}
                />
              )}
              {model.stock.now && (
                <circle
                  cx={model.stock.now.x}
                  cy={model.stock.now.y}
                  r={3.5}
                  className={
                    stockLevel(model.stock.now.value, model.stock.target) === 'low'
                      ? 'fill-danger'
                      : stockLevel(model.stock.now.value, model.stock.target) === 'high'
                        ? 'fill-success'
                        : 'fill-ink-muted'
                  }
                >
                  <title>{t('ui.stockTitle', { stock: formatInt(model.stock.now.value), normal: formatInt(model.stock.target) })}</title>
                </circle>
              )}
            </g>
          )}
          {/* the three marks: low, high, now */}
          {model.low.index >= 0 && (
            <circle cx={model.low.x} cy={model.low.y} r={3.5} className="fill-danger" data-testid="price-chart-low" />
          )}
          {model.high.index >= 0 && (
            <circle cx={model.high.x} cy={model.high.y} r={3.5} className="fill-success" data-testid="price-chart-high" />
          )}
          <circle
            cx={model.now.x}
            cy={model.now.y}
            r={4.5}
            fill="none"
            strokeWidth={2}
            className="stroke-accent"
            data-testid="price-chart-now"
          />
          {/* THE NEWS DOTS (0279, owner row 216): a point on the time axis for every happening, its cause
              on the press. r = 3 drawn, a 24 px hit target; accent for imp 3, ink-muted for 1-2; a cluster
              carries its count above it. Pressing never moves a pixel of the chart. */}
          {dots.length > 0 && (
            <g data-testid="price-chart-marks">
              {dots.map((d, i) => (
                <g key={i}>
                  {d.count > 1 && (
                    <text
                      x={d.x}
                      y={d.y - 8}
                      textAnchor="middle"
                      className="fill-ink text-t-caption tabular-nums"
                      data-testid="price-chart-mark-count"
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
                    onClick={(e) => {
                      e.stopPropagation()
                      const rect = e.currentTarget.getBoundingClientRect()
                      setPressed(pressed?.dot === d ? null : { dot: d, x: rect.left + rect.width / 2, y: rect.bottom })
                    }}
                    data-testid="price-chart-mark"
                  >
                    <title>{d.items[0] && newsHeadline(d.items[0], locale)}</title>
                  </circle>
                </g>
              ))}
            </g>
          )}
        </g>
      </svg>
      {shown && (
        <NewsCard
          dot={shown.dot}
          anchor={{ x: shown.x, y: shown.y }}
          nowMs={nowMs}
          onClose={() => setPressed(null)}
          onOpenCity={onOpenCity}
        />
      )}
      <p className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-t-caption text-ink-faint" data-testid="price-chart-legend">
        {model.sides.ask && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-0.5 w-3 bg-accent" aria-hidden />
            {t('ui.youPay')}
          </span>
        )}
        {model.sides.bid && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-0.5 w-3 bg-info" aria-hidden />
            {t('ui.youGet')}
          </span>
        )}
        {model.low.index >= 0 && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rounded-chip bg-danger" aria-hidden />
            low
          </span>
        )}
        <span className="inline-flex items-center gap-1">
          <span className="inline-block h-2 w-2 rounded-chip border-2 border-accent" aria-hidden />
          now
        </span>
        {model.high.index >= 0 && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rounded-chip bg-success" aria-hidden />
            high
          </span>
        )}
        {model.outlook && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-0.5 w-3 bg-accent opacity-75" aria-hidden />
            estimate
          </span>
        )}
        {model.outlook?.best && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rotate-45 bg-warning" aria-hidden />
            best
          </span>
        )}
        {model.stock && (
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-0.5 w-3 bg-info" aria-hidden />
            stock (dashed: normal)
          </span>
        )}
      </p>
    </div>
  )
}
