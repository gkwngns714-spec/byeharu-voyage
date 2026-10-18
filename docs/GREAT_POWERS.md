# GREAT POWERS — ten powers compete; thirteen nations rule their own cities

**Status: BUILT as slice GP1, 2026-10-18 — migration 0185 (provisional number) + its client, on branch
`osn-seven-powers`; not merged, not deployed.** The ten,
their homes and every DEFAULT here are the coordinator's and mine; the owner may swap any of them.

**The owner, 2026-10-18, verbatim:**
- ~14:00 UTC: *"make it 7 big power like uncharted island, spread mainly on europe and asia, as well
  as islamic region"*
- then: *"like uncharted island but different if it can"*
- then, after the correction below: *"in asia add korea, in europe add more."*

**The correction, with its sources (relayed by the coordinator, 2026-10-18).** Uncharted Waters
Origin has **8** national powers, not 7: the official App Store listing says *"8 national powers"*,
and Baidu agrees.
- **Five playable at the start:** Portugal, Spain, England, the Netherlands and the Ottoman Empire,
  one admiral each (João, Catalina, Otto, Ernst, Ali).
- **Three East Asian powers by immigration:** Ming, Joseon and Japan (namu.wiki).
- France and Venice are disputed between namu.wiki revisions.

So the set is **ten**, not seven: Origin's eight, plus France for "Europe, add more", plus Mughal
India so that the Islamic world has two powers, as the first order asked. The owner's earlier rule
still binds: *"each country will have 3~4 cities around them, and rest of them can be competitive"*
(docs/INFLUENCE.md O1).

This file extends `docs/INFLUENCE.md` (the race: influence, the daily count, mayors, rewards) and
`docs/research/UWO_*`. It changes **who** may race. It changes nothing about **how** the race runs.

---

## 0. The answer in ten lines

1. **One new fact:** `public.great_powers(nation_id)` holds the ten. It is authored in
   `scripts/lib/world-derive.mjs` (`GREAT_POWERS`) and held equal to that list by the world guard.
2. **The invariant is declared, not checked in code.** Three foreign keys point at it:
   `players.nation_id`, `port_allegiance.nation_id` and `port_influence.nation_id`. So a company, a
   city's flag and an influence point can belong to a great power only. Every rule that already
   reads those columns (the tax cut, coupons, mayors, the crown, the daily count) is right for ten
   with no change to its code.
3. **The ten keep their home cities**, measured by rule D1 (§2). Only Mughal India's change: Surat
   and Khambhat replace Hadibu, because Gujarat is no longer a power and the Mughals took Surat in
   1573.
4. **The thirteen others become local rulers.** `ports.nation_id`, the founding country, is already
   in the world, so a city founded by one of them keeps that ruler's flag and name as its **ruler**.
   It holds no influence, no flag of its own and no home.
5. **Day one:** a city held today by a great power keeps it (D2). A city held by a minor (its 43
   homes plus 25 won cities) starts at **No country**. Influence given for a minor is credited to
   the country its giver sails for after the migration. The first daily count then hands those
   cities on by the one existing rule (§3).
6. **Companies of a minor** (261 merchant companies, 0 players) sail for the **nearest great power
   by their home port**. Nobody's money, ships, cargo, route or home moves (§4).
7. **Mayors:** the 40 mayors of cities going to No country stand down. That is the same answer the
   daily count gives to a city with no country.
8. **Capitals:** the thirteen demoted capitals keep their purses (142.6 M d. in total). The crown's
   tax and aid now run for the ten only, through `city_capital`'s existing read of `port_nation`.
9. **Regional designs:** a ruler's hulls, line skills, Country gear and captains still belong to its
   own cities, whoever holds the flag there. One new reader, `public.port_countries(port)`, returns
   the holder plus the ruler (if the ruler is a minor). The yard, the academy and the inn compose it.
10. **Client:** Start and Profile offer the ten, and Rank's Countries board shows the ten. The city
    line prints the ruler (`No country · ruled by Venice`) with the ruler's small flag. The Codex
    lists the ten first and the rulers below them.

---

## 1. The ten great powers

| Region | Power | Capital | Home cities (sailed nm from the capital) | Companies today → after | Cities held at the migration (home / contested) |
|---|---|---|---|---|---|
| Europe | ⚓ **Portugal** (PRT) | Lisbon | Lisbon · Setúbal 38 · Porto 158 · Funchal 505 | 99 + 17 players → 103 + 17 | 4 / 20 |
| Europe | ⚔ **Castile-Spain** (ESP) | Seville | Seville · Sanlúcar 40 · Cádiz 66 · Ceuta 141 | 99 → 111 | 4 / 19 |
| Europe | ☩ **England** (ENG) | London | London · Portsmouth 172 · Hull 215 · Plymouth 290 | 46 → 77 | 4 / 2 |
| Europe | ⚑ **The Netherlands** (NLD) | Amsterdam | Amsterdam · Hoorn 18 · Rotterdam 49 · Middelburg 91 | 23 → 94 | 4 / 2 |
| Europe | ⚜ **France** (FRA) | Marseille | Marseille · Toulon 24 · La Rochelle 1,656 · Nantes 1,702 | 50 → 65 | 4 / 5 |
| Islamic world | ☾ **Ottoman Empire** (OTT) | Istanbul | Istanbul · Izmir 271 · Thessaloniki 294 · Rhodes 389 | 99 → 126 | 4 / 18 |
| Islamic world | ✺ **Mughal India** (MUG) | Karachi | Karachi · **Surat 430** · **Khambhat 437** · Chittagong 2,373 | 12 → 78 | 4 / 2 |
| Asia | 龍 **Ming China** (MNG) | Guangzhou | Guangzhou · Xiamen 343 · Quanzhou 383 · Fuzhou 457 | 31 → 66 | 4 / 6 |
| Asia | ☰ **Joseon** (JOS) | Busan | Busan · Ulsan 32 · Tongyeong 50 · Yeosu 80 | 36 → 36 | 4 / 6 |
| Asia | ⛩ **Japan** (JPN) | Sakai | Sakai · Osaka 0 · Tokyo 326 · Kagoshima 366 | 65 → 65 | 4 / 14 |

Every figure here was read from prod, read-only, on 2026-10-18 at ~22:50 UTC (head 0181), with
distances **sailed** (`public.sea_reaches`, the SAIL picker's miles).

**Spread.** Five powers are in Europe, two in the Islamic world (from the Bosphorus to the Indus),
and three in East Asia. Joseon and Japan both have real homes on their own coasts: Busan to Yeosu
spans 80 nm, and Sakai to Kagoshima 366 nm.

**The 40 homes were measured by D1, re-run for the ten** (`scripts/build-home-ports.mjs`). Each
power takes its capital, then its own harbours by sailed miles, up to 4. A power left short takes
the nearest harbour that no great power founded. Nine of the ten came out exactly as today.
**Mughal India** holds only two harbours of its own (Karachi and Chittagong). Today its third home
is Hadibu on Socotra, the top-up INFLUENCE.md §3.1 flagged ⚠. With Gujarat demoted, the nearest
free harbours to Karachi are Surat (430 nm) and Khambhat (437 nm). Akbar annexed Gujarat in 1573, so
history and the rule agree: Surat and Khambhat become Mughal homes, and **Hadibu becomes contested**.
Chittagong stays: it is a Mughal harbour, and the rule keeps a power's own harbours first.

### 1.1 A national edge drawn from what already exists (no new mechanic)

Each power's edge is its **home goods** (`public.port_specialties` at its four homes, read from
prod), its **ship line** (`public.ship_lines`, 0130/0135) and its **Country gear set** (0163). None
of it is new code. It is what the race is now for.

| Power | What its homes make (a selection) | Its yards build |
|---|---|---|
| Portugal | black pepper, cinnamon, raw silk, porcelain at Lisbon: the spice road ends at home | the Portugal line |
| Castile-Spain | quicksilver, silverware and plate, Toledo blades, cochineal | the Spain line |
| England | cannon, gunpowder, tin, Sheffield plate | the England line |
| The Netherlands | sea charts and globes, Delftware, Holland linen, gunpowder | the Netherlands line (shared with the Baltic rulers, §5) |
| France | silk cloth, velvet, Milanese armour, brandy, tapestries; homes on two seas | the France line |
| Ottoman Empire | Iznik tiles, alum, angora wool, mastic, carpets | the Ottoman line |
| Mughal India | Kashmir shawls, saltpetre, wootz steel, opium, Mughal miniatures | the Arabia & India line at Surat (regional, §5) |
| Ming China | porcelain, tea, lacquerware, cloisonné, Canton enamel | the China line |
| Joseon | celadon, ginseng, paper, war bows | the Joseon line |
| Japan | matchlocks, sword blades, Japan copper, Imari ware, Nishijin brocade | the Japan line |

A claim such as "Japan's silver" is **not** made: no home of Japan's produces silver in our data.

---

## 2. Home cities and contested ground

- **40 home cities**, 4 for each power, never change hands (O1; the guard trigger of 0143).
- **198 contested cities.** At the migration, 94 are held by a great power and **104 by No country**.
  The 104 are 68 cities held today by a minor (its 43 homes and 25 won cities), plus the 38 that are
  already free, less Surat and Khambhat, which become Mughal homes.
- **The 42 home flags that come off:** the 13 minors' 41 homes and Hadibu. They are re-authored in
  the open: the migration disables `port_allegiance_home_never_changes` by name for that one
  statement and re-enables it, as the trigger's own comment prescribes. `data/home-ports.json` then
  lists the ten only.

**Contested ground by region at the migration** (holder: count):
Baltic & the Hanse: none 10 · Scandinavia & the Arctic: none 8 · Southeast Asia: none 9, MNG 3,
JPN 2, PRT 1, JOS 1 · Pacific Americas: ESP 9, none 6, MNG 1, JPN 1 · Caribbean: none 7, ESP 2,
NLD 1 · West Africa: none 7, PRT 4 · Western India: none 6, PRT 2, JOS 1 · Eastern India: none 6,
MUG 1, JPN 1, PRT 1 · East Africa: none 6, PRT 2, NLD 1, JPN 1, OTT 1 · Adriatic & Ionian: none 5,
OTT 2 · Western Mediterranean: none 5, ESP 3 · Maghreb: none 4, OTT 4 · Arabia & the Gulf: OTT 4,
none 3, PRT 1, MUG 1, JPN 1 · the rest: 1–6 each.

### 2.1 Day one: No country plus the books, not a gift of territory (DEFAULT G1)

A city held today by a minor could start (a) at **No country**, or (b) **mapped onto a great power**
(for example, to the power its ruler's companies join).

**Chosen: (a), with the book credited.** The reasons:
- The influence coin was **paid**. It is not lost: every point given for a minor is re-keyed to the
  country its giver sails for after the migration (§3). Those powers hold the money there, so the
  first daily count (00:47 UTC) claims each city for whoever paid most, by D5's existing rule for a
  free city (leader ≥ `influence_claim_min`).
- (b) would hand 68 cities to powers that never paid for them. It would also need a second
  "who gets it" rule beside the count, and two authorities is the disease (NO_SPAGHETTI §1).
- A city nobody gave to stays No country until someone does, which is the race the owner asked for.

**Measured: what the first count does after the migration.** The prod book was seeded into a local
copy of the chain at head 0181: every holder, all 1,000 influence rows (45.6 M points) and the
mayors. GP1 was applied, and then the REAL `public.tick_influence` was run with the race lit
(`scripts/db/.gp-harness.local.mjs prodlike count`, local only):
- **74 of the 104 cities are claimed.** For example: Hamburg → NLD, Venice → OTT, Kozhikode → JPN,
  Banten → MNG, Copenhagen → NLD, Genoa → FRA.
- **23 held cities change flag** (97 changes in all, no errors, 155 ms). For comparison, a
  pure-JS replay of steps 1–3 on today's book *without* the migration changes **33** flags and
  claims 19 cities. The race is already this lively.
- Afterwards the cities held are: OTT 32 · JPN 29 · ESP 28 · PRT 24 · MNG 22 · MUG 18 · NLD 17 ·
  ENG 16 · JOS 13 · FRA 9 · No country 30.

Every change is announced by the existing `FLAG_CHANGED` History line.

---

## 3. The migration of existing state, conserved and explained

| What | Rule | Counts (prod 2026-10-18) | Conserved |
|---|---|---|---|
| **Players** of a minor | nearest great power by the minor's capital (players have no home port) | **0** (all 17 are Portuguese) | purse, fleet, cargo untouched |
| **Merchant companies** of a minor | nearest great power by **home port**: the fewest sailed miles to any of that power's four homes (ties: code) | **261 moved**: AYU→MNG 15 · BAN→MNG 20 · DNK→ENG 21, DNK→NLD 8 · GEN→FRA 15, GEN→OTT 4 · GUJ→MUG 21 · HAN→NLD 21, HAN→ENG 2 · MAR→ESP 12, MAR→PRT 4 · MLB→MUG 30 · PER→MUG 15 · POL→NLD 22 · RUS→ENG 8, RUS→NLD 5 · SWE→NLD 15 · VEN→OTT 23 | ducats, ships, cargo, route, **home port** untouched; ink set to the new power's (0145's table); one `NATION_CHANGED {reason: 'great_powers'}` event each |
| **Influence** given for a minor | each row re-keyed to its giver's country after the move; merged (points and `day_given` summed) where the giver already has a row for that country | **291 rows, 12.91 M of 45.60 M points** (28 %): AYU→MNG 1.52 M · BAN→MNG 1.07 M · GUJ→MUG 2.59 M · MLB→MUG 2.47 M · PER→MUG 0.56 M · HAN→NLD 0.90 M · POL→NLD 0.72 M · RUS→NLD 0.61 M · GEN→FRA 0.80 M · MAR→PRT 0.62 M · the rest under 0.3 M each | Σ points before = Σ after (asserted) |
| **Mayors** | a city going to No country has no mayor (the daily count's own answer) | **40** stand down; **0** had set a tax rate | none |
| **Cooldown** | a move made by the world is not the company's choice, so it does not start the 7-day cooldown (`nation_change_next_at` skips `reason = 'great_powers'`) | — | a moved player may choose again at once |
| **Capitals** | the 13 demoted capitals keep their purse and their standing purse (`city_standing` reads `capital_port_code`, which stays) | **142.6 M d.** (Venice 12.1 M, Banten 15.3 M, Genoa 12.8 M, …) | no money moves |
| **Crown tax and aid** | `city_capital(port)` = the capital of `port_nation(port)`; minors hold nothing, so they have no crown | the minors' crowns took **139.5 k d.** of CROWN_TAX since 13:37 UTC; from the migration, 0 | city-to-city only, as before |
| **S18 merchant hulls** (0167) and **ship lines** | the hulls a company sails stay hers; a minor's line stays buildable at its ruler's cities (§5) | 10 yards stand in minor-founded cities | no ship changes class |
| **Country gear** (0163) | `made_only_in` already reads the founding country, so a ruler's gear is still made in its cities | — | unchanged |
| **Captains** | languages, nation and home unchanged; a ruler's captains still favour their own inns (§5) | — | unchanged |

**World money W: unchanged by the migration** (asserted: Σ players.ducats and Σ purses before =
after). No sink and no faucet is added.

### 3.1 Merchants per power: the rebalance (DEFAULT G2: geography only, no weight rebalance now)

After the move, the merchant companies stand at:
**OTT 126 · ESP 111 · PRT 103 · NLD 94 · MUG 78 · ENG 77 · MNG 66 · FRA 65 · JPN 65 · JOS 36**, out
of 821. The most is 15.3 % and the least 4.4 %.

0145's weight rule (Σ commerce + industry of the harbours a power holds) is **not** re-run in this
slice, for two reasons:
- **The weights move overnight.** The first count claims 74 cities. Quotas computed at the migration
  would re-flag about 120 companies a second time against a map that is gone by morning.
- **The weights after that count are a projection.** Proportional to them, the ten would get PRT 107
  · ESP 103 · ENG 58 · NLD 79 · FRA 40 · OTT 113 · MUG 72 · MNG 90 · JOS 42 · JPN 116. Japan is
  the furthest under (65 against 116) and France the furthest over (65 against 40).

**The rule to re-run, a week after:** if any power is above 16 % of the companies, or below half its
weight share, run 0145's water-fill on the ten (the same code, as a data slice). It would use a cap
of 16 % and a floor of 30. 0145's 12 % was set for 23 countries, where a fair share is about 4 %;
for ten, a fair share is 10 %.

---

## 4. The minor powers: local rulers

The thirteen: **Denmark-Norway, Sweden, Poland-Lithuania, Muscovy, the Hanse, Venice, Genoa,
Safavid Persia, Morocco, Ayutthaya, the Gujarat Sultanate, Malabar, Banten.**

- They stay in `public.nations` with their flag, name and capital, so every old event, captain and
  ship that names them still reads.
- A city they founded (`ports.nation_id`, the authored founding record) names them as its **ruler**:
  `world.allegiance` serves `ruler` beside `nation`. A minor rules **37 harbours**, the cities whose
  founding country is one of the thirteen (DNK 6, MLB 5, MAR 4, VEN 4, SWE 3, and 2 or 1 for each of
  the rest).
- A ruler holds **no influence**: the foreign keys refuse a point, a flag or a company for it. The
  Start screen, Profile, `cmd.found_house` and `cmd.change_country` offer and accept the ten only.
  `E_MINOR_POWER` names the ten.
- Rank's Countries board (`world.nation_standings`) lists the ten.

---

## 5. Regional designs: what a ruler's city still builds (DEFAULT G3: yes, kept)

A line's `builder_nations` names its countries. Today it is read against the **holder**
(`port_nation`, D13). Three lines have minor builders:
- **Arabia & India**: Gujarat, Malabar and Banten, all minor.
- **Italy**: Venice and Genoa, both minor.
- **The Netherlands**: NLD plus the Hanse, Poland, Denmark and Sweden.

If the holder alone decided, the Italian and Indian hulls, their line skills and their yards'
output would become unbuildable anywhere. The order says removing content is not asked.

**The rule:** `public.port_countries(port) returns text[]` gives the holder's code, plus the
founding country's code when that country is a minor. Only those two.

The yard (`yard_wrong_country`), the line academy (`skill_taught_at`) and the inn's countrywomen
(`inn_chance`) compose it in place of `port_nation`, one hunk each:
- Venice, whoever holds it, builds Italian hulls and teaches the Italian line's skills.
- Surat (a Mughal home, founded by Gujarat) builds the Arabia & India line, so Mughal India gets the
  Indian Ocean designs.
- A great power's city taken by a rival builds the **holder's** line only, exactly as today (D13).

`made_only_in` (0163) already reads the founding country, so Country gear needs no change. That is
a known second reading of "whose city", recorded here, not widened. The merchant hull rule
(`npc_hull_for`) stays on the holder.

**Parity:** every answer is the same as its pre-image, except at the 37 minor-ruled harbours, where
the ruler's lines are added. This is asserted for every (hull, yard), every (skill, port) at the
yards, and a spread of (captain, inn).

---

## 6. How this differs from Uncharted Waters

Each difference rests on an authority that already exists. Anything new is marked.

| # | Uncharted Waters (Online / Origin) | Here | Authority |
|---|---|---|---|
| 1 | European powers plus the Ottomans; East Asia by emigration only (Origin), with Joseon, Ming and Japan as late additions | **Ten powers playable from the first day**, across Europe, the Islamic world and Asia; any of them can be chosen at founding | `great_powers`; `cmd.found_house` (0143) |
| 2 | Minor states are NPC scenery (Origin: about 43) | **Minor nations live on as local rulers.** Their cities keep their flag, and their hulls, line skills, gear and captains stay in those cities whoever holds the flag | `port_countries` (§5); `ports.nation_id` |
| 3 | A national edge comes from scripted bonuses and admirals | **A national edge comes from the world.** Each power's edge is what its four homes make and what its yards build (§1.1); nothing is scripted | `port_specialties`, `ship_lines`, 0163 gear sets |
| 4 | Influence comes from investment, war and naval battles | **Money only: Invest and Donate.** There is no war and no PvP (ECONOMY_LOOP §12.3) | 0144 |
| 5 | Mayor pay was removed as a runaway engine; tariffs come from the owner country | **Influence pays out through the city economy:** the mayor sets the city's tax (0–20 %), citizens pay half, holders' coupons are paid at 1.5 ×, and the crown takes 10 % of the cities' tax and aids its poor cities | 0147, 0148, 0172 |
| 6 | Weekly or monthly evaluation; Origin added seasons later | **A daily count**, with decay (influence halves in about a week) and UWO's damping (the leader gains less per coin) | 0144, 0146 |
| 7 | Demoted or absent states take nothing with them | **Nothing is lost when a nation is demoted.** Every coin given for it counts for the giver's new country, and the cities it held are won on that money at the next count (§2.1) | this migration |

**Proposed, not built — NOT the owner's, confirm:**
- **Alliances with a ruler.** A power that holds most of a ruler's cities could be named its
  *protector*, with the ruler's line skills taught in that power's own yards. Nothing in the game
  does this today, and it is not in GP1.

---

## 7. The slice

**GP1 · `the_great_powers` (migration 0185, provisional; numbered at push time) + client.** This is
one vertical slice, because the demotion and the ten-country picker are two sides of one contract
(never ship half a slice).

**Migration (in order, one transaction):**
1. **Pre-images:** the bodies and answers the parity proofs compare.
2. **`public.great_powers`** (10 rows), with RLS and no client grant.
3. **The move:**
   - Companies of a minor go to their nearest power (§3) and take its ink, with one event each.
   - Influence rows are re-keyed and merged.
   - Mayors of cities going to No country are deleted.
   - `port_allegiance`:
     - a minor's cities become No country;
     - the 42 homes are released, with the trigger disabled by name for that statement only;
     - Surat and Khambhat become Mughal homes.
4. **Three foreign keys** to `great_powers(nation_id)`, `not valid`, then `validate`.
5. **`public.port_countries(port)`**, and the hunks:
   - `yard_wrong_country`, `skill_taught_at` and `inn_chance`, one each;
   - `world.nation_standings` (the ten);
   - `world.allegiance` (`ruler`);
   - `world.snapshot` (`nations[].great`, `nations[].ruler_of`);
   - `cmd.found_house` and `cmd.change_country` (`E_MINOR_POWER`);
   - `nation_change_next_at` (a world move does not start the cooldown).
6. **The proofs** (self-asserts, each counting only its own rows):
   - every re-cut reverses to its pre-image, with ACL, volatility, definer, config and owner
     unmoved;
   - W unchanged; Σ points unchanged;
   - no company, flag or point belongs to a minor;
   - every moved company sits at its nearest power and kept its ducats, ships, route and home;
   - the companies per power match the plan's computation;
   - parity of yard, academy and inn outside the minor-ruled harbours;
   - a probe house founded under Venice is refused `E_MINOR_POWER`; one under Joseon starts at
     Busan;
   - `world.nation_standings` lists exactly the ten;
   - the foreign keys refuse a minor.

**Client:**
- `NationPicker` offers `great` nations only.
- `CityFlag` prints `· ruled by <ruler>` with the ruler's `Flag` (caption size).
- The Codex `NationsFace` has two groups: **Great powers** and **Local rulers**.
- The `NATION_CHANGED` headline for `reason = 'great_powers'` reads *"Venice is a local ruler now;
  your company sails for the Ottoman Empire."*
- `Flag.tsx` and the map's labels layer are not edited; another agent holds them (`osn-flags-2`).

**Data and tools:**
- `world-derive.mjs` gets `GREAT_POWERS`.
- `data/home-ports.json` lists the ten.
- `build-home-ports.mjs` gets the ten-power rule.
- The world guard checks `great_powers` and "only great powers have homes, 4 each".

**Watch after deploy:** the first 00:47 UTC count's receipt (`claimed`, `changed`); the companies
per power; and W.

---

## 8. Owner to confirm: every DEFAULT here

| # | DEFAULT | If you say no |
|---|---|---|
| **G0** | The ten: PRT ESP ENG NLD FRA · OTT MUG · MNG JOS JPN | Name others; it is one list (`GREAT_POWERS`) and the homes rule re-runs |
| **G1** | A minor's cities start at No country, and its influence goes to the givers' new countries (§2.1) | Map each minor's cities onto one power |
| **G2** | Companies go to the nearest power by home port; no weight rebalance until a week has been measured (§3.1) | Run the 16 % / 30 water-fill now |
| **G3** | A ruler's hulls, skills, gear and captains stay in its own cities (§5) | Only the holder's lines build anywhere |
| **G4** | Mughal homes: Karachi, Surat, Khambhat, Chittagong; Hadibu becomes contested | Keep Hadibu |
| **G5** | A demoted capital keeps its 10 M standing purse | Standing purse 2 M (its money stays; it only stops refilling above 2 M) |
