# 2026-11-01 — UNFOLD · COMPENDIUM (the Codex) (branch `unfold-codex`, client-only)

> Owner, row 260: *"everything is folded … make it compact showing everything possible."*
> Owner, 2026-11-01: *"make things unfolded, minimize scrolling, everything compact with full info."*
> Laws: `2026-11-01-ui-unfold.md` (U1–U8) on branch `city-mobile`. Second of five screens (Stats #447 merged; Ledger, Rank, Routes next).
> **Order of work, stated plainly:** the Codex was built from the Stats method and its first build measured; this budget table
> was written beside that first build, not before it. The Ledger, Rank and Routes tables are written before their code.

## 1. Inventory — the OLD Codex, measured (headless, local canary world, 390×844 · 320×640 · 1280×800)

Screenshots: `…\scratchpad\unfold\shots\before-compendium-<Face>-<W>x<H>.png` (EN), `…-page-codex-open.png` (the pop-up page);
data `before-en-US.json`.

| size | main (px between bar and nav) | Sheet | what stands on the face |
|---|---|---|---|
| 390×844 | **755** | 755/755 | face tabs and **one `SummaryRow`** (`codex-open`: `Goods 629 · Open`), about 80 % of the glass empty |
| 320×640 | **551** | 551/551 | the same |
| 1280×800 | **711** | 711/711 | the same |

Behind the press (`codex-open-page`, a full-screen `DetailPage`, 390×844): the page's own pane scrolled **39,172 px** of tiles
(Goods, 629), **9,017** (Ships, 103), **6,937** (Captains, 105), **1,384** (Nations, 23) in a 788-px pane. The search box and
every filter lived only inside that page. Tiles were a two-up `TileField`; a name wrapped or was cut inside a ~165-px tile.

Every figure / test id of the old face, and where it goes (nothing is removed — U3):

| old id / figure | was | now |
|---|---|---|
| `codex-open` (face name + count + `Open`) | summary row | the panel's title: `629 goods` · `103 ships` · `105 captains` · `23 nations` (plural keys EN + KO), live with the search |
| `codex-open-page` and its Back | pop-up `DetailPage` | **gone** — the face is the list; nothing is behind a press except an item's own tray |
| the search field (label/placeholder `Filter <face>`) | inside the page | `codex-search` on the panel's title line; label unchanged, placeholder is the one short word `Search` (`Filter capt…` was cut at 160 px) |
| `good-kind` headings, `good-tile` ×629 (name, rarity word, base price) | tile in a `TileField` | `Row` under the kind headings: mark, name (wraps, never cut), rarity word (drops under the name when the two do not fit), base price, chevron |
| `good-tray` (kind, rarity, base, weight, spoils, not-traded note) | tray | unchanged — a sibling of the panel, outside any scroller |
| `ship-filters` (country, size, role, tech: four chip groups) | chips in the page | `FilterBar compact`: four selects on one line in the panel header (`filter-pick-line · size · role · tech`), each naming itself while unfiltered |
| `ship-tile` ×103 (name, hold, speed, flag, tech, size · role · family · rig, crew) | tile | `Row`: ship mark, name, hold, chevron; facts line: **speed**, flag, tech, size · role · family · rig, crew |
| `ship-tray` | tray | unchanged |
| `captain-filters` (grade, role, job) | chip groups | `FilterBar compact`: three selects (`filter-pick-grade · focus · job`) |
| `officer-tile` ×105 (`OfficerTile`: name, grade, job, signed, level, home port, bonus %, muted when no effect) | tile | `Row`: crew mark, name, `+bonus %` (success / faint), muted tone when no effect, chevron; facts line: grade · job · signed · level · port |
| `officer-tray`; skeleton and `captainsFailed` note | tray | unchanged (the skeleton and the note stand in the panel) |
| `nation-rows` · `nation-great` · `nation-rulers` (23 flags with capitals) | page | in the panel, read-only rows in the two groups (new id `nation-row`) |

## 2. The change

* `CompendiumScreen`: `Sheet fill` · the face `Segmented` · ONE `ListPanel` per face (the shared primitive that Stats added),
  its `trailing` the search `Field`, its `controls` the face's `FilterBar compact`. The search clears when the face changes, as before.
* The four faces are rewritten to the panel: a press on a row opens THAT item's tray (kept as a sibling of the panel).
  No new primitive; no change to `Row`, `ListPanel`, `FilterBar`.
* `unfold.fixture.ts` — the measuring apparatus of the unfold laws (the three glasses, page / Sheet scroll, sideways
  scrollers, overlaps clipped by their panes, cut text, whole rows in a panel) moved out of `stats.unfold.spec.ts`, so Stats,
  the Codex and the next three screens read the glass the same way.
* Words: `codex.countGoods · countShips · countCaptains · countNations · search` (EN + KO). The unfiltered select names
  itself (`Country`, `Size`, `Role`, `Tech`, `Grade`, `Job`) instead of four identical `All`; Stats' Cities area select now does
  the same (one line, `stats.area`).

## 3. Budget — written beside the first build (see the note at the top)

Chrome (every face): sheet title 38 · face tabs 52 + 4 gap · panel top at 126 · bottom pad 8 → the panel is main − 102:
**653** at 390×844, **449** at 320×640, **609** at 1280×800. Inside it: header (title + search) **56** · controls line **48**
(Ships 4 selects, Captains 3; none on Goods and Nations) · the body takes the rest.

| face | row height (px) | body @390 | rows whole @390 | body @320 | @320 | body @1280 | @1280 |
|---|---|---|---|---|---|---|---|
| Goods | 44 (one line) · 65 (rarity under the name) · 89 at 320 (the name wraps too) · +24 per kind heading | 597 | budget ≥ 8 → **12** | 393 | ≥ 4 → **5** | 553 | ≥ 8 → **12** |
| Ships | 86–107 @390 · 106–147 @320 · 66 @1280 (name + hold / speed + flag / facts / crew) | 549 | ≥ 4 → **6** | 293 (the four selects wrap to two lines) | ≥ 2 → **2** | 505 | ≥ 4 → **7** |
| Captains | 60 · 85 at 320 when a name wraps (name + bonus / facts) | 549 | ≥ 4 → **9** | 345 | ≥ 2 → **5** | 505 | ≥ 4 → **8** |
| Nations | 32 (read-only) + 2 group headings | 597 | ≥ 12 → **16** of 23 | 393 | ≥ 6 → **10** | 553 | ≥ 12 → **15** |

The whole catalogue is static (the same 629 / 103 / 105 / 23 in the canary and the live world), so these are the live numbers
too, except a captain's *signed* word (only seen here unsigned).

## 4. Proof (`tests/codex.unfold.spec.ts`, 390×844 · 320×640 · 1280×800, every face)

Page and Sheet scroll 0 · no sideways scroller · the panel stands inside the glass with ≥ N rows **whole** before any press
(table above) · `codex-search`, the face's filters and its groups are present · no two text boxes cross · **no text in the panel
is cut at all** (stricter than the shared law: the names are static, so a name wraps at its spaces instead of using press-to-read) ·
a row press opens its tray and closing it leaves the list unchanged · the search narrows and clearing restores · a ship filter
narrows and resets. `layout.spec` — the three COMPENDIUM *grid* assertions (`maxPerRow ≥ 2`, `tileWidth < 220`) were the owner's
2026-08-26 grid rule for the catalogue; they are retargeted (with the reason in the spec) to *one entry a line, as wide as the
panel, ≥ N whole rows in the glass*. `captains.codex`, `greatPowers` no longer press `codex-open` and read the face where it stands;
`captains.codex` drives the pickers instead of chips.

## 5. Found on the way

* **The first cut build kept names in `Clip` (press-to-read) and was still wrong:** at 320×640 the name got 45–55 px beside
  two figures (`Niao…`, `Barque` cut by 2 px) and 26 px in a goods row beside the rarity word (`Camels` 49 needed). U5 would have
  allowed it; the owner's *full info* does not. Names now wrap, the ships' speed leads the facts line, and the rarity word drops
  under a goods name that is too long to share its line (no `Clip` anywhere in the Codex). Cost: rows are taller (Ships 7 → 6 whole at 390).
* Four identical `All` selects made the Ships header unreadable → each names itself; the cost is that the four selects wrap
  to two lines at 320 (the Ships body is 293 px there, still ≥ 2 whole rows).
* `Filter capt…` / `Filter nati…` were cut in the 160-px field → one short placeholder, the long label kept as `aria-label`.
* The `layout.spec` comment that quoted whole-row counts was not a measurement; it now quotes the printed ones (13 · 7 · 9 on the first build, 12 · 6 · 9 on the last).
* Judgment calls, stated: the Sheet's wide column (reserved tray width) is unchanged, so at 1280 the panel is 752 px wide and
  an item's tray opens in the reserved column; the top bar's `Game date` label is cut at 320 (117/107 px) — the shell's, not
  this screen's, and it carries its own text; not touched.
