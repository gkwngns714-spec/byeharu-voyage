// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REGIONS FILTER — one switch, kept in this browser, read by every chart surface at once.
//
// The owner (row 93): *"make filter so that i can choose to apply color, or return to the
// current state."* OFF is the default and OFF is the current map exactly (./regions.ts's header);
// ON tints the water and the land and names the regions.
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: IS THE REGIONS LAYER ON — a UI preference, no game state, not
//              per-account (the same reasoning as `foldStorageKey`, src/components/ui/collapsibleState.ts,
//              whose key convention this follows).
// WHERE        src/chart, because the two callers are both chart surfaces — the Map tab and
//              `SmallChart` — and a preference two surfaces read must be ONE value: a module-level
//              store behind `useSyncExternalStore`, so flipping it on one chart flips it on the
//              other in the same frame, and a reload finds it where it was left.
// SECOND CALLER  `SmallChart` (it wears the same `ViewControls`, so the same button).
// WRONG SHAPE  a `useState` inside each screen — two switches that can disagree — or a key
//              minted in a screen. There is one key, and it is here.
//
// Storage is read and written inside try/catch: a private window or a locked-down profile
// refuses it, and then the filter still works for this tab and simply does not outlast it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useSyncExternalStore } from 'react'

/** The one key. Versioned like every persisted preference in this app. */
export const REGIONS_FILTER_KEY = 'byeharu-voyage.map.regions.v1'

/** Read a persisted state through an injected reader (localStorage.getItem-shaped). ONLY the one
 *  value this module writes is trusted; absence, garbage or a throwing reader all mean OFF. */
export function readRegionsFilter(read: (key: string) => string | null): boolean {
  try {
    return read(REGIONS_FILTER_KEY) === '1'
  } catch {
    return false
  }
}

let current: boolean | null = null
const listeners = new Set<() => void>()

function snapshot(): boolean {
  if (current === null) current = readRegionsFilter((k) => localStorage.getItem(k))
  return current
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** Flip the filter and keep it. Exported for the surfaces' button; nothing else writes it. */
export function setRegionsFilter(on: boolean): void {
  current = on
  try {
    if (on) localStorage.setItem(REGIONS_FILTER_KEY, '1')
    else localStorage.removeItem(REGIONS_FILTER_KEY)
  } catch {
    // Storage refused: the filter still applies to this tab, it just does not outlast it.
  }
  for (const l of listeners) l()
}

/** The filter as this frame sees it. Every chart surface reads the same store. */
export function useRegionsFilter(): boolean {
  return useSyncExternalStore(subscribe, snapshot, () => false)
}
