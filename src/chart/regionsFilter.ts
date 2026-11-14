// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S FILTER — one choice, kept in this browser, read by every chart surface at once.
//
// The owner (row 93): *"make filter so that i can choose to apply color, or return to the
// current state."* Then (2026-11-15): *"also in map, make filter, like regions, no in regions,
// have option to see seas, showing waves, requirement to pass etc."* So the one switch became one
// choice of three, one at a time:
//   off      the map as it is (the default, element for element: ./regions.ts's header)
//   regions  the water and the land tinted and the regions named (row 93)
//   seas     each sea zone outlined and named with what it asks (./seaZones.ts)
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: WHICH LAYER IS ON — a UI preference, no game state, not per-account
//              (the same reasoning as `foldStorageKey`, src/components/ui/collapsibleState.ts).
// WHERE        src/chart, because the two callers are both chart surfaces — the Map tab and
//              `SmallChart` — and a preference two surfaces read must be ONE value: a module-level
//              store behind `useSyncExternalStore`, so a choice on one chart is the other's in the
//              same frame, and a reload finds it where it was left.
// WRONG SHAPE  a `useState` inside each screen — two switches that can disagree — or a key
//              minted in a screen. There is one key, and it is here.
//
// THE OLD KEY (`REGIONS_FILTER_KEY`, '1' = on) is still READ, so a player who left Regions on
// finds it on; the first choice made writes the new key and drops the old one.
//
// Storage is read and written inside try/catch: a private window or a locked-down profile
// refuses it, and then the filter still works for this tab and simply does not outlast it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useSyncExternalStore } from 'react'

export type MapLayer = 'off' | 'regions' | 'seas'
export const MAP_LAYERS: readonly MapLayer[] = ['off', 'regions', 'seas']

/** The one key. Versioned like every persisted preference in this app. */
export const MAP_LAYER_KEY = 'byeharu-voyage.map.layer.v1'
/** The row-93 switch's key ('1' = Regions on). Read once for a player who set it; never written. */
export const REGIONS_FILTER_KEY = 'byeharu-voyage.map.regions.v1'

/** Read the kept choice through an injected reader (localStorage.getItem-shaped). ONLY the values
 *  this module writes are trusted; absence, garbage or a throwing reader all mean OFF. */
export function readMapLayer(read: (key: string) => string | null): MapLayer {
  try {
    const v = read(MAP_LAYER_KEY)
    if (v === 'regions' || v === 'seas' || v === 'off') return v
    return read(REGIONS_FILTER_KEY) === '1' ? 'regions' : 'off'
  } catch {
    return 'off'
  }
}

/** The row-93 question, kept for its spec: is Regions on, by the kept choice? */
export function readRegionsFilter(read: (key: string) => string | null): boolean {
  return readMapLayer(read) === 'regions'
}

let current: MapLayer | null = null
const listeners = new Set<() => void>()

function snapshot(): MapLayer {
  if (current === null) current = readMapLayer((k) => localStorage.getItem(k))
  return current
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** Choose the layer and keep it. Exported for the surfaces' filter; nothing else writes it. */
export function setMapLayer(layer: MapLayer): void {
  current = layer
  try {
    if (layer === 'off') localStorage.removeItem(MAP_LAYER_KEY)
    else localStorage.setItem(MAP_LAYER_KEY, layer)
    localStorage.removeItem(REGIONS_FILTER_KEY)
  } catch {
    // Storage refused: the choice still applies to this tab, it just does not outlast it.
  }
  for (const l of listeners) l()
}

/** The layer as this frame sees it. Every chart surface reads the same store. */
export function useMapLayer(): MapLayer {
  return useSyncExternalStore(subscribe, snapshot, () => 'off')
}

/** Is Regions the layer on? (The tints' and the flags' one question.) */
export function useRegionsFilter(): boolean {
  return useMapLayer() === 'regions'
}
