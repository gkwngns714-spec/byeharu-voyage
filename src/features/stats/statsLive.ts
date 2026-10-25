import { useEffect, useState } from 'react'
import { useShellState } from '../../app/shellState'
import { worldStatsNow, type StatsNow } from '../../lib/rpc'
import { serverNow } from '../../lib/serverClock'

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
// MEASURED AS A GAP, NEVER AS A DATE (Rank's idiom, kept from statsPulse): the age of the last count is the
// server's own `at − counted_at` plus the time elapsed HERE since the answer landed, both on the one clock
// (lib/serverClock), so a device whose clock is wrong by an hour still ages a minute as a minute.

export const STATS_LIVE_MS = 1_000

export interface StatsLive {
  /** The newest answer, or null before the first one lands. Kept across a failed ask. */
  live: StatsNow | null
  /** Moves when `counted_at` moves: every face hands it to its rollup read as the `trigger`. */
  count: number
  /** How long ago the last count was, in ms, on the one clock. Null before the first answer. */
  countAgeMs: number | null
}

export function useStatsLive(): StatsLive {
  const { nowMs } = useShellState()
  const [state, setState] = useState<{ live: StatsNow; landedMs: number } | null>(null)
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
        setState({ live: r.value, landedMs: serverNow() })
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

  const countAgeMs =
    state === null
      ? null
      : Math.max(0, Date.parse(state.live.at) - Date.parse(state.live.counted_at)) + Math.max(0, nowMs - state.landedMs)
  return { live: state?.live ?? null, count, countAgeMs }
}
