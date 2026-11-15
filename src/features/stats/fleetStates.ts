import type { useT } from '../../lib/i18n'
import type { StatsFleetState } from '../../lib/rpc'

// THE FIVE STATES OF A FLEET — the one place the Stats faces name them (0448; the owner, 2026-11-16: *"stats is messed up. the ships at sea, in
// port, laid up, wrecked are all different numbers. i want you to make it so that this error does not happen again"*).
//
// THE SERVER DECIDES AND COUNTS (public.fleet_state_of, public.fleet_tally; docs/STATS_ONE_COUNT.md): a fleet is in exactly one of five states,
// and `fleets` is the sum of the five. This file only SAYS them: the same word, tone and order on the Ships, Merchants, Navy, Pirates and Cargo
// faces and on a fleet's line. No face adds, subtracts or derives a state figure (tests/stats.oneCount.spec.ts holds that), and no face spells a
// state's word for itself.

/** The five states in reading order: the server's key, its word in the dictionary, and the tone it means. */
export const FLEET_STATES = [
  { id: 'sea', word: 'stats.atSea', tone: 'info' },
  { id: 'port', word: 'stats.inPort', tone: 'success' },
  { id: 'battle', word: 'stats.inBattle', tone: 'warning' },
  { id: 'laid_up', word: 'stats.laidUp', tone: 'neutral' },
  { id: 'wrecked', word: 'stats.wrecked', tone: 'danger' },
] as const satisfies readonly { id: StatsFleetState; word: string; tone: string }[]

type T = ReturnType<typeof useT>

/** One state's word (a fleet's line in a list, her page). A word the client does not know yet is shown as the server sent it. */
export function fleetStateWord(t: T, state: StatsFleetState): string {
  const known = FLEET_STATES.find((s) => s.id === state)
  return known ? t(known.word) : state
}
