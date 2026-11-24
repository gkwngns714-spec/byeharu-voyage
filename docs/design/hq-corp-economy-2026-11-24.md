# HQ corp economy: the numbers (2026-11-24)

The owner, 2026-11-24: *"it is like tribal wars + madevor + eve + rs3 game. research thoroughly, income, maintanence, levels, and
more will be made."* ("madevor" is Melvor Idle.) The same day: the HQ company, hourly dividends, everything as +/- coin an hour,
levels gate land and sea and open fleets, crew slots (bought at a total level, section 4a) and ships, skills cut maintenance, Rank cuts tax.

This file turns the research (`docs/research/games-2026-11-24/`) and **our own measured numbers** into the tables the builders of
0492-0500 implement. The model and the slices are `docs/design/hq-corp-2026-11-24.md`; its section D now points here.

**Every number below is OWNER'S: default, reversible.** No existing knob or switch is changed by this document. All new play stays
behind the dark switches of the slice plan (`upkeep_enabled`, `rank_cuts_enabled`, `level_opens_more_enabled`,
`dividend_hourly_enabled`, `party_captains_enabled`, `estates_enabled`, `area_tiers_enabled`). A figure from a research file that
the file itself lists under "Not verified" is marked **(unverified source)**.

Short names for the research files, with line numbers: **TW** `tribal-wars.md`, **MI** `melvor-idle.md`, **EVE** `eve-online.md`,
**RS3** `runescape-3.md`.

---

## 0. The denominators (measured)

**How.** The local chain world at prod head 0491 (PGlite, the prefix cache, `applyChainCached`). Inside a rolled-back transaction
I set the knobs that are lit on prod to their prod values (`city_treasury_enabled`, `city_reserve_enabled`, `first_hour_enabled`,
`near_choice_enabled`, `fleet_jobs_enabled`, `hq_board_enabled`, `land_enabled`, `level_unlocks_enabled`, `yard_order_enabled`).
`economy_closed` stayed off locally: a local capital holds no coin to pay a founding (`E_NO_NEW_GOLD`), so local city purses do not
bind a sale as prod's do. Then I founded fresh companies (40,000 coin, one Barca) and asked the server's own reads:
`world.best_sales`, `world.good_board`, `world.land('mining')`, `world.hull_quote`, `world.tax_rate`. Prod: two read-only
statements (the gate, then one SELECT from a file).

**"Per hour" of a sea run** = the server's net profit of the trip (sale less buy, profit tax, dock fee, wages, stores) x 3600 /
(the trip's seconds + 300). The 300 s is the game's own "an hour of play" turn (`near_choice_turn_seconds`, 0475). It is one way:
a fleet job that sails back empty earns less, one that finds a paying card at the far end earns about the same.

| Denominator | Value | Source |
|---|---|---|
| Starting coin | **40,000** (prod and local) | prod `starting_ducats` |
| Prod companies (19 humans) | richest **235,000**; median **40,000**; poorest 8,976; all 19 together **1.23 M**. 18 of 19 had no ledger row in the last 24 h; the one active company (Trading 16) netted **-709,697** in 24 h (shares 461,384, ransom 199,118, dock fees 38,914) | prod read, 2026-11-24 06:05 UTC |
| Prod world stock | cities **24.39 B** (254 purses, median **2.11 M**); merchants **9.64 B** (1,441) | prod read |
| **R: a Barca's near run, Lisbon** | best card **36,200 /h** (black pepper to Setubal, 46 nm, +3,681 a run in 66 s); median paying card **9,500 /h** | `world.best_sales`, LIS |
| Near run, six other homes | best card / median card per hour: Amsterdam 36,700 / 14,500; London 26,900 / 8,400; Venice 27,600 / 10,300; Genoa 33,700 / 10,800; Nagasaki 18,200 / 5,600; Havana 15,100 / 8,700 | same, the fleet moved there |
| A near run repeated | 10 Lisbon-Setubal runs back to back (no recovery between them): each run's profit falls about 6 %; the ten average 96 % of the first | executed buys and sells |
| Full hold vs a 40,000 purse | Lisbon-Setubal pepper, 300 units: **+6,456** net a run (the purse-bound card: +3,681) | `world.good_board` |
| **A Barca's far run** | best far card per hour: Lisbon 8,800 (quicksilver to Hagatna, 12,985 nm, +45,272 in 5.1 h); 6,700-8,900 over the seven homes | `world.best_sales` `far` |
| Profit tax today | **15 %** of a sale's profit at every harbour (each port's column 0.03 x `profit_tax_scale` 5, under `tax_rate_max` 0.20), then the citizen cut where Influence is on | `world.tax_rate` over all harbours |
| Dock fee today | 250 base + 0.5 % of the cargo + 250 a ship: **1,012** on a 47,170 sale at Setubal | `world.good_board` |
| Where a near run's margin goes | gross margin 8,608 = net 6,456 (75 %) + tax 1,141 (13 %) + dock 1,012 (12 %) + wages 8 | the same quote |
| Wages at sea | 1 a crew a voyage-day (`wage_per_crew_day` 5 x `running_cost_level` 0.2); a voyage-day is 450 s, so **8 a crew an hour at sea**. Measured: 480 for a 53.9-day Barca voyage (about 71 an hour). Charged at the sale, never on a loss | quote |
| Stores at sea | about 0.6 a crew a voyage-day (food 0.015 t x 25, water 0.02 t x 10): **about 5 a crew an hour at sea** | knobs; quote "44 for 7 days" |
| Hull list prices | Barca at a yard **52,000** (+34,293 the order's fee, 30 minutes; `world.hull_quote`). Class `build_cost` medians: tier 1 **66,000** (40,000-176,000, crew 9, hold 114 t); tier 2 **160,000** (crew 24); tier 3 **714,000** (crew 69); tier 4 **1.21 M** (crew 115); tier 5 **2.68 M** (crew 220) | `ship_classes`, 157 classes |
| Captains | signing fee (OFFICER_WAGE, once) 2,750-8,000, median **4,700**; 105 officers. Crew: 100 a head to hire | `officers`, `hire_crew_rate` |
| Invest | **1.8 % of what was paid, per real day** (`works_coupon_day` **0.018** on prod; the plan's "0.09" was wrong), x the holder's Influence multiplier (the city's top investor 1.5). So **0.075 % an hour**: 100,000 invested pays 75 an hour, 1,800 a day; it pays back in about 55 days | `public.coupon_day_of` |
| Land party, 6 packs, median price | Mining 1 iron at home (Lisbon): 3,900 s a trip, **410 /h**. Mining 15 tin (British Isles): 1,100 /h. Mining 50 quicksilver at Lisbon: **8,000 /h**. Mining 60 gold: 2,000 /h. Mining 65 Baltic amber: 9,100 /h. Most jobs from 25 to 96: 700-3,600 /h | `world.land('mining')`, median ask over 254 harbours |

**Skill pace** (from the rules and the measured runs):

| Level | Rule | Pace used | Time to reach (cumulative), and the last step |
|---|---|---|---|
| **Trading** (1-20) | 1 point per 500 coin bought or sold; level = floor(sqrt(points/25)) + 1 | a purse-bound near run turns over about 44,000 (88 points); about 6 runs an hour = **~500 points /h** (a full-hold run: 173 points) | L2 3 min, L5 48 min, L10 4.1 h, L15 9.8 h, L20 18 h. One step costs 25 x (2L - 1) points: L4-5 21 min, L9-10 51 min, L19-20 1.9 h |
| **Exploration** (1-20) | 25 a new harbour, 1 per 100 nm | near runs ~10 /h; a far voyage Lisbon-Hagatna (12 stops, 13,000 nm) ~445 points in 6.7 h = **~66 /h** | L3 (100) = 4 new harbours; L5 (400) ~16 harbours; L7 (900) ~12 h of far sailing; L11 (2,500) ~38 h |
| **Rank** = the Title = the lower of Trading and Exploration (1-11) | `public.title_level` | Exploration sets the pace | Rank 2 ~15 min, Rank 3 ~1 h, Rank 5 ~4-6 h, Rank 7 ~1 day, Rank 9 ~3 days, Rank 11 ~1-2 weeks of play |
| **Mining** (1-100, `long` curve) | xp per action | xp an hour rises with the job: iron 300, tin 360, sulphur 480, marble 720, quicksilver 960, gold 1,200, jade 1,900, diamonds 2,400 | L10 27 min; L10-20 +1 h; L20-30 +2 h; L30-40 +4 h; L40-50 +9 h; L50-60 +18 h; L60-70 +37 h; L70-80 +79 h; L80-90 +155 h; L90-99 +273 h (marches add ~10 %) |
| **Granted levels** (Shipbuilding, Supplies, ...) | at most 300 xp a day | | L20 (9,025 xp) is at least 31 days |

So: Trading opens things in minutes, then about an hour a level (the 0468 ladder); Rank is the slow ladder (days); Mining is the
RS3 ladder (minutes early, hundreds of hours at the top). That is the shape the owner asked for (MI line 12, RS3 line 166 and 294).

---

## 1. Income per hour, by stage

**Rule.** A stage is a Trading level with the Rank, Mining, fleets and estates a player typically holds there. The L1 column is
measured; L5 to L20 are **targets** scaled from it (by hold and by the full-hold run measured above, less ~6 % a repeated run for
glut); they are the yardstick each later slice measures against, not measurements.

| Line, per hour | L1 (measured) | L5 | L10 | L15 | L20 |
|---|---|---|---|---|---|
| Profile | Rank 1, 1 Barca, Mining 1 | Rank 3, 2 tier-1 fleets, Mining 15, 1 estate T1 | Rank 5, 3 tier-2 fleets, Mining 30, 2 estates T2 | Rank 7, 4 tier-3 fleets, Mining 50, 3 estates T3 | Rank 9-11, 6 tier-4/5 fleets, Mining 60-70, 3 estates T4-T5 |
| Sea trade, near (each fleet) | **9,500** median card (best 36,200) | 15,000 | 25,000 | 50,000 | 80,000 |
| Sea trade, far (each fleet) | **8,800** best far (6,700-8,900) | 9,000 | 15,000 | 30,000 | 50,000 |
| Land party | **410** (iron) | 1,100 (tin) | 850 (alum) | 8,000 (Lisbon quicksilver) or 1,500 elsewhere | 2,000 (gold) |
| Estates (section 8) | 0 | 410 | 1,500 | 4,000-26,000 (the land guard bounds it) | 10,000-40,000 |
| Dividends (section 9) | 0 | 40 (50,000 invested) | 375 (500,000) | 1,500 (2 M) | 7,500 (10 M) |
| **Target net, all lines** | **~10,000** | **~30,000** | **~75,000** | **~200,000** | **~450,000** |
| Next unlock | minutes (Trading 2: 3 min; fleet room at Trading 3: 12 min; Rank 2: ~15 min) | ~30-50 min a step | ~1-2 h a step | ~2-4 h a step | Rank 11: days |

**Target hours per level** (Melvor/RS3 pacing, MI line 12, RS3 lines 294-297): Trading about 0.05 h at L2 rising to ~2 h at L20;
Rank about 0.25 h for Rank 2, ~1 day by Rank 7, ~1-2 weeks for Rank 11; Mining minutes below 10, ~1 h at 20, ~18 h at 60, ~270 h at
99. The levels already in the chain give this; nothing here changes a curve.

**Reference.** Melvor's XP-per-action and hourly town tick (MI lines 29, 136); RS3's port voyage times growing 20 to 640 minutes by
region (RS3 lines 56-63, 297); TW: cost grows ~1.25-1.3 a level, output ~1.16 (TW lines 33, 47-64, 205; the 1.163 is the author's
fit, **(unverified source)**).

---

## 2. Maintenance

**Rule.** A mix (EVE line 57 fuel per hour; MI line 141-143 decay + repair):
- **Ships: a flat hourly upkeep**, a share of the hull's list price (`world.hull_quote`'s price; the class `build_cost` where no yard
  quotes it), **0.25 % an hour while working** (an assignment, or at sea), **0.10 % an hour laid up** (in port, no assignment).
  Paid to the home city (`pay_city`, kind `UPKEEP`) by the hourly step of `tick_city`.
- **Estates: decay + repair**, no flat upkeep. Each hourly tick an estate has a 25 % chance to lose 1 % efficiency, never below 20 %.
  Output x efficiency. Repair to 100 % costs `build_cost / 3 x (lost efficiency)`, paid to the home city (Melvor's Township formula
  with one building, MI line 143).

| Hull tier (median list price) | Working /h | Laid up /h | Wages at sea /h (median crew) | Stores at sea /h | All running /h, working |
|---|---|---|---|---|---|
| Barca (52,000) | **130** | 52 | 64-71 | ~40 | ~240 |
| Tier 1 (66,000, crew 9) | 165 | 66 | 72 | 41 | 278 |
| Tier 2 (160,000, crew 24) | 400 | 160 | 192 | 110 | 702 |
| Tier 3 (714,000, crew 69) | 1,785 | 714 | 552 | 317 | 2,654 |
| Tier 4 (1.21 M, crew 115) | 3,025 | 1,210 | 920 | 529 | 4,474 |
| Tier 5 (2.68 M, crew 220) | 6,695 | 2,678 | 1,760 | 1,012 | 9,467 |

| Estate tier (build cost, section 8) | Expected repair /h at 100 % kept (0.25 % lost a tick) | Crew wages ashore /h | All /h | Share of a T-tier iron estate's output |
|---|---|---|---|---|
| T1 (20,000) | 17 | 32 (4 crew) | 49 | 12 % of 410 |
| T2 (54,000) | 45 | 64 | 109 | 15 % of 740 |
| T3 (146,000) | 122 | 96 | 218 | 16 % of 1,350 |
| T4 (394,000) | 328 | 128 | 456 | 19 % of 2,420 |
| T5 (1.06 M) | 886 | 160 | 1,046 | 24 % of 4,350 |

(Iron is the poorest paying job; on quicksilver or gold the same costs are 1-3 % of the output.)

**The hard rule: a starter company's running costs never exceed X = 5 % of its realistic income.** Running costs = upkeep + wages
+ stores (tax and the dock fee are shares of a sale, not running costs). The arithmetic, one Barca working:
- upkeep 130 + wages 71 + stores 40 = **241 an hour**;
- against Lisbon's median card 9,500 /h: **2.5 %**; against the worst measured home's median (Nagasaki, 5,567 /h): **4.3 %**; against
  Lisbon's best far run (8,800 /h): 2.7 %. All under 5 %.
- The new line alone (upkeep 130) is 1.4 % at Lisbon, 2.3 % at Nagasaki.
- 0496's proof asserts it on the local world: the Barca's upkeep + wages + stores an hour <= 5 % of the median paying card per hour
  at Lisbon and at Nagasaki. A change to the rates that breaks it fails the proof.

**When a company cannot pay (never a death spiral).**
- Upkeep never takes the purse below a **floor of 10,000** (a quarter of the starting coin). The part it cannot take is **waived,
  not owed**: no debt, no seized hull, no lock on assignments. The Ledger shows it as a grey "Unpaid" line.
- An estate is never shut by decay: at the 20 % floor it still produces a fifth.
- The Rank 1 home tier (section 5) is always open, so a company at the floor always has paying work.

**Reference.** EVE: fuel per hour, services offline at zero fuel (EVE lines 57, 60): we take the hourly rate, not the shut-down
(a shut-down is the death spiral). TW: the farm's population cap is TW's only recurring "upkeep" (TW line 109). Melvor: decay 25 % a
tick, -1 %, floor 20 %, repair `BaseCost/3 x count x lost` (MI lines 141, 143). RS3: dry dock instead of payment when a repair
cannot be paid (RS3 line 78), the same "no debt" idea.

---

## 3. Tax

**Rule.** Tax stays what it is today: **the profit of a sale** (15 % at every harbour, measured) **and the dock fee**. No new
tax: dividends, land and estate output, and upkeep are not taxed (a dividend is already paid from a city's profit; taxing it would
only send city coin back to the city). Estate and land goods pay the profit tax when they are sold, on their basis. Rank cuts both,
EVE-style: a fixed share of the base per step, to a floor. All of it goes to the city of the sale (closed economy; the 10 % on to the
capital, `CROWN_TAX`, unchanged).

| Rank | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Profit tax, share of base (-5 % a step, `tax_rank`) | 100 % | 95 % | 90 % | 85 % | 80 % | 75 % | 70 % | 65 % | 60 % | 55 % | **50 %** |
| On today's 15 % | 15.0 % | 14.25 % | 13.5 % | 12.75 % | 12.0 % | 11.25 % | 10.5 % | 9.75 % | 9.0 % | 8.25 % | 7.5 % |
| Dock fee, share of base (-3 % a step, `dock_rank`) | 100 % | 97 % | 94 % | 91 % | 88 % | 85 % | 82 % | 79 % | 76 % | 73 % | **70 %** |

- **Floors.** All cuts together (Rank, the citizen cut, the logbook's fee cuts, the race's home cut) never take the profit tax under
  **50 %** of its base, nor the dock fee under **50 %**. `public.rank_factor` applies the floor after multiplying.
- **Size.** On the measured Setubal run tax + dock are 25 % of the gross margin. At Rank 11 they are about 15 %: Rank 11 is worth
  about +13 % net on every sale. At L1 (Rank 1) nothing changes.
- **Reference.** EVE Accounting: `7.5 % x (1 - 0.11 x level)`, floor about 45 % of base at level 5 (EVE line 15); standing as a second
  discount on the broker's fee (EVE line 17). RS3's Grand Exchange: 2 % of the sale withheld from the seller (RS3 line 269). Melvor's
  tax rises with Town Halls (MI line 145), not used: our tax is the city's, not the player's.

---

## 4. Levels and unlocks

**Rule.** One table, `public.level_perks`, one reader, `public.level_perk`. Nothing 0417 or 0468 gives is renumbered; the rows below
are ADDED. "Rank" is a `level_skills` row `rank` read from `public.title_level` (hq-corp B5).

| Level | Opens (existing rows in plain text, **new rows in bold**) |
|---|---|
| Start | 1 fleet, 1 Barca, **1 crew slot** (more are bought: section 4a), **1 party**, **0 estates**, **sea and land tier 1**, home shed = the city's warehouse tier x 150 t |
| Trading 2 / 7 / 11 / 15 / 19 | +1 route (0468 `trade_routes`; an assignment slot once 0493 folds routes in) |
| Trading 3 / 6 | +1 fleet (`fleet_room_levels`); more fleets are bought (0354), up to `fleet_hard_max` 6 |
| Trading 4 / 9 / 13 / 17 | +1 ship in each fleet (0468 `fleet_ships`) |
| Trading 5, 8, 10, 12, 14, 16, 18, 20 | yard order fee -10 % each (0468 `yard_fee`) |
| **Rank 2** | **+1 estate slot**; **+150 t home shed** |
| **Rank 3** | **sea and land tier 2**; **estate tier 2** |
| **Rank 4** | **+150 t home shed** |
| **Rank 5** | **sea and land tier 3**; **+1 estate slot** (2); **estate tier 3** |
| **Rank 6** | **+150 t home shed** |
| **Rank 7** | **sea and land tier 4**; **estate tier 4** |
| **Rank 8** | **+1 estate slot** (3); **+150 t home shed** |
| **Rank 9** | **sea and land tier 5**; **estate tier 5** |
| **Rank 10** | **+150 t home shed** (+750 t in all) |
| Rank 2-11 | **profit tax -5 %, dock fee -3 % a step** (section 3) |
| **Mining 20 / 50** | **+1 party** (2, then 3) |
| **Mining 10, 20, ... 100** | **estate repair -5 % each** (section 6) |
| **Shipbuilding 2-20** | **hull upkeep -2.5 % each level** (section 6) |
| Supplies / Weather / Shipbuilding / Craft / Requests / Routes / Investment / Evasion | the 0417 and 0453 perks, unchanged |
| Academy skills | which hull classes the yard builds for her (unchanged: they already open hulls, docs/LEVELS.md section 1) |

New `level_perks` rows: `party_slots` (mining, count), `estate_slots` (rank, count), `estate_tier`
(rank, count), `area_tier` (rank, count), `shed_room` (rank, count of 150 t), `tax_rank` and `dock_rank` (rank, pct_less), `upkeep`
(shipbuilding, pct_less), `estate_repair` (mining, pct_less). Each new cap is first raised to the most any company holds on prod at
deploy (no one loses a captain or a party).

**Reference.** EVE: capacity is a skill, +1 slot a level (Mass Production, Laboratory Operation, Trade +4 orders a level; EVE lines
46, 97). RS3 ports: caps of 5 captains, 25 crew, 5 crew a ship (RS3 lines 17-19); we cap captains at 6 because a company holds at
most 6 fleets. TW: the warehouse grows each level (TW lines 80-93).

---

## 4a. Crew slots: bought at a total level, with gold and Reputation

The owner, 2026-11-24: *"crew slot will be open when total level hits, with gold, reputation rquirement"*. This **replaces** the
captain-slot rows that stood on Rank (hq-corp A2.6).

**The rule.** The next slot opens when three things are met, and the player then buys it with one press.
- **Total level:** `public.total_level(player)`, the sum of the company's levels: the eleven sea levels plus every lit land skill. It
  is 12 at founding.
- **Gold:** paid to the home city (`pay_city`, kind `CREW_SLOT`).
- **Reputation:** spent through `public.reputation_credit`, as captain skills spend it (0355).

The data is one table, `public.crew_slot_steps`. The switch is `crew_slots_enabled` (0497).

**The ladder.** Every row is OWNER'S: default, reversible.

| Slot | Total level | Gold | Reputation (spent) | Reached by a steady player | Gold against income at that stage (section 1) |
|---|---|---|---|---|---|
| 1 | start | 0 | 0 | founding | |
| 2 | 16 | 5,000 | 50 | ~10-20 min | ~0.5 h of ~10,000 /h |
| 3 | 30 | 20,000 | 250 | ~1-1.5 h | ~1 h |
| 4 | 45 | 60,000 | 600 | ~4-6 h | ~2 h of ~30,000 /h |
| 5 | 65 | 150,000 | 1,200 | ~1 day | ~2 h of ~75,000 /h |
| 6 | 90 | 400,000 | 2,500 | ~3 days | ~2 h of ~200,000 /h |
| 7 | 120 | 1,000,000 | 5,000 | ~1 week | ~2 h of ~450,000 /h |
| 8 | 160 | 2,500,000 | 10,000 | ~2-3 weeks | ~5 h |

**Where the timings come from:**
- **Total level:** section 0's paces. Trading L3 in ~6 min, L5 in 48 min, L10 in 4 h. Mining L10 in 27 min, L30 in ~3.5 h, L50 in
  ~17 h. Exploration +1 every few new harbours early. Granted levels are at most 300 xp a day.
- **Reputation:** from the 0352 rules. A sale gives profit / 250 (at most 120), so a near run gives ~15 and trade gives ~90 /h. Each
  level crossed gives 10 x the level. A new harbour gives 25. The capped kinds stop at `rep_day_cap` 600 a real day. That makes about
  250-400 in the first hour, and at most ~600 a day after, plus the level rewards.
- **Reputation is a sink with two uses:** captain skills and slots. Choosing between them is a real choice.

**The other rules:**
- **One cap:** the bought count caps how many workers (fleets with work, parties, estates) run at once.
  - Fleet room's fleet purchase (`cmd.buy_room('fleet')`, 0354, kind `SLOT`, destroyed) folds into it. The new price is moved to a city,
    not destroyed.
  - `fleet_hard_max` 6, ships-per-fleet room, `party_slots` and `estate_slots` stay as bounds per kind.
- **No one loses a worker:** at deploy each company's count starts at no less than the workers it holds, and no less than the most any
  company holds.

## 5. Area tiers, sea and land

**Rule: plain Rank** (the owner's words: "levels ... needed to access higher ranked areas"). RS3's cumulative distance (RS3 lines
50-65) and EVE's standing 1/3/5/7 (EVE lines 116-126) were weighed; Rank already contains distance (Exploration counts new harbours
and miles), so a second distance ladder would be a second authority. EVE's 1/3/5/7 spacing is kept: tiers open at **Rank 1, 3, 5,
7, 9**.

**The bands, in stored sailed miles from the home harbour** (`sea_reach_matrix`, the table 0491 made equal to the sail), so a tier is
a property of the map, not of the ship. The hours are a Barca's (15 kn x 192 = 2,880 nm a real hour).

| Tier | Sailed miles from home | Barca hours | Rank |
|---|---|---|---|
| 1 | up to 1,440 | under 0.5 h | 1 |
| 2 | 1,440-2,880 | 0.5-1 h | 3 |
| 3 | 2,880-5,760 | 1-2 h | 5 |
| 4 | 5,760-11,520 | 2-4 h | 7 |
| 5 | beyond 11,520 | 4 h+ (the farthest harbour from Lisbon is about 5 h) | 9 |

The placeholder bands (2, 6, 12, 24 hours) were wrong for this map: every harbour is within about 6 Barca hours of any home, so
tiers 4 and 5 would have been empty and tier 1 would have held over half the world.

**Harbours in each tier** (measured, `voyage.reach_from`):

| Home | T1 | T2 | T3 | T4 | T5 |
|---|---|---|---|---|---|
| Lisbon | **59** | 44 | 32 | 71 | 47 |
| Amsterdam | 44 | 41 | 47 | 52 | 69 |
| London | 46 | 40 | 47 | 54 | 66 |
| Venice | 33 | 32 | 62 | 43 | 83 |
| Genoa | 44 | 41 | 48 | 58 | 62 |
| Nagasaki | 29 | 19 | 36 | 48 | 121 |
| Havana | 14 | 6 | 101 | 52 | 80 |

**Paying work at Rank 1** (a fresh company, 40,000 coin, one Barca; every card below sails under 0.5 h, so its sale harbour is tier 1):
- **Lisbon:** 59 harbours open; 9 of its 10 paying cards are tier 1 (sold at Setubal, Porto, Sanlucar); best 36,200 /h. Land: 7
  regions in tier 1 (Iberia, Maghreb, West Iberia coast, British Isles, Baltic, West Africa, Scandinavia); at Mining 1 iron (home) and
  coal (British Isles) pay.
- **Amsterdam:** 44 harbours; 10 of 10 cards tier 1 (Hoorn, Rotterdam, Middelburg); best 36,700 /h.
- **Nagasaki:** 29 harbours; 9 of 10 cards tier 1 (6 harbours); best 18,200 /h.
- **Havana** (the thinnest tier 1): 14 harbours; 10 of 10 cards tier 1 (5 harbours); best 15,100 /h.

**Rank is reachable from the tiers it opens.** Exploration gives 25 a new harbour: Rank 3 needs 100 points (4 harbours, all homes
have 14+ in tier 1); Rank 5 needs 400 (16; tiers 1-2 hold 20 at Havana, 48 at Nagasaki); Rank 7 needs 900 (36; tiers 1-3 hold 84+);
Rank 9 needs 1,600 (64; tiers 1-4 hold 132+). Before 0500 is lit its proof repeats this count for every capital.

**Land** uses the same bands on the party's passage (the `nm` that `world.land` already serves). From Lisbon: tier 1 = 7 regions
(28 jobs), tier 2 = Adriatic, Aegean; tier 3 = Caribbean, South America, East Africa; tier 4 = 6 regions; tier 5 = China, Japan, Korea.
A job still needs its Mining level (`land_actions.level`).

---

## 6. Skills that cut costs

**Rule.** Melvor's: each step is a share of the BASE, the steps add, and there is a hard floor (MI lines 31, 65, 232). Each cut
multiplies one figure in the one function that owns it.

| Skill | Cuts | Per level | At the top | Floor | Owner of the figure |
|---|---|---|---|---|---|
| Shipbuilding (1-20) | hull upkeep | -2.5 % at each level 2-20 | -47.5 % at 20 | 50 % of base | `public.upkeep_due` (new) |
| Shipbuilding | ship repairs | -2 % at 4, 8, 12, 16, 20 (0417, unchanged) | -10 % | | `public.fleet_repair_cost` |
| Supplies | stores | -1 % at 4, 8, 12, 16, 20 (0417, unchanged) | -5 % | | `public.stores_cost` |
| Mining (1-100) | estate repair | -5 % at 10, 20, ... 100 | -50 % at 100 | 50 % of base | estate repair (0499) |
| Trading | yard order fee | -10 % at eight levels (0468, unchanged) | -80 % | | `public.hull_order_price` |
| Rank | profit tax / dock fee | -5 % / -3 % a step (section 3) | -50 % / -30 % | 50 % / 50 % | `public.rank_factor` |

- **Size.** Shipbuilding 20 on a tier-4 fleet of 6 hulls saves 6 x 3,025 x 47.5 % = **8,600 an hour**, about 2 % of an L20
  company's income: visible as "Saved" on the Ledger, never free.
- **Trade-offs (Agility-style, MI lines 193-201):** none added now. The one built-in trade-off is the laid-up rate: a hull with no
  work costs 40 % of a working one, so "sell the idle hull or give it work" is the decision.
- **Reference.** EVE Accounting -11 % of base a level (EVE line 15); RS3's repair discount of 0.5 % per Smithing level (RS3 line 271;
  its cap **(unverified source)**), which is our Mining estate repair at 0.5 % a level in 10-level steps.

---

## 7. Workers

**Rule.** We keep **our existing captain skills** (grades C/B/A/S, traits, Reputation-bought skills, `crew_pct`), not RS3's
"lowest of three stats" (RS3 line 74). One authority: a captain's effect is what it already is at sea, and it applies to a party or an
estate through the same `crew_pct` (hq-corp B1).

| Item | Value | Note |
|---|---|---|
| Captain, signing fee | 2,750-8,000, median 4,700, once (OFFICER_WAGE, existing) | to the city of the Inn |
| **Captain, wage** | **1 % of her signing fee an hour** while hired: median **47 /h**, at most 80 /h | new, hourly, to the home city; 0.5 % of R at L1; 6 captains ~300 /h |
| Crew, hire | 100 a head (`hire_crew_rate`, existing) | |
| Crew, wage at sea | 1 a crew a voyage-day = 8 an hour at sea, charged at the sale (existing) | |
| **Crew, wage ashore** | **the same 8 a crew an hour**, charged hourly (D11) | party and estate crew |
| Crew needed: sea | the hull's `crew_required` (Barca 8) | existing |
| **Crew needed: land party** | **a captain + 4 crew** | new (0498) |
| **Crew needed: estate** | **4 / 8 / 12 / 16 / 20** seats by tier, plus its captain | new (0499); an estate with fewer crew than seats produces seats-filled / seats of its output |
| A captain's level | +2 % to her stats a level (`captain_level_pct_per_level`, existing); on land her grade's `crew_pct` speeds the job | existing rules, read once |

**Reference.** RS3 ports: captains 0-10 levels, +10 % of base stat a level, daily salary 20/50/150 chimes (RS3 lines 28, 89-91);
EVE: one slot a level (EVE line 46).

---

## 8. Estates

**Rule.** An estate runs ONE land job of the home region forever, with no march (hq-corp B2). Its tier sets how many "lines" run at
once: output per hour = `3600 / the job's action seconds x lines x efficiency` units, at the land rules (the market guard 0457, the
day's cap). Each tier step costs ~2.7x and gives ~1.8x (TW's ~1.28x cost and ~1.16x output a level, about four levels a tier, TW lines
33, 47-64). Build time doubles a tier (TW's build factor 1.2 a level, TW line 68).

| Tier | Build cost | Build time | Lines | Crew seats | Rank | Iron at home /h | Quicksilver at Lisbon /h (Mining 50) | Storage it needs |
|---|---|---|---|---|---|---|---|---|
| T1 | 20,000 | 30 min | 1.0 | 4 | 1 | 410 | 8,060 | home shed |
| T2 | 54,000 | 1 h | 1.8 | 8 | 3 | 740 | 14,500 | |
| T3 | 146,000 | 2 h | 3.3 | 12 | 5 | 1,350 | 26,600 | |
| T4 | 394,000 | 4 h | 5.9 | 16 | 7 | 2,420 | 47,600 | |
| T5 | 1,063,000 | 8 h | 10.6 | 20 | 9 | 4,350 | 85,400 | |

- **Upgrade** = pay the difference to the next tier's cost; the estate keeps producing while it builds.
- **What it consumes:** a gather job (mine, later farm) consumes nothing but wages and repair; a make job (smithing) takes its inputs
  from the home Warehouse (the land rules).
- **Storage cap:** the home shed, `storage_cap` (city warehouse tier x 150 t) + the Rank `shed_room` rows (+150 t at Rank 2, 4, 6, 8,
  10). A full shed stops the estate, as a party's haul waits (TW: overflow is lost, TW line 96; we stop instead, nothing is lost).
- **Gold.** A gold or gold-dust estate's output is a GOOD in the Warehouse. Sold, it is paid by a city purse (`city_pays`): no new
  coin, `mint_guard` holds (hq-corp D7). The land guard and the day's cap bound how much of it a city will take.
- **Payback**, iron T1: 20,000 / (410 - 49) = 55 hours. Quicksilver T1 at Lisbon: under 3 hours, but the land guard (a job-hour at most
  1/100 of a middling target stock, the day's cap 0.35 of target) stops it long before 85,400 /h: the builder of 0499 measures the
  guard's real ceiling on the local world and prints it.

**Reference.** Melvor Township: hourly update, production x efficiency, storage caps (MI lines 136-147). RS3 Anachronia: 60 a worker
an hour, storage 5,000 to 150,000 by tier (RS3 lines 227-236). EVE PI: timed extraction, taxed on export (EVE lines 79-85).

---

## 9. Dividends, hourly

**Rule.** At every hourly `tick_city` (the cron already runs at :37 each hour), each holder is paid **1/24 of her day's coupon**
(`public.coupon_day_of` / 24 = **0.075 % of what she paid, an hour**, x her Influence multiplier, up to 1.5 for the city's top
investor), straight to her purse by `city_pays`.

| Item | Value |
|---|---|
| Rate | 0.075 % of paid an hour (1.8 % a day); top investor 0.1125 % an hour |
| Source of the coin | the city's purse (closed economy: coin moves city to company, nothing minted) |
| Cap 1 | the city's surplus above its reserve (as 0312) |
| **Cap 2** | **the city's profit over the trailing 24 hours / 24**, shared pro rata among its holders |
| An hour with no city profit | pays from the trailing 24 h figure if it is above nought; if the city lost money over the last 24 hours, it pays **0**, and nothing is carried |
| Old `accrued` balances | collected at arrival as today (not swept) |
| Size | L1 0; L10 375 /h on 500,000; L20 7,500 /h on 10 M: about 1-2 % of income at every stage. A slow, safe line, not a main income |

**Departure from D6:** D6 limited each hour by that hour's profit. 0312 itself warned that alternating hours over-pay and under-pay;
an hour-by-hour limit makes a choppy city pay much less than its day. The trailing 24-hour limit keeps the day's ceiling and the
city's protection and pays every hour.

**Reference.** RS3 Miscellania: the daily withdrawal is 10 % of the coffer, capped (RS3 lines 199-212). EVE dividends are manual and
proportional to shares (EVE line 100, forum sources only **(unverified source)**). Melvor's hourly township tick (MI line 136).

---

## 10. Faucets and sinks, per hour

**Rule.** Every line moves coin between a company and a city purse. Nothing is minted by this plan; nothing new is destroyed.

| Flow, per hour (+ in, - out) | L1 company (measured inputs) | L10 company (target) | L20 company (target) | Goes to / comes from |
|---|---|---|---|---|
| + Sale proceeds less buys (gross margin) | +12,700 | +100,000 | +600,000 | city of the sale / of the buy |
| - Profit tax | -1,700 | -10,800 (Rank 5, 80 %) | -46,000 (Rank 9, 60 %) | city of the sale (10 % to its capital) |
| - Dock fees | -1,500 | -10,500 (88 %) | -55,000 (76 %) | city of the harbour |
| - Wages at sea | -70 | -580 | -6,000 | the harbour the voyage reaches |
| - Stores | -40 | -330 | -3,500 | the harbour |
| - **Hull upkeep** (new) | **-130** | -1,200 | -14,200 (6 x tier 4-5, Shipbuilding 20) | home city |
| - **Captain wages** (new) | -47 | -190 | -280 | home city |
| + Land party | +410 | +850 | +2,000 | goods: a city pays when sold |
| + Estates | 0 | +1,500 | +25,000 | goods: a city pays when sold |
| - **Estate repair + crew ashore** (new) | 0 | -220 | -2,000 | home city |
| + **Dividends** (hourly) | 0 | +375 | +7,500 | city purses |
| **Net** | **~+9,600** | **~+79,000** | **~+508,000** | |
| New lines as a share of gross | 1.4 % | 1.6 % | 2.7 % | |

**The world.** The economy is closed (`economy_closed` lit on prod): every line above is a transfer, so **total coin holds**. It
moves only by the two documented minted kinds (`POPULATION_TAX` into city purses, `OWNER_GRANT`) and the one destroyed kind (`SLOT`,
fleet room). This plan adds none. The sizes: cities hold 24.39 B and merchants 9.64 B; all 19 companies together 1.23 M. An L20
company's whole hourly flow (~0.6 M) is 0.002 % of the world: no company can move the money supply; the watch is on single thin
purses (a city that pays dividends and buys gold), which 0457 and the purse brake already guard. I did not measure the size of
`POPULATION_TAX` an hour.

**Our biggest sink.** For a company it is the **profit tax (13 % of a near run's gross margin), then the dock fee (12 %)**: 25 % in
all, against 1-3 % for every new line together. That matches EVE, where the transaction tax is the biggest single sink (33,438 B of
119,400 B in October 2026, 28 %; EVE lines 152-185).

---

## 11. Offline

**Rule.** Everything is the server's, so it runs while the player is away: fleet jobs sail, estates and parties produce, dividends,
upkeep and wages are charged each hour. **The cap is ONE existing knob, `land_away_hours` (12 today)**, read as the away cap by
parties, estates and the fleet job tick (hq-corp A2.5). Melvor's figure is 24 hours (MI line 179); raising the knob is the owner's.

| Item | While away | After the away cap (`land_away_hours`) with no sign-in |
|---|---|---|
| Fleet jobs | run | the current run finishes, then the job waits (no new run) |
| Estates, land repeat | produce, up to the shed's room | pause |
| Hull upkeep, captain wages, wages ashore, estate decay | charged | **pause** (a dormant company is never drained) |
| Dividends | paid hourly | keep accruing into `accrued`, credited on return (today's rule) |
| Return | one "While you were away" card: per line, +/- coin, runs, units made, upkeep paid, "Saved", and anything waived | `world.away_report` (0481), extended with the hourly lines |

"Signed in" is the last-seen stamp the builder of 0496 finds on the company; if there is none, one column on `players`, written by the
sign-in read already made.

**Reference.** Melvor: 24-hour cap, the same rules online and off, a summary popup on return (MI lines 176-183). TW: production
accrues while logged out, capped by the warehouse (TW line 186).

---

## What I could not measure or verify

- **A fleet job's real per hour in time.** The per-hour figures are the server's quote with the game's 300 s turn. The 2-minute job
  tick, an empty return leg and glut recovery between runs were not simulated in game time; the ten-run repeat had no recovery.
- **Live player income.** 18 of 19 prod companies had no ledger row in 24 h; the one active company's 24 h was investing and ransom.
  So no prod per-hour income exists to compare with.
- **Local purses differ from prod.** With `economy_closed` off locally, a city purse does not bind a sale as on prod (the median prod
  purse is 2.11 M). The near-run figures may be higher than prod's for a big hold.
- **L5-L20 income** is a target scaled by hold, not measured: no tier 2-5 hull was quoted.
- Hull prices other than the Barca's yard quote are class `build_cost`; the yard's quote for them was not read.
- Repairs an hour, the size of `POPULATION_TAX`, the Influence multiplier of holders other than the top investor, and the land guard's
  real ceiling on an estate were not measured.
- From the research, marked where used: TW's 1.163 output factor (the author's fit), EVE's dividends (old forum posts), RS3's repair
  discount cap.
