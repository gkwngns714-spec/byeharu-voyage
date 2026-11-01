# THE CITY'S WORDS AND FIGURES SIT TOGETHER — the owner's compaction

2026-11-01. Owner, verbatim:

> *"so is the same in command hq, city hall. there are empty spaces between words and numbers
> horizontally which is in effective. make it so that htey are closer, more compact with full detail,
> without having to fold anything unless it is necessary"*

The scope of this slice: the HQ page (`src/features/city/**`) — the hall panel, the frame's own
rows, and the faces. The shared row primitives (`src/components/ui/Detail.tsx`, `Row.tsx`) belong to
another writer's in-flight slice and are NOT edited here; the rows that ride them are measured and
printed by the proof, and are held by that slice.

## BEFORE (origin/main f5976c61, served build, the same spec)

Label→figure horizontal gap, px (a Range from the label's visible edge to the figure's first glyph),
and each row's height:

| row group | 390×568 gap | h | 1280×800 gap | h |
|---|---|---|---|---|
| hall · Influence (fold row) | 57.7 | 44 | 502.7 | 44 |
| hall · Population | 24.5\* | 22 | 441.2 | 22 |
| hall · Gold | 75.7 | 22 | 520.7 | 22 |
| hall · Status | 92.1 | 22 | 537.1 | 22 |
| hall · Relationship | 8.1 | 20 | 453.1 | 20 |
| hall · Employees | 66.0 | 22 | 511.0 | 22 |
| hall · Investors | 58.4 | 44 | 503.4 | 44 |
| frame · Your earnings | 187.8 | 22 | 1,077.8 | 22 |
| market face · Basket row | 52.1 | 52 | 497.1 | 52 |
| storage face · Space row | 17.8 | 136 | 429.3 | 52 |
| forge face · tier rows | 26.3 / 30.9 / 30.7 | 44 | 471.3 / 475.9 / 475.7 | 44 |
| port face · Build / Repair | 60.3 / 21.7 | 44 | 505.3 / 466.7 | 44 |
| inn face · Crew / Captains | 16.3 / 33.2 | 44 | 461.3 / 420.8 | 44 |
| market ledger rows (shared) | −21 … −21.6 | 158–350 | 221.3–291 | 79 |

\* Population's label clips at 390 (its cell is 49 px and the figure is 82 px): the before probe
measured from its last glyph, 24.5 px; its visible edge (the ellipsis) stood 8 px from the figure in
the old layout too. Its true offender was the wide glass: 441.2 px at 1280. The proof now measures a
clipped cell to its visible edge — the line the eye reads.

## THE CHANGE (city files only)

- `src/features/city/CityHallPanel.tsx` — the five `FigureLine`s lose `justify-between`: the label
  and its figure stand 8 px apart (`gap-2`), and a clipped label carries its full text as `title`.
  The Influence fold row and the Investors row put the figure beside the word and the chevron keeps
  the row's right edge (`ml-auto`); both keep `min-h-11`.
- `src/features/city/CityScreen.tsx` — the frame's one earnings line: the purse stands 8 px behind
  "Your earnings" instead of at the far edge of the whole frame.
- `src/features/city/MarketFace.tsx` — the basket summary line (count and total beside `Basket`) and
  the open request's pay line (the escrow beside `Pay`, the Cancel button at the row's edge).
- `src/features/city/CityFace.tsx` — the faces' `Row` lines drop from `--spacing-row` (52 px = the
  44-px reach floor + 8 pt rhythm) to the 44-px floor via one city-scoped container class; the
  shared primitive is untouched, and a row whose content is taller than 44 still grows.

No content was removed, nothing was duplicated from the hall, and no new fold was added.

## AFTER (branch `city-compact`, same spec, served build)

| row group | 390×568 gap | h | 1280×800 gap | h |
|---|---|---|---|---|
| hall · Influence | **8** | 44 | **8** | 44 |
| hall · Population | **8** | 22 | **8** | 22 |
| hall · Gold / Status / Relationship / Employees | **8** each | 20–22 | **8** each | 20–22 |
| hall · Investors | **8** | 44 | **8** | 44 |
| frame · Your earnings | **8** | 22 | **8** | 22 |
| market · Basket line | **8** | 44 | **8** | 44 |
| market · Basket row (Row) | 52.1 | **44** | 497.1\*\* | **44** |
| storage · Space row | 17.8 | **136** | 429.3\*\* | **44** |

\*\* The Row-based figures that still stand far from their label inside a Row ride `Row.tsx`'s
shared columns; that hug is the primitive writer's slice (uncommitted at push time). The City's own
rows all stand at 8 px.

Fit and the frame, unchanged by the compaction:

- Hall panel 371 px at 390 (`city-hall-scroll` 326/326) and 603 px at 1280 (558/558) — no scroll in
  either state; the panel's height did not move.
- The document never scrolls: 390/390 wide × 568/568 tall, 1280/1280 × 800/800.
- The frame's boxes are identical across all six presses at both glasses: header [0,0,390,54] /
  [0,0,1280,54], six-tile grid [58,16,358,44] / [58,16,1248,44], rail [511,0,390,57] /
  [743,0,1280,57].
- Content: the five hall figure lines, the Forge's three tiers (180 / 96 / 11 products), the Port's
  two rows, the Inn's two rows, the Market's ledger rows and the Storage face are all still drawn.

## WHAT REMAINS FOLDED, AND WHY

The owner's law is "no folding unless it is necessary". Nothing in this slice folds anything, and
the two folds the owner ordered stay exactly as ordered:

- **The hall's Influence fold** — owner, 2026-10-31: *"MAKE INFLUENCE FOLDABLE…"* (row 255). It is
  the one sanctioned in-place fold and was not touched.
- **The Investors drawer** — the same instruction: *"investors - tappable where when tapped, a list
  slides to the right where you can close."*

The faces' summary rows still open their full-detail pages, and that is necessary, not cosmetic:
the Forge's tier 1 holds 180 products (tier 2: 96, tier 3: 11 — measured on this build), the yard
and shipwright are whole workspaces, the market board is the trade workspace, and the inn's crew and
captain lists exceed the panel's height. Bringing any of them onto the face would force the panel to
scroll or overflow — the owner's own page law (row 248) is the compact row → full page. Nothing was
tucked away to buy this density; the rows just stopped spreading.

## PROOF

- `tests/city.density.spec.ts` (new, fail-before → pass-after): walks the hall, all five building
  faces and the basket at 390×568 and 1280×800; asserts every City-owned gap ≤ 11 px, every
  pressable row ≥ 44 px, the document flat in both axes, the hall flat, the frame identical across
  presses, and the content present. Before: FAIL on Influence 57.7 (the first compactness
  assertion); after: PASS 17.0 s.
- `ALIGN_ONLY=City tests/align.spec.ts`: 0 defects at 1280 and 390 — the alignment law still holds.
- `tests/city.page.spec.ts`, `tests/city.audit.spec.ts`, `tests/market.desk.spec.ts`: 13/13 passed
  (3.4 min), including the hall's both fold states at 390 and 320, the in-panel basket proof, the
  forge labels and the loading meter.
- `tsc -b`, `eslint .`, `npm run build` clean.

## MEASURED AND NOT FIXED HERE (reported, not hidden)

- **The shared primitives' face rows.** Forge tiers, Port, Inn and the trade ledger still stand at
  the far edge inside their `SummaryRow`/`Row` rows: 16.3–60.3 px at 390, 413–505 px at 1280. Their
  hug is the other writer's uncommitted `Detail.tsx`/`Row.tsx` slice (wt-density); this PR neither
  edits nor asserts them, and the density spec prints their numbers on every run so that slice can
  pin them.
- **The Market ledger in the 171-px panel at 390.** The BUY/SELL ledger's `TradeRow`s draw 158–350-px
  rows and its name column collapses (the two 44-px price cells cannot fit beside a name in the
  panel); the text measures overlapping. This is a #433 composition issue, unchanged by this slice
  and outside the gap/pitch instruction — left for its own slice, stated here with numbers.
