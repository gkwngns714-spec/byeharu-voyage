import type { NewsMark } from '../../lib/rpc'

// THE NEWS DOTS' GEOMETRY — pure, so tests/newsMarks.spec.ts proves the cluster and the axis in Node and
// the two chart painters only draw (docs/NEWS_AND_MARKERS.md §3.2: "Pure geometry in a new
// newsMarksModel.ts — both charts call it; the two chart models stay separate").
//
// WHAT IT ANSWERS. Given a chart's plot rectangle and the stretch of TIME that rectangle draws (the
// same window the chart's own model mapped its line with), where does each news mark's dot stand: x by
// the mark's own instant on the time axis, y on the plot's floor line (the design's rule — a news mark
// is a point on the time axis, not on the line). Dots closer than 12 px merge into ONE dot with a count;
// the merged dot takes the highest importance in it. Imp 3 draws accent, 1-2 ink-muted — the painter's
// tokens, decided here so the two painters cannot drift.
//
// IT DECIDES NOTHING ABOUT THE SERIES. The chart's own model is a pure function of the served series
// alone (priceChartModel / seriesChartModel); this file reads its plot and window and returns dots that
// the painter draws BESIDE the series — the series geometry is untouched by construction, which is what
// "the chart series are unchanged apart from the markers" means in code.
//
// WHAT IT REFUSES. A mark whose instant lies outside the window is still given its true x (so the price
// chart's clip path can cut it at the edge, as it cuts the line) and is flagged `inWindow` false — the
// series chart, which has no clip, simply does not draw those.

export interface NewsMarkDot {
  /** The dot's centre, in the model's own coordinates (the svg viewBox). */
  x: number
  y: number
  /** The drawn radius: 3 px (the design's rule). The painter adds the 24 px hit target around it. */
  r: number
  /** `accent` for an importance-3 mark, `muted` for 1-2 — tokens, never literals. */
  tone: 'accent' | 'muted'
  /** The marks merged into this dot, newest first; one for a single mark. */
  items: NewsMark[]
  /** How many marks merged here (1 for a single mark). */
  count: number
  /** The highest importance in the dot. */
  importance: number
  /** Whether the dot's instant stands inside the drawn window. */
  inWindow: boolean
}

/** The stretch of time the chart's plane draws, in ms — the same window the chart's own model used. */
export interface MarksWindow {
  fromMs: number
  toMs: number
}

/** The plot rectangle, in the model's own coordinates — `priceChartModel.plot` / `seriesChartModel.plot`. */
export interface MarksPlot {
  x: number
  y: number
  w: number
  h: number
}

/** Dots closer than this many model px merge into one dot with a count (the design's §3.2 rule). */
export const MARKS_CLUSTER_PX = 12

/** The dot's drawn radius, px. */
export const MARK_R = 3

export function newsMarksModel(
  marks: readonly NewsMark[],
  plot: MarksPlot,
  window: MarksWindow,
): NewsMarkDot[] {
  const span = Math.max(1, window.toMs - window.fromMs)
  const floor = plot.y + plot.h
  const xOf = (atMs: number) => plot.x + ((atMs - window.fromMs) / span) * plot.w

  const placed = marks
    .map((m) => {
      const atMs = Date.parse(m.at)
      return Number.isFinite(atMs)
        ? { m, x: xOf(atMs), atMs }
        : { m, x: plot.x, atMs: Number.NaN }
    })
    .sort((a, b) => a.atMs - b.atMs)

  const dots: NewsMarkDot[] = []
  for (const p of placed) {
    const last = dots[dots.length - 1]
    // merge when the two centres stand closer than the cluster distance; the dot keeps the highest
    // importance and lists its items newest first (the design's §3.2 rule)
    if (last && Math.abs(p.x - last.x) < MARKS_CLUSTER_PX) {
      last.items = [p.m, ...last.items]
      last.count += 1
      last.importance = Math.max(last.importance, p.m.importance)
      last.tone = last.importance >= 3 ? 'accent' : 'muted'
      continue
    }
    dots.push({
      x: p.x,
      y: floor,
      r: MARK_R,
      tone: p.m.importance >= 3 ? 'accent' : 'muted',
      items: [p.m],
      count: 1,
      importance: p.m.importance,
      inWindow: Number.isFinite(p.atMs) && p.atMs >= window.fromMs && p.atMs <= window.toMs,
    })
  }
  return dots
}
