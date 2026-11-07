import { wholePeriods } from '../components/ui'
import { realDayMs } from '../lib/format'
import { serverNow } from '../lib/serverClock'
import type { ReportDay } from '../lib/rpc'

// THE REPORT'S DAYS AS BARS — WHOLE DAYS ONLY (owner, 2026-11-07: *"i said i don't like the right edge of the chart goes down. every chart"*).
//
// `world.report` serves its day axis zero-filled up to TODAY, and today's net is the day so far, so the newest bar always stood short beside the whole
// days before it (and the Report's Today span was one bar of nothing else). A day's bar is a SUM, so it is drawn once its day is over, by the one rule of
// every sum (`wholePeriods`) with the figures complete to the server's now. Today is not lost: it stands as a figure beside the bars (Me's Today, the
// Report's total). Both faces that draw these bars (Stats > Me and the Command Report) take them from here, so there is one reading of "a whole day".

/** The served days, oldest first, as `SignedBars` takes them: the days that are over. */
export function reportBars(days: readonly ReportDay[], nowMs: number = serverNow()): { id: string; value: number }[] {
  return wholePeriods(
    days.map((d) => ({ id: String(d.day), value: d.net, atMs: realDayMs(d.day) })),
    'day',
    nowMs,
  ).map(({ id, value }) => ({ id, value }))
}
