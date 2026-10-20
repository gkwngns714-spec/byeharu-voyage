# 2026-10-20 — a round trip never pays (migration 0212 at writing, `osn-same-port-flip`)

**The bug** (pre-existing; found 2026-10-19 while building the live-price tick, WORK_QUEUE HAND-OFF #2): buy 10 and
sell those 10 in the SAME port, with no time passing, and the sale was priced one stock step BETTER than the buy
(≈ 0.83 % at a 600-tun market). At a spread shaved to 0.4 % (purser + bargain + standing) the flip paid. It had to
land before `price_tick_on` is lit.

**Version.** 0212 at writing. Prod head was 0208 when cut, **0209 when checked read-only** (the hunks still occur
exactly once on the live body at 0209). 0210 and 0211 are open branches; `osn-live-prices` also calls its file 0212.
It renumbers to the prod head + 1 at push. Not deployed: this PR does not push or merge.

## 1. Root cause, in the one price authority

`world.quote_priced` (0169; the body `world.quote`, `cmd.do_buy`, `cmd.do_sell`, the baskets, the routes, the good
board and the merchants' planner all compose) walked the book in `trade_step_tuns` steps and priced EVERY step at the
mid of the stock it **started** from:

- buy branch (live body, the step): `v_mid := world.mid_from_terms(…, v_stock, …)` then `v_stock := v_stock - v_n` —
  a buy from stock S prices its first ten at mid(S) and leaves S − 10;
- sell branch: `v_mid := world.mid_from_terms(…, v_stock, …)` then `v_stock := v_stock + v_n` — the sale of those
  ten starts from S − 10 and prices them at mid(S − 10), the DEARER mid (mid falls as stock grows:
  `power(target / stock, elasticity)`, elasticity 0.5).

So the round trip gained one step of the curve, ≈ elasticity × step ÷ stock, and selling in one-tun lots gained
nearly a full step on every tun (each lot priced at the stock the last one left).

A second leak in the same body: `total := round(v_total)::bigint` rounded half up on BOTH sides, so a cheap good
whose bid landed on x.50 sold one tun at a time for a ducat more each than ten of them cost at once (goods go down
to 2.13 a tun on prod since 0208).

## 2. The fix (decided by default; the owner may reverse it)

Both rules live in `world.quote_priced`'s walk alone — three hunks sliced from the live body, each asserted to occur
exactly once, the body reverses to its pre-image, ACL / volatility / definer / config unmoved. No caller changed.

- **The shelf.** Stock is shelved in `trade_step_tuns`, the shelves (k·step, (k+1)·step]; a shelf has ONE mid, the
  mid at its TOP (its full level), whichever way it is walked. A buy takes tuns off the shelf the stock stands in
  (`ceil(stock / step) × step`) and works down; a sale puts them onto the shelf above (`(floor(stock / step) + 1) ×
  step`) and works up. A buy of N and the sale of those N walk the same shelves at the same mids, in opposite order,
  to the digit (asserted: `mid_total` equal, the stock back where it was); only the spread separates the totals.
- **The fraction.** A buy's total is CEILED to the ducat, a sale's FLOORED. The per-unit price keeps `round(…, 2)`,
  so `world.price_sides` (the display) and the quote still agree to the cent.

Together: for any stock, any spread (0 included), any N and any splitting into lots, cash out ≤ cash in.

**What moves on the live world.** A buy from a stock on a shelf boundary pays exactly what it paid (the first shelf's
top IS the stock; prod's 132,090 rows sit on tens until the first fractional regen). A sale pays one shelf lower than
today on its first ten (0.83 % at the thinnest prod market, 0.07 % at the deepest) and the same on every later ten.
Totals move by less than a ducat. Merchants' sell quotes (`npc_leg_lines`), routes and the good board follow, since
they quote through the same body.

**Not re-cut: `world.price`.** Its mid, ask and bid stay the market's price AT the current stock (the chart, the
outlook's "now" and "why this price" read it, and `tests/rpc.outlook` / `rpc.why` hold them equal). The ask equals a
one-tun buy quote to the cent on a boundary; the bid is now one shelf above a one-tun sell quote (the sale fills the
shelf above). The trade tray prices through `world.quote`, so what is quoted is what is charged. If the owner wants
the market list's "sell" column to be the executed first-tun bid: one more hunk in `world.price` (the sell shelf's
mid), and then `price_outlook` (k = 0 must equal `world.price` on every side) and `price_path` must follow — a
separate slice.

**Not fixed, noted:** 0194's glut (`do_sell` raises `glut` by `glut_per_depth × units / target` after a sale) makes a
SELL-then-BUY at the same quay ~0.1 % cheaper per cycle at the 0.4 % spread (0.5 % glut per ten at target 600). It
needs goods in hand, crashes the market under the trader (−30 % at the cap) and burns the day cap; the quote
authority is not where it lives. Flagged for the live-prices owner decisions.

## 3. The self-assert — receipt (local PGlite, cached 0200 prefix, 19.5 s with the snapshot)

> 0212 self-assert ok: A ROUND TRIP NEVER PAYS. world.quote_priced re-cut (3 hunks, reverses; ACL kept): a shelf of
> 10 tuns has one mid (its top), a buy's total is ceiled and a sale's floored. 68 probe rows (64 on a shelf boundary),
> 544 buy-then-sell pairs (N 1–100): every sale mirrors its buy to the digit and returns ≤ what was paid (worst sell ÷
> buy 0.923364); seven one-tun lots never beat the seven bought. The pre-image leaked on 536 of 544 pairs (its sale
> dearer than its buy). On a shelf boundary the buy is the pre-image's (units, mid; total within the ceiling); a
> 10-tun sale fell at most 0.936 % against it. Limit: 10.00 of 100 at ≤ 104.69. world.quote(50) ms
> {2,3,1,2,2,1,1,1}, world.price ms {2,1,1,1,1,1,1,1}.

The planted sales run in blocks rolled back by their own sentinel (`ZX212`); the probe stock is asserted back after
each row. The pre-image is kept under `pg_temp.quote_priced_old_0212` as the positive control.

**Prod, read-only** (`begin transaction read only`, stable functions only), head 0209: the three hunks occur exactly
once in the live body; the body does not yet carry the rule; 68 probe rows, 67 on a shelf boundary; the sample
10-tun quotes run; the walls are 0 / 0 / 0.

## 4. The spec — `tests/rpc.sameportFlip.spec.ts` (node, the built world)

- through the doors `cmd.do_buy` / `cmd.do_sell`: buy N, sell N (1, 7, 10, 15, 37), and seven sold one tun at a
  time — the purse never grows;
- through the authority: 12 stocks (0.5 … 50,000, fractional, below one shelf, on and off boundaries) × 4 spreads
  (0, 0.004, 0.02, 0.06, planted on `spread_base` / `spread_floor`) × 8 N (1 … 999) = 384 pairs: the sale mirrors the
  buy (`mid_total` equal, stock back), returns ≤ the buy, one-tun lots too; where the spread is worth a ducat a
  side the round trip LOSES, not breaks even;
- `world.price`: ask = a one-tun buy quote to the cent at stock 600; bid ≥ a one-tun sell quote; sell < ask.

**The specs CI's rule S selects, run locally on the built world** (`rpc.outlook`, `rpc.why`, `rpc.firstSession`,
`rpc.goodBoard`, `rpc.surface`, `db.image`): 54 of 55 green at first; `rpc.surface` "cmd.haggle(…, 'sell') moves
the bid" asserted that a won sell-side bargain shows as MORE DUCATS on a ten-tun lot of a cheap good (138 → 138: the
bargain is worth ~0.3 ducats there and the sale's total is now floored). It had passed on the luck of the fraction
under `round()`. The claim is re-cut to "never fewer ducats, more per unit" (avg_price and haggle_saved carry the
bargain, as they did); the buy-side test already made its bargain "several ducats, so cheaper is a fact of the total
and not of the rounding".

**CI, first run (head 309a47b):** build green, acceptance green (13 selected specs), apply-proof: disposable-chain,
pglite-gate (ledger) and (merchants) green; pglite-gate (the rest) red on two proofs for the same rounding reason:
`06_haggle.sql` ("a won SELL bargain did not raise what the quay pays — 10 at 153 (15.31 each) before, 10 at 153
(15.35 each) after": the total is floored, the unit price did rise) and `10_manifest.sql` (the breakdown bound
`0.005·qty + 0.515` carried a 0.5 ducat-rounding term; ceil/floor makes it 1). Both proofs re-cut to the new rule
(total never fewer / bound `0.005·qty + 1.015`); not re-run for green — the two reds were read to their last error
and each is the rounding change by construction. Prod re-checked read-only at head 0210: hunks occur once, rule absent.

## 5. How `osn-live-prices` (37c8af5, its own "0212") rebases

Its two `world.quote_priced` hunks (`exit when v_n <= 0;` + the buy-branch `v_mid := …(… v_stock …)` and `else` +
the sell-branch `v_mid := …`) no longer occur: this file collapses the two `mid_from_terms` calls into ONE, after the
shelf is chosen:

    v_mid := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_top, t.m_drift,   -- 0134, 0173, 0194; 0212: the shelf's top

So its re-slice is one hunk on that line (add `t.m_tick,` before `t.m_target`), cut from the live body after this
deploys; its other 7 bodies (`mid_from_terms`, `mid_terms`, `mid_price`, `price_path`, `market`, `price_why`,
`price_outlook`, `watchlist`) are untouched here. Its file must renumber behind this one, and its "dark = pre-image
exactly" asserts then compare against the shelf-priced quotes, which is what they should compare against. Its
no-free-money budget (80 % of the thinnest spread) stays valid: with the shelf rule the spread is the ONLY thing
between a buy and its sale, so the tick's swing within the window is the whole of what it must stay under.
