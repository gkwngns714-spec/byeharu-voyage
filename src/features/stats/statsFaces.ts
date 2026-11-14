import { wholePeriods, type RankRow, type SeriesPoint, type SumPeriod } from '../../components/ui'
import { instantMs } from '../../lib/format'
import { properName, t } from '../../lib/i18n'
import type { PriceSpan, StatsBonus, StatsFlowLine } from '../../lib/rpc'

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

/** WHAT A STATS READ'S POINTS SUM, by the span it answered: 1d the count's own rows (a quarter hour each), 1w and 1m hourly buckets, 1y and all daily ones
 *  (`public.stats_span_unit`, 0246, spoken once here). A read of no span is its own window of the count's rows. */
const SPAN_PERIOD: Record<PriceSpan, SumPeriod> = { '1d': 'quarter', '1w': 'hour', '1m': 'hour', '1y': 'day', all: 'day' }

/** What a stats read says about its series: the span it answered, and how far the counts reach (`counted_at`: its live point adds the minutes since). */
export interface ReadStamp {
  span?: string | null
  counted_at: string | null
}

/** THE ROWS OF A SUM THAT MAY BE DRAWN (owner, 2026-11-06 and 2026-11-07: no chart's right edge goes down). A stats read's series ends in a LIVE point at now()
 *  whose flows are only the minutes since the last count, and for a week, a month or longer its newest hour or day is still being counted. The rows that are
 *  WHOLE, by the one rule of every sum (`wholePeriods`, the figures reaching the read's `counted_at`), oldest first. A LEVEL (a holder, a purse, a count of
 *  ships) is not a sum: its live point is true, and the face keeps drawing `read.series` whole for it. A row whose instant does not parse is left out, as
 *  `toSeries` leaves it; a span this table does not know draws nothing rather than something short. */
export function wholeRows<T extends { at: string }>(read: ReadStamp, rows: readonly T[]): T[] {
  const reachMs = instantMs(read.counted_at)
  const period: SumPeriod | undefined = read.span == null ? 'quarter' : SPAN_PERIOD[read.span as PriceSpan]
  if (reachMs === null || period === undefined) return []
  const stamped = rows.flatMap((row) => {
    const atMs = instantMs(row.at)
    return atMs === null ? [] : [{ row, atMs }]
  })
  return wholePeriods(stamped, period, reachMs).map((s) => s.row)
}

/** The same rows as a sparkline's readings, oldest first — the line without an axis, for a figure
 *  that has a cell rather than a chart's worth of room. */
export function trendOf<T>(rows: readonly T[], pick: (row: T) => number): number[] {
  return rows.map(pick).filter((v) => Number.isFinite(v))
}

export type StatsFace = 'overview' | 'news' | 'markets' | 'cities' | 'merchants' | 'ships' | 'me'

/** The faces in order; each one's words are `stats.<id>` in the dictionary. 0347: News after Overview (docs/NEWS_AND_MARKERS.md §4). 0419: Ships after
 *  Merchants (the owner, 2026-11-15: "in stats, show like merchants navy, pirates, anad cargo"). */
export const STATS_FACES: readonly { id: StatsFace }[] = [{ id: 'overview' }, { id: 'news' }, { id: 'markets' }, { id: 'cities' }, { id: 'merchants' }, { id: 'ships' }, { id: 'me' }]

/** THE CHART OF A CARD (2026-11-02, owner row 267 — *"charts get room"*): a `SeriesChart` 176 px tall (its plot 150), drawn 1 : 1 at
 *  the width the card leaves, with its reading line above it — the unfold slice drew these as a 24-px sparkline. The large view
 *  (StatsChart.tsx `BIG`) is 640 × 280. */
export const CARD_CHART_H = 176

/** How many counts a bar row shows — the last six hours at a count a quarter hour. More bars than
 *  this and each one is thinner than the gap beside it (`SignedBars` says so), and 390px is the
 *  glass this game is drawn for. */
export const STATS_BARS = 24

/** A price move in percent points from `before` to `now`; null when either side is unknown. */
export function movePct(now: number | null, before: number | null): number | null {
  if (now === null || before === null || !Number.isFinite(now) || !Number.isFinite(before) || before === 0) return null
  return ((now - before) / before) * 100
}

/** The money flows as ranked rows, biggest first: the server's word on the left, its side as the
 *  tone — new money green, burned money red, money that only changed hands neutral (§4.4 keeps
 *  green and red for gain and loss alone). */
/** 0311: THE BONUS MONEY OF A PERIOD, off the lines the page already holds and the two figures the flows cannot say. One count: budget set and
 *  returned ARE the BOUNTY and BOUNTY_LAPSED lines. */
export function bonusBook(flows: readonly StatsFlowLine[], bonus: StatsBonus) {
  const line = (kind: string) => flows.find((f) => f.kind === kind)?.ducats ?? 0
  return { held: bonus.held, paid: bonus.paid, budget: -line('BOUNTY'), returned: line('BOUNTY_LAPSED') }
}

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
