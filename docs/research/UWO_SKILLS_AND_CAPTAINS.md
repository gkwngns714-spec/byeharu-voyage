# Uncharted Waters Origin — skills, captains and mates (research)

**Research date:** 2026-10-17. **Researcher:** Claude (Fable 5.1), on request of the owner.
**Purpose:** ground the captain/officer and skill work of byeharu-voyage (`docs/SHIPS_AND_SKILLS.md`,
`docs/DESIGN_V1.md` §7, migrations 0015 / 0073 / 0119 / 0127 / 0131 / 0133) in what *Uncharted Waters
Origin* (대항해시대 오리진, LINE Games / Motif / Koei Tecmo, 2022 KR, 2023 global) actually does with its
**mates** (항해사 — the game's word for captains/officers), its **admirals** (제독 — the player avatar)
and its **skills**, so that we copy on purpose and diverge on purpose. Companion to
`docs/DESIGN_RESEARCH.md` (2026-08-18), which covered trade, investment and the company shell; this
file goes deep on the people and the skills only.

Everything below is summarised in my own words; every fact carries the URL it was read from. Where a
page is a fan source (Namu Wiki, Inven, a Steam guide, a blog) it is marked **[F]**; official LINE
Games pages (guide.floor.line.games, uwo.floor.line.games) are **[O]**. Numbers from fan sources were
true at the date of that page and several have since been patched — the patch history in §5 says
which. Two Steam guides used heavily (Quizzical's "Promotions and training" and "Ships and
shipbuilding") now carry a Steam notice that they were removed from the Community, but their text was
still served at research time.

---

## 0. The fifteen findings that matter for us

1. **Origin has no "captain stat block" in the RPG sense.** A mate has three *levels* (Adventure /
   Trade / Combat), **twelve expertise numbers** (4 ship-side combat ones, 8 fleet-side adventure and
   trade ones), languages, and then *skills* and *effects*. Nothing like 통솔/항해/전투. §3.4.
2. **Positions are cabins, not job titles.** Every ship has one Captain's Cabin (100 % of a mate's
   expertise in all three focuses) plus roughly ten other cabins of five types (A–E; only A, B, C take
   a person). A mate in a cabin whose focus does not match loses up to 50 % of her expertise. Cabins
   are *changed at the shipyard* and the change applies to every ship of that class. §3.5.
3. **Ship vs fleet scope is the whole design.** Combat expertise (Artillery / Ramming / Support /
   Melee) is summed per *ship*; adventure and trade expertise (Nature / Aesthetics / Scouting /
   Supply / Purchasing / Sales / Negotiation / Trade) is summed across the *whole fleet*. So trade
   officers can sit anywhere and combat officers must sit on the ship that fights. §3.4, §3.5.
4. **Grades C → S set hiring cost and growth cost only; they do not cap level.** A C can be *trained*
   up to SS after her fourth promotion (C→B→A→S→SS), each step roughly doubling her numbers. §3.8–3.9.
5. **Mate level is capped by Company level**, which the publisher raises every few months (105/145 in
   Dec 2025, 110/150 in May 2026, 115/175 in Aug 2026), and **transcendence** adds +20 / +40 / +60 on
   top. There is no "awakening" of stats — transcendence adds *effect slots* and *level cap*. §3.7, §3.10.
6. **Promotion is the real mate grind**: 4 promotions (rank 1→5), gated by mate level 30 / 50 / 70 /
   90 and paid in *that mate's own* contracts (10 / 20 / 40 / 80), astrolabes and appointment
   certificates whose counts scale with grade (S: 50 / 80 / 120 / 160 astrolabes). Contracts come
   from inn "parties" (ducats, chance) or blue gems (certain). §3.8.
7. **Skills are combat-only; everything economic is an "effect" or "expertise".** A mate carries
   1–2 active *naval combat skills* (artillery / ram / melee / repair / medicine / seal variants) and a
   duel skill, each levelled 1–10 with published per-level tables; up to **4 effects** can be
   *activated* at once (5 after transcendence, 6 with a paid memoir). §4.3–4.4.
8. **Effects stack by count.** Two mates on one ship with the same skill or effect raise its level;
   fleet expertise is a sum over every assigned mate. This is the game's only "set bonus" between
   people; real set bonuses are mate *collections* (e.g. +0.1 % per tier) and ship engravings. §3.5, §4.7.
9. **Languages are a hard region gate carried by people, not by the player.** 36 languages, LV 1–5,
   the fleet's level is the *max* among its mates (not a sum); without the language a port offers
   only Supply / Repair / Recruit; LV 1 unlocks exchange-only trade, LV 2 quests, LV 5 about 5 % off
   prices. §4.6.
10. **Loyalty is a timer treadmill** (conversation every 4 h, speech every 24 h, decays at sea; a
    "slacking" mate cannot be assigned) and most players treat it as busywork. Negotiation hires
    start at 60 loyalty, gem hires at 100. §3.11.
11. **The one restriction Origin removed was the captain-level gate on hulls**: "operation conditions"
    (−5 % per unmet focus, −15 % max) were cut to LV 1 for every ship in the Dec 2024 rebalance, in
    the same note that turned Build LV from a gate into a time discount. Players had complained that
    the gate homogenised fleets. §3.6, §5.4.
12. **Gacha for mates was removed** (Nov 2024, global): mates moved to inns, contracts to the Black
    Market and the Fortune Teller, and the publisher gave 5,000 blue gems plus an admiral voucher as
    compensation. The old pull was 4,000 red gems per 10, with roughly 0.2 % per specific S/A mate. §5.4.
13. **Expertise bonuses are modest and capped**: Purchase / Sales Expert effects run 2.5 % → 15 % over
    ten levels with a 20 % cap; Purchasing expertise gives +5 % purchase *quantity* per level from
    LV 2; speed effects are 1 % → 10 % per effect; the whole thing is built so one mate never moves a
    number more than a few per cent. §4.4, §4.5.
14. **The admiral is the one "player skill" holder**: Admiral's Orders (voyage and combat commands
    paid in morale), unique skills by level, and Company Research (70 points per branch) are the only
    progression the *player* owns; everything else is on the mates. §4.2, §4.8.
15. **Origin's shape is a collection game grafted on UW2's crew idea.** UW2/New Horizons mates had
    8 personal stats and three flagship posts (First Mate / Bookkeeper / Chief Navigator); UW Online
    had the player's own 100+ ranked skills plus up to 5 "aides" with duties. Origin took the aides'
    duties (as cabins) and dropped the player's skills almost entirely. §6.

---

## 1. The container: Company, Admiral, Mates, Fleet

- A **Company** is the account; it holds the **Admiral** (the player's avatar, always aboard the
  flagship), the **Mates**, and up to **4 fleets** of ships. Company LV gates fleet size (7 ships at
  Company LV 55) and the dock holds 7 by default. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111115 ·
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114 ·
  **[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 (1–7 ships a fleet, 4 fleets).
- The **Admiral** is a mate too, structurally: an S-grade character with stats about 20–30 % above a
  normal S mate, a unique job title, unique skills, a Chronicle (story) and Admiral's Orders. Five
  starters are free; from Pietro Conti on they cost 5,000 red gems (or, since late 2024, a voucher),
  and the first extra admiral can instead be bought for 100 million ducats after Company LV 25.
  **[O]** https://guide.floor.line.games/UWO/en_US/detail/1111111111111111111 ·
  **[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 ·
  https://forums.mmorpg.com/discussion/500581/the-business-model-for-uncharted-waters-origin ·
  https://steamcommunity.com/app/1574360/discussions/0/4692280123603369124/
- The Admiral's three **Fame** types and 11 **Title** levels are the player's rank; the fame
  thresholds run 2,200 (LV 2) → 9,700 → 44,600 → 123,000 → 254,500 → 449,300 → 719,700 → 1,070,100 →
  1,512,600 → 2,053,100 (LV 11, lowered from 2,750,000). Title LV 5 is what lets you *build* ships of
  grade 13 and above; LV 4 starts pirate harassment. **[F]**
  https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 ; the tax table per title is in
  `docs/DESIGN_RESEARCH.md` §1.8.

---

## 2. How mates are obtained

| path | what it is | cost / rule | source |
|---|---|---|---|
| **Inn — Negotiation** | talk a mate down with ducats; success chance is the current Friendship; start Loyalty **60** | Friendship is raised by **Gift** (an item) or **Sponsor** (ducats); both need a mate in your fleet who speaks the candidate's language | **[O]** https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 ; KR page https://guide.floor.line.games/UWO/ko_KR/detail/1167031174330200447 |
| **Inn — Quick Hire** | pay Blue Gems, 100 % success, start Loyalty **100** | a fan page gives an S mate at ~4,800 gems with language LV 5 vs ~5,300 at LV 1 | **[O]** same KR page · **[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 |
| **Failed negotiation cooldown** | by grade | S 360 min · A 180 · B 30 · C 10 | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1653441748014014523 |
| **Who is in which inn** | each mate appears at a short list of "party ports" / "hire ports" (5–7 cities, usually her language area); the inn can be filtered by language | e.g. Catalina de Erauso: Valparaíso, Caracas, Copiapó, Tumbes, Palma, Gijón, Soda Is. | **[F]** https://uwo.inven.co.kr/db/character/chabbb058 · **[O]** every "New Mates" notice, e.g. https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 |
| **Chronicles** | an admiral's story hands over 1–3 mates (reward or inn-unlock) | e.g. Louise de Beaujoyeulx after Helen Raspberry's chronicle; Francis Drake after Otto's | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 · **[F]** namu (above) |
| **Employees (종업원)** | unique tavern NPCs hired after Friendship LV 4 | e.g. Malinalli (Panama), Ulloriaq (Cohasset) | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621 (Sep 2025 notice) |
| **Shop / Step-up (paid)** | some S mates are shop purchases | e.g. Valentina Morel, Giacomo Decampania | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 |
| **Investment Season shop** | seasonal mates for seasonal deeds | deeds expire with the season | **[O]** https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473 |
| **Gacha (removed)** | "Superior Mate" chests, 4,000 red gems / 10; duplicates gave 30 contracts | ended 6 Nov 2024 (global) | **[F]** https://forums.mmorpg.com/discussion/500581/the-business-model-for-uncharted-waters-origin · **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1729660250450018684 |

Two details worth copying: (a) the inn roster is per port and per mate, so *where* you sail decides
who you can sign (the thing 0073 derives for us); (b) the same inn later sells the mate's **contracts**
(§3.8) through a "party" — so the inn stays useful after the hire.

---

## 3. The mate (captain) system

### 3.1 Grades

- **C, B, A, S** at birth ("natural grade"); grade drives hire cost and growth cost, nothing else
  directly. **[O]** https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447
- Contract *interview* prices by grade (fan, 2023): C 10,000 ducats · B 50,000 · A 500,000 ·
  S 2,500,000; a successful interview (50 %) yields 5 contracts. **[F]**
  https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- Since March 2023 no new C-grade mate has been added; several C pirates were raised to B. **[F]** same.
- A fifth tier **SS** exists only as a *training* destination (§3.9). **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949
- Player sentiment: S and A mates are the game; C mates are "almost never used" except a handful
  with a specific trade effect. **[F]** Inven board summary in search of
  https://www.inven.co.kr/board/uwo/5715/274 · https://www.inven.co.kr/board/uwo/5715/258

### 3.2 Focus and job (계열 · 직업)

Every mate has one **focus** (Adventure / Trade / Combat) and one **job** (직업) that names her
primary expertise. Inven's database filter lists the job vocabulary — about 45 jobs — including:
Trade: 가공상 (crafts), 가축상 (livestock), 광물상 (ore), 미술상 (art), 방적상 (textiles), 보석상 (jewels),
식품상 (food), 약품상 (medicine), 염료상 (dye), 잡화상 (sundries), 주류상 (liquor), 향료상 (spices),
협상가 (negotiator), 회계사 (accountant), 투자가 (investor), 통역가 (interpreter);
Adventure: 고고학자, 생물학자, 예술학자, 지리학자, 측량사, 탐험가, 수렵가, 보급장 (supply chief),
위생사, 상담사 (counsellor), 수석 항해사 / 항해장 (chief navigator);
Combat: 대사수 / 함포수 (gunners), 유탄수 (grenadier), 백병대 / 타격대 / 특공대 (boarding corps),
조타수 / 조타원 / 조타장 (helmsmen → ramming), 수련의 / 일반의 / 전문의 (doctors → support),
수리공, 조선공, 설계사, 갑판장, 조범수. **[F]** https://uwo.inven.co.kr/db/character/

The job decides which **job effects** she unlocks by level (e.g. a Food Trader gets "Food Trade
Specialization", "Food Discount"; a Marine gets Melee crit and attack), so the job *is* the kit's
skeleton. **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621

A fan-made job recommendation chart exists (image only). **[F]**
https://trees.gamemeca.com/view.php?gid=1685443

### 3.3 Levels

- A mate has **three levels** — Adventure, Trade, Combat — each raised by the matching activity while
  she is *assigned to a cabin* (an unassigned mate earns nothing). **[F]**
  https://oyururi.info/daikoukaizidai-origin-koukaishi/ ·
  https://www.khitc.com/wp/ddon/origin5/ · **[O]** (unassigned mates do nothing)
  https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447
- EXP from a cabin: a cabin with a focus pays 100 % EXP for that focus and 50 % for the others; the
  Captain's Cabin pays 100 % for all three; commissions (dispatch) pay 100 % regardless. **[F]**
  https://www.khitc.com/wp/ddon/origin5/ ·
  https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Cap = Company LV** (fan reports), raised by the publisher: Company 105 / Mate 145 (Dec 2025),
  110 / 150 (May 2026), 115 / 175 (Aug 2026). **[F]**
  https://steamcommunity.com/app/1574360/discussions/0/3781373416983732223/ · **[O]**
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1765784705114026646 ·
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471
- Catch-up: Company "growth speed support" multipliers by level band (1,500 % for LV 1–25 down to
  nothing at 91–100 in Sep 2025; retuned May 2026), mate **EXP potions** that jump straight to a
  chosen level, and since Aug 2026 a *new* mate joins already at a level matching your Company LV.
  **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471

### 3.4 Stats: twelve expertise numbers, two scopes

| scope | focus | expertise (EN / KR) | what it moves |
|---|---|---|---|
| **Ship** (summed per ship) | Combat | Artillery 포격술 | artillery attack, accuracy, crit, artillery defence, evasion |
| | | Ramming 충파술 | ram attack, crit, ram defence |
| | | Support 지원술 | amount and chance of maximised Repair / Medicine |
| | | Melee 백병술 | melee attack, accuracy, crit, melee defence, evasion (and land-exploration combat power) |
| **Fleet** (summed over every assigned mate in the fleet) | Adventure | Nature 박물학 | chance of discoveries while exploring (observation) |
| | | Aesthetics 심미학 | ducats and fame when reporting discoveries |
| | | Scouting 척후법 | sailing speed, docking range, escape from inspections, disaster prediction (speed bonus stops at LV 6 — fan) |
| | | Supply 보급법 | daily food/water use, self-resolution of rat / scurvy / plague / fire; from LV 15, +300 recruitable crew every 5 levels (Aug 2026) |
| | Trade | Purchasing 구매 전략 | lower buy prices and better negotiated discount; since May 2026 also +5 % purchase quantity per level from LV 2 |
| | | Sales 판매 전략 | higher sell prices and better negotiated surcharge |
| | | Negotiation 협상 전략 | chance of a price negotiation and re-negotiations; parley in inspections |
| | | Trade 교환 전략 | distance at which market prices can be read at sea ("+20 miles to market prices") |

Sources: **[O]** https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028 (Mate Details) ·
https://guide.floor.line.games/UWO/ko_KR/detail/1167031174330200447 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 (Supply +300 crew, expertise max +10) ·
https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795 (Purchasing +5 %/LV) ·
**[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 (Scouting stops at 6; "exchange
strategy useless until barter") · https://steamcommunity.com/app/1574360/discussions/0/4692280123603369124/

Each expertise has its own **level** with an EXP curve: Combat expertise max was raised 15 → 20 in
Sep 2025 with LV 3→4 costing 1,557 (was 1,950) and LV 11→12 13,146 (was 6,840); Aug 2026 added +10
to every expertise cap. **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471

An actual sheet, for scale (B-grade Spanish grenadier Catalina de Erauso): Artillery 73, Ramming 27,
Support 20, Melee 32 · Nature 35, Aesthetics 20, Scouting 27, Supply 32 · Purchasing 7, Sales 19,
Negotiation 14, Trade 12; Spanish LV 2, Quechua LV 1. **[F]**
https://uwo.inven.co.kr/db/character/chabbb058

### 3.5 Positions on a ship: the Captain's Cabin and the cabin grid

- **The flagship carries the Admiral; every other ship may have one Captain** (a mate in the
  Captain's Cabin). Auto-assign puts the highest *Combat LV* mate there — a design players dislike
  because a promoted C can out-rank an S on that single number. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 · **[F]**
  https://namu.wiki/w/대항해시대%20오리진/평가
- **Cabin types.** A ship has ~10 cabins in five types: **A, B, C take a mate** (and give a stat
  bonus); **D and E give a stat bonus only**. Counts by ship grade (fan table): grades 1–4 have 2×A
  + 2×C assignable; grade 5–12 add a B; grades 13+ have 2A/2B/2–3C plus "+" cabins that unlock with
  blueprint level. **[F]** https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Rates.** Each cabin applies a percentage of the mate's expertise per focus. Captain's Cabin
  100/100/100; Old Rudder / Old Deck 70–80/70–80/70–80 (sources differ: 70 vs 80); Old Mast /
  Aide's Cabin / Measuring Room 70/70/70; Accounting Room 60/100/60; focus-specific A cabins
  100/50/50 (adventure), 50/100/50 (trade), 50/50/100 (combat). Rates rise 10 % per ship grade up to
  100 % and by cabin size (+10 medium, +20 large, +30 massive). **[F]**
  https://www.khitc.com/wp/ddon/origin5/ · https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Named cabins and what they add** (small / medium / large / massive ship):
  Type A — Rudder (Ramming +3/6/10/15 %), Deck (Melee +3/6/10/15 %, Scouting +2/4/6/10 %),
  Ice Breaking / Seaworthiness / Momentum labs, Rowing Cabin, Luggage Management (supplies cost
  −1…−4 %), "(skill) Lab" (+3/6/10/15 % to one adventure/trade/combat skill), Supply Management (load
  +3/5/7/10), "(goods) Management Room" (purchase quantity of one goods type +5/8/10/12 %),
  Ammo / Weapon / Disguise Management (artillery / melee / ram attack +5/10/15/20, crit +1…4 %),
  Crew Management (max crew +4…16), Banquet Management (mobility +6…20).
  Type B — Mast (Scouting +5/8/13/18 %), Crow's Nest (Scouting +3…15 %, Artillery +2…10 %).
  Type C — Aide's Cabin (Negotiation +3…15 %, Trade +2…10 %), Infirmary / Recreation Room / Personal
  Quarters (Support +3…15 %), Chapel / Livestock Pen (Supply +5…18 %), Kitchen (Supply + Support),
  Measuring Room / Strategy Room (Scouting + Artillery or Negotiation), Library (Aesthetics), Laboratory
  (Nature), Accounting Room (Purchasing +3…15 %, Sales +2…10 %), Marine Barracks (Melee +5…18 %),
  Training Room, Gun Port (Artillery +3…15 %).
  Type D (no mate) — Supply / Weapon / Ammo / Concealed / Enhanced / Luggage Storage, "(goods) Storage".
  Type E (no mate) — Lounge, Banquet Hall, Crew's Quarters, Rowing Deck. **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Compatibility rule.** A mate in a cabin that shows another focus's icon loses up to **50 %** of
  her expertise; this is the official number. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114 · the worked example on a fan
  page: a melee mate at 9,136 reads 10,049 in a melee lab (+10 %), 10,323 in marine barracks (+13 %),
  and 8,222 in a lookout post. **[F]**
  https://gall.dcinside.com/mgallery/board/view/?id=bigtimeofnavigation&no=349152
- **Stacking.** Two or more mates on one ship with the same skill or effect raise that skill's level
  (officially) and also its action-point (mobility) cost (fan). **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028 · **[F]** namu (above)
- **Two special cabins everyone is told about**: an **Aide's Cabin on the flagship** lets the aide
  auto-use tools to end fleet disasters; an **Accounting Room somewhere in the fleet** (on the flagship,
  per one guide) is required for price negotiations to appear at all, and it also shows nearby cities'
  prices on the world map. **[F]** https://steamcommunity.com/app/1574360/discussions/0/3781373416977477305/ ·
  **[O]** https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114
- **Changing cabins** happens at Shipyard → Blueprint → Change / Modify Cabin, costs ducats (≈10k per
  grade small, ≈100k medium) or blue gems (10 / 20 × grade for some A options), and **applies to every
  ship of that class you own or build** (schooners excepted). **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114 · **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Dispatch (파견)** uses fleets 2–4 (2 free slots, 3rd and 4th bought) on timed adventure / trade /
  combat missions with a fleet-LV band per region and a shown success chance; rewards include
  promotion materials and contracts. Example gate: Eastern Pacific dispatch needs LV 85, Trade
  expertise LV 17, Seaworthiness 150, Momentum 120. **[O]**
  https://guide.floor.line.games/UWO/ko_KR/detail/1167884807499300699 ·
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795

### 3.6 "Operation conditions": the captain-level gate that was removed

Until Dec 2024 every hull had minimum Adventure / Trade / Combat levels for the mate in its Captain's
Cabin; each unmet focus cost −5 % of base stats, −15 % at most. Fan pages record it; players said it
forced everyone into the same few hulls. The Dec 2024 rebalance set every ship's condition to LV 1 and
removed the penalty, and in the same note made Build LV a 50 % time discount instead of a build gate.
**[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보 ·
https://namu.wiki/w/대항해시대%20오리진/평가 · **[O]**
https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473

What *does* still gate: sea areas by fleet-average **Seaworthiness / Momentum / Ice Breaking / Rowing**
and Company LV (e.g. a chronicle at Company 40, Seaworthiness 130, Momentum 60; a route at Company 40,
Seaworthiness 210, Ice Breaking 160), languages (§4.6), and land exploration by **Combat Power /
Observation / Gathering Power** (e.g. 620 / 650 / 620). **[O]**
https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 ·
https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795 ·
https://guide.floor.line.games/UWO/en_US/detail/1167031265223600324

### 3.7 Ranks: promotion (승급), four times

- Every mate starts at rank 1 and can be promoted four times to rank 5. Each promotion raises her
  expertise by roughly 10 %, **adds one activated-effect slot (max 4)**, unlocks skills and raises the
  level cap. Level gates: rank 2 at mate LV 30 (two character effects), rank 3 at LV 50 (a naval
  combat skill), rank 4 at LV 70 (last two job effects), rank 5 at LV 90 (last two character
  effects); a few mates have a natural LV 99 effect. In Sep 2025 the LV 50 job effect moved to the
  2nd promotion and the LV 70 character effect to the 3rd. **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949 · **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621 ·
  https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028
- **Materials** (fan table, 2023; still the shape players quote): contracts 10 / 20 / 40 / 80 for
  ranks 2–5 regardless of grade; astrolabes = appointment certificates, by grade:
  C 20/30/40/50 · B 30/40/60/80 · A 40/60/90/120 · S 50/80/120/160, in material grades D / C / B / A;
  ducats are minor. Appointment certificates are split by focus (adventure / trade / combat).
  **[F]** https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949 ; an Inven tally gives
  totals per grade over promotion plus training (e.g. an S mate needs about 260 contracts in all).
  **[F]** https://www.inven.co.kr/board/uwo/5714/1182
- **Contracts are per mate** (generic "common" contracts of the mate's grade can substitute and are
  rarer); they come from inn parties (ducats, chance; blue gems, certain), re-hiring at inns (5
  each), combat dispatches, the Black Market, the Fortune Teller (30 lower common → 1 upper), and a
  weekly mileage shop (10 S-grade common contracts for 8,000 mileage). B and C grade *dedicated*
  contracts were deleted in June 2026 in favour of common ones. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1729660250450018684 ·
  https://uwo.floor.line.games/kr/bbs/community/walkthrough_kr/1/detail/1780911845784024615 ·
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1733294207241009126
- Astrolabes and certificates come from events and **land training** (3 per day, +1 with a prime
  minister, +7 with a paid buff). **[F]** https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949

### 3.8 Training (훈련): grade climb after rank 5

- Only a rank-5 mate trains. Each step moves her grade one up (C→B→A→S→SS), costs equal counts of
  contracts, astrolabes, certificates and training manuals (C 50 · B 65 · A 85 · S 110 per step, two
  material grades each) plus 100 blue gems, and roughly doubles her stats. **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949 · **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447
- **Training points**: up to 4 rounds; each point adds +10 to one expertise; points per step
  C→B 75, B→A 90, A→S 150, S→SS 260, with per-stat caps C 0 / B 20 / A 25 / S 40 / SS 70. A natural
  S therefore gets fewer total points than a natural C trained all the way — the game's one
  deliberate "C can matter" lever. Points are reset with blue gems. **[F]** same guide; **[O]** same page.
- Training *takes time*: job effects 3–4 12 h, character effects 3–4 24 h, potential effects 24 h
  (Aug 2026). **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471

### 3.9 Transcendence (초월): the level-cap and slot extension

- Requires the mate's highest training; adds **one effect slot**; costs a Tome of Transcendence
  (초월서, from the Lighthouse of the Ruins, Arctic land training, a Cape Town smuggler boss, or
  100 per 1,500 mileage weekly), contracts and promotion materials. **[O]**
  https://uwo.floor.line.games/kr/bbsCmn/detail/1727430459384024809 ·
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1733294207241009126
- Stage 1: max level = Fleet (Company) LV + 20; Stage 2 (Sep 2025): +40, needs 초월의 증표 from an
  event shop; Stage 3 (Aug 2026, S grade only for now): +60, a new per-mate Transcendence Effect, and
  a "Sacred Stone of Transcendence" (100 from a Prime Minister election). **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 · **[F]**
  https://byline.network/2025/09/26-493/
- An admiral with a paid **memoir** gets a sixth effect slot on top. **[O]**
  https://uwo.floor.line.games/kr/bbsCmn/detail/1727430459384024809

So Origin's "awakening/limit-break" is *not* a stat multiplier; it is +1 slot and +20 levels per stage.

### 3.10 Loyalty (충성도) and condition

- Every mate has Loyalty; a conversation raises one mate every 4 h, a speech raises all every 24 h;
  it **falls while sailing**; a mate who is "slacking" (태업) cannot be put in a cabin; injured mates
  cannot use skills. Negotiated hires start at 60, gem hires at 100; no max is published. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 ·
  https://guide.floor.line.games/UWO/ko_KR/detail/1167031174330200447 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1653441748014014523
- Two **fleet morale** states live beside it: **Homesickness** and **Anxiety / Quarreling** are
  fleet-wide afflictions that some mates' job effects relieve (e.g. a Counselor's "Homesickness Relieve
  3.3 %", "Mental Therapy 3.3 %"). **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621
  — the owner's "homesick captains" idea (`docs/DESIGN_V1.md` §7.2) has a direct precedent.

### 3.11 Gear and appearance

Mates have 6 gear slots (weapon, armour, cape, accessories); gear mostly raises combat stats and
duel, can raise expertise, and at high enhancement adds large expertise (e.g. an adventure/trade piece
at +10 went 532 → 1,200 in Sep 2025). Appearances add EXP bonuses and disguises. **[O]**
https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621

### 3.12 How many people per ship and per fleet

- 2–6 assignable cabins per ship by grade (§3.5), ~7 ships in Fleet 1 at Company 55, so a full
  main fleet carries on the order of **25–40 assigned mates**; four fleets in all; the mate roster
  itself is unbounded (collections of 150+ S mates exist). **[F]**
  https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460 · namu (above) · **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114

### 3.13 Example kits (numbers as published)

Format: *grade · focus · job · expertise · languages* → natural effect; job effects; character
effects; potential effects; skills. All LV 1 unless stated.

1. **Sophie Rosaline Vidocq** — S · Trade · Jewel Trader · Negotiation · French 5, German 3 →
   natural: Metal sale surcharge +0.2 %; job: Ram Attack +41, Jewelry trade specialisation +5.6 %
   purchase qty, Metal +5.6 %, Jewelry discount 1 %; character: Enchanted Ability (−1 % goods used in
   barter), Elusiveness (18 % chance +7.5 % all attack at turn start), Advanced Medical at Start
   (35.2 % chance, +6.1 % crew HP), Jewelry Sales Surcharge LV2 +2.5 %; potential: Jewelry Sales
   Expert +2.5 %, Metal Trade Expert +13 % qty; skills: Seal Skill LV1 (26.3 % chance, 2 turns),
   Enhanced Ram Strength LV2 (+26 % ram attack to allies in range, 3 turns). **[O]**
   https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621
2. **Beatrice Elena** — S · Trade · Food Trader · Purchasing · Latin 5, Greek 3 → Food sale
   surcharge +0.2 %; Medical recovery +13, Food +5.6 % qty, Seasoning +5.6 % qty, Food discount 1 %;
   Charming Offer (−1.1 % amity in barter quantity talks), Artillery crit resist +5 %, Ram crit damage
   resist +2.3 %, Food Sales Surcharge LV2 +2.5 %; potential: Food Sales Expert +2.5 %, Seasoning
   Purchase Expert 2.5 % off; skills: Seal Action LV1 (35 %, 2 turns), Enhanced Melee Attack LV2
   (+34.6 % to allies, 2 turns). **[O]** same.
3. **Malinalli** — S · Combat · Marine · Melee · N. American 5, S. American 3 → Quarrel
   prevention +0.2 %; Melee crit chance +166, Amplify melee crit +5 %, Melee attack +172, Melee crit
   damage +2.3 %; Metal discount 1 %, Extra fixed melee damage (14.4 %, +43), Melee crit resist +5 %,
   Additional Melee on Melee LV2 (17.5 % follow-up); potential: Advanced-amplify Melee Attack +10 %,
   Lethal Poison Melee (−10 % crew HP/turn, 3 turns); skills: Enhanced Melee: Damage Rudder LV1
   (148.5 % of melee attack to an area, 100 % rudder damage = −20.8 % mobility, 2 turns), Precise
   Melee: Confusion LV2 (121.1 %, 26.5 %). **[O]** same.
4. **Ulloriaq** — S · Adventure · Counselor · Supply · N. American 5, Caribbean 3 → Anxiety
   prevention +0.2 %; Melee evasion +23, Quarreling Relieve 3.3 %, Homesickness Relieve 3.3 %, Mental
   Therapy 3.3 %; Sweet Talker (−0.4 % profit standard for Trade Points), melee crit resists, Deep Sea
   Salvage +1; potential: Scrupulous Explorer +7 % loot, Unknown Strength (learned over time); skills:
   Enhanced Ram Strength LV1 (+18 %), Seal Action LV1. **[O]** same.
5. **Catalina de Erauso** (B, Spain, grenadier, Artillery) — see §3.4 for expertise; natural: Unknown
   Strength; job: artillery attack +2 %; effects by unlock level: LV 10 Artillery crit +35→+375 and
   Amplify crit +5 %→+90 %; LV 30 Techniques of Bargaining 1→10 % and Artillery counter +5.3→75 %;
   LV 70 Artillery attack +41→+500 and crit damage +2.3→12.5 %; LV 90 Treasure Hunter 0.1→1 % and
   Attack/Defence before action (18→50 % chance, +7.5→30 % / +6.1→25 %); skills: Artillery: Damage
   Rudder (LV1 60 mobility + 1 shot, 100 % dmg, rudder −12.5 %; LV10 195 mobility, 158 %, −25 %),
   Artillery: Ignore Defence (needs LV 50; LV1 15 % ignore / 100 % → LV10 50 % / 150 %); duel:
   Desperate Attack. **[F]** https://uwo.inven.co.kr/db/character/chabbb058
6. **João Franco** (starter admiral, Portugal, Royal Explorer, Aesthetics + Supply, Portuguese 4,
   Spanish 2) → skills Spread Shot, Precise Shot; orders: Vigilance (avoid enemy-started battles for
   a time), Control Sail (temporary speed), a fleet damage + guaranteed-crit battle order, Reinforce
   Ram, Golden Cannon (fixed crew damage + quarrel); effects: Wise Explorer, Sea Survey, defence when
   hit, speed at turn start. **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1653439283181013520
7. **Helen Raspberry** (admiral, Aug 2026, English chef, S, Trade, Negotiation, English 5, French 3;
   chronicle needs Company 40, Seaworthiness 130, Momentum 60). **[O]**
   https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471
8. **Players' "best mates"** (fan judgement): Jeanne Baret (Nature; Natural-born Merchant, Beast
   Hunting, Additional Durability, Combative Explorer), Olivia Mandeville (Natural-born Merchant,
   Rare Exploration, Deep-Sea Salvage LV2), Kim Hongdo, Qin Liangyu (melee kit), Aljeuna (a *C* who
   is "excellent" for Nature). Trade admirals' orders are mostly "+8.5 % overcharge on three goods
   types"; Grace O'Malley's Fleet Charge costs 50 morale. **[F]**
   https://steamcommunity.com/sharedfiles/filedetails/?id=3415268645
9. **Salvador Leis** (admiral) got a balance pass in Aug 2026: Mortal Charge melee attack 66.6 → 90 %,
   its defence-reduction 42.9 → 15 %; his gear's "Increase Melee Expertise" became "Melee Critical
   Damage". **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471
10. Older fan list of cheap useful picks (JP, 2023): Lorenzo Pinto (B accountant, negotiation chance),
    Walid Kemal (C sharpshooter, Ottoman), Anne Boleyn (B jewel merchant), Ibn Battuta (A explorer,
    Rare Exploration at LV 10). **[F]** https://oyururi.info/daikoukaizidai-origin-koukaishi/

---

## 4. The skill taxonomy

### 4.1 Who owns what

| holder | has | notes |
|---|---|---|
| **Admiral** (player) | unique naval-combat skills by level, duel skills, **Admiral's Orders**, three levels, three fames, titles; **Company Research** points | the only progression that is "the player's own" |
| **Mate** | 1–2 naval combat skills (LV 1–10), a duel skill, natural + job + character + potential **effects** (4 activated, +1 per transcendence stage, +1 memoir), 12 expertise, languages | §3 |
| **Ship** | a **trait** (Fixed Artillery, Ranged Charge, Rapid Melee, Formidable Support, Area Support…), a specialisation (Adventure / Trade / Combat), a combat type (Artillery / Ram / Melee / Support) in a rock-paper-scissors (Charging > Assault > Artillery > Charging), a **Captain's Cabin bonus** stat per hull, **Parts** (cannon, sail, figurehead, armour, ram, anchor, special), **cabins**, and for golden hulls **engravings** | **[O]** https://guide.floor.line.games/UWO/en_US/detail/1111111111111111113 · https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 · **[F]** https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460 |
| **Company / Guild / Pet / Collection** | Company Research effects; guild effects (e.g. +3 %…15 % vs a named enemy); pet effects (always on since Aug 2026); mate collections (+0.1 % per tier) | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1772088386191015429 · https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795 |

Origin therefore has **no player skill tree** in the EVE / UW Online sense. What `docs/SHIPS_AND_SKILLS.md`
builds (92 house skills, I–V, trained in real time) has no Origin counterpart; the nearest thing is
Company Research (§4.8).

### 4.2 Admiral's Orders

Admiral-only skills. Adventure and Trade orders are used in cities or at sea (avoid battle, speed,
price surcharges); Combat orders fire on the flagship's turn without spending it and cost **Morale**,
which builds through repeated combat. Trade admirals' orders are typically +8.5 % sale surcharge on
three goods categories (Imai Saki: crafts, livestock, fabrics; Kim Mandeok: dyes, sundries, liquor;
Chand Bibi: food, artwork, spices) and +15 % on any goods after a successful negotiation. **[O]**
https://guide.floor.line.games/UWO/en_US/detail/1111111111111111113 ·
https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028 · **[F]**
https://steamcommunity.com/sharedfiles/filedetails/?id=3415268645

### 4.3 Naval combat skills (mates and admirals)

- Three skill kinds: **Naval Combat Skills**, **Duel Skills**, **Admiral's Orders**. Skills are
  *active*, used in the hex-tile turn battle; each ship may register **4 quick skills**; a skill costs
  **Mobility** (action points) and sometimes ammunition. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111113
- Skill vocabulary (Inven DB "교전 기술" filter): families 포격 (artillery), 백병 (melee), 충파 (ram),
  수리 (repair), 의술 (medicine), 함성 (shout / buff), 첩보 (seal / intel); names are
  `<family>[: <status>]` — e.g. 광역 포격: 싸움 유발 (Area Artillery: Quarreling), 충파: 방어 무시 (Ram:
  Ignore Defence), 충파: 실명 유발 (Blind), 포격: 중독 유발 (Poison), 강화 백병: 키 손상 유발 (Enhanced
  Melee: Damage Rudder), 정밀 포격: 혼란 유발 (Precise Artillery: Confusion), 기술 봉쇄 (Seal Skill),
  행동 봉쇄 (Seal Action), 포격/수리/의술 봉쇄, 백병: 식량/물/자재/포탄 약탈 (plunder), 의술: 전 범위
  (Medicine: full range), 돌격 (Charge), 추가 기동력 증가/감소. **[F]** https://uwo.inven.co.kr/db/character/
- A skill has **10 levels**; the published curve for one (Artillery: Damage Rudder) is mobility
  60 → 195, damage 100 % → 158 % of artillery attack, rudder debuff 12.5 % → 25 %; a second skill on
  the same mate unlocks at mate LV 50. **[F]** https://uwo.inven.co.kr/db/character/chabbb058
- Base combat actions every ship has regardless of mates: Artillery (ammo, durability damage,
  counter-fire in range), Melee (adjacent, crew HP, captures), Ram (straight line, durability), Duel
  (same deck height, opponent must accept), Repair, Medicine; three sink conditions (durability 0,
  crew 0, lose the duel). **[O]** https://guide.floor.line.games/UWO/en_US/detail/1111111111111111113

### 4.4 Effects — the passive layer, with its published numbers

Effects come in four origins: **natural** (태생/소성, fixed, often a *debuff*, sometimes "Unknown
Strength" that reveals itself later), **job** (by the mate's job, unlocked by level), **character**
(인물, unlocked by promotion) and **potential** (잠재, from training/transcendence). Learning one costs
manuals (now "special manuals" instead of red gems), ducats and time; only *activated* effects work.
**[O]** https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621 · **[F]**
https://oyururi.info/daikoukaizidai-origin-koukaishi/

Official per-level values of potential effects (LV 1 … LV 10, cap where stated) — the full table is
at **[O]** https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1726144278318014479:

| effect | LV1 → LV10 | cap |
|---|---|---|
| Trade Expert (purchase quantity, one goods category) | 13 % → 150 % | 750 % |
| Purchase Expert / Sales Expert (discount / surcharge, one category) | 2.5 % → 15 % | 20 % |
| Techniques of Bargaining (negotiation occurs) · Gifted Merchant (negotiation succeeds) | 3 % → 15 % | 20 % · 35 % |
| Sage Discounter / Overcharger (on negotiation success) | 3 % → 15 % | 40 % |
| Excellent Negotiation / Trade Troubleshooter (barter price / quantity success) | 2.5 % → 20 % | 40 % |
| Kind Negotiation / Seductive Offer (amity cost in barter) | 5 % → 30 % | 50 % |
| Wonderous Ability (goods consumed when bartering) | 1 % → 10 % | 40 % |
| Seasoned Sail Handling (fleet speed) | 1 % → 10 % | – |
| Seasoned Rowing (galley speed) | 2 % → 15 % | – |
| Meager Rations (daily food/water) | 2 % → 10 % | 70 % |
| Seasoned Explorer (crew casualties exploring) · Exploration Supply Conservation | 3 % → 25 % | – |
| Master of Gathering / Scrupulous / Dedicated / Combative Explorer (loot rates) | 7 % → 22 % | – |
| Pirate Eradication / Beast Extermination (combat power vs type) | 5 → 42 | – |
| Advanced-amplify Artillery / Melee / Ram Attack or Defence | 10 % → 150 % | – |
| Nullify damage (chance) | 25 % → 70 % | – |
| Great Confusion (chance, 2 turns) | 30 % → 60 % | – |
| Lethal Poison (crew HP per turn, 3 turns) | 10 % → 27.5 % | – |
| Additional Durability on entering combat | 650 → 1,320 | – |
| Premium Repair / Medicine at Start | 10 % → 27.5 % | – |
| Create Opportunity (act again; chance / mobility back) | 25.6 % / 6.1 % → 60 % / 25 % | – |
| Formidable Heart (resist all status) | 15 % → 45 % | – |

The curve is the same shape everywhere: a large step at LV 2 and LV 5, a large step at LV 10, small
steps between — levels 2–4 and 6–9 are filler. Job effects use the same vocabulary at smaller
magnitudes (e.g. "Jewelry Discount LV1 1 %", "Food Trade Specialization +5.6 %"). **[O]** notices above.

### 4.5 Expertise levels and what a level is worth

- Each of the twelve expertise has a level driven by the fleet's summed values; a fan page records
  Fleet Expertise LV 1 at 15 and LV 30 at 650 (after the Sep 2025 retune, was 420). **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621
- **Purchasing**: +5 % purchase quantity per level from LV 2 (May 2026). **[O]**
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795
- **Supply**: from LV 15, +300 recruitable crew per 5 levels (Aug 2026). **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471
- **Scouting**: speed bonus stops growing after LV 6 (fan); Nature adds +0.5 % speed at LV 7 and no
  more. **[F]** https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- **Aesthetics** gates salvage areas (beginner LV 5, advanced LV 18). **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1768290895968000477
- Expertise caps were +10 across the board in Aug 2026; Combat expertise max 15 → 20 in Sep 2025.
  **[O]** links above.

### 4.6 Languages (언어) — the people-carried region gate

- 36 languages (Portuguese, Español, English, French, German, Turkish, Swedish, Latin, Russian,
  Dutch, Norwegian, Danish, Slavic, Greek, Arabic, Mande, Swahili, Bantu, Farsi, Sanskrit, Quechuan,
  Mayan, Nahuatl, Indigenous N./S. American, Arawakan, Caribbean, Mon-Ayutthaya, Malay, Mon-Khmer,
  Indigenous Oceanian, Tagalog, Javanese, Chinese, Japanese, Korean), each **LV 1–5**. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1167031198850700918
- The fleet speaks what **Fleet No. 1's** mates speak; its level in a language is the **highest** among
  them, never a sum; an admiral speaks her mother tongue at LV 4 and one other at LV 2; new S mates
  ship with LV 5 + LV 3. **[O]** same · notices above.
- Without the port's language only Supply, Repair and Recruit Crew work; fan pages add that LV 1
  allows exchange-shop trade only, LV 2 unlocks quests, and LV 5 is worth about 5 % on prices and more
  on hiring and shipbuilding. **[O]** same · **[F]**
  https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- Criticised for historical nonsense (Cervantes at Spanish LV 2; Park Yeon's Korean LV 1 below
  Hamel's). **[F]** https://namu.wiki/w/대항해시대%20오리진/평가

### 4.7 Ship-side skills, parts and set-like bonuses

- Every hull has a **Captain's Cabin bonus** — one expertise that the captain's seat amplifies on that
  hull (Tallette → Purchasing, Barque → Nature, Hansa Cog → Melee, Nao → Sales, Frigate → Artillery,
  Clipper / Junk / Treasure Ship → Trade, Golden Hind → Artillery…), and combat hulls always boost
  their own combat type. **[F]** https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- **Traits** on new hulls read like our Country sets: Fixed Artillery, Ranged Charge, Ranged Support,
  Rapid Melee, Formidable Support, Area Support. **[O]**
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471
- **Golden** (combined) hulls carry flat bonuses: +9 % advantage multiplier, −10 % disadvantage
  damage, +5.5 % mobility, or +4.5 % sale surcharge on three categories, or +9 exploration CP/OBS/
  gathering, or a 8.5 % per-turn area heal; **Ship Inscription** (grade 26+) rolls random effects that
  certificates can pin. **[O]** same · https://uwo.floor.line.games/us/bbsCmn/detail/1772088386191015429
- **Parts**: Special (seaworthiness, momentum, ice, rowing, sails, load, crew), Cannon (sets the
  artillery type), Sail, Figurehead (repair recovery), Armour, Ram, Anchor; enhancement to +12 with
  "unique and enhancement effects"; Part Engraving on SS parts at +8. **[O]**
  https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114 ·
  https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 ·
  https://www.invenglobal.com/articles/25770/uncharted-waters-origin-adds-two-s-grade-mates
- **Set bonuses**: mate **collections** (own a named trio → +0.1 % craft-goods surcharge per tier, +20
  medical recovery per tier) and guild effects; there is no equipment "set" on mates. **[O]**
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1765784705114026646 ·
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795

### 4.8 Company Research (the one player "skill tree")

Launched Feb 2025: Research Points from Admiral Chronicles and other content, spent on Adventure /
Trade / Combat effects; originally 70 points shared, redesigned (2026) to 70 points *per branch* with
sub-trees (Trade → General Trade / Barter / Smuggling) because players reset constantly once they
played more than one branch. **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1772088386191015429
· **[F]** search summary of https://www.line.games/company/news/1103

### 4.9 Where learning happens, and what it costs in time

| thing | where | pays | time |
|---|---|---|---|
| mate level | any activity while assigned; dispatch; EXP potions | — | continuous |
| effect (learn) | Mates menu | manuals / special manuals, ducats (red gems formerly) | instant (fan) |
| promotion | Mates → Promote | contracts, astrolabes, certificates, ducats | instant once paid |
| training | Mates → Train | contracts + astrolabes + certificates + training books + 100 blue gems | 12 h / 24 h per step (Aug 2026) |
| transcendence | Mates → Transcend | tome / token / sacred stone + contracts + promotion materials | acceleration tickets usable |
| language | hire a speaker into Fleet 1 | the hire | none |
| cabin change | Shipyard → Blueprint | ducats / blue gems | instant; class-wide |

**[O]** https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860

---

## 5. Progression economy and balance history

### 5.1 Currencies touching mates

Ducats (interviews, sponsors, negotiation, cabin changes), **Blue Gems** (earned; quick hire,
contracts-certain, training 100/step, point resets, cabin A options, 2nd quest slot 200/week),
**Red Gems** (paid; admirals 5,000, formerly gacha 4,000/10 and some effect unlocks, now vouchers such
as a Gold Astrolabe 108 or a Premium Manual voucher 48), **Mileage** (weekly shop: Tome of
Transcendence 100 / 1,500, S common contracts 10 / 8,000, Premium Training Book 100 / 2,000),
**Palace / Guild contribution** (training books, transcendence materials), **Seasonal investment
deeds** (seasonal mates). **[F]** https://forums.mmorpg.com/discussion/500581/the-business-model-for-uncharted-waters-origin
· **[O]** https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1733294207241009126 ·
https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471

### 5.2 Time gates

Loyalty 4 h / 24 h; negotiation cooldown 10 min–6 h by grade; land training 3/day; training 12–24 h
per step; shipbuilding 10 min (grade 1) to 7,020 min (grade 20+), halved by Build LV; Lighthouse and
season cycles monthly / quarterly. **[O]** §3 links · **[F]**
https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460

### 5.3 What players disliked, and what the publisher changed (chronological)

| when | change / complaint | source |
|---|---|---|
| CBT1 (2022) | gacha removed from the KR build — praised | **[F]** https://namu.wiki/w/대항해시대%20오리진/평가 |
| Mar 2023 global launch | surprise mate/item gacha, 4,000 red gems per 10, ~0.2 % per specific S/A; "40 GBP for 10 pulls at 1 %"; Steam reviews hostile | **[F]** https://forums.mmorpg.com/discussion/500581/the-business-model-for-uncharted-waters-origin · https://massivelyop.com/2023/03/08/uncharted-waters-origin-debuts-on-pc-and-mobile-devices-runs-afoul-of-gamers-thanks-to-gacha-monetization/ |
| Mar 2023 | new mates are B or above; C pirates promoted to B | **[F]** namu 게임 관련 정보 |
| 2023 | per-mate contracts seen as the pay wall; contracts repurposed from level-cap to effect slots | **[F]** https://steamcommunity.com/app/1574360/discussions/0/3781373416983732223/ |
| 2023 | auto-assign puts the highest Combat LV mate in the Captain's Cabin, so trained Cs displace S mates | **[F]** https://namu.wiki/w/대항해시대%20오리진/평가 |
| 2023 | "Supply" (보급법) partly unimplemented, "Trade/Exchange strategy" useless (until barter); min-crew rising with hull level felt backwards | **[F]** same |
| 2023 | ship homogenisation: blueprint level + operation conditions push everyone to the same hulls; Sep 7 patch unified seaworthiness, worsening it | **[F]** same |
| Oct–Nov 2024 | **gacha removed** (6 Nov 2024); gacha mates moved to inns, contracts to Black Market + Fortune Teller; 5,000 blue gems, 3 grade-20 ships, an admiral voucher, 200 EXP potions as gifts; reason stated: global grew slower than KR | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1729660250450018684 · **[F]** https://steamcommunity.com/app/1574360/discussions/0/4630356482652668850/ |
| Dec 2024 | **operation conditions → LV 1, penalty removed; Build LV → 50 % time discount**; investment seasons; ~40 admirals making 50 bn ducats a week named as the reason | **[O]** https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473 |
| Feb 2025 | Company Research added; redesigned 2026 after reset spam | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1772088386191015429 |
| Sep 2025 | LV 50 / LV 70 effects moved one promotion earlier; red-gem effects → special manuals; old mates' hire prerequisites removed; Combat expertise 15 → 20 with a re-curved EXP table; 2nd transcendence (+40); Fleet LV 100 | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621 · https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860 |
| Sep 2025 | several mate effects replaced by land-exploration effects (Francis Drake: Tight Net → Observation Study) | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860 |
| Dec 2025 / May 2026 | caps 105/145 → 110/150; Purchasing +5 % qty per level; "Recommended lists" stats removed | **[O]** links in §3.3 |
| Jun 2026 | B and C dedicated contracts deleted; common contracts, 30 lower → 1 upper at the Fortune Teller | **[O]** https://uwo.floor.line.games/kr/bbs/community/walkthrough_kr/1/detail/1780911845784024615 |
| Aug 2026 | Stage 3 transcendence (S only, +60); caps 115/175; training times fixed at 12 h / 24 h; new mates join at Company LV; Salvador Leis rebalanced; expertise caps +10; task rewards reworked toward mate growth | **[O]** https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471 |

Two systemic lessons the history teaches: **(a)** every gate placed on *people* (captain level per
hull, per-mate contracts, red-gem effects) was later loosened or deleted; **(b)** every power lever was
re-tuned toward *more levels and more slots* rather than bigger per-level numbers — the per-level
percentages in §4.4 have barely moved since 2024.

---

## 6. Where Origin's people and skills came from (brief)

### 6.1 Uncharted Waters II / New Horizons (1993–94)

- **Mates (navigators)** are hired in taverns/cafés or join through story; each has personal stats —
  Leadership, Seamanship, Knowledge, Intuition, Courage, Swordsmanship, Charm, Luck — plus a
  *Navigation level* and *Battle level* that grow with use, and binary skills: Celestial Navigation,
  Cartography, Gunnery, Accounting, Negotiation. **[F]**
  https://rpggamers.com/walkthrough/uncharted-waters-2-new-horizons ·
  https://listed.to/@Valtarien/60866/uwnh-mates
- A mate either **captains one of the fleet's ships** or holds one of three **flagship posts**:
  **First Mate** (morale, boarding — Leadership), **Bookkeeper** (prices, investment — Knowledge /
  Accounting), **Chief Navigator** (speed, storms — Seamanship / Celestial Navigation). The crew
  roster caps at 30 mates. **[F]** https://listed.to/@Valtarien/60866/uwnh-mates (its formulas are
  the author's own model, not the game's; treat as shape only)
- Examples: Rocco Alemkel (Sail 30 / Battle 32; Gunnery, Celestial Navigation), Hans Starten (Sail 10 /
  Battle 2; Celestial Navigation), Enrico Malione (Accounting; signs on as Joao's bookkeeper), Camillo
  Stefano (Celestial Navigation + Bookkeeping; Pietro's bargainer). **[F]** rpggamers (above)

Origin's lineage is visible: its mate roster re-uses these names (Rocco → 롯코 알렘켈 S combat, Enrico
Malione → 엔리코 마리오네 accountant, Camillo Stefano → 카미로 스테파노, Lopo/Hans/Pietro…), the three
posts became cabins, and the five New Horizons protagonists are Origin's five starter admirals.
**[F]** https://uwo.inven.co.kr/db/character/ · https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보

### 6.2 Uncharted Waters Online (2005–)

- The **player** has three jobs' levels (adventure / trade / maritime) and ~100 ranked **skills**:
  favoured skills rank to 15 at half the proficiency cost, unfavoured cap at 10, one "expert" skill
  per job reaches 16 (17 with items); examples — Sail Handling (+1 % speed per 2 ranks), Surveying,
  Accounts (haggling), Repair, Gunnery, Accuracy (+2 % hit per rank), Ballistics (+1.5 % per rank),
  Evasion (−2 % per rank), Steering, Rowing, Management, Navigation, Survival, Plunder, Mine Laying…
  Learning costs ducats at a guild master (3,000 for Fishing; 25,000 for Beginning Shipbuilding;
  300,000 for Management). **[F]** https://uwoelnavegante.wordpress.com/maritimer-guide-by-ogplanet/ ·
  search extracts of https://unchartedwaters.fandom.com/wiki/Profession_and_Skills ·
  https://unchartedwaters.fandom.com/wiki/Management_skill (fandom blocked direct fetch, 402)
- **Aides**: up to 5 NPC companions (1st at job level 20, 2nd at 40, then by quarters rank); each holds
  one **duty** — Navigator, Lookout, Paymaster, Storekeeper, Lieutenant, Surgeon — that decides which
  of the aide's three levels gains daily EXP (e.g. Navigation 100 % adventure, Surgeon 50/50
  maritime/trade); traits grow with sea days and food; **trust 50** lets an aide captain a second ship;
  some aide skills give the player +1 to the same skill. **[F]**
  https://uwoelnavegante.wordpress.com/2016/07/29/basic-information-about-aides/ ·
  https://uwo-hq.blogspot.com/2019/01/a-complete-guide-to-aides.html

Origin kept the *aide* idea (many companions with a seat each, levelled by activity, duties as rooms),
dropped the *player skill ladder* (the Admiral has a handful of fixed skills), and turned "which aide
has which duty" into "which mate sits in which cabin".

---

## 7. byeharu-voyage against Origin — matches and divergences

Verified on this checkout (branch `osn-research-uwo-skills` off `ee64e77`).

| topic | Origin | ours (file:line) | verdict |
|---|---|---|---|
| **People vocabulary** | mate (항해사) = everyone; admiral = the player | `public.officers` catalogue + `public.player_officers` signing (`supabase/migrations/20260818000015_an_officer_signs_on.sql:56-89`); the owner says "captains" | match in shape; our word is captain |
| **Where captains come from** | inn roster per port, chance, language-weighted | `world.inn_present(officer, port, day)` is a pure function weighted to nation/region/culture, S rarer (`20260818000073_who_is_drinking_here_today.sql` header); turns over every 15 real min (`20260818000119`) | **match** — ours is stricter (derived, un-rerollable) |
| **Hire cost / friendship / cooldowns** | ducats negotiation by friendship, gem instant, 10 min–6 h cooldowns by grade | `cmd.hire_officer` (0015:170, gated to the inn room by 0073) debits `wage_ducats` once; no friendship, no cooldown | diverges — simpler; we have no gems, so no second path. A failed-negotiation cooldown by grade is a cheap, honest import if haggling for captains is wanted |
| **Grades** | C/B/A/S birth grade + SS by training; grade only prices growth | owner row 61: S/A/B/C with **5/4/3/2 skill slots and 10/8/6/4 known skills**, promotable (`docs/OWNER_REQUESTS.md:137`, `docs/DESIGN_V1.md:383-410`); `officers` has **no grade column yet** | diverge on purpose — Origin's grade does *not* cap slots (4 for everyone + transcendence); the owner's design ties slots to grade. Keep ours; note Origin had to let C climb to SS to make Cs matter |
| **Positions** | one Captain's Cabin per ship + typed cabins; 50 % penalty off-focus; class-wide cabin changes at the yard | officers are posted to a **fleet** (`player_officers.fleet_id`); `fleet_officer_bonus` folds per fleet; cabins are planned per ship (`docs/DESIGN_V1.md:442-446`, SHIPS_AND_GEAR S1 "3 captain slots") | diverge today; the plan converges. Origin's split — **combat per ship, trade/adventure per fleet** — is the thing to copy: it is why Origin lets trade officers sit anywhere |
| **Stats** | 12 expertise + 3 levels; no personal attributes | `officers.specialty ∈ {NAVIGATOR, QUARTERMASTER, SURGEON, PURSER}` + one `bonus_pct ≤ 25` (`0015:60-61`), per-fleet cap 25 % (`0015:50-52`); owner's row 66 makes the four jobs *skills a captain may know* and adds role × specialisation | diverge — ours is one number per officer. Origin's 8 fleet expertise map one-to-one onto our rule readers: Scouting→`fleet_speed`, Supply→provision burn (0017), Purchasing/Sales→`spread_effective`/`world.quote`, Negotiation→haggle odds (`world.haggle_state`), Trade→price visibility, Support→`raid_crew_lost` (0027) |
| **Levels / XP** | mate LV capped at Company LV; three levels by activity; EXP potions; new mates join at Company LV | `officer_xp` **per signing**, miles/1,000 + 5/15 per pirate (`0127:173-194`), `captain_level_pct_per_level` 2 % under the cap; dark (`levels_bite` false) | diverge on cap (ours is uncapped by company) and on reset-on-dismiss (Origin never resets). Origin's "100 % EXP in the captain's cabin, 50 % elsewhere" is a cabin-era idea worth keeping in mind |
| **Promotion / awakening** | 4 promotions by level 30/50/70/90, per-mate contracts + astrolabes + certificates; training C→SS; transcendence +slot +20 LV/stage | owner row 61: promotion by **levels + items earned from trading/combat/exploration** ("like the yard but different items") — design only | match in intent; Origin's lesson: per-mate contracts were the hated pay wall and were deleted for B/C in 2026 — make the items **generic per grade**, never per captain |
| **Loyalty** | 4 h / 24 h timers, decays at sea, slacking | none; DESIGN_RESEARCH D4 dropped it deliberately | diverge on purpose. Origin's *Homesickness / Anxiety* fleet states (relieved by Counselor job effects) are the honest version of the owner's "homesick captains" (`docs/DESIGN_V1.md:425-440`) |
| **Skills** | combat-only actives (LV 1–10) + passive effects (4 slots); no player tree | **house** skills: 92 rows, 8 groups, I–V, real-time queue (`20260818000131`), effects + requirements dark (`20260818000133`); officers do not train | diverge by design (EVE, the owner's word). Origin confirms there is **no** skill the player studies; the nearest is Company Research 70 pts/branch |
| **Skill gating of ships / seas** | none on captains since Dec 2024; seas by hull stats + Company LV + language | hulls by line hull skills (`SHIPS_AND_SKILLS.md` §4.4), regions by exploration level, legs by NAVIGATION (`0107`) | ours gates on the *house*, Origin gated on the *captain* and removed it. Keep gating on the house — it is the EVE shape and avoids Origin's homogenisation complaint |
| **Languages** | 36, LV 1–5, carried by mates, max not sum, hard port gate | nothing | gap. A derived "interpreter" captain trait that unlocks a port's full services is the cleanest non-combat reason to carry a non-trade captain; it fits `officers.nation_id` as it exists |
| **Effects numbers** | 2.5–15 % per effect, 20–40 % caps, one category each | `bonus_pct ≤ 25`, fleet cap 25 % (`0015`), skill effects 2–5 %/level (`SHIPS_AND_SKILLS.md` §5.2) | match in magnitude; Origin's per-category trade effects (Jewelry Discount, Food Sales Expert) are what row 66's "jewellery trader" asks for |
| **Set bonuses** | mate collections (+0.1 %/tier), guild effects | 11 Country gear sets, 2/4-piece (`SHIPS_AND_SKILLS.md` §6.7) | ours is richer; Origin has no gear sets on people |
| **Economy** | three currencies + mileage + deeds; red-gem admirals; gacha removed | ducats only | diverge on purpose (DESIGN_RESEARCH D3) |

Three concrete recommendations that fall out, offered for the owner's decision and not acted on here:

1. **Scope split first.** When cabins land (`DESIGN_V1` §7.3), make combat-type captain effects
   *per ship* and trade/adventure effects *per fleet*, exactly as Origin does; it removes the "which
   ship does my purser sit on" question and keeps `fleet_officer_bonus` as the one fleet reader.
2. **Promotion items generic per grade and per focus** (astrolabe-like), never per captain. Origin's
   per-mate contracts were its single most resented wall and were walked back twice.
3. **Grade should not cap a captain's ceiling** if the owner wants C captains to stay relevant;
   Origin's answer (training C→SS with more training points for lower births) is the one proven fix.
   If the owner keeps slots-by-grade (row 61), expect every C to be dismissed on day one.

---

## 8. Gaps — what could not be sourced

1. **A full, current skill list** (every naval combat skill with its 10-level table). The Inven DB
   holds it per mate (`uwo.inven.co.kr/db/character/<id>`), not as one page; only one mate's two
   skills were read in full. No official skill compendium exists.
2. **A full job → job-effects table.** The gamemeca chart is an image; the official pages list jobs
   nowhere. The ~45 job names come from Inven's filter only.
3. **Mate EXP curve** (points per level) and the exact level → promotion gates after the Sep 2025
   relaxation; only the 2023 gates (30/50/70/90) are published.
4. **Loyalty numbers** (gain per conversation, decay per sailing day, the slacking threshold) — none
   published anywhere reached.
5. **Current promotion material counts** — the only tables are fan tables from 2023; the Aug 2026
   notice changed training times and task rewards but printed no new counts.
6. **The cabin rate for Old Rudder/Deck** — one fan page says 70 %, another 80 %.
7. **Expertise → effect formulas** (how 73 Artillery becomes +x % attack; what "Fleet Expertise LV
   30 = 650" multiplies). Only the Purchasing +5 %/level and Supply +300 crew rules are official.
8. **UW2 mate mechanics** — koei.fandom.com (402) and GameFAQs could not be fetched; the UWNH post
   positions are from a fan model page and a walkthrough, shape only.
9. **UW Online adventure / trade skill lists** — unchartedwaters.fandom.com returned 402 and the
   Papaya wiki 307/429; only the maritime list was read.
10. Namu Wiki's `/게임 관련 정보` page is ~197 k characters; sections 4.1–4.3 were read in part
    (names, jobs, unlock notes), not the full per-mate tables.

---

## 9. Source index

Official (LINE Games) **[O]**
- Mate guide (EN) https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447
- Mate guide (KR) https://guide.floor.line.games/UWO/ko_KR/detail/1167031174330200447
- Mate Details (skills, effects, expertise) https://guide.floor.line.games/UWO/en_US/detail/1167031313761600028
- How to Use Ships (cabins, parts, shipyard) https://guide.floor.line.games/UWO/en_US/detail/1111111111111111114
- Combat Guide (skills, quick skills, orders) https://guide.floor.line.games/UWO/en_US/detail/1111111111111111113
- Language guide https://guide.floor.line.games/UWO/en_US/detail/1167031198850700918
- What is an Admiral? https://guide.floor.line.games/UWO/en_US/detail/1111111111111111111
- Water conditions https://guide.floor.line.games/UWO/en_US/detail/1167031265223600324
- Dispatch (KR) https://guide.floor.line.games/UWO/ko_KR/detail/1167884807499300699
- Potential effect values https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1726144278318014479
- Early guide: inn cooldowns https://uwo.floor.line.games/us/bbsCmn/detail/1653441748014014523
- Admiral intro: João Franco https://uwo.floor.line.games/us/bbsCmn/detail/1653439283181013520
- Global improvements / gacha removal (Oct 2024) https://uwo.floor.line.games/us/bbsCmn/detail/1729660250450018684
- Season system, operation conditions, Build LV (Dec 2024) https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473
- Dec 6 2024 patch (weekly shop, contracts) https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1733294207241009126
- Transcendence (KR notice) https://uwo.floor.line.games/kr/bbsCmn/detail/1727430459384024809
- Company Research revamp (Feb 2026) https://uwo.floor.line.games/us/bbsCmn/detail/1772088386191015429
- Sep 2025 update (effects relaxed, expertise rework, kits) https://uwo.floor.line.games/us/bbsCmn/detail/1757321858140028621
- Sep 25 2025 patch (2nd transcendence, effect replacements) https://uwo.floor.line.games/us/bbsCmn/detail/1758517759446022860
- Dec 17 2025 patch (caps 105/145) https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1765784705114026646
- Jan 15 2026 patch https://uwo.floor.line.games/us/bbsCmn/detail/1768290895968000477
- May 13 2026 patch (caps 110/150, Purchasing +5 %) https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1778492589963011795
- Jun 2026 KR walkthrough notice (B/C contracts deleted) https://uwo.floor.line.games/kr/bbs/community/walkthrough_kr/1/detail/1780911845784024615
- Aug 10 2026 update (Stage 3, caps 115/175, training times) https://uwo.floor.line.games/us/bbsCmn/detail/1786095022818002471

Fan / press **[F]**
- Namu Wiki, 게임 관련 정보 https://namu.wiki/w/대항해시대%20오리진/게임%20관련%20정보
- Namu Wiki, 평가 https://namu.wiki/w/대항해시대%20오리진/평가
- Inven mate DB https://uwo.inven.co.kr/db/character/ · one sheet https://uwo.inven.co.kr/db/character/chabbb058
- Inven material tally https://www.inven.co.kr/board/uwo/5714/1182
- Steam guide: Promotions and training https://steamcommunity.com/sharedfiles/filedetails/?id=3075729949
- Steam guide: Ships and shipbuilding (cabins) https://steamcommunity.com/sharedfiles/filedetails/?id=2955998460
- Steam guide: Red gem admirals https://steamcommunity.com/sharedfiles/filedetails/?id=3415268645
- Steam: 9 tips https://steamcommunity.com/app/1574360/discussions/0/3781373416977477305/
- Steam: pay wall thread https://steamcommunity.com/app/1574360/discussions/0/3781373416983732223/
- Steam: no more gacha https://steamcommunity.com/app/1574360/discussions/0/4630356482652668850/
- Steam: newbie AMA https://steamcommunity.com/app/1574360/discussions/0/4692280123603369124/
- MMORPG.com business model https://forums.mmorpg.com/discussion/500581/the-business-model-for-uncharted-waters-origin
- MassivelyOP launch https://massivelyop.com/2023/03/08/uncharted-waters-origin-debuts-on-pc-and-mobile-devices-runs-afoul-of-gamers-thanks-to-gacha-monetization/
- DC gallery cabin placement https://gall.dcinside.com/mgallery/board/view/?id=bigtimeofnavigation&no=349152
- gamemeca job chart https://trees.gamemeca.com/view.php?gid=1685443 · growth https://trees.gamemeca.com/view.php?gid=1684437
- byline (transcendence stage 2) https://byline.network/2025/09/26-493/
- invenglobal (part engraving) https://www.invenglobal.com/articles/25770/uncharted-waters-origin-adds-two-s-grade-mates
- Japanese: oyururi mates https://oyururi.info/daikoukaizidai-origin-koukaishi/ · khitc cabins https://www.khitc.com/wp/ddon/origin5/ · 4Gamer https://www.4gamer.net/games/525/G052550/20230208100/ · Famitsu https://www.famitsu.com/news/202303/10292184.html
- UW2/UWNH: https://rpggamers.com/walkthrough/uncharted-waters-2-new-horizons · https://listed.to/@Valtarien/60866/uwnh-mates
- UWO Online: https://uwoelnavegante.wordpress.com/maritimer-guide-by-ogplanet/ · https://uwoelnavegante.wordpress.com/2016/07/29/basic-information-about-aides/ · https://uwo-hq.blogspot.com/2019/01/a-complete-guide-to-aides.html

Blocked from this environment: koei.fandom.com, unchartedwaters.fandom.com (HTTP 402), wiki.papayaplay.com (307/429), namu.wiki `/항해사` (404 — that sub-page does not exist; the content is under `/게임 관련 정보`).
