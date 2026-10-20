import type { RankRow, SeriesPoint } from '../../components/ui'
import { instantMs } from '../../lib/format'
import type { StatsFlowLine } from '../../lib/rpc'

// THE FACE TABLE of the Stats tab — pure data, so a spec can pin the five without reading JSX
// (navTabs.ts's idiom). Order is the owner's sentence: the world, the goods, the cities, the
// merchants, you. Each face asks ONE read (features/stats/*.tsx) and decides nothing.
//
// The helpers under it are PRESENTATION ONLY: they turn the server's rows into the shapes the
// design system's charts take (points on a time axis, readings for a sparkline, ranked rows). None
// of them computes a figure the server did not already serve.

/** Served rows with an `at` become the chart's points; a row whose instant does not parse is left out
 *  rather than drawn at nowhere (instantMs says null for one). Presentation. */
export function toSeries<T extends { at: string }>(rows: readonly T[], pick: (row: T) => number): SeriesPoint[] {
  const out: SeriesPoint[] = []
  for (const r of rows) {
    const ms = instantMs(r.at)
    if (ms !== null) out.push({ atMs: ms, value: pick(r) })
  }
  return out
}

/** The same rows as a sparkline's readings, oldest first — the line without an axis, for a figure
 *  that has a cell rather than a chart's worth of room. */
export function trendOf<T>(rows: readonly T[], pick: (row: T) => number): number[] {
  return rows.map(pick).filter((v) => Number.isFinite(v))
}

export type StatsFace = 'overview' | 'markets' | 'cities' | 'merchants' | 'me'

export const STATS_FACES: readonly { id: StatsFace; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'markets', label: 'Markets' },
  { id: 'cities', label: 'Cities' },
  { id: 'merchants', label: 'Merchants' },
  { id: 'me', label: 'Me' },
]

/** How often an open face asks its read again, in ms, when nothing else wakes it. The job writes
 *  every fifteen minutes; a face that re-asked on the world's 3-s beat would ask the same row 300
 *  times. One minute keeps "Updated N min ago" honest within the minute it prints — and the edge of
 *  the next count (statsPulse.ts) is what makes a fresh count arrive in seconds. */
export const STATS_REFRESH_MS = 60_000

/** How many counts a bar row shows — the last six hours at a count a quarter hour. More bars than
 *  this and each one is thinner than the gap beside it (`SignedBars` says so), and 390px is the
 *  glass this game is drawn for. */
export const STATS_BARS = 24

/** The share one holder has of the world's money, 0–100, for the Overview's bars. Presentation. */
export function sharePct(part: number, total: number): number {
  if (!Number.isFinite(part) || !Number.isFinite(total) || total <= 0) return 0
  return Math.max(0, Math.min(100, (part / total) * 100))
}

/** A price move in percent points from `before` to `now`; null when either side is unknown. */
export function movePct(now: number | null, before: number | null): number | null {
  if (now === null || before === null || !Number.isFinite(now) || !Number.isFinite(before) || before === 0) return null
  return ((now - before) / before) * 100
}

/** The money flows as ranked rows, biggest first: the server's word on the left, its side as the
 *  tone — new money green, burned money red, money that only changed hands neutral (§4.4 keeps
 *  green and red for gain and loss alone). */
export function flowRanks(flows: readonly StatsFlowLine[]): RankRow[] {
  return [...flows]
    .sort((a, b) => Math.abs(b.ducats) - Math.abs(a.ducats))
    .map((f) => ({
      id: f.kind,
      label: f.word,
      value: f.ducats,
      tone: f.side === 'minted' ? ('success' as const) : f.side === 'removed' ? ('danger' as const) : ('neutral' as const),
      note: f.side === 'minted' ? 'new money' : f.side === 'removed' ? 'money burned' : 'moved between purses',
    }))
}
