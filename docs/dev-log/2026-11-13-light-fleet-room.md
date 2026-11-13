# 0370: a company buys room and starts a second fleet (lights `fleet_room_bite`, `fleet_hard_max` 6)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."* Row 323 asks for an armada of up to six fleets. Rows 180 and 316 asked for fleets and for room bought with gold and levels.

0321 built the ladders and the move door, 0354 the buying door, #617 the Fleets page: all dark. This is the light, one migration in the form of 0178 and 0179. **Nothing here was run on production. No switch was touched.** Measured on the local PGlite world, cached prefix at `origin/batch-6`.

## What the file does
`supabase/migrations/20260818000370_a_company_buys_room_and_starts_a_second_fleet.sql`, one DO block:
1. **Refuses** unless `fleet_room_bite` reads exactly false and `fleet_hard_max` exactly 5, nobody holds bought room (`house_room` empty), the ladder can add up to 6, and 0367's `armada_fleet_max`, where it exists, is not below 6.
2. `fleet_hard_max` 5 -> 6.
3. **Refuses** if any house of any kind would stand over its lit caps: `over-caps.sql` written into the file as an assert (over_fleets, over_ships_a_fleet, over_hulls all 0), naming the houses.
4. `fleet_room_bite` false -> true.
5. A probe company, rolled back: the room read says on and top 6; both fleet steps bought at 60,000 and 1,000,000 (two SLOT rows, the gold in no purse); the third press refused `E_ROOM_BY_LEVEL`; with both Trading rungs reached she has room for six and the next press is refused `E_ROOM_TOP`; her second ship starts a second fleet; with the switch set back inside the probe a buy is refused `E_NOT_IN_USE` and the flat caps return.
6. No function moved; exactly two knob rows moved. News: **"Fleets: buy room, start a second fleet" / "선단: 자리 구매, 두 번째 선단 시작"**. Budget 30 s.

## Six fleets is one knob (the audit's section 4, checked)
- `public.fleet_room_caps`: fleets = least(`fleet_hard_max`, 2 free + Trading rungs reached (3, 6) + steps bought (60,000 then 1,000,000)). 2 + 2 + 2 = 6; only the knob held it at 5.
- **Nothing assumed five** on the Fleets page, in `world.house_room`, in the room card or in `src/`. Three test files did, and were changed (below).
- **There is no separate "sixth step".** The four rows of the ladder are the same as before (Trading 3, Trading 6, 60,000, 1,000,000); with the top at 6 all four now count. Before, a company with both rungs and one step bought was at the top and could not use the second price. The card shows each row's level or price (spec, 390 and 1280, EN and KO).
- Reaching six costs Trading 6 and 1,060,000 d. Proof 71 forms six fleets and puts them in one armada through `cmd.armada_form`.

## Two buys racing
PGlite has one connection, so two sessions cannot be raced here. What protects it, read in the live body and held by proof 71 (`LIT_BUY_ORDER`): `public.buy_room_for` takes `select ... from public.players where id = p_player for update` BEFORE it reads her caps and her bought steps. A second session waits on that row lock; when the first commits, the second reads the purse as it now is (the locked row) and, in its next statements, the new step count, so it pays the NEXT price or is refused. The write is also `on conflict (player_id, kind) do update set steps = h.steps + 1`. The proof holds the order of those reads in the function's text and that two presses in a row pay 60,000 then 1,000,000 with one SLOT row and one event each.

## The gold (decided by default; the owner may reverse)
Gold paid for room is **destroyed** (ledger kind SLOT, Stats side "removed"), as built in 0354. With the economy closed, `economy_closed_total` then stands above the real total by the SLOT sum. The other way, paying the realm's capital (`public.pay_city` in `public.buy_room_for`), is one small forward migration.

## Proofs and specs that assumed the room dark, or five (each changed here)
| File | What it assumed | Change |
|---|---|---|
| `scripts/db/proofs/29_fleet_room.sql`, `57_fleet_room_bought.sql` | "the room is not dark in this world" was a failure | They set the switch back at their start (rolled back with the proof) |
| `57_fleet_room_bought.sql` | 2 + 1 + 2 = 5 is the top | Both rungs reached: 2 + 2 + 2 = 6 (holds at 5 too) |
| `68_armada.sql` | raising `fleet_max` to 7 gives seven fleets | Also raises `fleet_hard_max` (the top, lit) |
| `tests/rpc.houseroom.spec.ts` | built world dark; top 5 | Sets its own database dark first; top 6 |
| `tests/rpc.fleetroom.spec.ts` | built world dark | Sets its own database dark first |
| `tests/fleets.room.spec.ts`, `tests/fleets.move.spec.ts`, `tests/fleetsPage.fixture.ts` | the shipped world is the dark world | The dark page is proven on a copy of the image with the switch set back (what a rollback would show) |
| `tests/manyFleets.fixture.ts` | `fleet_max` 8 gives a veteran eight fleets | Also raises `fleet_hard_max` (a layout world of eight rows) |

## In a browser, lit (headless, port 4421)
- `tests/fleets.page.spec.ts`: New fleet, Buy room (a ship place and a fleet), a ship's sheet, Move and the move back, the empty fleet: 390, 320 and 1280 wide, EN and KO. 18 passed.
- **The room card lit on a wide screen and in Korean** (the audit's "unproven"): a new test in `tests/fleets.room.spec.ts`, the world as shipped, at 390 and 1280, EN and KO: both level steps and both prices, one Buy in her language, nothing cut. 4 passed; the pictures were read.
- Run 1: 53 passed, 15 failed, all 15 in `fleets.design` and `fleets.you.grow` (the veteran fixture stopped at six fleets). After the fixture change, run 2 (`fleets.design`, `fleets.you.grow`, `layout`, `wide.layout`, `consistency`): 59 passed.

## Measured (local)
- The file: 0.31 s (over-caps read of 834 houses 234 ms, probe 35 ms).
- `over-caps.sql`, local world: HUMAN 13 houses, 0 over; MERCHANT 821, 0 over (most ships in a fleet 3 of 7).
- Proofs 71 (6 of 6), 29 (9), 57 (8), 68 (8): green.

## What a player sees the moment it is lit
- Fleets: "New fleet, Not open yet" becomes **New fleet**, a real flow (a second ship moves into a new fleet at her port; a company has two fleets free).
- The Room card: **Buy** on the next price she can pay (ships in a fleet 10,000 to 160,000; fleets 60,000 then 1,000,000). Level steps open by themselves.
- A ship's sheet: **Move**.
- One news row.
- Merchants: at most 7 ships in a fleet where it was 8.

## Rollback
One line (owner only): `update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';` Gold paid stays paid, bought room stays in `house_room` (it counts again if relit), a second fleet stays. `fleet_hard_max` may stay 6. As a migration: `scripts/ops/harness/fleet-room/rollback-0370.sql` (draft).

## Not proven
- Nothing ran on prod. `over-caps.sql` must read every `over_*` 0 the same hour, or the file refuses.
- Two real sessions buying at once (above: reasoned from the lock, not raced).
- 16 of 19 companies own one ship (11-13), so most will see New fleet say a second ship comes from a build yard.
