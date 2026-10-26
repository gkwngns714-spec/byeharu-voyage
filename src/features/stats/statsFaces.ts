import type { RankRow, SeriesPoint } from '../../components/ui'
import { instantMs } from '../../lib/format'
import { properName, t } from '../../lib/i18n'
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

/** The faces in order; each one's words are `stats.<id>` in the dictionary. */
export const STATS_FACES: readonly { id: StatsFace }[] = [{ id: 'overview' }, { id: 'markets' }, { id: 'cities' }, { id: 'merchants' }, { id: 'me' }]

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
      note: f.side === 'minted' ? t('stats.noteNew') : f.side === 'removed' ? t('stats.noteBurned') : t('stats.noteMoved'),
    }))
}

/** A served good in the viewer's language (Korean map by code; the served name otherwise). */
export const goodName = (g: { code: string; name: string }): string => properName('good', g.code, g.name)

/** A served port in the viewer's language (the map is keyed by the served name). */
export const portName = (name: string): string => properName('port', name, name)
