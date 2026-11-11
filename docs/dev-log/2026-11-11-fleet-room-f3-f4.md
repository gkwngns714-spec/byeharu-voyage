# 2026-11-11 - Room is bought, and a fleet reads its totals (migration 0354, F3 + F4, DARK)

Branch `fleet-room` · migration `supabase/migrations/20260818000354_room_is_bought_and_a_fleet_reads_its_totals.sql` · proof `scripts/db/proofs/57_fleet_room_bought.sql` · seam `tests/rpc.houseroom.spec.ts`, `tests/fleets.room.spec.ts` · harness `scripts/ops/harness/fleet-room/` (`proof-0354.mjs`, `gen-checks-0354.mjs`, `before-0354.sql`, `after-0354.sql`, `volatility-0354.sql`, `over-caps.sql`, `after-light.sql`, `cost-0354.sql`).

## The order
Owner rows 180 and 316: *"multiple fleets, with multiple ships"*; *"unlock slots by purchasing with gold, and some with levels"*; *"Show stats of individual ship and also as a fleet"*. `docs/SUCCESS_PLAN.md` section D: F4, F3 and the rename door, as one migration, with a small client. Design: `docs/FLEETS_AND_SLOTS.md`.

**Nothing here was run on production and no switch or knob was touched.** Everything below was measured on the local PGlite world, from the cached prefix at head 0350.

## What is built
| Part | Where |
|---|---|
| A fleet's totals | `public.fleet_totals(fleet, ships)`, served as `totals` on `world.fleets()` (two hunks) |
| The room and how more opens | `world.house_room()`, STABLE; its rows by `public.room_steps` |
| Room is bought | `public.buy_room_for(player, kind)`, door `cmd.buy_room(kind)`; writes `public.house_room` |
| A fleet is renamed | `public.rename_fleet(player, fleet, name)`, door `cmd.rename_fleet(fleet, name)` |
| The gold | ledger kind `SLOT`, `public.stats_flow_words` side `removed`, word "Fleet room" |
| Events | `ROOM_OPENED {kind, step, price, room}`, `FLEET_RENAMED {from, to}` |
| The news | one `public.news_update('0354', 'Fleet totals, rename', '선단 합계, 이름 변경')` row, outside the probe (0347's law, `tests/news.lint.spec.ts`). Buying room is dark and is not announced: that news belongs to the step that lights `fleet_room_bite` |
| The registry | three rows in `public.client_rpc_entry_points` (one hunk) |
| The client | `src/features/fleets/FleetTotals.tsx`, `RenameFleet.tsx`, `FleetRoom.tsx`; types, catalogue, words EN and KO |

No knob is written. `public.earned_caps`, `public.house_ship_max`, `public.fleet_room_caps` and `public.assert_house_caps` are not cut: since 0321 the caps read `house_room` only while lit, and this file only gives that table its writer.

### The totals (F4)
`world.fleets()` now builds a fleet's ship list once, in a lateral, serves it as `ships` as before and hands the same list to `public.fleet_totals`. So a total cannot disagree with the ships drawn under it:
`ships`, `attack`, `hull`, `hull_max`, `crew`, `crew_required`, `crew_max` (sums of the `world.ship_view` figures), `short_crew` (names), `wages_day` (`public.fleet_wage`, the figure `voyage.settle` charges) and `slowest` (`{id, name, speed}`, the ship `voyage.fleet_speed_at` takes its minimum from).

### The room (F4) and the price ladder as served (F3)
`world.house_room()` answers, for fleets and for ships in a fleet: `have` (what the caps trigger enforces now), `ladder` (what the steps add up to; the same while lit), `top`, `free`, `used`, `bought`, `full`, `price` (the next step's, or null) and `steps`. Also `on` (is fleet room lit), `purse`, and `hulls {have, used}`.

| ladder | free | level steps | gold steps, in order | top |
|---|---|---|---|---|
| Fleets | 2 | Trading 3, Trading 6 | 60,000 then 1,000,000 | 5 |
| Ships in a fleet | 2 | Seamanship or Command 1, 2, 3, 4, 5 | 10,000, 20,000, 40,000, 80,000, 160,000 | 7 |

A company has `free + level steps reached + gold steps bought`, at most `top`. That rule is 0321's (`public.fleet_room_caps`); this file only prices it. The Nth step a company buys of a kind costs the Nth figure of the knob (`fleet_room_prices`, `ship_room_prices`).

Refusals, each before anything moves: `E_NOT_IN_USE` (dark, or a merchant), `E_PARSE` (not FLEET or SHIP), `E_ROOM_TOP` (already at the top, with both figures in the sentence), `E_ROOM_BY_LEVEL` (every price used and room still to open), `E_INSUFFICIENT_FUNDS` (with `figures {have, need, unit: ducats}`). The house row is locked first, so two presses cannot buy one price.

### The rename
A fleet of hers, in any state: docked, at sea, in a battle, empty. Dark or lit. The name's rules are the table's own (`fleets_name_check` 3 to 24 letters, `fleets_player_name_unique`): the constraints judge, as `cmd.found_house` lets them for a company. `E_BAD_NAME`, `E_NAME_TAKEN`, `E_NO_SUCH_FLEET`. The same name again writes nothing. `fleets.version` does not rise.
Checked: nothing keys on a fleet's name except `public.tg_ledger_points`, which reads the name at the moment an event is written; `world.sea_roster` serves merchants only.

## Could lighting `fleet_room_bite` break an existing company? (asked before anything was built)
Read: `public.earned_caps`, `public.house_ship_max`, `public.fleet_room_caps`, `public.assert_house_caps`, `public.tg_house_caps`, and every caller of `public.form_fleet` and `public.commission_ship`.

- The caps are enforced by ONE trigger function (`tg_house_caps` → `assert_house_caps`) on `ships` (insert, or update of `fleet_id` / `player_id`) and on `fleets` (insert, or update of `player_id`). A house over a cap is refused only on her next new ship, new fleet or moved ship. Voyages, trades, repairs and crew writes never fire it.
- **Every house that is not a human** (`is_npc`): lit, `fleet_room_caps` answers fleets = `fleet_max` (2, the same as dark), ships a fleet = least(`fleet_ship_max` 8, `fleet_ship_top` 7) = **7** (dark: 8), and `house_ship_max` is unchanged (0321 keeps it for a merchant).
  - Crown cargo ships, navy ships and pirate ships: each is its own house with one fleet of one ship (`cargo_ships_commission`, `navy_commission`, `pirate_commission` insert a new `players` row per ship). 1 fleet ≤ 2, 1 ship ≤ 7. `cargo_hull` deletes her hull and lays one: still 1. They cannot be over, lit.
  - Merchants (`npc_found`): at most 2 fleets (the flat cap, unchanged). The only lit change is the 8th ship in one fleet. Local world: largest merchant fleet 3 ships (788 of 1, 43 of 2, 6 of 3).
- **Humans.** The only door to a second fleet is `cmd.move_ship`, dark, so a human has one fleet. Her dark cap for that fleet is least(8, 2 + Seamanship); `skill_max_level` is 5, so at most 7. Lit: ships a fleet = least(7, 2 + greatest(Seamanship, Command) + bought) ≥ her dark cap, fleets ≥ 2, hulls = fleets × ships a fleet ≥ 2 × her dark cap. A human who is inside her dark caps is inside her lit caps.
  - What does shrink for a human is the hull cap for FUTURE growth: 8 + Command dark, fleets × ships lit (4 for a new company). With one fleet that never bites before the per-fleet cap does.
- **No NPC maker reads a cap itself.** The knobs `fleet_max`, `fleet_ship_max`, `ship_max` are read only by `earned_caps`, `house_ship_max`, `fleet_room_caps`, `world.ship_moves` and `world.snapshot`.

**Answer: by the code, no existing company can stand over the lit caps, and no fix is needed in this migration.** The two ways the code could be wrong are data it cannot see: a merchant fleet of 8 ships, or a human with a fleet larger than 2 + her skill (a hand-made row). `scripts/ops/harness/fleet-room/over-caps.sql` counts both on prod, per kind of house, read-only, with the names of any house over a cap. It calls `public.fleet_room_caps` and `public.house_ship_max`, both STABLE, neither reads the switch. On the local world: HUMAN 13 houses, 0 over; MERCHANT 821 houses, 0 over (most fleets 2 of 2, most ships a fleet 3 of 7, most hulls 5 of 8).

## Where the build differs from `docs/FLEETS_AND_SLOTS.md`
- **Buying is dark with the room** (`E_NOT_IN_USE`). The F3 row says "No while dark". Room bought dark would be gold paid for nothing: the dark caps do not read `house_room`.
- **A price belongs to a company's Nth bought step, not to a numbered fleet.** Section 2.2's table reads "3rd: Trading 3 or 60,000 · 4th: Trading 6 only · 5th: 1,000,000 only". 0321 built the caps as a sum (free + rungs + bought), which the design also says for ships. Under a sum, a company at Trading 6 opens her 5th fleet for 60,000, and a company with no level buys her 3rd and 4th (1,060,000) and needs Trading 3 for the 5th. To price by the fleet's number needs a new knob and a re-cut of `fleet_room_caps`; not done.
- **The gold is destroyed, as the design says (Q6), but the younger `docs/CLOSED_ECONOMY.md` section 2.3 says every ducat is always in a purse** and measured "removed = 0". `SLOT` is the first `removed` kind. With the economy closed, the world's total falls by what is paid and `economy_closed_total` stands above the real total by the SLOT sum. `public.mint_guard` is asked only for a positive delta, so nothing refuses it (proved with both flags set). Stats already has the side (`stats_sides.removed`, drawn "Burned"). **The owner's call before F6.** To pay the realm's capital instead: `public.pay_city` in `buy_room_for` and the word `moved`, one forward migration.
- **`totals` carries no berth count.** That is `public.earned_caps`, which reads `public.player_progress`; `world.fleets()` is asked every 30 s by every client. `world.house_room()` serves it, asked when the Fleets page opens.
- **No count of guns.** No ship read serves one. `attack` is the sum of the ships' attack. "Crew able to board" is not served either.
- **The rename door is new.** The design has none (Q10 only says an empty fleet "can be renamed").
- **The client is part of F5, early:** the totals line, Rename, and the room rows with one Buy. The rest of F5 is not here.

## Decided by default (the owner may reverse)
- One switch still: `fleet_room_bite` lights the ladders, the move door and the buying door together.
- A fleet may be renamed anywhere, and the version stands.
- The ledger kind keeps the design's name `SLOT`; the player reads "Fleet room" (`docs/WORDS.md` bans "slot" in player text only).
- In the Money log's filter a room buy files under Fees.
- The room card prints "used / room now" for each kind ("Fleets 1 / 2"), the Levels page's reading, and each step on one short line.

## Measured (local PGlite, cached prefix at 0350, this PC)
- The file applies in 0.72 to 0.95 s, self-assert included (budget 45 s). 3 hunks, each once and reversing.
- **`world.fleets()`, OLD body against NEW, interleaved, 60 pairs a house (`cost-0354.sql`, three runs):**

| house | OLD ms | NEW ms | difference | `fleet_totals` alone |
|---|---|---|---|---|
| 1 fleet of 1 ship (most of prod) | 2.83 to 2.90 | 2.93 to 3.00 | +0.05 to +0.12 | 0.07 to 0.08 |
| 2 fleets of 2 | 9.52 to 9.77 | 9.58 to 10.07 | +0.07 to +0.30 | 0.13 to 0.15 |
| 5 fleets of 7 (the most there can be) | 75.5 to 77.1 | 76.0 to 77.0 | -0.12 to +0.55 | 0.40 to 0.42 |

  The added work is `public.fleet_totals`: one walk of a list already in memory and one `public.fleet_wage` call a fleet. It reads no ship a second time. On the common house that is 0.07 to 0.12 ms on 2.9 ms (PGlite's clock steps are about 0.02 ms at 60 pairs); on the largest it is inside the run-to-run noise. The file's own self-assert prints the same comparison on its probe (7.5 to 7.9 ms OLD, 7.5 to 8.0 ms NEW, 40 pairs).
- `world.house_room()`: 1.45 ms on the 5 × 7 house. Asked when the Fleets page opens and on the world's beat while it is open, not by every client.
- `over-caps.sql` on the local world (834 houses): 120 to 150 ms.

## Checks run
- The migration on the cached prefix: green more than 12 times (alone, with the proofs, with the checks, with the cost scene, and after 0351 and 0352 applied first from their branches). Its first run was red on one of the file's own asserts (a ledger row picked by an order the table does not have); the assert was fixed.
- Proof 57: 8 of 8 markers. Proof 29 (0321's) on the same world: 9 of 9. Proof 57 without the file: red.
- `proof-0354.mjs`: 23 of 23 mutations red for the intended reason. One candidate was dropped as not a mutation: removing the door's own short-of-gold test changes nothing a caller can see, because `public.credit` refuses with the same code and figures.
- The five PROD CHECK files run on the local world before and after the file: before, 3 hunks old 1 / new 0, nothing made; after, 3 hunks new 1, attrs equal, registry 3, `SLOT` removed, `house_room` 0 rows, dark.
- `tsc -b`, `eslint .`, `vite build` (world image from the cached prefix): clean.
- Specs, headless, served build on port 4871, one worker: `fleets.room` 2, `rpc.houseroom` 4, `rpc.fleetroom` 2, `rpc.surface` 29, `fleets.move` 2, `fleets.design` 12, `fleets.you.grow` 5, `fleet.supplies` 1, `sections` 8, `duplication` 11, `harness.guard` 4, `stats.moneySectors` 1, `words` 1, `verbHomes` 4, `consistency` and `layout` whole 36, `wide.layout` whole (see the last line of this list). All passed; none skipped.

## PROD CHECKS (read-only; `npx --yes supabase@2.120.0 db query --linked -f <file>`)
1. `scripts/ops/harness/fleet-room/volatility-0354.sql`: every function "called by a check" reads `s` or `i`.
2. `scripts/ops/harness/fleet-room/before-0354.sql`: head 0353; every hunk `old_times` 1, `new_times` 0; `made` all null; `fleet_room_bite` false; `house_room_rows` 0; `slot_word` null; `removed_kinds` []; `premises` all true. `ord_56_is` null (if 0351 to 0353 took 56 it is only a sort order; say so).
3. `scripts/ops/harness/fleet-room/over-caps.sql`: every `over_*` 0. Not needed to deploy (the file is dark); needed before F6.
4. After the deploy, `after-0354.sql`: head 0354; every hunk `new_times` 1 (`client_rpc_entry_points` `old_times` stays 1: its old text opens the new); `attrs` equal to before's; dark; `house_room_rows` 0; `slot_word` removed / Fleet room / 56; `registry` 3; `probe_left` 0.

No after-check window is owed for the deploy: dark, the only things that change are a new key on a read, a new read, and the rename door.

## What lighting the switch needs (F6, not now, the owner's)
1. F5 on the page first, or lighting gives a player a Buy and a Move but no New fleet flow.
2. The owner's answer on destroyed gold against the closed economy (above).
3. `over-caps.sql`: every `over_*` 0, read the same hour.
4. `after-light.sql` once before (every figure 0), then the switch, then `after-light.sql` every few minutes for 30 minutes: `unbalanced` 0, `past_top` 0, `merchant_rows` 0, `room_events` = `steps_held`.
5. Rollback, forward: `fleet_room_bite` false. The caps return to today's at once. Gold already paid stays paid and its `house_room` rows stay (they count again if it is relit). A second fleet already formed stays a fleet; a company holding more than the dark caps allow keeps what she has and is refused her next new ship or fleet.

## Not proven
- Nothing ran on production: not the file, not the checks, not `over-caps.sql`. The answer on NPC houses is from the code and the local world.
- 0353 (the fight log) was not available: the file was applied after 0351 and 0352 only. It is green there. If 0353 cuts `world.fleets()` or the `ship_moves` row of the registry, `before-0354.sql` shows it (a hunk not at 1).
- The cost on real Postgres with prod's data: PGlite only. The shape (no second ship read, one wage call a fleet) is what carries over, not the milliseconds.
- Two real clients buying at once: PGlite has one connection. The house row lock is reasoned, not raced.
- The room card with the room lit on a wide screen, and in Korean: the lit browser test runs at 390 wide in English and reads no picture.
- A rename while the fleet is in a battle or under repair: the proof renames docked, at sea and empty.
