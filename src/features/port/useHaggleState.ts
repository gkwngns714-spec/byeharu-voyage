// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HOW MUCH NEGOTIATION CAN BE DONE? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner asked for it in those words. Until migration 0022 the honest answer was "none", and
// the rail said what moved a price instead. 0022 gave the question a real answer, and this is the
// read that fetches it: `world.haggle_state(fleet, good)`.
//
// EVERY FIGURE IS THE SERVER'S, AND THE ODDS ESPECIALLY. `next_odds` comes from
// `public.haggle_odds` — the SAME function `cmd.haggle` rolls against (0022's own comment: "Read by
// cmd.haggle AND by world.haggle_state, so the number shown and the number rolled against cannot
// differ"). Nothing here recomputes a chance, counts an attempt, or predicts an outcome. A client
// that guessed `attempts_left` would be inventing a rule the server already keeps.
//
// SHAPED AFTER ./useBuyCapacity.ts, DELIBERATELY. Same question shape — one answer about (fleet,
// good) as of the last read — so it is keyed the same way and stales the same way. When the world
// is read again the key changes and the answer is re-asked, which is what makes a won bargain show
// up: `worldStore.haggle()` calls `refresh()`, `refresh()` moves `readAt`, and this asks again.
//
// AT SEA IS A STATE, NOT A FAILURE. `world.haggle_state` answers `{docked:false, why}` rather than
// refusing, and `why` is a sentence written for a player. It is rendered as-is.

import { useEffect, useState } from 'react'
import { worldHaggleState, type HaggleState } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'

export interface HaggleStateRead {
  /** Null until the answer for THIS (fleet, good, read) has arrived. */
  state: HaggleState | null
  loading: boolean
}

const WAITING: HaggleStateRead = { state: null, loading: true }
const IDLE: HaggleStateRead = { state: null, loading: false }

export function useHaggleState(fleetId: string | null, goodCode: string | null): HaggleStateRead {
  const goodId = useWorld((s) => (goodCode ? (s.goodByCode[goodCode]?.id ?? null) : null))
  const readAt = useWorld((s) => s.readAt)
  const key = fleetId && goodId ? `${fleetId}:${goodId}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: HaggleState } | null>(null)

  useEffect(() => {
    if (!key || !fleetId || !goodId) return
    let live = true
    void worldHaggleState(fleetId, goodId).then((r) => {
      if (!live) return
      // A REFUSAL HERE IS NOT THE PLAYER'S PROBLEM TO SOLVE. `haggle_state` refuses only for
      // E_NO_PLAYER and E_NOT_YOURS — neither of which a player can act on from a picker — so the
      // block simply does not draw, and the verb's own refusal states the reason in full if they
      // press anyway. Swallowing it here would be wrong for anything the player CAN fix; none of
      // these are.
      if (!r.ok) return
      setAnswer({ key, state: r.value })
    })
    return () => {
      live = false
    }
  }, [key, fleetId, goodId])

  if (!key) return IDLE
  return answer?.key === key ? { state: answer.state, loading: false } : WAITING
}
