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
import type { BuildingKind } from '../../lib/rpc'
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
    id: 'market',
    // 0067: which BUILDING this face is. `null` means the face is not a building and every
    // harbour turns to it. A face that names a building is offered only where that building
    // STANDS — one rule, read from the rows, replacing PortScreen's hand-written academy check.
    building: 'market',
    label: 'Market',
    title: 'The market',
    explain:
      'What this city trades, and the only place its prices become an order. A city deals in its own 4-10 goods (0061/0062), so the quay you are standing on is the one that decides — buy from what it offers, and sell it anything you carry.',
  },
  {
    id: 'city',
    building: null,
    label: 'City',
    title: 'The city',
    explain:
      'How far this place has grown, what the Mayor takes, and what it sells cheaper than its neighbours. Every figure is read from the market as it stands today.',
  },
  {
    id: 'warehouse',
    building: 'warehouse',
    label: 'Warehouse',
    title: 'The warehouse',
    explain:
      'Somewhere to leave a cargo. A warehouse belongs to the city it stands in — what you leave here cannot be reached from anywhere else, and it costs nothing to keep. How much it holds is how big this city is.',
  },
  {
    id: 'workstation',
    building: 'workstation',
    label: 'Workstation',
    title: 'The workstation',
    explain:
      'Where trade goods become a fitting for a ship. What it can make depends on how good this city is at it, and what it makes comes out of the hold of a ship lying here — a fitting made at Bilbao stays at Bilbao.',
  },
  {
    id: 'inn',
    building: 'inn',
    label: 'Inn',
    title: 'The inn',
    explain:
      'Who is drinking here today. Officers keep to their own coast, so a captain is likeliest to be found in her own nation’s ports and rarest far from home — and the better she is, the rarer she is anywhere. The room is the same for everybody and there is nothing to refresh: tomorrow it is a different room.',
  },
  {
    id: 'building_yard',
    building: 'building_yard',
    label: 'Yard',
    title: 'The building yard',
    explain:
      'Where a hull is laid down. She is built out of THIS city — timber from the warehouse here, fittings from your store here — and never out of a hold, because no ship afloat carries what a big hull wants. It is not the shipyard, which mends.',
  },
  {
    id: 'academy',
    building: 'academy',
    label: 'Academy',
    title: 'The academy',
    explain:
      'A trade is learned ashore, one level at a time. Only ports that keep an academy show this face at all.',
  },
] as const satisfies readonly {
  id: string
  /** 0067 — the building this face IS, or null for a face that is not one. */
  building: BuildingKind | null
  label: string
  title: string
  explain: string
}[]

export type PortFace = (typeof PORT_FACES)[number]['id']

export interface PortViewState {
  face: PortFace
  turnTo: (face: PortFace) => void
}

export const usePortView = create<PortViewState>()(
  persist(
    (set) => ({
      // MARKET opens first (row 56): with the Quay gone it is the face you came here to use,
      // and a persisted 'quay' from an older build falls back through `offeredFaces` anyway.
      face: 'market',
      turnTo: (face) => set({ face }),
    }),
    {
      // The v1 byte also carried `picked`; that key now belongs to `src/store/harbour.ts` and the
      // stale field is simply ignored by the merge below — sessionStorage, so no migration.
      name: 'byeharu-voyage.port.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face }),
      // A corrupt or half-written byte must open a face that EXISTS, never wedge the tab on one
      // that does not. It used to fall back to the Quay; row 56 removed that face, and this is
      // exactly the line that would have kept a stale byte pointing at it.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<PortViewState>
        return {
          ...current,
          face: PORT_FACES.some((f) => f.id === p.face) ? (p.face as PortFace) : 'market',
        }
      },
    },
  ),
)
