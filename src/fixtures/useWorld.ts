// THE FIXTURE DATA LAYER — the one place the six V0 screens get their world from.
//
// This module stands in for what will eventually be world.snapshot() + world.fleets() +
// world.market() + world.ledger() (Appendix 2). It is deliberately shaped like that future: ONE
// source, mounted once, read by every tab. No screen builds a fixture, and no screen keeps a
// second copy of one — the same rule src/app/shellState.ts states for server state, applied to the
// stand-in so there is nowhere for a second copy to appear when the real thing lands.
//
// NO NETWORK. NO SUPABASE. Nothing here writes anything.
//
// TWO CLOCKS, ONE SNAPSHOT. The world is built ONCE, at module load, against the wall clock at
// that instant — so the voyage that is twelve minutes out really is twelve minutes out, and its
// ETA really does count down while you watch. The per-tick derivation (fleet progress) is redone
// from src/app/shellState.ts's ONE CLOCK; the static half (the leg graph, the price index, the
// lookup maps) is built once and reused, because rebuilding a 12-node graph 60 times a minute
// would be work done for no reason.

import { useMemo } from 'react'
import { useShellState } from '../app/shellState'
import type { WorldModel } from '../features/command/worldModel'
import { buildStaticWorld, deriveWorld } from '../features/command/worldModel'
import { buildV0World } from './v0'

/** The instant the snapshot describes. Captured once so every tab agrees about when "now" was. */
export const WORLD_BUILT_AT_MS = Date.now()

const STATIC_WORLD = buildStaticWorld(buildV0World(WORLD_BUILT_AT_MS))

/** For specs and any pure caller: the same world, at any instant, with no React in the way. */
export function worldAt(nowMs: number): WorldModel {
  return deriveWorld(STATIC_WORLD, nowMs)
}

/** The hook every V0 screen uses. Re-derives once per shell tick — two fleets and a dozen ports,
 *  which is nothing — and returns a stable-enough object for a render. */
export function useWorld(): WorldModel {
  const { nowMs } = useShellState()
  return useMemo(() => deriveWorld(STATIC_WORLD, nowMs), [nowMs])
}
