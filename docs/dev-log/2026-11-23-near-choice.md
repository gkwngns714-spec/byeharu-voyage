# 2026-11-23: A real choice and a full hold (0475, proof 178)

The design: `docs/design/roadmap-2026-11-23.md` slice 4 (and removal X10); `docs/design/playable-2026-11-22.md` section 6, findings 7, 8
and 13. Ships **dark** behind `near_choice_enabled` (false). Lighting it is the owner's; it changes live play for every company, so it gets
its own 30-minute after-check (`scripts/ops/harness/near-choice/after-0475.sql`, against `before-0475.sql`'s baseline).

## What changes, lit (decided by default; every figure a knob)

| | Before | Lit |
|---|---|---|
| S1 the spread (`world.best_sales`) | each good's card names its own best sale; at Lisbon 5 of 10 cards (the play-test: 10 of 10) sold at Setubal | cards of goods bought here that pay, best first: a harbour keeps at most `near_choice_per_harbour` (3) cards; the next card names the NEAREST other harbour of its good whose profit an hour of play is at least `near_choice_similar_pct` (50 %) of its best, near for near; none: it stays. Moved cards carry `spread` (the harbour left); the card is the trip board's own row for that harbour (to the coin) |
| S2 the second good (`top`) | the one-press load is one good; quicksilver filled 8 of 180 tons | a load filling under `near_choice_topup_below_pct` (50 %) of its leg's room names a second good bought here for the same harbour: the one the tons left and at most `near_choice_topup_coin_pct` (25 %) of her purse make most of at the two prices, the first `near_choice_topup_goods` (4) quoted both ways; its profit is sale less buy, profit tax there and the dock fee the larger cargo adds. Only when above nought |
| S3 the near rule's end (`public.first_hour_near_seconds`) | near trips first under Trading 5 (minute 20 in the play-test) | near trips first while she was founded under `near_choice_hours_played` (2) hours ago AND owns under `near_choice_ships_below` (3) ships, whatever her Trading |
| S4 the mark (`near`) | a far card stood among one-minute ones with nothing to say so | with a near horizon, a paying card says `near`; the client prints "Far" before the city when false. Marked, not hidden |

**Profit an hour of play** (`near_choice_turn_seconds`, 300). Measured in the chain's world: at Lisbon the Setubal sales take about one
minute, Porto and Seville three to seven, each paying about as much or more (black pepper Setubal +1,437 in 64 s, Seville +1,608 in 382 s;
cork Setubal +576, Seville +672; porcelain Setubal +991, Porto +956 in 194 s). By sailing time alone a one-minute trip is always "best an
hour" and nothing is ever similar: that is the ping-pong. The spread adds 300 s a trip (the press, the load, the arrival card) when it
compares harbours. The good's own sale (0351 best per day, 0472 near first) is unchanged. Among the eligible harbours the nearest is
taken (tried first: the best-rate one sent Lisbon's porcelain to Soyo, 1 h 21 m: inside the 2 h horizon, but not a near choice).

**Time played** is real time since the company was founded (`players.created_at`): the game keeps no clock of time spent in it.

**Wages** are not taken off the second good's figure: they are owed by the voyage and paid from its profit; a bigger profit may pay more of
what is owed, never more than is owed. Every other cost is.

## Numbers, a fresh company with 40,000 coins (the chain's world, `first_hour_enabled` lit)

Cards that name each harbour, dark and lit (the far ones included):

| Harbour | Dark | Lit |
|---|---|---|
| Lisbon | Setubal 5, Sanlucar de Barrameda 2, Porto 1, Hagatna 1, Cape Town 1 (5 harbours) | Setubal 3, Porto 2, Sanlucar de Barrameda 2, Seville 1, Hagatna 1, Cape Town 1 (6) |
| Amsterdam | Hoorn 5, Bruges 3, Rotterdam 1, Matsumae 1 (4) | Hoorn 4, Bruges 3, Middelburg 1, Rotterdam 1, Matsumae 1 (5) |
| Cadiz, Seville, London, Venice, Porto, Gibraltar, Setubal | unchanged (no harbour over 3 cards with a near alternative within 50 %) | unchanged |

Second goods: 40 of 74 cards over nine harbours (Lisbon 6 of 10). On those 40 the load fills **19 % of the hold dark, 39 % lit**, and the
trip's profit is **161,579 dark, 259,881 lit (+61 %)**. Lisbon: quicksilver 10 (8 t) + porcelain 26 = 16 t, +1,483 and +563; silk cloth
36 + raw silk 22, +937 and +1,510. The coin binds most loads (a quarter of her purse), not the hold.

Marked far at Lisbon: anise (Hagatna, 6 h 10 m) and iron (Cape Town, 2 h 33 m): 2 of 10, 8 near.

Cost: `world.best_sales` at Lisbon 514 ms dark, 548-559 ms lit (pglite, one run each); Amsterdam 417 / 437 ms. Inside its 2.5 s budget;
past it no second good is offered.

## The client (same PR, minimal and local)

- `TradeCard.tsx`: "Far" / "먼 길" before the city when `near` is false; the line's title names the second good. Dark: no change.
- `Trade.tsx`: a card pressed opens the plan with its `top` as `also` (another city pressed: none).
- `TradePanel.tsx` (the Buy & sell sheet): one line, "Also load" / "함께 싣기" (a tick), the good, its units and the served profit; shown
  only while the sheet holds the units it was served for.
- `planLines.ts` (`planAlso`): BUY first, BUY second, SAIL, SELL first, SELL second. The queue halts on a refused line, so the second BUY
  runs at the quay right after the first, where a refusal is seen at once; it is never written once the first count moves.
- `useTripGo.ts`: the money check counts the second good's cost.

## Checks

The migration's self-assert (dark = the pre-images on copies, first hour off and on; lit moved cards, second goods, the near rule's end)
and proof 178 (NC_DARK, NC_SPREAD, NC_MARK, NC_TOPUP: the one press buys both, NC_END). `tests/insurance.spec.ts` (the plan builder) writes
the two extra lines only ticked and only at the served units. Harness: `scripts/ops/harness/near-choice/before-0475.sql`, `after-0475.sql`.

## The refused deploy (2026-11-23) and its cause

Prod refused the first push: `0475 self-assert FAIL: dark (first hour f), a card or her horizon moved` (head stayed 0474). Not reproduced
with every one of prod's 49 lit switches set locally (the file applied). Cause, by measurement: a dark `world.best_sales` call runs 108
functions (`track_functions`), every one STABLE or IMMUTABLE and none reading the wall clock but `world.best_sales` itself, for its 2.5 s
budget (`cut`: the goods after it are not answered). So two calls in one statement see one snapshot and one `now()`, and can differ only
when one of them runs out of its budget and the other does not. Locally the call takes 0.42 s; with the budget lowered to 0.3 s the
refused file fails with prod's exact message. The fix reads both answers in one statement after a warm-up call, compares the goods both
calls answered to the byte, in order (a cut answer must be a prefix of the other), and the whole answer when neither is cut; the lit
comparison reads its two answers in one statement too (two statements are two snapshots: a beat's write between them would move a card).
With the budget at 0.3 s the fixed file passes (12 cards compared as a prefix, 2 of 2 comparisons cut); at 2.5 s, 20 cards whole.
A Lisbon card read near 2.5 s on prod for a new company is itself worth reading before `near_choice_enabled` is lit (the after-check's beat).
