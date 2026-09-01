// WHICH FACE OF THE HARBOUR IS TURNED TOWARDS YOU — the PORT tab's own chrome, and only that.
//
// ── WHY THIS IS A STORE AND NOT `useState` (2026-08-22) ─────────────────────────────────────────
// It was `useState` in PortScreen, and the tab unmounts when you leave it. Losing a chosen face to
// a tab switch is losing work, exactly as `src/domain/order/draft.ts` says of a half-composed
// order. SESSION STORAGE for draft.ts's reason: a face you turned to is a thing you are DOING, not
// a thing you keep — it survives a reload and dies with the browser tab.
//
// ── WHICH HARBOUR IS NOT HERE ANY MORE (2026-08-23) ────────────────────────────────────────────
// `picked` lived in this store while MARKET kept its own component-local copy of the same choice —
// a seam both files named rather than crossed, and it meant Cádiz picked on MARKET was Lisboa
// again after a tab switch. It is PROMOTED: "which harbour is this house reading" is
// `src/store/harbour.ts` now — one owner that PORT and MARKET both compose, with the MAP named as
// its next caller. The FACE stays here because it is this one screen's chrome: no other tab has a
// quay to turn to.

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
    id: 'market',
    label: 'Market',
    title: 'The market',
    explain:
      'What this city trades, and the only place its prices become an order. A city deals in its own 4-10 goods (0061/0062), so the quay you are standing on is the one that decides — buy from what it offers, and sell it anything you carry.',
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
  face: PortFace
  turnTo: (face: PortFace) => void
}

export const usePortView = create<PortViewState>()(
  persist(
    (set) => ({
      face: 'quay',
      turnTo: (face) => set({ face }),
    }),
    {
      // The v1 byte also carried `picked`; that key now belongs to `src/store/harbour.ts` and the
      // stale field is simply ignored by the merge below — sessionStorage, so no migration.
      name: 'byeharu-voyage.port.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face }),
      // A corrupt or half-written byte must open the Quay, never wedge the tab on a face that no
      // longer exists.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<PortViewState>
        return {
          ...current,
          face: PORT_FACES.some((f) => f.id === p.face) ? (p.face as PortFace) : 'quay',
        }
      },
    },
  ),
)
