# 2026-10-19 — Far selling: skill, not distance (`osn-far-selling`) — WIP, NOT a PR yet

The owner, 2026-10-19: *"you receive a lot of cash just by selling far away. but i want this to be slightly different.
it shouldn't be that easy, yet not too hard."* Approved: (1) far prices only as fresh as your last visit or a rumour,
(2) far markets fill up (strengthen the 0194 glut for far goods), (3) perishables spoil at sea, (4) danger = insurance /
pirates (not here). Target: a long route ≈ 1.3–1.5× a short route's profit PER DAY for a competent trader.

## Baseline (measured, head 0208, before any change)

Metric (decided by default): a competent trader — 450 t of cargo, 20 crew, 4.97 knots (the biggest real player fleets on
prod), capital not binding — buys a full hold at a maker (capped by stock and the daily cap) and sells it all at one
destination. Profit = proceeds − outlay − profit tax − running costs (wage + food + water, 1.115 🪙 a crew a sea-day) ×
sea-days. Per day = profit / (sea-days + 1 turnaround day). Per origin, the best route in each distance band; then the
median over origins. Origins: harbours ordered by md5(code || 'far0213').

- **Prod, read-only** (12 origins, `scripts/ops/harness/far/measure_prod_readonly.sql`, 2026-10-19 ~08:15 UTC):
  median best per day by band <1k / 1–2.5k / 2.5–5k / 5–8k / 8k+ nm = **208 / 240 / 1,566 / 5,309 / 146,922 🪙**.
  Long (5k+) ÷ short (<1k), median of per-origin ratios: **~208×**; 2.5–5k ÷ short 1.41×.
- **Local prod-shaped world** (prod's knobs, all 132,090 market rows' state, city purses laid over the head-0208 image;
  matches prod to a few %): 24 origins, short = best under 2,500 nm, long = best ≥ 5,000 nm:
  **short median 464 🪙/day, long median 171,357 🪙/day, median ratio 232×** (2.5–5k 1.62×, 5–8k 7.1×, 8k+ 232×).
  The haul (0173, halved by 0208) is ×300 at the far end; a full hold of paintings LAR→14,427 nm turns 183k into 50M.
  So the brief's "~3×" is ~200× in fact; the target needs the far premium cut ~99 % for a full hold.
- Running costs ÷5 (`osn-running-costs-d5`) is not on any branch yet; costs are linear in this metric (22 🪙/day of 20
  crew against 464+/day), so ÷5 moves short routes by <5 %: not yet measured as a merged world.

## Mechanism (2), prototyped (`scripts/ops/harness/far/proto0213.sql`, functional core only, no proofs)

- One glut column, two leaves: `world.glut_after` (the mark; used by `cmd.do_sell` AND step by step inside
  `world.quote_priced`'s sell walk) and `world.glut_faded` (the fade; used by `tick_market_drift` AND `price_path` —
  this also folds 0194's two copies of the fade formula). CHECK on `port_goods.glut` 0.5 → 0.9999.
- Lit (`far_glut_power` > 0): the FAR part of the mark, per_depth × gain × (haul^power − 1) × units / depth, is felt
  ton by ton inside the sale itself (a maker row, haul 1, is untouched in the walk, so short routes are protected);
  the cap lets a far glut strip the whole distance premium and up to `floor` of the market's own price
  (cap = 1 − (1 − floor) / haul); far rows fade slower (decay interpolated toward `far_glut_decay` by 1 − 1/haul).
  Dark (power 0): every expression equals 0194's exactly (to be self-asserted).
- Calibration sweep (local prod-shaped world, long ÷ short median of per-origin ratios):

  | power | gain | floor | ratio | 2.5–5k | 5–8k | 8k+ |
  |---|---|---|---|---|---|---|
  | dark | – | 0.3 | 232 | 1.62 | 7.1 | 232 |
  | 0.5 (walk on all rows) | 1 | 0.3 | 45 | 1.62 | 3.9 | 45 |
  | 1.0 (all rows) | 1 | 0.3 | 6.8 | 1.54 | 3.0 | 6.8 |
  | 1.5 (all rows) | 1 | 0.3 | 2.6 | 1.35 | 2.2 | 2.2 |
  | 1.5 (far only) | 1 | 0.3 | 3.7 | 1.45 | 2.7 | 2.4 |
  | 1.5 (far only) | 1 | 0.6 | 2.7 | 1.45 | 2.3 | 1.7 |
  | 1.0 (far only) | 10 | 0.6 | 1.9 | 0.5 | −0.1 | 1.9 |

  Findings: the walk on maker rows kills 6 of 21 origins' short routes (hence "far only"); a large gain over-punishes
  the 2.5–8k band (H 1.3–6) and goes negative; power 1.5 with floor ~0.6 gives ~1.7–2.7×. Not yet at 1.3–1.5.

## HAND-OFF (2026-10-19 ~08:30 UTC, owner moving PCs)

**Done:** baseline measured (prod read-only + local prod-shaped); mechanism (2) prototyped and swept; perishability
found to ALREADY exist as data (`goods.perishable_pct_day`, 0002, from `PERISH` in `scripts/lib/world-derive.mjs`,
shown in the Codex, never applied): 37 goods carry it, no wine, no fresh fish. Client map for (1) done (summary below).
**Nothing is a migration yet; no PR.** Harness: `scripts/ops/harness/far/` (`far.mjs` lays prod state over an image —
needs `q_state.sql` exported to `.farwork/prod-state.json` first, read-only; `measure.sql`; `sum.mjs`).

**Next steps, in order:**
1. Finish (2)'s calibration: try power 1.5–2, floor 0.6–0.7, decay; consider making the far rate scale with the haul's
   premium so 5–8k is not the best long band. Pick the setting that gives ~1.4×; keep one switch knob
   (`far_glut_power`, 0 = dark) and its tuning keys.
2. Write migration 0213 (slice A = mechanisms 2 + 3, dark): the prototype's hunks (quote_priced 4, do_sell 1,
   tick_market_drift 2, price_path 2) cut against prod bodies (verify md5 = head-0208 image), the two leaves, the CHECK,
   knobs, plus (3): `spoilage_scale` (0 = dark); at arrival in `voyage.settle` (hunk before "-- 0034 STANDING ORDER"),
   `public.spoil_cargo(fleet, voyage)`: lost = round(qty × (1 − (1 − rate × scale)^voyage.total_days)), through
   `fleet_unload`, one `SPOILED` event {fleet, to, days, goods[{code,name,lost,had}]}; client: `headline.ts` case +
   `LedgerScreen` FACE_OF 'voyage'. Extend PERISH (decided by default): fresh fish 0.005, table wines/beers/ciders
   0.002–0.003, palm wine/pulque/chicha/kvass 0.005, extra grains 0.002; spirits, fortified wines, tea, coffee, cacao,
   salt, honey keep 0 — and a migration row update + world-guard agreement. Self-asserts: dark = 0194 exactly on a
   sample (old tree in pg_temp), planted lit probe, a probe voyage spoils by the amount, timings ×8 in one session.
3. Slice B (`osn-far-selling-2`, 0214+): price knowledge. Server: a per-company seen table (port, good, mid, seen_at)
   written on dock/trade/market read at a docked port; far reads (`good_board`, `watchlist`, `price_why`,
   `price_outlook`/`price_path`, `world.market` of a non-docked port, `world.contracts`) serve seen/rumour prices with
   `seen {kind: live|seen|rumour, at}` — note good_board RANKS by live mid and must rank by the seen price too. Rumours
   decided by default: the Inn of the docked city reports the region's prices, noised ±10–20 %, aged. NPC merchants keep
   perfect information (recorded). Client: Terminal/WatchRow, GoodTicket (BestTrade, SellAt), GoodChart, WhyThisPrice,
   PlanBuilder, PortPrices; wording in `src/lib/format` ("last seen 3 days ago", "rumour"); tests listed by the client
   map (rpc.goodBoard, rpc.outlook, rpc.why, layout's 🪙 rule, desk.*).
4. Measure the lit/dark ratio again with each lit; dev-log; PR(s) with the baseline table above.
