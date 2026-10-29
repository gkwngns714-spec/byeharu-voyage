# 2026-10-29 — The press lives in real time, and a lot moves a tenth (owner decision 2026-10-28, `osn-price-imp`, migration 0271)

> The owner, 2026-10-28: **"prices feel still"** for merchants, yet his own buys move prices too much —
> **"it should be the same"**.

Built in the worktree `~/dev/wt-osn-price-imp`, branch `osn-price-imp`, from `origin/main` (c998e4d, prod head 0269).
**Not merged, not deployed.** It deploys after 0270 (PR #384, a clear's re-plan), which changes none of the three
bodies cut here.

## The root (verified on prod, read-only, 2026-10-29 06:20 UTC — not re-derived)

- 138,990 `port_goods` rows; **14,211 carry any press**; avg |glut| **0.0087**; max **+0.0851**; min **-0.0478**;
  **5 rows over 5 %**; **none at the 0.30 cap**; 13,021 positive (sold into) vs 1,190 negative (bought out).
- Live knobs: `glut_per_depth` 0.30, `glut_max` 0.30, `glut_decay` 0.5, `time_compression` 960. A game day is
  **~90 real seconds**, so the old decay's "half-life of one game day" was a half-life of **~90 seconds**.
- `cmd.do_buy` and `cmd.do_sell` are the **only writers** of the press (`public.press_after`); their only live caller is
  `cmd.execute_order`, which `cmd.advance` calls for a player's order **and** a merchant's route order. One rule already.
- **So the fault is the constants and the decay, not a second rule.** The owner approved: step 0.30 → 0.10 (a whole
  lot of max stock moves ~10 %, the 30 % cap kept), and decay by **real** time with a half-life of **3 real hours**.

Re-confirmed from prod before writing the PR (read-only): head `20260818000269` (258 migrations),
`price_impact` and `economy_closed` both `true`, a press-writer set of **4** functions, and the three bodies' md5s
matching this worktree's chain exactly (see PROD CHECKS below).

## The design

| piece | what |
|---|---|
| `port_goods.glut_at` | `timestamptz NOT NULL DEFAULT now()`. THE ONE clock of a row's press — the instant it last moved. Added as a fast default (no table rewrite; `atthasmissing` asserted). Every live row is anchored at the migration's `now()` (decided by default). |
| `cmd.do_buy` (1 hunk) | the update that writes `glut` also writes `glut_at = now()` — the same transaction instant `updated_at` already carries. |
| `cmd.do_sell` (1 hunk) | the same. |
| `public.tick_market_drift` (2 hunks) | the restock update fades the press by **real time since `glut_at`**, and advances `glut_at` in the same update. The half-life is read once a harbour in 0247's materialised CTE, as `glut_decay` already is. |
| knobs | `glut_per_depth` 0.30 → **0.10**; NEW `glut_half_life_hours` = **3**; `glut_max` stays **0.30**; `glut_decay` stays **0.5** (its meaning is now "the fraction left after one half-life"). Notes updated (the registry reads true). |
| column comment | `port_goods.glut`'s comment said "faded each game day"; it now says the truth (signed press, real-time fade). `glut_at` has its own comment. |

**The exact decay expression** (owned by `public.tick_market_drift(p_now timestamptz, p_port uuid)`, inside its restock
`UPDATE ... FROM f`):

```
glut = round(pg.glut * power(f.glut_decay, extract(epoch from (p_now - pg.glut_at)) / 3600.0 / f.half_life), 4),
glut_at = p_now,
```

where `f.half_life = public.wc_num('glut_half_life_hours')` and `f.glut_decay = public.wc_num('glut_decay')`, both in the
materialised CTE (one read a harbour — the live body's 0247 shape; the brief's formula names `public.wc_num` directly,
and the CTE is that same reader, moved to where 0247 put it). `p_now` is the function's own clock, already used for
`updated_at`. The 4-place rounding is 0194's.

**Nothing else moves:** `public.press_after` (the rule), `world.quote_priced`, the ±0.30 cap, the press writers' set,
the client entry points (78), ACLs, volatility, definer and config flags. The outlook `public.price_path` still fades a
press by game-days (`1 - glut_decay`) — it is a forecast, not the market; it is deliberately untouched and its knob's
note now says so.

### Decided by default (the owner may reverse)

- **Every live row is anchored at the migration's `now()`.** A press that was fading under the old game-day rule gets a
  fresh 3-hour half-life at deploy. The alternative — each row's true last-press instant — was never recorded and does
  not exist.
- **`glut_at` is written by every trade even while `price_impact` is dark.** The design's words: "when they write glut
  they also write glut_at". Live, the flag is lit, so the press and the clock always move together.
- **No clamp on a negative elapsed** (the formula is exactly the owner's). A trade that commits between the drift
  job's start clock and its visit to that harbour can make the elapsed up to the run's length (~6-8 s) negative, which
  grows the press by < 0.05 % once; the next tick corrects it. Left as designed and recorded here.
- **`glut_max`'s note untouched** (still true); `world_config.updated_at` is set on the two rows this file edits.

## The proof (local, cached-prefix apply: 258 restored + 0271 applied, 259/259 self-assert receipts)

`node scripts/db/proof.mjs standing` → **PROOFS PASSED: 1 file(s), 5/5 PASS markers seen**
`node scripts/db/proof.mjs merchant` → **PROOFS PASSED: 1 file(s), 6/6 PASS markers seen**

The self-assert notice, verbatim:

```
0271 self-assert ok: THE PRESS LIVES IN REAL TIME, AND A LOT MOVES A TENTH. do_buy (1 hunk), do_sell (1) and tick_market_drift (2) re-cut, each hunk once and each body reversing to its pre-image; ACL / volatility / definer / config unmoved, the 16 functions they decide with unmoved, the 4 press writers (do_buy, do_sell, press_after, quote_priced) the same set, entry points and walls unmoved, every other knob and flag unchanged, the glut CHECK unchanged. port_goods.glut_at: NOT NULL DEFAULT now(), a fast default (atthasmissing), every live row at this migration's now(). THE RULE at per 0.10 / max 0.30: one full lot -0.10, three -0.30, a fourth stays; a sale +0.10 / +0.30. THE DECAY (rolled back): 0.4 at 0 h stays 0.4000, at 3 h 0.2000, 6 h 0.1000, 9 h 0.0500, a press of 0 stays 0 and its clock advances; OLD = NEW on the restock update with every press 0 (every column but glut_at) and on a house's buy 30 / sell 30 dark (answers, purse, cargo, rows, events, ledger); LIT: the buy wrote press 0.0470, the sale 0.0500, both press_after's, glut_at = the trade's instant. Nothing left behind.
```

What each probe did (all on planted rows, every probe a rolled-back sub-transaction):

- **(a) the hunks / catalog.** Each of the 4 hunk texts occurs once and reverses to its pre-image; ACL / volatility /
  definer / config unmoved; a digest of the 16 functions the three bodies decide with (`price_impact_lit`, `press_after`,
  `wc`, `wc_num`, `economy_closed`, `depth_stock`, `depth_target`, `depth_mult`, `restock_rate`, `works_factor`,
  `stock_after`, `world.quote`, `world.want_left`, `world.game_day`, `want_period`, `city_treasury_on`) unmoved; the
  press writers the same 4; entry points and the three walls unmoved; every other knob and flag unmoved; the glut CHECK
  unmoved.
- **(b) the column.** NOT NULL, default `now()`, added as a missing value (a fast default), and every live row's
  `glut_at` = the migration's `now()`.
- **(c) the rule at the new step.** `press_after(0, 1000, 1000, 'buy', 0.10, 0.30)` = **-0.10**; three full lots reach
  **-0.30**; a fourth stays -0.30; a sale the same the other way (+0.10 / +0.30, capped).
- **(d) the decay on five planted rows** at 0 / 3 / 6 / 9 real hours: 0.4 → **0.4000 / 0.2000 / 0.1000 / 0.0500**;
  a press of 0 stays 0 and its `glut_at` still advances to the tick's clock.
- **(e1) the restock update OLD vs NEW** with every press 0 on the five probe rows: every column but `glut_at` digests
  identically; the old body advances 0 clocks, the new 5.
- **(e2) a house's buy 30 then sell 30 OLD vs NEW (dark, flags forced):** the receipts, purse, cargo, row (minus
  `glut_at`), BOUGHT/SOLD payloads, BUY/SELL ledger rows and `trade_daily` are identical; the old body leaves the
  planted clock (2020-01-01), the new body writes `now()` on both trades.
- **(e3) the same trades LIT (rolled back):** the buy wrote **0.0470** = `press_after(0.05, 30, 1000, 'buy', 0.10, 0.30)`;
  the sale wrote **0.0500** = `press_after(0.0470, 30, 1000, 'sell', ...)`; both clocks = the trade's instant.
- **Positive control:** changing the one-lot expectation from `-0.10` to `-0.11` made the chain fail with
  `0271 self-assert FAIL: one full lot moves the press by -0.1000, not -0.10`; the file was restored (its SQL
  unchanged — the only later edit is the supersede declaration in the header, which changes no statement).
- **The header declares the supersede** (what this file re-cuts, why, and that there is no optional input to be a
  no-op without: the file creates its column and knob, or refuses). `tests/duplication.spec.ts` — all 10 tests,
  including "a migration that re-cuts an existing function declares the supersede in its header" — pass.

## PROD CHECKS (read-only, run before opening the PR)

1. **The live bodies are the ones the hunks were cut against — md5, prod = this worktree's 258-file chain:**

   | body | md5 |
   |---|---|
   | `cmd.do_buy(uuid,jsonb)` | `d3f6b4bea4ec43797f69774b2a7b0e4f` |
   | `cmd.do_sell(uuid,jsonb)` | `bf2851cfc27e3919f38f1fa20e11d173` |
   | `public.tick_market_drift(timestamptz,uuid)` | `1ae155de1806064d3c23c5f452cc7c8a` |

2. **Hunk occurrences (LF, prod):** do_buy 1 → **1**; do_sell 1 → **1**; tick_market_drift 1 → **1**, 2 → **1**.
3. `glut_at` column absent; `glut_half_life_hours` absent; probe house `Casa do Relógio 0271` absent;
   `client_write_grants` 0, `client_executable_writers` 0, `caller_evaluated_functions` 0; 78 entry points;
   `price_impact` true, `economy_closed` true, `glut_per_depth` 0.30, `glut_max` 0.30, `glut_decay` 0.5,
   `time_compression` 960; prod head **0269**.

**After deploy** (the 30-minute window):

- **The clock and the knobs** (immediately):
  `select count(*) from public.port_goods where glut_at is null;` → **0**;
  `select key, value from public.world_config where key in ('glut_per_depth','glut_half_life_hours','glut_max','glut_decay');`
  → **0.10 / 3 / 0.30 / 0.5**.
- **The press distribution at +10, +20, +30 minutes** (read-only):
  ```sql
  select count(*) as rows,
         count(*) filter (where glut <> 0) as pressed,
         count(*) filter (where glut > 0) as sold_into,
         count(*) filter (where glut < 0) as bought_out,
         round(avg(abs(glut)), 4) as avg_abs,
         max(glut) as max_pos, min(glut) as min_neg,
         count(*) filter (where abs(glut) >= 0.05) as at_5pct,
         count(*) filter (where abs(glut) >= 0.30) as at_cap
    from public.port_goods;
  ```
  **Before:** 14,211 pressed; 13,021 positive / 1,190 negative; avg |0.0087|; max +0.0851; min -0.0478; 5 at ≥ 5 %;
  0 at the cap. **A pass at +30 min:** every row has a clock; presses have not frozen (the same 14 k and no more) and
  have not run away (no row at 0.30, avg |press| well under 0.05, the 5 %-and-over count no longer a handful). **A
  rollback (report to the owner, who owns the knobs):** rows at the cap, or avg |press| many times the before.
  The immediate lever is `glut_per_depth` back to 0.30 (owner only); the structural rollback is a forward migration
  restoring the four old hunks.
- **The beats.** The drift job runs every 10 minutes (`byeharu-voyage:drift`, all harbours at one clock):
  `select jobname, start_time, round(extract(epoch from end_time - start_time)::numeric, 2) as s, status from cron.job_run_details where jobname = 'byeharu-voyage:drift' and start_time >= now() - interval '60 minutes' order by start_time desc;`
  → its duration should stay at the usual **6-8 s** (one `extract` + one division more a row than before). The next
  **:07** reconcile: the per-minute beat figures from `arrivals_beats` (0269 keeps the :06:30-:09:00 beats in
  `arrivals_beats_kept`) — pass if no new errors and the :07 minute sits inside the last hour's range (the recent
  baseline: beats p95 ~0.7-1.7 s, max ~2-3 s outside the reconcile; the :07 lap-start lag is the open issue of 0270,
  not this slice).

## What is NOT proven

- **Nothing about live price feel.** The probes prove the arithmetic, the one-rule path and the re-cut; whether prices
  now "feel" equally alive for merchants and for the owner is the 30-minute after-check above and the owner's own play.
  The local world's flags are dark; prod is lit, so the probes forced the flags to test both sides rather than measure
  the live mix.
- **The distribution this produces on prod is not predicted here.** The probe row is one Lisbon good; the live mix of
  stock depths, lot sizes and trade frequency decides the press distribution, and that is what the after-check reads.
- **The decay's many-tick product.** The probes are single ticks at 0/3/6/9 h; live it compounds every game day (~90 s)
  with a 4-place rounding each time. The error is bounded (~1e-4 a step) but not measured.
- **The negative-elapsed race** (a trade during a drift run, up to ~6-8 s) is reasoned, not reproduced.
- **No local timing of the drift job** was taken (a second heavy chain was avoided): the added per-row arithmetic is one
  `extract` and one division on top of the `power` the update already ran; the live duration above is the measurement.
- **The outlook (`price_path`) is unchanged** and still fades by game-days, so the chart's forecast of a press is now
  more pessimistic than the market itself. Stated, not fixed, in this slice.
