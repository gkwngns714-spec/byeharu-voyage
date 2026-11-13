# Attacks made ready to light (owner row 324)

Owner, 2026-11-13: *"do all, make everything work. open them if everything is built and is workable."*

`attack_enabled` (a company attacks cargo, navy and pirate ships; never another player) was built dark in 0323, 0327, 0333, 0334, 0339, 0357 and 0364. The switch audit of 2026-11-13 found it **not ready**: nobody had measured what sails, the sim was old, the battle card had never been in a browser, there was no after-check and no lighting file. This slice does those. **Nothing here lights anything.** The light is its own file, 0375, in its own PR.

## 1. What sails: `scripts/ops/harness/attacks/cargo-at-sea.sql`

One read-only statement for production (the lead runs it; it was run here only on the local world). Every cargo ship: class, guns, hands against her class's `crew_required`, hull, whether she is at sea, funds aboard. It prints counts by class and by state (armed and crewed / armed but short-handed / unarmed), the ships at sea by hands, the funds aboard (median, 90th centile, how many carry 400,000 or more), the 25 worst ships at sea, and `unsafe`: the unarmed ships at sea as a share of the ships at sea. That last figure is what the lighting file's guard reads.

**Not run on production by the builder.** The local world has no cargo ship until a scene makes some.

## 2. The sim on what really sails: `scripts/ops/harness/attacks/sim.mjs`

`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/sim.mjs --seeds=300 [--before=20260818000374]`

- **Every hull is a real ship of the cached world**, made by the game's own hands in a transaction that is rolled back: attackers by `public.new_house` + `public.commission_ship` (a new company: level 1, no captain, no gear, full complement); cargo ships by `public.tick_cargo_ships` (armed navire with `convoy_armed_enabled` lit, the old pinnace with it dark), five of each; navy ships by `public.navy_commission`; pirate ships as proof 48 makes them.
- Each side is read by `voyage.fleet_hulls` (what `public.battle_sheet_freeze` writes to a battle's sheet) and fought by `public.fight_sides` exactly as `public.battle_fight` calls it. 300 fights a cell, 264 cells.
- Level 5 is `npc_ship_level_enabled` lit and `public.crown_hull_level_fix` run on the same hulls.
- "Navy comes" is a called galleon on the sheet from round 3, as `public.battle_advance` joins her.
- Cost of a battle = hull points lost x the repair rate (2 d. a point at Lisbon) + a tenth of her hands x 100 d. when she is beaten or breaks off.
- The dice are this desk's `world_secret`, and each run rolls new hulls, so small-ship cells move by ten points or more between runs. The big-ship cells do not.

### The verdict on free gold, plainly

**Before this slice: yes, there was risk-free income, and not only from the old hull.**

1. **The old unarmed cargo ship is free gold for any fleet with one gun.** A 70,000 d. Kobaya is paid in 9 fights of 10 and loses no hull at all, at level 1 and at level 5.
2. **Her hands barely matter.** An armed navire with no hands is beaten by the same fleets, about as often, as one with all 60. The guns decide it. So "sails short-handed" is not the danger; "sails unarmed" is.
3. **A small fleet cannot rob an armed navire.** A Kobaya, an armed trader or a xebec is beaten 8 times in 10, loses a fifth of its hull and a tenth of its hands each time, and wins 0 to 8 %. Two xebecs win about 1 in 4.
4. **A Nau (600,000 d.) wins 3 in 4**, loses a tenth of her hull each fight and is beaten 1 in 5. Real risk, good pay.
5. **A strong fleet risked nothing.** Two galleons, a Great Galley with a Nef, or two Nau capitânia were paid in 96 to 100 fights of 100, lost 1 to 2 % of their hull (about 180 d. of repair) and took 15,000 d. a battle from a ship with 100,000 aboard, 60,000 from one with 400,000: the day's cap of 240,000 in four battles. A navy ship coming up for round 3 did not stop them. Level 5 did not stop them.
6. **The navy is what stops a middling fleet.** With a navy ship coming up, the Nau goes from 3 wins in 4 to none and is beaten 98 times in 100.
7. **Nothing a beaten attacker loses is much gold.** The worst battle in the table costs about 2,300 d. What an attack really costs is standing (150 regard an attack, 30,000 d. of fines to buy back), a WANTED mark, and the navy.

**After 0374 (below): no cell of the table is free gold** by the sim's own test (paid in 9 fights of 10, never 5 % of her hull lost, at least a twentieth of what is aboard). A strong fleet still wins, and still has a small income at next to no risk: about a quarter of what it had (3,400 to 4,000 d. a battle at 100,000 aboard, 14,000 to 16,000 at 400,000: 16 or more battles to fill the day, where it was 4). It can raise that only by taking more fire. An unarmed ship pays nothing at all.

### NPC hulls at level 5 (what production will be), 300 fights a cell

`0327 rule`: every won fight pays the whole share. `0374 rule`: this slice. Loot is the mean over all 300 fights, lost ones included.

| Attacker | Target | Navy comes | Won % | Beaten % | Attacker hull lost % (worst) | Battle cost d. | Loot a battle, 100k aboard: 0327 rule | 0374 rule | 400k aboard, 0374 rule | Battles to fill 240k (0374, 400k) |
|---|---|---|---|---|---|---|---|---|---|---|
| new: 1 Kobaya | navire, full crew | no | 0.0 | 84.0 | 21.2 (33.1) | 451 | 0 | 0 | 0 | - |
| new: 1 Kobaya | navire, full crew | yes | 0.0 | 84.0 | 30.7 (92.4) | 502 | 0 | 0 | 0 | - |
| new: 1 Kobaya | navire, no hands | no | 2.7 | 81.0 | 21.1 (33.0) | 438 | 213 | 0 | 0 | - |
| new: 1 Kobaya | navire, no hands | yes | 0.0 | 81.0 | 28.4 (90.6) | 478 | 0 | 0 | 0 | - |
| new: 1 Kobaya | unarmed pinnace | no | 91.7 | 0.0 | 0.0 (0.0) | 0 | 13750 | 0 | 0 | - |
| new: 1 Kobaya | unarmed pinnace | yes | 0.0 | 91.3 | 44.0 (63.6) | 604 | 0 | 0 | 0 | - |
| new: 1 Kobaya | navy ship | no | 0.0 | 85.0 | 43.2 (63.6) | 574 | 0 | 0 | 0 | - |
| new: 1 Kobaya | pirate ship | no | 14.3 | 80.7 | 16.1 (30.1) | 410 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | navire, full crew | no | 0.0 | 87.7 | 17.5 (34.9) | 330 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | navire, full crew | yes | 0.0 | 86.7 | 26.5 (72.9) | 408 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | navire, no hands | no | 8.3 | 78.0 | 16.9 (34.5) | 306 | 667 | 853 | 3413 | 71 |
| mid: 1 Haringbuis | navire, no hands | yes | 0.0 | 86.7 | 25.2 (67.4) | 396 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | unarmed pinnace | no | 90.7 | 0.0 | 0.0 (0.0) | 0 | 13600 | 0 | 0 | - |
| mid: 1 Haringbuis | unarmed pinnace | yes | 0.0 | 92.3 | 27.3 (38.9) | 427 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | navy ship | no | 0.0 | 82.3 | 25.6 (38.9) | 392 | 0 | 0 | 0 | - |
| mid: 1 Haringbuis | pirate ship | no | 50.7 | 45.7 | 7.1 (23.5) | 154 | 0 | 0 | 0 | - |
| mid: 2 Haringbuis | navire, full crew | no | 24.0 | 62.3 | 13.5 (24.0) | 567 | 1920 | 1180 | 4719 | 51 |
| mid: 2 Haringbuis | navire, full crew | yes | 0.0 | 86.0 | 20.1 (39.5) | 811 | 0 | 0 | 0 | - |
| mid: 2 Haringbuis | navire, no hands | no | 28.7 | 53.3 | 12.6 (24.1) | 506 | 4300 | 2610 | 10441 | 23 |
| mid: 2 Haringbuis | navire, no hands | yes | 0.0 | 87.0 | 19.9 (39.0) | 813 | 0 | 0 | 0 | - |
| mid: 2 Haringbuis | unarmed pinnace | no | 88.0 | 0.0 | 0.0 (0.0) | 0 | 13200 | 0 | 0 | - |
| mid: 2 Haringbuis | unarmed pinnace | yes | 0.0 | 93.3 | 19.0 (32.2) | 827 | 0 | 0 | 0 | - |
| mid: 2 Haringbuis | navy ship | no | 0.0 | 84.3 | 18.9 (32.8) | 780 | 0 | 0 | 0 | - |
| mid: 2 Haringbuis | pirate ship | no | 96.0 | 0.0 | 3.4 (12.1) | 64 | 0 | 0 | 0 | - |
| mid: 1 xebec | navire, full crew | no | 8.0 | 84.3 | 19.1 (34.7) | 1095 | 640 | 507 | 2027 | 119 |
| mid: 1 xebec | navire, full crew | yes | 0.0 | 92.7 | 26.3 (65.4) | 1250 | 0 | 0 | 0 | - |
| mid: 1 xebec | navire, no hands | no | 6.7 | 83.7 | 19.1 (34.6) | 1088 | 1000 | 750 | 3000 | 80 |
| mid: 1 xebec | navire, no hands | yes | 0.0 | 87.7 | 24.2 (65.6) | 1176 | 0 | 0 | 0 | - |
| mid: 1 xebec | unarmed pinnace | no | 92.7 | 0.0 | 0.0 (0.0) | 0 | 13900 | 0 | 0 | - |
| mid: 1 xebec | unarmed pinnace | yes | 0.0 | 95.3 | 28.2 (38.4) | 1296 | 0 | 0 | 0 | - |
| mid: 1 xebec | navy ship | no | 0.0 | 88.0 | 26.8 (38.4) | 1203 | 0 | 0 | 0 | - |
| mid: 1 xebec | pirate ship | no | 67.3 | 32.7 | 11.0 (23.6) | 456 | 0 | 0 | 0 | - |
| mid: 2 xebecs | navire, full crew | no | 23.3 | 63.7 | 13.4 (24.5) | 1632 | 3500 | 3075 | 12300 | 20 |
| mid: 2 xebecs | navire, full crew | yes | 1.0 | 89.0 | 20.7 (43.1) | 2316 | 80 | 53 | 213 | 1125 |
| mid: 2 xebecs | navire, no hands | no | 27.0 | 59.7 | 13.1 (24.9) | 1539 | 4050 | 3584 | 14335 | 17 |
| mid: 2 xebecs | navire, no hands | yes | 2.3 | 87.7 | 21.0 (42.8) | 2291 | 187 | 156 | 624 | 385 |
| mid: 2 xebecs | unarmed pinnace | no | 94.3 | 0.0 | 0.0 (0.0) | 0 | 14150 | 0 | 0 | - |
| mid: 2 xebecs | unarmed pinnace | yes | 14.7 | 79.7 | 18.0 (34.2) | 2063 | 1173 | 800 | 3200 | 75 |
| mid: 2 xebecs | navy ship | no | 6.7 | 81.3 | 18.3 (33.8) | 2104 | 0 | 0 | 0 | - |
| mid: 2 xebecs | pirate ship | no | 97.3 | 2.7 | 6.2 (19.5) | 166 | 0 | 0 | 0 | - |
| mid: 1 Nau | navire, full crew | no | 75.3 | 20.3 | 10.6 (19.2) | 599 | 11300 | 10181 | 40725 | 6 |
| mid: 1 Nau | navire, full crew | yes | 0.0 | 97.3 | 18.7 (29.3) | 1918 | 0 | 0 | 0 | - |
| mid: 1 Nau | navire, no hands | no | 75.3 | 21.7 | 10.5 (19.5) | 614 | 11300 | 9635 | 38541 | 7 |
| mid: 1 Nau | navire, no hands | yes | 0.0 | 96.3 | 18.8 (28.5) | 1906 | 0 | 0 | 0 | - |
| mid: 1 Nau | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| mid: 1 Nau | unarmed pinnace | yes | 21.3 | 78.7 | 13.7 (24.5) | 1508 | 1707 | 957 | 3827 | 63 |
| mid: 1 Nau | navy ship | no | 19.7 | 77.0 | 15.5 (24.8) | 1538 | 0 | 0 | 0 | - |
| mid: 1 Nau | pirate ship | no | 100.0 | 0.0 | 2.1 (6.5) | 62 | 0 | 0 | 0 | - |
| rich: 2 Galion | navire, full crew | no | 100.0 | 0.0 | 1.9 (4.6) | 176 | 15000 | 3847 | 15390 | 16 |
| rich: 2 Galion | navire, full crew | yes | 99.7 | 0.3 | 7.2 (15.2) | 688 | 14950 | 12438 | 49753 | 5 |
| rich: 2 Galion | navire, no hands | no | 100.0 | 0.0 | 1.9 (4.5) | 179 | 15000 | 3917 | 15670 | 16 |
| rich: 2 Galion | navire, no hands | yes | 100.0 | 0.0 | 7.2 (14.4) | 667 | 15000 | 12576 | 50305 | 5 |
| rich: 2 Galion | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| rich: 2 Galion | unarmed pinnace | yes | 100.0 | 0.0 | 5.2 (11.2) | 483 | 15000 | 10098 | 40395 | 6 |
| rich: 2 Galion | navy ship | no | 99.0 | 1.0 | 7.1 (15.7) | 720 | 0 | 0 | 0 | - |
| rich: 2 Galion | pirate ship | no | 100.0 | 0.0 | 0.2 (2.0) | 22 | 0 | 0 | 0 | - |
| rich: 1 Great Galley | navire, full crew | no | 96.0 | 0.0 | 4.0 (9.7) | 171 | 14400 | 8139 | 32559 | 8 |
| rich: 1 Great Galley | navire, full crew | yes | 45.3 | 50.0 | 12.7 (23.8) | 1546 | 3627 | 2873 | 11491 | 21 |
| rich: 1 Great Galley | navire, no hands | no | 96.7 | 0.0 | 4.3 (10.2) | 183 | 14500 | 8746 | 34984 | 7 |
| rich: 1 Great Galley | navire, no hands | yes | 60.7 | 37.3 | 12.9 (23.5) | 1299 | 4853 | 3783 | 15131 | 16 |
| rich: 1 Great Galley | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| rich: 1 Great Galley | unarmed pinnace | yes | 86.3 | 13.7 | 9.0 (19.2) | 661 | 9567 | 7177 | 28708 | 9 |
| rich: 1 Great Galley | navy ship | no | 87.0 | 12.0 | 8.6 (18.7) | 608 | 0 | 0 | 0 | - |
| rich: 1 Great Galley | pirate ship | no | 100.0 | 0.0 | 0.9 (4.2) | 40 | 0 | 0 | 0 | - |
| rich: 1 Nef | navire, full crew | no | 100.0 | 0.0 | 2.8 (6.6) | 165 | 15000 | 5518 | 22072 | 11 |
| rich: 1 Nef | navire, full crew | yes | 95.3 | 4.7 | 9.0 (17.9) | 683 | 8560 | 7614 | 30456 | 8 |
| rich: 1 Nef | navire, no hands | no | 100.0 | 0.0 | 3.0 (6.6) | 173 | 15000 | 5799 | 23196 | 11 |
| rich: 1 Nef | navire, no hands | yes | 93.0 | 7.0 | 9.1 (18.9) | 774 | 13880 | 12288 | 49152 | 5 |
| rich: 1 Nef | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| rich: 1 Nef | unarmed pinnace | yes | 100.0 | 0.0 | 6.0 (13.6) | 345 | 15000 | 10305 | 41221 | 6 |
| rich: 1 Nef | navy ship | no | 100.0 | 0.0 | 6.2 (12.3) | 357 | 0 | 0 | 0 | - |
| rich: 1 Nef | pirate ship | no | 100.0 | 0.0 | 0.7 (2.9) | 41 | 0 | 0 | 0 | - |
| rich: Great Galley + Nef | navire, full crew | no | 100.0 | 0.0 | 1.8 (4.3) | 178 | 15000 | 3599 | 14398 | 17 |
| rich: Great Galley + Nef | navire, full crew | yes | 100.0 | 0.0 | 5.5 (10.5) | 538 | 15000 | 10477 | 41910 | 6 |
| rich: Great Galley + Nef | navire, no hands | no | 100.0 | 0.0 | 1.8 (4.1) | 175 | 15000 | 3529 | 14119 | 17 |
| rich: Great Galley + Nef | navire, no hands | yes | 100.0 | 0.0 | 5.6 (11.8) | 550 | 15000 | 10684 | 42738 | 6 |
| rich: Great Galley + Nef | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| rich: Great Galley + Nef | unarmed pinnace | yes | 100.0 | 0.0 | 3.8 (8.0) | 372 | 15000 | 7528 | 30115 | 8 |
| rich: Great Galley + Nef | navy ship | no | 100.0 | 0.0 | 3.7 (8.1) | 360 | 0 | 0 | 0 | - |
| rich: Great Galley + Nef | pirate ship | no | 100.0 | 0.0 | 0.2 (1.3) | 16 | 0 | 0 | 0 | - |
| rich: 2 Nau capitania | navire, full crew | no | 96.3 | 0.0 | 1.0 (2.3) | 160 | 14450 | 1935 | 7742 | 31 |
| rich: 2 Nau capitania | navire, full crew | yes | 96.0 | 0.0 | 2.8 (6.1) | 458 | 14400 | 5540 | 22161 | 11 |
| rich: 2 Nau capitania | navire, no hands | no | 96.0 | 0.0 | 0.9 (2.2) | 150 | 14400 | 1814 | 7257 | 34 |
| rich: 2 Nau capitania | navire, no hands | yes | 97.7 | 0.0 | 3.0 (6.0) | 477 | 14650 | 5776 | 23104 | 11 |
| rich: 2 Nau capitania | unarmed pinnace | no | 100.0 | 0.0 | 0.0 (0.0) | 0 | 15000 | 0 | 0 | - |
| rich: 2 Nau capitania | unarmed pinnace | yes | 100.0 | 0.0 | 2.0 (4.3) | 327 | 15000 | 3959 | 15836 | 16 |
| rich: 2 Nau capitania | navy ship | no | 96.7 | 0.0 | 2.0 (4.2) | 316 | 0 | 0 | 0 | - |
| rich: 2 Nau capitania | pirate ship | no | 100.0 | 0.0 | 0.1 (0.6) | 12 | 0 | 0 | 0 | - |

Level 1 against level 5, the same fleets: within the run-to-run spread for every big-ship cell (two galleons on a full navire: 100 % and 2.0 % hull at level 1, 100 % and 1.9 % at level 5). Level 5 gives the crown hulls handling, accuracy and sighting; it does not change who wins here. The whole table at both levels is the script's own output.

## 3. The fix: migration 0374, loot follows the risk taken (dark)

**What changed, exactly.** One line of `public.loot_take` (the one place gold leaves a ship for a player), two knobs, two new server-only functions, and one line of `public.battle_sheet_freeze` (a fault of 0357, below).

- What is aboard now counts for `least(1, greatest(loot_risk_floor, her own hull lost in the fight / loot_risk_full))` before `public.loot_due` takes its share under the caps it always had.
- `loot_risk_full` 0.075: a fight that cost the attacker 7.5 % of her hull (half of the 15 % at which she breaks off) pays the whole share. 2 % pays about a quarter. Nothing lost pays nothing.
- `loot_risk_floor` 0. **The owner's levers:** `loot_risk_full` 0 turns the rule off (the loot of 0327 exactly); a floor of 1 does the same.
- The risk is read from the battle's own kept result (`battles.result.hull`). Nothing is recomputed and no dice are thrown.
- `public.loot_risk(jsonb)`: the factor of one fight. `public.attack_ready()`: the one reading of "may attacks be lit" (section 6).
- `public.loot_due`, `public.attack_close`, `public.battle_resolve` and the engine are not touched. Regard, hands lost, WANTED and the wreck are as they were (proof 74 holds that as text, rule on against rule off on one battle).

**Why this and not the others on the list.** A short-handed ship that does not sail, or hands from the realm's pool: the sim says hands do not decide it. An unarmed target that cannot be attacked: closes case 1 only. The navy's answer: it already stops the middling fleet and does not stop the strong one. Only the loot rule reaches every case with one line.

**Decided by default (the owner may reverse each):** 0.075 and 0; the rule applies to a ransom as to a boarding; no new line on the report (the card says "By hull risked" under Loot).

**Not solved, and said plainly:** a strong fleet still has a small, nearly risk-free income (above). A player can raise her share by bringing a fleet that takes more fire, which is the point, but it also means fewer guns can pay better. The designed answer to a company that raids for a living is the navy's hunt (section 7), which is dark.

### A fault of 0357 found by the browser: a called navy ship could fight as two

- **What a player would have met:** a navy ship lying in the harbour nearest the battle when she is called is "already there". `public.battle_sheet_freeze` put her on the sheet at the open, with no mark of her fleet; `public.battle_advance` then found a called ship "not on the sheet" and added her again for round 1. The card said "Ships 3, Crew 320" for a cargo ship and one galleon, and the galleon's broadside was fired twice.
- **How it was found:** `battle.live` failed about 1 run in 10. The cargo ship was half-way between two harbours, and when the nearer one happened to be the navy's, she was there at once and doubled. Reproduced in SQL: 3 hulls on the sheet for 2 ships.
- **The fix, one line:** a CALLED ship is never frozen at the open. `public.battle_advance`, the one place a called ship joins, puts her on the sheet once, marked, for the first round she is there for. An escort is frozen at the open as before.
- Proof 74 `CALLED_ONCE` holds it; proofs 40, 60 and 66 (the navy called, the rounds, the rings) stay green.
- It was on production, dark. No battle was ever fought there, so nothing was wrong in play.

- Self-assert: catalog and arithmetic, 20 ms locally. Proof 74 (`scripts/db/proofs/74_loot_follows_the_risk.sql`): 7 markers, real battles through `public.attack_for` and the real close, green under 10 other worlds' dice.
- Proofs 34 and 40 each had one line that assumed the whole share for a real fight; both now read the rule. Both green under 10 dice.
- Rollback: the knob. The file reversed is `scripts/ops/harness/attacks/rollback-0374.sql` (run locally: both bodies are their pre-images again).
- Prod check, before and after: `scripts/ops/harness/attacks/before-0374.sql` (each of the two lines once in its live body; nothing of 0374 there, then all of it).
- `-- news: none`: nothing a player can see changes while attacks are dark.

## 4. The battle in a real browser: `tests/battle.live.spec.ts`

Until now no page had reached the Attack section or the battle card. The spec lights attacks only inside a private copy of the built world (`tests/battleWorld.fixture.ts`): the armed cargo ship, the navy, regard and crown level lit, a round every 5 s, a cargo ship of Spain at sea with 100,000 aboard, her own fleet at anchor near her. The page presses the real doors. Two worlds are arranged so the ending is the same under any dice (the fixture says how): `board` and `flee`.

Five tests, 1.5 minutes with two workers: 390x844 English (the whole path), 1280x800 English (the ring), and Flee at 1280x800 Korean, 390x844 Korean and 320x640 Korean. Each checks that nothing leaves its box, nothing is cut with an ellipsis, no rule breaks inside a word, the page does not scroll sideways, and names are whole.

What is driven: a cargo ship's hull on the map, her card, the Attack read, the press, rounds arriving one at a time, both hull bars only ever falling, the round clock, the navy's own clock, Fight and Flee, Flee taking hold from the next round, the break-off, a fight to the boarding with gold (the purse on the bar rises by exactly the loot, the ship's funds fall by it), the navy joining in a later round on the card and on the defender's side of the fight opened from the map's ring, the held cargo ship arriving afterwards, and History: the report with its whole log, the regard that fell and the WANTED mark.

### Defects found and fixed in the client

| # | What a player would have seen | Fix |
|---|---|---|
| 1 | **The battle could stop at a round for ever.** A watching card fights each round by sending her stance again when the round falls due. If that moment came while the card's last answer was still out, the nudge was dropped and never sent again. On production the minute job would have picked it up a minute late; it would have looked frozen. | `BattleCard`: asked again every second while a round is due, and again after 5 s if the round is still the next one; the busy flag is always cleared |
| 2 | **The foe's hull bars rewrote themselves when the navy came.** Rounds 1 and 2 read 76 % and 54 %, then, once the navy ship was on the sheet, the same rounds read 29 % and 21 % and round 3 jumped to 82 %. | `fightLines`: a round is measured against the hulls that were there in it; the log says **Navy joined** above the round she first fights in. The same fix reaches the fight sheet opened from the ring |
| 3 | The log's first line read "Battle · 2 Cargo ship 1 · 190 crew" | "Battle · Cargo ship 1 · Ships 2 · Crew 190" |
| 4 | A press refused as stale ("this fleet has moved on") left the same stale version to be sent again, and the refusal lay under the button, below the fold of a phone, unseen | `AttackSection`: the world is read back at once on E_STALE; the refusal stands above the button |
| 5 | "Navy arrives: About 1 min" stayed frozen on the sheet through the battle and after it | The pre-fight rows go at the press; the card shows the navy's own running clock until she is there |
| 6 | A Korean card ended in an English sentence ("The navy came up before it ended.") | The four navy lines have their words in both languages |
| 7 | "Hull −0 (0%)" | "Hull 0 (0%)" |
| 8 | With 0374 the loot is smaller than 15 % and nothing said why | "By hull risked" under Loot |
| 9 | History, in English: "ESP wants you, 48 h." and "ESP thinks worse of you" (the events name a country by its code) | `headline`: a country is said by its name ("Castile-Spain wants you") |

Screenshots: `C:\Users\gkwng\dev\attacks-ready-shots\` on the builder's machine (not in the repo).

**Not driven:** the fleet fold's own battle card on the Fleets page (the same component, mounted there while she is in a battle); an attack on a navy ship or a pirate ship from their cards (the same Attack section; `rpc.attack` covers the door); a real 60 s round against the real minute job; two clients at once; the live site.

## 5. The after-check: `scripts/ops/harness/attacks/after-check.sh <start> <end>`

The seven lines of `docs/COMBAT_LOG.md` 3.6, each a read-only file of one statement:

| Line | File | Wanted |
|---|---|---|
| No battle FIGHTING past its clock + 2 min | `after-battles.sql` | `late` 0 |
| Rounds equal to a re-run of the sheet | `after-rounds.sql` | `rounds_differ`, `count_differs`, `result_differs` 0 |
| LOOT in the ledger = the battles = the reports; nobody over the day cap | `after-loot.sql` | three sums equal; `over_day_cap`, `over_ship_cap` 0 |
| No fleet IN_BATTLE or busy after its battle closed | `after-battles.sql` | `stuck_in_battle`, `stuck_busy`, `stuck_navy` 0 |
| No failed run of the battles job | `after-job.sql` (production only: pg_cron's tables) | `job_active` true, `failed` 0 |
| The arrivals beat | `../raid/after-check.sh` | avg <= 3 s, p95 < 5 s |
| A held voyage settles the days of a voyage never held | `after-held.sql` | `wrong_days`, `over_days`, `function_differs` 0 |

`before-light.sql` prints `public.attack_ready()`, the knobs, that nothing of an attack exists yet, the four doors, and how many companies own a gun. The script asks `read-only.mjs` before each send, as 0364's does, and `tests/harness.guard.spec.ts` now lists it.

**Seen to answer locally** (`run.mjs --cron scene-battles.sql after-*.sql`): three real battles (one fought to its clock by the job minute by minute, one with a Flee, one still being fought), every WANTED-0 figure 0, the three loot sums equal, a held voyage arrived with `wrong_days` 0 and `hold_would_have_cost` 3 (so the check has teeth). **None was run on production.**

## 6. The lighting file: 0375, its own PR

`public.attack_ready()` (0374) is the one reading: 0375's guard refuses unless it says ready, and `before-light.sql` prints the same thing on production first. Ready means: the loot rule on, the round clock 30 to 120 s, and, in a world where cargo ships sail, `regard_enabled`, `npc_ship_level_enabled` (written on 9 cargo hulls in 10), `convoy_armed_enabled` and `navy_enabled` lit, and the unarmed cargo ships at sea at most a tenth of those at sea.

A world built from the chain alone has no cargo ship and those switches are the owner's on production, not the chain's, so there the file applies with nothing to protect. That is what keeps CI and the shipped image building.

## 7. `navy_hunt_per_day`: recommended 0.25, as its own later light

Today 0. It is the chance a day that a country's navy finds a Hostile or WANTED company's voyage in its waters (0334), doubled while she is WANTED (`navy_hunt_wanted_mult` 2). The meeting is a real fight with a navy galleon; a plundered fleet loses 25 to 50 % of its cargo, a tenth of its hands and a fine of 5 % of the cargo's value up to 100,000 d.

- **Why not 0:** with the hunt dark, a WANTED mark is a line in History and nothing else, and a company that raids pays only in standing with a country it need not visit.
- **Why 0.25:** a WANTED company crossing that country's waters is then found on about half its days there (0.5 with the multiplier). A raid that paid 15,000 to 60,000 is followed, for 48 hours, by voyages that each risk a quarter to a half of a cargo. That is the same order as the loot, which is what makes raiding a choice. Higher than that and one attack closes a sea to her for two days.
- **Why later:** it bites trading fleets, including those of a player who attacked once to see. Light attacks first, read a week of battles (`after-loot.sql`: who attacks, how often, what they take), then light the hunt in its own window with `scripts/ops/harness/raid/after-check.sh`.
- **Known gap (R12 of the design):** a navy meeting ignores her standing order (Fight, Flee, Pay). And a war fleet sails with an empty hold, so the hunt costs a pure raider only hull and hands. Both are worth settling before the hunt is lit.

This figure is reasoned from the knobs, not measured. No sim of the hunt was run in this slice.

## 8. Proven, and not proven

**Proven (locally, PGlite, the cached chain; nothing was run on production):**
- 0374 applies on the cached world; its self-assert passes; proof 74 (7 markers) green, and under 10 other worlds' dice; proofs 31, 34, 40, 41, 56, 60, 66 green on it under 10 dice too.
- The sim's tables before and after.
- `battle.live`: 15 runs of 15 after the nudge fix (three passes of the five tests); the two boarding tests under 12 other worlds' dice, where 1 failure in 24 led to the called-ship fault; after that fix the whole spec green under 2 other worlds' dice, and in 4 more worlds every test green but for one assertion I added to the spec while the run was going (the country's name in History, checked against a build that did not have it yet). Re-run once more on the final build: 5 of 5.
- The seven after-check files and `before-light.sql` answer on a local scene of real battles.

**Not proven:**
- What sails on production today. `cargo-at-sea.sql` has to be run there.
- The after-check files on real Postgres (CI's disposable chain does not run harness files) and `after-job.sql` against real pg_cron tables (run here against a stand-in).
- The cost of `public.attack_ready()` and of the check files on production's data. They read a few hundred cargo ships and the battles; nothing that grows is read whole.
- 60 s rounds against the real minute job, in a browser. The spec's rounds are 5 s and the watching card fights them.
- Whether 0.075 is the right figure. It is half the break-off share, chosen so a Nau's ordinary fight pays in full.
