# 2026-11-01 — the HQ on a phone: every face legible at 320 / 390, and one law that catches an overlap

**Branch** `city-mobile` · client-only (no migration) · **start only after** `fix-main-red-1101` has merged (it edits the same shared
Row and the Market face): cut the work from the then-current `origin/main`. Review `origin/city-repoint` (DeepSeek WIP, one shared
Row re-point + a rewritten density proof) and take only what the fix needs — never merge it wholesale.

## 1. The owner's words that bind this (docs/OWNER_REQUESTS.md)
- 247: *"you know that this game is also for mobile right?"* — the HQ split (city view left, the page right) is the same on a phone.
- 251: *"pack them up, make it concise and simple so that it is easy to see in one eye without scrolling down."*
- 255: *"the market and rest of the tab (market, storage, forge etc), the same screen dividends (city view, then right side the info)
  should stay the same for all"* · *"no info duplicate"* · *"inn, horizontal space is too large, make it compact"*.
- 258/260: compact EVERYWHERE; label and figure close (the 8 px hug, #439/#440) — "with full detail".
- 201/241: no text is cut without a way to read it. 247-row law: a pressed control selects; it never re-flows the frame.
- Do NOT change: the split, the six tiles, the plan, the rail, the words of other faces, any data. Fix by the ONE shared primitive, not
  per-face patches (NO SPAGHETTI).

## 2. What is wrong — seen headless (local-mode build, fresh canary world so figures are 0, Korean UI), 2026-11-01
Screenshots (read them with the image reader): `C:\Users\gkwng\AppData\Local\Temp\claude\C--Users-gkwng\053e89dc-55cd-4bfd-83d7-ad778f295a98\scratchpad\shots\`
(`hq-phone/wide/small.png`, `phone-<face>.png`, `wide-<face>.png`; made by `…\scratchpad\shoot-hq.mjs <baseUrl> <outDir>` — reuse it).
The 1280×800 desktop view is good. The 390×844 phone view is not — the right column is ~175 px wide and nothing in it adapts:
1. **Market face (phone-market.png):** every good name wraps ONE CHARACTER PER LINE ("모/직/물"); the BUY and SELL tiles overlap each
   other and the name ("80.2" collides with "74.0"); the stock label "재고" is split and overlapped by "6,700 / 6,700 개"; "시세 폭" wraps;
   the chart's x-axis labels overlap ("−0.5시간" over "−0.3시간 지금"). This is the cause of the red `market.desk.spec.ts:34` (a
   disabled tile's figure sits over the first button) — the fix for that spec and this one is the same root.
2. **Warehouse (phone-storage.png):** the label "공간" wraps to "공/간" beside "0 / 750 tons" and is overlapped by it.
3. **Inn (phone-inn.png):** a row reads "이곳…" — cut off, with no way to read it (breaks 201/241).
4. Hall/Port/Forge faces are fine at 390; the plan is a ~170 px square in a 650 px column (calm, not a defect to "fix" by restructuring).
5. At 320 the tiles wrap to two rows (fine) — re-check every face there too.

## 3. Root cause to VERIFY first (read the code, then reproduce in the browser — do not assume)
The shared `Row` / `SummaryRow` (`src/components/ui/Row.tsx`, `Detail.tsx`) after #440 ("the figure sits beside its label, HUG"):
the label is allowed to shrink (flex-shrink / min-width 0) so a wide figure steals its width; and the Market row
(`src/features/city/MarketFace.tsx`) is a one-line [name+stock | BUY tile | SELL tile] built for the wide column. Confirm in the
DOM which box shrinks and which overflows (`getBoundingClientRect` of the label, the figure and the tiles at 390).

## 4. The change (smallest correct, one authority)
1. In the ONE Row primitive: the label never shrinks below its own text (`whitespace-nowrap`, `shrink-0`); when label + figure do not
   fit the row, the FIGURE moves under the label (still one Row, still ≥ 44 px pitch); a figure that must be clipped carries
   press-to-read (title / the existing detail page). No second row primitive.
2. Market row: below ~300 px of column width the name is one line (ellipsis + full name on press) and the BUY | SELL tiles sit
   as a 2-column grid UNDER it; at wider widths it is exactly what it is now (the desktop look must not change).
3. The chart's axis labels: never overlap (draw the first and last tick only when the axis is narrower than the labels need).
4. The Inn row: the full word shows (wrap or the shorter plain word, EN + KO through `src/lib/i18n/dict/*`).
5. NO change to the split, the tiles, the plan, the rail, the stats, any data or any other face's content.

## 5. The law that keeps it fixed (one new spec, `tests/city.phone.spec.ts`; reuse `appReady.fixture.ts`)
At 320×640, 390×844 and 1280×800, press each of the six tiles (Hall, Market, Warehouse, Forge, Port, Inn) and, inside the right
panel, assert: (a) no two sibling boxes (tiles, figures, labels) overlap by more than 2 px² area; (b) no text of 3+ characters is
laid out narrower than 1.4 × its font size (the one-character-per-line detector); (c) no element with `text-overflow: ellipsis`
is truncated without a `title`/press-to-read; (d) the document never scrolls sideways; (e) the frame (header, tile grid, rail)
does not move between presses (already in `city.density.spec.ts` — do not duplicate, import its numbers if needed). The known-red
`consistency.spec.ts:379/568` and `market.desk.spec.ts:34` must pass for the same reason, not by a loosened floor.

## 6. Gates (lean) and finishing
tsc · eslint on touched files · `npm run build` (local mode) · the specs you touched plus `city.density`, `align`, `consistency`,
`market.desk`, `desk.inplace` (they pass on main and must stay green; read the skipped count — `PLAYWRIGHT_BASE_URL` needs the
trailing slash). Headless only; `vite preview` on an explicit unusual port at `localhost`. Attach BEFORE/AFTER screenshots of the
Market, Warehouse and Inn faces at 390 (file paths in the report). Push once, client-only PR, `gh pr merge <n> --squash --auto`,
then read `gh pr checks`. Bookkeeping: an owner-row line (state only) and the top line of `docs/WORK_QUEUE.md`. Commit trailer
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
