// THE COMMAND DRAFT — one authority for "the order currently being MADE", shared across tabs.
//
// E.4: "tap a row → BUY/SELL prefilled on CMD". E.2: "tapping a row copies its name into the CMD
// line." E.3's port actions are written AS the order they would issue. Four screens write this
// draft; exactly one screen (CMD) reads it. If each kept its own idea of the pending order there
// would be four drafts and the player would lose one by switching tabs.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CHANGED 2026-08-19 — THE DRAFT IS A STRUCTURED INTENT, NOT A HALF-TYPED STRING.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The owner's correction was "not typing, but making commands". Orders are no longer typed, so a
// draft can no longer be "what is in the input box" — there is no input box. The draft is now what
// the player has PICKED so far: a fleet, a verb, and a value per argument NAME as the server's own
// verb schema names them (`world.snapshot().verbs` → VerbSpec.args[].name).
//
// The STRING is still the one contract with the server (F.4: "there is exactly one parser"), but
// it is now DERIVED from this intent at the moment of issue — see orderText.ts. Nothing stores a
// partially-written string, because a partially-written string is the thing that got deleted.
//
// ── WHAT CHANGED FOR THE THREE TABS THAT WRITE THIS STORE ──────────────────────────────────────
// `handOff` now takes an intent object instead of a string. `text` and `setText` are gone.
//
//   old (MarketScreen)  handOff(`BUY ${good.code} 50`)
//   new                 handOff({ verb: 'BUY', args: { good: good.code, qty: '50' } })
//
//   old (PortScreen)    handOff(`PROVISION ${fleet.name} FULL`)
//   new                 handOff({ verb: 'PROVISION', args: { mode: 'FULL' }, fleetId: fleet.id })
//
//   old (FleetsScreen)  handOff(`SAIL ${fleet.name} TO ${port.name}`, fleet.id)
//   new                 handOff({ verb: 'SAIL', args: { dest: port.code }, fleetId: fleet.id })
//
// Argument VALUES are the literal tokens the order line will carry: a port CODE (`CAD`), a good
// CODE (`sal`), `ALL` / `HALF` / a number of tuns. Codes, never display names — `Banda Aceh` is two
// tokens and the server's parser splits on whitespace, so a name would arrive as two arguments.
// Every argument left unset simply opens its picker on the CMD tab; a hand-off may be partial.
//
// The selected fleet lives here too, because a short order carries no fleet: `BUY sal 60` says
// nothing about which hull, and `cmd.issue(fleet_id, …)` needs one. The CMD tab's fleet strip sets
// it; MARKET and PORT read it so the order they hand over is aimed at the right ship.

import { create } from 'zustand'

/** A partially- or fully-made order. Every field is optional: a hand-off says what it knows. */
export interface CommandIntent {
  /** Which hull the order is for. Omit to keep whatever the CMD tab already had selected. */
  fleetId?: string | null
  /** A verb the server serves in `snapshot.verbs` — `SAIL`, `BUY`, … Omit to keep the current one. */
  verb?: string | null
  /** Values keyed by the server's own argument names (`dest`, `good`, `qty`, `mode`, `count`, …). */
  args?: Record<string, string>
}

export interface CommandDraftState {
  /** Which fleet the order is for. `cmd.issue()`'s first argument. */
  fleetId: string | null
  /** The chosen verb, or null while the player is still choosing one. */
  verb: string | null
  /** What has been picked so far, by the server's argument name. */
  args: Record<string, string>
  /** Bumped whenever another tab hands an order over, so CMD can scroll the composer into view
   *  without reacting to the player's own picking. */
  handoffs: number

  selectFleet: (fleetId: string | null) => void
  /** Choosing a verb DISCARDS the old arguments: `dest` means nothing to BUY. */
  chooseVerb: (verb: string | null) => void
  /** Set one argument, or clear it with null. */
  setArg: (name: string, value: string | null) => void
  /** Another tab hands an order over. Counts as a handoff. */
  handOff: (intent: CommandIntent) => void
  /** Put the composer back to "no verb chosen". Keeps the fleet — it is a selection, not an order. */
  clear: () => void
}

export const useCommandDraft = create<CommandDraftState>((set) => ({
  fleetId: null,
  verb: null,
  args: {},
  handoffs: 0,

  selectFleet: (fleetId) => set({ fleetId }),

  chooseVerb: (verb) => set({ verb, args: {} }),

  setArg: (name, value) =>
    set((s) => {
      const args = { ...s.args }
      if (value === null || value === '') delete args[name]
      else args[name] = value
      return { args }
    }),

  handOff: (intent) =>
    set((s) => ({
      fleetId: intent.fleetId === undefined ? s.fleetId : intent.fleetId,
      // A hand-off that names a verb replaces the arguments; one that does not is only adding to
      // what is already being made (MARKET setting a good on an existing BUY, say).
      verb: intent.verb === undefined ? s.verb : intent.verb,
      args: intent.verb === undefined ? { ...s.args, ...intent.args } : { ...intent.args },
      handoffs: s.handoffs + 1,
    })),

  clear: () => set({ verb: null, args: {} }),
}))
