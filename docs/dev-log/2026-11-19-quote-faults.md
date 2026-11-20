# 2026-11-19 - A trip is quoted as it is sailed (0459; the three faults 0454 left)

0454 (`docs/dev-log/2026-11-18-stores-quote.md`, "Not changed") left three faults in the trip quote. Each was checked in the code, then built on
purpose and sailed by proof 162 on the local chain at 0458, before any fix. All three were real.

## The faults, and their causes

1. **The time.** `world.trip_cost` (the Map's Send fleet), `world.board_sell` (Trade's sell rows) and `world.good_board` (Trade's buy rows) said a
   trip's `days`, `sail_days` and `arrive_at` at her speed in port: `voyage.fleet_speed` read once (`trip_cost`'s `v_speed`), or
   `world.board_origin`'s `speed`. The SAIL freezes her speed after the leg's top-up (`voyage.depart`). Since 0454 the walk already used that speed
   for the days it settles; only the time was left on the speed in port.
2. **A good bought on the way.** `world.board_legs` walked the legs after the buy city with the cargo aboard now. It knew nothing of the amount, so
   a full hold bought there was not in her speed (fill = cargo + stores over her hold, `load_speed_penalty` 0.25). The days, the wages and the
   stores after the buy were a lighter ship's.
3. **An anchorage.** From her own anchor the walk topped her up for the way in to the nearest harbour (`world.trip_leg` with a top-up).
   `cmd.do_sail` buys stores only when she is docked (`f.status = 'DOCKED'`), so the quote counted stores the SAIL never buys.

## Reproduced first (proof 162, local chain at 0458, before 0459)

The sea calmed (`hazard_p_max` 0) and the economy open, inside the rolled-back proof. Each block ran on its own:

    FAIL (time): the quote says 4.54 d (leg 4.54 d, all 4.54 d) and she takes 4.5713 d to REY (1634.5 nm; in port 15.0000 kn, she sails at 14.8979 kn)
    FAIL (bought on the way): andalusian-horses 378 at SET (378 units, 567.0 t), sold at NAN: stores: paid 190054 in all, the buy 190039 and the
         stores 13 were quoted (so 15 for stores); time: quoted 2.15 d (all 2.15 d), sailed 2.8205 d on the board's miles.
         Leg 1 to SET: 45.9 nm, 14.9888 kn, settles 1 d; leg 2 to NAN: 727.1 nm, 11.2500 kn, settles 3 d
    FAIL (anchorage): 18.8 nm in (42 on the board) at 15.6614 kn: stores: the SAIL bought 0, the row said 1

(A first run of the anchorage block with one day of casks also showed wages 30 owed against 20 quoted: she ended the way on short rations,
which the quote does not foresee. The proof gives her a day and a half, so it tests the stores alone.)

## The fix (0459)

One home for each rule. Where the quote and the sail did the same thing in two places, one now calls the other.

- `world.trip_leg` (dropped and created: its answer gains a column) answers `sail_days`: the leg's miles at her speed laden with its stores, in
  voyage-days with their fraction (what `voyage.depart`'s eta is). `sea_days` is that rounded up, as before. A hull's other keys ride through.
  Without a top-up it walks the leg on the casks she has.
- `world.trip_cost`: each leg's `days` and the trip's `sail_days` are `world.trip_leg`'s. Its speed in port is gone.
- `public.stow_takes` (new): THE stowing rule, `public.fleet_load`'s loop moved out whole (largest hull first, equal hulls by id, whole units in
  the room beside her cargo and stores). `public.fleet_load` now loads what it says. The migration checks a probe load is the same before and after.
- `world.trip_hulls` carries each hull's `cap` and `cargo` (tuns). `voyage.fleet_speed_of` takes `cargo` from the walked hulls, as it took water
  and food. `world.trip_stow` (new) puts a buy into walked hulls with `public.stow_takes`, and the stores' room with `public.ship_stores_room`.
- `world.board_trips` (new): `world.board_legs`' walk (0361), moved out whole. From an anchorage the way in is walked with no top-up. A buy
  (`p_ctx.buy`: units, bulk) is stowed as she leaves the buy city. Each row gains `t_sail`, `t_days` and `t_arrive`: the time to her first
  harbour is `world.board_origin`'s `lead_at` (a voyage's eta, or the way in at her speed now), then the walked legs, then the calls on the way.
- `world.board_legs` asks `world.board_trips` for its walk.
- `world.board_sell`: when one amount is bought for every row (Trade's board), its legs are walked with that buy. A priced row whose units the
  legs were not walked with (`fit`, or legs handed over by `world.best_sales`) is walked again with them, once a distinct count. `days`,
  `sail_days`, `arrive_at`, `supplies`, `wages` and `profit` read the walk.
- `world.good_board`: a buy row's `days`, `sail_days` and `arrive_at` read the walk.
- `world.best_sales`: the legs it shares for a good bought here are no longer walked (`only` none). `world.board_sell` walks each good's
  priced rows with that good's own amount aboard, and best_sales serves only priced rows. (Without this, best_sales walked every row twice.)
- The time's own variables (`v_tc`, `v_lead_at`) left `world.board_sell` and `world.good_board`: nothing there reads them now.

No second copy of the speed, the stowing, the top-up or the days. 33 hunks over 8 bodies, each once and reversing.

## After (proof 162 on the chain with 0459)

    PASS: QUOTE_TIME_MAP: LIS to REY (1634.5 nm): quoted 4.23 d, sailed 4.2312 d (in port 16.1900 kn, laden with the leg's stores 16.0956 kn)
    PASS: QUOTE_BUY_WEIGHT: 386 x andalusian-horses bought at SET (579.0 t aboard), sold at BOR: stores 15, wages 88, 2.83 d, as quoted
          (leg 1 to SET: 45.9 nm, 15.5279 kn, settles 1 d; leg 2 to BOR: 756.8 nm, 11.6550 kn, settles 3 d)
    PASS: QUOTE_ANCHOR_STORES: at anchor 42 nm off Lisbon: the SAIL bought 0 of stores and the row said 0; wages 20, as quoted

(A new hull rolls its stats, so each run picks its own scene; the figures differ run to run, the checks do not.)

## Other proofs run on the chain with 0459 (scratch runner on the cached world: each file in a rolled-back transaction, every declared marker checked)

- 157 (3/3), 07 (4/4), 62 (6/6), 63 (7/7), 70 (5/5), 74 (6/6), 97 (3/3), 134 (5/5), 04 (9/9), 162 (3/3): all pass, no error.
- After the last change to the file (best_sales, the buy stowed once), run again: 162, 134, 63, 70, 157, 62: all pass.
- Proof 63's TRADE_TIME now reads 3,218 s sailed and in port against 3,204 s quoted (0.4 %: the board measures the sailed-distance table, the
  SAIL its own course). Its 3 % bound is kept; its comment no longer says the board uses the speed in port.
- The migration's own receipt (local): 33 hunks once each and reversing; 60 live fleets' speeds unchanged; a probe load of public.fleet_load
  the same before and after (120 / 260 horses in two hulls); a docked board walks 229 rows the same before and after; 2,956 ms.
- Not run locally: the whole proof suite and the browser specs (CI runs them). `npm test` here would be a false green (`.env.local`).

## Cost

Local PGlite, a two-hull fleet (barca + caravelao) at Lisbon, mean of 5 calls, ms. Other builders were running heavy jobs on this PC at the
same time, so the same code measured up to 2x apart minute to minute. Each pair was run back to back.

| run | board_legs (docked) | good_board, bought at SET | good_board, bought cheapest | best_sales at LIS | best_sales at SET |
|---|---|---|---|---|---|
| 0458 (a) | 2,309 | 4,030 | 4,385 | 3,186 | 2,942 |
| 0459 first cut (a) | 2,731 | 7,405 | 7,409 | 3,244 (cut) | 3,691 |
| 0459 first cut, buy stowed once | 695 | 2,038 | 2,137 | 2,630 (cut) | 1,923 |
| 0458 (b) | 772 | 1,987 | 2,015 | 2,005 | 1,701 |
| 0459 shipped | 397 | 973 | 933 | 1,232 | 859 |
| 0458 (c) | 384 | 1,027 | 1,129 | 1,151 | 946 |
| 0459 shipped | 760 | 1,806 | 1,842 | 2,063 | 1,336 |

The first cut stowed the buy again on every way walked from the buy city (good_board about 1.8x), and best_sales walked every row twice, then
again per good (it hit its 2.5 s budget, "cut", at LIS). The shipped file stows the buy once a walk and best_sales skips the walk it never
serves. In the quiet pair (0459 shipped against 0458 (c)) the figures are within a few percent both ways; the noise here is larger than that,
so a difference under about 10 % is not shown either way. Prod is native Postgres; these are reads a player makes (no rows, no job).

## Not changed (seen, not fixed)

- From an anchorage the board measures the way in to the harbour itself (`world.board_origin`'s `lead_nm`: 42 nm in proof 162); the SAIL sails to
  its roadstead (18.8 nm). The way in's days and its wage day can differ from the quote. A slice of its own.
- The longest leg's `days` and `supplies.days` / `fits` (`public.supply_needs`) are still at her speed now.
- A storm, a calm, a raider, or short rations are not foreseen (as before).

## PROD CHECKS (read only; the lead runs them before `bv-deploy.sh`)

1. The gate: `scripts/ops/harness/db-health/gate.sql` green; prod head `20260818000458`.
2. `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/quote-faults/before.sql`: `new_names_free` and `probe_needs_there` true
   on every row, and each md5 the chain's at 0458 (local cached world, 2026-11-19):

   | function | md5 |
   |---|---|
   | public.fleet_load(uuid,text,numeric,numeric) | 4638d66e9f7113030e6d894700aacdc7 |
   | voyage.fleet_speed_of(jsonb,numeric,jsonb) | 7047717adf74fabfd211369daee1687f |
   | world.best_sales(uuid,uuid) | 364134ceefa907cf711c17dc006a4afc |
   | world.board_legs(uuid,jsonb) | 7067b82465b837b2de3b0f031d45a62c |
   | world.board_sell(uuid,uuid,jsonb) | c6b5802d403f6eecf59d2a8fddf5a136 |
   | world.good_board(uuid,uuid,uuid,numeric) | e6be6856c053e339b42740855902c5d7 |
   | world.trip_cost(uuid,jsonb) | d06eca8deb8e8661ed587b7bd22db485 |
   | world.trip_hulls(uuid) | e05f2b65d63603c95191c93854ebf05f |
   | world.trip_leg(jsonb,jsonb,numeric,boolean,numeric) | f039b39f4ff7fc1d18ab6a0cff54d552 |

   A different md5 means a hunk may not match: the migration then refuses with nothing changed, but read why first.
3. After the push: `scripts/ops/harness/quote-faults/after.sql`: 4, true, true, `20260818000459`.

The self-assert's probe sails nothing and rolls no dice, so prod's `world_secret` cannot change its answer. It reads the speed of up to ~60
live fleets and every armada's twice (stable reads) and walks one probe board twice. Rows a minute after the deploy: none extra (no table, job,
knob or cron; the board and the Map's quote are reads a player makes).
