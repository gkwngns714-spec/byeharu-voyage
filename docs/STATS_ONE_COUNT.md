# The Stats count once

**The rule (owner, 2026-11-16: "make it so that this error does not happen again").** Which state a fleet is in is decided in ONE
function, the fleets are counted in ONE function, and every Stats face prints that one count. Nothing else decides, counts or adds.

## The definitions

A fleet is in **exactly one** state, the first of these that is true (`public.fleet_state_of`):

| state (the server's key) | the word (EN / KO) | it is true when |
|---|---|---|
| `laid_up` | Laid up / 정박 보류 | a merchant's route is paused `laid_up`; a navy, pirate or cargo ship has `laid_up_at` |
| `wrecked` | Wrecked / 난파 | no hull above 0 (or no ship), a pirate's wreck lies at home (`wrecked_at`), or the status is `UNABLE_TO_SAIL` / `ADRIFT` |
| `battle` | In battle / 전투 중 | she is on a side of a battle that is `FIGHTING`, or her status is `IN_BATTLE` |
| `sea` | At sea / 항해 중 | her status is `SAILING` |
| `port` | In port / 입항 | anything else (`DOCKED`, `ANCHORED`, `REPAIRING`) |

- **Counted:** every merchant fleet, navy ship and pirate ship, and every cargo ship in service. A **retired** cargo ship
  (`cargo_ships.laid_up_at`) is hidden on every face and in no count.
- **The unit:** the five states count **fleets**. The faces show "Fleets" and "Ships" each under its own word, and the bar says "By fleet".
  The count also carries the ships in each state (`ships_by`).
- **The identity:** `fleets = sea + port + battle + laid_up + wrecked` and `ships = the sum of ships_by`, for every kind, on every face.
- **The time:** every state on a Stats face is the Stats count's (four an hour), written by one statement, under one "Counted" time. Only a
  fleet's own page is live (one fleet, by the same rule, as of now).

## Where it lives

| | |
|---|---|
| the rule | `public.fleet_state_of(laid, wrecked, battle, sailing)` |
| the facts of every fleet | `public.fleet_census(fleet)`: kind, state, ships, counted |
| one fleet's state | `public.fleet_state(fleet)` |
| the count | `public.fleet_tally()`: per kind `fleets, ships, sea, port, battle, laid_up, wrecked, ships_by` |
| stored by | `public.tick_stats` (ONE statement: `public.stats_fleets_count` and `public.stats_fleet_list_rows`) |
| read by | `world.stats_fleets` (Ships), `world.stats_merchants` (Merchants), `world.stats_fleet_list` (Navy, Pirates, Cargo), `world.stats_fleet` (a page) |
| the client's words | `src/features/stats/fleetStates.ts`; drawn by `src/features/stats/FleetStatesBar.tsx` |

## If you add a state, a kind or a counter

1. A new **state** is a new line in `public.fleet_state_of` (and its fact in `public.fleet_census`), a new key in `public.fleet_tally`, and a
   new row in `fleetStates.ts` with its word in `src/lib/i18n/dict/stats.ts`. Nowhere else.
2. A new **kind of ship** is a new branch of `public.fleet_census` and a new kind in `public.fleet_tally`.
3. A new **face or figure** that says where ships are reads the stored count (or `public.fleet_tally` / `public.fleet_state`). It never writes
   a `case ... then 'sea'` of its own, never counts a ship table itself, and never adds or subtracts served figures on the client.
4. A count of **events** (wrecks in 24 h, fights) is not a state and does not use a state's word ("Wrecks", not "Wrecked").

## What holds it

- `scripts/db/proofs/150_the_stats_count_once.sql`: a world with every state (a wreck, a lay-up, a battle at sea and in a harbour, a hidden
  retired cargo ship): one state a fleet; the identity for every kind; after a Stats count the Ships face's card equals each kind's own face
  and each list's rows; **no other function of the game chooses a state word in a `case`**; the count writes its row and lists in one statement.
- Migration 0448's own self-assert: the rule's whole truth table, and the same equalities on a rolled-back probe at every deploy.
- `tests/stats.oneCount.spec.ts`: the five words are spelled in one client file; every face draws through `<FleetStates>`; no Stats face
  computes with a figure of the count; the client's states are the server's five.
- `scripts/ops/harness/stats-one/after.sql`: the same check on production, read-only (`ok` true).

## Not part of the count (on purpose)

- The Stats strip's **"Fleets at sea"** (`world.stats_now.at_sea`) is the live journal of every fleet under sail, the players' too; a fleet held
  in a fight at sea is under sail there. It is a live figure of another question, not one of the five states.
- `public.merchant_doing_at` (what one merchant is doing, on her map card) and `world.report` (where a bug report was written) use the words
  `laid_up` and `port` for other things. Proof 150 names these two; a third fails it.
