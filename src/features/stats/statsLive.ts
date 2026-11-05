import { worldStatsNow, type StatsNow } from '../../lib/rpc'
import { useLiveRead } from '../../live/liveRead'

// THE TAB'S ONE WAY OF ASKING — every Stats read is asked again every second while it is on screen
// (0224 for the live band; 0232 for every face; docs/dev-log/2026-10-26-stats-all-live.md).
//
// THE OWNER (docs/OWNER_REQUESTS.md row 213, 2026-10-26, after rows 187 and 200): *"and why is next count in
// minutes? i told you it should be in seconds?"*. Since 0232 every face's read answers NOW on the server, so
// there is nothing to wait for and no count to show: a face simply asks its read every second.
//
// ONE RULE FOR EVERY READ ON THE TAB: `useLiveRead` (src/live/liveRead.ts — moved there 2026-11-05 so the City
// page shares the one hook). The rule is written there.
//
// THE HEADER says when the figures are from: the server's own `at` of the newest live-band answer, in Korea time
// like the top bar's clock, so it ticks with them.

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
