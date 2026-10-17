# 2026-10-18 — 0170: COMMAND DESK D1, a price says where it is going — `osn-desk-d1`

`docs/COMMAND_DESK.md` §4, §7.1, §10 row D1. The owner, 2026-10-17: *"i will be able to see the estimated price
movement so that i can plan buying and selling for max profit"*. **Not deployed.** Migration number 0170 (prod head
0169, read 2026-10-18). A server slice only: nothing on screen changes until D3 draws it.

## What was built

| Concept | Its one home | Notes |
|---|---|---|
| the regeneration rule | `public.stock_after(stock, target, rate, production, days)` | moved verbatim out of `tick_market_drift`'s UPDATE (one hunk); inlined by the planner (EXPLAIN VERBOSE shows `LEAST(...)`) |
| the drift walk's moments | `public.drift_moments(d0, k)` | mean = the tick's step with the draw at its mean, at the column's scale (exactly the σ = 0 tick); sd = σ·sqrt((1 − θ^2k)/(1 − θ²)) |
| what a quay adds to a mid | `world.price_terms(port)` + `world.price_sides(mid, spread, tax, bid factor)` | moved verbatim out of `world.price` (three hunks); `world.price` composes them |
| one row's estimated path | `public.price_path(port, good, slots)` (server-only) | k = 0 is the row as it stands (= `world.price`); k ≥ 1 the next slot boundaries |
| the client's read | `world.price_outlook(port, good, slots, side)` | registered, `authenticated` only; points / best / events / `assumes` "If nobody else trades here" / `held` |
| the knobs | `outlook_slots` 24, `outlook_slots_max` 96, `outlook_band_z` 1.2816 | |
| the record | stale `price_history` rows deleted; `tick_price_snapshot` also prunes `slot > now` (one hunk) | 61,824 rows on prod |

**Departures from the design, stated.** (1) No `p_fleet` on the outlook: a price is the market's; the fleet-dependent
money is D2's `good_board`. (2) `points[]` carry `value` (the side asked for), not `mid`. (3) The payload serves
`band_z`, not a `band: 0.80` literal; the proof checks the share inside against `erf(z/√2)`. (4) No catalogue entry,
type or hook yet — an entry point lands with the face that reads it (every pin in `rpc.surface.spec`), so D3 adds them.
(5) After the first boundary (`next_drift_change_at`) each step is one `drift_slot_seconds` later, read once: the
authority costs 0.25 ms a call on prod and 24 calls were most of the read.

## Proof (in the migration; cached PGlite world on 0169)

Receipt: world.price old = new on 2,135 rows; the outlook's now = world.price on 66 rows × mid/ask/bid to the cent;
the tick old = new over 24 steps × 3 harbours (1,665 rows, σ = 0, md5 per step); the outlook = the tick on 1,584
(row, step) pairs and = world.price on 198; every arm taken (both clamps, from zero, pulled down to target, production,
a 3-day catch-up, flat); best: none on a flat row, +16.22 % later on a −0.15 drift (bid), lower later on a short stock
(ask); the band, seeded: k = 1 mean 0.1081 vs 0.1080, 80.9 % inside; k = 4 0.0789 vs 0.0788, 78.2 %; k = 24 0.0094 vs
0.0096, 79.5 % (n = 1,665, tolerance 4 SE); 2,588 stale rows deleted locally, a planted future row pruned by the
snapshot; refusals; registry +1; leaves server-only; 4 bodies reverse to their pre-images, ACL/owner/volatility/
definer/config unmoved. The file takes 12.6 s on PGlite.

Timings (notice only): world.price old 354 ms / new 361 ms over 2,135 rows; the outlook 1.65 ms a call on PGlite.
The tick reads 1,685 → 2,295 ms in the file only because the new run goes second over the first's dead tuples:
alternated outside the file (6 harbours × 3 rounds, rolled back) it is old 440 ms / new 380 ms.

## Read-only on production (2026-10-18, after 0169 landed; `begin transaction read only`, result raised)

Every function called checked `provolatile` s / i first (all were). Every hunk's old text occurs exactly once in the
live bodies (tick_market_drift, world.price ×3, tick_price_snapshot, client_rpc_entry_points); none of the six new
functions and none of the three knobs exist; drift numeric(6,4), stock numeric(12,2); erf(1.2816/√2) = 0.8000.
The sample is BEL, SLV, ISL (555 rows each; 555 rows of the first inside the band under every bend). Stale history:
61,824 of 125,180 rows. **Cost:** the outlook's work emulated with the live leaves over 40 md5-spread rows,
24.8 ms a call with the per-step clock authority (0.25 ms × 24) — hence departure (5); the per-call costs measured:
mid_terms 0.25 ms, game_day 0.10, mid_from_terms 0.024, spread 0.58. Expected now ≈ 6–12 ms a call. It settles
nothing and steps no clock (asserted), so it never touches the arrivals sweep. world.price over the (a) rows:
3.5 s on prod, so (a) costs about 7 s of the push; the drift job's last 20 runs average 6.6 s.

## Verify (once)

`npm run build` (cached prefix: 160 restored, 0169 + 0170 applied, 66 s), `tsc -b` (in the build), `eslint .` clean,
`rpc.outlook.spec` 4 passed; the other selected specs on a local build at `localhost:4260` (rpc.surface,
duplication, rpc.firstSession, sea.dateline, map.townhall, route.stopface) 59 passed, 0 skipped; db.chain and
db.image left to CI. Selection map: `rpc.outlook.spec.ts` added to `tests/shard-weights.json`; rule S selects it
(it names `price_outlook`). No screenshot: this slice draws nothing (the desk is D3).

## Deploy

DEPLOY_RUNBOOK: unwind the clock → `supabase db push --linked` → wind the clock. Merge after the push. The history
repair shows at once; the read has no client caller until D3.
