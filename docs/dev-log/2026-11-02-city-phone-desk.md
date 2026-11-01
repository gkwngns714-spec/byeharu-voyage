# 2026-11-02 — THE DESK'S CITY BOARD ON A PHONE (branch `city-phone-desk`, client-only; part 2 of the HQ-on-a-phone slice)

> The brief's defects (b) and (c): *"Desk 'City' face at 390 leaves the board pane only about 190 px"* and *"the request rows' `deliver` cell runs 10–16 px past its row at 390"*.
> The slice is `docs/dev-log/2026-11-02-city-phone.md` (its first PR holds the shared primitives: `Row`'s wrapping flow, `ActCell`'s wrapping reason, the `pair:` / `narrow:` / `tight:` variants);
> this is its second PR. Owner, row 251: *"make it concise and simple so that it is easy to see in one eye without scrolling down"*.

## 1. Inventory — Command › City on a phone (served `main`, headless, English and Korean, DPR 1)

The desk's City face on a phone is a stack — the fleet strip (picker and two figures), the four desk faces, the city's header with `City view`, the eight buildings — over ONE board: the building's own face
(Trade: a supplies row, Buy · Sell · Requests, a filter, then the goods), which scrolls inside its pane so the page never does.

| | 390×844 | 320×640 | 1280×800 (the three-pane desk) |
|---|---|---|---|
| the Sheet | 32…787 (755 px), no scroll | 32…583 (551 px), **scrolls 41 px inside itself** | — |
| the board pane | **y 408, 192 px** (`max-h-[12rem]`) — and the Sheet ends 187 px below it (…600 vs 787) | y 408, 192 px — reaching 17 px **below** the Sheet's bottom | 974 px (Buy), 420 (Requests) |
| the pane's own controls | supplies row 52 + faces 52 + filter 52 = 150 of its 192 | the same | — |
| goods standing whole in the pane before any press | **0** | **0** | 10 (Buy) · 4 (Requests) |
| a request row's `deliver` cell | its dead reason ("0 / 30 units on board") on ONE line: 12.5–15.7 px past its 112-px box and its row; **the pane scrolls sideways by 16 px** | the same, 16 px | — |

**(b) is real, and worse than "about 190 px"**: 40 px of goods stood on the glass at 390 and none at 320. **(c) is real, but it is the REASON inside the cell**, not the cell: `Row`'s value is `whitespace-nowrap`
and the reason inherited it (the first PR's `ActCell` fix; this PR's test holds it on the desk, where it was measured).

## 2. Cause and the change

The pane was given a number (12 rem) where it should have been given *the rest*. Four edits and one attribute, no new primitive:

* `CommandScreen.tsx` — the phone's `Sheet` is `fill` (the unfold slice's own flag: the body is a flex column that takes the height under the title). For EVERY desk face, so pressing one never moves the title
  (the press law); a face taller than the glass still scrolls the Sheet, as before.
* `DeskFrame.tsx` — `DeskParts.mainFill`: on a phone `DeskStack` makes the centre part a flex column that takes what the list part leaves (`flex min-h-0 flex-1`), the list part `shrink-0`. The wide `DeskPanes` ignore it.
* `City.tsx` — the tabpanel and its `ScrollPane` are `flex-1` (7 rem at the least: `min-h-28`, so a short glass scrolls the Sheet rather than crush the board), the 12-rem cap is gone, and the pane is a **query
  container** (`@container`): the first PR's `pair:` makes a Trade row in the 288-px pane at 320 stand its name over its two price cells instead of squeezing the name to a letter column.

* `ActCell.tsx` + `index.css` — an act cell is `data-act-cell`, and the rule that hangs a lone control 10.5 px above and below its line (a 44-px `Button`) no longer applies to it: the `deliver` cell
  stands alone in its value, so it was hung like a button but is 56–78 px tall, and each row's cell ran 3 px into the next (336 px² at 390; the sweep's row 9). (The Market's pair never met the rule: it stands inside `ActPair`.)

## 3. Budget (before the code)

Everything above the pane is the same height at both widths: **376 px on `main`** (the pane starts at y 408, the Sheet at 32) — the fleet strip 100, the four desk faces 52, the city's header 52, its eight buildings 100, and the title and the pane's own margins. `fill` gives 8 px of the title's padding back: **368**. The pane is then the Sheet less that less its 8 px of bottom padding:

| glass | Sheet | − chrome 368 − padding 8 | the pane | its controls | goods before a swipe |
|---|---|---|---|---|---|
| 390×844 | 755 | | **379** | 150 | 229 px = two 64–80-px Trade rows whole and a third cut |
| 320×640 | 551 | | **175** | 150 | 25 px — the controls and no goods |

A 320×640 glass cannot be given more without taking something out of the strip, the faces or the buildings, which this slice does not do (§6).

## 4. The law (`tests/desk.city.spec.ts`, one added test; red on `main`)

At 390×844 and 320×640: the Sheet does not scroll; the pane's bottom edge stands within 16 px of the Sheet's; at 390 it is ≥ 350 px tall and two goods stand whole in it, at 320 it is ≥ 7 rem; and what is in it —
Buy, Sell and Requests — is clean by the HQ's laws (`readGlass`: no sibling overlap, no letter column, nothing cut, nothing sideways; the request rows' `deliver` cell included).

## 5. Measured (served builds of `main` and of this branch on the merged first PR; same world; headless; `tests/desk.city.spec.ts` prints the numbers on every run)

| | before (`main`) | after |
|---|---|---|
| 390×844 — the board pane | **192 px** at y 408, 187 px of Sheet below it | **379 px** at y 400 — to 8 px (the Sheet's padding) above the Sheet's bottom |
| 390×844 — goods whole in the pane before a swipe | **0** | **2** (Aniseed, Black Pepper; a third cut by the edge) |
| 320×640 — the Sheet | **scrolls 41 px** inside itself | **0** — flat |
| 320×640 — the pane | 192 px, reaching 17 px below the Sheet's bottom | 175 px, inside it (its 150 px of controls and 25 px of goods; 0 whole) |
| the Requests pane, sideways scroll | **16 px** (374 in 358 at 390; 304 in 288 at 320) | **0** |
| a dead `deliver` cell | its reason on one line, 12.5–15.7 px past its 112-px box | the reason wraps inside the box (2 lines): the cell is 78 px, whole |
| two request rows' cells | overlap by **3 px (336 px²)** at 390 and (79×3) at 1280 — the cell was hung 10.5 px above and below its line like a 44-px button | **0**: an act cell keeps its margin box (`data-act-cell`; `index.css`) |
| a request row | 59–81 px | **95 px** (the wrapped reason's line, and the hang's 21 px back) |
| 1280×800 — the three-pane desk | Buy pane 974 px, 10 goods whole; Requests pane 420 px | the same panes and the same 10 goods whole; **the Requests rows are 95 px, not 59** (the one wide-glass change, and it is the overlap's fix) |

The wrap and the margin box together make the request rows 36 px taller at every glass; that is what keeps a 78-px cell from standing on its neighbour. A row whose reason is short ("no ship here") is a one-line cell and a 78-px row.

## 6. Not done, and unverified

* The pane's three controls (supplies, the faces, the filter) scroll with the goods; they could be pinned above the board to give a 320×640 glass its goods at once. Not done: it would move controls the owner has not asked to move.
* The request rows' "staircase" at 1280 (each `deliver` cell hugs its own label, so the cells do not share a column) is the owner's hug rule at work, not a defect; the overlap under it is fixed.
* The desk's Trade face (the first desk tab, `TradeBoard`) and Invest / Report are other screens and were not measured here (the sweep's rows 1 and 3).
* The wide desk's `City` pane `@container` is inert at `pair:` widths (480 px); only the phone's 288 px pane stacks a Trade row.
