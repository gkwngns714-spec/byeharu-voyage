# 2026-11-14: Trade's sea tag is the door's own answer; the map's shade has its key (0402)

Owner rows 166 and 324. The seas are lit for players and merchants, so this is live play. Nothing here is deployed by this work.

## The gap

Since 0396 every fleet has two floors: the sea she lies in and her company's capital's sea each open the seas of the same title rank
("the way home", "home waters"). The sail door (`public.sea_gate`), the pathfinder (`voyage.reach_passage`) and `world.sea_conditions`
read them. A Trade row's `sea` tag did not: `public.sea_routes` took a title and a wave, not a fleet, and asked the plain rule. So a
row for a harbour of her home rank, or of the rank of the far sea she lies in, could say "Shut" while its passage was offered and the
door let her sail.

Measured on the cached world before the fix (0402's own probe, a title-1 barca of Portugal lying at Acapulco, lit): of the 248 direct
rows from Acapulco the old tag shut 13 that the door opens.

## What 0402 does

- `public.sea_routes` takes the fleet: `(p_fleet, p_title, p_wave, p_routes)`. It is the live body with three hunks, each asserted once
  and reversing. Lit, a leg brings the zones the door asks on that line (the straight line's zones and the zone of the harbour she makes
  for, as `public.sea_gate` gathers them), and the verdict is `public.sea_judge` with her floors from `public.sea_floor`. Dark, both are
  what they were. The three-argument function is dropped: the board was its one reader.
- `world.good_board`: two hunks, the two calls pass the fleet in hand. `world.best_sales` does not read the tag and is not cut.
- **Judged once per distinct sea of the board, not per row.** The floors are read once a call; each distinct sea on the board's routes
  (64 at most) is asked once of the judge; a route wears the answer of its first refusing sea, in the judge's own order.
- News: one UPDATE row, "Trade shows home waters open".

Trade, the map's Send row, the route builder and the door now ask the same judge with the same floors.

## Cost (cached world, PGlite, lit; `scripts/ops/harness/sea-tag/cost.sql`)

| | Before | After |
|---|---|---|
| The tag alone, 249 direct routes, at Lisbon (mean of 30) | 8.2 ms | 15.8 ms |
| The tag alone, lying at Acapulco | 10.4 ms | 17.2 ms |
| A whole board, at Lisbon (mean of 20) | 431.7 ms | 435.9 ms (+1.0 %) |
| A whole board, lying at Acapulco | 432.6 ms | 442.3 ms (+2.2 %) |

The first cut judged once per distinct SET of seas (as the plain rule was asked) and cost a board 4 to 6 % (the tag 12 ms to 36 ms): lit,
nearly every route has its own set. Judging per distinct sea brought it to 1 to 2 %. The migration's own notice (true pre-image against
the new body, six calls): 421.8 ms before, 427.8 ms after.

## Proved

- 0402's self-assert (cached apply, about 11 s of its 45 s budget): five hunks once and reversing; one `public.sea_routes`, server-only;
  no other function moved; dark, the tag and two boards are the same text as the pre-image at Lisbon and at Acapulco; lit at Acapulco,
  all 248 direct rows equal `public.sea_gate`'s answer for the same fleet, 13 the plain rule shut are open, 235 are shut still.
- Proof 97 (`scripts/db/proofs/97_trades_sea_tag_is_the_doors_answer.sql`), three markers: for a title-1 barca of Portugal lying at
  Acapulco and for a new company of Japan at Sakai, every buy and sell row of three boards (756 rows each) is shut exactly when the door
  refuses one of its legs, and a one-leg row wears the door's refusal to the letter (717 and 636 rows); 51 and 206 rows the plain rule
  shuts are open. Dark, all 1,512 rows wear the plain rule's reading, recomputed in the proof without `public.sea_routes`.
- Proof 97 under other worlds: green four times of four, each under another world secret and another market (every harbour's stock of every good multiplied by its own random factor between 0.2 and 1.8), by the method of `scripts/ops/harness/sea-merchants/dice-0400.mjs` pointed at proof 97. The proof picks its goods from her harbour's roster (world data), not from the market.
- Proofs 91 to 96 green with 0402 applied. Client: `seas.lit`, `trade.flow`, `trade.layout`, `rpc.goodBoard`, `map.sendfleet` (57 passed), `rpc.surface`,
  `news.lint`, `duplication`, `harness.guard`, `i18n.*` (58 passed), tsc, eslint, build.
- The two prod checks run on the cached world before and after the file answer what they say they want (the switch reads false there; prod's is true).
- The rollback draft (`scripts/ops/harness/sea-tag/rollback-0402.sql`) run after 0402 on the cached world: both bodies return to the pre-image to the byte (md5 of `world.good_board` and of the three-argument `public.sea_routes` equal those read before 0402), and the four-argument function is gone.

## Not proved, and what is left

- **The board reads the straight line; the door samples the course she really sails.** That difference (section 10.6, "the board and
  the door": 11 of 703 one-leg courses) is not touched: a Trade row can still be open where the door refuses the real course, and the
  door says why at the press. The proof asks the door on the straight line.
- A passage of several legs is judged with the floors of where she lies NOW, as the door judges it when she plans it. At a later
  departure she lies elsewhere and her lie-in floor moves (section 10.6, S7, the pathfinder's part). Not changed here.
- Prod's own board timing is not measured (no EXPLAIN ANALYZE on prod, by the rule). The figures above are PGlite's.

## The map's shade has its key

One line in the chart's bottom-left corner, only while a sea is shaded for the fleet in hand: a swatch of the shade and "Closed seas" /
"닫힌 바다" (`map.closedSeasKey`). It sits in the corner the minimap already uses, takes no press, and adds nothing to the Trade face.
The swatch's colour is the veil's own (`CLOSED_SEAS_VEIL_CSS`, one authority). `tests/seas.lit.spec.ts` holds it at 390 and 320 px in
English and Korean, inside the glass and one line high, and absent in the dark world.

## Prod checks, in order

1. `scripts/ops/harness/sea-tag/before-0402.sql` (read-only): five rows, every `old_times` 1 and `new_times` 0, `plain_tag_in` true,
   `fleet_tag_in` false, `tag_readers` the board alone, head 20260818000401.
2. Deploy 0402 with `~/bin/bv-deploy.sh <pr>`.
3. `scripts/ops/harness/sea-tag/after-0402.sql` (read-only): every `new_times` 1 and `old_times` 0, `fleet_tag_in` true, `plain_tag_in`
   false, `news_rows` 1, head 20260818000402.

Rollback: the draft above, as a forward migration (owner only). It needs no switch.
