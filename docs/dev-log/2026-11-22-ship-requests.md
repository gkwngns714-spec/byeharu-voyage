# 2026-11-22: Requests a ship can carry (0466, dark)

Content plan item 4 (`docs/design/content-plan-2026-11.md` 5.2/5.3, default 5.6: beside the city-sized requests, not instead), P1 of
`docs/design/playable-2026-11-22.md`. Migration `20260818000466_requests_a_ship_can_carry.sql`, proof 169, harness
`scripts/ops/harness/ship-requests/`.

## The problem

A city's request (`trade_contracts`, 0087/0311) is sized by the city's budget: 31,367 units on average on production, standing for days. A new
ship carries 180 to 300 t. No company has ever delivered one.

## What 0466 does

Each harbour also keeps up to **two hold-sized jobs** (`trade_contracts.size = 'hold'`), beside its three city-sized requests (counted apart).
They use the request machinery as it is: the board (`world.contracts`), the tray and its dry run (`cmd.preview_fulfil`, `useFulfilPreview.ts`),
the delivery (`cmd.fulfil` / `cmd.run_fulfil`: the sale at the live bid, the fixed bonus out of the escrow, Reputation, Requests experience, the
book of deliveries), expiry and the money going home (`public.contracts_expire`), and the wind job that keeps every board full.

- **One writer:** `public.hold_request_post(port, now)`. Dark it returns 0 at once.
- **The good:** one the harbour does not sell (0087's rule), its culture takes, some other harbour sells, not already asked for there, and
  whose daily sale allowance at the harbour covers the whole lot (so a delivery is never cut).
- **The lot:** a weight drawn between 40 and 150 t, in units of the good's bulk, at most 250 units and at most 24,000 d. at its mid (a new
  company starts with 40,000); rounded down to 5s; under 10 units, nothing is posted.
- **The deadline:** 2 to 6 real hours (whole game days, at least one).
- **Who:** companies. Merchants never answer a hold job (`public.contract_asks` lists only the city's), and its deadline is under the 6 h
  before merchants may answer a city's request anyway.
- **The purse:** lit purses, the bonus budget leaves the city at posting (BOUNTY) and must be under the harbour's share of its surplus; what
  is not delivered goes home at expiry (BOUNTY_LAPSED). A row is deleted a real day after its deadline.
- **The screen:** a hold job's row says **Ship job / 배 의뢰** beside the good and **Pays {total} / 보수 {total}** where a city's request says its
  bonus and budget. `total` is served (units x (today's bid + the bonus)); the client adds nothing.

## The pay rule (decided by default)

**The bonus is 20 to 30 % of the good's mid at posting, a unit, on top of the live sale price.** The city's request pays 8 to 20 %. The higher
share pays for the small lot and the short deadline.

Measured on the chain's world (prices at design level, 0285), every one of the 254 harbours asked once, lit, purses dark (1.5 s for all 254,
about 6 ms a post; 238 posted, 16 drew a lot under 10 units):

| | 10th pct | median | 90th pct |
|---|---|---|---|
| units | 20 | 60 | 115 |
| tons | 13 | 52 | 115 |
| cost to buy at the cheapest seller | 1,386 | 9,095 | 18,002 |
| what the job pays (served `total`) | 2,967 | 23,583 | 28,500 |
| the bonus | 590 | 4,482 | 6,373 |
| plain trade's profit, same goods (bid there minus cheapest ask) | 381 | 3,456 | 11,636 |
| **the job's profit over the plain trade's** | **1.43x** | **1.77x** | 3.46x |
| bonus over the sale price | 22 % | 26 % | 31 % |

So a job pays clearly more than selling the same goods there plainly (median 1.77 times the profit), and at most about a third more per unit
than the plain sale, so it is not absurd. The 3.5x tail is goods whose plain margin is thin, which is the job's point: it sends a ship where the
best-sale card would not. In 7 of 238 the plain trade would lose (the bid there is under the cheapest ask); the bonus is what makes it pay.
Distance is not counted (the same for the job and the plain trade).

Proof 169's worked example at Lisbon: 70 coriander (42 t), bonus 19.27 a unit on a mid of 87.58 (22 %), pays 7,418 against a plain sale of 6,069.

## Dark is today

`hold_requests_enabled` is false. Dark, `hold_request_post` returns 0 having read only the switch; the read and the wind job call it and post
nothing; the board serves two more keys (`size: 'city'`, `total: null`) the client ignores for a city's request; every other figure is the
same. The self-assert reads one real harbour's board before and after the hunks and finds it the same, and the writer and the wind job post
nothing. Rows a minute dark: **0**.

## Lit: expected extra rows a minute

About 238 harbours x 2 jobs, a mean life of 4 h: about **2 posts a minute**, each a `trade_contracts` row and a `treasury_flows` BOUNTY row,
and as many expiries or deliveries (an UPDATE, a BOUNTY_LAPSED flow when not delivered, a DELETE a day later). **About +6 new rows a minute**,
plus about 2 updates and 2 deletes. The first fill runs at `hold_request_wind_posts` (3) a minute for about 3 hours (6 new rows a minute).
About 4,000 rows stand at once (one day's posts, kept a day). The wind job's extra work: one harbour pick and about 6 ms a post, inside its
existing `contract_wind_ms` (4,000 ms a minute).

**Production before (read 2026-11-22, `before-0466.sql`, head 0464):** 1,678 request rows, 744 open, a mean of 34,991 units an open request;
0 deliveries by a company in 48 h; the wind job's last hour 60 runs, a mean of 1,981 ms and a worst of 4,398 ms. The hold step runs in what is
left of the minute's `contract_wind_ms` after the city's top-up, so on a slow minute it posts nothing and the next minute catches up; it adds no
time over the budget. Every one of 0466's nine OLD hunk texts occurs once in production's bodies.

## To light it (the owner)

1. Read the gate (`scripts/ops/harness/db-health/gate.sql`).
2. `update public.world_config set value = 'true'::jsonb where key = 'hold_requests_enabled';`
3. 30 minutes later, `scripts/ops/harness/ship-requests/after-0466.sql`: `open_hold` rising by about 3 a minute toward about 476, `hold_posted`
   in `wind_1h` about 180, `failed` not rising, the wind's `max_ms` under its 4,000.

**Rollback:** set `hold_requests_enabled` false. Nothing new is posted; open jobs drain inside 6 h and their escrow goes home. A full rollback
is a new migration reversing the nine hunks (their old texts are in 0466), dropping the writer, the knobs and the column.

## Not done here (named)

- Regard with the harbour's country on a delivery (the plan's "plus regard"): not added; Reputation and Requests experience are paid as today.
- The Trade card marking a good some harbour in reach asks for: `world.board_sell`'s `request` and `world.watchlist`'s `wanted_at` already read
  every open request, so they show hold jobs too once lit; nothing new was drawn.
- A screen test of a lit board: the local world is dark too; the words and the served-total rule are `tests/requests.hold.spec.ts`.
