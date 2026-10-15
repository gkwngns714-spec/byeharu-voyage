# SHIPS AND SKILLS — an EVE-style ship grid by country, real-time skills, and gear (EVE racks × RS3 grades)

**Status:** architect's plan, 2026-10-15. **Nothing here is built.** Written against production head
**0128**. 0129 (the twelve fittings of `docs/SHIPS_AND_GEAR.md` §7) is **stopped**: its twelve items
are folded into §6 below as raw ideas, not as a migration.

**The owner's words, verbatim:**
- *"i want a ship tier, ship class like eve online, multiple ships, different countries instead of fractions"*
- *"skill systems like eve too"*
- *"the gear should be like eve too, plus rs3"*
- earlier, still binding: *"we need levels, stats too"*; captain level per signing; merchant captains,
  skills, levels and gear FIXED; levelling is a LONG GRIND (`docs/SHIPS_AND_GEAR.md:21-24`).

**Rules this plan is bound by.** One authority per concept, compose don't fork, retire the old
(`docs/NO_SPAGHETTI.md`); merchants are the same tables and the same executor as players
(`docs/NPC_TRADERS.md` §0); a deployed migration is never edited, it is re-cut by hunks sliced from the
LIVE body (LF-normalised) that occur exactly once; every migration self-asserts with a positive control
and proves its pre-image; the arrivals tick has a hard 2-minute limit; prod is live multiplayer.
**Live-DB push rules** (each step obeys them): `db push` runs each top-level statement separately, so
there is no top-level `LOCK TABLE`, `set local` or `begin/commit` — knobs like `statement_timeout`/
`lock_timeout` go through `set_config(..., true)` inside a `do` block (the 0127/0128 pattern,
0127:78-81, 0128:74-78); no `set role` inside a self-assert; every probe uses its own throw-away house
(`new_house` / `npc_found`) and never a live fleet; new state goes into NEW side tables rather than
`ALTER`ing a table the arrivals tick writes (0127's method, 0127:18-22).

---

## 0. The answer in twelve lines

1. **Countries, not factions: eleven shipbuilding "lines"** — Portugal, Spain, the Netherlands, England,
   France, the Italian states, the Ottomans, Arabia & India, China, Japan, Joseon. A line is a design
   tradition with a philosophy, stat modifiers, two per-level traits and its own yards. The polity
   table `public.nations` (0002:56-63, 20 rows at 0003:35-55) stays the one home of "a country"; a line
   *references* nations (its builders), it does not copy them.
2. **The grid: six sizes × four roles × three techs.** Sizes small / light / medium / heavy / capital /
   flagship (≈ frigate → titan); roles trade, combat, explorer, support; tech T1, T2, famous.
   **103 hulls** in five waves: the 3 live + **52** T1 core (Wave A) + **15** capitals/flagships (B) +
   **22** T2 (C) + **11** famous (D). Every number is generated from ONE archetype table × ONE line
   modifier table, and the generator reproduces the live barca, caravela latina and nau to the digit.
3. **Skills like EVE:** ~90 skills in 9 groups, levels I–V, **trained in real time, offline too**, from a
   queue; time per level follows EVE's curve (`250 × rank × 2^(2.5(L−1))` skill points, 1,800 SP an
   hour): a rank-1 skill reaches V in ~6 days, a rank-10 one in ~59 days. Prerequisites, per-level
   bonuses, hull and gear requirements. Anyone may train any country.
4. **The skills ARE 0016's skills, extended** — the same `public.skills` / `public.player_skills`
   tables (0016:57, 0016:78), the same one reading `public.skill_level` (0107:169-185). The four live
   skills keep their levels; instant study for ducats (`cmd.study_skill`, 0016:155) is retired in
   favour of enrolment + the queue.
5. **Who trains: the house (the player).** Officers do not train skills; their progression stays 0127's
   per-signing level. Merchants: fixed skills, no queue, ever.
6. **Reconciling 0127 (live, dark):** KEEP hull XP/level as *hull veterancy* (slot unlocks + three small
   flat gains); KEEP captain level per signing; KEEP the company's three tracks (0069) as the record;
   **RETIRE `item_level_asks`** (0127:163-171, empty today) — "may I fit this" belongs to skills; DROP
   SHIPS_AND_GEAR S5's never-built `hull_recipes.min_level` — "may I build this" belongs to skills.
   One job per system (§2).
7. **Gear like EVE:** four racks — **High** (guns, boarding), **Mid** (sails, rudder, anchor, lookout,
   instruments), **Low** (hull, hold, pumps, sheathing), **Refit** (permanent, destroyed on removal) —
   plus the Flourish (figurehead, set piece). Two fitting budgets: **Deck** (a new hull column, EVE's
   CPU) and **Hands** (= `crew_max − ⌈crew_required / 2⌉`, EVE's powergrid — no new column). Passive vs active
   modules; meta ladder T1 → Named → T2 → Country → Famous; skill requirements per module.
8. **Gear like RS3:** five material **grades** per base type (pine → oak → teak → live-oak → greenheart;
   iron → cast iron → brass → Swedish iron → bronze; flax → hemp → duck → sailcloth → Holland duck), each
   gated by the module's skill at that level; **wear** and repair; **perks** (augments, chosen, never
   rolled); **sets** with 2- and 4-piece bonuses; one upgrade ladder per slot. **One item model:**
   `base type × grade/meta`, perks and wear on the mounted unit.
9. **The live twelve fittings are Grade 1** of their base types, effects untouched; `public.mount_fitting`
   (0126) stays THE one writer of a mounted fitting; merchant loadouts stay fixed, G1, wear-free.
10. **Economy:** prices are anchored on the live nau (labour 30,000 d., all-in ≈ 49,000 d. at market);
    a flagship is ≈ 4-5 naus, a famous ship ≈ 12-18. The real gate is skill time (~3 months to a T1
    flagship), not ducats. Yard labour already flows into the city purse (0122:573-576).
11. **Build order S8 → S18**, numbered when scheduled; every effect ships DARK behind a switch whose
    "off" is the proven pre-image.
12. Owner questions: two (§11).

---

## 1. What exists today (verified on the files)

| fact | where |
|---|---|
| The class table: code, name, family, rig ∈ square/lateen/mixed/oared, hold, crew, speed, durability, guns, draft 1-6, build_hours, build_cost, **tier 1-5** | `public.ship_classes` 0002:148-166; tier check 0002:163; rig check 0002:153 |
| Three live classes: barca 60 t / 5.0 kn / 8-20 crew / 400 / tier 1; carlat 90 / 6.0 / 12-30 / 550 / 2; nau 400 / 4.4 / 60-140 / 1,800 / 3 | 0003:2086-2092 (`docs/SHIPS_AND_GEAR.md:78`) |
| The six combat stats (handling, armour, attack, accuracy, reach, sighting) | 0074:74-96; authored `data/ship_stats.json:6-37` |
| Hulls are BUILT (no buying): recipes of goods + fittings + labour ducats; labour pays the city | `cmd.do_build` 0072:169-285; `data/hulls.json` (barca 3,000 d., carlat 7,000, nau 30,000); `pay_city(..., 'BUILD', ...)` 0122:573-576 |
| Building yards: `port_buildings(kind='building_yard')` at the 35 harbours with `yard_tier ≥ 3`, tier by `dev_industry` (≥15 → 3, ≥12 → 2, else 1) | 0072:154-166 |
| Countries: `public.nations` (code, name, flag, capital) with 20 powers of 1550; `ports.nation_id` | 0002:56-63, 0003:35-55, 0002:85; derived by `scripts/lib/world-derive.mjs:375-416` (`NATIONS`, `NATION_BY_COUNTRY`, `NATION_OVERRIDE`) and `:535` |
| A house has a nation, chosen at founding | `players.nation_id` 0004:53; `new_house` 0004:291-296 |
| Starting purse 8,000 d.; 4 hulls a house; 8 a fleet | 0001:146, 0001:164, 0001:165 |
| Skills: catalogue `public.skills` (one `effect` ∈ ENDURANCE/SPEED/TRADE_CAP/SPREAD, `pct_per_level` ≤ 10), `public.player_skills` (no row = level 0), max 5, 500 d. × level, studied INSTANTLY at an academy | 0016:57-65, 0016:78-84, 0016:50-53, `cmd.study_skill` 0016:155; four rows 0016:288-297 (SEAMANSHIP 6 %, NAVIGATION 4 %, ACCOUNTING 5 %, HAGGLING 5 %) |
| The one reading of a skill level; gates: leg length by NAVIGATION, hulls per fleet by SEAMANSHIP, fleets by TRADING level, regions by exploration level; merchants exempt by `players.is_npc` | `public.skill_level` 0107:169-185; 0107:47-87 |
| The core that raises a level (tuition through the one mover) — used by merchants' founding | `public.raise_skill` 0096:615; `npc_found` 0097:290-311 |
| A merchant company's "level" on the city list = sum of its four skills | 0113:16-27 |
| Company tracks (trading / exploration / combat), DERIVED, one curve `level_from_points` (cap 20, 25 points a step) | 0069:89-112 |
| Hull XP and captain XP (per signing), side tables; levels shipped **DARK** (`levels_bite` false) | `public.ship_xp` 0127:126-134, `public.officer_xp` 0127:136-146, knobs 0127:173-194, `level_in_force` 0127:216-226 |
| Slot unlocks by hull level; gear level asks (EMPTY) | `public.class_slot_unlocks` 0127:148-161 (barca +1 lookout @3, carlat +1 hull @4, nau +1 weapon @6); `public.item_level_asks` 0127:163-171 |
| THE one reading of a hull's slots | `world.ship_slots` 0127:279-314 |
| Merchant hull level fixed once from the skill sum | `public.npc_fix_level` 0127:316-343 |
| THE one ship builder / THE one stat computation | `world.ship_view`, `world.ship_stats` 0124:22-35 |
| THE one writer of a mounted fitting; merchants fitted by it from authored patterns, fixed | `public.mount_fitting` 0126:20-38; `public.npc_loadouts` + `data/npc-loadouts.json` ("no pattern spends hold") |
| Gear catalogue: 12 `item_kinds` (slot, buys, spends, volume, ws_tier); effects `item_effects` (every item buys one stat and spends another; figurehead none); recipes; store `player_items (player, port, item, qty)`; mounted `ship_fittings (ship_id, item_code, qty)` — **stacked by qty, no identity per unit** | 0068:78-108, 0074:161-192, 0068:165-171, 0074:205-210 |
| Seven slot kinds; per-class counts | `public.class_slots` 0074:104-109, rows 0074:125-140; the panel's kind → word map `src/live/ShipPanel.tsx:80-88` |
| Making gear: `cmd.do_make` at a workstation of `ws_tier` (tier 3 = 12 cities, tier ≥1 = 71) | 0068:241-308; workstations 0068:199-206 |
| Wages owed at sea, paid only from profit at a port | 0128:16-37 |
| Inn captains weighted toward their own nation/region/culture | 0119:11-13 (0073) |
| No client code reads `ship_fittings` directly | `grep ship_fittings src/` → nothing |

---

## 2. The concepts and their one home (and how 0127 is reconciled)

| concept | its ONE home | what happens to the second copy |
|---|---|---|
| a **country** (a polity) | `public.nations` (0002) — unchanged role; three rows added (S8) | — |
| a **shipbuilding tradition** ("Dutch hulls") | `public.ship_lines` (S8): code, name, philosophy, `home_nation`, `builder_nations text[]`, modifiers, traits | none exists |
| a hull's **size / role / tech / line** | columns on `public.ship_classes` (`tier` widened to 1-6 = size; `role`, `tech`, `line_code`, `deck`) | `tier` keeps its one job (escort score `tier × 3`) and becomes the size |
| **where a hull may be laid down** | `cmd.do_build`: yard tier (0072) + the yard's nation ∈ the line's builders (S8) + skills (S11) | SHIPS_AND_GEAR S5's `yard_regions` and `min_level` are never built — superseded here |
| **what the house knows** | `public.skills` + `public.player_skills` (0016) + `public.skill_queue` (S9); read only through `public.skill_level` (0107) | `cmd.study_skill`'s instant purchase retired (S9) |
| **may I build / sail / fit X** | skill requirements: `public.skill_requirements (subject_kind, subject_code, skill_code, level)` read by ONE function `public.requirements_met(player, kind, code)` | `item_level_asks` (0127, empty) retired; trading-level hull gates never built |
| **a percentage a skill gives** | `public.skill_effects (skill_code, stat, pct_per_level, line_code, size, role)` read by ONE function `world.skill_pct(player, ship, stat)`; 0016's `player_skill_bonus` re-cut to read the same table for its four company effects | `skills.effect` / `pct_per_level` columns become mirrors, asserted equal, retired later (the 0074→0077 lesson) |
| **a hull's effective stats** | `world.ship_stats` (0124) — still the one computation; new terms added by hunks | — |
| **a hull's veterancy** | 0127's `ship_xp` + `level_from_points` — KEPT: slot unlocks + handling/accuracy/sighting per level | its gear-gating half (`item_level_asks`) moves to skills |
| **an officer's veterancy** | 0127's `officer_xp` per signing — KEPT unchanged | — |
| **the company's record** | 0069's three tracks — KEPT; still gate fleets and regions (0107) | not used for ships or gear |
| **a mounted fitting** | `public.fitted_units` (S10): one row per mounted unit (id, ship, item, wear, perks, refit) — written only by `public.mount_fitting` and `public.unmount_fitting`, worn only by `voyage.settle`'s one hunk, repaired only by `public.repair_fitting` | `ship_fittings` becomes a read-only VIEW over it for one release, then dropped |
| **a hull's racks and budgets** | `class_slots` rows by RACK (`high/mid/low/refit/flourish`) + `class_slot_unlocks`, read only by `world.ship_slots`; budgets read only by `world.ship_budget(ship)` | the seven kinds stay as the item's TYPE word, not a capacity |

**Why this is not two progression systems doing one job.** Skills = what *the house* knows (gates +
percentages, slow, real-time). Hull level = what *this hull's crew* knows of *her* (flat small gains +
an extra slot, earned by miles). Officer level = *this signing's* seasoning (her own bonus). Company
tracks = *the record* (fleet count, regions). Each answers a different question and each is read in
exactly one place; the one overlap 0127 had — a hull level gating gear — is removed.

---

## 3. Countries: the eleven shipbuilding lines

### 3.1 The lines

Each line has a home nation, its builder nations (whose yards lay its hulls down), a philosophy, a stat
modifier set applied to the archetypes (§4.2), and two **traits** — a bonus per level of the line's
hull skill for that size (EVE's "per level of Caldari Cruiser"). Anyone may train any line.

| line | home nation · builders | philosophy | hold · speed · crew · hull · attack (×) | handling · armour · accuracy · reach · sighting (+) · draft | traits per level of the line's hull skill |
|---|---|---|---|---|---|
| **PRT** Portugal | PRT · PRT | the ocean pioneers: balanced, far-seeing, the anchor of the scale | 1 · 1 · 1 · 1 · 1 | 0 · 0 · 0 · 0 · 0 · 0 | +4 % sighting, +2 % speed |
| **ESP** Spain | ESP · ESP | the treasure fleets: high-sided, armoured, heavily manned, slow | 1.00 · 0.96 · 1.15 · 1.15 · 1.15 | −4 · +6 · 0 · +4 · 0 · 0 | +5 % hull, +4 % attack |
| **NLD** The Netherlands | NLD · NLD, HAN, POL, DNK, SWE | the efficient carriers: huge holds, tiny crews, shallow draft, light guns | 1.25 · 0.98 · 0.75 · 0.90 · 0.75 | +2 · −4 · 0 · 0 · 0 · −1 | +5 % hold, +3 % handling |
| **ENG** England | ENG · ENG | race-built gun ships: fast, handy, shoot straight and far | 0.92 · 1.05 · 1.00 · 0.95 · 1.05 | +6 · −2 · +8 · +8 · 0 · 0 | +4 % accuracy, +2 % speed |
| **FRA** France | FRA · FRA | elegant hulls: quick and handy, all-round | 1.00 · 1.04 · 1.00 · 1.00 · 1.05 | +4 · 0 · +4 · 0 · +1 · 0 | +4 % handling, +4 % reach |
| **ITA** Italian states | VEN · VEN, GEN | galleys and great galleys: oared, nimble, crowded, short-ranged | 0.90 · 1.00 · 1.35 · 0.95 · 1.15 | +8 · 0 · +2 · −10 · 0 · −1 | +5 % attack, +4 % handling |
| **OTT** Ottoman | OTT · OTT | the Arsenal's fleets: stout, manned for boarding | 0.95 · 0.98 · 1.25 · 1.10 · 1.15 | +2 · +4 · 0 · −4 · 0 · 0 | +5 % armour, +4 % attack |
| **IND** Arabia & India | GUJ · GUJ, MLB, BAN (new, S8) | sewn and teak hulls of the monsoon: fast, sweet-handling, lightly armed | 1.08 · 1.04 · 0.85 · 1.05 · 0.60 | +4 · −2 · −10 · −10 · +1 · −1 | +5 % hull, +3 % hold |
| **CHN** China | MNG · MNG | bulkheaded junks: roomy, very hard to sink, clumsy | 1.15 · 0.95 · 1.00 · 1.20 · 0.90 | −8 · +6 · −4 · 0 · 0 · 0 | +5 % hull, +4 % hold |
| **JPN** Japan | JPN · JPN | pine-hulled war boats and red-seal traders: precise gunnery, short range | 0.90 · 1.00 · 1.15 · 0.95 · 1.10 | +4 · +2 · +6 · −8 · +1 · 0 | +4 % accuracy, +4 % attack |
| **KOR** Joseon | JOS · JOS | plated decks: the best armour afloat | 0.90 · 0.97 · 1.10 · 1.10 · 1.10 | +2 · +10 · +4 · 0 · 0 · 0 | +5 % armour, +3 % accuracy |

Owner's list had "Japan/Korea" as one; they are split because `public.nations` already holds JPN and
JOS as separate powers (0003:35-55) and each has its own yards and famous ship — two short lines are
honest where one merged line would need a fake nation. The Hanse/Baltic yards build the Dutch line
(the Dutch carried the Baltic trade). Speed traits exist on only two lines and at 2 %/level, because
speed is money per real hour.

### 3.2 Yards per line (after S8)

| line | tier-3 yards (any size) | tier-2 (small + light) | tier-1 (small) |
|---|---|---|---|
| PRT | Lisbon | Salvador, Malacca, Old Goa¹ | Macau |
| ESP | Antwerp, **Seville**² | Cádiz, Havana, Manila, Callao | Barcelona, Cartagena, Veracruz |
| NLD | Hamburg, **Amsterdam**² | Lübeck, Gdańsk | Copenhagen |
| ENG | London | — | — |
| FRA | Marseille | Bordeaux | — |
| ITA | Venice, Genoa | — | — |
| OTT | **Istanbul**² | Alexandria | — |
| IND | **Surat**² | Kochi, Kozhikode, Jakarta | — |
| CHN | **Guangzhou**² | — | — |
| JPN | **Osaka**² | — | Nagasaki, Tokyo |
| KOR | **Busan**² | — | — |

Derived today from `world-derive.mjs` (yard ports and `dev_industry`, 0072:157-166). ¹ Old Goa derives
with NO nation today although Goa was the Portuguese capital in the Indies from 1510 — S8 adds it to
`NATION_OVERRIDE` as PRT. ² **Arsenals**: seven authored overrides that raise a line's chief yard to
building-yard tier 3 (the Atarazanas of Seville, the Amsterdam admiralty yard, the Tersane-i Amire,
Surat's yards, Guangzhou, Osaka, Busan), so every line can lay down every size. Today the eastern
yards all derive as tier 1 (`docs/SHIPS_AND_GEAR.md:437-438`). Only the `building_yard` row's tier
moves; `ports.yard_tier` (the repair yard, 0067) is untouched.

**Three nations added (S8):** `GUJ` Gujarat Sultanate (Surat, Khambhat), `MLB` Malabar — Calicut & Cochin
(Kozhikode, Kochi, Kannur, Kollam, Mangaluru), `BAN` Banten (Jakarta, Banten). They held these ports
in 1550 as plainly as the twenty already seeded (`world-derive.mjs` NATIONS comment: "a port is given
a nation only where one of these plainly held it"). Side effect, said plainly: the inn's weighting
toward an officer's own nation (0119:11-13) sees these ports as national for the first time.

---

## 4. The ship grid

### 4.1 Sizes, roles, tech

| size (`tier`) | EVE analogue | hold band | crew band | yard tier | hull skill rank |
|---|---|---|---|---|---|
| 1 small | frigate | 27-65 t | 4-19 / 12-54 | 1 | 1 |
| 2 light | destroyer | 65-160 t | 10-38 / 26-122 | 2 | 2 |
| 3 medium | cruiser | 270-575 t | 45-122 / 105-297 | 3 | 4 |
| 4 heavy | battlecruiser | 360-940 t | 60-162 / 150-400 | 3 | 6 |
| 5 capital | battleship | 540-1,125 t | 90-270 / 225-648 | 3 | 10 |
| 6 flagship | capital/titan | 735-2,155 t | 170-400 / 425-938 | 3 | (Capital Hulls V) |

| role | does | archetype leaning |
|---|---|---|
| trade (hauler) | carries | biggest hold, fewest hands, guns light |
| combat | fights / escorts by force | attack, armour, hands; small hold |
| explorer | sees, runs, reaches far | speed, handling, sighting, extra Mid slots |
| support | keeps a fleet alive | hull, armour, extra Low slots |

| tech | what it is | how it is gated |
|---|---|---|
| T1 | the standard hull of the line | the line's hull skill for its size |
| T2 | improved/elite variant: +1 rack slot in its role, a role uplift (trade +15 % hold; combat +25 % attack, +6 armour; explorer +6 % speed, +6 handling, +3 sighting; support +20 % hull), labour × 2.5, copper sheet in the recipe | line hull skill of its size at **V** + the role's T2 specialisation I |
| famous (F) | a named historic ship, unique per house (one of each), labour × 4, lignum vitae + sea charts | line hull skill V + **Famous Ships** I + the role specialisation III |

`guns` stays the 0074 data rule `guns = attack / 10` for every class (attack is generated in tens), so
SHIPS_AND_GEAR's S4 escort re-cut remains a no-op for unfitted hulls of every new class.

### 4.2 The method (one archetype table × one line table)

The generator (`scripts/build-ships.mjs`, S12) holds 20 archetypes `(size, role)` — the PRT values —
and the eleven line rows of §3.1; every hull = archetype × line (× tech uplift), rounded (hold to 5 t,
hull to 10, attack to 10). **Anchors:** PRT small trade = the live barca, PRT light explorer = the live
caravela latina, PRT medium trade = the live nau; the generator asserts all three reproduce the live
rows to the digit (checked in drafting this plan: `LIVE ANCHORS OK`). A designer changes a number in
ONE place and every hull of that size or line moves together.

Slots are by RACK (§6.1): **H/M/L/R** = High / Mid / Low / Refit (+ 1 Flourish on medium and up).
**Deck** is the new fitting budget (EVE CPU); **hands** = `crew_max − ⌈crew_required / 2⌉` (EVE powergrid,
derived, no column). Materials are the size template with each line's own goods substituted (Dutch
Memel fir and Stockholm tar, Indian teak and coir, Chinese abaca, Japanese/Korean iron nails, French
canvas duck, Ottoman cedar); "≈ market" prices each good at the middle of its `baseValue` band in
`data/goods.json`. Yard labour is what the city is paid (0122:573-576). The live three keep their
`data/hulls.json` recipes exactly.

### 4.3 The full list

#### Live today (stats unchanged, re-tagged only)

| code | name | line | class | role | tech | hold t | kn | crew req/max | hull | draft | slots H/M/L/R | deck · hands | hand/arm/att/acc/reach/sight | yard labour d. | materials (≈ market d.) | all-in ≈ d. | yard tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `barca` | Barca | PRT | small | trade | T1 | 60 | 5.0 | 8/20 | 400 | 1 | 1/2/0/0 | 12 · 16 | 70/5/0/0/20/8 | 3,000 | timber 40, tar 8, cordage 6, ships-nails 10 (≈2,900) | ≈5,900 | 1 |
| `carlat` | Caravela latina | PRT | light | explorer | T1 | 90 | 6.0 | 12/30 | 550 | 1 | 2/3/0/1 | 22 · 24 | 75/12/20/40/45/10 | 7,000 | timber 70, naval-timber 20, tar 12, cordage 10, ships-nails 18 (≈10,000) | ≈17,000 | 2 |
| `nau` | Nau | PRT | medium | trade | T1 | 400 | 4.4 | 60/140 | 1,800 | 3 | 3/5/1/2 | 56 · 110 | 45/30/120/55/70/14 | 30,000 | live-oak 90, naval-timber 40, timber 60, tar 25, ships-nails 40 (≈19,400) | ≈49,400 | 3 |

#### Wave A — T1 core, sizes small→heavy

| code | name | line | class | role | tech | hold t | kn | crew req/max | hull | draft | slots H/M/L/R | deck · hands | hand/arm/att/acc/reach/sight | yard labour d. | materials (≈ market d.) | all-in ≈ d. | yard tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `carred` | Caravela redonda | PRT | light | combat | T1 | 70 | 6.6 | 28/90 | 480 | 1 | 2/4/0/1 | 28 · 76 | 88/8/50/38/30/11 | 8,000 | timber 70, naval-timber 20, tar 12, cordage 10, ships-nails 18 (≈10,000) | ≈18,000 | 2 |
| `galeao` | Galeão | PRT | heavy | combat | T1 | 420 | 4.6 | 130/320 | 2,800 | 4 | 5/5/2/2 | 82 · 255 | 42/40/240/60/78/14 | 55,000 | live-oak 126, naval-timber 56, timber 84, tar 35, ships-nails 56 (≈27,200) | ≈82,200 | 3 |
| `patache` | Patache | ESP | small | support | T1 | 45 | 5.6 | 12/34 | 440 | 1 | 1/2/1/0 | 14 · 28 | 76/12/10/20/29/10 | 3,500 | timber 40, tar 8, cordage 6, ships-nails 10 (≈2,900) | ≈6,400 | 1 |
| `carabela` | Carabela de Indias | ESP | light | trade | T1 | 130 | 5.2 | 16/39 | 690 | 2 | 1/3/1/1 | 22 · 31 | 64/18/20/30/44/10 | 7,500 | timber 70, naval-timber 20, tar 12, cordage 10, ships-nails 18 (≈10,000) | ≈17,500 | 2 |
| `zabra` | Zabra | ESP | light | combat | T1 | 70 | 6.3 | 32/103 | 550 | 1 | 2/4/0/1 | 28 · 87 | 84/14/60/38/34/11 | 9,000 | timber 70, naval-timber 20, tar 12, cordage 10, ships-nails 18 (≈10,000) | ≈19,000 | 2 |
| `urca` | Urca | ESP | medium | trade | T1 | 400 | 4.2 | 69/161 | 2,070 | 3 | 3/5/1/2 | 56 · 126 | 41/36/140/55/74/14 | 33,000 | live-oak 90, naval-timber 40, timber 60, tar 25, ships-nails 40 (≈19,400) | ≈52,400 | 3 |
| `galeon` | Galeón | ESP | heavy | combat | T1 | 420 | 4.4 | 150/368 | 3,220 | 4 | 5/5/2/2 | 82 · 293 | 38/46/280/60/82/14 | 60,500 | live-oak 126, naval-timber 56, timber 84, tar 35, ships-nails 56 (≈27,200) | ≈87,700 | 3 |
| `jacht` | Jacht | NLD | small | explorer | T1 | 44 | 6.3 | 4/12 | 270 | 1 | 1/3/0/0 | 11 · 10 | 88/0/0/0/20/10 | 2,000 | timber 40, stockholm-tar 8, cordage 6, ships-nails 10 (≈2,400) | ≈4,400 | 1 |
| `buss` | Haringbuis | NLD | light | trade | T1 | 160 | 5.3 | 10/26 | 540 | 1 | 1/3/1/1 | 22 · 21 | 70/8/20/30/40/10 | 6,000 | timber 70, memel-fir 20, stockholm-tar 12, cordage 10, ships-nails 18 (≈4,800) | ≈10,800 | 2 |
| `fluyt` | Fluit | NLD | medium | trade | T1 | 500 | 4.3 | 45/105 | 1,620 | 2 | 3/5/1/2 | 56 · 82 | 47/26/90/55/70/14 | 25,500 | timber 150, memel-fir 40, stockholm-tar 25, ships-nails 40 (≈9,900) | ≈35,400 | 3 |
| `pinas` | Pinas | NLD | medium | combat | T1 | 375 | 4.7 | 68/165 | 1,800 | 2 | 4/5/1/2 | 62 · 131 | 52/30/130/58/72/14 | 29,000 | timber 150, memel-fir 40, stockholm-tar 25, ships-nails 40 (≈9,900) | ≈38,900 | 3 |
| `retour` | Retourschip | NLD | heavy | trade | T1 | 750 | 4.3 | 60/150 | 2,160 | 3 | 3/6/2/2 | 72 · 120 | 42/28/80/50/65/13 | 41,000 | timber 210, memel-fir 56, stockholm-tar 35, ships-nails 56 (≈13,900) | ≈54,900 | 3 |
| `pinnace` | Pinnace | ENG | small | explorer | T1 | 32 | 6.7 | 6/16 | 280 | 1 | 1/3/0/0 | 11 · 13 | 92/2/0/0/28/10 | 2,500 | timber 40, tar 8, cordage 6, ships-nails 10 (≈2,900) | ≈5,400 | 1 |
| `crayer` | Crayer | ENG | small | trade | T1 | 55 | 5.2 | 8/20 | 380 | 1 | 1/2/0/0 | 12 · 16 | 76/3/0/0/28/8 | 3,000 | timber 40, tar 8, cordage 6, ships-nails 10 (≈2,900) | ≈5,900 | 1 |
| `bark` | Bark | ENG | light | support | T1 | 90 | 6.1 | 20/60 | 620 | 2 | 2/3/1/1 | 28 · 50 | 78/12/30/48/58/11 | 9,500 | timber 70, naval-timber 20, tar 12, cordage 10, ships-nails 18 (≈10,000) | ≈19,500 | 2 |
| `levanter` | Levant Merchantman | ENG | medium | trade | T1 | 370 | 4.6 | 60/140 | 1,710 | 3 | 3/5/1/2 | 56 · 110 | 51/28/130/63/78/14 | 31,500 | timber 150, naval-timber 40, tar 25, ships-nails 40 (≈20,400) | ≈51,900 | 3 |
| `racegal` | Race-built Galleon | ENG | heavy | combat | T1 | 385 | 4.8 | 130/320 | 2,660 | 4 | 5/5/2/2 | 82 · 255 | 48/38/250/68/86/14 | 58,000 | timber 210, naval-timber 56, tar 35, ships-nails 56 (≈28,500) | ≈86,500 | 3 |
| `barque` | Barque | FRA | small | trade | T1 | 60 | 5.2 | 8/20 | 400 | 1 | 1/2/0/0 | 12 · 16 | 74/5/0/0/20/9 | 3,000 | timber 40, tar 8, canvas-duck 6, ships-nails 10 (≈3,000) | ≈6,000 | 1 |
| `carnorm` | Caravelle normande | FRA | light | explorer | T1 | 90 | 6.2 | 12/30 | 550 | 1 | 2/3/0/1 | 22 · 24 | 79/12/20/44/45/11 | 7,500 | timber 70, naval-timber 20, tar 12, canvas-duck 10, ships-nails 18 (≈10,100) | ≈17,600 | 2 |
| `navire` | Navire marchand | FRA | medium | trade | T1 | 400 | 4.6 | 60/140 | 1,800 | 3 | 3/5/1/2 | 56 · 110 | 49/30/130/59/70/15 | 31,500 | timber 150, naval-timber 40, tar 25, ships-nails 40 (≈20,400) | ≈51,900 | 3 |
| `galere` | Galère | FRA | medium | combat | T1 | 300 | 5.0 | 90/220 | 2,000 | 3 | 4/5/1/2 | 62 · 175 | 54/34/180/62/72/15 | 35,500 | timber 150, naval-timber 40, tar 25, ships-nails 40 (≈20,400) | ≈55,900 | 3 |
| `galion` | Galion | FRA | heavy | combat | T1 | 420 | 4.8 | 130/320 | 2,800 | 4 | 5/5/2/2 | 82 · 255 | 46/40/250/64/78/15 | 58,000 | timber 210, naval-timber 56, tar 35, ships-nails 56 (≈28,500) | ≈86,500 | 3 |
| `fusta` | Fusta | ITA | small | combat | T1 | 27 | 6.2 | 19/54 | 330 | 1 | 2/2/0/0 | 15 · 44 | 92/6/20/32/20/9 | 4,000 | timber 40, tar 8, hemp 6, ships-nails 10 (≈3,500) | ≈7,500 | 1 |
| `marcil` | Marciliana | ITA | light | trade | T1 | 115 | 5.4 | 19/46 | 570 | 1 | 1/3/1/1 | 22 · 36 | 76/12/20/32/30/10 | 7,500 | timber 70, naval-timber 20, tar 12, hemp 10, ships-nails 18 (≈11,000) | ≈18,500 | 2 |
| `galsott` | Galea sottile | ITA | light | combat | T1 | 65 | 6.6 | 38/122 | 460 | 1 | 2/4/0/1 | 28 · 103 | 96/8/60/40/20/11 | 9,000 | timber 70, naval-timber 20, tar 12, hemp 10, ships-nails 18 (≈11,000) | ≈20,000 | 2 |
| `galgros` | Galea grossa | ITA | medium | trade | T1 | 360 | 4.4 | 81/189 | 1,710 | 2 | 3/5/1/2 | 56 · 148 | 53/30/140/57/60/14 | 33,000 | timber 150, naval-timber 40, tar 25, ships-nails 40 (≈20,400) | ≈53,400 | 3 |
| `caracca` | Caracca genovese | ITA | heavy | trade | T1 | 540 | 4.4 | 108/270 | 2,280 | 3 | 3/6/2/2 | 72 · 216 | 48/32/130/52/55/13 | 53,000 | timber 210, naval-timber 56, tar 35, ships-nails 56 (≈28,500) | ≈81,500 | 3 |
| `kayik` | Kayık | OTT | small | trade | T1 | 55 | 4.9 | 10/25 | 440 | 1 | 1/2/0/0 | 12 · 20 | 72/9/0/0/16/8 | 3,000 | timber 40, tar 8, cordage 6, ships-nails 10 (≈2,900) | ≈5,900 | 1 |
| `xebec` | Şebek (xebec) | OTT | light | combat | T1 | 65 | 6.5 | 35/112 | 530 | 1 | 2/4/0/1 | 28 · 94 | 90/12/60/38/26/11 | 8,000 | timber 70, cedar 20, tar 12, cordage 10, ships-nails 18 (≈7,300) | ≈15,300 | 2 |
| `karamur` | Karamürsel | OTT | medium | trade | T1 | 380 | 4.3 | 75/175 | 1,980 | 3 | 3/5/1/2 | 56 · 137 | 47/34/140/55/66/14 | 30,000 | timber 150, cedar 40, tar 25, ships-nails 40 (≈15,000) | ≈45,000 | 3 |
| `kadirga` | Kadırga | OTT | medium | combat | T1 | 285 | 4.7 | 112/275 | 2,200 | 3 | 4/5/1/2 | 62 · 219 | 52/38/200/58/68/14 | 34,000 | timber 150, cedar 40, tar 25, ships-nails 40 (≈15,000) | ≈49,000 | 3 |
| `bastarda` | Baştarda | OTT | heavy | combat | T1 | 400 | 4.5 | 162/400 | 3,080 | 4 | 5/5/2/2 | 82 · 319 | 44/44/280/60/74/14 | 55,000 | timber 210, cedar 56, tar 35, ships-nails 56 (≈21,000) | ≈76,000 | 3 |
| `dhow` | Dhow | IND | small | trade | T1 | 65 | 5.2 | 7/17 | 420 | 1 | 1/2/0/0 | 12 · 13 | 74/3/0/0/10/9 | 2,500 | teak 40, coir 14, coco-fibre 10 (≈5,100) | ≈7,600 | 1 |
| `sambuk` | Sambuk | IND | small | explorer | T1 | 38 | 6.7 | 5/14 | 320 | 1 | 1/3/0/0 | 11 · 11 | 90/2/0/0/10/11 | 2,000 | teak 40, coir 14, coco-fibre 10 (≈5,100) | ≈7,100 | 1 |
| `ghurab` | Ghurab | IND | light | combat | T1 | 75 | 6.9 | 24/76 | 500 | 1 | 2/4/0/1 | 28 · 64 | 92/6/30/28/20/12 | 7,000 | teak 90, coir 22, coco-fibre 18 (≈10,900) | ≈17,900 | 2 |
| `baghlah` | Baghlah | IND | medium | trade | T1 | 430 | 4.6 | 51/119 | 1,890 | 2 | 3/5/1/2 | 56 · 93 | 49/28/70/45/60/15 | 25,500 | teak 190, coir 25, coco-fibre 40 (≈22,000) | ≈47,500 | 3 |
| `jahaz` | Gujarati Jahaz | IND | heavy | trade | T1 | 650 | 4.6 | 68/170 | 2,520 | 3 | 3/6/2/2 | 72 · 136 | 44/30/70/40/55/14 | 41,000 | teak 266, coir 35, coco-fibre 56 (≈30,800) | ≈71,800 | 3 |
| `niao` | Niaochuan | CHN | small | explorer | T1 | 40 | 6.1 | 6/16 | 360 | 1 | 1/3/0/0 | 11 · 13 | 78/10/0/0/20/10 | 2,000 | timber 40, tar 8, abaca 6, ships-nails 10 (≈3,400) | ≈5,400 | 1 |
| `shachuan` | Shachuan | CHN | light | trade | T1 | 150 | 5.1 | 14/34 | 720 | 2 | 1/3/1/1 | 22 · 27 | 60/18/20/26/40/10 | 6,500 | timber 90, tar 12, abaca 10, ships-nails 18 (≈6,600) | ≈13,100 | 2 |
| `cangshan` | Cangshan | CHN | light | combat | T1 | 80 | 6.3 | 28/90 | 580 | 1 | 2/4/0/1 | 28 · 76 | 80/14/40/34/30/11 | 7,000 | timber 90, tar 12, abaca 10, ships-nails 18 (≈6,600) | ≈13,600 | 2 |
| `junk` | Junk (Fuzhou trader) | CHN | medium | trade | T1 | 460 | 4.2 | 60/140 | 2,160 | 3 | 3/5/1/2 | 56 · 110 | 37/36/110/51/70/14 | 27,000 | timber 190, tar 25, ships-nails 40 (≈12,100) | ≈39,100 | 3 |
| `fuchuan` | Fuchuan | CHN | heavy | combat | T1 | 485 | 4.4 | 130/320 | 3,360 | 4 | 5/5/2/2 | 82 · 255 | 34/46/220/56/78/14 | 49,500 | timber 266, tar 35, ships-nails 56 (≈16,900) | ≈66,400 | 3 |
| `kobaya` | Kobaya | JPN | small | combat | T1 | 27 | 6.2 | 16/46 | 330 | 1 | 2/2/0/0 | 15 · 38 | 88/8/20/36/22/10 | 3,500 | timber 40, tar 8, cordage 6, iron 10 (≈3,300) | ≈6,800 | 1 |
| `kobune` | Kobune | JPN | small | trade | T1 | 55 | 5.0 | 9/23 | 380 | 1 | 1/2/0/0 | 12 · 18 | 74/7/0/0/12/9 | 3,000 | timber 40, tar 8, cordage 6, iron 10 (≈3,300) | ≈6,300 | 1 |
| `sekibune` | Sekibune | JPN | light | combat | T1 | 65 | 6.6 | 32/103 | 460 | 1 | 2/4/0/1 | 28 · 87 | 92/10/60/44/22/12 | 8,000 | timber 90, tar 12, cordage 10, iron 18 (≈6,500) | ≈14,500 | 2 |
| `shuinsen` | Shuinsen | JPN | medium | trade | T1 | 360 | 4.4 | 69/161 | 1,710 | 3 | 3/5/1/2 | 56 · 126 | 49/32/130/61/62/15 | 30,000 | timber 190, tar 25, iron 40 (≈13,500) | ≈43,500 | 3 |
| `ataka` | Atakebune | JPN | heavy | combat | T1 | 380 | 4.6 | 150/368 | 2,660 | 4 | 5/5/2/2 | 82 · 293 | 46/42/260/66/70/15 | 55,000 | timber 266, tar 35, iron 56 (≈18,900) | ≈73,900 | 3 |
| `hyeop` | Hyeopseon | KOR | small | explorer | T1 | 32 | 6.2 | 7/18 | 330 | 1 | 1/3/0/0 | 11 · 14 | 88/14/0/0/20/10 | 2,500 | timber 40, tar 8, cordage 6, iron 10 (≈3,300) | ≈5,800 | 1 |
| `sangseon` | Sangseon | KOR | light | trade | T1 | 115 | 5.2 | 15/37 | 660 | 2 | 1/3/1/1 | 22 · 29 | 70/22/20/34/40/10 | 7,000 | timber 90, tar 12, cordage 10, iron 18 (≈6,500) | ≈13,500 | 2 |
| `byeong` | Byeongseon | KOR | light | combat | T1 | 65 | 6.4 | 31/99 | 530 | 1 | 2/4/0/1 | 28 · 83 | 90/18/60/42/30/11 | 8,000 | timber 90, tar 12, cordage 10, iron 18 (≈6,500) | ≈14,500 | 2 |
| `joun` | Jounseon | KOR | medium | trade | T1 | 360 | 4.3 | 66/154 | 1,980 | 3 | 3/5/1/2 | 56 · 121 | 47/40/130/59/70/14 | 30,000 | timber 190, tar 25, iron 40 (≈13,500) | ≈43,500 | 3 |
| `panok` | Panokseon | KOR | heavy | combat | T1 | 380 | 4.5 | 143/352 | 3,080 | 4 | 5/5/2/2 | 82 · 280 | 44/50/260/64/78/14 | 55,000 | timber 266, tar 35, iron 56 (≈18,900) | ≈73,900 | 3 |

#### Wave B — T1 capitals and flagships

| code | name | line | class | role | tech | hold t | kn | crew req/max | hull | draft | slots H/M/L/R | deck · hands | hand/arm/att/acc/reach/sight | yard labour d. | materials (≈ market d.) | all-in ≈ d. | yard tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `naucarr` | Nau da Carreira | PRT | capital | trade | T1 | 900 | 4.2 | 120/300 | 3,400 | 5 | 3/7/3/3 | 100 · 240 | 35/38/160/50/65/13 | 80,000 | live-oak 180, naval-timber 80, timber 120, tar 50, ships-nails 80 (≈38,900) | ≈118,900 | 3 |
| `carraca` | Carraca grande | PRT | flagship | trade | T1 | 1500 | 3.9 | 200/500 | 5,000 | 5 | 4/7/4/3 | 138 · 400 | 30/42/220/50/65/13 | 150,000 | live-oak 270, naval-timber 120, timber 180, tar 75, ships-nails 120 (≈58,300) | ≈208,300 | 3 |
| `galmanila` | Galeón de Manila | ESP | capital | trade | T1 | 900 | 4.0 | 138/345 | 3,910 | 5 | 3/7/3/3 | 100 · 276 | 31/44/180/50/69/13 | 88,000 | live-oak 180, naval-timber 80, timber 120, tar 50, ships-nails 80 (≈38,900) | ≈126,900 | 3 |
| `galreal` | Galeón real | ESP | flagship | combat | T1 | 800 | 3.8 | 368/862 | 6,440 | 5 | 7/6/2/3 | 150 · 678 | 28/61/550/64/89/15 | 187,000 | live-oak 270, naval-timber 120, timber 180, tar 75, ships-nails 120 (≈58,300) | ≈245,300 | 3 |
| `spiegel` | Spiegelretourschip | NLD | capital | trade | T1 | 1125 | 4.1 | 90/225 | 3,060 | 4 | 3/7/3/3 | 100 · 180 | 37/34/120/50/65/13 | 68,000 | timber 300, memel-fir 80, stockholm-tar 50, ships-nails 80 (≈19,800) | ≈87,800 | 3 |
| `indiaman` | East Indiaman | ENG | capital | trade | T1 | 830 | 4.4 | 120/300 | 3,230 | 5 | 3/7/3/3 | 100 · 240 | 41/36/170/58/73/13 | 84,000 | timber 300, naval-timber 80, tar 50, ships-nails 80 (≈40,800) | ≈124,800 | 3 |
| `greatship` | Great Ship | ENG | flagship | combat | T1 | 735 | 4.2 | 320/750 | 5,320 | 5 | 7/6/2/3 | 150 · 590 | 38/53/500/72/93/15 | 178,500 | timber 450, naval-timber 120, tar 75, ships-nails 120 (≈61,200) | ≈239,700 | 3 |
| `grandnav` | Grand navire | FRA | capital | combat | T1 | 600 | 4.5 | 200/480 | 4,000 | 5 | 6/6/2/3 | 115 · 380 | 40/48/360/66/82/15 | 100,000 | timber 300, naval-timber 80, tar 50, ships-nails 80 (≈40,800) | ≈140,800 | 3 |
| `galeazza` | Galeazza | ITA | capital | combat | T1 | 540 | 4.3 | 270/648 | 3,800 | 4 | 6/6/2/3 | 115 · 513 | 44/48/390/64/72/14 | 104,500 | timber 300, naval-timber 80, tar 50, ships-nails 80 (≈40,800) | ≈145,300 | 3 |
| `kalyon` | Kalyon | OTT | capital | combat | T1 | 570 | 4.2 | 250/600 | 4,400 | 5 | 6/6/2/3 | 115 · 475 | 38/52/390/62/78/14 | 95,000 | timber 300, cedar 80, tar 50, ships-nails 80 (≈30,000) | ≈125,000 | 3 |
| `bashum` | Baştarda-i Hümayun | OTT | flagship | combat | T1 | 760 | 3.9 | 400/938 | 6,160 | 5 | 7/6/2/3 | 150 · 738 | 34/59/550/64/81/15 | 170,000 | timber 450, cedar 120, tar 75, ships-nails 120 (≈45,000) | ≈215,000 | 3 |
| `hajji` | Hajji Jahaz | IND | capital | trade | T1 | 970 | 4.4 | 102/255 | 3,570 | 4 | 3/7/3/3 | 100 · 204 | 39/36/100/40/55/14 | 68,000 | teak 380, coir 50, coco-fibre 80 (≈44,000) | ≈112,000 | 3 |
| `dachuan` | Dachuan (great junk) | CHN | capital | trade | T1 | 1035 | 4.0 | 120/300 | 4,080 | 5 | 3/7/3/3 | 100 · 240 | 27/44/140/46/65/13 | 72,000 | timber 380, tar 50, ships-nails 80 (≈24,200) | ≈96,200 | 3 |
| `oataka` | Ō-atakebune | JPN | capital | combat | T1 | 540 | 4.3 | 230/552 | 3,800 | 5 | 6/6/2/3 | 115 · 437 | 40/50/370/68/74/15 | 95,000 | timber 380, tar 50, iron 80 (≈27,000) | ≈122,000 | 3 |
| `daepanok` | Dae-panokseon | KOR | capital | combat | T1 | 540 | 4.2 | 220/528 | 4,400 | 5 | 6/6/2/3 | 115 · 418 | 38/58/370/66/82/14 | 95,000 | timber 380, tar 50, iron 80 (≈27,000) | ≈122,000 | 3 |

#### Wave C — T2 (improved)

| code | name | line | class | role | tech | hold t | kn | crew req/max | hull | draft | slots H/M/L/R | deck · hands | hand/arm/att/acc/reach/sight | yard labour d. | materials (≈ market d.) | all-in ≈ d. | yard tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `carvarm` | Caravela de armada | PRT | light | combat | T2 | 70 | 6.6 | 28/90 | 530 | 1 | 3/4/0/1 | 31 · 76 | 88/14/60/42/30/11 | 20,000 | timber 112, naval-timber 32, tar 19, cordage 16, ships-nails 29, copper-sheet 10 (≈16,200) | ≈36,200 | 2 |
| `nauguerra` | Nau de guerra | PRT | medium | support | T2 | 280 | 4.8 | 70/180 | 2,040 | 3 | 3/5/3/2 | 66 · 145 | 52/34/100/55/60/14 | 75,000 | live-oak 144, naval-timber 64, timber 96, tar 40, ships-nails 64, copper-sheet 10 (≈31,300) | ≈106,300 | 3 |
| `galplata` | Galeón de la Plata | ESP | heavy | trade | T2 | 690 | 4.2 | 92/230 | 3,040 | 4 | 3/6/3/2 | 84 · 184 | 36/42/130/50/69/13 | 132,000 | live-oak 202, naval-timber 90, timber 134, tar 56, ships-nails 90, copper-sheet 13 (≈43,900) | ≈175,900 | 3 |
| `dunkirk` | Fragata de Dunquerque | ESP | light | combat | T2 | 70 | 6.3 | 32/103 | 610 | 1 | 3/4/0/1 | 31 · 87 | 84/20/70/42/34/11 | 22,000 | timber 112, naval-timber 32, tar 19, cordage 16, ships-nails 29, copper-sheet 10 (≈16,200) | ≈38,200 | 2 |
| `armfluit` | Gewapende fluit | NLD | medium | trade | T2 | 575 | 4.3 | 45/105 | 1,780 | 2 | 3/5/2/2 | 65 · 82 | 47/30/90/55/70/14 | 64,000 | timber 240, memel-fir 64, stockholm-tar 40, ships-nails 64, copper-sheet 10 (≈16,000) | ≈80,000 | 3 |
| `kaper` | Kaperschip | NLD | light | combat | T2 | 90 | 6.5 | 21/68 | 480 | 1 | 3/4/0/1 | 31 · 57 | 90/10/50/42/30/11 | 17,000 | timber 112, memel-fir 32, stockholm-tar 19, cordage 16, ships-nails 29, copper-sheet 10 (≈7,900) | ≈24,900 | 2 |
| `qpinnace` | Queen's Pinnace | ENG | small | explorer | T2 | 32 | 7.1 | 6/16 | 280 | 1 | 1/4/0/0 | 12 · 13 | 98/2/0/0/28/13 | 6,500 | timber 64, tar 13, cordage 10, ships-nails 16, copper-sheet 10 (≈4,800) | ≈11,300 | 1 |
| `armmerch` | Armed Merchantman | ENG | medium | trade | T2 | 425 | 4.6 | 60/140 | 1,880 | 3 | 3/5/2/2 | 65 · 110 | 51/32/130/63/78/14 | 79,000 | timber 240, naval-timber 64, tar 40, ships-nails 64, copper-sheet 10 (≈32,800) | ≈111,800 | 3 |
| `fregcourse` | Frégate de course | FRA | light | combat | T2 | 70 | 6.9 | 28/90 | 530 | 1 | 3/4/0/1 | 31 · 76 | 92/14/70/46/30/12 | 21,000 | timber 112, naval-timber 32, tar 19, canvas-duck 16, ships-nails 29, copper-sheet 10 (≈16,400) | ≈37,400 | 2 |
| `fluteroy` | Flûte royale | FRA | medium | trade | T2 | 460 | 4.6 | 60/140 | 1,980 | 3 | 3/5/2/2 | 65 · 110 | 49/34/130/59/70/15 | 79,000 | timber 240, naval-timber 64, tar 40, ships-nails 64, copper-sheet 10 (≈32,800) | ≈111,800 | 3 |
| `galbast` | Galea bastarda | ITA | medium | combat | T2 | 270 | 4.8 | 122/297 | 2,090 | 2 | 5/5/1/2 | 71 · 236 | 58/40/240/64/62/14 | 93,500 | timber 240, naval-timber 64, tar 40, ships-nails 64, copper-sheet 10 (≈32,800) | ≈126,300 | 3 |
| `carcarm` | Caracca armata | ITA | heavy | trade | T2 | 620 | 4.4 | 108/270 | 2,510 | 3 | 3/6/3/2 | 84 · 216 | 48/36/130/52/55/13 | 132,000 | timber 336, naval-timber 90, tar 56, ships-nails 90, copper-sheet 13 (≈46,000) | ≈178,000 | 3 |
| `korsan` | Korsan şebeği | OTT | light | combat | T2 | 65 | 6.5 | 35/112 | 580 | 1 | 3/4/0/1 | 31 · 94 | 90/18/70/42/26/11 | 20,000 | timber 112, cedar 32, tar 19, cordage 16, ships-nails 29, copper-sheet 10 (≈11,900) | ≈31,900 | 2 |
| `mavna` | Mavna | OTT | heavy | support | T2 | 455 | 4.4 | 125/325 | 3,560 | 4 | 4/6/3/2 | 89 · 262 | 46/48/180/60/66/14 | 130,000 | timber 336, cedar 90, tar 56, ships-nails 90, copper-sheet 13 (≈33,800) | ≈163,800 | 3 |
| `batil` | Batil | IND | small | explorer | T2 | 38 | 7.1 | 5/14 | 320 | 1 | 1/4/0/0 | 12 · 11 | 96/2/0/0/10/14 | 5,500 | teak 64, coir 23, coco-fibre 16, copper-sheet 10 (≈8,300) | ≈13,800 | 1 |
| `ghurabj` | Ghurab-i-jang | IND | light | combat | T2 | 75 | 6.9 | 24/76 | 550 | 1 | 3/4/0/1 | 31 · 64 | 92/12/40/32/20/12 | 17,000 | teak 144, coir 35, coco-fibre 29, copper-sheet 10 (≈17,600) | ≈34,600 | 2 |
| `zhanchuan` | Zhanchuan | CHN | medium | combat | T2 | 345 | 4.6 | 90/220 | 2,640 | 3 | 5/5/1/2 | 71 · 175 | 42/46/190/58/72/14 | 76,500 | timber 304, tar 40, ships-nails 64, copper-sheet 10 (≈19,500) | ≈96,000 | 3 |
| `haicang` | Haicang | CHN | heavy | trade | T2 | 795 | 4.2 | 80/200 | 3,170 | 4 | 3/6/3/2 | 84 · 160 | 32/42/100/46/65/13 | 108,000 | timber 426, tar 56, ships-nails 90, copper-sheet 13 (≈27,300) | ≈135,300 | 3 |
| `murakami` | Murakami kobaya | JPN | small | combat | T2 | 27 | 6.2 | 16/46 | 370 | 1 | 3/2/0/0 | 18 · 38 | 88/14/30/40/22/10 | 9,000 | timber 64, tar 13, cordage 10, iron 16, copper-sheet 10 (≈5,400) | ≈14,400 | 1 |
| `oshuin` | Ō-shuinsen | JPN | medium | trade | T2 | 415 | 4.4 | 69/161 | 1,880 | 3 | 3/5/2/2 | 65 · 126 | 49/36/130/61/62/15 | 75,000 | timber 304, tar 40, iron 64, copper-sheet 10 (≈21,700) | ≈96,700 | 3 |
| `tamang` | Tamangseon | KOR | small | explorer | T2 | 32 | 6.6 | 7/18 | 330 | 1 | 1/4/0/0 | 12 · 14 | 94/14/0/0/20/13 | 6,000 | timber 64, tar 13, cordage 10, iron 16, copper-sheet 10 (≈5,400) | ≈11,400 | 1 |
| `bangpae` | Bangpaeseon | KOR | medium | combat | T2 | 270 | 4.7 | 99/242 | 2,420 | 3 | 5/5/1/2 | 71 · 192 | 52/50/230/66/72/14 | 85,000 | timber 304, tar 40, iron 64, copper-sheet 10 (≈21,700) | ≈106,700 | 3 |

#### Wave D — famous ships (one per house)

| code | name | line | class | role | tech | hold t | kn | crew req/max | hull | draft | slots H/M/L/R | deck · hands | hand/arm/att/acc/reach/sight | yard labour d. | materials (≈ market d.) | all-in ≈ d. | yard tier |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `madre` | Madre de Deus | PRT | flagship | trade | F | 1875 | 4.0 | 200/500 | 5,750 | 5 | 4/7/5/3 | 158 · 400 | 32/48/240/50/65/14 | 600,000 | live-oak 594, naval-timber 264, timber 396, tar 165, ships-nails 264, lignum-vitae 59, sea-charts 2 (≈132,500) | ≈732,500 | 3 |
| `sanmartin` | San Martín | ESP | flagship | combat | F | 800 | 4.0 | 368/862 | 7,730 | 5 | 8/6/2/3 | 172 · 678 | 32/71/770/72/89/16 | 748,000 | live-oak 594, naval-timber 264, timber 396, tar 165, ships-nails 264, lignum-vitae 59, sea-charts 2 (≈132,500) | ≈880,500 | 3 |
| `batavia` | Batavia | NLD | heavy | trade | F | 940 | 4.4 | 60/150 | 2,480 | 3 | 3/6/3/2 | 84 · 120 | 44/34/90/50/65/14 | 163,000 | timber 462, memel-fir 123, stockholm-tar 77, ships-nails 123, lignum-vitae 28, sea-charts 2 (≈33,700) | ≈196,700 | 3 |
| `goldenhind` | Golden Hind | ENG | light | explorer | F | 85 | 6.9 | 12/30 | 570 | 1 | 2/4/0/1 | 26 · 24 | 91/12/20/52/53/15 | 29,500 | timber 154, naval-timber 44, tar 26, cordage 22, ships-nails 40, lignum-vitae 20, sea-charts 2 (≈25,000) | ≈54,500 | 2 |
| `couronne` | La Couronne | FRA | capital | combat | F | 600 | 4.6 | 200/480 | 4,800 | 5 | 7/6/2/3 | 132 · 380 | 44/58/500/74/82/16 | 399,000 | timber 660, naval-timber 176, tar 110, ships-nails 176, lignum-vitae 40, sea-charts 2 (≈93,300) | ≈492,300 | 3 |
| `duodo` | Galeazza di Duodo | ITA | capital | combat | F | 540 | 4.4 | 270/648 | 4,560 | 4 | 7/6/2/3 | 132 · 513 | 48/58/550/72/72/15 | 418,000 | timber 660, naval-timber 176, tar 110, ships-nails 176, lignum-vitae 40, sea-charts 2 (≈93,300) | ≈511,300 | 3 |
| `turgut` | Turgut Reis's Kadırga | OTT | medium | combat | F | 285 | 4.8 | 112/275 | 2,640 | 3 | 5/5/1/2 | 71 · 219 | 56/48/270/66/68/15 | 136,000 | timber 330, cedar 88, tar 55, ships-nails 88, lignum-vitae 20, sea-charts 2 (≈36,000) | ≈172,000 | 3 |
| `rahimi` | Rahimi | IND | flagship | trade | F | 2025 | 4.2 | 170/425 | 6,040 | 4 | 4/7/5/3 | 158 · 340 | 36/46/150/40/55/15 | 510,000 | teak 1254, coir 165, coco-fibre 264, lignum-vitae 59, sea-charts 2 (≈149,300) | ≈659,300 | 3 |
| `baochuan` | Baochuan (treasure ship) | CHN | flagship | trade | F | 2155 | 3.8 | 200/500 | 6,900 | 5 | 4/7/5/3 | 158 · 400 | 24/54/220/46/65/14 | 540,000 | timber 1254, tar 165, ships-nails 264, lignum-vitae 59, sea-charts 2 (≈83,900) | ≈623,900 | 3 |
| `sjb` | San Juan Bautista | JPN | heavy | explorer | F | 360 | 5.5 | 80/207 | 2,300 | 3 | 2/8/2/2 | 78 · 167 | 64/32/110/60/57/23 | 184,000 | timber 585, tar 77, iron 123, lignum-vitae 28, sea-charts 2 (≈44,700) | ≈228,700 | 3 |
| `geobuk` | Geobukseon (turtle ship) | KOR | medium | combat | F | 270 | 4.8 | 99/242 | 2,640 | 3 | 5/5/1/2 | 71 · 192 | 56/54/260/70/72/15 | 136,000 | timber 418, tar 55, iron 88, lignum-vitae 20, sea-charts 2 (≈32,700) | ≈168,700 | 3 |

Counts: live 3 · Wave A 52 · Wave B 15 · Wave C 22 · Wave D 11 = **103 hulls, 11 lines × 6 sizes × 4
roles × 3 techs**. Every line has small, light, medium and heavy T1 in Wave A, one capital in Wave B
(flagships for the four great naval powers PRT, ESP, ENG, OTT), two T2 and one famous ship.

### 4.4 Hull requirements (the pattern, per line `X`)

| hull | requires |
|---|---|
| barca, caravela latina, nau | **nothing** — the Lisbon hulls every house already builds (pre-image; asserted) |
| small T1 | X Small Hulls I |
| light T1 | X Small Hulls III, X Light Hulls I |
| medium T1 | X Light Hulls III, X Medium Hulls I |
| heavy T1 | X Medium Hulls IV, X Heavy Hulls I, the role skill I (Merchant Ships / Ships of War / Exploration Vessels / Escort & Support) |
| capital T1 | X Heavy Hulls IV, X Capital Hulls I, Command III, the role skill III |
| flagship T1 | X Capital Hulls V, Fleet Command I, the role skill V |
| T2 (any size) | X ⟨size⟩ Hulls V + the role's T2 specialisation I (Armed Merchantmen / Privateers / Survey Ships / Convoy Escorts) |
| famous | X ⟨size⟩ Hulls V, Famous Ships I, the role's T2 specialisation III; one per house |

Requirements gate **BUILD** (`cmd.do_build`) and nothing else: a hull a house owns is never taken from
it, and there is no ship market to buy around the gate. (If a ship market or gift is ever added, the
same `requirements_met` reading gates taking command.)

**The grind, worked:** a new house wanting its first Dutch fluit: Small III (4.4 h) + Light III
(8.9 h) + Medium I (33 min) ≈ **14 h**. A first heavy of a new line ≈ **5 days** of queue. A capital ≈
**12 days**. A T1 flagship ≈ **3 months** (Capital Hulls V alone is ~59 days). A T2 medium ≈ **4
weeks**. A famous flagship ≈ **4-5 months**. Hulls cost money too, but the queue is the long grind.

---

## 5. Skills like EVE

### 5.1 The model

- **One catalogue, extended:** every skill is a row of `public.skills` (0016:57); a house's completed
  levels are rows of `public.player_skills` (0016:78). New side tables (no `ALTER` of a table the
  arrivals tick reads, 0127's method): `skill_profile (skill_id, group_code, rank, enrol_where)`,
  `skill_prereqs (skill_id, needs_skill_id, level)`, `skill_effects` and `skill_requirements` (§2),
  `skill_queue (player_id, pos, skill_id, to_level, starts_at, finishes_at)`, `skill_sp (player_id,
  skill_id, sp)` for partial progress kept when an entry is removed (EVE keeps your SP).
- **Real time, offline too, no cron.** A queue entry's `finishes_at` is computed when it is queued
  (chained after the one before). The ONE reading `public.skill_level(player, code)` (0107:169-185) is
  re-cut to `greatest(player_skills.level, max(to_level) of her queue rows with finishes_at ≤ now())` —
  so a level lands the instant its time passes, whether she is signed in or not, with nothing running.
  The queue verbs fold finished rows into `player_skills` when the house next touches the queue; the
  reading never needs the fold.
- **Time per level (EVE's curve):** skill points to reach level L = `250 × rank × 2^(2.5 × (L − 1))`
  (250 / 1,414 / 8,000 / 45,255 / 256,000 per rank); training rate `skill_sp_per_hour` 1,800 (one
  rate for everybody: no attributes, no implants — one number to tune the whole grind).

| rank | to I | to II | to III | to IV | to V (total) | used for |
|---|---|---|---|---|---|---|
| 1 | 8 min | 47 min | 4.4 h | 25 h | **5.9 days** | small hulls, the four live skills, Gunnery |
| 2 | 17 min | 1.6 h | 8.9 h | 2.1 days | 11.9 days | light hulls, Rigging, Lookouts, Boarding, Shipwright |
| 3 | 25 min | 2.4 h | 13 h | 3.1 days | 17.8 days | Command, Cargo Stowage, Gun Drill … |
| 4 | 33 min | 3.1 h | 18 h | 4.2 days | 23.7 days | medium hulls, role skills, Refitting |
| 5 | 42 min | 3.9 h | 22 h | 5.2 days | 29.6 days | specialisations, Augmentation |
| 6 | 50 min | 4.7 h | 27 h | 6.3 days | 35.6 days | heavy hulls |
| 8 | 1.1 h | 6.3 h | 35 h | 8.4 days | 47.4 days | Fleet Command |
| 10 | 1.4 h | 7.9 h | 44 h | 10.5 days | 59.3 days | capital hulls |
| 12 | 1.7 h | 9.4 h | 53 h | 12.6 days | 71.1 days | Famous Ships |

- **Enrolment (the money sink, the reason to travel):** a skill is enrolled once before its first level,
  for tuition `skill_study_base_cost × rank` (500 × rank, the live knob, 0016:52). General skills enrol
  at any academy (`ports.has_academy`); a line's hull skills enrol at **any yard of that line** (to learn
  Chinese hulls you sail to Guangzhou). Levels then train anywhere. The four live skills, and any level
  a house already has, count as enrolled.
- **The queue:** up to `skill_queue_max` 10 entries, each the next level of its skill; prerequisites
  must be met by the time the entry STARTS (checked against the chain); removing an entry keeps its
  SP. No pausing, no "speed-up for ducats".
- **Who trains:** the house. Officers do not (0127's per-signing level is theirs). **Merchants: fixed**
  — no queue, no enrolment; their skill rows are set once by `npc_found` through `public.raise_skill`
  (0096:615, 0097:290-311), and S18 seeds their hull skills the same way, once.
- **The old instant study** (`cmd.study_skill`, 0016:155) is re-cut into a door that enrols (if needed)
  and queues the next level — the Academy button keeps working and starts a timer instead of
  finishing at once. Its core `raise_skill` stays for merchants and seeds only.

### 5.2 The catalogue (≈ 92 skills, 8 groups)

**Hulls (55)** — for each line X ∈ {PRT, ESP, NLD, ENG, FRA, ITA, OTT, IND, CHN, JPN, KOR}:
`X Small Hulls` (rank 1), `X Light Hulls` (2), `X Medium Hulls` (4), `X Heavy Hulls` (6), `X Capital
Hulls` (10, also gates flagships at V). Prerequisites: Light I needs Small III; Medium I needs Light
III; Heavy I needs Medium IV; Capital I needs Heavy IV + Command III. **Per level:** the line's two
traits (§3.1) on that line's hulls of that size (the flagship reads Capital Hulls).

| group | skill | rank | prerequisites | per level | gates |
|---|---|---|---|---|---|
| Roles | Merchant Ships | 4 | Cargo Stowage II | trade-role hulls +3 % hold | heavy+ trade hulls |
| Roles | Ships of War | 4 | Gunnery III | combat-role hulls +3 % attack | heavy+ combat hulls |
| Roles | Exploration Vessels | 4 | Lookouts III | explorer-role hulls +4 % sighting, +1 % speed | heavy+ explorer hulls |
| Roles | Escort & Support | 4 | Hull Upkeep III | support-role hulls +4 % hull | heavy+ support hulls |
| Roles | Armed Merchantmen / Privateers / Survey Ships / Convoy Escorts | 5 each | the matching role skill V | T2 hulls of that role: +4 % of the role stat | T2 hulls |
| Roles | Famous Ships | 12 | Command V, any T2 specialisation III | famous hulls +2 % hull | famous hulls |
| Seamanship | **SEAMANSHIP** (live) | 1 | — | stores last +6 % (live, 0016:288-289); hulls per fleet (0107) | rudders, anchors, capstans |
| Seamanship | Hull Upkeep | 2 | SEAMANSHIP II | +4 % hull, every hull | — |
| Seamanship | Damage Control | 3 | Hull Upkeep III | +3 % armour, every hull | — |
| Seamanship | Deck Management | 3 | SEAMANSHIP III | +5 % Deck budget | — |
| Seamanship | Ship Handling Specialisation | 5 | SEAMANSHIP V | T2 Mid handling modules +3 % | T2 rudder/anchor/capstan |
| Navigation | **NAVIGATION** (live) | 1 | — | leg length doubles per level (0107:47-53); its SPEED effect stays unread as today (0016:291-292; "NOT READ", 0016:35) | — |
| Navigation | Rigging | 2 | NAVIGATION I | +3 % handling | sail modules by grade |
| Navigation | Lookouts | 2 | NAVIGATION II | +5 % sighting | lookout modules by grade |
| Navigation | Instruments | 3 | NAVIGATION III | +2 % sighting | binnacle & charts by grade |
| Navigation | Rigging / Instrument Specialisation | 5 each | Rigging V / Instruments V | T2 sail / instrument modules +3 % | T2 sails / instruments |
| Trade | **ACCOUNTING**, **HAGGLING** (live) | 1 | — | live effects unchanged (0016:288-297) | — |
| Trade | Cargo Stowage | 3 | ACCOUNTING II | +3 % hold, every hull | hold modules by grade |
| Trade | Stowage Specialisation | 5 | Cargo Stowage V | T2 hold modules +3 % | T2 hold frames |
| Gunnery | Gunnery | 1 | — | +3 % attack | guns, magazines by grade |
| Gunnery | Gun Laying | 2 | Gunnery II | +4 % accuracy | — |
| Gunnery | Long Guns | 3 | Gunnery III | +4 % reach | chase guns |
| Gunnery | Short Guns | 3 | Gunnery III | +2 % attack | carronades |
| Gunnery | Boarding | 2 | Gunnery I | +2 % attack | boarding gear by grade |
| Gunnery | Gun Drill | 3 | Gunnery III | High modules need −4 % Hands | — |
| Gunnery | Gunnery Specialisation | 5 | Gunnery V | T2 High modules +3 % | T2 guns, boarding, magazines |
| Command | Command | 3 | SEAMANSHIP III | officers' bonuses +2 % (inside `fleet_officer_bonus`, under the 25 % cap, 0015:50); the house may keep **+1 hull** (`ship_max` 4, 0001:164) | capital hulls (III) |
| Command | Fleet Command | 8 | Command V | prerequisite only, said on the screen | flagship hulls |
| Shipwright | Shipwright | 2 | SEAMANSHIP I | yard labour −3 % | hull (Low) modules by grade |
| Shipwright | Refitting | 4 | Shipwright III | — | refits (I needs I, II needs V) |
| Shipwright | Augmentation | 5 | Refitting III | — | perks (rank ≤ ⌈level/2⌉; a 2nd perk at V) |
| Shipwright | Shipwright Specialisation | 5 | Shipwright V | T2 Low modules +3 % | T2 hull modules |

Every per-level bonus is ONE row of `skill_effects` (skill, stat, pct, optional line/size/role filter),
read by ONE function into ONE place (`world.ship_stats`), so "where does my +15 % hold come from" has
one answer, printed on the ship panel line by line.

### 5.3 Where the numbers land in `world.ship_stats`

`stat = (class base + Σ mounted unit effects × wear factor + set bonuses) × (1 + Σ skill % / 100)
+ hull-level flat gain (0127)`, then 0074's floors. Order fixed and asserted. While `skills_bite` is
false the skill term is 0 and the result is the pre-image to the digit.

---

## 6. Gear like EVE, plus RS3

### 6.1 Racks and budgets (EVE)

| rack | holds (the item TYPE word stays, `ShipPanel.tsx:80-88`) | live kinds folded in | notes |
|---|---|---|---|
| **High** | guns, boarding gear, magazines, swivels | weapon | where fights are won |
| **Mid** | sails, headsails, studding sails, storm canvas, rudders, anchors, capstans, lookouts, instruments | rig, steering, ground-tackle, lookout | handling the ship; most actives live here |
| **Low** | planking, sheathing, ballast, hold frames, bilge pumps | hull | the hull and the hold |
| **Refit** | permanent refits | — (new) | fitted only at a building yard; destroyed when removed; no wear, no perks |
| Flourish | figurehead | flourish | a set piece, no budget |

A rack takes ANY item of its rack (EVE's flexibility): a barca may carry two suits of sails instead of
sails and anchor. Live counts convert exactly — barca H1/M2, carlat H2/M3, nau H3/M5/L1/F1 (0074:125-
140) — and 0127's unlocks convert kind → rack (barca Mid +1 @3, carlat Low +1 @4, nau High +1 @6).
Every item mounted today still fits (asserted).

**Budgets.** `Deck` (EVE's CPU) is a new per-class number (the tables in §4.3); `Hands` (EVE's
powergrid) = `crew_max − ⌈crew_required / 2⌉`, derived from columns the class already has. Each item
costs deck and hands; the check runs only on FIT (adding), so nothing mounted is ever refused after
the fact. Live G1 costs (deck/hands): broadside guns 6/8, boarding gear 2/5, powder magazine 3/2,
suit of sails 3/4, bowsprit & jib 2/2, rudder & helm 2/2, anchor & cable 3/2, crow's nest 1/1, ballast
2/0, copper sheathing 3/0, hold fittings 2/0, figurehead 0/0. With barca 12/16, carlat 22/24, nau
56/110 **every loadout legal under today's typed slots fits** (checked: carlat 2 guns + sails + anchor
+ rudder = 20 deck / 24 hands). Costs rise with quality (+10 % per grade above 1, T2 +50 %, Country
+30 %, Famous +60 %), so a hull cannot carry the best of everything — the EVE fitting puzzle.

**Active vs passive.** Passive modules always apply. **Active** modules carry a `trigger` (a PIRATES
day, a STORM day) and may `consume` a good from the hold per trigger (long guns: 1 shot-and-ball + 1
gunpowder per fight; pumps and storm canvas: nothing but hands). Without their consumable an active
works at half. Today no roll reads attack/armour (`docs/SHIPS_AND_GEAR.md:118-121`), so actives are
modelled now and **bite later** (switch `gear_actives_bite` false) with SHIPS_AND_GEAR S4 and the
hazard re-cut; until then they count as passive — the pre-image.

### 6.2 One item model: base type × grade/meta, perks and wear on the mounted unit

- **Catalogue row** (`item_kinds` + side table `item_profile`: base_type, rack, grade 1-5, meta,
  deck, hands, active, trigger, consumes, set_code, line_code). Stackable in the store and on the quay,
  exactly as `player_items` is today (0068:165-171).
- **Mounted unit** (`fitted_units`, S10): one row per piece on a hull with its own **wear** and up to
  two **perks**. Perks and refits are bound to the unit: unmount it and they are gone (EVE rigs). A
  worn unit is repaired on unmount (the repair is charged), so the store only ever holds pristine items
  — one storage model, no "item instance" in warehouses.

**The meta ladder (EVE) and the grade ladder (RS3), one line per slot:**

| rung | meta | what it is | effect on the stat it BUYS | stat it SPENDS | needs | made at |
|---|---|---|---|---|---|---|
| G1 | 0 | today's twelve items, and the G1 of each new base type | × 1.00 | × 1.00 | nothing (live pre-image) | live `ws_tier` |
| G2 | 0 | better material | × 1.30 (speed/hold: × 1.15) | × 1.00 | module skill II | workstation tier ≥ 2 (47 cities) |
| G3 | 0 | | × 1.60 (× 1.30) | × 1.00 | skill III | tier ≥ 2 |
| G4 | 0 | | × 1.90 (× 1.45) | × 1.00 | skill IV | tier 3 (12 cities) |
| G5 | 0 | the best material | × 2.20 (× 1.60) | × 1.00 | skill V | tier 3 |
| Named | 1-4 | a city's own pattern of a grade (e.g. *Lisbon-cast* G3 long guns) | grade × 1.10, deck −1 | × 1.00 | as its grade | that one city's workstation |
| T2 | 5 | improved | × 2.60 (× 1.80) | × 1.25 | skill V + its specialisation I | tier 3 |
| Country | 6-7 | a line's pattern, set piece, plus a line-flavoured second buy | × 2.40 (× 1.70) | × 1.00 | skill IV + the line's Medium Hulls I | tier ≥ 2 in a port of the line's builder nations |
| Famous | 8+ | the gear of a famous ship | × 3.00 (× 2.00) | × 1.00 | comes with the famous hull (§4), one per house | — |

Speed and hold (the "money stats") climb gentler than the combat stats, because they are profit per
real hour.

**Material ladders (RS3's bronze → rune, for the age of sail)** — every good named is in
`data/goods.json`:

| family | G1 | G2 | G3 | G4 | G5 | T2 component |
|---|---|---|---|---|---|---|
| guns (cast metal) | cast iron — bar-iron (the live broadside guns) | culverin pattern — culverin + bar-iron | brass — brass-ingots + culverin | Swedish iron — swedish-iron + culverin | bronze — copper + tin-ingots + falconet | gunpowder + falconet |
| timber (hull, rudder, frames) | pine/deal — norway-spruce or the live timber | oak — timber | teak — teak | live oak — live-oak + naval-timber | greenheart — greenheart + lignum-vitae | copper-sheet + swedish-iron |
| canvas (sails) | flax (the live suit) | hemp canvas — hemp | duck — canvas-duck | Baltic sailcloth — sailcloth | Holland duck — sailcloth + abaca + whale-bone-stays | abaca |
| cordage & iron (anchors, capstans) | iron + hemp (live) | osmund-iron + hemp | bar-iron + abaca | swedish-iron + abaca | swedish-iron + copper + abaca | lodestone (sheet anchor) |
| instruments (lookouts, binnacle) | naval-timber + cordage (live crow's nest) | riga-mast | brass-ingots + sea-charts | lodestone + sea-charts | lodestone + sea-charts + brass | sea-charts |

### 6.3 Base types (22) and their G1

| rack | base type | G1 item | buys | spends | active? | deck/hands | module skill |
|---|---|---|---|---|---|---|---|
| High | Long Guns | `broadside-guns` (live) | attack +60, reach +15 | hold −20, handling −6 | yes (fight; shot + powder) | 6/8 | Gunnery |
| High | Carronades | new | attack +90 | reach −15, hold −14, handling −4 | yes | 5/7 | Gunnery + Short Guns I |
| High | Chase Guns | new (0129's stern chasers) | reach +20, accuracy +10 | hold −8 | yes | 4/4 | Gunnery + Long Guns I |
| High | Swivel Guns | new | attack +20, accuracy +8 | handling −2 | yes | 2/3 | Gunnery |
| High | Boarding Gear | `boarding-gear` (live) | attack +35 | reach −20 | yes (fight) | 2/5 | Boarding |
| High | Powder Magazine | `powder-magazine` (live) | attack +25, accuracy +12 | hold −10, hull −60 | no | 3/2 | Gunnery |
| Mid | Sails | `suit-of-sails` (live) | speed +0.6 | handling −8 | no | 3/4 | Rigging |
| Mid | Headsails | `bowsprit-and-jib` (live) | handling +10, speed +0.2 | hull −40 | no | 2/2 | Rigging |
| Mid | Studding Sails | new | speed +0.9 | handling −14, hull −30 | no | 4/5 | Rigging |
| Mid | Storm Canvas | new | hull +50, handling +4 | speed −0.25 | yes (storm) | 3/3 | Rigging |
| Mid | Rudder | `rudder-and-helm` (live) | handling +14 | hold −6 | no | 2/2 | SEAMANSHIP |
| Mid | Whipstaff | new | handling +7 | hold −2 | no | 2/1 | SEAMANSHIP |
| Mid | Anchor | `anchor-and-cable` (live) | handling +4 | hold −8 | no | 3/2 | SEAMANSHIP |
| Mid | Sheet Anchor | new | hull +60, handling +2 | hold −10 | yes (storm) | 5/3 | SEAMANSHIP |
| Mid | Capstan | new | handling +6, speed +0.1 | hold −5 | no | 3/3 | SEAMANSHIP |
| Mid | Lookout | `crows-nest` (live) | sighting +5 | handling −4 | no | 1/1 | Lookouts |
| Mid | Binnacle & Charts | new | sighting +3, handling +5 | hold −3 | no | 2/1 | Instruments |
| Low | Ballast | `ballast` (live) | handling +8, armour +6 | speed −0.4 | no | 2/0 | Shipwright |
| Low | Sheathing | `copper-sheathing` (live) | armour +14, hull +120 | speed −0.3 | no | 3/0 | Shipwright |
| Low | Planking | new (doubled planking) | armour +10, hull +160 | speed −0.45, hold −12 | no | 4/0 | Shipwright |
| Low | Bilge Pumps | new | hull +90 | hold −5 | yes (storm; hands) | 3/4 | Shipwright |
| Low | Hold Frames | `hold-fittings` (live) | hold +25 | speed −0.35, handling −5 | no | 2/0 | Cargo Stowage |
| Flourish | Figurehead | `figurehead` (live) | nothing (set piece) | — | no | 0/0 | — |

0129's twelve ideas (`docs/SHIPS_AND_GEAR.md:494-507`) become the ten new base types above (topgallant
mast → a Lookout grade line; whipstaff its own light rudder). Every row keeps 0074's rule — buys one
stat, spends another (asserted, 0074:532-541); the figurehead stays the one exception.

### 6.4 Example ladders, with prices (≈ goods at the middle of their `baseValue` band)

**Long Guns (High)** — module skill Gunnery

| item | attack / reach | spends | needs | made at | recipe | ≈ d. |
|---|---|---|---|---|---|---|
| G1 Broadside Guns (live) | 60 / 15 | hold −20, handling −6 | — | ws 3 (live) | bar-iron 6, timber 2, ships-nails 2 | 1,900 |
| G2 Culverins | 78 / 20 | same | Gunnery II | ws ≥2 | culverin 4, bar-iron 4, timber 2 | 3,100 |
| G3 Brass Guns | 96 / 24 | same | Gunnery III | ws ≥2 | brass-ingots 8, culverin 6, live-oak 3 | 4,200 |
| G4 Swedish Guns | 114 / 29 | same | Gunnery IV | ws 3 | swedish-iron 8, culverin 8, shot-and-ball 2 | 7,300 |
| G5 Bronze Guns | 132 / 33 | same | Gunnery V | ws 3 | copper 12, tin-ingots 8, culverin 10, falconet 2 | 9,300 |
| Named: *Lisbon-cast Brass Guns* | 106 / 26 | same | Gunnery III | Lisbon only | as G3 + slow-match 1 | 5,000 |
| T2 Long Eighteens | 156 / 39 | hold −25, handling −8 | Gunnery V + Gunnery Spec I | ws 3 | swedish-iron 10, culverin 12, falconet 4, gunpowder 4 | 12,400 |
| Country (ENG) *Sea Dogs' Culverin Battery* | 144 / 36, accuracy +10 | hold −20, handling −6 | Gunnery IV + ENG Medium Hulls I | ws ≥2, English port | culverin 14, tin-ingots 6, oakum 4 | 7,900 |
| Famous: *Drake's Culverins* | 180 / 45, accuracy +12 | same | Golden Hind's (one per house) | — | with the hull | — |

**Sails (Mid)** — module skill Rigging; speed is a money stat (gentle ladder)

| item | speed | spends | needs | made at | recipe | ≈ d. |
|---|---|---|---|---|---|---|
| G1 Suit of Sails (live) | +0.60 | handling −8 | — | ws 1 | flax 6, cordage 2, tar 1 | 750 |
| G2 Hemp Canvas | +0.69 | handling −8 | Rigging II | ws ≥2 | hemp 6, cordage 3, tar 1 | 800 |
| G3 Duck Canvas | +0.78 | handling −8 | Rigging III | ws ≥2 | canvas-duck 20, hemp 6, cordage 3, tar 1 | 1,300 |
| G4 Baltic Sailcloth | +0.87 | handling −8 | Rigging IV | ws 3 | sailcloth 10, hemp 6, cordage 4, tar 2 | 2,300 |
| G5 Holland Duck | +0.96 | handling −8 | Rigging V | ws 3 | sailcloth 14, abaca 8, whale-bone-stays 4, tar 2 | 2,900 |
| T2 Racing Courses | +1.08 | handling −10 | Rigging V + Rigging Spec I | ws 3 | sailcloth 18, abaca 10, whale-bone-stays 6, canvas-duck 6 | 3,700 |
| Country (FRA) *Toiles de Bretagne* | +1.02, handling +4 | handling −8 | Rigging IV + FRA Medium Hulls I | ws ≥2, French port | canvas-duck 30, sailcloth 8, hemp 6 | 2,600 |

**Hold Frames (Low)** — module skill Cargo Stowage; hold is a money stat

| item | hold | spends | needs | made at | recipe | ≈ d. |
|---|---|---|---|---|---|---|
| G1 Hold Fittings (live) | +25 t | speed −0.35, handling −5 | — | ws 2 (live) | timber 5, ships-nails 3, oakum 2 | 400 |
| G2 Teak Frames | +29 t | same | Cargo Stowage II | ws ≥2 | teak 5, ships-nails 4, oakum 3 | 700 |
| G3 Live-oak Frames | +33 t | same | III | ws ≥2 | live-oak 10, teak 4, ships-nails 5, oakum 4 | 1,000 |
| G4 Knee-braced Frames | +36 t | same | IV | ws 3 | live-oak 14, naval-timber 4, lignum-vitae 6, oakum 6 | 2,100 |
| G5 Greenheart Frames | +40 t | same | V | ws 3 | greenheart 20, naval-timber 6, lignum-vitae 8, copper-sheet 6 | 2,500 |
| T2 Orlop Stowage | +45 t | speed −0.44, handling −6 | V + Stowage Spec I | ws 3 | naval-timber 10, greenheart 20, copper-sheet 10, swedish-iron 2 | 3,700 |
| Country (NLD) *VOC Frames* | +42 t | speed −0.18, handling −5 | IV + NLD Medium Hulls I | ws ≥2, Dutch/Hanse port | memel-fir 30, norway-spruce 20, oakum 6 | 1,400 |

**Planking (Low)** — module skill Shipwright

| item | armour / hull | spends | needs | recipe | ≈ d. |
|---|---|---|---|---|---|
| G1 Deal Planking | 10 / 160 | speed −0.45, hold −12 | — | norway-spruce 12, ships-nails 4, oakum 2, pine-pitch 2 | 400 |
| G2 Oak Planking | 13 / 208 | same | Shipwright II | timber 12, ships-nails 5, oakum 3, tar 1 | 900 |
| G3 Teak Planking | 16 / 256 | same | III | teak 10, ships-nails 6, oakum 3, tar 1 | 1,400 |
| G4 Live-oak Planking | 19 / 304 | same | IV | live-oak 16, naval-timber 4, ships-nails 8, oakum 4 | 1,900 |
| G5 Greenheart Planking | 22 / 352 | same | V | greenheart 20, lignum-vitae 10, naval-timber 6, copper-sheet 8 | 2,400 |
| Country (KOR) *Turtle-back Plating* | 30 / 250 | speed −0.6, hold −12 | IV + KOR Medium Hulls I | iron 20, copper-sheet 10, timber 10 | 2,000 |

The other eighteen base types follow the same two rules (the multipliers of §6.2 and the material
ladder of their family); the generator (`scripts/build-gear.mjs`, S12) writes every row, its recipe,
its requirement and its price, and asserts each against 0068's and 0074's rules.

**Catalogue size when complete:** 22 base types × 5 grades = 110 (12 live) · T2 22 · Named ~12 ·
Country 44 (4 per line) · Famous 11 · refits 16 · perk kits 4 ≈ **220 item kinds**.

### 6.5 Wear and repair (RS3 degradation)

- A mounted unit wears: Mid canvas/rigging items `gear_wear_per_1000nm` 1.0 per 1,000 nm; High
  items `gear_wear_per_fight` 4 per PIRATES day; Low and Mid hull-keeping items `gear_wear_per_storm`
  3 per storm day. Written by ONE hunk in `voyage.settle`'s arrival arm, beside 0127's XP hunk and
  behind the same one `players.is_npc` read (0127:352-365) — **player fleets only**; merchant gear is
  fixed and never wears.
- Effect: the BUY side × `(1 − wear / 200)` — a unit at 100 wear works at half. **Nothing ever breaks to
  dust**: the owner's long grind is in the skills, not in losing things.
- Repair at any port with a repair yard, through the existing repair door (one "repair" authority,
  paying the city's `REPAIR` flow, 0122): cost = the item's recipe value × wear % × `gear_repair_pct`
  0.30. A G1 sail at 100 wear (≈ 100,000 nm) costs ≈ 220 d. to repair.
- Ships DARK (`gear_wear_bite` false: wear accrues, the factor reads 1).

### 6.6 Perks (RS3 augments) — chosen, never rolled

A unit of grade ≥ 3, T2, Country or Famous may be **augmented** at a tier-3 workstation with **kits**
(made items): Gunsmith's Kit (swivel-gun, slow-match, gunpowder), Sailmaker's Kit (sailcloth,
whale-bone-stays, abaca), Shipwright's Kit (lignum-vitae, copper-sheet, oakum), Navigator's Kit
(sea-charts, lodestone). A perk of rank r costs r kits; Augmentation level L allows rank ≤ ⌈L/2⌉ and a
second perk at V. The player CHOOSES the perk (no lottery — the project's rule, 0126:30).

| perk | rack | rank 1 / 2 / 3 | kit |
|---|---|---|---|
| Weatherly | Mid | handling +3 / +6 / +9 | Sailmaker's |
| Swift | Mid (canvas) | speed +0.05 / +0.10 / +0.15 | Sailmaker's |
| Precise | High | accuracy +3 / +6 / +9 | Gunsmith's |
| Far-reaching | High | reach +4 / +8 / +12 | Gunsmith's |
| Hard-hitting | High | the unit's attack +5 / +10 / +15 % | Gunsmith's |
| Stout | Low | the unit's hull +4 / +8 / +12 % | Shipwright's |
| Roomy | Low (hold) | hold +2 / +4 / +6 t | Shipwright's |
| Seasoned | any | wear × 0.75 / 0.50 / 0.25 | any |
| Light | any | deck −1 / −2 / −3 (never below 1) | Shipwright's |
| Handy | High | hands −10 / −20 / −30 % | Navigator's |

### 6.7 Sets (RS3) — one per line, four pieces (High, Mid, Low, Figurehead)

| set | 2 pieces | 4 pieces |
|---|---|---|
| PRT *Carreira da Índia* | +3 % hold | +5 % sighting, +3 % hull |
| ESP *Flota de Indias* | +5 armour | +8 % attack, +5 % hull |
| NLD *VOC Return Fleet* | +4 % hold | fitted items need −10 % hands, +5 handling |
| ENG *Sea Dogs* | +5 accuracy | +8 reach, +2 % speed |
| FRA *Ponant* | +4 handling | +6 reach, +4 % hull |
| ITA *Arsenale* | +5 % attack | +8 handling |
| OTT *Kapudan* | +5 armour | +8 % attack |
| IND *Monsoon* | +3 % hold | +2 % speed, +5 handling |
| CHN *Ming Treasure* | +5 % hull | +4 % hold |
| JPN *Red Seal* | +5 accuracy | +6 % attack |
| KOR *Yi Sun-sin* | +6 armour | +10 armour, +4 accuracy |

A set bonus works on any hull; set pieces are the Country rung of their base type.

### 6.8 Refits (EVE rigs) — permanent

Fitted only at a building yard, into the Refit rack; cost no deck or hands; never wear; **destroyed
when removed**. Refit I needs Refitting I; Refit II needs Refitting V.

| refit | I | II | recipe gist |
|---|---|---|---|
| Fine Lines | speed +0.2, hold −15 | speed +0.35, hold −20 | live-oak, lignum-vitae |
| Extended Hold | hold +30, handling −6 | hold +50, handling −8 | timber, ships-nails |
| Doubled Frames | hull +200, speed −0.15 | hull +320, speed −0.2 | naval-timber, live-oak |
| Raised Forecastle | armour +8, handling −5 | armour +14, handling −6 | timber, oakum |
| Shallow Keel | draft −1 (never below 1), hold −20 | draft −1, hold −10 | greenheart, copper-sheet |
| Lateen Re-rig | handling +10, speed −0.1 | handling +16, speed −0.1 | hemp, naval-timber |
| Pierced Gun Deck | attack +40, hull −100 | attack +70, hull −120 | timber, bar-iron |
| Lookout Top | sighting +2, handling −2 | sighting +4, handling −2 | riga-mast, cordage |

### 6.9 Reconciling with the live gear

- `item_kinds` (0068) stays the one catalogue; `item_effects` (0074) stays the one effect table; the
  twelve live codes keep their codes, recipes and effects as **G1** (asserted byte-equal).
- `public.mount_fitting` (0126) stays **THE one writer** of a mounted fitting — re-cut by hunks to write
  `fitted_units`, check RACK capacity through `world.ship_slots`, the budgets through
  `world.ship_budget`, and requirements through `public.requirements_met`; `cmd.do_unfit`'s core becomes
  `public.unmount_fitting` (repairs on the way off; destroys refits and perks). No `is_npc` in either.
- **Merchant loadouts** (`npc_loadouts`, 0126) stay fixed and G1 (they need no skill, so the core's
  requirement check passes for a merchant without an exemption); merchants never wear, are never
  augmented, carry no refits. S18 authors G1 patterns for the new classes merchants sail.
- `item_level_asks` (0127:163-171) is EMPTY on prod (its comment says so) and is dropped in S11 after
  asserting it is still empty; if anything was ever put in it, each row is converted to a skill
  requirement first.

---

## 7. Economy fit

- **Anchors.** Starting purse 8,000 d. (0001:146): a barca all-in is ≈ 5,900 d. — a new house can
  still lay down its first hull. The nau, the dearest hull today, is labour 30,000 + ≈ 19,400 in
  goods. T1 sizes all-in: small ≈ 4,400-7,600 · light ≈ 10,800-20,000 · medium ≈ 35,000-56,000 · heavy
  ≈ 55,000-88,000 · capital ≈ 88,000-145,000 · flagship ≈ 208,000-245,000. T2 ≈ 2-2.3 × its T1 size;
  famous ≈ 55,000 (Golden Hind) to ≈ 880,000 (San Martín). Gear: a G1 module ≈ 400-1,900, G5 ≈ 2,400-
  9,300, T2 ≈ 3,700-12,400.
- **What I could not measure:** a PLAYER house's earnings per real day. Merchant laps before 0128 sold
  ≈ 3,300, bought ≈ 2,900, paid 300-430 in wages (0128:12-13). S12's receipt reads the ten richest
  player ledgers' net per day and prints "days of earnings per hull size" before Wave B is priced; the
  one lever is a single multiplier on yard labour (`hull_labour_mult` 1.0), never per hull.
- **Cities:** yard labour goes into the yard city's purse (0122:573-576), so the seven arsenals and the
  tier-3 workstation cities become the rich shipbuilding towns — it feeds 0123's investment loop.
- **Goods demand:** line recipes pull Baltic tar and fir to the Netherlands, teak and coir to India,
  live oak from the Americas to Iberia, culverins from England, sailcloth from the Baltic — new trade
  for players without a single new rule.
- **Hold and speed bonuses are the economic risk** (a Dutch hauler at NLD Medium V + Merchant Ships V +
  Cargo Stowage V + 4 VOC pieces is ≈ +45 % hold). They are players-only (merchants have no line
  skills until S18, and then fixed); each % is one `skill_effects` row.
- **Long grind:** ~3 months of queue to a flagship, ~4-5 months to a famous flagship, ~6 days per
  rank-1 skill to V — and every grade of every module wants its skill level.

---

## 8. Build steps (S8 …), in order

Numbers are assigned when scheduled (0129 is stopped; `npm run db:check-versions` arbitrates). Every
migration: pre-images first, hunks sliced from LIVE bodies and asserted to occur once, positive
controls, probes on throw-away houses only, all knobs via `set_config` in `do` blocks, no top-level
`LOCK TABLE` / `set local` / `begin`, no `set role` in asserts, new state in side tables, the world
guard (`scripts/db/world-guard.mjs`) extended in the same PR as each data step (SHIPS_AND_GEAR's S7,
done step by step), and the arrivals-tick read cost timed before/after like 0127 (0127:113-121).

| step | what it changes | self-assert | knobs | rollback | client |
|---|---|---|---|---|---|
| **S8** Countries & yards | +3 nations (GUJ, MLB, BAN) and the port fixes (Old Goa → PRT; Surat, Khambhat → GUJ; Kozhikode, Kochi, Kannur, Kollam, Mangaluru → MLB; Jakarta, Banten → BAN) in `world-derive.mjs` + an UPDATE of `ports.nation_id`; `ship_lines` (11 rows, `data/ship-lines.json`); side table `class_profile (class_code, line_code, size 1-6, role, tech, deck, any_yard)` — `ship_classes.tier` = `least(size, 5)`, so its 1-5 check is never altered; the 3 live classes tagged PRT with `any_yard` true; 7 arsenal `building_yard` tiers → 3 (authored list); `cmd.do_build` hunk: the yard's nation ∈ the line's builders unless `any_yard` (`E_WRONG_YARD`, figures) | the 3 live classes buildable at every yard exactly as before (probe house, every yard); every line has ≥ 1 tier-3 yard; only the 7 arsenal rows and the listed ports changed (counts); the derive script and the DB agree (guard); `ship_classes` untouched (row hash) | — | forward migration restores the 7 tiers and port nations, re-cuts `do_build`, drops the new tables | Codex & yard show a hull's country flag |
| **S9** Skills I: catalogue + queue | skill rows (~88 new; `skills.effect` check re-made `not valid` → `validate` to admit `NONE`, under `lock_timeout`), `skill_profile`, `skill_prereqs`, `skill_queue`, `skill_sp`; `skill_level` re-cut (queue term); `world.skills` extended (groups, ranks, prereqs, queue, SP, ETA); `cmd.study_skill` re-cut to enrol + queue; NEW `cmd.skill_enroll`, `cmd.skill_queue_set` (+2 entry points) | every house's level in the four live skills = pre-image; `player_skill_bonus` and 0107's gate results = pre-image for every player; a probe house enrols, queues, and `skill_level_at(probe, code, t)` steps exactly at the computed `finishes_at` (pure function, no clock travel); prereq refusal with figures; merchants have no queue rows; no cron added; entry points +2 exactly | `skill_sp_per_hour` 1,800 · `skill_queue_max` 10 · reuses `skill_study_base_cost` | re-cut `skill_level`/`study_skill` back; queue tables dropped (levels already folded stay — they were earned) | Academy → **Skills** screen: groups, queue with timers, "trains while you are away" |
| **S10** Gear I: racks, units, budgets | `class_slots` rows rewritten by RACK (+ Refit rows), `class_slot_unlocks` converted; `item_profile`; `fitted_units` + backfill from `ship_fittings` (qty → rows); `mount_fitting` / new `unmount_fitting` (core of `do_unfit`) re-cut; `world.ship_slots`, NEW `world.ship_budget`; `world.ship_stats` reads units (wear factor 1); `ship_fittings` → read-only view | every hull's ten stats = pre-image to the digit; `ship_view` = pre-image plus the new keys; Σ units = Σ qty per hull; every mounted item fits its rack; every loadout legal under the old typed caps fits the budgets (enumerated for barca/carlat/nau); over-budget hulls counted (expect 0); only `mount_fitting`/`unmount_fitting` write `fitted_units` (live-body scan + control); merchant hulls' units = their 0126 loadout | — (budgets bind on new FITs only) | forward migration: rebuild `ship_fittings` from units, re-cut the cores back | `ShipPanel`: High/Mid/Low/Refit racks + Deck and Hands bars |
| **S11** Skills II: effects & requirements (DARK) | `skill_effects`, `skill_requirements`; `world.skill_pct` into `ship_stats` (one hunk); `player_skill_bonus` re-cut onto `skill_effects`; `requirements_met` in `do_build` (door) and `mount_fitting` (core); Command → `fleet_officer_bonus` and the house hull cap (`assert_house_caps`, 0107) hunks; Deck Management / Gun Drill in `ship_budget`; `item_level_asks` dropped (asserted empty) | dark: every stat, slot, budget, refusal, officer bonus and cap = pre-image; lit in a rolled-back block: a probe house with PRT Medium Hulls III reads +12 % sighting and +6 % speed on its nau, Command II lets it keep a 6th hull; G1 items need nothing, so a probe merchant's `npc_fit_loadout` still mounts; merchant hull read cost timed | `skills_bite` false · `command_hulls_per_level` 1 | `skills_bite` false (one UPDATE) | ship panel lists each bonus by source; yard and workstation print "needs X IV" |
| **S12** Wave A: 52 hulls + Wave A gear | generators `scripts/build-ships.mjs`, `scripts/build-gear.mjs`; `ship_classes` + `class_profile` + racks + cabins + recipes for 52 hulls; 55 hull-skill requirement rows; gear G2-G5 of the 12 live types and G1-G5 of the 10 new types (~98 rows) with effects, recipes, costs, requirements | the 3 live classes and 12 live items unchanged (row hashes); 0072 (b)(c)(d) and 0068/0074 asserts over everything; `guns = attack/10` for all; every hull buildable at ≥ 1 yard of its line; every recipe good sold somewhere; generator re-run equals the DB | `hull_labour_mult` 1.0 | delete the new rows (asserted: no hull/unit/store row references them) | silhouettes by rig × size (8 shapes, not 52); `HullClass` becomes the served code with a fallback (`mapTypes.ts:167`, `liveWorld.ts:103`, `glyphs.ts:132`); Codex grid filters by line/size/role/tech |
| **S13** Gear II: wear, repair, refits, actives (DARK) | `settle` wear hunk (player fleets only, behind 0127's `is_npc` read); wear factor in `ship_stats`; the repair door repairs units; Refit rack fitting at a building yard; `item_profile.trigger/consumes` recorded | dark: stats = pre-image while wear accrues; a probe player arrival wears its sails by miles/1,000; a probe merchant arrival writes nothing; repair charges and pays the city; a removed refit is gone; tick timing printed | `gear_wear_bite` false · `gear_wear_per_1000nm` 1 · `gear_wear_per_fight` 4 · `gear_wear_per_storm` 3 · `gear_repair_pct` 0.30 · `gear_actives_bite` false | switches off; hunk re-cut out | wear bar per unit; "Repair all" at the yard |
| **S14** Wave B: 15 capitals & flagships | rows + recipes + requirements (Command, Fleet Command) | as S12; plus 0072 (d) "fits in the shed" — if a flagship's goods exceed the shed, goods are capped to the shed and the difference moves into labour (never loosen the assert) | — | delete rows | silhouettes for size 5-6 |
| **S15** Wave C: 22 T2 hulls + T2 & Named gear | T2 hulls, 22 T2 modules, ~12 Named items, the 10 specialisation skills' requirement rows | as S12; T2 requirements refuse with figures; Named items makeable only at their city | — | delete rows | "T2" badge |
| **S16** Gear III: perks, Country gear, sets | kits; `cmd.augment_fitting` (+1 entry point); perks on units; 44 Country items; 11 sets with a set term in `ship_stats` | a probe unit takes a chosen perk and loses it on unmount; set bonus appears at 2 and 4 pieces only; perks/sets absent → pre-image | `perks_max_per_unit` 2 | delete rows; re-cut the hunk out | perk picker; set progress on the ship panel |
| **S17** Wave D: 11 famous ships | rows; famous gear as `hull_recipe_items`; one-per-house check in the `do_build` door | a second famous of the same code refused for a probe house | — | delete rows | "Famous" badge and the ship's history line |
| **S18** Merchants of every flag | `npc_found` picks a line hull by home port nation; a one-time conversion of existing merchant hulls to their line's hull nearest in hold (±10 %) and speed; merchant hull skills fixed once via `raise_skill`; G1 patterns for new classes in `data/npc-loadouts.json` | merchant fleet hold within ±10 % and speed within ±5 % of pre-image per fleet; no player row touched; no merchant queue rows; zero-net lap share and arrivals duration measured before/after (the 0120 method) | — | reverse conversion from the printed pre-image | the sea shows Dutch fluits in the Baltic, junks off China |

SHIPS_AND_GEAR's **S4** (combat stats bite) stays where it was; actives (§6.1) and armour/attack from
gear matter in a roll only once S4 and the hazard re-cut land. Its **S5/S6** are superseded by S8/S12
and §6.

---

## 9. What the owner will see

- At a yard, ships now carry a **flag**: Portuguese, Spanish, Dutch, English, French, Italian, Ottoman,
  Arab-Indian, Chinese, Japanese, Korean. Each country builds its own ships in its own yards — Chinese
  junks at Guangzhou, fluits at Amsterdam and Hamburg, galleys at Venice. Over the waves, ~100 ships
  from a fast little jacht to the treasure ships and famous names like the Golden Hind, Batavia and
  the turtle ship.
- A **Skills** screen like EVE: you queue skills and they train in real time, even while you are
  away. "Dutch Medium Hulls" lets you build Dutch medium ships and makes every Dutch ship of that size
  carry more per level. The first new ship takes hours of training; a capital ship weeks; a flagship
  about three months.
- Your ship's equipment becomes **High / Mid / Low / Refit** racks with two bars — deck space and
  hands — so you cannot fit the best of everything.
- Gear comes in **grades** like RuneScape's metals — deal → oak → teak → live oak → greenheart, iron →
  brass → bronze guns, flax → sailcloth — each needing a higher skill, then T2, country patterns that
  form **sets**, and the famous ships' own gear. Gear **wears** and is repaired at a yard; good gear can
  be **augmented** with a perk you choose. Refits are permanent.
- Nothing you own today changes or is taken away. Merchants keep fixed gear and fixed skills; later
  they sail their own country's ships.

---

## 10. Risks

1. **The arrivals tick.** `world.ship_stats` is read per merchant hull through speed and hold
   (0127:113-121 times exactly this read). The skill and wear terms add lookups; merchants have no
   queue rows and (until S18) no line skills, but the join still runs. Each step prints the read time
   before/after and refuses (self-assert) on a regression above a stated bound.
2. **Data volume** (~100 hulls, ~220 items): only generators + the world guard keep it honest; no
   hand-written row in a migration that the generator did not produce.
3. **The shed assert** (0072 (d)) for capitals and flagships (§8 S14 rule).
4. **Client union types** for hull codes (`docs/SHIPS_AND_GEAR.md:614-617`) — S12 must make the code a
   served string with a fallback silhouette.
5. **Player profits** rise with hold/speed traits; every % is one row and `skills_bite` is the net.
6. **Anachronism:** the game's nations are those of 1550 (`world-derive.mjs` NATIONS comment); the
   Dutch, English and French ship types are from 1570-1640. Accepted as flavour.

---

## 11. Owner questions (only what cannot be decided here)

1. **Does a house's founding nation give a head start?** A house picks a nation at signing (0004:291-
   296). Default in this plan: **no** — the nation is a name; everyone starts with the Lisbon hulls and
   trains any country. The alternative is free Small III + Light I in your own nation's line.
2. **Should anything ever be lost for good?** Default: **no** — gear wears to half strength and is
   repaired, ships are never deleted by this plan; only refits and perks vanish when removed (EVE's
   rule).

Everything else is decided above and is a knob: the pace of training (`skill_sp_per_hour`), the cost
of hulls (`hull_labour_mult`), wear and repair rates, and each per-level percentage.
