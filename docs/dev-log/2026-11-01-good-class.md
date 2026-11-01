# 2026-11-01 — 0293: every trade good carries a PREMIUM CLASS the player can see at a glance

**Branch** `good-class` · server + client in ONE PR (a served field with no reader, or a reader with no field, is half a slice) ·
migration `supabase/migrations/20260818000293_a_good_has_a_class.sql` (the number is what is free at deploy: 0290 stats-budget,
0291 port-goods-hot and 0292 stats-period are queued ahead of it and deploy first; renumber at deploy if the order moves —
the file AND its self-assert strings). Deploy by the coordinator (`~/bin/bv-deploy.sh <pr>`), never by the author.

## 1. The owner's words
2026-11-01: *"new trade goods - distinctive class showing what is more premium."* ("go", no permission questions.) Read with rows 37/52/67
(a real, regional, sorted catalogue; "wtf is foodstuff") and 177 (the rarity word in a third place). Decided by default (owner may reverse):
the class is a FIVE-step PREMIUM scale by a good's value, drawn so a premium good is unmistakable in every list a good appears in.

## 2. What exists — do not duplicate it
- `public.good_rarity(id)` (0032/0051) = how SCARCE a good is (producer count: common / uncommon / rare / exotic), served as `rarity` on
  `SnapshotGood` and `MarketGood`; drawn by `RarityMark` (`src/components/ui/Rarity.tsx`, pure table `rarityTiers.ts`): a 12-px glyph +
  colour token. Its two serving points were last re-cut by 0281 with hunks `'rarity', public.good_rarity(g.id),` (snapshot goods and market goods).
- `goods.tier` (0..3) = PRODUCTION tier (0 raw, 1–3 made in the Forge, 0280/0281) — NOT premium. `goods.base_value numeric(10,2)` (4 … 3,300)
  is the value; `data/goods.json` carries an authored `valueBand` 1–5 that prod's `goods` table does NOT have.
- So three different ideas live on one row: scarcity (rarity), production tier, and PREMIUM (value). This slice adds only the last, as ITS OWN
  concept with its own mark. Never fold it into rarity.

## 3. The design
**Class** = 1 Basic · 2 Standard · 3 Fine · 4 Premium · 5 Luxury (EN; KO 기본 · 일반 · 고급 · 프리미엄 · 최고급 — the dict decides the final
words; plain, short, one voice with `docs/WORDS.md`; the banned-words spec must stay green).
**Server authority (one rule, data-driven):**
- knob `public.world_config('good_class_edges')` = `[45, 140, 350, 950]` (jsonb, four ascending base-value edges: class = 1 + the number
  of edges ≤ base_value). Measured against the authored bands: 593 of 629 goods (94 %) land in their authored `valueBand`; sizes
  86 / 215 / 162 / 108 / 58. (Brute-forced from `data/goods.json` on 2026-11-01; re-run it, state the result, and keep the knob — tuning is a knob.)
- `public.good_class(p_base_value numeric) returns smallint`, STABLE, `search_path` set, ONE leaf. It must cost almost nothing on a
  629-row read: read the knob ONCE per call (not per row through a correlated subquery you have not measured); `good_rarity` is already the
  biggest single cost of the market read (87 ms of ~240) — the class must add < 5 ms, measured, and say so in the dev-log.
- Served as `'class', public.good_class(g.base_value)` beside each `'rarity'` in the SAME two serving functions (hunk method: each hunk
  exactly once, reversible, cut against the LIVE body: re-read its md5 on prod first). If you find a third place that serves goods
  (Forge recipe inputs/outputs, the request board, the compendium), serve it the same way — grep every `'rarity'` in the live functions.
- Self-assert (rolled back where it writes; asserts the RULE, never a seed): the knob exists with four ascending numbers; the function maps
  the edge values exactly (44.99→1, 45→2, 139.99→2, 140→3, 349.99→3, 350→4, 949.99→4, 950→5; below the first edge → 1); every served
  good carries a class 1–5; the served class equals `good_class(base_value)` for EVERY good (a join on the table, no hard-coded counts);
  every function in public/cmd/world/voyage other than the two re-cut is md5-unmoved (0287's technique).
**Client (appearance only; the served number is the only input — `docs/NO_SPAGHETTI.md` §7B/§7C, exactly like rarity):**
- Pure table `src/components/ui/goodClassTiers.ts` (class → word key, bars, colour token) + ONE component `GoodClassMark` in the design
  system, exported from `components/ui/index.ts`. TWO channels, always: a colour token (measured ≥ 4.5:1 on the panel in light AND dark,
  figures in `src/index.css`) AND a shape — a 5-step ascending BAR meter (▂▃▅▆█, 1–5 lit) so it survives greyscale and colour-blindness and is
  never mistaken for the rarity glyph (ring / diamond / gem / star). Classes 4 and 5 are LOUD: a premium good must read as premium from the
  list without opening it (a tinted row edge / the word beside the meter; the agent designs it, the owner can reverse).
- It is drawn by the ONE place that draws a good's identity — `GoodKind` — so every caller (Market rows, `TradeRow`, `PriceRows`,
  `TradePanel`, the Compendium's `GoodsFace`, the request board, the Forge, cargo/storage lists) shows it without copying it. Where a row has
  no room, the meter shows and the word is the accessible name + press-to-read (U5). The rarity mark stays; the two marks sit as a pair.
- Sorting: the lists that sort (0244) gain `Class` as a key (premium first) — through the existing sort machinery, not a second one.
- i18n EN + KO through `src/lib/i18n/dict/*`; no hard-coded word. A server older than this build (no `class`) renders NOTHING, never a guess.
- UI laws v2 (`docs/dev-log/2026-11-01-ui-unfold.md`) bind: the mark must not add a line or push a figure — rows stay compact at 390.

## 4. Proof
tsc · eslint · build · `check-versions` · the prefix-cached chain proof (`BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing`,
never from zero) · `tests/duplication.spec.ts` · a new spec `tests/good.class.spec.ts`: the pure table is complete for classes 1–5 and
distinct from the rarity table; every goods list at 390×844 and 1280×800 (Market buy/sell/request, Compendium goods, a cargo list, the Forge)
shows a class mark per good, no row grows taller, no overlap; premium (4–5) rows are visibly distinct from basic (1–2) ones (assert the
tokens differ, not a pixel). Screenshots BEFORE/AFTER of the Market and Compendium goods lists at 390.

## 5. Bookkeeping and finishing
PR title `MIGRATION — 0293: every trade good has a premium class (deploy AFTER 0292)`; PROD CHECKS in the body (head; live md5s of the two
re-cut functions; the knob key and `good_class` absent; the 629-good value spread read-only). Do NOT edit `docs/WORK_QUEUE.md` (the
coordinator does); edit your own row state in `docs/OWNER_REQUESTS.md` (add a new row for this order if none). Trailer
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body ends with the Claude Code line. Never re-run a red until green.
