# CITY_CONVOYS — cargo ship ships: goods city to city, gold capital to depleted city

**Words (owner, 2026-11-05):** the ship is a **Cargo ship**; the gold is **Funds**; its load is a **Shipment**. Not "gift", not "aid".

**Status: DESIGN (2026-11-05). Nothing here is built. No migration, no code.** Prod head at writing: **0305** (0306 bank B1 in review).
**The owner (2026-11-05):** *"i need a transportation ship, cities moving trade goods to different cities, moving gold to gold. Capital city with its massive income, will provide other cities with gold when depleted."*
Every "decided by default" is mine; the owner reverses afterwards.

Standing rules kept: closed economy (no minted gold; `mint_guard` untouched), a city never below zero (0122), one place per concept, switches/knobs owner-only, ships dark.

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

- New fleet kind `CARGO_SHIP`; count per nation = knob `convoy_ships_per_nation` (default 2). Never takes a player's cargo, cannot be boarded in v1.
- Upkeep per leg comes from the capital purse (`convoy_upkeep_per_leg`, a moved flow, not minted).

**Graphics (one renderer, no fork):** ships are drawn by `src/chart/glyphs.ts` (`hullPath`, one renderer for fleets and merchants, nation ink) and chosen by `src/chart/shipMarks.ts`. So:
- `glyphs.ts` gains one new hull: wide, deep-bellied, a high stern, heavier than any merchant, and readable at small size.
- `world.sea_traffic` serves a `kind` on each row; a cargo ship picks the new hull. Nothing else in the renderer branches.
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

`convoys_enabled` false · `convoy_goods_enabled` false · `convoy_ships_per_nation` 2 · `convoy_low_water_days` 3 · `convoy_target_days` 7 · `convoy_floor` 50,000 · `convoy_cap_per_city_day` (decided at build from a prod read) · `convoy_capital_reserve_pct` 0.30 · `convoy_max_days` 10 · `convoy_surplus_pct` 0.80 · `convoy_lack_pct` 0.20 · `convoy_upkeep_per_leg`.

---

## 7. Is it needed now? (a measurement owed before lighting)

I could not show a depletion problem today: two prod reads of city purses disagreed (one used the rolled column, one a recomputed balance that came out negative for a city, so it was wrong). Before any switch is lit, a correct read of the live balance (`treasury_balance` if its volatility is stable/immutable, else the same sum the game pays against) must list: cities under 3 days of cover, by nation; the capitals' free gold; and what `CROWN_AID` / `CAPITAL_GIFT` already move per day (24 h: CAPITAL_GIFT 4 flows, -145,000 d.; no CROWN_AID). If few cities are short, the gold run ships dark and waits.

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
