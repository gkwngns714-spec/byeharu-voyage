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
// THE SHAPE OF THE READ — a CEILING-style read (useBuyCapacity), not a VIEW read (useServedRead):
// the answer is keyed by (fleet, count) and an answer for another count is never printed as this
// one's. Three things differ from useBuyCapacity, each for a reason:
//   * DEBOUNCED, like useTrade's dry run: the stepper's slider reports every step of a drag, and
//     each step is a new count, so an un-debounced effect would turn a 20-step drag into twenty
//     round trips. The ask waits until the finger has rested for SETTLE_MS.
//   * NOT re-keyed on `readAt`. `crew_cost(fleet, n)` for an EXPLICIT n depends on the wage knobs
//     alone — not on what is aboard, not on the purse — so the world's 3-second re-read changes
//     nothing about it, and re-asking on every beat would be the flicker row 77 removed. A caller
//     that passes `null` (the crew aboard now) is asking about the world and gets the served
//     answer for the fleet as it was read; it re-asks when the fleet's crew changes, because the
//     count it derives changes.
//   * ANSWERS ARE KEPT, keyed by count, so stepping back to a count already priced is instant and
//     the caption never blanks between two known figures. `loading` is true only while the count
//     under the finger has no answer yet. The map is STATE (replaced, never mutated), so a landed
//     answer is a render and a read during render is a read of state, not of a ref.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect, useState } from 'react'
import { worldCrewCost } from '../lib/rpc'
import type { CrewCost } from '../lib/rpc'

/** How long a chosen count must stand still before the server is asked to price it. */
const SETTLE_MS = 200

export interface CrewCostState {
  /** The served figures for THIS count, or null before its first answer. */
  cost: CrewCost | null
  /** True while the count under the finger has no answer yet. */
  loading: boolean
}

const IDLE: CrewCostState = { cost: null, loading: false }

export function useCrewCost(fleetId: string | null, count: number | null): CrewCostState {
  const key = fleetId !== null ? `${fleetId}:${count ?? '-'}` : null
  // One map per hook instance: a fleet's answers do not outlive the screen that asked.
  const [answers, setAnswers] = useState<ReadonlyMap<string, CrewCost>>(() => new Map())
  const known = key !== null && answers.has(key)

  useEffect(() => {
    if (key === null || fleetId === null || known) return
    let live = true
    const timer = setTimeout(() => {
      void worldCrewCost(fleetId, count).then((r) => {
        if (!live) return
        // A refusal (not your fleet, no house) leaves the caption blank rather than wrong: the
        // press states the reason in full when the order is issued (§7C's mirror — a truthful
        // lesser answer, never a fabricated figure).
        if (!r.ok) return
        setAnswers((prev) => {
          const next = new Map(prev)
          next.set(key, r.value)
          return next
        })
      })
    }, SETTLE_MS)
    return () => {
      live = false
      clearTimeout(timer)
    }
  }, [key, fleetId, count, known])

  if (key === null) return IDLE
  const cost = answers.get(key) ?? null
  return { cost, loading: cost === null }
}
