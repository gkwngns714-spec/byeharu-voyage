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
 * sides. One table drives the strip and this store's own "is that a real face?" guard, so a
 * seventh face is one entry and cannot be half-added.
 *
 * ── TWO FIELDS DIED HERE (docs/UI_DIRECTION.md §7 step 4) ──────────────────────────────────────
 * `title` and `explain` were the panel heading and the ⓘ paragraph of the Card this screen used to
 * be. §6 deletes the card, the heading and the dot: the strip already names the face, and the
 * explain lines were seven paragraphs that answered a question nobody had pressed. A field nothing
 * renders is data the next reader has to disprove, so they go with the thing that printed them
 * (docs/NO_SPAGHETTI.md §5).
 *
 * `label` is what the tab says, and it is now ONE WORD — §6's strip is `[Trade][Town][Store]
 * [Craft][Inn][Yard]` on a single scrolling row, where the old labels wrapped to two rows at
 * 390px. The ORDER of this array is the order of the strip.
 */
export const PORT_FACES = [
  {
    id: 'market',
    // 0067: which BUILDING this face is. `null` means the face is not a building and every
    // harbour turns to it. A face that names a building is offered only where that building
    // STANDS — one rule, read from the rows, replacing PortScreen's hand-written academy check.
    building: 'market',
    label: 'Trade',
  },
  { id: 'city', building: null, label: 'Town' },
  { id: 'warehouse', building: 'warehouse', label: 'Store' },
  { id: 'workstation', building: 'workstation', label: 'Craft' },
  { id: 'inn', building: 'inn', label: 'Inn' },
  { id: 'building_yard', building: 'building_yard', label: 'Build' },
  // 2026-09-09: REPAIR's doorway, moved off COMMAND's grid to the building whose act it is. Its
  // label is the server's own name for the building (0067) — one word, and not the Yard's word.
  { id: 'shipyard', building: 'shipyard', label: 'Shipyard' },
  { id: 'academy', building: 'academy', label: 'School' },
] as const satisfies readonly {
  id: string
  /** 0067 — the building this face IS, or null for a face that is not one. */
  building: BuildingKind | null
  label: string
}[]

export type PortFace = (typeof PORT_FACES)[number]['id']

export interface PortViewState {
  face: PortFace
  turnTo: (face: PortFace) => void
}

export const usePortView = create<PortViewState>()(
  persist(
    (set) => ({
      // TRADE opens first (row 56): with the Quay gone it is the face you came here to use,
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
