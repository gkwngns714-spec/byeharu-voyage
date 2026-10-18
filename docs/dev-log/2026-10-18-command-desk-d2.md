# 2026-10-18 — 0171: COMMAND DESK D2, one good, every city — `osn-desk-d2`

`docs/COMMAND_DESK.md` §3.2, §3.3, §7.2, §7.3, §10 row D2. **Not deployed.** The number 0171 is **provisional**:
prod head was 0170 (D1, live) when I wrote this. Two other migrations are in flight in this area (city purses;
distance pricing), so the number is head + 1 at push time.

## What was built

| Concept | Its one home | Notes |
|---|---|---|
| the best-time rule | `public.outlook_best(points, from, side)` | moved out of `world.price_outlook` (one hunk). The read composes it at its own now; the board composes it at an arrival |
| one good at every city, for your fleet | `world.good_board(good, fleet, from, qty)` | registered; `authenticated` only; `E_NOT_YOURS` for another company's fleet |
| every good once | `world.watchlist(fleet)` | registered; `authenticated` only |
| how many rows are priced in full | knob `good_board_quoted` 10 | |

**Every figure is a call of its one authority:**

| Figure | Authority |
|---|---|
| money | `world.quote` (0169's `quote_priced` / `quote_terms` underneath, with the fleet's purser and bargain) |
| market price | `world.mid_price` |
| profit tax | `public.profit_tax` |
| wages | `public.fleet_wage` × voyage days (voyage.settle's own figure) |
| miles | `voyage.reach_from` |
| speed | `voyage.fleet_speed` |
| cap left | `world.daily_cap_remaining` |
| the estimate | `world.price_outlook` + `public.outlook_best` |

No price arithmetic is copied. A term added inside `world.mid_terms` / `world.mid_from_terms` / `world.quote_priced`
therefore reaches the board and the watchlist by itself. The one caller to watch is **`public.price_path` (0170)**.
It calls `world.mid_from_terms` with the row's terms spelt out, as `world.market` and `world.quote_priced` do. A new
argument to that expression must be passed there too. Every such caller is a hunk of the migration that adds the term.

**Where it departs from COMMAND_DESK, stated:**
1. **The port fee is served but not subtracted again** (D7 listed it as a cost). It is already inside what the fleet
   gets.
2. **Requests carry `premium_pct` and `days_left`, not a clock time.** The clock is `world.contracts`' own spelling.
3. **The watchlist's market price is the record's.** It reads `public.price_history` at its newest slot (world.mid_price
   as the snapshot wrote it, at most a drift slot ago; `as_of` says when). A pair with no point there is priced live
   and marked `recorded: false`. That covers the local game, which has no snapshot job.
   - On prod this read takes 83 ms. Pricing all 1,348 sold pairs live takes 292 ms.
4. **Only the 10 dearest cities by market price are priced in full.** The rest carry the market price and the miles.
   - This is the design's own fallback ("stage 1 / stage 2").
   - The client sorts the quoted rows by net.
5. **A board from a bare sea point has no miles, days or arrival.** An anchored fleet has no row in the
   sailed-distance table.

## Proof (in the migration; cached PGlite world on 0170)

- **world.price_outlook:** old = new on 60 md5-chosen rows × mid / ask / bid. It reverses to its pre-image, with the
  ACL unmoved.
- **outlook_best, on built points, takes every arm:**
  - a rise gives the top;
  - from the top, nothing;
  - an ask from 100 gives nothing;
  - from 110, 104 beats a ±5 band;
  - a +2 gain inside a ±5 band gives none;
  - an empty list gives none.
- **The probe company** ("Casa do Balcão 0171", Lisbon, signed in as it, rolled back), on anise:
  - 3 buy rows, with Lisbon here at 0 miles;
  - 238 sell rows, equal to the harbours that buy it;
  - 10 quoted rows, each equal to `world.quote` + `profit_tax` + `fleet_wage × days` to the coin (the top row is HOB,
    net 1,640);
  - after buying 10 through `cmd.do_buy`: basis `on_board`, cost = `fleet_cargo_basis × units`;
  - another company's fleet is refused `E_NOT_YOURS` on both reads;
  - the watchlist has every good once, with the cargo on board;
  - the cheapest seller of 20 goods matches a recomputation;
  - no sparkline is longer than 12 points;
  - the company is gone after the rollback.
- **Receipt:** registry +2; both reads are `authenticated` only; the leaf is server-only; the walls hold; neither read
  steps a clock or settles a fleet.
- Timings on PGlite (notice only): good_board 151 ms, watchlist 227 ms (every pair live — no record in a built world).

## Read-only on production (2026-10-18, after 0170; `begin transaction read only`, result raised)

**Safety and hunks:**
- I checked every function I called for `provolatile` first. All were `s` or `i`.
- Both hunks occur exactly once in the live bodies (`world.price_outlook`, `client_rpc_entry_points`).
- None of the three new functions and not the knob exist yet.

**Timing:** I ran the two reads' bodies as anonymous blocks against a real docked player fleet. `outlook_best` is not
on prod yet, so it was replaced by null in those runs.
- **watchlist: 83 ms.** 555 goods, all 555 recorded.
- **good_board: 333 ms** on a second run (500 ms on the first; bombard from Acapulco, 3 buy and 238 sell rows). This
  is over the design's 150 ms target.

**Where good_board's time goes:**

| Piece | Prod cost |
|---|---|
| `world.price_outlook` | 9.4 ms a call × 13 (3 buy rows + 10 quoted) |
| `world.quote` with the fleet named | 5.8 ms a call (1.3 ms without: the purser and bargain read) × 13 |
| `world.daily_cap_remaining` | 1.6 ms × 10 |
| `world.mid_price` over 238 cities | 4 ms |
| `voyage.reach_from` | 2 ms |

The read is asked on a tap: opening a good, or changing the amount. It is never asked on the 30 s beat. It settles
nothing and steps no clock, so it cannot load the arrivals sweep.

If it must be faster, the levers are:
- `good_board_quoted` (each quoted row ≈ 17 ms on prod);
- the estimate only for the first few rows.

Either is a one-line change.

## Verify (once)

- Build on the cached prefix (162 restored, 0171 applied); `tsc -b` ran inside the build.
- `eslint .` clean.
- `rpc.goodBoard.spec` (new): 4 passed.
- The other selected specs, on a local build at `localhost:4260`: 56 passed, 0 skipped (rpc.surface, rpc.firstSession,
  duplication, sea.dateline, map.townhall).
- `rpc.outlook.spec`: 4 passed (run with the new spec).
- db.chain and db.image are left to CI.
- Selection map: `rpc.goodBoard.spec.ts` added to `tests/shard-weights.json`; rule S selects it.
- No screenshot: this slice draws nothing (the desk is D3).
