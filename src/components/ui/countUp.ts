// A FIGURE THAT MOVES TO ITS NEW VALUE — the arithmetic, pure, so tests/countUp.spec.ts proves it
// in Node and the component below it only draws.
//
// THE OWNER, 2026-10-20 (request 188): *"it has no visuals, no charts, no number moving around"*.
// docs/UI_DIRECTION.md §4.6 says sheets rise, folds open and "nothing else animates" — this is the
// one exception the owner asked for by name, and it is kept as narrow as the sentence: a FIGURE
// whose served value changed walks from the old number to the new one over 480 ms and then stops.
// Nothing else moves, nothing loops, and a player who asked for less motion
// (`prefers-reduced-motion`) is given the new number at once (Counter.tsx).
//
// WHY A WALK AND NOT A FADE. The figures on the Stats tab are sums of money, and the question a
// player asks of them is "which way, and by how much". A number that counts up says both while it
// moves; a cross-fade says only "something changed".
//
// 480 ms IS TWO FOLDS (`--duration-fold` is 180 ms, `--duration-sheet` 240). Long enough to read as
// a movement rather than a flicker, short enough that the figure is settled before the eye reaches
// the next one — and far shorter than the three seconds between the world's reads, so a counter is
// never still mid-walk when the next value lands.

/** How long a figure takes to reach its new value, in ms. */
export const COUNT_UP_MS = 480

/** Ease-out cubic on 0–1, clamped: fast at the start, settling at the end — the house curve's
 *  shape (`--ease-sheet` is a cubic bezier that lands the same way). */
export function countUpEase(p: number): number {
  const c = p <= 0 ? 0 : p >= 1 ? 1 : p
  return 1 - (1 - c) ** 3
}

/**
 * Where the figure stands at `p` of its walk from `from` to `to`.
 *
 * The ENDS ARE EXACT: at `p <= 0` it is the old value and at `p >= 1` it is the served one, so a
 * walk never leaves a number that is nearly right on the screen. A value that is not a finite
 * number (a first paint, a refused read) is not walked to — it is simply the answer.
 */
export function countUpValue(from: number, to: number, p: number): number {
  if (!Number.isFinite(to)) return to
  if (!Number.isFinite(from)) return to
  if (p <= 0) return from
  if (p >= 1) return to
  return from + (to - from) * countUpEase(p)
}
