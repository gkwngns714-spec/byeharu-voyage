# 2026-11-06 - The chart's right edge no longer drops (client only, no migration)

Owner: "in chart, i don't like the right edge chart to drop verticley."

Both causes were true. Read from prod (read-only, one `begin read only` session) and drawn headless at DPR 2 with the real series.

**B, the line plunges: true, for every SUM.** The newest day/week/month bucket is the period so far. On 2026-11-06 02:00 UTC: a good's day sold 6,728 against 95,202 the day before; a company earned 150,218 against 21,547,338; the world sold 198.7 M against 2.41 B. Levels (purses, holders, price close, the 15-minute stats count) do not do this: their newest reading is true.
**A, the wall: true, on every chart.** The wash closed `L lastX floor`, so every chart ends in a vertical wall at the right edge.

## What changed (one helper each, shared)
- `seriesChartModel.ts`: `settledBuckets(points, period, nowMs)` leaves out the bucket still open (day +1 d, week +7 d, month to the 1st; UTC like the server's `history_bucket`). Nothing is drawn in its place. `HistoryLine.flow` marks the twelve sums (minted, removed, sold, bought, profit, income, spending, earned, lost, net); `HistoryChart` applies it to those lines only, with `serverNow()`.
- `seriesChartModel.ts`: `washFade(firstX, lastX)` is the one spelling of the wash's right edge (opaque, then gone over the last 28 px, or half a short wash). `AreaWash.tsx` draws it (a mask, fill only; the line is untouched, nothing past the last point). `SeriesChart`, `PriceChart` and its stock strip all use it; `areaFade` is in both models.
- Specs: `tests/seriesChart.spec.ts` (open bucket out, whole ones kept, week and month ends, fade), `tests/priceChart.spec.ts` (shared fade). The ten word-label specs in those two files fail locally in the Korean locale before and after this change; CI is English.

## Images
Before: `img/2026-11-06-chart-right-edge-before.jpg` (world sold and good sold plunge; wall on every chart). After: `img/2026-11-06-chart-right-edge-after.jpg` (open day gone from the sums; wash fades out).
