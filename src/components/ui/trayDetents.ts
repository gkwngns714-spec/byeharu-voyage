// THE TRAY'S DETENTS — pure arithmetic, in its own module so it can be read without a browser.
//
// PURE (no React) for the same reason `buttonStyles.ts` and `screenLayout.ts` are: a file that
// exports a component and a helper breaks Fast Refresh, and a rule that decides where a dragged
// sheet lands is a rule worth testing without mounting anything.
//
// ── THE THREE STOPS, AND WHY THESE THREE ───────────────────────────────────────────────────────
// docs/UI_DIRECTION.md §5: "a bottom-docked sheet with detents (peek 96px · half · full)". The
// reference is Apple Maps' place sheet, and the reason it has exactly three is that each one is a
// different QUESTION:
//   peek  96px  — "what did I just tap?" The answer is one line and one action, and the world
//                 behind it is still the subject. 96 = 52 (one row) + 44 (one reach floor).
//   half  50%   — "let me work in it." A quantity, a passage check, a queue: enough for a stepper
//                 and its primary button with the chart still visible above.
//   full  100%  — "this is the screen now." A list that is genuinely long — every fleet, every
//                 order, a captain's whole entry.
// A fourth stop would be a slider, and a slider has no stops.
//
// ── HALF AND FULL ARE FRACTIONS OF THE CONTAINING BLOCK, NOT OF THE WORLD ──────────────────────
// The docked tray's containing block is the viewport (it is `fixed`), so `half` is half the glass
// — 422px at the 390×844 this project measures everything at. An `inline` tray's containing block
// is the sheet it folds under, and the same fractions apply to that box. One rule, two grounds,
// which is what lets the owner choose docked or inline without the plan changing.
//
// ── SNAPPING IS BY POSITION, NOT BY VELOCITY ───────────────────────────────────────────────────
// `nearestDetent` takes the height the finger left the sheet at and returns the stop it belongs
// to. No flick detection, no momentum: a velocity rule is a second answer to "where does it go",
// and on a 96px peek the two disagree constantly. Dragging BELOW half of the peek closes it, which
// is the drag-to-dismiss gesture §5 asks for and is why `closed` is in the ladder at all.

export const TRAY_DETENTS = ['closed', 'peek', 'half', 'full'] as const
export type TrayDetent = (typeof TRAY_DETENTS)[number]

/** The peek stop, in CSS pixels. One row plus one reach floor. */
export const TRAY_PEEK = 96

/** How tall the tray stands at a detent, given the height of its containing block. */
export function detentHeight(detent: TrayDetent, containerHeight: number): number {
  switch (detent) {
    case 'closed':
      return 0
    case 'peek':
      // A container shorter than the peek gets the container: a stop taller than its own ground is
      // not a stop, it is an overflow.
      return Math.min(TRAY_PEEK, containerHeight)
    case 'half':
      return Math.round(containerHeight / 2)
    case 'full':
      return containerHeight
  }
}

/** The stop a drag that ended at `height` belongs to. Below half the peek, it is dismissed. */
export function nearestDetent(height: number, containerHeight: number): TrayDetent {
  if (height < TRAY_PEEK / 2) return 'closed'
  let best: TrayDetent = 'peek'
  let bestGap = Infinity
  for (const d of TRAY_DETENTS) {
    if (d === 'closed') continue
    const gap = Math.abs(detentHeight(d, containerHeight) - height)
    if (gap < bestGap) {
      bestGap = gap
      best = d
    }
  }
  return best
}

/** The next stop up, and the next down — what the grab handle's keyboard arrows do. */
export function stepDetent(from: TrayDetent, direction: 1 | -1): TrayDetent {
  const i = TRAY_DETENTS.indexOf(from)
  const next = Math.max(0, Math.min(TRAY_DETENTS.length - 1, i + direction))
  return TRAY_DETENTS[next]
}
