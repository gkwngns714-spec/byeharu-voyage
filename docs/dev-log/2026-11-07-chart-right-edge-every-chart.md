# 2026-11-07 - No chart's right edge goes down: every chart audited, one rule for every sum (client only, no migration)

Owner, 2026-11-06 (row 303): "in chart, i don't like the right edge chart to drop verticley." Owner, 2026-11-07, after #530 and #531 were live: "and fix the charts. i said i don't like the right edge of the chart chat goes down. - every chart".

He repeated himself, so the first fix had not removed what he looks at. #530 / #531 left out the still-open day, week or month of a RECORD (`world.history`) and faded the wash; they were applied to the twelve sum lines of `HistoryChart` and nowhere else. This file is the audit of every chart and the fix at the root. Nothing here is inferred: the real faces were drawn headless at DPR 2 (1440x731 and 390 wide) from rows read off prod tables.

## The causes (found by looking, not by reasoning)

**1. THE LIVE POINT. Every Stats sum, at every span, ended in a plunge.** `world.stats_overview` and `world.stats_city` end their `series` with one point at `now()` (0232: "a chart = the counts' points + one live point at now()"). That point's STATES are true (a purse, a holder). Its FLOWS (sold, bought, minted, removed, moved, income, spending) are only the minutes since the last count. The live bodies on prod say so (`pg_get_functiondef`, read-only). Measured, 2026-11-07:
- 07:22:23 UTC, 1.5 minutes after the 07:21 count: 1,821,942 sold against 26,122,487 in the quarter hour before it, 93 % down. A city (Copenhagen): 29,222 in against 578,762.
- 07:19:09 UTC, 13 minutes after the 07:06 count: 21,711,164 against 25,022,617, 13 % down.
So the edge swung between a cliff and a wiggle every quarter hour, which is why it looked like a defect that came and went, on every chart of a sum: Overview sold and bought, the Money flows bars, Markets sold and bought, Cities trade, a city's Net bars.

**2. THE OPEN HOUR OR DAY (1w, 1m, 1y, All).** The bucket the last count stands in is still being counted: the 07:00 hour held 2 of its 4 slots (51,145,104 against 101,091,608 the hour before), today 30 of 96 (719,427,742 against 2,371,026,924). Before the live point, a second drop.

**3. TODAY'S BAR (Stats > Me, Command > Report).** `world.report` zero-fills its days up to today and today's net is the day so far: the newest bar stood short beside whole days (drawn with a merchant company's three kept days standing in for a player's books: today +2,065,159 against -3,802,633 the day before), and the Report's Today span was a single bar of nothing else.

**Not causes (looked at, left alone):** the levels (their live point is the true reading; the line ends at its real last value, including a real fall: the merchants' purses 10.34 B to 10.23 B over the day); the wash (the fade of #530 is the last 28 px of fill only, no chart has a wall now); the price chart (`world.price_series` serves each period's CLOSE; no live point; the line ends at the last served point with the now ring); the estimate to the right of now (`outlook` is passed by no caller since the Markets face lost it); every record line (already whole after #530: rendered byte-identical before and after this change).

## The audit: what each chart's right edge does, and why

| Chart | Drawn by | Kind | Right edge BEFORE | After |
|---|---|---|---|---|
| Overview: Sold to cities, Bought from cities (1d 1w 1m All) | SeriesChart via StatsChart | sum | plunge to the floor: the live point (plus the open hour or day on 1w..All) | ends at the last whole count, hour or day |
| Overview: Money flows bars | SignedBars | sum | last bar = the live point | whole periods only |
| Markets: Sold, Bought; Cities: City trade | SeriesCard | sum | plunge: the live point (and the open bucket) | whole periods only |
| City page: Net (income less spending) | SignedBars | sum | last bar a sliver (the live point: +29,222) | whole periods only |
| Me: My week; Report: by day | SignedBars | sum | today so far | days that are over; today stays a figure |
| StatsChart large view (tray) | SeriesChart | sum | the same points as its card | follows its card |
| Overview: World money; holders | SeriesChart, Sparkline | level | the real current value | unchanged |
| Cities: City purses; Merchants: purses, at sea, earned 24 h; City page: purse, people | SeriesChart | level | the real current value (the merchants' purse really falls) | unchanged |
| Money / City / Market / Gold record (HistoryChart, day week month) | SeriesChart | levels and sums | levels end today; sums end at the last whole period (#530) | unchanged: the one rule, now shared |
| Good tray (world line, city line); goods rows; Buy/Sell day line | SeriesChart, Sparkline | level | the real last price | unchanged |
| Price chart (good page, map market panel, quay tray rows): ask, bid, bands, stock strip | PriceChart | level | last served close, now ring, wash faded | unchanged |
| Ledger: moves bars | SignedBars | one bar per MOVE, no period | the real newest move | unchanged |
| StackedBar, RankBars, design gallery (`/ui`) | - | no time axis, or literal fixtures | - | - |

## The fix: one authority per concept

- `wholePeriods(points, period, reachMs)` in `src/components/ui/seriesChartModel.ts` replaces `settledBuckets` (deleted). `period` is `quarter` (a count's own row), `hour`, `day`, `week` or `month` (`SumPeriod`). `reachMs` is the instant the figures are complete to. (1) Nothing that stands after the reach is a period: that is the live point. (2) Of what is left only the newest can still be running: it goes while its period ends after the reach. A level is never passed.
- A Stats read's reach is its `counted_at` (the server's own word for how far the counts go), not the clock: a count that did not run leaves its hour open instead of showing it short. A record's reach is the server's now. A month is judged by its longest length (31 days), as before: the client does no month arithmetic (tests/duplication.spec.ts).
- `wholeRows(read, rows)` in `features/stats/statsFaces.ts` is the Stats faces' door to it: the span names the period (`1d` quarter, `1w`/`1m` hour, `1y`/`all` day: `public.stats_span_unit`, 0246), `counted_at` is the reach. Overview, Markets, Cities and the city page draw their sums from it; their levels keep drawing `series` whole, live point included.
- `reportBars(days)` in `src/live/reportBars.ts` serves both bar faces (Me, Report) and replaces two hand-written copies of the day-to-bar mapping; `realDayMs` in `lib/format/time.ts` is the one place a real UTC day number becomes an instant. `HistoryChart` calls `wholePeriods` with the server's now.
- Not changed: the server (no migration), the figures beside the charts (the day totals and counters still walk to the second, owner row 213), the fade, the axis words.

Said plainly: the right tick still reads "now" (it is the newest point, as it was for the record lines after #530); in a young world a week or longer has no whole hour or day yet and says "line soon"; a month is held back for the minutes between its end and the next month's first row.

## Specs

- `tests/wholePeriods.spec.ts` (pure Node, passes in the Korean and the English locale): each period against the real 07:22 figures above; the reach exactly on a bucket's end (whole) and one millisecond before (open); the live point; only the newest can be open; any order; NaN draws nothing; `wholeRows` for all five spans, a read of no span, an unknown span, a count that did not run; `reportBars`; `realDayMs`.
- `tests/rpc.stats.spec.ts`: one more test holds the rule on the server's real reads, the world and a city, over every span: the live point is never whole, no whole row stands after the last count, the hour or day the last count stands in is left out.
- `tests/seriesChart.spec.ts`: the two `settledBuckets` tests moved into the new file; the wash test stays.

## Images (DPR 2, headless, the real faces fed by rows read off prod tables)

`img/2026-11-07-chart-edge-sums.jpg` the sums, BEFORE (left) and AFTER (right): Overview Sold to cities at 1d 1.5 minutes after a count (the plunge at its deepest: the reading above the chart was the live point's 1,821,942, now the last whole count's 26,122,487, and the y scale is the data's again, not stretched to the floor by the plunge), at 1d 13 minutes after one (the plunge at its shallowest, a dip), at 1w, at All (two drops, the open day and the live point); Bought from cities 1d; Markets Sold 1d; Cities City trade All.
`img/2026-11-07-chart-edge-bars.jpg` the bars, BEFORE and AFTER: Money flows at 1w (its net is zero at the right edge in this world, so it barely moves), a city's Net at 1d and All (the live sliver of +29,222 is gone), My week (today's bar is gone), and the last four rows at 390 px wide.
`img/2026-11-07-chart-edge-levels.jpg` the levels, the records and the price chart, which are byte-identical before and after.

## How it was measured

Read-only SELECTs from files, one statement each, inside `begin transaction read only`: `stats_world`, `stats_city`, `stats_merchants` (cut into the span tiers exactly as `world.stats_*` cut them), `history_world_day`, `history_city_day`, `history_good_day`, `history_company_day`, `price_history`, `price_history_hour`, `price_history_day`, and, for the live point, `events`, `treasury_flows`, `ledger`, `stats_flow_words`, `port_treasury` (the three `stats_window_*` rules re-spelt as table reads; no `world.*`, `cmd.*` or `tick_*` function was called; the live LEVELS are the last count's, because `stats_now` was not called). A throwaway backend answered the real faces from those rows (never committed), the page clock fixed at the instant of each read, two reads: 07:22 (1.5 minutes after a count, the plunge at its deepest) and 07:19 (13 minutes after one, at its shallowest). 34 of the 65 shots are byte-identical before and after (every level, every record, every price chart); the 31 that changed are exactly the sums.

Checks, all green here: `tsc -b`, `eslint`, `vite build`; `tests/wholePeriods.spec.ts` (9), `tests/seriesChart.spec.ts`, `tests/countUp.spec.ts`, `tests/rpc.stats.spec.ts` (8, booted from the cached world image of this chain, 11 s); and against this build 42 existing tests that draw these faces: `stats.tab`, `stats.listCharts`, `stats.listCharts.noShift`, `stats.design`, `stats.bigChart`, `stats.goodTray`, `history.periods`, `desk.report`. Two mutation controls: with the reach cut removed (the live point kept) 6 specs go red, including the real-read test in `rpc.stats`; with the open-period rule removed 8 go red. The machine locale is Korean: the word specs (`seriesChart` 10 and 45, `countUp` 43) fail here without an English `navigator.language` and pass with one (a preload that sets it), as on CI. CI's selection for this diff is 126 specs (rule A: `src/components/ui` changed), `wholePeriods`, `rpc.stats` and `seriesChart` among them.
