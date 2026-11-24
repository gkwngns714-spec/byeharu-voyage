# The quote is on her course (2026-11-24, migration 0491)

## The fault

Main's proof 63 went red on TRADE_WAGES: the trip settled 8 days of wages (160) and the board quoted 7 (140). The board and the trip
quote (`world.trip_cost`, `voyage.reach_passage`, `world.board_*`) measure a leg on `public.sea_reaches` / `public.sea_reach_matrix`.
The SAIL (`cmd.do_sail`, `voyage.depart`) settles on the course it carries: the sum of `voyage.segments_from_course`, pieces of at most
500 nm along the straight lat/lon line between the course's points, each rounded to 2 decimals (the line the plotter, the no-land audit
and the map draw). The table was measured another way in 0442 (great circles between the points).

Measured on the chain's world (prod's courses digest `a9b593754530495de24d331cc3be1204` and its matrix equal the image's; the previous
builder read them on prod read only), over the 32,128 stored courses (`public.sea_courses`, 0482):

- 19,428 pairs differ by more than 0.1 %; median +0.19 %, p99 +6.57 %. Largest by share SYD-TDC 6,480.3 -> 7,886.9 nm (+21.7 %); largest
  in miles ARI-AYU 10,942.7 -> 12,369.6 (+1,426.8 nm, +13.0 %). 29,683 pairs sail longer than quoted, 2,088 shorter (at most BND-MNG
  3,768.2 -> 3,699.7, -1.8 %), 357 equal.
- Whole days quoted fewer than settled (every day begun is a day): 5 kn 9,578 pairs (20 quoted more), 10 kn 6,023 (11), 15 kn 4,556 (8),
  17.5 kn 4,014 (5). Two or more days fewer at 15 kn: 595 pairs. Sailing time short by more than 24 h at 15 kn: 1,094 pairs.

## The decision ("A whole", the lead's default; the owner may reverse it)

One distance: the table takes the SAIL's measure; haul is refilled from it; the stored course is the one a press carries.

**Keeping it one: a stored copy plus a loud proof, not a trigger keeper.** The measure stays `voyage.segments_from_course` (unchanged).
`scripts/db/gen-0491-sea-lengths.mjs` calls it (and `public.sea_course`) on the chain's world for every stored course, both ways, and
writes the seed. 64,256 calls took 213 s on PGlite (each also scans the raster for shelter), so it must not run on prod. A trigger keeper
would need the piece loop cut out of `voyage.segments_from_course` (a hot body every departure runs) and would re-measure all courses on
prod inside a migration. Instead proof 194 pins the courses' digest the lengths were measured from and the table's digest, and
re-measures a sample live every run: a later `sea_courses` write without the generator in the same migration fails it.

## What 0491 does

1. `public.sea_reaches`: every harbour pair with a stored course (32,128 of 32,131; the other 3 share one roadstead and keep their figure)
   gets its sailed length, both ways (equal both ways for all 32,128: 0442's law holds). One UPDATE of 254 rows; the matrix follows by its
   trigger. Sea-place cells unmoved (digest `9009e9f6...`).
2. `public.port_goods.haul_nm / haul` refilled from `world.haul_rows()` in one statement (as 0442 / 0446), held equal to it; every other
   market column unmoved (md5 over the row, inside the migration).
3. `public.fleet_job_course` (two hunks): lit, the stored course first; lane, coast course, own voyage only where none is stored. An HQ
   card's press and a standing job carry it (`public.sale_lines` -> `public.fleet_job_sails` -> it).
4. News row `0491`: "Long trips: true days and prices" / "먼 항해: 실제 일수와 가격".

## Measurements (local, PGlite, the chain's world at 0489 + 0491)

- The migration: 11.8 s for the whole file. Its self-assert re-measured 122 sampled pairs live both ways: equal.
- Prices (`haul`, the far-sea multiplier on a good's price): 101,096 of 159,766 market rows move (132,825 rows written: the rest move
  `haul_nm` only); 99,494 up, 1,602 down (by at most 0.36 %, the pairs that got shorter). |move| median 0.20 %, p95 2.43 %, p99 5.03 %,
  max +12.36 % (Ayutthaya cacao-bean / chuno / agave: haul_nm 10,942.7 -> 12,369.6, haul 1.4348 -> 1.6122). 6,531 rows move more than
  2 %: Hobart 311, Sydney 300, Wellington 295, Auckland 294, Honolulu 159, Darwin 153. `price_history` is not rescaled.
- Trip days: after 0491 the table equals the sailed length for every stored pair, so quoted whole days = settled days at every speed
  (proof 194 checks it on its sample at 5 / 10 / 15 / 17.5 kn, and sails Longyearbyen -> Reykjavik for real: 1,117.99 nm sailed = the
  table's, 4 d settled = 4 d quoted; before 0491 the table said 1,092.8).
- Rollback: `scripts/ops/harness/quote-on-her-course/rollback-0491.sql` (with its local guard line) on the chain with 0491: 4.4 s and
  8.1 s on two runs; afterwards every digest equals
  the before (reaches_hh `3cbac251...`, reaches_rest `9009e9f6...`, haul `2ad60b0c...`, job_course `11df277c...`, matrix `09856110...`).

| digest | before 0491 | after 0491 |
|---|---|---|
| courses | a9b593754530495de24d331cc3be1204 | (same) |
| reaches_hh | 3cbac251bb36faa50ba6710eadec9f7f | 8e418cd663c8c3790b94f9c4fe57e2b9 |
| reaches_rest | 9009e9f67a735c705e577806ec0d2a53 | (same) |
| haul | 2ad60b0c9fb244c8f98a7c95cecc5499 | 186307520393f981125371d1e036792f |
| job_course | 11df277c754935805a787d035c659581 | 40599d42a7fb56879c6d636fc0f97af7 |
| matrix | 09856110c841352927f990ad2dcda4be | 79fcbc8e7e9076863d002060cc936d33 |

## Proofs and checks (local)

- 194 (new): PQ_PINNED, PQ_MEASURE (123 pairs both ways), PQ_DAYS, PQ_SAIL; 1.5-1.7 s. (PQ_SAIL's days move with the game clock:
  4 d = 4 d on one run, 3 d = 3 d on the next.)
- Green, one run each: 63 (7/7), 62, 148, 157, 162, 165, 185, 142, 143, 97, 98, 176, 11, 163. Specs: harness.guard, db.budget,
  news.lint; `scripts/db/check-versions.mjs` OK.
- No-land audit, `node scripts/db/audit-land-crossings.mjs --apply <0491>` on the newest cached image (448 files): `checked
  {"npc":1141,"route":3350,"coast":12,"leg":0,"roadstead":268,"pair":0}`, 0 courses cross drawn land or are refused, 0 roadsteads on land
  (the same as without --apply). 0491 moves no course, roadstead or raster cell.
- 63: each leg now sails the stored course (`public.sea_course`; `proof.course` only where none is stored) and each leg's line in the
  failure message says the nm sailed and the board's leg nm and days (#851's diagnostic, folded in; #851 closed).
- Courses, raster and roadsteads are not touched: proof 148 (straits) and the no-land audit unchanged (outputs below).

## Prod (filled at deploy)

(before-0491, deploy, after-0491, 30-minute after-check)
