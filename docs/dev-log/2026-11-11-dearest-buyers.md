# 2026-11-11 — 0350: the best sale reads the sea once (`dearest-buyers`)

## The order
`world.best_sales(fleet, port)` (0348) is slow on prod: the health read shows a mean of ~2.6 s and a max of ~4.4 s over 68
calls, against the 2.5 s soft budget inside it (past the budget a card gets no line). The Trade screen asks it once per city
in hand. The queue named the fix: "a precomputed dearest-buyers list". The brief: measure first, keep the SAME answer, do not
slow the price hot path or the beat, and say so plainly if the list is the wrong fix.

## In one paragraph
**A precomputed list is the wrong fix, and 0350 does not build one.** Measured, ranking the buyers by price is about a fifth
of a call and no single part is most of it; and a stored list cannot be exact without a write on every stock move. The cost
that could go has gone exactly, with nothing stored: every buyer's price is now read in ONE statement (`world.good_mids`, the
dearest-buyers list read live), and her passage and stores to every harbour are worked out ONCE a call (`world.board_legs`)
instead of once per good. Same answers, byte for byte; a 10-good call takes about two thirds of the time it did (local,
paired). The rest of a call is `world.quote` (15 sell quotes a good) and `voyage.reach_passage`, which are the figures
themselves and are not touched. **This does not make the read "fast" on its own: expect about 1.7-1.9 s on prod, not 0.5 s.**

## Where the time went (local PGlite world at head 0349, this PC; `scripts/ops/harness/best-sales/split.sql`)
A new company docked at Lisbon, 10 goods, nothing aboard. `world.best_sales` 562 / 539 / 561 ms.

| part of one call | ms | share |
|---|---|---|
| `world.board_origin` (one `voyage.reach_passage`, 248 passages) | 98 | 18 % |
| 10 x `world.board_sell` (37-54 ms each) | 435 | 79 % |
| the loop, `board_amount`, the answer | ~20 | 3 % |

Inside ONE `board_sell` (black-pepper, 37.6 ms; `EXPLAIN ANALYZE` of its statement in a scratch copy, per CTE):

| part | ms | share | depends on the good? |
|---|---|---|---|
| `world.mid_price` x 249 harbours (`cand`) | 10-11 | 29 % | yes, but it is 249 calls of two nested plpgsql functions, five statements each |
| the passages parsed twice (`reach`, `reach2`) | 0.9 | 2 % | no |
| `public.supply_needs` over 81 distinct legs (`needs`) | 5.4 | 14 % | no |
| the join of 249 harbours to 81 legs (19,920 pairs thrown away) and `stores_in_hold` x 249 (`ranked`) | 8.8 | 23 % | no |
| the buy quote (1 distinct count for this fleet) | 0.9 | 2 % | yes |
| 15 sell quotes (`world.quote`, 0.65 ms each) | 9.7 | 26 % | yes: the figure itself |
| tax, wages, the answer, planning | ~2 | 4 % | |

So of a call: the passage 18 %, the prices ~20 %, the leg work repeated for every good ~30 %, the quotes ~20 %.
A quote alone (`quote.sql` in the PR was scratch, the figures): 249 sell quotes of 346 units for a fleet 167-199 ms
(0.7-0.8 ms each), of which `world.quote_terms` 63 ms and `world.mid_terms` 8 ms; the stock walk is the rest.

Every priced row was sailable and there was one buy quote a good (the probe fleet's stores are the same tuns on every leg),
so "quote fewer rows" has nothing to give either.

## Why not a stored list
1. **It is the smaller cost.** The price ranking is ~20 % of a call here. The dev-log of 0348 measured it on prod read-only:
   `mid_price` 249 x 15 in 710-764 ms, so ~0.5 s of a 2.6 s call.
2. **It cannot be exact and cheap at once.** A city's price moves with its stock (every trade, every merchant arrival) and
   with each drift slot. A list refreshed by the beat or by a job is stale between refreshes; a stale ranking prices a
   different ten cities than `world.good_board` does, so a card could name a city the trade tray does not price (the law
   0348 asserts). A list refreshed by every trade puts a write on the price hot path. Neither is allowed.
3. **A filter would not remove the scan.** `board_sell` must still rank every harbour that buys the good for "the five
   nearest she can sail to", so the 249 rows are read with or without a list.
4. **The same cost goes exactly.** `world.mid_price` is slow because it is asked one harbour at a time, not because a
   price is hard to work out: the one price expression (`world.mid_from_terms`) over the good's 249 market rows in one
   statement is ~1 ms.

## What 0350 does (`supabase/migrations/20260818000350_the_best_sale_reads_the_sea_once.sql`)
| Piece | What |
|---|---|
| `world.good_mids(good)` NEW, server only, plain SQL, STABLE | every market row of a good with its price, in one statement: `world.mid_from_terms` on the terms `world.mid_terms` reads. Asserted equal to `world.mid_price(port, good, stock)` on every market row of the probe's goods (2,490 rows). No definer and no setting on purpose, so the planner folds it into the caller's statement. |
| `world.board_legs(fleet, ctx)` NEW, server only, STABLE, definer | her passage to every harbour and what its longest leg asks of her stores: `board_sell`'s own `reach` / `reach2` / `needs` and the leg columns of its `cand`, MOVED there (not copied), plus the room those stores take (`stores_in_hold`, once a leg). It reads the fleet, where she sails from, the buy city and whether the good is her cargo; nothing of the good. |
| `world.board_sell` re-cut, 4 hunks | `cand` reads the prices from `good_mids` and the legs from `board_legs`: handed over by the caller as `legs`, else asked there. The ranking, the quotes, the tax, the wages and the answer are unmoved. |
| `world.best_sales` re-cut, 2 hunks | asks `board_legs` once for the goods bought at the city in hand and once for her cargo, and hands them to every `board_sell`. Its 2.5 s budget is unmoved. |

`world.good_board` is not edited. It calls `world.board_sell` as before, which now asks `world.board_legs` itself, so the
board and the cards still share one sell-side authority. No table, knob, switch, job, registry row or client file.
The RPC's shape is unchanged.

**Refresh cost: none.** Nothing is stored, so nothing is refreshed. `cmd.do_buy`, `cmd.do_sell`, the merchants and the beat
read and write nothing new (the file asserts every other function, every `world_config` row, every relation and every cron
job unmoved).

## The same answer (asserted inside the migration, on a probe house that is rolled back)
Each in ONE statement (one snapshot), against `pg_temp` copies of the three bodies as they were:
* `world.good_board` = before, byte for byte: no city, her own city, an amount, another city that sells it, and her cargo;
* `world.best_sales` = before: at her own city, at another city in hand, and with cargo aboard (both kinds of legs in one
  call). If the old or the new answer is cut by the 2.5 s budget on a busy world, the goods both answered are compared;
* the law 0348 asserted, kept: a card's profit and units are `world.good_board(good, fleet, here, units)`'s row for that
  city, to the coin (the first 3 cards);
* `world.good_mids` = `world.mid_price` on 2,490 market rows;
* each of the 6 hunks occurs once and reverses to its pre-image; ACL, volatility, definer, settings and owner of the two
  re-cut bodies unchanged; `board_sell` no longer names `mid_price(`, `supply_needs(` or `stores_in_hold(`;
* a time bound safe on a busy world: over the pairs not cut, new may not exceed old by more than a quarter (it measures
  ~70 %). The whole file fails above 45 s; statement_timeout 90 s.

## Measured, before and after (local PGlite, cached prefix, this PC; the machine's speed moves ~20 % between runs)
The migration's own probe, old and new in the same statement (4 applies):

| case | old ms | new ms |
|---|---|---|
| Lisbon, 10 goods, nothing aboard | 515 / 434 / 495 / 526 | 330 / 266 / 307 / 340 |
| Setubal in hand (not where she lies), 4 goods | 365 / 290 / 381 / 363 | 299 / 246 / 304 / 291 |
| Lisbon with cargo aboard, 10 goods | 515 / 400 / 546 / 512 | 336 / 270 / 368 / 344 |
| the three together | 1,395 / 1,124 / 1,422 / 1,401 | 965 / 782 / 979 / 975 (69-70 %) |

Steady calls, `scripts/ops/harness/best-sales/calls.sql` without and with `--apply` (two runs each, back to back):

| what | before | after |
|---|---|---|
| `best_sales` at Lisbon x6 | 404-481, 432-541 | 273-365, 259-271 |
| `best_sales` at Setubal x4 (two `reach_passage`) | 289-295, 291-360 | 286-323, 243-252 |
| one `board_sell` (10 goods) | 30-42 each, sum 334 / 327 | 14-27 each, sum 187 / 158 |
| `board_legs`, once a call | (inside every `board_sell`) | 12-15 |
| `board_origin` / the second `reach_passage` | 76-77 each | 80-111 each (not touched; the run was slower) |
| one `good_board` x4 | 287-307, 298-308 | 365-374 (the slow run), 285-292 |

A call from a city she does not lie at gains least (about 15 %): two `reach_passage` are ~155 ms of its ~250 ms and
0350 does not touch them. The migration applies on the cached prefix in 5.7-8.2 s here, its self-assert included.

## What is left in a call, and what would cut it (not in this slice)
After 0350 a 10-good call here is ~265 ms: `reach_passage` ~80, `board_legs` ~13, and 10 x ~16 ms of which ~11 are the
15 sell quotes and the buy quote. The next cuts are inside the price authority or the pathfinder, each its own slice:
* `world.quote` reads its terms per call (`quote_terms` with a fleet is ~0.25 ms of ~0.7 ms: the captains twice, the
  bargain, the investor's shave, the bid factor). 160 quotes a call.
* `voyage.reach_passage` is asked twice when the city in hand is not where she lies.

## Prod: an estimate, NOT measured
I did not query prod (the brief forbids it for this build). Composed from 0348's read-only part figures on prod
(`mid_price` 249 x 15 = 710-764 ms; `quote` x 225 = 594-1,354 ms; `reach_passage` 175-276 ms in older logs): the prices
are ~0.5 s of a 2.6 s call and go to almost nothing; the repeated leg work is perhaps 0.2-0.4 s and goes to once. So a
mean of **about 1.7-1.9 s** is the honest expectation, and fewer calls cut by the budget. The local ratio (70 %) says the
same. The real figure is the health read after the deploy.

## PROD CHECKS (read only; NOT YET RUN: the lead or the owner runs them)
One statement a file, pure SELECTs, STABLE / IMMUTABLE functions only, generated from the migration's own hunks by
`node scripts/ops/harness/best-sales/gen-checks-0350.mjs`. Run each with
`npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/<file>`.

| when | file | wanted |
|---|---|---|
| before | `before-0350.sql` | 6 rows; every `old_times` 1; `new_times` 0 (hunk 2 alone 1); `new_fns` 0; head 20260818000349 |
| before | `mids-before.sql` | `rows` > 0 (3,735 here), `differ` 0: the one-pass price is `mid_price` on the live market |
| before or after | `volatility-0350.sql` | every `volatile` s or i; after: `good_mids` and `board_legs` present, neither open to authenticated or anon |
| after | `after-0350.sql` | 6 rows; every `new_times` 1; `old_times` 0 (hunk 5 alone 1); `new_fns` 2; head 20260818000350 |
| after | `mids-after.sql` | `differ` 0 and `rows` = `market_rows` |
| after | the health read of `world.best_sales` (mean, max, calls) over a fresh window | below the 2.6 s mean; this is the measurement that counts |

Run locally on PGlite through `measure.mjs` (it strips the wrapper and the migrations table): before 6 rows as wanted,
3,735 / 0; after 6 rows as wanted, 3,735 / 0 / 3,735.

## Checks run here
* `npm run build` (`tsc -b` and `vite build`): exit 0. The world image restored 333 of 334 migrations from the cached prefix
  and applied 0350 alone (chain applied in 10.5 s; certified).
* `npx eslint .`: clean.
* The migration on the cached PGlite prefix through `measure.mjs --apply`: green 8 times, 5.7-8.2 s, every probe line above.
* `npx playwright test tests/rpc.bestSales.spec.ts tests/rpc.goodBoard.spec.ts tests/harness.guard.spec.ts tests/news.lint.spec.ts
  tests/duplication.spec.ts`: 28 passed. `tests/rpc.surface.spec.ts`: 29 passed.
* `tests/command.bestSale.spec.ts` (the card and the tray print one figure, at 1280 and 390, headless, against
  `vite preview` of this build): 2 passed.
* Not run: a from-zero replay, `db:proof`, `db.chain.spec`, the rest of the browser suite (CI's), anything against prod.

## Not proven
* **The prod speed.** Everything above is local; prod was not read. The share of `world.quote` may be larger there than
  here (0348 measured prod quotes at 2.3-6.7x local, prices at ~2x), in which case the gain is smaller than 30 %.
* **The self-assert's run time on prod.** 5.7-8.2 s here; it runs 6 `best_sales` (3 old, 3 new), 1 more for the law and
  13 `good_board`. At prod's speeds that is perhaps 20-30 s against the 45 s it allows itself. If it trips, it fails
  safe (nothing applied) and says so.
* **A fleet at sea or at anchor, and a fleet whose stores differ by leg** (several buy quotes a good): the probe is a
  new company docked at its home harbour. The moved code is the same statement text, and `good_board` parity covers
  the shut rows of a starter's reach, but those two openings are not driven here.
* **The seas** (`sea_conditions_bite`, false on prod) are not read by `best_sales`, as before.
* No mutation run was made for this file (the older harnesses have one); the parity asserts are the net.

## Rollback (forward)
A new migration that reverses the 6 hunks (each OLD text is in the file verbatim) and drops `world.good_mids` and
`world.board_legs`. Nothing else depends on them.
