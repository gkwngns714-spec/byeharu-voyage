# Melvor Idle - research notes for an HQ trading-company game

Date read: 2026-11-24. Game version on every wiki page read: v1.3.1 (released 30 Oct 2024).
Method note: the wiki blocks the normal page fetcher (HTTP 403), so pages were read with curl and stripped to text. Item/resource icons were lost in that text, so in some tables (Township building costs) the resource TYPE of each cost number is not readable. Wiki base: https://wiki.melvoridle.com/w/ (page name appended). No developer blog or patch-note page was read (see Not verified).

---

## 1. XP curve, Mastery, Mastery Pool

Source: https://wiki.melvoridle.com/w/Experience_Table and https://wiki.melvoridle.com/w/Mastery

**Level formula (wiki says "approximately"):** XP difference between level L-1 and L = floor( (L - 1 + 300 * 2^((L-1)/7)) / 4 ). XP roughly doubles every 7 levels.

| Level | Total XP | Step from previous level |
|---|---|---|
| 2 | 83 | 83 |
| 10 | 1,154 | 185 |
| 30 | 13,363 | 1,332 |
| 50 | 101,333 | 9,612 |
| 60 | 273,742 | 25,856 |
| 80 | 1,986,068 | 187,260 |
| 99 | 13,034,431 | 1,228,825 |
| 101 | 15,889,109 | 1,497,949 |
| 110 | 38,737,661 | 3,652,007 |
| 120 | 104,273,167 | 9,830,430 |

The wiki also says XP from level 1 to 92 equals XP from 92 to 99. Base game cap is 99; the Throne of the Herald expansion raises the skill cap to 120; Into the Abyss adds an Abyssal cap of 60 (skill pages). Mastery levels use the same table and caps.

**XP per action and rate:** each action lists a fixed XP; XP/hour = XP per action x 3600 / interval seconds. Examples (https://wiki.melvoridle.com/w/Woodcutting): Normal Tree 10 XP / 3 s = 3.33 XP/s; Magic Tree 100 XP / 20 s = 5.00 XP/s; Redwood 180 XP / 15 s = 12.00 XP/s. Wiki gathering pages show "XP/s" and "Price/s" columns.

**Interval maths** (https://wiki.melvoridle.com/w/Interval): effective interval = max( floor( (base x (1 - sum of % reductions) - sum of flat reductions) / 0.05 ) x 0.05 , 0.25 s ). Reductions are taken off the BASE interval and added together, so each extra -10% is worth more as the total grows. Game tick 0.05 s; minimum action time 0.25 s.

**Mastery XP per action** (Mastery page): [ (UnlockedActions x PlayerTotalMastery / TotalMastery) + (ItemMasteryLevel x TotalItems / 10) ] x ActionTime x 0.5 x (1 + Bonus). Action time is the real seconds for gathering skills (so Mastery XP per second stays constant when the interval shrinks); for artisan skills it is a fixed value (Smithing 1.7, Fletching 1.3, Crafting 1.65, Runecrafting 1.7, Herblore 1.7, Summoning 4.85, Cooking 85% of base interval, Firemaking 60% of base burn interval); for Farming it is growth time in hours.

**Mastery Pool** (Mastery page):

| Fact | Value |
|---|---|
| Share of each Mastery XP gain added to the pool | 25% (50% after skill level 99 "Skill Mastery") |
| Pool cap | 500,000 x number of items in the skill; excess lost |
| Checkpoints | pool 10%, 25%, 50%, 95% full |
| Spending | pool XP converts to item Mastery XP 1:1; dropping below a threshold switches that checkpoint bonus OFF until refilled |
| Mastery Token | adds 0.1% of the pool maximum |
| 10% checkpoint, all skills except Thieving | +5% Mastery XP for that skill |

**Checkpoint examples (base-game pool XP / all-expansions pool XP)**, each from https://wiki.melvoridle.com/w/<Skill>:

| Skill | 10% | 25% | 50% | 95% |
|---|---|---|---|---|
| Woodcutting (4.5M / 10M) | +5% Mastery XP | +5% double items | +50% GP from log sales | +1 base Bird Nest qty |
| Mining (5.5M / 11.5M) | +5% Mastery XP | -10% node respawn interval | -0.2 s interval | +10 node HP |
| Farming (12M / 19.5M) | +5% Mastery XP | crops cannot die | +5% base primary qty | -10% Farming interval |
| Thieving (11.5M / 17M) | +30 Stealth, +3% skill XP | -0.2 s interval, +3% Mastery XP | +100% GP from Thieving | +100 Stealth, +200% area unique drops |
| Smithing (57.5M / 106M) | +5% Mastery XP | +5% preserve | +5% preserve | +10% double |
| Crafting (28.5M / 57M) | +5% Mastery XP | +5% preserve | -0.2 s interval | +1 qty rings and necklaces |
| Agility (25.5M / 39.5M) | +5% Mastery XP | +10% GP from Agility | -10% obstacle item and currency build cost | -15% obstacle item build cost |
| Summoning (10M / 14.5M) | +5% Mastery XP | -1 shard cost tier 1-2 familiars | +10% preserve | +10 base qty, -1 shard tier 3 |

**Item Mastery level unlocks (per recipe or node):**
- Woodcutting: every 10 levels +5% chance of 2 logs; level 99 -0.2 s cut interval for that tree.
- Mining: each Mastery level +1 max Rock HP; levels 10 to 90 add +1% double-ore per step (to 9%); level 99 15%.
- Smithing: levels 10/30/50/70/90 +5% double; levels 20/40/60/80 +5% preserve; level 99 +10% preserve and +10% double.
- Cooking: each level +0.6% success; levels 10 to 90 +5% Perfect Cook each; level 99 +50% Perfect Cook and +20% healing.

**Preservation** (https://wiki.melvoridle.com/w/Preservation): generic preservation chance is capped at 80% for all skills (a few effects raise the cap). With preserve chance p, N inputs give N/(1-p) actions (wiki example: 120 bars at 80% = 600 daggers).

---

## 2. Gathering skills

**Woodcutting** (https://wiki.melvoridle.com/w/Woodcutting): trees never deplete.

| Tree | Level | XP | Interval |
|---|---|---|---|
| Normal | 1 | 10 | 3 s |
| Oak | 10 | 15 | 4 s |
| Willow | 25 | 22 | 5 s |
| Teak | 35 | 30 | 6 s |
| Maple | 45 | 40 | 8 s |
| Mahogany | 55 | 60 | 10 s |
| Yew | 60 | 80 | 12 s |
| Magic | 75 | 100 | 20 s |
| Redwood | 90 | 180 | 15 s |

Bird Nest 0.5% per action. Axe shop upgrades (permanent, no equipping): Iron lvl 1 50 GP (-5% time); Steel lvl 10 750; Black lvl 20 2,500; Mithril lvl 35 10,000; Adamant lvl 50 50,000; Rune lvl 60 200,000; Dragon lvl 80 2,000,000 (total -40%). Multi-Tree (cut 2 trees at once) 1,000,000 GP (https://wiki.melvoridle.com/w/Shop). Expansion axes cost 50M to 200M GP plus a second currency.

**Fishing** (https://wiki.melvoridle.com/w/Fishing): each catch rolls a random interval between a min and max. Raw Shrimp lvl 1, 4-8 s (avg 6 s), 5 XP; Raw Lobster lvl 40, 4-11 s, 50 XP; Raw Shark lvl 70, 7-15 s, 150 XP. 15 Melvor fishing areas, each with its own fish/junk/special split (Shallow Shores 75/25/0).

**Mining** (https://wiki.melvoridle.com/w/Mining): base action 3 s.

| Fact | Value |
|---|---|
| Max rock HP | 5 + Mastery level + boosts |
| HP regen | 1 per 10 s (not during respawn) |
| Respawn after full depletion | Copper/Tin 5 s, Iron 10 s, Coal 10 s, Silver/Gold 15 s, Mithril 20 s, Adamantite 30 s, Runite 1 min, Dragonite 2 min, Pure Crystal 4 min |
| Level gates | Copper/Tin 1, Iron 15, Coal 30, Silver 30, Gold 40, Mithril 50, Adamantite 70, Runite 80, Pure Crystal 85, Dragonite 95 |
| XP / sell value | Copper 7 XP / 2 GP; Iron 14 / 5; Mithril 65 / 65; Runite 86 / 100; Dragonite 101 / 135 |
| Never-depletes condition | zero-damage chance >= ceil(1 - interval/10) |

Pickaxes (permanent shop upgrades): Iron lvl 1 250 GP; Steel lvl 10 2,000; Black lvl 20 10,000; Mithril lvl 35 50,000; Adamant lvl 50 200,000; Rune lvl 60 1,000,000; Dragon lvl 80 5,000,000; total -50% time.

**Thieving** (https://wiki.melvoridle.com/w/Thieving): base 3 s per attempt. Success = min(1, (100 + Stealth) / (100 + Perception)). Failure stuns 3 s and deals damage up to the NPC's max hit. Man lvl 1, 5 XP, perception 110, gold 1-100; Golbin lvl 8, 10 XP; Bandit Thug lvl 12, 13 XP, perception 220.

**Farming** (https://wiki.melvoridle.com/w/Farming and https://wiki.melvoridle.com/w/Seeds):

| Fact | Value |
|---|---|
| Plots | 1 free allotment plot; more bought with GP and level-gated (plot 2: 500 GP; plot 3: 5,000; plot 4 lvl 5: 10,000 plus 20 Giant Clay Pot; plot 15 lvl 85: 4,000,000 plus 350 pots) |
| Herb plots | plot 1 lvl 15: 50,000; plot 4 lvl 80: 400,000 |
| Seeds per planting | allotment 3, herb 2, tree 1 |
| Survival | no fertiliser 50%; each Compost +10% (5 = guaranteed); Weird Gloop fills the bar with 1 and adds +10% harvest; guaranteed at item Mastery 50 or the 25% pool checkpoint |
| Growth, allotments | Potato lvl 1 2 h (8 XP); Onion lvl 5 2 h; Sweetcorn lvl 20 3 h; Watermelon lvl 47 4 h (78 XP); Pumpkin lvl 100 5 h; Starfruit lvl 118 7 h 30 m |
| Growth, trees | Oak lvl 15 6 h 40 m (5,835 XP); Yew lvl 60 13 h 20 m; Magic lvl 75 16 h; Carrion lvl 120 22 h |
| XP | planting gives seed XP once; harvest XP = base XP x items harvested (allotment, herb); trees give fixed XP |
| Seed return | from Mastery 16, up to 1 seed back, rising at 31/46/61/76/91 |

Farming has no auto-replant offline (https://wiki.melvoridle.com/w/Offline).

---

## 3. Production skills

- **Smithing** (https://wiki.melvoridle.com/w/Smithing): ores to bars. Bronze Bar lvl 1, 5 XP; Iron Bar lvl 10, 8 XP; Steel Bar lvl 25, 12 XP; Mithril lvl 40, 35 XP; Runite lvl 70, 50 XP. Base time 2 s. Skillcape (lvl 99, 1,000,000 GP) -50% coal cost. Smithing Gloves 100,000 GP for 500 charges, +60% skill XP.
- **Cooking** (https://wiki.melvoridle.com/w/Cooking): base 70% success, +0.6% per Mastery level, 100% at Mastery 50. A failure gives 1 XP and loses the ingredients unless preserved. Perfect Cook: +10% healing, +50% sale value. Passive cooking is 5x slower and gives no XP.
- **Crafting** (https://wiki.melvoridle.com/w/Crafting): Leather Gloves lvl 1, 13 XP, 1 leather; Hard Leather Body lvl 44, 50 XP, 3 leather. Skillcape -0.5 s interval.
- Doubling/preserve chances: see section 1 (Mastery unlocks and checkpoints) and the 80% preserve cap.

---

## 4. Township (closest analogue to HQ estates)

Source: https://wiki.melvoridle.com/w/Township unless noted. No Mastery; runs on a town update **every hour** ("Each hour, a town update will occur"). Resources and GP are gained each update; buildings and health decay over time.

| Mechanic | Fact |
|---|---|
| Tick | 1 hour |
| Population | +1 Township XP per citizen per update; scaled by Happiness %; falls 1% per 1% health lost |
| Happiness | flat multiplier on population/XP; no cap |
| Education | +1% building production per 1%; no cap |
| Health | after level 15, 25% chance per update of -1% (floor 20%); restored by converting Herbs or Potions, cost 10% of that resource's per-update output |
| Building decay | each update each building has 25% chance of -1% efficiency, floor 20%; Storage buildings do not decay |
| Production | Base x (1 + biome/building bonus) x (1 + Education + resource bonus) x (efficiency / 100) |
| Repair cost | (BaseBuildingCost / 3) x BuildingsBuiltInBiome x (1 - BuildCostReduction%) x (1 + RepairCost%) x (1 - Efficiency%); minimum 1 resource; build-cost reduction capped at 80%; each Market -0.25% repair cost |
| Free repair | building another of the same building (if max not reached) fully repairs the existing one |
| Taxes (GP) | tax rate starts 0%, +10% per Town Hall, max 80%; each citizen pays 1.5 GP per 10% of tax rate per update; not affected by global GP modifiers |
| Town Hall | level 80, max 8, +10% tax rate each; listed first cost number 100,000,000 |
| Storage | base 50,000 per resource; Storehouse (lvl 1, max 20) +5,000; Warehouse (lvl 35, pop 2,500) +25,000; Repository (lvl 80) +300,000 (Grasslands figures). No gain above cap |
| Biomes | 10 Melvor biomes; Grasslands/Forest/Mountains/Water level 1; Swamp/Valley/Arid Plains level 15; Jungle/Desert/Snowlands level 35 and population 2,500 |
| Housing | Basic Shelter (max 20, lvl 1) +5 pop; Wooden Hut (max 30) +10; House (lvl 15, max 20) +40; Cottage (lvl 35, pop 2,500) +80; Large Cottage (lvl 60, pop 15,000) +160; Manor (lvl 100, pop 80,000) +240; Estate (lvl 110, pop 175,000) +360 |
| Building limits | each building has a max count; at max, an upgrade to the next tier appears; buildings cannot be destroyed or downgraded (except worship buildings) |
| Trading Post | lvl 15, each built -0.33% trade cost; 49.5% off after 150 |
| Seasons | 72 h each, order Spring, Summer, Fall, Winter; rare seasons need a particular worship and have a 20% chance to replace a regular one |
| Season effects | Spring +50% Happiness, +25% Food/Herbs/Potions/Leather, -25% repair, +50% Education; Summer +25% GP, -10% repair, -25% ore/stone/coal/bar; Fall -15% repair, +25% Wood/Planks/Clothing; Winter -50% Happiness, +50% repair, -50% GP, -50% Education |
| Worship | stat cap 2,000; checkpoints at 5/25/50/85/95%; per-biome production bonuses and building cost cuts (-15% to -25%); changing worship costs 50,000,000, destroys all Chapels/Statues and cuts buildings above 50% efficiency to 50% |
| Tasks | main tasks once; casual tasks assigned every 5 h, max 5 incomplete; skipping costs GP |
| Resources | 12 Melvor resources (GP, Food, Wood, Planks, Stone, Bar, Ore, Coal, Rune Essence, Herbs, Potions, Leather, Clothing in the page list) held in Storage; GP goes straight to the Bank |

Building cost examples (lists of several numbers; resource types unreadable in my capture): Basic Shelter 100/10/10; Fishermans Dock 1,300/150/113; Farmland 440/50/38; Storehouse 1,750/200/150; Market (lvl 15, max 100) 4,000/2,500/2,000/5,000; Trading Post 500,000/5,000/7,500/5,000/2,000/2,000. First numbers of the housing line rise by tier: Wooden Hut 700, House 7,000, Cottage 29,000, Large Cottage 102,000, Manor 244,000, Estate 591,000 (Grasslands).

---

## 5. Gold faucets and sinks

Sources: https://wiki.melvoridle.com/w/Shop, https://wiki.melvoridle.com/w/Bank, https://wiki.melvoridle.com/w/Gold_Pieces, https://wiki.melvoridle.com/w/Slayer_Coins

- GP faucets (Gold_Pieces page): selling bank items; Thieving; Agility; Alt. Magic alchemy; killing monsters. Also Township tax hourly (section 4).
- **Bank slot cost** C_b = floor( 132,728,500 x (n+2) / 142,015^(163/(122+n)) ), n = slots already bought. Start 20 slots. Sample (Bank page): n=0 34 GP; n=10 691; n=30 12,673; n=50 90,413. Capped at 5,000,000 GP each after 118 purchases. Bank Slot Tokens add slots without raising the price.
- Hardcore slot limit: Shop page says 88, Bank page says 108 (disagree).
- Bank tabs: start 12; extra tabs 10,000 / 100,000 / 1,000,000 / 10,000,000 / 100,000,000; max 10 purchasable per Shop page.
- Other sinks: axes 50 to 2,000,000 GP; pickaxes 250 to 5,000,000; Multi-Tree 1,000,000; Auto Eat Tier I/II/III 1M/5M/20M; extra equipment set up to 100,000,000; skillcape 1,000,000 (lvl 99), superior 10,000,000 (lvl 120); Township worship change 50,000,000.
- Slayer Coins: earned from Slayer tasks, 10% of the slain monster's hitpoints; spent in the Shop. Resupply packs (Slayer_Coins page): Basic 5,000 SC = 91,600 GP value (18.32 GP/SC); Standard 10,000 SC = 221,500; Generous 20,000 = 483,800; Plentiful 75,000 = 2,165,900; Bountiful 150,000 (lvl 110) = 8,323,500 (55.49 GP/SC).
- https://wiki.melvoridle.com/w/Money_Making lists max profit per method from about 306k GP/hr (Mining with Gem Gloves) up to 110b-225b GP/hr (endgame Into the Abyss). Prices and sinks scale by orders of magnitude; I found no source stating a designed inflation brake.

---

## 6. Offline progress

Source: https://wiki.melvoridle.com/w/Offline and https://wiki.melvoridle.com/w/Beginners_Guide
- Cap: **24 hours**.
- Method: on close the game records the skill and action being done; on return it measures time away (max 24 h) and simulates it as if the game had stayed open. The wiki says there is no difference between online and offline gain apart from not being able to switch actions. Mastery level-ups apply within the simulated session.
- Return: a summary popup of what was earned (Skill XP, Mastery XP, items), then the action continues.
- Rules: combat and Thieving are off offline until "Toggle Offline Combat" is on (Thieving can kill you). Farming does not replant. Potions work offline only with Auto Re-use Potion. Equipped gloves and skillcapes work. Mastery Tokens can drop offline.
- Browser throttling or a hidden tab can also trigger offline progression (Settings page).

---

## 7. Unlock pacing and the Agility course

- Start: at level 1 a new player can cut Normal Trees, mine Copper/Tin, fish Shrimp, cook, pickpocket Man, plant Potatoes, and fight many zones with no requirement (https://wiki.melvoridle.com/w/Combat_Areas: Farmlands, Golbin Village, Graveyard, Sandy Shores, Wet Forest, Bandit Hideout and others list "None"). Beginners Guide advice: start with Woodcutting, Mining or Fishing; get all skills to about level 30.
- Later combat zones need an item or discovery (e.g. Tree Overgrowth: Old Route Chart).
- Slayer areas (https://wiki.melvoridle.com/w/Slayer_Area): Penumbra lvl 1; Strange Cave lvl 10 + Mirror Shield; Holy Isles 30; Crystal Caves 40; Arid Plains 50 + Desert Hat; High Lands 60 + Magical Ring; Toxic Swamps 65; Perilous Peaks 85; Dark Waters 90; Millennium Gate 118. Each has an area-effect penalty.
- Skill-gated items: tools by level (section 2), Skillcape at 99, Township buildings by level and population.
- **Agility** (https://wiki.melvoridle.com/w/Agility): a course of obstacle slots; each built obstacle gives global bonuses AND penalties, and completing it pays XP, Mastery XP and GP.
  - Cargo Net (slot 1, lvl 1): 10,000 GP; +3% global GP, +2% Fishing Mastery XP.
  - Balance Beam (slot 2, lvl 10): 50,000 GP; +2% Agility XP.
  - Pit Jump (slot 3, lvl 20): 150,000 GP + 300 Raw Herring + 300 Raw Salmon; +3% skill XP all skills, -4% Agility XP.
  - Pipe Balance (slot 3): +3% preserve resources, +10 Mining node HP.
  - Rock Climb (slot 5): 500,000 GP + items; -10% preserve, +5% double items in Fishing/Woodcutting/Mining/Thieving.
  - Tree Climb (slot 5): +3% Mastery XP all skills, +4% skill XP all skills, -10% preserve.
  - Heat Trap (slot 7): 2,500,000 GP; -10% Auto Eat efficiency, -10% damage to monsters.
  - Rules: a bonus applies only if all earlier slots are built; each time an obstacle is built its item cost drops 4% (up to 10 times, 40%); item cost reduction max 95% (100% with an upgrade); GP/Slayer Coin cost reduction max 60%; destroying refunds nothing; up to 5 blueprints per realm.
  - Every obstacle has skill-level requirements; Mastery checkpoints cut build costs (-10% at 50% pool, -15% item cost at 95%).

---

## 8. Astrology and Summoning as passive modifiers

- **Astrology** (https://wiki.melvoridle.com/w/Astrology): studying a constellation costs nothing, base 3 s; 5% Stardust and 2% Golden Stardust per action. Each constellation has 6 stars of passive modifiers; first upgrade costs 10 Stardust (or 50 Golden), cost doubles each upgrade; normal modifiers max level 8 (2,550 Stardust to max), unique max level 5. Example: Deedree +8% Woodcutting skill XP, +8% Farming skill XP.
- **Summoning** (https://wiki.melvoridle.com/w/Summoning): familiars as tablets and synergies. Ent +10% chance of +1 resource in Woodcutting; Owl -5% Astrology interval; Eagle + Owl -10% Astrology interval; Salamander +20% chance of +1 base logs or smithed items. Pool checkpoints cut shard costs.

---

## 9. How the UI shows rates

Sources: https://wiki.melvoridle.com/w/Beginners_Guide, https://wiki.melvoridle.com/w/Settings
- Each action tile shows XP per action, the item's Mastery level and progress to the next Mastery level; an XP bar fills across the top during the action.
- The wiki tables list XP/s and price/s per action.
- Skilling Minibar (right side of skill pages, setting default Enabled): Pets, Quick Equip, Summoning Synergy list, Milestones (level unlocks), Item Mastery Unlocks, minimise arrow. A Combat Minibar shows equipment sets and enemy HP.
- Offline summary popup on return (section 6).
- I could not confirm from a page that the live UI prints XP/hr, items/hr or time-to-level.

---

## What transfers to an HQ trading-company game

1. Hourly town tick (Township): one 1-hour update that pays tax, makes resources and applies decay maps to "gold per hour" estates and hourly dividends.
2. Tax = population x rate, with the rate raised by counted buildings (Town Hall +10% each, max 80%): an HQ tax-office tier can scale the same way.
3. Decay plus repair (25% chance per tick of -1% efficiency; repair = BaseCost/3 x count x lost efficiency): a ready upkeep model, with "build another to repair" as a free alternative.
4. Hard storage caps with tiered storehouses (50,000 base; +5,000, +25,000, +300,000): a warehouse model.
5. Per-item Mastery (formula and double/preserve unlocks): captain experience on a named good unlocks cheaper or faster runs of that good.
6. Mastery Pool checkpoints at 10/25/50/95% that switch off when spent: a keep-or-spend choice for company reputation.
7. Additive reductions on the base value with hard floors and caps (0.25 s minimum, 80% preserve, 80% building-cost cap): level-based cost cuts that cannot reach zero.
8. Agility-style slot course with bonuses and penalties, 4% cheaper per rebuild, level-gated: a "skills reduce costs" ladder with trade-offs.
9. Bank-slot price curve (34 GP rising to a 5,000,000 cap at 118 buys) and the 24-hour offline cap with a return summary: templates for warehouse slots and an away report.
10. Seasons of +/- modifiers on production and repair (72 h): a recurring, readable market or weather layer.

---

## Not verified

- No developer posts, patch-note pages or official dev blog were read; everything is from the community-edited wiki, which says itself it can be out of date. Only wiki.melvoridle.com pages (v1.3.1) were used.
- Township: the resource type of each building cost number was lost in my text capture, so whether the first number is GP is not confirmed. Whether construction cost rises with the number already built was not found (one cost per building is listed; only the repair formula uses buildings built). The Building Cost Reduction Boosts page was empty in my read. Trading Post max count (50 per biome entry vs 150 total) is as printed.
- Hardcore bank-slot limit: Shop page says 88, Bank page says 108.
- Mastery Pool checkpoints for Fishing, Cooking, Firemaking, Fletching, Herblore, Runecrafting and others were not read; only the 8 skills in the table.
- Live UI readouts of XP/hr, items/hr or time-to-level: not confirmed.
- Any designed inflation brake: no source statement found.
- Dungeon entry requirements: the Dungeons page text was empty in my capture.
- First-10-minute and first-hour pacing: inferred only from level-1 requirements in tables and Beginners Guide advice; no timed benchmark found.
- Agility: only the obstacles quoted were read in detail; other obstacles' exact bonuses and costs not checked.
