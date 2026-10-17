# SKILLS AND CAPTAINS — EVE's house skills, Origin's captains (v2 design)

**Status: DESIGN v2, BUILD-READY (2026-10-17). K0 (0149) and K1 (0151) are LIVE and dark; K4 (0156, `osn-k4-captains`, 2026-10-18) and K5 (0157) are LIVE and dark; K6 (0160, `osn-k6-levels`) K7 (0161, `osn-k7-traits`) and K8 (0162, `osn-k8-promotion`) are built, not deployed** — dev-log `docs/dev-log/2026-10-18-k4-captains-grades-traits.md`. The rest of this paragraph is the plan as written:
no production change. Written against production head **0140**, read-only. `docs/INFLUENCE.md` has
already claimed 0141–0146 (I1–I6), so the slices here are numbered **K0, K1, …** and get migration
numbers only when they are scheduled (`npm run db:check-versions` decides).

**The research behind it** (in this PR, so the plan and its sources land together):
- `docs/research/UWO_SKILLS_AND_CAPTAINS.md`: Uncharted Waters Origin's mates, cabins, grades,
  promotion, effects and languages. It is cited here as **[UWO §n]**.
- `docs/research/EVE_SKILLS.md`: EVE Online's skill system and the "thin / wrong" audit of ours. It is
  cited here as **[EVE §n]**.

**The owner, 2026-10-17, verbatim:** *"do a thorough research … of 대항해시대 오리진 (Uncharted Waters
Origin), their skills and EVE-style skill sets, and make them properly. so are captains — 선장 in
대항해시대 오리진 … apply it to the game as well. this is very important."*

**Still binding, the owner's earlier words (each one is an OWNER rule below):**

| # | The owner said | Source |
|---|---|---|
| **O1** | *"skill systems like eve too"*, and today: *"EVE-style skill sets … make them properly"* | `SHIPS_AND_SKILLS.md` header; today |
| **O2** | Today: the captains of 대항해시대 오리진, *"apply it to the game as well"* | today |
| **O3** | *"captains. There will be ranked. S rank the best, A, B C - for now. C ranked captains will be able to promote to B, A, S. The S ranked captain will have 5 skill slots, with 10 skills. A 4 skill slots, with 8 skills, you get the pattern."* | row 61 |
| **O4** | *"Promotion will be done with requirements - levels. items that will be earned when doing activities like trading, combat, exploration - like for 건조소 but different items"* | row 61 |
| **O5** | *"captains will also be designated a role - role based on combat, exploration, trading … trading specialized captains, such as jewelery trader, meat trader etc. make one captain for each role. combat close, long range, etc."* | row 66 |
| **O6** | *"navigator could be increasing speed, or make wheather more fable etc, surgeon could be a healer where captains may be homesick even crews"*. The four jobs survive as skills a captain may know. | row 70; `DESIGN_V1.md` §13 #4 |
| **O7** | *"Each ship will also have cabins that can have captain. for tier 1 … 3 captain slot. it will grow as the tier of the ship grows"* | row 68 |
| **O8** | A captain's level is **per signing** (dismissed and signed again, she starts over). Merchant captains, skills, levels and gear are **fixed**. Levelling is a **long grind**. | 0127 header, 2026-10-15 |
| **O9** | Captains come from the inn: from their own country first, then related fields, *"not 100%, S tear especially"*, and the room turns over every 15 real minutes | 0073, row 133, 0119 |

**How rules are tagged.**
- **OWNER Ox**: the owner said it (the table above). Copying Origin or EVE **as published** counts as
  OWNER O1 / O2, because the order was to apply them.
- **DEFAULT Dx**: my choice. That covers every number I adapted, every place we diverge from Origin or
  EVE, and every gap the owner left open. Each one is in the table below, with the research it rests on.
- **LIVE**: already in the game, with the migration cited. It is not re-decided here.

The owner has been burned by rules I invented (the draft gate, removed by 0139). So this plan adds
**no new gate**. No hull, port, sea or route is refused because of a captain, a language or a grade
(D9, D14). Every number is a knob in `world_config` with one reader.

---

## Owner to confirm — every DEFAULT in this plan, in one table

| # | DEFAULT | Why (research) | If you say no |
|---|---|---|---|
| **D1** | **The training queue holds 50 levels** (it holds 10 today). | EVE allowed 50 from 2009 and 150 from 2021, and never fewer [EVE §1.6]. A queue costs nothing to store. | Keep 10, or set any number: it is one knob. |
| **D2** | **The hull ladder asks for III, not IV**: Heavy Hulls I needs Medium **III**, and Capital Hulls I needs Heavy **III**. The heavy and capital hulls' requirement rows change to match. | CCP cut every class prerequisite from IV to III in 2013 so that "no vessel should require another to be mastered" [EVE §0.4, §3.3]. IV takes 5.7 times as long as III, and ours is the only ladder that still asks for it. | Keep IV. |
| **D3** | **The 33 general skills can be enrolled in any port** (today: only at an academy). Line hull skills stay at that line's yards ("to learn Chinese hulls you sail to Guangzhou"). | EVE's Skills on Demand (2019) removed the location friction for core skills and kept rare skills location-gated [EVE §1.7, §0.12]. | Academies only, as today. |
| **D4** | **T2 specialisations ask for one support skill at V**: Armed Merchantmen needs Cargo Stowage V, Privateers needs Gun Laying V, Survey Ships needs Lookouts V, and Convoy Escorts needs Hull Upkeep V. **Each specialisation gives a second bonus per level** on its T2 hulls (§3.2). | In EVE, T2 = class skill V + the line skill + support skills at V, and every T2 hull reads two bonuses per level from its line skill [EVE §0.5, §0.6, §2.4]. | Specialisations stay as they are (one bonus, no support skill needed). |
| **D5** | **15 new skills, 92 → 107** (§3.3): five Trade, three Navigation, two Seamanship (one is **Crew Drill**, +3 % Hands per level), a new **Social** group of three, and two Command. Every one moves a rule that already exists. Hull skills drop from 60 % of the catalogue to 51 %. | Our Trade group has 4 skills to EVE's 15, Navigation 6 to 15, and there is no Social group. Crew Drill is EVE's Power Grid Management, the missing half of the fitting pair [EVE §5, recommendations 4 and 10]. | Strike any row; each one is a data row and at most one hunk. |
| **D6** | **Bonus training from sailing**: an arrival after a passage of at least 300 nm adds 1,000 skill points to the skill in training, up to 10,000 a real day. It is never sold for coin. | EVE pays 10,000 SP a day for daily goals. It is the one accelerator EVE's players accept [EVE §1.9, recommendation 8]. 10,000 is about 23 % of a day's training. | No bonus (the knob is set to 0). |
| **D7** | **Three things are never added**: skill injectors or extractors, attributes or remaps, and skill points sold for coin. | Injectors are EVE's most criticised feature, and CCP itself has wanted attributes gone since 2015 [EVE §0.11, §3.2]. | — (each would need a design of its own) |
| **D8** | **Words**: the people are **captains**, which is your own word (rows 61, 66, 133). What a captain can do is a **trait**, your word from row 113 ("captain traits"), so that **Skills** stays the company's word (the Academy). The game stops calling you, the player, "captain"; you are **you** (`WORDS.md` row "the person in charge of a fleet" changes). | WORDS law 3 says one word per thing. Origin itself separates mate *effects* from the admiral's *skills* [UWO §4.1]. | Call them "skills". The Academy and the captain card would then share one word for two things. |
| **D9** | **Cabin layout**: seat 1 on every ship is the **Captain's cabin**. The other seats (the live 3–8 per ship) are typed **Trade / Exploration / Combat** cabins, in turn, starting with the hull's own role (a trade hull: Trade, Exploration, Combat, Trade, …; a support hull counts as Exploration). Captains are seated, and traits changed, **only while that ship is in port**. **A ship needs no captain to sail.** | Origin has one Captain's Cabin plus typed cabins, and an off-focus seat costs up to 50 % [UWO §3.5]. That 50 % is OWNER O2. The rotation is mine: it seats every merchant officer of today at full value on the three hulls merchants sail (§6.2). | Other layouts are data (`cabin_layout`, generated). |
| **D10** | **Grades for the 63 captains who exist**, from what each is worth today (`bonus_pct`): **C** 4–5 % (18 captains), **B** 5.5–6.5 % (17), **A** 7–8 % (20), **S** 8.5–9 % (8). | 0073 already treats `bonus_pct` as the rarity stand-in ("no ranks yet") [UWO §7 "Grades"]. Nothing a captain does changes. | Name the grades captain by captain; it is a data file. |
| **D11** | **A captain's three levels come from her fleet's record**: Exploration from miles (0127's rate), Combat from pirates seen off (0127's points), Trading from her fleet's trade turnover (100 🪙 = 1 point, 0069's rate). A Trade cabin pays 100 % of Trading experience and 50 % of the other two, and the same for each focus. The Captain's cabin pays 100 % of all three. **Her level in a focus never passes your company's level in that track.** | Origin: three levels by activity, cabin experience at 100 % / 50 %, and a mate's level capped at Company level [UWO §3.3]. The rates are the ones the game already uses. | No cap, or other rates. |
| **D12** | **Promotion C → B → A → S**: her level in her job's focus is at least **5 / 10 / 15**, and she spends **10 / 20 / 40** promotion items of her focus. The items are **Trade Seals**, **Sea Charts** and **Battle Honours**: the same item for every captain, never one per captain. You earn **one item per 100 points** your fleets earn in that track (a Sea Chart ≈ 100,000 nm), put into storage at the port of arrival. Trading points come far faster than miles, so the Trade Seal's figure is **measured in K8**, not guessed: it is set so that a seal takes about as long as a chart. A promotion adds trait slots and known traits (your 2/4 → 5/10 pattern), and lifts every trait to at least the new grade's lowest value. | Origin: contracts 10 / 20 / 40 / 80 per promotion, level gates 30 / 50 / 70 / 90 (out of ~100; ours are scaled to our cap of 20). Its per-mate contracts were its most hated wall and were removed for B and C in 2026. Training raises a low-born mate's numbers ("C can matter") [UWO §3.7, §3.8, §5.3]. | Other counts or gates (knobs); or promotion changes slots only. |
| **D13** | **Homesickness**: a captain who has not docked in her **home region** for **72 real hours** is homesick. Her traits then work at **80 %**. Each point of Surgeon care in her fleet cancels one point of that 20 %, and Hospitality (§3.3) cancels 2 more per level. The clock starts when she is hired and restarts every time her fleet docks in her home region. There is **no loyalty meter**. Merchant captains are never homesick. **Crew homesickness is not in this plan.** | Origin's Homesickness is a fleet-wide state that a Counselor relieves at 3.3 % per effect level [UWO §3.10]. Origin's loyalty timers are its busiest busywork [UWO §0.10], and `DESIGN_RESEARCH` D4 dropped loyalty for that reason. Your row 70 asks for exactly this: a surgeon who heals homesick captains. | Other numbers (knobs); or crew homesickness too (a slice of its own). |
| **D14** | **Languages: 20**, one for each people the map has (§4.9). Each harbour has one language (authored by the world generator). A captain speaks her home's language, and an A or S captain one or two more. **A language is never a gate.** If one of the captains in the haggling fleet speaks the port's language, bargain odds there rise by **5 points**. | Origin has 36 languages and makes them a hard port gate [UWO §4.6]. Its history says every gate placed on people was later loosened [UWO §5.3], and our own lesson from the draft gate says the same. Origin values level 5 in a language at about 5 % on prices. | Languages as display only, or Origin's hard gate. |
| **D15** | **Traits beyond the ones you named**: **Provisioner** (supplies last longer, Origin's Supply). **The roster grows from 63 to 105** so that every job has at least two captains (one C or B, one A or S), spread across the nations. Every captain carries a **kit of 10 ordered traits**, made by a generator: her job first at her base value, the rest at 60 % of it. A new hire uses her first traits, up to her slots. | Origin: the job sets the kit's skeleton, and effects unlock with promotion [UWO §3.2, §3.7]. | Strike Provisioner; or a different roster size (data). |

**Consequences to know (stated, not gated):**
- **Almost nobody holds any progress today** (prod, 2026-10-17): the 17 players hold **one** skill
  level between them (NAVIGATION I), **0** queue entries, **0** banked skill points and **1** signed
  captain (not posted), and `officer_xp` has 0 rows. So every catalogue fix lands with nothing to
  convert. Merchants hold 1,425 skill rows (the four live skills, I–III) and 511 signed officers posted
  to 498 fleets. Those are held to their exact pre-image (§6).
- **What merchants get from their officers does not move.** For all 498 merchant fleets, speed, cargo
  space, spread and raid losses are proven equal to today's, dark and lit (§6.2, §7).
- **Combat traits do nothing until combat lands** (S4). They are in the catalogue, and their cards say
  *"works when combat arrives"*.

---

## 0. The answer in twelve lines

1. **Two progressions, each with one home.** The **company** learns **Skills** (EVE: a real-time queue,
   ranks, prerequisites; what you may build and fit, plus per-level bonuses). The **captains** carry
   **traits**, a **grade**, **three levels** and **languages** (Origin's mates). Neither one ever writes
   the other's numbers.
2. **The skills are 0131/0133's, fixed by EVE's own lessons**: queue 50, ladder III, general skills
   enrolled anywhere, a support skill at V for T2, a second T2 bonus per level, Crew Drill, capped
   bonus training from sailing, and no injectors, attributes or skill points for coin (D1–D7).
3. **107 skills in 9 groups**. 15 new ones, all on rules that already exist (fees, routes, wages,
   storms, calms, hiring, influence, captains' experience, homesickness). Hull skills fall to 51 %.
4. **A captain** = a grade (C/B/A/S, a data ladder), a **job** (her first trait), a kit of 10 traits
   (she *knows* 4/6/8/10 and *uses* 2/3/4/5 at a time, the owner's pattern), three levels
   (Exploration / Trading / Combat, per signing), a home and languages.
5. **Cabins per ship** (the live 3–8): one **Captain's cabin**, which takes any trait at 100 %, and
   typed cabins, which take traits of their own focus at 100 % and the rest at 50 %.
6. **Scope is Origin's**: combat traits add to **the ship they sit on**. Trade and exploration traits
   add to **the whole fleet**, so a trader can sit anywhere.
7. **One reader, `public.crew_pct(fleet, ship, effect, good)`**, replaces `fleet_officer_bonus`
   in all six of its callers. With `crew_bite` off it is today's arithmetic, to the digit.
8. **Every trait effect lands in a rule that already exists**: speed (`voyage.fleet_speed`), cargo
   space (`ship_hold_capacity`), spread (`world.spread_effective`), raid losses (`raid_crew_lost`),
   supplies (`voyage.endurance_days`), storm damage (`voyage.settle`'s STORM arm) and bargain odds
   (`haggle_odds`). Combat traits go to `world.ship_stats`, dark until S4.
9. **Promotion** C→B→A→S: a level in her focus, plus 10 / 20 / 40 generic items of her focus, earned
   by your fleets (O4, D12). It adds slots and known traits.
10. **Homesick**: 72 real hours away from her home region costs her 20 %. The surgeon heals it (O6,
    D13). Languages raise bargain odds and never refuse anything (D14).
11. **Hired at the inn as today** (0073 / 0119: derived, never rolled, no gacha). Merchant captains
    stay fixed: they keep their job, sit at full value, never level and are never homesick.
12. **Twelve slices, K0–K10 plus K2b**, each one dark or byte-parity, with three switches: `skills_bite` and
    `levels_bite` (live, both off) and a new `crew_bite`. **K0 makes lit skills cheap for merchants
    before anything is lit.**

---

## 1. The game today (prod, read-only, 2026-10-17)

| Fact | Where |
|---|---|
| Prod head **0140**. `skills_bite` **false**, `levels_bite` **false**, `skill_queue_max` 10, `skill_sp_per_hour` 1,800, `skill_study_base_cost` 500, `officer_bonus_cap_pct` 25, `captain_level_pct_per_level` 2, `inn_captain_rotate_minutes` 15 | `world_config` |
| **92 skills** in 8 groups: HULLS 55, ROLES 9, GUNNERY 7, NAVIGATION 6, SEAMANSHIP 5, TRADE 4, SHIPWRIGHT 4, COMMAND 2. Rank sum 389. Enrolment: 55 at a line's yard, 33 at an academy, 4 none | `skill_profile` (0131), `data/skills.json` |
| 160 `skill_effects` rows. 256 `skill_requirements` (158 hull, 98 item; 44 of them at level IV). 22 prerequisites at IV: every Heavy ← Medium IV and every Capital ← Heavy IV | 0133, 0135, 0138 |
| Humans: 17 houses, 20 ships, 17 fleets. **1** `player_skills` row (NAVIGATION I). **0** `skill_queue`, **0** `skill_sp`. **1** signed officer, not posted | prod |
| Merchants: 821 houses, 892 ships, 837 fleets, 1,425 skill rows (ACCOUNTING ≤ III, HAGGLING ≤ II, NAVIGATION ≤ III, SEAMANSHIP ≤ III), **511** signed officers posted to **498** fleets: 488 with one, 7 with two, 3 with three. At most 2 exploration-type and 1 trade-type officers in a fleet. No fleet has more officers than seats | prod |
| **63 officers** (NAVIGATOR 17, PURSER 16, QUARTERMASTER 15, SURGEON 15). `bonus_pct` 4–9 (avg 6.4), `wage_ducats` 550–1,600, 19 nations plus 7 with none. Columns: code, name, specialty, bonus_pct, wage_ducats, nation_id, home_port_id, blurb | `public.officers` 0015:56, roster 0073 |
| A signing = `player_officers (id, player_id, officer_id, fleet_id, hired_at)`, unique per (house, officer). Posted to a **fleet**, never to a ship | 0015:76 |
| **The one reading of officers**: `public.fleet_officer_bonus(fleet, specialty)` = least(Σ bonus_pct × `captain_level_mult`, 25) / 100, × (1 + Command %) under the cap when lit. Called by `voyage.fleet_speed`, `public.ship_hold_capacity`, `public.raid_crew_lost`, `world.spread_effective`, `world.fleets()` and `voyage.settle` | prod `pg_get_functiondef`; 0015, 0017, 0027, 0127, 0133 |
| Company skill effects, through `public.player_skill_bonus`: SEAMANSHIP → `voyage.endurance_days`; NAVIGATION → `voyage.fleet_speed` (multiplied with navigators, 0027); ACCOUNTING → `world.daily_cap_remaining`; HAGGLING → `public.haggle_odds` | 0016, 0027 |
| **Cabins**: `class_cabins` for all 70 classes: 3 / 4 / 5 / 6 / 7 / 8 by size 1–6. No rule reads them; the ship view shows the count ("captain ranks and cabins are their own slice") | 0074:111, 0135, 0138 |
| Captain experience per signing, `officer_xp (player_officer_id, xp, aboard_since)`: 0 rows. Credited by `voyage.settle`'s arrival arm to officers aboard since departure. Merchants have no row | 0127 |
| Inn: `world.inn_present(officer, port, shift)`, derived from the world secret and weighted by nation 0.40 / region 0.22 / culture 0.12 / abroad 0.04 × `officer_scarcity(bonus_pct)` | 0073, 0119 |
| Ports carry `region_id` and `culture` (14 values: latin 82, islamic 28, indic 21, malay 16, anglo 14, germanic 14, open-sea 14, guinean 13, japanese 11, swahili 9, nordic 8, korean 8, sinic 8, oceanic 6). 23 nations | prod |
| Goods: 555, in the owner's 17 categories (row 70): grain, food, drink, tobacco, spice, medicine, dye, cloth, metal, gems, crafts, weapons, guns, ship-supplies, art, books, animals | `data/goods.json` |
| Arrivals sweep: every 15 s on a 10 s budget. After 0136: avg 2.4 s, max 4.1 s. **Lighting `skills_bite` costs about 2 × the merchant ship reads** (speed + cargo space 345 → 622 ms, ship_view 1,388 → 2,414 ms on the cached world) | RESUME 2026-10-17, DEV_LOG 0133 |
| Storm damage: `voyage.settle`, STORM arm: hull lost = maxd × (0.08 + 0.17 × magnitude), plus 36 h delay. CALM: delay (1 + 3 × magnitude) × 24 h. Hazards are a pure function of (voyage, day, secret) | settle (0027 onward), `voyage.hazard_roll` |
| Haggling: `cmd.haggle(p_fleet, p_good, p_side)` → `public.haggle_odds(player, port, good)` (base + HAGGLING, hardened by today's failures) | 0022:430 |
| Costs computed inside a door: crew hiring (`cmd.do_hire`'s `v_cost`), yard labour (`cmd.do_build`), a captain's wage (`sign_officer` charges `wage_ducats`). The daily crew wage is `public.crew_wages(count, short)`, which `voyage.settle` charges and `world.crew_cost` serves | 0086, 0122, 0015 |

---

## 2. The concepts and their one home

| Concept | Its ONE home | What happens to today's copy |
|---|---|---|
| what **the company** knows | `skills` + `player_skills` + `skill_queue` + `skill_sp`, read only through `public.skill_level(_at)` (LIVE, 0131) | — |
| what a **skill level** gives | `skill_effects`, read by `world.skill_pct` / `player_skill_bonus` (LIVE, 0133), plus new stat codes for the new readers (§3.3) | — |
| a **captain** (who she is) | `public.officers` (LIVE), plus side tables `captain_profile (officer, grade, job_trait)`, `captain_traits (officer, ord, trait, base_pct)` and `captain_languages (officer, language)` | `officers.specialty` / `bonus_pct` become **mirrors** of trait ord 1 (asserted equal) and are retired in K9, the 0074 → 0077 lesson |
| a **signing** (your copy of her) | `player_officers` (LIVE): its `id` stays the per-signing key (O8) | `fleet_id` is retired in K9 (where she sits is the seat) |
| a signing's **grade, active traits, home clock** | `captain_state (signing, grade, home_seen_at)`, `captain_active (signing, trait)` | — |
| **where she sits** | `captain_seats (signing PK, ship_id, seat)`, written only by `public.seat_captain_for` | `player_officers.fleet_id` and `post_officer_to` (re-cut onto the seat core in K5, deleted in K9) |
| a ship's **cabins** | `cabin_layout (class_code, seat, focus)`, generated from `class_cabins` (LIVE count) and the hull's role (D9) | — |
| what a **trait** does | `traits (code, focus, category)` + `trait_effects (trait, effect, mult)` + `crew_effects (effect, scope, cap_pct, reader)` | `officers.specialty`'s four-value CHECK |
| **what the captains give** a fleet or a ship | **`public.crew_pct(p_fleet, p_ship, p_effect, p_good)`**, one function | `public.fleet_officer_bonus` (dropped in K5 once its six callers are re-cut) |
| a captain's **levels** | `captain_xp (signing, exploration, trading, combat)` → `level_from_points`, capped (D11) | `officer_xp` (one number; migrated in K6, dropped in K9) |
| **promotion items** | `item_kinds` rows of kind `promotion` in `player_items (player, port, item, qty)`: one item system, storage per port (LIVE, 0068 / 0070) | — |
| a **port's language** | `port_language (port, language)`, authored by `world-derive.mjs`, held by the world guard | — |

**Why this is not two systems doing one job.** The company's Skills say what *you* may build and fit,
and how your hulls perform (slow, real time, never lost). Captains say *who* is aboard (hired, seated,
promoted; lost when dismissed, O8). A rule that both touch, such as speed, reads both **sources**
through their one function each and multiplies them. That is already how `voyage.fleet_speed` composes
NAVIGATION with navigators (0027). No source ever writes into the other.

---

## 3. Company skills v2 (EVE, OWNER O1)

### 3.1 What stays exactly as it is (LIVE)

The SP curve (250 / 1,414 / 8,000 / 45,255 / 256,000 × rank, matching EVE [EVE §0.1]), 1,800 SP an hour
for everybody, offline training with no cron (`skill_level_at` is a pure function of time), enrolment
as the coin cost, SP kept when an entry is removed, no pausing, prerequisites (with 0131's OR groups),
`skill_effects` / `skill_requirements` / `requirements_met`, `E_NEEDS_SKILL` sentences, merchants with
fixed skills and no queue, and `skills_bite` as the switch.

### 3.2 The fixes (D1–D4, D6, D7)

| Fix | Exactly what changes | Rule |
|---|---|---|
| Queue 50 | `skill_queue_max` 10 → 50 (one UPDATE, K1) | D1 |
| Ladder III | 22 `skill_prereqs` rows: `X_HEAVY ← X_MEDIUM` and `X_CAPITAL ← X_HEAVY` level 4 → 3. In `skill_requirements`, the hull rows that ask Medium IV (heavy T1) or Heavy IV (capital T1) → III. Item rows at IV (G4 gear) are untouched. | D2 |
| Enrol anywhere | `skill_profile.enrol_where` gains `anywhere`. The 33 `academy` rows and the 15 new skills use it. `public.skill_taught_at` (the one place rule) answers null for `anywhere`. `line_yard` is unchanged. | D3 |
| T2 support at V | 4 `skill_prereqs` rows: ARMED_MERCHANT ← CARGO_STOWAGE V, PRIVATEERS ← GUN_LAYING V, SURVEY_SHIPS ← LOOKOUTS V, CONVOY_ESCORTS ← HULL_UPKEEP V | D4 |
| T2 second bonus | 4 `skill_effects` rows (scope ship, tech T2, that role): Armed Merchantmen **+2 % hull**, Privateers **+2 % reach**, Survey Ships **+1 % speed**, Convoy Escorts **+2 % armour**, per level, beside each one's live +4 % | D4 |
| Bonus training | Knobs `skill_sp_per_arrival` 1,000, `skill_sp_arrival_min_nm` 300, `skill_sp_day_cap` 10,000. **One** writer: `voyage.settle`'s arrival arm (beside 0127's experience hunk) calls `public.skill_sp_grant_for(player, sp)`, which banks into the head entry's `skill_sp` and rebuilds the chain through `skill_queue_set_for`'s own chain step, so the queue still has one writer. A day's total is kept in `skill_sp_grants (player, day, sp)`. With nothing in training, nothing is credited, and the arrival's report says so (*"No skill in training: the sailing bonus waits for one."*). Merchants have no queue, so the core returns at once. | D6 |
| Never | No injector, extractor, attribute, remap, or skill points for coin. Stated here as a rule; K1's spec greps the skill catalogue and the RPC registry for `inject`, `extract` and `remap` | D7 |

**Not adopted, said plainly.** Command asked along the hull ladder [EVE recommendation 7] and gun size
tiers [EVE §2.6] are not asked for and not needed: hulls are the grind (`SHIPS_AND_SKILLS.md` §4.4).

### 3.3 The catalogue: 92 → 107 (D5)

Every new skill is one `skills` row, one `skill_profile` row (`enrol_where = anywhere`), its
prerequisites and its effect rows in `data/skills.json`. Every effect has an existing reader. Rows
marked *data* need no code: their reader already sums `skill_effects` for that stat.

| Group | Skill | Rank | Needs | Per level | The one reader | Slice |
|---|---|---|---|---|---|---|
| Trade | **Wholesale** | 4 | Factorage III | +3 % daily trade limit (company `TRADE_CAP`) | `world.daily_cap_remaining` via `player_skill_bonus` | K1 *data* |
| Trade | **Negotiation** | 3 | HAGGLING III | +2 % bargain odds (company `SPREAD`) | `public.haggle_odds` via `player_skill_bonus` | K1 *data* |
| Trade | **Factorage** | 3 | ACCOUNTING III | +1 standing route | the route-cap trigger `public.standing_routes_cap()` (knows `new.player_id`) | K2 |
| Trade | **Pursership** | 2 | ACCOUNTING I | −3 % crew wages | the fleet's daily wage, `public.fleet_wage(fleet, short)` (lifted) | K2 |
| Trade | **Brokerage** | 2 | ACCOUNTING II | −5 % of the profit tax | `world.tax_rate(port, player)`, **after INFLUENCE I5** gives it the player | K2b |
| Seamanship | **Crew Drill** | 2 | SEAMANSHIP II | +3 % Hands (fitting `hands`) | `world.ship_budget` | K1 (one hunk) |
| Seamanship | **Provisioning** | 2 | SEAMANSHIP II | +3 % supplies last (company `ENDURANCE`) | `voyage.endurance_days` via `player_skill_bonus` | K1 *data* |
| Navigation | **Celestial Navigation** | 5 | NAVIGATION V | +1 % speed (company `SPEED`) | `voyage.fleet_speed` via `player_skill_bonus` | K1 *data* |
| Navigation | **Weather Lore** | 3 | NAVIGATION III | −4 % storm hull damage | `voyage.settle` STORM arm, level read at the voyage's departure (`skill_level_at`), so a settlement never depends on when it runs | K2 |
| Navigation | **Light-air Sailing** | 2 | NAVIGATION II | −5 % calm delay | `voyage.settle` CALM arm, at departure as above | K2 |
| Social | **Recruiting** | 1 | — | −5 % captain hiring wage | `public.captain_wage(player, officer)` (lifted) | K2 |
| Social | **Etiquette** | 2 | Recruiting II | −4 % crew hiring cost | `public.crew_hire_cost(fleet, n)` (lifted) | K2 |
| Social | **Patronage** | 3 | Etiquette III | +4 % influence for the coin you give | `influence_post` (**after INFLUENCE I2**) | K2b |
| Command | **Leadership** | 2 | COMMAND I | +5 % captains' experience | the captain-experience credit (K6) | K6 |
| Command | **Hospitality** | 2 | COMMAND I | homesickness −2 points | `public.crew_pct`'s homesick term (K6) | K6 |

**Effects given to skills that already exist** (planned in `SHIPS_AND_SKILLS.md` §5.2, not given by
0133): **Shipwright** −3 % yard labour (`public.yard_labour(player, class)`, lifted, K2). Fleet Command,
Refitting and Augmentation stay as gates for flagships, refits and perks (S13 / S16).

**"Lifted" means one authority first.** Four of these costs are computed inline in a door today and
printed by a screen from elsewhere. If the skill term went into the door, the screen would print a
number the game does not charge. So K2 first lifts each into one function that **both** the door and
the screen read, proves it gives today's figure, and only then adds the term:
`public.fleet_wage(fleet, short)` (read by `voyage.settle` and `world.crew_cost`, composing
`crew_wages`), `public.crew_hire_cost(fleet, n)` (`cmd.do_hire` and the Inn's hire step),
`public.captain_wage(player, officer)` (`sign_officer` and `world.inn`), and
`public.yard_labour(player, class)` (`cmd.do_build` and `world.building_yard`). The K2 slice reads the
four live bodies first and names every caller it finds.

**Totals.** HULLS 55, ROLES 9, NAVIGATION 9, TRADE 9, SEAMANSHIP 7, GUNNERY 7, COMMAND 4, SHIPWRIGHT 4,
SOCIAL 3 = **107**. Hull skills make up **51 %** (60 % today; EVE 18 % [EVE §4]). Rank sum 389 + 38 =
**427**, which is 109 M SP: **6.9 years** to train everything at 1,800 SP/h, or about 5.6 years with
the daily sailing bonus. EVE takes about 41 years [EVE §0.3].

---

## 4. Captains v2 (Origin, OWNER O2)

### 4.1 What a captain is

| Part | Rule | Tag |
|---|---|---|
| **Grade** | C / B / A / S, from `captain_grades (code, ord, slots, known, floor_pct)`: **C 2 / 4 · B 3 / 6 · A 4 / 8 · S 5 / 10** (trait slots / traits known). Floors are 4 / 5.5 / 7 / 8.5 %. A grade above S costs one row (*"for now"*). SS exists in Origin [UWO §3.8], but is not seeded: the owner said S is the best for now | O3; floors D12 |
| **Job** | Her first trait (`captain_profile.job_trait` = `captain_traits` ord 1). It names her role: exploration, trading or combat | O5, O6 |
| **Kit** | 10 ordered traits. She *knows* the first `known` of them and *uses* up to `slots` of the known ones (`captain_active`), chosen by you while her ship is in port. A new hire uses her first ones | O3; D15 |
| **Three levels** | Exploration, Trading and Combat, **per signing** (a new signing starts at 1) | O2, O8; sources D11 |
| **Home** | `officers.home_port_id` (LIVE; every one of the 63 has one) → its region, for homesickness | O6; D13 |
| **Languages** | Her home's language, plus authored ones | O2; set D14 |
| **Wage** | `officers.wage_ducats` (LIVE), paid once at hiring | LIVE |

### 4.2 Traits (the catalogue)

`focus` decides the cabin rate (§4.3). `scope` says where the value adds up: **fleet** = every seated
captain in the fleet, **ship** = only the ship she sits on (Origin: combat expertise per ship, trade
and adventure per fleet [UWO §3.4], O2). `cap` is the most a fleet (or ship) can gain from that effect.

| Trait (job word) | Focus | Effect → scope | The one reader | Cap | Today | Tag |
|---|---|---|---|---|---|---|
| **Navigator** | Exploration | `speed` → fleet | `voyage.fleet_speed` | 25 % | LIVE (NAVIGATOR) | O6 |
| **Pilot** (*kinder weather*) | Exploration | `storm` → fleet: storm hull damage × (1 − v) | `voyage.settle` STORM arm | 25 % | new | O6 |
| **Surgeon** | Exploration | `crew_saved` → fleet, **and** `homesick_relief` → fleet | `public.raid_crew_lost`, and `crew_pct`'s homesick term | 25 % / 20 | LIVE + new | O6 |
| **Provisioner** | Exploration | `supplies` → fleet: supplies last × (1 + v) | `voyage.endurance_days` | 25 % | new | D15 |
| **Quartermaster** | Trading | `hold` → fleet (each hull's cargo space) | `public.ship_hold_capacity` | 25 % | LIVE | O6 |
| **Purser** | Trading | `spread` → fleet | `world.spread_effective` | 25 % | LIVE | O6 |
| **⟨Category⟩ trader** ×17: Grain, Food, Drink, Tobacco, Spice, Medicine, Dye, Cloth, Metal, Gem, Crafts, Weapons, Guns, Ship-supplies, Art, Book, Animal trader | Trading | `category_spread` → fleet, only on goods of that category | `world.spread_effective` (it already takes the good) | 20 % a category | new | O5 (jewellery → Gem, meat → Food); cap from Origin [UWO §4.4] |
| **Gunner** (*long range*) | Combat | `accuracy`, `reach` → ship | `world.ship_stats` | 25 % | **dark until S4** | O5 |
| **Boarder** (*close*) | Combat | `attack` → ship | `world.ship_stats` | 25 % | **dark until S4** | O5 |

25 traits. A trait can carry two effects (`trait_effects`, like `skill_effects`), as the surgeon does.
**O5's "one captain for each role"**: every one of the 25 jobs has at least two captains in the roster
(D15).

### 4.3 Cabins, seats and the Captain's cabin (O7, O2, D9)

- Every ship has `class_cabins.cabins` seats (LIVE: 3 on a small hull, then one more per size, up to
  8: the owner's *"3 captain slot … grows as the tier grows"*).
- **Seat 1 is the Captain's cabin**: every trait works there at **100 %**.
- **The other seats are typed** Trade / Exploration / Combat. A trait of the cabin's focus works at
  **100 %**, any other at **50 %** (Origin's official figure [UWO §3.5]). The order rotates from the
  hull's role: trade → T, E, C, T, …; explorer and support → E, T, C, E, …; combat → C, T, E, C, ….
  It is generated into `cabin_layout` by `scripts/build-ships.mjs` (D9).
- Captains are seated, moved, put ashore and have their traits changed **only while that ship is in
  port**. So whoever sails from a port is the same crew that arrives, and settlement reads a fixed set
  (0127's "aboard since departure" rule becomes structural).
- **No ship needs a captain.** An empty Captain's cabin gives nothing and refuses nothing (Origin
  removed its captain gate on hulls [UWO §3.6], and we never add one).
- A ship that is lost puts her captains ashore. The seat row goes; the signing stays.

### 4.4 The one reader: `public.crew_pct(p_fleet, p_ship, p_effect, p_good)`

For one effect, add up every **active** trait of every captain seated in the scope (the fleet's ships
for a fleet effect, `p_ship` for a ship effect):

```
value = greatest(trait.base_pct, grade.floor_pct)        -- D12: a promotion lifts it to the new floor
      × trait_effect.mult                                -- 1, or the surgeon's second effect
      × captain_level_mult(signing, trait.focus)         -- LIVE 0127: 1 + 2 % × (level − 1), 1 while levels are dark
      × cabin_rate(seat, trait.focus)                    -- 1 or 0.5
      × homesick_factor(signing, fleet)                  -- 1, or 0.8 eased by care (D13)
sum   = least(Σ value, crew_effects.cap_pct)             -- per category for category_spread
result = least(skill_scale(sum, Command %), cap) / 100   -- LIVE 0133: Command lifts it, still under the cap
```

- **Dark (`crew_bite` false)**: only trait ord 1 counts, at rate 1, factor 1 and no floor, and only the
  four live effects exist. That is `fleet_officer_bonus` exactly: the same sum of `bonus_pct ×
  captain_level_mult`, the same cap, the same Command term (asserted for all 498 merchant fleets and
  every probe, K5).
- The function is PL/pgSQL. Its dark branch is today's query shape (seats → ships of the fleet), and
  its plan is cached. It reads no switch twice and calls nothing else while dark.
- `world.crew_bonuses(fleet)` is the display reading: every term by source (*"Ana de Sousa · Navigator
  · Captain's cabin · +7 % speed"*), the cap, and the homesick line. The client prints it and computes
  nothing.
- **Readers re-cut onto it in K5** (one hunk each, sliced from the LIVE body): `voyage.fleet_speed`
  (`speed`), `public.ship_hold_capacity` (`hold`), `public.raid_crew_lost` (`crew_saved`),
  `world.spread_effective` (`spread` + `category_spread` for `p_good`, in one query), `world.fleets()`
  (display) and `voyage.settle` (wherever it names the officer bonus). Readers added in K7:
  `voyage.endurance_days` (`supplies`), `voyage.settle`'s STORM arm (`storm`) and `public.haggle_odds`
  (language, §4.9). `fleet_officer_bonus` is then dropped, because it has no caller left.

### 4.5 Levels and experience (O8, D11)

- `captain_xp (signing, exploration, trading, combat)` holds points. Each track goes through LIVE
  `public.level_from_points` (cap 20).
- **Exploration**: her fleet's miles ÷ `ship_xp_nm_per_point` (LIVE 1,000), credited in `voyage.settle`'s
  arrival arm. That is 0127's hunk, split into three columns. **Combat**: 0127's fight points (EVADED 5,
  DRIVEN_OFF 15) in the same hunk. **Trading**: her fleet's purchases and sales, 100 🪙 = 1 point
  (0069's rate). It is credited in the buy and sell cores beside their ledger write, one hunk each.
- Each credit × her cabin's experience rate (100 % for its focus, 50 % for the others; the Captain's
  cabin 100 % for all), × (1 + Leadership %) once skills are lit.
- **Only signings with a `captain_xp` row earn**, and only player hires get one. Merchants' captains
  have none, so the credits touch zero rows for them, with no `is_npc` read (0127's method).
- **The level in force** = least(her level in that track, **your company's level in the same track**
  from LIVE `public.player_progress`). It is read only when her own level is above 1, so a level-1
  captain (every merchant) costs nothing.
- Shown always. It bites only while `levels_bite` is on (LIVE 0127).

### 4.6 Promotion (O3, O4, D12)

| Step | Her level in her job's focus | Items of her focus | Gains |
|---|---|---|---|
| C → B | ≥ 5 | 10 | 3 slots, 6 known, every trait ≥ 5.5 % |
| B → A | ≥ 10 | 20 | 4 slots, 8 known, ≥ 7 % |
| A → S | ≥ 15 | 40 | 5 slots, 10 known, ≥ 8.5 % |

- **Items** (O4: *"like for 건조소 but different items"*): three `item_kinds` rows, `trade-seal`,
  `sea-chart` and `battle-honour` (kind `promotion`, volume 0.01 t). They are the **same for every
  captain** (D12). They sit in `player_items` at a port, like every other item.
- **Earning**: `voyage.settle`'s arrival arm, players only, in the same hunk as the experience: for
  every `promotion_item_points_<track>` points your fleet earned in a track on this passage (trading:
  its turnover since its previous arrival), one item of that track goes into storage **at the arrival
  port**. Exploration and combat: 100 points (a Sea Chart ≈ 100,000 nm). Trading: measured in K8 from
  the players' own ledgers (the S12 receipt method), so that a seal takes about as long as a chart,
  because 100 🪙 = 1 point comes far faster than 1,000 nm = 1 point.
- **The pace** (LIVE curve: level L at 25 × (L − 1)² points; 0127 puts level 10 at about a month of
  round-the-clock sailing): one captain is eligible for B after about a week, for A after about a
  month and for S after about two and a half months. Her items come from all your fleets. That is the
  long grind (O8).
- **The verb** `cmd.promote_captain(signing)`, with core `public.promote_captain_for`: her ship is in
  port, the items are in storage at that port, and the level gate is met. It spends the items and
  raises `captain_state.grade`. A refusal names the figures (*"Needs 10 Sea Charts here: you have 6 at
  Lisbon"*). Combat captains promote with Battle Honours, which come from pirates seen off.
- Per signing (O8): a dismissed captain loses her grade, as she loses her levels.

### 4.7 Homesickness (O6, D13)

- `captain_state.home_seen_at` is set at hiring. It is set again **only** by `voyage.settle`'s arrival
  arm when her fleet arrives at a port of her home region (players only, the same hunk).
- **Homesick** = `now − home_seen_at > homesick_after_hours` (72). This is derived at read time from
  one timestamp of a real event, so it cannot be farmed.
- Her factor in `crew_pct` = 1 − max(0, `homesick_penalty_pct` 20 − fleet care − 2 × Hospitality) /
  100. Fleet care is the sum of the fleet's `homesick_relief` (Surgeon), capped at 20. *A 7 % surgeon
  turns −20 % into −13 %; a full bench turns it into nothing.*
- **Merchants**: no `captain_state` row, so the factor is 1. This follows O8 (their captains are
  fixed), and it is stated, not a silent fallback (NO_SPAGHETTI §7C).
- `world.captains` and the fleet sheet say it in words: *"Homesick: 4 days from Iberia · −13 %
  (Surgeon Ana de Sousa)"*.

### 4.8 Hiring and the inn (O9, LIVE)

Unchanged: who is in the inn is derived from (officer, port, shift, secret), weighted toward her own
country and rarer the better she is, and the room turns over every 15 minutes. Hiring needs her to be
in the room and pays `wage_ducats` once. There is **no gacha**, because Origin removed its own [UWO §0.12].
What is new: the inn card shows her grade, job, known traits and languages. Hiring gives her a
`captain_state` row (grade = her birth grade, home clock = now) and makes her first traits active.
She starts ashore, or goes straight into a seat on a ship in that port if you name one.

### 4.9 Languages (O2, D14)

**20 languages**: Portuguese, Spanish, French, Italian, English, Dutch, German, Nordic, Slavic, Turkish,
Arabic, Persian, Indic, Malay, Thai, Chinese, Japanese, Korean, Swahili, Guinean. A harbour's language
is authored by `world-derive.mjs`: its founding nation's language if it has one, otherwise its
culture's (latin harbours by country). It is stored in `port_language` and held by the world guard. It
is **not** the flag, so a city won through INFLUENCE keeps its language. Open-sea points have none.

- A captain speaks her home's language. Generated A and S captains speak 1–2 more (Origin's new S mates
  arrive with two [UWO §4.6]).
- **The one effect**: `public.haggle_odds` gains `p_fleet` (default null, which gives today's answer,
  the 0139 drop-and-create method). If a captain seated in that fleet speaks the port's language, add
  `language_haggle_points` 5 to the odds. Merchants never haggle, so no merchant read changes.
- **Never a gate**: a port without your language offers everything it offers today.

### 4.10 Merchants (O8)

Merchant captains are the same tables. They are **seated** by `npc_found` through `seat_captain_for`
(K5; from S18 on, for new lines), and each uses **only her job trait** (written once). They have no
`captain_xp` or `captain_state` row, so they never level, promote or get homesick. Their numbers are
today's numbers.

### 4.11 Combat (dark, O5)

Gunner and Boarder are in kits now. Their `ship` effects are read by `world.ship_stats`'s **lit**
branch only when S4's combat switch is on (`SHIPS_AND_GEAR` S4). Until then the trait card says
*"works when combat arrives"*. Origin's combat actives [UWO §4.3] become, with S4, trait effects with
`trigger = PIRATES` read by `voyage.settle`'s PIRATES arm (the escort score), the same shape as gear
actives (`SHIPS_AND_SKILLS` §6.1). There is no visual combat, ever (`DESIGN.md`).

---

## 5. Every effect and its one reader

| Effect | Source(s) | The ONE reader | Lands | Dark switch |
|---|---|---|---|---|
| fleet speed | NAVIGATION, Celestial Navigation (company); Navigator (crew) | `voyage.fleet_speed` (frozen into the voyage at departure) | LIVE / K1 / K5 | skills_bite / crew_bite |
| cargo space | Cargo Stowage, role and line skills (ship); Quartermaster (crew) | `world.ship_stats` → `public.ship_hold_capacity` | LIVE / K5 | both |
| spread | Purser, ⟨Category⟩ traders (crew) | `world.spread_effective` | LIVE / K5 / K7 | crew_bite |
| bargain odds | HAGGLING, Negotiation (company); language (crew) | `public.haggle_odds` | LIVE / K1 / K7 | both |
| daily trade limit | ACCOUNTING, Wholesale | `world.daily_cap_remaining` | LIVE / K1 | skills_bite |
| supplies | SEAMANSHIP, Provisioning (company); Provisioner (crew) | `voyage.endurance_days` | LIVE / K1 / K7 | both |
| raid crew losses | Surgeon (crew) | `public.raid_crew_lost` | LIVE / K5 | — / crew_bite |
| storm hull damage | Weather Lore (company); Pilot (crew) | `voyage.settle` STORM arm | K2 / K7 | both |
| calm delay | Light-air Sailing | `voyage.settle` CALM arm | K2 | skills_bite |
| Deck / Hands | Deck Management, Gun Drill (LIVE); Crew Drill | `world.ship_budget` | LIVE / K1 | skills_bite |
| standing routes | Factorage | `public.standing_routes_cap()` | K2 | skills_bite |
| daily crew wage | Pursership | `public.fleet_wage` (lifted) | K2 | skills_bite |
| profit tax | Brokerage | `world.tax_rate` | K2b (after I5) | skills_bite |
| captain hiring wage | Recruiting | `public.captain_wage` (lifted) | K2 | skills_bite |
| crew hiring cost | Etiquette | `public.crew_hire_cost` (lifted) | K2 | skills_bite |
| influence | Patronage | `influence_post` | K2b (after I2) | skills_bite |
| yard labour | Shipwright | `public.yard_labour` (lifted) | K2 | skills_bite |
| captains' bonuses | Command (LIVE) | inside `public.crew_pct` | K5 | skills_bite |
| captains' experience | Leadership | the K6 experience credit | K6 | skills_bite |
| homesickness | Surgeon (crew); Hospitality | inside `public.crew_pct` | K6 | crew_bite |
| hulls kept | Command (LIVE) | `public.house_ship_max` | LIVE | skills_bite |
| attack / accuracy / reach | gunnery skills (LIVE); Gunner, Boarder (crew) | `world.ship_stats` | LIVE / S4 | skills_bite / S4's switch |

No effect has two readers, and no reader computes a source's sum itself. The client computes none of
these. It prints `world.skill_bonuses`, `world.crew_bonuses`, `world.captains` and `world.ship_view`.

---

## 6. From today's live data, without anyone losing progress

### 6.1 The company's skills

| Live | After | How | Proof |
|---|---|---|---|
| 92 skills, every `skills.id` | the same rows + 15 | **No skill is renamed, merged or deleted.** Only added | catalogue = pre-image ∪ new (row hashes) |
| `player_skills` (1 human, 1,425 merchant) | unchanged | nothing | every house's level in every skill = pre-image |
| `skill_queue`, `skill_sp` (0 rows; any written before K1 lands) | kept | queue max only grows (10 → 50); an entry already queued keeps its `finishes_at`. The ladder change only loosens a prerequisite, so no queued entry becomes illegal | every row's finish = pre-image; `skill_queue_refusal` over every house's queue = null |
| enrolments (`skill_sp` rows) | kept | `academy` → `anywhere` only widens where | every enrolment row = pre-image |
| prereqs at IV, hull requirements at IV | III | data UPDATE (D2) | every hull a probe house could build before, it can build after (a superset) |

### 6.2 Captains

| Live | After | How | Proof |
|---|---|---|---|
| 63 `officers` | + `captain_profile` (grade by D10's bands, job = specialty), `captain_traits` (ord 1 = specialty at `bonus_pct`; ords 2–10 from the generator), `captain_languages` | K4 | `specialty` / `bonus_pct` = ord 1 for every officer (mirror); `world.inn` for 50 sampled (port, shift) = pre-image (the scarcity still reads `bonus_pct`) |
| 511 merchant signings posted to 498 fleets | a seat each | **K5 seats them greedily**: per fleet, flagship first, each officer into a free typed seat of her focus, else the Captain's cabin, else the next ship. Measured today: a fleet holds at most 2 exploration-type and 1 trade-type officers, and merchants sail only the three Lisbon hulls, whose first three seats are Captain + Trade + Exploration (barca, nau) or Captain + Exploration + Trade (caravela latina). So **every officer gets a seat at 100 %** | for every fleet and each of the four effects, `crew_pct` = the old `fleet_officer_bonus`, dark **and lit** (rate 1, ord 1, no state row); a fleet that cannot be seated at 100 % fails the migration (expected 0) |
| 1 human signing, not posted | ashore, with a `captain_state` (her birth grade, home clock = the migration time) and `captain_xp` (0) | K5 / K6 | — |
| `officer_xp` (0 rows) | `captain_xp.exploration` = old `xp` | K6: miles were the bulk of `voyage_xp`, and 0127 never kept fights apart, so all of it goes to exploration. Stated | Σ = old Σ; every level in force = pre-image while `levels_bite` is off |
| `player_officers.fleet_id` | derived (seat → ship → fleet) | written by `post_officer_to` until K5 re-cuts it onto the seat core; dropped in K9 once no body reads it | `pg_proc` scan: no body names `fleet_id` of `player_officers` (K9) |
| `cmd.post_officer(code, fleet)` | kept as a door (seats her in the fleet's first fitting seat) until the client stops calling it | K5 re-cut; K9 delete | entry points −1 in K9 |

A player's captain is never lost or downgraded by any slice. Grades only rise by promotion; levels only
rise.

---

## 7. Performance

**The budget**: the arrivals sweep runs every 15 s on a 10 s budget (avg 2.4 s, max 4.1 s after 0136).
Merchants are 892 of 912 ships, so **every hot read must cost a merchant nothing new**.

1. **K0, before anything is lit: lit skills must be cheap for merchants.** Today, lighting
   `skills_bite` doubles the merchant ship reads (§1), because `world.skill_pct` works through the
   whole skill catalogue for a house whose skills cannot touch a ship. K0 adds
   `public.house_skill_scopes(player)`: the set of scopes for which the house holds a level above 0,
   from `player_skills` ∪ queue rows. It is one indexed probe. `world.skill_pct` and `skill_bonuses`
   return 0 at once for a scope the house lacks. Merchants hold only the four company skills, so their
   ship reads leave at that probe. **K0's bound**: merchant speed + cargo space and `ship_view` lit ≤
   dark × 1.15 + 50 ms. It is printed in the receipt and asserted in CI's real Postgres 17 chain
   (0133's gate, now on the lit side). On prod, timing is a `raise notice`, never a raise, because the
   CPU is burstable (RESUME lesson).
2. **`crew_pct` dark** is today's query shape: two indexed lookups (seats of the fleet's 1–2 ships,
   then traits) in a PL/pgSQL wrapper with a cached plan (0133's lesson: PG 17 re-plans SQL bodies).
   **Lit**, for a merchant: ord 1 only, rate 1, no xp row (the level is 1, so no `player_progress` read)
   and no state row (factor 1). That is the same row count as dark, plus one lookup into
   `cabin_layout`. `category_spread` is a conditional sum inside the same query, so it is not a second
   call.
3. **Writes at arrival are players only**: experience, items, the home clock and bonus training touch
   only rows that exist for player hires and player queues. That is 17 houses today, and zero rows for
   merchants.
4. **Language never runs in a merchant path**: it lives in `haggle_odds`, and merchants do not haggle.
   Homesickness never reads a voyage: it compares one timestamp.
5. **Every K slice times** merchant speed + cargo space, `ship_view`, and 200 sampled
   `spread_effective` quotes, dark and lit, taking the faster of two passes (0133's method), at
   `random_page_cost` 1.1 (RESUME: PGlite plans at 4).
6. **Before any switch is thrown**: read 24 h of `cron.job_run_details` for the arrivals job on prod.
   Throw it only if the arrivals p95 is under 5 s and the max under 8 s, then watch the next 24 h.
   Rollback is one UPDATE.

---

## 8. The slices

Every slice follows the live-DB rules in `SHIPS_AND_SKILLS.md`'s header and `DEPLOY_RUNBOOK.md`:
hunks sliced from the LIVE body (LF-normalised), each occurring exactly once and reversing to its
pre-image, ACLs unchanged; self-asserts on throw-away houses (`new_house` / `npc_found`), never a live
fleet; own-row proofs, never whole-table digests (players write during a push); knobs through
`set_config` inside `do`; no `LOCK TABLE` / `set local` / `begin`; new state in side tables. Deploy is
unwind → `db push --linked` → wind → merge at once; then `npm run refresh` in `tools/projectmap`.

| # | What it changes | Proof (self-assert, rolled back) | Dark / rollback | Client (after the migration is LIVE) | CI (scoped) |
|---|---|---|---|---|---|
| **K0** · skills read cheaply | `public.house_skill_scopes`; early exits in `world.skill_pct`, `world.skill_bonuses`, `world.ship_stats` / `ship_budget` lit branches | dark and lit answers = pre-image for every hull (lit inside the assert); merchant lit ≤ dark × 1.15 + 50 ms printed; a probe house with PRT Medium Hulls III still reads +12 % sighting (control) | no switch moves; rollback re-cuts the exits out | none | names `world.skill_pct`, `world.skill_bonuses` → `db.chain`, `db.image`, ship-panel specs |
| **K1** · EVE fixes I (data + one hunk) | `skill_queue_max` 50; 22 prereqs and the heavy/capital hull requirement rows IV → III; `enrol_where = anywhere` + `skill_taught_at` hunk; 4 support-V prereqs; 4 T2 second-bonus rows; 15 new skills' rows (the 8 that need a K2 / K2b reader and the 2 that wait for K6 carry their effect rows, but nothing reads those stats yet); the SOCIAL group; `data/skills.json` + world guard; Crew Drill's `hands` stat in `world.ship_budget` (lit) | §6.1's table; a probe house enrols Gunnery at a port with no academy and is refused a line hull skill away from its yards; 50 queued levels accepted, 51 refused (`E_SKILL_QUEUE_FULL` with figures, LIVE 0131); every house's levels, bonuses and 0107 gates = pre-image; lit (rolled back): Crew Drill II → Hands × 1.06, Wholesale and Provisioning add to the same company sums | `skills_bite` (effects); the data changes are loosenings. Rollback: forward slice restoring the knobs and rows (no house can hold a level that only the new rows allow) | Skills screen: Social group; "Enrol here" in any port for general skills; Training `3 / 50 levels` | names `world.skills`, `skill_taught_at`, `world.ship_budget` → `skills.screen.spec` (new), ship-panel specs |
| **K2** · new readers for new skills | first the four lifts (§3.3: `fleet_wage`, `crew_hire_cost`, `captain_wage`, `yard_labour`, each proven equal to today's figure on probes), then hunks: `standing_routes_cap()` (Factorage), the four lifted functions (Pursership, Etiquette, Recruiting, Shipwright), `voyage.settle` STORM and CALM arms (Weather Lore, Light-air, levels at the voyage's departure) | dark: every body = pre-image on probes (a storm on a probe voyage loses exactly the old hull; same wage, cost, labour, route cap). Lit: Factorage II → 2 more routes; Weather Lore III → hull lost × 0.88; settlement is the same whenever it runs (two settles at different clocks agree) | `skills_bite` | Skill bonuses lines for the new stats (the server's words) | names `voyage.settle` (wide; the npc pool is selected, which is the long leg), `world.crew_cost`, `world.inn`, `world.building_yard` |
| **K2b** · after INFLUENCE I2 / I5 | `influence_post` (Patronage), `world.tax_rate(port, player)` (Brokerage) | as K2 | `skills_bite` | — | names `world.tax_rate` (wide) |
| **K3** · bonus training | `skill_sp_grants`; `public.skill_sp_grant_for` (composes the queue's chain step); arrival hunk; knobs (D6) | a probe arrival of 400 nm moves the head entry's finish earlier by exactly 1,000 SP ÷ 1,800 h; a 200 nm arrival credits nothing; the 11th grant in a day credits 0; empty queue → nothing, with the report line; a merchant arrival writes nothing (row counts) | `skill_sp_per_arrival` 0 = off | Training: *"+1,000 from sailing today · 3,000 / 10,000"*; a ledger/history line | names `voyage.settle` |
| **K4** · captains I: who they are | `captain_grades`, `traits`, `trait_effects`, `crew_effects`, `captain_profile`, `captain_traits`, `languages`, `port_language`, `captain_languages`; roster 63 → 105 (`scripts/build-captains.mjs` → `data/captains.json`); `officers.specialty` check re-made NOT VALID → VALIDATE to admit the 25 job codes; `world.inn`, `world.officers` serve grade, job, known traits and languages | §6.2 row 1; every new captain is placed in some inn within 24 h (derived, measured over the shifts); every job has ≥ 2 captains and every grade ≥ 1 per focus; the inn's average and fullest room printed (0073's receipt) | nothing reads traits beyond the mirror. Rollback: drop the new tables and roster rows (asserted: no signing references them) | Inn cards: grade badge, job, traits, *"Speaks Portuguese, Spanish"*; Codex Captains: Grade / Role / Job filters | names `world.inn`, `world.officers` → `port.inn.spec` (new), the Codex spec |
| **K5** · captains II: cabins, seats, the one reader | `cabin_layout` (generated); `captain_seats`, `captain_active`, `captain_state`; seed from `fleet_id` (§6.2); **`public.crew_pct`** + `world.crew_bonuses`; the six callers re-cut; `fleet_officer_bonus` dropped; `seat_captain_for` + `cmd.seat_captain(signing, ship, seat)` and `cmd.captain_traits_set(signing, traits)` (+2 entry points); `post_officer_to` and `npc_found` re-cut onto the seat core; `world.ship_view` + `cabins`; knob `crew_bite` false | for all 498 merchant fleets and the four effects, `crew_pct` = old bonus (dark and lit); every live hull: seats = `class_cabins`, seat 1 = Captain's cabin; a probe: seat at sea refused `E_NOT_IN_PORT`, an off-focus trait at 50 % lit, 100 % in the Captain's cabin, 6 active traits on a B refused; `pg_proc` scan: no body names `fleet_officer_bonus` | `crew_bite`. Rollback: forward slice restoring `fleet_officer_bonus` from the hunks file and re-cutting the six callers back | Ship panel **Cabins**: seat word, captain, `100 % / 50 %`, *Seat* / *Ashore* (in port only); fleet sheet **Crew bonuses**; Inn hire → "seat in …" | names `world.ship_view`, `world.fleets`, `cmdSeatCaptain` → `ship.cabins.spec` (new); `world.spread_effective` (wide) |
| **K6** · captains III: levels and homesickness | `captain_xp` (+ seed from `officer_xp`); the settle hunk split into three tracks with cabin rates; trade credit in the buy and sell cores; the level cap; `home_seen_at` + homesick factor; Leadership and Hospitality effects; `world.captains()` (registered) | Σ xp = old; a probe captain in a Trade cabin earns 100 % trading and 50 % miles; level capped at the company's track; homesick after 72 h, −20 %, a 7 % surgeon → −13 %, Hospitality II → −9 %, docking in her home region clears it; merchants: zero rows written | `levels_bite`, `crew_bite` | Captains roster (Cabin group): three level bars `7 / 20`, *"capped at your Trading level 7"*, homesick line | names `world.captains`, `voyage.settle` |
| **K7** · captains IV: new effects | readers: `voyage.endurance_days` (Provisioner), STORM arm (Pilot), `world.spread_effective` (category), `haggle_odds` gains `p_fleet` (language; drop + create, the 0139 method); `cmd.haggle` passes it | dark = pre-image on 200 sampled quotes and 50 haggles; lit on probes: a Gem trader narrows a gem's spread and leaves a grain's alone; the 20 % cap per category; language +5 points only where spoken | `crew_bite` | Crew bonuses lines; the haggle tray says *"Ana speaks Arabic here: +5 %"* | names `haggle_odds` (wide), `endurance_days` |
| **K8** · captains V: promotion | 3 promotion `item_kinds`; the earning hunk in settle (players only); `promote_captain_for` + `cmd.promote_captain` (+1) | a probe C with level 5 and 10 Sea Charts at the port becomes B: 3 slots, 6 known, traits ≥ 5.5 %; refused with 9 charts or at sea or at another port, with figures; one Sea Chart per 25 exploration points arrives in storage at the arrival port | `crew_bite` | Captain card: *Promote to B* with its needs; storage shows the items | names `cmd.promote_captain`, `voyage.settle` |
| **K9** · retire | drop `player_officers.fleet_id` (NOWAIT step, 0133 §7's lock order), `officer_xp`, `cmd.post_officer` (−1); `officers.specialty` / `bonus_pct` → read from ord 1 (`officer_scarcity` re-cut; inn pre-image asserted), then dropped | `pg_proc` scans: no reader of any dropped name; inn = pre-image | — | client stops calling `cmdPostOfficer`; `words.spec` bans *officer* in player text | wide (an altered table) |
| **K10** · combat traits (with S4) (**0168** provisional, built 2026-10-18 with S4, not deployed — `docs/dev-log/2026-10-18-s4-k10-combat-stats.md`. As built: `public.crew_pct` answers a ship effect for the captains on that ship while `combat_bite` is on; `public.ship_crew_terms` applies Gunner / Boarder last in `world.ship_stats`, both branches; no PIRATES-trigger trait effect exists to build — none is authored) | the `ship_stats` lit term for Gunner and Boarder; the PIRATES-trigger effects | lands in S4's own proof | S4's switch | "works when combat arrives" goes | with S4 |

**Lighting order**: K0 → `skills_bite` (after §7.6's check) → K6 → `levels_bite` → K5–K8 →
`crew_bite`. Each switch is one UPDATE.

New specs (each sets its own preconditions and uses the fixture it needs): `tests/skills.screen.spec.ts`,
`tests/port.inn.spec.ts`, `tests/ship.cabins.spec.ts`, `tests/captains.roster.spec.ts`. Each one names
its functions and catalogue keys (`worldSkills`, `worldInn`, `worldShipView`, `cmdSeatCaptain`,
`worldCaptains`, `cmdPromoteCaptain`), so CI rule S selects it (`docs/CI.md`). No slice edits an old
migration (that triggers rule F, the full suite). K1 and K4 edit `scripts/db/world-guard.mjs`, which is
selected by rule G.

---

## 9. What changes in `docs/SHIPS_AND_SKILLS.md`

| Part | Change |
|---|---|
| §0 line 5, §5.1 "Who trains" | Still the house. Captains do not train Skills; they have traits, grades and three levels (this file §4) |
| §2, "an officer's veterancy … KEPT unchanged" | **Replaced** by `captain_xp`'s three tracks (K6) |
| §2, "a percentage a skill gives" | unchanged, plus the new stat codes of §3.3 |
| §4.4, heavy T1 needs Medium **IV**; capital T1 needs Heavy **IV** | **III** (D2, K1). Rows 0135 / 0138 are re-cut as data |
| §5.1, `skill_queue_max` 10; general skills enrol at any academy | **50** (D1); **any port** (D3) |
| §5.2, the catalogue | **Superseded by §3.3 here** (+15; the four specialisations gain a support-V and a second bonus) |
| §8 **S13** Gear II | **unchanged** |
| §8 **S14** Wave B | built (0138). Only its capital rows' Heavy IV → III (K1) |
| §8 **S15** Wave C (T2) | Hulls and gear **unchanged**. The specialisations' support-V prerequisites and second per-level bonus **move to K1**; S15 no longer authors them |
| §8 **S16** perks and sets | **unchanged** |
| §8 **S17** famous ships | **unchanged** |
| §8 **S18** merchants of every flag | **Changes**: `npc_found` seats captains through `seat_captain_for` (not `post_officer_to`), and each uses her job trait only. Its proof adds "every merchant fleet's `crew_pct` = pre-image" |
| §8, before lighting `skills_bite` | **K0 first** (§7.1) |

`SHIPS_AND_SKILLS.md` gets a pointer to this file at §5 and §8 in this PR.

---

## 10. Words (`docs/WORDS.md`, added with the client slices)

| Concept | Say | Never |
|---|---|---|
| a hired person | **captain** (`Hire captain`, `Captains today`) | officer, mate, navigator (as the general word) |
| you, the player | **you** / **your company** | captain (for the player) |
| what a captain can do | **traits** (`Traits · 3 / 5 in use`), each named by its job word (`Navigator`, `Gem trader`) | skills (that is the Academy's word), effects, perks |
| her grade | **S captain** · grade **S / A / B / C** | rank (that is RANK's word), tier, star |
| her levels | **Exploration 7 · Trading 3 · Combat 1** (`7 / 20`); *"capped at your Trading level 3"* | XP, Lv |
| where she sits | **Captain's cabin** · **Trade cabin** · **Exploration cabin** · **Combat cabin**; **Seat** · **Ashore**; `50 % here` | slot, berth, posted |
| what the captains add | **Crew bonuses** (the fleet sheet), one line per source | expertise, buff |
| moving up a grade | **Promote** (`Promote to B · 10 Sea Charts`) | rank up, ascend, transcend |
| promotion items | **Trade Seal** · **Sea Chart** · **Battle Honour** | contract, astrolabe, certificate |
| homesickness | **Homesick** (`Homesick: 4 days from Iberia · −13 %`) | morale, loyalty, mood |
| languages | **Speaks Portuguese, Spanish** | LV, fluency |
| a combat trait before combat | *works when combat arrives* | locked, disabled, coming soon |
| bonus training | *+1,000 from sailing today* | injector, boost, XP |

---

## 11. Watching it

| Measure | Target, a week after each switch | Where |
|---|---|---|
| Arrivals sweep | avg ≤ 3 s, max < 8 s | `cron.job_run_details` |
| Merchant lap net | unchanged (merchant numbers are pre-image) | ECONOMY_LOOP §7 query |
| Captains hired by players | > 0 per active house; S rare | `player_officers` |
| Grades reached | first B within weeks, first S in months (O8) | `captain_state` |
| Bonus training | most active houses at or near the cap | `skill_sp_grants` |

**Levers (knobs, no migration):** `skill_queue_max`, `skill_sp_per_arrival` / `_day_cap`,
`homesick_after_hours` / `_penalty_pct`, `promotion_item_points`, `language_haggle_points`, each
`crew_effects.cap_pct`, `captain_level_pct_per_level`.

---

## 12. What this plan does not do

- **No new gate.** Not on hulls, ports, seas, routes or languages (D9, D14). Origin's captain gate on
  hulls and its language gate are both left out [UWO §3.6, §5.3].
- **No loyalty meter**, no conversations or speeches (D13).
- **No crew homesickness** (the owner's *"even crews"*). It needs a figure per hull and is a slice of its
  own if wanted (D13).
- **No gacha, gems, contracts per captain, transcendence, gear on captains or admirals** [UWO §0.12,
  §3.9, §3.11]. The house is the admiral; its Skills are Origin's Company Research, grown into EVE's
  tree [UWO §4.8].
- **No injectors, attributes or skill points for coin** (D7).
- **No dismissal penalty beyond O8** (a re-signed captain starts over).
- **No visual combat**, ever. Combat traits are probability-table inputs once S4 lands.
