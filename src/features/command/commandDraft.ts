// THE COMMAND DRAFT — one authority for "what is currently in the CMD input", shared across tabs.
//
// E.4: "tap a row -> BUY/SELL prefilled on CMD". E.2: "tapping a row copies its name into the CMD
// line." E.3's port actions are written AS the command they would issue, and tapping one loads it.
// Four screens write the draft; exactly one screen reads it. If each of those screens kept its own
// idea of the pending command there would be four drafts and the player would lose one of them by
// switching tabs.
//
// The draft is A STRING, deliberately — the same string the keyboard produces and the same string
// that will be sent to cmd.issue() (F.4 step 4). No screen ever composes a structured order.
//
// The selected fleet lives here too, because it is what makes a short line complete: `BUY sal 60`
// has no fleet in it, and something has to say which one. The CMD tab's selector sets it; MARKET
// and PORT read it so the command they prefill is aimed at the right hull.

import { create } from 'zustand'

export interface CommandDraftState {
  /** The exact contents of the CMD input. */
  text: string
  /** Which fleet a fleet-less order belongs to. */
  fleetId: string | null
  /** Bumped every time another tab writes the draft, so CMD can focus/scroll on arrival without
   *  reacting to the player's own typing. */
  handoffs: number
  /** The player typing. Does not count as a handoff. */
  setText: (text: string) => void
  /** Another tab handing an order over. Counts as a handoff. */
  handOff: (text: string, fleetId?: string | null) => void
  selectFleet: (fleetId: string | null) => void
  clear: () => void
}

export const useCommandDraft = create<CommandDraftState>((set) => ({
  text: '',
  fleetId: null,
  handoffs: 0,
  setText: (text) => set({ text }),
  handOff: (text, fleetId) =>
    set((s) => ({
      text,
      fleetId: fleetId === undefined ? s.fleetId : fleetId,
      handoffs: s.handoffs + 1,
    })),
  selectFleet: (fleetId) => set({ fleetId }),
  clear: () => set({ text: '' }),
}))
