import { MINUS, formatFixed, priceDigits } from '../../lib/format'
import type { ChartWindow } from './chartPan'
import type { OutlookPoint, PricePoint } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PRICE CHART'S GEOMETRY — pure, so the axis can be proved without a browser
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// CONCEPT (docs/NO_SPAGHETTI.md §7B): "where a served price line's points sit on a drawn plane,
// and what the axes say". One noun phrase, one file. `PriceChart.tsx` paints what this returns and
// decides nothing; `tests/priceChart.spec.ts` reads this and never mounts React.
//
// WHERE IT LIVES, AND WHY. Beside `Sparkline.tsx`, in the design system: a chart is a SHAPE on a
// screen, not a fact about the world (SECTIONS.md's table), and it is composed by `PriceRows`,
// which two trays already draw, and by the COMMAND desk's good page (2026-10-18), which adds the
// server's ESTIMATE to the right of now. One model, one painter, every caller.
//
// ── WHAT THE AXES SAY, AND WHERE THE NUMBERS COME FROM ─────────────────────────────────────────
// Every figure on the chart is SERVED or DERIVED from what was served — never a literal.
//   · y ticks: the drawn minimum, the drawn maximum, and the round midpoint between them — the
//     record's own, and with an estimate its band as well. The band is the data's own min…max, so a
//     2 % move and a halving are the same shape at different labels. The labels' decimals follow the
//     SPAN (2026-10-18: prices run from ~1 to ~100,000 a unit): a span under 1 coin reads to the
//     cent, under 10 to a tenth, and otherwise whole — so 1.20 · 1.35 · 1.50 never collapse to three
//     1s, and 98,000 · 99,000 · 100,000 carry no noise.
//   · x ticks: HOURS BEFORE NOW, ending at `now`. The span is derived from the served points and
//     `slot_seconds`: the wider of (now − the earliest `at`) and (points × slot_seconds). With an
//     estimate the axis runs on to its last served instant and is labelled `+Nh` there.
//   · marks: the lowest point, the highest point, and now. Ties go to the LATEST occurrence. With an
//     estimate: the served best time (◆) and the arrival (a rule), when the caller has them.
//
// ── THE ESTIMATE (docs/COMMAND_DESK.md §5.4) ──────────────────────────────────────────────────
// `world.price_outlook`'s points, at their served instants, drawn as a dashed line from now, with
// the band between lo and hi as one polygon. The model adds nothing to them: no smoothing, no
// interpolation, no second guess.
//
// ── THE WINDOW, AND THE DRAG (owner request 178, 2026-10-20) ───────────────────────────────────
// Given a `window` — a from and a to, which `chartPan` works out from the chosen width and how far
// back it has been dragged — the axis spans THAT stretch instead of the record's own, and x is no
// longer clamped to the plot: a point outside the window is given its true x and the PAINTER clips it
// (`PriceChart`'s clip path). So the line enters and leaves the plot's edges instead of piling up on
// them, and the y band, the x labels and the low / high marks are all read from what is INSIDE the
// window — panning back rescales to the prices you are looking at, which is what a price chart does.
// Without a window every line below behaves exactly as it did.
//
// ── WHAT IT REFUSES ────────────────────────────────────────────────────────────────────────────
// Without an estimate: fewer than two points, a point whose `at` does not parse, or a non-positive
// slot → null, as before. With one, the record may be EMPTY (a city that does not sell a good keeps
// no record of it — COMMAND_DESK D4): the estimate alone is drawn from now.

/** The drawn plane: 340×170 (docs/QUAY_LEDGER.md Appendix A B), the width of a tray column at
 *  390 px less the gutter, and tall enough for three y labels to stand apart at t-caption. */
export const PRICE_CHART_W = 340
export const PRICE_CHART_H = 170

/** Room for the y labels on the left and the x labels under the plot; the plot fills the rest. */
const PAD = { left: 48, right: 8, top: 10, bottom: 20 }

export interface ChartMark {
  x: number
  y: number
  /** The price at that point. */
  mid: number
  /** Which served point of the record it is, oldest first, or -1 for now on the estimate. */
  index: number
}

/** THE STOCK STRIP (0183; owner, 2026-10-18: "i don't see stock of the trade goods"): the city's stock
 *  under the price, on the same time axis — a trading terminal's volume pane. Its scale is 0 … the
 *  larger of twice the normal level and the most drawn, so the normal rule sits at or under the middle. */
export interface ChartStock {
  /** The strip's rectangle, under the price plot. */
  y: number
  h: number
  /** The record's stock, as a line and its ground ('' when the record carries none). */
  line: string
  area: string
  /** The estimate's stepped stock, dashed from now ('' without one). */
  estimate: string
  /** The normal level's rule. */
  normalY: number
  /** The stock now: the estimate's first point, else the record's last. */
  now: { x: number; y: number; value: number } | null
  target: number
}

/** What the estimate adds to the plane. */
export interface ChartOutlook {
  /** The dashed line, now → the last served point. */
  line: string
  /** The band, as one closed polygon (hi forward, lo back). */
  band: string
  /** `+Nh` at the right edge, where the estimate ends. */
  endLabel: string
  /** The x of now, between the record and the estimate. */
  nowX: number
  /** The served best time, when there is one. */
  best: { x: number; y: number; value: number } | null
  /** The arrival, as an x on the plot, when it falls inside it. */
  arriveX: number | null
}

export interface PriceChartModel {
  width: number
  height: number
  /** The plot rectangle inside the padding — the axes are drawn on its edges. */
  plot: { x: number; y: number; w: number; h: number }
  /** One `x,y` per served point of the record, oldest first. */
  points: { x: number; y: number }[]
  /** The line through the record, as an SVG path ('' when the record is empty). */
  line: string
  /** The record's line closed down to the plot's floor, for the fill ('' when empty). */
  area: string
  /** Drawn min · round(mid) · drawn max, each with the y it sits at. Bottom to top. */
  yTicks: { y: number; label: string }[]
  /** `−Nh` at the left edge, `−N/2h` in the middle (record only), `now`, and `+Nh` with an estimate. */
  xTicks: { x: number; label: string }[]
  /** The span the record's half of the x axis covers, in hours — derived. */
  spanHours: number
  low: ChartMark
  high: ChartMark
  now: ChartMark
  outlook: ChartOutlook | null
  /** The stock strip, when a normal level was given and any point carries a stock. */
  stock: ChartStock | null
}

/** Hours as an axis label: whole hours as `8h`, otherwise one decimal (`7.5h`). */
function hoursLabel(hours: number): string {
  const rounded = Math.round(hours * 10) / 10
  const text = Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
  return `${text}h`
}

/** An edge of a dragged window, as hours from now: `now` within a minute of it, else signed hours. */
function edgeLabel(ms: number): string {
  if (Math.abs(ms) < 60_000) return 'now'
  return `${ms < 0 ? MINUS : '+'}${hoursLabel(Math.abs(ms) / 3_600_000)}`
}

/** The y labels' decimals: by the drawn SPAN, or by the price itself when nothing moved. */
function axisDigits(lo: number, hi: number): number {
  const span = hi - lo
  if (span === 0) return priceDigits(lo)
  return span < 1 ? 2 : span < 10 ? 1 : 0
}

function axisLabel(v: number, dp: number): string {
  return formatFixed(v, dp)
}

export interface ChartOutlookInput {
  /** `world.price_outlook`'s points, k = 0 (now) first. */
  points: readonly OutlookPoint[]
  /** The served best time, when there is one. */
  bestAt?: string | null
  /** When the fleet would arrive there, ms — a rule on the plot when it falls inside it. */
  arriveMs?: number | null
}

export function priceChartModel(
  /** The served points for ONE good at ONE port, oldest first. */
  points: readonly PricePoint[],
  /** `PriceHistory.slot_seconds` — how many real seconds one served slot spans. */
  slotSeconds: number,
  /** The instant the axis ends at (or, with an estimate, where now stands), in ms. */
  nowMs: number,
  /** The server's estimate, drawn to the right of now. */
  outlook?: ChartOutlookInput | null,
  /** The plane, when the caller's column is wider than a tray's (the desk's good page). */
  size: { width: number; height: number } = {
    width: PRICE_CHART_W,
    height: PRICE_CHART_H,
  },
  /** The city's normal stock for the good (served): draws the stock strip under the price. */
  stockTarget: number | null = null,
  /** The stretch of time on the plane (`chartPan`'s `panView`). Null: the record's own span, as before. */
  view: ChartWindow | null = null,
): PriceChartModel | null {
  const est = outlook && outlook.points.length >= 2 ? outlook.points : null
  if (!(slotSeconds > 0) || !Number.isFinite(nowMs)) return null
  if (!est && points.length < 2) return null
  const ats = points.map((p) => Date.parse(p.at))
  if (ats.some((t) => !Number.isFinite(t))) return null
  const estAts = est ? est.map((p) => Date.parse(p.at)) : []
  if (estAts.some((t) => !Number.isFinite(t))) return null

  // INSIDE THE WINDOW, when there is one: the y band is the prices on the plane, not every price ever
  // served. A window that holds nothing falls back to all of them rather than dividing by nothing.
  const inView = (t: number) => !view || (t >= view.fromMs && t <= view.toMs)
  const mids = points.map((p) => p.mid)
  const all = [...mids, ...(est ? est.flatMap((p) => [p.lo, p.hi, p.value]) : [])]
  const shown = [
    ...mids.filter((_, i) => inView(ats[i])),
    ...(est ? est.filter((_, i) => inView(estAts[i])).flatMap((p) => [p.lo, p.hi, p.value]) : []),
  ]
  const drawn = shown.length ? shown : all
  const lo = Math.min(...drawn)
  const hi = Math.max(...drawn)
  const band = hi - lo

  // THE STOCK STRIP takes the bottom of the plane when there is anything to draw in it.
  const hasStock =
    stockTarget !== null &&
    stockTarget > 0 &&
    (points.some((p) => typeof p.stock === 'number') || (est?.some((p) => typeof p.stock === 'number') ?? false))
  const inner = size.height - PAD.top - PAD.bottom
  const stockH = hasStock ? Math.max(28, Math.round(inner * 0.22)) : 0
  const stockGap = hasStock ? 10 : 0
  const plot = {
    x: PAD.left,
    y: PAD.top,
    w: size.width - PAD.left - PAD.right,
    h: inner - stockH - stockGap,
  }

  // THE RECORD'S SPAN: the wider of its true age and its cadence × count, never a constant. With
  // an empty record (estimate only) it is nought, and now stands at the left edge.
  const earliest = points.length ? Math.min(...ats) : nowMs
  const spanMs = points.length ? Math.max(nowMs - earliest, points.length * slotSeconds * 1000, 1) : 0
  const spanHours = spanMs / 3_600_000
  const endMs = est ? Math.max(nowMs, ...estAts) : nowMs
  const totalMs = view ? Math.max(1, view.toMs - view.fromMs) : Math.max(spanMs + (endMs - nowMs), 1)
  const startMs = view ? view.fromMs : nowMs - spanMs

  // With a window, x is NOT clamped: a point outside it keeps its true place and the painter clips it.
  const xOf = (t: number) => {
    const f = (t - startMs) / totalMs
    return plot.x + plot.w * (view ? f : Math.max(0, Math.min(1, f)))
  }
  // A flat plane has no band to scale into: draw it through the middle rather than divide by zero,
  // because "it did not move" is a real answer (the sparkline's rule).
  const yOf = (v: number) => (band === 0 ? plot.y + plot.h / 2 : plot.y + plot.h - ((v - lo) / band) * plot.h)

  const xy = points.map((p, i) => ({ x: xOf(ats[i]), y: yOf(p.mid) }))
  const line = xy.map(({ x, y }, i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ')
  const floor = (plot.y + plot.h).toFixed(1)
  const area = xy.length ? `${line} L${xy[xy.length - 1].x.toFixed(1)} ${floor} L${xy[0].x.toFixed(1)} ${floor} Z` : ''

  // Ties go to the LATEST occurrence: the mark says where the price IS at that level. Only points on
  // the plane are marked — a low dragged off the left edge is not this chart's low.
  let lowI = -1
  let highI = -1
  for (let i = 0; i < mids.length; i++) {
    if (!inView(ats[i])) continue
    if (lowI < 0 || mids[i] <= mids[lowI]) lowI = i
    if (highI < 0 || mids[i] >= mids[highI]) highI = i
  }
  const nowValue = est ? est[0].value : mids[mids.length - 1]
  const mark = (i: number): ChartMark =>
    i >= 0 && i < xy.length
      ? { x: xy[i].x, y: xy[i].y, mid: mids[i], index: i }
      : { x: xOf(nowMs), y: yOf(nowValue), mid: nowValue, index: -1 }

  const dp = axisDigits(lo, hi)
  const factor = 10 ** dp
  const midValue = Math.round(((lo + hi) / 2) * factor) / factor
  const yTicks =
    band === 0
      ? [{ y: yOf(lo), label: axisLabel(lo, dp) }]
      : [
          { y: yOf(lo), label: axisLabel(lo, dp) },
          { y: yOf(midValue), label: axisLabel(midValue, dp) },
          { y: yOf(hi), label: axisLabel(hi, dp) },
        ]

  const nowX = xOf(nowMs)
  // Two labels never stand on each other: a record too short to give its own left label room beside
  // `now` (a fresh record of two slots against six hours of estimate) is labelled at now alone.
  const roomForLeft = nowX - plot.x >= 64
  const xTicks = view
    ? // THE WINDOW'S OWN EDGES, in hours from now, with `now` in the middle where it has room to
      // stand (the estimate puts it inside the window) and the window's midpoint where it does not.
      [
        { x: plot.x, label: edgeLabel(view.fromMs - nowMs) },
        nowX - plot.x >= 48 && plot.x + plot.w - nowX >= 48
          ? { x: nowX, label: 'now' }
          : { x: plot.x + plot.w / 2, label: edgeLabel((view.fromMs + view.toMs) / 2 - nowMs) },
        { x: plot.x + plot.w, label: edgeLabel(view.toMs - nowMs) },
      ]
    : points.length && roomForLeft
    ? [
        { x: plot.x, label: `${MINUS}${hoursLabel(spanHours)}` },
        ...(est
          ? []
          : [
              {
                x: plot.x + plot.w / 2,
                label: `${MINUS}${hoursLabel(spanHours / 2)}`,
              },
            ]),
        { x: nowX, label: 'now' },
      ]
    : [{ x: nowX, label: 'now' }]

  let chartOutlook: ChartOutlook | null = null
  if (est) {
    const exy = est.map((p, i) => ({
      x: xOf(estAts[i]),
      y: yOf(p.value),
      lo: yOf(p.lo),
      hi: yOf(p.hi),
    }))
    const eline = exy.map(({ x, y }, i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ')
    const top = exy.map(({ x, hi: h }, i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${h.toFixed(1)}`).join(' ')
    const bottom = [...exy]
      .reverse()
      .map(({ x, lo: l }) => `L${x.toFixed(1)} ${l.toFixed(1)}`)
      .join(' ')
    const endLabel = `+${hoursLabel((endMs - nowMs) / 3_600_000)}`
    if (!view) xTicks.push({ x: plot.x + plot.w, label: endLabel })
    const bestMs = outlook?.bestAt ? Date.parse(outlook.bestAt) : NaN
    const bestI = Number.isFinite(bestMs) ? estAts.findIndex((t) => t === bestMs) : -1
    const arrive = outlook?.arriveMs
    chartOutlook = {
      line: eline,
      band: `${top} ${bottom} Z`,
      endLabel,
      nowX,
      best: bestI >= 0 ? { x: exy[bestI].x, y: exy[bestI].y, value: est[bestI].value } : null,
      arriveX: arrive != null && arrive > nowMs && arrive <= endMs ? xOf(arrive) : null,
    }
  }

  let chartStock: ChartStock | null = null
  if (hasStock && stockTarget !== null) {
    const sy = plot.y + plot.h + stockGap
    const recS = points.map((p, i) => ({ t: ats[i], v: p.stock })).filter((p): p is { t: number; v: number } => typeof p.v === 'number')
    const estS = est
      ? est.map((p, i) => ({ t: estAts[i], v: p.stock })).filter((p): p is { t: number; v: number } => typeof p.v === 'number')
      : []
    const top = Math.max(stockTarget * 2, ...recS.map((p) => p.v), ...estS.map((p) => p.v))
    const ys = (v: number) => sy + stockH - (Math.max(0, v) / top) * stockH
    const path = (pts: { t: number; v: number }[]) =>
      pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.t).toFixed(1)} ${ys(p.v).toFixed(1)}`).join(' ')
    const sline = path(recS)
    const sfloor = (sy + stockH).toFixed(1)
    const nowS = estS[0] ?? recS[recS.length - 1] ?? null
    chartStock = {
      y: sy,
      h: stockH,
      line: sline,
      area: recS.length
        ? `${sline} L${xOf(recS[recS.length - 1].t).toFixed(1)} ${sfloor} L${xOf(recS[0].t).toFixed(1)} ${sfloor} Z`
        : '',
      estimate: path(estS),
      normalY: ys(stockTarget),
      now: nowS ? { x: xOf(nowS.t), y: ys(nowS.v), value: nowS.v } : null,
      target: stockTarget,
    }
  }

  return {
    width: size.width,
    height: size.height,
    plot,
    points: xy,
    line,
    area,
    yTicks,
    xTicks,
    spanHours,
    low: points.length ? mark(lowI) : mark(-1),
    high: points.length ? mark(highI) : mark(-1),
    now: est ? mark(-1) : mark(mids.length - 1),
    outlook: chartOutlook,
    stock: chartStock,
  }
}
