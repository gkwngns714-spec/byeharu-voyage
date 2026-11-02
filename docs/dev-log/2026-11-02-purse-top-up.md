# 2026-11-02 - City purses x100, capitals x500 (migration 0302)

Owner order: enlarge every city purse 100-fold, the 23 nation capitals 500-fold, no famous-city tier.

## What was built
- New flow kind `OWNER_GRANT`, registered `minted` ("New money: owner grant", ord 8): Stats shows it as new money.
- ONE exception in `public.mint_guard`: `OWNER_GRANT` passes only while the transaction-local setting `byeharu.owner_grant = 'on'`. Only 0302 sets it, around its own loop, and puts it back to `off`.
- Top-up: per harbour, `public.treasury_post(port, 'OWNER_GRANT', (m-1) * treasury_balance(port))`, balance read at run time, m = 500 for capitals, 100 otherwise. `treasury_flows` locked exclusive for the block.
- Not touched: the stamp `economy_closed_total`, any knob, cron job, switch, any other function.

## Self-assert (in the migration)
Every purse = old x m; purse = rolled + flows; rolled = daybook; OWNER_GRANT flows exact; live Stats "cities" figure moved by exactly the grant; guard controls in a rolled-back closed+lit probe (OWNER_GRANT refused without setting, every other minted kind refused with it, OWNER_GRANT passes with it); all other functions, world_config, cron jobs unchanged.

## Local proof
Chain to 0301 (cached prefix), run 0302: fresh dark world passes; populated world with economy closed and purses lit (246 harbours, random purses): total 1,180,729,900 = expected sum of old x m.

## Prod numbers
Deployed with ~/bin/bv-deploy.sh 468 (PR #468, merge d6be60b); prod head 20260818000302. The grant ran 2026-11-02 05:23:49 UTC.

| | harbours | live purse total |
|---|---|---|
| Before (read-only, minutes earlier, purses drift every second) | 246 (23 capitals) | 192,122,298 (capitals 8,970,721) |
| Old balances AT RUN TIME, recovered from the grant flows | 246 | non-capitals 189,391,212 + capitals 12,705,411 = 202,096,623 |
| Expected after, at the moment of the grant | | 189,391,212 x 100 + 12,705,411 x 500 = 25,291,826,700 |

- 238 OWNER_GRANT flows (the other 8 harbours were at 0), sum 25,089,730,077 d. = 99 x non-capital old + 499 x capital old: 215 non-capital flows divisible by 99, 23 capital flows divisible by 499, old sums as above.
- The migration's own self-assert (every purse = old x multiplier, purse = rolled + flows, guard controls) passed on prod, or the push would have rolled back.
- Purses move with play every second, so the total read minutes later (25,273,361,936 at 05:27, 25,154,318,716 at 05:39) is lower than the grant-moment figure: that is trade, not a defect.
- Books after: tick_city (05:37) rolled it: treasury_daybook OWNER_GRANT = 25,089,730,077; Stats live cities figure equals the actual purse sum (25,154,318,716 at 05:39). The stamp economy_closed_total was not touched.
- cron.job_run_details since the deploy: byeharu-voyage:stats 05:36, 05:51, 06:06 succeeded; byeharu-voyage:city 05:37 succeeded; byeharu-voyage:reconcile 06:07 succeeded. All 12 jobs active.

Choice made: "old" is the live balance (treasury_balance = rolled + unrolled flows), not port_treasury.ducats alone, because that is the purse the game pays against.
