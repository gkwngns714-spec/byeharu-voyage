# Cities and Markets take Merchants' page (owner rows 294, 295, 2026-11-05)

Orders: *"in stats, make the cities tab like merchants"* and *"same for markets, a general graph would be nice"*.

## What was found
- `stats_cities` and `stats_markets` serve no series. `world.stats_overview(hours, span)` already serves one across every city and every good (`holders.cities`, `sold`, `bought` per count), over the shared span (`useChartSpan`). So the graph is client-only: no migration.
- PR #499 (0316) adds a daily/weekly/monthly `HistoryChart` and touches Merchants, Overview, CityDetail, GoodTray. This slice touches none of those files; it adds a Stats dict block at a different place. #499 can land before or after.

## What changed
- `WorldSeries.tsx`: `SeriesCard`, one chart card (title, current figure, 176 px line), the Merchants pattern. `useWorldSeries.ts`: the Overview's own read under its own subject (one ask per subject).
- Cities: PageSplit, side first. Main: city purses and city trade cards over the list. Side: the day (taken in, paid out, taxes, traded: plain sums of the served rows) and money by area (the purses summed per served area).
- Markets: main gains two cards (sold to cities, bought from cities) over the list.
- Law test `tests/stats.listCharts.spec.ts`.
