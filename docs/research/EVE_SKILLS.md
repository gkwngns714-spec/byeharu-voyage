# EVE Online's skill system, researched for byeharu-voyage

**Status:** research note, 2026-10-17. No code. Written against `docs/SHIPS_AND_SKILLS.md` (plan of
2026-10-15) and the two skill migrations already on prod, 0131 (catalogue + queue) and 0133 (effects +
requirements, dark). The owner's words that this serves: *"skill systems like eve too"*.

**How this was gathered.** EVE University wiki pages, CCP's own news/dev-blog posts, the official
patch notes, EVE Ref and Fuzzwork for data, and — because the live truth beats any wiki — a pull of
every skill in the game from CCP's public ESI API on 2026-10-17 (category 16 "Skill", 25 groups,
589 types of which **512 are published**; each type's dogma attributes 275 `skillTimeConstant`,
180/181 primary/secondary attribute, 182–184 / 277–279 required skills and levels — the attribute
ids verified against Fuzzwork's `dgmAttributeTypes.csv`). Reddit could not be read from this
machine (its robots policy blocks the crawler); player-sentiment material comes from the official
forums, MassivelyOP, MMOs.com, Tobold and Macworld instead, and is labelled as opinion. Every number
below is either from a cited page or from that ESI pull; the few I computed myself are marked
*(computed)*.

**Citations are at the end (§8), numbered; `[n]` in the text.**

---

## 0. The twelve findings that matter most for us

1. **The curve we copied is exactly EVE's**, including the quirk that the formula does not reproduce
   levels II and IV: EVE's table is 250 / 1,414 / 8,000 / 45,255 / 256,000 SP × rank, and level V is
   82.3 % of a skill's total [1]. 0131:37-39 uses the same five numbers. Match.
2. **1,800 SP/h is EVE's Omega base rate exactly** (20/20 attributes, no implants): 30 SP/min, 43,200
   a day, 1.296 M a month [1][2]. Real EVE players run 2,070–2,700 SP/h with implants and a remap;
   Alphas run 900. Our single rate is the floor of EVE's band, with no lever above it.
3. **Ranks in EVE run 1–16**; of 512 skills the modal rank is 5 (112 skills), then 2 (86), 3 (75), 1
   (64), 8 (41) (ESI pull). Sum of all ranks 2,513 → 643 M SP to train everything, about **41 years
   at 1,800 SP/h** *(computed)*; EVE Uni's older figure is 494 skills, 604 M SP, "over 24 years" at
   max attributes [1]. Our 92 skills sum to 389 ranks → 99.6 M SP → **6.3 years** at 1,800 SP/h
   *(computed from `docs/SHIPS_AND_SKILLS.md:457-496`)*. A tenth of EVE's horizon; a sensible size.
4. **EVE's T1 hull chain is Frigate III → Destroyer III → Cruiser III → Battlecruiser III → Battleship
   III → capitals**, at ranks 2 / 2 / 5 / 6 / 8 / 12–16 (ESI; [3]). CCP deliberately **cut the
   prerequisite levels from IV to III in 2013** to shorten the ladder [4]. Our chain (`SHIPS_AND_SKILLS.md:459-460`)
   asks Medium **IV** before Heavy and Heavy **IV** before Capital — stricter than EVE at the two
   steps CCP relaxed.
5. **T2 in EVE = racial hull V + the specialisation skill I + several support skills at V**, not hull V
   alone: Assault Frigates needs Mechanics V and Power Grid Management V; Heavy Assault Cruisers needs
   Weapon Upgrades V, Energy Grid Upgrades V, Capacitor Management IV and Spaceship Command V; the
   Cerberus from nothing is **63 days 9 h** at base rate [5] (ESI). Ours: size-hull V + role
   specialisation I, where the specialisation needs the role skill V (`:469`). Same shape, no
   support-skill rung.
6. **EVE's per-level hull bonuses are written on the hull, two per skill**, e.g. Caracal: per level of
   Caldari Cruiser 5 % missile rate of fire and 10 % heavy-missile velocity [6]; a T2 hull reads TWO
   skills (Cerberus: Caldari Cruiser ×2 bonuses + Heavy Assault Cruisers ×2) plus flat **role
   bonuses** that need no skill (Cerberus: −50 % MWD signature penalty) [5]; a pirate hull reads two
   races' skills (Gila: Gallente Cruiser 10 % missile damage, Caldari Cruiser 4 % shield resists,
   role 500 % medium-drone damage) [7]. Ours puts two traits per line on the line's hull skill
   (`:144-156`) and a static "role uplift" on T2 — the same idea, minus a per-level term from the
   specialisation on T2 hulls (we give +4 % of the role stat, `:469`; EVE gives two).
7. **The "Magic 14"** are 14 cross-hull support skills, all +5 %/level (Spaceship Command +2 %), ranks
   1–3, rank sum 21: all to IV = 950 k SP ≈ **22 days**, all to V = 5.38 M SP ≈ **124 days** at
   1,800 SP/h [8] *(computed)*. CPU Management V and Power Grid Management V are each +25 % to the
   two fitting budgets. Our Deck Management (+5 %/level, `:474`) is CPU Management; nothing is Power
   Grid Management — Gun Drill (`:489`) only discounts High items, like EVE's Advanced Weapon Upgrades.
8. **Prerequisite levels in EVE cluster at V**: of 779 prerequisite edges, 304 are "at V", 145 at IV,
   183 at III, 57 at II, 90 at I; 225 of 512 skills need something at V; 30 skills are roots (ESI).
   The unlock pattern is: I flies the T1 thing, III opens the next size, IV opens the support
   skills (Surgical Strike needs Gunnery IV), V opens T2 and specialisations. Ours follows this
   (`:457-496`), and adds an OR-prerequisite ("any T2 specialisation III" for Famous Ships, 0131:31-33)
   that EVE's data model does not have — EVE prerequisites are always AND (0131:31-33).
9. **Weapons in EVE are size-tiered skills** — Small / Medium / Large / Capital turret at ranks
   1 / 3 / 5 / 7, +5 % damage per level, each needing the smaller one at III, and T2 guns need the
   size skill V plus a specialisation (rank 3 / 5 / 8 / 10, +2 %/level) [9] (ESI). That is why a
   battleship takes months to be *useful*, not just to *sit in*. Our Gunnery group (`:484-490`) has no
   size tier; guns are one base type at every hull size.
10. **Offline training was CCP's answer to the grind, and the queue limits were a retention lever
    that CCP later gave up.** 2009: queue of 50 entries, every entry must START within 24 h, stated
    reason "EVE is a social game and we want you exposed to other players" [10]. 2014: 24-hour window
    removed, 10-year window, 50 entries kept [11]. 2021: 150 entries, Alpha 24-hour rule removed,
    Skill Plans [12]. Our `skill_queue_max` 10 (`:445`) is below every value EVE ever used.
11. **Skill injectors (2016) are the most criticised feature of the system** — extract 500 k SP from a
    character above 5.5 M, inject with diminishing returns 500 k / 400 k / 300 k / 150 k by the
    receiver's total SP (<5 M / <50 M / <80 M / ≥80 M) [13][14]; a large injector was ≈ 739 M ISK on
    2026-10-17 (ESI average price), an extractor ≈ 468 M. We have no injectors; that is the right
    call and should stay a stated rule.
12. **Skills-on-Demand (2019) removed the "sail to the market to buy the book" friction for core
    skills** because new players found a second system confusing; rare skills stayed location-gated
    [15]. Our enrolment (`:440-444`) is that pre-2019 friction by design — fine for line hull skills
    (the travel IS the flavour), questionable for the 33 general skills.

---

## 1. Core mechanics

### 1.1 Levels and skill points

Every skill has five levels. SP to reach level L from zero is `250 × rank × 32^(L−1)` in CCP's
description, but the table EVE actually uses is the rounded one below (II and IV do not come out of
the formula; EVE Uni notes this) [1]:

| level | total SP (rank 1) | SP for that level | share of the skill |
|---|---|---|---|
| I | 250 | 250 | 0.10 % |
| II | 1,414 | 1,164 | 0.45 % |
| III | 8,000 | 6,586 | 2.57 % |
| IV | 45,255 | 37,255 | 14.55 % |
| V | 256,000 | 210,745 | 82.32 % |

Consequences that shape play: I–IV together are 17.7 % of a skill; level V costs 4.7× levels I–IV
combined; the per-level *bonus* is linear while the *cost* is ×5.66 per level, so V is where the
system asks "do you really want this". Alpha clones are often capped at IV precisely because V is
the expensive, prestige rung.

### 1.2 Ranks (training-time multipliers)

Rank multiplies every SP figure. Range **1–16** [1]. From the 2026-10-17 ESI pull of the 512 published
skills:

| rank | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 14 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| skills | 64 | 86 | 75 | 33 | 112 | 23 | 9 | 41 | 4 | 23 | 3 | 14 | 18 | 7 |

Level V by rank (SP, and days at 1,800 SP/h, *computed*): rank 1 = 256 k (5.9 d); 2 = 512 k (11.9 d);
3 = 768 k (17.8 d); 4 = 1.02 M (23.7 d); 5 = 1.28 M (29.6 d); 6 = 1.54 M (35.6 d); 8 = 2.05 M (47.4 d);
10 = 2.56 M (59.3 d); 12 = 3.07 M (71.1 d); 14 = 3.58 M (83 d); 16 = 4.10 M (94.8 d). Anchors: Navigation
1, Evasive Maneuvering 2, Surgical Strike 4, racial Cruiser 5, Battlecruiser 6, Battleship 8, Marauders
10, Dreadnought 12, Carrier / Capital Ships / Jump Freighters 14, Titan 16 [1][3] (ESI).

### 1.3 Attributes and SP per hour

Five attributes — Intelligence, Memory, Perception, Willpower, Charisma. Every skill names a primary
and a secondary; rate in SP/minute = **primary + secondary ÷ 2** for Omega, half that for Alpha.
Base 20 in each except Charisma 19 (99 points); remap floor 17, ceiling 27, 14 points movable [2].

| clone | primary / secondary | implants | SP/min | SP/h | SP/day | SP/30 d |
|---|---|---|---|---|---|---|
| Alpha | 20 / 20 | none | 15.0 | 900 | 21,600 | 648 k |
| Alpha | 27 / 21 | +3 | 21.0 | 1,260 | 30,240 | 907 k |
| Omega | 20 / 20 | none | **30.0** | **1,800** | **43,200** | **1.296 M** |
| Omega | 20 / 20 | +3 | 34.5 | 2,070 | 49,680 | 1.49 M |
| Omega | 20 / 20 | +5 | 37.5 | 2,250 | 54,000 | 1.62 M |
| Omega | 27 / 21 | +5 | 45.0 | 2,700 | 64,800 | 1.944 M |

Source [1][2]. EVE Ref's calculator gives the same 1,296,000 SP/month for a bare Omega and 1,944,000
for the best remap with +5s [16]. Which attributes a group uses is in §2.1.

History: "learning skills" (skills that raised attributes, i.e. training to train faster) were
removed in the Incursion release (Dec 2010); their SP was refunded as free SP and every character got
+12 fixed points per attribute [17]. CCP has said more than once it would like to remove attributes
altogether (CSM notes 2015; secondhand reports of a Fanfest 2022 talk), but no shipped removal was
found; EVE Uni's Skills page, edited 2026-04-19, still documents remaps as live [1][18].

### 1.4 Neural remaps

One "normal" remap that comes back **one year** after use, plus **two bonus remaps** on a new character
that never replenish. EVE Uni's rule of thumb: plan a remap for ~4 months of one attribute pair [2].

### 1.5 Implants, hardwirings, accelerators

- **Attribute implants**, slots 1–5, one per attribute: Ocular Filter (Perception), Memory
  Augmentation, Neural Boost (Willpower), Cybernetic Subprocessor (Intelligence), Social Adaptation
  Chip (Charisma); +1 Limited, +2 Limited-Beta, +3 Basic, +4 Standard, +5 Improved; the +4 needs
  Cybernetics IV and the +5 Cybernetics V (Cybernetics is rank 3, needs Science III); pirate sets
  give +2 / +3 / +4 by grade plus a set bonus [19][20]. Lost with the pod.
- **Skill hardwirings**, slots 6–10: +1 % … +6 % to one specific thing (e.g. turret damage), the
  larger ones gated by Cybernetics II–V [20].
- **Cerebral accelerators**: temporary +all-attribute boosters, e.g. +9 for 14 days = 272,160 extra SP,
  +3 for 35 days (starter packs) = 226,800; event ones +4 to +12 for 12 h – 3 d; Biology extends
  booster duration 20 %/level, doubling at V [2][16].
- EVE Ref prices (2026) the +3 set at ≈ 37 M ISK for +194,400 SP/month, the +5 set at ≈ 485 M for
  +324,000 — i.e. the whole implant layer is worth +15 % … +25 % training speed [16].

### 1.6 The training queue

| era | rule | why CCP said so |
|---|---|---|
| 2003–2009 | no queue; one skill at a time; idle time lost | — |
| Apocrypha, Mar 2009 | up to **50** entries, each must **start within 24 h** | "EVE is a social game and we want you exposed to other players… a long abstinence would ruin this for us" (CCP Eris Discordia) [10] |
| Phoebe, Nov 2014 | 24-hour window removed; **10-year** window; 50 entries kept "as a temporary safety measure"; trial accounts keep 24 h | players have busy lives and plan around them [11] |
| Nov 2016 (Alpha clones) | Alphas inherit the trial accounts' 24-hour start window | [11][12] |
| Sep 2021 | **150** entries for Alpha and Omega; Alpha 24-hour rule removed; **Skill Plans** (10 personal plans, 5 milestones each, one-click buy-and-queue, shareable); Certified Skill Plans per career | so a certified plan longer than 50 levels fits [12] |

Mechanics that have never changed: the first entry trains in real time whether you are logged in or
not; the next starts automatically; entries can be reordered and removed with no SP lost (SP stays
*in the skill*); when an Omega drops to Alpha the queue **pauses** and non-Alpha skills go inert but
keep their SP, resuming on re-subscription [21]. An empty queue simply wastes time — the original
2008 complaint ("if a skill ends while you are offline you lose training time") [22].

### 1.7 Skill books and how a skill is obtained

A skill must be **injected** (book consumed, skill sits at level 0) before it can be queued; a book
may be injected without its prerequisites, but training needs them [1]. Core books are cheap (Magic
14 books: 30 k – 200 k ISK [8]); T2 and capital books run to millions; EVE Uni reimburses NPC-seeded
books up to 3.5 M ISK [1]. **Skills on Demand (Feb/Mar 2019)**: core skills are bought straight from
the character sheet (with their prerequisites in one click) at a mark-up — EVE Uni quotes **+30 %**
over the NPC price — because "new players find the market confusing and must learn a second system
to set up a skill plan"; rare skills (Precursor, LP-store, exploration drops) stay off the sheet so
their rarity survives [15][1].

### 1.8 Extractors and injectors (skill trading, Feb 2016)

- **Skill Extractor** (sold for PLEX, ≈ 468 M ISK average on 2026-10-17 by ESI): pulls **500,000 SP**
  out of trained skills on a character with **more than 5,500,000 SP**, docked, no active ship;
  prerequisites of still-trained skills and a few skills (Cybernetics, Infomorph Psychology…) cannot
  be extracted [13].
- **Large Skill Injector** (≈ 739 M ISK): gives unallocated SP by the receiver's total —
  **500 k below 5 M, 400 k from 5 to 50 M, 300 k from 50 to 80 M, 150 k above 80 M** [14][16].
- **Small Skill Injector** (2017; a large splits into five): 100 k / 80 k / 60 k / 30 k on the same
  brackets [14].
- **Daily Alpha Injector**: 50,000 SP, one a day, Alphas only, ≈ 40 M ISK [16].
- CCP's stated rationale: "favour transfers to younger characters while protecting the prestige of
  long commitment"; CCP sells extractors, never SP directly, and called selling SP outright
  pay-to-win — then sold starter packs with flat SP anyway [13][23].

### 1.9 Unallocated SP and free SP

Unallocated SP is a pool on the character sheet (from injectors, rewards, refunds) applied to any
queued skill or spread across the queue; it counts toward total SP and toward the Alpha 5 M cap [1].
Sources today: **AIR Career Program** ≈ 750 k SP per account (4 × 100 k per career graduation + 50 / 75 /
100 / 125 k at career-point milestones) [24]; **AIR Daily Goals** 10,000 SP for two of four goals a
day [25]; **Omega weekly** 15,000 SP in the store (since Jul 2024) [1]; before Jun 2024 the login
calendar gave Alphas ≈ 50 k and Omegas ≈ 150 k a month [26]; **referral** 1,000,000 SP for a new
account [16]; starter packs 50 k – 1.75 M SP plus accelerators [16]. **Expert Systems** (Mar 2021):
rented skill sets for 7 days (T1 exploration frigate, mining barge, core flying skills), character-bound,
removed on expiry; the community reaction was strongly negative [27].

### 1.10 Alpha vs Omega

Alpha (free, since Nov 2016; widened Dec 2017): trains at **half speed**; free training stops at
**5,000,000 SP** (unallocated counts); the Alpha set is **175 skills / 19.67 M SP** with level caps
(e.g. racial Destroyer and Cruiser max IV, turret specialisations max III, Large turrets max IV);
battleships yes, T2 ships no, T2 large weapons no; injectors can take an Alpha to ≈ 20 M in Alpha
skills [21][28][3][9]. CCP's reasoning for the cap: "giving away more free training would reduce the
value of skill points and harm balance and the economy" [28]. Omega: everything.

---

## 2. Structure

### 2.1 The skill groups (25 in the live data; EVE Uni lists 24 — "Fake Skills" is unpublished)

Counts are **published skills on 2026-10-17 (ESI)**; attributes from EVE Uni [1].

| group | n | ranks seen | primary / secondary | what it does |
|---|---|---|---|---|
| Spaceship Command | 91 | 1–16 | Perception / Willpower (Willpower / Perception for advanced) | fly each hull class: racial Frigate…Titan, T2 lines, haulers, barges |
| Gunnery | 66 | 1–14 | Perception / Willpower | turret sizes, specialisations, support (tracking, range, RoF, damage) |
| Resource Processing | 35 | 1–12 | Memory / Intelligence | mining, ice, gas, reprocessing, salvaging |
| Science | 43 | 1–8 | Intelligence / Memory | research, invention, the 33 rank-5 science disciplines |
| Drones | 33 | 1–14 | Memory / Perception | drone sizes, racial specialisations, fighters |
| Missiles | 31 | 1–10 | Perception / Willpower | launcher sizes, specialisations, support |
| Fleet Support | 20 | 1–12 | Charisma / Willpower | Leadership → Wing Command (8) → Fleet Command (12); command bursts |
| Subsystems | 16 | 1 | Intelligence / Memory | T3 cruiser subsystems (all rank 1) |
| Sequencing | 16 | 1–9 | Charisma / Perception | player-made ship skins (2024+) |
| Electronic Systems | 15 | 2–8 | Intelligence / Memory | EWAR, cloaking, cynos |
| Engineering | 15 | 1–10 | Intelligence / Memory | CPU / powergrid / capacitor; the fitting skills |
| Navigation | 15 | 1–14 | Intelligence / Perception | speed, agility, warp, jump drives |
| Trade | 15 | 1–10 | Charisma / Memory | order count (Trade→Retail→Wholesale→Tycoon), fees (Accounting, Broker Relations), remote orders (Marketing, Procurement, Daytrading, Visibility), contracts |
| Armor | 14 | 1–10 | Intelligence / Memory | Mechanics, Hull Upgrades, repair, resistance compensation |
| Shields | 13 | 1–10 | Intelligence / Memory | capacity, recharge, boosters, compensation |
| Production | 13 | 1–16 | Memory / Intelligence | Industry, advanced industry, capital & supercapital construction (16) |
| Social | 10 | 1–4 | Charisma / Intelligence | standings, mission rewards, negotiation |
| Rigging | 10 | 2–3 | Intelligence / Memory | −10 %/level rig drawback per rig family; Jury Rigging |
| Neural Enhancement | 9 | 1–12 | Intelligence / Memory | Cybernetics, Biology, jump clones, boosters |
| Targeting | 8 | 1–3 | Intelligence / Memory | lock count, speed, range |
| Scanning | 7 | 1–8 | Intelligence / Memory | probing, hacking, archaeology |
| Structure Management | 7 | 2–8 | Memory / Willpower | Upwell structures |
| Corporation Management | 5 | 1–8 | Memory / Charisma | member caps, offices, alliances |
| Planet Management | 5 | 1–5 | Intelligence / Memory | planetary industry |

EVE Uni's totals of 1 Mar 2025: 494 skills, 2,361 total rank, 604.4 M SP; the live count is 512 and
2,513 rank (+18 skills since, mostly Sequencing and new hull lines) [1] (ESI).

### 2.2 Prerequisite trees — the shape of the data

- 30 root skills (no prerequisite), 233 skills with one prerequisite, 201 with two, 48 with three; a
  type carries at most three required skills in the main attributes (ESI).
- The most-used prerequisites: Spaceship Command (51 dependants), Science (49), Mechanics (31), Power
  Grid Management (28), Gunnery / Missile Launcher Operation / CPU Management (27 each), Leadership
  (22), Drones (21), Capital Ships (17), Motion Prediction (16) (ESI). Those are the trunk skills.
- Prerequisite **levels**: I 90, II 57, III 183, IV 145, **V 304** of 779 edges; 225 of 512 skills need
  some other skill at V (ESI).

**The T1 hull ladder (Caldari shown; all four races identical; ESI, [3]):**

| skill | rank | needs | SP to V | days at 1,800 |
|---|---|---|---|---|
| Spaceship Command | 1 | — | 256 k | 5.9 |
| Caldari Frigate | 2 | Spaceship Command I | 512 k | 11.9 |
| Caldari Destroyer | 2 | Caldari Frigate III | 512 k | 11.9 |
| Caldari Cruiser | 5 | Caldari Destroyer III, Spaceship Command II | 1.28 M | 29.6 |
| Caldari Battlecruiser | 6 | Caldari Cruiser III, Spaceship Command III | 1.54 M | 35.6 |
| Caldari Battleship | 8 | Caldari Battlecruiser III, Spaceship Command IV | 2.05 M | 47.4 |
| Advanced Spaceship Command | 5 | Spaceship Command V | 1.28 M | 29.6 |
| Capital Ships | 14 | Advanced Spaceship Command V | 3.58 M | 83 |
| Caldari Dreadnought | 12 | Battleship III, Capital Ships III, Tactical Weapon Reconfiguration I | 3.07 M | 71 |
| Caldari Carrier | 14 | Battleship III, Capital Ships IV, Drone Interfacing V (+ jump skills) | 3.58 M | 83 |
| Caldari Titan | 16 | Battleship III, Capital Ships V, Leadership V (+ Jump Portal Generation I) | 4.10 M | 95 |

Minimum SP to sit in a hull of each class from nothing *(computed, Omega base)*: frigate 250 SP
(8 min); destroyer Frigate III (16 k) + Destroyer I (500) ≈ 9 h; cruiser + Destroyer III (16 k) +
Cruiser I (1.25 k) + SSC II ≈ 19 h; battlecruiser + Cruiser III (40 k) + BC I (1.5 k) + SSC III ≈ 42 h;
battleship + BC III (48 k) + BS I (2 k) + SSC IV (45 k) ≈ 95 h ≈ 4 days; dreadnought + BS III (64 k) +
SSC V (256 k) + ASC V (1.28 M) + Capital Ships III (112 k) + Dread I (3 k) ≈ 1.8 M SP ≈ **42 days**;
titan ≈ 5.5 M SP ≈ **4 months** (Capital Ships V alone is 3.58 M). Sitting in it is not flying it well: the hull bonus scales with the
racial skill level, and the weapons have their own ladder (§2.6).

**T2 / T3 / other lines (rank; prerequisites; ESI, [3][5]):**

| skill | rank | needs |
|---|---|---|
| Assault Frigates | 4 | Spaceship Command III, Mechanics V, Power Grid Management V (+ racial Frigate V on the hull) |
| Interceptors | 4 | Evasive Maneuvering V, SSC III |
| Covert Ops | 4 | Electronics Upgrades V, SSC III |
| Logistics Frigates / Cruisers | 4 / 6 | Signature Analysis V, Long Range Targeting IV / V, SSC III |
| Heavy Assault Cruisers | 6 | Energy Grid Upgrades V, Weapon Upgrades V, Capacitor Management IV, SSC V |
| Command Ships | 8 | SSC V, Command Burst Specialist IV, Wing Command IV |
| Marauders | 10 | Energy Grid Upgrades V, Advanced Weapon Upgrades V, SSC V |
| Tactical Destroyers (T3D) | 3 | racial Destroyer V |
| Strategic Cruisers (T3C) | 5 | racial Cruiser V (+ Subsystems) |
| Haulers | 4 | SSC III; Transport Ships 6: Industry V; Freighters 10: ASC V + Hauler III; Jump Freighters 14 |
| Mining Frigate 2 → Mining Barge 4 (Industry V, Astrogeology III) → Exhumers 5 (SSC IV, Astrogeology V) | | |

Worked total: a Cerberus (Caldari HAC) from a blank sheet is Caldari Cruiser V (29 d 15 h) + Heavy
Assault Cruisers I (50 min) + Energy Grid Upgrades V (11 d 20 h) + Weapon Upgrades V (11 d 20 h) +
SSC V (5 d 22 h) + Capacitor Management IV (3 d 3 h) + the chain below = **63 d 9 h 37 m** at base
attributes, no implants [5].

### 2.3 How ships require skills, by tech tier

| tier | requirement pattern | example |
|---|---|---|
| **Tech I** | racial class skill I (+ the chain behind it) | Caracal: Caldari Cruiser I ← Caldari Destroyer III ← Caldari Frigate III ← SSC I, + SSC II [6] |
| **Navy / Empire faction** | same skills as the T1 of that class, sometimes one level higher (Navy battleships II since 2013) | "if you can fly a faction's T1 ships you can fly its faction ships" [29][4] |
| **Pirate faction** | **two races'** class skills at low level | Gila: Caldari Cruiser II + Gallente Cruiser II (and both destroyer/frigate chains) [7] |
| **Tech II** | racial class skill **V** + T2 line skill I + support skills at V | Wolf: Minmatar Frigate V, Mechanics V, Power Grid Management V [1] |
| **Tech III** | racial Cruiser V (or Destroyer V) + subsystem skills | Strategic Cruisers rank 5 (ESI) |
| **Capital / super** | Battleship III + Capital Ships III–V + the class skill (12–16) + jump skills | §2.2 |

Requirements gate **boarding/undocking**: a ship whose skills you lack cannot be flown but can be
owned, bought, given; losing Omega makes non-Alpha hulls inert in station [21]. There is a free ship
market, so the requirement is the only gate — unlike our build-only gate (`SHIPS_AND_SKILLS.md:397-399`).

### 2.4 Per-level hull bonuses and role bonuses

Three layers on every hull [5][6][7]:

1. **Per level of the class skill** — usually two lines, scaled by the pilot's level in THAT skill:
   Caracal "5 % bonus to RLML/HML/HAML rate of fire per level; 10 % heavy-missile velocity per level"
   (so +25 % / +50 % at V). Typical magnitudes: 5 %, 7.5 %, 10 %, 20 % per level; resistances 4–5 %.
2. **Per level of the T2 line skill** (T2 hulls only) — a second pair: Cerberus adds "7.5 % shield
   booster amount, 5 % missile RoF per level of Heavy Assault Cruisers", and its Caldari Cruiser pair
   is **different** from the Caracal's (2.5 % damage, 20 % HAM velocity): T2 hulls are re-authored,
   not T1 + a flat uplift.
3. **Role bonus** — flat, no skill: Cerberus −50 % MWD signature penalty, "can fit Assault Damage
   Controls"; Gila +500 % medium-drone damage, +250 % drone HP. Role bonuses define the ship's
   identity; skill bonuses reward investment.

### 2.5 Support skills — the Magic 14 and the multipliers

All affect every hull, none are stacking-penalised, and they multiply with ship bonuses and modules [8][30]:

| skill | group | rank | per level | at V |
|---|---|---|---|---|
| CPU Management | Engineering | 1 | +5 % CPU | +25 % |
| Power Grid Management | Engineering | 1 | +5 % powergrid | +25 % |
| Capacitor Management | Engineering | 3 | +5 % capacitor | +25 % |
| Capacitor Systems Operation | Engineering | 1 | −5 % cap recharge time | −25 % |
| Mechanics | Armor | 1 | +5 % hull HP | +25 % |
| Hull Upgrades | Armor | 2 | +5 % armour HP | +25 % |
| Shield Management | Shields | 3 | +5 % shield HP | +25 % |
| Shield Operation | Shields | 1 | −5 % shield recharge time | −25 % |
| Long Range Targeting | Targeting | 2 | +5 % lock range | +25 % |
| Signature Analysis | Targeting | 1 | +5 % lock speed | +25 % |
| Navigation | Navigation | 1 | +5 % speed | +25 % |
| Evasive Maneuvering | Navigation | 2 | +5 % agility | +25 % |
| Warp Drive Operation | Navigation | 1 | −10 % warp cap | −50 % |
| Spaceship Command | Spaceship Command | 1 | +2 % agility | +10 % |

Rank sum 21 → all IV 950,355 SP (**22 days**), all V 5,376,000 SP (**124 days**) at 1,800 SP/h
*(computed)*. EVE Uni's advice is III–IV first, V "in the long term", and only after the skills that
let you sit in the ship you want [8]. Other multipliers in the same style: Weapon Upgrades −5 %/level
weapon CPU, Advanced Weapon Upgrades (rank 6) −2 %/level weapon powergrid, Electronics / Energy Grid
Upgrades −5 %/level module CPU, Acceleration Control +5 %/level prop-mod speed, Repair Systems −5 %/level
repairer cycle [31]. Fitting skills are the pattern we copied as Deck Management (CPU) — see §5.

### 2.6 Weapons: size tiers and the specialisation ladder

Gunnery (rank 1, +2 % rate of fire/level) is the root. Per turret family (energy / hybrid / projectile)
there are four size skills, **Small 1 / Medium 3 / Large 5 / Capital 7**, each +5 % damage per level,
each needing the previous size at III and Gunnery at I / III / V / V. T2 turrets need the size skill
at **V** plus a **Specialization** skill (rank 3 / 5 / 8 / 10 for S / M / L / Capital; +2 % damage per
level; needs a support skill at III / IV / V — Sharpshooter for long-range, Motion Prediction for
short-range). Supports: Motion Prediction (2, +5 % tracking), Rapid Firing (2, +4 % RoF), Sharpshooter
(2, +5 % optimal), Controlled Bursts (2, −5 % cap), Surgical Strike (4, +3 % damage, needs Gunnery IV),
Trajectory Analysis (5, +5 % falloff) [9] (ESI). Missiles and drones mirror the layout. This is why
EVE's "time to be useful in a battleship" is dominated by Large guns (1.28 M to V) rather than by the
8-rank hull.

### 2.7 Modules by meta and their skill needs

T1 (meta 0) needs the base skill; **named / meta 1–4 need no more than T1**; **T2 (meta 5) needs more
skills** (the base at V plus a specialisation) and more CPU/powergrid; **faction / storyline / deadspace
/ officer need the same skills as T1** and are equal to or better than T2 with lower fitting cost —
money substitutes for time at the top of the ladder [29]. T2 drones: 20 % more damage and HP than T1
plus a further skill; T2 ammo needs higher skills and fits only T2/faction/officer weapons [29].

### 2.8 The unlock-tier pattern, stated

- **I** — sit in the T1 ship, use the T1 module (Drake flies at Caldari Battlecruiser I [1]).
- **II** — minor supports (Hull Upgrades needs Mechanics I; Retail needs Trade II).
- **III** — the next hull size; the next weapon size; most rigging and industry steps (183 edges).
- **IV** — the support branch (Surgical Strike ← Gunnery IV; Capital Ships IV for carriers; Daytrading
  ← Trade IV) (145 edges).
- **V** — T2 anything, specialisations, the capital trunk (304 edges; 225 skills carry one).

### 2.9 How bonuses combine

Skills, ship bonuses, implants, hardwirings and boosters are **never stacking-penalised**; modules and
rigs that touch the same percentage attribute are, at 100 % / 86.9 % / 57.1 % / 28.3 % / 10.6 % / 3.0 %
in descending order of strength [30]. The arithmetic is multiplicative: two +5 %/level skills at V give
×1.25 × 1.25 = ×1.5625, not +50 %.

---

## 3. Design rationale and player experience

### 3.1 Why real-time offline training

- **No grind.** A character improves by the clock, not by repetition; the player's session time goes
  to the sandbox (trade, war, politics) rather than to levelling. CCP framed the 2009 queue limits
  explicitly as a *retention* device — keep people logging in — and then dismantled those limits in
  2014 and 2021 because players organised their lives around them anyway [10][11][12].
- **Long-term goals.** Every target is a date: "Cerberus in 63 days". The queue is a plan, and Skill
  Plans (2021) turned it into a shareable artefact with milestones [12].
- **Subscription fit.** Training continues while subscribed, whether or not you play; critics have
  called it "Skill Queue Online" — logging in only to re-queue [32][22].
- **The lore fig-leaf**: implanted knowledge downloaded over time; "makes sense, if only marginally"
  [32].

### 3.2 The standing complaints

1. **The gap.** Tying progress to calendar time gives early joiners "an unreachable head start" [32];
   a 2015 forum view: veterans are "12 years ahead… you will never catch up"; the usual rebuttal is
   that a focused 10 M SP pilot in one ship line equals a 200 M SP pilot in that ship, because a hull
   reads only the skills that touch it [33]. CCP's answers over time: starting SP 55 k → ~400 k
   (Vanguard, Sep 2015) [34], the 1 M referral, AIR career SP, injectors.
2. **Too slow at the start.** The 2023 "EVE skills STILL take too long" thread: new players want to
   fly a null-sec doctrine ship in two weeks; replies: a new account arrives with ≈ 1.3 M SP, the game
   is meant to be measured in years, blanket speed-ups help veterans just as much [33].
3. **Injectors = pay-to-win.** Extractors are sold for cash, injectors for ISK; a blank character was
   maxed in one sitting in 2016 for real money; CCP's line is that it sells extractors, not SP, and
   that diminishing returns protect veteran prestige [13][23][35]. The counter-argument that "SP is not
   skill" is also the community's standard defence [35].
4. **Expert Systems (2021)**: renting skills for a week read as monetising the one thing the system
   had kept pure; Reddit was "very much displeased" [27].
5. **Attributes are busywork.** Remaps reward spreadsheet planning over play; CCP has agreed in
   principle since at least 2015 and has not shipped a removal [18].

### 3.3 How CCP tuned it, in order

| when | change | effect |
|---|---|---|
| 2009 Mar (Apocrypha) | skill queue, 50 entries, 24-h start window | end of "wake up at 3 a.m. to re-queue" [10] |
| 2010 Dec (Incursion) | learning skills removed, SP refunded, +12 base per attribute | ~2 weeks of "training to train" deleted [17] |
| 2013 summer | Destroyers/Battlecruisers split into racial skills; class prerequisites IV → III; capitals need Battleship III not V; industrials to I; tiericide of hull requirements | shorter, consistent ladder; "no vessel should require another to be mastered to unlock it" [4] |
| 2014 Nov (Phoebe) | 24-h window removed, 10-year window | plan months ahead [11] |
| 2015 Sep (Vanguard) | starting SP ≈ 55 k → ≈ 400 k | a new pilot sits in a T1 cruiser on day one [34] |
| 2016 Feb | skill extractors / injectors | SP becomes tradable [13] |
| 2016 Nov / 2017 Dec | Alpha clones; Alpha set widened to battleships, 20.4 M SP set, 5 M free cap | free-to-play with a level cap, not a time cap [28] |
| 2017 | small injectors, daily Alpha injector | [14][16] |
| 2019 Mar | Skills on Demand: buy core skills from the sheet | market friction removed for core skills [15] |
| 2020–2024 | login SP (≈ 150 k/month Omega), then AIR Daily Goals 10 k/day | engagement SP, small [25][26] |
| 2021 Mar | Expert Systems (7-day rentals) | poorly received [27] |
| 2021 Sep | queue 150; Alpha 24-h rule gone; Skill Plans + Certified plans | planning made first-class [12] |
| 2022+ | AIR Career Program ≈ 750 k SP; referral 1 M | the newbie's first ~1.5 M SP is a gift [24][16] |
| 2024 Jul | Omega weekly 15 k SP | [1] |

Nothing in 2019–2023 changed the curve, the ranks of existing skills or the attribute formula; the
tuning was all around the edges: how skills are obtained, how long the queue is, how much SP is given
away, and (2013) how the ladder is wired.

### 3.4 A newbie's first week and first year in SP *(computed from §1 rates)*

- **Day 0:** ≈ 384–387 k SP of starting skills (CPU / PG Management IV, Gunnery IV, Science IV,
  Spaceship Command III, Mechanics III, Navigation III, plus racial frigate and weapon skills whose levels the wiki does not tabulate) [34]; +1,000,000
  unallocated from a referral link [16] → ≈ 1.4 M. Can sit in a T1 destroyer at once and a T1 cruiser
  within a day.
- **Week 1 (Omega, bare):** +302 k trained; AIR career missions pay out most of their ≈ 750 k in the
  first weeks; daily goals +70 k → ≈ 2.2–2.5 M SP. Flying a T1 cruiser with its weapon size at III–IV.
- **Month 1:** +1.3 M trained → ≈ 3–3.5 M. A T1 battlecruiser, Magic 14 at III.
- **Month 3:** ≈ 6–7 M. First T2 frigate or a T1 battleship with Large guns at III–IV.
- **Year 1:** trained 15.8 M bare, 18–24 M with +3/+5 implants and a sensible remap; plus ≈ 3.6 M daily
  goals, 0.8 M weekly, 0.75 M AIR, 1.4 M start → **≈ 22–30 M SP**. Two or three ship lines to T2,
  Magic 14 at IV–V. An Alpha: 900 SP/h → hits the 5 M free cap in 5–7 months.
- **Veteran:** 100 M SP ≈ 6–8 years of continuous Omega training; 200 M+ exists only through injectors
  or 15+ years. The biggest single skill (Titan, 4.1 M) is 95 days by itself.

### 3.5 Training culture that fell out of the numbers

"Train to IV, V only for what you fly every day" (IV is 17.7 % of the cost for 80 % of the bonus); "fly
what you can afford to lose" (hulls are gated by skills, not by level, so a skilled pilot loses a
cheap ship and shrugs); "support skills first, then the shiny hull" is EVE Uni's standing advice [8][1].

---

## 4. Mapping hints for an age-of-sail game

### What translates cleanly

| EVE | byeharu-voyage | note |
|---|---|---|
| four races × Frigate/Destroyer/Cruiser/BC/BS/capital racial skills | eleven lines × Small/Light/Medium/Heavy/Capital hull skills | our 55 hull skills are EVE's 4×5=20 racial ladder scaled to 11 lines; EVE never had more than 4 "races" of ladder, so our catalogue is hull-heavy (60 % of skills vs EVE's 18 %) |
| Spaceship Command / Advanced SC / Capital Ships (generic trunk) | Command / Fleet Command | EVE gates every class on the generic trunk too (SSC II/III/IV/V); ours gates only capital (Command III) and flagship (Fleet Command I) |
| T2 line skill + racial V | T2 role specialisation I + size-hull V | add 1–2 support skills at V to T2 (EVE's pattern), e.g. Hull Upkeep V for Convoy Escorts |
| per-level hull bonuses, two per skill | line traits per level | match; consider a second per-level pair from the specialisation on T2 hulls |
| role bonus (flat, no skill) | T2 "role uplift" static numbers | match |
| Gunnery group: sizes + specialisations + supports | Gunnery, Long/Short Guns, Gun Laying, Boarding, Gun Drill | no size tier; see §5 |
| Navigation group | NAVIGATION, Rigging, Lookouts, Instruments | fine; EVE's Navigation group is also where "propulsion module" skills live, ours is where sails live |
| Engineering (CPU / PG Management, Weapon Upgrades) | Deck Management, Gun Drill | missing a "Hands Management" |
| Armor / Shields / Mechanics | Hull Upkeep, Damage Control | fine |
| Trade group (order count, fees, remote trading) | ACCOUNTING, HAGGLING, Cargo Stowage | EVE's Trade is 15 skills about *how many orders, from how far, at what fee*; ours could grow the same way (remote buying through factors, more open contracts) |
| Fleet Support (Leadership → Wing → Fleet Command, command bursts) | Command → Fleet Command | EVE gives fleet-wide % bonuses from the commander's skills — the natural home of "convoy" bonuses |
| Social / standings | (none) | nation/city standing skills are an obvious future group |
| implants (slot 1–5 attributes; 6–10 hardwirings) | officers (0127's per-signing level) and the Flourish | officers = hardwirings (a +3 % to one stat you can lose); attribute implants have no analogue because we have no attributes |
| cerebral accelerators (event rewards) | a time-limited "tutor aboard" booster | the one accelerator EVE's community accepts; never sold for ducats |
| skill books (cheap, core; rare, located) | enrolment (500 × rank; general at academies, line hulls at the line's yards) | keep the located rare ones (line hulls), drop the friction for core |
| Alpha / Omega | — | not applicable unless a free tier is ever monetised |
| injectors / extractors | — | deliberately absent; say so in the plan |
| unallocated SP from daily goals / AIR | — | a small, capped, play-earned SP trickle (e.g. 10 k/day for a completed voyage) is the EVE-tested way to reward logging in without touching the curve |

### What does not translate

- **One character, one clone.** EVE's SP lives in a pilot who pods and re-clones; ours lives in the
  house. That removes jump clones, implant loss, and the "which character trains" MCT market — all
  of which are monetisation, none of which we need.
- **Fitting budgets scale with skills in EVE because CPU/PG are abstract.** Our Hands budget is
  derived from real crew numbers (`crew_max − ⌈crew_required/2⌉`); a "Hands Management" skill would
  mean "the crew work better", which is a believable per cent but should stay small (3 %/level).
- **The free ship market.** In EVE the skill requirement is the ONLY thing between a newbie and a
  titan someone gives him. Our requirements gate BUILD only (`SHIPS_AND_SKILLS.md:397-399`); if a ship
  market or gifting ever lands, the same `requirements_met` must gate *taking command*, or the gate
  is void.
- **Weapon sizes.** EVE's biggest "time to be useful" lever is Large guns; our hulls have no gun
  size, so a heavy hull is useful the moment it is built. Either accept (hulls, not guns, are the
  grind — the plan's stated intent, `:402-404`) or introduce a size on guns later.
- **Attributes and remaps.** Deliberately absent (one rate). EVE's own designers wanted rid of them;
  do not import them.
- **Level caps per clone state** (Alpha max IV) — unless a free tier exists.

---

## 5. Our plan and migrations against EVE — match, thin, wrong

File references: `docs/SHIPS_AND_SKILLS.md` (the plan), `supabase/migrations/20260818000131_a_skill_is_learned_by_the_hour.sql`
(0131), `supabase/migrations/20260818000133_a_skill_makes_the_ship_better.sql` (0133).

| aspect | ours | EVE | verdict |
|---|---|---|---|
| SP per level | 250 / 1,414 / 8,000 / 45,255 / 256,000 × rank (0131:37-39; plan `:424-426`) | identical [1] | **match** |
| rate | 1,800 SP/h, one rate (0131:39; `:425-426`) | 1,800 base Omega; 900 Alpha; 2,070–2,700 with implants/remap [1] | match at the floor; **thin**: no lever for the player, and no reward-shaped accelerator |
| offline, no cron, level lands at `finishes_at` | `skill_level_at` pure function of time (0131:40-43) | the queue trains in real time while offline [1] | **match**, and cleaner than EVE (EVE needs a server-side completion event) |
| queue length | `skill_queue_max` 10 (`:445`) | 50 (2009–2021), 150 (2021–) [11][12]; Alphas had a 24-h start window until 2021 | **thin** — raise to 50; a queue is free to store |
| removing an entry keeps SP | `skill_sp` banks the partial level (0131:32-34) | SP stays *in the skill* [1] | match |
| pausing | none ("no pausing", `:447`) | pauses only on Omega → Alpha [21] | match |
| unallocated SP | none | injectors, rewards, refunds [1] | fine; add only as a capped reward pool if ever |
| skill books / obtaining | enrolment 500 × rank, at an academy (general) or at a yard of the line (hull skills) (`:440-444`) | books 30 k–millions ISK; since 2019 core skills bought from the sheet (+30 %), rare skills location-gated [15][1] | **partly wrong by EVE's own lesson**: location-gating *core* skills is what CCP removed; keep it for line hull skills only |
| instant purchase retired | `cmd.study_skill` becomes enrol + queue (0131:12-14, 44-48) | never had instant levels except by injector | match |
| ranks | 1 / 2 / 4 / 6 / 10 for Small…Capital; Famous 12; Fleet Command 8; specs 5 (`:428-438`, `:457-496`) | Frigate 2, Destroyer 2, Cruiser 5, BC 6, BS 8, Dread 12, Carrier 14, Titan 16; Fleet Command 12; T2 lines 4–10; specs 3–10 (ESI) | close; our Small (1) is lighter than Frigate (2); our 10 for capital sits between Marauders 10 and Dread 12 — fine for a game whose horizon is a tenth of EVE's |
| catalogue size | 92 skills / 8 groups, 389 total rank, 99.6 M SP, 6.3 years to all V *(computed)* | 512 / 24 groups, 2,513 rank, 643 M SP, ~41 years *(computed)* | right order of magnitude for a smaller game; 60 % of our skills are hull skills vs EVE's 18 % — **thin** everywhere else (Trade 4 skills vs 15, Navigation 6 vs 15, no Social, no Fleet Support beyond two) |
| T1 ladder prerequisites | Small III → Light I; Light III → Medium I; **Medium IV** → Heavy I; **Heavy IV** → Capital I (`:459-460`) | III at every step since 2013 [4] | **stricter than EVE at two steps** — CCP moved the other way on purpose; Medium III / Heavy III would halve the wait at those rungs (IV is 5.7× III) |
| generic trunk | Command III for capital; Fleet Command I for flagship (`:392-393`) | SSC I/II/III/IV at each class, ASC V + Capital Ships III–V for capitals [3] | **thin**: Command could be asked at I/II/III along the ladder like SSC, which also makes Command a trunk skill (EVE's most-used prerequisite) |
| T2 gate | size-hull V + role spec I; spec ← role skill V (`:394`, `:469`) | racial V + line skill I + 1–3 support skills at V [3][5] | close; **thin**: add one support-V (the role's natural support) to each specialisation |
| famous ships | hull V + Famous Ships I + spec III, one per house (`:395`) | no analogue (AT prize ships are limited editions); pirate hulls need two races' skills | ours is an extension; the "two lines" idea (a famous ship needing two lines' hull skills, like Gila) is available and cheap |
| per-level hull bonuses | line traits (2 per line) on the line hull skill, 132 HULL rows of `skill_effects` (0133:28-34) | 2 per class skill on T1; 2 + 2 on T2; + flat role bonus [5][6][7] | **match** for T1; **thin** on T2 (no per-level pair from the specialisation; EVE re-authors the racial pair on T2 hulls) |
| where a bonus lives | `skill_effects (skill, scope, stat, pct, filters)`, one reading `world.skill_pct` (0133:37-40) | dogma effects on the hull type referencing the skill's level | equivalent; ours is the cleaner authority |
| arithmetic | `(base + units) × (1 + Σ skill %)` (`:504-506`; 0133:46) | multiplicative per bonus, skills never stacking-penalised; modules penalised 0.869/0.571/0.283 [30] | **different, defensible**: additive-within-skills is slightly weaker than EVE's product at high levels (two +25 % → +50 % vs +56 %); no module stacking penalty at all in ours — note for gear |
| support skills | Hull Upkeep 4 %, Damage Control 3 %, Rigging 3 %, Lookouts 5 %, Instruments 2 %, Cargo Stowage 3 %, Deck Management 5 %, Gun Drill −4 % hands (`:472-489`) | Magic 14 all 5 % (SSC 2 %); fitting CPU and PG both +5 %/level [8] | match in kind; **thin**: no Power-Grid analogue (a "Hands" skill), no targeting/sighting-range pair, no cap/endurance pair beyond live SEAMANSHIP |
| weapons | Gunnery 1, Gun Laying 2, Long/Short Guns 3, Boarding 2, Gun Drill 3, Gunnery Spec 5 (`:484-490`) | sizes 1/3/5/7 at +5 %/level, specs 3/5/8/10 at +2 %/level, six supports 2–5 [9] | **thin by design** (no gun sizes); acceptable while hulls are the grind |
| requirements table | `skill_requirements (subject_kind hull/item, code, skill, level)`, EMPTY at 0133, filled by S12+ (0133:35-36) | up to 3 required skills per type, levels I–V, 779 edges across 512 skills | match; our table is unbounded, which EVE's three slots are not |
| requirement gates | BUILD only; fitting via `mount_fitting` (`:397-399`; 0133:41-43, 49-50) | boarding/undocking and module activation | **gap if a ship market or gift ever exists** — the plan says so; keep it binding |
| OR-prerequisites | `skill_prereqs.choice` groups (0131:31-33) | none (AND only) | extension; fine |
| merchants fixed | no queue, four skills (0131:54-58) | NPCs have no skills at all | fine |
| the switch | `skills_bite` false, pre-image proven (0133:11, 64) | n/a | our discipline, not EVE's |
| starting position | four live skills at 0, three Lisbon hulls free; first new-line hull ≈ 14 h (`:401-404`) | ≈ 400 k SP + 1 M referral; T1 cruiser within ~19 h of training *(computed)* | match in feel; consider a starter grant (Small III in the house's own line) — the plan's own open question 1 (`:853-855`) |
| the long grind | flagship ≈ 3 months; famous flagship 4–5 months (`:402-404`) | titan ≈ 4 months to sit in; years to fly it well *(computed)* | match |
| injectors | none | 2016; the main P2W complaint [13][35] | **right**; write "never" into the plan |
| attributes / remaps / implants | none (`:426`) | 900–2,700 SP/h band; CCP wants rid of attributes [1][18] | right to omit attributes; **thin** on the *reward* side (accelerators) |

**Specific recommendations, in priority order (numbers are proposals, each one knob):**

1. `skill_queue_max` 10 → **50** (0131 knob; `:445`). EVE's 2014 value; costs nothing.
2. Ladder prerequisites Medium **IV** → **III** before Heavy, Heavy **IV** → **III** before Capital
   (`:459-460`; `data/skills.json` prereqs). EVE's 2013 reasoning applies word for word: the ladder
   should be consistent and no hull should need another *mastered*. Keep IV only where the plan wants
   a deliberate wall (Capital Hulls V for flagships already is one).
3. Give the 33 general skills enrolment **anywhere** (or at any academy *plus* a 30 % mark-up from any
   port, EVE's 2019 shape); keep the line hull skills at the line's yards. `skill_profile.enrol_where`
   already carries the distinction (0131:30-31).
4. Add a Power-Grid analogue: **Crew Drill** (rank 2, Seamanship, +3 % Hands per level), the second
   half of EVE's fitting pair; Deck Management stays CPU.
5. T2 specialisations ask one support at V: Armed Merchantmen ← Cargo Stowage V; Privateers ← Gun
   Laying V; Survey Ships ← Lookouts V; Convoy Escorts ← Hull Upkeep V. One row each in
   `skill_prereqs`. Makes the supports matter the way EVE's do.
6. T2 hulls read a per-level pair from their specialisation (e.g. Privateers: +3 % attack and +2 %
   reach per level) in `skill_effects` with a `tech` filter — 0133's table already has the column.
7. Command asked along the ladder like Spaceship Command: Light I needs Command I, Medium needs Command
   II, Heavy needs Command III, Capital needs Command IV — makes Command the trunk skill it is in EVE
   (51 dependants) and gives the Command line a reason to exist before capitals.
8. A **capped play-earned SP trickle**: e.g. 5,000 SP per completed voyage of ≥ N nm, cap 10,000 a day
   (EVE's daily-goal number), credited as a per-skill top-up through the existing `skill_sp` bank.
   The one accelerator EVE's players accept; never for ducats.
9. Write two absences into the plan as rules: no injectors/extractors, no attributes. EVE's history
   says both are the places the system got hurt.
10. Later, when the Trade and Social groups are built out, use EVE's Trade group as the template:
    "how many standing orders", "from how far away", "at what fee" are three separate skills (Trade /
    Marketing / Accounting), each one a per-level number.

---

## 6. Numbers worth keeping to hand

- SP/level ×rank: 250 · 1,414 · 8,000 · 45,255 · 256,000. Level V = 82.3 % of a skill.
- Omega base 30 SP/min = 1,800/h = 43,200/day = 1.296 M/30 d; ceiling ≈ 2,700/h; Alpha 900/h.
- Ranks 1–16; live distribution peaks at 5; sum 2,513 over 512 published skills (2026-10-17).
- Queue: 50 (2009) → 50 + no window (2014) → 150 (2021). Alpha 24-h window until 2021.
- New character ≈ 385 k SP; +1 M referral; AIR ≈ 750 k; daily goals 10 k; Omega weekly 15 k.
- Injector 500 k / 400 k / 300 k / 150 k at <5 M / <50 M / <80 M / ≥80 M; extractor needs > 5.5 M.
- Magic 14: rank sum 21; IV everywhere 22 days; V everywhere 124 days.
- T1 ladder prerequisites: III at every step; Battleship III for every capital.
- Cerberus from zero: 63 d 9 h. Titan from zero: ≈ 4 months to sit in.

---

## 7. Gaps in this research

- Reddit threads could not be fetched (crawler blocked); sentiment is from the official forums,
  MassivelyOP, MMOs.com, Tobold, Macworld.
- EVE Uni's "Skill points", "Skill injectors", "Skill queue", "Skill groups", "Character creation",
  "Meta level" pages returned 404 under those names; their content was recovered from the "Skills",
  "Starting skills", "Spaceship Command", "Gunnery", "Tech 2", "Stacking penalties", "Attributes" and
  "Alpha clone" pages plus official posts.
- The exact per-skill Alpha level caps were not tabulated (EVE Uni marks them per skill; only the
  ship and turret examples are quoted).
- The CCP Fanfest 2022 statement on removing attributes is secondhand (forum recollection); no
  official page was found.
- The Spaceship Command page's Minmatar Cruiser row said "Minmatar Frigate III"; the ESI data says
  Minmatar Destroyer III (same as the other races) — the wiki row is stale, the table above uses ESI.

---

## 8. Sources

1. EVE University, *Skills* (edited 2026-04-19) — https://wiki.eveuniversity.org/Skills
2. EVE University, *Attributes* — https://wiki.eveuniversity.org/Attributes
3. EVE University, *Spaceship Command* (skill group) — https://wiki.eveuniversity.org/Spaceship_Command
4. CCP, *The great ship skill changes of summer 2013* (2013-02-07) — https://www.eveonline.com/news/view/the-great-skill-change-of-blessed-2013
5. EVE University, *Cerberus* — https://wiki.eveuniversity.org/Cerberus
6. EVE University, *Caracal* — https://wiki.eveuniversity.org/Caracal
7. EVE University, *Gila* — https://wiki.eveuniversity.org/Gila
8. EVE University, *The Magic 14* — https://wiki.eveuniversity.org/The_Magic_14
9. EVE University, *Gunnery* (skill group) — https://wiki.eveuniversity.org/Gunnery
10. CCP Eris Discordia, *More Queue Queue* (2009-02-04) — https://eveonline.com/article/more-queue-queue
11. CCP Delegate Zero, *Longer Queues Expected: Skill Training Above and Beyond 24 Hours* (2014-10-28) — https://www.eveonline.com/article/longer-queues-expected-skill-training-above-and-beyond-24-hours
12. CCP, *Updates To Skill Training* (2021-08-24) — https://www.eveonline.com/news/view/updates-to-skill-training
13. CCP, *Patch Notes for February 2016 Release* (skill trading) — https://www.eveonline.com/news/view/patch-notes-for-february-2016-release ; press release — https://cosmocover.com/newsroom/ccp-introduces-skill-trading-to-eve-online-allowing-players-to-transfer-skillpoints-between-characters
14. EVE Ref, *Small Skill Injector* (brackets) — https://www.everef.net/type/45635 ; CCP, *Increased Skill Injector Flexibility Coming On May 23rd* (2017) — https://www.eveonline.com/article/increased-skill-injector-flexibility-coming-on-may-23rd
15. CCP, *Skills On Demand — Changes Coming To The Skill System!* (2019-02-26) — https://www.eveonline.com/news/view/skills-on-demand-changes-coming-to-the-skill-system ; *The March 2019 release is now live* — https://www.eveonline.com/news/view/the-march-2019-release-is-now-live
16. EVE Ref, *Skill Points* (prices and SP/ISK, live) — https://everef.net/skill-points
17. CCP, *Learning skills are going away* (2010) — https://www.eveonline.com/news/view/learning-skills-are-going-away-1 ; Massively interview with CCP Greyscale (2010-11-26) — https://www.engadget.com/2010-11-26-massively-interviews-ccp-greyscale-on-the-eve-christmas-gift.html
18. CSM summit notes on attribute removal (2015, forum archive) — https://forums-archive.eveonline.com/message/5594381/ ; forum thread *Attributes are pointless* — https://forums.eveonline.com/t/attributes-are-pointless/492713
19. EVE University, *Implants* — https://wiki.eveuniversity.org/Implants
20. EVE University, *Cybernetics* — https://wiki.eveuniversity.org/Cybernetics
21. EVE University, *Alpha clone* / *Clone States* — https://wiki.eveuniversity.org/Alpha_clone , https://wiki.eveuniversity.org/Clone_States
22. Tobold, *Offline skill training* (2008-07) — http://tobolds.blogspot.com/2008/07/offline-skill-training.html ; Macworld on the 2009 queue — https://www.macworld.com/article/194843/skillqueue.html
23. MassivelyOP on starter-pack SP and CCP's "we sell extractors, not SP" position — https://massivelyop.com/?p=231531
24. EVE University, *AIR Career Program* — https://wiki.eveuniversity.org/AIR_Career_Program ; *Guide to AIR Career Programme* — https://wiki.eveuniversity.org/Guide_to_AIR_Career_Programme
25. EVE University, *AIR Daily Goals* — https://wiki.eveuniversity.org/AIR_Daily_Goals
26. EVE University, *Login rewards* (Evergreen, 2020–2024-06-10) — https://wiki.eveuniversity.org/Login_rewards
27. CCP, *Expert Systems — Live Now* (2021-03) — https://www.eveonline.com/article/qpp9x6/expert-systems-now-live ; MassivelyOP reaction — https://massivelyop.com/?p=324593
28. CCP, *Clone States — The Next Steps* (2017-12) — https://www.eveonline.com/news/view/clone-states-the-next-steps
29. EVE University, *Tech 2* (meta ladder and skill needs) — https://wiki.eveuniversity.org/Tech_2
30. EVE University, *Stacking penalties* — https://wiki.eveuniversity.org/Stacking_penalties
31. EVE University, *Support skills* — https://wiki.eveuniversity.org/Support_skills
32. MMOs.com, *Offline Training: A Blessing Or a Curse?* — https://mmos.com/editorials/offline-training-a-blessing-or-a-curse
33. EVE forums, *EVE skills STILL take too long to train* (2023) — https://forums.eveonline.com/t/eve-skills-still-take-too-long-to-train-sponsored-streamer-reaction/388549 ; 2015 "never catch up" thread — https://forums.eveonline.com/t/impression-after-returning-5-years-later/93245
34. EVE University, *Starting skills* — https://wiki.eveuniversity.org/Starting_skills
35. EVE forums, *Pay to win or not a pay to win?* — https://forums.eveonline.com/t/pay-to-win-or-not-a-pay-to-win/51305 ; EN24, blank character maxed by injectors (2016-02-15) — https://evenews24.com/2016/02/15/event-blank-character-maxes-all-skills-via-skill-injectors-in-a-single-sitting
36. Data: CCP ESI — https://esi.evetech.net/latest/universe/categories/16/ and `/universe/groups/{id}/`, `/universe/types/{id}/`, `/markets/prices/` (pulled 2026-10-17); Fuzzwork SDE dumps — https://www.fuzzwork.co.uk/dump/ (attribute ids from `latest/csv/dgmAttributeTypes.csv`: 180 primaryAttribute, 181 secondaryAttribute, 182–184 requiredSkill1–3, 275 skillTimeConstant, 276 skillPoints, 277–279 requiredSkill1–3Level, 280 skillLevel)
