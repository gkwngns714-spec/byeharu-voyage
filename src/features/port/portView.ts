// WHICH HARBOUR THE PORT TAB IS READING, AND WHICH FACE OF IT IS TURNED TOWARDS YOU.
//
// ── WHY THIS IS A STORE AND NOT `useState` (2026-08-22) ─────────────────────────────────────────
// It was `useState` in PortScreen, and the tab unmounts when you leave it. Measured in the
// playtest: pick Lisbon on PORT → go to MARKET → come back → `Port · Acapulco`. Choosing a harbour
// out of 214 is deliberate work — a filter typed, a name found, a chip tapped — and losing it to a
// tab switch is losing work, exactly as `src/domain/order/draft.ts` says of a half-composed order.
// The trap it set was worse than the annoyance: the screen silently went back to composing orders
// from a port ~10,000 nm from the fleet.
//
// SESSION STORAGE, NOT LOCAL, and the reasoning is draft.ts's word for word: a harbour you are
// reading is a thing you are DOING, not a thing you keep. It dies with the tab, so tomorrow opens
// on wherever the fleet actually is rather than resurrecting a port that stopped being interesting
// three voyages ago.
//
// ── WHAT IT IS NOT ─────────────────────────────────────────────────────────────────────────────
// It is NOT "the port the game is at" — there is no such thing; a house is wherever its hulls are
// (`domain/fleet`'s `housePortCode`). `null` here means "nothing chosen", and the screen falls back
// to the house's own harbour, which is the only default that is ever right.
//
// A NAMED SEAM, not a hidden one: MARKET keeps the same kind of selection as component-local state
// (`features/market/MarketScreen.tsx:103`, `chosenPortId`, by port ID where this is by port CODE).
// If a player is ever meant to read one harbour on both tabs, those two are ONE question and this
// store is where the answer belongs — but folding MARKET's copy in means editing MARKET, so it is
// written down here rather than left to be rediscovered.

import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'

/**
 * THE FACES OF ONE PLACE, EACH DESCRIBED ONCE. Not routes: a port is one screen, and these are its
 * sides.
 *
 * The tab strip, the panel heading and this store's own "is that a real face?" guard were three
 * lists of the same six words — and the heading was not even a list, it was the string "The
 * quayside" hard-coded for all six, so CITY, SERVICES, OFFICERS and ACADEMY each sat under the name
 * of a face they were not. One table drives all three now, and the `PortFace` type is derived from
 * it, so a seventh face is one entry and cannot be half-added.
 *
 * `label` is what the tab says; `title` is what the panel is called while this face is up;
 * `explain` is the ⓘ line under it. The ORDER of this array is the order of the strip.
 */
export const PORT_FACES = [
  {
    id: 'quay',
    label: 'Quay',
    title: 'The quayside',
    explain:
      'Each line is the exact order it would become. Tapping one sends it to Command; nothing here issues anything.',
  },
  {
    id: 'city',
    label: 'City',
    title: 'The city',
    explain:
      'How far this place has grown, what the Mayor takes, and what it sells cheaper than its neighbours. Every figure is read from the market as it stands today.',
  },
  {
    id: 'services',
    label: 'Services',
    title: 'What the port keeps',
    explain:
      'The shipyard, the inn, the chandler and the school. What a service COSTS is set when the order runs, so PREVIEW on Command quotes it — no price is listed here.',
  },
  {
    id: 'ships',
    label: 'Alongside',
    title: 'Your hulls alongside',
    explain:
      "Your own shipping in this harbour. Only your own: no harbour reports another house's hulls to you.",
  },
  {
    id: 'officers',
    label: 'Officers',
    title: 'The hiring quay',
    explain:
      'An officer signs on where they live and serves in one fleet. Signing is immediate — it is not an order, so it does not go through the queue.',
  },
  {
    id: 'academy',
    label: 'Academy',
    title: 'The academy',
    explain:
      'A trade is learned ashore, one level at a time. Only ports that keep an academy show this face at all.',
  },
] as const

export type PortFace = (typeof PORT_FACES)[number]['id']

export interface PortViewState {
  /** The port CODE the player chose, or null while the house's own harbour stands. */
  picked: string | null
  face: PortFace
  pick: (code: string | null) => void
  turnTo: (face: PortFace) => void
}

export const usePortView = create<PortViewState>()(
  persist(
    (set) => ({
      picked: null,
      face: 'quay',
      pick: (picked) => set({ picked }),
      turnTo: (face) => set({ face }),
    }),
    {
      name: 'byeharu-voyage.port.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ picked: s.picked, face: s.face }),
      // A corrupt or half-written byte must open the Quay at the house's own harbour, never wedge
      // the tab on a face that no longer exists.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<PortViewState>
        return {
          ...current,
          picked: typeof p.picked === 'string' ? p.picked : null,
          face: PORT_FACES.some((f) => f.id === p.face) ? (p.face as PortFace) : 'quay',
        }
      },
    },
  ),
)
