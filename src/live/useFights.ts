import { useEffect, useState } from 'react'
import { cmdBattleEnd, worldFights, type FightCard } from '../lib/rpc'
import { instantMs } from '../lib/format'
import { noteFightCuts } from './fightCuts'

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
// A TICK BATTLE ENDS WHEN ITS LAST TICK IS FOUGHT (owner 2026-11-15: the circle goes when the fight ends). Its end is on the
// card (`resolves_at`), but the server closes it on the minute job, up to a minute later, and holds its ships until then.
// So the hook asks again the moment the end comes, and when the battle is still open then it presses the door the design
// gives every reader for exactly this (`cmd.battle_end`, docs/design/tick-combat.md 6: "any reader may close it AT the
// end"), once a battle, and asks again. The server does then what the minute job would have done, no more.

const FAST_MS = 5_000
const IDLE_MS = 15_000
const DARK_MS = 60_000
/** After a tick battle's served end, this long before it is asked about: the server's own 2 ticks of grace are in `resolves_at`. */
const END_GRACE_MS = 400
/** Never asked faster than this. */
const FLOOR_MS = 1_000

export const NO_FIGHTS: readonly FightCard[] = []

/** THE POLL TOUCHES THE MAP ONLY WHEN THE ANSWER CHANGED. `next` when it differs from `prev` in anything served, else `prev` itself: React then skips the map's
 *  render altogether, so an answer that says what the last one said (the usual case: no fight, or the same rings standing) re-renders no layer, no tray and no
 *  sheet. Exported for the spec. */
export function sameOrNext(next: readonly FightCard[], prev: readonly FightCard[]): readonly FightCard[] {
  if (next.length === 0 && prev.length === 0) return prev
  return JSON.stringify(next) === JSON.stringify(prev) ? prev : next
}

/** The served card with the places it had while it was fought, for one that is now over. Exported for the spec. */
export function keepPlaces(next: readonly FightCard[], prev: readonly FightCard[]): FightCard[] {
  return next.map((card) => {
    if (card.status === 'FIGHTING') return card
    const before = prev.find((p) => p.id === card.id)
    if (!before) return card
    return { ...card, sides: card.sides.map((s) => ({ ...s, at: s.at ?? before.sides.find((b) => b.fleet === s.fleet)?.at })) }
  })
}

/** The tick battles on `cards` still open at `serverNowMs` though their last tick is fought, and how long until the next one ends (ms; null: none ahead). */
export function endsOf(cards: readonly FightCard[], serverNowMs: number): { due: string[]; nextInMs: number | null } {
  const due: string[] = []
  let nextInMs: number | null = null
  for (const c of cards) {
    if (c.status !== 'FIGHTING' || c.ticks !== true) continue
    const end = instantMs(c.resolves_at)
    if (end === null) continue
    const left = end + END_GRACE_MS - serverNowMs
    if (left <= 0) due.push(c.id)
    else if (nextInMs === null || left < nextInMs) nextInMs = left
  }
  return { due, nextInMs }
}

export function useFights(active = true): readonly FightCard[] {
  const [fights, setFights] = useState<readonly FightCard[]>(NO_FIGHTS)
  useEffect(() => {
    if (!active) return
    let live = true
    let timer: number | undefined
    const closed = new Set<string>()
    const ask = async () => {
      let wait = DARK_MS
      if (typeof document === 'undefined' || document.visibilityState !== 'hidden') {
        const r = await worldFights().catch(() => null)
        if (!live) return
        if (r?.ok) {
          const served = r.value.fights ?? []
          noteFightCuts(served, Date.now())
          setFights((prev) => sameOrNext(keepPlaces(served, prev), prev))
          wait = served.some((c) => c.status === 'FIGHTING') ? FAST_MS : r.value.on || served.length > 0 ? IDLE_MS : DARK_MS
          const ends = endsOf(served, instantMs(r.value.now) ?? Date.now())
          const press = ends.due.filter((id) => !closed.has(id))
          if (press.length > 0) {
            for (const id of press) closed.add(id)
            await Promise.all(press.map((id) => cmdBattleEnd(id).catch(() => null)))
            if (!live) return
            wait = FLOOR_MS
          } else if (ends.nextInMs !== null) wait = Math.max(FLOOR_MS, Math.min(wait, ends.nextInMs))
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
