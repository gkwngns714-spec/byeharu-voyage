# 2026-11-14: a broke merchant of the pirates is given her capital by the hoard (0408)

**State: built, PR open, not deployed.** Prod head 0407. 0408 touches `public.capital_gift_roster` and `public.capital_gift_one` and nothing else.
It changes live play (who is gifted), so it gets an after-check (`scripts/ops/harness/pirate-gift/after.sql`).

## The order

The owner, 2026-11-14, on the broke merchant houses: "do all". Later the same day, of the pirates: "pirate ships don't trade", then reversed:
"actually, make them trade too, but engage combat more aggressively with other npcs and players". The fighting half is another slice (0410).
This slice is the first order as it stood at the end: the pirates' merchants trade, so the broke ones are refilled.

**Decided by default (the owner may reverse it):** a broke merchant house of the pirates gets the same top-up as an ordinary house (her own
capital, by the same roster rule and the same weekly limit), paid through the pirates' own payer `public.pirate_pay` from Port Royal's purse.
This reverses 0341's default ("a pirate merchant is never gifted: the hoard pays her founding and nothing after").

## What was read on production (read-only, 2026-11-14 08:26 to 08:40 UTC, head 0407)

| | |
|---|---|
| merchant houses in all | 869 |
| of the pirates | 24, each founded with 250,000 d., one carlat |
| pirates under the broke line (purse under 20 % of capital) | 14 at 08:26, 15 at 08:39 |
| pirates with a purse under 100 d. | 13, all laid up, 12 of them owing dock fees (8,916 d. in all, 2,989 the most) |
| gifts ever given to a pirate house | 0 |
| ordinary houses under the broke line | 25; 18 of them at the weekly limit of 3 gifts; 9 with a purse under 100 d. |
| Port Royal's purse / the hoard | 980,320,202 / 980,158,465 d. |
| the hoard's room for the day (0.5 % of the hoard, less what was spent) | 4,788,292 d. at 08:26 (spent that day: 112,500) |
| the hoard's spend on the five days before | 335,000 to 485,000 d. a day |
| knobs | `merchant_broke_pct` 0.2, `gift_max_per_week` 3, `gift_cooldown_hours` 24, `gift_max_per_hour` 50, `pirate_spend_day_pct` 0.005 |

## (a) The pirates: what 0408 does

Three hunks over two bodies, each asserted to occur once and to reverse; no knob, no table, no new word.

1. `public.capital_gift_roster`: 0341's line `and (h.human or not public.pirate_power(pl.nation_id))` goes. A merchant of the pirates is on the
   roster by the rule every merchant is.
2. `public.capital_gift_one`: a merchant house (`npc_houses`) of the pirate power is paid by `public.pirate_pay('CAPITAL_GIFT', her capital, p_now,
   p_player := her)`: Port Royal's purse to hers (`public.city_pays`), whole or nothing, inside `public.pirate_spend_room`, written to
   `pirate_spend_day`. Never `public.capital_pays` for her, so no `CROWN_CALL` and nothing outside the cap. Then the pass's own lines, unchanged:
   the `capital_gifts` row (it is what counts her week and her cooldown), `port_fee_collect` (her debts first), `news_gift`.
   Her `CAPITAL_GIFT` event carries the payload every gift's does.
3. `public.capital_gift_one`: when the hoard cannot pay her whole capital now (the day's room, Port Royal's surplus, its purse busy at that instant,
   the pirates dark) the sub-block is rolled back, she is counted in `gift_waiting` and nothing is written. She is on the roster again next pass.
   **Decided by default:** no `GIFT_WAITING` event for her (a purse busy for a second is not news).

A company (a player) sailing for the pirates is paid as before, by `capital_pays`: untouched.

### What it should lift, and what it costs

- At the first hourly pass after the deploy: the 13 houses with nothing, and the one or two more under the line: **14 to 15 houses, 250,000 d.
  each, 3,500,000 to 3,750,000 d. from Port Royal's purse.** The room that day was 4.77 million and the ships' pay (60,000 d. a ship a day) comes
  out of the same room, so if the deploy is late in the UTC day the last one or two wait until after 00:00 UTC. Nothing is lost by waiting.
- Their debts (8,916 d.) are paid out of the gift first, to the harbours owed.
- The worst case after that: every one of 24 houses three times a week, 18,000,000 d. a week, 1.8 % of the hoard. The day's room (4.9 million)
  holds it without a new rule. The money goes to the harbours they buy at and pay fees and tax to: nothing is minted, nothing leaves the world.
- **This does not make them profitable.** The 13 lost their 250,000 d. in one to four days each: of their last 100 laps, 57 to 85 lost money, and
  the sum of those laps was a loss for 11 of the 13 (between 4,146 and 145,450 d.), before dock fees (the lap's book does not count them). If the
  loops still lose after 0406 and 0409, each gift is spent the same way and the weekly limit is what stops it. Read `after.sql` at +24 h and +7 d.

## (b) The ordinary houses: why they empty again inside the week

**It is the losing-loop problem, not the gift rule. Nothing is changed for them here** (0406 is live since today; 0409 is another builder's).

- The gift works as written: each of the 18 got her capital (25,000 d. for 17 of them) up to three times in seven days and lost it each time.
- A merchant's ledger is kept for hours only, so the read is of the 14 houses whose ledger still had trade in it: they sold 6,412,503 and bought
  6,177,974, so trade made **234,529 d.** Against it: dock fees **186,876**, profit tax **138,793**, wages, insurance, stores and repairs **38,387**:
  364,056 d. of costs on 234,529 of margin, **a loss of 129,527 d.** The same houses gave away 697,413 d. in donations when they were above twice
  their capital (the invest rule keeps 1.5 times capital), so the cushion before the fees is thin. That is the invest rule, not the gift's.
- The laps look healthy because the lap's book has no dock fee in it: Casa de Ramírez shows +247,507 d. over her last 100 laps with a purse of 0.
  House by house, 34 to 72 of the last 100 laps lost money even before fees, and 16 to 54 traded nothing at all and still paid a fee at every call.
- Not the cause: no raid in their kept events; no wage is taken from a laid-up house (their ledgers show nothing moving).
- Their last gifts were on 11-10 to 11-13, before 0406 (the planner counts the dock fee) went live, so 0406's effect is not in these numbers yet.
- For scale: the crowns' pass gave 117 gifts, 5,825,000 d., in the 24 hours before the read.

## Proofs

- **The migration's own self-assert:** each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function
  moved (md5 over every one). Then the probe, in a rolled-back sub-transaction: ONE broke merchant of the pirates not gifted in eight days gets her
  turn in the pass. Paid: one gift row and one ledger row of hers at this instant, the day's spend up by her capital, she off the roster after.
  Or, if Port Royal's purse is busy or the room short at that instant: waiting 1, nothing written. Both arms were run locally on the cached world
  (a throwaway proof with the probe's lines pasted in, the room at 0.005 and at 0): both passed. It reads only its own rows.
- **Proof 103** (`scripts/db/proofs/103_a_broke_merchant_of_the_pirates_is_given_her_capital_by_the_hoard.sql`, 6 markers, local: 6/6 in 0.7 s):
  PG_ROSTER, PG_ROOM (no room: waiting 1, nothing written), PG_PAID (250,000 d. from Port Royal, one gift row, one ledger row, one event, the
  spend book, no CROWN_CALL), PG_WEEK (cooldown; three in seven days and no fourth; a fourth when the first is seven days old), PG_CROWN (a crown
  merchant's turn is what it was and does not touch the hoard's book), PG_MONEY (W unchanged to the ducat).
- **Proof 47** (0341's): its marker PM_NO_GIFT asserted the rule this slice reverses. It is now PM_GIFT_ROSTER (she is on the roster, her payer
  Port Royal). Local: 12/12 in 3.2 s.
- Not run locally: anything from zero, the whole proof suite (CI's).

## Prod checks

- Before: `scripts/ops/harness/pirate-gift/before.sql`. Read 2026-11-14 08:40 UTC: head 0407, applied false, hunks 1/1/1, every function it calls
  stable, economy closed, pirates on, capital POR, 24 houses, 15 broke, 13 under 100 d., 13 laid up, on_roster 0, room 4,773,253.
- After: `after.sql` (the same read). Wanted: head 0408, applied true, hunk 1 at 0; after the next hourly pass `pirates.gifts_7d` 14 to 15,
  `spend_today` up by 250,000 a gift, `under_100` near 0; within the hour after, `laid_up` falling.
- Rollback: `rollback-0408.sql`, a draft (the three hunks reversed). Gifts given stay given.

## Could not establish

- Whether the gifted pirate houses will keep their money: that depends on 0406 and 0409, not on this rule.
- Why Hwang Dohoe (an ordinary house, 1 gift in the week, purse 0) has a `GIFT_WAITING`: her capital's realm was short once; not followed.
- Seen in passing, not this slice's: all 7 pirate SHIPS (`public.pirate_ships`) were `UNABLE_TO_SAIL` with hull 0 at 08:30 UTC. Ships 2 to 7 wait
  for a 40,000 d. refit their home's purse must pay (the two sampled, at Djerba and Goto, say `REFIT_WAITING`, "broke"); ship 1 is refitted by
  Port Royal and arrives wrecked again after a quiet voyage. Whoever builds the fighting slice should read this first.
