import type { CargoShipState } from '../lib/rpc'

// WHAT A CARGO SHIP WITH NOTHING ON BOARD IS DOING (0437; the owner, 2026-11-15: "there are still cargo ships that have 0 gold. if they are
// returning after they provided transport, instead of 0 gold, say it is returning."). The server decides the state (public.cargo_ship_state);
// this is the one map from it to the word, read by her map card (CargoSheet) and her Stats page. LOADED has no word: the gold is the figure.
// Null: show the gold (a loaded ship, or a server before 0437 that serves no state).
export const CARGO_STATE_WORD = {
  RETURNING: 'map.cargoReturning',
  HOME: 'map.cargoAtHome',
  LAID_UP: 'map.laidUp',
} as const

export function cargoStateWordKey(state: CargoShipState | undefined, aboard: number): (typeof CARGO_STATE_WORD)[keyof typeof CARGO_STATE_WORD] | null {
  if (aboard > 0 || !state || state === 'LOADED') return null
  return CARGO_STATE_WORD[state]
}
