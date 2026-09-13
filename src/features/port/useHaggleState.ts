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
// ── A DOORWAY ONTO useServedRead, NOT A SECOND HOOK (slice 3, 2026-09-13) ──────────────────────
// Until slice 3 this file kept its own copy of "ask again when the world is read" and answered
// `{state: null, loading: true}` every time `readAt` moved — the shell reads the world every 3 s
// (AppShell.tsx, READ_MIN_MS), so the bargain row went blank and repainted on that beat. That is
// the defect owner row 77 named in four other port hooks (*"why is store keep refreshing?"*), and
// a haggle THREAD — several turns of a conversation — cannot be a thing that blanks every three
// seconds. So this is one line of subject and one line of ask on `useServedRead`: the SUBJECT is
// (fleet, good), a re-read of the same subject keeps the last answer on screen and marks it
// `loading` until the fresh one lands, and a new subject shows nothing of the old one. A won
// attempt reaches the screen through the same beat: `worldStore.haggle()` calls `refresh()`,
// `refresh()` moves `readAt`, and this re-asks — the count and the odds arrive one read later,
// which the thread shows as `loading`, never as a blank.
//
// AT SEA IS A STATE, NOT A FAILURE. `world.haggle_state` answers `{docked:false, why}` rather than
// refusing, and `why` is a sentence written for a player. It is rendered as-is. A REFUSAL here
// (E_NO_PLAYER, E_NOT_YOURS) is not the player's problem to solve from a tray: `useServedRead`
// clears the view, the thread does not draw, and the verb's own refusal states the reason if
// they press anyway.

import { worldHaggleState, type HaggleState } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { useWorld } from '../../live/worldStore'

export interface HaggleStateRead {
  /** The last answer for this (fleet, good), or null before the first one (or after a refusal). */
  state: HaggleState | null
  /** True while an ask is on the wire — the first one, or a re-ask on the world's beat. */
  loading: boolean
}

export function useHaggleState(fleetId: string | null, goodCode: string | null): HaggleStateRead {
  const goodId = useWorld((s) => (goodCode ? (s.goodByCode[goodCode]?.id ?? null) : null))
  const subject = fleetId && goodId ? `${fleetId}:${goodId}` : null
  const read = useServedRead<HaggleState>(subject, () => worldHaggleState(fleetId as string, goodId as string))
  return { state: read.view, loading: read.loading }
}
