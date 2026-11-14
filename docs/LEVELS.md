# LEVELS: many, and each raised by doing

**Status: the first cut is built (migration 0412, 2026-11-14): the mechanism and ten levels. Three more are designed and wait for the next migration.**

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

They stay two systems. A level gives Reputation, titles, room and captains' ceilings; a skill gives stat bonuses and opens hulls and
gear. No level in this document raises a stat that a skill raises. (Two Academy groups are called Seamanship and Shipwright: no
level takes those names.)

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

**No new stat bonus is made in the first cut.** A bonus to speed, price or build cost needs its own knob, its own balance pass and
a cut into a hot function; a level that only gives what the server already applies cannot promise what is not built. Section 7
lists the bonuses that fit each level, as later slices.

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
- **Gives:** Reputation.

### Weather / 악천후 (granted)
- **Raises it:** a storm day come through, **25**; a day of calm, foul water or shoal water, **10** (the voyage's `STORM`, `CALM`,
  `FOUL_WATER`, `SHOAL_WATER` day rows), granted when the voyage ends.
- **Limits:** once a voyage each (keys `storm:<voyage>`, `rough:<voyage>`). 300 a day. Bad days cannot be made: the sea rolls them,
  and each costs hull, water or time.
- **Gives:** Reputation.

### Shipbuilding / 조선 (granted)
- **Raises it:** a ship built, **60**, once a ship (`cmd.do_build`, beside `HULL_LAID_DOWN`; key `hull:<ship>`); coin paid for
  repairs, **1 per 100 d.** (`cmd.do_repair`, the price the yard was paid).
- **Limits:** 300 a day. Both are coin and materials that do not come back.
- **Gives:** Reputation.

### Requests / 의뢰 (granted)
- **Raises it:** a city's request fulfilled, **1 per 100 d. of its premium**, at most 100 a delivery (`cmd.run_fulfil`, the
  `FULFILLED` event's premium).
- **Limits:** 300 a day. No floor a delivery, so landing a request a ton at a time gains nothing.
- **Gives:** Reputation.

### Craft / 제작 (granted)
- **Raises it:** an item made at a workshop, **5 each** (`cmd.do_make`, `MADE`); a good produced from stored goods, **1 each**
  (`cmd.forge_good`, `FORGED`).
- **Limits:** 300 a day. The materials are used up.
- **Gives:** Reputation.

### Routes / 항로 (granted)
- **Raises it:** a route lap finished at a profit, **10** (`cmd.standing_route_close_lap`, the lap's `net` above 0).
- **Limits:** only at a profit; once a lap (key `lap:<lap>`). 300 a day.
- **Gives:** Reputation.

### Investment / 투자 (granted)
- **Raises it:** coin invested in a city's shares, **1 per 1,000 d.** (`public.invest_for`, the cost of the shares bought).
- **Limits:** 300 a day (300,000 d. of shares): a rich company cannot buy the level in a day. The same coin also counts toward
  Trading, as it has since 0148.
- **Gives:** Reputation.

**Anti-abuse, in all:** a merchant earns nothing (one probe of `players.is_npc`, then out). Every granted level has its limit a
day, read on `public.real_day`, the game's one day. A ship and a lap pay once. A lap pays only at a profit. Past the limit
nothing is written, so the limit also bounds the book.

**No back-pay.** The seven new levels start at nothing for everyone on the day 0412 deploys (as 0352 and 0356 decided). The three
old levels keep what they have.

## 5. Designed, not built: the next migration

| Level | Raises it | Why it waits |
|---|---|---|
| **Gunnery / 포술** | damage her guns deal in a battle she fought (`public.battle_resolve`, the fight's own result) | no company has fought a battle yet (0 `BATTLE_REPORT` rows from players on 2026-11-14), and migrations 0408 to 0411 re-cut the fight's and the pirates' functions now: two PRs slicing one body is the risk |
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

## 7. Later benefits (none is built; none is shown in the game)

Each needs its own knob and its own measured slice. Written down so the direction is known: Supplies, supplies used a day at sea;
Weather, hull lost to a storm; Shipbuilding, build and repair price; Requests, the premium; Craft, materials used; Routes, a
route's fees; Investment, the dividend. Small steps (1 % a level or less), and never above what an Academy skill gives for the
same thing.

## 8. The mechanism

| Thing | What it is |
|---|---|
| `public.level_skills` | the list, as data: code, order, English word, `kept` (record or book), `day_cap` |
| `public.level_activities` | the rates, as data: per activity `xp` for every `per` units, `most_xp`, `once`, `at_gain`, `voyage_nm`; a record level's row names the knob instead |
| `public.level_activity_terms()` | the one reading of the rates; the writer and the page both use it |
| `public.level_xp`, `public.level_book` | a company's experience in a granted level, and every grant (append-only, a chain, the once-ever key) |
| `public.level_grant(player, activity, units, key)` | THE ONE WRITER: merchant out, switch, rate, key, limit a day, book row, level crossed → Reputation and `LEVEL_UP` |
| `public.level_arrival(player, voyage)` | one read of the voyage's days; grants Supplies and Weather |
| `public.level_benefits(code, gift)` | what a level gives, read from the rules that apply it |
| `public.level_skills_card(player, progress)` | the page's data; `world.levels()` serves it as `level_skills` |
| knob `level_skills_on` | false stops every grant at once |

A new level is two inserts and one hook line. The page needs no change: it draws what is served. The words of a new level go in
`src/lib/i18n/dict/command.ts` (`lv<Code>`, `lvAct_<activity>`); until then the server's English word is shown.

The client: `src/features/command/levels/LevelTiles.tsx` (tiles, the level's detail, the phone's tray), `src/live/levelWords.ts`
(names, marks, sentences; the arrival card and History name a level through it).

## 9. Reading it after a deploy

`scripts/ops/harness/levels/after-0412.sql` (one read-only statement): the hooks in place, the data, the tables' grants, the
arrivals beat, and per level how many companies hold experience, the top level and the experience granted.
