# SEA CONDITIONS AND REGIONS — far seas are earned by title and by the ships you sail

**Status: DESIGN, 2026-10-20. No code, no migration. Every number here was read from prod
(head 0211) read-only, or computed offline from a read-only export of prod, on 2026-10-20.**

**The owner's decisions (2026-10-20), binding:**
- Far seas are limited the way 대항해시대 오리진 does it: each sea has **entry conditions**, a
  **captain level** plus the **fleet-average wave resistance (내파)**. The ship class gives the stat;
  gear (anchors, planking and sheathing) adds to it. **Hard wall**: refused when a plan is written
  and again at departure; the map shades the closed seas. No damage-while-sailing penalty.
- Navigation's per-leg reach (0107 / 0188, the owner's own rule) **stays**. Both rules compose in
  the one passage gate.
- NPC merchants live under the **same rule** (option A), through the merchant planner's
  feasibility test. Small-ship houses drop far loops at their next review; carrack houses keep
  them; fleets at sea finish their trip.
- Everyone **starts in Europe**; regions unlock as the captain progresses (the sea conditions ARE
  the unlock); the **capital** can be moved later to a city in an unlocked region; the **hub**
  (buildings, resources) is a later design, with a clean seam kept here.
- **Law: ships never have to go "home" to act.** They trade and sail from whatever port they are
  docked at. The hub is the economic base, not a parking spot.

---

## 0. The answer in twelve lines

1. **One new table, `public.sea_zones`**, is the whole requirement: every named sea is a zone, and the
   five oceans are cut into a few zones each by latitude/longitude boxes (the North Atlantic is one
   raster sea from Lisbon to Newfoundland; it cannot be one requirement). Each zone has **a title**
   and **a wave resistance**. 61 zones, §2.
2. **Coastal seas ask any hull** (wave 0–16). **Crossings** ask a real ship: the Doldrums 24, the
   Atlantic 30, the Indian Ocean 40, the Cape 44, the Philippine Sea 50, the Tasman 56, the open
   Pacific 70. The **title** is what keeps a starter in Europe: title 1 home waters, 2 Macaronesia,
   3 Guinea and the Arctic, 4 the Americas, 5 the Cape and East Africa, 6 Arabia and India,
   7 the Far East, 8 the Pacific.
3. **The ship's stat is a new class column, `ship_classes.wave`, derived** from what the class already
   is (size, rig, role): barca 12, caravel 26, nau 39, galleon 51, Indiaman 63, carrack-of-state 75.
   **Gear adds through the existing `item_effects`** table (stat `wave`): anchors, sheet anchors,
   storm canvas, planking, sheathing, pumps, ballast, two refits. A full kit on a nau adds 28.
4. **The fleet's figure is the average** of her hulls' `world.ship_stat(ship, 'wave')`, in one new
   reading `public.fleet_wave(fleet)`. Mixed fleets are pulled down by their smallest hull, as in 오리진.
5. **The captain level is the title**, and the title is **derived**, never stored:
   `public.title_level(player)` = the lower of her Trading and Exploration levels
   (`player_progress`, 0069), capped at 11. The dead column `players.title_level` goes.
6. **One pure rule**, `public.sea_refusal(title, wave, zones[])`, says yes or names the first zone that
   refuses, with the four figures. **One gatherer**, `public.sea_gate(player, fleet, dest, course)`,
   finds the zones (the harbour's roadstead + the zones the course crosses) and asks the rule.
   `public.passage_gate` composes reach (0107/0188) + `sea_gate`; it gains the fleet and the course.
7. **Merchants**: `npc_feasible_legs` asks `sea_gate` for every known leg (their title is skipped; the
   wave is not); `npc_plan` marks a present loop with a closed leg unsailable, so it loses to any open
   loop at her next lap start. The sail door stays exempt for merchants, so a fleet at sea finishes.
8. **Measured on prod-shaped data**: 548 of 837 merchant loops cross water their fleet cannot hold
   (289 of 442 caravel loops, 94 of 123 barca loops, 88 of 167 nau loops). **0 houses are left without
   an open leg** from home. 120 of the 133 far harbours stay reachable by some house's open leg; **13
   are not** (the Spice Islands, Cape Town, Hawaii, Australia, Kollam, Port Louis) and get **20
   far-trader houses** with size-4 hulls (slice S4).
9. **Europe is enough to progress**: 82 harbours, 495 roster goods, 411 of 837 merchant homes, and
   15–43 % returns on single trades inside home waters (Lisbon→Hamburg cinnamon 16 %, Genoa→Rhodes
   velvet 33 %, London→Tangier felt hats 27 %). Title 8 needs ~122,500 d. of turnover and ~49 port
   calls; Europe has 82 harbours.
10. **Europe-only start**: `great_powers.starting` (PRT ESP ENG NLD FRA OTT); `cmd.found_house`
    refuses the four Asian powers with `E_FAR_POWER`; `cmd.change_country` keeps all ten.
11. **The capital**: `players.capital_port_id` (today: the country's capital), `cmd.move_capital(port)`
    for 20,000 d., once a week, to a harbour open to her title where one of her fleets is docked.
    Nothing physical moves. The hub reads `public.capital_of(player)` and nothing else — the seam.
12. **Six migration slices, five client slices**, each dark behind its own switch where it changes
    behaviour (`sea_conditions_bite`, `sea_conditions_bite_npc`), §6. **Seven questions** for the
    owner, each with a default, §7.

---

## 1. The concepts and where each one lives (NO_SPAGHETTI §7B: one authority each)

| Concept | Its ONE home | Who reads it | What it replaces or must never be copied into |
|---|---|---|---|
| **Which zone is this point of water in** | `public.sea_zone_at(lat, lon) → text`: `voyage.sea_at` (0040, the one raster read) then the first matching box in `public.sea_zones` for that sea; a sea with no boxes is its own zone | `sea_gate`, `course_zones`, `harbour_zone`, the map's shading asset generator | the client never recomputes it: it receives a zone raster asset built by the SAME generator (`scripts/build-sea-raster.mjs`) |
| **A zone's requirements** | `public.sea_zones (code, sea_id, name, title_min, wave_min, lat_min, lat_max, lon_min, lon_max, ord)` — data, authored in `data/sea-zones.json`, held by the world guard | `sea_refusal`, `world.sea_conditions()` | `seas.danger_level` is a THREAT tier (read by nothing, 0040); it is not a wave figure and is not reused for one |
| **A harbour's zone** | `public.harbour_zone(port) → text` = `sea_zone_at` at its **roadstead** (`sea_reaches.roadstead_lat/lon`, the water the sail door actually judges) | `sea_gate`, `reach_passage`, `sea_leg_asks` | NOT `ports.sea_id`: that authored label disagrees with the raster at 16 of 238 harbours (Bergen's roadstead is in the North Sea, Havana's in the Gulf of Mexico); hazards already key on the raster, so does this |
| **The zones a course crosses** | `public.course_zones(course jsonb) → text[]`: sample every segment of the polyline every `sea_sample_nm` (30 nm) and collect `sea_zone_at`; a sample on land (raster 0) is ignored | `sea_gate` (the door, the plan builder, the route save, the merchant planner) | **sampling only the vertices is wrong**: merchant courses average 7 vertices per leg and an Atlantic crossing hides between two of them (measured: vertex-only sampling missed the mid-Atlantic on 197 loops) |
| **A harbour pair's ask, without a course** | `public.sea_leg_asks (from_port, to_port, wave_min, title_min)` — 56,644 rows, DERIVED by the slice from the straight lat/lon line between the two roadsteads plus the destination's zone; re-derived and asserted whenever `sea_zones` changes | `voyage.reach_passage` (the desk's Dijkstra has distances, not courses) | one derivation function, materialised; never hand-edited |
| **The ship's wave resistance** | `ship_classes.wave int`, DERIVED: `12 × size + rig + role` (`class_profile.size`; rig square +3, mixed +1, lateen 0, oared −6; role explorer +2), asserted by the slice like 0107's region levels | `world.ship_stats` base list (one hunk: `('wave', c.wave)`), so `world.ship_stat(ship,'wave')` sums the gear exactly as it sums `armour` | no second formula anywhere; the generator `scripts/lib/world-derive.mjs` carries the same rule for the data file |
| **What gear adds** | `public.item_effects (item_code, 'wave', delta)` rows for the eight families below; the CHECK on `stat` gains `'wave'`; authored in `data/gear.json` by a (base type, grade) rule | `world.ship_stats` — already sums every mounted unit's effects, worn units through `worn_delta` (0158), perks and sets (0163) | nothing new reads fittings; the existing summation IS the gear bonus |
| **The fleet's figure** | `public.fleet_wave(fleet) → numeric` = `floor(avg(world.ship_stat(s.id,'wave')))` over her hulls; null for an empty fleet | `sea_gate`, `reach_passage`, `world.fleets()` (served per hull and per fleet), `npc_feasible_legs` | the client prints it; it never averages |
| **The captain level** | `public.title_level(player) → int` = `least(trading level, exploration level)` from `public.player_progress` (0069), capped `title_max` (11); **null for a merchant** (no title) | `sea_gate`, `reach_passage`, `world.player()`, `cmd.move_capital` | **`players.title_level` (0004, moved by nothing, served raw by `world.player()` 0014 and the merchant card 0096) is dropped**; both readers re-cut to the function. Title names: `public.title_names (level, name)`, one row each, served with the level |
| **The pure rule** | `public.sea_refusal(p_title int, p_wave numeric, p_zones text[]) → jsonb` (a `cmd.refusal` or null): over the zones in requirement order, the first with `title_min > p_title` (skipped when `p_title` is null) or `wave_min > p_wave` refuses `E_SEA_CLOSED` with figures `{zone, zone_name, needs_title, title, needs_wave, wave}` | `sea_gate`, `reach_passage` (figures computed once per board), `cmd.move_capital` (title only, wave null) | the only place the comparison is written |
| **The gatherer** | `public.sea_gate(p_player, p_fleet, p_dest, p_course) → jsonb`: zones = `harbour_zone(dest)` ∪ `course_zones(course)`; `sea_refusal(title_level(player), fleet_wave(fleet), zones)`; null while `sea_conditions_bite` is off; a null player (the world's housekeeping) is clear | `passage_gate` (players), `npc_feasible_legs` and `npc_plan` (merchants) | — |
| **The composed passage gate** | `public.passage_gate(p_player, p_fleet, p_nm, p_dest, p_course)`: (1) reach (0107/0188, unchanged formula, `passage_reach_at`), (2) `sea_gate`. Arity changes, so **drop, recreate, re-revoke** (§3 of NO_SPAGHETTI) and re-cut its four callers in the same slice: `voyage.sail_refusal`, `cmd.standing_route_save_for`, `cmd.issue_lines`, `voyage.reach_passage` | the desk, the plan builder, the route save, the sail door, the map (through `world.sea_conditions` and the board) | **`E_REGION_CLOSED` and `regions.min_exploration_level` (0107 (c)) are retired in the same slice**: two authorities for "is this place open to her" is the disease; the zone table is the one. Decided by default, Q2 |
| **The merchant's feasibility** | `public.npc_feasible_legs(port, fleet, speed, days)` (gains the fleet; arity change, drop/recreate; `npc_loop_candidates` passes `p_fleet`) adds `and public.sea_gate(player, fleet, to_port, course) is null` | `npc_loop_candidates` → `npc_plan` | the sail door stays exempt for `is_npc` (0107's exemption), which is what lets a fleet at sea finish |
| **Where a house's capital is** | `players.capital_port_id uuid not null references ports`, read only through `public.capital_of(player)` | `world.player()`, `cmd.move_capital`, the hub (later) | a house still has no "home port" for sailing (NO-HOME law); nothing in `voyage.*` or `cmd.do_*` reads it |
| **The switches** | `world_config`: `sea_conditions_bite` (players), `sea_conditions_bite_npc` (merchants), `sea_sample_nm` 30, `title_max` 11, `capital_move_cost` 20000, `capital_move_cooldown_days` 7 | — | one knob per behaviour; both default `false` |

**Why the title and not a skill or a fame.** The four company skills (SEAMANSHIP / NAVIGATION /
ACCOUNTING / HAGGLING, max 5) are bought at an academy for money: a sea gate on them would be a sea gate
on ducats, and NAVIGATION already owns the leg reach — one skill, one rule. The three fames of DESIGN
I.3 exist as `player_progress`'s derived levels (trading, exploration, combat), and I.3 itself says a
title is earned when **all** fames reach the bar. Combat is honestly zero for everyone
(`playable:false`), so the title reads the two playable tracks and takes the lower: a trader who never
leaves Lisbon stays title 1 on exploration, an explorer who never trades stays title 1 on trading. The
day combat is playable the owner decides whether it joins (Q1). Nothing is stored: the title is right
retroactively for every voyage already sailed, exactly as 0069's levels are.

**Why a zone table and not the 51 seas as they are.** The raster's North Atlantic (NOR) holds 28
harbours from Lisbon and Bristol to St John's, Gorée and Cidade Velha. One requirement for it would
either lock Lisbon or open Newfoundland. The same holds for the South Atlantic (Angola and Brazil), the
Indian Ocean (Swahili coast and the Roaring Forties), and both Pacifics (Japan's coast, Acapulco's
coast, and the crossing between). Boxes on top of the raster, in one table, keep the raster untouched
(hazards and piracy keep their key) and keep every zone a thing the player can read on the map.

---

## 2. The sea table — every zone, its ring, its requirements, and why

**The ladder, in one table.** Titles come from the two playable progress tracks; waves from the ships
(§3). "Coastal" means any hull of the game sails it (the barca reads 12). Oceans ask a real ship.

| Ring | Title | Waters | Why these numbers |
|---|---|---|---|
| 0 Home waters | 1 | all of Europe's coastal seas, Morocco's Atlantic coast, Madeira | a starter's whole world; 82 harbours |
| 1 Near Atlantic | 2 | Macaronesia and the Canary Current (Azores, Canaries, Cape Verde, Senegal), the Norwegian Sea | 오리진's "NW Africa at level 20": the first prize, one title up, wave 8–10 (a barca does it) |
| 2 Guinea and the Arctic | 3 | Gulf of Guinea, Angola, the White, Barents and Arctic seas, Iceland–Greenland | coastal 10–12 so a barca sails them once titled; the Arctic ice waters 20 |
| 3 The Americas | 4 | the Atlantic crossing (30), the Doldrums (24), the American shore, the Caribbean, the Gulfs, Brazil and the Plate (coastal 10–12) | 오리진's "Caribbean at 30 + 15" relative to Africa's "25 + 4–10": a caravel with two cheap fittings crosses, a barca never does |
| 4 The Cape and East Africa | 5 | the Cape and the Roaring Forties (44), Swahili coast and Mozambique (12) | the Cape is the wall of the age; a nau needs a planking or an anchor to round it |
| 5 Arabia and India | 6 | Red Sea, Persian Gulf, Oman, Aden, Arabian Sea, Laccadive (10–12); the Indian Ocean crossing to Ceylon (40) | Suez is not dug (0079), so India is behind the Cape anyway; its own seas are coastal |
| 6 The Far East | 7 | Bay of Bengal, Andaman, the Strait, Java, Makassar, Molucca, Banda (16), Timor (16), Siam, Tonkin, South China Sea, Visayas, Taiwan Strait, East China Sea, Yellow Sea, Korea Strait, Sea of Japan (16), Seto (8), Japan's Pacific side (16) | 오리진's East Asia at 85 is its far end; ours is behind the Cape plus the Indian Ocean crossing, so its seas themselves stay coastal and the 194 merchant houses that live there keep their loops |
| 7 The Pacific | 8 | Pacific Americas, both coasts (12); the Philippine Sea (50), the Tasman (56), the North and South Pacific crossings and the Drake Passage (70) | the Manila galleon: a size-5 hull with a kit, or a size-6 hull |

**Every zone** (61; `title` / `wave`; harbours as the roadstead's zone; NPC homes = merchant houses
whose loop starts there, prod 2026-10-20). Boxes are lat/lon bounds inside the named raster sea; a sea
with no box is one zone.

| Zone | Sea · box | T | W | Harbours (n) | NPC homes |
|---|---|---|---|---|---|
| MED Mediterranean Sea | MED | 1 | 0 | 26: ALE ALG ANT BAR BEI CAG CEU FAM GIB GOA LIV MES MLG MRS NAP ORA PAL PLM RHO TAN TOU TRI TRP TUN VAL VLL | 112 |
| NEA North Sea | NEA | 1 | 0 | 12: AMS ARP BER BRU CLS HAM HRN KIN LEI LON MID ROT | 76 |
| NOR-EU European Atlantic | NOR · lat ≥ 30, lon ≥ −20 | 1 | 0 | 12: AGA BRS CAD CRK FNC LIS OPO SAF SAL SET SNL SVQ | 69 |
| BAL Baltic Sea | BAL | 1 | 0 | 9: COP GDA KAL LUB RIG STO TAL TUR VIS | 50 |
| AEG Aegean Sea | AEG | 1 | 0 | 4: CHS HER IZM THE | 26 |
| BAY Bay of Biscay | BAY | 1 | 0 | 4: BIL BOR LAR NAN | 26 |
| ENG English Channel | ENG | 1 | 0 | 4: LEH PLY PTH SNT | 15 |
| ADR Adriatic Sea | ADR | 1 | 0 | 4: ANC DBR SPL VEN | 12 |
| SEA Sea of Marmara | SEA | 1 | 0 | 1: IST | 8 |
| ION Ionian Sea | ION | 1 | 0 | 3: COR PAT ZAK | 7 |
| IRI Irish Sea | IRI | 1 | 0 | 1: DUB | 7 |
| BLA Black Sea | BLA | 1 | 0 | 2: FEO TRA | 3 |
| NOR-MAC Macaronesia and the Canary Current | NOR · lat 10–30 & lon −30…−5; lat 30–45 & lon −32…−20; lat 10–30 & lon ≥ −5 | 2 | 10 | 7: ANG CID GOR LPA PON SAI TEN | 23 |
| NRW Norwegian Sea | NRW | 2 | 8 | 2: TOR TRO | 2 |
| GUL Gulf of Guinea | GUL | 3 | 12 | 7: ACC CAL CAP ELM LAG OUI SAO | 11 |
| WHI White Sea | WHI | 3 | 10 | 1: ARK | 10 |
| SOU-ANG Angola and the Skeleton Coast | SOU · lat > −30, lon ≥ −20 | 3 | 12 | 2: LUA SOY | 10 |
| BAR Barents Sea | BAR | 3 | 12 | 1: VAR | 3 |
| ARC Arctic Ocean | ARC | 3 | 20 | 1: LNG | 2 |
| NOR-ICE Iceland and Greenland waters | NOR · lat ≥ 58, lon < −10 | 3 | 20 | 2: NUU REY | 1 |
| SOU-BRA Brazil and the Plate | SOU · lon < −20 (and lat > −45 west of −40) | 4 | 12 | 6: BEL BUE REC RIO SLV SOS | 36 |
| CAR Caribbean Sea | CAR | 4 | 12 | 7: BRI CAR CUM POR PRT SGO WIL | 17 |
| GCO Gulf of Mexico | GCO | 4 | 10 | 2: HAV VER | 15 |
| NOR-AM The American shore | NOR · lat 10–58, lon < −45 | 4 | 12 | 7: BOS JAM NEW SAN STA STG STJ | 3 |
| GCE Gulf of Saint Lawrence | GCE | 4 | 12 | 1: QUE | 1 |
| NOR-DOL The Doldrums | NOR · lat < 10 | 4 | 24 | 1: PAR | 0 |
| NOR-MID The Western Ocean (Atlantic crossing) | NOR · the rest | 4 | 30 | 0 | 0 |
| MOZ Mozambique Channel | MOZ | 5 | 12 | 2: ISL SOF | 10 |
| IND-EAF East African coast | IND · lat > −30, lon < 60 | 5 | 12 | 6: KIL MLN MOG MOM PLO ZAN | 2 |
| SOU-CAPE The Cape | SOU · lat ≤ −30, lon > −40 | 5 | 44 | 1: CPT | 0 |
| IND-S The Roaring Forties | IND · lat ≤ −30 | 5 | 44 | 0 | 0 |
| PER Persian Gulf | PER | 6 | 10 | 4: BAS BSR HOR MAN | 15 |
| RED Red Sea | RED | 6 | 10 | 5: JED MAS MOC SUA SUE | 14 |
| ARA Arabian Sea | ARA | 6 | 12 | 7: DIU HAD KAR KHA MUM OLD SRT | 11 |
| LAC Laccadive Sea | LAC | 6 | 12 | 8: COL GAL KAN KOC KOL KOZ MLE MNG | 9 |
| GLF Gulf of Aden | GLF | 6 | 12 | 1: ADE | 8 |
| GAN Gulf of Oman | GAN | 6 | 12 | 1: MUS | 0 |
| IND-E The Indian Ocean crossing to Ceylon | IND · lat > −30, lon ≥ 60 | 6 | 40 | 0 | 0 |
| KOR Korea Strait | KOR | 7 | 12 | 9: BUS FUK HIR JEJ SHI TON TSU ULS YEO | 45 |
| SOA South China Sea | SOA | 7 | 12 | 6: GUA HOI HON MAC MNL TAI | 28 |
| EAS East China Sea | EAS | 7 | 12 | 5: FUZ KAG NAG NAH NIN | 21 |
| SET Seto Inland Sea | SET | 7 | 8 | 2: OSA SAK | 15 |
| TAI Taiwan Strait | TAI | 7 | 12 | 2: QUA XIA | 15 |
| GND Gulf of Thailand | GND | 7 | 10 | 2: AYU PTT | 10 |
| YEL Yellow Sea | YEL | 7 | 10 | 3: INC MOK NAM | 10 |
| STR Strait of Malacca | STR | 7 | 10 | 1: MAL | 8 |
| NRT-JP Japan, Pacific side | NRT · lat 20–50, lon 120–150 | 7 | 16 | 1: TOK | 8 |
| BYF Bay of Bengal | BYF | 7 | 12 | 6: CHE CHI HOO JAF MCH PUL | 5 |
| JAV Java Sea | JAV | 7 | 12 | 3: BNT JAK SUR | 1 |
| VIS Visayan Sea | VIS | 7 | 12 | 1: CEB | 1 |
| AND Andaman Sea | AND | 7 | 12 | 3: BAN MYE THA | 0 |
| MAK Makassar Strait | MAK | 7 | 12 | 1: MAK | 0 |
| MOL Molucca Sea | MOL | 7 | 12 | 2: TER TID | 0 |
| BAN Banda Sea | BAN | 7 | 16 | 3: AMB BND DIL | 0 |
| TIM Timor Sea | TIM | 7 | 16 | 1: KUP | 0 |
| SFJ Sea of Japan | SFJ | 7 | 16 | 1: MAT | 0 |
| GIN Gulf of Tonkin | GIN | 7 | 10 | 1: HAN | 0 |
| PHI-JP The Kuroshio off Shikoku and Kyushu | PHI · lat ≥ 24, lon 122–142 | 7 | 16 | 0 | 0 |
| NRT-AM Pacific Americas, north coast | NRT · lat −5…50, lon −130…−70 | 8 | 12 | 10: ACA BUV HUA MTY MZT NAV PAN REA SDG SFR | 31 |
| STH-AM Pacific Americas, south coast | STH · lat > −45, lon ≥ −90 | 8 | 12 | 7: ARI CLL CON COQ GYE PAI VLP | 25 |
| PHI Philippine Sea | PHI · the rest | 8 | 50 | 1: HAG | 0 |
| TAS Tasman Sea | TAS | 8 | 56 | 2: HOB SYD | 0 |
| NRT-OPEN The North Pacific crossing | NRT · the rest | 8 | 70 | 1: HNL | 0 |
| STH-OPEN The South Pacific and the Drake Passage | STH · the rest; SOU · lat ≤ −45 | 8 | 70 | 0 | 0 |

Two rules shaped the waves: **every zone that holds a harbour takes the hull of the houses that live
there** (so the 821 merchant houses keep their coastal loops wherever they are — the Pacific houses at
Callao and Acapulco sail barcas), and **the crossings carry the whole weight** (the Doldrums, the
Western Ocean, the Cape, the Indian Ocean, the Pacific). The title does the Europe-centred gating; the
wave does the seaworthiness gating. That separation is what lets one table serve players who all start
in Lisbon and merchants who live in Nagasaki.

**Does Europe give a starter enough to progress without leaving? Measured (read-only, 2026-10-20):**
- **82 harbours** are title-1 water (36 % of the 238); they offer **495 roster goods** and hold
  **411 of the 837 merchant homes** (so the quays are busy).
- **Trades inside home waters pay.** `world.trade_routes` (the desk's own board, 150 tuns, no fleet):
  from Lisbon within 2,000 nm: cinnamon → Hamburg **16.4 %**, aniseed → Visby **19.8 %**; from Genoa
  within 1,500 nm: Italian canvases → Palermo **18.5 %** (10,528 d. on 56,769), velvet → Rhodes
  **32.6 %**, marble → Porto **32.7 %**, fustian → Safi 19.4 %; from London within 1,500 nm: felt hats →
  Tangier **27.0 %**, Sheffield plate → Cádiz **24.7 %**, cannon → Safi 13 %. The board's best rows do
  reach out to ring 1 (Lisbon: quicksilver → Saint-Louis 25.4 %, raw silk → Cidade Velha 36.0 %,
  woollen cloth → Gorée 42.9 %) — which is the point: title 2 is the first prize and it is one title away.
- **The climb is inside Europe's reach.** Trading level L needs `25 × (L−1)²` points at 100 d. of
  turnover a point (`level_from_points`, 0069): level 4 at 22,500 d. of buys-plus-sells, level 6 at
  62,500, **level 8 at 122,500**. Exploration: 25 points per distinct harbour called plus 1 per 100 nm:
  level 4 at 9 harbours, level 6 at 25, **level 8 at 49** — Europe has 82. So the far end of the ladder
  (title 8, the Pacific) is reachable without crossing a single ocean, by trading hard and calling
  everywhere; the ocean then asks for the ship.
- What Europe does **not** give: the distance premium (0173/0208) — the far goods that pay 300× are
  behind the rings, which is what the rings are for.

---

## 3. The ships' wave resistance, the gear, and how a player climbs

### 3.1 Every class on prod (101), derived: `wave = 12 × size + rig + role`

Rig: square +3, mixed +1, lateen 0, oared −6 (galleys do not keep the sea). Role: explorer +2. Size is
`class_profile.size` (1–6). Hull counts are prod's (merchant / human).

| Size | Wave | Classes (rig/role adjustments shown where they differ) | Hulls on prod |
|---|---|---|---|
| 1 | **12** lateen trade | barca (163 / 18), dhow, kayik | barca is 181 of 912 hulls |
| 1 | 13 mixed | barque (11), patache | |
| 1 | 14 lateen explorer | batil, niao, sambuk | |
| 1 | 15 square / mixed explorer | crayer (6), kobune, jacht, pinnace, qpinnace | |
| 1 | 6–8 oared | fusta, kobaya, murakami (6); hyeop, tamang (8) | |
| 2 | **26** lateen explorer | **carlat** (486 / 2), carnorm (37) | the merchant workhorse |
| 2 | 24 lateen | cangshan, ghurab, ghurabj, korsan, xebec, sangseon, shachuan | |
| 2 | 25 mixed | bark, carabela, carred, carvarm | |
| 2 | 27 square | buss, marcil, dunkirk, fregcourse, kaper, zabra, goldenhind (mixed explorer) | |
| 2 | 18 oared | byeong, galsott, sekibune | |
| 3 | **39** square | **nau** (184), levanter (4), navire (4), armfluit, armmerch, fluteroy, fluyt, nauguerra, oshuin, pinas, shuinsen, urca | the first ocean hull |
| 3 | 36 lateen | baghlah, joun, junk, karamur, zhanchuan | |
| 3 | 30 oared | bangpae, galbast, galere, galgros, geobuk, kadirga, turgut | |
| 4 | **51** square | galeao, galeon, galion, galplata, racegal, batavia, caracca, carcarm, retour; sjb 53 (explorer) | none afloat yet |
| 4 | 48–49 lateen / mixed | fuchuan, haicang (48); jahaz (49) | |
| 4 | 42 oared | ataka, bastarda, mavna, panok | |
| 5 | **63** square | couronne, galmanila, grandnav, indiaman, kalyon, naucarr, spiegel | |
| 5 | 60–61 | dachuan (60), hajji (61) | |
| 5 | 54 oared | daepanok, duodo, galeazza, oataka | |
| 6 | **75** square | carraca, galreal, greatship, madre, sanmartin | |
| 6 | 72–73 | baochuan (72), rahimi (73) | |
| 6 | 66 oared | bashum | |

The derivation is asserted by the slice against `class_profile` and `ship_classes.rig`, exactly as
0107 asserted the region levels: a hand-set value would be seen. The three tiers of merchant hull on prod
(1 ×180, 2 ×523, 3 ×192) read 12–15, 26, 39.

### 3.2 Gear: eight families add wave, by grade (`item_effects` rows, stat `wave`)

| Family (base type) | Rack | Grade 1 → 5 | Members (examples) |
|---|---|---|---|
| Anchor | mid | +2 +3 +3 +4 +5 | anchor-and-cable, osmund/genoese/manila/swedish/copper-fast anchor, admiralty-anchor |
| Sheet anchor | mid | +3 +4 +4 +5 +6 | sheet-anchor, osmund/bar-iron/swedish/copper-fast sheet anchor, bower-and-sheet-anchors, ancla-de-la-esperanza |
| Storm canvas | mid (rig) | +2 +3 +3 +4 +5 | storm-canvas, hemp/double-duck/sailcloth/holland storm canvas, typhoon-canvas, storm-trysails |
| Planking | low | +3 +4 +4 +5 +6 | deal/oak/danzig/teak/live-oak/cedar/greenheart planking, diagonal-planking, batavia-double-planking, zheng-he-bulkheads, tablazon-de-galeon, turtle-back-plating |
| Sheathing | low | +2 +2 +3 +3 +4 | copper-sheathing, doubled-copper, teak-and-copper, live-oak-and-copper, admiralty-copper, greenheart/surat-teak/monsoon-teak sheathing, copper-bolted-sheathing |
| Pumps | low | +1 +2 +2 +3 +3 | bilge/chain/teak chain/brake/malabar chain/copper chain/bentinck pumps, pompes-du-ponant |
| Ballast | low | +1 +1 +2 +2 +3 | ballast, iron/pig-iron/lead/cast kentledge, lastro-de-sal, zavorra, red-seal-ballast, callao-copper-ballast, trimmed-kentledge |
| Refits | refit | Doubled Frames I/II +2/+3 · Raised Forecastle I/II +2/+3 | — |

Every other fitting (guns, sails, headsails, studding sails, rudders, lookouts, hold frames, kits,
figureheads) adds nothing: wave is what keeps her afloat in a sea, not what makes her fast or armed.
0074's "buys one, spends another" rule is untouched: these rows are an extra buy on items that already
spend hold or speed. The best kit a rack set allows (one sheet anchor, one storm canvas, one anchor in
the mid rack; one planking in the low rack; both refits) is **+11 on a barca** (mid 2), **+19 on a
caravel** (mid 3, refit 1, no low rack), **+28 on a nau** and on everything above it.

### 3.3 The climb, ship by ship

| Fleet | Wave | Opens (wave) | With the best kit | Title asked |
|---|---|---|---|---|
| a barca | 12 | every coastal sea on earth; Macaronesia; Guinea; the American and Asian coasts once she is there | 23: nothing new — a barca never crosses an ocean | her title decides where she may be |
| a caravel (carlat) | 26 | the Doldrums (24): the southern route to Brazil and Guinea | 45: the Atlantic (30) with one sheet anchor and one storm canvas (+5, grade 1, workstation tier 1–2); the Cape (44) with the full grade-5 kit | 4 for the Americas |
| a nau / carrack | 39 | the Atlantic; everything to 39 | 67: the Cape and the Indian Ocean (44/40) with one grade-2 planking (+4) or anchor+canvas; the Philippine Sea (50) and the Tasman (56) with the kit | 5 the Cape, 6 India, 7 the Far East |
| a galleon / Indiaman (size 4–5) | 51 / 63 | the Cape and India outright | 79 / 91: the Pacific (70) — the Manila run — with a kit (size 4) or almost bare (size 5) | 8 |
| a carrack of state (size 6) | 75 | everything | — | 8 |

**A mixed fleet averages.** A nau escorting two barcas reads (39+12+12)/3 = 21 and cannot cross the
Atlantic; that is 오리진's rule and it is the reason to build matched fleets. The desk prints the fleet
figure beside the title, and the refusal names which of the two is short.

**How long, roughly, in real time** (time compression 960: a 1,000 nm leg at 5 kn ≈ 12.5 real minutes;
the standing routes sail while the player is away):
- Title 2 (Macaronesia): one full day of Lisbon–Porto–Seville trading (~2,500 d. turnover, 1 new port);
  a first evening.
- Title 4 (the Americas): 22,500 d. turnover and 9 harbours called — a week of casual play or a
  weekend of routes; the caravel (26,000 d. at a yard, `SHIPS_AND_GEAR` §1.1) plus two cheap fittings
  is the real cost.
- Title 5–6 (the Cape, India): 40,000–62,500 d. and 16–25 harbours; a nau (120,000 d.). The owner's
  own house today (JOOHOON HA: trading 3, exploration 4, one barca) is title 3 — Guinea and the Arctic
  are open to him, the Caribbean is one trading level away, and the Atlantic asks for a caravel.
- Title 8 and the Pacific: 122,500 d. and 49 harbours; a galleon or an Indiaman with a kit.

---

## 4. The merchants, measured on prod-shaped data

**How it was measured.** Read-only exports on 2026-10-20 (head 0211): the 837 merchant routes with
their hulls, stops and course polylines (`standing_route_stops`, 2,745 stops, 18,998 vertices), the
1,205 remembered courses (`npc_courses`), the 252 ports, and the sea raster (`sea_cells`, 720 rows).
Offline: every course was sampled every 0.5° along each straight segment (the chart is
equirectangular, so a leg is a straight line in lat/lon), each sample resolved with `voyage.sea_at`'s
own arithmetic (row `floor((90−lat)/0.25)`, column `floor((lon+180)/0.25)`) and then boxed into the
zone table of §2; a harbour's zone is the zone of the first vertex of a course leaving it (its
roadstead). The fleet's wave is the average of its hulls' class figure (merchant fittings on prod add
at most +2: 68 copper sheathings on 912 hulls). "Known legs" are `npc_known_legs`' definition: every
leg of every merchant loop in both directions plus every remembered course.

| Measure | Today | After the rule (dark → lit) |
|---|---|---|
| Merchant loops | 837 | 837; **548 cross water their fleet cannot hold** (65 %) |
| By hull: caravel loops | 442 | 289 closed (the Atlantic: 197 loops bind on NOR-MID 30; the Doldrums 26) |
| barca loops (one or two barcas) | 143 | 110 closed |
| nau loops | 174 | 94 closed (the Indian Ocean crossing 125 loops across all hulls, the Cape 83, the Philippine Sea 40, the Pacific 65, the Tasman 5) |
| navire / levanter loops (size 3, square) | 8 | 0 closed |
| Loops by the farthest ring they touch | ring 1: 46 · 2: 34 · 3: 27 · 4: 359 · 5: 44 · 6: 13 · 7: 182 · 8: 132 | closed: 0 · 0 · 4 · 223 · 44 · 10 · 157 · 110 |
| **Houses with no open leg from home** | — | **0 of 837** (every home's own waters take its hull: the rule of §2) |
| Houses whose loop closes, by open legs they keep | — | 1 leg: 6 · 2: 20 · 3: 48 · 4: 48 · 5: 59 · 6+: 367 |
| Fleets at sea on a closed loop | — | 535 (they finish the lap; re-planned at the lap start) |
| Far harbours (title ≥ 4) visited by a loop | 122 of 133 | 72 by the loops that stay; **120 reachable by some house's open known leg** (the planner's candidates) |
| Far harbours no house can reach | — | **13**: AMB BND DIL TER TID KUP (the Spice Islands and Timor), CPT (Cape Town), KOL (Kollam), PLO (Port Louis), HAG (Guam), HNL (Honolulu), HOB SYD (Australia) |
| Visits to far harbours by loops | 1,344 | 243 by the loops that stay; the planner refills from the 120 |
| Loop length, median | — | closed 11,100 nm · open 7,500 nm |

**What this means for the owner's three sentences.**
- *Small-ship houses drop far loops at their next review.* 454 caravel, barca, barque and crayer loops
  close (331 caravel, 123 of the size-1 hulls). Each
  house keeps 1–6+ open legs from home (none keeps zero), so at her next lap start `npc_plan` prices
  her present loop as unsailable (0203's `v_unsail`, composed with `sea_gate`) and takes the best open
  loop on offer, or sails her present loop with no BUY until one pays (0197/0181). Her next review is
  her next lap start (0203: a loop that cannot be sailed is reviewed at once) — median 11,100 nm, so
  within one to three real hours of the switch for most, longer for the Pacific loops.
- *Carrack houses keep them.* The nau's 39 keeps the Atlantic and the Doldrums (129 loops stay with
  those two crossings as their hardest water: naus on both, caravels on the Doldrums); the nau loses the
  Cape, the Indian Ocean and the Pacific (94 nau loops) until it carries one planking — and
  merchant gear is endowed at founding (0126), so **a nau house does not re-fit itself**: slice S4 gives
  the far-trading houses hulls and kits that reach.
- *Fleets at sea finish their trip.* The sail door keeps 0107's `is_npc` exemption: `passage_gate`
  returns null for a merchant, so nothing refuses her SAIL at a far stop. Only the planner judges her,
  and only at a lap start.

**Far-market supply after the change.** 120 of 133 far harbours stay in some house's open candidate
set, and the Asian, Indian, Caribbean, Brazilian and Pacific-coast houses (the 400-odd homes outside
Europe) keep every coastal loop. What is lost is the **inter-ocean** merchant traffic: the Spice Islands,
Cape Town, Australia and the mid-Pacific have no local houses and were served only by European caravels
and naus crossing the Cape or the Pacific. **The remedy is S4**: 20 far-trader houses founded at the
seven great yards' cities (Lisbon, Seville, Amsterdam, London, Marseille, Genoa, Venice — `0072`'s
tier-3 yards) with one size-4 hull each (galeao / retour / batavia / caracca, wave 51) and an endowed
grade-1 planking and sheet anchor (+6, reaching 57 — the Tasman at 56 and the Philippine Sea at 50),
plus 4 houses with a size-5 hull (indiaman / naucarr, 63 + 6 — the Pacific at 70 stays closed to
merchants, deliberately: the Manila run is the players' prize; Honolulu is the one harbour that only a
player will reach). `npc_fleet_max` is 861 and 837 are founded: room for 24. The slice asserts that
**every harbour has at least one merchant house whose fleet reaches it** — except Honolulu, named.
Its loops are planned by the one planner like every other house's (0120/0197: the trade candidates
ranked by the distance premium), so the Spice Islands are served by the hulls that can get there, and
by nobody else.

**What the merchant title half is not.** Merchants have no title (`title_level` returns null and
`sea_refusal` skips the title test). Their "level" on the city list is the sum of their four skills
(0113) and stays so. Decided by default, Q3.

---

## 5. Everyone starts in Europe; the capital; the seam for the hub

### 5.1 The start
- `public.great_powers` gains `starting boolean not null default false`; PRT ESP ENG NLD FRA OTT are
  `true`. `world.snapshot().nations[]` gains `starting` beside `great` (0187).
- `cmd.found_house(name, nation)` refuses a great power that is not starting with **`E_FAR_POWER`**:
  *"Ming China is reached by sailing there. Found your company in Europe; you can move your capital
  east once its seas are open to you."* The fixes list the six.
- `cmd.change_country` is unchanged: all ten (the owner may want a Portuguese to sail for Japan after
  immigrating; immigration is a later design).
- Start screen: `SignTheBook` passes `starting` to `NationPicker` (a prop; the Profile's picker keeps
  `great`). The hint keeps *"You start at Lisbon."* Today's 17 players are all PRT: nothing moves.
- The Asian and Islamic powers from 0187 stay great powers, keep their homes, their merchant houses and
  the Countries board. Nothing is demoted.

### 5.2 The capital
- `players.capital_port_id uuid not null references ports(id)`, backfilled at the slice with each
  house's country's capital (`nations.capital_port_code`; all 17 → Lisbon). `cmd.found_house` sets it
  through `public.new_house`. Read only through **`public.capital_of(player) → uuid`**.
- **`cmd.move_capital(p_port_code text)`**, registered to clients, refuses in this order (each a
  `cmd.refusal` with a sentence): `E_NO_SUCH_PORT` · `E_NOT_A_HARBOUR` · `E_SAME_CAPITAL` ·
  `E_SEA_CLOSED` when `sea_refusal(title_level(me), null, [harbour_zone(port)])` refuses — the city's
  waters must be open to her **title** (wave is a fleet's matter, not a city's) · `E_NOT_THERE` when no
  fleet of hers is docked at that harbour (she must have been there; default, Q5) · `E_TOO_SOON` inside
  `capital_move_cooldown_days` (7) of her last `CAPITAL_MOVED` event · `E_INSUFFICIENT_FUNDS` under
  `capital_move_cost` (20,000 d.). Then: debit the cost to the city's purse (the one sink that exists:
  `city_treasury`, 0172 — the new capital's city is paid, which is what a court moving in does), set
  the column, emit `CAPITAL_MOVED {from, to}`, return the next allowed date. **Country unchanged.**
- **What moves: nothing physical.** Fleets stay where they are (NO-HOME law), store items stay in
  their ports (`player_items` is per port), influence stays by the country that gave it (I2),
  mayorships stay, routes stay.
- **What the capital does today:** the Profile prints *"Capital: Lisbon"* and a *Move capital* sheet;
  History carries the move. Nothing in `voyage.*` or `cmd.do_*` reads it, and the slice asserts that
  with a live-body scan (0132's method).
- 0143's `nation_change_next_at` is the pattern for the cooldown and `cmd.change_country` for the
  shape; one event kind, one knob each.

### 5.3 The seam for the hub (later; not designed here)
- The hub keys on **the house**, not on a port: `capital_buildings (player_id, kind, level, …)` and
  `capital_stock (player_id, good_id, qty)` will reference `players.id`, and read the place through
  `capital_of(player)`. So a capital move carries the hub with it by construction, and whether moving
  should cost the buildings is a hub decision, not a capital decision (noted, not decided).
- The hub never becomes a required stop: it produces into the house's books, not into a hold; the
  owner's law above is written into `capital_of`'s header so the next designer reads it first.
- Nothing else is reserved. A seam is one function and one column.

---

## 6. Slices, in deploy order (each dark; its own switch where it changes behaviour)

Numbers are provisional (renumbered to prod head + 1 at push; prod head 0211 today). Every migration
slices live bodies by hunks (each occurs once, reverses to its pre-image, ACL unmoved), reads its
pre-images live, probes with its own rows rolled back, and never edits an applied file.

| # | Slice | Server | Switch | Proof (self-assert, counting only its own rows) |
|---|---|---|---|---|
| **S1** | `the_seas_have_conditions` — the data and the readings | `sea_zones` (61 rows + boxes, `data/sea-zones.json`, world guard) · `sea_zone_at`, `harbour_zone`, `course_zones`, `sea_leg_asks` (derived) · `ship_classes.wave` (derived; one hunk in `world.ship_stats`, both branches) · `item_effects` 'wave' rows + CHECK · `fleet_wave` · `title_level`, `title_names`; `players.title_level` dropped, `world.player()` and the 0096 merchant card re-cut · `sea_refusal`, `sea_gate` (returns null while dark) · `world.sea_conditions()` registered read (zones, the caller's title, each fleet's wave) · `world.fleets()` serves `wave` per hull and per fleet | `sea_conditions_bite` false | every class's `wave` equals the derivation; every item of the eight families has a 'wave' row and no other item does; `ship_stats` of **every hull on prod** unchanged on the ten old stats (parity, to the digit) and `wave` = class + mounted; `fleet_wave` of a probe fleet of nau + 2 barcas = 21; `title_level` = min of the two levels for every human (17) and null for a merchant; `sea_zone_at` at every harbour's roadstead names a zone and 238 harbours resolve; `course_zones` of the prod course Bristol→Cape Coast contains NOR-MID and NOR-DOL (the vertex-only miss, as a positive control); `sea_refusal(1, 12, {NOR-MID})` refuses with the four figures and `(4, 30, {NOR-MID})` is clear; `sea_leg_asks` row LIS→HAV reads wave 30 / title 4; walls hold |
| **S2** | `the_passage_gate_reads_the_sea` — players | `passage_gate(player, fleet, nm, dest, course)` dropped/recreated/revoked; four callers re-cut by hunks: `voyage.sail_refusal` (passes `f.id`, `p_path`), `cmd.standing_route_save_for` (the stop's course), `cmd.issue_lines` (`p_fleet`, `v_lpath`), `voyage.reach_passage(player, fleet, from)` (+ `world.good_board`'s two call sites) — an edge is open when `sea_leg_asks` allows it for her title and wave, the figures computed once per call · the 0107 region branch (`E_REGION_CLOSED`) removed and `regions.min_exploration_level` dropped · refusal word `E_SEA_CLOSED` | lit by `sea_conditions_bite` (S1's knob) **in the same deploy window**, after the push's 30-minute after-check | probe house at Lisbon, barca, title 1: SAIL Funchal clear; SAIL Las Palmas refused `E_SEA_CLOSED` naming Macaronesia, title 2 asked, 1 held, wave 10 asked, 12 held; the same with a title forced to 2 (probe skill rows: 4 ports called, 10,000 d. turned) is clear; a nau to Havana clear at title 4, refused on the crossing at title 3, refused on **wave** with two barcas added (21 < 30) — the sentence names the wave; a merchant is exempt at the door on a 999,999 nm leg into the Pacific (0107 d4 kept); `issue_lines` refuses the plan up front, line named; `reach_passage` from Lisbon at title 1 reaches 82 harbours and at title 8 / wave 75 reaches 238; dark (switch off) every answer equals its pre-image for 20 sampled passages; walls hold |
| **S3** | `a_merchant_sails_the_seas_her_hull_can_hold` — merchants | `npc_feasible_legs(port, fleet, speed, days)` dropped/recreated (+ `sea_gate` on the leg's course); `npc_loop_candidates` passes `p_fleet`; `npc_plan`: her present loop's legs asked of `sea_gate` → `v_unsail` (0203's own flag, composed) | `sea_conditions_bite_npc` false, lit after S2's window | prod-shaped probe (own merchant rows, rolled back): Comptoir at Bristol with a carlat and the loop BRS-CAP-ROT-STA-SET-SGO-RIG: with the switch lit her loop is unsailable, the Caribbean legs are not among her candidates, Cape Coast and Rotterdam are; a nau at Palermo keeps PAL-CAP-REC-WIL-SET-TRA; a barca at Acapulco keeps ACA-PAN; the count of feasible legs out of Lisbon for a barca fleet equals the sim's (one number, derived, printed); dark: every candidate list equals its pre-image |
| **S4** | `the_far_traders_are_founded` — data | 24 houses (0105's founding path): 20 × size-4 square hull + grade-1 planking + sheet anchor, 4 × size-5; homes at the seven great yards' cities; loops seeded by the planner's trade candidates | none (data; the planner is already lit) | `npc_fleet_max` not exceeded (861); each founded fleet's `fleet_wave` ≥ 57; **every harbour but HNL is reachable by at least one house's fleet** (asserted by `sea_leg_asks` from each home); W unchanged (their capital comes from the founding faucet 0105 used, named) |
| **S5** | `everyone_starts_in_europe` | `great_powers.starting`; `cmd.found_house` `E_FAR_POWER`; `world.snapshot` nations[].starting | none (a refusal where there was none; 0 humans affected) | a probe founding under JPN is refused with the six fixes; under OTT starts at Istanbul; the ten still race; `cmd.change_country` to MNG still allowed |
| **S6** | `a_house_has_a_capital` | `players.capital_port_id` backfilled; `capital_of`; `cmd.move_capital` registered; knobs; `CAPITAL_MOVED`; `world.player().capital` | none needed (a new verb; nothing reads the column but the Profile) | all 17 read Lisbon; a probe move to Las Palmas at title 1 refused `E_SEA_CLOSED`, at title 2 with no fleet there `E_NOT_THERE`, docked there and 20,000 d. richer: moved, 20,000 d. in Las Palmas's purse, W unchanged, a second move `E_TOO_SOON`; live-body scan: no `voyage.*` or `cmd.do_*` body names `capital_port_id` |

**Client slices** (each with S-numbers it needs; `tests/words.spec.ts` rows for the new words):

| # | Client | Needs | What the owner sees | Proof |
|---|---|---|---|---|
| C1 | Start: the six starting powers | S5 | the Start sheet offers Portugal, Spain, England, the Netherlands, France, the Ottoman Empire; Profile still offers ten | Playwright: six chips on Start, ten on Profile |
| C2 | The figures | S1 | ship panel: **Wave resistance 26**; fleet header: **Fleet 21 (nau 39, barca 12, barca 12)**; Profile: **Title 3 · Master** (`title_names`) | spec reads the served numbers, never computes |
| C3 | The conditions panel and the map | S1 | Codex face **Seas**: every zone, its title and wave, open / closed for the selected fleet (`world.sea_conditions`); tap on open water: the zone's name and its two asks; **the map shades closed zones** for the selected fleet — a zone raster asset (`public/sea-zones.png`, palette-indexed, built by `scripts/build-sea-raster.mjs` beside the server raster; the world guard holds its hash to `sea_zones`) painted as a tinted sheet like `DaylightSheet`, under the marks | the asset's hash matches the table; the shaded cells of Lisbon's bay are 0 and of the mid-Atlantic are all, for a barca; 390 px: the panel folds |
| C4 | The desk's refusal sentence | S2 | `reachWords` (planLines.ts, the one wording, WORDS row 44) gains the sea case from the refusal's figures: *"The Western Ocean asks title 4 and wave resistance 30. You are title 2 and your fleet holds 26: a bigger ship, or anchors and planking."*; the best-trade card marks a closed city **closed sea** instead of a passage | words spec; the sentence is the server's figures rendered, never recomputed |
| C5 | Move capital | S6 | Profile: *Capital: Lisbon · Move* → a sheet listing the harbours where a fleet of hers is docked, each open / closed by title, the cost and the next date | Playwright on the local chain |

**Measured windows.** S2's switch and S3's switch each get their own 30-minute after-check: refusals per
hour by code (`E_SEA_CLOSED` should appear at plan time, not at departure, for players; 0 for merchants
at the door), arrivals sweep average and max (the planner now calls `course_zones` per candidate leg:
~100 raster reads a leg; measure, and if a lap start grows past 0203's 277 ms, store `zones` on
`npc_courses` and `standing_route_stops` at write time — the same function, cached once), merchant
lay-ups (0181) before and after, and the count of loops re-planned. Forward rollback: both switches off
restore every answer to its pre-image (asserted dark in S2 and S3).

---

## 7. Open questions for the owner (each with the default that is built unless you say otherwise)

| # | Question | Default | If you say no |
|---|---|---|---|
| Q1 | The captain level is the **title = the lower of Trading and Exploration** (derived, capped 11); Combat joins only when it is playable | yes | name the formula (e.g. Trading alone, or the sum); it is one function |
| Q2 | The 0107 **region gate** (`min_exploration_level`, distance from Lisbon) is **retired** — the sea conditions replace it | yes | keep both; the doc then owes a sentence for what the second gate is for |
| Q3 | Merchants are judged on **wave only** (no title) | yes | give merchants a title from their skill sum (0113) and gate them on it too |
| Q4 | **24 far-trader houses** (size-4/5 hulls, kits) are founded so the Spice Islands, the Cape, Australia and Kollam keep a merchant; **Honolulu stays players-only** | yes | leave those harbours unserved until a player gets there |
| Q5 | Moving the capital costs **20,000 d.** (paid to the new city), **once a week**, to a harbour **open to her title where one of her fleets is docked** | yes | drop the docked-fleet rule, or price it as a share of her purse |
| Q6 | The six **starting powers**: PRT ESP ENG NLD FRA OTT | yes | add or remove; it is one boolean per row |
| Q7 | The numbers: waves **12 / 26 / 39 / 51 / 63 / 75** by hull size, gear up to **+28**, crossings **24 / 30 / 40 / 44 / 50 / 56 / 70**, titles **1–8** | yes | every one is a row in `data/sea-zones.json` or a knob; the sim re-runs in a minute |

---

## 8. What this design deliberately does not do

- **No ice-breaking, breakthrough or rowing stats** (오리진 has them). The Arctic zones ask wave 20 and
  title 3; `ports.is_ice_closed` already closes the frozen harbours (0047). One stat, one gate.
- **No damage while sailing a closed sea.** The wall is at plan time and at departure; a fleet is never
  at sea in water she may not be in.
- **No new progression counter.** The title is read off the ledger and the voyage reports, as the two
  levels already are.
- **No change to hazards or piracy.** `seas.hazard_base`, `piracy_index`, `danger_level` and the raster
  key are untouched; the zone boxes live beside the raster, not in it.
- **No hub.** One column and one function are the seam; everything else waits for its own design.
- **No change to what a harbour sells, prices, or the distance premium.** The rings decide who may go,
  not what is there.

---

## 9. Corrections found while building (S1, 2026-10-20 — docs/dev-log/2026-10-20-sea-conditions-s1.md)

- The §2 table has **64** zones (its prose said 61); the table is what was built.
- Prod holds **103** ship classes (§3.1 said 101); every one derives.
- The prod course **Bristol → Cape Coast never enters the Western Ocean**: it hugs the coast (never west of 17.6° W)
  and its ten vertices already name every zone it crosses (European Atlantic, Macaronesia, the Doldrums, the Gulf of
  Guinea). The §1 claim that vertex-only sampling misses the mid-Atlantic on it was wrong for that course. The
  positive control S1 asserts instead is a two-vertex Lisbon → Havana line: its vertices name two zones, the 30 nm
  sampling finds Macaronesia, the Western Ocean and the American shore between them.
- Boxes live in a child table (`sea_zone_boxes`): three zones have two or three boxes and one spans two seas. The zone
  raster (`sea_zone_cells`) is a derived materialisation of the boxes over the 0040 raster, so a course sample is one
  byte read.
- In S2 the 0107 region door stays as the DARK path and goes with its column in the slice after the switch is lit
  (S2b): the owner's standing rule that a dark slice changes no answer outranks §6's "same slice", and the door refuses
  real plans today (13 of 17 houses are refused Havana by it).
