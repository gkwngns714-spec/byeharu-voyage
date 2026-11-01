# 2026-11-01 — UNFOLD · STATS (branch `unfold-stats`, client-only)

> Owner, row 260: *"everything is folded in stats this is soo wrong. make it compact showing everything possible."*
> Owner, 2026-11-01: *"make things unfolded, minimize scrolling, everything compact with full info."*
> Laws: `2026-11-01-ui-unfold.md` (U1–U8). Brief: `2026-11-01-unfold-lists.md`. Both live on branch `city-mobile`.

## 1. Inventory — the OLD Stats, measured (headless, local world, 390×844 · 320×640 · 1280×800)

Screenshots: `…\scratchpad\unfold\shots\before-stats-<Face>-<W>x<H>.png` (EN) and `…-ko-…` (KO); data
`before-en-US.json`, `before-ko-KR.json`.

| size | main (px between bar and nav) | Overview sheet | Markets | Cities | Merchants | Me |
|---|---|---|---|---|---|---|
| 390×844 | **755** | 755/755 | 755/755 | 755/755 | 755/755 | 755/755 |
| 320×640 | **551** | **562/551 (scrolls)** | 551/551 | 551/551 | **637/551 (scrolls)** | **580/551 (scrolls)** |
| 1280×800 | **711** | 711/711 | 711/711 | 711/711 | 711/711 | 711/711 |

Defects seen: (1) **every face is 1–5 collapsed `SummaryRow`s with ~65 % of the glass empty under them** (Overview 5 rows,
Markets 3, Cities 2, Merchants 4, Me 1; 21 pages behind them); (2) the *Right now* band **overlaps at 390**: the 9-digit
world money (`131,367,515 🪙`, 118 px) sits in an 81-px grid cell and runs over `At sea`; (3) **three faces already scroll
at 320×640** (Overview +11, Merchants +86, Me +29 px); (4) KO titles **`돈의 흐름` twice** (`feed.heading` and `stats.newMoney`);
(5) the money log is 100–300 rows behind a press; the goods list (629), cities (246) and companies (821) likewise.

Every figure / test id of the old face, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `stats-live` · `stats-live-purse` · `stats-live-world` · `stats-live-trades` (+ At sea) | 4-cell grid (overlapping) | four label→figure pairs that wrap like words (`stats-live-sea` added); "Right now" is the green dot beside the header's *Updated* |
| `stats-money` (World money) + page: hero total, `StackedBar`, 4× `stats-holder` (trend + share bar), purse chart `stats-chart-tap` | summary row → page | **block on the face** *Who holds it*: ONE stacked bar, 4 holder cells with their trend beside the figure, the purse line on the heading's line. The hero total *is* the band's `World money` (one home, U4); its `+x today` is the Money flows figure; the per-holder share bars are the stacked bar |
| `money-log` (+ page `money-log-page`: 13 sector tiles, `money-move` rows) | summary row → page | **the Overview's list panel** (`money-log`), same rows and attributes; the 13 sector tiles are ONE select that carries the same counts; `Mine` is a chip |
| `stats-new-money` + page: printed / burned / moved / trades, net `SignedBars`, sold + bought charts | summary row → page | **block on the face** *Money flows*: the four figures, the net bars, and the sold / bought lines as mini charts (a press opens the large chart) |
| `stats-watch` + page: 7 figures, `stats-watch-gifts` | summary row → page | **block on the face** *Economy watch*: the same seven pairs. A figure the server did not serve is **left out, not dashed** (consistency law 5) |
| `stats-flows-filters`, `stats-flows-day`, `stats-flows-period` + RankBars pages | 4 tiles + 2 summary rows | the panel's *By kind* view: the side select + both periods' ranked bars |
| Markets: `stats-markets` 4 figures · `stats-markets-filters` page · `stats-movers` page (`stats-risers/-fallers/-most-traded`) · `stats-goods` page (629 `stats-good`) · `stats-show-all` | 4 figs + 3 summary rows | the 4 figures (window select on their block) + the three movers boards on the face; **the goods are the panel** with kind / rarity / sort selects. A price or move the server lacks is not drawn (no dash) |
| Cities: `stats-cities-filters` page · `stats-cities-list` page · `stats-city-open` rows · `stats-city-*` detail | 2 summary rows | **the panel** (246 rows) with area / country / sort selects and `My cities`; a row press opens THAT city's page (`stats-city-page`; Back returns) |
| Merchants: 4 figures · `stats-merchant-fold` (+`stats-merchant-states`, 2 charts) · `stats-merchants-top/-bottom` pages · `stats-merchants-all` (821, `stats-merchants-show-all`, `stats-merchants-filters`) | 4 figs + 4 summary rows | figures, fleet states and two mini charts on the face; **the panel has three views** — companies, best day, worst day (the RankBars the pages held) |
| Me: 4 figures · `stats-me-bars` · trades hint · `stats-best-trades` page (sort) | 1 summary row | the week's figures, bars and hint on the face; **the best sales are the panel** with their sort |

## 2. The change

* **`ListPanel`** (`src/components/ui/ListPanel.tsx`) — ONE inline list panel: a fixed header (title, count, a `trailing`
  sort, a `controls` line), a body that scrolls INSIDE it, the shared `Row` packed to the reach floor (44 px pressable, ~32 px
  read-only — chosen by selector, so a row that gains an `onClick` gains its floor), a cut edge that fades only while rows lie
  below, and an optional `above` slot: the face's figures stand over the panel on a phone and beside it from `lg`.
  Second callers: Compendium, Ledger, Rank, Routes (next four PRs) and the five Stats faces now. `DenseRows` is its packing, exported.
* **`Sheet fill`** (additive) — the body is a flex column that takes the glass the title leaves, with a 8-px-shorter title line.
* `FilterBar compact` (additive) — pickers and toggles on one line, a picker as wide as what it says (`field-sizing`), named for
  assistive tech and by `title`. `StatCell` gained `trendBeside` and `inline`, and `StatRun` is the line the inline pairs wrap on
  (five callers). `StatsChart` draws a mini (`Sparkline` in a 44-px press target); the press opens the SAME `Tray` over the
  SAME `SpanPicker` and `SeriesChart`, drawn large. Reads are untouched (`statsLive.ts`: every second; the money feed likewise).
* KO: `feed.heading` is `돈 기록` (it was `돈의 흐름`, the same as Money flows).

## 3. Budget — 390×844 (main 755), written before the code; measured values in §5

Chrome (every face): sheet title line 38 · face tabs 52 + gap 4 · *Right now* band 48 (two lines of pairs) + gap 4 · bottom pad 8 →
**face body ≈ 600**.

| face | block | target px (worst-case wrap) | where each old element goes |
|---|---|---|---|
| **Overview** | Who holds it: heading+purse line 44 · bar 8 · holders 2×40 | 140–168 | `stats-money`, 4× `stats-holder`, purse chart |
| | Money flows: heading 22 · pairs 2×24 · net/sold/bought row 48 | 126–150 | `stats-new-money` |
| | Economy watch: heading 20 · seven pairs in 2–3 lines | 72–96 | `stats-watch`, `stats-watch-gifts` |
| | **figures sum** | **≤ 406** | |
| | **panel (Money log · By kind)**, floor 12 rem | **≥ 192** (header 64 + ≥ 2 rows) | `money-log`, flows by kind |
| **Markets** | Market today: heading 44 (window select) · 2 lines of pairs · Movers: 3 boards × 3 entries | 158–222 | `stats-markets`, `stats-movers` |
| | **panel (629 goods)** | **rest** (header ≈ 100) | `stats-goods`, filters in its header |
| **Cities** | **panel (246 cities)** | **all** (header ≈ 100) | list + filters |
| **Merchants** | 4 figures 2×40 · fleets: bar + legend + 2 mini charts | 246 | figures, `stats-merchant-fold` |
| | **panel (companies · best day · worst day)** | **rest** | `stats-merchants-all/-top/-bottom` |
| **Me** | week: heading · pairs · bars 48 · hint | 146 | `stats-me`, bars |
| | **panel (best sales)** | **rest** | `stats-best-trades` |

The rule that makes it hold on a short glass: the face is a grid `minmax(0,auto) / minmax(12rem,1fr)` — the figure block is
content-sized and only when the glass is too short for figures + a 12-rem panel does the figure block scroll INSIDE itself;
the panel keeps its floor and the page never scrolls. At `lg` the same two blocks stand side by side (5fr figures | 7fr list),
the panel taking the whole height.

## 4. Proof (`tests/stats.unfold.spec.ts` — 390×844 · 320×640 · 1280×800, every face)

Page and Sheet scroll = 0 · the figure block is whole on a tall phone and on a desktop · the panel stands in the glass with ≥ N
rows WHOLE before any press (N: Overview 2 · Markets 4 · Cities 6 · Merchants 3 at 390; 1 · 1 · 2 · 1 at 320; 8 · 6 · 6 · 6 at 1280)
· every old test id above is present · no two text boxes cross (clipped by the panes that hold them) · cut text carries its
full text · a city row opens its page and Back returns · a chart press opens the large chart and moves nothing, ALSO where the
figure block scrolls (320×640) · the views of the Merchants panel are not pages · the band's "Updated" moves by itself.
Specs that encoded the folded structure were rewritten, with the reason in the commit: `stats.tab`, `stats.bigChart`,
`stats.moneyFeed`, `stats.filters`, and `onepage` / `consistency` where they walked Stats summary rows.

## 5. Measured (served build, headless, local canary world; `[above]` = the figure block)

| face @390×844 | figure block | list rows whole | | face @320×640 | figure block | rows whole | | face @1280×800 | rows whole |
|---|---|---|---|---|---|---|---|---|---|---|
| Overview | 348 / 348 | **3** of 100 | | Overview | 494 / 173 (scrolls inside) | 1 | | Overview | **10** |
| Markets | 158 / 158 | **6** of 60 | | Markets | 194 / 173 (scrolls inside) | 1 | | Markets | **8** |
| Cities | — | **8** of 246 | | Cities | — | **3** | | Cities | **7** |
| Merchants | 246 / 246 | **4** of 60 | | Merchants | 334 / 173 (scrolls inside) | 1 | | Merchants | **8** |
| Me | 146 / 146 | — (no sales yet) | | Me | 146 / 146 | — | | Me | — |

Document and Sheet: **0 px** of scroll in all fifteen cells (before: three faces scrolled at 320×640). The live-sized world
(nine/ten-digit holders, a day of rollup history; `scratchpad\unfold\seed-rich.mjs`, local only) at 390×844: figures 385 of 385
with the panel at its 12-rem floor on the Overview (one holder's sparkline drops under its figure there) — the budget's worst case.

## 6. Found on the way

* **A `mask-image` fade on a scroller clips a `position: fixed` descendant** — the large-chart tray opened from a chart inside
  the figure block was drawn at the right of the glass and could not be pressed (`stats.bigChart` at 1280×707 hung on
  "intercepts pointer events"). The fade is now a sibling overlay (`ListPanel`, `CutEdge`) and `stats.unfold` presses the tray
  at 320×640, where the block scrolls.
* The consistency spec's `pagesOpened` floor counted Stats' 15 summary rows per glass; it is rewritten (below), not loosened.
* Judgment calls, stated: the Sheet's wide column (reserved tray width) is unchanged — the face stands in it as two blocks;
  the live band keeps `Money` (your purse, also in the top bar) because `stats-live-purse` is pinned and the owner asked for it.
