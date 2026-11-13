import { useEffect, useState } from 'react'
import { worldFights, type FightCard } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLES ON THE MAP (0364, owner row 321) — `world.fights()`, asked only while the map is open.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server decides everything a ring shows: which battles, where, who is in them, when one is over and for how long
// it is still shown (`keep_seconds`). This hook only asks, on a pace that follows what the last answer said:
//   · a battle is being FOUGHT ...... every 5 s (a round is a minute; a ring should come and go within a breath of it)
//   · fights are in use (`on`) ...... every 15 s: a raid's or a navy fight's ring stays 5 minutes, so it is found in time
//   · nothing is in use (`on` false)  every 60 s: a world with no fight to find is barely asked
// and never while the tab is hidden. A refused or failed read keeps the last answer and asks again at the slow pace.
// A FLEET'S PLACE IS KEPT THROUGH THE END: the server serves `at` only while a battle is fought (afterwards the fleets
// sail on), so the last places seen are kept on a battle that is over and its ring stays where it was.

const FAST_MS = 5_000
const IDLE_MS = 15_000
const DARK_MS = 60_000

export const NO_FIGHTS: readonly FightCard[] = []

/** The served card with the places it had while it was fought, for one that is now over. Exported for the spec. */
export function keepPlaces(next: readonly FightCard[], prev: readonly FightCard[]): FightCard[] {
  return next.map((card) => {
    if (card.status === 'FIGHTING') return card
    const before = prev.find((p) => p.id === card.id)
    if (!before) return card
    return { ...card, sides: card.sides.map((s) => ({ ...s, at: s.at ?? before.sides.find((b) => b.fleet === s.fleet)?.at })) }
  })
}

export function useFights(active = true): readonly FightCard[] {
  const [fights, setFights] = useState<readonly FightCard[]>(NO_FIGHTS)
  useEffect(() => {
    if (!active) return
    let live = true
    let timer: number | undefined
    const ask = async () => {
      let wait = DARK_MS
      if (typeof document === 'undefined' || document.visibilityState !== 'hidden') {
        const r = await worldFights().catch(() => null)
        if (!live) return
        if (r?.ok) {
          const served = r.value.fights ?? []
          setFights((prev) => (served.length === 0 && prev.length === 0 ? prev : keepPlaces(served, prev)))
          wait = served.some((c) => c.status === 'FIGHTING') ? FAST_MS : r.value.on || served.length > 0 ? IDLE_MS : DARK_MS
        }
      } else wait = FAST_MS
      if (live) timer = window.setTimeout(() => void ask(), wait)
    }
    void ask()
    return () => {
      live = false
      if (timer !== undefined) window.clearTimeout(timer)
    }
  }, [active])
  return fights
}
