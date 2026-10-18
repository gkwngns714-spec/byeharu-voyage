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

export interface PlacedName {
  readonly code: string
  readonly box: PlacedLabel['box']
}

let current: readonly PlacedName[] = []

export function setPlacedNames(labels: readonly PlacedLabel[]) {
  current = labels.filter((l) => l.id.startsWith('port:')).map((l) => ({ code: l.id.slice(5), box: l.box }))
}

export function placedNames(): readonly PlacedName[] {
  return current
}
