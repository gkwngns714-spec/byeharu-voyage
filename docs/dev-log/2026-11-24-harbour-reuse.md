# 2026-11-24 — 0488 a harbour is asked once (no switch; the same answers)

## The problem
- After 0487, `world.best_sales(fleet, port)` at Lisbon takes 1,777-1,957 ms on prod (no longer cut by its 2.5 s budget; before 0487
  it was 2,555 ms and cut). The HQ board and the standing fleet jobs wait on it.
- What is left is CPU in many small function calls. 0487's dev-log named the next step: stop asking a harbour's terms once for every
  good and every row.

## Where the time went (the local chain, prod's switches lit, one Lisbon read)
Traced with `track_functions = all` on the chain at head 0487 (a new Portuguese house at Lisbon, 2,000,000 ducats):

| Piece | Calls a read | Time a read (local) | Depends on |
| --- | --- | --- | --- |
| `world.quote_terms` (inside each sell quote) | 168 | 55 ms | harbour and good |
| ... of it `public.crew_pct` (twice a quote) | 336 | 30 ms | the good only |
| ... of it `world.spread` | 178 | 15 ms | the harbour only |
| `public.port_fee` | 271 | 40 ms | harbour and cargo value |
| `world.tax_rate` (inside `public.profit_tax`) | 127 | 15 ms | the harbour only |

- The read prices about 150 sale rows over its 10 goods, but only 57 distinct harbours.
- So most of this work repeats: the same harbour's terms are asked again for every good, and her captains' share of the spread is
  asked again for every quote of the same good.

## What it does
- **The reads and the arithmetic are split, each kept once** (the 0169 pattern: `world.quote_priced` already takes a quay's terms
  handed over). Nine new server-only functions, revoked from public, anon, authenticated and service_role:
  - `world.spread_parts(port, fleet)`: the harbour's reads of the spread (`world.spread`, `public.investor_shave`).
  - `world.spread_purser(fleet, good)`: her captains' share (`public.crew_pct` 'spread' + 'category_spread').
  - `world.spread_pair_from(...)`: `world.spread_effective_pair`'s arithmetic (her bargain, the floor), moved there whole.
  - `world.quote_quay(port, fleet)`: the harbour's reads of a quote (spread_parts, the tax a quote carries, `public.city_bid_factor`).
  - `world.quote_terms_from(...)`: `world.quote_terms`' arithmetic (the bid factor times her mastery), moved there whole.
  - `public.port_fee_terms(port, player)`: `public.port_fee`'s gate and terms (null: no fee).
  - `public.port_fee_of(terms, value)`: `public.port_fee`'s arithmetic, moved there whole.
  - `public.profit_tax_at(on, profit, rate)`: `public.profit_tax`'s arithmetic, moved there whole.
  - `world.board_sell_memo(good, fleet, ctx, memo)`: `world.board_sell`'s body, moved there whole by 11 hunks, with a memo.
- **Six bodies re-cut** to read through them (each asserted against the md5 of the body it was written against; prod matched):
  - `world.spread_effective_pair` = `spread_pair_from(spread_parts, spread_purser)`;
  - `world.quote_terms` = `quote_terms_from(quote_quay, spread_purser)`;
  - `public.port_fee` = `port_fee_of(port_fee_terms, value)`;
  - `public.profit_tax` = `profit_tax_at(...)`, the rate asked only when lit and the profit is above nought, as before;
  - `world.board_sell` = `board_sell_memo(..., no memo)`;
  - `world.best_sales` hands each good's `world.board_sell_memo` the memo the last one handed back (5 hunks; the 0433 narrowing ask
    stays `world.board_sell`).
- **Inside `world.board_sell_memo`**, three CTEs take a harbour's terms from the memo, or ask them once:
  - `quay`: each sold-at harbour's quote terms (`world.quote_quay`). The sell quote is then `world.quote_priced` with
    `world.quote_terms_from`'s terms handed over, which is exactly what `world.quote` reads itself.
  - `dock`: each called-at harbour's dock fee terms (`public.port_fee_terms`).
  - `rate`: each harbour's profit tax rate (`world.tax_rate`), asked exactly where `public.profit_tax` asked it.
  - Her purser for the good is asked once a call.
  - It hands back the memo with what it asked. A memo of another fleet or house is not read.
- Every other caller (the trade, the merchants, the beat, Trade's board) gets the same answers through the same arithmetic.
- No table, no row, no knob, no cron job. Load: 0 new rows a minute.

## Why the answers are the same
- Each value is asked of the same reader with the same inputs: the harbour, her fleet and her house, fixed for the read. They are
  asked in the same snapshot (a STABLE read: one snapshot, one `now()`).
- Each value is kept as its exact text. Numeric and numeric[] text round-trip to the same value and the same scale.
- The arithmetic is the old body's, moved and not rewritten: the same expressions in the same order.
- **The self-assert** (the probe rolled back by a sentinel; the re-cut tried inside it, then for real):
  - two houses at Lisbon: a rich one with a captain seated and a goods mastery (purser and mastery not nought), and a thin purse
    (the tray's Max binds; FIT rows);
  - the switches lit for the probe where not already on (on prod all 16 are);
  - compared to the byte, before and after: the quote terms and spreads, quotes, dock fees and profit taxes (her, a merchant, a crown
    house, nobody), `world.board_sell` for every good, `world.board_sell_memo` with the memo threaded, and `world.best_sales` of both
    houses with its budget taken off (a pg_temp copy, 2.5 s -> 1 hour; nothing else of it moves);
  - then the catalog: each hunk once and reversing to the old body (md5 for md5), the six's grants, owner, definer, search path,
    volatility and types unmoved, no other function moved, the nine new server-only.
  - It took 6.1 s locally (with a dark pass prod skips). Its budget is 60 s.
- **Proof 191 goes the other way.** Inside its own transaction it writes the six bodies back as they were before 0488:
  `world.best_sales` and `world.board_sell` by reversing 0488's own hunks, and the four small bodies from their text (md5 checked).
  Then it compares again, wider:
  - three houses: Lisbon rich with a captain and a mastery, Lisbon thin, Seville;
  - lit, and as the switches are;
  - 3,840 quote terms and spreads, 640 quotes, 10,160 dock fees and profit taxes;
  - `world.board_sell` three ways (the read's context, an asked count, a full board), and the memo threaded;
  - `world.best_sales` with its budget off.
  - Everything is the same. It took 40 s locally.
- **No time-budgeted call is compared with another.** `world.best_sales` is compared only as an unbudgeted pg_temp copy. Each
  comparison runs in one transaction, so no scene straddles UTC midnight.
- Proof 27 (regard) built its dock fee pre-image by cutting the regard term out of `public.port_fee`'s text. It now cuts it out of
  `public.port_fee_terms` (1 in its place) and builds the fee with `public.port_fee_of`. It passes.

## Measured
- **Local PGlite (PostgreSQL 18.3), chain at head 0487, prod's 16 switches lit, a new house at Lisbon.** `world.best_sales`, median of
  9 warm calls, two rounds each, before and after 0488 applied:

  | House | Before | After | Change |
  | --- | --- | --- | --- |
  | rich (2,000,000 ducats; the hold binds) | 361 / 362 ms | 301 / 300 ms | -17 % |
  | thin purse (900 ducats; the tray's Max binds) | 284 / 288 ms | 241 / 240 ms | -16 % |

  - Not cut either way. The min-max spread within a round was under 10 ms.
- The self-assert's own timing (unbudgeted copy, one call, the rich house): 597 ms before, 377 ms after (the first call; cold plans).
- Proof 191's (one call after warm pieces): 393 ms with 0488's bodies, 598 ms with the old ones.
- `before-0488.sql` / `after-0488.sql` on the chain (a new house, lit): `best_sales_ms` 468 -> 312 (one call each, the first one
  cold).
- **Expected on prod:** about the same share, around 15 %, from 1,777-1,957 ms to about 1.5-1.7 s. Prod pays more per small call
  than local (0487: 4-8x), so the share saved may be larger. This is an estimate until `after-0488.sql` measures it.

## Prod checks
- **Before (done 2026-11-24, read-only, the gate green: beat 135 ms mean, db 770 MB, io waits 0):** head 20260818000487, server
  17.6. The six bodies have the md5s this file was written against. `world.board_sell`'s definition starts with the header hunk.
  None of the nine new names is taken. All 16 switches are lit, so the probe skips its dark pass. There are 105 captain officers.
- **Before the deploy:** `scripts/ops/harness/harbour-reuse/before-0488.sql`. Expect head 0487, `bodies` 6, `md5_ok` 6, `new` 0,
  `lit` 16, plus the cost: one `best_sales_ms`, and 80 calls each of quote, quote_terms, port_fee and profit_tax.
- **After (and 30 minutes after):** `scripts/ops/harness/harbour-reuse/after-0488.sql`. Expect head 0488, `md5_ok` 6, `new` 9,
  `server_only` 9, `lit` 16, `best_sales_ms` below before's, and `cut` false.
- The push's own notice times `world.best_sales` (its budget off) before and after on prod.
- Both harness files set the probe company's identity with `set_config(..., true)` for their own read-only transaction, as
  `lisbon-read/before-0487.sql` did. I did not run them on prod; the lead runs them around the deploy.

## Decided by default (the owner may reverse)
- **Split, not copied.** Each old body keeps its name and now reads through the moved arithmetic, so there is one authority for
  each rule. Every other caller of a quote or a fee makes 2-4 more small plpgsql calls than before, and gets the same answer.
- **The memo lives for one read.** It is a jsonb value `world.best_sales` holds; nothing is stored. It is kept for one fleet and one
  house.
- **The buy quotes at the buy city (`buys`, FIT) and the 0433 narrowing ask are left as they were.** They are a few calls a read, and
  `buys` can run with no buy city named.
