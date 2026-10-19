# 2026-10-19 — Live prices (the tick / "market mood"), migration 0212 — WIP

The owner: *"would it be possible, for the prices to be like of stock market? like it moves like real-time stock."*

## Design (decided by default)
- A deterministic tick per market: a PURE integer function of (port uuid, good uuid, 15-second bucket). No writes per tick.
  The leaf is `public.price_tick_ppm`. It uses value-noise octaves, a hash mod 67,108,859, and no sines, so the client can port it exactly.
- The tick goes into the ONE price authority: `world.mid_from_terms` gains `p_tick` (15 arguments), and `world.mid_terms` gains `m_tick`.
  The formula is `mid = round(round(old, 4) × tick, 4)`. The re-cut callers are mid_price, quote_priced, price_path, market, price_why (term `mood`), price_outlook (serves `tick` and `calm`) and watchlist (serves `tick`, and `calm` when lit).
  There is also a new `world.mid_calm`, which gives the price with the tick at 1.
- Kill switch: `price_tick_on` is false. Dark, every price is bit-identical to 0208 (asserted).
- **No free money.** The budget is 80 % of the thinnest round trip any trader can reach:
  spread_floor 0.02 × (1 − buff cap 50 %) × haggle floor 0.2 = 0.2 %, so the budget is 1,600 ppm.
  The tick may move no more than that within 300 s. Jitter and the fast wave each get ±200 ppm.
  The slow wave's lattice step is derived from its amplitude:
  - common ±1.5 %: 1185 / 451 buckets
  - uncommon ±2.5 %: 1975 / 751 buckets
  - rare ±3.5 %: 2765 / 1051 buckets
  - exotic ±5 %: 3950 / 1501 buckets

  So the slow mood is a multi-hour wave, and **a game day's mean is NOT 1**. That trade-off is forced by the 0.2 % spread floor.
  The visible flutter is about ±0.04 %, so cheap goods will rarely change at 2 decimal places. The owner should decide: widening the haggle floor widens the budget.
- The tick is predictable: a client can compute it ahead. Inside the window this is worth nothing, by the law. Over hours, the slow wave is a mood a trader can plan for.

## HAND-OFF
**Done:**
- The migration is written: `supabase/migrations/20260818000212_a_price_ticks_while_you_watch.sql`.
- Its self-assert **passed once** on local PGlite, on the cached 0208 prefix.
  - Dark checks: mids, quotes, paths and the Lisbon ranges equal the pre-image exactly.
  - Lit checks: mid = old × tick; path k = 0 and the outlook equal world.price on every side; `why` carries the mood.
  - No free money held over more than 100k pairs, and the positive control fails as it should.
  - A limit order at the calm price refuses `E_PRICE_LIMIT` when the tick is above it, and fills at the ticked price.
- Two cosmetic fixes to the receipt text were made AFTER that run and have not been re-run: the `%` placeholders and the `v_ticked` counter.
  **Re-apply first**, for example with `node scripts/db/apply-chain.mjs`, or through the prefix cache.

**Not done (next steps, in order):**
1. Re-apply and read the full receipt. It holds the dark/lit timings for quote, mid_price, outlook and watchlist, the worst ratio and the game-day mean. Copy them here.
2. Run the hunks read-only against prod's live bodies (head 0208), so each one is confirmed to occur exactly once there.
3. Write the client:
   - `src/domain/market/tick.ts`: the leaf ported with the same integer rules, the seed from the first 6 hex digits of each uuid, and `liveMid(calm, ppm)` in integer 1e-4 units with round half away from zero.
   - `src/live/` store: the rule served by the watchlist and the outlook, plus ONE shared bucket timer, only when `on`.
   - WatchRow: the live figure, a flash via a span keyed on the text, nothing under reduced motion, and a reserved min-width.
   - GoodChart: a live hero figure and the live point appended to the history.
   - The useTrade preview re-asks once per bucket when lit.
   - "Why this price": a line for `mood`.
   - Keep the watchlist's sort on the served figures, so no row moves.
4. Write `tests/priceTick.spec.ts`: 1,000 (market, t) pairs, SQL `price_tick_ppm` / `mid_from_terms` against the TS port, to the ppm and the cent. Name `price_tick` so CI selects it.
5. Add a world-guard check that `price_tick_goods` equals `good_rarity`.
6. Add a docs/PRICE_FACTORS.md §3.5 section.
7. Run the arrivals harness, lit against dark: `origin/osn-arrivals-fast` `scripts/ops/harness/arrfast`.
8. Open the PR.

**Pre-existing finding, not fixed:** a 10-unit buy-then-sell in the same port prices the sale one stock step lower. That raises the mid by about 5/stock (0.8 % at stock 600). At a fully shaved 0.2 % spread, a same-port flip can already pay today, with no tick.
