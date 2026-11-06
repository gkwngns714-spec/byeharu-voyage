# A late chart read no longer moves the list (2026-11-06)

Cause of the intermittent red in `stats.goodTray.spec.ts` ("first row's top moved", 311 vs 463 at 1280, +304 at 390): Cities and Markets draw their two chart cards from `world.stats_overview`, which answers after the list's own read. Until then each card held the 44 px "line soon" note; on arrival it grew to the chart (20 px reading line + 176 px), pushing the list down 152 px (two stacked cards: 304). It only showed when the two reads landed in different frames.

Observed: with the CPU slowed 6x and a per-frame sampler, the list top went 1276 -> 1580 (+304) at 390 px.

Fix, in `SeriesChart` (the one place): a chart of a stated `height` reserves reading line + height for its `empty` too (`flow-root` so the note's margin cannot spill out). Covers Cities, Markets, Merchants, Overview and the city page. Spec: `tests/stats.listCharts.noShift.spec.ts` (red before, green after). `stats.goodTray` is unchanged.
