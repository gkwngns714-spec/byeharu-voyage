# Ship stores space, and every ship rolls her own stats (owner rows 221, 222)

Owner, 2026-10-26:
- **221**: *"separate cargo space so that provision is set differently by ship."*
- **222**: *"all ships when made or bought will not have same stats even though its name is same, it should have variety (randomness) too."*

Design only: no code and no migration in this PR. **(D)** marks a decision I made by default; the owner may reverse it.

## 0. The answer in eight lines

1. Each ship gets a **stores space** in tuns, beside her hold. Water and food go there and nowhere else. Cargo never takes stores room, and stores never take cargo room.
2. Class size = **36 days for a full crew** (`ceil(crew_max × 0.035 × 36)`), so about 90 days at the crew she needs. Barca 26 t, carlat 38 t, nau 177 t. **(D)**
3. The hold stays the class hold, all of it cargo. Every fleet **gains** the tuns its stores take today. No fleet loses a leg (prod proof in §1.4).
4. Every new ship (build, founding, NPC founding) **rolls six stats** once: speed, hold, stores, hull, crew max, handling. Usually within ±12 %; 1 in 20 is **Fine** (+8 to +20 %), 1 in 20 is **Poor** (−8 to −20 %). The roll is seeded by the ship's id, stored on her row, and fixed for life.
5. **One authority:** `public.ship_base(ship)` = class × her roll. Every reader that reads a ship's class column today reads this instead.
6. **Existing ships keep their class values** (roll 1.000), so no live ship changes. **(D)**
7. The ship shows `Speed 16.1 kn (+7 %)` and a word: **Fine / 우수**, **Poor / 부실**. The yard is a **blind roll**: same price, with the range shown before you build. **(D)**
8. Three slices, smallest first. V1 is byte-identical and dark.

## 1. Stores space (row 221)

### 1.1 Today (prod head 0235, read-only 2026-10-26)

- There is one pool. `public.fleet_free_hold` = Σ(hold − cargo − water − food). DAYS top-ups (`stores_topup`) fill up to `hold − cargo`. `store_ratio` (0.45) only caps FULL.
- So a full hold means short stores. 0231 had to cap passages by "room beside cargo" (`supply_reach`), and the shut words say `Hold too full`.
- Consumption: water 0.020 + food 0.015 = **0.035 t per crew per day**. A barca with 8 crew uses 0.28 t a day.

| Prod, 2026-10-26 | Humans | NPC merchants |
|---|---|---|
| Ships (fleets) | 22 (19): 20 barca, 2 carlat | 895 (837): 486 carlat, 184 nau, 163 barca, 37 carnorm, 11 barque, 6 crayer, 4 levanter, 4 navire |
| Hold (with quartermaster stretch) | 4,140 t | 409,486 t |
| Cargo aboard | 64 t (1.6 %) | 80,780 t (19.7 %) |
| **Stores aboard** | **274 t (6.6 % of hold)**, p50 ship 2.3 %, max 32 % | **6,849 t (1.7 %)**, p50 1.2 %, max 6.4 % |
| Most days of stores on one ship | 96 (barca) | 40 (barca), 34 (nau) |
| Longest leg asked, in stores-days (retained voyages + route stops) | 7.1 | 55.9 (p99 52.6) |
| Fleets shut today because the hold is too full | 0 | **11** |

### 1.2 The rule

| What | Where it lives |
|---|---|
| Class size | NEW `ship_classes.stores int` = `ceil(crew_max × 0.035 × 36)` **(D: 36 days at full crew)** |
| Ship size | `public.ship_base(ship).stores` = class × `ships.roll_stores` (§2) |
| The one reading | NEW `public.ship_stores_capacity(ship)` = `floor(world.ship_stat(ship,'stores'))`. `'stores'` joins `world.ship_stats`, so a fitting could change it later. The quartermaster stretch is **not** applied, because Provisioners already stretch days through `endurance_mult`. **(D)** |
| Cargo room | `public.ship_free_hold(ship)` = `ship_hold_capacity − ship_cargo_tuns`. NEW, and the one per-hull rule. `fleet_free_hold` sums it. |
| Weight | Stores still **weigh**: `ship_speed_at`'s fill stays `(cargo + stores) / hold`, so speed is byte-identical. **(D)** |
| `store_ratio`, `store_ratio_default` | Unread after V2. FULL now means "fill the stores space". The column is dropped in V4. |

Class sizes on prod's classes: barca, barque, crayer 26 t · carlat, carnorm 38 t · nau, navire, levanter 177 t.

### 1.3 Every reader that mixes them today, and what it reads after

| Reader (live body) | Today | After V2 |
|---|---|---|
| `public.fleet_free_hold` | hold − cargo − water − food | Σ `ship_free_hold` (hold − cargo) |
| `public.fleet_load` | **a second copy** of the free rule (hold − cargo − water − food) | reads `ship_free_hold`. The copy is cut (NO_SPAGHETTI). |
| `public.stores_topup(crew, water, food, room, days, full)` | callers pass room = hold − cargo, full = hold × ratio | body unchanged. Callers pass room = full = `ship_stores_capacity` |
| `public.supply_needs` / `supply_need` (`fits`, `tons`, `cost`) | room beside cargo | stores capacity. `fits` no longer depends on cargo. |
| `public.supply_reach` (0231 cap) | room beside cargo | stores capacity. It is now a fact of the fleet that does not move as she loads. |
| `voyage.leg_refusal` E_ENDURANCE | words `Hold too full: {carry}…` | same code. Words `Stores short: {carry}, crossing needs {need}` / `보급 부족: {carry}, 항해에 {need} 필요` |
| `cmd.do_provision` (DAYS, FULL) | least(hold − cargo, hold × ratio) | stores capacity |
| `public.npc_provision_for` | room = hold | stores capacity |
| `public.npc_casks_blocked` | hold − cargo | stores capacity |
| `world.good_board` | `units_fit` = (free − stores tuns) / bulk, `sailable` = fits, `shut` | `units_fit` = free / bulk. `sailable` and `shut` are the same code, now independent of cargo. |
| `cmd.do_buy`, `fleet_buy_capacity`, `run_manifest`, `npc_plan` | through `fleet_free_hold` | no code change; they gain the room |
| `world.ship_view` / `world.fleets` / `npc_fleet_card` | hold used includes stores | + `stores_cap`. Hold used = cargo only. |
| Client `shipHoldUsed`, `fleetHoldBreakdown`, `FleetHold`, `FleetStores`, desk `holdTooFull` | provisions are a share of the hold | the hold bar is goods + free. FleetStores shows `Stores 8 / 26 t · 29 days`. |

### 1.4 The switch, proved on prod numbers

Existing ships get `stores` = class size, or the stores already aboard if those are more. Three human ships carry more than their class space today (barca up to 27 t, carlat up to 87.6 t); each keeps exactly what she holds. That is stored as `roll_stores = ceil(aboard) / class` (≥ 1). **(D)** Water and food stay in their columns, so nothing is moved row by row. The columns simply now belong to the stores space.

| Check (computed read-only on prod, 2026-10-26) | Humans | NPC |
|---|---|---|
| Cargo room gained | +274 t | +6,849 t |
| Stores space created | 596 t | 58,538 t |
| Stores-days she can carry, p50: today (empty hold reads huge) → after | 643 → 92.9 | 573 → 90.5 |
| Least stores-days of any fleet after | 92.9 | 74.3 |
| Same, if every ship rolled −20 % (worst case for new hulls) | 74.3 | 59.4 |
| Longest leg asked | 7.1 | 55.9 |
| **Fleets that could not sail their longest leg** | 0 → **0** | 11 → **0** |

Method: legs are `max(voyages.total_nm)` per fleet, together with every `standing_route_stops.course_nm`. Speed is the slowest class speed × 0.75 (full load) × formation, which is the slow case. The ENDURANCE skill is ignored, and it only adds days. "Carry drops" from ~600 days happens only because an empty hold today counts as casks. No leg anyone sails comes near the new figures.

## 2. Variety (row 222)

### 2.1 The roll

| What | Decision |
|---|---|
| When | `public.commission_ship` (the ONE ship insert, 0096). Every creator goes through it: `cmd.do_build`, `new_house`, `cmd.found_house`, `npc_found`. |
| Seed | the new ship's id (generated before the insert). NEW `public.ship_roll(seed uuid)` is IMMUTABLE: md5(seed ‖ stat) → uniforms. The same seed always gives the same roll, which makes it testable. |
| Stored | `ships.roll_speed, roll_hold, roll_stores, roll_hull, roll_crew, roll_handling numeric(4,3) not null default 1.000`, fixed for life. Nothing else writes them. |
| Tier | u < 0.05 → **Poor**: each stat −8 to −20 %. u > 0.95 → **Fine**: each stat +8 to +20 %. Otherwise each stat is `1 + 0.12 × (u1+u2+u3 − 1.5)/1.5`, a bell shape within ±12 %. **(D)** |
| Stats rolled | speed, hold, stores, hull (max durability), crew max, handling. Not rolled: crew needed (wages), draft, guns and the combat stats (they are inert, SHIPS_AND_GEAR §1.4). **(D)** |
| Clamps | crew max ≥ crew needed. Hold, stores and hull are floored to whole numbers. Speed is rounded to 0.01 kn. |
| Grade | derived, never stored: `public.ship_grade(ship)` = mean of the six. ≥ +7 % → `fine`, ≤ −7 % → `poor`, else null. |
| Founding ship (a new player's first hull) | rolls, but each factor is `max(1, f)`, so a new player never starts Poor. **(D)** |
| Famous ships (one to a house, 0165) | roll 1.000, always the ship of the legend. **(D)** |
| **Existing ships** | **keep 1.000** (class values). Nothing live changes, and V1 proves it byte for byte. **(D)** Option: roll them once in V3, which is one UPDATE through `ship_roll(id)`. Not taken, because it changes 22 players' ships and 837 merchant laps without being asked. |

### 2.2 One authority

`public.ship_base(ship) → (hold, speed, stores, durability, crew_max, handling)` = class × her roll. This is the only place a class column meets a ship.

| Reads a class column for a ship today | After V1 |
|---|---|
| `world.ship_stats` (base of all ten stats; `ship_stat`, `ship_hold_capacity` and `ship_speed_at`'s speed come through it) | base from `ship_base` |
| `cmd.do_hire`, `public.class_budget` (crew_max) | `ship_base.crew_max` |
| `cmd.do_repair`, `fleet_repair_due`, `voyage.fight`, `fight_resolve`, `sail_refusal`, `settle`, `ship_speed_at` (max durability) | `ship_base.durability` |
| `public.ship_set_bonus` (hold, speed, durability, handling) | `ship_base` |
| `commission_ship` (starting hull = class durability) | = her rolled max |
| `world.ship_view` (`*_rated`) | `*_rated` = her base. NEW `class_*` = the class average |
| `world.building_yard` | stays on the class: it is the catalogue, not a ship |

Self-assert (V1): no live body other than `ship_base`, `building_yard` and `ship_view`'s `class_*` reads `ship_classes.{hold,speed_kn,durability,crew_max,handling,stores}` joined to a ship.

## 3. What the player sees

| Where | Shows |
|---|---|
| Ship tile / panel | `Speed 16.1 kn (+7 %)`, `Hold 171 t (−5 %)`, `Stores 28 t (+8 %)`, `Hull 430 (+8 %)`, `Crew max 21 (+5 %)`. Long-press or hover shows `Barca avg 15.0`. 0 % prints no bracket. |
| Grade word | Fine / **우수** (accent), Poor / **부실** (warning). A standard hull shows no word. |
| Fleets → Stores | `Stores 8 / 26 t · 29 days` / `보급 8 / 26 t · 29일` |
| Hold bar | Goods / Free only. Provisions leave the hold bar. |
| Yard (before building) | class average + `Each hull differs ±12 %` / `배마다 다름 ±12 %`. **Blind roll (D):** a 3-hull pick needs an offers table and invites re-roll farming. |
| After building | toast `Gaivota came out Fine` / `가이보타: 우수` (or no grade word) |
| Merchant card | the same tile (it reads `ship_view`) |

## 4. Economy (closed economy)

| Question | Decision |
|---|---|
| Price of a better roll | **None.** Same build cost, because it is luck. No faucet or sink is added, and no resale market exists to price it. **(D)** |
| Repair | already per hull point, so a Fine hull (more points) costs proportionally more to repair. No new rule. |
| Insurance | insures cargo at cost (`fleet_stock_at_cost`), not hulls. A bigger hold can carry more value; the rule is unchanged. |
| Cargo room | +7,123 t world-wide at the switch (1.7 %). Merchants' laps carry slightly more. This is goods moved, not money minted. |

## 5. Slices (one migration each, "next" numbers in order; client in the same PR)

Common self-assert rules: count **only probe rows** (probe company and probe ids; an `id >` mark taken in-block). Never count or sum a growing table. Never DELETE from append-only tables (`ledger`, `treasury_flows`, `events`). No hour-of-day dependence. Probes run in sub-blocks rolled back whole. Every replaced body is the LIVE body (LF), each hunk asserted once and reversible, ACL unchanged, files saved LF. Byte-identical wherever a slice is dark.

| # | Name | Does | Self-asserts / tests |
|---|---|---|---|
| **V1** | `every_ship_has_a_base_of_her_own` | six `roll_*` columns (1.000), `public.ship_base`, the class readers of §2.2 re-cut onto it. No client. | For every hull afloat, `world.ship_stats` new = pre-image (jsonb-equal). `ship_view` and `fleets` byte-identical. The no-other-reader assert. No ship has roll ≠ 1 (NOT EXISTS, no count). |
| **V2** | `stores_have_their_own_space` | `ship_classes.stores`, `'stores'` in `ship_base` and `ship_stats`, `ship_stores_capacity`, `ship_free_hold`; existing ships get `roll_stores` ≥ 1 (§1.4); every reader in §1.3 re-cut; E_ENDURANCE words; `store_ratio` unread. Client: FleetStores, FleetHold, `derive.ts`, desk words, ship tile `stores`. | Probe barca: fill the hold with cargo → `supply_need(fleet, 1000 nm).fits` stays true. A top-up never lowers `fleet_free_hold`. A top-up never exceeds `ship_stores_capacity`. NOT EXISTS a ship whose stores exceed her space. `fleet_load` reads `ship_free_hold`, with no second copy. PGlite chain test plus `fleet.supplies.spec.ts`, `desk.*` words. |
| **V3** | `every_new_ship_rolls_her_own` | `ship_roll(seed)`, `ship_grade`; `commission_ship` writes the roll (founding clamp, famous 1.000); `ship_view` serves `roll`, `grade`, `class_*`; `building_yard` serves the range. Client: tile % and grade, yard line, toast, EN/KO. | `ship_roll` over 1,000 fixed seeds: every factor within [0.80, 1.20], Poor and Fine each 30–70, normal tier within ±12 %. Deterministic. A probe build gives a row roll = `ship_roll(its id)`. A probe founding ship has every factor ≥ 1. Pre-mark ships unchanged. Vitest for the % format; a Playwright tile spec. |
| V4 | `the_store_ratio_is_gone` | drop `ships.store_ratio` and `store_ratio_default` once nothing reads them | no live body names them |

## 6. Risks

| Risk | Size | Handling |
|---|---|---|
| NPC laps re-planned | 837 fleets, all on standing routes | V1 and V2 leave speed byte-identical. V2 only opens legs (11 shut → 0) and adds 1.7 % room. `npc_plan` reads `fleet_speed` / `supply_need`, so it plans with the new figures on its next lap. |
| A Poor hull drags a fleet (formation reads the slowest) | ~5 % of new hulls, −8 to −20 % | shown on the tile before she joins a fleet. Moving ships between fleets (FLEETS_AND_SLOTS §2.4) is the remedy. |
| 0220 speed ×3 balance | ±12 % = ±1.8 kn on a barca; Fine is up to +3 kn | only new hulls. A Fine fleet earns about 10–20 % more per real hour, the same scale as a skill level. Watch human ducats/hour for 3 days after V3. |
| Standing routes | 0 human routes, 837 NPC | `leg_refusal` re-judges each lap. Stores no longer shrink as she loads, so a lap that loads full still sails. |
| Long NPC legs at full crew | the 55.9-day leg needs ~1.6 × crew needed | NPCs sail at crew needed (avg = needed). A full-crew hull carries 36 days × roll. `fits` refuses with words, never strands her. Revisit the 36 if prod shows E_ENDURANCE on merchants. |
| Insurance values | cargo-only | none |
| Crew max below crew needed | a Poor roll | clamp ≥ crew needed |
| Re-roll farming | a blind roll costs a full build | no cancel refund is added |
