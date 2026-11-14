# LEVELS: many, and each raised by doing

**Status: built in two cuts, 2026-11-14. Migration 0411: the mechanism and ten levels. Migration 0417: a benefit of its own for each of the seven new levels, and the tiles on the You page. Three fight levels are designed and wait (section 5).**

The owner, 2026-11-14: *"levels we only have trading, exploration, combat. like rs3, i want diverse skills related to this game"* and
*"with exp table, exp info, with benefits when leveling up, what activity needs done etc."*

Every choice below is **decided by default**; the owner may reverse any.

---

## 1. What a level is, and how it differs from an Academy skill

A **level** rises by DOING something the game already has and already records. Each has its own experience, its own level from 1 to
20, and gives something as it rises. All of them are on one page (Command, Levels) as tiles; a pressed tile shows that level's
experience, what raises it, what its levels give, and the experience table.

**How levels and the 107 Academy skills relate, in the one sentence the page prints:**
*"Levels rise by doing. Academy skills are studied. A level never changes what a skill gives."*

They stay two systems. A skill gives stat bonuses and opens hulls and gear. A level gives Reputation, titles, room, captains'
ceilings and (0417) a small benefit on a figure no skill touches: the PRICE of supplies (a skill has their endurance), the WEAR of
gear (a skill has storm damage to the hull), the price of a REPAIR (a skill has the build yard's labour), Reputation and favour.
One figure is shared on purpose: the count of routes, where a Routes level's one or two routes add to the Factorage skill's, in the
one function both are read in. (Two Academy groups are called Seamanship and Shipwright: no level takes those names.)

## 2. One curve, for every level

`level = floor(sqrt(experience / 25)) + 1`, from 1 to 20 (`public.level_from_points`, knob `level_points_per_step` 25, 0069). The
same curve as Trading, Exploration and Combat have had since 0069: "level 4" is the same amount of work whichever level it is.

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Experience | 0 | 25 | 100 | 225 | 400 | 625 | 900 | 1,225 | 1,600 | 2,025 |

| Level | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|
| Experience | 2,500 | 3,025 | 3,600 | 4,225 | 4,900 | 5,625 | 6,400 | 7,225 | 8,100 | 9,025 |

The page prints this table for each level with her own level marked, the next one lit, and what is left to it.

## 3. What every level gives

**Reputation: 10 × the level reached, once** (`rep_level_per_level`, 0356), with a `LEVEL_UP` moment on the arrival card and in
History. Level 2 gives 20, level 20 gives 200; a level taken from 1 to 20 gives 2,090 in all. Reputation buys captain skill steps
(0355), so every level is worth something a player can spend.

**And each of the seven new levels gives a benefit of its own, at five of its twenty levels** (0417; section 7 has the table). Every
benefit the page lists is applied by the server and served from the same rows the server reads.

No pay-to-win: nothing here is bought with real money. No PvP: no level is raised against another player.

## 4. The ten levels that are built

Two kinds, and the page says which:

- **Counted from the record** (Trading, Exploration, Combat): `public.player_progress` re-reads her whole history each time, as it
  has since 0069. It stays the one authority for these three; every gate that asks them is untouched. They have no daily limit
  and no list of grants.
- **Granted by doing** (the seven new ones): `public.level_grant` writes experience into `public.level_xp` when the activity
  happens, at most **300 a day** each, and keeps every grant in `public.level_book`.

For each level: what raises it (the event that grants, and how much), its limits, and what its levels give beyond the Reputation
of section 3.

### Trading / 교역 (counted from the record)
- **Raises it:** goods bought or sold, 1 per 500 d. of turnover (ledger rows of `BOUGHT` and `SOLD`); coin invested in or donated
  to a city, 1 per 500 d. (`INVESTED`, `DONATED`); a day as mayor, 25 (`MAYOR_DAY`). Knobs `fame_ducats_per_point`,
  `fame_per_mayor_day`.
- **Limits:** none a day. Buying and selling in one port loses the spread and the tax.
- **Gives:** one more fleet at levels 3 and 6 (`fleet_room_levels`); the title of each level from 2 to 11, held at the lower of
  Trading and Exploration, and the seas a title opens; a captain's Trading level may rise to the company's; a captain's promotion
  to B, A, S asks level 5, 10, 15.

### Exploration / 탐험 (counted from the record)
- **Raises it:** a port reached for the first time, 25 (`VOYAGE_REPORT`, distinct ports); miles sailed, 1 per 100 (the report's
  `total_nm`). Knobs `fame_per_port`, `fame_nm_per_point`.
- **Limits:** none a day. A port counts once ever.
- **Gives:** the title (with Trading) and its seas; the captains' ceiling; the promotion levels.

### Combat / 전투 (counted from the record)
- **Raises it:** pirates evaded, 5; pirates driven off, 15 (a voyage's `PIRATES` days, `public.fight_points`). Knobs
  `xp_evaded_points`, `xp_driven_off_points`.
- **Limits:** none a day; counted while `levels_bite` is on.
- **Gives:** the captains' ceiling; the promotion levels.

### Supplies / 보급 (granted)
- **Raises it:** a day at sea with enough supplies, **2 a day**, granted at arrival (`voyage.settle` → `public.level_arrival`, from
  the voyage's own day rows in `voyage_events`).
- **Limits:** only a voyage of 100 miles or more that makes a port, with no day on short rations (one hungry day and the voyage
  gives nothing). Once a voyage (key `fed:<voyage>`). 300 a day.
- **Gives:** Reputation; **supplies cost 1 % less at each of levels 4, 8, 12, 16, 20** (5 % in all).

### Weather / 악천후 (granted)
- **Raises it:** a storm day come through, **25**; a day of calm, foul water or shoal water, **10** (the voyage's `STORM`, `CALM`,
  `FOUL_WATER`, `SHOAL_WATER` day rows), granted when the voyage ends.
- **Limits:** once a voyage each (keys `storm:<voyage>`, `rough:<voyage>`). 300 a day. Bad days cannot be made: the sea rolls them,
  and each costs hull, water or time.
- **Gives:** Reputation; **gear wears 5 % less on a storm day at each of levels 4, 8, 12, 16, 20** (25 % in all).

### Shipbuilding / 조선 (granted)
- **Raises it:** a ship built, **60**, once a ship (`cmd.do_build`, beside `HULL_LAID_DOWN`; key `hull:<ship>`); coin paid for
  repairs, **1 per 100 d.** (`cmd.do_repair`, the price the yard was paid).
- **Limits:** 300 a day. Both are coin and materials that do not come back.
- **Gives:** Reputation; **ship repairs cost 2 % less at each of levels 4, 8, 12, 16, 20** (10 % in all; the hull's price, not worn gear's).

### Requests / 의뢰 (granted)
- **Raises it:** a city's request fulfilled, **1 per 100 d. of its premium**, at most 100 a delivery (`cmd.run_fulfil`, the
  `FULFILLED` event's premium).
- **Limits:** 300 a day. No floor a delivery, so landing a request a ton at a time gains nothing.
- **Gives:** Reputation; **a request fulfilled gives 10 % more Reputation at each of levels 4, 8, 12, 16, 20** (50 % in all).

### Craft / 제작 (granted)
- **Raises it:** an item made at a workshop, **5 each** (`cmd.do_make`, `MADE`); a good produced from stored goods, **1 each**
  (`cmd.forge_good`, `FORGED`).
- **Limits:** 300 a day. The materials are used up.
- **Gives:** Reputation; **gear wears 3 % less from miles and fights at each of levels 4, 8, 12, 16, 20** (15 % in all).

### Routes / 항로 (granted)
- **Raises it:** a route lap finished at a profit, **10** (`cmd.standing_route_close_lap`, the lap's `net` above 0).
- **Limits:** only at a profit; once a lap (key `lap:<lap>`). 300 a day.
- **Gives:** Reputation; **a profitable lap gives 20 % more Reputation at levels 4, 12, 20** (60 % in all); **one more route at levels 8 and 16**.

### Investment / 투자 (granted)
- **Raises it:** coin invested in a city's shares, **1 per 1,000 d.** (`public.invest_for`, the cost of the shares bought).
- **Limits:** 300 a day (300,000 d. of shares): a rich company cannot buy the level in a day. The same coin also counts toward
  Trading, as it has since 0148.
- **Gives:** Reputation; **investing wins 10 % more favour with the city's country at each of levels 4, 8, 12, 16, 20** (50 % in all).

**Anti-abuse, in all:** a merchant earns nothing (one probe of `players.is_npc`, then out). Every granted level has its limit a
day, read on `public.real_day`, the game's one day. A ship and a lap pay once. A lap pays only at a profit. Past the limit
nothing is written, so the limit also bounds the book.

**No back-pay.** The seven new levels start at nothing for everyone on the day 0411 deploys (as 0352 and 0356 decided). The three
old levels keep what they have.

## 5. Designed, not built: the next migration

| Level | Raises it | Why it waits |
|---|---|---|
| **Gunnery / 포술** | damage her guns deal in a battle she fought (`public.battle_resolve`, the fight's own result) | no company has fought a battle yet (0 `BATTLE_REPORT` rows from players on 2026-11-14), and migrations 0409 and 0412 (the pirates' homes, then their trade) re-cut the fight's and the pirates' functions now: two PRs slicing one body is the risk |
| **Boarding / 백병전** | a boarding action won, from the same result | the same |
| **Raiding / 약탈** | loot taken by an attack (`public.attack_close`) | the same; and it must be held to merchants and pirates only: never another player |

One migration, after the pirate slices land: three rows in `level_skills`, their rows in `level_activities`, one hunk in
`public.battle_resolve`. The page shows them by itself: a tile is a row.

## 6. Judged and dropped

| Candidate | Why not |
|---|---|
| Sailing / Navigation (miles, voyages) | Exploration already counts every mile. A second level on the same miles is one level shown twice. |
| Cartography (first landfalls, seas opened) | Exploration already counts each new port; no row records a sea "opened". |
| Diplomacy / Standing | Regard with each country is already a score with its own bands, on the same page. Contracts became Requests. |
| Leadership / Crew | each captain already has three levels of her own; the company has no record of "crew kept alive" to grant from. |
| Smuggling, Piracy for the pirate power | no record of a sale as contraband; Raiding (section 5) covers the attack. |
| Banking | the bank is not lit (PR 484). Investment covers the shares. |

## 7. The benefits of the seven new levels (0417)

A benefit is a list of STEPS (`public.level_perks`: benefit, level, amount). What it is worth to a company is the sum of the steps
at or below her level (`public.level_perk`, the one reading). Each multiplies ONE figure in the ONE function that already owns it,
so what a screen quotes and what a door charges are the same number.

| Level | Benefit | Steps | In all | The figure it acts on, and its unchanged knob |
|---|---|---|---|---|
| Supplies | supplies cost less | 1 % at 4, 8, 12, 16, 20 | 5 % | `public.stores_cost` (`provision_water_price` 10, `provision_food_price` 25) |
| Weather | gear wears less on a storm day | 5 % at 4, 8, 12, 16, 20 | 25 % | `public.wear_units_for` (`gear_wear_per_storm` 3) |
| Shipbuilding | ship repairs cost less | 2 % at 4, 8, 12, 16, 20 | 10 % | `public.fleet_repair_cost`, the hull's part (`repair_rate_per_point` 10) |
| Requests | a request gives more Reputation | 10 % at 4, 8, 12, 16, 20 | 50 % | `public.reputation_request` (`rep_request_per_point` 250, min 5, max 100) |
| Craft | gear wears less from miles and fights | 3 % at 4, 8, 12, 16, 20 | 15 % | `public.wear_units_for` (`gear_wear_per_1000nm` 1, `gear_wear_per_fight` 4) |
| Routes | a profitable lap gives more Reputation | 20 % at 4, 12, 20 | 60 % | `public.reputation_lap` (`rep_lap` 10) |
| Routes | one more route | 1 at 8 and 16 | 2 | `public.standing_route_max_for` (`standing_route_max` 3) |
| Investment | a stake wins more favour with the country | 10 % at 4, 8, 12, 16, 20 | 50 % | `public.invest_for` → `public.regard_gift` (`regard_per_100k` 10) |

- **The old values are all still there.** No knob above was changed. A benefit is its step rows: set an amount, or switch every
  benefit off at once with `level_perks_on` false (then every figure is exactly what it was before 0417).
- **A merchant gets none:** she has no experience row, so the reading answers 0 after two index probes.
- **Not pay-to-win, not PvP.** A better dividend share was judged and left out: a city pays its shareholders pro rata, so one
  company's better share would be another's worse one.
- **Trading, Exploration and Combat get nothing new here.** The page lists what they already give (section 4).
- **Judged and not built:** supplies that last longer, storm damage, build labour, the tax (each is an Academy skill's figure); a
  bigger premium on a request (it is paid from the city's own escrow); less material for an item (the recipe is read in three
  places, with no one function to cut); more stops on a route (the same).

On the page, a level's detail says what each benefit is worth to her NOW (or the level it begins at), and the experience table
shows every step at its level with the figure it reaches there.

## 8. The mechanism

| Thing | What it is |
|---|---|
| `public.level_skills` | the list, as data: code, order, English word, `kept` (record or book), `day_cap` |
| `public.level_activities` | the rates, as data: per activity `xp` for every `per` units, `most_xp`, `once`, `at_gain`, `voyage_nm`; a record level's row names the knob instead |
| `public.level_activity_terms()` | the one reading of the rates; the writer and the page both use it |
| `public.level_xp`, `public.level_book` | a company's experience in a granted level, and every grant (append-only, a chain, the once-ever key) |
| `public.level_grant(player, activity, units, key)` | THE ONE WRITER: merchant out, switch, rate, key, limit a day, book row, level crossed → Reputation and `LEVEL_UP` |
| `public.level_arrival(player, voyage)` | one read of the voyage's days; grants Supplies and Weather |
| `public.level_benefits(code, gift)` | what a level gives, read from the rules that apply it (0417: and the steps of `level_perks`) |
| `public.level_perks`, `public.level_perk(player, perk)` | 0417: the steps of each benefit, and the one reading of what a benefit is worth to a company now; knob `level_perks_on` |
| `public.level_skills_card(player, progress)` | the page's data; `world.levels()` serves it as `level_skills` |
| knob `level_skills_on` | false stops every grant at once |

A new level is two inserts and one hook line. The page needs no change: it draws what is served. The words of a new level go in
`src/lib/i18n/dict/command.ts` (`lv<Code>`, `lvAct_<activity>`); until then the server's English word is shown.

The client: `src/features/command/levels/LevelTiles.tsx` (tiles, the level's detail, the phone's tray), `src/live/levelWords.ts`
(names, marks, sentences; the arrival card and History name a level through it).

**Where a player finds them:** Command → Levels (the tiles, whole), and the You page (0417: the same ten tiles, small, under its
three bars; a pressed one opens the same detail in a tray).

## 9. Reading it after a deploy

`scripts/ops/harness/levels/after-0417.sql` for the benefits (the hooks, the steps, a merchant's price unmoved), and
`scripts/ops/harness/levels/after-0411.sql` for the levels (one read-only statement each): the hooks in place, the data, the tables' grants, the
arrivals beat, and per level how many companies hold experience, the top level and the experience granted.
