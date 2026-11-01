# 2026-11-01 — UNFOLD · ROUTES (branch `unfold-routes`, client-only)

> Owner, row 260: *"everything is folded … make it compact showing everything possible."*
> Owner, 2026-11-01: *"make things unfolded, minimize scrolling, everything compact with full info."*
> Laws: `2026-11-01-ui-unfold.md` (U1–U8) on branch `city-mobile`. Fifth and last of the five screens (Stats #447, Codex #448,
> Ledger #449 merged; Rank in review). **Budget below was written before any Routes code.**

## 1. Inventory — the OLD Routes, measured (headless, 390×844 · 320×640 · 1280×800)

Screenshots: `…\scratchpad\unfold\shots\before-routes-main-<W>x<H>.png` (canary world: **no lanes**, NPC traders off) and
`beforeL-routes-main-…` (a local live-sized world: `world.route_board` replaced in a scratch image by a board of **40 of 120
lanes**, two hers, some unmeasured, some shut to her, some with no lap closed yet — the shape `RouteBoard` documents, served up to
`route_board_max`). Data `before-en-US.json`, `beforeL-en-US.json`.

| size | main | Sheet | what stands on the face |
|---|---|---|---|
| 390×844 | **755** | 755/755 | **one `SummaryRow`** (`routes-open`: `Routes 40 · Open`) and nothing else — ~90 % of the glass empty |
| 320×640 | **551** | 551/551 | the same |
| 1280×800 | **711** | 711/711 | the same |

Behind the press (`routes-open-page`, a full-screen `DetailPage`; on the 40-lane board its pane scrolled **2,618 px** in 788): a line
`N lanes · <age>` with the `Read again` button (`routes-refresh`), the stale note, the order strip (`Distance · Earnings · Calls`),
her lanes on their own panel, the merchants' lanes on another, the *omitted* hint, and the lane tray (`route-tray`). Defects: (1) the
whole board is behind a press (U1); (2) the order strip and the refresh button are invisible until the press; (3) a lane with no
figure drew a dash (`—`) in the ranked column — the consistency law (omit, do not dash) forbids a placeholder on a compact screen.

Every figure / test id of the old face, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `routes-open` (`Routes N · Open`) | summary row | the panel's title: `N lanes` / `N of M lanes` (the served words), and the board's age beside it |
| `routes-open-page` and its Back | pop-up `DetailPage` | **gone** — the board is the list |
| `routes-refresh` (`Read again`, busy label) | a button in the page | the panel's one button, on the title line |
| order strip `Distance · Earnings · Calls` | `Segmented` in the page | `Segmented` in the panel's header (it sorts this list) |
| `routes.stale` note | in the page | in the panel's header |
| her lanes (accent) then the merchants' | two panels | one list, hers first, accent tone kept |
| `route-lane` ×N (name, ranked figure, caption line, chevron) | rows in the page | the same rows in the panel |
| ranked figure absent (`—`) | a dash | the word the tray already uses (`Not yet` for earnings, `Unmeasured` for distance) |
| `routes.omitted` hint | under the panels | the last line of the panel's body |
| `route-tray` (`LaneTray`) | tray in the page | unchanged, a sibling of the panel (never inside a scroller) |
| loading skeleton / `routes.failed` note / empty row (`No routes`) | in the page | the same states (skeleton and failed note stand in the Sheet; the empty row in the panel) |

## 2. The change

`Sheet fill` · ONE `ListPanel` (`routes-list`): title = how many lanes the board holds with its age beside it, the refresh button
as `trailing`, the stale note and the order strip as `controls`, the lanes (hers first) as rows, the omitted hint last. The lane tray is
a sibling outside the panel. No new primitive. Reads unchanged (`useRouteBoard`).

## 3. Budget — 390×844 (main 755), 320×640 (551), 1280×800 (711)

Chrome: sheet title 38 · bottom pad 8 (there is no face strip on this screen: the order strip is the panel's) → the panel is
main − 46: **709 · 505 · 665**. Inside it: header — the title line with the 44-px button ≈ 56, the order strip ≈ 56 (≈ 112 in all;
the stale note adds ≈ 48 when it shows) → body **≈ 597 · 393 · 553**.

| glass | label track (row − value ≈ 80 − chevron 32) | caption line | row height | rows whole (budget) |
|---|---|---|---|---|
| 390×844 | ≈ 220 px | 2 lines (`company · 5 calls · 3 regions · 4,120 nm · no fleet`) | ≈ 74 | **≥ 6** of 8 |
| 320×640 | ≈ 150 px | 3 lines | ≈ 95 | **≥ 3** of 4 |
| 1280×800 | ≈ 640 px (the panel is 752 wide) | 1 line | ≈ 52 | **≥ 8** of 10 |

The proof floor is `min(lanes served, N)`: the canary serves no lane (the empty state is what is proven there), a live world up to
`route_board_max`; both are exercised (below).

## 4. Proof (`tests/routes.unfold.spec.ts` on `tests/unfold.fixture.ts` — 390×844 · 320×640 · 1280×800)

Page and Sheet scroll 0 · the panel stands inside the glass with ≥ `min(lanes, N)` lanes whole before any press · the three
orders and `routes-refresh` (44 px) are present · no two text boxes cross · cut text carries its full text · no placeholder dash
in a lane · pressing a lane opens `route-tray` and closing it leaves the board unchanged; an order tab re-ranks without moving the
title. **The lanes come from a played world the fixture builds at run time** (`playedWorld(page)`: this build's own image,
`world.route_board` replaced by forty lanes — the Ledger's CI red, #449, taught that a spec may not skip for want of rows); the
young world (the canary: no lane) has its own test — the board says so, the orders and the button stand.
`align.spec` (it pressed `routes-open` to reach the order strip) is rewritten with the reason in the commit.

## 5. Measured (served build, headless)

| lanes whole before any press | 390×844 | 320×640 | 1280×800 |
|---|---|---|---|
| 40-lane board (of 40 served, 120 on the board) | **9** | 5 | 9 |
| canary world (no lane: the empty row `No routes of yours.` stands in the panel) | 0 of 0 | 0 of 0 | 0 of 0 |

Lane heights: 56–73 px at 390 · 56–97 at 320 · 56–57 at 1280. Page and Sheet scroll **0 px** at every glass on both worlds; the old
page behind the press was 2,618 px of lanes in 788. Panel 709 / 505 / 665 px (the budget's 709 · 505 · 665).

## 6. Found on the way

* The ranked column drew `—` for a lane the server could not measure (and, on the Earnings order, for every lane before a second
  lap closes). On a screen that is a placeholder the consistency law forbids; the lane now says `unmeasured` / `not yet` — the words the tray
  already uses — so the ranked column is never blank and never a dash.
* At 320 the title `40 of 120 lanes`, the board's age and the one button no longer fit one line: the title wraps to two and the age
  was wrapping to two as well (`just / now`). `ListPanel`'s count is now `whitespace-nowrap` (one class, shared: Stats' counts are one word each).
* Judgment calls, stated: her lanes lead the list on their accent tone instead of standing on their own panel (the owner row 115 asked to see
  every route; a second panel would have cost 56 px of header for two rows); the live-sized board is a scratch image whose
  `world.route_board` returns forty type-shaped lanes, so real route names, nations and the `ink` colour were not exercised.
