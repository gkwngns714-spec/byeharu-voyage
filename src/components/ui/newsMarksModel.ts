// NEWS DOTS ON A CHART'S TIME AXIS — pure geometry (0347, owner row 216: *"when an update or a happening is made, it should make a point on
// the chart, and i will be able to press it to see what caused it"*; docs/NEWS_AND_MARKERS.md §3.2).
//
// Both charts draw it (PriceChart, SeriesChart, through NewsDots) with their own plot and the stretch of time their width spans; the two
// chart models stay separate. A mark stands on the floor line at its own instant; a mark outside the axis is not drawn (the chart does
// not show that time). Marks closer than NEWS_HIT_PX merge into one dot that carries all of them, newest first, and the highest
// importance among them.
//
// THE PRESS TARGET (2026-11-11, docs/dev-log/2026-11-11-news-dot-size.md): a dot is a control, so its target is NEWS_HIT_PX square (the
// 44-px law every page spec measures) while the mark drawn stays small. ONE number is both the target's side and the merging distance, so
// two dots' targets never overlap: what stands closer than a target is one dot. The model is in the units of the plot it is given;
// NewsDots gives the plot as it stands on the glass (CSS px), so 44 is 44 px of glass at any scale of the chart's sheet. With the `box`
// the plot stands in, each target is kept inside that box (a mark at the plot's edge or on its floor would hang its target over the
// chart's neighbours) and the targets are kept a side apart; the mark itself never moves, and it is always inside its own target.
//
// THE TARGET HOLDS STILL WHILE ITS MARK KEEPS TIME (2026-11-13, docs/dev-log/2026-11-13-news-dots-trays.md). A live chart's axis ends at
// now, so every mark creeps left with the clock: measured on the HQ's market chart 0.14 px a second, on a Stats city page 0.10. The
// target was centred on its mark, so the BUTTON crept with it, a fraction of a px each second: a control that is never at rest. (It is
// what made tests/news.dotSize.spec.ts red about one run in twenty: Playwright found the dot "not stable" under its press, tried again,
// and its second try scrolls the dot to the glass's foot; the spec read that scroll as "pressing moved its chart".) In a box, a target
// now stands on a lattice of NEWS_HIT_STEP px: it holds still for a minute or more and then steps once, while its mark is drawn at its
// own instant inside it, never more than half a step from the target's centre unless the box or a neighbour moved the target further.
// The step divides the side, so targets a side apart before the lattice are a side apart on it.

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
  /** The mark, in the plot's units. */
  x: number
  y: number
  /** The centre of its press target (NEWS_HIT_PX square), in the same units. */
  hitX: number
  hitY: number
  /** The marks in it, newest first. */
  ids: number[]
  importance: number
}

/** The side of a dot's press target, and so the distance under which two marks are one dot (px of the plot it is given). */
export const NEWS_HIT_PX = 44
/** The lattice a target stands on inside a box: a quarter of its side (it must divide the side, so neighbours stay a side apart). */
export const NEWS_HIT_STEP = NEWS_HIT_PX / 4

export function newsMarksModel(
  marks: readonly ChartNewsMark[],
  plot: { x: number; y: number; w: number; h: number },
  axis: { fromMs: number; toMs: number },
  /** The box the plot stands in (its origin is the plot's origin's): the targets are kept inside it. Absent, a target is centred on its mark. */
  box?: { w: number; h: number },
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
    if (last && p.x - last.xs[last.xs.length - 1] < NEWS_HIT_PX) {
      last.xs.push(p.x)
      last.marks.push(p.m)
    } else groups.push({ xs: [p.x], marks: [p.m] })
  }
  const xs = groups.map((g) => g.xs.reduce((s, v) => s + v, 0) / g.xs.length)
  // THE TARGETS: inside the box, a side apart. Two neighbouring marks are at least a side apart already (a group's centre is never
  // right of its last mark, nor left of its first), so the pass from the left moves a target at most half a side off its mark, and
  // the pass from the right the same: the mark stays inside its target.
  const half = NEWS_HIT_PX / 2
  // in a box the target stands on the lattice (it holds still while its mark creeps with the clock); without one it is its mark's centre
  const hitX = box ? xs.map((x) => Math.round(x / NEWS_HIT_STEP) * NEWS_HIT_STEP) : [...xs]
  if (box) {
    for (let i = 0; i < hitX.length; i++) hitX[i] = Math.max(hitX[i], half, i > 0 ? hitX[i - 1] + NEWS_HIT_PX : -Infinity)
    for (let i = hitX.length - 1; i >= 0; i--) hitX[i] = Math.min(hitX[i], box.w - half, i < hitX.length - 1 ? hitX[i + 1] - NEWS_HIT_PX : Infinity)
  }
  const hitY = box ? Math.max(half, Math.min(floor, box.h - half)) : floor
  return groups.map((g, i) => ({
    x: xs[i],
    y: floor,
    hitX: hitX[i],
    hitY,
    ids: [...g.marks].sort((a, b) => b.atMs - a.atMs || b.id - a.id).map((m) => m.id),
    importance: Math.max(...g.marks.map((m) => m.importance)),
  }))
}
