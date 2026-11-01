# MAIN RED on fe610dd0 (#440): three specs, one root in the shared Row

2026-11-01. Main's full-suite Acceptance has been red since #440 ("the figure sits beside its label",
`fe610dd0`); the last green main was #439 (`f4cac950`). 208 passed, 3 failed — and none of #440's
four gates (`primitives.geometry`, `layout`, `onepage`, `align`) measures any of the three screens:

| spec | what it read | the screen |
|---|---|---|
| `consistency.spec.ts:379` (390×844) | `390 desk/City: sideways scroller desk-city (367/358)` | Command › City, the quay's trade rows |
| `consistency.spec.ts:568` | the expanded hall book's inner scroll **313/278** (35 px; floor 12) | HQ at 320×568, the Influence book |
| `market.desk.spec.ts:34` | `<span …>444</span> from <button disabled …> subtree intercepts pointer events` | City › Market at 390, the first good's Buy cell |

All three reproduced locally on a served build of `08c4afac` (local mode) with the CI numbers:
313/278, the interception, and the sideways scroller (366/358 here, 367 on CI — one pixel of font).

## Cause: two defects in `Row`'s new tracks (`src/components/ui/Row.tsx`, #440)

#440 replaced the template `[mark] 1fr [value] [chevron]` (a track only for a slot that exists) with
five FIXED tracks, `auto minmax(0,auto) auto minmax(0,1fr) auto` (`Row.tsx:112` on `08c4afac`), under
the shell's `gap-x-3` (`:152`).

1. **A gap was charged for every track, filled or not.** An empty track is 0 px wide but the 12 px
   `column-gap` on each side of it is real: a lone-label row paid 4 × 12 = 48 px. Measured in the HQ
   book (120 px wide at 320): `"No gifts yet."` got `0px 72px 0px 0px 0px` — 72 of 120 px — and wrapped
   to a second line (24 → 48 px). That is the +24 px: the panel's inner scroll went 11 → **35**. (The
   same empty first track also stood every mark-less label 12 px in from its row's edge: 188 against
   the book's 176.) The chevron made it worse: it was placed at `gridColumn: -1` (`:136`), and line −1
   is the grid's END line, so it started an IMPLICIT sixth track — a fleets row resolved to
   `32 113.1 0 132.9 0 20` (six tracks, five gaps = 60 px) in the red build.
2. **The `auto` value track was not protected from the label.** An `auto` track starts at its
   MIN-content and shares the free space with the label's `minmax(0, auto)` track. The quay's trade
   row puts a buy+sell pair of two `w-28` (112 px) cells in the value; at min-content a `grid-cols-2`
   pair is 4 px. Measured on the desk City face (358-px row): tracks `0 133.5 176.5 0 0` — the label
   took its whole 133.5 px and the pair was squeezed to 176.5 px, so its cells drew at
   `173.5..285.5` and `263.8..375.8` (21.7 px over each other; the Sell cell 1.8 px past the pane's
   right edge). The disabled Sell cell therefore sat on top of the Buy cell: Playwright's
   "subtree intercepts pointer events", and the pane's `scrollWidth` 366 > `clientWidth` 358.

Under the old `1fr` label the value track won first (the label was a flexible track with a fixed
0 minimum), so neither could happen. The hug itself — the owner's 2026-11-01 instruction — never
needed either cost.

## Fix: the hug stays, the cost goes (one edit, the one Row, no prop changed)

- **A gap belongs to a cell, not to a track.** The shell has no column gap; the cell that has a
  neighbour on its left carries `ml-3` (the same 12 px): the value, the chevron, and the label and
  line 2 when a mark stands before them. An empty mark / value / chevron slot and the slack track
  cost nothing, so a row spends exactly the width the old template did.
- **The value track is `max-content`** (`auto minmax(0,auto) max-content minmax(0,1fr) auto`). The
  value reserves its whole width first; the label takes what is left and alone wraps, as under the
  `1fr` label. The slack still follows the value, so the figure still hugs the label (12 px) and the
  chevron still stands at the edge.
- The chevron is placed in explicit track 5 (`chevronCol`), not `gridColumn: -1`.

No floor was raised and no assertion loosened: the 12-px ceiling in `consistency.spec.ts:599` and the
"measured 11 px" it states are true again (the fixed build reads 289/278).

## Measured, red vs fixed (served builds, headless)

| | red (`08c4afac`) | fixed |
|---|---|---|
| desk City trade row @390: tracks | `0 133.5 176.5 0 0` | `0 118 240 0 0` (the pre-#440 label width) |
| the buy / sell cells | `173.5..285.5` / `263.8..375.8` (overlap 21.7) | `146..258` / `262..374` (4 px apart; ends at the row's edge 374) |
| HQ book @320: `"No gifts yet."` | label 72 px, 48 px tall | label 79.7 px, 24 px tall |
| HQ book @320: panel scroll | **313/278** | **289/278** (11), book 125 px |
| a fleets row @390 (mark · label · chevron) | `32 113.1 0 132.9 0 20` (6 tracks) | `32 125.1 0 168.9 32` (5 tracks); chevron 354..374 in both |

## What changed in `Row`, exactly (for whoever builds on it next)

- **Props: none.** `mark · label · value · chevron · tone · hairline · onClick · href · disabled ·
  className · under · children` and the `data-row-cell` names (`mark`, `label`, `value`, `chevron`)
  are as before.
- **Tracks:** `auto minmax(0, auto) max-content minmax(0, 1fr) auto` = mark · label · value · slack ·
  chevron; always five, columns 1–5. Label = 2, value = 3, chevron = 5 (`chevronCol`). Line 2
  (`children`) is `2 / -1`, or `2 / 3` for `under="label"`.
- **Gaps:** the shell has NO `gap-x`. `ml-3` sits on the value and the chevron, and on the label and
  on line 2 only when `mark` is set. A new slot gets its own track AND its own `ml-3` — never a
  column gap on the grid (that is the 48 px bug), and never a second `gap-x` beside the margins (it
  would double them).
- **Unchanged:** the hug (value 12 px after its label), the 52-px floor, `.bv-row-line`, the value's
  `text-left` + `whitespace-nowrap`, the `under` semantics.
- A cell that must never be squeezed (a pair of fixed-width controls) belongs in a `max-content`
  track; the label is the one cell that is allowed to wrap.
- The `city-repoint` WIP adds `size="compact"` on top of #440's template and its dense shell keeps
  `gap-x-3`: re-apply it on this version and DROP `gap-x-3` there. `stats-unfold` carries #440's own
  Row unchanged (its commit `c125c1f4` is #440's pre-squash form), so it has no fix to reuse.

## Gates (served builds of this branch, local mode, headless, `localhost`, explicit ports)

- `tsc -b`, `eslint src/components/ui/Row.tsx`, `npm run build`: clean.
- The three that were red, on the final `npm run build`: `consistency:379` (390×844) **0 violations**,
  `consistency:568` pass (inner scroll ≤ 12; the probe on the same code read 289/278), `market.desk:34`
  pass — 3 passed, 0 skipped (58 s).
- `align` 2/2 (**0 defects** at 1280 and at 390) and `city.density` 1/1.
- Every spec that measures a Row, 79 tests in 16 files (`primitives.geometry`, `layout`,
  `wide.layout`, `desk.layout`, `desk.city`, `desk.sweep`, `onepage`, `city.audit`, `city.page`, the
  whole of `consistency`, the whole of `market.desk`, `selection.lock`, `trade.ceiling`,
  `city.goodTrades`, `stats.moneyFeed`, `map.goodChartSlide`): 78 passed, 1 not a product result —
  `stats.moneyFeed` reads its world image from `dist/db` and the first run served a scratchpad build
  ("no world image under …\dist\db — run `npm run build` first", 174 ms). With the real
  `npm run build` in place it passes (1 passed, 11.8 s).
