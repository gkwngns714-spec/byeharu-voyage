# SHIPS AND GEAR — merchants with real slots and stats, more ship types, more gear, and levels

**Status:** architect's plan, 2026-10-15. Nothing is built. Written against `main` `28305e8`, production
head **0121**. Owner queue item 3 in `docs/RESUME.md:35` (*"Merchant ships: serve slots + combat
stats (server change), and make more ship types and more gear"*) plus the owner's addition the same
evening: *"we need levels, stats too."*

**Rules this plan is bound by.** One authority per concept, compose don't fork, retire the old
(`docs/NO_SPAGHETTI.md`); a deployed migration is never edited, it is re-cut by hunks that occur
exactly once (the `pg_temp.recut` method, 0074:46-66); every migration self-asserts in its own
transaction with a positive control; merchants are the same tables and the same executor as players
(`docs/NPC_TRADERS.md` §0); the arrivals tick has a hard 2-minute limit and averages ~14 s
(`docs/RESUME.md:29`); prod is live with ~30 players.

**Numbering.** The steps below are **S1 … S7**. The city-economy plan (`docs/ECONOMY_LOOP.md`)
holds **0122–0123**; these steps follow it, in deploy order: **S1 0124 · S2 0125 · S3 0126 · S5 0127
· S6 0128 · S4 0129**; S7 is a CI change with no migration. Provisional until the branch runs
`npm run db:check-versions`, which arbitrates. Every step is one migration unless it says "client
only".

**Owner decisions of 2026-10-15 folded in:** captain level is per signing; merchant captains and
merchant skills are constant and merchant hulls carry a fixed level; levelling is a long grind
(§4.2 gives the numbers); merchant gear is fixed, and whether merchants ever buy better gear is
deferred to the economy plan.

---

## 0. The answer in ten lines

1. A merchant's ship panel cannot match the player's because `world.npc_fleet_card` builds its
   `ships` list inline, without slots or the six combat stats (0099:321-333), while `world.fleets()`
   builds a richer object inline (0074:490-511). Two builders, one concept. **S1 extracts ONE ship
   builder, `world.ship_view(ship)`, and both reads call it.** The client already draws everything
   when it is served (`src/live/ShipPanel.tsx:20-22`).
2. Merchant hulls carry **no fittings at all** — `commission_ship` mounts nothing (0096:435-442) and
   `npc_found` never fits. **S2 gives every merchant hull an endowed loadout** through a sliced core
   of the player's own `cmd.do_fit`, chosen deterministically per fleet, backfilled once (~1,100
   hulls), and mounted for new merchants in `npc_found`. Nothing runs in the arrivals tick.
3. **Levels (S3):** ships and captains get an `xp` column written by exactly ONE function, the
   arrival arm of `voyage.settle` (the same place the `VOYAGE_REPORT` is written), and a level through
   the ONE curve that already exists, `public.level_from_points` (0069:105-112). A long grind: a hull
   running a route round the clock reaches level 10 in about a month and level 20 in about five
   (§4.2). A captain's level is per signing. The company's three tracks stay what 0069 made them;
   the combat track stops reading an honest zero and reads the pirate roll's own record.
4. **Merchant levels are fixed** (owner, 2026-10-15): a merchant hull's `xp` is written once, from
   her company's skill sum, and never moves; merchant officers and skills are constant. The settle
   hunk runs for player fleets only, by the one predicate `players.is_npc`, so the minute tick does
   no levelling work for the ~830 merchants. The reading is the same one reading for everyone.
5. What a level gives: small stat gains (handling, accuracy, sighting) inside the one stat reading
   `world.ship_stat`; **slot unlocks** as rows of the existing `class_slots` table with a `min_level`;
   **gear requirements** as `item_kinds.min_level`; a captain's level multiplies her own bonus inside
   the one officer reading `fleet_officer_bonus`.
6. **Combat stats bite (S4):** the pirate roll's escort score reads `attack/10` instead of `guns`,
   which is a proven no-op for every unfitted hull (the three classes were authored so that
   `guns = attack/10`: 0/2/12 against 0/20/120, 0003:2089-2091 and 0074:94-96), and armour turns a
   knob-sized share of hull damage, landing at 0.
7. **Eight new ship types (S5)** across three families and three tiers, with slots, stats, recipes
   and the yards that lay them down; **twelve new fittings (S6)** that each buy one stat and spend
   another, with recipes of goods this world sells and the workstation tier that makes them.
8. The world guard does NOT check ships or gear today (`scripts/db/world-guard.mjs:14-22` guards
   harbours, goods and sea places only) although `data/fittings.json:3` and `data/hulls.json:3` say
   "guarded". **S7 makes that sentence true.**
9. Cost: nothing in this plan adds a query to the minute tick except two tiny UPDATEs per PLAYER
   arrival (S3); a merchant arrival gets one boolean read. Slots, stats and loadouts are read at tap
   time only.
10. Owner questions: none open; §10 lists the decisions taken in and the one knob to turn if the
    grind reads wrong.

---

## 1. What exists today, one authority each (verified on the files)

### 1.1 Ship types

| what | where | notes |
|---|---|---|
| the class table | `public.ship_classes` — 0002:148-166 (code, name, family, rig ∈ square/lateen/mixed/oared, hold, crew_required, crew_max, speed_kn, durability, guns, draft 1-6, build_hours, build_cost, tier 1-5) | `build_cost` and `build_hours` are read by nothing (`docs/RESUME.md:69`; `src/domain/fleet/statGloss.ts:101-110` says so to the player) |
| the three rows | 0003:2086-2092 — `barca` 60 t · 8/20 crew · 5.00 kn · 400 · 0 guns · draft 1 · 12,000 · tier 1; `carlat` 90 · 12/30 · 6.00 · 550 · 2 · 1 · 26,000 · 2; `nau` 400 · 60/140 · 4.40 · 1,800 · 12 · 3 · 120,000 · 3 | all family `Western` |
| the six combat stats on the class | 0074:74-81 (handling 0-100, armour 0-100, attack ≥0, accuracy 0-100, reach 0-100, sighting >0); values 0074:93-96; authored in `data/ship_stats.json:6-37` | barca 70/5/0/0/20/8 · carlat 75/12/20/40/45/10 · nau 45/30/120/55/70/14 |
| how a hull is built | `public.hull_recipes` / `_goods` / `_items` 0072:78-97, rows 0072:103-142, authored in `data/hulls.json`; `cmd.do_build` 0072:169-285; the yards are `port_buildings(kind='building_yard')` placed by `dev_industry` (0072:159-166: ≥15 → tier 3, ≥12 → tier 2, else 1, at the 35 harbours with `yard_tier ≥ 3`) | derived from `scripts/lib/world-derive.mjs:526-530`. Today: tier 3 = Antwerp, Genoa, Hamburg, Lisbon, London, Marseille, Venice (7); tier 2 = Alexandria, Amsterdam, Bordeaux, Cádiz, Callao, Gdansk, Havana, Istanbul, Jakarta, Kochi, Kozhikode, Lübeck, Malacca, Manila, Old Goa, Salvador, Seville, Surat (18); tier 1 = Barcelona, Busan, Cartagena, Copenhagen, Guangzhou, Macau, Nagasaki, Osaka, Tokyo, Veracruz (10) |
| what the yard screen reads | `world.building_yard(port)` 0072:357-405; client `src/live/useBuildingYard.ts:15-17` | serves every hull with `buildable`, goods/items against what the player holds here |
| the class catalogue on the wire | `world.snapshot().ship_classes` = `to_jsonb(c)` per class (0009:97-98) | so the six 0074 stats ALREADY cross the wire; the client type `SnapshotShipClass` (`src/lib/rpc/types.ts:134-150`) just does not declare them. The Codex lists classes from it (`src/features/compendium/ShipsFace.tsx:26-39`) |
| silhouettes | `HullClass = 'barca' \| 'carlat' \| 'nau'` (`src/chart/mapTypes.ts:167`); `hullPath` draws barca and carlat and falls through to the nau shape (`src/chart/glyphs.ts:439-455`); half-lengths `glyphs.ts:132`; the map maps served names/codes to the union and anything else to `null` (`src/chart/liveWorld.ts:92-103`); the ship panel keeps its own name→code map (`ShipPanel.tsx:45-50`) | an unknown code is drawn as a class-less hull, not an error |

### 1.2 Slot kinds

| what | where |
|---|---|
| THE slot table | `public.class_slots (class_code, slot, count)` 0074:104-109; rows 0074:125-140: barca rig 1 · weapon 1 · ground-tackle 1 (3); carlat + steering 1, weapon 2 (5); nau rig 2 · weapon 3 · ground-tackle 1 · steering 1 · hull 1 · lookout 1 · flourish 1 (10). Authored in `data/ship_stats.json:39-43` |
| one authority, proven | 0077 removed the `guns` branch from `cmd.do_fit` (0077:65-80) and the `weapon` override from `world.fleets` (0077:83-90); `guns` keeps one job, the escort score (0077:92-96) |
| cabins | `public.class_cabins` 0074:111-114, rows 142-146 (3/4/5). **Nothing reads it** (0074:121-123) |
| the seven kinds, as the player sees them | `ShipPanel.tsx:80-88`: rig → Sail, weapon → Weapon, ground-tackle → Anchor, steering → Rudder, hull → Hull, lookout → Lookout, flourish → Flourish; a kind the server adds later still gets boxes (`ShipPanel.tsx:114-120`) |

### 1.3 The gear catalogue

| what | where |
|---|---|
| the twelve fittings | `public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier)` 0068:78-108; authored in `data/fittings.json` (generator `scripts/build-fittings-0068.mjs`) |
| what each does, in numbers | `public.item_effects (item_code, stat, delta)` 0074:149-154, rows 0074:161-192; the figurehead is the one fitting with no effect (0074:539-541 asserts it) |
| the rule | every fitting buys one stat and spends another — asserted in the world at 0074:532-541 and in the generator |
| recipes | `public.item_recipes` 0068:111-162 (2-5 goods each, every good sold somewhere: 0068:433-445) |
| ownership | `public.player_items (player, port, item, qty)` 0068:165-171 — items have a LOCATION |
| mounted | `public.ship_fittings (ship_id, item_code, qty)` 0074:205-210; RLS reads only your own (0074:219-221) |
| verbs | `MAKE` → `cmd.do_make` 0068:241-308 (a workstation of `ws_tier`, goods out of the HOLD); `FIT`/`UNFIT` → `cmd.do_fit` 0074:293-374 / `cmd.do_unfit` 0074:376-433 (docked only; capacity from `class_slots`; the item moves between `player_items` and `ship_fittings`) |
| workstations | `port_buildings(kind='workstation')` 0068:199-206: `dev_industry ≥ 13` → tier 3 (12 cities: Antwerp, Callao, Gdansk, Genoa, Hamburg, Kochi, Lisbon, London, Lübeck, Marseille, Surat, Venice), ≥ 9 → tier 2, ≥ 7 → tier 1; 71 cities in all |
| the workstation screen | `world.workstation(port, fleet)` 0068:359-394 |

### 1.4 Stats, and what reads them today

| stat | class column | the one effective reading | read by a rule today? |
|---|---|---|---|
| hold | `ship_classes.hold` | `world.ship_stat(ship,'hold')` 0074:224-263 → `public.ship_hold_capacity` (0074:271-280) | YES — cargo, stores, speed-by-load |
| speed | `speed_kn` | `ship_stat('speed')` → `voyage.ship_speed` (0074:282-287) | YES — the mover |
| draft | `draft` | `ship_stat('draft')` | YES — `voyage.sail_refusal` E_DRAFT |
| durability | `durability` (max) | hull points on `ships.durability` | YES — speed floor, repair, raids |
| handling | 0074 | `ship_stat('handling')` | NO rule reads it |
| armour | 0074 | `ship_stat('armour')` | NO |
| attack | 0074 | `ship_stat('attack')` | NO — the pirate roll reads `guns` (0027:334-336) |
| accuracy | 0074 | `ship_stat('accuracy')` | NO |
| reach | 0074 | `ship_stat('reach')` | NO |
| sighting | 0074 | `ship_stat('sighting')` | NO — `lookout_expertise` is pinned 0 since V0 (0006:686-687) |

The only combat in the game is the pirate roll in `voyage.settle` (live body re-cut through 0114):
`escort = Σ(guns + crew×0.02 + tier×3)` against `piracy_index × 40 × (0.5 + magnitude)`, five
outcomes by ratio (0027:334-345), crew and hull losses (0027:353-373), the payload with `outcome`,
`escort`, `raider` (0027:380-390). `docs/RESUME.md:69` already lists "attack/armour are unused".

### 1.5 Levels, skills and captains today

| what | where | what it is |
|---|---|---|
| the company's three tracks | `public.player_progress(player)` 0069:119-177 — trading (ledger turnover), exploration (ports + sea miles), combat (**honestly 0**, `playable:false`, 0069:176) | DERIVED from the append-only record, never stored (0069:179-182) |
| THE level curve | `public.level_from_points(points)` 0069:105-112: `floor(sqrt(points / level_points_per_step)) + 1`, floor 1, cap 20; knob `level_points_per_step` 25 (0069:89-99) | one curve for every track, on purpose ("level 4 means the same work whatever word is in front") |
| served | `world.player().levels` (0069:220) | the house screen |
| the four skills | `public.skills` 0016:57 (SEAMANSHIP/NAVIGATION/ACCOUNTING/HAGGLING), `player_skills` 0016:78, max `skill_max_level` 5 (0016:50) — studied for money at an academy | a merchant company's "level" on the city list is the SUM of its four skills (0113:18-27) |
| what levels gate today | 0107 `public.passage_gate` (0107:219-281): leg length by NAVIGATION (0107:47-53), hulls per fleet by SEAMANSHIP and fleets per house by TRADING level (0107:55-70), regions by exploration level (0107:72-79). **Merchants are exempt by `players.is_npc`** (0107:81-87) | the gate is called from `voyage.sail_refusal` and the route save door only |
| captains | = officers. `public.officers` 0015:55 (specialty, `bonus_pct` ≤ 25, wage, nation, home port), `public.player_officers` 0015:82 (one row per signing, posted per FLEET); THE reading `public.fleet_officer_bonus(fleet, specialty)` 0015:108-125, capped by `officer_bonus_cap_pct` 25 (0015:50) | `docs/WORDS.md:92`: "captain" is the PLAYER for their own fleets; the people are **officers**; a merchant's named master is flavour |
| the inn | who is in which inn is derived from (officer, port, shift, secret) — 0073; 0119 turns the room every `inn_captain_rotate_minutes` (0119:44-62) | nothing stored, nothing to level |
| crew | `ships.crew` is a COUNT (0004); wages, losses, the speed floor read the count | no identity, no level — and this plan gives it none |
| DESIGN_V1 §7 (captain rank S/A/B/C, roles, cabins) | `docs/DESIGN_V1.md:383-448` | design only; cabins unread; "rank is data, not four letters" |

### 1.6 Merchant ships today — why their panel cannot match

- A merchant company is a `players` row with `is_npc` (0096; the law restated at 0097:11-14). Its
  hulls are ordinary `ships` rows put in by THE one insert, `public.commission_ship` (0096:416-447),
  with the class's own numbers and **no fittings**.
- The card: `world.npc_fleet_card(fleet)` (0099:238) builds `ships` inline at 0099:321-333 — name,
  class NAME, flagship, durability/max, crew/required/max, hold (stowed)/rated, speed/rated, cargo,
  and `fittings` as `{name, qty}` only (0099:328-331). No `slots`, no `slot` on a fitting, none of the
  six stats, no class CODE.
- The player's: `world.fleets()` builds its ship object inline (0074:490-511, 0077:89-90) with the
  six stats, `fittings{code,name,slot,qty}`, `slots{kind:count}`, `cabins`.
- The client: `MerchantShip` (`src/lib/rpc/types.ts:1823-1839`) versus `FleetShip`
  (`types.ts:686-726`); `ShipPanel` draws slots and stats only when present and says so
  (`ShipPanel.tsx:20-22`, `:99-110` "the empties would be a guess at her class's slots",
  `:236-244`); the merchant sheet opens the panel per ship (`src/live/MerchantSheet.tsx:97,120`).
- The map reads merchant hull CODES from `world.sea_roster` (0118:56; 0113:112).
- Scale: 0098 founded 60 companies / 76 fleets / 131 hulls; 0105 founded 761 more companies, 761
  fleets, 761 hulls (0105:9-10) — **~820 companies, 837 fleets, ~890 hulls**, `npc_fleet_max` 861
  (0105:168-171; `docs/OWNER_REQUESTS.md` row 118).

### 1.7 Costs measured

- `tick_arrivals` (0010:54-83) settles only fleets with a day or an ETA due, `for update skip
  locked`. 0105:106-107 measured 291 ms a minute at 295 running routes and 17.9 s if every fleet
  arrived at once; since 0120 (planning at lap start, inside the tick) the job averages **14.3 s,
  max 46.8 s** (`docs/RESUME.md:29`). The hard limit is 2 min.
- `world.npc_fleet_card` 2.38 ms a call; `world.sea_traffic` 7 ms (NPC_TRADERS §3.3). The stat
  reading `world.ship_stat` is two queries per call and `world.fleets` calls it six times per hull.

---

## 2. The concepts, and their one home (NO_SPAGHETTI §7B)

| concept | home (one) | today's second copy, retired by | callers after |
|---|---|---|---|
| "what one ship is, on the wire" | **`world.ship_view(ship)`** (S1) | `world.fleets` inline (0074:490-511) and `npc_fleet_card` inline (0099:321-333) → both re-cut to call it | `world.fleets`, `world.npc_fleet_card`; later any read that prints a hull |
| "a ship's effective stats" | `world.ship_stat(ship, stat)` (0074:224) — stays the name; S1 makes `world.ship_stats(ship)` the one computation (ten stats in one query) and `ship_stat` a projection of it | — | `ship_hold_capacity`, `voyage.ship_speed`, `ship_view`, the escort score (S4) |
| "mount a fitting on a hull" | **`public.mount_fitting(ship, item)`** (S2): capacity by `class_slots` at her level, the insert | the same lines inside `cmd.do_fit` (0074:338-367), which becomes door + core | `cmd.do_fit` (the player, from the store), `public.npc_fit_loadout` (a merchant, endowed) |
| "how many slots of a kind this hull has NOW" | **`world.ship_slots(ship)`** (S3) over `class_slots` rows with `min_level ≤ her level` | `cmd.do_fit`'s `class_slots` read (0077:77-80) and `world.fleets`'s (0077:89-90) | `mount_fitting`, `ship_view` |
| "a hull's level" / "a captain's level" | `ships.xp`, `player_officers.xp` (S3) + `public.level_from_points` (0069) — ONE writer, `voyage.settle`, for player fleets; a merchant hull's `xp` is written once (S3's seed, `npc_found` for new ones) and never again | none exists | `ship_stats`, `ship_slots`, `mount_fitting`, `fleet_officer_bonus`, `ship_view`, `world.officers`, the card |
| "the company's levels" | `public.player_progress` (0069) — unchanged shape; combat track derived from `voyage_events` (S3) | none | `world.player`, `passage_gate` (0107), `cmd.do_build` (S5 min level) |
| "a merchant's loadout" | `public.npc_loadouts (class_code, pattern, item_code, qty)` (S2) — authored data | none | `npc_fit_loadout` only |
| "which yard may lay a hull down" | `hull_recipes.yard_tier` (0072) + `hull_recipes.yard_regions` (S5) + `hull_recipes.min_level` (S5), all read in `cmd.do_build` and printed by `world.building_yard` | none | `do_build`, `building_yard` |

Wrong shapes, and the guards that catch them: a merchant-only ship builder (S1's assert reads the
live bodies of `world.fleets` and `npc_fleet_card` and fails if either still contains
`'fittings', (select`); a second writer of `ship_fittings` beside `mount_fitting`/`do_unfit` (S2's
assert scans every live body for `insert into public.ship_fittings` — positive control first); a
second writer of `xp` (S3, same method, token `set xp`); an `is_npc` test inside `ship_stat`,
`ship_view` or `mount_fitting` (S1/S2/S3 asserts: the token `is_npc` must not occur in those bodies).

---

## 3. Merchant ships get slots and stats

### 3.1 S1 — one ship builder, `world.ship_view(ship)`

The precedent is 0099 itself: it sliced the voyage object out of `world.fleets` into
`world.voyage_view` and had both reads call it, proving the player's payload byte-identical
(0099 header, "the voyage object lives verbatim in world.voyage_view"). Do the same for the ship:

- `world.ship_view(p_ship uuid) returns jsonb`, server-only, `stable`, `security definer`: exactly
  the keys `world.fleets` serves today (0074:490-511 as re-cut by 0077) — plus `class_code` (the
  code, so the client stops keeping a name→code map, `ShipPanel.tsx:45-50`) and `max_durability`.
  Order of keys and every value identical to today's for a player's hull.
- Re-cut `world.fleets()`: the inline ship object → `world.ship_view(s.id)`. Self-assert: a
  pre-image of `world.fleets()` for every fleet in the world (merchants included — the function is
  identity-free on the server) equals the post-image once `class_code`/`max_durability` are
  stripped, jsonb-equal, over all hulls.
- Re-cut `world.npc_fleet_card`: the inline `ships` → `jsonb_agg(world.ship_view(s.id) order by
  s.is_flagship desc, s.name)`. The merchant's ship gains `slots`, `fittings[].slot`, the six stats,
  `cabins`, `class_code`. Nothing a player may not know is in it: these are class data and what is
  mounted — the same keys the owner's own hull shows. (`ship_fittings` RLS is by `auth.uid`,
  0074:219-221; the card is `security definer`, as it already is for `fittings`.)
- `world.ship_stats(p_ship) returns jsonb`: the ten effective stats in ONE query (base from the
  class, `sum(delta × qty)` grouped by stat over `ship_fittings × item_effects`, the 0074 floors).
  `world.ship_stat(ship, stat)` is re-cut to `(world.ship_stats(ship) ->> stat)::numeric` and keeps
  raising `E_NO_SUCH_STAT` on an unknown name. Self-assert: for every hull afloat and every one of
  the ten names, old and new agree to the digit (pre-image taken before the re-cut).

Cost: `world.fleets` per hull goes from 6 × 2 queries to 1; `npc_fleet_card` gains ~1 ms per ship.

### 3.2 S2 — merchant loadouts, endowed and deterministic

Merchants do not visit workstations and do not hold `player_items`; their hulls are endowed
(0004:308's Gaivota, 0096 comment at 0096:445-447). Their gear is endowed the same way, and the
plan says so rather than inventing a merchant shopping trip.

- **Slice `cmd.do_fit`** (0074:293-374) into door + core, the 0096 method (NPC_TRADERS §3.1):
  `public.mount_fitting(p_ship, p_item_code)` = the slot-capacity check (0074:343-359, reading
  `world.ship_slots` after S3; `class_slots` before it) + the `ship_fittings` upsert (0074:366-367).
  The door keeps DOCKED, the item lookup, the store debit (0074:361-364), the event and the return
  shape. Reverse-substitution proves the door is its pre-image plus the call.
- **`public.npc_loadouts (class_code, pattern smallint, item_code, qty)`**, authored in
  `data/npc-loadouts.json`, three patterns per class, each within the class's slots:
  *trader* (sails + anchor + hold fittings where there is a hull slot), *armed trader* (sails +
  anchor + boarding gear / broadside guns), *convoy* (nau/galleon-class: 2 sails, anchor, rudder,
  copper sheathing, broadside guns ×2, crow's nest). Patterns never fill every slot — a full hull
  is the player's design, not the world's default.
- **`public.npc_fit_loadout(p_ship)`**: pattern = `('x' || left(md5(fleet_id::text), 8))::bit(32)::int % 3`
  (deterministic per fleet, no secret needed: nothing here is a lottery a player could replay),
  then `mount_fitting` per row. Server-only.
- **Backfill in the migration:** every hull whose company `is_npc` and which carries no fitting →
  `npc_fit_loadout`. ~890 hulls × ≤ 6 rows, one statement each; measured on the apply.
- **`npc_found`** (0097:241): one hunk after each `commission_ship` → `npc_fit_loadout(v_ship)`.
- Self-assert: every merchant hull has ≥ 2 fittings and none exceeds its slots (recomputed from
  `class_slots`, not from the function); a player's hull is untouched (count of player
  `ship_fittings` rows before = after); the card for a probe merchant serves `slots` with at least
  one `fitted` box; `cmd.do_fit` under a probe player still refuses `E_SLOTS_FULL` on a full slot
  (0077:163-174 replayed) — the door still gates.
- **Fixed for good (owner, 2026-10-15):** a merchant never changes her gear. Whether merchants
  should one day buy better gear is the economy plan's question and is deferred there.
- **What this changes in the live economy, said plainly:** a suit of sails is +0.6 kn and −8
  handling; hold fittings +25 t. Merchants with loadouts sail a little faster and carry a little
  more, which moves lap profits upward. Measure after: zero-net lap share and arrivals duration,
  exactly as 0120 was measured (`docs/RESUME.md:33`).

### 3.3 The client (S1/S2, client only, one PR with S1)

- `src/lib/rpc/types.ts`: retire `MerchantShip` (1823-1839) — `MerchantCard.ships` becomes
  `FleetShip[]` minus `id`-dependent keys, or simply `ShipView` as served. One served ship type.
- `ShipPanel.tsx`: delete `CLASS_CODE` (45-50) and read `ship.class_code`; keep `slots?`/stats
  optional for one release so a stale bundle against the old server still renders (the 2026-09-11
  law: never ship a client ahead of its database — the order is S1 deployed, then the client).
- `MerchantSheet.tsx:284-299` `ShipTile` gains nothing; it already takes `fittings` (`src/components/ui/ShipTile.tsx:41`).
- `tests/map.merchants.spec.ts`: the merchant ship panel shows `ship-equipment` boxes with a
  fitted count `n / m` where `m` = the class's slots, and the six stat tiles.

---

## 4. Levels and stats (S3)

### 4.1 Who has a level

| who | the number | where it lives | the curve | writer |
|---|---|---|---|---|
| a **ship** | her sea miles and fights, as points | `ships.xp numeric not null default 0` | `public.level_from_points(xp)` (0069) via `world.ship_level(ship)` | `voyage.settle`, arrival arm + PIRATES arm, **player fleets only** — the ONE writer. A merchant hull's value is written once and never moves (§4.5) |
| a **captain** (officer signing) | the miles and fights of the fleet she was posted to | `player_officers.xp numeric not null default 0` | the same curve via `world.captain_level(player_officer_id)` | the same hunk (`where fleet_id = p_fleet`). **Per signing** (owner, 2026-10-15): dismissed and hired again, she is a new row at 0. A merchant's officers stay at 0 for ever |
| the **company** | three tracks | `public.player_progress` (0069) — unchanged home | the same curve | nothing: derived |
| crew | none | — | — | a count has no level; morale (DESIGN_V1 §7.2) is its own future slice |

Why a stored `xp` and not a derivation like 0069: a ship's miles cannot be re-read from the
record — `VOYAGE_REPORT` names a fleet, not her hulls, and a merchant's events are compacted to a
rolling window (`npc_compact`, 0097:883-889). A counter written by the one function that also
writes the report, in the same transaction, is as honest as the report; the assert that exactly one
live body writes it is the farm-loop guard. Points use the same unit as the company's exploration
track (`fame_nm_per_point` 100, 0069:89-93) so "a level" means the same work everywhere.

### 4.2 How XP is earned

| event | who gains | points | where it is written | knob |
|---|---|---|---|---|
| a voyage arrives (the `VOYAGE_REPORT`, `total_nm`) | every hull in a PLAYER's fleet; every officer posted to it (never a merchant's: §4.5) | `total_nm / ship_xp_nm_per_point` | `voyage.settle` arrival arm (0036:515-524 as cut; live through 0114): one `is_npc` read, then two UPDATEs after the report | `ship_xp_nm_per_point` **1,000** |
| pirates EVADED | the same | +5 | the PIRATES arm, after the outcome (0027:338-345) | `xp_evaded_points` 5 |
| pirates DRIVEN_OFF | the same | +15 | same | `xp_driven_off_points` 15 |
| RANSOM / PLUNDERED / STRIPPED | nobody | 0 | — | — |
| a trade | nobody per hull — trading is the COMPANY's track (0069, turnover) | — | derived already | `fame_ducats_per_point` |
| the company's combat track | the company | +5 per EVADED, +15 per DRIVEN_OFF, read from `public.voyage_events` (0006:89) joined through `voyages.fleet_id` (0006:56) to `fleets.player_id`, `payload->>'outcome'` | `player_progress` re-cut: `combat.playable = true`, points derived | the same two knobs |

**The curve, and why it is a long grind.** One curve for everything, `public.level_from_points`
(0069:105-112): `level = floor(sqrt(points / 25)) + 1`, cap 20 — so level L costs `(L−1)² × 25`
points. The pace lever is how many sea miles make a point, and it is set high on purpose (the
owner, 2026-10-15: a long grind): **`ship_xp_nm_per_point` = 1,000**. The company's exploration
track keeps its own 100 nm a point (0069:89-93) because 0107's gates read those levels and
re-pacing them would re-gate live players.

At the 960× voyage clock (0100) a 5-kn hull makes 4,800 nm a real hour at sea (5 × 24 × 40
voyage-days an hour). Two profiles: a hull that **runs a route round the clock**, at sea ~60 % of
the time (~65,000 nm a real day), and a hull **sailed in sessions**, at sea ~3-4 real hours a day
(~16,000 nm a day).

| level | points | sea miles | Cape laps (Lisbon–Cape–Kochi–Goa–Mozambique–Lisbon, ≈ 19,600 nm) | Lisbon–Cádiz hops (188 nm) | round-the-clock route hull | session hull |
|---|---|---|---|---|---|---|
| 2 | 25 | 25,000 | 1.3 | 133 | ~9 hours | ~1.5 days |
| 3 | 100 | 100,000 | 5 | 532 | 1.5 days | 6 days |
| 5 | 400 | 400,000 | 20 | 2,128 | 6 days | 25 days |
| 10 (mid) | 2,025 | 2,025,000 | 103 | 10,771 | **~1 month** (31 days) | ~4 months |
| 15 | 4,900 | 4,900,000 | 250 | 26,064 | 2.5 months | 10 months |
| 20 (max) | 9,025 | 9,025,000 | 460 | 48,005 | **~4.5 months** (139 days) | ~19 months |

A faster hull levels faster (a xebec at 6.6 kn is a third quicker than a barca; an Indiaman at
4.5 kn a tenth slower). A fight won is 5 or 15 points — 5,000 or 15,000 miles' worth, a real
bonus for a rare event and never a farm, because the raider decides whether there is a fight.
Captains pace exactly with the hull they are posted to, and per signing: dismissed and hired
again, she starts at 0. If the grind reads wrong it is one UPDATE of `ship_xp_nm_per_point`.

Seeding at apply, once: a player's hull gets Σ `total_nm` of her fleet's own `VOYAGE_REPORT`s
(the sum 0069 already reads) and her posted officers the same figure — honest history, and at
1,000 nm a point a modest start (a house that has sailed 100,000 nm opens at level 3). A merchant
hull gets a FIXED value (§4.5). Written once; after that only `settle` moves a player's.

### 4.3 What a level gives

| level of | what it gives | where (one place) | default knobs |
|---|---|---|---|
| ship | **stat gains** per level above 1: handling +1, accuracy +1.5, sighting +0.15 (a worked-up ship: the crew knows her) | the one stat computation `world.ship_stats` adds `level_bonus(stat, level)`; proven zero at level 1 | `ship_level_handling_per_level` 1 · `ship_level_accuracy_per_level` 1.5 · `ship_level_sighting_per_level` 0.15 |
| ship | **slot unlocks** — rows of `class_slots` with `min_level > 1` (table in §6.2); a locked slot is served as `slots_locked {kind: {count, at_level}}` and drawn dimmed with "Level 6" | `class_slots` gains `min_level int not null default 1` and the PK becomes `(class_code, slot, min_level)`; `world.ship_slots(ship)` sums rows with `min_level ≤ level`. Existing rows keep 1, so **nothing already mounted is ever in a locked slot** | the rows |
| ship | **gear requirements** — `item_kinds.min_level` (default 1; the twelve of today stay 1) | `mount_fitting` refuses `E_SHIP_LEVEL` with figures `{have: her level, need: min_level}` in 0050's shape | the rows |
| captain | her own bonus × `(1 + captain_level_pct_per_level × (level − 1))`, still under `officer_bonus_cap_pct`; per signing — the multiplier belongs to the `player_officers` row and dies with it | `public.fleet_officer_bonus` (0015:108-125): one hunk, `o.bonus_pct` → `o.bonus_pct × world.captain_level_mult(po.id)` | `captain_level_pct_per_level` 2 (a level-10 navigator at 6 % is worth 7.08 %; a merchant's officers stay at level 1, multiplier 1) |
| company — trading | fleets per house (0107, exists); **hull build requirement** `hull_recipes.min_level` (S5: galleon 5, indiaman 6; today's three stay 1) | `cmd.do_build` refuses `E_LEVEL` with figures; `world.building_yard` prints `min_level` and `your_level` | the rows |
| company — exploration | regions (0107, exists) | — | — |
| company — combat | playable from S3; nothing gates on it yet — said on the screen rather than invented | — | — |
| a switch | `levels_bite` (bool, default **true** at apply after the dry run; **false** turns every effect above off while XP keeps accruing) | read in `ship_stats`, `ship_slots`, `mount_fitting`, `fleet_officer_bonus`, `do_build` | `levels_bite` |

### 4.4 The stat list, and what each feeds

| stat | feeds today | S3/S4 wires | stays inert (and the screen says so) |
|---|---|---|---|
| hold | cargo, stores, load→speed | — | — |
| speed | passage time | — | wind (`wind_mult_v0` 1.00) |
| draft | harbour entry | — | — |
| durability | speed floor, repair cost, raids | S4: armour reduces the loss | — |
| handling | nothing | S3: +1 per ship level | course efficiency / fight position (DESIGN §1.2) — not built |
| armour | nothing | S4: `hull loss × (1 − armour/100 × armour_turns_pct)`, knob lands at **0** | — |
| attack | nothing | S4: escort reads `attack/10` in place of `guns` — a no-op for every unfitted hull of every class (data rule: `guns = attack/10`) | — |
| accuracy | nothing | S3: +1.5 per ship level | S4 does NOT read it: the roll has no "shot tells" step; wiring it is the combat slice, not this one |
| reach | nothing | — | the band she fights at — the combat slice |
| sighting | nothing | S3: +0.15 per ship level | `lookout_expertise` stays 0 (0006:686) until the hazard roll is re-cut to read it — named as the next step, not done here |

### 4.5 Merchants: fixed levels, the same reading, no work in the tick

The owner (2026-10-15): merchant captains and merchant skills are constant for now. The choice for
merchant hulls, made here for consistency: **constant too — a fixed value, assigned once.**

- A merchant hull's `xp` is written once by S3's seed: the points of level `1 + floor(skill_sum / 3)`,
  where `skill_sum` is the company's four skill levels added — the number the city list already
  prints as her level (0113:18-27). A sum of 0 is level 1, 12 is level 5, the best companies (20)
  level 7. A merchant founded later gets the same value in `npc_found` (one hunk after
  `commission_ship`, beside S2's loadout hunk). It never moves afterwards.
- The reading is the one reading: `world.ship_level(ship) = level_from_points(ships.xp)`, served
  through `ship_view` like any hull. There is no merchant level column and no merchant level
  function.
- Merchant officers: `player_officers.xp` stays 0, so `captain_level_mult` is 1 and her
  `bonus_pct` is exactly what `npc_found` signed. The card serves no officer level.
- Merchant skills: set once by `npc_found` (0097:241); nothing in the chain raises them today and
  this plan adds nothing that does.
- **The settle hunk does not run for a merchant fleet.** It reads the ONE predicate `players.is_npc`
  once per arrival — the way the crew floor (0097) and the fortnight's rest (0101) read it
  (0107:84-86) — and skips both UPDATEs. No `auth_uid is null`, no name test, no second spelling
  of "merchant" (NPC_TRADERS §1.1). `passage_gate` keeps its own `is_npc` exemption (0107:81-87)
  untouched. The company tracks (`player_progress`) are not served on the card and are not needed.
- Her loadout (S2) is authored within her class's level-1 slots, so a locked slot never holds
  anything and nothing about her depends on a level that does not grow.

### 4.6 Cost on the arrivals tick

Per PLAYER arrival: one read of `players.is_npc` by primary key (the fleet row is already in hand),
then `update public.ships set xp = xp + :pts where fleet_id = p_fleet` (≤ 8 rows; `settle` already
updates `ships … where fleet_id = p_fleet` in the raid arm, 0027:365-370) and `update
public.player_officers set xp = xp + :pts where fleet_id = p_fleet` (0-3 rows). Under a
millisecond, on the ~30 players' arrivals only. For the ~830 merchants — most of what the tick
settles — the hunk is one boolean read and nothing else. Levels are READ at tap time (`ship_view`)
and inside `fleet_officer_bonus`, which already runs per speed/hold/spread reading — one more
column on the row it already reads. No cron, no table scan, no new job; the tick that averages
14 s because of 0120's lap-start planning does not notice.

---

## 5. Combat stats bite (S4)

- Re-cut the PIRATES arm of `voyage.settle` (0027:334-336 as cut): `sum(c.guns + …)` →
  `sum(world.ship_stat(sh.id, 'attack') / 10 + sh.crew × 0.02 + c.tier × 3)`.
  Self-assert: for every fleet in the world the new escort equals the old to 4 places when no
  weapon fitting is mounted (pre-image over all fleets, computed with both formulas); for a probe
  hull with broadside guns mounted the escort is strictly higher; `guns` is no longer read in
  `settle` (token scan with a positive control) and `ship_classes.guns`'s comment is re-written to
  say it is now a data mirror of `attack/10`, asserted equal for every class.
- Storm and raid hull loss × `(1 − armour/100 × armour_turns_pct)`; knob `armour_turns_pct`
  lands at **0** (no-op, proven on a pre-image); the probe flips it to 0.5 in a rolled-back block
  and shows a nau losing 15 % less hull than a barca. The owner turns it on by one UPDATE.
- Not here: accuracy, reach, sighting (§4.4). Said in the header so nobody reads them as wired.

---

## 6. New ship types (S5)

Eight new classes, eleven in all. Three families (`Western`, `Mediterranean`, `Eastern`), three
tiers. Numbers are set against the three that exist (barca 60 t/5.0 kn, carlat 90/6.0, nau
400/4.4) so that a bigger hull is slower, a fighting hull carries less, and tier is paid for in
crew and ducats as well as timber. The data rule the assert pins: **`guns = attack/10`** for every
class, so S4's escort re-cut stays a no-op for unfitted hulls of every type.

### 6.1 The classes

| code | name | family · rig | tier | hold t | crew req/max | kn | hull | draft | guns | buy price | yard labour | yard tier | built where (`yard_regions`) | min trading level | role |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `pinnace` | Pinnace | Western · mixed | 1 | 35 | 6 / 16 | 6.4 | 300 | 1 | 0 | 10,000 | 2,500 | 1 | any yard | 1 | scout: fast, sees far, carries little |
| `dhow` | Dhow | Eastern · lateen | 1 | 75 | 9 / 22 | 5.2 | 380 | 1 | 0 | 11,000 | 2,800 | 1 | WIA ARA EAS SOU (Kochi, Kozhikode, Old Goa, Surat, Jakarta, Malacca, Manila) | 1 | the Indian Ocean coaster; a barca with a bigger hold |
| `carred` | Caravela redonda | Western · square | 2 | 130 | 16 / 40 | 5.6 | 650 | 2 | 4 | 34,000 | 9,000 | 2 | IBE FRA BRI WES ADR BAL CAR STH PAC | 2 | the all-round trader |
| `fluyt` | Fluyt | Western · square | 2 | 240 | 10 / 26 | 4.9 | 700 | 2 | 2 | 40,000 | 10,000 | 2 | FRA BAL BRI (Amsterdam, Antwerp, Hamburg, Lübeck, Gdansk, London) | 3 | the bulk hauler: a nau's share of cargo on a carlat's wages |
| `xebec` | Xebec | Mediterranean · mixed | 2 | 70 | 28 / 90 | 6.6 | 480 | 1 | 5 | 30,000 | 8,000 | 2 | WES ADR LEV AEG IBE (Genoa, Marseille, Venice, Alexandria, Istanbul, Cádiz, Seville, Lisbon) | 3 | the fast escort and boarder; big crew, small hold |
| `junk` | Junk | Eastern · mixed | 2 | 200 | 20 / 60 | 4.8 | 850 | 2 | 2 | 38,000 | 9,500 | 1 | CHI JAP KOR SOU (Guangzhou, Macau, Nagasaki, Osaka, Tokyo, Busan, Jakarta, Malacca, Manila) | 2 | the sturdy eastern trader: watertight bulkheads, hard to sink |
| `galleon` | Galleon | Western · square | 3 | 320 | 80 / 220 | 4.7 | 2,100 | 3 | 17 | 150,000 | 38,000 | 3 | the seven great yards | 5 | the armed convoy: fights at range |
| `indiaman` | East Indiaman | Western · square | 3 | 520 | 70 / 180 | 4.5 | 2,000 | 3 | 11 | 170,000 | 42,000 | 3 | the seven great yards | 6 | the long-haul trader: more hold than anything afloat |

The junk's yard tier is 1 on purpose: every eastern yard derives as tier 1 (`world-derive.mjs:530`,
`dev_industry` 10 at Guangzhou/Nagasaki/…), and a junk is the hull those yards have always built.
`yard_regions` is a new nullable `text[]` on `hull_recipes` read by ONE new gate in `cmd.do_build`
(`E_WRONG_COAST: a junk is laid down in the East`); null = any yard of the tier. `min_level` is the
company's TRADING level from `player_progress`; the three existing hulls stay at 1 so nothing a
player can build today is taken away.

### 6.2 The six stats, and the slots (with level unlocks)

| code | handling | armour | attack | accuracy | reach | sighting | rig | weapon | ground-tackle | steering | hull | lookout | flourish | total | cabins | unlocks (`min_level` rows) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| barca (exists) | 70 | 5 | 0 | 0 | 20 | 8 | 1 | 1 | 1 | – | – | – | – | 3 | 3 | +1 lookout @3 |
| carlat (exists) | 75 | 12 | 20 | 40 | 45 | 10 | 1 | 2 | 1 | 1 | – | – | – | 5 | 4 | +1 hull @4 |
| nau (exists) | 45 | 30 | 120 | 55 | 70 | 14 | 2 | 3 | 1 | 1 | 1 | 1 | 1 | 10 | 5 | +1 weapon @6 |
| `pinnace` | 86 | 4 | 0 | 0 | 20 | 10 | 1 | 1 | 1 | – | – | 1 | – | 4 | 3 | +1 flourish @3 |
| `dhow` | 72 | 5 | 0 | 0 | 20 | 8 | 1 | 1 | 1 | – | 1 | – | – | 4 | 3 | +1 lookout @3 |
| `carred` | 68 | 14 | 40 | 42 | 50 | 11 | 2 | 2 | 1 | 1 | – | – | – | 6 | 4 | +1 hull @4, +1 lookout @6 |
| `fluyt` | 55 | 10 | 20 | 35 | 45 | 9 | 1 | 1 | 1 | 1 | 2 | – | – | 6 | 4 | +1 hull @5 |
| `xebec` | 88 | 8 | 50 | 38 | 30 | 11 | 2 | 2 | 1 | 1 | – | – | – | 6 | 4 | +1 weapon @5 |
| `junk` | 58 | 20 | 20 | 30 | 40 | 9 | 2 | 1 | 1 | – | 2 | – | – | 6 | 4 | +1 weapon @5 |
| `galleon` | 42 | 36 | 170 | 58 | 75 | 14 | 2 | 4 | 1 | 1 | 1 | 1 | 1 | 11 | 5 | +1 weapon @6, +1 hull @10 |
| `indiaman` | 40 | 30 | 110 | 50 | 65 | 13 | 2 | 3 | 2 | 1 | 2 | 1 | 1 | 12 | 5 | +1 hull @6, +1 rig @10 |

0074's assert (c) "slots grow with the tier" is re-asserted over all eleven: every tier-2 total >
every tier-1 total, every tier-3 > every tier-2 (at level 1).

### 6.3 Recipes (timber out of the warehouse, fittings out of the store, labour in ducats)

| code | goods (`hull_recipe_goods`) | fittings (`hull_recipe_items`) | labour |
|---|---|---|---|
| `pinnace` | timber 25, tar 5, cordage 4, ships-nails 6 | suit-of-sails 1, anchor-and-cable 1 | 2,500 |
| `dhow` | teak 30, coir 8, tar 4, ships-nails 4 | suit-of-sails 1, anchor-and-cable 1 | 2,800 |
| `carred` | timber 80, naval-timber 25, tar 12, cordage 12, ships-nails 20 | suit-of-sails 2, anchor-and-cable 1, rudder-and-helm 1 | 9,000 |
| `fluyt` | timber 110, norway-spruce 20, tar 15, cordage 10, ships-nails 24 | suit-of-sails 1, anchor-and-cable 1, rudder-and-helm 1, hold-fittings 1 | 10,000 |
| `xebec` | naval-timber 40, timber 50, tar 10, cordage 14, ships-nails 16 | suit-of-sails 2, anchor-and-cable 1, rudder-and-helm 1, boarding-gear 1 | 8,000 |
| `junk` | teak 70, timber 40, tar 10, rattan 10, ships-nails 12 | suit-of-sails 2, anchor-and-cable 1, hold-fittings 1 | 9,500 |
| `galleon` | live-oak 110, naval-timber 50, timber 70, tar 30, ships-nails 50 | suit-of-sails 3, anchor-and-cable 2, rudder-and-helm 1, copper-sheathing 1, broadside-guns 1 | 38,000 |
| `indiaman` | live-oak 100, naval-timber 60, timber 80, tar 30, ships-nails 50 | suit-of-sails 3, anchor-and-cable 2, rudder-and-helm 1, hold-fittings 2, copper-sheathing 1 | 42,000 |

Every good named exists in `data/goods.json` (checked: teak, coir, rattan, norway-spruce are
`ship-supplies`); 0072's asserts (b) "sold somewhere", (c) "every hull has a yard", (d) "fits in
the shed it is built from" are re-run over all eleven. If (d) refuses the galleon or the indiaman,
the timber lines are trimmed, not the assert.

Silhouettes: `HullClass` grows to eleven codes; `hullPath` gets eight new shapes (a dhow's raked
lateen, a junk's battened sails, a galleon's high stern); `hullHalfLength` per code. Until drawn,
`liveWorld.ts:103` renders an unknown code as the class-less hull — nothing breaks on the map.

---

## 7. New gear (S6)

Twelve new fittings, twenty-four in all. Every one buys one stat and spends another (0074's rule,
re-asserted); the figurehead stays the single exception. `min_level` is the SHIP's level
(`mount_fitting` refuses below it); `ws tier` is the workstation needed (tier 1 = 71 cities, tier 2
= 47, tier 3 = the twelve in §1.3).

| code | name | slot | buys | spends | effects (`item_effects`) | vol | ws tier | min ship level | recipe (`item_recipes`) |
|---|---|---|---|---|---|---|---|---|---|
| `storm-canvas` | Storm Canvas | rig | durability, handling | speed | durability +50 · handling +4 · speed −0.25 | 3 | 1 | 1 | canvas-duck 4, cordage 2, tar 1 |
| `studding-sails` | Studding Sails | rig | speed | handling, durability | speed +0.9 · handling −14 · durability −30 | 4 | 2 | 4 | sailcloth 5, norway-spruce 2, cordage 3 |
| `whipstaff` | Whipstaff | steering | handling | hold | handling +7 · hold −2 | 2 | 1 | 1 | timber 3, iron 1, hemp 1 |
| `binnacle-and-charts` | Binnacle & Charts | steering | sighting, handling | hold | sighting +3 · handling +5 · hold −3 | 2 | 3 | 3 | sea-charts 2, brass-ingots 1, lignum-vitae 1 |
| `sheet-anchor` | Sheet Anchor | ground-tackle | durability (weather-holding), handling | hold | durability +60 · handling +2 · hold −10 | 5 | 2 | 2 | iron 6, hemp 6, tar 1 |
| `capstan` | Capstan | ground-tackle | handling, a little speed | hold | handling +6 · speed +0.1 · hold −5 | 3 | 2 | 3 | live-oak 3, iron 2, tallow 1 |
| `bilge-pumps` | Bilge Pumps | hull | durability | hold | durability +90 · hold −5 | 3 | 1 | 1 | timber 3, lead 2, hides 1 |
| `doubled-planking` | Doubled Planking | hull | armour, durability | speed, hold | armour +10 · durability +160 · speed −0.45 · hold −12 | 6 | 2 | 3 | live-oak 6, ships-nails 4, oakum 2, pine-pitch 1 |
| `swivel-guns` | Swivel Guns | weapon | attack, accuracy | handling | attack +20 · accuracy +8 · handling −2 | 2 | 2 | 1 | bar-iron 3, timber 1, shot-and-ball 1 |
| `stern-chasers` | Stern Chasers | weapon | reach, accuracy | hold | reach +20 · accuracy +10 · hold −8 | 4 | 3 | 4 | culverin 2, live-oak 2, shot-and-ball 2 |
| `carronades` | Carronades | weapon | attack | reach, hold, handling | attack +90 · reach −15 · hold −14 · handling −4 | 5 | 3 | 5 | bar-iron 8, brass-ingots 2, gunpowder 2 |
| `topgallant-mast` | Topgallant Mast | lookout | sighting, a little speed | handling, durability | sighting +7 · speed +0.2 · handling −8 · durability −30 | 3 | 2 | 3 | riga-mast 2, cordage 3, tar 1 |

Balance against what exists: broadside guns (attack +60, reach +15, hold −20, handling −6, tier 3)
stay the standard gun deck; carronades out-hit them at the cost of range and need a level-5 hull;
swivel guns are the cheap tier-2 defence a barca can mount in her one weapon slot. Storm canvas
and bilge pumps are tier-1 "keep her alive" gear for the first week; studding sails are the
exploration prize behind level 4. Every recipe good is in `data/goods.json` (riga-mast,
pine-pitch, sea-charts, brass-ingots, culverin, shot-and-ball, hides, sailcloth checked); 0068's
asserts (a) 2-5 inputs, (b) no dead ingredient, (d) every fitting makeable somewhere, and 0074's
(a) buys-and-spends, (b) a slot for every fitting, are re-run over all twenty-four.

---

## 8. The build steps

Each step is one migration with its own self-assert (positive controls first), its knobs, its
rollback, and the client change that rides with it. The economy plan holds 0122–0123; provisional
numbers in deploy order: **S1 0124 · S2 0125 · S3 0126 · S5 0127 · S6 0128 · S4 0129**, S7 none
(`npm run db:check-versions` arbitrates on the branch). Every prod push follows `docs/DEPLOY_RUNBOOK.md`: dry
run inside `begin … rollback` with `set local statement_timeout`, then `unwind_the_clock()` →
`db push` → `wind_the_clock()`.

| step | changes | self-assert | knobs | rollback | client |
|---|---|---|---|---|---|
| **S1** one ship builder | `world.ship_stats(ship)` (ten stats, one query); `world.ship_stat` re-cut to project it; `world.ship_view(ship)` with `class_code` + `max_durability`; `world.fleets` and `world.npc_fleet_card` re-cut to call it | pre-image of `world.fleets()` for every fleet and of the card for every merchant equal the post-image with the two new keys stripped; every hull × ten stats agree to the digit; neither live body still contains `'fittings', (select`; no `is_npc` token in `ship_view`/`ship_stats`; 0 client write grants, no new entry point | none | one forward migration re-cutting both readers to the inline bodies kept in S1's header (the pre-image is printed in the apply notice); `ship_view` dropped | types: one served ship type; `ShipPanel` reads `class_code`, drops `CLASS_CODE`; spec: merchant panel shows slots + stats |
| **S2** merchant loadouts | `mount_fitting` core sliced out of `do_fit`; `npc_loadouts` table + `data/npc-loadouts.json`; `npc_fit_loadout`; backfill every bare merchant hull; `npc_found` hunk | door = pre-image + call (reverse substitution); every merchant hull ≥ 2 fittings, none over its slots (recomputed from `class_slots`); player rows untouched (count before = after); a probe player's `FIT` still refuses `E_SLOTS_FULL`; only `mount_fitting` and `do_unfit` write `ship_fittings` (live-body scan, positive control); backfill time printed | none (data) | `delete from ship_fittings where ship's company is_npc`; `npc_found` hunk re-cut out | none (S1's panel draws them). After deploy: measure zero-net lap share and arrivals avg/max against `RESUME.md:29` |
| **S3** levels | `ships.xp`, `player_officers.xp`; `class_slots.min_level` + PK; `item_kinds.min_level`; `world.ship_level`, `world.captain_level`, `world.captain_level_mult`, `world.ship_slots`; `settle` arrival + PIRATES hunks; `ship_stats` level term; `mount_fitting` reads `ship_slots` + `min_level`; `fleet_officer_bonus` hunk; `player_progress` combat track derived; `ship_view` serves `level`, `xp`, `next_level_at`, `slots_locked`; `world.officers` serves `level` (the card's officers do not — constant); the one-time seed (a player's hulls and officers from her reports; a merchant's hulls a FIXED value from the skill sum, §4.5) and the `npc_found` hunk that seeds a new merchant the same way | `settle` is its pre-image plus the hunks; exactly one live body contains `set xp` (positive control); the hunk reads `players.is_npc` and nothing else to tell a merchant (token scan: no `auth_uid is null`); at level 1 every stat, every slot count and every officer bonus equals its pre-image for every hull/fleet in the world (`levels_bite` on); a probe PLAYER hull given 25,000 nm reads level 2 and +1 handling; a probe MERCHANT arrival moves no `xp` at all and her hull reads `1 + floor(skill_sum/3)`; the merchant seed touches no player row (counts before = after); a locked slot refuses `E_SLOT_LOCKED` and opens at the level; `carronades`-shaped probe item refuses `E_SHIP_LEVEL` with figures; a probe fleet with one EVADED day reads `combat.points` 5 and `playable` true; `levels_bite` false → all pre-images again; the tick: `tick_arrivals` on a probe arrival is timed and printed | `ship_xp_nm_per_point` 1,000 · `xp_evaded_points` 5 · `xp_driven_off_points` 15 · `ship_level_handling_per_level` 1 · `ship_level_accuracy_per_level` 1.5 · `ship_level_sighting_per_level` 0.15 · `captain_level_pct_per_level` 2 · `levels_bite` true (reuses `level_points_per_step` 25) | `levels_bite = false` is the first rollback (one UPDATE, effects off, XP keeps counting); full: re-cut the hunks out, drop the columns | `ShipPanel`: level chip + XP bar + dimmed locked boxes "Level 6"; `OfficerTile` level; house screen shows combat as playable; workstation/yard faces print "needs level N"; `statGloss.ts` gains `level` |
| **S4** combat stats bite | escort reads `attack/10`; armour turns hull loss by `armour_turns_pct` | new escort = old to 4 places for every fleet with no weapon fitting; strictly higher with one; `guns` no longer read in `settle` (scan + control); `guns = attack/10` for every class; knob at 0 → storm/raid losses byte-identical on a pre-image; probe at 0.5 shows the nau loss 15 % lower | `armour_turns_pct` 0 | re-cut the two hunks out; knob to 0 | none; `statGloss.ts` lines for attack/armour stop saying "unused" |
| **S5** new ship types | eight `ship_classes` rows + six stats; `class_slots`/`class_cabins` rows incl. unlock rows; `hull_recipes` (+ `yard_regions text[]`, `min_level`) and goods/items; `do_build` gains the coast and level gates; `building_yard` prints them; `data/ship_stats.json`, `data/hulls.json` extended; generator `scripts/build-ships-S5.mjs` | 11 classes; `guns = attack/10` all; slots grow with tier; 0072 (b)(c)(d) over all eleven; every new hull buildable at ≥ 1 real yard; a junk refused `E_WRONG_COAST` at Lisbon and laid down at Nagasaki by a probe house; galleon refused `E_LEVEL` at trading level 1 with figures; nothing about the three existing classes moved (pre-image rows equal) | none | `delete` the eight classes and their rows (no hull of a deleted class may exist: asserted before delete); re-cut `do_build` | `HullClass` union + 8 silhouettes + half-lengths; `SnapshotShipClass` declares the six stats; Codex ships face shows stats + slots; yard face shows coast/level; `tests/map.hulls.spec.ts` unchanged (names) |
| **S6** new gear | twelve `item_kinds` (+ `min_level`), `item_effects`, `item_recipes`; `data/fittings.json` extended; generator `scripts/build-gear-S6.mjs` | 24 kinds; 0068 (a)(b)(d) and 0074 (a)(b) over all; a probe makes `swivel-guns` at a tier-2 workstation and mounts them in a barca's weapon slot; `carronades` refused `E_SHIP_LEVEL` on a level-1 hull and mounted on a level-5 probe | none | `delete` the twelve (no `ship_fittings`/`player_items` row may reference them: asserted, or the rows are moved back to store first) | workstation face lists them (served already); Codex gear face if one exists, else the workstation face |
| **S7** the guard | `scripts/db/world-guard.mjs` gains ships and gear: `ship_classes` (all columns incl. the six stats), `class_slots`, `class_cabins`, `item_kinds`, `item_effects`, `item_recipes`, `hull_recipes` + goods/items, `npc_loadouts` must EQUAL `data/ship_stats.json`, `data/hulls.json`, `data/fittings.json`, `data/npc-loadouts.json` | the guard's own planted-drift positive control (as for harbours, `world-guard.mjs:47-50`) | — | — | none. No migration; a CI change in the same PR as S6 |

Order and bundling: **S1+S2** in one PR (one deploy, one measurement); **S3** alone (the largest
behavioural change; `levels_bite` is its net); **S5+S6+S7** in one PR (data, generators, guard,
silhouettes); **S4** last and alone, after a week of S3's numbers. S4 can be skipped without
blocking anything. S5 depends on S3 only for `min_level`; if S3 slips, S5 lands with the column
defaulting to 1.

---

## 9. What the owner will see in the game

- Tap a merchant on the map, then one of her ships: the same panel as your own — the hull
  portrait, the equipment grid with her sails, anchor and guns in their slots and the empty slots
  shown, and the six combat figures under Speed and Cargo. No merchant reads "Nothing fitted" any
  more.
- Every ship of yours carries a **level** on her chip and a small bar to the next one. Ships level
  by sailing, slowly: a hull that runs a route round the clock reaches level 10 in about a month
  and level 20 in about five; a fight she wins pays extra. A higher level makes her answer the helm
  a little better, shoot a little straighter, see a little farther, and opens one or two more slots
  on her grid (shown dimmed with the level they open at). Some gear says "needs level 4".
- A merchant's ship shows a fixed level — the better the company, the higher — that never changes.
- Your officers show a level beside their bonus; a veteran navigator is worth more than she was the
  day you signed her. The level is hers for this signing only: dismiss her and hire her again and
  she starts over. A merchant's officers carry no level.
- The house screen's Combat track stops reading "not yet playable" and counts the pirates you
  evaded or drove off.
- At a build yard: eight more hulls to lay down — a pinnace or a dhow for a beginner, a caravela
  redonda, a fluyt, a xebec or a junk for a company with a trading record, a galleon or an East
  Indiaman at the seven great yards for a company at trading level 5-6. Eastern hulls are built in
  the East. The yard says which you can build here and why not.
- At a workstation: twelve more things to make — storm canvas, pumps and a whipstaff cheaply
  anywhere, carronades and stern chasers at the twelve industrial cities.
- Nothing changes on the first day for any ship you already own: no stat moves, no slot you have
  filled locks, no fitting you own is taken away.

---

## 10. Owner decisions taken into this plan, and what is still open

Decided by the owner on 2026-10-15 and now in the plan:

1. **Captain level is per signing** (`player_officers.xp`): dismissed and hired again, she starts
   at 0 (§4.1, §4.3).
2. **Merchant captains and merchant skills are constant**; merchant hulls carry a **fixed level**
   assigned once from the company's skill sum, and the settle hunk does nothing for a merchant
   fleet (§4.5, §4.6).
3. **Levelling is a long grind**: `ship_xp_nm_per_point` 1,000 on 0069's curve — level 10 in about a
   month and level 20 in about five for a hull running a route round the clock (§4.2's table).
4. **Merchant gear is fixed**; whether merchants ever buy better gear is the economy plan's
   question, deferred (§3.2).
5. **Numbering**: the economy plan holds 0122–0123; S1 → 0124 onward (§8).

Open: nothing that cannot be decided here. The one figure to read is §4.2's table — if a month to
level 10 and five to level 20 is the wrong length of grind, it is one knob, changed by one UPDATE.

---

## 11. Risks found

1. **S2 moves the live merchant economy.** Loadouts add speed and hold; 0120's planner prices
   loops per real hour, so lap choices and profits shift. Mitigation: the same two measurements
   0120 is waiting on (`RESUME.md:33`), taken before and after S2; the rollback is one DELETE.
2. **The galleon/indiaman recipes against 0072's shed-capacity assert (d).** A nau's 255 units
   passed; these are ~310. If (d) refuses, the timber is trimmed at generation — the assert is not
   loosened.
3. **The 2-min tick is dominated by 0120's planning, not by anything here.** S3 adds two small
   UPDATEs per PLAYER arrival and one boolean read per merchant arrival. The risk is that S3 is
   blamed for a slow tick that 0120 owns; S3's assert prints its own timing so the two are not
   confused.
4. **Collision with the economy plan** on migration numbers from 0122 and on `world_config` knob
   names; also on whether merchants pay for anything (§10 Q3). Schedule the two plans' numbers in
   one sitting.
5. **Level gates must never be retroactive.** Existing `class_slots` rows stay `min_level 1`, the
   twelve existing fittings stay `min_level 1`, the three existing hulls stay buildable at level 1,
   and the gate is on FIT/BUILD only — nothing mounted or owned is ever refused after the fact.
   S3's assert proves every pre-image at level 1.
6. **Silhouettes.** Eight shapes to draw; until then unknown codes draw as class-less hulls on the
   map and the panel's portrait (`liveWorld.ts:103`, `hullPath` fall-through) — degraded, not
   broken. The `HullClass` union is a compile-time list in three files (`mapTypes.ts:167`,
   `liveWorld.ts:103`, `glyphs.ts:132`); S5's client PR must touch all three or `tsc` will say so.
7. **`guns` stays as data.** After S4 it is a mirror of `attack/10`, asserted equal; retiring the
   column is a later cleanup, never done in the same step that changes what reads it (the lesson
   of 0074→0077).
