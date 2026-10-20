import type { SeriesPoint } from '../../components/ui'
import { instantMs } from '../../lib/format'

// THE FACE TABLE of the Stats tab — pure data, so a spec can pin the five without reading JSX
// (navTabs.ts's idiom). Order is the owner's sentence: the world, the goods, the cities, the
// merchants, you. Each face asks ONE read (features/stats/*.tsx) and decides nothing.

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

export type StatsFace = 'overview' | 'markets' | 'cities' | 'merchants' | 'me'

export const STATS_FACES: readonly { id: StatsFace; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'markets', label: 'Markets' },
  { id: 'cities', label: 'Cities' },
  { id: 'merchants', label: 'Merchants' },
  { id: 'me', label: 'Me' },
]

/** How often an open face asks its read again, in ms. The job writes every fifteen minutes; a face
 *  that re-asked on the world's 3-s beat would ask the same row 300 times. One minute keeps "Updated
 *  N min ago" honest within the minute it prints. */
export const STATS_REFRESH_MS = 60_000

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
