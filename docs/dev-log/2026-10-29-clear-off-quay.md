# 0274 — her clear's acting runs before the quay (the clear-off-quay slice)

Worktree `wt-osn-clear-offquay`, branch `osn-clear-offquay` (cut from origin/main 3b04c828, prod head
0272). The migration: `supabase/migrations/20260818000274_the_clear_acts_before_the_quay.sql`.

## The measured prod root (2026-10-29 09-12 UTC, head 0272; full report
`C:\Users\gkwng\dev\prodcheck-2026-10-29\quay-holds.md`)

- Of every tend hold over 100 ms in 09-12 UTC, **every one is a clear except one 255 ms tow** (11:07).
- A cleared merchant's step holds the quay **63.7-508.8 ms (median 176.2 ms)** — `step_ms` is ~all of
  `held_ms` (`check_ms` 0.3-3.3 ms, `commit_ms` 1.1-6.6 ms). Combined 09-12: **3,538 of 14,495 ms =
  24.4 %** of the tend phase's quay-held time (per hour 6.9-31.7 %; 0.36-1.47 s a :07 minute).
- Inside the clear, after the NPC_CLEARED count the step runs `cmd.clear_for` then `cmd.advance` under
  `public.hold_the_quay()`: the advance executes her whole pending queue (priced SELL/BUY, PROVISION,
  HIRE, SAIL — 9-14 orders at the clear's own timestamp) and, when it runs dry, 0092's queue-dry
  refill renders and executes the next stop.
- The :07 lap-start lag is a **queue, not a sum of holds** — its p95 (4.30 s) now equals the other
  minutes' (4.37 s). This slice removes the next measured root (the only recurring 100-500 ms hold);
  it does not claim to remove the whole lag (the 837-transaction tend queue and the start/resume
  re-plan remain, and are the slice after this one).

## The design (0266/0270's pattern, one copy of every gate)

1. `public.npc_tend_route` gains a **CLEAR PASS** mode beside 0270's plan pass: transaction flags
   `byeharu.tend_clear_pass` (the mode) and `byeharu.tend_cleared` (the verdict). The same function
   walks the same gates; the clear pass stops before the four acting roads (pause-dark, tow,
   off_route-assign, plan/start/resume) exactly as the plan pass does, and at the clear branch —
   after the 0114 budget check and `public.npc_clear_due` — performs the clear's acting exactly as
   the step does (the one NPC_CLEARED event with the same n, the step's conditional plan,
   `cmd.clear_for`, `cmd.advance`), sets `byeharu.tend_cleared = 'on'` and continues. The conditional
   plan is kept in the pass so that a plan-pass fallback (plan not made) still re-plans exactly once,
   outside the quay — the rows stay identical to the step's in every arm.
2. `public.tick_reconcile` runs the clear pass in its **own transaction after the plan pass and before
   the quay**, for the merchants a failed order makes clearable (the same test the plan pass uses);
   after the quay grant it sets the verdict for her step (as 0270 sets `tend_planned`). Her step under
   the quay then skips the clear branch's acting and every acting road and only counts — the budget
   (0114) was read at her step's head, which is now the clear pass. A pass that raises or cannot take
   her rows leaves the verdict 'off' and commits; her step clears inline exactly as today.
3. Order and locks do not move: the pass never calls `public.hold_the_quay()`, takes her fleet and
   route rows NOWAIT at the function's head (as her step does), runs under `public.npc_upkeep_scope`
   (2 s lock_timeout, 0114's deadline) and commits before her step's transaction opens. The receipt
   gains `tend_clear {n, ms}` beside 0270's `tend_plan`.

## The probes in the migration (all rolled back; 0270's shapes)

- **Hunks once + reverse**: 7 hunks of `npc_tend_route`, 4 of `tick_reconcile`; ACL / volatility /
  definer / config unmoved; the md5 of every function the two bodies decide with unmoved (0270's kept
  list + `npc_clear_due`); the quay takers and the client entry points unmoved.
- **Probe 1 (per merchant, up to 6)**: her step OLD vs NEW vs OLD (control) vs the plan pass + the
  clear pass + her step, on planted failed orders covering a first clear (E_NO_CARGO), the third clear
  of her lap, E_ENDURANCE and E_CREW_SHORT — rows digest and receipt identical; the clear pass must
  have cleared ('on') and the plan pass must not plan where the rule says no.
  - **Spent budget**: a past deadline (0114) defers in the plan pass, the clear pass and her step,
    exactly as her step deferred alone; the pass's verdict stays 'off'.
  - **Raised pass**: the clear pass raises (the block is `tick_reconcile`'s own begin/exception shape;
    the raise stands in for any pass-level raise on prod — a statement_timeout, a deadlock, a cancel —
    the catch, the rollback of the pass's acting and the 'off' verdict are the production ones); her
    step clears inline — same digest, same receipt. One planned-then-raised case (E_ENDURANCE) proves
    the fallback does not re-plan.
- **Probe 2**: the hourly loop OLD vs NEW with 0269/0270's cuts — same rows, same receipt apart from
  `ms` / `quay` / `tend_holds` / `tend_plan` / `tend_clear`; the old loop carries neither tally; the
  new loop counts 1 plan and 1 clear for the planted merchant.
- The chain's fresh world leaves routes unstarted — `pg_temp.prep_0274` starts them inside the rolled
  back block, as 0270's prep does.

## Local gates (2026-10-29, the gate run)

Verbatim self-assert receipt:

```
0274 self-assert ok: HER CLEAR ACTS BEFORE THE QUAY. npc_tend_route and tick_reconcile reverse to their pre-images hunk by hunk, ACLs unmoved, the functions both decide with and the quay takers unmoved; 0150/0272's rule in public.npc_clear_due alone. Probes: 24 step cases on 6 merchants (old = new = control, and the plan pass + the clear pass + the step = the step), 18 planning cases, the spent budget and the raised pass on every merchant, one planned-then-raised; the hourly loop old vs new, 1 plan(s) and 1 clear(s) counted. Rolled back.
```

```
node scripts/db/proof.mjs standing — chain 262 migration(s): 261 restored from the prefix cache
  (preamble-p0261-515581ffabcac2a2d2200326), 1 applied here (0274) — 262 with a self-assert receipt
  (268 receipt line(s)); chain key f9d4b567f643aad8, 20.7 s; world-guard ok;
  ✓ 11_standing_route.sql — 5/5 PASS markers in 0.5 s.
node scripts/db/proof.mjs merchant — 262 restored (preamble-p0262-f9d4b567f643aad88d22dd0c),
  world-guard ok; ✓ 12_merchant_companies.sql — 6/6 PASS markers in 48.1 s.
```

The gate caught two author defects, both fixed and re-gated before this entry: (1) the step's count now
stands BEFORE the halt law's failed-order read — the pass's clear cancels the failed order and the
advance may sail her, so by the step the order is gone and an in-branch count never fired (the step's
receipt said cleared 0 where the old step said 1); (2) the loop-receipt comparison excludes
`tend_plan` from BOTH receipts — this file's OLD is 0270's NEW, so 0270's tally is in both, and only
`tend_clear` is this file's own.

## PROD CHECKS (read-only, before the push; go in the PR body)

Run against prod (head must be 0272 and 0273 must not have re-cut these two bodies — see the risk
below). One SELECT per file, `begin transaction read only`.

1. The live bodies are the ones the hunks were cut against — md5 of `prosrc` must equal:
   - `public.npc_tend_route(timestamptz,uuid,uuid,bigint)`: **`e4911bf9dfd0088a82f9a37a9c3b9d8c`**
   - `public.tick_reconcile(boolean)`: **`41339a36b1bef1f5b173c238d6afeeaa`**
   ```sql
   select p.oid::regprocedure, md5(p.prosrc)
     from pg_proc p
    where p.oid in ('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'::regprocedure,
                    'public.tick_reconcile(boolean)'::regprocedure)
    order by 1;
   ```
   If either differs, re-cut the hunks against the live bodies — do not push.
2. The two live clear merchants (routes `1b52a58e…`, `63ade18d…`, 0272's after-check) still clear
   hourly at :07 — they are the deploy's first `tend_clear` samples.
3. No new quay taker: `select p.oid::regprocedure from pg_proc p where pg_get_functiondef(p.oid)
   like '%hold_the_quay()%'` — same set as before the deploy (the migration's own assert also holds it).

## The after-check (the first clean :07 after the deploy, from `reconcile_runs.receipt`)

- `receipt.tend_clear` carries the pass's own n/ms; `receipt.tend_holds.kept` carries **no `cleared`
  entry above ~10 ms** (the step is now the purse check plus the commit).
- `receipt.quay.tend.held_ms` falls by the clears' share — 0.36-1.47 s in a :07 minute.
- The :07 lag: p95/late-laps against 09-12's baseline (p95 4.30 s, 0.75 late/min). If p95 stays near
  4 s, the residual is the 837-transaction tend queue and the start/resume re-plan — the next slice.
- Watch the two E_CREW_SHORT routes (0272): their clear now runs in the pass — `npc_plan`,
  `cmd.clear_for`, `cmd.advance` in the pass's transaction — their NPC_CLEARED n/code/line payloads
  and the orders at the clear's timestamp must be unchanged.

## The forward rollback

If the clear pass must be undone, ship a forward migration (never revert on prod) that re-cuts the two
bodies back: in `tick_reconcile`, remove the clear-pass block and its verdict/tally lines; in
`npc_tend_route`, drop the two flags and restore the clear branch's acting to the step (the 0274
hunks' old texts are the exact re-insertion text — they are in this file, in
`20260818000274_the_clear_acts_before_the_quay.sql`).

## What this slice does NOT prove (say it in the PR)

- **The pass's concurrency on prod** (PGlite is one connection): like 0270, the claim rests on the
  code — no quay in the pass, her rows NOWAIT, commit before the step — and on the unchanged
  quay-taker set.
- **The raised-pass probe's raise is a stand-in**: no in-call failure propagates out of
  `npc_tend_route` (its per-row handler catches everything), so the probe raises inside the pass
  block after the pass acts, exercising the production catch/rollback/verdict shape. A real
  statement_timeout or deadlock on prod lands in the same handler.
- **The lag attribution** (quay-holds.md §7): 4 samples; removing the clears' 24.4 % of the held time
  is expected, not guaranteed, to move the :07 p95.
- **0273's overlap**: this file was authored against the 0272 bodies. If 0273 re-cuts
  `npc_tend_route` or `tick_reconcile`, the 0274 self-assert fails loudly at apply time (each hunk
  must occur once) — re-cut the hunks against the 0273 bodies then; never weaken the assert.
