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
(filled after deploy)
