# 2026-11-18 - A trip is quoted at each departure's speed (0454; the known fault recorded in #752)

## The fault

Trade's board and the Map's Send fleet quote a trip's supplies and wages by walking the trip leg by leg (`world.trip_leg`, 0361). The walk
used ONE speed for every leg: her speed in port, before any stores were aboard (`world.trip_cost`: `voyage.fleet_speed` once;
`world.board_legs`: `world.board_origin`'s `speed`).

The SAIL reads her speed twice a leg (`cmd.do_sail`):

- before the top-up, `public.supply_need` -> `public.supply_needs` reads `voyage.fleet_speed` with the casks she carries into that departure:
  the days she is topped up for (`public.npc_leg_days`);
- after the top-up, `voyage.depart` reads `voyage.fleet_speed` again and freezes it for the leg: the days `voyage.settle` settles, eats and
  owes a wage for (`voyage.total_days`).

Stores weigh: `voyage.ship_speed_at`'s fill is cargo + water + food over her hold, and `load_speed_penalty` is 0.25. So laden she is a shade
slower than in port. A leg that ends just inside a day in port runs into the next one at sea: one more day eaten and owed, and the next
leg's casks start emptier, so the next top-up buys more than the quote said.

## Reproduced first (local chain at 0453, before any fix)

Proof 157 (new) builds the case on purpose: a barca at Lisbon, casks empty, a calm sea (`hazard_p_max` 0 inside the rolled-back proof), the
economy open; the first leg is the one from Lisbon closest under a whole day count, and her hull is worn (durability, a straight write) until
in port the leg is under n days and laden with its own top-up (the real `cmd.do_provision`, rolled back to a savepoint) it is over n.

Before the fix:

    PASS: STORES_QUOTE_SCENE - LIS to ARP (1064.5 nm) then MID (35.9 nm): in port at 14.8210 kn the first leg is 2.9927 d (settles 3),
          laden with its top-up at 14.7493 kn 3.0073 d (settles 4)
    FAIL: the supplies cost 14 over the trip and the quote said 12 (leg 1: stores 12, settled 4 d at 14.7493 kn; leg 2: stores 2,
          settled 1 d at 14.7924 kn; quote ... "wages": 80, "supplies": 12 ...)

The quote walked leg 1 as 3 days and leg 2 as 1 (wages 80: 4 settled days at her 20 a day) with nothing to buy for leg 2; the SAILs settled
4 days on leg 1 and 1 on leg 2 (owed 100), and leg 2 had to buy 2 of stores. Proof 63's own run on the same chain also showed her laden speed under her speed in port at
every departure (14.828 / 14.771 / 14.785 against 14.857), only without crossing a day that time.

The cause is in the walk's speed, as recorded. Places (live bodies at 0453):

- `world.trip_cost` (0360, re-cut 0361): `v_speed := greatest(voyage.fleet_speed(p_fleet), 0.1);` then
  `world.trip_leg(v_hulls, v_nm, v_speed)` for every leg.
- `world.board_legs` (0350, re-cut 0361): `v_speed numeric := greatest(coalesce((p_ctx->>'speed')::numeric, 0), 0.1);` then
  `world.trip_leg(v_h, v_nm, v_speed)` for every leg.
- `world.trip_leg` (0361): `v_top := public.npc_leg_days(p_nm, p_speed)` and `sea_days := ... ceil(p_nm / p_speed / 24)`, both at the one
  speed handed in.

## The fix (0454)

One speed rule, cut in two at the fill, so the walk can ask it of the casks it walked:

- `voyage.ship_speed_parts(ship)`: what a hull's speed is made of, all but her fill (k = speed stat x hull state x hands x wind; hold;
  cargo by bulk; casks). `voyage.ship_speed_of(parts, fill)`: the fill put in, `round(k x (1 - load_speed_penalty x fill), 4)`.
- `voyage.fleet_speed_parts(fleet, alone)`: every hull's parts, the fleet's factor (formation x captains x Navigation), and her kind's
  multiplier or, in an armada, its other fleets' parts. `voyage.fleet_speed_of(parts, fill, stores)`: the fleet's speed from them;
  `stores` gives a hull other casks than her own.
- `voyage.ship_speed_at`, `voyage.fleet_speed_alone_at`, `voyage.fleet_speed_at` keep their signatures and call these. Every speed read is
  unchanged to the digit (self-assert: 60+ live fleets with every armada's and some navy and pirate fleets, null fill and full, and their
  hulls at null, half and full; proof 68's 879 fleets old against new).
- `world.trip_leg(speed parts, hulls, nm, top, sea)` replaces the old one: the top-up's days at `fleet_speed_of` with the casks she carries
  into the departure, the settled days at `fleet_speed_of` with the casks topped up. Exactly where `cmd.do_sail` reads it.
- `world.trip_hulls` carries each hull's id; `world.trip_cost` and `world.board_legs` hand the walk her parts (the board reads them once).

No second copy of the speed formula, the fill, the top-up or the days.

### A first cut that was too slow

The first version passed the casks down through the old bodies (`voyage.fleet_speed_stores` -> `ship_speed_stores`), so every leg of the
walk re-read every hull (`world.ship_stats`) twice. Measured on the local world (PGlite, a two-hull fleet at Lisbon, mean of 5):

| | before 0454 | first cut | parts cut (shipped) |
|---|---|---|---|
| `world.board_legs` | 173-203 ms | 559 ms | 281 ms |
| `world.good_board` | 371-444 ms | 757 ms | 541 ms |
| `world.best_sales` | 465-554 ms | 851 ms | 645 ms |
| `voyage.fleet_speed` over 875 fleets | 1,029-1,049 ms | - | 1,052-1,157 ms |

(The "before" range is two runs of the same chain on different minutes: PGlite timing is noisy.) The shipped cut asks the parts once a
board and does arithmetic each leg: the board costs about 80 ms more on PGlite (two `fleet_speed_of` a leg), the plain speed read the same.
Prod is native Postgres: the board is a player's read on opening Trade, not a job, so it adds no rows and no load a minute.

## Proofs

- 157 (new): fails before (above), passes after: `14 over 2 departures, as quoted`; `100 owed, as quoted`.
- 63: its supplies and wages checks are strict again where the sea took nothing (#752 had to add "and every leg settled the board's days";
  now a clean sea with a leg off the walk's days is itself a failure). Run after: clean sea, 24 against 24, wages 160 against 160, leg 2
  laden at 14.492 against 14.857 in port.
- 70: walks with the new `world.trip_leg`. Also found while running it: its dark step was flaky on its own. The barca's hold is rolled
  (180 t one run, 182 and 199 others); abaca at 1.4 t a unit left 0.8 t free in a 180 t hold, and dark, 0.8 t of stores carry 20 hands
  over the short first leg, so the dark SAIL was not refused. A brimmed hold now leaves under 0.3 t (it was under 1 t). Run on main without
  0454 it passed (hold 199) and failed with 0454 only on the 180 t roll; the next run (182 t) passed.
- 68 (armada, every fleet's speed old against new) and 119 (combat ships' speed): run once, pass.

## Not changed

- A trip's `days`, `sail_days` and `arrive_at` are still at her speed in port (`world.trip_cost`'s `v_sail`, `world.board_sell`'s days);
  proof 63 holds the time within 3 %. A slice of its own if the owner wants the minutes exact.
- A good bought first on the way weighs her down too; the board walks the cargo aboard now (0361's "what it does not know").
- From an anchorage the walk still tops her up for the way to the nearest harbour, where `cmd.do_sail` buys only when docked.

## PROD CHECKS (read only; the lead runs them before `bv-deploy.sh`)

1. The gate: `scripts/ops/harness/db-health/gate.sql` green; prod head `20260818000453`.
2. `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/stores-quote/before.sql`: `new_names_free` and `probe_needs_there`
   true on every row, and each md5 the chain's at 0453 (local cached world, 2026-11-18):

   | function | md5 |
   |---|---|
   | voyage.fleet_speed_alone_at(uuid,numeric) | 3b9df421d19ce260a5aa4618e3c4c670 |
   | voyage.fleet_speed_at(uuid,numeric) | 7c805dc9617400f3449d2e14ccf87be7 |
   | voyage.ship_speed_at(uuid,numeric) | a6edec86baa55f7d311481c8d4c60896 |
   | world.board_legs(uuid,jsonb) | 52030b62bd04a5b05c9636c9533f6770 |
   | world.trip_cost(uuid,jsonb) | 04e38b5cc79bfb8aca8a9dfdfbd6dc33 |
   | world.trip_hulls(uuid) | 76c358d6c3d0da7fe9f0ffbc4389fe6f |
   | world.trip_leg(jsonb,numeric,numeric,boolean,numeric) | ef5326d284d25730dbfb15ffbe8407ae |

   A different md5 means a hunk may not match: the migration then refuses with nothing changed (each hunk is asserted once), but read why first.
3. After the push: `scripts/ops/harness/stores-quote/after.sql`: 5, true, `20260818000454`.

The self-assert's probe sails nothing and rolls no dice, so prod's `world_secret` cannot change its answer. It reads the speed of up to ~80
live fleets twice (stable reads). Rows a minute after the deploy: none extra (no table, job, knob or cron; the board and the Map's quote are
reads a player makes).
