# 2026-11-13: a wall says what is short (migration 0396, branch `seas-wall`)

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
- Proof 91 (`scripts/db/proofs/91_a_wall_says_what_is_short.sql`): 7 of 7 markers. Proofs 33, 45, 54, 56, 57, 62, 63 after the file: green.
- `cmd.refusal_caught` is the only function that filters a refusal's figures (searched the live bodies of `public`, `cmd`, `world`, `voyage` for a read of `->'have'`): `cmd.execute_order`, `cmd.preview`, `cmd.issue` and `cmd.run_standing_provision` all call it.
- `before.sql`, `after.sql`, `volatility.sql` answer as their headers say, before and after the file. `rollback-0396.sql` followed by `before.sql` in one scene: every `old_times` 1, `new_times` 0, `new_functions` 0.
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
- No client screen reads the new keys yet; the shapes are held by the self-assert and proof 91 only.
- With the catcher's cut, a client that reads `figures` on a refused order may now receive the sea's shape where it only ever received `{have, need, unit}` or nothing. Every reader of `figures.have` on the client was not audited here.
- `world.route_legs.sea` judges the DIRECT course the client proposed (or, with no course, only the destination's own sea). A far city whose own sea is open but which lies behind a closed crossing, asked with no course, reads `sea` null.
- A company already sailing for a far power is not touched by this file (`before.sql` counts them: 0 locally). What happens to it at lighting is the lighting file's to judge.
- The full proof suite and a from-zero chain were not run locally (CI's job).

## Later the same day: renumbered to 0396, merged onto main (head 0375), and the way home

- **0376 became 0396** (the lead's order: 0379 to 0390 deploy first; 0396 meets 0390). The file, proof (now 91), the rollback draft and every check were renamed.
  `origin/main` was merged in: five switches and attacks are lit on that chain. All ten hunks still occur once; the self-assert, proofs 91 and 68 and the three
  check files run green on it.
- **The way home (two more hunks and one new function, `public.sea_floor`).** The lead read prod: one company, title 1, lies at Acapulco with two barcas, in a
  sea that asks title 8. Lit as first written, every departure of hers would be refused, and the lighting step's guard would refuse to light while she lay there.
  The rule now: **a fleet is judged as holding at least what the sea she lies in asks.** She is in that water already, so that water and any that asks no more
  never refuse her. It is read at the door (`public.sea_gate`), by the board's pathfinder (`voyage.reach_passage`, from the harbour she leaves) and in
  `world.sea_conditions` (her own sea is not called closed, so the map does not shade it). A refusal's figures still carry her own title and her fleet's own wave.
  Where she lies is the server's fact (her port, or her position at sea), never the course the client proposes.
  What it does not do: take her home across water her hull cannot hold (from Acapulco the open Pacific still refuses two barcas). She keeps her own coast.
  Not chosen: moving idle fleets home at lighting (it moves a player's ships and cargo without her).
  Known gap: `public.sea_routes` (a Trade row's `sea` tag) still reads the plain rule, so a row in her own far sea can wear "Shut" while the passage is offered.
- **Proof 68 (the armada) was red on this PR's CI and it was not this file.** Every new ship rolls her own speed from her id (0276, 0.80 to 1.20). Proof 68 wears
  the second fleet's hull to 0.6 and asserts she is then the slower; with an unlucky pair of rolls she is not. Measured on 400 random pairs: 8 are the wrong way
  round (2 %). The proof now makes the two rolls equal before it wears the hull. **0367's own self-assert has the same pattern (0.5 of a hull)**: it is an applied
  file, so a from-zero replay can fail there by the same chance; that wants a line in `src/lib/db/frozenAsserts.ts`, not done here.

## 2026-11-14: renumbered to 0396, home waters, founding refused nowhere

- **0391 became 0396** (it meets 0395, the armada's battle). Proof stays 91. `origin/main` merged (0380 in).
- **Founding is refused nowhere.** The hunk on `cmd.found_house` (`E_FAR_POWER`) is gone. The lead's prod read: one company already sails for Japan, players
  found under Japan and Joseon today, and pirate companies were opened on 2026-11-13; refusing eleven flags at the light was not workable.
- **Home waters, the sibling of the way home.** `public.sea_floor` now answers two seas: the one a fleet LIES in and the one her company's CAPITAL lies in (the
  capital of the country she sails for now). `public.sea_judge` (new) asks the one rule with both: a sea of the same title rank as either never asks her title,
  and asks her hull no more than that sea asked. The door, the board's pathfinder and the conditions read all use it; the read also serves `home_sea`.
  Figures in a refusal stay her true title and wave. Server facts only. Dark: no path enters it.
- **The floors open a rank, not everything below it.** Read literally ("every sea asking no more"), a floor of title 7 opens every sea of title 1 to 7: a
  title-1 barca of Japan would read 187 of 249 harbours on the board, a Mughal one 138. So both floors (lie-in and home) open only seas that ask the SAME title.
  This also narrows yesterday's way home: a fleet lying in a far sea keeps the waters of that sea's rank, not all easier water.
- **A change of country moves her home at once** (the floor reads `players.nation_id` live). It cannot strand her: the sea she lies in is the other floor, so
  the waters of the rank she lies in stay open whatever flag she takes (proof 91, `WALL_HOME_WATERS`).
- **Day one, a title-1 barca at her capital** (cached world, the board's pair table, legs within 1,700 nm; 249 harbours):

  | Country (capital's sea asks title/wave) | Harbours on the board |
  |---|---|
  | Portugal, Spain, England, the Netherlands, France, the Ottomans and the seven minor European flags (1/0) | 82 |
  | Russia (3/10) | 102 on the board; at the door about 20, and Europe is NOT joined to them until title 2 (the Norwegian Sea lies between) |
  | The Brethren (4/12) | 23 |
  | Mughal, Gujarat, Malabar, Persia (6/10 to 6/12) | 114 on the board; at the door about 26 |
  | Japan, Joseon, Ming, Ayutthaya, Banten (7/8 to 7/12) | 66 |

  The two "on the board" figures are too high because the pair table judges a straight line between two roadsteads: Suez to Alexandria is a straight line over
  land whose seas are the Red Sea (her rank) and the Mediterranean (title 1), so the board joins Arabia to Europe; the door samples the real course and does not.
  This is the board-and-door gap already listed in the design (re-derive the pair table from sailed courses); home waters make it matter for the six flags of
  ranks 3 and 6. No country's home opens most of the map.
- Cost: `world.sea_conditions` for five fleets 18 ms (it was 21). The first cut through `public.sea_judge` a zone at a time read 167 ms; the read now lays the
  floors on inline, one call of the rule a zone as before.
- Nine hunks, seven cut bodies, four new functions (`far_powers`, `sea_zone_map`, `sea_floor`, `sea_judge`). `public.far_powers` stays as a reading; nothing
  refuses on it.
