import { useId, useMemo, useRef, type KeyboardEvent, type PointerEvent } from 'react'
import { panBackMs, panByDrag, panByKey, type ChartWindow, type PanLimits } from './chartPan'
import { priceChartModel, type ChartOutlookInput } from './priceChartModel'
import { stockLevel } from './stockLevel'
import { formatInt } from '../../lib/format'
import type { PricePoint } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

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
}: {
  /** The served points for ONE good at ONE port, oldest first. */
  points: readonly PricePoint[]
  /** `PriceHistory.slot_seconds`, so the axis can be labelled without knowing the cadence. */
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
}) {
  const t = useT()
  const clip = useId()
  const drag = useRef<{ id: number; x: number; offsetMs: number } | null>(null)
  const model = useMemo(
    () => priceChartModel(points, slotSeconds, nowMs, outlook, size, stockTarget, view),
    [points, slotSeconds, nowMs, outlook, size, stockTarget, view],
  )
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
    <div className="mt-1 w-full" data-testid="price-chart">
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
        </g>
      </svg>
      <p className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-t-caption text-ink-faint" data-testid="price-chart-legend">
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
