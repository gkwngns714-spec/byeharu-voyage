# 2026-11-01 — 0292: the count's `period` is read over the count's real window

**Branch** `stats-period` · migration `20260818000292_the_period_is_the_whole_window.sql` (number = prod head + 1 AT DEPLOY; this file
assumes 0290 `stats-budget` and 0291 `port-goods-hot` are live first — it re-cuts `tick_stats`, whose pre-image is 0290's output, so
the migration is cut against the LIVE body at that time). Start the build only after 0290 is merged.

## 1. The defect — measured read-only on prod, 2026-11-01
Each `stats_world` row's `period` (→ `minted` / `removed` / `moved`, the Stats money log) is the per-kind DIFFERENCE between this
count's `recent` and the previous count's `recent`, where `recent` = the newest THREE game days of `treasury_daybook` + `treasury_flows`
(`tick_stats`: `d.game_day >= world.game_day(p_now) - 2` and `world.game_day(f.created_at) >= world.game_day(p_now) - 2`).
`game_day_seconds` is now **60** (the count runs every 15 minutes), so `recent` reaches back ~3 of the row's 15 minutes and two
consecutive recents never share a day: the difference is just the last 3 days. The window-based figures of the SAME row are right:

| row | bought (window) | period.BUY | ratio | sold (window) | period.SELL | ratio |
|---|---|---|---|---|---|---|
| 10-30 18:06 | 6,565,278 | 659,505 | 9.95 | 6,087,608 | −449,600 | 13.54 |
| 10-30 17:51 | 6,859,463 | 1,382,795 | 4.96 | 5,910,157 | −895,512 | 6.60 |
| 10-30 17:36 | 7,728,137 | 759,903 | 10.17 | 7,499,340 | −914,231 | 8.20 |
| 10-30 17:21 | 8,652,564 | 1,414,376 | 6.12 | 9,534,434 | −963,572 | 9.89 |
| 10-30 17:06 | 10,666,400 | 1,594,850 | 6.69 | 8,012,942 | −998,198 | 8.03 |
(5–13× under, and not constant — the ratio is "how many of the 15 minutes the last three game days happened to hold").
`world.stats_overview` serves the completed rows' `period` PLUS the minutes since the last count read over a real window, so the
money log mixes a 5–13× understated past with a correct tail.

## 2. The fix — one seam, one rule
- A new STABLE function `public.stats_recent(p_now timestamptz, p_since timestamptz) returns jsonb`: the `{game_day: {kind: ducats}}` map
  over the game days from `least(world.game_day(p_now) - 2, world.game_day(p_since))` to `world.game_day(p_now)` — i.e. EVERY game
  day since the previous count, and never fewer than the last three. It is the current inline query of `tick_stats`, moved verbatim
  apart from that lower bound (daybook half and flows half, the 0243 per-(day,kind) sum before the aggregate, `CARRIED` excluded).
- `tick_stats`: ONE hunk replaces the inline `select … into v_recent` with `v_recent := public.stats_recent(p_now, v_prev_at)`.
  `v_prev_at` is the window start AFTER 0290's cap (so a catch-up row reads at most `stats_max_window_minutes`). The `period` difference,
  `stats_window_founded`, `stats_sides` and every other line stay as they are.
- Consumers: `stats_world.recent` grows from ≤3 keys to ~16 (steady) — each key ≤ ~12 kinds, ~4 KB a row; only `tick_stats` reads it
  (grep to prove it; `world.stats_*` readers use `period`, not `recent`). No client change.

## 3. Proof
Self-assert on rolled-back probe rows dated 2004 (never a real day): plant `treasury_daybook` rows for 15 consecutive game days and a
previous `stats_world` row 15 minutes earlier whose `recent` holds the first day only; `stats_recent` returns all 15 days; the
`period` the hunked `tick_stats` writes equals the hand-computed sum of the 14 new days plus the difference on the shared day — NOT the
last three days. Keep the probe cheap (no full tick on prod volume if it is slow: test `stats_recent` and the difference arithmetic
through the seam). Function md5s elsewhere unmoved (0287's technique).

## 4. After-check (coordinator, read-only)
On the first 3 rows after the deploy: `bought / (period->>'BUY')` and `sold / −(period->>'SELL')` are stable and near each other
across rows (the variable 5–13× is gone); the row's `recent` has ≥ 15 keys; the count still finishes inside its budget (phases in
`stats_runs`). Old rows keep their understated `period` (history is not rewritten — say so in the dev-log).

## 5. Bookkeeping
Owner row 256/259 state; one line at the top of `docs/WORK_QUEUE.md`; PR title `MIGRATION — 0292: the period is the whole
window (deploy AFTER 0291)`; trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
