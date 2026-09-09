// APPEARANCE — the ONE place the colour scheme is chosen (docs/UI_DIRECTION.md §4.4: "Both
// palettes ship; `prefers-color-scheme` picks, the Cabin toggles").
//
// src/index.css states both palettes and selects the day sea with ONE selector,
// `:root[data-theme='light']`. It used to be a media query, and a media query cannot be toggled
// from a control: `prefers-color-scheme` is the device's word, and the Cabin's Appearance control
// needs the last one. So the device's word is read HERE, through matchMedia, and written onto the
// root as the same attribute a chosen scheme writes — one attribute, one selector, and the CSS
// carries each light value exactly once. Auto follows the device live (the media query's `change`
// event); Dark and Light are kept in this browser and outlast the tab.
//
// This module PAINTS AT IMPORT. App.tsx imports ProfileScreen statically, so this runs before the
// first render; before the bundle arrives the page is `bg` in the night palette, which is a
// frame or two of dark on a light device and no more. Boot belongs to the shell (src/app) — when
// the shell takes this call, it moves; the rule does not get a second copy.
//
// The storage key is never printed (§2 item 13: a storage key on a player's screen is jargon).

export type Appearance = 'dark' | 'light' | 'auto'

export const APPEARANCES: readonly { id: Appearance; label: string }[] = [
  { id: 'dark', label: 'Dark' },
  { id: 'light', label: 'Light' },
  { id: 'auto', label: 'Auto' },
]

const KEY = 'byeharu-voyage.appearance'
const DAY = '(prefers-color-scheme: light)'

/** What the player chose, or `auto` when they never chose (or storage is unreachable). */
export function readAppearance(): Appearance {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'dark' || v === 'light' ? v : 'auto'
  } catch {
    return 'auto'
  }
}

/** Keep the choice and paint it. `auto` is kept as the ABSENCE of a choice, so a player who goes
 *  back to it is exactly where a player who never touched the control is. */
export function writeAppearance(pref: Appearance): void {
  try {
    if (pref === 'auto') localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, pref)
  } catch {
    // Storage refused (private mode, a locked-down profile): the scheme still paints for this
    // tab, it just does not outlast it.
  }
  paint(pref)
}

/** The scheme the root wears right now — what a test reads to prove a toggle actually rendered. */
export function paintedScheme(): 'dark' | 'light' {
  return document.documentElement.dataset.theme === 'light' ? 'light' : 'dark'
}

function paint(pref: Appearance): void {
  const scheme = pref === 'auto' ? (window.matchMedia(DAY).matches ? 'light' : 'dark') : pref
  document.documentElement.dataset.theme = scheme
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  paint(readAppearance())
  window.matchMedia(DAY).addEventListener('change', () => {
    if (readAppearance() === 'auto') paint('auto')
  })
}
