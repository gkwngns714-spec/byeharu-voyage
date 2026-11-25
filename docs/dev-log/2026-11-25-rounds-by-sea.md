# 0535: rounds, by sea (dark)

`world.rounds(fleet)` serves the seas a docked fleet may be sent to (nearest base of each), `world.round_quote` what a round costs from a base before any Send,
and a run that is out serves the log lines already passed but not booked. Proof 229.

## Balance (local, real tick; nothing changed)

Figures are gold an hour while out, from `scripts/ops/harness/rounds/balance-*.sql`: 4 runs a cell, full crew and hull, stop at 60 % hull, 20 units each of the
two ammo goods, ammo costed at 878 a pair. The cities' purses and the daily pirate caps were lifted, so combat's gold is an upper bound. Salvage is at base value.

| Fleet | Sea strength | Rounds | Gold | Wrecks | Repair | Crew, stores | Ammo | Net |
|---|---|---|---|---|---|---|---|---|
| xebec x1 | 4 | 12 | 449 | 1,003 | 184 | 1,277 | 446 | -454 |
| xebec x1 | 8 | 6 | 1,664 | 1,009 | 359 | 2,364 | 0 | -50 |
| xebec x1 | 16 | 1 | 738 | 185 | 775 | 4,989 | 0 | -4,842 |
| xebec x3 | 32 | 5 | 7,646 | 989 | 1,373 | 8,882 | 1,054 | -2,674 |
| nau x1 | 8 | 34 | 309 | 977 | 214 | 594 | 1,179 | -701 |
| nau x1 | 32 | 9 | 4,821 | 1,006 | 846 | 2,101 | 898 | 1,981 |
| galeao x1 | 32 | 15 | 2,894 | 972 | 779 | 2,747 | 2,362 | -2,022 |
| sanmartin x1 | 32 | 12 | 441 | 996 | 328 | 1,376 | 7,902 | -8,168 |

Expedition at level 1: barca x1 +32, xebec x1 -352, nau x1 -472, sanmartin x1 -3,576 (crew losses are 1 % of a crew a round against 30 gold a fleet).
Trading, the best option the server lists: 16,700 to 44,000.

Tried together, not adopted: `pirates` ammo 0.2 to 0.02, its gold 40 to 200, `round_hand_share` 0.5 to 0.1: xebec x1 sea 4 +2,933; xebec x3 sea 16 +12,512, sea 32
+35,663; nau x1 sea 16 +8,719, sea 32 +29,051. The last two rival trading: a gold of 100 is the prudent figure (about half; not measured).
