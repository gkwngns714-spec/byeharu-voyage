// WHICH HARBOUR THIS HOUSE IS READING — the one owner, for every screen that asks.
//
// ── THE CONCEPT, IN ONE NOUN PHRASE (docs/NO_SPAGHETTI.md §7B, answered before it was built) ────
// "The harbour the house is looking at." One question, and until 2026-08-23 it had two answers
// that could disagree: PORT persisted its pick in `features/port/portView.ts` while MARKET kept a
// component-local `chosenPortId` that died on every tab switch — measured in the playtest as
// "pick Cádiz on MARKET, check the fleet, come back: Lisboa again." Both files NAMED the seam
// rather than copying across it, and this store is the promotion they both pointed at.
//
// ── WHERE IT LIVES, AND WHY HERE ────────────────────────────────────────────────────────────────
// `src/store/` — app-wide UI state, beside authStore. It is not a screen's (two screens read it
// and neither may import the other), not the world's (`src/live` holds what the SERVER said, and
// no server payload carries a player's spyglass), and not a game rule (`src/domain` decides
// nothing and this decides nothing either — it remembers a choice).
//
// ── THE CALLERS, NAMED ──────────────────────────────────────────────────────────────────────────
//   1. PORT    reads it for which harbour's faces to show.
//   2. MARKET  reads it for whose prices to fetch.
//   3. THE MAP is the named NEXT caller: "read this harbour's market" from a tapped port is
//      `pick(code)` + navigate — a button the map could not offer while the choice was
//      component-local, because it would have landed the player on the default port regardless.
//
// ── THE DECISIONS, DEFENDED ─────────────────────────────────────────────────────────────────────
// * ONE choice for both screens. A player who picked Cádiz on PORT has answered "which harbour?"
//   and must not be asked again on MARKET. The two tabs are two faces of one reading.
// * By PORT CODE, not id. The code is the world's stable name (`portByCode` resolves it), it is
//   what PORT already persisted, and what `cmd`'s own parser speaks. MARKET converted from id.
// * SESSION STORAGE, so it survives a reload but dies with the browser tab — portView.ts's
//   reasoning, kept word for word: a harbour you are reading is a thing you are DOING, not a
//   thing you keep. Tomorrow opens on wherever the fleet actually is, not on a port that stopped
//   being interesting three voyages ago.
// * `null` means "nothing chosen", and the fallback is the house's own harbour — `harbourCode`
//   below is the ONE spelling of that fallback, composed on `housePortCode` (domain/fleet), so
//   the two screens cannot derive different defaults the way PORT once fell through to Acapulco.
//
// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────────────────────────
// It is NOT where a fleet's orders happen. That is `fleetPortCode` (domain/fleet): an order runs
// where the fleet is, and reading a distant harbour is a READ. The two questions were tangled
// once and untangled at cost — this store must never feed an order's destination.

import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'
import type { FleetView, SnapshotPort } from '../lib/rpc'
import { housePortCode } from '../domain/fleet'

export interface HarbourState {
  /** The port CODE the player chose to read, or null while the house's own harbour stands. */
  picked: string | null
  pick: (code: string | null) => void
}

export const useHarbour = create<HarbourState>()(
  persist(
    (set) => ({
      picked: null,
      pick: (picked) => set({ picked }),
    }),
    {
      name: 'byeharu-voyage.harbour.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ picked: s.picked }),
      // A corrupt or half-written byte must fall back to the house's own harbour, never wedge.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<HarbourState>
        return { ...current, picked: typeof p.picked === 'string' ? p.picked : null }
      },
    },
  ),
)

/**
 * THE HARBOUR BEING READ — the pick, or the house's own harbour, or (for a house with no fleet at
 * all) the world's first port so a screen still opens on a real market. The ONE spelling of the
 * fallback: PORT and MARKET both call this, so they cannot disagree about the default.
 */
export function harbourCode(
  picked: string | null,
  fleets: readonly FleetView[],
  ports: readonly SnapshotPort[],
): string | null {
  return picked ?? housePortCode(fleets) ?? ports[0]?.code ?? null
}
