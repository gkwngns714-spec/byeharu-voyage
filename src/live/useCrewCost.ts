// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT WOULD THIS MANY CREW COST PER DAY? — asked of the server for the count the stepper names,
// and never worked out here.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE CONCEPT (docs/NO_SPAGHETTI.md §7B): "the daily cost of a crew count", served. The owner
// (row 85): *"by doing so show how much it will consume everyday"*. The client HAS the rate
// (`snapshot.config.wage_per_crew_day`) and the crew, and multiplying them here would be exactly
// the second author §1 forbids: `voyage.settle` charges `public.crew_wages(crew, short)` on every
// settled voyage-day (0086), and the day that rule gains a term — an officer's discount, a
// nation's levy — a caption that multiplied would print the wrong number without a test going red.
// So the caption reads `world.crew_cost(fleet, n)`, which IS `crew_wages`, for the n under the
// finger.
//
// WHERE IT LIVES, AND WHY HERE. `src/live/` holds the served reads a screen composes (useInn,
// useBuyCapacity, useTrade); the design system may read nothing above it. The Inn is the first
// caller; a crew row on FLEETS ("what this fleet costs per day at sea") is the plausible second,
// and it reads THIS with `count` null.
//
// THE SHAPE OF THE READ — composed from the two shared hooks, not written a third time:
//   * DEBOUNCED through `useSettled` (the one settle timer): the stepper's slider reports every
//     step of a drag, and an un-debounced ask would turn a 20-step drag into twenty round trips.
//   * ASKED through `useServedRead`, with the (fleet, settled count) as the SUBJECT, so an answer
//     for another count is never printed as this one's: a new count shows "checking" until its
//     own answer lands. The world's beat re-asks silently and keeps the figure on screen.
//   * While the count under the finger has not yet settled, the figure on screen would answer an
//     earlier count, so it is withheld (`loading`) rather than printed as this one's.
// A refusal (not your fleet, no house) leaves the caption blank rather than wrong: the press states
// the reason in full when the order is issued (§7C's mirror — a truthful lesser answer, never a
// fabricated figure).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { worldCrewCost } from '../lib/rpc'
import type { CrewCost } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useSettled } from './useSettled'

export interface CrewCostState {
  /** The served figures for THIS count, or null before its first answer. */
  cost: CrewCost | null
  /** True while the count under the finger has no answer yet. */
  loading: boolean
}

const IDLE: CrewCostState = { cost: null, loading: false }
const WAITING: CrewCostState = { cost: null, loading: true }

export function useCrewCost(fleetId: string | null, count: number | null): CrewCostState {
  const settled = useSettled(count)
  const read = useServedRead(fleetId !== null ? `${fleetId}:${settled ?? '-'}` : null, () =>
    worldCrewCost(fleetId as string, settled),
    { name: 'worldCrewCost' },
  )
  if (fleetId === null) return IDLE
  if (settled !== count) return WAITING
  return { cost: read.view, loading: read.loading }
}
