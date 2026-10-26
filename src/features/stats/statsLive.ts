import { useEffect, useState } from 'react'
import { worldStatsNow, type RpcResult, type StatsNow } from '../../lib/rpc'

// THE TAB'S ONE WAY OF ASKING — every Stats read is asked again every second while it is on screen
// (0224 for the live band; 0227 for every face; docs/dev-log/2026-10-26-stats-all-live.md).
//
// THE OWNER (docs/OWNER_REQUESTS.md row 213, 2026-10-26, after rows 187 and 200): *"and why is next count in
// minutes? i told you it should be in seconds?"*. Since 0227 every face's read answers NOW on the server — the
// count's completed quarter hours plus the minutes since, the state as it stands, each chart ending at now() —
// so there is nothing to wait for and no count to show: a face simply asks its read every second.
//
// ONE RULE FOR EVERY READ ON THE TAB (useLiveRead): asked once on mount, then every STATS_LIVE_MS while the
// component is mounted; a hidden document skips its asks (the figures are re-read the moment the tab is looked at
// again); an ask still on the wire is never stacked under a new one (a slow answer delays the next, it never piles
// up); a failed ask keeps the last answer on screen. A new subject (another city) drops the old answer.
//
// THE HEADER says when the figures are from: the server's own `at` of the newest live-band answer, in Korea time
// like the top bar's clock, so it ticks with them.

export const STATS_LIVE_MS = 1_000

export interface LiveRead<V> {
  /** The newest answer for this subject, or null before the first one (or when the first one failed). */
  view: V | null
  /** True until the first ask for this subject has answered, either way. */
  loading: boolean
}

export function useLiveRead<V>(subject: string, ask: () => Promise<RpcResult<V>>): LiveRead<V> {
  const [answer, setAnswer] = useState<{ subject: string; view: V | null } | null>(null)

  useEffect(() => {
    let alive = true
    let asking = false
    const tick = async () => {
      if (asking || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) return
      asking = true
      try {
        const r = await ask()
        if (!alive) return
        // a failed ask keeps the last answer for this subject; the first failed ask is an answer of nothing
        setAnswer((prev) => (r.ok ? { subject, view: r.value } : prev !== null && prev.subject === subject ? prev : { subject, view: null }))
      } finally {
        asking = false
      }
    }
    void tick()
    const id = window.setInterval(() => void tick(), STATS_LIVE_MS)
    return () => {
      alive = false
      window.clearInterval(id)
    }
    // `ask` is the subject's RPC: a new subject is a new ask, the same subject asks the same thing
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subject])

  if (answer === null || answer.subject !== subject) return { view: null, loading: true }
  return { view: answer.view, loading: false }
}

export interface StatsLive {
  /** The newest answer of world.stats_now(), or null before the first one lands. Kept across a failed ask. */
  live: StatsNow | null
  /** The server's instant of the newest live answer, in ms. Null before the first one lands. */
  liveAtMs: number | null
}

/** The RIGHT NOW band's read (world.stats_now, 0224), on the tab's one rule. */
export function useStatsLive(): StatsLive {
  const { view: live } = useLiveRead<StatsNow>('stats:now', worldStatsNow)
  const liveAtMs = live === null ? null : Date.parse(live.at)
  return { live, liveAtMs: liveAtMs !== null && Number.isFinite(liveAtMs) ? liveAtMs : null }
}
