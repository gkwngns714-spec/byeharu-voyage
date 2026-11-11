# 2026-11-11 — a news dot is a 44-px press target (follow-up to 0347 / #573)

## What was found

`tests/hq.design.spec.ts` failed its "all five places" tests on unchanged `origin/main` (ffa9bf60) on a local world, with one line:
`market: (b) a control under 44 px — news-dot "3 news" 24×24`. Main's Acceptance run was green.

## Why local was red and CI green (read off the running state, not guessed)

Both worlds HAVE the news rows: every built world carries the `UPDATE` rows of 0347, 0348 and 0349 (ids 15, 17, 18 in the local image).
What differs is whether a chart's time reaches back to them.

- A news row's `at` is the moment its migration was applied when the world image was built (`clock_timestamp()`). In the local image:
  2026-11-11 13:38:37, :49, :53 UTC.
- A price chart in a local tab has no record of its own (the image's `price_history` is one slot of 2026-11-05, outside the 1-day
  span). `src/lib/rpc/localBackend.ts` writes the present slot and a copy one slot (15 min) earlier, so the chart's record starts
  **15 minutes before the tab opened**, and `useChartNews` asks for news from that minute on.
- So the HQ's market chart draws the image's own Update rows **only when the image was built in the last quarter hour.** Reproduced:
  at about 13:52 UTC `hq.design` at 1280×800 failed with the line above; a few minutes later (past 13:54) the same command passed, on
  the same build, with nothing changed.
- CI keys the image by the chain (`world-image-<hash of the migrations>`) and restores it; the image of a chain is built once, by the
  first build that sees that chain (the migration's own PR), long before main's Acceptance shards open the HQ. Its rows are hours old,
  the chart does not reach them, no dot is drawn, nothing is measured.

The live game is the case that matters: there a price chart's record is a real day (and 30 days, and years, on the longer spans), so
every Update row is a dot on it. The 24-px button was live.

## The defect, and a second one behind it

1. **The target was 24 × 24** (`h-6 w-6`), under the 44-px law of every control.
2. **Neighbouring dots lay over each other.** Marks merged only under 12 px (of the chart's sheet), but each had a 24-px button: two
   marks 13 px apart were two buttons 11 px over each other. Measured on main at 1280 on the HQ's market chart with the probe below:
   three dots at x = 641, 654, 667; Playwright could not press the first one ("another news-dot intercepts pointer events") for the
   whole 900-s budget.

## The fix

- `src/components/ui/newsMarksModel.ts`: `NEWS_HIT_PX = 44` replaces `CLUSTER_PX = 12`. ONE number is the target's side and the
  merging distance, so what stands closer than a target is one dot and two targets never overlap. With the `box` the plot stands in,
  the model also gives each dot a target centre (`hitX`, `hitY`) kept inside that box and a side apart from its neighbour; the mark
  itself stays at its instant and is always inside its own target.
- `src/components/ui/NewsDots.tsx`: the button is 44 × 44 (the game's way for a small glyph: a 44-px box around it, as Stepper, Tray's
  close and Field's clear do with `h-11 w-11`); the mark drawn is unchanged (6 px, or 14 px with a count). The layer measures its own
  box and gives the model the plot in px of the glass, so 44 is 44 on a scaled sheet too (the non-compact charts are scaled). The
  layer is still `absolute inset-0` over the svg: nothing re-flows when a dot is drawn or pressed.
- No word, no migration, no chart model changed.

## Measured (local preview, DPR 2, the probe of `tests/news.dotSize.spec.ts`)

| surface | before (main ffa9bf60) | after |
|---|---|---|
| HQ market @390 | "4 news" 24×24 | "4 news" 44×44, mark 14×14 |
| desk good @390 | "4 news" 24×24 | "1 news" 44×44 (mark 6×6) · "3 news" 44×44 (mark 14×14) |
| Stats world / merchants @390 | 24×24 each | 44×44 each |
| Stats city @390 | 24×24 each | "1 news" 44×44 · "3 news" 44×44 |
| HQ market @1280 | three dots 24×24 at x 641 / 654 / 667, overlapping 11 px; the first cannot be pressed | "1" · "1" · "2", each 44×44, at x 543 / 606 / 656: none overlaps, each opens its own news |
| Stats city @1280 | (not reached: the run ended at the HQ) | "1" · "1" · "2", each 44×44 |

(The before and after probes differ in spacing: before 3 / 2 / 1 min / 55 s, after 10 / 5 / 1 min / 55 s, widened so that neighbours
stand apart under the new merging distance.)

## The spec that closes the gap

`tests/news.dotSize.spec.ts` puts the news there itself: the built world, its first count half an hour old, four world headlines
10 min, 5 min, 1 min and 55 s before the seed (seeded for each test, because the facts are minutes old). At 390 and 1280 it walks the
HQ's market chart, the desk's good chart, Stats Overview (all three charts), Stats Merchants and a Stats city page, and on every dot
reads: target at least 44 × 44, inside its chart's box and the glass; no two targets of a chart overlap; the mark inside its target; a
press at its centre reaches it; the card it opens holds exactly its news; the chart's box does not move; no sideways scroll. It must
see two dots on some chart, so the neighbour law is never vacuous. Red on main's build (34 lines at 390; at 1280 a dot that cannot be
pressed), green on this one.

`tests/news.lint.spec.ts` gains the model's own law (targets inside the box, a side apart, the mark inside); `tests/news.chart.spec.ts`
asks 44 px of the dot and reads the instant off the mark.

## Decided by default

- The merging distance grew from 12 to 44 px: a busy stretch of a chart shows fewer dots with larger counts. That is the price of every
  dot being pressable; the card lists all of a dot's news.
- A dot's target covers 44 px of the plot's foot: the chart's own hover does not answer under it.

## Not proven

- Nothing was read from or measured on the live game. That the live charts showed 24-px dots follows from the code and the chain, not
  from a look at prod.
- CI's timing is read from the workflow (image cached by chain) and from main's green runs; no CI log was opened to read the image's
  age. A main run that opened the HQ within 15 minutes of building a new chain's image would have been red.
- A plot that fills its box edge to edge with dots packed at exactly 44 px can need more room than the box has (n × 44 > the width):
  the targets then keep apart and the leftmost hangs out of the box. No chart in the game has such a plot (each has a figure column or
  padding); the spec would say so if one did.
- `hq.design` is green locally now, but it was already green again once the image was 15 minutes old; its law on a chart WITH news
  is what `news.dotSize` measures.
