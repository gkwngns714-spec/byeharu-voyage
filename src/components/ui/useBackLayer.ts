import { useCallback, useEffect, useRef } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LAYERS THAT ANSWER "BACK" — every DetailPage and sheet in the game, one rule (2026-11-24, docs/design/simplify-2026-11-24.md S1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"when i press HQ - city, a whole new tab shows up then i cannot go back to the previous page"*. A page
// opened over a screen (a building's page on HQ, a ship's sheet, the trade sheet) is left ONE step at a time, the one opened last
// first (2026-11-11, the Fleets page), and by every back there is:
//   · opening a layer puts ONE step on the browser's history (same URL, so the screen under it never re-mounts and keeps its scroll);
//   · the browser's back and a phone's back gesture take that step: the top layer closes;
//   · its own back arrow (or ✕) and Escape take the same step, at the press (the `back` this hook returns), so the close IS the
//     browser's back and nothing is left to undo later.
// A layer that goes away for any other reason — a route change, a press inside it that navigates, its owner dropping it — takes NO
// step: a step taken then would land after the navigation that follows and bounce it (a link pressed, a tab, a goto). Instead:
//   · a route change made while a layer's step is the current entry REPLACES that entry, so no dead step is left under the new page;
//   · a layer opened on a dead step (its layer gone) takes that step over rather than adding one.

interface Layer {
  token: string
  close: () => void
}

/** Mounted layers, the one opened last on top. */
const layers: Layer[] = []
/** The history entries layers put down, oldest first (a token whose layer is gone is a dead step). */
const entries: string[] = []
let serial = 0
/** This page load's own mark on its tokens: a step left in the history by an earlier load is never taken for one of this load's. */
const LOAD = Math.random().toString(36).slice(2, 8)
let armed = false

const KEY = 'bvLayer'
const tokenOf = (state: unknown): string | null => {
  const s = state as Record<string, unknown> | null
  return s && typeof s[KEY] === 'string' ? (s[KEY] as string) : null
}
const current = () => tokenOf(window.history.state)
const pathOf = (url: string | URL | null | undefined) => (url == null ? null : new URL(String(url), window.location.href).pathname)

/** The browser's back (or a layer's own, `back`): every step past the one now shown is gone; their layers close, top first. */
function onPop() {
  const at = current()
  const i = at === null ? -1 : entries.indexOf(at)
  entries.length = i + 1
  for (let k = layers.length - 1; k >= 0; k--) if (!entries.includes(layers[k].token)) layers[k].close()
}

/** Once: listen for the back, and make a route change over a layer's step replace that step (the router pushes; a step under a new
 *  page would be a back that shows nothing). A push that keeps the path (a search change under the layer) stays a push. */
function arm() {
  if (armed) return
  armed = true
  window.addEventListener('popstate', onPop)
  const push = window.history.pushState.bind(window.history)
  window.history.pushState = (data: unknown, unused: string, url?: string | URL | null) => {
    const at = current()
    const to = pathOf(url)
    if (at !== null && tokenOf(data) === null && to !== null && to !== window.location.pathname) {
      if (entries.includes(at)) entries.splice(entries.indexOf(at))
      window.history.replaceState(data, unused, url)
      return
    }
    push(data, unused, url)
  }
}

/** This layer closes on the browser's back and on Escape while it is the one opened last. Returns `back`: what its own arrow (or ✕)
 *  presses — the same step back, so the close comes through the one door. */
export function useBackLayer(onClose: () => void): () => void {
  const close = useRef(onClose)
  useEffect(() => {
    close.current = onClose
  })
  const token = useRef<string | null>(null)
  useEffect(() => {
    arm()
    const layer: Layer = { token: token.current ?? `${LOAD}-${++serial}`, close: () => close.current() }
    token.current = layer.token
    layers.push(layer)
    const state = { ...((window.history.state as Record<string, unknown> | null) ?? {}), [KEY]: layer.token }
    const at = current()
    if (at !== null && entries.includes(at) && !layers.some((l) => l !== layer && l.token === at)) {
      // the current step is a dead one (or this layer's own, re-mounted): this layer takes it over
      entries.splice(entries.indexOf(at), 1, layer.token)
      window.history.replaceState(state, '')
    } else {
      entries.push(layer.token)
      window.history.pushState(state, '')
    }
    const onKey = (e: KeyboardEvent) => {
      // one key, one layer: a layer leaves the list when React unmounts it, after every listener has heard this key
      if (e.key === 'Escape' && layers[layers.length - 1] === layer) back(layer.token)
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
      const i = layers.indexOf(layer)
      if (i >= 0) layers.splice(i, 1)
      // no step is taken here: a layer that goes without its own back press leaves a dead step, taken over or replaced later
    }
  }, [])
  return useCallback(() => back(token.current), [])
}

/** A layer's own back: the step it put down, taken now (the close follows on the pop); a layer whose step is not the one shown
 *  closes at once. */
function back(token: string | null) {
  if (token !== null && current() === token) {
    window.history.back()
    return
  }
  layers.find((l) => l.token === token)?.close()
}
