# 2026-11-13: a far city is sent in one press, with its time and its price

Owner, 2026-11-13: *"when moving to a city, anywhere, far away, it says navigation restriction. i want the game to calculate which cities to cross automatically, and just tell me the final time, price reaching the destination when pressed send fleet."* Then: *"add wages and dock fees to the price too"*, *"but separately"*, and *"docking - resailing takes time too. So this also needs to be accounted for."*

## What was wrong

The Map's city panel (Send fleet) dry-ran ONE sail to the tapped city. A city past one leg of her Navigation ended at the server's refusal (`E_LEG_TOO_FAR`: "that leg is 3843 nm and your navigation carries you 1700 nm"). Trade's Sail & sell and Sail & buy already went through stop-over ports, and route mode already offered "Via N". The plain send did not, and it printed no price at all.

## What was built

- **The client (works without the migration):** one passage planner (`src/domain/passage/chain.ts`, `src/live/passagePlan.ts`). The stop-over ports are the server's (`world.route_legs` → `voyage.reach_passage`: fewest sailed miles with every leg inside her Navigation and her supplies; of two equal ways, fewer calls). Every leg is judged by the server before the trip is offered, the first sail is dry-run like any other, and Send queues every sail through `cmd.issue_lines`, all or none. Her per-leg reach is unchanged. A city no chain reaches keeps the refusal, with "No port to stop at on the way."
- **Migration 0360 `a_trip_says_its_time_and_its_price`:** `world.trip_cost(fleet, legs)`, a STABLE read granted to authenticated only, plus one registry row (anchored after `world.route_legs`) and its news row. It prices a trip with the authorities that charge it:
  - **supplies**: her casks walked along the trip (topped up before each leg as `cmd.do_sail` tops her, each leg's settled days eaten as `voyage.settle` eats them). `world.route_legs` serves each leg as her hold stands now, which under-reads a trip of several legs.
  - **wages**: `public.fleet_wage` for every settled day of every leg (a day begun is a day owed, `voyage.total_days`). Owed as she sails, paid out of her next sale's profit.
  - **dock fee**: `public.port_fee` of every harbour called at, the last included, for the cargo aboard now at cost. 0 while the economy is open.
  - **time**: the sailing of every leg plus `port_prep_seconds` a call on the way while the economy is closed (`fleets.ready_at`). The arrivals job runs every second (0242), so nothing more is added.
- **The row:** the whole trip's days with real time, a small "via A, B" line, then Supplies, Wages, Dock fee (Trade's words, Trade's order) and Total, each on its own line. Before 0360 is in a world the read is missing and the row falls back to sailing time and `route_legs`' supplies.
- **Trade:** the panel's Days now adds the real time of the calls on the way (the same read). Its money lines are still the board's.

## Measured

- Local apply (PGlite, the prefix cache: 337 files restored, 0360 applied): the self-assert passed in 485 ms; `world.trip_cost` 2 ms a call for a two-leg trip. Its notice: empty casks out and home cost 7 then 2; with a leg's stores aboard 0 then 2 where `route_legs` serves 0 then 0; closed, 60 s a call on the way.
- `scripts/db/proofs/57_trip_cost.sql` (6/6 markers, 0.3 s) sails Lisbon → a harbour a day away → Lisbon with the economy closed for that transaction and compares the read, taken before she left, with what the game then did: 7 at the first departure as read; in port 60 s after the first arrival (still docked one second before), then the second sail left; 5 at the second departure, read 5; dock fees 250 and 63 as read; 80 wages owed, read 80; the purse fell by 325 = supplies 12 + dock fees 313.
- Browser drive `tests/map.autoroute.spec.ts`, local world (economy open: no dock fee, no port time), headless, 390 px English: Lisbon to Istanbul via Algiers, shown 509 s, arrived after 518 s on one press (tolerance: 10 s early, the larger of 45 s and 15 % late); shown Supplies 0, Wages 48, Dock fee 0, Total 48; the purse was 40,000 before and after (wages are owed, not debited). 320 px Korean: the four cost lines each on one line, no sideways scroll, and Callao keeps its refusal with the plain reason.

## Not done, not proven

- `scripts/ops/harness/trip-cost/before.sql` was NOT run on prod from this session (the read was refused by the session's permissions). It must be run before the deploy: it also prints whether the economy is closed on prod, which decides whether dock fees and port time are in force there.
- 0354 to 0359 belong to other branches. 0360 deploys after them; until then the client shows sailing time and `route_legs`' supplies only.
- The read cannot know a storm or a calm (a longer leg: more days, more eaten, more owed), cargo bought or sold on the way (the dock fee is for the cargo aboard now), or short rations (the wage is then 1.5 times).
- Trade's board is not re-cut: its `wages` line is the wage times the days with their fraction, so on a trip of several short legs it reads lower than the Map's (which is what settle owes); its dock fee is the destination's only; its cards' days leave the calls on the way out. That is a re-cut of `world.good_board`, its own PR.
- Insurance is not offered on a chained send. A fleet already at sea still turns in one leg.
