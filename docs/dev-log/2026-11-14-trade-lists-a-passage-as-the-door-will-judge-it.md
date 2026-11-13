# 2026-11-14: Trade lists a passage as the door will judge it (0403)

Owner rows 166 and 324. The seas are lit for players and merchants, so this is live play. Nothing here is deployed by this work.

## The gap

`public.sea_leg_asks` says which seas lie between two harbours, and so what title and wave a leg asks. Trade's board (`public.sea_routes`) and the
server's pathfinder (`voyage.reach_passage`) read it. It was derived from the STRAIGHT line between the two roadsteads, and every sample of that line
that fell on land was left out. The sail door (`public.sea_gate`) judges the course the player's client plots, which goes round the land. So the
table joined Suez to Alexandria by the Red Sea and the Mediterranean alone (the real course rounds Africa), Arkhangelsk to Bergen through the Baltic,
and Surat to all of Europe without the Cape. Trade listed harbours the door then refused at the press, and hid some the door opens.

Measured on the cached world at 0402, against the course of every pair:

| | |
|---|---|
| Pairs of harbours (249 harbours) | 30,876 (61,752 rows, one each way) |
| Pairs whose straight line crosses land (the client's own land check, `segmentIsWater`, roadstead to roadstead) | 29,780 |
| Rows that named other seas than the real course crosses | 50,976 |
| Rows that asked another title or wave than the real course | 34,697 |
| ... asked too little (Trade said open, the door refuses) | 32,434 |
| ... asked too much (Trade said shut, the door opens) | 2,068 |
| ... one figure too little and the other too much | 195 |
| Pairs whose course crosses other seas one way than the other | 7,507 |
| Remembered merchant courses (1,061) that cross a sea their row lacked | 329 (62 of them asked more wave than the row) |

The earlier count ("11 of 703 one-leg courses") was taken on the merchants' remembered courses, which are short and coastal. Over every pair the
straight line is wrong far more often: nearly every long line crosses a continent.

## The choice: plot every pair at build time (approach a)

The server has no pathfinder; the client has one, `src/lib/sea` `findPath`, a pure module that the build scripts already run under Node
(`scripts/build-sea-migration.mjs`, `scripts/db/proof-courses.mjs`). So every pair can be plotted exactly as a player's browser plots it. That makes
the board exact, where correcting only from remembered and sailed courses (approach b) would have fixed 1,061 of 61,752 rows and left the rest marked
"unsure".

`scripts/build-sea-legs.mjs`:

1. restores the cached world at the head before the migration (never from zero);
2. plots the course of every ordered pair of harbours, roadstead to roadstead, with `findPath` over the raster that world serves (the call
   `src/domain/passage` `proposeCourse` makes): 61,752 searches, 3.5 minutes on 12 threads; every pair has a water course;
3. asks that world's own `public.course_zones`, the door's sampler, for the seas of each course (10 minutes in PGlite);
4. writes `data/sea-legs.json` (454 KB): the harbours, the 3,507 distinct sets of seas, one index a pair.

There is no second sampler and no second pathfinder: the plot is the client's, the seas are the door's.

## What 0403 does

Data only. No function is written; no rule moves.

- Every row of `public.sea_leg_asks` takes the seas of its plotted course; `wave_min` and `title_min` are, as before, the most those seas and the
  destination's own sea ask. A harbour's own row does not move. The seed is `data/sea-legs.json` to the letter.
- Where the world remembers a course on a pair (`public.npc_courses`) that crosses a sea the plotted course does not, the row takes that sea too: a
  row never asks less than a course the world holds. On the chain's world this adds nothing (all 1,061 remembered courses cross exactly the plotted
  seas: they were plotted by the same pathfinder). Prod's table also holds merchant legs as they stood at 0203's deploy, so there it may add a few.
- The file refuses a world that is not the one its courses were plotted on (the harbour list, the roadsteads, the sea raster, the sea boxes, each
  by md5). `before-0403.sql` reads the same four on prod first (`same_world`).
- The comments on the table and on `public.sea_leg_asks_derive` say who writes the table now. News: "Trade lists only passages you can sail".

Trade's tag (0402: the judge over the row's seas and the destination's sea), the pathfinder and the map's Send row read the table and follow with no
function change. The merchants read their own courses through their memo (0397): untouched, and asserted whole.

**The table's author is now the build.** A slice that moves a sea box, the sea raster, a roadstead or the harbour list re-runs
`scripts/build-sea-legs.mjs` and ships its file as 0403 does. `public.sea_leg_asks_derive` (the straight line) no longer writes the table.
`scripts/db/world-guard.mjs` holds the table equal to `data/sea-legs.json`.

## The five pairs known bad

| Pair | Before (straight line) | After (plotted course) |
|---|---|---|
| Suez - Alexandria | wave 10: Mediterranean, Red Sea | wave 44: round Africa by the Cape (13 seas) |
| Arkhangelsk - Bergen | wave 10: Baltic, North Sea, White Sea | wave 12: White Sea, Barents Sea, Norwegian Sea, North Sea (no Baltic) |
| Ayutthaya - Malacca | wave 10: Gulf of Thailand, Strait of Malacca | wave 12: with the South China Sea, round the peninsula |
| Cebu - Ternate, Cebu - Tidore | wave 12: Molucca Sea, Visayan Sea | the same: 0401's coastal strip already took the open Philippine Sea off these lines, and the plotted course does not enter it either |

## What Trade lists for a new company's barca (title 1, wave 12; cached world; `counts-0403.sql`)

Harbours one leg away that the tag shows open, for a company whose capital's sea is the harbour's own.

| Lying at | Before | After | What moved |
|---|---|---|---|
| Lisbon | 82 | 82 | nothing |
| Sakai | 55 | 45 | 19 lost (the Mediterranean and Portugal: the straight line ran over Asia); 9 gained (Busan, Incheon, Mokpo, Nampo, Tongyeong, Ulsan, Yeosu, Makassar, Surabaya) |
| Surat | 108 | 25 | 83 lost: every harbour of Europe and the Mediterranean (the straight line ran over Arabia and left the Cape out) |
| Port Royal | 24 | 19 | 5 lost: Buenos Aires, Recife, Rio de Janeiro, Salvador, Santos (the straight line ran over South America) |

Every harbour lost was one the door refused at the press. Every harbour gained is one the door opens.

## Cost (cached world, PGlite, lit)

A row now holds 8.1 seas on average (4.7 before). The board judges each distinct sea once (0402), so the cost does not follow.

| Same process, old rows and new rows turn about, three rounds | Old rows | New rows |
|---|---|---|
| A whole board at Lisbon (mean of 24) | 511.8 ms | 511.2 ms |
| The tag alone, 249 direct routes (mean of 60) | 18.9 ms | 19.4 ms |

Two separate runs of `scripts/ops/harness/pair-table/cost.sql` (before and after the file) read 476.8 and 497.3 ms for a board at Lisbon and 465.4
and 476.4 ms lying at Acapulco: the run-to-run spread, which the turn-about measure removes. The migration applies in 5 s on PGlite.

## Proved

- 0403's self-assert (cached apply, 5 s of its 120 s budget): one row a pair of 249 harbours, every seed row read, no harbour's own row moved; every
  row asks the most its seas and its destination's sea ask; 46 plotted courses kept in the file (the five pairs both ways and a spread of 36 out of
  Lisbon) cross exactly the seas of their rows by `public.course_zones`; each of the five pairs is on its real course; every remembered course
  crosses only seas its row holds; the merchants' memo is whole; lit, for a title-1 barca of Portugal at Lisbon, the Trade tag of each of the 36
  harbours is `public.sea_gate`'s answer on the plotted course to the letter (26 shut, 10 open); the probe rolls back.
- Proof 98 (`scripts/db/proofs/98_trade_lists_a_passage_as_the_door_will_judge_it.sql`, new, three markers). It carries the plotted course from
  Acapulco and from Sakai to every other harbour (496 courses). Lit, for a title-1 barca of Portugal lying at Acapulco and a new company of Japan at
  Sakai, the Trade tag of all 248 harbours is the door's answer on the plotted course, to the letter (234 and 203 shut); for 69 and 127 of them the
  door answers otherwise on the straight line, which is what the board read before. All 1,061 remembered courses cross only seas their row holds.
- Proof 97 now asks the door's judge (`public.sea_judge` with her floors) over the seas of each leg's pair row, where it asked `public.sea_gate` on
  the straight line: with plotted rows the straight line is no longer what the board reads, and proof 98 holds the row to the door on the real
  course. Its three markers are green (756 rows a company, 717 and 639 of one leg to the letter).
- Proof 95 chose its merchant by the first sea of the pair table's straight-line rows, a stand-in. It now counts her known legs by the seas their
  courses cross, as the readers it tests do. Seven markers green. Nothing about the merchants changed.
- Proofs 91 to 98 green with 0403 applied. Proofs 95 and 97 green three times of three, and proof 98 twice of twice, each under another world secret
  and another market (every harbour's stock of every good multiplied by its own random factor between 0.2 and 1.8), by the method of
  `scripts/ops/harness/sea-merchants/dice-0400.mjs`.
- The rollback draft run after 0403 on the cached world returns the table to its pre-image: the same md5 (`md5.sql`) as before 0403.
- The prod checks run on the cached world before and after the file answer what they say they want.
- The world guard (in `npm run build`'s world image, 367 files) holds the table equal to `data/sea-legs.json`.
- Client (no client file changed): `seas.lit`, `trade.flow`, `trade.layout`, `rpc.goodBoard`, `map.sendfleet`, `map.autoroute`, `rpc.surface`, `news.lint`,
  `duplication`, `harness.guard`: 115 passed against the served build; tsc, eslint, build.

## What is still approximate

- The row is the course from the harbour's roadstead. A fleet lying at sea, or a course a player bends by hand in the route builder, is judged by the
  door on its own line; Trade judges the lead leg of a fleet at sea as before.
- A passage of several legs is still judged with the floors of where she lies now (10.6, S7, the pathfinder's part). Not changed here.
- On prod a remembered course may add a sea to a row (see above); the board is then stricter than a fresh plot on that pair, never laxer. The
  migration's notice prints how many.
- The pathfinder and the door's sampler are deterministic, but the table is a snapshot: it is right for the raster, roadsteads and boxes it was
  plotted on. The migration's refusal and the world guard are what hold a later slice to re-running the build.
- Prod's own board timing is not measured (no EXPLAIN ANALYZE on prod, by the rule). The figures above are PGlite's.

## Prod checks, in order

1. `scripts/ops/harness/pair-table/before-0403.sql` (read-only): head 20260818000402, `applied` false, `same_world` TRUE (if false, do not deploy),
   `rows_off_the_straight_line` 0, `remembered_crossing_a_sea_the_row_lacks` some hundreds, `news_rows` 0.
2. `scripts/ops/harness/pair-table/counts-0403.sql` (read-only): keep the four rows (cached world: Lisbon 82, Port Royal 24, Sakai 55, Surat 108).
3. Deploy 0403 with `~/bin/bv-deploy.sh <pr>`.
4. `scripts/ops/harness/pair-table/after-0403.sql` (read-only): head 20260818000403, `applied` true, `rows_off_the_straight_line` about 51,000
   (the count of pair rows the file changed; 50,976 on the cached world), `remembered_crossing_a_sea_the_row_lacks` 0, the five pairs as in the
   table above, `news_rows` 1.
5. `counts-0403.sql` again (cached world: Lisbon 82, Port Royal 19, Sakai 45, Surat 25).

Rollback: `scripts/ops/harness/pair-table/rollback-0403.sql`, a draft, as a forward migration (owner only): the table back to the straight-line
derivation. Run after 0403 on the cached world it returns the table to its pre-image (the same md5, `md5.sql`).
