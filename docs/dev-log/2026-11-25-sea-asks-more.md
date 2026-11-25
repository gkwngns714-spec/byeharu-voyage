# 2026-11-25: `sea-asks-more`, first part: 0525 (dark twice: the switch is false and every ask is 0), proofs 230 and 231

Stacked on 0514. Nothing touched production. **No figure of the red file's section 3.2 is shipped as an ask.**

## The figures (placeholders' scale: wave resistance's), one rule, `public.sea_stats_derive()`
- **Ice resistance**: hull 0.6 x armour + 3 x (6 - draft); gear 0.6 x its armour, and Anchor, Sheet Anchor, Hold Frames, Doubled Frames by grade. Hulls 15 to 46.
- **Current strength**: hull 0.2 x handling + 2 x speed - 10; gear 0.2 x handling + 2 x speed (Sails, Rudder, Headsails), and the anchors by grade. Hulls 16 to 53.
- **Light wind**: the better of OARS (oared: 40 - 2 x size) and SAILS (2 x speed - 12, lateen +6, mixed +4); gear 2 x speed, Lateen Re-rig by grade. Hulls 8 to 38.
- Every coefficient is decided by default. Read through `world.ship_stat`; fleets by average (`public.fleet_sea_stats`). `world.ship_stats`, the merchants' hot read, is not touched.

## The proven table (`scripts/ops/harness/sea-asks-more/table.mjs`; "holds the way" = has the wave the way asks, with the same kit; gear = ordinary pieces in her own slots, deck and hands)
| Sea, proposed ask | Wave | Bare hulls meeting | Grade 1 gear | Grade 3 | Least: bare / grade 1 | Harbours shut if nobody meets it |
|---|---|---|---|---|---|---|
| Cape, current 20 | 44 | 41 of 48 | 93 of 93 | 93 of 93 | 16 / 29 | 11 at rung 2, 44 at 5, 92 at 6, 97 at 7 (2 at 8, by the Pacific) |
| Kuroshio, current 25 | 44 | 14 of 48 | 93 of 93 | 93 of 93 | 16 / 29 | 2 (Osaka, Sakai) |
| Open Pacific, current 50 | 70 | 0 of 8 | 1 of 47 | 20 of 56 | 16 / 24 | 21 |
| Arctic, ice 50 | 20 | 0 of 121 | 72 of 138 | 93 of 148 | 17 / 19 | 1 (Longyearbyen) |
| Arctic, ice 70 (a later way) | 70 | 0 of 8 | 8 of 47 | 49 of 56 | 28 / 51 | 1 |
| Doldrums, light wind 20 | 24 | 62 of 121 | 129 of 129 | 134 of 134 | 8 / 34 | 0 (there is a way round) |
| Indian Ocean crossing, light wind 20 | 44 | 9 of 48 | 93 of 93 | 93 of 93 | 8 / 29 | 2 (Diego Garcia, Galle) |
| Philippine Sea, light wind 35 | 50 | 0 of 45 | 55 of 81 | 81 of 93 | 8 / 19 | 1 (Guam) |

**The Cape's figure must be at most 16** for every hull that holds its wave to pass bare (17 stops at least one); at most **29** if a piece of ordinary grade 1 gear in every slot is asked of her.
The proposed 20 stops 7 of 48 bare hulls. **Open Pacific 50 is too high**: no bare hull and 1 of 47 with grade 1 meets it.

Harbour by harbour at its own rung, were 3.2 set (`table.mjs --harbours`): 133 need none of the three; 93 need only the Cape's current; 2 the Kuroshio's; 2 the Cape's and the
Indian Ocean's light wind; 21 the Pacific's current 50; 1 the Arctic's ice; 1 (Guam) the Cape's current and light wind 35; 1 more at rung 8 only the Cape's.

## Rungs
Wave fixes the ordinary hull of a rung, so each row is judged on the hulls that hold its wave: 147 of 157 hold 12 bare, 121 hold 24, 48 hold 44 (93 with grade 1 gear), 45 hold 50, 8 hold 70 (47 with grade 1).

## Held
- One rule: `public.sea_refusal` gains the fleet's three figures; every old answer is the same to the letter. `sea_gate`, `sea_closed` (so the pathfinder and the board), the Seas read and
  the read before the light ask it through `public.sea_more`, with `sea_floor`'s two floors. Pass home covers the new asks by construction (AM_FLOOR: every sea at 200 of all, home from Acapulco).
- Merchants are never asked. With the asks at 0: 0.010 ms a gate, nothing read; `fleet_sea_stats` 0.10 ms when one asks. Two small tables (157 and 308 rows). The tick: 0.

## Not proven, not built
- One kit holding TWO of the new figures at once (the Cape's current and the Indian Ocean's light wind are met one at a time here). Gear's skill asks and prices. Skills, sets, perks, refits.
- The screens' three words (the server's sentence says "Ice resistance 12 / 50."); skills (Handling, Light-air). Fremantle and the pass: as 0513.
