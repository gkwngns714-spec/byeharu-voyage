# 2026-11-24 — 0495 `dividend-hourly`: dividends are paid every hour (dark, proof 198)

The owner, row 373: "investing will give you dividends every hour". Design: `docs/design/hq-corp-2026-11-24.md` D6 (there numbered
0494; the numbers moved up), `docs/design/hq-corp-economy-2026-11-24.md` section 9. Switch `dividend_hourly_enabled`, false as deployed.

## What happens today (read in the live bodies)

- `public.tick_city` runs at :37 every hour. Its step 6 calls `public.city_coupons` for a harbour once a real day (the 00:37 UTC run).
- `public.city_coupons` pays least(the dues, the city's surplus, its profit of the day), pro rata, into `city_shares.accrued`
  ("set aside"; the DIVIDEND flow leaves the city's purse then). It credits no purse.
- A purse is paid only by `public.collect_coupons`, when a fleet of hers makes that harbour.
- So a holder who buys shares and never has a fleet arrive there is never paid. The owner's 461,384 d. of shares earned her purse
  nothing: that is the fault under "investing causes less money".

## The first build was refused by the database budget (2026-11-25)

The first build computed a coupon every hour for every holder at every harbour (a ring of 24 hourly profits on each purse row).
The lead's prod read, 2026-11-24 20:57 UTC: **3,657 pairs = 3,656 merchants + 1 player**, 254 harbours. Lit, that was up to
H + 5 P = 18,500 row writes an hour and about 88,000 new ledger rows a day on the smallest database. Refused. Rebuilt as below;
0495 was never deployed, so the file itself was changed.

## The rule now, lit: one computation a day, as today; only its pay-out to players is hourly

- **The day's coupon is untouched.** `public.city_coupons` computes it once a real day for every holder, merchant and player
  together, by today's one statement: same dues, same least(dues, surplus, the day's profit), same pro rata, same DIVIDEND flow,
  same `accrued`.
- **So the limits are shared by construction.** The hourly pay-out to players and the merchants' coupon come out of one figure,
  computed once. Nothing can be paid twice against the same profit, and the city pays, to the coin, what today's rule lets it pay.
- **A merchant** (`players.is_npc`) stays exactly on today's path: `accrued`, collected at arrival. No row of hers gets a new value.
- **A player's** part of the day's coupon is, besides, marked on her share row (one hunk on `city_coupons`' own UPDATE):
  `drip_left` = what is still to pay out, `drip_hour` = round(that / 24).
- **Every hour** `public.tick_city` (one hunk) calls `public.city_coupon_hour`: each player with something left is paid
  least(`drip_hour`, `drip_left`, `accrued`) from each such row, straight to her purse, in one credit (kind DIVIDEND) for all her
  harbours; `accrued` falls by the same coin. This is what `collect_coupons` does at an arrival, an hour's part at a time.
- No city's purse is read or written by the hour, and no harbour without a human holder is touched at all.
- So her dividend arrives every hour, and it is yesterday's coupon: the first hourly coin comes after the first daily coupon that
  follows her buy (the 00:37 UTC run), then 1/24 of it every hour.

Why not a coupon computed each hour: an hourly limit cannot keep "never more than today's rule" (0312's own warning: hour 1 earns
100 and pays it, hour 2 loses 100, the day netted 0 and paid 100). Paying out a coupon that is already computed keeps it exactly.

## The owner's holding

| 461,384 d. of shares, one hour, lit | paid to her purse |
|---|---|
| yesterday's coupon was paid in full (the city's profit and surplus covered it) | **346 d.** (8,305 d. a day; 1 d. rolls to the next day) |
| she sails for the country that holds the city, race lit (x1.5) | 519 d. |
| the city's day earned 12,000 d. against 29,905 d. due | 139 d. (her part, 3,332 d., over 24 hours) |
| the city lost money that day | **0 d.**, nothing carried |
| dark (as deployed), no fleet ever arrives | 0 d. to the purse; the coupon waits in `accrued` |

## An hour she misses is not lost; twice in an hour is impossible

- The hour never waits for a holder's row: the house first (FOR UPDATE SKIP LOCKED), then her share rows (0122's order). No
  harbour lock is taken: no purse is judged.
- A holder who is mid-trade at that instant, or an hour the tick did not run, is not paid then. The coin stays in her `drip_left`
  and `accrued`. The next day's coupon folds what is left into the new pay-out, and an arrival collects all of it, as today.
  It is bounded by what was set aside for her, so no lump can exceed it.
- A row is paid only while its `drip_at` is before this hour, read under its row lock and set in the same statement, and never
  more than `accrued` holds.
- Old `accrued` (from before the switch) is never paid out hourly: only coin marked by a lit day's coupon is. An arrival collects
  everything, marked or not; the hour then finds nothing left and clears the mark.

## Decided by default (the owner may reverse)

1. Yesterday's coupon paid out hourly, not a coupon computed each hour (above).
2. One credit a player an hour for all her harbours: one ledger row.
3. No event and no news for a paid hour. Holdings (`world.holdings` `paid`, `owed`) and the Ledger's Dividends line
   (`company_rate_for`, 0493) already read ledger kind DIVIDEND and `accrued`: no client change and no new word.
4. If the switch goes dark again nothing is lost: what is left is in `accrued` and is collected at arrival.

## Rows

P = player-and-harbour pairs with a pay-out left, held by N players. Merchants: none, ever.

| table | dark | lit, an hour |
|---|---|---|
| city_shares | every row once a day (the coupon), as today | + P row updates |
| ledger | as today | N rows (DIVIDEND) |
| players | as today | N purse updates |
| stats_live_deltas | as today | N + P rows |
| port_treasury, treasury_flows | as today | 0 |

- **P = 1** (prod today: one player, one harbour): **5 row writes an hour**, 24 ledger rows a day.
- **P = 100** (100 players, one harbour each): **500 row writes an hour** (8 a minute, in the :37 run), 2,400 ledger rows a day.
- The first build: 18,500 an hour, 88,000 ledger rows a day.

The tick, local PGlite, whole world, proof 198's notice: step 6 with the day's coupon 43 ms dark and 43 ms lit; a lit hour with
no coupon 2 ms (2 players paid). Not measured on real PostgreSQL.

## Verified (local, PGlite)

- 0495's self-assert (156 ms): 2 hunks once and reversing; no other function, knob or grant moved; three new functions server only
  (public, anon, authenticated, service_role); DARK IDENTICAL (the daily coupon before and after the hunks: every figure, row and
  flow; nothing marked). On a probe player and a probe merchant standing on a SEA_PLACE (no real purse, holder or lock touched):
  - a lit day's coupon equals the dark day's to the coin, also with the profit limit binding (12,000 of 29,905);
  - the merchant is paid nothing hourly and holds no mark;
  - the player's 461,384 d. is paid 346 d. an hour for 24 hours, each hour once (every hour is run twice: the second pays 0);
  - 21 missed hours fold into the next day's pay-out (7,267 + 8,305 -> 649 an hour);
  - an arrival collects the rest once and later hours pay 0; old `accrued` 555 is never paid out hourly; a city that lost pays 0;
  - no hour wrote a city's purse or a flow.
- Proof 198, 10 markers: the REAL `tick_city` over the whole world for 24 hourly runs; the same day run dark (rolled back) and lit:
  the receipt's `coupons_paid`, the three cities' purses and the merchant's `accrued` are equal, and each player's `accrued` plus
  what she was paid is her dark `accrued`; a player with no fleet who bought through `public.invest_for` is paid by the tick.
- Proof 22 (0312's daily coupon) still 8/8 with 0495 applied, dark.
- `rollback-0495.sql` run locally: both bodies return to their md5 of before 0495.
- `tests/db.budget.spec.ts`, `tests/news.lint.spec.ts`, `npm run db:check-versions`, `tsc -b`.
- The proofs were run through `scripts/ops/harness/dividend-hourly/local.mjs`, which writes and prunes no shared snapshot.

## Not verified

- Production after this rebuild: the before-check was read for the first build (head, digests, the pairs); nothing lit.
- The two-session test below has NOT been run on this machine (no PostgreSQL, Docker or psql). Its scene SQL and its three hourly
  calls ran on the local PGlite world in one session (1,096 paid, 0 the same hour again, 1,096 the next hour); `bash -n` passes.
  Its first real run is the PR's `disposable-chain`.
- `public.tick_city` itself under two sessions (the test calls `public.city_coupon_hour`, the tick's own call).

## Two sessions, on real PostgreSQL (branch `dividend-race`, PR #861; rewritten 2026-11-25 for the rule above)

`scripts/ci/dividend-race.sh`, run by `disposable-chain` (migrations-apply-proof.yml) with psql sessions, only when
`public.city_coupon_hour` exists (else it prints SKIPPED). Two probe players at a SEA_PLACE, their rows marked as a lit day's
coupon marks them (8,305 d. at 346 an hour; 18,000 d. at 750). It needs no knob and no city purse. Three markers:

- `DIVIDEND_RACE_SKIPPED_HOLDER_OWED`: a second session holds player a's `players` row; the hour runs inside its 5 s lock limit
  while the row is still held, pays b alone, and leaves every figure of a's row as it was.
- `DIVIDEND_RACE_OWED_HOUR_PAID_ONCE`: the next hour, a free, pays her 346; the missed hour's coin is still set aside for her; an
  arrival (`collect_coupons`) then collects the rest, and she holds the whole 8,305 d., once.
- `DIVIDEND_RACE_SAME_HOUR_PAYS_ONCE`: a first caller runs the hour and keeps its transaction open; a second caller of the same
  hour does not wait and pays 0; after the commit a third pays 0; purses and ledger rows show one payment.

Each step waits for `pg_stat_activity` to show the other session where it must be: no timed sleeps. It commits, so it refuses any
database not on 127.0.0.1 / localhost and runs AFTER the snapshot is kept, on the stack the next step throws away.
