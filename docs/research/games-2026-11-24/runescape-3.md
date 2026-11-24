# RuneScape 3 research for an HQ trading-company game (2026-11-24)

All figures were read on runescape.wiki pages on 2026-11-24. The source URL is given under each section. Where a figure is an inference or the page did not say, it is listed under "Not verified".

Base URL for sources: https://runescape.wiki/w/

---

## 1. Player-Owned Port (PoP)

Sources: https://runescape.wiki/w/Player-owned_port ; /Player-owned_port/Buildings ; /Player-owned_port/Captains_and_crew ; /Player-owned_port/Guide

### 1.1 Entry, limits, rerolls

| Item | Value | Source |
|---|---|---|
| Entry to play | Level 90 in at least one of 12 skills (boosts do not count) | Player-owned_port |
| Captains owned | max 5 (one per ship) | Player-owned_port; Captains_and_crew |
| Crew owned | max 25; up to 5 crew per ship | same |
| Standard voyage rerolls | 15 per day, 3 voyage display slots, so max 18 standard voyages per day | Player-owned_port |
| Crew rerolls | 15 per day, reset at 00:00 UTC; hiring or forfeiting a crew member costs one; only 3 crew shown for hire at once | Captains_and_crew |
| Visiting captain | one at a time, resets 00:00 UTC or on a Captain Reroll | Captains_and_crew |
| Random event reward | +5 voyage or crew rerolls | Player-owned_port |
| Unused rerolls | lost at reset | Player-owned_port |
| Chimes cap | soft cap 200,000 per day (excess reset to 200,000) | Player-owned_port |
| Other resources cap | hard cap 999,999 each | Player-owned_port |
| Trade goods cap | 250 each | Player-owned_port |
| Daily salary in chimes | 20 (refitted office), 50 (renovated), 150 (refurbished) | Player-owned_port |
| Adventurers | 12, each needs level 90 in its own skill | Player-owned_port |
| Ship customising | 5 hotspots per ship: ram/figurehead, two deck items, rudder, hull | Player-owned_port |

### 1.2 Ships and ship slots

- The Office building adds ship slots: Refitted +1, Renovated one more, Refurbished one more. The wiki page does not give an absolute count. The Guide says an office upgrade allows "up to four voyages at a time" (Player-owned_port/Guide).
- The Guide mentions two ships in the Scythe, three by the Hook/Scythe, four in the Loop. The Guide does not map each Office level to a ship count.
- Office cost: Refitted 150 bamboo; Renovated 3,000 bamboo + 4,000 black slate; Refurbished 8,000 cherrywood + 10,000 jade (Buildings).
- Ship upgrade totals per region (Guide, https://runescape.wiki/w/Player-owned_port/Guide):

| Region | Chimes | Other resources |
|---|---|---|
| Arc | 1,380 | 1,310 bamboo |
| Skull | 7,800 | 6,400 gunpowder |
| Hook | 15,200 | 6,600 bamboo, 13,500 black slate |
| Scythe | 29,400 | 2,000 bamboo, 1,000 slate, 18,700 cherrywood |
| Bowl | 71,000 | 14,000 cherrywood, 38,900 jade |
| Pincers | 107,000 | 3,000 slate, 5,000 cherrywood, 3,000 jade, 58,200 stainless steel |
| Loop | 238,250 | 5,000 stainless steel, 53,700 terracotta |
| Shield | 312,500 | 130,300 azure |

### 1.3 Regions: distance unlock and voyage time

Source: https://runescape.wiki/w/Player-owned_port

| Region | Total distance to unlock | Distance to next | Standard distance per voyage | Standard voyages to next | Min speed / time | Max speed / time |
|---|---|---|---|---|---|---|
| Arc | start | 5,000 | 250 | 20 | 300 / 33 min | 500 / 20 min |
| Skull | 5,000 | 35,000 | 600 | 59 | 600 / 80 min | 1,000 / 48 min |
| Hook | 40,000 | 100,000 | 1,200 | 84 | 900 / 160 min | 1,500 / 96 min |
| Scythe | 140,000 | 310,000 | 2,400 | 130 | 1,200 / 320 min | 2,000 / 192 min |
| Bowl | 450,000 | 750,000 | 4,800 | 157 | 1,500 / 640 min | 2,500 / 384 min |
| Pincers | 1,200,000 | 1,100,000 | 6,000 | 184 | 1,875 / 800 min | 3,125 / 480 min |
| Loop | 2,300,000 | 1,800,000 | 6,800 | 265 | 2,325 / 906 min | 3,875 / 544 min |
| Shield | 4,100,000 | 1,900,000 | 8,000 | 238 | 2,625 / 1,066 min | 4,375 / 640 min |

- Distance counts fully only for voyages to the most recently unlocked region; other voyages add half the standard distance (Player-owned_port).
- Minimum voyage time 15 min. Scroll, trade-good and unlock missions take 50% longer, speed limits 25% higher. Story missions give 0 distance (Guide).
- Totem of Navigation reduces voyage time by 15% (Player-owned_port); Guide gives Arc 17 min and Shield 544 min with it at max speed.
- Workshop requires reaching the Hook (Buildings).

### 1.4 Success chance and failure

Source: https://runescape.wiki/w/Player-owned_port

- Success chance = the LOWEST of the three indicators (Morale, Combat, Seafaring). Example: 100%, 100%, 56% gives 56%.
- Speed affects time only, not success.
- Speed max = floor(1.25 x voyage speed); speed min = floor(0.75 x voyage speed); effective speed = max(min(speed max, ship speed), speed min).
- Failed voyage: partial completion gives 20% of rewards (Opportunist trait: 50% chance of 35%; Pilferer: 10% chance of 0%).
- Repairs after damage: mild 40 bamboo/black slate, 50 gunpowder/cherrywood, 60 jade/stainless steel/terracotta/azure; heavy 150 bamboo, 200 slate, 300 gunpowder, 450 cherrywood, 600 for the top four. Cannot pay: dry dock 1 h (mild), 2 h (damage), 5 h (heavy).
- Crew and captain survival after a lost voyage: 5% each.
- Command Centre (Fort Forinthry) adds port voyage success: +3% / +6% / +10% by tier (https://runescape.wiki/w/Fort_Forinthry).

### 1.5 Captains and crew

Source: https://runescape.wiki/w/Player-owned_port/Captains_and_crew

| Item | Value |
|---|---|
| Captain stats | Three stats share one base; the speciality stat is about double. Examples: Morale-speciality 1,050 Morale / 550 Combat / 600 Seafaring / 350 Speed, 35,000 chimes. Speed-speciality (Shield) 550/550/550/950, 27,500 chimes |
| Level range | 0 to 10; each level adds 10% of base stat |
| Cumulative XP to level | L1 7, L2 21, L3 50, L4 100, L5 200, L6 400, L7 800, L8 1,500, L9 2,300, L10 4,000 |
| XP per resource voyage by region | Arc 7, Skull 11, Hook 17, Scythe 29, Bowl 53, Pincers 65, Loop 73, Shield 85 |
| Captains earn | half crew XP; failed voyage: crew 1 XP, captain 0 |
| Traits | captains 0 to 4 traits |
| Trait examples | Tier 1 +/-40 to 80 to one stat; Tier 3 Awe-Inspiring +100 Morale, Workhorse +150 Speed; Merchant +10% to +33% goods; Solidarity +25 to +125 all stats per unique crew type |
| Trait removal | only via The Memory's final clue voyage |

Crew for hire (examples from the page):

| Crew | Morale | Combat | Seafaring | Speed | Cost | Unlock |
|---|---|---|---|---|---|---|
| Stowaway | 0 | 70 | 0 | 0 | free | Arc |
| Varrock Chef | 150 | 0 | 0 | 0 | 80 chimes | Arc |
| Dwarven Engineer | 0 | 0 | 0 | 400 | 60 chimes, 30 bamboo | Arc |
| Eastern Overseer | 120 | 120 | 120 | 0 | 400 chimes, 300 gunpowder | Skull |
| Zhonghu Player | 2,100 | 0 | 0 | 0 | 8,000 chimes, 850 azure | Shield |

### 1.6 Port buildings (costs and effects)

Source: https://runescape.wiki/w/Player-owned_port/Buildings

Bar (captain quality and adventurers):

| Tier | Cost | Effect |
|---|---|---|
| Refitted | 120 bamboo | +2% higher-quality captains |
| Renovated | 600 bamboo, 1,000 slate | +3% captains, +2% adventurers |
| Refurbished | 1,000 slate, 2,000 cherrywood | +5% captains, +3% adventurers |
| Sinister / Nautical / Luxurious | 3,000 cherrywood, 5,000 jade | +5% captains plus specialisation or +5% adventurers |
| Opulent | 5,000 terracotta, 5,000 stainless steel | 7% captains, 5% adventurers |
| Malevolent / Maritime / Ostentatious | 5,000 azure | up to 10% specialty captains, 7-8% captains, 6-8% adventurers |

Lodgings (crew quality): Refitted 1,500 gunpowder (+2%); Renovated 1,000 bamboo + 3,000 slate (+4%); Daredevil 2,000 bamboo + 3,000 cherrywood (+5%, +2% speed crew); Cutthroat/Nautical/Luxurious 6,000 stainless steel + 3,000 slate (+5%, +2-3% specialty); Fearless/Swashbuckler/Mariner 10,000 azure (+7%, +3% specialty).

Shipwright (ship stats): Refitted 100 bamboo (+2%); Renovated 2,000 gunpowder (+3%); Nautical 5,000 cherrywood (+3%, +2% seafaring); Warship/Luxurious/Sleek 6,000 stainless steel + 3,000 jade (+3%, +2% one stat); Ostentatious/Battleship/Maritime 10,000 azure (+5%, +3% one stat).

Workshop (needs the Hook): Refitted 2,000 bamboo + 500 slate (+5% workshop skill XP, bank); Renovated 3,000 cherrywood + 6,000 jade (+10%); Refurbished 5,000 cherrywood + 10,000 stainless steel (+15%); Revamped 20,000 azure (+20%).

Warehouse (more rewards; the only building that costs chimes):

| Tier | Cost | Effect |
|---|---|---|
| Dilapidated | free | +2% chimes |
| Refitted | 200 chimes, 80 bamboo | +3% chimes, +5% bamboo |
| Renovated | 1,200 chimes, 500 gunpowder | +4% chimes, +10% bamboo, +5% gunpowder |
| Refurbished | 2,000 chimes, 1,000 slate | +5% chimes, +5% slate |
| Spacious | 3,000 chimes, 2,000 cherrywood | +6% chimes, +5% cherrywood |
| Pristine | 8,000 chimes, 4,000 jade | +7% chimes, +5% jade |
| Imperial | 15,000 chimes, 10,000 stainless steel | +8% chimes, +5% steel |
| Dynastic | 25,000 chimes, 15,000 terracotta | +9% chimes, +5% terracotta |
| Sovereign | 50,000 chimes, 20,000 azure | +10% chimes, +5% azure |

Totems: each costs 3,000 jade + 2,000 cherrywood; stacking gives +4%, +7%, +9%, +10% for 1 to 4 of a type. Types: telescope (scroll voyages), parrot (XP voyages), cherry tree (extra resource rewards), Pandora's Box (random events), jade statue (trade good voyages), map table (clue voyages).
Icons: 1,000 chimes each; need 90 in the matching skill and the adventurer's first story voyage done.

### 1.7 Resources and trade goods

Source: https://runescape.wiki/w/Player-owned_port

- Resources: chimes, bamboo, black slate, cherrywood, jade, gunpowder, stainless steel, terracotta, azure. (The Guide's regional costs above show the resource ladder by region: Arc bamboo, Skull gunpowder, Hook slate, Scythe cherrywood, Bowl jade, Pincers stainless steel, Loop terracotta, Shield azure.)
- Trade goods: ancient bones, spices, chi, plate, lacquer, koi scales, pearls.
- Trade good quantity per standard trade-good voyage (Hook, Scythe, Bowl, Pincers, Loop, Shield): 1, 2, 3, 5, 6, 8. Spices: 10, 15, 20, 30, 35, 40. Merchant units multiply by up to 1.33x (Guide).
- Guide gives minimum reward examples: Ardougne Storekeeper 300 bamboo; Terracotta Merchant 1,250 terracotta.

### 1.8 Special voyages and adventurers

- 12 adventurers, each tied to a 90-level skill and attracted by an icon (list in Buildings: Whaler/Fishing, Biologist/Herblore, Occultist/Runecrafting, Assassin/Slayer, Convict/Thieving, Missionary/Prayer, Trapper/Hunter, Chef/Cooking, Architect/Construction, Exile/Dungeoneering, Memory/Divination, Tengu/Agility).
- 6 clue adventurers, 3 clue voyages each. Reefwalker's cape needs 4 scroll pieces. Port score achievements at 400, 800, 1,200, 1,600, 2,000, 3,500, 4,500. Eastern Explorer achievement at 4,100,000 distance (Player-owned_port).
- Reward items need skill levels (e.g. Smithing 90-92, Cooking 93/99, Crafting 90, Invention 88) (Player-owned_port).

---

## 2. XP curve and level unlocks

Source: https://runescape.wiki/w/Experience

Formula (regular skills): xp(L) = floor( (1/4) x sum for n = 1 to L-1 of floor( n + 300 x 2^(n/7) ) ). Elite skills (Invention) use a different curve. Maximum 200,000,000 XP per skill.

| Level | Total XP |
|---|---|
| 2 | 83 |
| 10 | 1,154 |
| 20 | 4,470 |
| 30 | 13,363 |
| 40 | 37,224 |
| 50 | 101,333 |
| 60 | 273,742 |
| 70 | 737,627 |
| 80 | 1,986,068 |
| 90 | 5,346,332 |
| 99 | 13,034,431 |
| 110 | 38,737,661 |
| 120 | 104,273,167 |

Mining tiers (https://runescape.wiki/w/Mining): copper/tin 1; iron 10; coal 20; mithril 30; adamantite 40; runite 50; orichalcite 60; necrite 70; banite 80; light animica 90; novite 100. Each tier has a durability and a hardness; the pickaxe penetration must meet or exceed the rock hardness or yield drops. Pickaxe tiers: bronze 1, iron 10, steel 20, mithril 30, adamant 40, rune 50, orikalkum/dragon 60, necronium/crystal 70, bane 80, elder rune 90, primal 100. Example numbers: iron durability 120 / hardness 5; novite 3,000 / 275.

Woodcutting (https://runescape.wiki/w/Woodcutting): normal 1, oak 10, willow 20, teak 30, maple 40, acadia 50, mahogany 60, yew 70, magic 80, elder 90, crystal 94, eternal magic 100. Hatchets follow the same 10-level steps (rune 50, dragon 60, crystal 70, elder rune 90, primal 100).

Fishing (https://runescape.wiki/w/Fishing): shrimp 1, trout 20, salmon 30, tuna 35, lobster 40, swordfish 50, monkfish 62, shark 76, manta ray 81, cavefish 85. Different tools per fish type; some spots are in gated areas (Menaphos Port district, Piscatoris, City of Um).

Pattern: tier unlocks every 10 levels up to 90 or 100, and the better tool unlocks at the same level as the resource.

---

## 3. Timed and assigned-work systems

### 3.1 Managing Miscellania
Source: https://runescape.wiki/w/Managing_Miscellania

| Item | Before Royal Trouble | After Royal Trouble |
|---|---|---|
| Max coffer | 5,000,000 | 7,500,000 |
| Daily withdrawal | 10% of coffer, capped at 50,000 | capped at 75,000 |
| Coffer for full daily resources | 500,000 | 750,000 |
| Approval decay | 3 points/day (of 127) | 1 point/day |
| Subjects (workers) | 10 | 15 |
| Max per resource | 10 | 10 |

- Resources gathered = approval rating x daily withdrawal. Example: 95% approval and 75,000 withdrawn gives 71,250 coins of resource value; 3,750 wasted.
- Approval scale 0 to 127; floor 31/127 (about 25%) from decay alone. Approval is raised by doing the matching skilling in the kingdom (e.g. +1 per weed/log, +3 or +6 with boots 2 or 4); killing a civilian costs 6.
- Six resource categories, freely split. Max daily output example (Royal Trouble, 10 workers, 100%): 892 maple logs; 546 coal; 301 teak.
- Approval boost: Miscellania Table, 750 coins per subject per day sets approval to 100% for up to 7 days (needs Command Centre Tier 3).
- Drain happens every 24 hours at the time the quest was completed.

### 3.2 Player-Owned Farm
Source: https://runescape.wiki/w/Player-owned_farm

- Requirements: Farming 17 and Construction 20 to start. Pens: small 6 animals (Farming 17), medium 4 (Farming 35), large 3 (Farming 49). Two of each size, plus one breeding pen of 4.
- Growth totals to elder: rabbit 60 min, sheep 120 min, cow 360 min, chicken 250 min, spider 1,512 min, chinchompa 2,520 min, yak 4,032 min, zygomite 5,040 min, dragon 10,080 min. Animals grow offline.
- Breeding: success 40% (rabbit) to 80% (dragon); breeding pen guarantees success after 5 consecutive failures. Shiny base chance 0.1%.
- Traits: 78 in total, 1 to 3 slots per animal; perks in tier 1 and tier 2.
- Feeding (this is the upkeep): each animal eats 1 food per hour; wrong food drops health and happiness 10% per hour; trough holds up to 1,000 items; low health or happiness can cut produce to 10% of maximum.
- Beans: adolescents sell for the most beans, elders yield the most XP and produce. Seasonaliser wheel costs 5,000 beans.

### 3.3 Anachronia base camp
Source: https://runescape.wiki/w/Anachronia_base_camp

| Item | Value |
|---|---|
| Starting workers | 10 |
| Sleeping Quarters | T1 +5 (15), T2 +15 (30), T3 +30 (60); Command Centre adds 5 and 5 more (up to 70) |
| Output | 60 of the resource per worker per hour (1,440 per day per worker, derived by the page reader as workers x 60 x 24; the page gives 60/hour) |
| Updates | roughly every 10 minutes, continues offline |
| Storage cap per resource | 5,000 (none), 25,000 (T1), 80,000 (T2), 150,000 (T3) |
| Resources | wood, vines, leaves, hides, stone, clay |

Costs: Town Hall T1 1,000 each wood/vines/stone; T2 20,000; T3 70,000. Storehouse T1 3,000 vines/hides/stone; T2 22,000; T3 75,000. Sleeping Quarters T1 10,000 wood/leaves/hides; T2 65,000; T3 130,000. Lodges (Spa, Hunter, Slayer, Player) need level 40/70/90 in the skill and cost 7,500-12,000 / 60,000-75,000 / 120,000-150,000 each of three resources. No upkeep listed on the page.

### 3.4 Fort Forinthry
Source: https://runescape.wiki/w/Fort_Forinthry

- Buildings have 3 tiers gated by Construction level: Workshop 1/35/75; Town Hall 10/45/80; Chapel 15/55/90; Command Centre 25/70/99; Kitchen 25/50/85; Guardhouse 40/65/95.
- Each tier costs Construction XP (e.g. Workshop 2,304 / 17,280 / 110,592) and frames (wooden to elder) plus 6 stone wall segments.
- Town Hall rested XP cap 500 / 1,000 / 1,500; rested XP accrues 1 per 15 min logged out.
- Command Centre tiers give port success +3/+6/+10%, Anachronia workers +5/+10, Chronote cost -3% at T2. No upkeep on the page.

### 3.5 Invention and divine charges
Source: https://runescape.wiki/w/Invention

- Machines need Invention 60, up to 6 devices with 2 tiers each, run offline, and are powered by a generator fed with divine charges.
- Augmented items use divine charges from the charge pack instead of degrading. Each divine charge costs 225 incandescent energy (or more lower-tier energy).
- On death an unprotected augmented item drains 2 hours of its drain rate (example: 1 charge per second loses 7,200).
- Item level lowers drain by 10% at level 5, 12.5% at 14, 15% at 18.
- Machine charge-use rates are not on the page.

### 3.6 Menaphos reputation
Source: https://runescape.wiki/w/Menaphos_reputation

- City reputation tiers (cumulative): 4,000, 6,600, 19,800, 39,600, 66,000, 99,000, 141,900, 194,700, 254,100, 330,000 (tiers 1 to 10).
- District tiers (Imperial, Port, Merchant, Worker) thresholds from tier 2: 6,000, 18,000, 36,000, 60,000, 90,000, 129,000, 177,000, 231,000, 300,000.
- Unlocks: tier 1 GE and bank; tier 7 VIP skilling area access; tier 8 district skilling boost; bank deposit box at district tier 2; bank chest at district tier 6.
- Daily cap: soul obelisks yield up to 20,060 base reputation per day. No other cap stated.

---

## 4. Money sinks and faucets

| Item | Figure | Source |
|---|---|---|
| Grand Exchange tax | 2% of sale price, withheld from seller, per item, rounded down, introduced 9 Jan 2023. Exempt: items under 50 coins, bonds. Page shows no cap in that section | https://runescape.wiki/w/Grand_Exchange |
| GE buying limits | quantity per item per 4 hours, countdown starts at first purchase; some items share limits | same |
| Armour repair at armour stand | base discount 0.5%, plus 0.5% per Smithing level (page wording) | https://runescape.wiki/w/Repair_cost |
| Degradation | max drain 1 charge per tick; 30,000 charges lasts 16.7 h average combat | same |
| Example full recharge | Ahrim's hood/top/skirt 180,000 / 270,000 / 240,000 coins (100,000 charges); Linza's cuirass 2,000,000 | same |
| Invention charges | 225 incandescent energy per divine charge | Invention |
| High Level Alchemy | Magic 55; 5 fire + 1 nature rune, 574 coins (369 with a fire staff); yields 60% of item value; 1,200 casts/hour max; 65 XP per cast | https://runescape.wiki/w/High_Level_Alchemy |
| Alchemy as faucet | the wiki says some buyable items yield more than they cost and this is a major cause of inflation; alchemy sets a price floor | same |
| Port repairs, rerolls | see 1.4 | Player-owned_port |

---

## 5. Area gating

- Port regions: by cumulative distance (1.3), plus level 90 in one skill to play at all.
- Resource tiers: by skill level in 10-level steps (section 2).
- Fort Forinthry and Anachronia buildings: by Construction (or Agility/Hunter/Slayer) level 40/70/90 plus quest prerequisites (Fort Forinthry page lists quests such as New Foundations, Unwelcome Guests).
- Menaphos: reputation tiers per city and per district (3.6).
- Miscellania: quest completion (Throne of Miscellania, Royal Trouble) raises caps (3.1).
- Daily and weekly caps seen: port rerolls 15/day and 200,000 chimes/day; Menaphos obelisk rep 20,060/day; GE buy limits per 4 h.

---

## 6. Reward pacing and UI

- Level 2 needs 83 XP; level 99 needs 13,034,431; level 92 is about half of that for regular skills, level 84 for Invention (Experience, Invention pages).
- Between level 90 and 99 the XP needed is about 7.7 million, roughly 1.4 times the entire amount from level 1 to 90.
- Fort Forinthry Construction XP costs scale about 7-8x per tier (Workshop 2,304 to 17,280 to 110,592).
- Port voyage time scales from 20 min to 640 min with region; voyages needed to unlock the next region run 20, 59, 84, 130, 157, 184, 265, 238 (1.3).
- XP/hr and GP/hr examples on the wiki: alchemy 78,000 Magic XP per hour at maximum casts (High_Level_Alchemy).
- UI elements (XP tracker, RuneMetrics, time to level): not checked on a page. See "Not verified".

---

## What transfers to an HQ trading-company game

1. Ports first: success chance = the lowest of three indicators (morale, combat, seafaring), not an average. This makes crew balance matter and is easy to show as three bars.
2. Region ladder by cumulative distance, not by level: the next region needs total distance sailed to the newest region, and older regions add half. Voyages needed rise from 20 to 265 per step.
3. One resource per region (bamboo, gunpowder, slate, cherrywood, jade, steel, terracotta, azure) that is also the currency for upgrading buildings at that depth. Upgrades always cost what the region gives.
4. Building tiers with plain percentage effects (warehouse +2% to +10% chimes and +5% for the newest resource) and rising costs; only the warehouse costs the soft currency.
5. Slot limits as the pacing tool: 5 captains, 25 crew, 5 crew per ship, ship slots from Office upgrades, 15 rerolls per day, 3 offered at a time.
6. Daily salary and soft cap: 20/50/150 chimes per day and a 200,000/day cap on the main currency.
7. Level-and-XP on workers: levels 0 to 10, each +10% of base stat, XP per voyage by region, cumulative 7 to 4,000.
8. Offline production with storage caps (Anachronia: 60 per worker per hour, caps 5,000 to 150,000). Matches "gold per hour (+/-)" with a hard stop at storage full.
9. Coffer model (Miscellania): daily withdrawal = 10% of coffer capped at a limit, output = approval x withdrawal, approval decays daily. A ready-made dividend/upkeep pattern.
10. Charge-based maintenance plus a fixed trade tax: repair cost discounted by a skill (0.5% per level) and GE tax of 2% with a 50-coin floor give two simple sink models.

---

## Not verified

- Exact ship count per Office level (page gives only increments; the Guide says up to four voyages at a time).
- Captain cost table for lower tiers (the page's table was garbled), and the Judge of Dice cost resource.
- The voyage success indicator formulas (how ship and crew stats are turned into the percentage per indicator) and the three "adversity" values per voyage were not on the pages read.
- Per-region resource reward amounts per voyage (only two minimum-reward examples).
- The 0.5% per Smithing level repair discount is the page's wording; the 50% at 99 figure and any cap are not stated. The Repair_cost page was truncated (197,865 characters unread).
- The Anachronia "1,440 per day" figure is a multiplication of the stated 60 per hour.
- Invention elite XP formula and level-120 XP; machine charge consumption.
- Death/reclaim fees and gravestone costs (Death page does not give them; separate pages not read).
- Whether the GE tax has a cap (the section read mentions none; other parts of the page were not read).
- XP tracker, RuneMetrics and time-to-level UI details; XP/hr and GP/hr culture beyond alchemy; Jagex news posts were not read.
- Menaphos tier 1 district threshold; Player-owned farm beans price table and the last 190,929 characters of that page.
- Special voyages page and random events/lifeboats details were not read directly.
