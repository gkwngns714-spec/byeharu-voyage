# The Map, on the page pattern (2026-11-04)

Owner, 2026-11-02, verbatim (row 267): *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now everything is on left, too packed. this was a mistake"*. Stats (#466, `2026-11-02-stats-design.md`), HQ (#478, `2026-11-04-hq-design.md`) and Fleets (#479) took the page; the Map is the last. Client-only: no migration, no served field, no read changed.

## 0. What the pattern means for a one-glass chart

The Map is not a column of cards: it is one glass of chart, and the order was not to reduce it or add density. So the pattern is read as:

- **MAIN is the chart**, whole, edge to edge, as it was. It is never reduced or pushed (a law below).
- **SIDE is the tray column.** A selection panel (a harbour, a fleet, a merchant, open water) is the page's side column: from 1,024 px it is `--page-side` wide (352 / 384 / 416 px at 1,024 / 1,280 / 1,440) with its right edge on the page's margin, rounded on every side, and it slides OVER the chart's right part. It was 39 rem (624 px) flush to the glass's edge, a third of the chart at 1,440. The second panel (a ship opened from a fleet) stands to its left, the same width, 1 rem between (it was 26 rem, flush to the first).
- **The corner chrome gives way** to the tray's real left edge (zoom column, Regions), by the same numbers.
- Below 1,024 nothing changes: the tray is the glass.

The chart's own corner controls, the fleets pill, the minimap and every test id are untouched. No text was added, so no dictionary entry.

## 1. What changed

- `src/features/map/MapScreen.tsx`: the chart root takes `pageVarsClass()`, so `--page-pad` / `--page-side` are set there as on a Sheet (the trays are inside it and read them).
- `src/components/ui/screenLayout.ts`: **shared primitives touched, additively in value only.** `traySideEdgeClass`, `traySideNextClass` and `chromeAsideSideTrayClass` change their `lg:` classes to read the page vars. Their only users are the Map's trays (`Tray mode="side"` / `"side-next"`: VoyageTray, SendFleet, MerchantSheet, ShipPanel, TradeHistoryPanel); no function was added or removed and no other screen's look moves. Below `lg` the strings are as they were.

`Tray.tsx`, `Sheet`, `Card` and the rest are unchanged. The `<main>` landmark is the AppShell's, which the Map stays inside (it does not own one); `tests/onepage.spec.ts` was run.

## 2. The test, red then green

`tests/map.design.spec.ts` (five glasses: 1,440 / 1,280 / 1,024 / 390 / 320): press Lisbon; (a) the chart's box is identical shut and open; (b) from 1,024 the tray is the side column's width and its right edge is at the page's margin; (c) the zoom column stands left of the tray; (d) below 1,024 the tray is the glass; (e) the document stays flat.

**Red** against origin/main's build (`f689db21`): 1,440 and 1,024 fail (b): "the tray is 624 px wide — the side column is 416 / 352" and "right edge 0 px from the glass's — the margin is 80 / 32". (The 1,280 walk was not run on the old build; 390 / 320 passed there too, as expected since below 1,024 nothing changes.)
**Green** against this branch: all five pass.

`tests/map.shipPanel.spec.ts` (wide) pinned the old numbers (39 rem and 26 rem flush to the edge) and now pins the new (right edge 40 px at 1,280, both panels 24 rem, a 1-rem gap).

Picture (headless Chromium, dark, DPR 1, local world): `img/map-design/after-map-open-1440.jpg`, `after-map-open-390.jpg`. No "before" picture was kept: the old build was replaced before it could be shot with the harbour open; its measured numbers are above.

## 3. Other specs run by hand (local mode, one file at a time, `--workers=1`, this branch's build)

Passed: `onepage` (2: 390 and 1,280, every route incl. map, main landmark, flat document), `map.shipPanel` 2, `map.sendfleet` 9, `map.goto` 11, `map.goodChartSlide` 2, `map.hulls` 10, `map.marks` 9, `map.landfall` 4, `map.wrap` 8, `map.regions` 11, `map.shipFullPath` 2, `map.noblink` 2, `map.lag` 5, `nav.geometry` 4, `wide.layout` 7, `align` 2, `flags` 7, `map.design` 5.

Failed, 4 tests, all plain-logic word checks that read the machine's Korean locale and have nothing to do with layout: `waters.panel` x3 ("240 miles" vs "240해리"), `map.merchants` :239 ("7 merchants · 4 in port" vs "상인 7명 · 4명 정박"). CLAUDE.md names this ("plain-Node word specs may fail locally and pass on CI"). They were not run on origin/main's build here; that they fail the same way there is the expectation, not a measurement.

## 4. What was not verified

- Only the local (PGlite) world, canary data; DPR 1; dark scheme. Korean was seen in the picture only; the new spec runs in the default locale.
- The merchant, fleet and open-water trays were not looked at on the new layout by eye; the fleet + ship pair is held by `map.shipPanel.spec.ts` at 1,280.
- At 1,440 a strip of chart (the page margin, 80 px) shows to the right of the tray; that is the pattern's margin, and it is a taste call.
