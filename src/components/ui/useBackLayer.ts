import { useEffect, useRef } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LAYERS THAT ANSWER "BACK" — every DetailPage and sheet in the game, one rule (2026-11-24, docs/design/simplify-2026-11-24.md S1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"when i press HQ - city, a whole new tab shows up then i cannot go back to the previous page"*. A page
// opened over a screen (a building's page on HQ, a ship's sheet, the trade sheet) is left ONE step at a time, the one opened last
// first (2026-11-11, the Fleets page), and by every back there is:
//   · its own back arrow (or ✕), and Escape: the layer closes, and the history entry it pushed is taken back;
//   · the browser's back and a phone's back gesture: opening a layer pushes ONE history entry (same URL, so the screen under it
//     never re-mounts and keeps its scroll); going back pops it and closes the top layer. Before this a phone's back left HQ.
//
// A layer that gives way to another in the same moment (a fleet's sheet replaced by her trade sheet) hands its entry over instead
// of popping it, so the history never collects dead entries. React's StrictMode re-mount takes the same path.

interface Layer {
  token: string
  close: () => void
}

/** Mounted layers, the one opened last on top. */
const layers: Layer[] = []
/** The history entries the layers pushed, oldest first; an entry whose layer has gone is popped on the next tick. */
const entries: string[] = []
let settle: number | null = null
let serial = 0
let listening = false

const KEY = 'bvLayer'
const current = (): string | null => {
  const s = window.history.state as Record<string, unknown> | null
  return s && typeof s[KEY] === 'string' ? (s[KEY] as string) : null
}
const live = (token: string) => layers.some((l) => l.token === token)

/** The browser's back: drop every entry past the one now shown, and close the layers whose entry is gone (top first). */
function onPop() {
  const at = current()
  const i = at === null ? -1 : entries.indexOf(at)
  entries.length = i + 1
  for (let k = layers.length - 1; k >= 0; k--) if (!entries.includes(layers[k].token)) layers[k].close()
}

/** After a layer closed itself: pop the entries at the top whose layers have gone, in one step. */
function popOrphans() {
  settle = null
  let n = 0
  while (entries.length > n && !live(entries[entries.length - 1 - n])) n++
  if (n === 0) return
  // the route moved on (a press inside the layer navigated): the entries stand behind it; leave the history as it is
  if (current() !== entries[entries.length - 1]) {
    entries.length = 0
    return
  }
  entries.length -= n
  window.history.go(-n)
}

/** This layer closes on its back arrow (the caller's), on Escape while it is the one opened last, and on the browser's back. */
export function useBackLayer(onClose: () => void): void {
  const close = useRef(onClose)
  useEffect(() => {
    close.current = onClose
  })
  useEffect(() => {
    if (!listening) {
      window.addEventListener('popstate', onPop)
      listening = true
    }
    const layer: Layer = { token: `L${++serial}`, close: () => close.current() }
    layers.push(layer)
    const state = { ...((window.history.state as Record<string, unknown> | null) ?? {}), [KEY]: layer.token }
    const top = entries[entries.length - 1]
    if (top !== undefined && !live(top) && current() === top) {
      // the entry of a layer that has just gone is this one's now
      entries[entries.length - 1] = layer.token
      window.history.replaceState(state, '')
    } else {
      entries.push(layer.token)
      window.history.pushState(state, '')
    }
    const onKey = (e: KeyboardEvent) => {
      // one key, one layer: a layer leaves the list when React unmounts it, after every listener has heard this key
      if (e.key === 'Escape' && layers[layers.length - 1] === layer) layer.close()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      const i = layers.indexOf(layer)
      if (i >= 0) layers.splice(i, 1)
      if (entries.includes(layer.token) && settle === null) settle = window.setTimeout(popOrphans, 0)
    }
  }, [])
}
