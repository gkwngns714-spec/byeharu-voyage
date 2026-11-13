# 2026-11-13: Trade says what a trip really costs (0361)

Owner, 2026-11-13, after the Map's Send fleet learned a trip's real time and price (0360, #611): asked whether Trade should agree with it, *"do all"*. This slice is stacked on #611.

## What was wrong

Trade's board (`world.good_board`, and `world.best_sales` for the goods cards, both through `world.board_sell`) priced a trip its own way:

- **Wages**: the day's wage times the days at sea with their fraction. The game owes a whole day for every day begun, on every leg (`voyage.settle`, `voyage.total_days`).
- **Dock fee**: the destination's only, for the parcel only, printed beside the profit and never taken off it. The game charges every harbour she calls at, on all the cargo aboard (`public.port_call`).
- **Supplies**: what the longest leg would buy as her hold stands now. The game buys before every leg, her casks emptier each time (`cmd.do_sail`).
- **Time**: the sailing only. A call on the way takes `port_prep_seconds` while the economy is closed.
- The tray also added the days to the buy city to a sell row that already counted them (a trip that buys in another city first read too long).

## What was built

- **Migration 0361 `trade_says_what_a_trip_really_costs`** (no table, no knob, no switch):
  - Three server-only helpers, 0360's own lines moved whole: `world.trip_leg` (one leg: topped up as `cmd.do_sail` tops her, its settled days eaten), `world.trip_hulls`, `world.trip_stop_seconds`.
  - `world.trip_cost` re-cut (3 hunks) to ask them. **Its answer does not change** (asserted against its pre-image, open and closed).
  - `world.board_legs` re-cut (3 hunks): every harbour's row gains the trip there (`t_sea` days owed, `t_sup` supplies walked, `t_stop` seconds in port, `t_pre` / `t_post` the harbours called at before and after a buy). A way already walked is remembered, so a harbour beyond another walks one leg more.
  - `world.board_sell` re-cut (9 hunks): `wages`, `supplies.cost`, `days`, `arrive_at` and `profit` are the trip's; new keys `sail_days`, `stop_seconds`, `dock_fee`. The dock fee is asked of `public.port_fee` once for each harbour and cargo value, for the priced rows only, and not at all while the economy is open.
  - `world.good_board` re-cut (7 hunks): its buy rows read the same legs (walked to the sellers only); her cargo's board hands its legs to `world.board_sell`.
  - `world.best_sales` is not re-cut: it reads the same rows, so every goods card moves with them.
- **Client**: `tripRows` reads the trip's end row whole (no adding); `useTripGo` no longer asks `world.trip_cost` a second time; the tray's Dock fee line prints the row's `dock_fee`; the order estimate on the Trade map gains a Dock fee line. No new words.

Where Trade knows more than a plain trip: a good bought first raises the cargo aboard, so the harbours after the buy charge on the cargo aboard now plus that buy. The Map's read prices a plain trip, on the cargo aboard now. For her own cargo, and for any trip while the economy is open, the two agree to the coin.

## What a player sees change

- **Wages go up**: a day begun is a whole day, never under one a leg.
- **Supplies go up** on a trip of several legs.
- **While the economy is closed** (prod has been since 2026-10-26): the Dock fee is every call's (250 base a call locally) and now comes off the profit; days and the real time carry 60 s a call on the way.
- **Profit goes down** by exactly those amounts. Nothing new is charged: these were always charged, and the board now says so. A goods card's best sale can change city, since profit per day is judged on the true figures.
- The city where she lies costs nothing to "sail" to (a one-day top-up used to be taken off that row).

## Measured (local, PGlite, the cached world: 339 files restored, 0361 applied)

- Self-assert: 5.7 s. Its notices: `world.trip_cost` is its pre-image on 6 trips; open, 2 boards: every other key of every row unmoved, 30 priced rows are `world.trip_cost`'s trip (20 through a harbour between), over them wages +1,051 and supplies +811; closed, her cargo: 15 priced rows are the trip to the coin (the dearest dock fee 2,615); closed, bought where she lies: 15 rows pay every call's fee on the cargo aboard after the buy.
- `scripts/db/proofs/63_trade_true_cost.sql` (7/7 markers, 1.1 s) sails the sale the board offers, economy closed: abaca from Lisbon to Boston via Angra and St. John's. On the last run the row said supplies 21, wages 160, dock fees 574, 120 s in port; the game charged 21 over three departures, 574 over three arrivals, owed 160, and she lay in port 120 s. Read again under way on the first leg, the same sale still said dock fees 574 and wages 160. The whole time was 749 s against the row's 745 s. (Her speed moves with the clock: an earlier run of the same trip read 25, 200 and 574, and was charged 25, 200 and 574.) Wages and supplies are held only where the sea left the trip alone and no leg ran into another day; dock fees and port time are held always.
- Time a call, old against new, alternated in one transaction (`paired.mjs`, 15 pairs, median):

| read | open: before | open: after | closed: before | closed: after |
| --- | --- | --- | --- | --- |
| `world.best_sales` where she lies | 414 ms | 466 ms | 386 ms | 482 ms |
| `world.best_sales` at another city | 382 ms | 429 ms | 366 ms | 427 ms |
| `world.good_board`, bought where she lies | 327 ms | 400 ms | 380 ms | 435 ms |
| `world.good_board`, her cargo | 320 ms | 362 ms | 371 ms | 402 ms |
| `world.board_legs`, once | 18 ms | 54 ms | 18 ms | 50 ms |

  So about 12 % slower open and up to 25 % closed, on this PC under PGlite. The added work is the walk in `world.board_legs` (about 35 ms a call here, twice a `best_sales`). Prod was not timed.
- Specs: `rpc.goodBoard` (new: a priced row is `world.trip_cost`'s trip), `rpc.bestSales`, `rpc.sellAnywhere`, `trade.flow` (T3 at 390: the sheet 717 in 717, as before), `trade.layout` (320, 390, 1280; EN and KO), `trade.orderEstimate`, `command.bestSale`, `command.buySell`: green locally.

## Overlaps with the other open migrations

None re-cuts a body this file re-cuts. 0355 cuts `public.crew_terms` and the registry; 0356 and 0357 the registry; 0358 `world.yard_sources`. 0361 adds no registry row. It does re-cut 0360's `world.trip_cost`, so it must deploy after 0360, and a change to that body before 0360 deploys makes 0361 refuse (each hunk must be found once).

## Decided by default (the owner may reverse)

- The dock fee comes off the profit.
- A best sale "within her purse" (0351) now asks the whole trip's supplies of her purse, not the longest leg's.
- `dues.fee` (0237) is left as it is (the destination's, for the parcel); Trade prints `dock_fee`.
- The order estimate on the Trade map always shows a Dock fee line (0 while the economy is open).

## Not done, not proven

- No prod read was made from this session. `before.sql` must be run after 0360 is in: it prints whether the economy is closed and the city purses lit on prod.
- Prod timing is not measured; only the local old-against-new above.
- The browser was driven on the local world, where the economy is open: the Dock fee lines read 0 there. Dock fees above 0 are proven on the server only (self-assert, proof 63).
- A fleet at anchor with no voyage (her first leg is the miles to the nearest harbour) is walked but not proven by a sailed trip.
- Not known to any read: a storm or a calm, short rations (the wage is then 1.5 times), the room a buy takes from her stores on the legs after it.
- The route builder's lap figures (`RouteFold`, the Map's passage estimate) come from other reads and were not touched.
