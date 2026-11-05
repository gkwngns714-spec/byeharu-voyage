# 2026-11-05 - Merchants invest their surplus (migration 0313)

Branch `merchants-invest` · migration `supabase/migrations/20260818000313_merchants_invest_their_surplus.sql` · proof `scripts/db/proofs/21_merchants_invest.sql`
· mutation harness `scripts/ops/harness/merchants-invest/proof-0313.mjs` · prod checks `before.sql`, `after-check.sql` beside it. **Not deployed** (PR only). Prod head when cut: 0310. **0311 (#494) and 0312 (#495) deploy first; rebase then.** Alters live play.

## The order
Owner, 2026-11-05: merchants should spend and invest their surplus in cities so city purses rise. In the existing door, no second mechanism, no forced hand-in (0184), no minting. About 100 M d. a day at most at first, with a knob.

## The proven cause (prod, head 0310, about 07:30 UTC, pure SELECTs)

**The shares ran out. The guess was right.** The door itself works.

| Measured | Figure |
|---|---|
| Works at `works_level_max` | **924 of 984** |
| Still on sale | 60 works at 26 ports, **2,447 shares, 11.8 M d.** |
| Shares ever subscribed | 480,853 (`level` × 100 + `subscribed`) |
| Held by houses (`city_shares`) | 183,215 |
| Not held by any house | 297,638, 62 %: the cities' own BUILD step (`tick_city` step 4), the only other writer in the code |
| Works last changed 2026-10-23 to 11-04 | 162 rows, 142 of them finished; 40 on 11-02, 30 on 10-30 |

BUILD spends a city's surplus on its own works and hands the gold to its region (`WORKS_OUT`/`WORKS_IN`). So the cities bought their own shares and left merchants nothing.

**The hour (`reconcile_runs`, last 26 hours):** 574-597 steps an hour, `deferred` 0, `failed` 0, `skipped` 0. **Bought: 2 companies in 26 hours.** Gave: 21-486 companies an hour, 1,956 in 24 hours. The roster is not the limit: 556 companies, knob 1,000.

**Why each company did not buy** (559 on the roster, the live rule replayed read-only, all purses and offers as they stood):

| Her path | Why | Companies | Surplus |
|---|---|---:|---:|
| Race city on her loop | **no share for sale there**, day's gift used up (398) | 398 | 7.99 B |
| Race city | no share for sale there, gives a gift | 27 | 0.54 B |
| No race | **nothing on sale at any stop** | 101 | 1.34 B |
| Race city | shares on sale, but the remainder is under `invest_min_ducats` | 20 | 0.17 B |
| No race | same | 10 | 0.16 B |
| No race | **can buy** | 3 | 3 M |

So 526 of 559 find no share at all, 30 a scrap under the minimum, 3 can buy. Budget, deadline and price are not the cause. One buy per house per hour is real but never reached.

**A second finding the brief did not have: gifts already reach cities at scale.** `DONATED` events: 92.6 M d. in the 6 hours kept; 1,956 donors in 24 hours at about 85,000 d. each is about 165 M d. a day (0312's own record: 159 M). So SHARE's 0.4 M a day is true, but the merchants' money into cities today is about 165 M a day, all to race cities. The 398 above are stopped by `influence_day_cap`, which this file leaves alone.

## What was built (one authority per concept)

| Concept | The one place |
|---|---|
| What a finished work sells | knob `works_open_shares` 100; `public.city_offered`. 0 = today |
| The price | `works_share_price(works_level_max)`, 10,486 d., the next step of the same curve. Never cheaper than the last share sold |
| A lot closing | `public.invest_for`: the last of what is offered closes it. Under the max the level rises as before; a finished work's level stands |
| What one merchant may buy | `public.npc_share_budget(now, player, ducats)`: read by `npc_invest_one` |
| Her hour | `roster_ord % 24`, UTC. One stake a day, 32-35 companies an hour |
| The day cap | knob `npc_invest_day_cap` 100,000,000. Her part = cap / companies on the roster. 0 = no merchant buys |
| Her working cash | the larger of `npc_invest_keep` × capital and `npc_invest_keep_laps` (2) × each route's dearest lap, summed (last 20 laps, none older than 3 days) |

**Why not raise `works_level_max`.** (1) A level changes the world: production, docks, the inn, a city's earnings +10 % a level. Not asked for. (2) BUILD reads the same knob, so the cities would buy the new levels first, with the gold going to the region. Selling lots on a finished work avoids both with no edit to `tick_city`: BUILD reads only works under the max, so it cannot touch them, and a share's gold goes through `pay_city` to the city that sold it.

**The client.** `CityTownHall.tsx`: a finished work reads Built only once it offers nothing, so Invest stands on it, with `0 of 100 sold` and the price. An old client on the new server still shows Built: harmless. **Players can buy these shares too**, through the same door, docked. 0312 records that no human holds a share today.

**The beat (0266/0267).** The stake stays in `npc_invest_one`'s transaction under the quay, and the new read runs for about 23 companies an hour; the others answer at the first test. `npc_invest_roster` read its two knobs once a row: 25 ms a read on prod. Two hunks make it 3 ms, the same rows in the same order, measured as an equivalent SELECT. It is read once by `npc_invest_one` for every company, so it may also trim the companies' step; not measured. Laps, prod, one hour's cohort: 19-177 ms warm and 1.7 s at the coldest, for all 34 companies, before the limit of 20 laps; 143 ms cold after it.

**Gifts are untouched.** A gift still reads `npc_invest_keep` × capital, not the new working cash. Off her hour a merchant does exactly what she did, but for the 20 + 10 + 3 companies above, who now buy only in their hour.

**Decided by default:** (a) one stake a day per merchant, an equal part; (b) lots of 100, no ceiling on how many lots a work sells: the ceiling is the day cap; (c) 2 laps of working cash; (d) a lot's price stays 10,486 d. and does not climb.

## Expected gold a day

Replayed on prod with the exact rule, every company on the roster:

| | |
|---|---|
| Companies on the roster | 558 |
| Her equal part | 179,211 d. (17 shares, 178,262 d.) |
| **Have a stake to spare** | **447** |
| Kept out by working cash | 111 |
| **Gold a day into purses** | **about 77 M d.** |
| Surplus free of working cash | 9.97 B of 10.2 B |

All merchants' money into cities: about 165 M gifts + 77 M shares = about 240 M a day. 77 M a day is 0.8 % of their free surplus. It lands by the race rule first: about 4 in 5 companies have a race on their loop, so most stakes go to race cities.

**Side effects that come with the gold, by design, none of them new mechanisms:** SHARE counts for influence (a 0144 rule), so race cities see up to 47 % more coin than today's gifts (77 M on 165 M; not all stakes go to race cities): watch flips. It counts in `invested` (half-life 72 h): at 77 M a day that settles near +333 M on today's 696 M, restock and depth up in the cities that sell, population's INVEST signal too. It lands on the town hall boards. Each of these is a real change to play; none was simulated.

## What the new shares cost in dividends

From 0312 (PR #495): `works_coupon_day` 0.09 of `paid` a real day, `payable = least(due, surplus, profit)`, once a day at 00:37, nothing carried.

| Day | New shares paid | New coupons due a day |
|---:|---:|---:|
| 1 | 77 M | 6.9 M |
| 10 | 770 M | 69 M |
| 11 | 847 M | 76 M, as much as comes in |
| 30 | 2.31 B | 208 M |

On top of 62 M due today on the 693 M held (0312: about 12 M actually paid).

**0312 caps this: no city can go into a daily loss for its coupons.** So the runaway I first feared does not exist. **But 0312 counts SHARE as profit**, so share gold can leave again as a coupon the same night. 50 M a day of today's coupons go unpaid only for want of profit and surplus; the new gold unlocks them where it lands. Bound, not a measurement: day 1, 20-77 M of the 77 M stays in purses; by about day 4, worst case, close to none stays, the gold going straight back to merchants. Real figure unknown: it depends on which cities sell.

**OWNER'S CHOICE, not made here (coupon code is 0312's):** take `SHARE` out of `public.flow_is_profit`, one word. Then share gold stays in the purse and coupons are paid from trade alone, which is what "so city purses rise" needs. 0312's PR flagged the same. The file does not touch it.

**Do not deploy before 0312.** At today's coupon (0.3 % a game day, 432 % a real day) each day's 77 M would add 333 M a day of coupons due.

## PROD CHECKS (before the push; pure SELECTs, one statement per file)

`npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/merchants-invest/before.sql`

Expect `head` 20260818000312, every `hunk_*` true, `maxed` about 924, `knobs_already_there` 0. Run at head 0310: all true, 924, 0.

Do not push within two minutes of :07 (the hourly companies' step) or :37.

## After-check (changes live play)

Run at +30 minutes, after the first two :07 hours, and at 24 hours:

`npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/merchants-invest/after-check.sql`

| Read | Pass |
|---|---|
| `failed`, `deferred` | 0 |
| `companies_ms` | not above the week's 8,000-17,000 |
| `hold_max_ms` | under about 130 (the last 26 hours peaked at 127) |
| `bought` an hour | about 15-25 |
| `share_gold` an hour | no more than about 4.2 M |
| `level_above_max` | 0 |
| `merchants_paused` | about 35 laid up (before), no new reason |
| Flips of a city | not above the usual count: read `port_allegiance.since` by hand at 24 h |

Before the deploy, at 07:30 UTC: `merchants_paused` 35 (all `laid_up`), `purses` 23.33 B, `purses_under_floor` 123, `shares_paid` 693.3 M.

## Forward rollback (a NEW migration, owner only)

```sql
update public.world_config set value = '0' where key in ('npc_invest_day_cap', 'works_open_shares');
```

The next hour no merchant buys and no finished work sells; the town hall shows Built again. Shares sold stay held and keep paying. To slow it rather than stop it: lower `npc_invest_day_cap`.

## Verified

- Gate on the cached PGlite world, no from-zero replay: **19 of 19 mutations red first, then the real file and proof 21 green** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/merchants-invest/proof-0313.mjs`).
  The first run caught two holes in my own asserts: a NULL share price passed its test, and a one-merchant world could not tell the cap from her part. Both fixed. One mutation was dropped as equivalent: removing the cap's 0 test changes nothing, 0 / n is 0.
- Proof 21: real `npc_invest` over 821 merchants and real `tick_city`: 35 bought, only in their hour, none above their part, 6,239,170 d. paid = 6,239,170 d. of SHARE, gold unchanged, no level built, no `WORKS_OUT`.
- **Also green with the 0311 and 0312 PR files applied under it** (head 0312, temporary copy, 0313 and proof 21 only).
- `tsc`, `eslint` on the touched files, `vite build`. `tests/rpc.holdings.spec.ts` 2 of 2; `tests/map.townhall.spec.ts` 4 of 4 headless, including Invest on a finished work; `tests/rpc.surface.spec.ts` 29 passed under a name filter, not the whole file.
- Cause, counts, estimate and hunks: read on prod, pure SELECTs. Only `s`-volatility functions called.

## Not verified

- Not run on prod. Not run against a merged 0311/0312: re-gate after the rebase.
- The 77 M is one moment's purses, not a measured day.
- How much share gold stays in purses under 0312: bounded above, not measured.
- Effect on lap stalls: the rule keeps 2 dearest laps, but no lap was simulated. Whether 2 is enough is an after-check question.
- Effect on races, restock, depth, population, prices: not simulated.
- Companies' step time: the cold 20-lap read and the roster gain were measured as SELECTs, not in the hour itself.
- That the 297,638 unheld shares were all BUILD: read from the code, not from a record.
