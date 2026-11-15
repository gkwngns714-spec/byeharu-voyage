# 2026-11-16 · pirates-at-sea · 0445 PIRATES CRUISE THE SEA (owner row 353)

The owner, 2026-11-15: *"pirates still in port. too much. fix this please"*. Standing (rows 347, 349): *"pirates' main goal is to attack
other npcs, loot them"*. The Stats that day, after 0429 put every laid-up pirate back to work: pirate fleets 121, ships 193, laid up 0,
**port 118, sea 0**, wrecked 3.

## What production showed (read-only, 2026-11-15 14:55 UTC, head 0442, gate green: beat 119 ms, 682 MB)

`scripts/ops/harness/pirates-at-sea/before.sql` and `design.sql` (one statement each, after `db-health/gate.sql`):

| figure | value |
|---|---|
| pirate fleets | 121: 116 at work, 4 wrecked, 1 laid up |
| the 116 at work | **112 DOCKED at their haunt harbour**, 2 IN_BATTLE at their haunt, **2 SAILING** (at sea: 2 %) |
| how long the 112 had lain | 386 minutes at the median, 407 at most (4 had just come in) |
| `pirate_haunt_hours` | **12** (real hours) |
| a pirate's passage, last 2 hours | 38 passages by 30 fleets; 6 real minutes at the median (21 at most); 1,007 nm at the median; **168 nm a real minute** |
| raids, last hour | 116 (the ceiling is 120), by 76 different pirates; 18 in the last 10 minutes |
| the raids being fought at the read | 2, **both with their pirate in port** |
| a raid lasts | 48 s at the median, 73 at most (0435's tick battle) |
| homes and their haunts (fleets / haunts / median lane) | PTC 42 / 8 / 3,046 nm; TDC 24 / 8 / 2,069; FLO 24 / 10 / 1,006; DGA 18 / 8 / 1,030; GOT 3 / 3 / 47; LGA 3 / 3 / 393; DJE 3 / 3 / 222; POR 3 / 1 / 1,467 |
| a stored lane between two haunts of one home | rare: 34 of 276 pairs |
| `pirates_trade` | true (18 fleets with cargo aboard) |
| `navy_steps_per_run`, `pirate_strike_tries_per_run`, `attack_reach_nm` | 40, 8, 240 |

## THE ROOT CAUSE

1. **The twelve-hour lie.** `public.pirate_ship_step` (0339) sails a pirate ONE stored course from her home to a haunt harbour, where she
   lies `pirate_haunt_hours` = 12 real hours, then one course home, and at once out again. Since 0422 a pirate sails 4.5 times her speed, so
   the passage is 6 real minutes. Six minutes under sail, twelve hours at the quay: 2 % at sea, which is what the read shows.
2. **She raids from the quay.** `public.pirate_strike` (0427) asks every pirate in `public.pirate_ships_cruising`, and that view counts a
   ship lying DOCKED at her haunt as "in her sea". So the ~116 raids an hour were opened from a harbour on a merchant up to 240 miles off:
   the raids ran while nobody sailed. (Both raids being fought at the read had their pirate in port.)
3. The Stats "port" figure is right: it is every pirate fleet whose `fleets.status` is not `SAILING` (`public.stats_fleets_count`).

Not the cause: nobody was held after a battle (0 held outside the 2 fighting), nobody waited on `ready_at` or a repair, nobody was unpaid.

## What 0445 does

1. **A pirate cruises** (new `public.pirate_cruise_plan`, stable; 3 hunks in `public.pirate_ship_step`). A cruise is ONE voyage along
   several stored lanes (`public.npc_courses`) of her waters laid end to end: from her home out to her haunts in turn (0339's and 0414's own
   haunt rule and order), by the lane between two haunts where one is stored and through her home where none is, until it is
   `pirate_cruise_nm` (5,000) long or `pirate_cruise_courses` (24) lanes. An OUT cruise ends at a haunt; the cruise BACK ends at her home.
   5,000 nm is about 30 real minutes at 168 nm a minute. Her sea (who raids, the pressure, the navy's hunt) is the first haunt's on her way,
   both ways. **No new course is drawn**: every piece is a stored lane as it is sailed today, so none crosses the drawn land (0440-0442,
   `docs/NAVIGATION_PLAN.md` §8).
2. **Port time is short.** At the end of a cruise she lies `pirate_port_minutes` (2), not 12 hours, then takes her next cruise from where she
   lies. At her home she is mended free (as before) and sails at her next step. `pirate_haunt_hours` is no longer read.
3. **Hurt, she goes home to refit** (new `public.pirate_hurt`, stable): her hulls together under `pirate_refit_below` (0.5) of their best,
   she sails the one stored course straight home from the harbour she lies in, in no sea (she raids nobody and the hunt cannot find her), and
   is mended there. A fight at sea holds her where she is and she sails on when it ends (0432's hold, unchanged): the same voyage, later by
   the fight.
4. **She raids from the sea** (1 hunk each in `public.pirate_strike` and `public.pirate_strikes`): only a pirate under sail strikes (while `pirate_strike_from_port` is false). The
   reach (240 nm), the rest (5 min), 0432's flee and 5 minutes of peace, no PvP and 0429's "never her own cargo ships" are unmoved.
   `pirate_strike_from_port` (false) is the quick way back. `pirate_strike_tries_per_run` 8 -> 16 (only from prod's 8): a pirate in mid-ocean
   has nobody in reach more often than one lying beside a harbour had, so more are asked a run; the ceiling of 2 raids a minute is unmoved.
5. **The minute job keeps up** (3 hunks in `public.tick_pirates`, 1 in `public.pirate_trade`, new `public.pirate_trader_step`). Before, the
   run stopped at the first ship that traded (0415: nothing runs behind a trade's locks) and left the strikes, the add and the pay to the
   next minute. With ~4 pirates leaving a harbour a minute and `pirates_trade` lit, that would be one sailing a minute and no raid at all.
   Now ONE ship a run may trade: the first in the turning order is put aside (only while `pirates_trade` is lit) and steps LAST, after the strikes, the purses and the joins;
   every other ship of the run sails without trading. 0415's law holds better than before: nothing at all runs behind a trade's locks. At
   most `pirate_sails_per_run` (8) ships leave a harbour a run (plus the trader), so the first minutes after the deploy (112 pirates past
   their two minutes) are spread over ~14 runs.

6. **The join finds her** (1 hunk in `public.battle_join_near`): 0436's sieve places a sailing ship between the two harbours of her voyage. A
   cruise is a chain of lanes and may end where it began, so a pirate is placed where she is (`voyage.fleet_point`); the navy's sieve is unmoved.

Not changed: who pays a pirate, the roster, the wreck and rebirth at home, the navy's hunt, the join rule's chances and caps (0436), the battle itself.

## Before and after, the same scene (`scene-cruise.sql`, the cached chain, prod's clock, the whole roster built by the job)

| last hour of three | before 0445 | after 0445 |
|---|---|---|
| working pirates under sail, mean of each minute | **0.0 %** (0 of 131) | **94.6 %** (lowest minute 87.0 %) |
| pirate voyages begun a minute | 0 | 7.0 (the local hulls sail ~340 nm a minute; see below) |
| rows written a minute, every table | 27 | 198 |
| `tick_pirates`, mean / max (PGlite) | 41 / 224 ms | 307 / 425 ms |
| a cruise | none | 6,583 nm and 20 minutes at the median, 36 minutes at most |

By home after (the last minute): PTC 42 of 42 under sail, TDC 24 of 24, FLO 24 of 24, DGA 16 of 18, the small homes 21 of 23.

**Prod's own figures (expected).** Prod's pirates sail 168 nm a real minute, half the local scene's, so each cruise lasts twice as long and
half as many begin: a cruise of 30 minutes (FLO, DGA: five lanes of ~1,000 nm), 37 (TDC: three of ~2,070), 54 (PTC: three of ~3,000), 30 for LGA and DJE (13 and 23 short lanes), 7 for GOT's three fleets
(24 lanes of 47 nm); a harbour is 2-4 minutes (the two-minute lie and the job's
minute). **At sea ~85-93 % of the working pirates, never under 70 %**, within about half an hour of the deploy.

**Load.** ~3.6 pirate voyages begin a minute (121 fleets) against 0.3 today. The scene writes 24 rows a voyage begun (the voyage, its days,
the fleet, ship and quay rows of the departure and the arrival, the pay), so **about +90 rows a minute, +110 at most**, inside a per-minute
job's 5,000. No job, no table, no index. The pirates' job (never in the beat) lays ~4 cruises a run, 9 at most; in the scene 9 sailings
cost ~270 ms on PGlite. The arrivals beat lands ~3.6 more ships a minute beside the merchants' own (it is at 119 ms; the half-limit is
1,000). Raid rows are unchanged (the ceiling stays 2 a minute).

## Proofs

- 0445's own probe, rolled back, on any world: the CI world (pirates dark, no ship) has them lit and one roster fleet built; a world with
  pirates lends one lying in a harbour. Local: `ord 1001 out 8967 nm in 3 lanes to a haunt, lay 2 min at her haunt, back 9083 nm in 3 lanes
  to her home; hurt, straight home 2951 nm`, ~200 ms. On prod's shape (`scene-prod-shape.sql` before the file): `ord 1 out 7428 nm in 5
  lanes ... (a pirate of this world)`, and with prod's own pick, ord 3 of GOT: `out 1390 nm in 24 lanes (the most lanes a cruise has)`.
- `scripts/db/proofs/147_pirates_cruise_the_sea.sql`, 7/7: PC_KNOBS, PC_OUT (one voyage of stored lanes, both pirates leave in one run),
  PC_STRIKE (a RAID opened under sail; over, she sails on, the same voyage), PC_QUAY (in a harbour: NOT_HUNTING), PC_PORT (two minutes,
  then the cruise back to her home), PC_REFIT (hurt: straight home, mended, out again), PC_SHARE (six pirates, an hour: 90 % under sail).
- Amended, one line each: proofs 128, 133, 136, 137 set 0445's two way-back knobs (their pirate lies at her haunt and raids from it: they
  prove the battle, not where she lies). Proof 114's PT_JOB is the new law: one run sails all six, exactly one of them trades, the strikes
  ran. Pirate and battle proofs green locally: 46, 48, 69, 106, 114, 115, 116, 118, 128, 130, 132, 133, 136, 137, 147. Proof 46 (0339's) turns trading off for its scene, one line: its lone pirate must
  step before the pressure is written, and with trading lit the job's first ship steps last.
- Prod reads before the PR (read-only, gate green): `before.sql` and `design.sql` (the tables above); `hunks.sql`: all ten hunks occur
  once in prod's bodies at head 0442 (the bodies' md5 equal the local chain's), nothing of 0445 there, the probe would borrow ord 3 of GOT.
- `rollback-0445.sql` (a draft) run after the file on the local chain: the six bodies' md5 are prod's again.

## The after-check (30 minutes; this changes live play)

1. Before: `scripts/ops/harness/db-health/gate.sql` (gate_ok), `scripts/ops/harness/pirates-at-sea/hunks.sql` (ok true, applied false).
2. +10 min: `scripts/ops/harness/pirates-at-sea/before.sql`: applied true; `at_sea_share` rising (8 sailings a run: ~0.6 by +10 min).
3. +30 min: the same read: **`at_sea_share` >= 0.70** (expected ~0.85-0.93); `lying_min.p50` under 5; `raids_fighting.attacker_in_port` 0;
   `raids_1h` not collapsed (see below); `stuck` 0; beat mean under 1,000 ms. Then the gate, and `cron.job_run_details` for
   `byeharu-voyage:pirates`: no failed run, no run over a few seconds.
4. Fail lines (any one is a step back): the beat over 2 s; a failed pirates run; `at_sea_share` under 0.5 at +30 min; a raid stuck FIGHTING.

**Raids an hour may fall, and what to do.** At the read there were 116 an hour (the ceiling is 120) because a pirate at a harbour mouth
always has a merchant in reach. A pirate in mid-Pacific does not. The job now asks 16 pirates a minute instead of 8. If `raids_1h` settles
well under ~60: `pirate_strike_tries_per_run` up (each try is one read of the sailing voyages, ~850 rows), or `pirate_cruise_nm` down
(more time near the harbours). Not known before the deploy: it depends on where prod's merchants sail.

## Forward rollback (owner only)

Quick, no file: `pirate_strike_from_port` true (raids from the quay again) and `pirate_port_minutes` 720 (the twelve-hour lie; within an
hour most pirates lie at a harbour again). Whole: `scripts/ops/harness/pirates-at-sea/rollback-0445.sql`, a draft generated from the file's
own hunks (the ten reversed, the three functions and six knobs gone, the tries back to 8).

## Decided by default (the owner may reverse any)

- A cruise is long (5,000 nm, about half an hour), not a hop of a minute: fewer voyages for the database, and she is still always under sail.
- A pirate lies 2 minutes in a harbour between cruises; at her home she is mended free and leaves at her next step.
- Hurt means her hulls together under half of their best; then she goes straight home and raids nobody on the way.
- A pirate in a harbour opens no raid (the owner's "at sea"); she may still be attacked there by a player, as before.
- The raid's reach stays 240 nm (the owner's knob): "where they meet" is a pirate under sail within sight of her prize, not a quay.
- One pirate a minute trades (it was one a minute at most before, and in practice 0.3); the others carry what they hold to the next harbour.
- The Stats still count a pirate held in a fight in a harbour as "port"; one held under sail stays "sea" (she is `SAILING`, held).
- GOT's three fleets cruise about 7 minutes at a time (their haunts lie 47 nm off and a cruise is at most 24 lanes); LGA's and DJE's reach
  5,000 nm in 13 and 23 lanes. Giving GOT farther haunts is 0414's roster and reach, not this slice.
