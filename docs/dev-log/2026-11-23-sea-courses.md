# 2026-11-23 — 0482 sea courses and a faster Lisbon read (dark: `sea_courses_enabled`)

`docs/design/hq-command-2026-11-23.md` section 2, v2. The owner, 2026-11-23: "all the work(activities) are done in HQ ... choosing best
options available, finding best options."

## The two problems
- **The server cannot plot a course.** `cmd.do_sail` refuses a SAIL with no course when the straight line crosses land (`E_NO_COURSE`).
  So 0481's standing `best` jobs could sail only a course already sailed (a merchant lane, a coast course, her own past voyage). Prod's
  harness found 0 of 8 paying Lisbon sales with such a course (`coursed: 0`, before-0481 and again before-0482). An HQ card's trip also
  needed the browser's chart to plot it.
- **The HQ board read takes ~3.1 s on prod.** About 2.6 s of that is `world.best_sales` at Lisbon, cut by its own 2.5 s budget.

## What it does
### 1. Stored courses (lit only)
- **The table** `public.sea_courses` stores one course for every pair of harbours. The course is what the browser's own course author
  plots: `src/domain/passage` `proposeCourse` (`src/lib/sea` `findPath` over the served raster, then `refineCourse` off the coast mask),
  roadstead to roadstead.
  - It is written offline by `scripts/build-sea-courses.mjs`, on the world at prod's head. The script uses the same functions the
    browser runs.
  - There is one row a harbour. Each row holds that harbour's courses to every harbour after it by code ("C" order). A pair stored once
    is sailed either way: asked the other way, the same water is reversed.
  - Each point is rounded to 4 decimals (about 11 m). The courses are packed as zigzag base-128 varints: the first point, then each
    point's difference from the one before. Each row has one `bytea` and the byte offset of each course.
- **Checked when built:**
  - Every course is held to the drawn land by the no-land audit's own reading (`crossingsOf` over `truthLand`, and the server's law as
    `courseRefusedAt` mirrors it). None crosses.
  - The packed bytes are decoded again, and the server's door (`voyage.path_refusal`, with `cmd.do_sail`'s allowances) is asked about
    every course both ways. All 32,128 pass.
  - 3 pairs are left out: BAS-HOR, CAP-ELM and OSA-SAK (harbour codes). Each pair's two harbours share one roadstead, so a course between
    them "has no length".
- **The seed carries the digest of the world it was plotted on** (the harbours, their roadsteads and the raster). The migration refuses
  any other world. Prod's digest equals it (before-0482: `roadsteads 263d4650…`, `raster 84c911a4…:1440x720:0.25`, 254 harbours).
- **`public.sea_course(from, to)`** decodes one course. It returns null for the same harbour, a place that is not a harbour, or one of
  the 3 pairs.
- **`public.fleet_job_course`** (by a hunk) falls back to the stored course when lit, after the merchant lane, the coast course and her
  own voyage.
  - So a `best` job sails her best sale wherever it is.
  - A fixed route no longer needs a voyage sailed first.
  - `cmd.set_fleet_job` refuses `E_NO_COURSE` only where no water joins two harbours.
- **`public.sale_lines(fleet, from, sale, stops)`** is the one writer of a sale's lines: BUY (none for her cargo), SAIL through the
  stops, each with its course, then SELL ALL.
  - 0481's `best` branch wrote these lines. That code moved here whole (`public.fleet_job_plan`, by a hunk).
  - When lit, each HQ trade card's act also carries `lines` (`public.hq_board_for`, by a hunk). The client sends them as they are
    (`servedPress.ts`), so the press needs no chart.
  - When dark, the act is exactly 0480's and the client plots the course.
- `cmd.do_sail` is unchanged. It judges every course at every departure, as before.

### 2. A faster Lisbon read (whatever the switch; the same answers)
- **Why it was slow.** Measured locally with prod's lit switches (`track_functions` on the chain): ~16 % of `world.best_sales` at Lisbon
  was ONE `voyage.reach_passage`. 67 ms of its ~85 ms went to building the harbours' distance matrix out of 254 jsonb documents (64,516
  cells), on every call. Every good also re-read her hulls and her speed's parts (`world.trip_hulls`, `voyage.fleet_speed_parts`) once per
  good.
  - The rest is spread thin over ~35,000 small calls: the knob reader `wc` 12,900 times, `crew_pct` 430, the quote chain 194 quotes.
    Prod is about 2.5x local on CPU-bound loops and 5-11x on small queries (before-0482: `wc` 2,000 calls 32 ms; `player_progress`
    12 calls 46 ms).
- **a. The kept matrix.** `public.sea_reach_matrix` holds that very `float8[]` and its harbours in the same order.
  - `voyage.reach_passage` (by a hunk) reads it when its harbours are the call's own. Otherwise it builds the matrix as before.
  - The matrix is kept by `public.sea_reach_matrix_keep`, a statement trigger. It fires on every write to `public.sea_reaches` and on a
    harbour added, removed, renamed or re-kinded. The game's only run-time update of `ports` is `crew_pool`, which never fires it.
- **b. Read once a call.** `world.best_sales` (by a hunk) reads her hulls and speed parts once. It hands them to `world.board_trips` (by a
  hunk) in the context it already passes.
  - `board_trips` takes them only when they are for its own fleet and of the right shape. Otherwise it reads them itself.
  - One fleet, one snapshot (a STABLE read): the values are the same.
- **Proof that the answers match.** The self-assert and proof 185 compare every piece with and without the change: the matrix,
  `reach_passage` (5 harbours x 3 caps), `board_legs`, `board_trips` and `board_sell` for every good sold at Lisbon and Seville (one fleet
  with a captain seated).
  - `world.best_sales` itself (time-budgeted) is never compared with a second call.
  - Found on the way: `board_legs` / `board_trips` return their rows in no fixed order between calls. This was already true on 0481, and
    their readers join by id. So those two are compared by id.

## Measured
- **Rows and bytes added:**

  | Table | Rows | Bytes on disk | Notes |
  | --- | --- | --- | --- |
  | `public.sea_courses` | 253 | 1,523,712 (about 1.5 MB, with index and TOAST) | 32,128 courses, 541,085 points, 2,664,592 bytes packed; TOAST compresses it |
  | `public.sea_reach_matrix` | 1 | 573,440 | |
  | **Total** | | **about 2.1 MB** | prod is 763 of 1,500 MB (gate, 2026-11-23 08:39 UTC) |

  The migration file is 3.9 MB (the seed is 3.9 M characters of JSON and base64).
- **Prod, before (`before-0482`, the one read, 2026-11-23 ~08:40 UTC):**
  - Head 0481; `fleet_jobs_enabled` and `hq_board_enabled` lit.
  - The newest company's oldest idle fleet at LIS (1 ship, no captain): `world.best_sales` **2,603 ms** (`cut`, 8 goods answered, 8 paying);
    `world.board_passages` **198 ms**; `coursed` **0** of 8.
  - The function bodies 0482 hunks have the same md5 as the chain's.
- **Local, before and after.** Same probe, prod's lit switches (economy closed, first hour, near choice, city treasury, goods mastery,
  logbook, `levels_bite`), median of 3-5 calls after the first:

  | Read | Before (0481) | After (0482) | Change |
  | --- | --- | --- | --- |
  | `world.best_sales` at Lisbon, no captain | 391 ms | 316 ms | -19 % |
  | `world.best_sales` at Lisbon, one captain seated | 653 ms | 558 ms | -15 % |
  | `world.board_passages` from Lisbon | 75 ms | 18 ms | -76 % |
  | `world.hq_board()`, one idle fleet at Lisbon | 471 ms | 345 ms | -27 % |

- **Prod, expected:** `best_sales` ~2.1 s instead of 2.6 s (still near its budget at Lisbon), `board_passages` ~50 ms instead of 198 ms.
  The board then takes ~2.3 s instead of ~3.1 s. The lead's `after-0482` read measures it.
- **The rest of the prod gap is not this code's:** the gate shows `public.port_goods` at 53 % dead rows (181,751 dead to 159,766 live,
  102 MB), last autovacuumed 2026-11-01. Every quote, price and mid in this read touches it. That is the lead's or the owner's to act
  on (a vacuum), not a migration's.
- **A stored course:** 100 decoded in 7 ms. The self-assert takes ~2.3 s locally. Proof 185 takes ~23 s.

## Load
- Two new tables, written once by the migration. Nothing is written at run time: the matrix row is rewritten only when the harbours or
  their miles change, and that happens only in migrations.
- No cron job and no step on the beat.
- Lit, a job plan or a board card reads a few course rows (each under 1 ms).

## Decided by default (the owner may reverse)
- **The switch is `sea_courses_enabled`, false.** Lit, the stored course is the LAST source a job tries, after the merchant lane, the
  coast course and her own voyage, so courses already sailed keep their priority.
- **The faster read is not behind the switch.** It changes no answer.
- **One course per pair**, sailed either way. The door takes all 32,128 both ways. The script would store a second row for a pair the
  door takes only one way; there are none.
- **Rounded to 4 decimals** (about 11 m). That is well under the 2 nm no-land tolerance and the 15 nm raster cell.
- **The board card's `lines`** are sent as they are when present. When a leg has no course, the card has no `lines` and the client plots,
  as in 0480.
- The 3 shared-roadstead pairs (BAS-HOR, CAP-ELM, OSA-SAK) have no stored course. Their straight line has no length, so they are left as
  they are.

## Re-shipping
Re-run `node scripts/build-sea-courses.mjs --into=<a new migration>` (about 10 minutes) after any change to a roadstead, a harbour, the
raster or the coast mask. A new migration then ships the table again. The seed's digest makes this one refuse a changed world.

## Prod checks
- Before: `scripts/ops/harness/sea-courses/before-0482.sql` (done, the one read).
- After (and 30 minutes after lighting): `scripts/ops/harness/sea-courses/after-0482.sql`.
