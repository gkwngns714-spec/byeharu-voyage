# 2026-10-28: each company acts in her own transaction (`osn-company-steps`, migration 0267)

Symptom: in the hourly reconcile minute (:07) merchant lap-start lag spikes (06:07 p95 21.1 s, 11 due left; 05:07 p95 11.1 s; other minutes ~5.5 s), and the beat's worst case in that minute reaches ~8-10 s.

## The root cause, measured (prod, read-only, head 0266, 10-28 02:07-06:23 UTC)

- **Lap starts** (`lap_start_runs`): at 05:07 and 06:07 one open step (`lap_start_open`, under the quay) took **5.8 / 7.3 s** (`open_ms_max`); 10 opens waited their full 1.5 s for a beat gap (`late` 10). 06:08 carried the leftovers (p95 23.7 s, max 24.4 s).
- **Beats** (`arrivals_beats.splits.q`): at **06:07:30.001 a beat waited 8,838 ms for the quay**, then ran 102 fleets due at once (3.5 s). At 05:07:32 a beat waited 8,023 ms. No other beat in :07-:08 over the last 6 h waited more than 1.5 s.
- **The holder** (`reconcile_runs.receipt.ms`): the companies' step, ONE transaction under `hold_the_quay()`: 5,881 / 8,097 / 5,728 / 8,553 / **8,898 ms** (02:07 … 06:07). It starts right after the tend phase (06:07:00 + 29.8 s): the beat at :30 waited until :39.
- Inside it: `npc_tend_houses` = `npc_invest` over its roster (501 companies above 2× capital; 5 invested + 52 donated at 06:07), `capital_gift_pass` (its roster prices all 821 merchants' worth), then every company's purse check (821 ledger sums, ~2.8 ms each per `pg_stat_user_functions` = ~2.3 s). All under the quay, though only the acts write.
- **Not the cause:** the tend steps hold the quay a merchant at a time (longest beat wait in that phase 1.2 s). The compactor's :07 sweep is off the quay (0265; SKIP LOCKED, no lap start `busy`). The E5/E5b city tick runs at :37, not :07. The 06:07-vs-05:07 doubling is the same ~9 s hold landing on more due laps (24 started + 11 left), not a new holder.

## The fix (0267)

- `npc_invest` and `capital_gift_pass` are cut at the company, rules verbatim: `npc_invest_roster(p_only)` / `capital_gift_roster(p_now, p_only)` (the roster queries, plain stable reads) and `npc_invest_one(p_now, h)` / `capital_gift_one(p_now, h)` (the loop bodies; she is re-read through the roster narrowed to her). The two passes become roster → body in one transaction. `npc_tend_houses`, `npc_tend`, `player_gift` and every callee unmoved (md5).
- `tick_reconcile`'s companies' step: the rosters are read outside the quay, then **each company in her own transaction**: quay, the step's scope (same budget, from the step's start), her turn, HER purse checked, commit. The 821-company check leaves the step (each act checks the purse it moved; the whole-world check after is unchanged).
- New receipt: `reconcile_runs.receipt.quay = {tend, companies}`, each `{n, held_ms, hold_max_ms, wait_ms, wait_max_ms}` (`quay_tally`).

**Byte-identical.** Probe in the migration, on the world it is applied to (prod's live companies at deploy), from the same state, rolled back: the OLD `npc_tend_houses` + every purse (run before anything is replaced), the NEW `npc_tend_houses`, and the step as `tick_reconcile` now walks it, a company at a time. Digest: every company's purse, version and invested_at; city_shares, city_works, port_influence, port_fee_debts; the step's new ledger, events, treasury_flows and capital_gifts rows (generated ids excluded). Same rows, same answer.

**No deadlock.** Each company's transaction takes the quay first, then exactly the locks the old step took for her, in the same order (the same callees; the calls set is asserted equal to the old one). At any wait it holds a subset of what the old step held at that point and waits for the same lock, so the wait-for graph is a subgraph of the old one. The rosters take no lock (asserted: stable, no lock clause, no advisory lock, no writes). The set of functions that take the quay is unchanged (asserted).

## Local (PGlite, cached chain → 0266, merchants lit, city treasury + influence + closed economy lit, every 3rd house +3× capital, every 7th broke)

- 0267 applied in 2.9 s, **self-assert ok: 323 companies probed (273 invested, 16 donated, 43 gifts), 332 ledger / 339 events / 332 flows / 43 gifts rows, identical three ways.**
- `tick_reconcile(false)`: companies phase 2,038 ms over **323 transactions, longest 15 ms**; tend 837 transactions, longest 97 ms.

## Deployed (0267)

2026-10-28 ~07:03 UTC: PR #380, CI all green, `bv-deploy.sh`: push landed at head 0267 (the self-assert probe ran on prod's live companies and passed), clock back (11 jobs), merged 4018c78, main Acceptance green.

## After-check (prod, read-only; 07:07 and 08:07 measured, 09:07 and later NOT measured)

| :07 window | companies step | quay hold, companies (longest one) | beat in :07, p95 / max / longest quay wait | lap-start lag in :07, p95 / max | longest lap open |
|---|---|---|---|---|---|
| 05:07 (before) | 8,553 ms, 1 txn | ~8.5 s | 7.6 s / 8.3 s / 8.0 s | 11.1 / 12.0 s | 5.8 s |
| 06:07 (before) | 8,898 ms, 1 txn | ~8.9 s | p95 1.7 s / 10.0 s / 8.8 s | 21.1 / 21.8 s | 7.3 s |
| 07:07 (0267) | 10,811 ms, 517 txns | **48.9 ms** | 0.95 s / 1.12 s / 0.93 s | 24.3 / 26.1 s (deploy backlog, see below) | 1.2 s |
| 08:07 (0267) | 9,519 ms, 513 txns | **38.0 ms** | 1.21 s / 2.00 s / 1.09 s | 13.9 / 14.6 s | 1.3 s |

- Tend step (unchanged), from the new tally: 836-837 txns, longest hold 1.17-1.21 s, longest wait 1.37-1.50 s.
- **The companies' hold is gone**: the beats during the companies phase (08:07:31-:41) waited at most 15 ms; the 8-9 s beat stall is gone. 0 beat errors, 0 failed companies, 0 lap starts failed / busy.
- **07:07 lag is not clean**: the deploy stopped the clock ~07:03-07:05, so 07:05-07:06 drained rests that ran out meanwhile (lag up to 126 s) and 07:07 still carried that queue.
- **08:07 lag is still above the ~5.5 s of other minutes, at a NEW place in the minute.** Before, the early laps of :07 were fine and the spike came at the companies' hold (~:30). At 08:07 the laps after :16 are all <= 1.7 s, but the first 15 (08:07:00-:15) lag 7-14.6 s: one lap every ~1-3 s while the tend phase starts (beats 0.9-2.0 s, quay waits up to 1.09 s, 4 opens waited the full 1.5 s for a gap, plan max 2.6 s), beside the compactor's :07 sweep (08:07:00-:08.5) and the stats job (08:06:00-08:07:29). One sample: the cause is NOT yet proven. Next: measure 09:07 and later windows; if it repeats, split the first 15 s of :07 by holder (tend step holds vs compactor sweep vs stats).
