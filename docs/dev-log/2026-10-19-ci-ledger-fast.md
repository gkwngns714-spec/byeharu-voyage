# 2026-10-19 — pglite-gate (ledger) in a minute and a half, not twelve — `ci-ledger-fast`

**The owner's words.** The work "takes forever". On recent PRs the CI leg `pglite-gate (ledger)` was
the slowest by far: 12m16s on #254 (00:41:41 → 00:53:57 UTC) against 3m37s for `merchants`, 4m25s
for `the rest` and 2m56s for `disposable-chain`. Every main run paid it too (13–14 min on
39180776707, 39167926132, 39165370703).

**Where the time went, measured, not guessed.** The leg's log already split it: the world restored
from the prefix cache in 3.2 s, built in 13.8 s, world guard and fixtures ~40 s — then
`02_ledger_reconciliation.sql` alone, 11m06s. A clock put inside the soak (first commit of PR #255,
run 39185351620, where the whole proof took 401 s on that runner) said:

| part of the soak | seconds |
|---|---|
| the 500 orders through `proof.issue` (BUY 156, SAIL 132, SELL 92, PROVISION 47, HIRE 37, REPAIR 25, CLEAR 11) | 0.9 |
| the refused orders' `cmd.clear` | 0.1 |
| 25 jumps: `update public.voyages …` | 0.0 |
| 25 jumps: `update public.fleets set busy_until …` (853 fleets) | 0.0 |
| 25 jumps: `update public.port_goods set drift_slot = drift_slot - 1, last_regen_day = …` — ALL 132,090 rows | 121.3 (1.9 s the first pass, 6.9 s the last: 3.3 M dead tuples in one transaction) |
| 25 jumps: `public.tick_arrivals()` | 1.0 |
| 25 jumps: `public.tick_market_drift()` over every rewound row — the whole world | 275.7 |

So 99 % of the proof was the market of ~230 quays nobody in the proof ever reads, walked 25 times.
The world had 70 goods and a handful of ports when the soak was written; it has 238 harbours × 555
goods now, and the rewind was never scoped.

**The fix (scripts/db/proofs/02_ledger_reconciliation.sql).** The rewind reaches only the quays the
soak can see — where one of its three fleets lies (`fleets.port_id`) or is bound (its SAILING
voyage's `dest_port_id`) — and `tick_market_drift()`, keyed per row since 0010 (`drift_slot <
slot`, `last_regen_day < day`), walks those alone. That is how the game itself has moved a market
since 0137: `world.market` drifts the ONE quay being read (`tick_market_drift(now, p_port)`), not the
world. Nothing the six markers measure changes — same three houses, same 500 random orders, same 25
jumps, `tick_reconcile` still over every purse, the sailing invariant over all 853 fleets. The soak's
shape is unchanged too: 296 succeeded / 204 refused (was 283 / 217), 3,514 ledger rows, 2,478 debits
and 1,036 credits (was 3,507 / 2,471 / 1,036).

**After (run 39186187514, PR #255).** Proof 02: **28.9 s** (orders 1.6 s, the 25 jumps: port_goods
1.6 s, arrivals 1.7 s, drift 22.1 s). The leg: **1m36s** (01:37:26 → 01:39:02), now the fastest of
the three; `merchants` 3m21s, `the rest` 6m08s, `disposable-chain` 2m24s, `build` green. The world
was restored 196/196 from the prefix cache in 3.6 s — no from-zero apply anywhere (the law).

**What else landed.**
- `scripts/db/proof.mjs` prints each proof's wall time (`… 6/6 PASS markers in 28.9 s`) and any
  `TIMING:` notice a proof raises; the soak raises one line at its end. The next growth is read off
  the log ("measure every slice").
- `scripts/ci/select-specs.mjs`: the proof runner `proof.mjs` and its fixtures `proof-courses.mjs` /
  `market-fixture.mjs` are no longer "chain machinery" for the growth rule — they are certifiers in
  no snapshot's key, like `world-guard.mjs` (K4) and `proofs/**` (K5). A one-line header edit to
  proof.mjs (2613844) used to send the 45–65 min growth test and lift the no-from-zero law. A new
  positive control pins it (8 of 8 hold); a change to any of them still runs every pglite leg.

**Not changed.** The selection of the ledger leg itself: #254 ran it because 0204 writes
`public.voyages` and calls `public.new_house`, both of which the proof names — correct. No migration
touched; no budget raised; the other legs and the required checks (`build`, `disposable-chain`)
untouched.
