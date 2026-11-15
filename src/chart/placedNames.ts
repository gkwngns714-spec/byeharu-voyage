import type { PlacedLabel } from './labels'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHERE THE HARBOUR NAMES WERE LAST DRAWN (2026-10-18) — so a tap on a name opens its city.
//
// A harbour's name and its flag are ONE unit (the owner: "the flag is too far away from the name
// of city"): flag first, then the name, snug. The unit sits beside the mark, and on a long name its
// far end lies beyond the mark's reach (glyphs.ts `hitRadius`) — measured in PR #198, a tap on the
// tail of a right-hand name fell into open water. So the map's tap (src/features/map/MapScreen.tsx,
// through hitTest.ts `names`) asks this list first: a tap inside a drawn name's box — flag and
// letters — is that harbour.
//
// LabelsLayer writes it after every paint (the plan is decided in ChartCanvas; the layer is the one
// place that sees the names actually drawn). It holds boxes in the chart's own units, on the copy
// of the sheet each was drawn on — the same units a tap arrives in.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

//
// A NAME ANSWERS A FEW PIXELS PAST ITS LETTERS (2026-11-15, the owner: tapping "Gibraltar" at 1280 opened Ceuta). Measured
// on the opening frame at 1280×800: Ceuta's mark stands 22 px under Gibraltar's, right below the start of the word
// "Gibraltar", so a tap on the lower edge of the word, just outside its box, was nearer Ceuta's MARK than Gibraltar's and
// opened Ceuta. Each name therefore carries `pad` (NAME_HIT_PAD_PX, in chart units at the scale it was drawn): a tap within
// that margin of a name is that name, and where two margins meet, the name whose letters are nearer wins (./hitTest.ts).

/** How far past a drawn name's box, in screen pixels, a tap still means that name. */
export const NAME_HIT_PAD_PX = 5

export interface PlacedName {
  readonly code: string
  readonly box: PlacedLabel['box']
  /** The margin round `box` that still answers for this name, in chart units. */
  readonly pad?: number
}

let current: readonly PlacedName[] = []

export function setPlacedNames(labels: readonly PlacedLabel[], unitsPerPx = 0) {
  const pad = NAME_HIT_PAD_PX * unitsPerPx
  current = labels.filter((l) => l.id.startsWith('port:')).map((l) => ({ code: l.id.slice(5), box: l.box, pad }))
}

/** Is `at` on (or within its margin of) a drawn name? The one rule for "the tap was on a name". */
export function onPlacedName(name: PlacedName, at: { x: number; y: number }): boolean {
  return boxDistance(name.box, at) <= (name.pad ?? 0)
}

/** How far `at` lies outside `box` (0 inside it), in chart units. */
export function boxDistance(box: PlacedLabel['box'], at: { x: number; y: number }): number {
  const dx = Math.max(box.x - at.x, 0, at.x - (box.x + box.width))
  const dy = Math.max(box.y - at.y, 0, at.y - (box.y + box.height))
  return Math.hypot(dx, dy)
}

export function placedNames(): readonly PlacedName[] {
  return current
}
