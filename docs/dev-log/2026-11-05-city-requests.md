# 2026-11-05: a request stands a day (migration 0311)

Owner, verbatim:
- "the request, for example cumana, soju, the +300 gold should be on top of the prices. for example soju sold at 1000 each would be 1300. get it?"
- "and it should show quantity, and time. time should be much longer..."
- "the bonus fee should be set, for example the 예산 is 1,000,000. if bonus of 1,000,000 is depleted, that request no longer stands"
- "and in report, or stats, bonus fees should also be monitored too"

## What changed for a player
- A request shows ONE price each: this harbour's live sale price plus the bonus, for example 1,300, with `market 1,000` small under it.
- It shows what is wanted (what the budget still pays for), what you hold, the bonus each, the budget left, and the time left as a live countdown.
- A request stands 24 hours, not 4 minutes.
- You can deliver part of it. Several houses can deliver to one request. It closes when the budget cannot pay one more unit's bonus.
- Report: `Bonus` is its own line under trade. Stats, world and each city: `Bonus, 24 h` with held now, budget set, paid out, returned. Money log: a Bonus filter.

## Measured on prod before building (read-only, 2026-11-05)
- Head 0309 at the start, 0310 before the PR. `game_day_seconds` 60, `contract_deadline_days` 4, `bounty_reserve_mult` 2, `treasury_reserve_floor` 50,000, purses lit, economy closed.
- **Nothing has ever been delivered:** 0 `PREMIUM` ledger rows.
- **The brief's 274 open rows are mostly not open:** 270 had passed their deadline at 69 harbours nobody had read since (the oldest from 2026-10-15), holding 6,558,792 d. They go back to their cities the next time each harbour is read. Really open: 4 rows at 1 harbour, 5,873 d. This stays as it was: a request is wound when its harbour is read.
- 32 open rows had no escrow (posted before 0122), all past their deadline. 0311 marks them expired; no money moves.
- Bounty load, last 24 h: 15 BOUNTY and 9 BOUNTY_LAPSED rows of 25,145 flows, at 2 harbours (Cumana 11, one other 4).
- **One draw costs about 1 s on prod** (60 draws, 59.5 s). The old wind could make 4 on one read, and did at every read of a poor city.
- Purses, 246 harbours: median balance 50,021 d., median surplus 48,243 d. (the order said about 15,000; the measured figure is about three times that). 24 harbours have no surplus. Positive surplus in all: 23.3 billion d.

## Decided by default (the owner may change any of these)
| Decision | Value | Why |
|---|---|---|
| Deadline | 1,440 game days = **24 real hours** | "much longer". Knob `contract_deadline_days`. |
| Open at a harbour | **3** | Knob `contract_open_max`. Replaces one a game day; `contract_posts_per_day` is removed. |
| Budget | **least(1,000,000, surplus / 6)** | Knob `contract_budget`. 6 is `bounty_reserve_mult` x `contract_open_max`, so a harbour's three requests together hold 42 % of its surplus at most. |
| Minimum | the bonus on the lot `contract_draw` names (10 to 30 units) | Below it nothing posts. It is 0122's gate kept. No new knob. |
| Bonus each | fixed at posting, paid as posted | The market may drift for 24 h; the bonus does not. The price each moves with the live sale price. |
| A delivery too big | **cut**, the rest stays aboard | Cut to the budget, and to today's sale allowance. No plain-price sale of the excess. |
| Bonus rounding | up to the ducat | The budget is whole ducats, so a whole delivery spends it exactly. A part is paid up to 1 d. more; never past the budget. |
| Status when spent | `spent` | Many houses can share a request, so `fulfilled_by` stays empty; the ledger and FULFILLED events say who. An odd coin left goes home as BOUNTY_LAPSED. |
| One authority | `premium_ducats` = budget left, `escrow` = the money for it | Lit, the same figure on every open row. Both fall together on each delivery. |
| Signature | `cmd.fulfil` unchanged | A delivery is what she holds; no quantity argument, no stepper. |

## Estimate, from a prod read
At the rule above, on 2026-11-05 purses:
- **Cities that could post:** 211 of 246 can fund a request at the sampled median lot (450 d.), 206 at the mean (1,184 d.), 196 at the 90th percentile (2,349 d.), 66 at the sampled largest (13,794 d.). 44 cities can fund the full 1,000,000 d. Sample: 3 draws at 20 harbours.
- **Size:** median first budget 8,040 d.; 90th percentile 1,000,000 d.
- **Gold held, upper bound:** **142.8 M d.** if every harbour were read and posted all three, 0.6 % of positive surplus. The order's 738 M (3 x 1 M x 246) cannot happen under the share rule.
- **Gold held, likely:** far less. A harbour posts only when read, and only 2 were read in the last 24 h.
- **Flow load:** at most 3 BOUNTY and 3 BOUNTY_LAPSED a harbour a day, plus an odd-coin row for a request spent; at most about 1,476 rows a day if every harbour were read, against 25,145 flows a day now. At today's reading, single figures.
- **A read:** at the cap, no draw. Under it, at most one, about 1 s. It was up to four.

Held gold lowers a purse, but stays above the reserve, because the budget comes only from surplus. Nothing is minted: BOUNTY out, PREMIUM or BOUNTY_LAPSED back, each through the existing `treasury_post` and `credit`.

## Open at deploy
Open rows keep their own `expires_day` and drain within 4 minutes. They take partial delivery under the new rule; a row's budget is its old lot premium. A harbour with 4 stale rows posts nothing until they expire, on the same wind.

## Proof
- `scripts/ops/harness/city-requests/proof-0311.mjs`, cached PGlite world, no from-zero replay: **27 mutations red for their reasons, the real file green, dark and on a lit, closed world** (the lit run caught a real blocker: a founding is refused on a closed economy, so the probe would have failed on prod). Self-assert takes 1.6 s here; on prod add about 8 draws.
- The self-assert reconciles to the ducat: BOUNTY set = PREMIUM paid + BOUNTY_LAPSED returned + escrow still held; and house + city + escrow does not move on a delivery.
- `tests/requests.design.spec.ts`: red on the old client (no price each), green at 1280, 390 and 320.

## Not proven here
- The money-log "ratio 1.0000" has no script of that name. What stands in for it is the reconcile above; the 30-minute after-check reads the world total on prod.
- The self-assert's probe runs on LIS on prod. Its purse row stays locked for the probe's few seconds; the deploy script's drain covers that.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
1. Head, and the six bodies the hunks were cut against:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(replace(pg_get_functiondef('public.tick_contracts(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) as tick_contracts,
  md5(replace(pg_get_functiondef('world.contracts(uuid)'::regprocedure), E'\r', '')) as contracts,
  md5(replace(pg_get_functiondef('cmd.run_fulfil(uuid,uuid)'::regprocedure), E'\r', '')) as run_fulfil,
  md5(replace(pg_get_functiondef('world.report(text)'::regprocedure), E'\r', '')) as report,
  md5(replace(pg_get_functiondef('world.stats_overview(integer,text)'::regprocedure), E'\r', '')) as stats_overview,
  md5(replace(pg_get_functiondef('world.stats_city(uuid,text)'::regprocedure), E'\r', '')) as stats_city
```
-> head `20260818000310`, `MD5_PLACEHOLDER`.

2. Every row the migration touches, and no live row that could pay from nothing:
```sql
select count(*) filter (where status = 'open' and escrow = 0) as zero_escrow_open,
       count(*) filter (where status = 'open' and escrow = 0 and expires_day > world.game_day(now())) as zero_escrow_live,
       count(*) filter (where status = 'open' and escrow <> premium_ducats and escrow <> 0) as other_mismatch,
       count(*) filter (where status = 'open' and floor(premium_ducats / premium_per_unit) < 1) as pays_nothing
  from public.trade_contracts
```
-> `zero_escrow_live`, `other_mismatch`, `pays_nothing` all 0.

3. The probe harbour draws (three draws, about 3 s):
```sql
select x.s, d.good_id is not null as draws, d.qty
  from public.ports p cross join generate_series(1, 3) x(s)
 cross join lateral public.contract_draw(p.id, world.game_day(now()), x.s) d
 where p.code = 'LIS'
```
-> three rows, `draws` true.

## After-check, 30 minutes (pure SELECTs, one statement per file)
Stamp the deploy time as T. The world total must not move, except by what the closed economy's own kinds move.

4. The knobs and the board:
```sql
select (select value from public.world_config where key = 'contract_deadline_days') as deadline,
       (select value from public.world_config where key = 'contract_open_max') as open_max,
       (select value from public.world_config where key = 'contract_budget') as budget,
       count(*) filter (where status = 'open') as open_rows,
       count(*) filter (where status = 'open' and expires_day > world.game_day(now()) + 4) as new_rows,
       count(*) filter (where status = 'spent') as spent,
       coalesce(sum(escrow) filter (where status = 'open'), 0) as held,
       coalesce(max(n.c), 0) as most_open_at_a_harbour
  from public.trade_contracts
  left join lateral (select count(*) c from public.trade_contracts t where t.port_id = trade_contracts.port_id and t.status = 'open' and t.expires_day > world.game_day(now())) n on true
```
-> 1440, 3, 1000000; `most_open_at_a_harbour` at most 3 (4 only for a stale board); `held` under 142.8 M.

5. Open rows are one figure, and the books reconcile (T as a timestamp):
```sql
select (select count(*) from public.trade_contracts where status = 'open' and escrow <> premium_ducats) as open_rows_two_figures,
       (select coalesce(sum(ducats), 0) from public.treasury_flows where kind = 'BOUNTY' and created_at > 'T') as set,
       (select coalesce(sum(ducats), 0) from public.treasury_flows where kind = 'BOUNTY_LAPSED' and created_at > 'T') as returned,
       (select coalesce(sum(ducats_delta), 0) from public.ledger where kind = 'PREMIUM' and created_at > 'T') as paid
```
-> `open_rows_two_figures` 0. `paid` and any `set` are real; no delivery may exceed its request's budget.

6. The world's money:
```sql
select (world.stats_now()) ->> 'total' as total, (world.stats_now()) -> 'drift' as drift, public.bonus_figures(null, now() - interval '30 minutes') as bonus
```
-> `drift` all zero; total as the closed economy leaves it. `world.stats_now` and `public.bonus_figures` are both stable (`s`).

## Forward rollback (a NEW migration, owner only)
Nothing here needs undoing to stop harm: setting `contract_open_max` to 0 stops all new posts at once, and open requests drain. To go back in full:
1. `contract_deadline_days` to 4, `contract_posts_per_day` back, `contract_open_max` and `contract_budget` removed.
2. The six bodies back to their pre-images (their digests are in PROD CHECK 1); `public.bonus_figures` and `ledger_premium_at` dropped.
3. Before that, return every open budget by expiring the rows through `tick_contracts`, so no escrow is stranded. The pre-0311 `cmd.run_fulfil` pays `premium_ducats` for `qty`, which is wrong on a part-spent row.
4. The client must be reverted with it: it reads `price_each`.
