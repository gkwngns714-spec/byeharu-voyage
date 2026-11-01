# 2026-11-01 — UNFOLD · LEDGER (History) (branch `unfold-ledger`, client-only)

> Owner, row 260: *"everything is folded … make it compact showing everything possible."*
> Owner, 2026-11-01: *"make things unfolded, minimize scrolling, everything compact with full info."*
> Laws: `2026-11-01-ui-unfold.md` (U1–U8) on branch `city-mobile`. Third of five screens (Stats #447, Codex #448 merged).
> **Budget below was written before any Ledger code** (the Codex's was written beside its first build; see its log).

## 1. Inventory — the OLD Ledger (History), measured (headless, 390×844 · 320×640 · 1280×800)

Screenshots: `…\scratchpad\unfold\shots\before-ledger-<Face>-<W>x<H>.png` (canary world, 1 entry) and
`beforeL-ledger-…` (a local live-sized world: `world.ledger` replaced in a scratch image by a page of **50** events — the
size the client reads, `worldLedger(null, 50)` — so the page's own height is on record). Data `before-en-US.json`, `beforeL-en-US.json`.

| size | main (px between bar and nav) | Sheet | what stands on the face |
|---|---|---|---|
| 390×844 | **755** | 755/755 | four face tabs (`All · Trade · Voyage · Crew`) and **one `SummaryRow`** (`ledger-open`: `History 1 · Open`), ~80 % of the glass empty |
| 320×640 | **551** | 551/551 | the same |
| 1280×800 | **711** | 711/711 | the same |

Behind the press (`ledger-open-page`, a full-screen `DetailPage`; at 390×844 on the 50-entry world its pane scrolled **3,733 px**
in 788 — All 50 entries, Trade 10 (853), Voyage 20 (1,543), Crew 20 (1,423)): the rows (`ledger-row`: mark, the headline sentence,
the money movement, the clock time under it) and, on a row with a report, a chevron that opens the report `Tray`
(`ledger-report`, with `battle-report` rounds). Defects: (1) the whole feed is behind a press (U1; the owner's *"make things
unfolded"*); (2) the face tabs filter a list nobody can see; (3) one `SummaryRow` carries the count as its only figure.

Every figure / test id of the old face, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `ledger-open` (`History N · Open`) | summary row | the panel's title: `N entries` (plural key EN + KO), live with the face tabs |
| `ledger-open-page` and its Back | pop-up `DetailPage` | **gone** — the feed is the list; the report tray is the only thing behind a press |
| `ledger-row` ×N (mark, headline, movement, clock time, chevron when there is a report) | rows in the page | the same rows in the panel, same attributes |
| `ledger-report` (report lines) + `battle-report` rounds | tray | unchanged, a sibling of the panel (never inside a scroller) |
| the face tabs `All · Trade · Voyage · Crew` | `Segmented` above the summary row | unchanged, above the panel |
| empty state (`Nothing yet.` / `Nothing here yet.`) | a muted row in the page | the same muted row in the panel |

## 2. The change

`Sheet fill` · the face `Segmented` · ONE `ListPanel` (`ledger-list`) of `Row`s. The row is the feed row the Stats money log
already uses (the headline on line one with the movement, the clock time on line two); a row with a report keeps its chevron
and opens the tray as before. No new primitive. Reads unchanged (`worldLedger(null, 50)`).

## 3. Budget — 390×844 (main 755), 320×640 (551), 1280×800 (711)

Chrome: sheet title 38 · face tabs 52 + 4 gap · panel top at 94 below main · bottom pad 8 → the panel is main − 102:
**653 · 449 · 609**. Inside it: header (the title line, no search, no filter) **≈ 40** → body **≈ 613 · 409 · 569**.

| glass | label track (row − mark 40 − movement ≈ 72 − chevron 32) | headline lines | row height | rows whole (budget) |
|---|---|---|---|---|
| 390×844 | ≈ 190 px | 2 (a sentence of ~40 characters wraps once) | ≈ 69 | **≥ 6** of 8–9 |
| 320×640 | ≈ 120 px | 3 | ≈ 89 | **≥ 3** of 4–5 |
| 1280×800 | ≈ 560 px (the panel is 752 wide) | 1 | ≈ 49 | **≥ 8** of 11 |

The proof floor is `min(rows served, N)`: the canary world serves one entry, a live world fifty; both are exercised (below).

## 4. Proof (`tests/ledger.unfold.spec.ts` on `tests/unfold.fixture.ts` — 390×844 · 320×640 · 1280×800, every face tab)

Page and Sheet scroll 0 · the panel stands inside the glass with ≥ `min(rows, N)` rows whole before any press · `ledger-row`, the
face tabs and the empty state are present · no two text boxes cross · cut text carries its full text · a row with a report
opens the report tray and closing it leaves the list unchanged, and a face tab narrows the feed and the title counts it (the
live-sized local world only: `UNFOLD_WORLD=<image>`, otherwise **skipped, with the reason printed** — the canary has no entry
with a report). No existing spec named the Ledger's summary row, so none is rewritten: `align`, `consistency`, `onepage`
and `layout`'s table walk read the screen generically.

## 5. Measured (served build, headless)

| rows whole before any press | All | Trade | Voyage | Crew |
|---|---|---|---|---|
| 390×844, 50-entry world (of 50 · 10 · 20 · 20) | **9** | 8 | 8 | 10 |
| 320×640 | 4 | 4 | 5 | 6 |
| 1280×800 | 11 | 10 (all) | 11 | 11 |

Row heights (All): 49–81 px at 390, 49–105 at 320, 48–57 at 1280. Page and Sheet scroll **0 px** on every face at every glass,
on the canary (1 entry) and the 50-entry world; the old page behind the press was 3,733 px of rows in 788.

## 6. Found on the way

* The world image of the first seeded run was stale (older than the current migration chain) and the app sat at *World 0 %*
  for 130 s; a seed has to be rebuilt from the current `dist/db` image every time. Local scaffolding only, nothing in the repo.
* Judgment call, stated: the clock time stays under the sentence (line two), as on the old page and on the Stats money log; at
  390 a two-line sentence plus the time makes most rows 72–81 px — the cost of full sentences (nothing is cut).
