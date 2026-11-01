# 2026-11-01 — 0294: every trade good carries a PREMIUM CLASS the player can see at a glance

**Branch** `good-class` · server + client in ONE PR (a served field with no reader, or a reader with no field, is half a slice) ·
migration `supabase/migrations/20260818000294_a_good_has_a_class.sql`. **The number moved twice.** The design said 0293 (0290, 0291,
0292 queued ahead); the coordinator's queue of 2026-11-02 is: 0290 LIVE, 0291 the laps' autovacuum (PR #443), 0292 the port_goods
rewrite, 0293 the Stats period fix (design only) — so this file is **0294, the last migration**, and it deploys after them (the gap
0291–0293 in this branch is deliberate: `check-versions` allows gaps and the chain applies in filename order; the file AND its `0294`
self-assert strings are renumbered if the order moves again). Deploy by the coordinator (`~/bin/bv-deploy.sh <pr>`), never by the author.

## 1. The owner's words
2026-11-01: *"new trade goods - distinctive class showing what is more premium."* ("go", no permission questions.) Read with rows 37/52/67
(a real, regional, sorted catalogue; "wtf is foodstuff") and 177 (the rarity word in a third place). Decided by default (owner may
reverse): the class is a FIVE-step PREMIUM scale by a good's value, drawn so a premium good is unmistakable in every list a good appears in.

## 2. What exists — do not duplicate it (as found, 2026-11-01, head 0290)
- `public.good_rarity(id)` (0032/0051) = how SCARCE a good is (producer count: common / uncommon / rare / exotic), served as `rarity`; drawn
  by `RarityMark` (a 12-px glyph + a colour token). `goods.tier` (0..3) = PRODUCTION tier (raw / made in the Forge, 0280/0281) — NOT premium.
  `goods.base_value numeric(10,2)` (4 … 3,300 after 0285's ×5) is the value; `data/goods.json` carries an authored `valueBand` 1–5 that
  prod's `goods` table does NOT have. Three ideas on one row — scarcity, production tier, PREMIUM (value): this slice adds only the last, as
  its own concept with its own mark, and never folds it into rarity.
- **THE SERVING POINTS — the design was wrong: there are THREE, not two.** Grepping every `'rarity'` in the LIVE functions of
  public/cmd/world/voyage (one pure SELECT on prod) finds `world.snapshot()`, `world.market(uuid)` AND `world.contracts(uuid)` — the request
  board, whose rows (`TradeRequest.rarity`) `RequestBoard` draws. All three are re-cut. `world.goods_forge`, the cargo lines and the storage
  lines carry a good by CODE and never served rarity either: the client reads their class from the catalogue by code (`goodByCode[code].class`),
  the lookup it already makes for their name and category — nothing is computed.
- `world.market(uuid)` and `world.contracts(uuid)` are **VOLATILE** (their drift / board catch-up writes), so neither is ever called on prod from
  here; the self-assert reads them inside rolled-back sub-transactions. `world.snapshot()` is STABLE.

## 3. The design — AS BUILT, and where it differs from the first draft
| | first draft | built | why |
|---|---|---|---|
| serving points | two (snapshot, market) | **three** (+ `world.contracts`) | found by the grep the draft itself asked for |
| the leaf | one `good_class(value)` reading the knob per call | **a reader `good_class_edges()`, a pure rule `good_class(value, edges)`, and the leaf `good_class(value)` over both** | measured: the leaf per good costs ~8 ms over the snapshot's 629 goods (the knob read 629 times); the rule over edges read ONCE costs ~1 ms. The snapshot hands the rule its edges through an uncorrelated sub-select (read once per statement); the market and the board (a few rows) ask the leaf. One rule, one reader. |
| class 4's English word | "Premium" | **"superior"** | docs/WORDS.md keeps *premium* for what a request pays over the market (`Premium +200 🪙`); the Fulfil tray shows both. Korean keeps 프리미엄 (its request word is 웃돈). The words: basic · standard · fine · superior · luxury / 기본 · 일반 · 고급 · 프리미엄 · 최고급. A row was added to WORDS.md. |
| the compact mark | the meter beside the rarity glyph | **the two marks STACKED** (glyph over meter, one 14-px-wide cluster that gives 3 px back by a negative margin) | beside it, the cluster cost 20 px of the name's line and on a phone it wrapped under the name: Cinnamon 79 → 86 px, a request row 59 → 81. Stacked it advances the line by 11 px where the glyph alone advanced it by 12, and adds no height (§5, §5a). |
| "a tinted row edge" | an edge rail | **a soft background wash from the row's start edge, classes 4–5** (10 % → 0 by 55 % of the width) | a rail hung in the gutter was clipped by the desk's scroll pane (invisible at 390), and an inset one lay over a name's first letter; a background cannot overlap, add a pixel, or be clipped. |
| Stats | "the lists that sort gain Class" | `Class` is one more key of the Stats › Markets sort (`SORTS`, `FilterBar` — after the unfold of #447 a select in the list panel's own header), and its rows wear the mark | the only goods list with a sort control |

**Server (0294).** Knob `world_config.good_class_edges = [45, 140, 350, 950]` (four ascending base-value edges). `class = 1 + the number of
edges at or below base_value`. All three functions server-only (revoked from every client role), `search_path` set, invoker; the rule is
IMMUTABLE + strict (plpgsql — a SQL function with a `SET` clause is never inlined and costs ~3 µs a call against ~1 µs), the reader and the leaf
STABLE. Served as `'class', …` directly after each `'rarity'` line — one anchor line, present exactly once in each live body (re-read on prod).
**Self-assert** (rolled back where it writes; asserts the RULE, never a seed): every hunk present exactly once and the set reversing to the
pre-image, ACL / volatility / definer / config of the three bodies unmoved; the knob is four ascending positive numbers and the reader returns
them; the posture of the three new functions; the leaf maps the knob's OWN edges exactly (below edge i = class i, at it = i + 1, 0 and a value
above every edge = 1 and 5, NULL = NULL, a short edge array = NULL), derived from the stored knob so tuning it cannot make this false; the rule
over the reader's edges equals the leaf equals an independent count, for EVERY good; every served good (the snapshot, joined to the table for all
629; every row of three harbours' markets; request-board rows planted at the class boundaries and rolled back) carries class =
`good_class(base_value)`; the snapshot minus `class` is the pre-image byte for byte; the reverse restores the snapshot payload, the registry and
the function set; every other function in public/cmd/world/voyage is md5-unmoved and exactly three were added; the registry, the walls and both
owner switches as found.

**Client (appearance only; the served number is the only input — `docs/NO_SPAGHETTI.md` §7B/§7C, exactly like rarity).**
`src/components/ui/goodClassTiers.ts` is the pure table (class → word key, lit bars, colour token, row wash; `goodClassRow` is what a LIST ROW
spreads); `GoodClassMark.tsx` is the ONE component (a five-bar meter at the block characters' ▂▃▅▆█ heights, lit bars = the class, plus the word
in the tile / tray form); `GoodKind` is the one composition of a good's identity (kind · rarity · class; `compact` = the two marks stacked, for
a list row). Drawn by: the Market rows (`TradeRow`), the request board, the Codex's rows (the meter hangs under the good's own icon: no width, no height) and its tray, the trade tray's Kind row and `TradePanel`,
the cargo rows (a fleet's, a merchant's, the desk's), the Forge tiles (the meter alone: a control's text is the product's name, which the tray it opens must repeat — the tray's first row says the class) and ingredients, the Storage rows, and Stats › Markets. A server older
than this build serves no `class` and the client then draws NOTHING — never a guess. Two channels, always: a colour token (§4) AND the shape.
Not drawn (and said so): the desk's Trade-face goods cards (`TradeBoard`, which shows no rarity either — its panel does show the class), route
stops and the trade history's sentences.

## 4. Measurements
**The edges (re-run 2026-11-01).** `[45, 140, 350, 950]` over `data/goods.json` (the midpoint of each good's baseValue range): **593 of 629
goods (94.3 %) land in their authored `valueBand`**; sizes 86 / 215 / 162 / 108 / 58. An exhaustive search over every possible cut finds 598
(95.1 %) at the irregular edges 53 / 135.5 / 379.5 / 1050 — five goods for numbers nobody can say; the round edges stay (the knob is the tuning).
**Prod, read-only, the same day:** 629 goods, min 4.00, max 3300.00; by class 86 (4.00–44.00) / 215 (45.00–137.00) / 162 (141.00–345.00) /
108 (379.50–925.50) / 58 (1050.00–3300.00) — the data file's sizes to the good. A good sits exactly ON the first edge (45.00), so "at or
below" is the rule that matters, and the self-assert pins it.

**Cost, PGlite 18.3 (WASM, a shared machine — read the quartiles), paired A/B against each body with its hunk reversed, same session:**
| read | rows | before | added by this slice |
|---|---|---|---|
| `world.snapshot()` | 629 goods | ~246 ms | **+1.0 ms** median (quartiles −13 … +17 = the noise); the first draft's leaf per good would have added **+14 ms** (4 … 28) |
| `world.market(port)` | 7 | ~16 ms | **+0.05 ms** median (quartiles −0.8 … +1.4 = the noise) — the brief's budget is < 5 ms |
| `world.contracts(port)` | 4 | ~1.4 ms | **+0.05 ms** (0 … +0.15) |
| the pieces over the 629 base values | | | leaf per good 8.0 ms · the rule with edges read once 1.0 ms · one read of the edges ≈ 0.002 ms |
For scale: `good_rarity` over the same 629 goods costs ~190 ms of the snapshot's ~216 — the class is a rounding error beside it.

**Tokens (`src/index.css`; `tests/good.class.spec.ts` re-measures them from the file AND in the running page).** Contrast on the sheet / the inset:
night — 1 ink-faint 5.78 / 5.15 · 2 ink-muted 8.09 / 7.21 · 3 ink 15.72 / 14.00 · 4 `#ee9a5c` 7.70 / 6.85 · 5 `#ffdc6a` 12.83 / 11.43; day — 1 `#646c79`
5.30 / 4.84 (the day's ink-faint, 4.42 on the inset, is not used) · 2 ink-muted 7.56 / 6.91 · 3 ink 17.74 / 16.21 · 4 `#a8501c` 5.48 / 5.01 · 5 `#7a5a00`
6.38 / 5.83. All ≥ 4.5. Classes 1–3 are the game's own three inks (channel spread ≤ 0.09), 4 and 5 are the scale's only chroma (0.48–0.58), and no
class borrows a rarity hue.

**Self-assert, tried to be broken:** 23 mutations of the file (a hunk dropped; the rule's edge off by one at each end; the knob unordered / three edges /
never written / every edge below the cheapest good; each of the three served wrongly or under another key, consistently in the re-cut and in the assert's
own hunk table; an extra payload key; a grant to a client role on each of the new functions; the leaf not strict / a definer / hard-wired to other edges;
the rule merely stable; an unrelated function moved) — every one stops at its own `0294 self-assert FAIL`, and the control applies.

## 5. Proof — the gates, and what each said (2026-11-02; the local gates on the tree that was pushed, the CI's in §5a)
- `tsc -b`: clean · `eslint` on the touched TypeScript files: clean · `node scripts/db/check-versions.mjs`: OK, 280 migration files, no collision.
- THE CHAIN, through the prefix cache (`BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing`, never from zero), on the tree with main merged in (0291, 0292,
  0293 and the Stats unfold are in; prod head 0293): 282 migrations — 281 restored from the cached prefix, 1 applied here (0294) — all 282 with a self-assert receipt (293 receipt
  lines), the world guard `ok` (the applied world equals `data/*.json`), `PROOFS PASSED: 1 file(s), 5/5 PASS markers`. So 0294's hunks apply, and its self-assert holds, on the
  bodies as 0292 and 0293 left them. Earlier, on the tree rebased onto 0291: 280 migrations, 278 restored, 2 applied, 291 receipt lines, the same pass.
- 0294's self-assert, tried to be broken: 23 mutations, every one caught by its own `0294 self-assert FAIL`; the control applies (§4).
- `npm run build` (local mode): clean; the world image built from the prefix cache.
- Playwright against the built image (headless, `localhost`, an explicit port, the trailing-slash base — nothing skipped for a missing server, read), on the FINAL build, main merged in
  through #449: **138 passed, 1 skipped, 0 failed in 28 spec files (5.4 min)** — `good.class` 13 · `duplication` 11 · `sections` 8 · `i18n.keys` 4 · `words` 1 · `market.desk` 3 ·
  `align` 2 · `consistency` 17 · `layout` 19 · `primitives.geometry` 5 · `city.density` 1 · `city.page` 1 · `city.audit` 9 · `onepage` 2 · `wide.layout` 6 · `desk.layout` 4 · `i18n.ko` 2 ·
  `stats.unfold` 6 · `stats.tab` 3 · `stats.filters` 3 · `stats.moneyFeedDrip` 2 · `stats.bigChart` 2 · `stats.moneySectors` 1 · `stats.moneyFeed` 1 · `codex.unfold` 4 · `ledger.unfold` 3 + 1
  skipped (its own: it needs `UNFOLD_WORLD`, a live-sized world, and says so) · `greatPowers` 4 · `captains.codex` 1. After the last merge (#450, the Rank unfold) on a fresh build, the
  files it touches again: `good.class` 13 · `consistency` 17 · `layout` 19 · `stats.unfold` 6 · `codex.unfold` 4 · `rank.unfold` 4 · `rank.countries` 1 — **64 passed, 0 failed**.

`tests/good.class.spec.ts` — PURE: the table is complete for 1–5 (a word in both languages, a lit-bar count, a token each), a list row wears the
class from the number alone (the wash from class 4 only; none, null, 0, 6 and 99 draw nothing), the class table is not the rarity table (no shared
token, word or glyph), `premium` is not a class word, and every colour clears 4.5 : 1 on the sheet and the inset in BOTH schemes, measured from
`src/index.css`, is its own colour, and only 4–5 are chroma. BROWSER (the built image, headless, 390×844 and 1280×800): the design gallery in both
schemes (the painted colour is the token, ≥ 4.5 measured in the page); then every list — the desk's Buy and Requests, the Codex's 629 goods (all five
classes present), the Forge, the City page's Market (wide), a cargo list — shows exactly one class mark per row in the dictionary's word, **no row grows
when the class is taken away** (the measurement that caught the first draft), the mark overlaps nothing in its row, a premium row's mark colour and
wash differ from an everyday one's, one class is one colour in every list; the press that opens a good spells the class out (the trade tray's Kind row,
`TradePanel`'s header, the Codex tray's Class row); Korean; and Stats › Markets sorts by class, premium first.

## 5a. The first CI run (PR #446 at 4777ce81): two reds in `acceptance-shard (3/3)`, each read to its last error
Everything else was green — `select` ×2, `build`, `disposable-chain` (the real chain through the prefix cache), `pglite-gate` ×3, `acceptance-shard` 1/3, 2/3,
db, npc 1/2, npc 2/2, `npc-on-world`. Shard 3/3 ran 174 tests: 172 passed, 2 failed, and the `acceptance` roll-up failed with it. The CI selects 107 spec files
for this diff (`GoodKind` is the app shell); the local batch had run 16, and the two that failed were not among them.
1. **`city.audit.spec.ts:437`, "the Forge product controls carry the product name, never the recipe".** The Forge tile's text was `Adire Cloth fine` (the name and the
   class word) and the test requires the tray the tile opens to contain the tile's whole text; the tray had the name, not the word. My tile put the class word in its meta
   line. **Fix:** the tile draws the meter alone (its word is the accessible name) and the tray's first row says the class (`forge-class-row`: `codex.class` + the mark with its
   word) — where the Codex's tray already says it. A control's text is the product's name.
2. **`good.class.spec.ts:370` (phone), "the class mark GREW a row".** Desk Buy, Cinnamon: 86 px with the mark, 79 with it hidden. **A defect of my own spec's baseline, not of the
   screen.** The baseline hid the mark but kept the cluster's −2 px give-back, so it was 2 px NARROWER than the row as it stood before this change (the rarity glyph alone, 12 px)
   while the shipped cluster advanced the line by exactly 12. Cinnamon at 390 sits on its wrap edge: squeezing each row from the right in quarter-pixel steps (a scratch sweep
   over the Buy list, the requests, every 12th Codex tile and every 6th Forge tile), the row as it was before the class has **0 px** of slack, the first draft's cluster 0 px
   and the cluster as now built **1 px**; the runner's text is a hair wider, so there the 12-px row wrapped its cluster under the name (+7 px) and the 10-px baseline did not.
   Reproduced here: widening every glyph by 0.025 px (`letter-spacing`) makes the first draft read `Cinnamon 86/79` — the runner's numbers — at 9 of 25 widths, and the shipped
   one at none (and in 5 row-and-width cases it is SHORTER than the baseline: the row it saves). The sweep found no row, in any of the four lists, that wraps earlier with the cluster than
   with the glyph alone. **Fix:** (a) the cluster gives back 3 px, so it advances its line by 11 px against the glyph's 12 and can never wrap what the glyph alone did not;
   (b) the spec's baseline is the row as it was — the class hidden AND the give-back removed; (c) the growth check is one-sided (a row may get shorter, never taller);
   (d) two invariants that hold on any machine's fonts: the cluster advances its line by no more than the glyph it joined (or its own 14 px when it stands alone), and it is
   no taller than the 24-px line. The failing test stopped at its first list, so the phone test's other lists (the requests, the Codex, the Forge) had not yet run on the runner.

3. **Main moved while the fix was written** (0292 and 0293 deployed — prod head read 0293 — the Stats unfold #447, then the Codex unfold #448 and the History unfold #449). Merged in, two conflicts: `docs/OWNER_REQUESTS.md` (main's
   row 260 kept, my row 261 after it) and `src/features/stats/Markets.tsx` (the unfold rewrote the face onto `ListPanel`; main's structure taken whole and my four additions re-applied:
   the `class` key of the sort and its label, the class served to `GoodRow`, the compact mark, the row wash). The Markets list is no longer behind a detail page, so my Stats test
   now reads the sort where it stands (a select in the list panel's header). #448 then turned the Codex's goods from tiles into 44-px rows of one list panel (its law:
   at least 8 whole rows on the glass at 390, no text cut, none crossing), and `GoodsFace.tsx` conflicted: main's rows taken, the class re-placed. The tile's meta line is gone, and
   every place in a row's label costs width (the label already wraps the rarity word under a long name) — so the meter hangs **under the good's own icon, in the mark cell**:
   absolutely positioned, 14 px under a 20-px icon, so it adds no width to the row and no height (the cell's line is the row's 24 and the 44-px row has 28 px of content) — a
   row cannot grow by it, on any font. The Codex steps of this spec lost their `codex-open` press (the face is the list). #449 (History) and #450 (Rank) merged without a conflict in code. Re-proved on the merged tree: §5.

## 6. BEFORE / AFTER (headless Chromium, DPR 2, English, dark; `…\scratchpad\good-class\shots\`)
`before-*` is the design commit built as it was (no client change); `after-*` is this branch. Desk City › Buy at 390: `before-desk-buy-phone.png` /
`after-desk-buy-phone.png`; Requests at 390: `before-requests-phone.png` / `after-requests-phone.png`; the City page's Market at 1280:
`before-market-wide.png` / `after-market-wide.png`; the Codex's goods at 390: `before-codex-phone.png` / `after-codex-phone.png` (+ `after-codex-loud-phone.png`
a luxury tile, `after-codex-tray-phone.png` its tray with the Class row); the Forge's tier page: `before-forge-phone.png` / `after-forge-phone.png` (the tile is its name and the meter) and the tray a tile opens, its first row the class: `after-forge-tray-phone.png`;
the design gallery's Good marks (the ladders and a cargo list): `after-gallery-phone.png`; Stats › Markets, the unfolded list sorted by Top class:
`after-stats-class-phone.png` / `after-stats-class-wide.png`. The measured row heights are in the spec's console output (`tallest growth` per list).

## 7. Found on the way, NOT fixed here (not this slice's files)
- **The City page's Market at 390×844 is broken on main before this change** — its two-region layout leaves the name column one character wide
  ("S i l k", "In st o c k"), the buy / sell cells over the names; `before-market-phone.png` shows it, `after-market-phone.png` the same layout with the
  class marks in it. It is the HQ / City faces slice's (`src/features/city/*`, `docs/dev-log/2026-11-01-ui-unfold.md` §3). The spec measures the City page's
  Market at 1280 only, and says why.
- The desk's City face at 390×844 leaves its trade / request board a pane of ~190 px (its rows start at the pane's last 8 px) — the same row of the roster.
- The request rows' `deliver` cell runs 10–16 px past its row at 390 on main (`0 / 20 units on boa…` is cut in `before-requests-phone.png`; the rows'
  `scrollWidth` exceeds their `clientWidth` with the class marks hidden too). The spec therefore asks only that the class mark add no spill.

## 8. Bookkeeping
PR title `MIGRATION — 0294: every trade good has a premium class (deploy AFTER 0293)`; PROD CHECKS in the body (head; the live md5s of the three re-cut
functions and that their anchor line occurs once in each; the knob key and the three functions absent; the 629-good value spread by class). `docs/WORK_QUEUE.md`
is the coordinator's; this PR edits its own row in `docs/OWNER_REQUESTS.md` (261) and the WORDS table. Trailer `Co-Authored-By: Claude Sonnet 5.5
<noreply@anthropic.com>`; PR body ends with the Claude Code line. Never re-run a red until green.
