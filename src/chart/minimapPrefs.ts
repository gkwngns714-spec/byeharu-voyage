// THE MINIMAP'S SIZE AND FOLD (owner, 2026-11-14: "enable me to change the size of the minimap, and fold").
//
// One small record kept in this browser, the same way as the regions filter (./regionsFilter.ts): a UI
// preference, no game state, not per-account; one key; read and written inside try/catch, so a private window
// keeps the choice for this tab only.
//
//   width    the width the player dragged it to, in CSS px; null = never resized (today's size).
//   folded   true = folded to its tab; false = unfolded on purpose; null = never chosen.
//
// A record with any choice in it is one the minimap OBEYS at every zoom (`minimapChosen`); with none, the
// screen's own rule for when the minimap appears stands (MapScreen: only once the opening frame is left).

import { useSyncExternalStore } from 'react'

export interface MinimapPrefs {
  readonly width: number | null
  readonly folded: boolean | null
}

/** The one key. Versioned like every persisted preference in this app. */
export const MINIMAP_PREFS_KEY = 'byeharu-voyage.map.minimap.v1'

const NONE: MinimapPrefs = { width: null, folded: null }

/** Today's size, and the smallest it goes: 144 x 52 px. Its shape is kept at every size. */
export const MINIMAP_MIN_WIDTH = 144
export const MINIMAP_ASPECT = 144 / 52

/** Read the record through an injected reader. Only the shape this module writes is trusted. */
export function readMinimapPrefs(read: (key: string) => string | null): MinimapPrefs {
  try {
    const raw = read(MINIMAP_PREFS_KEY)
    if (!raw) return NONE
    const v = JSON.parse(raw) as { width?: unknown; folded?: unknown } | null
    if (v === null || typeof v !== 'object') return NONE
    const width = typeof v.width === 'number' && Number.isFinite(v.width) && v.width > 0 ? v.width : null
    const folded = typeof v.folded === 'boolean' ? v.folded : null
    return width === null && folded === null ? NONE : { width, folded }
  } catch {
    return NONE
  }
}

/** Has the player resized, folded or unfolded it on purpose? */
export function minimapChosen(prefs: MinimapPrefs): boolean {
  return prefs.width !== null || prefs.folded !== null
}

/**
 * The widest it may be on a glass: 40% of the glass's width, and never taller than a third of the glass.
 * A phone's 40% is no wider than the minimum, which would make the grip do nothing there, so a narrow glass
 * allows up to 280 px (less a 12 px inset each side).
 */
export function minimapMaxWidth(glassWidth: number, glassHeight: number): number {
  const byWidth = Math.max(glassWidth * 0.4, Math.min(glassWidth - 24, 280))
  const byHeight = (glassHeight / 3) * MINIMAP_ASPECT
  return Math.max(MINIMAP_MIN_WIDTH, Math.floor(Math.min(byWidth, byHeight)))
}

/** The width it is drawn at on this glass: the player's, held between the minimum and the glass's maximum. */
export function minimapWidth(prefs: MinimapPrefs, glassWidth: number, glassHeight: number): number {
  const max = minimapMaxWidth(glassWidth, glassHeight)
  return Math.round(Math.min(max, Math.max(MINIMAP_MIN_WIDTH, prefs.width ?? MINIMAP_MIN_WIDTH)))
}

let current: MinimapPrefs | null = null
const listeners = new Set<() => void>()

function snapshot(): MinimapPrefs {
  if (current === null) current = readMinimapPrefs((k) => localStorage.getItem(k))
  return current
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** Change the record and keep it. Only the minimap's own grip, fold button and tab write it. */
export function setMinimapPrefs(patch: Partial<MinimapPrefs>): void {
  current = { ...snapshot(), ...patch }
  try {
    localStorage.setItem(MINIMAP_PREFS_KEY, JSON.stringify(current))
  } catch {
    // Storage refused: the choice still applies to this tab, it just does not outlast it.
  }
  for (const l of listeners) l()
}

/** The record as this frame sees it. */
export function useMinimapPrefs(): MinimapPrefs {
  return useSyncExternalStore(subscribe, snapshot, () => NONE)
}
