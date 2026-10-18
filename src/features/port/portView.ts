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
import { PORT_FACES, type PortFace } from '../../live/cityFaces'
import { persist, createJSONStorage } from 'zustand/middleware'


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
