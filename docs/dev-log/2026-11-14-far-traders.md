# 2026-11-14: far traders reach the far harbours (0404, slice S4)

Owner rows 166 and 324. Design: `docs/SEA_CONDITIONS_AND_REGIONS.md` sections 4, 6 (row S4), 10.6 and the new section 12. The seas are lit for players and
merchants, so this is live play. **Nothing here is deployed by this work, and nothing was read on prod.**

## The gap

Since the merchants' sea light a merchant sails only the seas her hull holds. Every merchant hull was of size 1 to 3 (wave 12 to 39). The harbours behind
an ocean leg have no house of their own, so they lost every merchant call. Measured again today on the cached world at head 0403, lit, one planning pass
by the real planner (`sim.mjs --name=20260818000403`): 12 harbours lose every call, 226 of 237 harbours are still called at, 2,891 stops of 3,302.

## What 0404 does

- **24 merchant houses, one hull each: 20 of size 4 and 4 of size 5**, the count the design gave. Founded through `public.npc_found`, the same way
  as the 821 crown merchants (0097, 0105) and the pirate merchants (0341).
- **Homed at the far harbours themselves** (15 harbours; the nine that had the most calls get a second house of another flag).
- **Hulls that exist** (none new): `taforeia` (Portugal), `retour` (Netherlands), `nao` (Spain), `hourque` (France), size 4, trade, wave 51; `indiaman`
  (England) and `naucarr` (Portugal), size 5, trade, wave 63. Each gets one merchant loadout (`public.npc_loadouts`, `data/npc-loadouts.json`): two suits of
  sails, a crow's nest, deal planking (+3) and a sheet anchor (+3). A size-4 hull reads 57, a size-5 hull 69. 57 holds every sea but the open Pacific (70).
- **`npc_fleet_max` + 24** (861 to 885 on prod; 861 to 885 locally, where 837 were founded).
- Their first loop is home, the nearest remembered harbour her hull holds both ways, and home. The planner re-plans her at her first lap start.

| Home | Houses (flag, hull) | First loop | The loop the planner gave her in the simulation |
|---|---|---|---|
| AMB Ambon | Kamer Ambon (NLD retour) | AMB-SYD | AMB-BND-WLG-BND |
| BND Banda Neira | Kamer Banda (NLD retour) | BND-DAR | BND-WLG |
| CPT Cape Town | Kaapse Kamer (NLD retour), Casa do Cabo (PRT taforeia) | CPT-CAL | CPT-COL, CPT-COL |
| DIL Dili | Casa de Timor (PRT taforeia), Kamer Timor (NLD retour) | DIL-DAR | DIL-AMB-SYD-AMB, twice |
| GAL Galle | Casa de Gale (PRT taforeia), Kamer Galle (NLD retour) | GAL-OLD | GAL-OLD-CPT-OLD, GAL-TER |
| HAG Hagatna | Casa de las Marianas (ESP nao) | HAG-MOK | HAG-SRT |
| HOB Hobart | Derwent Company (ENG indiaman) | HOB-WLG | HOB-WLG-BND-WLG |
| KOL Kollam | Casa de Coulão (PRT taforeia), Comptoir du Malabar (FRA hourque) | KOL-PLO | KOL-MLE-YEO-MLE, KOL-KOZ-JEJ-KOZ |
| MAK Makassar | Kamer Makassar (NLD retour), Casa de Macáçar (PRT taforeia) | MAK-JAK | MAK-BNT-BAR-BNT, twice |
| OLD Old Goa | Casa de Goa Velha (PRT taforeia), Carreira da Índia (PRT naucarr) | OLD-KOC | OLD-COL-NAM-COL, OLD-KOC-MAC-KOC |
| PLO Port Louis | Comptoir Port-Louis (FRA hourque) | PLO-KOL | PLO-KOC |
| STG St. George's | Somers Isles Company (ENG indiaman), Comptoir des Bermudes (FRA hourque) | STG-JAM | STG-ANG-NEW, twice |
| SYD Sydney | Port Jackson Company (ENG indiaman), Kamer Nieuw-Holland (NLD retour) | SYD-WLG | SYD-AMB, SYD-WLG-BND-WLG |
| TER Ternate | Casa de Ternate (PRT taforeia), Casa del Maluco (ESP nao) | TER-GUA | TER-GUA-MNG-GUA, TER-TID-MOG-TID |
| TID Tidore | Casa de Tidore (ESP nao) | TID-MAC | TID-MAC-KOC-MAC |

## Where the design did not fit, and what was decided

1. **Homes.** The design homed them at seven European yards. The planner plans a merchant from her loop's first stop, offers at most five near loops and
   six trade loops, and every one returns to that stop. A house homed at Lisbon calls at Ambon only if Ambon ranks among her six. A house homed at Ambon
   calls there every lap. So the homes are the far harbours.
2. **Port Royal gets no house.** Its legs ask wave 12; the sea does not close it. It is a pirate home: while the pirates bite, no merchant's planner offers
   a pirate home but her own (0341), and its merchants are the pirates' own, founded from the hoard. A crown house living there would break that rule.
   On the cached world (pirates dark) it keeps 2 calls before and after.
3. **Hulls.** The design named galeao (a fighting hull), retour, batavia, caracca. Built with trade hulls of each flag's own line; three of them
   (taforeia, nao, hourque) are 0366's cargo carriers, so proof 67's "no NPC is given a new class" now names that one exception.
4. **`npc_fleet_max`.** The design counted room for 24 under 861. The pirate merchants took berths since, so the ceiling rises by 24.
5. **The loadout spends hold** (the sheet anchor), against the note in `data/npc-loadouts.json`. Holding the ocean is what these houses are for.
6. **The assert.** The design asked "every harbour but Honolulu reachable by a house's fleet, by `sea_leg_asks`". Built: each house's own wave, her open
   loop from home, and proof 99. Honolulu stays players-only (no remembered leg reaches it).
7. French houses use the ink `eng` (there is no French ink among the six on the roster). Capital 40,000 (size 4) and 60,000 (size 5). Skills Navigation
   2 and Haggling 1. No officers.

## The simulation: calls at the 16 harbours (cached world, lit, every merchant planned once at her lap start by the real planner)

"Roster" is the loops as founded, before the pass. "0403" is after the pass without the far traders, "0404" with them.

| Harbour | Roster | 0403 | 0404 |
|---|---|---|---|
| AMB | 5 | 0 | 6 |
| BND | 4 | 0 | 5 |
| CPT | 17 | 0 | 3 |
| DIL | 9 | 6 | 8 |
| GAL | 11 | 2 | 4 |
| HAG | 8 | 0 | 1 |
| HOB | 4 | 0 | 1 |
| KOL | 9 | 0 | 2 |
| MAK | 10 | 0 | 2 |
| OLD | 8 | 0 | 4 |
| PLO | 8 | 0 | 1 |
| POR | 12 | 2 | 2 |
| STG | 15 | 0 | 2 |
| SYD | 10 | 0 | 4 |
| TER | 8 | 6 | 9 |
| TID | 4 | 4 | 7 |
| **the 16** | **142** | **20** | **61** |

| | 0403 | 0404 |
|---|---|---|
| Merchants planned | 837 | 861 |
| Harbours called at after the pass | 226 | 239 |
| Harbours that lose every call | 12 (AMB BND BNT CPT HAG HOB KOL MAK OLD PLO STG SYD) | 0 of those (see Darwin below) |
| Stops after the pass | 2,891 | 2,971 |
| Loops with a closed leg after | 0 | 0 |
| Laid up | 53 | 53 (none of the 24) |
| Plans that failed | 0 | 0 |
| Far traders that sail with a cargo to buy | | 24 of 24 |

- DIL, GAL, TER and TID kept some calls at 0403 (0401 opened their coasts); they were in the 16 at head 0400.
- Banten (BNT) lost its calls at 0403 and gets them back: the two Makassar houses sail by it.
- Darwin (DAR) is "lost" in the 0404 pass only because three far traders were FOUNDED sailing to it and the planner moved all three. It had no
  merchant call before S4 (it is not on the roster), so nothing is taken from it. It is one more harbour no merchant calls at; not fixed here.
- The traffic added is 80 stops in 2,891 (2.8 %), 41 of them at the 16 harbours. The 16 had 142 on the roster: this restores, it does not flood.

**Expected added laps.** 24 fleets on loops of about 1,000 to 9,000 nm. The existing size-3 houses close a lap of that length in about 2 to 12 real
hours, so expect 3 to 8 more laps an hour in all, against the 861 fleets sailing now (2.8 % more fleets). Not measured on prod.

## Cost

- **The file:** the 24 foundings take 320 to 390 ms on the cached world, the file under 1 s. Prod is 6 to 18 times slower: 2.5 to 7 s. The self-assert
  fails above 25 s; `statement_timeout` 30 s. The first cut took 30 s here and its own budget refused it: it asked `public.npc_known_legs` for every
  harbour a home has a leg to, to find the way back. This cut sails the same course back, as `npc_known_legs` itself remembers a leg both ways.
- **A lap start** (`cost.sql`, 60 merchants, lit, `public.npc_plan` alone): 0403: 278 and 267 ms mean (two runs); 0404: 269 ms. Loops on offer: 39 and 37 ms
  against 37 ms. No growth. The whole pass read 237 ms a plan at 0403 and 267 ms at 0404 on a machine doing other work; the dark arm of the same scene
  moved between 270 and 301 ms from run to run, so that difference is the machine's.
- The tender has 24 more fleets to tend (2.8 %).

## Where the gold comes from

Nowhere new. `public.npc_found` pays starting money through `public.founding_credit` (0234). Closed, as prod is, her country's capital pays from its
purse (`public.capital_pays`): Lisbon for 8 houses, Amsterdam 7, Seville 3, London 3, Marseille 3; a capital that is short calls its realm. Capital in
all: 1,040,000 d. (20 x 40,000 + 4 x 60,000), plus each house's tuition, which she pays at once to her home harbour. Hulls and gear are endowed, as every
merchant's are. The self-assert refuses the file if, closed, the 24 houses' ledger and the cities' flows that name them do not sum to nothing.
Proof 99 `FT_GOLD` founds one more far trader closed with the purses lit: her ledger and the cities' flows sum to 0 and `world.stats_now()`'s total is
the same before and after.

## Checks

- 0404 applies on the cached chain at head 0403 with its self-assert (file 420 ms, foundings 252 ms) and the world guard is green after it.
- Proof 99 (5 markers); proofs 91 to 98 after it; proofs 12 and 47 (the merchants', the pirate merchants'); proof 67, whose `MORE_SHIPS_NPC` now
  names the far traders' three cargo carriers as the one exception to "no NPC is given a class of 0366".
- `tests/rpc.surface.spec.ts`, `news.lint`, `duplication`, `harness.guard` (52 green); tsc, eslint, build.
- The simulation and the cost scene above. The rollback draft was not run.

## Prod checks (read-only; in the PR body in order)

`scripts/ops/harness/far-traders/before-0404.sql`, `legs-0404.sql`, `calls-0404.sql` before; `after-0404.sql` and `calls-0404.sql` after. Rollback
draft: `rollback-0404.sql` (the 24 fleets off the roster; nothing deleted from the books, no money moved).

## Not verified

- Nothing on prod: the remembered legs there are prod's own loops (re-planned since the light) plus `public.npc_courses`. If a home has no leg out and
  back that wave 57 holds, the file refuses itself and writes nothing; `legs-0404.sql` reads that first.
- That the five capitals can pay (`before-0404.sql` prints their purses). `capital_pays` calls the realm, then the richest harbour.
- The simulation is one planning pass at lap 0 on a static local market. What the planner gives the 24 on prod's market, and whether one is laid up
  there, is read by `after-0404.sql`.
- Prod time. Laps an hour is an estimate.
- Port Royal's calls on prod (the pirates' merchants): `calls-0404.sql` shows them.
