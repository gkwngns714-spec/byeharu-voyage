# The owner's specification: what exists, what is missing, the slices (2026-11-25)

Source: `docs/design/owner-spec-2026-11-25.md` (row 385), the owner's words, which outrank every earlier design.
Everything here not marked as a question in section 2 is **decided by default; the owner may reverse it.**

**How this was made.** Read on origin/main 12e9807e (prod head 0496 by `docs/WORK_QUEUE.md`), in 60 minutes. No production read was made.
I read the design files named in the brief and `docs/SEA_CONDITIONS_AND_REGIONS.md`; three helper agents located the code.
- `NNN:line` means `supabase/migrations/20260818000NNN_*.sql`, the line of the definition. Many functions are later re-cut by text hunks,
  so the line is where the concept is defined, not always the whole live body.
- "lit" and "dark" are **as documented** (WORK_QUEUE, OWNER_REQUESTS, migration headers). No switch was read on prod.
- Lines I opened myself: 001:160-173, 004:92-95, 215 header, 321:104, 352:26-31 and 317-331, 396 header, 478 header, 481 header,
  `data/sea-zones.json`, `src/app/navTabs.ts`. Every other file:line is a helper's report, **not re-proven by me**.
- The open migrations are called by their planned numbers: 0497 wreck-can-sell, 0498 jobs-never-lose, 0499 near-round, 0500 fit-to-sail,
  0501 cargo-at-cost. On their branch tips the files still carry older numbers.

**The largest finding.** The sea part of the spec is mostly BUILT: 64 named seas, each with a level ask and a wave resistance ask, a
wave figure on every hull and on gear, one gate, a rule that never traps a fleet, the player's wall words, a Seas page. It was lit on
2026-11-13 and switched off on 2026-11-23 at the owner's word (row 369). The spec asks for it back. Nothing new needs inventing there;
the table needs three changes and the switch needs a careful light.

---

## 0. After the owner's answers (2026-11-25): the seas by continent, then slots, HQs, riot, stores

Source: "The owner's answers" in `docs/design/owner-spec-2026-11-25.md`. **This section outranks sections 1 to 6 where they differ**
(Q1's default "only the sealed oceans ask a level" is reversed; Q2 to Q8 are answered). Third pass, 60 minutes, no production read.

**How the numbers were made (all from files in the repo, nothing guessed).**
- The 64 seas, their level and wave asks: `data/sea-zones.json`.
- Which seas a trip between two harbours crosses: `data/sea-legs.json` (the course a fleet really sails, for all 254 x 254 pairs).
- How long each trip is: the 32,128 stored courses in migration 0482's seed, decoded and measured point to point.
- A harbour is "reachable at rung R" when a chain of harbour-to-harbour trips joins it to the capital and no trip crosses a sea above R.
- Hours are a Barca's: 2,880 nm a real hour (economy file, section 5). Three pairs have no stored course (BAS-HOR, CAP-ELM, OSA-SAK).
- Not counted: the range of one leg (`nav_leg_nm_base`), which 0494 already plans round harbour by harbour.
- The script was a scratch file, not committed. S1 must turn it into a spec so the table cannot drift.

### 0.1 The rungs

A sea asks two things, as built in 0215: a **level** and a **wave resistance**. The level is `public.title_level`: the lower of the
company's Trading and Exploration levels, at most 11. The owner's order sets the level; the wave figures stay as they are.

| Rung | Continent | Level asked | Hardest wave on the way there | Harbours it opens | Harbours open in all |
|---|---|---|---|---|---|
| 1 | Europe (with the Mediterranean's south shore, the Norwegian, Barents and White seas) | 1 | 12 (83 of them need 0) | 89 | 89 |
| 2 | Africa, round the Cape to Zanzibar | 2 | 12 to Luanda; **44** past the Cape | 28 | 117 |
| 3 | North America and the Caribbean | 3 | 20 (by Iceland; 30 straight across) | 21 | 138 |
| 4 | South America (Brazil and the Plate) | 4 | 20 | 6 | 144 |
| 5 | India and Arabia | 5 | 44 (the Cape) | 33 | 177 |
| 6 | Asia | 6 | 44 | 48 | 225 |
| 7 | The rest (Timor, Australia, New Zealand) | 7 | 44 to 56 | 5 | 230 |
| 8 | Sealed: the Pacific crossings, the Pacific coast of the Americas, the Arctic, the far south | 8 | 70 (Guam 50, Longyearbyen 20) | 24 | **254** |

**Every one of the 254 harbours is reachable at rung 8, and 230 without any sealed sea.** Each harbour's earliest rung is the rung of
its own sea: no harbour sits behind a harder sea than its own (checked for all 254).

**From each European capital: harbours each rung opens (middle / farthest Barca hours to the new ones).**

| From | 1 Europe | 2 Africa | 3 North America | 4 South America | 5 India | 6 Asia | 7 The rest | 8 Sealed |
|---|---|---|---|---|---|---|---|---|
| Lisbon | +89 (0.4 / 1.1 h) | +28 (1.2 / 3.5 h) | +21 (1.1 / 1.6 h) | +6 (1.5 / 1.8 h) | +33 (3.4 / 3.7 h) | +48 (4.2 / 4.7 h) | +5 (3.9 / 4.1 h) | +24 (3.8 / 4.8 h) |
| Seville | +89 (0.5 / 1.2 h) | +28 (1.2 / 3.5 h) | +21 (1.2 / 1.7 h) | +6 (1.5 / 1.9 h) | +33 (3.4 / 3.7 h) | +48 (4.2 / 4.8 h) | +5 (3.9 / 4.1 h) | +24 (3.8 / 4.8 h) |
| London | +89 (0.5 / 1.3 h) | +28 (1.5 / 3.9 h) | +21 (1.3 / 1.7 h) | +6 (1.8 / 2.2 h) | +33 (3.7 / 4.0 h) | +48 (4.6 / 5.1 h) | +5 (4.2 / 4.4 h) | +24 (4.1 / 5.2 h) |
| Amsterdam | +89 (0.5 / 1.3 h) | +28 (1.6 / 3.9 h) | +21 (1.3 / 1.7 h) | +6 (1.8 / 2.2 h) | +33 (3.7 / 4.1 h) | +48 (4.6 / 5.1 h) | +5 (4.2 / 4.5 h) | +24 (4.2 / 5.2 h) |
| Marseille | +89 (0.5 / 1.4 h) | +28 (1.4 / 3.7 h) | +21 (1.4 / 1.9 h) | +6 (1.7 / 2.1 h) | +33 (3.6 / 3.9 h) | +48 (4.5 / 5.0 h) | +5 (4.1 / 4.3 h) | +24 (4.0 / 5.1 h) |
| Istanbul | +89 (0.7 / 1.8 h) | +28 (1.8 / 4.1 h) | +21 (1.8 / 2.3 h) | +6 (2.1 / 2.5 h) | +33 (4.0 / 4.3 h) | +48 (4.8 / 5.4 h) | +5 (4.5 / 4.7 h) | +24 (4.4 / 5.4 h) |

Lisbon to Busan is 4.5 Barca hours the long way (the Cape, India). From Recife to Busan the stored course is 3.9 hours with or without
the Pacific: the Pacific is a shortcut from the Americas' west coast, not from Brazil.

**The 64 seas.** "Level today" is the 0215-0404 table; 42 of 64 change. Wave is unchanged. "Pirates today" is the danger of the
sea in `data/seas.json` (1 to 5); how a pirate's strength follows it in code was **not verified**. Proposed: a sea's pirates carry
its rung as their level, set in the combat slice, not here.

| Sea | Rung | Level asked | Level today | Wave resistance | Pirates today (danger) | Harbours |
|---|---|---|---|---|---|---|
| Mediterranean Sea (MED) | 1 Europe | 1 | 1 | 0 | 3 | 27 |
| North Sea (NEA) | 1 Europe | 1 | 1 | 0 | 1 | 12 |
| European Atlantic (NOR-EU) | 1 Europe | 1 | 1 | 0 | 2 | 12 |
| Baltic Sea (BAL) | 1 Europe | 1 | 1 | 0 | 1 | 9 |
| Aegean Sea (AEG) | 1 Europe | 1 | 1 | 0 | 2 | 4 |
| Bay of Biscay (BAY) | 1 Europe | 1 | 1 | 0 | 2 | 4 |
| English Channel (ENG) | 1 Europe | 1 | 1 | 0 | 1 | 4 |
| Adriatic Sea (ADR) | 1 Europe | 1 | 1 | 0 | 1 | 4 |
| Sea of Marmara (SEA) | 1 Europe | 1 | 1 | 0 | 1 | 1 |
| Ionian Sea (ION) | 1 Europe | 1 | 1 | 0 | 2 | 3 |
| Irish Sea (IRI) | 1 Europe | 1 | 1 | 0 | 1 | 1 |
| Black Sea (BLA) | 1 Europe | 1 | 1 | 0 | 2 | 2 |
| Norwegian Sea (NRW) | 1 Europe | 1 | 2 | 8 | 2 | 2 |
| White Sea (WHI) | 1 Europe | 1 | 3 | 10 | 2 | 2 |
| Barents Sea (BAR) | 1 Europe | 1 | 3 | 12 | 3 | 2 |
| Macaronesia and the Canary Current (NOR-MAC) | 2 Africa | 2 | 2 | 10 | 2 | 8 |
| Gulf of Guinea (GUL) | 2 Africa | 2 | 3 | 12 | 3 | 7 |
| Angola and the Skeleton Coast (SOU-ANG) | 2 Africa | 2 | 3 | 12 | 3 | 2 |
| Mozambique Channel (MOZ) | 2 Africa | 2 | 5 | 12 | 3 | 2 |
| East African coast (IND-EAF) | 2 Africa | 2 | 5 | 12 | 4 | 6 |
| The Cape (SOU-CAPE) | 2 Africa | 2 | 5 | 44 | 3 | 2 |
| The Roaring Forties (IND-S) | 2 Africa | 2 | 5 | 44 | 4 | 1 |
| Gulf of Mexico (GCO) | 3 North America | 3 | 4 | 10 | 3 | 2 |
| Caribbean Sea (CAR) | 3 North America | 3 | 4 | 12 | 4 | 8 |
| The American shore (NOR-AM) | 3 North America | 3 | 4 | 12 | 2 | 8 |
| Gulf of Saint Lawrence (GCE) | 3 North America | 3 | 4 | 12 | 2 | 1 |
| Iceland and Greenland waters (NOR-ICE) | 3 North America | 3 | 3 | 20 | 2 | 2 |
| The Western Ocean (NOR-MID) | 3 North America | 3 | 4 | 30 | 2 | 0 |
| Brazil and the Plate (SOU-BRA) | 4 South America | 4 | 4 | 12 | 3 | 6 |
| The Doldrums (NOR-DOL) | 4 South America | 4 | 4 | 24 | 2 | 0 |
| Persian Gulf (PER) | 5 India | 5 | 6 | 10 | 3 | 4 |
| Red Sea (RED) | 5 India | 5 | 6 | 10 | 3 | 5 |
| Arabian Sea (ARA) | 5 India | 5 | 6 | 12 | 4 | 7 |
| Laccadive Sea (LAC) | 5 India | 5 | 6 | 12 | 2 | 7 |
| Gulf of Aden (GLF) | 5 India | 5 | 6 | 12 | 4 | 1 |
| Gulf of Oman (GAN) | 5 India | 5 | 6 | 12 | 3 | 1 |
| Bay of Bengal (BYF) | 5 India | 5 | 7 | 12 | 3 | 6 |
| The Indian Ocean crossing (IND-E) | 5 India | 5 | 6 | 40 | 4 | 2 |
| Seto Inland Sea (SET) | 6 Asia | 6 | 7 | 8 | 1 | 2 |
| Gulf of Thailand (GND) | 6 Asia | 6 | 7 | 10 | 2 | 2 |
| Yellow Sea (YEL) | 6 Asia | 6 | 7 | 10 | 2 | 3 |
| Strait of Malacca (STR) | 6 Asia | 6 | 7 | 10 | 5 | 1 |
| Gulf of Tonkin (GIN) | 6 Asia | 6 | 7 | 10 | 2 | 1 |
| Korea Strait (KOR) | 6 Asia | 6 | 7 | 12 | 2 | 10 |
| South China Sea (SOA) | 6 Asia | 6 | 7 | 12 | 4 | 7 |
| East China Sea (EAS) | 6 Asia | 6 | 7 | 12 | 3 | 5 |
| Taiwan Strait (TAI) | 6 Asia | 6 | 7 | 12 | 3 | 2 |
| Java Sea (JAV) | 6 Asia | 6 | 7 | 12 | 3 | 3 |
| Visayan Sea (VIS) | 6 Asia | 6 | 7 | 12 | 2 | 1 |
| Andaman Sea (AND) | 6 Asia | 6 | 7 | 12 | 3 | 3 |
| Makassar Strait (MAK) | 6 Asia | 6 | 7 | 12 | 3 | 1 |
| Molucca Sea (MOL) | 6 Asia | 6 | 7 | 12 | 3 | 2 |
| The Kuroshio off Shikoku and Kyushu (PHI-JP) | 6 Asia | 6 | 7 | 12 | 4 | 0 |
| Japan, Pacific side (NRT-JP) | 6 Asia | 6 | 7 | 16 | 4 | 1 |
| Banda Sea (BAN) | 6 Asia | 6 | 7 | 16 | 3 | 3 |
| Sea of Japan (SFJ) | 6 Asia | 6 | 7 | 16 | 2 | 1 |
| Timor Sea (TIM) | 7 The rest | 7 | 7 | 16 | 3 | 2 |
| Tasman Sea (TAS) | 7 The rest | 7 | 8 | 56 | 3 | 3 |
| Pacific Americas, north coast (NRT-AM) | 8 Sealed | 8 | 8 | 12 | 4 | 11 |
| Pacific Americas, south coast (STH-AM) | 8 Sealed | 8 | 8 | 12 | 4 | 8 |
| Arctic Ocean (ARC) | 8 Sealed | 8 | 3 | 20 | 4 | 1 |
| Philippine Sea (PHI) | 8 Sealed | 8 | 8 | 50 | 4 | 1 |
| The North Pacific crossing (NRT-OPEN) | 8 Sealed | 8 | 8 | 70 | 4 | 2 |
| The South Pacific and the Drake Passage (STH-OPEN) | 8 Sealed | 8 | 8 | 70 | 4 | 1 |

**Four things the data forced, each decided by default:**
1. **The Roaring Forties (IND-S) are on Africa's rung.** Every stored course from the Cape to East Africa crosses them; at any higher
   rung East Africa, India and Asia would all open only with "the rest". Side effect: Fremantle, which lies in that sea, opens at rung 2
   (3.5 hours away, wave 44). S1 should cut the sea at about 60 E so Fremantle goes to rung 7; that needs `data/sea-legs.json` rebuilt.
2. **The Pacific coast of the Americas (19 harbours, Acapulco to Valparaiso) is rung 8.** Every stored course to it passes "The South
   Pacific and the Drake Passage", one sea that holds both Cape Horn and the open ocean. To open that coast with South America (rung 4),
   S1 would cut Cape Horn's waters off as a 65th sea. Not done by default: the owner said the Pacific is hardest.
3. **The Arctic Ocean is rung 8** (today level 3, wave 20). Its one harbour is Longyearbyen.
4. **The Bay of Bengal is India** (it was grouped with the Far East).

**Does the raster pass north of Russia? No.** `scripts/sea-grid.mjs` line 200 closes it by hand: the ICE row `northeast-passage`
(everything north of 66.5 N between 60 E and 180 E), with the Canadian arctic (`northwest-passage`) and everything south of 60 S
(`antarctic-pack`). `scripts/straits.mjs` lists no Bering or Arctic strait, and no stored course runs along Siberia. So:
- "Over Russia" **does not exist as water today.** Opening it is its own slice: one ICE row changed, then the raster, the 32,128 stored
  courses and the pair table rebuilt, with the no-land and straits audits. Not in the slices below; named `arctic-passage`, later.
- "Antarctica (south)": the sea south of 60 S is ice and stays ice. The southern shortcut that exists is the Drake Passage, inside the
  rung 8 sea above.

### 0.2 Nobody is trapped

**What the built rule already gives (`public.sea_floor`, 396:171).** A fleet is judged as holding at least what the sea she lies in
asks. With the table above, the way home from every one of the 254 harbours needs no LEVEL above that of the harbour's own sea
(checked: 0 exceptions). So a fleet beyond its company's rung can always sail home on levels.

**What it does not give.** The same check on WAVE fails for 137 harbours: the sea she lies in asks less than the way home does
(Busan's sea asks 12, the Cape on the way home asks 44; Diego Garcia's asks 40, the Cape 44). 0396 says so itself ("it does not carry
her across water her hull cannot hold"). While the gate was off (since 2026-11-23) a weak hull may have sailed anywhere.

**The missing piece, slice `pass-home`.** At the light, every player fleet lying outside rung 1 is given a pass: the level and wave of
the way from where she lies to her capital, stored on her own row (two small numbers). `sea_floor` reads it as a third floor. It is
cleared when she next docks in a rung 1 harbour. No table.

**What a fleet beyond her rung may do:** trade where she lies; sail to any sea that asks no more than the one she lies in; sail home
on her pass; finish a voyage under way. **What she may not:** go further out. Her jobs are not cancelled: a job with a closed leg
waits with the wall's words (0500's wait).

**Existing companies: all of them come under the rule, with the pass** (default). New-only would leave two sets of rules for one sea
for ever. They keep every ship, cargo, shed, HQ, share and job.

**Which of the 19 would be beyond their rung: not known, by rule.** That needs each company's two levels and each fleet's sea and wave
figure: a production read, which this pass did not make. The read exists (`impact.sql`, SEA doc 10.7) and is the lead's one read
before the light; the light's guard prints the same list. What is known from the docs:
- **The owner's company:** Trading 16; the title is the LOWER of Trading and Exploration, and its Exploration was not read (the SEA doc
  recorded title 10 on 2026-11-13). The wreck lies at Diego Garcia, in "The Indian Ocean crossing": rung 5, wave 40. With a title of 5
  or more it is inside its rung. Its way home asks wave 44: if the hull reads under 44, it is the pass that brings it home. A wreck does
  not sail in any case; 0497 lets it sell where it lies.
- A company with two barcas at Acapulco was read on 2026-11-13 (rung 8 water, way home wave 70). Whether it is still there: not read.
  It is the hardest case and the reason for the pass.

### 0.3 Passive slots (answer 3: "trading 3 is good. Number of fleet you can choose to passive trading")

The number of fleets that may hold a repeating job at once, by Trading level. A row of `level_perks` (417:128), read inside
`fleet_job_set_for`; no table.

| Trading level | 1-2 | 3 | 5 | 8 | 11 | 14 | 17 |
|---|---|---|---|---|---|---|---|
| Passive fleets | 0 | 1 | 2 | 3 | 4 | 5 | 6 |

- 6 is `fleet_hard_max`, the most fleets a company may own. Pace (economy file 4a): Trading 3 in about 6 minutes, 5 in 48 minutes,
  10 in 4 hours.
- A company keeps at least the number of jobs it runs on the day of the light. The owner's company (Trading 16) has 5.
- A hand trade, a single "once" job and Bring home once are not passive.
- Passive orders may bargain (answer 7): the job spends its attempts by the same server roll, the first three attempts only, so a
  job's gain is the expected 2.2 % a side for a new company, never a certainty. This replaces 6.2's "may not bargain".

### 0.4 Further HQs (answer 4: "by total level, gold, reputation")

Beside the crew slot ladder (economy file 4a), on the same three readings: `public.total_level`, gold paid to a city, Reputation spent
through `reputation_credit`. The gold goes to the NEW HQ's city. A fleet of hers must be docked there and the city's sea must be within
her rung.

| HQ | Total level | Gold | Reputation | The crew slot at the same total level |
|---|---|---|---|---|
| 1 | founding | 0 | 0 | slot 1 |
| 2 | 30 | 50,000 | 300 | slot 3: 20,000 and 250 |
| 3 | 65 | 250,000 | 1,200 | slot 5: 150,000 and 1,200 |
| 4 | 120 | 1,500,000 | 5,000 | slot 7: 1,000,000 and 5,000 |
| 5 | 160 | 4,000,000 | 10,000 | slot 8: 2,500,000 and 10,000 |

An HQ costs about 1.5 to 2.5 times the crew slot of its level: it brings half tax in its city (T1), a shed and the Forge there without
a fleet in port. Reputation is one balance, so an HQ competes with crew slots and captain skills. Every number is the owner's to change.

### 0.5 Riot, storm, and food and water in the hold (answer 2)

**Food and water take cargo space.** 0345 made this a switch: `ship_stores_separate` false is the one pool again
(free hold = hold - cargo - water - food). Use is 0.020 water + 0.015 food = 0.035 tuns a crew a sea-day (001:167-168); at 192 times
real time that is **0.28 tuns a crew a real hour**. Twenty crew on a 4 hour passage with the 15 % margin carry about 26 tuns of
stores, which is 26 tuns of cargo not carried. A fleet whose cargo and stores are over her hold on the day keeps both and may sail;
she cannot load more until she is under.

**Riot (no food or no water on a settled sea-day).** Each such day:
- crew: 15 % of those aboard are lost (at least 1);
- cargo: **5 % of each good** is lost ("some", never all);
- three such days leave 61 % of the crew and 86 % of the cargo.
When the crew falls under a quarter of the minimum the voyage ends at the nearest city, as `voyage.forced_home` (279:267) does today,
but **with the cargo she still holds**; its "all cargo lost" goes.

**Storm and other happenings.** Crew: 2 to 5 % lost. Cargo: 1 to 2 % of each good (the owner's figure). Calm: nothing lost.

**Speed under the minimum crew:** crew / minimum, never under 0.30 (today a flat 0.70). All of these are frozen at departure, written on
the one `voyage_events` row a sea-day that exists, and booked through 0501's lost-cargo record.

### 0.6 The slices, 0508 onward, smallest first

T1 to T3 hold 0505 to 0507 (section 6.4). The rest of section 3 follows after these.

| # | Slice | Kind | Owns | The player sees | Proof | Database cost |
|---|---|---|---|---|---|---|
| 0508 | **`stores-in-hold`** | one switch, one guard | `ship_stores_separate` false through a light step; `public.fleet_free_hold` never under 0 | Food and water inside the hold bar | Dark and lit pre-images of 0345 hold; an over-full probe fleet sails and cannot load | None |
| 0509 | **`passive-slots`** (`passive_slots_enabled`) | migration + client | seven `level_perks` rows; one check in `fleet_job_set_for`; `AssignSheet.tsx` | "Passive 2 / 3" on Assign; a locked row says Trading 8 | Probe at Trading 3 sets one job, the second is refused with the level; a company with 4 jobs keeps 4 | One small int a company (`players.passive_kept`) |
| 0510 | **`seas-by-continent`** (S1) | data, gate dark | `data/sea-zones.json`, the 42 `sea_zones` rows, a spec that repeats section 0.1's counts | The Seas page lists the continents in order | The counts 89 / 28 / 21 / 6 / 33 / 48 / 5 / 24; every harbour's earliest rung is its own sea's; 254 at rung 8 | 42 rows updated. If the pair table stores levels, it is re-derived once (61,752 rows, off the beat; to be read) |
| 0511 | **`riot-and-storm`** (`happenings_bite`) | migration | hunks on `voyage.settle` and `voyage.forced_home`, `voyage.ship_speed_parts` | "Riot: 4 crew, 5 % cargo lost"; "Storm: 2 crew, 1.4 % cargo" | Probe voyage without food loses 15 % crew and 5 % of each good a day and keeps the rest at the forced stop | None new |
| 0512 | **`hq-cities`** (`hq_cities_enabled`) | migration + client | `public.company_hqs`, `public.hq_steps` (5 rows), `cmd.open_hq`; the HQ city switch | The city name under the company name; "Open HQ: total 30, 50,000, 300 Reputation" | Probe opens HQ 2, the city's purse gains the gold, Reputation falls, home is row 1 | Two tables: at most 5 rows a company; 5 data rows |
| 0513 | **`pass-home`** | migration, dark | two small columns on `fleets`; one hunk on `sea_floor`; the light's guard prints fleets beyond their rung | Nothing until the light | A probe barca at Acapulco with title 1 sails home and nowhere further; the pass clears in rung 1 | No table; no rewrite (nullable columns) |
| 0514 | **`seas-relit`** (S2) | client, then the light | `src/lib/sea/pathfind.ts` (shut seas are closed water), the wall words; `sea_conditions_light()` | Shut seas shaded; a course goes the long way; a wall says what is short | The lit proofs of 0396 to 0402; the lead's `impact.sql` read and the owner told the count first; 30-minute check | None |
| later | **`arctic-passage`** | raster | the ICE row, the raster, stored courses, the pair table | A sealed way north of Russia | No-land and straits audits pass | About 32,000 stored courses rewritten once |

0508, 0509 and 0510 can be built now, in parallel. Each light that changes live play (0508, 0511, 0514) has its own window.

**Not verified in this section:** any company's levels or fleets (no production read); whether `sea_leg_asks` stores levels or only
the seas; how pirate strength is set per sea; the formula of the Exploration level (the economy file's "25 a new harbour" suggests
level 8 needs about 49 harbours, and Europe alone has 89: a company could reach level 8 without leaving Europe, so the PACE of the
levels, not their order, is what the owner should look at next); the hold of a Barca.

---

## 1. The spec, sentence by sentence

Columns: **Today** (authority, state) · **Missing** · **Contradicts** · **Smallest change** (slice name, section 3).

### Company and home

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 1 | "COMPANY NAME – you can change it." | `players.company_name` 004:52. No rename door exists (only `cmd.rename_fleet` 354:357). | A rename door. | Nothing. | `cmd.rename_company` (**A1**). |
| 2 | "When creating the account ... it will ask you to assign a company name." | `cmd.found_house(name, nation)` 011:41; `src/features/found/SignTheBook.tsx`. Live. | Nothing. | Nothing. | None. |
| 3 | "It should not overlap with any other names (countries, trade goods, and with other player info, no special characters)." | 3 to 24 characters, unique, **case-sensitive** (004:52); `E_NAME_TAKEN`, `E_BAD_NAME`. | Case-blind uniqueness; no country name, no good name; letters, digits and single spaces only. | Live names may already break the new rule (not read). | One reading, `public.company_name_refusal(name)`, called by founding and rename (**A1**). Old names stay. |
| 4 | "You can change your name again for free (1st time), but later ... you will have to pay (real money – not decided yet)." | Nothing. | A rename count. | The game has no real-money path at all. | `players.renames int`. Rename 1 is free; rename 2 refuses with "Not available yet" until the owner decides payment (**A1**). |
| 5 | "Then you will choose your home COUNTRY (EUROPE)." | Founding is refused nowhere: every joinable country is offered (0396 header line 46, the lead's decision of 2026-11-14). `great_powers` 187:181 holds PRT ESP ENG NLD FRA OTT MUG MNG JOS JPN. | A Europe-only rule at founding. | 0396's "founding is refused NOWHERE"; companies of Japan or Joseon may exist on prod (one of Japan was read on 2026-11-13; not re-read). | `public.nation_joinable` (0338) also asks that the capital's sea is a European home sea (**A2**). Existing companies keep their country. |
| 6 | "Your first HQ will be in your CAPITAL CITY." | A new company starts at its country's capital (143:402); `public.home_port_of` 288:116 reads the founding harbour. Live. | Nothing for a new company. | hq-corp F1: "HQ is the home city only". | None now; see 13. |

### The HQ screen and income

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 7 | "Below the COMPANY NAME ... how much income you receive, how much maintenance it costs." | `world.company_rate` 493:184 (lines of the last 24 h, live); HQ's Ledger (`src/features/city/corp/LedgerArea.tsx`). | The figures under the name, in three groups. | Nothing. | `public.company_rate_line` 493:109 gains a `group` (active, passive, maintenance); read only (**B1**). |
| 8 | "Active income – fleets, trading / gold per hour." | `world.workers` 496:958 serves each fleet's coin per hour. Live. | Nothing. | Nothing. | Shown in B1's header. |
| 9 | "Passive income – your investments on other cities – dividend." | `city_shares` 123:120; `city_coupon_hour` 495:305, `dividend_hourly_enabled` lit 2026-11-24. | Nothing. | Nothing. | Shown in B1's header. |
| 10 | "Maintenance." | Wages are taken at a sale (`wages_due` 474:154); repairs, tow, dock fee. No hourly upkeep exists. | Hourly upkeep. | Nothing: hq-corp economy section 2 already designs it. | Build hq-corp's `upkeep-and-cuts` as designed (**B2**), dark. |
| 11 | "MANAGING – ... where you manage FLEETS, EXPEDITION (land or sea), INVESTMENT." | HQ's worker list (`WorkerList.tsx`), land parties (0455, lit), Invest (`cmd.invest` 123:324). | Sea expeditions (row 19). The three names as HQ's three headings. | hq-corp C1 names the areas differently. | Client: HQ headings Fleets, Expeditions, Investments (**B1**). |
| 12 | "FLEETS – you can choose between 3 actions – COMBAT, EXPEDITION, TRADING." | `public.fleet_jobs` 481:160, kinds `best`, `fixed`, `land`; one door `cmd.set_fleet_job` 481:782. Lit. | Kinds for combat and expedition. | Nothing. | Two new kinds on the same table and door (**F1**, **F2**). No second job system. |
| 13 | "[FLAG] CITY NAME – by clicking the city name, you can change cities that have your HQ. The whole HQ screen will change ... Top left corner below company name." | The HQ screen already draws any city: `CityScreen.tsx:197-201` (`?port=`, else the fleet in hand, else home). A company has one implicit home; no HQ ownership exists. Storage is per harbour (`storage_cap` 070:130). | "Cities that have your HQ": a list a company owns, and the switcher. How a second HQ is opened is **not in the spec**. | hq-corp F1 and C4 delete `?port=`. | `public.company_hqs` (one row an HQ) seeded from `home_port_of`; the switcher lists them (**B3**). Question Q4. |

### Trading

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 14 | "TRADING – Active: You will choose a good, buy, and sell at different city." | The Trade tab (`/command`, `CommandScreen.tsx` -> `buysell/Trade.tsx`); `cmd.do_buy`, `cmd.do_sell`. Live. | Nothing. | simplify S3, hq-corp F5 and branch `desk-into-hq` delete it. | Keep the tab; do not merge `desk-into-hq`. |
| 15 | "Or you can transport the trade goods to other cities that are needed (mission) for profit & REPUTATION." | City requests: `trade_contracts` 087:178, `cmd.fulfil` 087:481 (live); hold-size requests 0466 (lit per the 0473 header); courier contracts 0483 (lit). | Courier contracts pay no Reputation. | Nothing. | One hunk: `courier_settle` 483:386 credits Reputation by the request's rule (**D1**). |
| 16 | "For transportation, the quantity ... matter. The higher trade quantity, the higher REPUTATION POINTS." | A request earns 1 point per 250 coin of its bonus, 5 to 100 (352:325-327); the bonus is quantity x price x premium, so it already rises with quantity. | A plain quantity term. | Nothing. | Points = by tuns delivered (new knob `rep_request_per_tun`), same 5 to 100 bounds (**D1**). |
| 17 | "For profits you will have to choose cities that pay the most, and REPUTATION POINTS will be earned when the profit rate is higher (profit % + total overall price)." | A sale earns 1 point per 250 coin of profit, at most 120 (`public.reputation_sale` 352:404-439). Amount only; the rate is not read. Daily cap 600. | The profit rate. | Nothing. | `reputation_sale` multiplies by a margin factor (profit / cost), bounded; the caps stay (**D1**). |
| 18 | "Some trade goods can be combined to create PREMIUM TRADE GOODS. Each PTG will be needed by one city only, and it will pay 300~500% more. PTG by themselves costs more. 1 PTG linked with 1 city." | Recipes: `goods_recipes` 280:805 (287 recipes). The Forge: `cmd.forge_good` 281:267, `forge_take` 461:216 (the one take), screen HQ > Production. Smithing 0461 is dark (`land_smith_enabled`). No good has a single buying city; no premium for a made good. City wants (0255, x2, rotating) are a different thing. | The premium list; one city each; the pay. | Closed economy: a city pays from its own purse, so 300-500 % needs a daily cap or it empties the city. The reading of "300~500 % more" (Q5). | Three columns on `public.goods` (`premium_port`, `premium_pct`, `premium_day_units`) and one hunk on the sell side of `world.quote_priced` 169:514, beside `want_mult` (**D2**). No new table, no second forge. |
| 24 | "ACTIVE METHOD: ... Or you can combine in your HQ, manufacture PTG and sell them at a designated city." | The Forge is on HQ already and uses the Storage of that city with a fleet docked there. | Nothing but row 18. | Nothing. | D2. |
| 25 | "PASSIVE METHOD: You can order your fleet to do a repeated task – buy at a city, sell at this city." | `fleet_jobs` kind `fixed` {good, buy, sell, end, times} (481, 492: lit). | Nothing. | Nothing. | None. |
| 26 | "You can choose to stop or continue based on your settings. Settings include buying at a certain price range, selling at a certain price range." | No price setting on a job. The old standing routes had `price_limit` (092:181). 0498 jobs-never-lose (open) adds a WAIT state: a job that would lose waits. | `buy_max`, `sell_min` on the job. | Nothing. | Two params on `fixed`; out of range uses 0498's wait and says why (**E1**). |
| 27 | "PASSIVE METHOD will have restrictions and require higher LEVELS and SKILLS." | No gate on jobs (481, 492, 494). Every live company may set one. | The gate. | Rows 372-376 ("Melvor with many workers": every worker automated from minute one); the owner's own standing order that fleets earn while away. | A gate read from `level_perks` (417:128) inside `fleet_job_set_for`; companies that exist keep the right (**E1**). Question Q3. |
| 28 | "THE TRADE TAB is for ACTIVE TRADING ... it will show your FLEET name, and you can change your FLEET by tapping the name." | `FleetStrip.tsx` / `FleetPicker.tsx`; one fleet in hand (`src/domain/order/draft.ts:56-130`). Live. | The name as the one press, at the top. | `desk-into-hq` deletes these files. | Client only (**C1**). |
| 29 | "In the trade tab there should be a map, showing no NPCs but only locations, where you can click them for info – price info." | A small folding map, `plans/TradeMap.tsx`. The big chart draws merchants (`model.traffic` from `world.sea_traffic` 102:130). Whether TradeMap draws them: not verified. | A map of places only, a press for prices. | Nothing. | Client only: the chart with traffic off, a harbour press opens its prices (**C1**). |

### Expedition and combat

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 19 | "EXPEDITION – is where you visit certain location (sea and land), find architect, report to your CAPITAL CITY for rewards (GOLD) and REPUTATION POINTS." | Land parties dig goods (`land_sites` 455:267, lit). The logbook records firsts (`public.logbook` 478:137, lit 2026-11-23) and pays Reputation for a finished set. Choices at sea (0486, lit). | Sites to visit at sea and on land; a find that is carried; the report at the capital; the reward. | Closed economy: the gold must come from the capital's purse (`city_pays`), never minted. "architect" is unclear (Q6). | A data table of sites; job kind `explore`; the find is a `logbook` row; the report pays on arrival at the capital (**F1**). |
| 20 | "COMBAT – is where you send FLEET for combat – PIRATES. Winning will provide you with GOLD and RP." | A player attacks by hand: `public.attack_for` 327:246 (`attack_enabled` lit by 0375). Loot is moved, not minted (`loot_due` 327:135). Bounties 0471 are dark. `rep_battle` 40 is seeded and **read by nothing** (352:331). | Sending a fleet as an order; Reputation for a win. | Nothing. | Job kind `hunt` that calls `attack_for`; `rep_battle` hooked in `battle_resolve` 323:425 (**F2**). |

### The map

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 30 | "The MAP itself will be black, and your fleet will provide a radius that will show you nearby map. The radius will be larger based on your NAVIGATION SKILL." | The whole chart is drawn. NAVIGATION gives speed and leg reach (454:201; 112:105). No sight exists. | Sight; the black. | Nothing. | **G1**, section 3. |
| 31 | "The location you've visited (city, sites etc) will show like a grey map, where you can tab on that city to not see the info, but to go there." | Visited harbours: `logbook` kind `harbour` (478, lit, humans only). | Grey drawing; "no info, only go". | Today every city's prices are served to everyone (`world.market`). Hiding them on the client only is not secrecy. | G1 (client mask first); a served mask later (**G2**). |
| 32 | "The MAP will be completely black, but where your fleets moved and been will be in grey, showing lands partly (transparent)." | A voyage is one row with its path (`voyages` 006:56); position is computed on read (`voyage.position` 047:504). Nothing records where a company has been. | The trail. | The database budget: no row per step. | One bitmap a company, written once per arrival (**G1**). |

### The voyage

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 33 | "You will need PROVISION (FOOD + WATER + CREW) as a core source." | `ships.water_t`, `ships.food_t`, `ships.crew` (004:92-95); 0.020 and 0.015 tuns a crew a day (001:167-168); spent per sea-day in `voyage.settle` 027:237. Live. | Nothing. | Nothing. | None. |
| 34 | "The CARGO SPACE based on your FLEET (up to 8 SHIPS) will also hold trade goods as well as your PROVISIONs." | Stores have had their OWN space since 0345 (`ship_stores_separate`, lit by 0369, rows 221 and 324). Ships in a fleet: at most 7 (`fleet_ship_top` 321:104). | Stores in the hold; an 8th ship. | 0345/0369; 0321's "8 -> 7". | `fleet_ship_top` 7 -> 8 (**H1**). Stores back in the hold: Q2 (**H2**). |
| 35 | "The FLEET will have a crew slot too – min and max. You will need to fill up your crew to min to operate fully." | Per class `crew_required`, `crew_max` (002:155-156); hire `cmd.do_hire` 007:632. Live. | A fleet total shown as one min / max. | Nothing. | Client: the fleet's summed min and max (**H1** client). |
| 36 | "If you meet a storm, or other HAPPENINGs at sea, your crewmates will die." | `voyage.hazard_roll` 035:292: STORM, CALM, PIRATES. A storm costs hull and time only (`storm_hull_lost` 154:464). Crew die only in fights (`raid_crew_lost` 027:167). | Crew deaths in a storm. | Nothing. | One hunk on `voyage.settle`'s STORM arm (**H3**). |
| 37 | "These Happenings may lose your trade goods too (1~2% per happening)." | None. 0501 cargo-at-cost (open) records the cost of lost cargo. | The loss. | Nothing. | Same hunk: 1 to 2 % of each good, booked through 0501's record (**H3**). |
| 38 | "IF NO FOOD or WATER is given, crews may cause RIOT – causing dramatic decrease in crew numbers." | Today an empty store ends the voyage: `voyage.forced_home` 279:267 (ALL cargo lost, hull damage, docked at the nearest city; row 223, the owner's earlier order). `SHORT_RATIONS` raises wages. | The riot. | Row 223's forced home. | Question Q2b folded into Q2: riot replaces the total loss (**H3**). |
| 39 | "IF crew numbers are below MIN, the ship speed will decrease dramatically." | x0.70 flat (`crew_short_speed_mult` 001:172, in `voyage.ship_speed_parts` 454:133). Live. | "Dramatically". | Nothing. | Speed scales with crew / min, floor 0.30 (**H3**); frozen at departure as today. |
| 43 | "The PASSIVE METHOD should also require you to make provision, crew up in the setting. The provision will be spent more with the number of crews. Since Provision takes a cargo space ... choose the appropriate amount." | A job tops up stores by itself (`stores_topup` 150:91). Use per crew exists. 0500 fit-to-sail (open): a short-handed job waits. | Crew and stores as a job's settings. | Row 34's space. | Params `crew`, `days` on the job; the planner hires and provisions to them (**E1**, after H2). |

### The seas

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 40 | "The SEA will have names." | `public.sea_zones` 215:137, 64 named seas (`data/sea-zones.json`); the Seas page in the Codex. Data live; the gate dark. | Nothing. | Nothing. | None. |
| 41 | "Some SEA will have higher level pirates, and higher expedition sites." | Hazard per sea (`hazard_base`); pirate strength per sea: not verified. | Site level by sea. | Nothing. | F1's sites carry their sea's rank; pirates: read before building F2. |
| 42 | "Some seas will require wave resistance, etc. ... gear up your ship overall ... If you do not meet the requirement, you will not be able to pass into that sea." | BUILT in 0215/0396: `ship_classes.wave`, gear `item_effects` stat `wave`, `public.fleet_wave` 215:640, level `public.title_level` 215:652, the one rule `public.sea_refusal` 215:677, the gatherer `public.sea_gate` 215:700, `E_SEA_CLOSED`. `sea_conditions_bite` was lit 2026-11-13 and set false 2026-11-23. | Nothing in code. | **Row 369** ("remove sea limits entirely"); hq-corp 0500 `area-tiers` (a second gate, by miles from home). | Re-light the existing gate (**S2**). `area-tiers` is not built. |
| 44 | "The whole cities should be reachable, but the game should [be cut] into parts – real life basis, and will add restriction." | 64 zones cut on real seas. Today's table gives nearly every far sea a LEVEL ask (title 2 to 8): a new company cannot enter the Korea Strait until level 7. | A proof that every city is reachable by a way round. | The table's level ladder against "the whole cities should be reachable" (Q1). | **S1**: data change and a reachability proof. |
| 45 | "From Brazil to Korea, you can cross the [Pacific], but that route will be sealed (requiring levels, and wave resistance), which you will have to go around through INDIA to reach KOREA." | North and South Pacific crossings ask level 8, wave 70 (the highest). The way round (the Cape 44, the Indian Ocean crossing 40) also asks levels 5 to 7. | Nothing for the Pacific. | Same as 44. | S1. |
| 46 | "One can go over Russia [the Arctic] (north), or Antarctica (south) as a shortcut but these two routes will require significant levels in Sailing and ship gear." | Arctic Ocean: level 3, wave **20** (low). The far south: "The South Pacific and the Drake Passage" 70; "The Roaring Forties" 44. Whether the raster lets a ship sail north of Russia from the Barents Sea to the Pacific: **not verified**. No skill is named Sailing (NAVIGATION and SEAMANSHIP exist). | The Arctic as a sealed shortcut; a far-south zone. | The Arctic's low ask; the harbour LNG lies in the Arctic zone. | S1: an Arctic passage zone east of the Barents Sea and a Southern zone, both at the top ask; "Sailing" read as the level the gate already uses. |
| 47 | "Design the game so that you can reach all the places of the world, but due to restrictions of the sea, you will have to go around." | `voyage.reach_passage` 188:134 already avoids shut seas when the gate is lit (396). The client's pathfinder (`src/lib/sea/pathfind.ts`) does not avoid a shut zone (helper's reading). | The pathfinder going round. | Nothing. | S2: `findPath` takes the shut zones as closed water. |
| 48 | "For both Active and Passive methods, when you choose the final destination ... the game itself will choose appropriate paths ... by visiting multiple cities for provision + crew, fix ships etc." | 0494 (live): a job sails harbour by harbour when a leg is too long or stores run short; the sail tops up stores. Active: `src/domain/passage/chain.ts`. #864: one press to Repair or Hire. 0500 fit-to-sail (open): an unfit job waits. | Stops that hire and repair by themselves. | Nothing. | `fleet_job_legs` 494:240 adds HIRE and REPAIR at a stop when 0500's `fleet_unfit` says so (**P1**). |

---

## 2. Questions for the owner (six; one line answers each)

Each has the default I build if there is no answer.

| # | Question | Default |
|---|---|---|
| Q1 | **Do ordinary seas ask a level, or only the sealed oceans?** Today's table asks level 7 for Korea's own sea. Your spec says every city is reachable and only the Pacific, the Arctic and the far south are sealed. On 2026-11-23 you said "i can't send ships because of restriction". | **Only the three sealed oceans ask a level.** Every other sea asks wave resistance alone (gear and hull), so the way round is always open to a ship that is fit for it. |
| Q2 | **Do food and water go back into the cargo hold, and does a riot replace "lose all cargo"?** Stores have had their own space since 2026-11-13 (row 221), and an empty store today ends the voyage with all cargo lost (row 223). | **Yes to both.** Stores share the hold again; no food or water means a riot (crew lost each day), and the total loss happens only when no crew is left. |
| Q3 | **What level opens the PASSIVE method?** Every company can set a repeating job today, from its first minute. | **Trading level 3 for a repeating job; price ranges at level 5.** Companies that exist today keep it for ever. |
| Q4 | **How is a second HQ opened?** The spec says you switch between cities that have your HQ; it does not say how a city gets one. | **Bought in a city where one of your fleets is docked, paid to that city; one more HQ at Rank 3, 5, 7, 9.** |
| Q5 | **"300~500 % more": 3 to 5 times the normal price, or 4 to 6 times?** | **3 to 5 times**, paid by that city's purse, up to a daily quantity. |
| Q6 | **"find architect": is this an artifact (a thing found and carried home)?** | **Yes: a find**, carried in the hold to your capital and reported there for gold and Reputation. |

Decided by default, not asked: Europe-only applies to NEW companies; a second rename is refused until payment is decided; the Trade tab
stays and `desk-into-hq` is not merged; `area-tiers` is not built; 8 ships is the top, the ladder to it stays; "Sailing" means the level
the sea gate reads; fog hides on the client first.

---

## 3. The slices

Every slice is dark behind its own switch unless it is read-only. Migration numbers are the order after 0501; a slice takes the next
free number when it is built. Client slices own only the files named.

| # | Slice | Kind | Owns | The player sees | Proof | Database cost |
|---|---|---|---|---|---|---|
| 0502 | **A1 `company-name`** | migration + client | `public.company_name_refusal`, `cmd.rename_company`, `players.renames`; one hunk on `cmd.found_house`; `SignTheBook.tsx`, `ProfileScreen.tsx`, `dict/found.ts` | A name refused with the reason; "Rename (1 free)" on Profile | Probe: "LISBON", "Pepper", a taken name in other case and "A*B" are refused; rename 1 passes, rename 2 refused | One int column (no rewrite: default 0). One unique index on `lower(company_name)` over players: built only if no two live names collide (before-check); else the rule is in the function alone |
| client | **C1 `trade-tab-fleet-map`** | client | `features/command/buysell/*`, `plans/TradeMap.tsx`, `FleetStrip.tsx`, `dict/trade.ts` | Trade tab: the fleet's name at the top (press to change), a map of places only, a press on a place shows its prices | Headless drive at 390 and 1440: change fleet, press a city, read a price; no merchant drawn | None |
| 0503 | **G1 `chart-fog`** (`chart_fog_enabled`) | migration + client | `public.company_chart`, `public.chart_mark`, `world.chart()`; one hunk in `voyage.settle` beside `logbook_arrival`; `src/chart/FogLayer.tsx` | A black map; a circle of sight round each fleet; grey where she has been; grey cities can be pressed to sail there | Probe voyage marks only the cells of its path; a merchant writes nothing; dark = nothing written, chart as before | See "The fog" below: one row a company, at most 8.1 KB, one update per arrival |
| 0504 | **H1 `fleet-of-eight`** | migration (knob) + client | `fleet_ship_top` 7 -> 8; fleet row min / max crew | "8" as the top of fleet room; crew 34 / 20-60 | `fleet_room_caps` serves 8 | None. Load: at most one more hull a fleet for a company that buys it |
| 0505 | **A2 `europe-start`** (`europe_start_enabled`) | migration + client | one hunk on `public.nation_joinable`; `NationPicker` | The start sheet offers European countries only | Probe founding under Japan refused; `cmd.change_country` unchanged; no existing row touched | None |
| 0506 | **B1 `income-header`** | migration (read only) + client | `group` in `company_rate_line`; `corp/HqCompany.tsx`, `dict/hq.ts` | Under the name: Active +x/h, Passive +y/h, Maintenance -z/h; HQ headings Fleets, Expeditions, Investments | Sum of the three = `net_per_hour` on the same rows | None (STABLE read) |
| 0507 | **B2 `upkeep`** (`upkeep_enabled`) | migration | as hq-corp `upkeep-and-cuts`, unchanged | A Maintenance line that is real | hq-corp's 5 % proof | One ledger row a company an hour |
| 0508 | **B3 `hq-cities`** (`hq_cities_enabled`) | migration + client | `public.company_hqs`, `cmd.open_hq`; `CityScreen.tsx` switcher | The city name under the company name; a press lists her HQ cities; the screen changes | Probe opens a second HQ, pays the city, is listed; home is row 1 | One table, at most 5 rows a company; no cron |
| 0509 | **S1 `seas-sealed`** | migration (data, gate stays dark) | `data/sea-zones.json`, `sea_zones` rows, `sea_leg_asks` re-derived; `scripts/build-sea-legs.mjs` | Nothing yet (the Seas page shows the new asks) | For every harbour and every European capital, a chain exists that crosses none of the three sealed zones; a barca reaches every title-1 harbour as before | 64 rows updated; `sea_leg_asks` re-derived once (about 61,752 rows: off the beat, stated in the PR, gate read first) |
| 0510 | **S2 `seas-relit`** | migration + client, then the light | `sea_conditions_light`'s guard gains the reachability count; `src/lib/sea/pathfind.ts` (shut zones are closed water); the wall words | Sealed oceans shaded; a course goes round; a wall names what is short | The existing lit proofs (0396, 0398, 0402); a probe fleet beyond a gate sails home | None new |
| 0511 | **H2 `stores-in-hold`** | migration | `ship_stores_separate` and its light step | Food and water take hold space | A fleet over its hold keeps what she carries and may sail | None |
| 0512 | **H3 `happenings-bite`** (`happenings_bite`) | migration | hunks on `voyage.settle` (STORM, CALM arms), `voyage.ship_speed_parts`; riot in place of `forced_home` | Storm: "3 crew lost, 1.4 % cargo lost"; riot; slow when short-handed | Probe storm loses 1-2 % of each good and crew by the knob; no food: crew falls daily | None new: the fields ride the `voyage_events` row already written each sea-day |
| 0513 | **P1 `stops-mend`** | migration | `fleet_job_legs`, `fleet_job_plan` | A job that repairs and hires at a stop by itself | Probe job with a damaged hull repairs at the next yard and goes on | None new |
| 0514 | **E1 `passive-settings`** (`passive_gate_enabled`) | migration + client | `fleet_job_set_for`, `fleet_job_plan`; `AssignSheet.tsx` | Buy under / Sell over / Crew / Days on a job; a locked row with the level it needs | Out-of-range job waits and says why; an old company is not locked | One boolean a company (`players.passive_kept`, no rewrite) |
| 0515 | **D1 `reputation-by-rate`** | migration | `reputation_sale`, the request credit, `courier_settle` | Reputation on the sell face before the press | Two probe sales, same profit, the higher rate earns more; caps hold | None |
| 0516 | **D2 `premium-goods`** (`premium_goods_enabled`) | migration + client | three columns on `goods`; one hunk on `world.quote_priced`; `PortForge.tsx` | "Premium: sells at Venice, x4" on the recipe and the good | Probe sale at the linked city pays x3 to x5 from its purse up to the day's units; elsewhere the normal price; purse never negative | No table; a daily counter in the city's existing day row (to be read: where `city_wants` keeps its own) |
| 0517 | **F1 `expeditions`** (`expeditions_enabled`) | migration + client | `public.expedition_sites` (data), job kind `explore`, the report at the capital | Assign > Expedition: a site, the trip, the reward; "Report" at the capital | Probe finds, carries, reports; the capital's purse falls by the reward | Sites: bounded data (about 100 rows). One `logbook` row a company a site, first time only |
| 0518 | **F2 `hunt`** (`hunt_enabled`) | migration + client | job kind `hunt`; `rep_battle` hook | Assign > Combat: a sea, the pirates' level, the odds | Probe win pays loot (moved) and Reputation | None new |
| later | **G2 `fog-served`** | migration | the price reads take the chart | Prices only for cities in sight or with an HQ | to be designed | None |

### The fog, within the budget

- **One row a company**, players only (merchants keep none): `public.company_chart(player_id primary key, cells bytea, updated_at)`.
  `cells` is a bitmap of the world in 1 degree squares: 360 x 180 = 64,800 bits = **8,100 bytes at most**, mostly zeros (it compresses).
  `-- retention: none, bounded by one row a company of a fixed size`.
- **Written once per arrival, never per step.** `voyage.settle`'s arrival already calls `public.logbook_arrival` (478); the same hunk
  calls `public.chart_mark(player, voyage)`. It walks the voyage's stored path (`voyages.path`), sets the bits within the sight radius
  frozen at departure, and writes one UPDATE. A diverted or ended voyage marks the part sailed.
- **While she sails, nothing is written.** The client already holds the voyage row; it draws the sight circle and the fresh trail
  from the path and the clock, as it draws the ship (`voyage.position` is computed on read).
- **Visited cities are not stored again:** grey cities are `logbook` kind `harbour` (478), the authority that exists.
- **Sight:** `chart_sight_nm` (150) plus `chart_sight_per_level` (50) a NAVIGATION level, read through `public.player_skill_bonus`
  (a new effect kind on the existing skill; no new skill).
- **Cost:** rows written a minute = player arrivals a minute (well under 1 today; about 19 companies by the docs). 1,000 companies at the
  full size are about 8 MB. No cron, no index beyond the key.
- **Honest limit:** G1 hides on the client. A player reading the network sees every price. G2 closes that if the owner wants secrecy.

### What is kept, changed, thrown away

| Work | Verdict | Why |
|---|---|---|
| 0497 wreck-can-sell (#868) | **Kept** | A stranded company can act; needed more once riots and storms cost crew and cargo. |
| 0498 jobs-never-lose (#865) | **Kept, built on** | Its WAIT state is the spec's "stop or continue based on your settings" (E1). |
| 0499 near-round (#866) | **Kept** | A passive job near home; will respect the sea gate through `reach_passage`. |
| 0500 fit-to-sail (#867) | **Kept, built on** | `fleet_unfit` is what P1's automatic repair and hire stops read. |
| 0501 cargo-at-cost | **Kept, built on** | Its lost-cargo record is where H3 books the 1-2 %. |
| #862 pages-stand-still-2 | **Kept** | Client quality; touches no deleted screen (not checked file by file). |
| `desk-into-hq` (H3 / S3) | **Not merged; thrown away as a whole** | It deletes the Trade tab, FleetPicker and FleetStrip, which the spec keeps. Its HQ-side parts may be cherry-picked later; not sorted here. |
| simplify S4 `tabs-shrink`; hq-corp F1, F5, C4 | **Reversed** | Trade stays on the bar; `?port=` stays (it is the HQ city switch). |
| hq-corp 0500 `area-tiers`, `area_refusal` | **Thrown away** | A second answer to "is this place open". The sea gate is the one authority. |
| hq-corp `upkeep-and-cuts`, hourly dividends, `company_rate`, `workers`, crew slots | **Kept** | They are the spec's income, maintenance and managing. |
| civ-layer K1-K5 | **Kept, after this plan** | Not named by the spec, not contradicted. |
| Standing routes (0092-0096) | **Still to be folded** (hq-corp 0493) | Their `price_limit` idea moves to the job (E1); no second automation. |
| Sea conditions 0215-0404 | **Kept: the base of S1, S2** | Built, proven, once lit. |

---

## 4. The first three, started now without an answer

Chosen so that no live company is stranded and no answer is needed.

1. **A1 `company-name` (0502).** The spec is exact. It changes nothing for a company that exists: old names stay, even ones the new
   rule would refuse. No gate, no sea, no coin.
2. **C1 `trade-tab-fleet-map` (client).** The Trade tab exists; this adds the fleet name press and the map of places. No server change.
   It also settles in code that `desk-into-hq` is not merged.
3. **G1 `chart-fog` (0503), dark.** Fog hides; it never refuses a sail, so it cannot trap anyone. Before it is lit, every live
   company's chart is filled from where she has already been (section 5), so nobody wakes to a black world.

Built in parallel (three writers, files do not overlap). S1 can also be prepared, since its data is dark, but its numbers wait for Q1.
**Not started without an answer:** S2 (the light), H2 and H3 (stores and riot), E1's gate, B3, D2, F1.

**The three safety rules, where they are kept:**
- *A live company can be anywhere.* Nothing in the first three reads where a fleet is.
- *A sea gate never traps a fleet already beyond it.* The existing rule `public.sea_floor` (396:171): a fleet is judged as holding at
  least what the sea she lies in asks, so her own waters and the way home never refuse her. S2 lights only through
  `public.sea_conditions_light()` (398:161), whose guard refuses while any player route has a closing leg; S2 adds the count of player
  fleets lying in a sealed zone to that guard's print.
- *Existing companies keep everything.* No slice deletes a ship, a name, a country, a job, a share or a shed.

---

## 5. Live players under each new rule

| Rule | What happens to a company that exists |
|---|---|
| Name rules | Keeps her name. The new reading applies to founding and to renames. Two old names equal but for case both stay; the case-blind index is built only if none collide. |
| Rename count | Starts at 0: everyone has the one free rename. |
| Europe only | Keeps her country and home, wherever it is. `cmd.change_country` is unchanged. |
| HQ cities | Row 1 of `company_hqs` is written from `home_port_of` for every company at the slice. Sheds in other cities stay as "Stored elsewhere". |
| Income header, upkeep | The header is a read. Upkeep keeps hq-corp's rules: never under a 10,000 purse, unpaid is waived, not owed. |
| Passive gate | Every company founded before the light gets `passive_kept`: her jobs run on and she may set new ones. |
| Price ranges | Jobs without a range behave as today. |
| Reputation by rate | Balances are not recomputed; only later sales use the new rule. |
| Premium goods | Stock and Storage untouched; a made good that becomes premium simply pays more at its city. |
| Fog | At the slice, each company's chart is marked once from her stored voyages' paths and a sight circle round every harbour in her logbook and her arrival events (how far back voyages and events are kept: **not verified**; a company with no history gets her home waters). Then lit. |
| 8 ships | A cap that only rises. |
| Stores in the hold | A ship whose cargo and stores then exceed her hold keeps both and may sail; she cannot buy more until she is under. Lit in its own window with the 30-minute check. |
| Storm deaths, cargo loss, riot | Apply to voyages that DEPART after the light (the figures are frozen at departure, as speed is). A voyage at sea finishes under the old rule. |
| Speed below min crew | Frozen at departure, so the same. |
| Seas sealed | `sea_floor` keeps every fleet free to leave where she lies and to sail home. A job with a leg that closes waits with the wall's words (0500's wait), it is not cancelled. The light's guard prints each affected company first; the lead tells the owner the count before lighting. |
| Automatic stops | Only adds orders to a job's plan; a job without need plans as today. |
| Expeditions, hunt | New job kinds; nothing existing changes. Land parties stay as they are, under the Expeditions heading. |

---

## 6. The addition (trading and tax), same day

Source: the "Addition" block of `docs/design/owner-spec-2026-11-25.md`. Written in a second pass of 35 minutes; no production read.
Lines I opened myself here: 0022 header, 205-222, 228-246, 283-300, 318-336; 0122:24, 103-105, 402-407; 0147:18-41, 101, 128-146;
0174 and 0212 headers; 0211:8-22; 0488:190-206. Knob values are as SEEDED in those files; 0024 re-tuned three bargain knobs and I did
not re-read their present values.

### 6.1 Sentence by sentence

| # | The owner's sentence | Today | Missing | Contradicts | Smallest change |
|---|---|---|---|---|---|
| 49 | "Trade goods price will grow in accordance with the distance between the two cities." | BUILT and live: the haul, `world.haul_at` (0173), stored per market row (`port_goods.haul`), multiplied into the price by `world.mid_from_terms`. `haul_max` 3 (0212): x1.003 at 1,000 nm, x1.07 at 5,000, x1.34 at 10,000, x2 from 14,500. Since 0491 the miles are the sailed miles. | Nothing. It is nearly flat near home by the owner's own earlier target (a far route 1.3 to 1.5 times a near one). | Nothing. | None. The sale face (0490) may show the distance share; not a slice. |
| 50 | "You can bargain 10 times for price reduction or increase when selling." | BUILT on the server and still there: `cmd.haggle`, `world.haggle_state`, `public.haggle_odds` 022:283, `public.haggle_concession`, one row `public.haggle_daily` (company, city, good, day; re-keyed to the real day by 0317). Still read by the price (`world.spread_effective`, last re-cut 0256/0488). 3 attempts a day. The CLIENT lost it: the haggle UI sat in the desk tray, unreachable since 2026-11-23 (simplify "Removed", `TRADE_ON_DESK`). | 10 attempts; the press on the Trade tab. | simplify's "Removed: haggle UI"; the owner's open "haggling back?" is now answered yes. | `haggle_attempts_per_day` 3 -> 10; the press back on the Trade tab (**T2**). |
| 51 | "The success rate will decrease every time you attempt." | Odds = (0.45 + HAGGLING skill) x (1 - 0.25 x FAILS today), cap 0.85 (022:296-300). It falls only after a failure. | Falling on every attempt. | The 0022 curve. | One hunk in `haggle_odds`: the factor is by attempts, not fails (**T2**). |
| 52 | "Each time you attempt will create 5 % of total price reduction." | A win shaves a share of the city's SPREAD (seeded 15 % of a 2-6 % spread, about 0.3-0.5 % of the price); 0022 forbids touching the price itself. | 5 % of the total. | 0022's first rule ("never the world's price"); the spread floor. | The concession becomes a share of the TOTAL of her own quote, in the one quote authority (`world.quote_terms` 169:484). The published price and the mid stay untouched (**T2**). |
| 53 | "This will also be enhanced by captains, and skills (level) – I am thinking NEGOTIATION skill." | The skill exists as HAGGLING (0016; effect `SPREAD` through `public.player_skill_bonus`), already added to the odds. A captain's PURSER bonus shaves the spread (`fleet_officer_bonus`), not the odds. | The captain in the odds; the word Negotiation. | Nothing. | The PURSER bonus is added to the odds; the dict shows HAGGLING as "Negotiation". No second skill (**T2**). |
| 54 | "Each city will have its own tax, with 0 %~30 %." | Each city has its own rate: `ports.tax_rate` x `profit_tax_scale` 5, capped at `tax_rate_max` **0.20** (`world.tax_rate`, 122:402, re-cut 147:128). A mayor sets it within 0 to the cap, once a day (`cmd.set_tax` 147:188). | 30. | The 0.20 cap; the mayor's 0-20. | `tax_rate_max` 0.20 -> 0.30, with every city's present rate held where it is (**T1**). |
| 55 | "Your own country or the city that has your HQ will provide less tax." | Own country: a company of the country that HOLDS the city pays half (`influence_citizen_tax_cut` 0.5, 147:146). Stance between countries scales the dock fee (`country_factor`, 488:200); whether it also scales the tax today: **not verified**. HQ city: nothing for the tax (the dock fee has a home factor, `nation_fee_factor`). | The HQ city. | Nothing. | In `world.tax_rate`: the same half where the city is her home (`home_port_of`; her HQ cities once B3 exists). The better of the two, never both (**T1**). |
| 56 | "TAX is only paid when a profit is made, or when buying." | On a profit only, at the sale, to the city's purse (`public.profit_tax` -> `profit_tax_at` 488:27). A BUY pays no tax since 0122 turned the old turnover tax into a profit tax. | A tax when buying. | 0122. Near trade: see 6.3. | A buy tax in the same quote authority, to the city's purse (**T3**, dark, Q7). |

### 6.2 What ten successes do

**Added, not compounded.** Each success moves the price by 5 % of her FIRST quoted total, so ten are 50 %.
- Added: buying 100 -> 50 (-50 %); selling 100 -> 150 (+50 %).
- Compounded: buying 100 x 0.95^10 = 59.9 (-40.1 %); selling 100 x 1.05^10 = 162.9 (+62.9 %).
- Why added: the owner's words are "5 % of total price" each time; both sides stay equal (compounding gives the seller more than the
  buyer); the row stores one number (wins x 0.05; the column `concession` already holds a fraction up to 1); the face shows "-15 %".

**Both sides at once.** A round trip that costs C and sells for S, with b wins buying and s wins selling, earns
S x (1 + 0.05 s) - C x (1 - 0.05 b). With S = 1.10 C (a 10 % trade): no bargain 0.10 C; one win each side 0.205 C (double);
ten each 1.15 C (11.5 times). So the success curve, not the 5 %, is the whole balance.

**The curve I propose.** Chance on attempt n = p1 x 0.5^(n-1); it falls on EVERY attempt, won or lost.
p1 = 0.25 + Negotiation + captain, never above 0.50.

| | p1 | Expected wins in 10 | Expected move a side | At least one win | All ten |
|---|---|---|---|---|---|
| New company | 0.25 | 0.50 | **2.5 %** | 42 % | under 1 in 10^19 |
| Best skill and captain | 0.50 | 1.00 | **5.0 %** | 71 % | under 1 in 10^16 |

(Sum of p1 x 0.5^(n-1) over ten attempts = p1 x 1.998.) Nearly all the value is in the first three attempts; ten are allowed, as the
owner says, and the long tail is a lottery ticket. For comparison p1 0.50 with a factor of 0.70 gives 1.62 wins (8.1 % a side): too much.

**The same-city leak, which must be closed in T2.** A city's spread is 2 to 6 %. Two wins buying (-10 %) already put her price under
what the same city pays back, so buy-and-sell on one quay would take coin from the purse with no voyage. Rule: the day's row is one
side only (it holds `last_side` already), and a good bought in a city sells in that city, that day, for no more than was paid.

**Abuse, and what already stops it.**
- *Bargain, cancel, retry:* the attempt count is written BEFORE the roll and the roll is keyed on (company, day, city, good, attempt)
  (022:541 and the table's comment). A retry is the next attempt, already paid for. Kept as it is.
- *Many small buys:* a bargain is spent by the one trade that uses it (0022). Kept.
- *Many fleets:* the row is the company's, not the fleet's. Kept.
- *Volume:* ten attempts a good, a city, a day; the daily trade cap (`world.daily_cap_remaining`) bounds the units a bargain can carry.
- *Passive orders:* **may not bargain** by default (Q8): a job that bargained would turn the expected 2.5-5 % into a rate on every
  automated ton.

### 6.3 What it does to money

**City purses (closed economy).** A bargain is paid by the city: it receives less for what it sells and pays more for what it buys.
Per 100,000 of a player's turnover in a city, the purse gives up 2,500 (new company) to 5,000 (best) on average. Nothing is minted;
the empty-purse rule (the bid reads the live purse, 0174) still shrinks a sale the city cannot pay. Tax returns part: a buy tax of
1.5 % returns 1,500 per 100,000 bought, and the profit tax takes its share of the bargained gain. With about 19 companies this is
small against the purses; it is a per-company rate and grows with players, so `haggle_base_success` stays the knob to watch.

**Near trade.** Measured income today: near Repeat 148 to 3,328 /h; Trade nearby 2,700 to 19,700 /h at 40,000 coin.
For ONE round trip of a full 40,000 purse (buy 40,000, sell about the same):

| | Active, new company | Active, best | Passive job |
|---|---|---|---|
| Bargain, both sides (2.5 % / 5 % of about 80,000) | +2,000 | +4,000 | 0 |
| Buy tax at 1.5 % of 40,000 (half at home) | -600 (-300) | -600 (-300) | -600 (-300) |
| Profit tax at 15 % on the bargained gain | -300 | -600 | 0 |
| Net change a round trip | **about +1,100** | **about +2,800** | **-600** |

How many round trips an hour a near trade makes is **not measured here**. At two an hour an active new company gains about 2,200 /h
(most of Trade nearby's low end again) and a passive near Repeat loses 1,200 /h, which is more than its low end earns (148 /h).
So: bargaining roughly doubles the weakest active near trade, and **any buy tax on turnover sinks the weakest passive jobs**;
with 0498 jobs-never-lose they would wait instead of sailing. That is why T3 is dark and asked (Q7).

**Tick and row cost.** No tick, no cron. An attempt is one UPDATE of the one row a (company, city, good, day); ten attempts are ten
updates of the same row. A hand trade of 5 goods bargained fully on both sides is at most 100 small updates. The table needs a
retention line when touched: rows older than yesterday are deleted (whether a job already does this: **not verified**).

### 6.4 Slices (numbers after 0504; the rows of section 3 from 0505 on each move down three)

| # | Slice | Owns | The player sees | Proof | Database cost |
|---|---|---|---|---|---|
| 0505 | **T1 `tax-to-thirty`** | `tax_rate_max` 0.20 -> 0.30; one statement that holds every city at today's served rate; one hunk in `world.tax_rate` (home city pays the citizen's half) | Nothing moves at deploy. A mayor may set up to 30 %; "Home: half tax" on the sale face | Before and after: `world.tax_rate` equal for every harbour; a probe sale at her home pays half; never both halves | A one-off update of `ports` rows whose rate x 5 is over 0.20 (count read before the PR) |
| 0506 | **T2 `bargain-ten`** (`bargain_total_enabled`) | hunks in `haggle_odds`, `cmd.haggle`, `world.quote_terms`, `cmd.do_buy`, `cmd.do_sell`; the three knobs; the Trade tab's Bargain press (C1's files), the sale face line | "Bargain 3 / 10 · 6 % chance · -10 %" beside Buy and Sell; the won price in the face before the press | Dark: every quote is the pre-image. Lit, on a probe: a win moves her total 5 % of the first quote and nobody else's price; attempt 11 refused; the same-city resale pays no more than was paid; a second trade gets no bargain; the city's purse never goes negative | No table. Updates of the existing row only |
| 0507 | **T3 `buy-tax`** (`buy_tax_enabled`) | one term in `world.quote_terms` (buy side), paid to the city's purse as kind TAX; the buy face | "Tax 1.5 %" on the buy face before the press | Dark: buys as today. Lit: the purse gains exactly the tax; home pays half; a job's quoted profit (0498) counts it | Meant to ride the buy's own ledger row (to be confirmed on `cmd.do_buy`) |

T1 can start now. T2 can be built dark now; its light is a live-play change with the 30-minute check and the purse totals read before
and after. T3 waits for Q7.

**Live players.** T1: nobody's rate changes; the home half only lowers. T2: an open bargain of the old kind (a share of the spread) is
honoured for its day, then the row means the new thing; nobody loses a won bargain. T3: cargo already bought is not taxed again.

### 6.5 Two questions for the owner

| # | Question | Default |
|---|---|---|
| Q7 | **How big is the tax when BUYING?** The city's full rate (0-30 %) on every purchase would cost more than a near trade earns. | **One tenth of the city's rate (0 to 3 %)**, half in your own country or HQ city; not lit until you have seen its effect on near trade. |
| Q8 | **May a PASSIVE order bargain?** | **No.** Bargaining is the active trader's edge; a repeating job trades at the listed price. |

Not verified in this section: the present values of the bargain knobs after 0024; whether stance scales the profit tax; whether the
distance premium is still paid from outside the city's purse (0174) under the closed economy (0233 may have closed it); round trips an
hour of a near trade; how many cities have a rate x 5 over 0.20; the retention of `haggle_daily`.

---

## What I did not verify

- Any switch on production; any live row. All states are as written in the docs.
- Whether the sea raster lets a ship pass north of Russia or south of Cape Horn outside the Strait of Magellan; S1 must measure it
  (and the no-land and straits audits must pass: CLAUDE.md).
- Pirate strength per sea; the retention of `voyages` and `events`; which hunks last re-cut `passage_gate`, `invest_for`, `tick_contracts`.
- Whether `TradeMap.tsx` draws merchants; which `desk-into-hq` commits are worth keeping.
- The 300-500 % premium against real city purses: D2 must measure a city's purse and set the daily units before it is lit.
- Most file:line references (helpers' reports), as said at the top.
