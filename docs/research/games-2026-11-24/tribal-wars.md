# Tribal Wars (InnoGames) - economy research for an HQ trading-company game

Researched 2026-11-24. Facts only; every figure has a source beside it. Where I did arithmetic on source data it is marked "my arithmetic".

Source key:
- **[OFF-xxxx]** = official InnoGames help page `https://support.innogames.com/kb/TribalWars/en_DK/xxxx` (classic Tribal Wars).
- **[LIVE]** = the game's own public config feed on a running world (casual world "enc1"): `https://enc1.tribalwars.net/interface.php?func=get_building_info`, `...func=get_unit_info`, `...func=get_config`. Read 2026-11-24. That world has speed 3.6 and unit_speed 0.278 (get_config).
- **[DE-FAN]** = German fan site tables (Die Staemme = German Tribal Wars): `https://staemme.de.tl/Eisenmiene.htm`, `/Bauernhof.htm`, `/Speicher.htm`, `/Marktplatz.htm`, `/Versteck.htm`, `/Kaserne.htm`, `/Hauptgeb.ae.ude.htm`. Their cost columns match the official English tables, so I treat them as reliable.
- **[BB]** = `https://benchmarkbuddy.com/die-staemme-dorfaufbau-guide/` (German third-party guide, says its numbers come from the live interface, checked 23 Aug 2026).
- **[NB]** = community notebook `https://github.com/mikenoethiger/tw-scavenge/blob/master/scavenge.ipynb`.
- **[FORUM-SCAV]** = `https://forum.tribalwars.net/index.php?threads/the-scavenging-guide-the-future-of-early-game-farming.280700/` (2017 player post on a speed-2 beta world).
- **[GIST]** = `https://gist.github.com/amiuhle/61b0334997805ada0e99` (player script for build time; cites the TW forum "Building Formulas" guide).

---

## 1. Resource production (wood / clay / iron)

The official English pages do NOT print production per level (it is in pictures only: [OFF-5324] timber camp, [OFF-5327] clay pit, [OFF-5330] iron mine). The table below is the iron mine table from the German fan page [DE-FAN Eisenmiene], world speed 1, normal base production. [BB] gives the same anchors: L1 = 30, L10 = 117, L20 = 530, L30 = 2,400 per hour.

| Level | Per hour | Level | Per hour | Level | Per hour |
|---|---|---|---|---|---|
| 1 | 30 | 11 | 136 | 21 | 616 |
| 2 | 35 | 12 | 158 | 22 | 717 |
| 3 | 41 | 13 | 184 | 23 | 833 |
| 4 | 47 | 14 | 214 | 24 | 969 |
| 5 | 55 | 15 | 249 | 25 | 1,127 |
| 6 | 64 | 16 | 289 | 26 | 1,311 |
| 7 | 74 | 17 | 337 | 27 | 1,525 |
| 8 | 86 | 18 | 391 | 28 | 1,774 |
| 9 | 100 | 19 | 455 | 29 | 2,063 |
| 10 | 117 | 20 | 530 | 30 | 2,400 |

- Growth per level (my arithmetic): (2400/30)^(1/29) = 1.16312; 30 x 1.163118^(L-1) gives L10 = 116.9, L20 = 529.6, L30 = 2400.0. The factor 1.163118 is NOT printed on any page I read; it is my fit to the table.
- I opened only the iron table; I did not open the wood and clay pages. Official text says only "the higher its level the more wood is produced" [OFF-5324].
- Resources accrue while logged out: "You also receive those resources when you are not logged into your account" [OFF-1176].
- World speed: the feed's times equal base / world speed (enc1: spear recruit 283.33 s; my arithmetic 283.33 x 3.6 = 1020 s base). How world speed multiplies production is not printed in any page I read. enc1 config also has `<base_production>33</base_production>` [LIVE get_config]; its meaning is not documented where I looked.
- Bonuses:
  - Resource-production flag: levels 1..9 = +4, +6, +8, +10, +12, +14, +16, +17, +18 percent. Combine 3 flags of one level into 1 of the next; a level-9 flag needs 6,561 grey flags; one flag per village; can be moved only after 24 h [OFF-2996].
  - Premium: enc1 lists a `ProductionBonus` premium feature (0 there) [LIVE get_config]; its size: not verified.
  - Bonus villages: enc1 `<bonus_villages>0</bonus_villages>`; effect not verified.
- Player anchor: at L21, 616/hour x 24 = 14,784 per day per resource [FORUM-SCAV post #2]. A German tips page quoted 616 at "level 20" in a search snippet (netzsieger.de, not opened); the table above has 616 at level 21, so that snippet looks off by one.

## 2. Building costs and build times

Cost at level L = base x factor^(L-1). Base and factor are published by the server [LIVE get_building_info]:

| Building | Max lvl | Base wood/clay/iron (L1) | Cost factor wood/clay/iron | Pop L1 | Pop factor |
|---|---|---|---|---|---|
| Headquarters | 30 | 90/80/70 | 1.26 / 1.275 / 1.26 | 5 | 1.17 |
| Timber camp | 30 | 50/60/40 | 1.25 / 1.275 / 1.245 | 5 | 1.155 |
| Clay pit | 30 | 65/50/40 | 1.27 / 1.265 / 1.24 | 10 | 1.14 |
| Iron mine | 30 | 75/65/70 | 1.252 / 1.275 / 1.24 | 10 | 1.17 |
| Farm | 30 | 45/40/30 | 1.3 / 1.32 / 1.29 | 0 | 1 |
| Warehouse | 30 | 60/50/40 | 1.265 / 1.27 / 1.245 | 0 | 1.15 |
| Hiding place | 10 | 50/60/50 | 1.25 all | 2 | 1.17 |
| Barracks | 25 | 200/170/90 | 1.26 / 1.28 / 1.26 | 7 | 1.17 |
| Stable | 20 | 270/240/260 | 1.26 / 1.28 / 1.26 | 8 | 1.17 |
| Workshop | 15 | 300/240/260 | 1.26 / 1.28 / 1.26 | 8 | 1.17 |
| Smithy | 20 | 220/180/240 | 1.26 / 1.275 / 1.26 | 20 | 1.17 |
| Market | 25 | 100/100/100 | 1.26 / 1.275 / 1.26 | 20 | 1.17 |
| Wall | 20 | 50/100/20 | 1.26 / 1.275 / 1.26 | 5 | 1.17 |
| Rally point | 1 | 10/40/30 | - | 0 | - |
| Statue | 1 | 220/220/220 | - | 10 | - |
| Academy (noble building, feed key `snob`) | 3 on that world | 15,000/25,000/10,000 | 2 / 2 / 2 | 80 | 1.17 |

Official cost tables (spot values): timber camp L1 50/60/40, L2 63/77/50, L5 122/159/96, L10 373/534/287, L12 582/868/446, L20 3,469/6,065/2,572, L30 32,312/68,857/23,013 [OFF-5324]. Clay pit L30 66,561/45,666/20,478 [OFF-5327]. Iron mine L30 50,768/74,595/35,837 [OFF-5330]. HQ L30 73,280/91,809/56,996 [OFF-5288]. Farm L30 90,692/125,517/48,331 [OFF-5333]. Warehouse L30 54,799/51,201/23,013 [OFF-5336]. Market L25 25,639/34,060/25,639 [OFF-5321]. Barracks L25 51,277/63,605/23,075 [OFF-5291]. The feed factors reproduce these only approximately (e.g. 50 x 1.25^11 = 585 vs 582 listed, my arithmetic), so the published tables are the exact numbers.

Base build time per building, seconds, on a speed-3.6 world [LIVE get_building_info]: HQ 250, timber camp 250, clay pit 250, iron mine 300, farm 333.3, warehouse 283.3, hiding place 500, barracks 500, stable 1666.7, workshop 1666.7, smithy 1666.7, market 750, wall 1000, rally point 3016.7, statue 416.7, academy 163,000. `build_time_factor` is 1.2 for every building.

How the Headquarters shortens build time: the "time factor" column of the HQ table [DE-FAN Hauptgeb.ae.ude]: L1 95%, L2 91%, L5 78%, L10 61%, L15 48%, L20 38%, L25 30%, L30 23%. This equals 1.05^(-HQ level) (my arithmetic: 1.05^-1 = 0.952, 1.05^-30 = 0.231). The player script [GIST], citing the TW forum Building Formulas guide, uses:

`time = build_time x 1.18 x build_time_factor^max(-13, level - 1 - 14/(level-1)) x 1.05^(-HQ level)`

This formula is third party; the game config says only `<buildtime_formula>2</buildtime_formula>` [LIVE get_config]. My arithmetic with it, timber camp base 250 (enc1 numbers): at HQ 1, level 5 = 308 s, level 10 = 1,092 s, level 20 = 7,848 s, level 30 = 50,894 s; at HQ 20, level 10 = 432 s, level 20 = 3,106 s, level 30 = 20,140 s. Not checked in the game.

Early help: finishing a building gives a resource reward in the Rewards tab [OFF-3020 quest 5]; a quest reward is a "Construction Booster (10%)" [OFF-3020 quest 9]; the quest text mentions an "instant construction option" [OFF-3020 quest 6].

## 3. Storage

Warehouse capacity per resource (each of the 3 resources has its own cap) [DE-FAN Speicher]:

| Lvl | Cap | Lvl | Cap | Lvl | Cap |
|---|---|---|---|---|---|
| 1 | 1,000 | 11 | 7,893 | 21 | 62,305 |
| 2 | 1,229 | 12 | 9,705 | 22 | 76,604 |
| 3 | 1,512 | 13 | 11,932 | 23 | 94,184 |
| 4 | 1,859 | 14 | 14,670 | 24 | 115,798 |
| 5 | 2,285 | 15 | 18,037 | 25 | 142,373 |
| 6 | 2,810 | 16 | 22,177 | 26 | 175,047 |
| 7 | 3,454 | 17 | 27,266 | 27 | 215,219 |
| 8 | 4,247 | 18 | 33,523 | 28 | 264,611 |
| 9 | 5,222 | 19 | 41,217 | 29 | 325,337 |
| 10 | 6,420 | 20 | 50,675 | 30 | 400,000 |

- The official help shows a max of 400,000 per resource in its example [OFF-1176].
- When full: "If the warehouse limit is reached the excess resources are wasted" (said of scavenging returns) [OFF-3002]. Quest text: "Once your Warehouse becomes full, you will be unable to collect anymore resources... a full warehouse is just as detrimental to your growth as an empty one" [OFF-3020 quest 8].
- Hiding place (resources raiders cannot take) [DE-FAN Versteck]: L1 150, L2 200, L3 267, L4 356, L5 474, L6 632, L7 843, L8 1,125, L9 1,500, L10 2,000 (max level 10). Official: enemy scouts cannot see what is hidden [OFF-1184].
- Premium accounts see "the time when your warehouse will be full" [OFF-2960].

## 4. Population (farm) as the upkeep lever

Farm capacity (max population) [DE-FAN Bauernhof]: L1 240, L2 281, L3 329, L4 386, L5 452, L6 530, L7 622, L8 729, L9 854, L10 1,002, L11 1,174, L12 1,376, L13 1,613, L14 1,891, L15 2,216, L16 2,598, L17 3,045, L18 3,569, L19 4,183, L20 4,904, L21 5,748, L22 6,737, L23 7,896, L24 9,255, L25 10,848, L26 12,715, L27 14,904, L28 17,469, L29 20,476, L30 24,000 (about x1.17 per level, my arithmetic). [BB] states the same range, 240 to 24,000.

- Rules: "Without extending your farm your village cannot grow" [OFF-5333]. "You can only build as many units as you have farm space. This includes those in the queue - so if you cannot build any more you may need to upgrade your farm!" [OFF-2969]. Farm and warehouse use 0 population [OFF-5333/5336 tables, LIVE].
- Buildings use population: the official tables list "extra for this level / cumulative total", e.g. timber camp L1 5/5, L2 +1 = 6, L10 +2 = 18, L20 +10 = 77, L30 +43 = 326 [OFF-5324]; HQ L30 total 475 [OFF-5288]; barracks L25 total 303 [OFF-5291]; market L25 total 866 [OFF-5321]; hiding place L10 total 8 [OFF-5339].
- Units use population [OFF-1185]: spear/sword/axe/archer 1, scout 2, light cavalry 4, mounted archer 5, heavy cavalry 6, ram 5, catapult 8, paladin 10, nobleman 100, militia 0.
- Population flag: +2% (L1) to +10% (L9) [OFF-2996].
- Raising the cap gets expensive: farm cost factors 1.3 / 1.32 / 1.29 [LIVE].
- There is no gold wage: the population cap is the only recurring "upkeep" I found. The bonus of mass: spare capacity is shared between buildings and units.

## 5. Units, loot capacity, recruitment

[OFF-1185] (cost wood/clay/iron, population, speed in minutes per field at world speed 1, carry = "loot"):

| Unit | Cost W/C/I | Pop | Speed (min/field) | Carry |
|---|---|---|---|---|
| Spear fighter | 50/30/10 | 1 | 18 | 25 |
| Swordsman | 30/30/70 | 1 | 22 | 15 |
| Axeman | 60/30/40 | 1 | 18 | 10 |
| Archer | 100/30/60 | 1 | 18 | 10 |
| Scout | 50/50/20 | 2 | 9 | 0 |
| Light cavalry | 125/100/250 | 4 | 10 | 80 |
| Mounted archer | 250/100/150 | 5 | 10 | 50 |
| Heavy cavalry | 200/150/600 | 6 | 11 | 50 |
| Ram | 300/200/200 | 5 | 30 | 0 |
| Catapult | 320/400/100 | 8 | 30 | 0 |
| Paladin | 20/20/40 | 10 | 10 | 100 |
| Nobleman | 40,000/50,000/50,000 | 100 | 35 | 0 |
| Militia | 0/0/0 | 0 | 0.02 | 0 |

- The live feed agrees on carry (spear 25, sword 15, axe 10, light 80, heavy 50, knight 100) [LIVE get_unit_info].
- Recruit times in the feed (seconds, speed-3.6 world) [LIVE get_unit_info]: spear 283.3, sword 416.7, axe 366.7, scout 250, light 500, heavy 1,000, ram 1,333.3, catapult 2,000, paladin 6,000, nobleman 5,000. Travel speed in the feed: spear 17.99 = 18 / (3.6 x 0.278) (my arithmetic).
- Barracks level shortens recruiting: the table column "Zeitfaktor" (time factor) is L1 63%, L2 59%, L5 50%, L10 37%, L15 28%, L20 21%, L25 16% [DE-FAN Kaserne]. I read it as the recruit-time multiplier; the page does not say so.
- Recruiting gates: barracks needs HQ L3 [OFF-2960]; cavalry needs the stable, rams/catapults the workshop [OFF-1184]; axe/archer need smithy research [BB].
- Flags: unit recruitment speed +6% (L1) to +20% (L9); haul capacity flag +2% (L1) +3% +4% +5% +6% +7% (L6), higher levels cut off in my fetch [OFF-2996].
- Raiding loot rule: no official page with the rule found. enc1 has `<hauls>2</hauls>`, `<hauls_base>1000</hauls_base>`, `<hauls_max>100000</hauls_max>` [LIVE get_config]; meaning not documented where I looked. Barbarian villages regrow: `barbarian_rise 0.01`, `barbarian_max_points 1500` [LIVE]. Not verified how these map to loot.

### Scavenging ("send units out, they return with resources after a time")

Official [OFF-3002]: at the Rally Point there are four options; each must be unlocked "for resources and some time"; yield "is primarily defined by the selected option and the carry capacity of the units"; all four can run at once but not the same one twice; you see the resources and the return time before starting; cannot cancel; resources go to the warehouse and excess is wasted; flags and items add bonuses; only units in the village count. It is a per-world setting: enc1 has `<scavenging>0</scavenging>` [LIVE get_config].

Community numbers (not official) [NB], [FORUM-SCAV]:

| Option | Share of total carry capacity returned |
|---|---|
| 1 | 10% |
| 2 | 25% |
| 3 | 50% |
| 4 | 75% |

- Return = total carry capacity x share. Example: 5 spears + 10 swords = 5x25 + 10x15 = 275 [NB].
- Duration in seconds = (((share x capacity)^2 x 100)^d1 + d2) x d3. d1, d2, d3 are per-world constants visible in the scavenge page source [NB]. World CH60 constants: d1 = 0.45, d2 = 1800, d3 = 0.7722074897 [NB].
- Worked with CH60 constants (my arithmetic), minutes for options 1/2/3/4: 50 spears (capacity 1,250): 31 / 41 / 57 / 72. 150 spears (3,750): 44 / 72 / 113 / 153, returning 375 / 938 / 1,875 / 2,812. 600 spears (15,000): 97 / 192 / 337 / 476.
- The 2017 post (speed-2 beta world) quotes 150 spears at options 2/3/4 taking 1:03:15, 1:40:17, 2:15:26, and about 3:20:34 for a level-3 run on a speed-1 world; that world's constants are not given [FORUM-SCAV]. Same post: unlocking option 4 cost 10,000/12,000/10,000 [FORUM-SCAV post #2]. Other unlock costs: not found.
- Design facts stated there: unit speed does not matter, only carry capacity; duration rises slower than capacity, so income per hour falls as the army grows; the notebook concludes that an even split over all four options is the best general policy [NB, FORUM-SCAV].

## 6. Market / trading

- One merchant carries at most 1,000 resources, any mix (example 100 wood, 350 clay, 550 iron); a bigger market gives more merchants [OFF-1265].
- Merchants by market level [DE-FAN Marktplatz] (market needs HQ L3 and warehouse L2): L1 1, L2 2, L3 3, L4 4, L5 5, L6 6, L7 7, L8 8, L9 9, L10 10, L11 11, L12 14, L13 19, L14 26, L15 35, L16 46, L17 59, L18 74, L19 91, L20 110, L21 131, L22 154, L23 179, L24 206, L25 235.
- Free trade (sending without return) can be restricted for a period after joining a world; for strangers use offers on the market so both sides get what they asked [OFF-1265].
- Premium exchange: buy resources with Premium Points or sell spare resources for Premium Points [OFF-3035 quest 3]; bought resources take two hours to be delivered "on a world with game speed 1" [OFF-265]. Rates and fees: not verified. enc1 config shows `PremiumExchange 0`, `MerchantExchange 0`, `MerchantExchange_ratio 1` [LIVE].
- Questline "Resources" opens when the market is built: 4 quests (make a trade offer, market L5, open the premium exchange screen, assign a flag) [OFF-3035].
- Merchant travel speed: not verified.

## 7. Progression gates

| Building | Needs | Source |
|---|---|---|
| Barracks | HQ L3 | OFF-2960, OFF-5291 |
| Market | HQ L3 + Warehouse L2 | OFF-5321 |
| Wall | Barracks L1 | OFF-2960 |
| Academy / nobles | HQ L20, Smithy L20, Market L10 | BB (third party) |
| Catapult | Workshop L2, Smithy L12 | BB (third party) |
| Timber camp, clay pit, iron mine, farm, warehouse, rally point | none | OFF-5324, 5327, 5330, 5333, 5336, 5315 |

- HQ L15 allows demolishing buildings [OFF-5288].
- Points: each finished building level scores points; no points for research or units [OFF-1184]. The points table columns were unlabelled in my fetch, so I do not quote them.
- Noble sink: the nobleman costs 40,000/50,000/50,000 and 100 population [OFF-1185]; on enc1 a coin costs 28,000/30,000/25,000, `rise 2`, `max_dist 200` [LIVE get_config]; the flag "Reduce coin / package costs" gives -10% (L1) to -24% (L9) [OFF-2996].
- Quest ladder "Construction" (24 quests, final reward a Privilege) [OFF-3020]: timber camp, clay pit, iron mine built -> timber/clay L2 -> HQ L2 -> claim a reward -> L3 -> HQ L3 + barracks -> warehouse L2 + farm L2 -> L4 (reward: 10% construction booster) -> L5 + iron L3 -> HQ L5 + smithy (reward: L1 flag) -> wall -> market -> HQ L7, barracks L5, wall L5 (L1 flag) -> HQ L10, smithy L5, stable (reward: 10 spies) -> pits L10, iron L8 -> HQ L12, wall L10 -> pits L16, iron L15 -> HQ L15 -> pits L20 -> smithy L10 -> HQ L20 + smithy L15 -> wall L20 -> final quest toward the Academy.
- Protection: quest text says new villages are protected, "use this valuable time" to upgrade resource buildings [OFF-3020 quest 3]; enc1 `<newbie><days>3</days>` [LIVE]; the 2017 post says 5 days [FORUM-SCAV].
- enc1 starts with custom levels (HQ 15, farm 10, storage 15, barracks 5, smithy 5, pits 20, market 5, stable 5) [LIVE get_config `buildings`]; this is a world setting, not the normal start.

## 8. Session design

- Offline: production accrues offline [OFF-1176], capped by the warehouse; overflow is lost [OFF-3002, OFF-3020 quest 8].
- First minutes: first upgrades are cheap (timber camp L2 63/77/50 [OFF-5324]); base build time is 250 s for a timber camp on a speed-3.6 world [LIVE], i.e. 900 s at speed 1 (my arithmetic 250 x 3.6), then times the HQ factor (95% at HQ 1). I did not find a page stating first-upgrade durations in minutes.
- Cost grows about 25-30% per level while output grows about 16.3% per level (factors above, my arithmetic), so each level pays back later; the quest ladder alternates pits, HQ, storage and farm to keep up.
- Day scale: 2017 player estimate: scavenge runs of about 1-3.5 hours, "8 runs a day" at one option on speed 1 (or 12 with fewer troops) [FORUM-SCAV]. Premium exchange delivery 2 hours at speed 1 [OFF-265].
- Premium features seen in the world config: AccountManager, BuildTimeReduction (50%), BuildInstant, FarmAssistent (flags 0/1 per world) [LIVE get_config]; prices not verified.
- World settings for sleep and night modes exist (`<sleep>`, `<night>`, off on enc1) [LIVE get_config].

## 9. What the game shows the player about rates

- Top bar: stock and warehouse cap per resource, e.g. 53,313 wood / 222,435 clay / 21,519 iron of a 400,000 cap [OFF-1176, OFF-2960].
- Village overview: building sizes, "your current resource production", troops, troop movements; premium adds production per building, merchants and the time the warehouse will be full [OFF-2960].
- HQ screen lists requirements and cost of each next level [OFF-2960].
- Scavenge screen shows resources to be gained and return time before you start [OFF-3002]; a report on return lists origin village, units, haul [OFF-3002].
- Exact in-game layout of per-level production in each building screen: not verified (the fan tables label columns "production per hour", "capacity", "number of merchants", "time factor").

---

## What transfers to an HQ trading-company game

1. Cost grows geometrically (about x1.25-1.3 per level) while output grows slower (x1.163): the gap sets pacing. Store base + factor per asset as the server does (section 2).
2. One HQ level multiplies build times by 1.05^-level (95% to 23% over 30 levels): a cheap, readable "management reduces costs" lever (section 2).
3. Warehouse cap per resource, overflow lost, 1,000 -> 400,000 over 30 levels: forces "come back and sell" with no extra rule (section 3).
4. Population cap as the maintenance lever: every building and unit has a pop cost, cap 240 -> 24,000; growth stops at the cap. Maps to crew/captain slots and fleet size (section 4).
5. Carry capacity per unit decides the haul; unit speed does not. Cargo per captain/ship as the income driver (section 5).
6. Scavenging template for "send a crew out with a good, it returns after a time": four tiers returning 10/25/50/75% of capacity, higher tiers wait longer, tiers unlocked by paying (section 5).
7. Duration formula has a fixed floor (d2 = 1800 s before the d3 factor) plus a term that rises slower than capacity, so small crews are floor-limited and big crews have falling income per hour (section 5).
8. Merchant count by market level (1 per level to L11, then 14 ... 235) times 1,000 per merchant: a clean trade-throughput gate (section 6).
9. A quest ladder that names the next target and pays small rewards (resources, 10% build booster, flags) during the first hours (section 7).
10. Flags: stackable percentage modifiers (+4% to +18% production, -10% to -24% coin cost), merged 3-for-1: a long-tail progression layer (sections 1, 7).

## Not verified

- Production per hour for the wood and clay pits (only the iron table was opened; the 1.163118 factor is my fit); how world speed multiplies production; what `base_production 33` means.
- Premium production bonus size; bonus villages effect; item bonuses; scavenging unlock costs for options 1-3 and unlock times; haul-capacity flag levels 7-9.
- Merchant travel speed, premium exchange rate and fees, length of the free-trade restriction.
- The official build-time formula (only the third-party script plus the HQ time-factor table; my sample build times use the third-party formula and were not checked in the game); real first-upgrade durations.
- The raiding loot rule (meaning of hauls_base, hauls_max); that "Zeitfaktor" in the barracks table is the recruit-time multiplier.
- Prerequisites for the Academy and Catapult come from a third-party guide, not an official page I read.
- enc1 is a casual world with custom starting levels and scavenging off; other worlds differ in speed, protection days and coin cost.
- Official English tables are text-only for costs/population; production, storage and farm numbers come from the German fan site. The TW forum "Building Formulas" thread was not reachable.
