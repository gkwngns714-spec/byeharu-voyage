# 2026-11-15: a combat ship sails three times as fast as a merchant (0424, owner row 343)

**The owner, verbatim:** "make combat ships(pirates, navy) at least 3 times faster than merchants."

## What it means (decided by default; the owner may reverse any)

- **Combat ships** are the computer's navy ships (`public.navy_ships`, 43 on prod) and pirate ships (`public.pirate_ships`: the seven of
  0339 and 0414's roster, up to ~200 fleets). `public.fleet_kind` calls them NAVY and PIRATE.
- **Merchants** are `public.npc_fleets` (kind MERCHANT; the pirates' own merchants are MERCHANT too) **and the countries' cargo ships**
  (`public.cargo_ships`, kind CARGO_SHIP). Cargo ships carry goods and funds and never hunt, so for this order they are merchants: they keep
  their speed.
- **Not a player's fleet.** A player's speed comes from her ships, captains, skills and levels. Changing it would be pay-to-win territory. The
  multiplier never names COMPANY, and the door refuses it.
- **"3 times faster"** is measured on the typical ship: the median knots of each kind's voyages at sea, as they departed (`speed_profile`),
  compared on the same course, under the one-hour game day (`time_compression` 192).

## Measured on prod (read-only, head 0421, gate green: beat 110 ms mean, 903 MB, 0 disk waits)

`scripts/ops/harness/combat-speed/measure-speeds.sql` (knots at departure of the voyages at sea):

| kind | fleets | at sea | median kn | p10 | p90 | a passage | arrivals a minute |
|---|---|---|---|---|---|---|---|
| MERCHANT | 885 | 617 | 17.48 | 13.95 | 19.76 | 38 min, 2,113 nm | 28.61 |
| CARGO_SHIP | 372 | 52 | 13.11 | 11.57 | 14.22 | 69 min | 1.20 |
| NAVY | 43 | 11 | 13.43 | 11.66 | 13.66 | 110 min, 4,743 nm | 0.11 |
| PIRATE | 25 | 4 | 15.73 | 11.70 | 16.33 | 41 min, 1,658 nm | 0.12 |
| COMPANY (players) | 19 | 0 | | | | | |

`measure-duty.sql`: pirates lie 12 h at a haunt (`pirate_haunt_hours`), are reborn in 60 min (`pirate_respawn_minutes`); the navy hunts for 6 h
(`navy_hunt_hours`), 5 fights a minute at most. Right now: navy 31 lying on a hunt, 2 sailing to one, 10 on escort; pirates 4 at work, 17 laid
up, 3 wrecks.

## The choice: 4.5 for both kinds

3 x the merchant median is 52.4 kn.

| | before | x 4.5 | against the merchant median |
|---|---|---|---|
| NAVY median | 13.43 | 60.4 | **3.46 x** |
| PIRATE median | 15.73 | 70.8 | **4.05 x** |
| NAVY p10 (a slow navy ship) | 11.66 | 52.5 | 3.00 x |
| PIRATE p10 | 11.70 | 52.7 | 3.01 x |
| the merchants' fast tenth (p90 19.76) vs the median navy ship | | | 3.06 x |

So the typical combat ship is well past 3 x, and even a slow one is at 3 x. A navy passage of ~110 minutes now takes ~25 minutes; a pirate's of
~41, ~9. On the same course the merchant's 38 minutes become, for the median navy ship, ~11 (a third would be ~12.7).

The local proof (proof 119, the chain's world): Lisbon-Setubal-Lisbon, 76 nm. The median of 861 merchants 18.88 kn, 75.8 s; a manned galion
68.2 kn, 21.0 s (0.277 of the merchant's time); a xebec 90.3 kn, 15.8 s (0.209); a player's house at her own 14.92 kn, unchanged.

## How: one authority, one door

- **The authority.** `voyage.fleet_speed_at` (0367) is the speed of a fleet. Everything reads it: the departure's frozen speed and arrival, the
  stores a leg needs, the passage gate, the navy's call to a battle, the quotes. One hunk: a fleet not in an armada sails at her own speed times
  `public.fleet_speed_mult(fleet)`, the one reader of the knob `fleet_speed_by_kind` (`{"NAVY": 4.5, "PIRATE": 4.5}`) by `public.fleet_kind`;
  any kind it does not name reads 1. An armada is a player's: untouched. Ship classes, rolls, ship stats, gear, captains, skills and levels are
  untouched, so a ship card still shows her own hull's speed (navy and pirate cards show none).
- **The door.** `public.fleet_speed_set(kind, multiplier, at)` (owner only, like `public.clock_set`) writes the knob and re-times that kind's
  voyages at sea. A voyage's position is a pure function of its departure, its per-segment frozen speeds and the clock. So the segment she is on
  at the instant keeps its speed: she stands where she stood and ends that segment on time. Every later segment's speed is multiplied by
  new / old, and her arrival moves by exactly the hours those segments gain or lose. Her departure, days, delays and holds do not move, so no
  day is settled twice and none is skipped. No ship jumps. (0413 could stretch the whole clock about the instant; a speed for one kind cannot
  move the clock, so this is the exact continuous form for a speed. Most combat passages have 4 to 20 segments, so most of a passage at sea
  speeds up at once.)
- **Rollback:** `scripts/ops/harness/combat-speed/rollback-0424.sql`, the same door with 1 (continuous too). Or a softer figure, e.g. 3.5.

## Raids and hunts

The fight reads no speed (`public.fight_sides`, the battle's rounds: hulls, guns and crews), so pursuit and flight in a fight do not change.

- **Raids** are rolled per voyage-day of the RAIDED ship (a merchant's or a player's), against the pirate ship cruising that sea when she
  left and the sea's pressure. The victims' days at sea do not change. A pirate ship counts as "at work" in her sea while she sails out and
  lies at her haunt, not on her way home. A cruise was ~41 + 720 + 41 minutes (at work 94.9 %). It is now ~9 + 720 + 9 (at work 98.8 %). So
  the raid pressure is a little **stronger**, and the owner's "more aggressive" pirates are at least as aggressive.
- **The hunt**: a navy ship sails to the most dangerous sea, lies 6 h, and sails home. With ~25-minute passages instead of ~110 she is in the
  hunted sea ~88 % of a hunt instead of ~62 %, so she meets pirates up to ~1.4 times as often (still at most one fight an hour a ship). A pirate
  who loses is back at work after ~69 minutes instead of ~101 (the reborn hour plus a shorter sail out). The pirates' time lost to the hunt is
  about what it was (1.4 x 0.68 = 0.97), while their time at work rises.
- **The navy's call** to a battle (0333) arrives sooner (its arrival is distance at her speed): a player who attacks a cargo ship meets the
  navy sooner. Escorts reach their cargo ship's port sooner.
- The combat ships' own passages roll their own weather per voyage-day, so a 4.5 x faster passage has a 4.5th of the days at sea.

## The load (docs/DATABASE_BUDGET.md: stay inside half of each limit)

A voyage-day takes the same real 450 s whatever the speed. So the days settled a minute do not rise; they fall, because a faster ship spends
less of the time at sea. What rises is arrivals and departures:

| | today | after, realistic | after, bound |
|---|---|---|---|
| navy arrivals a minute | 0.11 | ~0.2 (hunt cycles 580 -> 409 min) | 0.5 (4.5 x today) |
| pirate arrivals a minute | 0.12 (4 at work) | ~0.54 with ~200 fleets (cruise 802 -> 738 min; ~0.50 at the old speed with the same roster) | ~1.3 (roster full, 4.5 x) |
| rows a minute (~20 an arrival and departure) | | about +2 (the increase is ~+0.1 arrivals a minute) | at most +32 (+1.6 arrivals) |

The beat handles ~137 fleets and ~109 voyage-days a minute (28.6 merchant arrivals a minute alone). At the bound this is ~1 % more of the
beat's work (beat 110 ms against a limit of 2,000, half 1,000). The navy's and pirates' minute jobs step a few more departures an hour (a
pirate trades at each departure: ~8 % more trade calls). Computer houses' voyages are cut at `npc_retention_hours` (3): at most ~290 more
standing `voyages` rows, and fewer `voyage_events`. Rows written by a per-minute job: unchanged (5,000 a run limit). Database size: no new
table, a few hundred rows. Everything stays far inside half of every limit (the size was already over half before this slice, 903 of 1,500
MB; this slice does not move it).

## Checks

- Migration self-assert: the hunk once and reversing; no other function moved; the door and the reader server-only. A probe (rolled back): a
  player's house, one made a navy ship, one a pirate ship, put to sea Lisbon-Setubal-Lisbon. The door is moved half way along the first
  segment. Asserted: the player's voyage and speed unchanged to the digit; navy and pirate on the same mile at the instant, ending the first
  segment on time, later segments x 4.5, the arrival earlier by exactly those hours; the door refuses COMPANY; back to 1, as she was.
- Proof 119: `CS_KNOB`, `CS_SAME_COURSE`, `CS_PLAYER`, `CS_RETIME` (above). Green locally.
- Prod: `before.sql` and `after.sql` (read-only) under `scripts/ops/harness/combat-speed/`. After: `ratio_navy` and `ratio_pirate` (median
  departure knots since the switch against the merchant median) at least 3; `combat_arrivals_per_min` under 2.

## Version

0424 = production head 0421 + 0422/0423 (reserved for the at-sea builder, branch `at-sea`, not yet on GitHub when this was built) + 1. 0424
cuts only `voyage.fleet_speed_at`, which the at-sea builder's navy patrol and rest bodies do not touch. If 0422/0423 do not land first, rename
this file to the next number before the deploy.
