# 2026-11-14: a pirate ship trades, the pirate cities fund an empty purse, no wreck waits on one empty purse (migration 0415)

**State: built, PR open, not deployed.** Migration 0415 (written as 0412, renumbered). The order on production: 0409 slimming, 0410 merchants, 0411 levels, 0412 the sweeper, 0413 THE ONE-HOUR DAY (all live, head 0413), then 0414 the pirates' homes (PR #678), then this. **Rebuilt 2026-11-14 on `pacific-pirates` `4d52a559`** (PR #678 as merged with origin/main `517bf154`): the hunks' pre-images are main's bodies with 0414 on top. **No production read was made for this slice** (the live database was IO-bound): everything below is from the code, the local world and what the earlier builders read. The reads still wanted are listed at the end.

## What the owner ordered, in his words

1. "pirate ships don't trade. they only do and engage combat", then reversed: "actually, make them trade too, but engage combat more aggressively with other npcs and players".
2. "each pirate ship should have a home city ... and will be restock, rebased, fixed when they lose and their ships destroyed (respawn)" (PR #678).
3. "the pirate cities will fund those that have empty purse." On the amount: "just enough to start", then taken back: "not just enough to start, just like before./"
4. Of every fault of the day: "find the root cause, make it so that this problem does not occur again".

## A. A pirate ship trades, as the one ship she is

**The choice, and why.** Two shapes were weighed.

- *Her house as a merchant house with a standing route, the pirate job adding the raids.* Not taken. One fleet would be in two tables: `public.fleet_kind` answers MERCHANT first (so the raid rule, the navy's hunt and the pirate sheet would stop seeing a pirate), `public.crown_house` would still waive her wage and dock fee, the merchants' tend AND `public.tick_pirates` would both move her, `public.pirate_pay_hour` would pay a merchant, and her position (`sea_id`, which decides who raids) is written only by the pirate cruise. Each of those is a re-cut of a body the merchants' files cut this week.
- *She stays a pirate ship and trades at the two harbours her cruise already calls at.* **Taken.** Nothing moves her but the pirates' own job; her raiding is PR #678's to the letter; trading is one call at the two moments her step already sends her to sea.

**What a pirate ship does in an ordinary cruise** (every pirate ship: the 13 of 0339 and the roster's):

1. At her **home**, on duty: mended free (as before). NEW: she sells what she brought and buys a cargo for her haunt. She sails for her haunt; her sea is the haunt's sea, where she is the named raider and adds to the sea's danger (as before).
2. At her **haunt** she lies `pirate_haunt_hours` (12 real hours), raiding from there (as before).
3. Leaving the haunt: NEW: she sells the cargo from home and buys one for home. She sails home, in no sea (as before).
4. Off duty (switch off, unpaid, not wanted) she only sells on her way home and is laid up.
5. Wrecked: PR #678's home rule, unchanged. Her hold is lost with her (the game's rule for every NPC wreck).

**How she sells** (`public.pirate_trade`): each good aboard goes to THE sale door, `cmd.do_sell`, with a limit of what it cost her times (1 + `npc_sell_margin`). So **no sale is ever made below cost**, and the door's own empty-purse rule (0122 / 0233) pays her only what the city's purse holds; what is refused stays aboard and is offered again at the next harbour. A good whose cost the hold does not know is not offered.

**How she buys** (`public.pirate_cargo_plan`, a plain read, then THE buy door `cmd.do_buy`): the merchants' own measures in the merchants' own order: the ranking `world.trade_routes`, the size the sink takes above cost plus the margin (`world.quote_priced`), the day's cap at both ends, the hold left, what her house can pay (`public.npc_affordable`), **and 0410's rule: no more than the sink's live purse can pay, by the door's own measure**, the purse falling with every parcel kept. A parcel is kept only if it pays `npc_min_return_pct` after the sink's profit tax; at most `npc_lines_per_stop` goods.

**What she may spend:** what her house holds above the gift's broke line (`merchant_broke_pct`, 20 %, of her capital). So buying a cargo never makes her "broke", and a house at the line buys nothing until it is funded. (A first cut kept back her refit instead, half her capital: a house left between 20 % and 50 % then neither traded nor was gifted, for ever. Found before the PR; proof 114 holds it.)

**What it costs her:** nothing but the cargo. A pirate ship's house pays no wage and no dock fee (0339), her stores and hands are free, the hoard pays her upkeep. She pays the profit tax of the city she sells in. So the only way trading loses her money is a wreck with a cargo aboard.

**The economy stays closed.** Every ducat is `public.pay_city` or `public.city_pays`; every tun is the doors'. proof 114 holds the world total to the ducat through gifts, trades and refits.

**A hub starts with a purse of 0** (PR #678), so under 0410 nothing is planned INTO it. It fills by her own buying: what she pays for a cargo at her hub is the hub's purse, and the hub can then pay for what she brings back. In the proof's day the two hubs went from 0 to 87,450 and 40,321 d.

**Not done, said plainly:** plunder still lands in her HOME's stock (`public.pirate_stow`, 0339), not in her hold. She buys it there like anyone (it makes her home's price low, so it is what she tends to carry out). Gear is not restocked (the game tracks none for an NPC ship). Weak and strong are not placed in different waters of one sea. No screen shows her cargo.

**Knob:** `pirates_trade` (true). False: she cruises and raids and trades nothing; what she holds stays aboard.

## B. The pirate cities fund a pirate ship's house with an empty purse, "like before"

It is 0408's rule: the same roster (`public.capital_gift_roster`), the same body (`public.capital_gift_one`), the same line (purse under 20 % of her capital), the same `gift_cooldown_hours` (24) and `gift_max_per_week` (3), the same book (`public.capital_gifts`).

- **Who asks:** the pirates' own job, once an hour (`public.pirate_gift_hour`), for every house of a pirate ship at work under the line, the smallest capital first. Her house is admitted to the roster ONLY when asked for alone, as a player's company is (0241). Why: the merchants' hourly pass takes at most 50 houses, never-gifted first. 116 pirate houses waiting on a short day would have taken every place every hour and no ordinary merchant would have been gifted.
- **Who pays** (`public.pirate_gift_pay`), whole or nothing: her **home city**; else **another city the pirates hold, the richest first**; else **Port Royal's hoard** (`public.pirate_pay`). A city pays from its surplus only. All of it inside the day's room (`public.pirate_spend_room`) and written to the day's spend.
- **A gift never takes the pay's room:** a house is paid only if the room left, less what the rest of the UTC day's pay of the ships at work still needs, covers it. Without this, a morning of gifts could leave the fleets unpaid by evening; an unpaid pirate sails home and is laid up.
- A merchant house of the pirates is paid exactly as 0408 pays her (the hoard); nothing of hers changes.
- `pirate_spend_day_pct` is **not** changed (it is PR #678's: 2.4 times what the clock's door leaves, 0.0024 on the one-hour day).

**Her capital** (`public.pirate_house_capital`): `pirate_house_capital_pct` (0.5) of what her hulls cost to build. The arithmetic: a refit is `npc_refit_share` 0.25 of the build cost and a house with a purse pays her own refit first (PR #678's order), so half the build cost is one refit and as much again to buy a cargo with. A lone carlat merchant of the pirates has 250,000 (0341), 1.8 times her hull; a pirate ship's house has less because she pays no wage, no dock fee and no upkeep.

| Kind of house | Hulls | Build cost | Capital | Houses | Together |
|---|---|---:|---:|---:|---:|
| lone fusta | 1 | 76,000 | 38,000 | 18 | 684,000 |
| lone brigantin | 1 | 80,000 | 40,000 | 36 | 1,440,000 |
| lone xebec (roster) | 1 | 160,000 | 80,000 | 18 | 1,440,000 |
| lone xebec (0339's) | 1 | 160,000 | 80,000 | 13 | 1,040,000 |
| pair of xebecs | 2 | 320,000 | 160,000 | 13 | 2,080,000 |
| Flores squadron (korsan + 3 xebecs) | 4 | 880,000 | 440,000 | 3 | 1,320,000 |
| Flores house with two fleets | 6 | 1,200,000 | 600,000 | 1 | 600,000 |
| squadron (galeoncete + 3 xebecs) | 4 | 1,416,000 | 708,000 | 10 | 7,080,000 |
| house with two fleets (pair + squadron) | 6 | 1,736,000 | 868,000 | 4 | 3,472,000 |
| **all** | 193 | 38,312,000 | | **116** | **19,156,000** |

**Worst case a week** (every house under the line three times in seven days): pirate ships' houses 3 x 19.16 M = **57.5 M**, the 24 merchant houses 18 M (0408): **75.5 M a week** asked for.

**What can actually be paid, on the one-hour day (0413).** 0413 divided the rates per real day by 5: `navy_upkeep_day` 12,000 and `pirate_spend_day_pct` 0.001, which 0414 multiplies by 2.4 to 0.0024. Of a hoard of 980 M (read by the earlier builders):

| A real day | old clock (as first written) | one-hour day |
|---|---:|---:|
| the day's room | 11.8 M | 2.35 M |
| pay of 121 fleets, kept back first | 7.26 M | 1.45 M |
| left for gifts, refits and building together | 4.5 M | 0.90 M |

So about **6.3 M a real week** is left, against a worst case of 75.5 M asked (the gift's cooldown and weekly limit are real-time pacing and were not moved by the clock; a capital is a price paid once and does not scale either). The houses wait, cheapest first, and nothing is lost by waiting. In order of cost: the 54 lone weak ships need 2.1 M together, the 31 lone xebecs 2.5 M, the 13 pairs 2.1 M, the 18 houses with a squadron 12.5 M. If the room were spent on gifts alone the weak ships and xebecs are funded inside the first week and the squadrons take two more; but building the roster (36.2 M, PR #678) draws on the same 0.90 M a day, so in practice the squadrons' houses wait weeks. **This is the same shortage PR #678's dev-log now states for building, and it wants the same decision** (a larger room during the rollout, or one-off payments counted apart). This file adds no rate per real time, so nothing is added to the list `public.clock_set` scales: `pirates_trade` is a switch and `pirate_house_capital_pct` a share of a build cost. The five hubs start at 0 and Djerba, Goto and Lingga hold little, so in practice the payer is the hoard until the hubs have earned.

**How long it lasts if the pirates keep losing.** The hoard cannot fall faster than the room: 0.24 % a real day on the one-hour day. From 980 M: about 912 M after 30 real days, half after about 290 (on the old clock it was 1.2 % a day: 680 M after 30 days, half after 58). It does not reach zero: as the hoard falls the room falls, gifts wait first, then refits wait (loudly), then the room falls under the pay and the last fleets are laid up. The gift does not add a new drain: a house with a purse pays her own refit, which the cities would otherwise have paid. What is new money out is cargo lost in wrecks, at most what a house holds above the broke line at each wreck.

## C. No wreck waits on one empty purse (merchants, cargo ships, navy ships)

**The fault** (PR #678 fixed it for pirate ships only): `public.npc_refit_step` (0322) let ONLY the wreck's home (a navy ship's station) pay. A home with an empty purse and she sat for ever. Nobody was stuck that way on 2026-11-14, but nothing prevented it.

**The rule now** (`public.npc_refit_payer`, called by the step):

1. her **home** (station), when its surplus covers the refit: as before;
2. behind an empty home, **her country's capital**; then **the richest other city her country holds**. Her country is the crown's for a cargo or navy ship (`public.crown_nation`), her house's nation for a merchant. A city pays from its surplus, never the yard that is to be paid;
3. a ship of the pirates' **merchants**: Port Royal's hoard alone, inside the day's room;
4. every payer dry: she waits as before: a row in `public.npc_refit_waits`, one `REFIT_WAITING` event a day, and the hourly job asks again. No hull is restored unpaid.

Whole or nothing, city to yard, kind REFIT, moved. Her `REFITTED` event names who paid (`paid_by`).

## The guards

- **proof 114** (`scripts/db/proofs/114_a_pirate_ship_trades_and_no_wreck_waits_on_one_empty_purse.sql`, 8 markers, 1 s):
  - `PT_GIFT`: three empty houses paid 40,000 by the home, 80,000 by Djerba (the home short), 708,000 by the hoard; none on the merchants' roster; world total unchanged.
  - `PT_WEEK`: none inside the cooldown, three in seven days and no fourth; with a room that covers her gift but not the day's pay as well she waits and nothing is written.
  - `PT_PLAN`: bound for a harbour with no purse she plans and buys nothing; with 3,000 there every plan is within it; with a rich sink within what she holds above the line; at the line she plans nothing.
  - `PT_DOOR`: a cargo of 17,974 met a purse of 1,500: she was paid 1,299, kept the rest, the purse never under nothing; no sale of hers below cost.
  - `PT_DAY`: over 25 real hours of the job (home, haunt, home, haunt; arrivals set by hand) six fleets of two hubs that trade net **+87,057 d.** together (a brigantin 3,809 to 12,028, a xebec 10,787 to 15,682, a squadron 40,741; no fleet at a loss); the same fleets with trading off net 0.
  - `PT_JOB`: a run of the job steps no more ships after one that traded and leaves the pay and the gift to a later minute.
  - `PT_REFIT_M`, `PT_REFIT_N`: a merchant and a navy ship wrecked with an empty home are mended, the capital paying; every city of the country dry: a row and an event, no hull unpaid; a purse back, mended.
- **The health check:** `scripts/ops/harness/pirate-trade/after.sql` (`waits.others_over_3h` should read `{}`), and PR #678's `health.sql`, which already counts every NPC ship waiting over three hours by kind (not edited: it is that PR's file).
- **Proofs moved with the rule:** 30 (`NPC_BROKE_WAITS`: she waits only when every city of her country is dry), 37 (a navy ship the same), 46 (a pirate house may hold a purse now and pays her own refit first; the arm that proves the HOME paying gives the purse back first).

**Honest limits of `PT_DAY`.** The local world's market is fresh, every foreign city was given 2 M, there is no navy and no raid in it, and an arrival is set by hand. It shows that the rule earns and cannot sell at a loss; it is not a forecast for production. On production the navy took every pirate it met on 2026-11-14 (ship 1 was wrecked 22 times in four days): a weak pirate that is taken with a cargo aboard loses that cargo, so her trading can be a net loss there even though no sale is.

## Load

- Nothing in the arrivals beat.
- In the pirates' own job, measured on the local world (wasm; not on production): a plan 6 ms, a whole trade call about 20 ms; the gift pass 3 ms a house asked, 1 ms when nobody is under the line.
- A cruise is two trade calls. A cruise is `pirate_haunt_hours` (12 real hours, real-time pacing) at the haunt plus two passages, and a passage is five times as long in real time since 0413 (a voyage-day is 450 s): a hub's haunts lie 190 to 3,100 miles out, so roughly 1 to 16 voyage-days, 8 minutes to 2 hours a passage. With 121 fleets that is 15 to 20 trade calls an hour, **under 10 ms a minute on average**; a run with a trade is some tens of ms longer. The gift pass is about 0.35 s once (all 116 houses empty at the start), then near nothing. Nothing here types a day's length.
- **Locks.** A ship that traded holds the market rows she traded and the purse that paid her until the job's run commits. So the run steps no more ships after her and leaves the adding, the pay and the gift to the next minute (each has its own clock): at most one trading fleet a minute, 60 an hour against about 20 needed. A burst (many fleets ready at once) clears at one a minute.

## Checks run

The file on the cached local world on main's chain (0409 to 0413) with 0414 (PR #678 at `4d52a559`): its eleven hunks each once on those bodies, its probe; proofs 114, 30, 37, 46, 106, 103 after the rebuild (before it, on the first base: also 47, 48, 69 a pirate company, 36, 18, 49, 64, 35, 50, 104); the rollback draft after the file restores the five pre-image md5s; eslint on the generator; `tests/news.lint.spec.ts`; `tests/harness.guard.spec.ts` (green: PR #678's three files now carry the guard).

**Not run:** anything from zero, the whole proof suite, the world guard, any production read. No red-first run of proof 114 against the old bodies (it calls this file's functions); the old rule is shown by proofs 30 and 37, which were red until moved.

## PROD CHECKS

1. Before (after PR #678 and PR #681 are live, head ...0414): `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-trade/before.sql`. Wanted: `applied` false; every `hunks` count 1; every `volatility` s. Write down `ships`, `houses`, `cities`, `waits`, `room_today`, `pay_left_today`.
2. Deploy: `~/bin/bv-deploy.sh <pr>`. Expected well under 10 s.
3. After, at once, +1 h, +24 h, +7 d: `... -f scripts/ops/harness/pirate-trade/after.sql`. Wanted: `applied` true; hunks `{1:1, 2:1, 3:1, 4:0, 5:0, 6:1, 7:1, 8:0, 9:0, 10:0, 11:0}`; within the hour `houses.gifts_7d` up and `houses.under_line` down; within a cruise `ships.with_cargo` above 0 and the hubs' purses above 0; `waits.others_over_3h` `{}`; `houses.worth_less_gifts` is what trading has made less what refits and wrecks cost.
4. The pirates' job's time before and after: `C:\Users\gkwng\dev\pirate-trade-reads\p04_pirates_job_time.sql`.
5. Levers: `pirates_trade` false; `pirate_house_capital_pct` 0. Full undo: `scripts/ops/harness/pirate-trade/rollback-0415.sql`, a draft.

## Production reads still wanted (none was run)

- `C:\Users\gkwng\dev\pirate-trade-reads\p01_before_0415.sql`: the before-check (the eleven hunks once on the live bodies). Needs PR #678 and PR #681 live first.
- `p02_navy_fights_24h.sql`: how often the navy takes a pirate (it sizes the refit bill and how fast a house empties).
- `p03_second_payers.sql`: per country, the capital, whether the country holds it and its surplus, and how many merchant houses and navy ships are homed at the capital itself (for those the second payer is the country's richest other city).
- `p04_pirates_job_time.sql`: the last 60 runs of the pirates' job.

## Decided by default (the owner may reverse any)

1. One migration for A, B and C: they share two bodies and it stays small (eleven hunks, six functions, 150 ms).
2. Every pirate ship trades and is funded, 0339's 13 as well as the roster's 103 houses: one rule, as the home rule is. So 116 houses, not 103.
3. Capital = half the hulls' build cost, a knob.
4. She spends on cargo what she holds above the broke line.
5. No cut-loss: a parcel that cannot be sold at a gain stays aboard until it can, or until she is wrecked.
6. The gift's book row and its news name the pirates' capital as the giver even when a hub paid (the row is what counts her week; the money's true path is in the ledger and the cities' flows).
7. At most one trading fleet a minute.
8. A merchant's second payer is her house's nation's capital even if her home has changed flag.
9. The new proof is 114 (108 was taken while this was built).
