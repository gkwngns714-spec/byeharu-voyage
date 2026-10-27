# 2026-10-27 — The game-day's drift run took 65-95 s (`osn-drift-slow`, migration 0247)

## The finding (prod, read-only)

`byeharu-voyage:drift` (jobid 2, `call public.tick_market_drift_each_port()`, `*/10`), 48 h of
`cron.job_run_details`: 288 runs, all succeeded. Every run is 1-7 s **except one run every 48 minutes**:
the first run after a game-day boundary (`game_day_seconds` = 2880). Those runs fell 40 or 50 minutes apart
(07:20, 08:00, 08:50, 09:40, …), on every minute of the hour and every hour alike.

| window | the game-day's run |
|---|---|
| 10-25 07:20 → 10-26 12:00 UTC | 30-50 s |
| 10-26 12:50 UTC on (0245 merged 12:40) | 64-95 s (max 95.3 s, 10-27 04:00) |

`pg_stat_statements` (since 10-20): the CALL, 996 calls, mean 9.3 s, max 95.3 s. No run overlapped the next
(95 s < 600 s), so neither pg_cron overlap nor a neighbour job (arrivals every 1 s, snapshot at the same
second, stats) explains it: the slow runs track the game-day, nothing else.

## The cause

On a new game-day `public.tick_market_drift`'s §G.2 regen update writes every one of the 138,990 `port_goods`
rows (~535 a harbour, 260 harbours). Per row it calls `restock_rate(port)` (→ `restock_lit` → `wc`,
`economy_closed`, a `port_treasury` read, `wc_num`), `works_factor(port, …)` (→ `city_level` ×2, `wc_num`) and
`wc_num('glut_decay')`. All are `SECURITY DEFINER` + `SET search_path`, so none is inlined: a full call with a
GUC save/restore each, ~1.7 M calls a game-day. Every value depends only on the harbour. 0245 swapped a
once-per-call variable (`v_rate`) for the per-row `restock_rate` and doubled the run (38 → 68 s). The drift
step over the same rows, with no such calls, costs 1-4 s.

## The fix (0247)

One hunk: the three readers move into a `MATERIALIZED` CTE over `public.ports` (the one harbour asked for, or
all), joined by `port_id`. Same readers, same statement, same snapshot, same arguments → the same numbers.
`MATERIALIZED` because an inlined CTE is pulled up and its calls go back into the row loop. Nothing else moves:
not the drift step, the procedure, the schedule, any knob.

Self-assert: the hunk reverses to the pre-image (ACL / volatility / definer / config unmoved); the old body
(kept as a pg_temp copy) and the new run on the same probe harbours (Funchal, a treasury harbour, the highest
production-works harbour) from the same rolled-back state — three game-days behind, 40 % stocked, glut 0.3,
production 2.5, works level 3 — and must write a byte-identical digest of every row and return the same jsonb.

## Measurements

Local (PGlite, cached prefix p0235 + 0247, 138,990 rows / 246 harbours; plans and per-call costs differ from prod):
- 0247 self-assert ok in 9.6 s apply: 2 probe harbours, 565 rows each, all restocked and faded, works 1.30, old and new
  digests identical; old 85 / 61 ms, new 22 / 17 ms a harbour.
- Whole market, one game-day behind, harbour by harbour (the procedure's loop), rolled back: old body 10.4 / 11.0 s,
  new 3.8 / 3.7 s.

Prod before (48 h to 10-27 06:30 UTC): game-day runs 64-95 s since 0245; other runs 1-7 s.
