/** A figure's share of the largest of its set, 0-100, for a `Bar` (MarkRow.tsx). 0 when the set is all zero: an empty bar, never a full
 *  one. Presentation only: both figures are served. */
export function shareOf(value: number, widest: number): number {
  return widest > 0 ? (Math.abs(value) / widest) * 100 : 0
}
