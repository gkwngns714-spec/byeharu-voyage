# 0369: supplies have their own space (lights `ship_stores_separate`)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."*
Owner, 2026-10-26 (row 221): *"separate cargo space so that provision is set differently by ship."*

0345 built the supply room dark (`docs/dev-log/2026-11-10-ship-stores.md`). This is the light: one migration, in the form of 0178 and 0179. **Nothing here was run on production. No switch was touched.** Everything below was measured on the local PGlite world, from the cached prefix at `origin/batch-6` (0364, 0366, 0367 beneath).

## What the file does
`supabase/migrations/20260818000369_supplies_have_their_own_space.sql`, one DO block:
1. **Refuses** unless 0345's readers, `world.trip_cost` and the news exist, and the switch row reads exactly `false`.
2. **Refuses** if any fleet with a leg under way or a stop on a standing route could not carry its longest leg in its supply room. This is `impact.sql`'s `short_lit`, spelt with the live `public.ship_stores_space`.
3. Writes the one row (`value` true, a note on the description).
4. Lit, on the real judge: every company fleet and the first 20 merchant fleets with such a leg carry it by `public.supply_reach`.
5. A probe house, rolled back: hold brimmed with cargo, casks empty. Cargo room is the hold less the cargo; PROVISION FULL fills her supply room to the ton; her view serves `stores_cap`; with the switch set back inside the probe the dark figures return (the rollback, played).
6. No function moved, no other knob moved. One news row: **"Supply room: the hold is all cargo" / "보급 창고: 선창은 전부 화물"**.
7. Budget 30 s (statement timeout 60 s, lock timeout 5 s).

## What was owed, and what was found
The audit: 0360 (`world.trip_cost`) and 0361 (Trade's board) call `public.ship_stores_room` but had no lit proof.

**Found: nothing to fix.** Proof 70 (`scripts/db/proofs/70_supplies_have_their_own_space_lit.sql`) takes the case only the lit world allows, a hold brimmed with cargo and empty casks, reads the board and the trip, then sails it by the real commands:

| Marker | Result |
|---|---|
| LIT_BY_0369 | the chain leaves the switch true, one news row |
| LIT_DARK_WOULD_REFUSE | with the switch set back, 183 t of cargo in a 183 t hold: SAIL OPO refused `E_ENDURANCE`, nothing bought |
| LIT_ROW_IS_THE_TRIP | abalone to TOR via OPO: supplies 19, wages 120, dock fees 541, port time 60 s. The board and `world.trip_cost` say the same |
| LIT_SUPPLIES_CHARGED | 19 charged over 2 departures, as read; at most 4.90 t aboard in a 26 t supply room, cargo untouched |
| LIT_DOCK_FEES | 541 over 2 arrivals, as read |

Once 0369 is in the chain, proofs 62 and 63 also run lit (they do not set the switch): both were written against `public.ship_stores_room`, so they hold either way. Proof 52 sets the switch itself, both ways.

## Measured (local, this PC)
- The file on the cached world: 0.10 s. The local world has **no** fleet with a leg under way or a standing-route stop, so the precondition read counted 0 fleets there.
- So the read was run on a scratch scene (not committed): every fleet given a standing route with one 1,500 nm stop. **850 fleets: precondition read 1.3 s, lit `supply_reach` on 33 fleets 69 ms, probe 31 ms, green.** Prod has about 900 such fleets (881 on 11-10).
- The same scene with one company's stop set to 30,000 nm: **refused**, "1 fleet(s) (1 of them a company's) could not carry their longest leg".
- The file run a second time on a world where it is applied: **refused**, "ship_stores_separate is not false in this world".
- `after-light.sql` and `impact.sql` run on the lit local world; `rollback-0369.sql` run on it: green.
- `impact.sql`, local world: human 16 ships, 3 over their room (they keep it); merchants 892 ships, 0 over; least lit days 90.5 / 84.3.

## Specs
No spec names the switch. A new one, `tests/fleet.supplyRoom.spec.ts`, reads the lit row on the Fleets page at 390 px, English and Korean ("Supply room 8/26 tons", "보급 창고 …톤"). The specs that read holds and supplies were run on the lit build (results in the PR).

## What a player sees the moment it is lit
- Hold bars count goods only. A ship's whole hold is cargo room.
- Fleets, her fleet: a new row **Supply room 8/26 tons** above "Supplies N days".
- A full hold still sails: the SAIL buys the leg's supplies into the supply room.
- A leg too long for the supply room reads "Supplies short: can carry X, crossing needs Y".
- A ship that carries more supplies than her room (3 human ships on 11-10) keeps them until eaten.
- One news row.

## Decided by default
- The precondition counts a voyage under way as well as standing-route stops, as `impact.sql` does. A voyage under way is not touched by the light (her supplies are aboard), but a company that could not repeat the leg she is on should stop the deploy and be read first.

## Rollback
One line (owner only): `update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';`
As a migration: `scripts/ops/harness/ship-stores/rollback-0369.sql` (a draft; strip its guard line, number it, add its news line).

## Not proven
- Nothing ran on prod. The precondition read's time on real Postgres with prod's fleets is not known; `after-light.sql` is the same read and can be timed read-only before the deploy.
- Two human ships in one fleet with different rolls were not walked in a browser.
