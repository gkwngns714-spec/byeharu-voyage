# 2026-11-13: a wall says what is short (migration 0376, branch `seas-wall`)

**Owner rows 166** ("in order to sail far distance, one needs better ship and levels") **and 324** ("do all, make everything work. open them if everything is built and is workable"). Design: docs/SEA_CONDITIONS_AND_REGIONS.md. The wall itself (0215, 0216, 0219, 0222) is on prod, dark behind `sea_conditions_bite`. This file serves what a screen needs before the wall can be lit. **It lights nothing and is not deployed by this PR.**

## What landed

| # | Piece | What it does |
|---|---|---|
| 1 | `public.sea_refusal` (1 hunk) | `figures` gain `short_title` and `short_wave`: which ask is above hers; false when her figure is null. The sentence, the order and the six old figures are unmoved. Still the one place the comparison is written. |
| 2 | `public.far_powers()` (new, internal) | The nations whose capital harbour's own sea asks a title above 1. The harbour's sea is its self row in `public.sea_leg_asks` (`zones[1]`, 0222): a primary-key probe, no raster read. Asserted equal to the raster reading (`public.harbour_zone`) for every nation. |
| 3 | `cmd.found_house` (1 hunk) | While `public.sea_conditions_on()`, founding under a far power is refused `E_FAR_POWER`, in this function's own answer shape (`ok: false`, `error_code`, `error_message`, `fixes`) plus `figures {nation, capital, zone, zone_name, needs_title}`. Dark, the block is not entered. |
| 4 | `world.sea_conditions()` (3 hunks) | `zones[].harbours`; `fleets[].port` (null at sea); `fleets[].seas`: only the zones that refuse her, keyed by zone code, each the whole `figures` of `public.sea_refusal` for that zone; top-level `far_powers`. Served dark and lit. |
| 5 | `world.route_legs` (1 hunk) | Each leg gains `sea`: lit, for a leg shut by its length or its stores with no harbours between, `public.sea_gate`'s refusal on the direct course; null otherwise and always while dark. The gate order is not changed. |
| 7 | `cmd.refusal_caught` (1 hunk) | The one catcher of a raised refusal kept figures only in `cmd.figures`' shape `{have, need, unit}`, so an order refused `E_SEA_CLOSED` (`cmd.preview`, `cmd.issue`, `cmd.issue_lines`, `cmd.execute_order` and so `orders.error_figures`, the armada verbs) reached the client with a sentence and no figures. It now also keeps the sea rule's shape (`zone` a string, `needs_title` and `needs_wave` numbers). The have/need/unit test is the same text, every other shape is still dropped, it stays IMMUTABLE. Found by the client builder driving the lit Map. |
| 6 | `world.sea_zone_map()` (new, registered read) | `{cols 1440, rows 720, cell_deg 0.25, codes, runs}`: `public.sea_zone_cells` run-length coded by row ("value:count,..."); a byte is `sea_zones.ord`, 0 is land or water with no zone, `codes[0]` is null. Granted as `world.sea_conditions` is (authenticated only), one registry hunk. |

Client: `src/lib/rpc/catalog.ts`, `index.ts` (`worldSeaZoneMap`), `types.ts` (`SeaZoneMap`; the new keys, every one optional because prod serves the old shape until the deploy), `tests/rpc.surface.spec.ts` (the pin). No screen is in this PR.

## Functions cut, and who cut them last

| Function | Last written or cut by | This file's anchor |
|---|---|---|
| `public.sea_refusal(integer,numeric,text[])` | 0215 (whole) | the `'needs_wave', z.wave_min, 'wave', p_wave))` line |
| `world.sea_conditions()` | 0215 (whole) | the `v_title` declaration, the zone row's first line, the whole `fleets` expression |
| `cmd.found_house(text,text)` | 0338 (the `E_MINOR_POWER` door); 0354 calls it and does not cut it | the comment line above the `public.new_house` block |
| `world.route_legs(uuid,jsonb)` | 0346 (whole); 0360 and 0361 read beside it | the `'via', v_via));` line |
| `public.client_rpc_entry_points()` | 0367 (armada rows), 0364, 0360 | the `world.sea_conditions` row (0215) |
| `cmd.refusal_caught(text,text)` | 0050 (whole); never cut since | the `if v_figs is null` line |

Not touched: `world.good_board` (0361), `voyage.settle` (0362, 0367), `public.sea_gate`, `public.passage_gate`, `public.sea_routes`, `voyage.reach_passage`, every merchant reader. The self-assert digests every other function of `public`, `cmd`, `world` and `voyage`, every `world_config` row and the list of relations, before and after.

## Measured (local PGlite world, cached head 0367; prod is a different machine)

| Read | Before | After |
|---|---|---|
| `world.sea_conditions()`, a company of five one-barca fleets | 3.4 ms, 13.5 KB | 16.4 to 17.0 ms, 56.6 KB |
| `world.sea_zone_map()` | (new) | 134 to 137 ms, 63 KB |
| 320 calls of `public.sea_refusal` on their own | 5 to 8 ms | |
| The migration, apply and self-assert | | 0.7 to 1.1 s (budget 45 s) |

- The first cut of hunk 5 read 117 ms: the planner flattened the lateral that reads the fleet's wave, so `public.fleet_wave` ran once a zone (320 times) instead of once a fleet. `offset 0` on that lateral fixed it. The self-assert prints the timing at every apply.
- The payload grew to 56 KB for five fleets because `seas` carries the whole figures of every refusing zone (the client asked for them, to save a round trip): 52 zones a title-1 fleet. A company at a high title in good ships carries few.
- The map is computed at each call. The client is expected to keep it for the session (it is world data). If prod's time is far above the local 135 ms, the fix is a derived table of the 720 strings; not built.

## Checks run

- Apply + self-assert on the cached world: green.
- Proof 69 (`scripts/db/proofs/69_a_wall_says_what_is_short.sql`): 7 of 7 markers. Proofs 33, 45, 54, 56, 57, 62, 63 after the file: green.
- `cmd.refusal_caught` is the only function that filters a refusal's figures (searched the live bodies of `public`, `cmd`, `world`, `voyage` for a read of `->'have'`): `cmd.execute_order`, `cmd.preview`, `cmd.issue` and `cmd.run_standing_provision` all call it.
- `before.sql`, `after.sql`, `volatility.sql` answer as their headers say, before and after the file. `rollback-0376.sql` followed by `before.sql` in one scene: every `old_times` 1, `new_times` 0, `new_functions` 0.
- `tsc -b`; the three specs named in the PR.

## Decided by default

1. `public.far_powers()` lists every nation whose capital's sea asks a title, the minor ones too (AYU BAN GUJ JOS JPN MLB MNG MUG PER PIR RUS locally). Who may be joined stays `public.nation_joinable`'s answer.
2. The far-power door sits behind `sea_conditions_bite` itself, not a switch of its own.
3. `cmd.change_country` is not cut (the design keeps it open to all). A company that changes country keeps its fleets where they lie.
4. `cmd.found_house` answers in its own shape (`ok: false, error_code, ...`), not `cmd.refusal`'s `{code, sentence, figures}`: every other door of that function answers so, and the Start screen reads that shape. `figures` is added beside it.
5. The map is run-length text computed per call; no table, no static asset (the design's C3 named a PNG asset held by the world guard: one authority fewer this way).
6. `-- news: none`: nothing a player sees changes with this file. The news of the wall belongs to the file that lights it.
7. Proof number 69. Another branch may take the same number; whichever lands second renumbers.
8. The probe raises `fleet_max` inside its rolled-back block to time five fleets.

## Not verified

- Nothing was read on prod. `before.sql` has not been run there: whether each hunk occurs once on prod's live bodies is unproven until it is (prod head is 0363; 0364, 0366 and 0367 cut `public.client_rpc_entry_points` on other lines).
- Prod's timings of the two reads.
- No client screen reads the new keys yet; the shapes are held by the self-assert and proof 69 only.
- With the catcher's cut, a client that reads `figures` on a refused order may now receive the sea's shape where it only ever received `{have, need, unit}` or nothing. Every reader of `figures.have` on the client was not audited here.
- `world.route_legs.sea` judges the DIRECT course the client proposed (or, with no course, only the destination's own sea). A far city whose own sea is open but which lies behind a closed crossing, asked with no course, reads `sea` null.
- A company already sailing for a far power is not touched by this file (`before.sql` counts them: 0 locally). What happens to it at lighting is the lighting file's to judge.
- The full proof suite and a from-zero chain were not run locally (CI's job).
