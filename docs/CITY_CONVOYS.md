# CITY_CONVOYS — cargo ships: goods city to city, gold capital to depleted city

**Words (owner, 2026-11-05):** the ship is a **Cargo ship**; the gold is **Funds**; its load is a **Shipment**. Not "gift", not "aid".

**Status: V1 live dark (0308, `docs/dev-log/2026-11-05-cargo-ships.md`): the fleet kind, the book of funds aboard, the sizing. V2 built dark (0309, `docs/dev-log/2026-11-05-cargo-funds.md`): loading from `crown_aid`'s same decision, one circuit of a realm, delivery, return, funds aboard in the total, no dock fee, hull rule. V4 built dark (0310, `docs/dev-log/2026-11-05-cargo-visible.md`): her hull, the map's reads, her card, the hall and Stats. Goods are design.** Prod head at writing: **0305**.
**0324 (W7, dark behind `convoy_rich_enabled`): where this doc says a ship loads at or returns to the capital, lit she does so at her origin, a rich city of her realm, and the capital is a stop. `docs/WORLD_POWERS.md` section 3.1.**
**0328 (W8, dark behind `convoy_armed_enabled`): where this doc says a cargo ship is crewless, lit she is a `navire` with guns, hands from the quay and free stores, and her origin pays an upkeep each leg. `docs/WORLD_POWERS.md` section 3.2.**
**The owner (2026-11-05):** *"i need a transportation ship, cities moving trade goods to different cities, moving gold to gold. Capital city with its massive income, will provide other cities with gold when depleted."*
Every "decided by default" is mine; the owner reverses afterwards.

Standing rules kept: closed economy (no minted gold; `mint_guard` untouched), a city never below zero (0122), one place per concept, switches/knobs owner-only, ships dark.

---

## REVIEW 2026-11-05: read this first; it overrides the sections below where they differ

Measured on prod (pure reads, `treasury_balance`, `stats_city` last 24 h, `port_goods`). The original draft got three things wrong: it said no `CROWN_AID` ran (it read `treasury_flows` right after the hourly roll at :37, and that table only holds flows since the last roll; a 24 h figure comes from `stats_city`), it treated capital funding of cities as new, and it assumed cities lack goods.

| Claim | Measured |
|---|---|
| The capital already funds poor cities | **True, today, instantly.** `city_day`: `CROWN_AID` tops a city up to its reserve from what the capital holds above its own. Last daily record: 21.0 M d. out of capitals, about 160 cities received |
| Capitals have massive income | **Half true.** Median income 11.6 M a day vs 3.1 M for other cities, 562.6 M together; but they spent 685.7 M. 12 of 23 capitals hold under 100,000 d. |
| Gold is where it is needed | **False.** Top 10 of 246 cities hold 74 % of 23.4 B; 32 hold 0; 95 hold under 10,000. |
| Cities lack goods | **False by stock.** 154,723 of 154,734 stock rows are above 80 % of target, 0 below 20 %, 0 empty |
| Empty purses hurt | 217 of the 14,195 orders on file failed `E_CITY_BROKE` (1.5 %). Period not measured |

**Why 101 cities under 10,000 d. stay broke:** (a) 47 have a capital under 100,000 d. to draw on, often while the nation holds plenty in one other city (MRS capital 6,857 d., nation 3.36 B); (b) 16 have a capital over 1 M but already meet their reserve, because the reserve is 3 days of the city's own recent sale payouts, and a broke city pays out little (43 of the 101 show zero outflow), so a broke city is judged not short. (c) One nation (BUS) holds 49,145 d. in total: nothing inside it can help.

**Results so far (2026-11-05):** 0306 and 0307 are live. Run at 03:37: 7.60 M d. to 168 cities, gold conserved, cities under 50,000 d. 113 -> 63. By 04:08 it was back to 101, and `E_CITY_BROKE` did not fall (143 of 1,773 sale orders in 30 minutes). Funds arrive and are gone within the hour, because these cities pay out far more than 50,000 d. an hour. Dividends are the larger outflow: the 121 paying cities under 50,000 d. paid 115 M d. on their last daily record against 12 M of aid; 1.56 B of the 1.57 B "Set aside" in Stats is uncollected dividends, nearly all owed to merchants. Open owner decision: pause dividends while a city is broke.

**Better plan, in order:**
1. **Fix the reserve floor** so a broke city counts as short (owner knob; one small migration). Built as 0306, PR open, not deployed: the floor enters the aid decision only, not the reserve, because the reserve also sets the sale bid (`docs/dev-log/2026-11-05-reserve-floor.md`).
2. **Let the capital draw on its nation's rich cities** before funding: `CROWN_CALL` already does this for merchant gifts; reuse it. Built as 0307, PR open, not deployed: a share of each donor's surplus per run, and a donor keeps about an hour of payouts above its reserve (`docs/dev-log/2026-11-05-crown-call.md`).
3. **Cargo ships carry funds only**, and they **replace** the instant `CROWN_AID` delivery: one rule, one path, never both. Measure first: instant aid reaches about 160 cities a day, and 2 ships per nation cannot, so the ship count and a route that serves several cities on one trip must come from a prod read, and the extra `E_CITY_BROKE` during the delay must be watched. **Answered in `docs/dev-log/2026-11-05-cargo-ships.md`: 160 is cities an hour (168 read), 5 ships a realm on one circuit.**
4. **Goods run (section 4): dropped for now.** No city is short by stock, and crown ships moving goods would take the player's own trade.

---

## 0. The answer in ten lines

1. A **cargo ship** is a ship owned by a nation's crown, based at its capital. It is a real fleet that sails real legs, so the player can see it on the map and meet it.
2. It carries **two kinds of load**: (a) **gold** from a purse to a purse, (b) **trade goods** from a city that has too much to a city that lacks it.
3. **Gold run:** when a city of the nation is depleted, the capital loads gold and sends a cargo ship. The gold leaves the capital purse at loading and enters the city purse at docking. In between it is **cargo, not nobody's**: counted in Stats as "in transit".
4. **Goods run:** a cargo ship picks up goods a city holds above its need, pays the city for them from the *buying* city's treasury at the normal price, and delivers them. No gold is created: the receiving city pays the sending city.
5. The capital sends **funds** (owner said "provide"), free, not a loan, up to a per-city, per-day cap. A loan is the bank's job (docs/BANK.md); the two do not overlap.
6. The capital cannot give what it does not hold: it keeps a reserve and stops at it.
7. A cargo ship can be **delayed, but not lost** in v1 (pirates are owner row #268, parked). The route is fixed at departure.
8. Everything is decided by **one daily rule** in its own cron job, never in the beat (the 0301 lesson).
9. Ships **dark**: `convoys_enabled` false. Off = today's game, byte for byte.
10. Five slices (§8).

---

## 1. What already exists (so nothing is built twice)

| Existing | Where | Relation |
|---|---|---|
| `CAPITAL_GIFT` (capital -> a poor merchant company, instant) | 0234, `capital_gifts` | stays; merchants only |
| `CROWN_AID` / `CROWN_CALL` (city -> city, instant; funds a new harbour from its capital) | 0228/0233/0235 | the **instant** version of the gold run; the convoy replaces it for depleted cities, same flow kinds, kept "moved" |
| `treasury_post`, `pay_city` (the only city-purse writers), `mint_guard` | 0122 | the convoy uses `treasury_post` only |
| NPC merchant fleets, standing routes, voyages, `voyage.reach_from`, arrivals beat | 0099-0114, ... | a cargo ship is a fleet of a new kind, sailing the same voyage engine |
| City wants (E6b), restock by investment (E5), max stock by tier/rare (0303) | CLOSED_ECONOMY | the goods run feeds exactly what wants/stock already measure; it adds no new price rule |
| Population (0304): FAMINE / WAR / INVEST signals, daily POPULATION_TAX | 0304 | a city in FAMINE or WAR ranks first for funds |

**To read on prod before building (not yet re-read for this doc):** the bodies of `treasury_post`, `fleet_unload`, how an NPC fleet loads cargo, and whether a fleet can hold a non-goods cargo (gold). If it cannot, gold rides as a **ledger row** on the cargo ship (`convoy_cargo`), not as a goods item.

---

## 2. The cargo ship

**Name: Cargo ship** (EN), KO 화물선. NPC like the merchants, but a different kind of ship with a different look and a different job.

| | Merchant | Cargo ship |
|---|---|---|
| Owner | a merchant company | the nation's crown, based at its capital |
| Goal | profit on its own route | move goods and funds the daily rule assigns |
| Purse | its own | none; legs are paid by the capital purse |
| Route | standing route, loops | one job: load, sail, unload, go home |
| Invests, gets capital gifts, is refounded | yes | never |
| On the map | merchant hull, nation ink | its own hull, nation ink plus a crown mark |

- New fleet kind `CARGO_SHIP`; count per nation = `public.convoy_ships_of` (0326: 20 to 50 by the country's cash). Never takes a player's cargo, cannot be boarded in v1.
- Upkeep per leg comes from the capital purse (`convoy_upkeep_per_leg`, a moved flow, not minted).

**Graphics (one renderer, no fork):** ships are drawn by `src/chart/glyphs.ts` (`hullPath`, one renderer for fleets and merchants, nation ink) and chosen by `src/chart/shipMarks.ts`. So:
- `glyphs.ts` gains one new hull: wide, deep-bellied, a high stern, heavier than any merchant, and readable at small size.
- `world.sea_roster` (the read the client uses since 0118) and `world.sea_traffic` serve a `kind` on a cargo ship's row, and on hers alone, so a merchant's row never changes; a cargo ship picks the new hull. Nothing else in the renderer branches.
- `shipMarks.ts`: cargo ships are **never thinned** at wide zoom (there are at most 46), like your own ships.
- The fleet card (like `src/live/MerchantSheet.tsx`) shows its load and destination: "Cargo ship - shipment: 420,000 d. to Bristol". `ShipTile` and the Codex Ships face get the same hull.

---

## 3. Gold run: the capital provides when a city is depleted

**Depleted** (all knobs): the city's purse (the live balance via `treasury_balance`, **not** the rolled column) is below `convoy_low_water_days` (3) x its average daily payout over 7 days, or below `convoy_floor` (a flat floor, default 50,000 d.). FAMINE or WAR in the last 24 h lowers the bar to 1 day.

**Amount:** `min(target_days x avg daily payout - purse, convoy_cap_per_city_day, capital_free)`, where `capital_free = capital purse - convoy_capital_reserve_pct (30 %) x capital purse`.

**Order:** cities served by need (lowest days-of-cover first) until the capital's free gold or the cargo ships run out; the rest wait for tomorrow. No queue is stored.

**Steps:**
1. Daily job picks (city, amount); `treasury_post(capital, 'CONVOY_LOAD', -amount)`; a `convoy_cargo` row (gold, amount, from, to) rides the cargo ship.
2. The cargo ship sails the normal route to the city.
3. On docking: `treasury_post(city, 'CONVOY_DELIVER', +amount)`; the cargo row closes. Both flow kinds are **moved** in `stats_flow_words`.
4. If the cargo ship has not docked within `convoy_max_days` (10), the cargo is returned to the capital purse (`CONVOY_RETURN`), nothing is lost.

**Why this cannot mint:** gold only leaves one purse and enters one purse, in two steps, with an auditable row between them. Σ(purses + cargo in transit + vaults) is constant.

---

## 4. Goods run: city to city

- A city **has a surplus** of good G when its stock is above `convoy_surplus_pct` (80 %) of its max stock for G (max from 0303's stock scale).
- A city **lacks** G when it is one of its wants (E6b) or its stock is below `convoy_lack_pct` (20 %) of max.
- Match within one nation first, nearest pair first, by an overlap-free pass: surplus city S, lack city L, quantity `min(S surplus, L room, hold)`.
- **Price:** L pays S at the normal quote (`world.quote`) from L's treasury at delivery, S is credited when the goods are loaded (S is paid by the crown's float: the capital advances it, and L reimburses it on delivery, so nobody is out of pocket if the ship is delayed; the advance is a `convoy_float` row, repaid in full or returned).
- If L's purse cannot pay, the cargo ship waits one day, then delivers at a smaller quantity; it never forces a city below zero.
- The goods run is **off by default** even with `convoys_enabled` (`convoy_goods_enabled` false): the gold run can ship first.

---

## 5. Where it shows

- Map and sea roster: the cargo ship and its load. Stats -> a nation: gold in transit, runs this week, cities funded.
- City hall: "Funds on the way: 420,000 d., arriving in 2 days" and the history of funds received.
- Words: 1-2 plain words, EN + KO via the dictionary ("Cargo ship" 화물선, "Funds" 자금, "Shipment" 수송).

---

## 6. Knobs (rows; all added dark)

`convoys_enabled` false · `convoy_goods_enabled` false · `convoy_ships_min` 20 · `convoy_ships_max` 50 · `convoy_low_water_days` 3 · `convoy_target_days` 7 · `convoy_floor` 50,000 · `convoy_cap_per_city_day` (decided at build from a prod read) · `convoy_capital_reserve_pct` 0.30 · `convoy_max_days` 10 · `convoy_surplus_pct` 0.80 · `convoy_lack_pct` 0.20 · `convoy_upkeep_per_leg`.

---

## 7. Is it needed now? (a measurement owed before lighting)

Settled by the REVIEW at the top of this file: cities do run short, and the fault is the reserve rule and where the gold sits. The ship is not the cure by itself.

---

## 8. Slices (strict order, each its own PR, deployed with `~/bin/bv-deploy.sh`)

| Slice | Content | Proof (red first) |
|---|---|---|
| **V1** `cargo_ships_exist` | fleet kind, `convoy_cargo`, `convoy_float`, knobs, flow kinds as **moved**, dark | kind exists per nation, based at its capital; cargo/flows append-only; Σ supply unchanged by any probe row |
| **V2** `the_capital_loads_gold` | the daily job: depleted rule, loading, `CONVOY_LOAD`, the cargo ship departs on the normal voyage engine | probe depleted city gets exactly the §3 amount; capital never below its reserve; not depleted -> no run; dark -> nothing |
| **V3** `the_gold_arrives` | docking delivery, `CONVOY_DELIVER`, `CONVOY_RETURN` after `convoy_max_days`, in-transit counted in Stats | delivery credits the city exactly; late -> returns to the capital; Σ(purses + in-transit) constant to the ducat; money-log ratio 1.0000 |
| **V4** `convoys_you_can_see` | map/roster/city-hall/Stats faces, dictionary | red-then-green design spec; no page scroll at 390x844 and 320x568 |
| **V5** `the_goods_run` | surplus/lack matching, float, delivery payment | probe surplus city sells to a probe lacking city at the quote; float repaid; empty purse -> smaller quantity, never below zero |

**Cost rule:** measure the daily job per call on prod-like I/O before enabling; nothing slow inside the beat. Prod reads are pure SELECTs, one statement per file.

## 9. Not in v1

Pirate attacks (#268), player-owned cargo ships, cross-nation convoys, loans (the bank), insurance, convoy escorts, gold as a goods item with a price.

## 10. Open questions for the owner

1. Free funds or a loan for the capital's gold? (default: free funds, the bank does loans)
2. Two cargo ships per nation fine, or one per city pair on demand?
3. May a nation's capital fund another nation's city? (default: no)
4. Should the goods run wait until the gold run has been watched for a few days? (default: yes)
