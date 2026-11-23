import type { SeaConditions, SeaZone } from '../../lib/rpc'

// THE SEAS, AS A LIST — every sea zone `world.sea_conditions` serves (0215), in the served order. A sea is a place on the chart
// with a name and its harbours, nothing more: the owner switched the sea limits off on 2026-11-23 ("remove sea limits entirely",
// docs/design/hq-command-2026-11-23.md), so no screen draws what a sea asks or calls one closed. A refusal the server still makes is
// printed where it lands, in its own words (lib/rpc/seaWall.ts); nothing here judges a sea.

export interface SeaRow {
  zone: SeaZone
}

export function seaRows(conditions: SeaConditions | null | undefined): SeaRow[] {
  if (!conditions) return []
  return [...conditions.zones].sort((a, b) => a.ord - b.ord).map((zone) => ({ zone }))
}
