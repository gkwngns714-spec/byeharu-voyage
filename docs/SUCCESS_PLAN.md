# SUCCESS PLAN: what makes this game work, in build order

Owner, 2026-11-11 (rows 313-317): *"analyze this game, and think about what you should do to make this game work - success. then implement it one by one. deploy and merge without asking. do all until everything is clean."* His examples: trading is a mess; combat as a steered log (Fight keeps fighting, Flee tries to flee, damage shown); multiple fleets of multiple ships; a new currency, Reputation, from every success, spent on captain skills, like 대항해시대 오리진.

This file is the plan. `docs/WORK_QUEUE.md` is the state. Every choice below marked **default** was decided without asking and the owner may reverse it.

## 1. What the analysis found (2026-11-11, five read-only reports)

**The game has deep systems and a thin surface.** Nearly everything the owner named exists underneath and is either switched off, unreachable, or shown badly.

| Area | What exists | Why a player does not feel it |
|---|---|---|
| Trade | One board, best sale on every card, arrival card, requests, routes | The advice is wrong for a new player (best sale = biggest total anywhere: Japan, Guam; 6 of 10 Lisbon cards cost more than the 40,000 purse; no days, no cost). The same job lives in 3 lists and 3 trays that disagree. At sea the home screen shows a stranger's market and no voyage. Your cargo's rows are a dead end. "No buyer" is false. |
| Combat | A real round engine (`public.fight_sides`: 6 rounds at long / medium / close, hits, damage, armour, hull left, boarding) | Only pirate raids are live. The player chooses nothing, the fight is computed when the fleet lands, the numbers are thrown away and only sentences are kept, shown afterwards in History. A 10-minute battle and a player Attack exist dark; nothing happens during the ten minutes; Break off was designed, never built. |
| Fleets | Fleets and ships tables, caps by level, Move a ship (0321), 103 hulls, a yard | A second fleet cannot be made on prod (the only door is dark behind `fleet_room_bite`). The Levels page says "Fleets 1 of 2" with nothing to press. A second ship needs ~90 t of materials from four ports 505-1,517 miles away in a 60 t hold. Buying room (F3), fleet totals (F4), the fleet page (F5) are not built. |
| Captains | 105 captains, 25 jobs, typed cabins, three XP tracks, grades C-S, promotion by items earned from activity (0162), a stat sheet (0337) | No way to upgrade one ability: each is a fixed percentage. Promotion items are already "a currency from activity spent on captains", under another name. The ledger wrongly says rows 61 and 66 are design only. |
| Progress | Company levels (derived), time-trained Skills, Fame on Rank, Regard (dark) | Nothing fires when a level is crossed; no spendable reward for doing well. |

**The reference game (대항해시대 오리진), as ideas only, no content copied:** three kinds of fame earned by trade / adventure / combat, used as thresholds for titles (not spent); mates with a specialty in typed cabins and passive effects with limited active slots; a choice before every fight (fight, retreat on a roll, surrender a share, parley for coin) that can be preset for offline play; up to 4 fleets of 7 with extra fleets bought; each price shown as a percent of the region's average with buy and sell shortlists. Disliked there and avoided here: a rank that makes the game harsher, random-roll recruitment, an energy gate on top of timers, management scattered over many menus.

## 2. What success means here

1. **A new player earns a profit in the first minute and knows why.** (Trade)
2. **Every success pays something to spend.** (Reputation)
3. **There is something to grow: captains, then ships, then fleets.** (Captain skills, fleets)
4. **Danger is a decision, and its story is worth reading.** (Combat log, Fight / Flee)
5. **One place for each job, one word for each thing.** (NO SPAGHETTI)

## 3. The slices, in build order

Migrations deploy in number order, one PR in the lane at a time. Client slices stack on the open client PRs (#589 → #590) until those merge.

### A. Trade (row 314)

| # | Slice | Kind |
|---|---|---|
| T5 | **A best sale a new player can use**: ranked by profit per day, units capped by the purse, `days` and `cost` served; the dearest sale kept as a second row. Re-cut `world.best_sales` only. | migration 0351 |
| T1 | Your cargo's row closes its page so the tray shows | client |
| T2 | Honest sell word: the city's bid with "none aboard", never a false "No buyer" | client |
| T3 | A sailing strip on Trade (to where, arrives when, a bar); the board stays on the destination, not a waypoint | client |
| T8 | No jumps: chips keep their order, the goods list scrolls with the page | client |
| T9 | Figures with units: real time beside days, Profit / Loss on the arrival card, an amount on every toast, one rounding | client |
| T4 | **One tray**: Trade's own frame becomes a caller of the one `TradeTray` (short body + More); sell city, time and profit above the fold | client |
| T6 | The sell-city chooser inside the tray (Your cargo's rows, also before buying) | client |
| T7 | One goods list: the Trade > City market and the Map tray draw the one card; the Map's dead "buy" becomes Sail & buy | client |
| T10 | Routes are one word for one thing; "Not open yet" says what opens it | client |
| T11 | Words: KO gaps, the sea-rules sentence in plain words under More | client |

Row 229 (*"press cities, not a list, since it will be too easy"*) pulls against any suggestion; row 307 already overrode it and T5 goes further. **Default:** suggestions stay; the chips stay as "look at another city".

### B. Reputation and captain skills (row 317)

**Default design.**
- **One new balance, Reputation / 평판.** (명성 is Fame on Rank; 명예 is a regard band; both taken.) Stored, with its own append-only book, one writer `reputation_credit`, one event kind, one spend door. Outside the gold books and outside `mint_guard`: it is not gold.
- **Earned on success, humans only:** a sale (not a buy), an arrival (miles), a pirate raid seen off, a city request delivered, a battle won, a route lap closed, a ship built, a first landfall. A daily cap stops buy-sell churn. No back-pay: it banks from the deploy, as 0162 did.
- **Spent on captain skills:** a rank per captain per ability (`captain_trait_rank`), one new term inside `public.crew_terms` so every reader (speed, hold, spread, fight stats, the sheet) picks it up. Rising cost per rank, capped by her grade.
- **Words:** the owner said "captain skills". In the UI a captain's abilities are called skills from now (reversing the old D8 word "traits" for the UI only); the company's time-trained Skills keep their Academy.
- **One captain currency in the end:** R1 adds Reputation and skill ranks; R2 makes promotion cost Reputation and converts held promotion items at their point value, so Sea Chart / Trade Seal / Battle Honour stop being a second currency.

| # | Slice | Kind |
|---|---|---|
| R0 | Design doc `docs/REPUTATION.md` (tables, the earn table with numbers, costs, caps, hot-path cost, proofs) | design |
| R1 | Reputation book + earn hooks + top bar figure + the arrival card says "+N Reputation" | migration + client |
| R2 | Captain skill ranks: spend door, `crew_terms` term, the captain sheet's upgrade rows | migration + client |
| R3 | Promotion costs Reputation; items converted | migration + client |
| R4 | A level-up moment: crossing a level fires an event, a card, and a Reputation gift | migration + client |

### C. Combat (row 315)

Law 4 (*no visual combat, prose only*) stands: a text log with two buttons is prose.

| # | Slice | Kind |
|---|---|---|
| C0 | Design doc `docs/COMBAT_LOG.md` | design |
| C1 | **The log with damage**: a raid keeps the engine's per-round numbers (shots, hits, damage, hull left per ship, crew), and the arrival card and History show them as a round-by-round log | migration + client |
| C2 | **A standing order per fleet: Fight / Flee / Pay**, chosen before sailing, frozen at departure, read by the one engine through new `fight_sides` options (absent = byte-identical answer). Flee = each round a roll to slip away, taking that round's fire; Pay = ransom before boarding. Works for offline players by construction. | migration + client |
| C3 | **Live rounds**: the timed battle advances round by round (`tick_battles`), the player's stance is a door (`cmd.battle_stance`), Fight keeps fighting, Flee tries each round, the log grows on screen. First for player-started attacks on NPC ships (needs `attack_enabled`). | migration + client |
| C4 | A raid on an online player opens the same live battle instead of resolving at landing, on a short clock that burns no stores | migration + client |
| C5 | Combat pays: Reputation and Battle progress on every outcome but a loss | rides R1 |

No player attacks a player, in any slice (the owner's hold).

### D. Fleets (row 316, row 180)

| # | Slice | Kind |
|---|---|---|
| F4 | Fleet totals served (guns, hull, crew, wages a day, slowest ship) + `world.house_room` (open / locked / price / level) | migration |
| F3 | `cmd.buy_room`: gold buys a fleet or a ship berth (a pure sink; knob prices exist) + `cmd.rename_fleet` | migration |
| F5 | The Fleets page: New fleet, rename, 7 berths with unlock rows, fleet line with totals, a room line on You | client |
| F6 | Light `fleet_room_bite` with the 30-minute after-check, after re-reading that no company exceeds the lit hull cap | switch |
| F8 | A second ship a new player can reach: **default**, no price change: the starting yard's port sells the four materials of the starter hull (a stock change), or a small starter hull; decided in the slice from measured prices | migration |
| F9 | Side fleets matter: route room follows fleet room; a fleet can be sent on a standing route from the Fleets page | client + maybe migration |

### E. Housekeeping that blocks the rest

- CI caches are over GitHub's 10 GB limit (caused the from-zero rebuild that turned proof 41 red): trim.
- The world build is not deterministic (0126 `npc_fit_loadout` by random fleet id): recorded, frozen; proofs must not depend on it.
- Ledger rows 61, 66 are built: correct their state.
- The Sell button stands past its card at 320 px.

## 4. Switches

Read from prod before any slice that depends on one (the two code reports disagree on `combat_bite` and `crew_bite`): `combat_bite`, `crew_bite`, `levels_bite`, `attack_enabled`, `navy_enabled`, `regard_enabled`, `fleet_room_bite`, `sea_conditions_bite`, `standing_routes_enabled`. Until the owner's new order these were his alone; under rows 313-317 a switch is lit only as a named step of a slice above, with its after-check and a forward rollback ready, and is reported the same hour.

## 5. Order

1. T5 (0351) and the first client trade pass (T1, T2, T3, T8, T9), now.
2. R0 and C0 designs, now, read-only.
3. R1 (0352), then C1 + C2 (0353), then F4 + F3 (0354), then R2, C3, F5, F6, T4, T6, T7, then the rest.
