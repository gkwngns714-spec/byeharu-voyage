# 2026-10-27 — two frozen self-asserts, fixed in the applier (0019 pirates roll, 0108 stopwatch)

> **THIS PR'S CI APPLIES THE CHAIN FROM ZERO.** It changes `src/lib/db/**` and `scripts/db/apply-chain.mjs`,
> which `scripts/ci/select-specs.mjs` counts as chain machinery (`growth.run`), the one exemption from
> the no-from-zero law (docs/CI.md). No migration file changes, so no prefix key, kept snapshot or
> world-image fingerprint moves: after this PR, PRs build on main's snapshots exactly as before.

## The two problems

1. **0108 (d5)** requires `world.route_board()` to average <= 400 ms over 10 calls. PC gkwng measured
   426 and 451 ms, so every from-zero replay there (its prefix cache was pruned by the 0019 edit in #349's
   first commit) died at 0108 and local `npm run build` was impossible. CI's runners pass it.
2. **0019 (g)** plays the quay's top row BUY -> SAIL -> SELL and requires the realised totals to equal the
   predicted ones. The voyage id is `gen_random_uuid()`, and the hazard dice are seeded from it (0006
   `voyage.rng`), so a boot now and then rolls PIRATES -> STRIPPED (0007 `voyage.settle` empties the hold)
   and the SELL answers E_NO_CARGO: "the quay predicted 6818 out / 7706 in and the orders moved 6818 /
   <NULL>" (PR #343, run 40292383876, cold boot). #349 found this, and its fix (`hazard_p_max` 0 inside
   the probe) was taken back out because it edited the applied file.

## The fix

`src/lib/db/frozenAsserts.ts` is the one list of frozen-assert patches; both PGlite appliers
(`src/lib/db/applyChain.ts`, `scripts/db/apply-chain.mjs`) execute `sqlToApply(file)` instead of the raw
text. The files themselves are untouched.

- 0019: `update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max'` before the probe's
  `world.trade_routes(v_lis, v_fleet, 1, null)` (inside the rolled-back probe; #349's line, word for word).
- 0108: `if v_ms > 400` -> `if v_ms > 1200` on PGlite. Real Postgres (`supabase db push`: production and
  CI's disposable-chain) applies the file as written and keeps 400.
- A patch may touch only text inside the file's final `do $$` block, must match exactly once, or the
  apply fails loudly (`tests/db.frozenAsserts.spec.ts`).

## Proof (this PC, 디폴리스)

- Prefix cache here was HEALTHY before the change: browser variant p0032…p0235 and preamble p0032…p0230 all
  on the current chain's key path (235 files), so `npm run build` here restores the whole chain.
- 0019, positive control on a scratch PGlite (files 0001-0018, then every sea's hazard forced high and
  pirates certain, check constraints dropped on that scratch database): the raw file FAILED with the CI message shape ("predicted 7424 out / 8270 in … moved
  7424 / <NULL>"); the patched apply PASSED.
- 0108: the restored p0096 snapshot plus files 0097-0108 (4 files; 15 min, most of it 0098/0105) through the
  patched applier: receipt printed, **156.70 ms a call** on this PC. PC gkwng's 426/451 ms sit 2.6x under the new
  1,200 ms line. Not proven ON gkwng itself (that PC is not here): re-run `npm run build` there after the merge.

## Not fixed here

- The nightly from-zero `disposable-chain` on real Postgres still runs 0019 as written, so the pirates roll
  can still (rarely) fail it there. Only an edit of 0019 would close that, and that is not allowed.
