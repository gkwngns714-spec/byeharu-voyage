import { MINUS, formatInt } from '../../lib/format'
import type { PricePoint } from '../../lib/rpc'

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
// which two trays already draw — the quay she lies at and a quay she is only reading. Not in
// `src/chart/`: that layer is the NAUTICAL chart (the picture of the world), and a price line has
// nothing to say to a coastline. The SECOND CALLER is any future face that wants a served series
// with an axis — a purse-over-time line, a fame line — which is why the model takes plain points
// and not a `MarketGood`.
//
// ── WHAT THE AXES SAY, AND WHERE THE NUMBERS COME FROM ─────────────────────────────────────────
// Every figure on the chart is SERVED or DERIVED from what was served — never a literal.
//   · y ticks: the served minimum, the served maximum, and the round midpoint between them. The
//     band is the data's own min…max, exactly as the sparkline's is (Sparkline.tsx: "it does not
//     scale to zero"), so a 2 % move and a halving are the same shape at different labels.
//   · x ticks: HOURS BEFORE NOW, ending at `now`. The span is derived from the served points and
//     `slot_seconds` (0013 carries it "so a client can label a time axis without knowing the tick
//     cadence"): the wider of (now − the earliest `at`) and (points × slot_seconds), so a window
//     that was served short still reads at its true cadence and a record with gaps still reads
//     at its true age. THERE IS NO "12 h" AND NO "48" HERE — 0013's default window is 48 slots of
//     600 s, which is 8 h, and the mockup that said 12 h was wrong; a literal would be wrong the
//     day either knob moves (docs/QUAY_LEDGER.md Appendix A tripwires).
//   · marks: the lowest point, the highest point, and the last point ("now"). Ties go to the
//     LATEST occurrence, so a flat run marks where the price is rather than where it was.
//
// ── WHAT IT REFUSES ────────────────────────────────────────────────────────────────────────────
// Fewer than two points, a point whose `at` does not parse, or a non-positive slot: null. The
// caller keeps the sparkline (or the "no history" row) — a truthful, lesser answer, which is the
// §7C mirror: a chart that cannot be drawn is not a crash.

/** The drawn plane: 340×170 (docs/QUAY_LEDGER.md Appendix A B), the width of a tray column at
 *  390 px less the gutter, and tall enough for three y labels to stand apart at t-caption. */
export const PRICE_CHART_W = 340
export const PRICE_CHART_H = 170

/** Room for the y labels on the left and the x labels under the plot; the plot fills the rest. */
const PAD = { left: 44, right: 8, top: 8, bottom: 20 }

export interface ChartMark {
  x: number
  y: number
  /** The served mid at that point. */
  mid: number
  /** Which served point it is, oldest first. */
  index: number
}

export interface PriceChartModel {
  width: number
  height: number
  /** The plot rectangle inside the padding — the axes are drawn on its edges. */
  plot: { x: number; y: number; w: number; h: number }
  /** One `x,y` per served point, oldest first. */
  points: { x: number; y: number }[]
  /** The line through the points, as an SVG path. */
  line: string
  /** The line closed down to the plot's floor, for the fill. */
  area: string
  /** Served min · round(mid) · served max, each with the y it sits at. Bottom to top. */
  yTicks: { y: number; label: string }[]
  /** `−Nh` at the left edge, `−N/2h` in the middle, `now` at the right. */
  xTicks: { x: number; label: string }[]
  /** The span the x axis covers, in hours — derived, and printed on the left tick. */
  spanHours: number
  low: ChartMark
  high: ChartMark
  now: ChartMark
}

/** Hours as an axis label: whole hours as `8h`, otherwise one decimal (`7.5h`). */
function hoursLabel(hours: number): string {
  const rounded = Math.round(hours * 10) / 10
  const text = Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1)
  return `${text}h`
}

export function priceChartModel(
  /** The served points for ONE good at ONE port, oldest first. */
  points: readonly PricePoint[],
  /** `PriceHistory.slot_seconds` — how many real seconds one served slot spans. */
  slotSeconds: number,
  /** The instant the axis ends at, in ms — the moment the chart was opened. */
  nowMs: number,
): PriceChartModel | null {
  if (points.length < 2 || !(slotSeconds > 0) || !Number.isFinite(nowMs)) return null
  const ats = points.map((p) => Date.parse(p.at))
  if (ats.some((t) => !Number.isFinite(t))) return null

  const mids = points.map((p) => p.mid)
  const lo = Math.min(...mids)
  const hi = Math.max(...mids)
  const band = hi - lo

  const plot = {
    x: PAD.left,
    y: PAD.top,
    w: PRICE_CHART_W - PAD.left - PAD.right,
    h: PRICE_CHART_H - PAD.top - PAD.bottom,
  }

  // THE SPAN: the wider of the record's true age and its cadence × count, never a constant.
  const earliest = Math.min(...ats)
  const spanMs = Math.max(nowMs - earliest, points.length * slotSeconds * 1000, 1)
  const spanHours = spanMs / 3_600_000

  const xOf = (t: number) => plot.x + plot.w * Math.max(0, Math.min(1, 1 - (nowMs - t) / spanMs))
  // A flat record has no band to scale into: draw it through the middle rather than divide by
  // zero, because "it did not move" is a real answer (the sparkline's rule).
  const yOf = (v: number) => (band === 0 ? plot.y + plot.h / 2 : plot.y + plot.h - ((v - lo) / band) * plot.h)

  const xy = points.map((p, i) => ({ x: xOf(ats[i]), y: yOf(p.mid) }))
  const line = xy.map(({ x, y }, i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ')
  const floor = (plot.y + plot.h).toFixed(1)
  const area = `${line} L${xy[xy.length - 1].x.toFixed(1)} ${floor} L${xy[0].x.toFixed(1)} ${floor} Z`

  // Ties go to the LATEST occurrence: the mark says where the price IS at that level.
  let lowI = 0
  let highI = 0
  for (let i = 0; i < mids.length; i++) {
    if (mids[i] <= mids[lowI]) lowI = i
    if (mids[i] >= mids[highI]) highI = i
  }
  const mark = (i: number): ChartMark => ({ x: xy[i].x, y: xy[i].y, mid: mids[i], index: i })

  const midValue = Math.round((lo + hi) / 2)
  const yTicks =
    band === 0
      ? [{ y: yOf(lo), label: formatInt(lo) }]
      : [
          { y: yOf(lo), label: formatInt(lo) },
          { y: yOf(midValue), label: formatInt(midValue) },
          { y: yOf(hi), label: formatInt(hi) },
        ]

  const xTicks = [
    { x: plot.x, label: `${MINUS}${hoursLabel(spanHours)}` },
    { x: plot.x + plot.w / 2, label: `${MINUS}${hoursLabel(spanHours / 2)}` },
    { x: plot.x + plot.w, label: 'now' },
  ]

  return {
    width: PRICE_CHART_W,
    height: PRICE_CHART_H,
    plot,
    points: xy,
    line,
    area,
    yTicks,
    xTicks,
    spanHours,
    low: mark(lowI),
    high: mark(highI),
    now: mark(mids.length - 1),
  }
}
