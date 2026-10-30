# 2026-10-30 — The market ticks every minute, with no cap on price swings (owner decision, knobs + cron, no migration)

> The owner, 2026-10-29/30: **"the market price is not changing as fast it needs to"** →
> **"every hour is not good. every minute - change"** → **"set no limit to price swings. but rather,
> change the tick time of whole economy, market related areas"**.

Live `world_config` + cron changes, not a migration (migrations 0273–0276 are queued and un-deployed;
this is a reversible owner-directed knob move).

## What moved (prod, applied directly)

| knob / job | before | after | meaning |
|---|---|---|---|
| `drift_slot_seconds` | 900 | **60** | the drift noise steps every minute (was every 10 min) |
| `drift_theta` | 0.90 | **0.993** | slow mean-reversion — drift accumulates into wide swings |
| `drift_sigma` | 0.02 | **0.03** | bigger per-step swing |
| `drift_clamp` | 0.20 | **10.0** | no effective limit on how far a price can swing |
| `game_day_seconds` | 2880 | **60** | the CALENDAR/economy clock: one game-day = 1 minute (was 48 min) |
| `byeharu-voyage:drift` cron | `*/10 * * * *` | **`* * * * *`** | the job runs every minute |

`game_day_seconds` is the master clock of the market (0005/0028). Cutting it 2880 → 60 makes EVERY
game-day-keyed mover tick every minute at once: stock regeneration (the `(target/stock)^0.5` price
term), press fade application, seasons/fairs, daily caps and merchant lap pacing. The voyage clock
(`time_compression` 960, a voyage-day = 90 s) is deliberately untouched — sailing stays as-is.

## Verified on prod (read-only, the real target)

- Knobs read back: `drift_clamp` 10, `drift_sigma` 0.03, `drift_slot_seconds` 60, `drift_theta` 0.993,
  `game_day_seconds` 60.
- `cron.job` for `byeharu-voyage:drift`: `schedule = '* * * * *'`, `active = true`; runs landing every
  minute, all `succeeded` (durations ~4–8 s).
- Stock regeneration is now keyed to the minute: `floor(epoch/60)` = `max(last_regen_day)` =
  29888652 (the regen ran at the current minute). A one-time side effect of the clock jump: all stock
  snapped toward `stock_target` on the first tick under the new clock (the closed-form regen over
  ~28.7 M "days"), which is the intended "everything now moves from a clean target" reset, not a bug.

## Rollback (report to the owner, who owns the knobs)

```
update world_config set value = to_jsonb(2880), updated_at = now() where key = 'game_day_seconds';
update world_config set value = to_jsonb(0.2),  updated_at = now() where key = 'drift_clamp';
update world_config set value = to_jsonb(0.02), updated_at = now() where key = 'drift_sigma';
update world_config set value = to_jsonb(0.90), updated_at = now() where key = 'drift_theta';
update world_config set value = to_jsonb(900),  updated_at = now() where key = 'drift_slot_seconds';
select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:drift'), schedule := '*/10 * * * *');
```

## The 30-minute after-check (measured, 2026-10-30 ~00:35 UTC — PASS)

Read-only on prod at the window's end: the per-minute job keeps succeeding with no error and no duration
blowup, prices are visibly moving, and nothing has run away.

- Drift job: **39 succeeded, 0 failed** over the last hour, mean **13.11 s** a run, last at 00:35 UTC.
  13 s is doing drift **and** the stock regen on all 138,990 rows every minute — under a quarter of the
  minute, no blowup.
- Prices moving: **138,952 of 138,990** rows carry a drift now; the spread is **−0.5819 … +0.6249** — the
  wide, uncapped swing the owner asked for ("set no limit to price swings"), not the old ±0.20.
- Knobs read back as set: `game_day_seconds` 60, `drift_clamp` 10.0, `drift_sigma` 0.03, `drift_theta`
  0.993, `drift_slot_seconds` 60.

Verdict: PASS. The one thing worth the owner's eye is that the drift now wanders ±0.6 (a 1.6× price
factor), which is exactly what "no cap" produces with `theta 0.993` and a per-minute step; if it feels
too wild, the owner-only levers are `drift_sigma`/`drift_theta`/`drift_clamp` (the rollback SQL above
restores the old tight band). No action taken — the knobs are the owner's.
