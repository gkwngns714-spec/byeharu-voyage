// WHICH VERBS GET A RAIL, AND WHAT THE RAIL IS ABOUT — pure, no React, in its own module for the
// reason `src/components/ui/screenLayout.ts` and `buttonStyles.ts` are: a file that exports both a
// component and a helper breaks Fast Refresh, and eslint's `react-refresh/only-export-components`
// says so out loud rather than letting it rot.
//
// TWO CALLERS, ONE PLACE. `FleetRail` asks it nothing — it switches on the verb it was given — but
// `OrderComposer` asks it twice over: whether to lay the composer out in two columns at all, and
// what to render into the left-hand one. Written in the composer as
// `verb === 'BUY' || verb === 'HIRE' || …` it would have been two copies of one list within thirty
// lines of each other, which is the shape every entry in docs/NO_SPAGHETTI.md §0 started as.

/**
 * The verbs whose rail shows THE FLEET, and the reason each one qualifies: every one of them is a
 * decision about the fleet's own state.
 *
 *   BUY        how much room she has, and what this order would take of it
 *   HIRE       hands aboard against berths, and the idle men this port can offer
 *   REPAIR     the worst hull, every hull, and whether this port even keeps a yard
 *   PROVISION  days of stores, and the fact that water and food take cargo's own tuns
 *
 * SELL is deliberately absent: its ceiling is what is aboard, which the quantity stepper states in
 * full. A rail on a verb it says nothing about is furniture, and this game has been told once
 * already that it prints too much.
 */
export const FLEET_RAIL_VERBS: readonly string[] = ['BUY', 'HIRE', 'REPAIR', 'PROVISION']

/**
 * The verbs whose rail shows THE WORLD — a chart of where she lies and where this order would send
 * her (`SmallChart`, from `src/chart`, composed by the composer).
 *
 * The owner, 2026-08-23: *"sail — a small map + current location on the left side."*
 *
 * ── WHY THIS IS A SECOND LIST AND NOT A LONGER FIRST ONE ───────────────────────────────────────
 * SAIL was named in the list above as deliberately ABSENT, with a sentence that is still true and
 * is exactly the reason it now has a rail of its OWN kind: *"SAIL's decision is about the WORLD —
 * where, how far, what the passage costs."* A `FleetRail` on SAIL would print her hold, her hands
 * and her hulls beside a question about geography — furniture, by the paragraph above. So the fact
 * this module records is not "does this verb get a rail" but "what is this verb a decision ABOUT",
 * and the composer switches on that. One list per answer; the boolean is derived from them.
 */
export const CHART_RAIL_VERBS: readonly string[] = ['SAIL']

/** What this verb's rail is about, or `null` when it has none. THE one place that decides. */
export function railKind(verb: string | undefined): 'fleet' | 'chart' | null {
  if (verb === undefined) return null
  if (FLEET_RAIL_VERBS.includes(verb)) return 'fleet'
  if (CHART_RAIL_VERBS.includes(verb)) return 'chart'
  return null
}

/** Whether the composer lays this verb out in two columns at all. DERIVED — never listed again. */
export function hasRail(verb: string | undefined): boolean {
  return railKind(verb) !== null
}
