# 2026-11-13 — news dots on the trays' chart; the "pressing moved its chart" red (owner row 216)

Client only. No migration, no new read.

## 1. The red: `tests/news.dotSize.spec.ts` at 390 px, "pressing '… news' moved its chart"

### What was believed

A block above the chart lands late, after the press, and pushes the chart down (as the Watch card did on Stats, fixed in #598).

### What was measured (unchanged main 26a028e0, a served build, the spec run again and again at 390 px)

- **Before rate: 1 red in 25 runs** of the spec as it stood ("stats city: pressing '3 news' moved its chart", y 296 → 668). A copy of
  the spec that also logged the page went red in runs 15 and 1 of two more loops, the same line both times.
- The logged red (every frame: each chart's box, each dot's place, the open card, the focus; every scroll; every layout shift the
  browser reports):
  - no block was added, none changed height, the browser reported **no layout shift**;
  - one frame before the press, both dots moved by −0.11 and −0.125 px;
  - then the Stats city page's own scroller went from 750 to 378: **a scroll of 372 px, exactly the "move"**. After it the dot's foot
    stands on the glass's foot (y 668 + 176 = 844).
- The trace of that press: `element is not stable` → `retrying click action` → `scrolling into view if needed`. Playwright's second
  try of a press scrolls its target to the bottom edge. The spec compared boxes on the glass, so that scroll read as a moved chart.

**So nothing in the page jumps, and a player does not see this.** What is real is the trigger: a dot's press target was never at
rest.

### Why a target was never at rest

A live chart's time axis ends at now. A mark stands at its own instant, so it creeps left with the clock, and the target was centred
on its mark. Sampled every 250 ms for 7 s on main:

| Chart | The target's left edge |
|---|---|
| HQ market (`MarketLeft`, the axis ends at the shell's clock) | 282.625 → 281.641: **0.14 px each second** |
| Stats city page (the live read's last point) | 195.953 → 195.281: **0.10 px each second** |
| The desk's good chart (the axis ends at the instant it was opened) | did not move |

The desk's chart is the one surface this red was never seen on.

### The fix (in the app)

`newsMarksModel`: in a chart's box a target stands on a lattice of `NEWS_HIT_STEP` = 11 px (a quarter of its 44-px side; it divides
the side, so targets a side apart stay a side apart). The target holds still for a minute or more and then steps once; the mark is
still drawn at its own instant, inside the target, at most 5.5 px from its centre unless the box's edge or a neighbour moved the
target further (as before). Without a box a target is its mark's centre, as before. `tests/news.lint.spec.ts` proves it in Node: over
two minutes of a quarter-hour chart read each second the marks creep 238 times and the targets move at most 8 times, one step each,
never overlapping.

### The spec

"The chart's box does not move" is now read in the page's own terms (`placeOf`: the box plus how far everything it scrolls in is
scrolled). A block that lands late above a chart still moves it; a scroll does not. This is not a looser law: the law was always
about the page re-flowing.

### After

Measured on the new build at 390 px; the figures are in the PR's body (the spec as it stood on main, run against the new build, and
the new spec).

## 2. News dots on the trays' chart (the map's good panel, the quay's trays)

`docs/NEWS_AND_MARKERS.md` N4-N6 are SERVER slices (big trades, price spikes, pirates, gifts as news kinds: hunks in `cmd.do_sell`,
`cmd.do_buy`, `tick_price_snapshot`, `voyage.settle`). None of that is built here, and none can be from the client.

What the client could do, and now does: the chart the trays draw (`PriceRows`) shows the same dots as the HQ's and the desk's.

- `PriceTrend` (the design system's shape of one good's price at one city) may carry `news`; `PriceRows` hands it to its `PriceChart`.
- `useTrendNews(port, good, trend)` in `src/live/useChartNews.tsx` is the one place a tray's trend gets its news: the existing
  `useChartNews('price', …)` over the existing `world.news_marks`, asked only once the series has landed.
- Its three callers render the card beside their tray: `PortPrices` (the map's good panel and the read-only price tray),
  `PortTrade` (the quay's trade tray), `MarketFace` (the HQ market's trade tray).
- Dots stand on the unfolded chart only. The folded sparkline draws none (the design: too small to press).

So a tray's chart shows this city's news of this good and the world's headlines. Today the server writes only `UPDATE`,
`NEW_HARBOUR` and `RELATIONS`; when N4-N6 add kinds, these charts draw them with no client change.

Decided by default: the tray asks for news whenever its series has landed, folded or not (one small read, again each half minute while
open), so the dots are there the moment the chart unfolds.

## 3. The same spec red in the combined tree (batch-5, #626): a dot that was no longer there

**Seen:** `tests/news.dotSize.spec.ts` at 390 px ran 15.1 minutes on CI and hit its 900 s clock, waiting for the third dot of the
Stats city chart (`news-dot` `nth(2)`). The chart had been read as `"5 news" · "1 news" · "3 news"`.

**Cause (the spec's method, met by two facts of the world):**

- **Dots regroup as a live chart's time stretches.** Marks closer than a 44-px target are one dot, and a Stats chart's time ends at
  now, so the gap between two marks shrinks every second. The probe's headlines 10 and 5 minutes old stand about 46 px apart on a
  Stats city page at 390 px, and come under 44 px about a minute after the seed. Sampled on a build of batch-5: the chart read
  `"1 news" · "8 news"` until 36 s after the seed and `"9 news"` from 44 s on. CI reached that chart 62 s after the test began. The
  spec counted the dots once and then pressed them by position, and a wait with no limit used the whole 900 s.
- **The image's own news joins the probe's.** Every lit migration writes one "Update" row when the world image is BUILT. On an image
  minutes old those rows stand inside the charts' time: on the local batch-5 build five of them, 44 to 58 s old, joined the probe's
  last dot ("8 news"); on CI they were the extra "5 news" dot. This is also the "no chart drew two dots" red an integrator saw once.

A dot merging into its neighbour once, as the record grows, is what grouping by distance means; a player would have to press in that
very frame, and the merged dot opens the same news. The app's grouping is left as it is.

**The fix (the spec, and one attribute):**

- The probe's world holds ONLY the probe's four headlines: the image's own news rows are taken out of the test's private copy. The
  number of migrations no longer changes what the test reads or how long it runs.
- A dot carries `data-news-ids` (`NewsDots.tsx`). The spec reads the chart again before each press, asks for the next unpressed dot
  by its own news, and treats a dot that is gone at its turn as a regrouping: it reads again and presses what stands there now.
- Every step has a 10 s limit; a surface gets at most 24 reads; the whole test has 300 s (was 900 s).
- The laws are the same, and one is tighter: each chart's dots must hold exactly the probe's four headlines, each once (it was "at
  least four").
- The card's count stops at five (the same line as `news-kinds`, so the two merge).

A forced case (35 s of waiting before each press, Stats city only): read `"1 news" [51] · "3 news" [54 53 52]`, the second was gone at
its turn, read again `"4 news" [54 53 52 51]`, pressed, green.
