# The rounds' seeds, tuned (0521, 0522, 0523; dark; decided by default)

| Seed | Before | After | File |
|---|---|---|---|
| `pirates` ammo a 100 attack a round | 0.2 | 0.01 | 0521 |
| `round_hand_share` | 0.5 | 0.1 | 0521 |
| `round_hull_stop` | 60 | 40 | 0521 |
| `pirates` gold a round, won, at full risk | 40 x strength | 1,250 + 75 x strength (`gold_base`, `gold`) | 0522 |
| `expedition` crew lost a round (less a level; least) | 1 % (.04; .3) | 0.1 % (.004; .03) | 0523 |
| `expedition` gold a round | 30 | 700, +100 a ship more, +3 % a level (frozen at Send) | 0523 |

Method: the jobs' own tick sends and settles (`tick_fleet_jobs`), the city purses lit, the pirates' hoard 895 M, day's room 1 %, 240,000 a company a day. Gold an hour
out plus repair time; wrecks at base value; less repair, crew, stores, ammo. 4 runs a cell (`scripts/ops/harness/rounds/balance-*.sql`); the fights' dice move a cell by about a tenth.
An undamaged fleet in the before run was sent out again before it was read: its gold (near nothing) and wrecks (about 1,000) are missing from those cells (marked *).

| Fleet | Sea strength | Before | After | Trading's best listed |
|---|---|---|---|---|
| xebec x1 | 4 / 8 / 16 / 32 | -386 / -56 / -5,109 / -5,459 | 5,317 / 8,830 / -1,728 / -1,760 | 20,722 |
| xebec x3 | 4 / 8 / 16 / 32 | -2,232 / -3,004 / -3,641 / -6,840 | 1,854 / 3,524 / 7,917 / 16,477 | 43,605 |
| nau x1 | 4 / 8 / 16 / 32 | -438 / -639 / -443 / 1,928 | 1,507 / 2,604 / 6,033 / 14,589 | 34,227 |
| nau x3 | 4 / 8 / 16 / 32 | -3,827* / -3,929* / -3,783 / -4,201 | 746 / 811 / 1,736 / 4,599 | 30,164 |
| galeao x1 | 4 / 8 / 16 / 32 | -2,534* / -2,139 / -2,717 / -2,073 | 856 / 1,496 / 3,266 / 8,623 | 29,968 |
| galeao x3 | 4 / 8 / 16 / 32 | -7,570* / -7,582* / -7,831* / -8,613 | 360 / 384 / 428 / 1,500 | 29,126 |
| sanmartin x1 | 4 / 8 / 16 / 32 | -8,144* / -8,142* / -8,232* / -8,743 | 388 / 373 / 410 / 1,247 | 25,735 |
| sanmartin x3 | 4 / 8 / 16 / 32 | -23,551 / -23,459 / -23,478 / -23,594 | -918 / -940 / -887 / -889 | 19,442 |

No sea is stronger than 40, so galeao x3 and any sanmartin are over-strong everywhere. A xebec against 16 sits on the edge: other draws won a round or two and netted 2,757 to 5,007.

Expedition, level 1 / 8 / 15 (before, level 1): barca 2,788 / 3,378 / 3,968 (32); xebec 2,731 / 3,344 / 3,944 (-352); nau 2,700 / 3,322 / 3,928 (-472); galeao 2,600 / 3,260 / 3,884;
sanmartin 2,244 / 3,035 / 3,721 (-3,576); barca x3 3,564; xebec x3 3,390; nau x3 3,318; galeao x3 2,965; sanmartin x3 1,970 (just under 2,000).
Computed from the frozen terms, not from a settled run. Paid by the capital; a purse that cannot pay owes it. What a capital earns was not measured.

## What caps combat gold

- A company: 240,000 a day of loot of every kind (`loot_per_company_day`), so 10,000 an hour over a day, whatever the number of fleets.
- The hoard: 1 % a day of it (8.95 M at 895 M), shared with the pirates' other spending. Settled locally from 60 companies that each earn the full 240,000: 20 are paid
  in full (4.8 M, 10,000 an hour each); the 37th takes the last of the room and the rest get nothing. Pay and refits are written to the same day: on a day like
  2026-11-14 (5.2 M spent) 20 companies share about 3.7 M, 7,800 an hour each.
- The refill could not be measured: the local world has no pirates. Recorded on prod: 980 M (11-14), 950 M (11-15), 895 M (11-16), so it was falling. `hoard-flow.sql` reads it
  (lead). 20 companies at the cap take 4.8 M a day. Nothing is minted.
