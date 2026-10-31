# THE CITY AUDIT ROWS + SIX OWNER INSTRUCTIONS OF 2026-10-31: ONE SPLIT FOR SIX FACES, A FOLDABLE HALL, AN IN-PANEL BASKET, A LOADING METER, NO RING

2026-10-31 · client-only (`city-audit-fix`; no migration, no server change) · owner rows 251/252/253
and the day's six city instructions (row 255) · consistency-audit rows 1/2/3/5/6/32/34/35/36/39

## The audit, then the owner's six instructions

`docs/dev-log/2026-10-31-consistency-audit.md` (merged as `ac2865f1`, #427) measured 90 screens and
left seven city-owned violations. The City page had just been rewritten by its own slice (#426), so
every row was **re-measured on the merged build before it was fixed**: three came back clean and are
reported as already fixed by #426; the rest are fixed here. Then six owner instructions landed in
the same minute and reshaped the slice (all verbatim in `docs/OWNER_REQUESTS.md` row 255):

> "CITY HALL - THERE IS A SCROLL YOU NEED TO DO FOR INFLUENCE. MAKE INFLUENCE FOLDABLE, ADD
> POPULATION GOLD STATUS RELATIONSHIP EMPLOYEES ON THE RIGHT SIDE SINCE THERE WILL BE MORE ROOM"

> "MARKET- BASKET? WTF IS THIS POPPING UP BLOCKING THE WHOLE SCREEN? FIX THIS AND I DON'T NEED TO
> SEEP POPULATION AND RELATION, ANYTHING THAT WAS ALREADY SHOWN ON TOWN HALL"

> "SAME FOR ALL THE OTHER TABS, NO INFO DUPLICATE INFO NEEDED. AND FOR EXAMPLE INN, HORIZONTAL SPACE
> IS TOO LARGE. MAKE IT COMPACT SO THAT I DON'T NEED TO SCROLL DOWN. THIS GOES FOR EVERY PARTS OF
> THE GAME"

> "when reloading, for example opening the city, or loading the map, show percentage of its loading
> time"

> "the market and rest of the tab (market, storage, forge etc), the same screen dividends (city
> view, then right side the info) should stay the same for all"

> "remove that ring. dont need this" · "no no not the map, the city. redo that." · "the yellow
> circle means the one that circle around a building. i don't get what that is."

## Re-measured audit rows, before → after

| # | audit row | measured BEFORE (merged main) | AFTER (this PR) | state |
|---:|---|---|---|---|
| 1 | City rail missing Fleets / hand-written cells with a second dictionary (rows 1–2) | rail cells **HQ · Fleets · Map · Stats · Menu**, heights **56** each at 390 and 1280, from the shell's `NavBar` (`NAV_CELLS`) | same; the four dead rail keys (`city.hq/menu/map/stats`) are deleted from the city dictionary | **already fixed by #426**; keys removed here |
| 2 | building-face Back control 36 px (`city-face-back`, row 32) | no `city-face` / `city-face-back` exists in `src/`; every visible control on the six panels clears **44×44** at 390 and 1280 | same | **already fixed by #426** |
| 3 | Market / Forge / Port faces scroll (rows 34 + 39; Sheets 1,075/844 · 17,496/844 · 6,488/844 at 390, Forge 8,856/800 at 1280) | in the #426 panel the market's inner scroller overflowed **1,090/548 at 390** and **1,010/504 at 1280**; the forge and port faces were the same long boards | every building panel is a compact screen that fits — measured **647/647 at 390 and 603/603 at 1280 for all five** (root and inner scroller); each row opens the existing face as the one `DetailPage` (root does not scroll; its body is the one scroller) | **FIXED here** |
| 4 | the 320×568 hall panel scrolls (row 35; 336/179; owner: "CITY HALL - THERE IS A SCROLL…") | hall scroller **336/179** in a **136×224** panel | the hall panel now carries the owner-ordered Influence FOLD (collapsed = one 44-px row; a press expands the influence book in place (tax rows OFF — the owner's 2026-10-30 rule stands)) and the five-figure block; measured **326/326 collapsed AND expanded at 390×568**; at 320×568 **278/278 collapsed** and the expanded book **289/278** (it scrolls 11 px inside the panel — stated — while the page stays 568/568 flat) | **FIXED here** |
| 5 | a building press may cover the six doors with a full-screen `city-face` (row 36) | each of the six presses left the frame **box-for-box identical** at 390 and 1280; only the two regions changed; no `city-face` layer exists | same, and now with the owner's newest split law: all six faces keep the SAME left image region and right panel region (rect sets compared across the six; no face takes the two regions) | **already fixed by #426**; split law proven here |
| 6 | Forge product controls carry whole recipe names (row 39; e.g. "Adire Cloth Indigo · Potash · Raw Cotton") | the control carried the product name **+ the ingredient list joined by `·`** | the control carries the product's own name only (no `·`); the tray the press opens is titled with that name and lists the ingredients (180 products measured; 7 proper names of three or four tokens declared: "Attar of Roses", "Dried & Salt Fish", "Ink & Brushes", "Raisins & Currants", "Russia Hemp Cloth", "Says & Serges", "Silverware & Plate" — good names, not recipes) | **FIXED here** |

The audit did not name the **inn's** overflow, but the composed face outgrew the #426 panel once its
reads landed — **873/548 at 390** and **633/504 at 1280** (a first pass that measured before the
reads landed read a false 548/548; the permanent spec now waits for each face's own content). It is
a compact screen too (Crew · Captains here), and all five building panels fit.

## What changed, by root cause

1. **ONE SPLIT FOR ALL SIX FACES (owner, 2026-10-31: "the same screen dividends (city view, then
   right side the info) should stay the same for all").** `CityScreen.tsx`: the city image is
   ALWAYS on the left (the same square plate, never cropped) and the open place's panel on the
   right — Town Hall or the building — at 390 and at 1280. The #426 branch that let an opened
   building take both regions is removed; the six rect sets (image, panel, split) are compared
   across the six presses by `tests/city.audit.spec.ts`. Measured identical across all six:
   at 390×844 the image is 179×647 at x16 and the panel 171×647 at x203 (the split 358×647);
   at 1280×800 the image is 624×603 and the panel 616×603 (the split 1248×603).
2. **THE FRAME'S FIGURES CARD IS DE-DUPLICATED; THE HALL IS THE SINGLE HOME (owner: "I DON'T NEED
   TO SEEP POPULATION AND RELATION, ANYTHING THAT WAS ALREADY SHOWN ON TOWN HALL").** The five
   figures moved out of the frame into the hall panel's compact block: Population (≈, the stated
   estimate off the served size tier) · Gold (the hall's purse) · Status (your influence points) ·
   Relationship (the served stance) · Employees (the crew aboard your hulls). No other face prints
   one of those words (asserted). The frame keeps ONE line of its own — YOUR purse ("Your
   earnings"), a fact the hall does not show — so the frame is header + six tiles + one earnings
   line + rail, identical across every press. That is the shape the owner's law allows ("the row
   shows nothing duplicated from the hall on non-hall faces"), and it is also what the merged #427
   `tests/consistency.spec.ts` still reads (its HQ-geometry proof requires a `city-summary` block
   between the split and the rail — the file is the audit writer's and was not edited here). The
   height the old card gave back is part of what lets the hall show its book at 390×568.
3. **THE INFLUENCE IS FOLDABLE — THE ONE OWNER-ORDERED FOLD (owner: "MAKE INFLUENCE FOLDABLE…").**
   `CityHallPanel.tsx`: collapsed, Influence is ONE row (its word, your served points, the
   disclosure chevron, ≥ 44 px); the press expands the book in place — `TownHallInfluence` with
   `showTax={false}` (TAX INFO STAYS OFF: the owner, 2026-10-30, *"no need market info. tax
   info. influence yes…"* — unchanged, not ours to supersede), its rows compressed so the panel fits — and a second press folds it. The game's "enough
   with folding" law does not apply to this control: the owner asked for it. The Investors row and
   its side drawer are unchanged.
4. **THE BASKET IS NOT AN OVERLAY (owner: "MARKET- BASKET? WTF IS THIS POPPING UP BLOCKING THE
   WHOLE SCREEN?").** `CityFace.tsx`: the Market's Basket row opens a compact summary IN THE PANEL
   — the staged line count, the served total (`cmd.preview_basket` via `useManifestPreview`), the
   hold bar, and one row to the board — never a page and never the `ManifestPanel` Tray (the thing
   that popped up). The board itself (the quay ledger and its trays) opens only from an explicit
   row, as the one `DetailPage`. The specs prove no `[data-detail-page]`, no `basket-panel`, and
   that every one of the six doors is still the element under its own centre after the Basket press.
5. **PACKED FACES (owner: "INN, HORIZONTAL SPACE IS TOO LARGE. MAKE IT COMPACT").** Every building
   face is a compact panel of rows; the Inn is Crew · Captains here (its whole face opened as a
   page); each opened page's content sits in one bounded column (`max-w-2xl`) so a wide glass never
   spreads a handful of rows across the glass. Measured: the inn panel fits at 390 (its content
   height ≤ the panel's) and at 1280; the inn page's content column is 672 px wide inside the page,
   where the unpacked face spanned the full body.
6. **THE YELLOW RING IS REMOVED (owner: "the yellow circle means the one that circle around a
   building. i don't get what that is").** Found on the served build, not guessed: the only
   enclosing circle on the plan was the selection ring around the open place —
   `data-testid="city-selected"`, an accent-stroke circle of **r 19.5 viewBox units**, computed
   color **rgb(138, 96, 17)** (the gold accent), rendered **29×29 px at 390** and **101×101 px at
   1280**. Removed entirely with its `selected` plumbing; nothing replaces it (the pressed tile
   says which place is open). The scene keeps its glyphs: hall 9 · market 13 · storage 7 · forge 5 ·
   port 23 · inn 5 children; scene nodes 393 → **391** (< 400). Note: the instruction's cited code
   (`b.ring`, enclosing circles at r 4.8/7.5/4.6) does not exist in this tree — no house is drawn
   as a hollow ring — so nothing else was removed; the plate border, the smoke/plaza ornaments and
   the port's drawn piers/hulls/cranes stay.
7. **A LOADING METER OF REAL STEPS (owner: "show percentage of its loading time").** One shared
   primitive, `src/components/ui/LoadMeter.tsx` (steps in, completed/total out, weighted where a
   caller knows a size; no timer, no easing; gone the instant every step is done), and the world
   store now records its boot's three REAL completions (`boot` 1 = the served snapshot/bundle, 2 =
   the sea raster, 3 = the first beat read). The City composes **World · Sea · Fleets · Hall**: the
   gate shows the four-step scale while the world opens, and the same scale stays up until the
   hall's own served read lands. Map is NOT touched here — the primitive is generic for its own
   slice.
8. **One rail, one dictionary (rows 1–2).** #426 already rendered the shell's `NavBar`; this PR
   deletes the four unused rail words from the city dictionary.

## The proof

- **`tests/city.audit.spec.ts` — NEW, permanent (9 tests).**
  @390×844 and @1280×800, `city audit @N: the one rail, the frame that never moves, the plan that
  stays`: the rail is the five shell cells (56 px); all six presses leave the frame box-for-box
  identical; the city image is visible for every press and the panel stands right of it; the six
  split rect sets are identical; the scene has no enclosing circle (the ring is gone), no house is
  a stroke-only ring, every landmark keeps its glyphs, scene nodes < 400; every visible control
  ≥ 44×44.
  `city audit @N: every building panel is a compact screen with no hall words, and its rows open
  pages`: all five panels fit (root and inner scroller), no non-hall face prints Population · Gold
  · Status · Relationship · Employees, every row (≤ 2 words) opens a `DetailPage` that does not
  scroll at its root and leaves the frame unmoved.
  `city audit @390×568: the hall — Influence folded and expanded — shows everything without
  scrolling`: the 44-px fold row, no scroll collapsed OR expanded, the five figures present with
  values, the frame unmoved, page 568/568.
  `city audit @320×568: …`: collapsed fits and the expanded book scrolls inside the panel — printed
  — while the page stays flat in both states.
  `city audit: the Market Basket opens in the panel — no page, no tray, nothing over the doors`.
  `city audit: the Forge product controls carry the product name, never the recipe`.
  `city audit: the loading meter is measured work — monotonic, step-bound, gone only at ready`:
  cold context per size, network throttled, the percentage sampled from commit to ready — it only
  rises, only takes the four steps' values, disappears only when the world is ready AND the hall
  figures are on the glass, and the load's long tasks stay under 100 ms.
- **`tests/city.page.spec.ts`** — updated to the new shape (the plan always visible on presses; the
  hall fold for the influence book; the five figures read from the hall block; the Forge tier page
  and the Market row page; the 320 hall held to no scroll).
- **`tests/onepage.spec.ts`** — unchanged: the City route still has no summary row at rest.

## Local verification (this machine, 2026-10-31)

Headless chromium against the served local-mode build (`vite preview` on **4311**, `localhost`); the
build is the merged `ac2865f1` + this PR, build id `ac2865f+2026-10-31T…` (`version.json`). The
permanent spec is run in chunked invocations (the same tests the suite runs; the earlier full-suite
invocation stalled in the runner before its browser launched — a process-layer issue, not an
assertion).

- **`tests/city.audit.spec.ts`**
  - `city audit @390 / @1280: the one rail, the frame that never moves, the plan that stays` —
    **PASS (6.3 s / 6.4 s)**: the rail is the five shell cells (56 px each); the frame (header, six
    tiles, the earnings line, the rail) is box-identical across all six presses; the scene is
    **391 nodes / 89 circles** with **no enclosing circle** (no `city-selected`, no stroke-only
    ring; the marks keep their glyphs — hall 9 · market 13 · storage 7 · forge 5 · port 23 ·
    inn 5) and stays under the 400-node cap; **one split for all six** — at 390×844 the image is
    179×647 at x16 with the panel 171×647 at x203, at 1280×800 the image is 624×603 with the panel
    616×603, identical across every press; every visible control is ≥ 44×44; no page scroll.
  - `city audit @390 / @1280: every building panel is a compact screen with no hall words, and its
    rows open pages` — **PASS (7.8 s / 7.9 s)**: the market/storage/forge/port/inn roots and their
    scrollers are **647/647 at 390** and **603/603 at 1280**; no non-hall face prints Population ·
    Gold · Status · Relationship · Employees; every row (Buy · Sell · Requests, Tier N, Build ·
    Repair, Crew · Captains here) opens a `DetailPage` whose root does not scroll, leaves the frame
    unmoved, and carries a ≥ 44-px back control.
  - `city audit @390×568: the hall — Influence folded and expanded — shows everything without
    scrolling` — **PASS (5.4 s)**: the hall scroller is **326/326 folded AND expanded** (no scroll
    in either state), the Influence row is ≥ 44 px, the five figures are all present with values
    (Population "≈ 160,000"), the frame is unmoved and the page is 568/568 flat.
  - `city audit @320×568: the hall says what fits and what scrolls, and the page never moves` —
    **PASS (5.3 s)**: collapsed **278/278**; the expanded book is **289/278** — it scrolls 11 px
    inside the panel (stated) — while the page stays flat in both states; the five figures are
    present and every control is ≥ 44 px.
  - `city audit: the Market Basket opens in the panel — no page, no tray, nothing over the doors` —
    **PASS (5.2 s)** at 390: the Basket press shows the in-panel summary (an empty basket prints
    "Basket empty." beside the hold bar), opens no `DetailPage` and mounts no `basket-panel`; every
    one of the six doors is still the element under its own centre; the frame does not move.
  - `city audit: the Forge product controls carry the product name, never the recipe` —
    **PASS (5.1 s)**: 180 product controls, none carries the recipe glue (`·`); the seven proper
    names over two tokens are declared ("Attar of Roses", "Dried & Salt Fish", "Ink & Brushes",
    "Raisins & Currants", "Russia Hemp Cloth", "Says & Serges", "Silverware & Plate"); the tray a
    product opens carries that product's name.
  - `city audit: the loading meter is measured work — monotonic, step-bound, gone only at ready` —
    **PASS (49.0 s) at 390 and 1280**: every sample was one of the four step values
    (0 · 25 · 50 · 75) and non-decreasing; the steps run world → sea → fleets → hall; the meter
    was gone only when the world was ready AND the hall figures were on the glass; 4 percentage
    writes for the 4 steps (mounts and completions only — no timer). The load's own long tasks
    (the cold world-image restore measured at 1.88 s in #426) are recorded and reported, not
    blamed on the meter.
- **`tests/city.page.spec.ts` — PASS (20.9 s)**: entry from the desk, the six-tile frame, the hall
  **602/602 at 390** (no scroll) and **278/278 at 320** (the old "it scrolls inside itself" caveat
  is retired), no page scroll at 390/320/360/1280/1440, the Market's Buy page and the Forge's tier
  page driven, scene 391 nodes.
- **`tests/consistency.spec.ts` (the merged #427 audit's permanent net, NOT edited here) — its two
  city tests PASS (8.6 s + 13.4 s, 25.5 s total)**: the City rail equals the shell rail cell for
  cell, and the HQ press-stability/geometry proof holds at 390 and 320 — that proof reads a
  `city-summary` block, which is why the frame keeps ONE earnings line of its own (your purse, a
  fact the hall does not show) rather than nothing at all.
- **`tests/onepage.spec.ts` (unchanged) — PASS 2/2 (1.2 min)**: both walks (@390×844 and @1280×800)
  are green; on the City route the document reads 390×844 / 390×844 and 1280×800 / 1280×800 with
  sheet none and Y 0.
