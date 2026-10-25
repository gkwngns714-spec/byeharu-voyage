# 2026-10-25 — Every list lines up (owner rows 196, 198, 199, 201)

The owner, 2026-10-25:

- 196 *"at stats, market, risers fallers and all doesn't fit. it is not in the same line. fix this."*
- 198 *"same for stats, best and worst part, not alligned. review all the game and make it allign on the things that aren't"*
- 199 *"on stats, the chart, the gold overlapps with the chart line. fix this"*
- 201 *"some sentences such as 'the longests stretch a...', can't read, and cant find a way to read long sentences that are cut in this game. fix this too"*

## How it was measured

`tests/align.spec.ts`, headless, against `vite preview` of a production build (local PGlite world, no
credentials), at 1280×800 and 390×844. It walks every tab and sub-tab: Command (Markets, City,
Invest, Profit), the City's every building face, Fleets, Map with Lisbon's panel open, Stats (Overview,
Markets, Cities, Merchants, Me), Ledger (4 faces), Rank (2), Routes (3), Compendium (4), You, Profile
and the `/ui` gallery. For every list it measures:

| check | the rule |
|---|---|
| LINE | the first line of text in each cell of a row has its vertical centre within 2 px of the others |
| COLUMN | sibling rows of one shape start each cell at the same x (end, for a right-set figure), within 2 px; `[data-col]` cells and `[data-track]` bars likewise |
| SPILL | no cell runs past its row |
| FIGURE | no figure breaks across two lines |
| PAIR | sections standing side by side start their headings on one line |
| CHART | no text box intersects a chart's plot rectangle |
| CUT | any element whose text is cut (overflow with ellipsis, nowrap clip, line-clamp) carries its full text |

Not walked: COMMAND › Plans (`src/features/command/plans/*`, owned by the Command redesign; it moves onto
`Row`'s columns there) and the map's own labels (another PR).

## The audit, before (main at a38bfa6): 697 findings at 1280, 969 at 390

### Misaligned lists — 12

| screen | list | defect |
|---|---|---|
| Stats › Markets | every good (`stats-good`) | the price/move stack centred on name + facts block: first lines 20.5 px apart, both widths |
| Stats › Markets | Risers · Fallers · Most traded | the three sections start 16 px apart (1280): only the first was a "first child", `mt-0 first:mt-0` lost to the section's own `mt-6` |
| Stats › Merchants | Best day · Worst day | same, 16 px (1280) |
| Stats › Markets / Merchants / Me | ranked bars (`RankBars`) | the figure centred on label + bar, half a line below the name; each bar as long as its own row's label column, so no two bars start or end together |
| Stats › Cities | locked harbours (`stats-city-locked`) | first lines 14 px apart |
| Rank › Captains, Countries | `rank` rows | 8.5 px |
| Command › Invest, City › Town | Town Hall holder / influence | 3.5 px; the influence bar's track varied with its figure |
| City › Inn | crew rows | 4 px |
| You | level tracks | 6.5 px |
| City › Trade, Command › City, Map › Lisbon | `trade-row` | the two `ActCell` price boxes centred their content, so a cell with a reason line stood 12 px higher than its neighbour: 10 px at 390 |
| Stats (Overview, Merchants, City detail) | `SeriesChart` (row 199) | the high/low figures were laid over the plot's right edge and the hover reading over its top-left: the line ran through the gold figures. The fresh world has one count, so no line is drawn there; measured on the gallery's chart |
| `/ui` gallery | stacked `Bar`s | tracks end 7–18 px apart (each track as long as its figure left it) |

A 13th finding, Compendium › Nations "COLUMN drift", was the measure's own error: it compared the
left edges of right-set figures. Fixed in the measure (a right-set cell is held at its end).

### Cut text with no way to read it (row 201) — 8 lists

City › Craft (fittings: names AND sentences — "Weather-holding, and a faster turnaround"), Compendium ›
Ships, Captains, Goods (tile names and their fact lines), City › Skills, City › Build (hull names),
Command › Markets (watch-row facts; the ticket's reach sentence "too far to sail in one go: your
navigato…", the owner's "longest stretch" family), City › Inn (guest names).

## Root cause

**Spaghetti: no row primitive owned the line.** `Row` was a flex box that centred its value against
everything in the label column, including the bar or caption the label carried, so the figure sat
half a line below the name; the bar lived inside the label column, so its length was the row's
leftover width. Multi-figure rows stacked their figures in a hand-rolled `w-24` box. Sections side by
side were patched three ways (a `mt-0 first:mt-0` that lost the cascade, a `div` around each section,
nothing). Text cutting was 49 hand-written `truncate`/`line-clamp` sites with no full-text path.

## The fix: one authority each

- **`Row`** (`src/components/ui/Row.tsx`) is a grid: line 1 holds mark · label · value in fixed
  tracks, every cell's first line in one 24 px line box (`.bv-row-line`, `src/index.css`; a lone
  control is centred on the line); line 2 (`children`) spans under label and value, so every bar of a
  list shares one track. **`Col` / `Cols`** are the fixed column scale (xs 40, sm 64, md 80, lg 112 px;
  `phone="hide"` stands a column down below `sm`). `Bar` takes `figureCol` in a stack. A row whose
  value is taller than a line (a pair of `ActCell`s: trade, storage, requests) sets `under="label"`:
  line 2 stands under the label only and the value spans both lines, so the row is as tall as its
  value, not the sum (with line 2 under both, a trade row measured 100 px and layout.spec's "three priced goods above
  the fold" went red; with `under="label"` it passes again).
- **`SectionColumns`** (`src/components/ui/Sheet.tsx`) is the one way sections stand side by side;
  Markets, Merchants and the fleet fold moved onto it, their patches deleted.
- **`SeriesChart`** gives its figures their own space: the reading in a header line above the plot
  (always one line, so a hover moves nothing), high/low in a column to its right.
- **`Clip`** (`src/components/ui/Clip.tsx`) is the only way text may be cut, and only a short name:
  a `title` for hover, a press on a touch glass opens the full name as a layer over the cell (no
  re-flow). Every sentence site moved to wrapping. `ActCell` top-aligns its content.
- Hand-rolled rows deleted: Stats good row, Profit lines, the trade books, Town Hall influence.

## After

`tests/align.spec.ts`: **0 findings at 1280, 0 at 390** (2 passed). Can it fail? Broken on purpose
(SectionColumns' margin reset removed, the chart's header line collapsed onto the plot, Clip's title
removed, the row's line box removed): PAIR, CHART, CUT and LINE all went red on the gallery, then put
back. Locally on this PC, six unit tests (countUp, seriesChart, route.stopface, insurance) fail the
same way on main and on this branch: Node reads this machine's `ko-KR` as the language. It is selected by `scripts/ci/select-specs.mjs` rule L (any face) and rule A (the design system).
