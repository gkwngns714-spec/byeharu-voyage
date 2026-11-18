# 2026-11-18: the Invest tray says what a share pays (0456, fault 2 of `2026-11-18-play-faults.md`)

The Town Hall's Invest tray showed the share count and the cost, and nothing of what the shares give back. Now it shows one more row,
**Daily pay / 하루 배당**, "≤ +N", where N is served by the server.

## What the code says (read from the chain's own world, PGlite, at 0454)

- **The pay.** `public.city_coupons` (0312, re-timed by 0413) computed each holder's due inline:
  `round(s.paid * v_rate * <real days since the row's stamp, at most the days since the city's last coupon> * public.influence_coupon_mult(port, holder))`,
  with `v_rate = works_coupon_day` (0.018 in the local world).
- **"Up to" is true.** Once a real day the city pays `least(sum of dues, city_surplus, its profit since the last coupon)`, split pro rata. The
  shortfall is not owed. A first day pays only for the part of the day the stake has been held.
- **The buy.** `public.invest_for` (live body: 0123, cut by 0313, 0319, 0411 and 0417) answered port, kind, shares, price, cost, completed,
  level, subscribed and purse. `cmd.invest` returns it as it is, and `cmd.preview_invest` returns it as `estimate`.
- **No proposed hunk existed on disk.** The play-faults log points to "the hand-off below", but it has no such section. The hunks here were
  written against the live bodies as dumped from the chain.

## What changed

**Migration 0456** (`supabase/migrations/20260818000456_the_invest_tray_says_what_a_share_pays.sql`). One authority: the rule was inline in
`city_coupons`, so it was moved into one small function that both callers use, not copied.
- NEW `public.coupon_day_of(port, player, paid)`: `paid × works_coupon_day × influence_coupon_mult`. It is SQL, stable, server only.
- `public.city_coupons`, 2 hunks:
  - the due is now `round(coupon_day_of(...) × the real days)`;
  - its `v_rate` is removed.
  - Numeric multiplication is exact, so the due is the same figure to the coin. The self-assert checks this against 0413's inline formula,
    and proof 22 (all 8 markers) is unchanged.
- `public.invest_for`, 1 hunk: the answer gains `coupon_day = round(coupon_day_of(port, buyer, cost))`. This is what the buy adds to the daily
  coupon, because the due is linear in what was paid.

**Client.**
- `InvestReceipt.coupon_day`.
- `InvestTray` (`src/live/CityTownHall.tsx`) has the row `townhall-invest-daily`, which shows `≤ {formatDucatsDelta}`.
- The words are `town.dailyPay` ("Daily pay" / "하루 배당").
- Decided by default: the Cost row and the Daily pay row both stay in place and show "—" while the dry run of a new count is asked. Before
  this, the Cost row disappeared and came back on each press, which re-flowed the tray.

## Measured

- **0456 self-assert** (local chain): `Probe: LIS docks x5 for 5000: coupon_day 90; Lisbon's coupon due 90 (the inline formula 90), paid 0 (surplus 5000, profit 0), the probe credited 0. 132 ms.`
- **Proof 159**, 4/4 PASS:
  - 10 shares of Lisbon's docks for 10,000: the holder of the city is quoted 270. With influence dark the same buy is quoted 180.
  - The dry run and the buy give the same figure.
  - A real day later, with room to pay, her row was credited 270.
  - With a profit of 1, the city paid 1 and her row was credited 1 of the 270 quoted.
- **The tray** (headless, local build, the lit fixture, 2 shares for 20,972): "Daily pay ≤ +566", which is 20,972 × 0.018 × 1.5. At 390 px and at
  1280 px a press leaves both rows where they were, and nothing scrolls sideways.

## PROD CHECKS (read only; the lead runs them)

- `scripts/ops/harness/invest-return/before.sql`. Expected:
  - hunk occurrences `{1,1}` (city_coupons) and `{1}` (invest_for);
  - `new_name_free` true, `probe_needs_there` true;
  - md5 (CR stripped) at 0454: city_coupons `34651f46407d868a4d478655d76440e9`, invest_for `e8533d8d890acf45ed2886c343562e60`.
- `scripts/ops/harness/invest-return/after.sql`. Expected:
  - head 0456 (or as renumbered);
  - `coupon_day_of_present` true, `client_can_run` false, volatility `s`;
  - city_coupons `2ae682d14f8a513b5246f9651ff649c2`, invest_for `859292a6c5b4baee71ed3eeb96919251`;
  - `coupons_reads_rate` false, `invest_serves_coupon` true.

## Checks (each once)

- `tsc -b` clean.
- eslint on the 4 changed TS files clean.
- `vite build` ok.
- `proof.mjs 159_` 4/4.
- `proof.mjs 22_dividends` 8/8.
- `map.townhall.spec.ts -g 0456`: 2/2 (390, 1280). The first run was red because the spec asked for 10 shares the new company could not pay
  for (the tray showed the refusal). The spec now steps down to 3; the tray was right.
- `i18n.keys` + `i18n.ko`: 4 passed, 2 skipped.
- `rpc.surface` pins only the names (`cmdPreviewInvest`, `cmdInvest`), which are unchanged, so it was not run.

## Not done / seen

- The figure depends on the holder's multiplier **today**. If the city changes hands, the coupon changes with it.
- At 1280 px the Lisbon city panel's tab grid sits over the "Mayor" and "Your tax" lines (seen in the spec's screenshot). This is older than
  this change and was not looked into.
