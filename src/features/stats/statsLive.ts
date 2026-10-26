import { useEffect, useState } from 'react'
import { worldStatsNow, type StatsNow } from '../../lib/rpc'

// THE TAB'S ONE LIVE PATH — world.stats_now() every second while the Stats tab is open, and nothing else
// re-asks anything (0224; docs/dev-log/2026-10-26-stats-live.md).
//
// THE OWNER (docs/OWNER_REQUESTS.md row 200, 2026-10-25, asked three times): *"i told you that stats, i
// want to be updated every second"*. The server keeps the live figures as running counters in the same
// transactions that change them and serves them as one small read, so asking it every second costs one
// row plus the rows written since the last count — never an aggregate scan.
//
// ONE PATH, NOT TWO. Before this file the tab re-asked the rollup on a 60-s backstop AND at the computed
// edge of the next count (statsPulse.ts, deleted with 0224). Both are gone: the live answer carries
// `counted_at`, the instant the last count folded the figures, and a face re-asks its rollup read when
// that instant moves (`count` below) — the count's own word that a new row exists, not a clock's guess.
//
// WHILE THE TAB IS OPEN, ONLY THEN. The interval lives in this hook's effect, so it exists exactly while
// StatsScreen is mounted. A hidden document skips its asks (both outcomes are truthful: the figures are
// re-read the moment the tab is looked at again); an ask still on the wire is never stacked under a new one.
//
// THE HEADER SAYS WHEN THE FIGURES ARE FROM (owner, 2026-10-26: "it says last count 13:28" — the age of the
// fifteen-minute rollup read as a stale clock while the figures under it moved every second). It prints the
// server's own `at` of the newest live answer, in Korea time like the top bar's clock, so it ticks with them.

export const STATS_LIVE_MS = 1_000

export interface StatsLive {
  /** The newest answer, or null before the first one lands. Kept across a failed ask. */
  live: StatsNow | null
  /** Moves when `counted_at` moves: every face hands it to its rollup read as the `trigger`. */
  count: number
  /** The server's instant of the newest live answer, in ms. Null before the first one lands. */
  liveAtMs: number | null
}

export function useStatsLive(): StatsLive {
  const [live, setLive] = useState<StatsNow | null>(null)
  const [count, setCount] = useState(0)

  useEffect(() => {
    let alive = true
    let asking = false
    let lastCountedAt: string | null = null
    const ask = async () => {
      if (asking || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) return
      asking = true
      try {
        const r = await worldStatsNow()
        if (!alive || !r.ok) return
        setLive(r.value)
        if (lastCountedAt !== null && lastCountedAt !== r.value.counted_at) setCount((c) => c + 1)
        lastCountedAt = r.value.counted_at
      } finally {
        asking = false
      }
    }
    void ask()
    const id = window.setInterval(() => void ask(), STATS_LIVE_MS)
    return () => {
      alive = false
      window.clearInterval(id)
    }
  }, [])

  const liveAtMs = live === null ? null : Date.parse(live.at)
  return { live, count, liveAtMs: liveAtMs !== null && Number.isFinite(liveAtMs) ? liveAtMs : null }
}
