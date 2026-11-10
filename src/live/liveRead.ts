import { useEffect, useState } from 'react'
import type { RpcResult } from '../lib/rpc'

// THE ONE LIVE READ — every figure that must move on screen without the player leaving the page asks
// through this hook (owner, 2026-10-26 for Stats: rows 187/200/213; 2026-11-05 for the HQ and the City
// hall: *"the HQ, city hall, population and gold change, can it be live like stats?"*).
//
// Moved out of features/stats/statsLive.ts so that Stats, the City page and the map's city panel share
// ONE authority, not three. THE RULE: asked once on mount, then every LIVE_READ_MS while a component is
// mounted (`refresh`: a changed value asks again NOW with the new `ask`, keeping the answer on screen);
// a hidden document skips its asks (the figures are re-read the moment the tab is looked at again); an
// ask still on the wire is never stacked under a new one (a slow answer delays the next, it never piles
// up); a failed ask keeps the last answer on screen. A new subject drops the old answer.
//
// ONE ASK PER SUBJECT, however many components read it: components that name the same subject share a
// single timer and a single ask in flight (the City page mounts the HQ header and the Town Hall panel
// on the same `world.town_hall(port)`; two timers would ask twice a second). The first reader starts the
// timer, the last one stops it. A subject names ONE question: two readers of it must ask the same RPC.
//
// `keep` (default off): a remount of the subject draws the last answer at once, then refreshes it — the
// tab-switch rule (src/store/resourceCache.ts) for a face that must not go back to a skeleton.
// Every Stats read keeps (the player's own `me` record excepted): row 250, *"keep it even though you move from tab to tab"*; tests/drive.nav.spec.ts holds it.

export const LIVE_READ_MS = 1_000

export interface LiveRead<V> {
  /** The newest answer for this subject, or null before the first one (or when the first one failed). */
  view: V | null
  /** True until the first ask for this subject has answered, either way. */
  loading: boolean
}

interface Feed {
  ask: () => Promise<RpcResult<unknown>>
  readers: Set<(view: unknown) => void>
  view: unknown
  answered: boolean
  asking: boolean
  timer: number
}

const feeds = new Map<string, Feed>()
/** The last answer of a subject whose readers have all left, for a reader that asked to `keep` it. */
const kept = new Map<string, unknown>()

function tick(subject: string, feed: Feed): void {
  if (feed.asking || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) return
  feed.asking = true
  void feed
    .ask()
    .then((r) => {
      if (feeds.get(subject) !== feed) return
      // a failed ask keeps the last answer; the first failed ask is an answer of nothing
      if (r.ok) feed.view = r.value
      feed.answered = true
      for (const reader of feed.readers) reader(feed.view)
    })
    .catch(() => {
      // an ask that throws is a failed ask: the last answer stays, the next tick asks again
    })
    .finally(() => {
      feed.asking = false
    })
}

export function useLiveRead<V>(subject: string | null, ask: () => Promise<RpcResult<V>>, refresh = '', keep = false): LiveRead<V> {
  const [answer, setAnswer] = useState<{ subject: string; view: V | null } | null>(null)

  useEffect(() => {
    if (subject === null) return
    let feed = feeds.get(subject)
    if (!feed) {
      feed = { ask, readers: new Set(), view: null, answered: false, asking: false, timer: 0 }
      if (keep && kept.has(subject)) {
        feed.view = kept.get(subject)
        feed.answered = true
      }
      feeds.set(subject, feed)
    }
    const mine = feed
    mine.ask = ask
    const reader = (view: unknown) => setAnswer({ subject, view: view as V | null })
    mine.readers.add(reader)
    if (mine.answered) reader(mine.view)
    if (mine.readers.size === 1) mine.timer = window.setInterval(() => tick(subject, mine), LIVE_READ_MS)
    tick(subject, mine)
    return () => {
      mine.readers.delete(reader)
      if (mine.readers.size === 0) {
        window.clearInterval(mine.timer)
        if (feeds.get(subject) === mine) feeds.delete(subject)
        if (keep && mine.answered) kept.set(subject, mine.view)
      }
    }
    // `ask` is the subject's RPC: a new subject is a new ask, the same subject asks the same thing
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subject, refresh])

  if (subject === null) return { view: null, loading: false }
  if (answer === null || answer.subject !== subject) return { view: null, loading: true }
  return { view: answer.view, loading: false }
}
