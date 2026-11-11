// NEWS DOTS ON A CHART'S TIME AXIS — pure geometry (0347, owner row 216: *"when an update or a happening is made, it should make a point on
// the chart, and i will be able to press it to see what caused it"*; docs/NEWS_AND_MARKERS.md §3.2).
//
// Both charts call it (PriceChart, SeriesChart) with their own plot and the stretch of time their width spans; the two chart models stay
// separate. A mark stands on the floor line at its own instant; a mark outside the axis is not drawn (the chart does not show that time).
// Marks closer than CLUSTER_PX merge into one dot that carries all of them, newest first, and the highest importance among them.

/** What a chart needs to know of a news item to draw it. */
export interface ChartNewsMark {
  id: number
  atMs: number
  /** 3 headline, 2 notable, 1 local. */
  importance: number
}

/** The news a chart draws, and what a press on a dot does (the caller opens the card). */
export interface ChartNews {
  marks: readonly ChartNewsMark[]
  onPress: (ids: number[]) => void
}

export interface NewsDot {
  /** On the chart's sheet (its viewBox), like every other figure of its model. */
  x: number
  y: number
  /** The marks in it, newest first. */
  ids: number[]
  importance: number
}

/** Dots closer than this (sheet px) are one dot. */
export const CLUSTER_PX = 12

export function newsMarksModel(
  marks: readonly ChartNewsMark[],
  plot: { x: number; y: number; w: number; h: number },
  axis: { fromMs: number; toMs: number },
): NewsDot[] {
  const span = axis.toMs - axis.fromMs
  if (!(span > 0) || plot.w <= 0) return []
  const placed = marks
    .filter((m) => Number.isFinite(m.atMs) && m.atMs >= axis.fromMs && m.atMs <= axis.toMs)
    .map((m) => ({ m, x: plot.x + ((m.atMs - axis.fromMs) / span) * plot.w }))
    .sort((a, b) => a.x - b.x || a.m.atMs - b.m.atMs)
  const floor = plot.y + plot.h
  const groups: { xs: number[]; marks: ChartNewsMark[] }[] = []
  for (const p of placed) {
    const last = groups[groups.length - 1]
    if (last && p.x - last.xs[last.xs.length - 1] < CLUSTER_PX) {
      last.xs.push(p.x)
      last.marks.push(p.m)
    } else groups.push({ xs: [p.x], marks: [p.m] })
  }
  return groups.map((g) => ({
    x: g.xs.reduce((s, v) => s + v, 0) / g.xs.length,
    y: floor,
    ids: [...g.marks].sort((a, b) => b.atMs - a.atMs || b.id - a.id).map((m) => m.id),
    importance: Math.max(...g.marks.map((m) => m.importance)),
  }))
}
