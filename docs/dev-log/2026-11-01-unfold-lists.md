# 2026-11-01 — UNFOLD: Stats, Compendium, Ledger, Rank, Routes show their content on the face

**Branch** one per screen (`unfold-stats`, `unfold-codex`, …), client-only PRs, in this order: STATS → COMPENDIUM → LEDGER → RANK → ROUTES.
Start each from the then-current `origin/main` AFTER `fix-main-red-1101` has merged (it changes the shared Row). Laws: `2026-11-01-ui-unfold.md`
(U1–U8, the method, the budget table) — read it first. Owner: row 260 *"everything is folded in stats this is soo wrong. make it compact showing
everything possible"* and 2026-11-01 *"make things unfolded, minimize scrolling, everything compact with full info"*.

## 1. What is wrong — seen headless at 390×844 (canary world; screenshots in
`C:\Users\gkwng\AppData\Local\Temp\claude\C--Users-gkwng\053e89dc-55cd-4bfd-83d7-ad778f295a98\scratchpad\shots\`: `stats-phone/wide`, `compendium-phone`,
`ledger-phone`, `rank-phone`, `routes-phone`, `you-phone`, `profile-phone`, `fleets-phone`, `map-phone`)
- **Every list screen is ONE folded 44-px row with ~75 % of the screen empty under it:** Compendium `교역품 629 열기 >`, Ledger `기록 1 열기 >`,
  Rank `선장 10 열기 >`, Routes `항로 0 열기 >`. The 629 goods, the ledger, the ranking are all behind a press, on a screen that has the whole
  height free. That is the U1 defect in its purest form.
- **Stats** (`src/features/stats/*`): the Overview face is five collapsed `SummaryRow`s (`세계의 돈 … 열기`, two rows both titled `돈의 흐름`,
  `경제 감시`, `종류별`) and the other four faces (시세 prices, 도시 cities, 상인 merchants, 나 me) hold 4–5 summary rows + 7–9 detail pages each
  (`Overview` 4/8, `Markets` 4/7, `Merchants` 5/9, `Cities` 3/5). The live "now" band overlaps at 390 (`항해 중 0` sits over the previous
  column's coin icon). Two rows with the same title is a duplicate-info defect (U4).
- Cosmetic/overlap elsewhere at 390: Profile's logout row — the button covers its own sentence, which is also far too long (plain short words);
  You (`나`) has wrapping labels. Fleets and Map are fine on the canary world.
- The pattern lives in `src/components/ui/Detail.tsx` (`SummaryRow` → `DetailPage`) and is used per screen (counts above).

## 2. The change — one inline pattern, used by all five screens
1. **A design-system inline list panel** (name it; ONE component in `src/components/ui`, named second callers = the other four screens): a header
   row (title, count, the sort/filter chips already in use), a body that scrolls INSIDE the panel (fixed header; cut edge visible; the page never
   scrolls), rows are the shared `Row` (label→figure hug, 44 px only where pressable). Pressing a ROW opens that item's detail page (kept, with a
   way back); the list itself is never behind a press. The panel takes the height the screen leaves free (flex-1), so on a tall phone it shows
   10+ rows, not one.
2. **Charts and figures inline (Stats):** each face is a block stack that fits 390×844 with the figures NEXT to their small chart; a chart press
   opens the large chart page (progressive detail), but the figures and the shape are visible without any press. Keep the live reads exactly as
   they are (every second; owner: "nothing regarding time"). Nothing is removed (U3): before editing, list every figure/test id of the old
   face; the spec asserts each is still present.
3. **Stats faces, suggested budget (390×844; measure the real content height first):** `지금` band 1 row of 4 cells (fix the overlap) · world money
   as ONE stacked bar + its four figures · the flow chart with its four figures · the economy watch figures · the money log by kind as an inline
   list panel taking the remaining height. Prices: the 629-good list inline with sort chips (Class/Name/Price/Trend as they exist); Cities and
   Merchants likewise. Decide per face with the budget table in the dev-log BEFORE code (U2).
4. DeepSeek's `origin/stats-unfold` ("WIP: stats unfold — charts at mini scale, figures on the face"; it also DELETES `Watch.tsx`) may be mined
   for ideas, never merged: re-derive from the laws, and confirm every old figure survives (the Watch figures must stay — move them, don't drop them).
5. Do NOT edit the shared `Row` (the red-fix PR owns it) beyond what you strictly need; if you need a Row change, make it small and additive and say so.

## 3. Proof (each PR)
`tests/<screen>.unfold.spec.ts` (or extend `consistency.spec.ts`'s walk): at 390×844 AND 320×640 — page scroll = 0 on every face; the list panel is
visible with ≥ N rows without any press (N per screen, stated); no sibling overlap; no cut text without press-to-read; every old figure still
present; a row press opens its detail and back returns; the live band still refreshes every second (the existing stats specs stay green).
Existing green specs stay green: `align`, `consistency`, `city.density`, `duplication`, `stats.*`, `primitives.geometry`, `onepage` (if a spec
encodes the OLD folded structure — e.g. `onepage` — it is rewritten to the new law with the reason in the commit, never loosened silently).

## 4. Finishing
Client-only PR → `gh pr merge <n> --squash --auto`, then read `gh pr checks` (ALL) and main's own Acceptance on the merge commit (it is the net;
`acceptance` is not a required check). Do NOT edit `docs/WORK_QUEUE.md`. Screenshots BEFORE/AFTER (paths) + the budget table in the report.
Headless only; `vite preview` on an explicit unusual port at `localhost`; `PLAYWRIGHT_BASE_URL` with the trailing slash; read the skipped count.
Trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
