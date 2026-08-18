# DESIGN_RESEARCH.md — Sourced notes for byeharu-voyage

Research date: **2026-08-18**. Researcher: Claude (Opus 5).
Purpose: ground `docs/DESIGN.md` in what *Uncharted Waters Origin* (대항해시대 오리진, LINE Games / Motif)
and its ancestors actually do, so the new game copies deliberately rather than by vibe.

## 0. Source quality legend

Every claim below carries a marker:

| Marker | Meaning |
|---|---|
| **[P]** | **Primary, directly fetched.** I retrieved the publisher's own page and read it. |
| **[S]** | **Secondary, search-snippet only.** The page blocked direct fetch (HTTP 402/403); I have the search engine's extract, not the page. Treat as strong-but-unconfirmed. |
| **[U]** | **Unverified.** I could not confirm this at all. Stated as a gap, never as fact. |

Fandom wikis (`unchartedwaters.fandom.com`, `koei.fandom.com`), Grokipedia and GameFAQs all refused
direct fetch from this environment (402 / 403). Anything sourced from them is **[S]**.

---

## 1. Uncharted Waters Origin — the reference game

### 1.1 What it is

- 16th-century age-of-sail game, marking the series' 30th anniversary; mobile + PC (Steam), free-to-play. **[S]**
  — search extract of the Steam store page and Google Play listing; the Steam page itself is behind an
  age gate and returned only the gate to me.
- Advertised world scale: **8 national powers, ~200 ports, ~60 villages, 300+ battlegrounds, 20+ weather types.** **[S]**
  (Publisher marketing copy, via search extract. Useful as a *scale target*, not as verified content.)

### 1.2 The Company = the player's account and org unit **[P]**

Source: [Fleet Basics: The Company](https://guide.floor.line.games/UWO/en_US/detail/1111111111111111115)

- A **Company** is the account. It contains the **Admiral** (the player's avatar/commander), the **Mates**
  (officers) and the **Fleet** of ships.
- **Company LV directly gates fleet size**: "A high Company LV means your Admiral can command more
  ships, which means your Fleet grows in number." The guide does *not* publish the LV→ship-count table. **[U]**
- Company LV also grants **Energy**, spent on the Admiral's Order and on village exploration.
- A designated **Flagship** exists (referenced via the "Old Aide's Cabin in your Flagship").
- Combat uses **Front / Middle / Back line** ship placement with per-formation bonuses.

**Takeaway for us:** the "Company" framing — one account = one trading house, with commander + officers +
ships — is exactly the right container for a text game. Fleet capacity as a level-gated number is a clean,
server-computable growth lever.

### 1.3 Ships **[P]**

Sources: [Ships](https://guide.floor.line.games/UWO/en_US/detail/1167022785491300092),
[Ship Details](https://guide.floor.line.games/UWO/en_US/detail/1167031287203500028)

- Three families: **Western** (Mediterranean / North Sea / Black Sea), **Eastern** (China, India,
  Polynesia, Joseon, Japan), **Special** (original + collaboration designs).
- **Grades 1–23.** Every ship has one of three specialisations: **Adventure / Trade / Combat**.
  Named examples: Grade 1 — Tallette (Trade), Barque (Adventure), Hansa Cog (Combat);
  Grade 20 — La Royale, Vaisseau, Clipper; Grade 23 — Ironsides, Thermopylae (Trade), La Mort.
- Specialisation shapes stats: "Ships specialising in Adventure are faster than other ships of the same
  grade, and ships specialising in Trade have higher Load Capacities."
- **Stat vocabulary** (names confirmed; **numeric values are not published** in the guide **[U]**):
  - `Life` — decays slowly while sailing; at 0 the ship suffers **−50% to all stats**.
  - `Durability` — combat/disaster damage. **If the Flagship's Durability hits 0, the Fleet becomes
    "Unable to Sail."**
  - `Load` — total cargo space.
  - `Crew` — falls through naval combat and disasters.
  - `Ice Breaking`, `Momentum` (obstacles e.g. seaweed), `Seaworthiness` (endures Rogue Waves).
  - `Rowing` — oared ships get more speed from more crew.
  - `Vertical Sail` (crosswind speed) vs `Horizontal Sail` (tailwind speed).
  - Artillery / Melee / Ram — Strength and Defense pairs. `Repair Recovery`, `Medicine Recovery`.
- **Shipbuilding** needs Blueprints + parts (Keels, Wood, Gunports) + Ducats. A **Build Succession**
  system cuts build time by 50% and inherits stats from a scrapped lower-grade ship.
- Per the later rebalance note (§1.9), **Build Level now reduces build time by up to 50% instead of
  acting as a hard requirement.**

**Takeaway for us:** the *shape* of the stat block is excellent and fully text-renderable. The
wind-direction split (vertical vs horizontal sail) is the single best idea here: it makes wind a
**number that multiplies a speed**, not an animation. We take it. We drop everything under the
Artillery/Melee/Ram tree except a single aggregated defensive number.

### 1.4 Mates (officers) **[P]**

Source: [Mate](https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447)

- Mates have one of three **Jobs**: Adventure, Trade, Combat. **Grades C → S**, driving hire cost and
  growth cost.
- **Skills** = active (Naval Combat Skills, Duel Skills). **Effects** = passive, and *natural effects can
  be debuffs*.
- **Expertise** splits two ways:
  - **Ship Expertise**: Artillery, Ramming, Support, Melee.
  - **Fleet Expertise**: Adventure (Nature, Aesthetics, Scouting, Supply) and Trade (Purchasing, Sales,
    Negotiation, Trade).
- **Languages** gate access to other nations' cities; higher Language LV improves trade and negotiation.
- **Hiring** happens at a city **Inn**, by Hire (Blue Gems), Negotiation (Ducats, scaled by friendship —
  mates start at **60 Loyalty**), or Gift/Sponsor.
- **Cabin assignment**: a mate placed in a **compatible cabin** gives full benefit; an incompatible
  cabin **halves their Expertise (−50%)**.
- **Loyalty**: conversation raises one mate's loyalty every **4 hours**; a speech raises all mates'
  every **24 hours**. Loyalty **decreases while sailing**. A "slacking" mate cannot be assigned.
- **Promotion** costs materials (Contracts, Astrolabes, Certificates) and raises expertise / effect capacity.

**Takeaway for us:** Fleet Expertise (Purchasing / Sales / Negotiation / Supply / Scouting) is a
perfect fit — each is literally a coefficient in a server formula. The 4h/24h loyalty timers are a
retention treadmill and we drop them. The Blue-Gem hire path is monetisation and we drop it.

### 1.5 Trade **[P]**

Source: [How to Trade](https://guide.floor.line.games/UWO/en_US/detail/1167031103747200277)

- Core loop stated plainly: "buying Trade Goods at a low price, travelling to a city that needs the Trade
  Goods, and selling them at a high price." Rewards: **Ducats, Trade Fame, Trade EXP.**
- **Prices are shown as a percentage relative to nearby cities** — this is the key UI decision:
  - `< 100%` = cheaper than neighbours → buy.
  - `> 100%` = dearer than neighbours → sell.
  - `< 90%` → auto-listed on the **Recommended Purchase List**.
  - `> 110%` → auto-listed on the **Recommended Sell List**.
- **7-day price graphs** with min/max markers.
- Price modifiers: **Language Level** (purchase discount / sale surcharge), **Fleet Expertise**,
  **season and culture** (e.g. alcohol unavailable in Islamic-region ports), and **taxes** (vary by
  nation; reduced by Tax Permits, Diplomacy, Admiral Titles, city traits, Expertise). Taxes begin after
  the "Amateur Benefit" newbie period ends.
- **Trade events** move prices: *Soaring / Plunging* (one good), *Trending / Overflowing* (a whole
  category), *Booming* (unpopular items). Triggered by Mates or by anchoring.
- **Specialties**: region-exclusive goods hold stable prices.
- **Negotiation events** fire on a buy/sell depending on the assigned Mates' Jobs and Expertise; high
  Negotiation LV raises both the event chance and the discount/surcharge on success.

**Takeaway for us:** the **percent-of-neighbours display** is the single most valuable UI import in this
whole document. It turns a market into a *readable table* — exactly what a text game needs. The
`<90% buy / >110% sell` auto-lists are a free onboarding tutorial. We take all of it.

### 1.6 City investment **[P]**

Source: [How to Invest](https://guide.floor.line.games/UWO/en_US/detail/1167031186467500250)

- Investment happens at a city's **Bureau** and raises the city's **Development LV**. High Development LV
  improves the **Shipyard, Market and Item Shop stock**, and raises **crew recruitment capacity at the Inn**.
- **Three investment tracks: Industry, Commerce, Military.**
- **Minimum investment: 50,000 Ducats.** Players see a preview of the Development LV gain before committing.
- **Mayor**: the player who invests most in a city that week becomes **Mayor of the week**; ties break to
  whoever invested **earlier**. The Mayor **sets the tax rate** on the city's Market goods and Shipyard
  builds; tax can be adjusted **once per day** per city/nation.
- **Reputation**: an investment of **≥100k Ducats at once** moves your Company's reputation with that
  nation — up for your home nation, down for an enemy's.
- **National control**: Free Ports, Allied Ports and Occupied Ports belong to whichever nation holds the
  **highest Investment Score**. National Power = total city count + summed Development LV across all
  three tracks.
- **Area-occupation bonuses**:
  - **50–99% occupation**: +1 sailing speed, extra trade goods, **−5% ship build time**, higher capture rate.
  - **100% monopoly**: +2 sailing speed, extra trade goods, **−10% build time**, higher capture rate,
    strike prevention.
- **Remote investment** is available to Mayors once weekly (Mon–Sat).

**Takeaway for us:** this is a fully text-native system with zero graphics dependency and it is the
strongest multiplayer hook in the game — a shared number that many players push on. We take it nearly
whole. The one thing we change: a *player-set tax rate* is a griefing surface, so we cap and band it (§3).

### 1.7 Investment seasons and the anti-snowball rebalance **[P]**

Source: [Season System for Investment and Rebalancing of Shipbuilding and Trade](https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473)

This note is the most useful *design-lessons* document in the whole set, because it is the developers
admitting what broke:

- **Investment Seasons last 3 months.** At Season 1 all Investment Points were refunded as Ducats; from
  **Season 2 onward Investment Points are NOT refunded** — the ladder resets.
- Motivation stated: roughly **40 admirals were exceeding 50 billion Ducats of weekly trade profit** across
  servers, and the team concluded the old design — where "Ducats makes additional Ducats" — had to be
  restructured.
- Trade rebalance goal: "redistribute excessively high values of certain cities to other cities" and
  reassign trade goods across locations.
- Shipbuilding changes: non-monopolising guilds pay **Ducats (3× the guild cost)** instead of Blue Gems;
  monopolising guilds get **30% faster builds** and tradeable ships; **Build Level → up to 50% time
  reduction** rather than a gate; all ships now need only Operation Condition LV 1.
- **Top-50 investor dividends raised 8×–12×**, plus a seasonal currency buying unique mates, appellations
  and flag-type ship parts.

**Takeaway for us — this is a warning label.** An investment economy with unbounded compounding produces
a runaway top 40 and forces a retrofitted season wipe. We design the season reset **in from day one**
rather than bolting it on (§H of DESIGN.md).

### 1.8 Admiral titles, Fame and rank **[P]**

Source: [What is an Admiral?](https://guide.floor.line.games/UWO/en_US/detail/1111111111111111111)

- **11 title levels (LV 1–11).** (One starting Admiral, Otto Baynes, begins at Title LV 3 for story reasons.)
- **Three Fame types** — Adventure, Trade, Combat. **Title advancement requires all three to be raised
  reasonably evenly**: "your three Fame types must be equally invested in."
- Promotion runs through **Royal Orders** issued by your nation's palace as Fame grows.
- **Tax reduction by title level**, applying in ports where your nation holds **≥10% share**:
  LV1–2 → 0–1%, LV3–4 → 2%, LV5–7 → 3%, LV8–10 → 4%, **LV11 → 5%**.
  (A search snippet also reported "0% at level 1, 5% at level 11" — consistent. **[S]**)
- Higher titles unlock Admirals' Chronicles, ships, builds and Black Market items.
- At **LV10+**, neutral NPCs may challenge the player to combat.

### 1.9 The three growth pillars **[P]**

Source: [Growing Your Fleet: Adventure, Trade, Combat](https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354)

- **Adventure** EXP/Fame: Adventure Union Requests; discovering/collecting architecture, fauna, flora,
  artifacts; **docking in cities, scaled by distance travelled**; reporting discoveries to Collectors.
  Daily-task reward currency: **ship masts**.
- **Trade** EXP/Fame: Trade Union Requests; profitable transactions; bonus EXP for large profits and for
  specialty goods; **Trade Points, with a random reward triggering at 1,000 points**.
  Daily-task reward currency: **wood**.
- **Combat** EXP/Fame: Combat Union Requests; naval victories; bonus for beating stronger opponents;
  looting goods/gear/materials. Daily-task reward currency: **Gun Ports**.
  Combat itself is **turn-based on hexagonal tiles**.
- All three compete for the **same shared pool of crew supplies and Ducats**, which is what forces
  specialisation.

**Takeaway for us:** "**docking in cities, scaled by distance travelled**" is a gift — it is a pure
server-side formula that rewards the exact behaviour we want (long voyages) with zero content authoring.
We take it as the backbone of the Adventure axis. The hex-tile combat is precisely what killed the
previous byeharu and is discarded entirely.

### 1.10 Search, exploration and discovery **[P]**

Sources: [Voyage_Search and Exploration](https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1653444258130018779),
[Journal](https://guide.floor.line.games/UWO/en_US/detail/1166988257148200215) (title/section list via search **[S]**)

- **Search at sea** consumes one **Telescope** (bought at a port item shop) to scan a suspicious area;
  a yellow telescope icon marks the find.
- **Exploration ashore** consumes an **Exploration Bedroll**, in **Exploration Mode** or **Gathering
  Mode**. Both burn **food, water and crew**. Each exploration day rolls a random event (combat /
  observation / gathering) with success or failure; **events are skippable**; a results screen reports
  actual resource cost and rewards.
- Requirements vary by region and depend on mate expertise, skills, effects and commands; consumable
  tools can temporarily top up an inadequate stat.
- Finds enter an **Encyclopedia / Journal**, split into **Discoveries** (Nature, Animals, Plants,
  Architecture, Artifacts, Treasures, Fishing), **Blueprints**, and **Adventure Notes**. **[S]**

**Takeaway for us:** "each exploration day rolls an event, events are skippable, and you get a results
screen listing costs and rewards" **is already a text game**. It is literally an after-action report.
We adopt this exact shape and extend it to cover hazards and piracy — see §3.

### 1.11 Voyage and supply handling **[P]**

Source: [Voyage_How to Set Sail](https://uwo.floor.line.games/us/bbsCmn/detail/1653443788526014645)

- Voyages start at a port's **Harbor**; navigation is manual or **automatic** by picking the destination
  harbour on the mini-map.
- **"Food and Water are consumed every day during a voyage."**
- **Materials** are carried for emergency repairs after combat or disaster. **Ammunition** scales naval damage.
- A **Set Ratio function** auto-stocks supplies per ship characteristics.
- **Crew** are recruited at a port up to a per-port maximum; exceeding it costs more ("urgent recruitment").
- Damaged **Durability** is repaired for Ducats; **a ship at 0 Durability cannot sail.**
- **Gap:** this page does *not* publish sailing speed maths, wind/current formulas, distance calculation,
  fatigue rules, or whether voyages progress offline. **[U]** I could not verify UWO Origin's offline
  sailing behaviour from any primary source.

### 1.12 Guilds **[P]**

Source: [Guild System](https://guide.floor.line.games/UWO/en_US/detail/1166995021094200118)

- **30 members at Guild LV1 → 75 at LV11.**
- Benefits: tax reduction at monopolised cities' markets and shipyards, extra trade goods, exclusive
  items and improved ships, passive Adventure/Trade/Combat effects.
- A guild that invests most in a city becomes the **Monopolising Guild** — special trade goods, improved
  ships, unique cabin options.
- **Contribution points, 8 categories, with caps**: login **100/day**, combat **≤1,000**, trading
  **≤1,000**, exploration **≤1,000**, crafting **≤500**, investment **≤1,000**, requests **≤500**,
  combining **≤500**. Contribution buys guild currency for blueprints and materials.

**Takeaway for us:** the **capped per-category contribution table** is a clean anti-whale pattern worth
stealing outright, and it is trivially implementable as a ledger aggregate.

### 1.13 Monetisation shape **[S]**

Search extracts of Steam Community discussion threads and MMORPG.com forums report:

- Originally two gachas — **superior mate** and **superior item**, each **4,000 red gems per 10-pull**;
  **Admiral Memoirs** as a **5,000 red gem season pass**.
- Two currencies: **Blue Gems** (softer/earnable) and **Red Gems** (paid).
- Heavy early criticism: the global build shipped loot boxes where the Korean server had used a
  "buy to progress faster" model; mate rank-up contracts were widely seen as pay-gated.
- **The gacha was later removed** (reported as the November 6 update; existing chests withdrawn in a
  January update), and players reported the power gap narrowing afterwards.

**Takeaway for us:** byeharu-voyage has **no monetisation at all** in the planned scope. The relevant
lesson is structural, not commercial: **do not build a system whose balance depends on a paid power
axis**, because when you remove it you must rebalance everything it touched.

---

## 2. The ancestors — Uncharted Waters I / II (New Horizons) and Uncharted Waters Online

### 2.1 Uncharted Waters II / New Horizons **[S]**

Source: search extract of [Koei Wiki: Uncharted Waters: New Horizons](https://koei.fandom.com/wiki/Uncharted_Waters:_New_Horizons)
and [Koei Wiki: Uncharted Waters (series)](https://koei.fandom.com/wiki/Uncharted_Waters_(series)) — **direct
fetch blocked (HTTP 402); snippet only.**

- **Six protagonists**, each with their own play style and objective.
- **Three fames**: **explorer** (discovering world wonders and remote ports, selling maps),
  **piracy** (defeating enemy fleets), **trade** (investing large sums into ports, fulfilling fetch quests).
  Each character must build up *their* fame to advance their story.
- Ship roles: "adventure ships are the fastest, merchant ships have the most cargo space, maritime ships
  have the most cannons, armor and crew."
- A **Shipbuilding skill** allows building/modifying ships; shipyards customise inventory, active members
  and weaponry.
- **Wind velocity and water currents have a toggleable display** in console versions. "Wind currents,
  weather conditions and supplies affect sailing; failing to keep an eye on these before reaching a port
  may prematurely end the game."
- **Failure states**: the game ends early if the character dies in battle, **runs out of provisions**, or
  reaches old age.

**The load-bearing point:** in UW2, *running out of provisions is a game-over*. Supply is not decoration —
it is the primary tension of an age-of-sail game, and it is entirely numeric. This is the mechanic that
lets a text game be *tense* without a single pixel of combat.

### 2.2 Uncharted Waters Online **[P] for the forum primer, [S] for the wiki numbers**

Source (fetched): [MMORPG.com — Uncharted Waters Online: The Basics](https://forums.mmorpg.com/discussion/366992/uncharted-waters-online-the-basics)

- Three careers: **Adventurer**, **Merchant**, **Maritimer**, with a matching **Fame** per career. Fame
  unlocks **port permits**, higher-tier quests, and equipment with minimum requirements.
- **Three parallel levels** (adventure / trade / maritime, capped 65/65/65 at time of writing). Skills
  rank **0–16** depending on job favourability.
- Ship classes follow the same three-way split (speed / cargo / guns+armour+crew). Players start in a
  weak "bacra".
- Merchant play splits into **trading** and **production** (clothes, food, cannons, ship parts, alchemy).
- **Port permits** gate access to seas progressively: Europe → Africa → Caribbean → India → beyond.
- **Court ranks** rise via **port investment, discoveries, naval victories** and large PvP "Epic Sea Feuds".

Supply numbers, from search extracts of [unchartedwaters.fandom.com/wiki/Sailors](https://unchartedwaters.fandom.com/wiki/Sailors)
and [.../Disasters](https://unchartedwaters.fandom.com/wiki/Disasters) — **direct fetch blocked (HTTP 402);
snippet only, treat the constants as indicative** **[S]**:

- **Each sailor consumes 0.1 barrel of water, 0.1 barrel of food, and 1 coin per day.** A 10-crew ship
  therefore burns 1 food + 1 water + 10 coin per day.
- Ships have a **maximum** and a **recommended** sailor count, with recommended typically **half of
  maximum**; a ship can sail with one sailor but needs its "required" percentage — which rises with ship
  quality and type — to operate at full capacity.
- **Fatigue** rises from sailing under bad status effects, from unmet upkeep, and fastest from melee.
- Running out of food or water **reduces loyalty, raises fatigue, and eventually kills crew**.
  **Malnutrition** (underfeeding) reduces loyalty and can become **scurvy** if untreated. Unmet upkeep
  can cause **mutiny**.
- A **Frugality** skill reduces food and water consumption and sailor hiring cost.

**Takeaway for us:** the 0.1/0.1/1-per-crew-per-day triple is the cleanest supply model in the genre and
we adopt its *shape* directly. We retune the *magnitude* (see DESIGN.md §C.5) because our voyages are
compressed and a literal 0.1 barrel/crew/day would make an Indies run physically impossible to provision —
which, historically, it very nearly was.

---

## 3. What we take, what we drop, and why

Judged strictly against the owner's eight constraints.

### 3.1 TAKE

| # | Import | Source | Why it survives the constraints |
|---|---|---|---|
| T1 | **Company / Admiral / Mates / Fleet** as the org unit | §1.2 **[P]** | Pure nouns in a table. Satisfies C5 (fleets, plural) and gives a natural home for rank. |
| T2 | **Three-axis Fame — Trade / Adventure / Naval** with titles gated on *balanced* growth | §1.8, §2.1, §2.2 **[P]/[S]** | C7 wants rank first-class. Three ledgered counters are computable server-side (C8). Balance-gating stops single-axis grinding. |
| T3 | **Price shown as % of neighbouring ports**, with auto `<90% buy` / `>110% sell` lists | §1.5 **[P]** | The killer text-UI idea. A market becomes a sortable table. Directly serves C1. |
| T4 | **7-day price history** | §1.5 **[P]** | A sparkline is renderable as text (`▁▂▄█▆▃▂`) and rewards reading over clicking. |
| T5 | **City investment → Development LV, three tracks, nation share, mayor** | §1.6 **[P]** | C7. Entirely numeric, entirely multiplayer, zero graphics. |
| T6 | **Investment seasons with a hard reset** | §1.7 **[P]** | Designed in from day one instead of retrofitted after a runaway top-40 forced it. |
| T7 | **Capped per-category contribution ledger** | §1.12 **[P]** | Best anti-snowball pattern found; a trivial SQL aggregate. |
| T8 | **Food + water + wages consumed per crew per day; running out is a real failure** | §1.11, §2.1, §2.2 **[P]/[S]** | This is the *tension source* that replaces combat. Numbers only. Satisfies C1 and C4 simultaneously. |
| T9 | **Wind as a speed multiplier split by point of sail** (vertical vs horizontal sail) | §1.3 **[P]** | Wind becomes a coefficient in the ETA formula — an *output* on the map, never an input. Serves C3. |
| T10 | **Exploration = a day-by-day event roll producing a results screen of costs and rewards** | §1.10 **[P]** | Already a written after-action report. This is the template for *all* our at-sea event resolution, including hazards. Serves C4. |
| T11 | **Fame for docking, scaled by distance sailed** | §1.9 **[P]** | Free content: rewards long voyages with a formula, no authoring. |
| T12 | **Fleet Expertise coefficients — Purchasing / Sales / Negotiation / Supply / Scouting** | §1.4 **[P]** | Each is literally a multiplier in a server formula, and each is one line in an officer table. |
| T13 | **Ship specialisation triangle: speed / cargo / protection**, three ship families incl. Eastern hulls | §1.3, §2.1, §2.2 **[P]/[S]** | Gives every ship class a reason to exist as a row of numbers. Supports the real-world requirement (C6) — junks, dhows, turtle ships. |
| T14 | **Flagship-is-special; flagship at 0 durability strands the fleet** | §1.3 **[P]** | One dramatic, legible failure state expressible in a single sentence of report text. |
| T15 | **Port permits / language gating access to regions** | §1.4, §2.2 **[P]** | Natural progression fencing with no content cost, and historically true. |
| T16 | **Trade events (Soaring / Plunging / Booming) that move whole categories** | §1.5 **[P]** | Makes the Ledger tab worth reading daily; pure server state. |

### 3.2 DROP

| # | Dropped | Source | Why it dies |
|---|---|---|---|
| D1 | **All tactical combat** — hex tiles, front/middle/back formations, Artillery/Melee/Ram, duels, ammunition, boarding | §1.2, §1.3, §1.9 **[P]** | **C4, absolute.** This is exactly what killed the previous byeharu, visually and in code. Nothing from this tree returns in any form. Combat strength survives only as *one aggregated defence number fed into a risk roll*. |
| D2 | **PvP of every kind** — piracy against players, Epic Sea Feuds, port capture by force | §1.6, §2.2 **[P]** | C4 plus the owner's brief. Players compete on *ledgers*, never on each other's hulls. |
| D3 | **Gacha, Blue/Red Gems, season pass, paid power** | §1.13 **[S]** | Out of scope, and §1.7/§1.13 show the rebalancing debt it creates. |
| D4 | **Loyalty timers (4h conversation / 24h speech)** | §1.4 **[P]** | A pure retention treadmill: it punishes absence rather than rewarding planning. Our offline rule (C8) is that a fleet at sea keeps *working*, not that a player must clock in. |
| D5 | **Energy / stamina as an action gate** | §1.2 **[P]** | Same reason. Our natural limiter is already better and thematic: **hold space, provisions and voyage time**. |
| D6 | **Mate gacha grades C–S with rank-up contract materials** | §1.4, §1.13 **[P]/[S]** | Collection-power spiral. Officers exist, but they are hired with Ducats and reputation and they cap out. |
| D7 | **Manual at-sea navigation / steering** | §1.11 **[P]** | **C3.** Our map cannot accept a command. A voyage is declared as `SAIL … TO … VIA …` and then it is *watched*. |
| D8 | **Real-time ship-to-ship position on an open-world sea with collision, seaweed, ice** (`Momentum`, `Ice Breaking`) | §1.3 **[P]** | Those stats presuppose a navigable 2D sea. Ice and rough water survive as **route-modifier numbers** on named legs, not obstacles. |
| D9 | **300+ battlegrounds, 60 villages, NPC duel challenges at title LV10+** | §1.1, §1.8 **[S]/[P]** | Content mass that only pays off with graphics and a combat engine we are not building. |
| D10 | **Player-set uncapped market tax by the weekly Mayor** | §1.6 **[P]** | An unbounded griefing lever over other players' economies. Kept, but **banded** (see DESIGN.md §H). |
| D11 | **Production / crafting trees** (clothes, food, cannons, alchemy) | §2.2 **[P]** | A whole second economy. Deferred past V2; shipbuilding alone carries the sink. |
| D12 | **Six fixed protagonists with authored personal storylines** | §2.1 **[S]** | Authored narrative content is the most expensive thing per hour delivered. Our story is the ledger. |

### 3.3 CHANGE

| # | Origin's version | Ours | Why |
|---|---|---|---|
| C-a | Sailing speed formula unpublished; offline behaviour unknown **[U]** | **Published, closed-form**: position is a pure function of `(departure_time, route, speed_profile)`, so an offline fleet's location is *computed*, never simulated | C8. It also means no tick can ever drift, and the client can render an exact position with no server round-trip. |
| C-b | 0.1 food + 0.1 water + 1 coin per crew per day **[S]** | **0.020 water + 0.015 food tuns per crew per voyage-day, 1 ducat wage** | A literal 0.1/0.1 makes a Lisbon→Goa run unprovisionable at any realistic hold size. Retuned so a well-found carrack has ~45–50 days of endurance — enough that watering stops matter but are achievable. |
| C-c | Combat as an engine | **Combat as a risk roll → an after-action report row** | C4. Danger becomes `P(hazard) × outcome table`, seeded and replayable. |
| C-d | Investment refunded in S1, then never **[P]** | **Seasonal decay published up front**: points decay 100% at season end, dividends paid from the pot | Avoids the trust damage of changing the refund rule mid-flight. |
| C-e | Ports as 3D scenes | **Ports as tabs of tables** | C1, C2. |
| C-f | ~200 ports at launch **[S]** | **12 ports at V0, ~40 at V1, ~90 at V2** | Every port is a real city with real coordinates and real goods; we would rather have 40 correct ports than 200 invented ones (C6). |

---

## 4. Explicit gaps — things I could NOT verify

Stated here so `DESIGN.md` never launders a guess as a fact.

1. **UWO Origin's Company LV → maximum ship count table.** The guide states the relationship but publishes
   no numbers. **[U]** Our fleet-capacity table is our own design, not an import.
2. **Any numeric ship stat in UWO Origin** — durability, load, crew, knots. The guide names the stats and
   explicitly says values vary with Build Level, but publishes no figures. **[U]** All ship numbers in
   `DESIGN.md` are derived from historical tonnage/crew/speed ranges, not from Origin.
3. **UWO Origin's sailing-speed, wind and distance formulas**, and **whether voyages progress while
   offline**. Not published on any page I could reach. **[U]**
4. **UWO Origin's price formula.** Only the *display* convention (% of neighbours, 90/110 thresholds) is
   published. The underlying supply/demand maths is not. **[U]** Our formula in `DESIGN.md` §G is
   original.
5. **Fandom / Grokipedia / GameFAQs content** — all blocked (402/403) from this environment. Every UW1/UW2/
   UWO-classic number above is a search-engine extract, marked **[S]**, and none of it is load-bearing for
   our design; it informs shape only.
6. **Current live state of Origin's monetisation.** Reports of gacha removal come from player forum posts
   **[S]**, not from a publisher notice I could fetch. Irrelevant to us, but do not repeat it as fact.

---

## 5. Source index

Directly fetched **[P]**:

1. https://guide.floor.line.games/UWO/en_US/detail/1111111111111111115 — Fleet Basics: The Company
2. https://guide.floor.line.games/UWO/en_US/detail/1111111111111111111 — What is an Admiral?
3. https://guide.floor.line.games/UWO/en_US/detail/1167031103747200277 — How to Trade
4. https://guide.floor.line.games/UWO/en_US/detail/1167031174330200447 — Mate
5. https://guide.floor.line.games/UWO/en_US/detail/1167022785491300092 — Ships
6. https://guide.floor.line.games/UWO/en_US/detail/1167031287203500028 — Ship Details
7. https://guide.floor.line.games/UWO/en_US/detail/1167031186467500250 — How to Invest
8. https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354 — Growing Your Fleet: Adventure, Trade, Combat
9. https://guide.floor.line.games/UWO/en_US/detail/1166995021094200118 — Guild System
10. https://uwo.floor.line.games/us/bbsCmn/detail/1653443788526014645 — [Guide] Voyage: How to Set Sail
11. https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1653444258130018779 — [Guide] Voyage: Search and Exploration
12. https://uwo.floor.line.games/us/bbs/community/community_us/1/detail/1734056399615031473 — Season System for Investment; Shipbuilding/Trade Rebalancing
13. https://forums.mmorpg.com/discussion/366992/uncharted-waters-online-the-basics — UWO Online: The Basics

Search-extract only, fetch blocked **[S]**:

14. https://unchartedwaters.fandom.com/wiki/Sailors — crew upkeep constants (402)
15. https://unchartedwaters.fandom.com/wiki/Disasters — disasters, scurvy, mutiny (402)
16. https://koei.fandom.com/wiki/Uncharted_Waters:_New_Horizons — UW2 fames, ships, wind/currents (402)
17. https://koei.fandom.com/wiki/Uncharted_Waters_(series) — series overview (402)
18. https://store.steampowered.com/app/1574360/Uncharted_Waters_Origin/ — world scale, F2P (age gate)
19. https://play.google.com/store/apps/details?id=com.linegames.uwogl — store listing
20. https://gamingonphone.com/guides/uncharted-waters-origin-beginners-guide-and-tips/ — beginner guide
21. https://guide.floor.line.games/UWO/en_US/detail/1166988257148200215 — Journal (Discoveries / Blueprints / Adventure Notes)
22. https://steamcommunity.com/app/1574360/discussions/ — monetisation threads (gacha cost, removal)
23. https://grokipedia.com/page/Uncharted_Waters — series mechanics (403)
