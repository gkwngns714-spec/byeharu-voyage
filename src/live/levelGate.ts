// THE ONE LEVEL GATE (roadmap 2026-11-23 X6; docs/design/visual-overhaul-2026-11-23.md, slice 7): the Academy (Skills), the
// Workstation (Craft) and the Office's Invest stand for a company from Trading 5. Under it they are hidden, and HQ says, once,
// what Trading 5 opens. ONE TABLE AND ONE RULE: every place that offers one of the three (the Office's face strip, HQ's doors, the
// City face's buildings and its Town rows) asks `useLevelGate`, and never reads a level itself.
//
// IT BITES ONLY WHILE TRADING'S UNLOCKS ARE LIT (0468, the owner's switch `level_unlocks_enabled`: the served Trading benefits carry a
// step, the goal card's own test). Dark, a level opens nothing, so the gate shuts nothing. Until the levels read has answered, the three
// stay shut: a place is never shown and then taken away.
//
// REVERSIBLE: `GATED` empty opens all three again (the roadmap's "Level gate in one place"); `FROM.level` moves the threshold.
// THE READ: the levels read every levels reader shares (`world.levels()`, cached as `worldLevels`), re-asked only when the store's own
// Trading level moves (the player read rides the beat already), so HQ and the Office add no read on the world's beat.

import { worldLevels, type LevelsView } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

/** The places the gate holds. `academy` and `workstation` are City-face buildings (live/cityFaces.ts); `invest` is an Office face. */
export type GatedPlace = 'academy' | 'workstation' | 'invest'

/** WHAT IS HELD, AND FROM WHICH LEVEL — the one table. */
export const GATED: readonly GatedPlace[] = ['academy', 'workstation', 'invest']
export const FROM = { track: 'trading', level: 5 } as const

export interface LevelGate {
  /** True while this place is not offered. */
  shut: (place: string) => boolean
  /** The held places, in the table's order, while any is held (for the one unlock line); empty when none is. */
  held: readonly GatedPlace[]
  /** The level that opens them. */
  at: number
}

/** The verdict from one levels answer (null: not answered yet). Pure, for the one hook below. */
export function gateOf(v: LevelsView | null | undefined): LevelGate {
  const held = ((): readonly GatedPlace[] => {
    if (GATED.length === 0) return []
    if (!v) return GATED
    if (!v.company) return []
    const trading = v.level_skills?.skills.find((s) => s.code === FROM.track)
    const lit = trading?.benefits.some((b) => b.kind === 'perk') ?? false
    return lit && v.tracks.trading.level < FROM.level ? GATED : []
  })()
  return { shut: (place) => (held as readonly string[]).includes(place), held, at: FROM.level }
}

export function useLevelGate(): LevelGate {
  const level = useWorld((s) => s.player?.levels?.trading?.level ?? 0)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels', trigger: level })
  return gateOf(read.view)
}
