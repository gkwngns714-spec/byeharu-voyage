# 2026-11-02 — THE HQ ON A PHONE (branch `city-phone`, client-only): every face legible at 390 and 320, and the law that keeps it so

> Owner, row 247: *"you know that this game is also for mobile right?"* · row 251: *"make it concise and simple so that it is easy
> to see in one eye without scrolling down"* · row 255: *"the same screen dividends (city view, then right side the info) should
> stay the same for all"* · rows 258/260: *"compact EVERYWHERE; label and figure close … with full detail"*.
> The plan was `docs/dev-log/2026-11-01-city-phone.md` (branch `city-mobile`), written BEFORE #441 (the Row tracks) and BEFORE the unfold
> (#447–#452). Its section 2 was **re-measured on `98a75c04`** below; what it called a defect and is not, is said.

## 1. Inventory — what is wrong on `origin/main` 98a75c04, measured (headless, local build, English and Korean, DPR 1)

The split keeps the right panel at **half the glass**: (vw − 48) / 2 — **171 px at 390 (139 px of room inside its padding), 136 at 320 (104)**,
616 at 1280 (584). The chart card on its left is 163 / 128 / 608. Everything below is a face written for the wide column standing in that room.
The law (§4) was run on `main` first; its counts are the BEFORE.

| face | at 390×844 | at 320×640 |
|---|---|---|
| **Market** (panel) | each good's name **0 px wide** — a column of letters 9.7–16 px wide ("Iron" 4 lines, "Woollen Cloth" 12 lines high); the two price tiles are 228 px in a 139-px row — **101 px past their row, 85 px past the panel's edge, the SELL tile cut off**; the BUY tile stands on the name | the same; the Buy · Sell · Requests tabs **overlap by 440 px²** ("Sell" under "Requests") |
| Market (chart card, left) | the five span buttons are 44 px wide in 29-px columns — **520 px² of each pair overlapped**; Korean axis labels "−0.5시간" × "−0.3시간" **335 px²**; "In stock" a column of letters | **828 px²** between span buttons; "−0.5h" × "−0.3h" 220 px², "−0.3h" × "now" 77 px²; the rows below are clipped out of reach |
| **Storage** | "Space" a column of letters beside "0 / 750 tons" (5 lines × 9.0 px) | the label **0 px wide** ("공간" / "Space" under the figure) |
| **Inn** | "Captains here" 107 px of text in a **59-px** cell, cut with "…" and only a `title` (no hover on a phone) | "Crew" 40 px in **6**, "Captains here" in 24 |
| Forge · Port | fine | "Tier 1" 41 in 17 px, "Repair" 50 in 20 — cut |
| Hall (default face) | "Population" cut to "Popul…" | "Po…" and "Relatio…" |
| Requests (Market face) | "New request" 98 px in 87 | 98 in 52 |
| **Request page** (a page the Requests face opens) | the chart step: a **256-px box** (`h-64`) round a card of 262–420 px — at 1280 the price and quantity fields stand **over the span picker (1,213 px² of control over control)**; at 390 the picker straddles the box's edge; Range and In stock are cut out of reach | the same; the page's body holds 584 |

Elsewhere (the brief's list; reproduced in the browser first):

* **(a) the Market face — REAL**, all four named defects (names one letter wide; tiles over each other and the name; the stock label split — here
  "In stock" — and the chart's axis labels crossing). The Korean build showed the tiles standing ON the name; English cuts the SELL tile instead — one cause.
* **(b) the desk City face at 390 — REAL, and worse than "190 px"**: the board pane is `max-h-[12rem]` (192 px) inside a Sheet that ends 187 px BELOW it
  (pane 408…600, Sheet 32…787), and the pane's own controls (Supplies, Buy · Sell · Requests, the filter: 150 px) take 150 of its 192 — **40 px of goods
  stand on the glass at 390 and none at 320×640**.
* **(c) the request rows' `deliver` cell — REAL**: the dead cell's reason ("0 / 20 units on board") inherits the Row value's `whitespace-nowrap`, stands on ONE
  line, **12.5–15.7 px past its 112-px box and its row** at 390 and 320, and the pane scrolls sideways (374 in 358; 304 in 288). Not 10–16 px of the cell — of
  the reason inside it.
* **(d) Warehouse "space" and the Inn rows — REAL** (table above). "이곳…" is "inn.captainsHere" (이곳의 선장) cut to two syllables.
* **(e) Profile — REAL, but not an overlap you can see.** At 320×568 the sign-out row's rectangle lies **22 px over the rail's Stats and Menu cells** (the Sheet
  clips it, so it is cut, not drawn over); at 320×640 the Sheet scrolls **21 px** inside itself (572 in 551) and at 360×640 7 px — its sign-out card sits flush on the
  rail with nowhere to go. The unfold laws name 320×640: no scroll. (PR 3.)
* NOT real, from the plan: the Hall/Port/Forge faces "fine at 390" — Hall's label cut and Port/Forge/Inn at 320 are in the table. The plan's "stock label
  overlapped by the figure" is "In stock" in the chart card, not a row's.

**Found on the way, not in the brief:** the Market's trade pane (the tray a good opens in the panel) is the same squeeze (one letter "Max", "Carg-o space", the Buy
button cut) — its ROWS are fixed by the same primitive; its button strip is not (UNVERIFIED, §7). The desk's own Trade rows at 320 (a 288-px pane: name 48 px)
break the same way — PR 2 stands the pane in a container so they wrap.

## 2. Cause, and the one place each is fixed (NO SPAGHETTI: shared primitives, no per-face patch)

One cause: **a figure's width was never allowed to move the figure.** `Row`'s value track is `max-content` (#441: right, it stops the buy+sell pair being
squeezed), so a value wider than the row took everything and the label's track (`minmax(0, auto)`) went to 0. `SummaryRow`'s title was `truncate`.

| primitive (file) | change |
|---|---|
| `src/index.css` | three `@custom-variant`s that ask a **query container** how wide it is, not the screen: `narrow:` < 15 rem, `pair:` < 22 rem, `tight:` < 8.25 rem; `short:` a glass < 600 px tall |
| `Row.tsx` | below its container's threshold the grid becomes a **wrapping flow**: label never below its words (up to 7 rem, then it wraps), value whole and **under the label** when the two do not fit one line, chevron laid over the right edge, line 2 a full line. `pair` prop: a row whose value is two act cells waits for 22 rem |
| `Detail.tsx` `SummaryRow` | the same flow: title wraps instead of "…", figure under it, chevron at the edge, `px-0` (the panel already insets it 16) |
| `ActCell.tsx` | the reason wraps (`whitespace-normal`) and the cell yields (`max-w-full`); new `ActPair` (two callers: Trade, Storage) — 14.25 rem, 2 columns, 1 column `tight:` with label and figure on one line |
| `StockGauge.tsx` · `Figure.tsx` | the figure drops under the bar / the unit under the number rather than run past the room |
| `TileGrid.tsx` · `tileStyles.ts` | `narrow:` choices are a wrapping line, never under the 44-px floor (Buy · Sell / Requests; the span picker in two rows) |
| `priceChartModel.ts` | `declutterTicks`: x labels that would stand on each other drop — the middle, then the first; `now` never |
| `CityPanel.tsx` · `MarketLeft.tsx` | the two surfaces ARE query containers (`@container`); the chart card scrolls whole when the glass is too short |
| `RequestPage.tsx` | the chart's 256-px box (`h-64`) is gone: the card stands at its own height and the page's body is the one scroller |
| `SpanPicker.tsx` | **no edit**: it is a `Segmented`, so the `TileGrid` change above is its fix (its five tabs overlapped by 520 / 828 px²; they are now a wrapping line, two rows at 390, three at 320) |
| `Detail.tsx` `DetailPage` · `Tray.tsx` | pages and trays standing over the HQ are containers of their own, so the rows in them ask the page, not the panel underneath |
| `CityHallPanel.tsx` `FigureLine` | label never cut; figure under it (`narrow:`); the one stated exception: a glass < 600 px (`short:`), where `consistency.spec.ts` holds the 320×568 panel to 12 px of inner scroll |

`container-type` does NOT trap `position: fixed` descendants in the engines this is served to (probed: a fixed child of a `container-type: inline-size` box
stands at the viewport), so a page opened from the panel is still a page. Nothing outside a query container ever matches `narrow:`/`pair:`/`tight:` — the wide
glass, the desk, and every other screen are the grid they were.

## 3. Budget (written before the code) — room, and what each thing needs

| room | 390 | 320 | what stands there |
|---|---|---|---|
| right panel, inner | 139 | 104 | rows, summary rows, the pair |
| chart card, inner | 163 | 128 | chart, legend, span picker, two rows |
| a Market row needs | name ≥ 112 + 12 + pair 228 = **352** to stand beside; else name / pair / gauge | | 
| the pair | 2 columns of 67 (a 4-digit price is 42 + 12 padding) | **1 column** (50-px columns are under what a price needs): 104 wide, label + figure on one line, 44 px | |
| Buy · Sell · Requests | Buy│Sell over Requests: 2 lines, 102 px | the same | |
| span picker | 1 day│1 week│1 month / 1 year│All: 2 lines, 96 | 1 day│1 week / 1 month│1 year / All: 3 lines, 140 | |
| panel height 647 / 395 | caption 24 + Basket 44 + faces 102 + group 28 = 198 → 449 px of goods ≈ **3.7 goods** (≈ 120 each) | 197 px ≈ **1.3 goods** (≈ 150 each) | a long list scrolls INSIDE the panel |
| chart card height 647 / 395 | 24 + chart 200 + picker 96 + two rows ~150 = 470 — **all stands** | 24 + 215 + 140 + 150 = 530 — **scrolls 135 px inside the card**; nothing is out of reach | |

The panel's pitch: every pressable row ≥ 44 px (a stacked summary row is 2 lines, 56–70); the cell pair's cells are ≥ 44 × 44.

## 4. The law (`tests/city.phone.spec.ts`; the measuring is `tests/unfold.fixture.ts`'s `readGlass`, extended with `scope` and the phone laws)

At 320×640, 390×844 and 1280×800 (and 390 / 320 in Korean), press each of the six tiles; inside the right panel — and, on the Market, the chart on the glass's left and
its three faces — **(a)** no two sibling boxes (and no two chart labels) overlap by more than 2 px²; **(b)** no text of 3+ characters stands in a column narrower than
1.4 × its font size *(read off the text's own line boxes: a label squeezed to 0 px has no box to read; and only text that WRAPPED can be such a column — "All" is 14.6 px
at 12 px type and stands on one line)*; **(c)** nothing is cut without its full text — an ellipsis carries a `title` (a `Clip`), a row's LABEL is never cut at all (4 px
of a trailing mark's side is not cut text), nothing is clipped by the panel's edge; **(d)** nothing scrolls sideways, the page or a box. Plus two text boxes crossing, and (a) also reads **control over control whoever the parents are** (a span picker over the field below it is two cousins, not two siblings — that is how the request page's overlap was found and
why the first cut of the law missed it).
The three previously-red specs (`consistency.spec.ts` 379 / 568, `market.desk.spec.ts` 34) pass on the same build — they were fixed by #441; this slice keeps them so.
`priceChart.spec.ts` pins the axis rule, and `layout.spec.ts`'s request test now asserts nothing in a request row stands right of the row.

## 5. Measured (served builds of `98a75c04` and of this branch; same world, same machine; headless Chromium, DPR 1)

The law's own numbers — worst case over the six faces, the Market's chart and its three faces — before → after:

| | 390×844 EN | 320×640 EN | 390 KO | 320 KO | 1280×800 |
|---|---|---|---|---|---|
| (a) greatest overlap of two sibling boxes | 520 px² → **0** | 828 px² → **0** | 520 → **0** | 828 → **0** | 0 → 0 |
| (b) texts standing one letter wide · the narrowest | 12 · 9.0 px → **0** | 12 · 8.4 px → **0** | 4 · 16.0 px → **0** | 4 · 16.0 px → **0** | 0 → 0 |
| (c) texts or labels cut with no way to read them | 12 → **0** | 21 → **0** | 12 → **0** | 21 → **0** | 0 → 0 |
| (d) the panel's content clipped past its edge · the page's sideways scroll | 85 px → **0** · 0 | 120 px → **0** · 0 | 85 → **0** · 0 | 120 → **0** · 0 | 0 · 0 |

**1280×800 is the same picture to the pixel box**: every row, cell, button and test-id box of the Market (86 elements), Storage, Forge, Port and Inn is identical before and after, and the Hall's
`city-*` boxes are identical — the wide glass is the grid it was.

What the phone shows now (served build, the canary world; the Market list is long and scrolls INSIDE the panel):

* **Market panel**, whole goods before any press — 390×844: **2** in English (rows 140 px: a name of two lines, the pair 78 px because "none on board" wraps to three lines in a 56-px cell, the gauge), **3** in Korean
  (124 px rows); 320×640: **1** in English (166 px) — against **0** legible before (the budget in §3 said 120 px a good and 3.7 goods; the dead reason's three lines are the 20 px it missed). Every cell is at least
  68×78 px at 390 and 104×44 at 320 — over the 44-px floor either way. 1280×800: 4 whole, 79 px rows, as before.
* **Chart card**: at 390 everything stands at once (chart, legend, the span picker in two rows, Range, In stock) and nothing scrolls; at 320×640 it is 566 px of a 395-px card in English (540 in Korean) and **scrolls 171 px inside the card (145)**,
  every row within reach (the budget said 135).
* **Inn · Forge · Port** at 320: "Crew" over "8 / 20" and "Captains here" over "8" (whole words; a chevron at the edge), "Tier 1 · 180" on one line, "Build" on one line and "Repair" over "0%" — every row at least 44 px, none cut.
* **Storage**: "Space" over "0 / 750 tons" at both; its pair of act cells (a stored good's Put and Take) is the same `ActPair`.
* **Hall**: "Population" over "≈ 160,000" at 390; "Population" and "Relationship" over their figures at 320×640. On a glass under 600 px tall it stays the one-line version (§2, `short:`): 320×568 with the book open is
  289 in 278, exactly as on `main`.

Gates (lean; headless; `localhost`; ports 4781 baseline · 4783 this build; Node's locale forced to English for the plain-Node word specs, because this machine's is Korean): `tsc -b`, `eslint` on every touched file,
`npm run build`. One run on the rebased branch (`95211ac0`): **141 passed in 13.0 min, 0 failed, 0 skipped** — `city.phone` (5), `city.density`, `city.page`, `city.audit`, `consistency` (379 at both glasses, 568, the HQ ones),
`market.desk` (34), `align`, `onepage`, `layout`, `wide.layout`, `desk.layout`, `desk.sweep`, `desk.inplace`, `desk.city`, `primitives.geometry`, `good.class`, `selection.lock`, `trade.ceiling`, `trade.loop`,
`city.goodTrades`, `command.buySell`, `command.sellCargo`, `priceChart` (+1), `words`, `i18n.keys`, `i18n.ko`, `duplication`. After the last commit (the request page, the control-over-control law, the opt-in scope of the phone laws):
`city.phone` 5/5 and `market.desk` 3/3 on the new build, and the five unfold specs (`stats`, `codex`, `ledger`, `rank`, `routes`: 29 tests) pass against the extended fixture. CI is the full proof (the selection runs every browser spec).

## 6. What the three previously-red specs say

`consistency.spec.ts` 379 (390×844 and 1280×800) and 568 (the HQ at 320) and `market.desk.spec.ts` 34 pass on this build — for the reason they went red and were fixed (#441: `Row`'s gap belongs to a cell, the value track is
`max-content`), which this slice keeps true: nothing here loosens a number in them. The 568 one is why `short:` exists (§2): stacking the hall's two long figures at 320×568 with the Influence book open would take its
inner scroll from 11 px to 43, and that spec holds it to 12.

## 7. Not done, and unverified

* **Left over from the coordinator's sweep (row 14), for a next slice — each is a decision about what a row IS, not a layout:** the Inn's "Crew" and "Captains here" rows open the SAME page; "Repair 0%" opens a page with
  no line; a Forge tier opens a 796-px page. U1 says a row whose page holds one line should be the line. Fixing them changes what the HQ's Inn / Port faces contain and the specs that count their rows (`city.density`: "the inn lost a row"),
  so they were not done here.
* **The HQ with no city in hand** (sweep row 8) is PR 4 (`city-phone-nocity`).
* **The trade pane** — the tray a good opens inside the Market panel (Max, Cargo space, the Add and Buy buttons): its rows now wrap by the same primitive, but its button strip (two buttons side by side in 139 px: "Buy 80 units 4,700")
  and the stepper were not rebuilt, and the law does not press into it. UNVERIFIED at 390/320.
* **The Hall on a glass under 600 px tall** keeps "Popul…" (titled): the one stated exception, §2.
* **A rotated phone, and DPR 2 / 3**: layout is in CSS px and nothing here reads DPR; I did not look at it at 2 or 3.
* **Real Korean fonts on a device**: measured with the machine's own; a narrower or wider Hangul face moves the wraps, not the laws.
* The desk (PR 2) and the Profile (PR 3) are their own slices, `docs/dev-log/2026-11-02-city-phone-desk.md` and the Profile section of its PR.

## 8. Found after the merge (PR 5, `city-phone-openreq`)

The first cut of the law walked the Requests face with NO request open (the canary world has none until one is placed). Placing one — the house's own request is a line on that face: what it is, the sum held, and a
**Cancel** — showed what the walk could not: `MarketFace`'s line was one non-wrapping row of the word, the sum and an 85-px button, **190 px in a panel with 139 px of room at 390 and 104 at 320**. Measured on `main`
after #456–#459: the Cancel stood at x 332…417 against the panel's edge at 374 — **43 px past it at 390, 78 px at 320** (297…382 against 304: seven pixels of an unpressable button, clipped by the panel; English and Korean).
The line is now `flex-wrap`: the word and the sum, and the Cancel under them at the right edge when the three do not fit (−16 px = inside, at 390, 320 and 1280). The law presses Requests › New request › the first good › Place
and reads the face with the request open (`market requests · one open`): red on `main` at 390 and 320 in both languages (the panel body clipped), green here. `market.desk.spec.ts`'s place-list-cancel test still passes.
