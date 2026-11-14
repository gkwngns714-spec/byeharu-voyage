# 2026-11-14: a merchant carries only what the city's purse can pay for (0410)

**State: built, PR open, not deployed.** Built on head 0408; 0409 (the pirates' file, PR #678) lands first and this is 0410. It changes live play (what merchants carry and to where; what a lap's book says), so it
gets an after-check. The owner, on the merchant houses losing money: *"find the root cause, make it so that this problem does not occur again"*.

## The question

0406 made the planner count the dock fee. The share of houses whose hour ends under water did not move: 29.8 % before, 32 % at +1 h, 27.9 % at
+3 h. Why?

## What the numbers say (prod, read-only, 2026-11-14 07:28 to 08:35 UTC, head 0407; the query files are kept in `~/dev/under-water-reads/`)

**1. The measure first.** "The merchants lose 3.0 M an hour" is the sum of the losers only. All merchants together, lap net less dock fees:

| hours ago | houses trading | under water | share | the losers' sum | everybody's sum |
|---|---:|---:|---:|---:|---:|
| 0 | 746 | 238 | 31.9 % | -3.8 M | **+10.6 M** |
| 1 | 755 | 251 | 33.2 % | -3.5 M | +14.8 M |
| 2 | 758 | 211 | 27.8 % | -2.8 M | +12.3 M |
| 3 | 767 | 240 | 31.3 % | -3.4 M | +15.9 M |
| 4 | 800 | 238 | 29.8 % | -2.7 M | +14.7 M |
| 5 | 811 | 259 | 31.9 % | -2.8 M | +17.0 M |
| all six hours together | 831 | 130 | **15.6 %** | -6.4 M | +85.4 M |

Of the 666 houses that traded in all six hours, 114 were never under water, 201 once, 177 twice, 101 three times, 54 four, 13 five, 6 all six:
close to what chance gives at three in ten an hour. **An hour is mostly noise; it is mostly different houses each hour.** Over six hours about
one house in six really loses, and that is the figure to watch.

**2. Item by item, one hour (07:28 to 08:28), the 238 houses under water against the 507 above:**

| | under water (769 laps) | above (1,999 laps) |
|---|---:|---:|
| sold | 22.76 M | 120.83 M |
| bought | 25.73 M | 101.02 M |
| stock carried out less carried in | -0.01 M | -0.71 M |
| profit tax | 0.20 M | 2.16 M |
| wages | 0.11 M | 0.35 M |
| stores | 0.02 M | 0.04 M |
| repairs | 0.01 M | 0.02 M |
| insurance (less paid back) | -0.06 M | 0.07 M |
| **lap net (the book)** | **-3.27 M** | +16.46 M |
| dock fees (the ledger; not in the book) | 0.81 M | 1.48 M |
| net after fees | -4.08 M | +14.98 M |

The houses under water **sold their goods for 2.97 M less than they paid for them**. Fees are 0.81 M of their 4.08 M; tax, wages, stores,
repairs and insurance together 0.28 M. The gap is in the sale price, not in a cost the plan forgot.

**3. Which sales.** Every losing lap of that hour by its cause (4.52 M in all):

| cause | laps | net |
|---|---:|---:|
| a sale below cost (the parcel's cost known from the kept laps) | 170 | -3.06 M |
| a sale of older stock below cost (bought more than 7 laps ago) | 38 | -1.11 M |
| a raid (the insurance paid out) | 4 | -0.17 M |
| traded nothing at all (stores and repairs only) | 510 | -0.05 M |
| other (small costs on a thin lap) | 412 | -0.13 M |

**92 % of the loss is sales below cost.** In the orders still kept (each route's newest lap, one hour): 573 at-profit sales, none at a loss,
+6.05 M; 120 sales by the cut-loss line (`SELL <good> ALL`, no limit: 0142), 93 of them at a loss, -1.28 M. Following each parcel through the kept
laps: 2,801 sold at the next stop at a gain (+21.5 %), 3 at a loss; 1,355 carried on and sold later at a gain; **354 sold at a loss, 335 of them
after being carried five stops or more, at 21.6 % under cost.** So: a parcel is bought, her at-profit SELL is refused at the harbour it was bought
for, she carries it for laps (her hold full: 178 BUYs refused E_HOLD_FULL in the same sample), and after two refused laps the cut-loss lets it go.

**4. Why the sale is refused where the planner said it would pay.** Of 3,907 parcels bought, 2,880 sold on first arriving, 872 were refused
E_PRICE_LIMIT, 149 E_CITY_BROKE (26 % not sold). Two causes, both measured:

- **The city's purse (the root in the planner, fixed here).** By the purse of the city the parcel was bought for:

  | the sink's purse | parcels | their cost | not sold whole on arriving | loss later on sales below cost |
  |---|---:|---:|---:|---:|
  | under a quarter of the parcel's cost | 543 | 66.9 M | 76 % | } -3.1 M (62 % of it) |
  | under the parcel's cost | 309 | 32.6 M | 64 % | } |
  | one to five times it | 468 | 34.0 M | 52 % | -0.58 M |
  | more than five times it | 2,587 | 125.5 M | 30 % | -1.35 M |

  At 08:52, of the 906 BUY lines standing on sailing merchants' routes, **293 (32 %; 40.6 M d.) are bound for a city whose purse is smaller than
  the parcel** (at 08:35: 232 of 918; Luanda held 2,170 d. with 13 lines worth 2.96 M bound for it). 40 of 249 cities hold under 10,000 d.
- **The price walks (not fixed here; the owner's knob).** `drift_sigma` 0.03 a `drift_slot_seconds` 60: every price in the world steps about 3 % a
  minute at random. Measured on `price_history` over three hours: with NO change of stock, a price moves a mean 7.0 % in ten minutes and falls more
  than 5 % in 28.5 % of ten-minute spans. A leg takes 4 to 16 minutes; the planner asks 5 % (`npc_min_return_pct`) and sells only above cost + 5 %
  (`npc_sell_margin`). That is the 30 % refused even at rich cities, and the reason one hour of one house says little.

**5. Laps that trade nothing and still pay a dock fee at every call** (1,143 of 5,735 kept laps, 20 %; 498 of 2,694 in the last hour):

| what happened | laps |
|---|---:|
| she carries a parcel her harbour refused (60 to 80 thousand d. at cost), her SELLs refused, her BUYs refused E_HOLD_FULL or for want of coin | 530 |
| she carries such a parcel and the plan wrote no BUY (0186: sails in ballast; 0181 lays up only an empty hold) | 229 |
| empty hold, every BUY refused E_PRICE_LIMIT at the quay (the ask walked past her ceiling between the plan and the quay) | 381 |
| empty hold, E_DAILY_CAP | 3 |

Two thirds of them are the same stuck parcel again: until the cut-loss frees her hold she can buy nothing and still pays every call. The last
third is the price walk on the buying side: she finds her parcel too dear, sails the leg empty anyway, and pays the fee. That one is NOT fixed
here (see "Not done").

**6. The lap's book and the purse are two lists** (verified: Don Rodrigo Valdés' house shows +247,507 over its last 100 laps with a purse of 0,
55 of them losing and 36 trading nothing; nine other broke ordinary houses alike). `cmd.standing_route_close_lap` takes sold, bought, supplies,
repairs, wages, taxes and insurance; **not the dock fee** (0237 added the charge; nobody told the book). The invest rule's donations are of the
house, not of a lap, and are not touched here.

## The root, in the code

- **0122** (`a_city_keeps_a_purse`) gave the sale door the empty-purse rule: `cmd.do_sell` sells a city only what `public.treasury_balance`
  covers, refuses E_CITY_BROKE past it, and a purse under its reserve bids down to half (`public.city_bid_factor`). 0233 made the purse pay the
  whole sale once the economy closed. The leg planner (`public.npc_leg_lines`, 0114 / 0129) sizes a parcel by the sink's price, her daily cap, her
  purse and her hold. **It was never told about the sink's purse.** The same shape as 0237's dock fee, which the planner was told about only in
  0406: a door learned a rule and the planner, which promises what the door will do, did not.
- **0237** added the dock fee to `public.port_call`; the lap's book was not told (0406 said so and left it).
- There was no list of what a lap costs, so nothing could notice either gap.

## What 0410 does

Six hunks over three bodies (each asserted to occur once and to reverse), one column, one table.

1. **The planner.** `public.npc_leg_lines` reads the sink's purse once a leg (`public.treasury_balance`, the door's own reading) and sizes each
   parcel so that what the purse pays of its sale (the door's own line: `round(total / haul)`, haul 1 while the economy is closed) is within what
   the purse has left after the parcels already kept on the leg. Too big: shrunk until it fits. Cannot fit: not kept, the next good is tried.
   The keep test and the loop's net then judge the smaller parcel, so a loop to a city that cannot pay stops being "a loop that pays".
   Purses dark: nothing read, every plan as it was. Every purse rich: the plan is the pre-image's, row for row (asserted).
2. **The book.** `standing_route_laps.fees` (new). `public.port_call`, the one writer of a port call, adds the fee it charges to the fleet's open
   lap; `cmd.standing_route_close_lap` takes it from the lap's net. Stats, earnings, the month's book, "stop after losing laps" and reputation
   read that net and follow. For players' routes too. Laps already closed are not rewritten.
3. **The list.** `public.lap_costs`: a row per ledger kind a house can be charged by: does a lap pay it, which column of the book keeps it, which
   function the planner prices it by, or why it does not (REPAIR, INSURANCE, HIRE are entered as not planned, with the reason).

## The guard (so it cannot come back silently)

- **Proof 105** (`scripts/db/proofs/105_a_lap_pays_every_cost_on_the_list.sql`, 4 markers). It sails REAL laps (the whole roster by the arrivals
  beat, the lap starts and the reconcile, the economy closed and the purses lit) and reads what the purses were really charged from the ledger.
  - LC_LIST: a charge of a kind that is not in `public.lap_costs` fails. **Red first, for real: the first run failed on OFFICER_WAGE and TUITION**,
    two charges nobody had classified; they are entered now (of the house, not of a lap).
  - LC_BOOK: every closed lap's net must equal sold less every listed column of the book (the sum is built from the list) plus stock out less
    stock in; and the fees charged must be in the books.
  - LC_PLAN: every listed price must be called by the planner's bodies; the costs "a lap pays, the planner does not count" must be exactly
    REPAIR, INSURANCE, HIRE: a new uncounted cost cannot be entered without editing the proof.
  - LC_PAYS: no probe merchant sails with cargo a loop that leaves her nothing or less after every listed planned cost, each by its own function.
- **Proof 104** (`104_a_merchant_carries_only_what_the_citys_purse_can_pay_for.sql`, 3 markers, 7 s): six merchants; every purse rich, short (half
  of what her dearest stop takes: 4 kept their loop with what the purse covers, 2 wrote another loop) and empty: no BUY line is ever past what the
  harbour it is bound for can pay, by the door's measure.
- **The health check**: `scripts/ops/harness/under-water/after.sql` (read-only; `before.sql` is the same read). Houses under water with ALL
  costs counted over six hours and over one; laps that traded nothing; sales below cost; BUY lines bound for a purse that cannot pay.
  **`health.six_hours.under_water_pct` should stay under 12** (15.7 before); `purse.cannot_pay_pct` under 10 (32.3 before).
- **Proof 101** (0406's) now makes every city rich in its scene: the cached world's purses are empty, and with 0410 a merchant buys nothing for an
  empty city, so its fee test had nothing to test. Green again, 5 of 5.

**Which check should have caught this and did not.**
- Proof 12 (MERCHANT_AFK_LAP) is the only proof that sails merchant laps, and it sails them with the purses dark and asserts one probe lap with
  net above nothing. No proof sailed a lap against a city that could not pay, and none compared what the purse was charged with what the plan and
  the book count. Proof 105 is that proof.
- 0406's own proof (101) and its simulation price the plan with the planner's own arithmetic: they prove the planner agrees with itself.
- The Stats' losing count and 0406's hourly check read `standing_route_laps.net`, which left the dock fee out, over a window (an hour) in which
  chance alone puts three houses in ten under water. The alarm was both too kind (no fees) and too noisy (an hour).

## Measured before the deploy (prod, 08:52 UTC, `before.sql`)

cut: all false; hunks: all six once; six hours: 830 houses, 130 under water (15.7 %), losers -6.56 M, all +85.1 M; hour: 748 houses, 234 under
(31.3 %), losers -3.3 M, all +11.2 M; laps in the hour 2,694, losing 1,138, traded nothing 498 (18.5 %); newest laps: 79 sales below cost
(-0.82 M), 651 at a gain (+7.64 M), 677 SELLs refused on price, 42 E_CITY_BROKE; BUY lines 906, 293 bound for a purse that cannot pay (32.3 %,
40.6 M); fleets 885, laid up 176, sailing 395.

## Expected on prod, honestly

- `purse.cannot_pay_pct` falls from 32 % to a few per cent within one lap round (about an hour): this is the direct effect and must show.
- Sales below cost fall as the stuck parcels already aboard are let go: over three to six hours. 62 % of that loss came from parcels bought for a
  purse too small; I expect the six-hour share to go from 15.7 % towards 10 % and the hourly one from about 31 % towards 22 to 25 %. **The hourly
  share will not go near zero**: the price walk alone refuses about three parcels in ten.
- More merchants laid up (tens, of 885) and fewer goods carried to the 40 to 70 poor cities. Those parcels were not all bad: they also made
  +15.6 M of gains in the kept laps, sold a part at a time. So **the merchants' total gain may fall a little** while fewer houses sink.
  This is an estimate from the reads above, not from a run.
- The Stats' merchant profit drops by about the dock fees (2.3 M an hour) at once: the book now tells the truth; no money moved.

## Proof run here (cached world, head 0407 + 0410)

- The file's self-assert: six hunks once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; one
  merchant planned by the live planner with every purse rich before and after the cut (the same plan, row for row) and with every purse at
  nothing (no BUY past a purse); one port call on an open lap and the lap closed (the lap keeps the fee, its net is less by it).
  2.2 s here. In this world the probe merchant's one port call charged 0 (so that arm only shows the book and the call agree); the fee landing in
  the books is proved on real laps by proof 105 (180,117 d. of dock fees in 95 closed laps' books).
- Proofs 101 (5 of 5, 32 s), 102 (7 of 7), 104 (3 of 3, 7 s) and 105 (4 of 4, 218 s: it sails the whole roster) green. 105 was red first on OFFICER_WAGE and TUITION.
- Prod's three live bodies are the cached pre-images (md5 npc_leg_lines fbea55693fbf12054c8edd8fe29dcfee, port_call bf6b10f20b729f6e1208c04b7d5a1ba7, standing_route_close_lap ecdd93d7172f4c051a7add0c21a1ae9c; read at head 0407 and the six hunks counted once each again at head 0408)). The rollback draft, run on the cached world after the file, restores the three pre-image md5s.
- `before.sql` passes the read-only reader and ran on prod (above). The rollback draft is generated from the file's own hunks.

## PROD CHECKS

1. Before: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/under-water/before.sql`. Wanted: head ...0409; `cut` all false;
   `hunks` every count 1; volatility s. Write down `health`, `purse`, `newest_laps`, `laps_hour`, `fleets`.
2. Deploy: `~/bin/bv-deploy.sh <pr>`. Expected under 10 s on prod.
3. After, at +1 h, +3 h, +6 h, +24 h: `... -f scripts/ops/harness/under-water/after.sql`. Wanted: `cut` all true; `purse.cannot_pay_pct` under 10
   at +1 h; `newest_laps.below_cost_loss_k` falling; `health.six_hours.under_water_pct` under 12 by +6 h (it looks back six hours, so it is only
   wholly after the deploy from then); `fleets.laid_up` may rise by tens.
4. If the lay-ups jump by hundreds or `health.six_hours.sum_k` falls by more than a third: the forward rollback draft is
   `scripts/ops/harness/under-water/rollback-0410.sql` (owner only; rows 1 to 4 alone reverse the planner and keep the book).

## Not done, and not verified

- **The price walk** (3 % a minute) is the other half of the refusals and of the empty-hold laps. It is `drift_sigma` / `drift_slot_seconds`,
  the owner's knobs; no change proposed here without a measured run.
- **A merchant whose every BUY is refused at the quay still sails the leg empty and pays its fee** (381 laps in the kept sample). Not fixed.
- **Two merchants bound for the same city each see its whole purse.** The purse is not reserved between plans.
- **REPAIR, INSURANCE and HIRE are not priced by the planner** (on prod, merchants, one hour: repairs 29 thousand, insurance 185 thousand less
  199 thousand paid back, hire 3 thousand, against 2.3 M of dock fees). They are in the list as not planned; the proof holds that set fixed.
- The size of the effect on prod (no simulation was run; the cached world's purses are empty and its market fresh).
- The coordinator's totals for the 14 broke houses' fees, tax and donations (the ledger older than six hours is gone); the +247,507 with a purse
  of 0, the losing and the traded-nothing counts are verified.
- No screen shows `fees`.

## Decided by default

1. One migration carries the planner fix, the book's fee and the list, because the owner asked for the root and the guard together.
2. The purse is the door's live balance at the plan; no reserve against other merchants' plans.
3. The book's fee is for every route, players' too.
4. The new proofs are 104 and 105 (103 was left for the slice in flight beside this one).
