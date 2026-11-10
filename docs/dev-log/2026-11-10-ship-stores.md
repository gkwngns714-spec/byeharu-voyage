# 0345: stores have their own space (owner row 221)

Owner, 2026-10-26: *"separate cargo space so that provision is set differently by ship."*

Design: `docs/SHIP_STORES_AND_VARIETY.md` §1 (branch `osn-ship-stores-variety`, commit f2cad0bd, written at head 0235). This is its slice V2, checked against the live chain at head 0344. The variety half (row 222, V1+V3) is already live as 0276: every hull carries `roll_stores`, which nothing read until now.

## What was there
One pool. `public.fleet_free_hold` = hold − cargo − water − food, and every stores top-up (`public.stores_topup`) fills "the room beside her cargo". So a full hold meant short stores, and 0231 had to cap a passage by the stores that fit beside the cargo.

## What 0345 does (dark)
- Switch `ship_stores_separate` (false; owner only). Knob `ship_stores_days` (36).
- Her **stores space** = `floor(ceil(class crew_max × (water + food per crew day) × 36) × roll_stores)`. Barca and barque 26 t, carlat 38 t, nau 177 t at roll 1.000. About 90 days at the crew she needs.
- Five small readers: `ship_stores_separate()`, `ship_stores_space(ship)`, `ship_stores_room(ship, dark)`, `stores_in_hold(tons)` and `ship_stores_card(ship)`. All are STABLE, definer and server-only.
- 13 hunks over 11 live bodies (head 0344), each one occurring once and reversing to its pre-image:
  - Cargo room is hold − cargo when lit: `fleet_free_hold`, `fleet_load`, and `good_board`'s `units_fit`.
  - Every stores top-up fills her stores space when lit, whatever her cargo, and FULL fills it: `cmd.do_provision` (both passes), `supply_needs` (0225's `fits`, `tons` and `cost`), `supply_reach` (0231's cap), `npc_provision_for` and `fleet_stores` (a crown's free top-up).
  - `npc_casks_blocked` is never true when lit, because selling cargo frees no stores room.
  - `world.ship_view` adds `stores_cap` when lit. `voyage.leg_refusal` changes its words to "her stores space carries…" and adds the figure `stores_space: true` when lit.
- Client:
  - When `stores_cap` is served, supplies leave the hold. The hold bars and figures count goods only (`shipStoresInHold`), and the Hold breakdown drops its Supplies bar.
  - Fleets → Stores shows a new row, **Supply room / 보급 창고** `8/26 tons`.
  - A shut desk row reads **Supplies short: can carry X, crossing needs Y / 보급 부족: …** instead of "Hold too full" (docs/WORDS.md: "supplies", never "stores", in player text).

## What a player sees when it is lit
- A ship's hold is all cargo. Buying fills the whole hold, and the stores no longer eat into it.
- The Fleets page shows the stores in their own row, for example `Supply room 8/26 tons`. The hold breakdown has Trade goods and Empty only.
- A full cargo hold still sails. The SAIL buys the leg's stores into the stores space. Proof 52 shows this: a barca with 182 t of cargo in a 182 t hold is refused dark and sails lit.
- A leg that is too long for the stores space reads "Supplies short: can carry X, crossing needs Y".

## Dark parity
- **By construction.** When dark, each reader returns its argument, `'{}'` or false, so every re-cut body computes what it computed before.
- **Asserted in the migration.**
  - The whole world's `fleet_free_hold`, `supply_reach`, `supply_needs` (500 nm and 2,000 nm) and `world.ship_view` (every ship) give the same md5 before and after the hunks.
  - A probe company's barca, with a fixed id so her roll is the same every time, runs before the hunks and again after them while dark. It provisions 20 days, loads to the brim, reads free hold, reach and needs, gets a leg refusal, reads `npc_provision_for`, provisions FULL (refused E_HOLD_FULL), takes a crown's 90-day top-up, and reads her view. The two runs give the same jsonb.
- Lit probe: space 28 t, 210 loaded against 196 dark, free hold 0, the days her stores carry are not moved by the cargo, and FULL fills exactly to the space.

## Prod, read only, 2026-11-10, head 0344
- `scripts/ops/harness/ship-stores/before.sql`: all 13 hunks occur once (`old_times` 1, `new_times` 0), nothing of 0345 exists yet, head 20260818000344.
- `volatility.sql`: every function `impact.sql` calls is STABLE.
- `impact.sql` (what lighting it would do):

| | Humans | Merchant / crown / pirate houses |
|---|---|---|
| Ships (fleets) | 22 (19) | 1,304 (1,246) |
| Stores aboard = cargo room given back | 273.6 t | 21,766 t |
| Stores space made | 596 t | 129,604 t |
| Ships holding more stores than their space (they keep them; no refill past it) | 3 | 41 |
| Least lit stores-days of any crewed fleet | 37.1 | 71.4 |
| Median lit stores-days | 92.9 | 90.5 |
| Fleets with a leg under way or on a route | 0 | 881 |
| Longest leg asked, in stores-days | none | 53.8 |
| Fleets that cannot carry their longest leg: today → lit | 0 → 0 | **6 → 0** |

## Decided by default
- **36 days at full crew** (the design's figure), as the knob `ship_stores_days`. Space is read from the class `crew_max` and her 0276 roll. The quartermaster's stretch is not applied, because Provisioners already stretch the days.
- **No backfill.** A hull that carries more stores than her space keeps them until they are used. A top-up then adds nothing. No row is written, so the dark world is exactly the world before 0345.
- **Stores still weigh**: `ship_speed_at`'s fill stays (cargo + stores) / hold, so speed is the same lit and dark.
- **One rule for every house.** When lit, a crown's 90-day free top-up fills her stores space and no more.
- `store_ratio` is unread when lit. Dropping it is a later slice (design V4).

## Proofs
- Migration self-assert: the catalog, world parity, and probe parity (above). The new readers are server-only, and the registry and the walls are unmoved.
- Proof 52 (`scripts/db/proofs/52_stores_have_their_own_space.sql`) walks the real paths: `new_house`, a hold brimmed with cargo, SAIL through the client door (`proof.sail`), PROVISION FULL, and `ship_view`.
  - **Red first** on head 0344 (without the migration): "lit, a hold brimmed with cargo could not SAIL LIS -> CAD … E_ENDURANCE".
  - **Green** with 0345: 4/4 markers.
- Older proofs re-run locally, all green: 01, 04, 05, 07, 10, 11, 12, 18, 29, 30, 35, 36, 37, 40, 46, 47 and 48.

## Rollback
Lit: `update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate'`. The world is back to before 0345 at once. To remove it entirely, a forward migration swaps the hunks back (every old text is in 0345 word for word) and drops the readers and the knobs.
