# 2026-11-01 — UNFOLD · RANK (branch `unfold-rank`, client-only)

> Owner, row 260: *"everything is folded … make it compact showing everything possible."*
> Owner, 2026-11-01: *"make things unfolded, minimize scrolling, everything compact with full info."*
> Laws: `2026-11-01-ui-unfold.md` (U1–U8) on branch `city-mobile`. Fourth of five screens (Stats #447, Codex #448 merged; Ledger in review).
> **Budget below was written before any Rank code.**

## 1. Inventory — the OLD Rank, measured (headless, canary world: 10 captains on the board, 23 countries; 390×844 · 320×640 · 1280×800)

Screenshots: `…\scratchpad\unfold\shots\before-rank-<Face>-<W>x<H>.png` (+ `-page-rank-open.png`, the pop-up page) and
`beforeL-rank-…` (the 50-entry local world; Rank is unchanged by it). Data `before-en-US.json`, `beforeL-en-US.json`.

| size | main | Sheet | what stands on the face |
|---|---|---|---|
| 390×844 | **755** | 755/755 | `Rank · settled just now`, two face tabs (`Captains · Countries`) and **one `SummaryRow`** (`rank-open`: `Captains 10 · Open`) — ~80 % empty |
| 320×640 | **551** | 551/551 | the same |
| 1280×800 | **711** | 711/711 | the same |

Behind the press (`rank-open-page`, a full-screen `DetailPage`): the **pinned line** (`rank-you`: your place, company, fame, flag
and *tied*; a chevron opens the fame tray `fame-tray` — trade fame, exploration fame, ports, total) over the board rows (place,
company, fame; flag · tied; `rank-mayor-of` cities) and, on the Countries face, 23 `rank-country` rows (flag, held, home · won ·
this week · its three biggest givers). Defects: (1) the whole board is behind a press (U1); (2) the face tabs switch a list
nobody can see; (3) the one summary row's only figure is a count.

Every figure / test id of the old face, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `rank-open` (`Captains 10 · Open`, `Countries 23 · Open`) | summary row | the panel's title: `10 captains` / `10 countries` (plural keys EN + KO). **A figure that changed:** the old Countries figure was the 23 nations of the catalogue, while the page below it listed the 10 great powers; the title now counts the rows it shows |
| `rank-open-page` and its Back | pop-up `DetailPage` | **gone** — the board is the list |
| `rank-you` (+ its second line, the *below the board* hint) | pinned panel in the page | **pinned in the panel's header** (fixed over the scrolling rows) — same row, same press |
| `fame-tray` (trade / exploration / ports / total) | tray under the board | unchanged, a sibling of the panel (never inside a scroller) |
| board rows (place, company, fame, flag · tied, `rank-mayor-of`) | rows in the page | the same rows in the panel |
| skeleton / `rank.failed` note / empty-world `why` / `rank.notRanked` | in the page | the same states in the panel |
| `rank-countries` / `rank-country` ×23 | page | the same rows in the panel |
| `rank.settled` (the photograph's age) | Sheet trailing | unchanged |

## 2. The change

`Sheet fill` · the face `Segmented` · ONE `ListPanel` per face: Captains (`rank-list`: header = the count and YOUR pinned line,
body = the others) and Countries (`rank-list`, body = the 23 country rows). The fame tray is a sibling outside the panel. No
new primitive. Reads unchanged (`loadStandings` on the world beat, `world.nation_standings`).

## 3. Budget — 390×844 (main 755), 320×640 (551), 1280×800 (711)

Chrome: sheet title 38 (with the settled caption) · face tabs 52 + 4 gap · panel top 94 below main · bottom pad 8 → the panel is
main − 102: **653 · 449 · 609**. Header: the title line ≈ 40 + (Captains only) the pinned line ≈ 64 (a 52-px pressable row with its
flag line) → body **≈ 549 · 345 · 505** on Captains, **≈ 613 · 409 · 569** on Countries.

| face | row height | rows whole (budget) at 390 · 320 · 1280 |
|---|---|---|
| Captains (others) | 52 (name + fame) · ≈ 70 with the flag · tied line | **≥ min(rows, 6 · 3 · 8)** |
| Countries | ≈ 70 (flag name + held / home · won · week · givers, which wrap) | **≥ min(rows, 6 · 3 · 8)** of 23 |

The proof floor is `min(rows served, N)`: the canary serves 10 captains (9 under the pinned line) and 23 countries; a live
world serves more captains, which only lengthens the scroll inside the panel.

## 4. Proof (`tests/rank.unfold.spec.ts` on `tests/unfold.fixture.ts` — 390×844 · 320×640 · 1280×800, both faces)

Page and Sheet scroll 0 · the panel stands inside the glass with ≥ `min(rows, N)` rows whole before any press · `rank-you` stays
on the glass while the board scrolls · `rank-country` rows, the face tabs and the settled caption are present · no two text boxes
cross · cut text carries its full text · pressing `rank-you` opens `fame-tray` and closing it leaves the board where it was.
`rank.countries.spec` (it opened the Countries page) and the one-home-per-fact test in `consistency.spec` (it pressed `rank-open` to
find `rank-you`) are rewritten with the reason in the commit.

## 5. Measured (served build, headless, canary world: 10 captains, 10 countries)

| rows whole before any press | Captains (under the pinned line) | Countries |
|---|---|---|
| 390×844 | **10** of 10 | **10** of 10 |
| 320×640 | 7 of 10 | 7 of 10 |
| 1280×800 | 10 of 10 | 10 of 10 |

Page and Sheet scroll **0 px** on both faces at every glass; `rank-you` does not move while the board scrolls and its press opens
`fame-tray` (closing leaves it in place). The old page behind the press held the same rows in a 788-px pane (it fitted).

## 6. Found on the way

* The `Countries 23` summary figure disagreed with the ten rows under it (see the mapping); the title now counts what is shown.
* A live board has more captains than the canary's ten; that only lengthens the scroll inside the panel (the pinned line and the
  title stay fixed). The seeded world of the Ledger/Routes screens does not replace `world.standings`, so the board was not
  exercised beyond ten rows.
