# 2026-11-02 — FLEETS and YOU stand on the glass (branch `sheets-grow`, client-only)

> Owner, 2026-11-01: *"don't ask me for permission, but check everything, fix all, redo the design, make things unfolded,
> minimize scrolling, everything compact with full info."* Laws: `2026-11-01-ui-unfold.md` (U1–U8) on branch `city-mobile`.
> Origin: the layout sweep of 2026-11-02, row 5 (*Fleets and You with a veteran's 8 hulls*) and row 17 (*empty glass*).
> The pattern is the five unfolded screens (Stats #447, Codex #448, Ledger #449, Rank #451, Routes #452): figures + ONE
> `ListPanel` that stands in the glass and scrolls INSIDE itself. **The budget below was written before any code.**

## 1. Inventory — the OLD screens, measured (origin/main 9a97051e, headless Chromium, English)

Worlds are throwaway images built from this build's own image (`tests/manyFleets.fixture.ts`, `tests/twoFleets.fixture.ts`):
**two** = the canary's founding hull + `Segunda` (2 hulls, no captain); **veteran** = `fleet_max` raised to 8, eight hulls, six
captains (one ashore, one whose bonus nothing reads yet, a 47-character name; one fleet has the longest name the chain allows,
24 characters). Scratch driver and data: `…\scratchpad\grow\measure.spec.ts`, `before-en-two.json`, `before-en-many.json`;
screenshots `…\scratchpad\grow\shots-before\`.

| screen | world | glass | page scroll | glass left empty under the content |
|---|---|---|---|---|
| FLEETS | 2 hulls | 390×844 | 0 | **508 px** of 755 (67 %) |
| FLEETS | 2 hulls | 320×640 | 0 | **304 px** of 551 |
| FLEETS | 2 hulls | 1280×800 | 0 | **544 px** of 711 (77 %) |
| FLEETS | 8 hulls | 390×844 | **122 px** (Sheet 877 in 755) | 0 |
| FLEETS | 8 hulls | 320×640 | **326 px** | 0 |
| FLEETS | 8 hulls | 1280×800 | 0 | 178 px |
| YOU | 2 hulls | 390×844 | 0 | **256 px** |
| YOU | 2 hulls | 320×640 | 0 | 52 px |
| YOU | 2 hulls | 1280×800 | 0 | 212 px |
| YOU | 8 hulls + 6 captains | 390×844 | **476 px** (the sweep, 8 hulls and no captain: 140) | 0 |
| YOU | 8 hulls + 6 captains | 320×640 | **1,050 px** (sweep: 344) | 0 |
| YOU | 8 hulls + 6 captains | 1280×800 | **378 px** (sweep: 184) | 0 |

Cause (both screens): `Sheet` without `fill` and no `ListPanel` — the list is as long as the number of hulls, and the Sheet is the
page's scroller. Row heights as they stand: a fleet row **101 px** at 390 and 320 (four lines: name + where · supplies · cargo ·
hull), **61 px** at 1280; a ship row 59 px; a captain a **112–126-px tile** in a two-column field (names cut with `Clip`).

Every figure / test id the old screens carry, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `fleets` (the Sheet) · `fleet-row` ×N · `fleet-row-bars` · `fleet-page` (+ `fleet-fold`, its sections) | rows straight on the Sheet; the page is a fixed `DetailPage` | the SAME rows in ONE `ListPanel` (`fleets-list`); the page is unchanged (a sibling overlay, never inside the scroller) |
| `fleets.noFleets` row | row on the Sheet | the same row in the panel |
| the fleet count (never printed; the old header counts were removed on purpose, "limits are not assets") | — | the panel's TITLE (`fleets.count`): `8 fleets` — the rows it holds, the way Rank counts its captains |
| `you` · `levels` · `level-track` ×2 · `combat-waits` · `you-no-company` | three `Row`s on a surface (Trading, Exploration, Combat) under a 32-px heading | one compact strip over the panel: heading `Levels` and the combat line on one line; the two tracks side by side, each `label figure` hugging, the 20-rung bar under it |
| `you-ships` · `you-ships-count` · `you-ship` ×N · `you-no-ships` | section on the Sheet | the first section of the panel's body (heading `Ships`, the count at its right, the rows) |
| `your-captains` · `your-captain` ×N · `your-captains-none` · `your-captain-tray` (+ the tray's own ids) | a field of `OfficerTile`s, the tray inside the section | the second section of the panel's body, a `Row` per captain (the Codex's captain row: crew mark · name · `+12 %` · chevron, and one caption line: grade · job · ship · cabin or *Ashore*); the tray is a SIBLING of the panel |

## 2. The change

* **FLEETS** — `Sheet fill` · ONE `ListPanel` (`fleets-list`): title = how many fleets, the rows are the fleet rows. The three
  facts of a row stand on **three lines on a phone, not four** (name + where · supplies and hull · cargo): supplies and hull share a
  line when they fit (390: they do; 320: they wrap as before). From `sm` all three still stand on one line, as they did. Nothing is
  dropped, only reordered visually: supplies → hull → cargo. Reads unchanged. **The name and where she is stand on one line while
  they fit and WRAP when they do not** (found on the way, §6): a fleet at sea says `to Cape St Vincent · 22s`, and beside it her name
  was 16 px wide at 320×640 — the where line drops under the name now, and the name is whole.
* **YOU** — `Sheet fill` · the levels strip (the figures) over ONE `ListPanel` (`you-list`) whose body holds two sections, **Ships**
  and **Captains** (`SheetSection` headings, so the heading is the shared one; from `lg` the two stand side by side in `SectionColumns`,
  the same blocks with more room). The captains face is split in two parts the screen composes (`src/live/YourCaptains.tsx`: its
  rows and its tray, one hook for the read and the open captain — `src/live/useYourCaptains.ts`): the rows stand in the panel's body, the
  tray is a sibling outside it. `OfficerTile` is untouched (the Codex and a merchant's sheet still draw it).
* No shared primitive is edited (Sheet, ListPanel, Row, Detail, Tray, screenLayout stay exactly as they are).

## 3. Budget — written BEFORE the code (main 755 · 551 · 711 are measured; the rest are CSS sums of the primitives)

Chrome on both screens: Sheet title row 38 (`fill`) · bottom pad 8 → the region under the title is **709 · 505 · 665** px.

**FLEETS** — the panel takes the whole region. Header (the count) = `pt-2 8 + h2 22 + pb-1 4` = **34** → body **675 · 471 · 631**.

| glass | row | rows whole before any press (8 hulls) | 2 hulls |
|---|---|---|---|
| 390×844 | 81 px = 16 + 24 + (4 + 16 + 4 + 16) + 1 (3 lines) | **8 of 8** (648 ≤ 675), the page 0 | 196 of 709 used |
| 320×640 | 101 px (4 lines; supplies and hull cannot share a 224-px line) | **4 of 8** (404 ≤ 471), the rest scrolls INSIDE the panel | 236 of 505 used |
| 1280×800 | 61 px (one facts line) | **8 of 8** (488 ≤ 631) | 156 of 665 used |

**YOU** — the strip stands on the glass like a Stats face's figure block (`StatsBlock.tsx`: no box, one heading line and the figures
under it): `heading 20 + gap 4 + (figure line 22 + bar 4 + 4)` = **54**, +8 under it → the panel gets **647 · 443 · 603** px.
(The first draft of this budget boxed the strip on a surface — 72 + 8; it was unboxed before the first measure, because a surface
standing over a surface is what the sheet's own law forbids and the Stats faces do not do it.)
Body: Ships = `mt-2 8 + head 32 + mb-2 8` = 48, then rows of **49** (a read-only packed row: py 4 + 24 + a 16-px caption + 1);
Captains = `gap 16 + head 40` = 56, then rows of **61** (a pressable row: py 8 + 24 + 4 + 16 + 1).

| glass | what stands whole before any press (8 hulls + 6 captains) | scroll |
|---|---|---|
| 390×844 | Ships: **8** (48 + 392 = 440 ≤ 647) + Captains: **2** (122 of the 151 left) = 10 of 14 rows | inside the panel (862 in 647) |
| 320×640 | Ships: **7 – 8** (391 ≤ 443; the eighth ends at 440 against a body of 439), no captain | inside the panel |
| 1280×800 | Ships **8** and Captains **6**, side by side (left 440, right 414, both ≤ 603): 14 of 14 | none needed |

2 hulls and no captain (the canary): 234 of the 647 px used at 390 (the empty state stands in the panel).

The proof floor in the spec is `min(rows, N)` with N held below the budget by a small margin (it must hold on CI's fonts too).

## 4. Proof — `tests/fleets.you.grow.spec.ts` (390×844 · 320×640 · 1280×800, EN; 320×640 also in KO; two worlds; 19 tests)

For FLEETS and YOU in the 2-hull world and the 8-hull veteran's: the document and the Sheet scroll **0 px** and nothing scrolls
sideways · the list panel stands inside the glass and reaches the foot of it (≤ 12 px of glass under it) · at least `min(rows, N)`
rows are whole before any press · the phone laws of `tests/unfold.fixture.ts` (no two boxes or texts cross, no text one letter wide,
no row label cut, cut text carries its full text) · every old test id is present, with as many as the world has hulls and captains ·
rows ≥ 44 px (every data row; every control in the panel) · with 8 hulls, where the panel's content is longer than the panel the
PANEL scrolls (its last row comes into view; the page stays at 0) · a press on a fleet row still opens `fleet-page` and nothing
behind it moves; a press on a captain opens `your-captain-tray`, outside the panel's scroller · the longest fleet name the chain
allows stands whole at 320 with the where line under it, and a fleet AT SEA (sent through the map's own flow) keeps her name whole ·
on a touch glass a press on a cut captain's name reads it whole and opens no tray.


**The spec has teeth** — run against three deliberately broken builds, each read to its last line, none re-run to green:
* `fill` removed from both screens: 5 of the 6 veteran cases at 390 and 320 failed (`the Sheet scrolls 1014/755`, `915/551`,
  `1030/551`, `the panel is not inside the glass`). The sixth, FLEETS at 390×844, passed: the compacted rows alone (8 × 81 = 648 + chrome
  62) fit the 755-px glass even without the panel — which is why the 320 glass carries the proof of the inner scroll, and why the
  foot-of-the-glass line exists.
* `fill` removed from FLEETS only, with that line in: both 390×844 cases failed with `510 px of glass stand under the panel — the panel
  does not fill the glass` (the sweep's 508 px under two fleets, found again).
* the old squeezed label (`shrink-0` where line, no wrap) restored: both name tests failed (`the 24-character name is cut at 320`,
  `her name is cut beside where she is bound`).

## 5. Measured (served build, headless Chromium, EN; origin/main 38c3bccb + this slice; two worlds from this build's own image)

Scratch driver and data: `…\scratchpad\grow\measure.spec.ts` (+ `measure-sail.spec.ts`), `before-en-*.json`, `after-en-*.json`; shots in
`…\scratchpad\grow\shots-before\` and `shots-after\` (`<screen>-<W>x<H>-<two|many>.png`, `-ko`, `-dpr2`, `sail-…`).

**Page scroll** (document and Sheet; px beyond the glass), before → after:

| screen · world | 390×844 | 320×640 | 1280×800 |
|---|---|---|---|
| FLEETS, 8 hulls | 122 → **0** | 326 → **0** | 0 → **0** |
| YOU, 8 hulls + 6 captains | 476 → **0** | 1,050 → **0** | 378 → **0** |
| (the sweep's YOU, 8 hulls, no captain) | 140 | 344 | 184 |
| FLEETS and YOU, 2 hulls | 0 → **0** | 0 → **0** | 0 → **0** |

**Glass left empty under the content** (2 hulls; the after figure is the Sheet's own 8-px bottom padding — the panel reaches the foot of the glass):
FLEETS 508 → **8** · 304 → **8** · 544 → **8**; YOU 256 → **8** · 52 → **8** · 212 → **8**.
**What is still empty INSIDE the panel with 2 hulls** (the honest half of that number): FLEETS 510 px (72 %) · 266 (53 %) · 506 (76 %);
YOU 412 (64 %) · 208 (47 %) · 448 (75 %). See §6.

**Rows whole before any press** (8 hulls; budget in §3 → measured): FLEETS 8 · 4 · 8 of 8 (budget 8 · 4 · 8). YOU ships 8 · 7 · 8 of 8 and
captains 2 · 0 · 6 of 6 (budget 8+2 · 7–8+0 · 8+6). Where the rows are longer than the panel the panel scrolls and the page does not:
FLEETS 833 in 471 px at 320 (none at 390 and 1280: they fit); YOU 880 in 645 at 390 and 896 in 441 at 320 (none at 1280).
With 2 hulls every row stands whole at every glass.

Row heights, measured: a fleet row **81** (390: three lines; it was 101) · 101 (320) · 123 (320, the 24-character name, its where line wrapped
under it) · **61** (1280); a ship row 51; a captain row 61 (77 at 320 where her line wraps). The panel stands 709 · 505 · 665 px (FLEETS) and
645 · 441 · 601 (YOU: the strip is 56 px, not the 54 planned), as budgeted ±2.

Also measured, none different: **Korean** at 390 / 320 / 1280 (FLEETS 5 of 8 whole at 320 — `보급 15.0일` is short enough for supplies and hull
to share a line even there — YOU 7 of 8; page 0 everywhere); **DPR 2** (the owner's laptop): identical figures, page 0; **a fleet AT SEA**
(the flagship sent to Cape St Vincent through the map's own flow, both worlds, three glasses): page 0, no overlap, no cut text, her name
whole, `to Cape St Vincent · 22s` under it where the two do not fit one line. Every box the panel does not hold is where it was: the
column still ends at x = 804 at 1280 (`screenLayout.ts`, the sweep's S7, untouched).

## 6. Found on the way, and the judgment calls

* **A fleet AT SEA lost her name.** The sweep never sent a fleet to sea in its 8-hull world. With one at sea, `to Cape St Vincent · 22s`
  (160 px) stood beside the name in a label of 188 px at 320×640 and 258 at 390: the name was left **16 px** (nothing to read or press) and
  76 px. The old row, 24 px wider, left about 40 px by arithmetic (the old build was not sent to sea), so the defect is older than this slice. The label stack wraps now: one line while they
  fit, the where line under the name when they do not (one more line for that fleet: 105 px instead of 81 at 390).
* `you.shipsCount` said `1 in 1 fleets`; it is plural-aware now.
* The captain tiles cut most captains' names at 390 (`Afonso de Al…`, `Isabel de Cas…`); a row has the room for twenty-odd characters and the rest is a `Clip`
  (the full name on hover, and on a touch glass a press reads it whole and opens nothing: proved).
* A ship's 24-character name wrapped to two lines in YOU (59 → 81 px); a `Clip` keeps every ship row to one name line.
* The first draft of the YOU strip stood on a surface (72 px in the budget); a surface over a surface is what the sheet's own law forbids and
  the Stats faces' figure block has none, so it stands on the glass (56 px).
* **Judgment, stated.** FLEETS has no figure block: the old header counts were removed on purpose ("limits are not assets"), and a fleet-wide
  total would be a NEW fact and, with two fleets, a near copy of the rows. YOU's two sections stand side by side from `lg` in the shared
  `SectionColumns`. `src/live/YourCaptains.tsx` is edited and `src/live/useYourCaptains.ts` added: the file is outside the brief's
  "own" list but not on its forbidden list, and its only caller is the YOU screen; `OfficerTile` (the Codex's old tile, the merchant's
  sheet) is untouched.
* **With two fleets the panel is mostly empty inside** (§5). That is the five unfolded screens' behaviour too (a list panel takes the
  glass), and it is a different thing from the sweep's row 17 (glass nothing stands on). What would fill it is real content, and each
  candidate is a decision for the owner, not a layout: the fleet's own page standing beside the list on the wide glass (a different
  press: the row would select, not open a page), or a fleet's ships and cargo as lines under its row (the owner asked on 2026-10-31 for
  the fleet's detail on a page and a small row). Not built.

## 7. Not verified

* The owner's real world: both worlds are throwaway images from this build's own image; the six captains are a type-shaped
  `world.captains()`, every fleet has one hull and the fleet names are the fixture's. Real captains' grades and jobs, fleets of several ships,
  ship names unlike their fleet's name were not drawn.
* More than one fleet at sea at once (each such row is one line taller on a phone; eight at sea at 390 would not all stand whole), and any
  at-sea state in Korean.
* The light colour scheme; a real phone (the touch press-to-read ran in Chromium's mobile emulation).
* Production: this is a client-only change; the Pages deploy and main's Acceptance on the merge commit are read after the merge (PR).
