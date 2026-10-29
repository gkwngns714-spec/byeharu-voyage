# 2026-10-29: 0270, a merchant's clear re-plans her lines before the quay

Follows `2026-10-28-tend-holds.md`. That log (0269) recorded the long tend holds. Its receipts name the root: in every hour the longest tend hold is a `cleared` step, and that step re-plans the clearing merchant's lines (`npc_plan`) inside the quay. 0270 moves that re-plan out of the quay, the `2026-10-28-lap-start-job.md` (0266) pattern. It changes no decision.

## Prod root (0269's recording, read 2026-10-29 06:00 UTC, head 0269, 14 hours of receipts)

- Every hour's longest tend holds are the same kind of step: `did` = `{cleared: 1}`, `step_ms` 0.40-1.09 s, and `step_ms` is ~all of `held_ms` (`check_ms` <= 3 ms, `commit_ms` <= 11 ms).
- The :07 lap-start lag follows them: p95 4.0-7.2 s and max 8.4 s in the :07 minute of the last 9 hours, with 1-3 laps a minute that waited their full 1.5 s for a beat gap, and a lap open's own quay wait up to 1,062 ms.
- The work inside that step is 0150's rule: a clearing merchant's lines are re-planned (`npc_plan`: ~11 legs and up to 16 candidate loops priced, ~0.4-1.1 s on prod). 0150 fires it for ~1 in 3 clears: the third clear of a lap, or a SAIL refused E_ENDURANCE.
- First 14:07 reading after 0269 went live (10-28): the only tend holds over 15 ms were 3 `cleared` steps (997 / 546 / 464 ms), and all three ran `npc_plan` inside the quay (2 x E_ENDURANCE, 1 x the 9th clear of a lap, E_CREW_SHORT). The `NPC_CLEARED` count itself is 8 ms (ruled out).
- 0150 did not create this; 0267/0269 began running every tend step under `public.hold_the_quay()`.

## The design

1. **`public.npc_clear_due(player, route, lap, verb, error_code)`** is the one place for 0150's rule: `n` = the clears of this lap (her `NPC_CLEARED` events of the lap) + 1, and `plan` = `n >= 3`, or a SAIL refused E_ENDURANCE. `public.npc_tend_route`'s clear branch and its plan pass both ask it, so they cannot disagree. It reads `public.events` only: no lock, no write, no clock. Stable, security definer, server-only.
2. **`public.npc_tend_route` gets a plan-pass mode** (transaction flag `byeharu.tend_plan_pass`). It walks her gates exactly as her step does, and at every acting road that is not the clear branch it `continue`s without acting (4 stops: the pause at `k > v_max`, the tow of a wreck in port, the off-route loop assignment, and the plan / start / resume block). At the clear branch it asks `npc_clear_due`; when the rule says plan it runs `npc_plan` and sets `byeharu.tend_planned`, then continues. Every gate still has one copy: the plan pass is the same function, not a second reading of the rules.
3. **`public.tick_reconcile` runs the plan pass** in its own transaction, before the quay, for exactly the merchants a clear can reach at all: a failed order is the only road to the clear branch, so it tests a plain SELECT of `public.orders` (`fleet_id`, `status = 'failed'`). It sets `byeharu.tend_planned` to the plan pass's verdict for her step, after the quay as before, and her step under the quay does the clear without re-planning. The receipt gains `tend_plan` = `{n, ms}`: how many plan passes planned and what the passes cost, outside the quay.
4. **The clear itself is unchanged**: one `NPC_CLEARED` event with the same count, `cmd.clear_for`, `cmd.advance` — the same calls in the same order. The gates, their order and their writes are unmoved (the plan pass returns before each act).
5. **The budget (0114)** is read at her step's head, which is now the plan pass: one reading per merchant, before the dear work, as before. When the plan pass planned, her step skips the second budget copy — that copy could only defer a clear whose plan was already made.
6. **The pause a plan may set (0181 `laid_up`)**: her step still clears her after it, exactly as the old clear branch did after its inline plan. `public.npc_tend` (the one-transaction door) never sets the flags and behaves as before.

## Order and locks do not move

- The plan pass takes her fleet and route rows NOWAIT, as her step already did. It never takes the quay: it is on no wait cycle, and it commits before her step's transaction opens.
- Her step still takes the quay FIRST, then her rows. The set of functions that take the quay is unchanged (self-asserted by text: the same list of function OIDs before and after).
- A plan pass that raises sets `tend_planned = 'off'` and commits; her step then plans for herself, as before.

## The self-assert's probes (all rolled back, on the world 0270 is applied to)

- **(a) The hunks.** Every hunk (8 in `npc_tend_route`, 3 in `tick_reconcile`) occurs exactly once in the live body and reverses to its pre-image. ACL / volatility / definer / config unmoved. Every function the two bodies decide with (28 of them, from `npc_plan` to `cmd.standing_route_tail`) has the same md5; the quay takers are the same set; the client entry points are the same count.
- **(b) The fix's own shape.** In the new `tick_reconcile`, the plan pass's `npc_tend_route` call stands before the quay and the verdict is set after it; the loop carries both flags; `npc_tend_route` asks the rule exactly once, 0150's rule no longer appears inside the clear branch, and the plan pass stops at exactly 4 acting roads.
- **(c) The rule itself.** E_ENDURANCE plans, a first clear with E_NO_CARGO does not, and there is exactly one `npc_clear_due` in `public`.
- **(d) Probe 1, her step.** Up to 6 merchants the clear branch can reach (a docked hull, a route with stops, no failed order of her own; `pg_temp.prep_0270` enables the traders, assigns her fleet and starts her route — the chain's fresh world leaves every route unstarted, prod's running merchants are already started and the prep then does nothing). Three cases per merchant, each with a planted failed order: a first clear (no plan), the clear that makes three (plan), a SAIL refused E_ENDURANCE (plan). Four runs per case: OLD (a temp copy of the live body), NEW, OLD again (control), and the plan pass + her step. The digest of her route, stops, lines, laps, orders, fleet, ships, voyages, purse, this transaction's ledger rows and events, her port's market and treasury is identical across OLD, NEW and the control, the receipt is identical, and the plan pass + her step leaves the same rows and receipt as her step alone. The plan pass never plans where the rule says no.
- **(e) Probe 2, the hourly loop.** OLD vs NEW `tick_reconcile`, with the same cuts as 0269's: only the sample's routes, no companies, the sample's purses. Same rows. The receipts are equal apart from `ms`, `quay`, `tend_holds` and the new `tend_plan`; the old loop carries no `tend_plan`; the new tally counted its plans.

## Local result (PGlite, chain restored at 0269 + 0270 applied here)

- The chain: 259 migrations, 258 restored from the prefix cache, 1 applied here; 0270 took 8,236 ms; chain key `823a2514279ff7c3`, 17.8 s; world guard ok.
- The 0270 self-assert notice, verbatim:

```
0270 self-assert ok: A MERCHANT'S CLEAR RE-PLANS HER LINES BEFORE THE QUAY. npc_tend_route and tick_reconcile reverse to their pre-images hunk by hunk, ACLs unmoved, the functions both decide with and the quay takers unmoved; 0150's rule in public.npc_clear_due alone. Probes: 18 step cases on 6 merchants (old = new = control, and the plan pass + the step = the step), 12 planning cases; the hourly loop old vs new, 1 plan(s) counted. Rolled back.
```

- `node scripts/db/proof.mjs standing`: `✓ 11_standing_route.sql — 5/5 PASS markers in 0.5 s`, final line:

```
PROOFS PASSED: 1 file(s), 5/5 PASS markers seen
```

- The brief expected the self-assert to fail first on probe details (the chain's fresh world leaves every route unstarted). It did not: the probe fixture already starts the merchant's route (`pg_temp.prep_0270`), and 6 merchants were sampled, 18 step cases run. No probe change was needed.

## Overhead

| what | cost | inside the quay hold? |
|---|---|---|
| the plan pass's own `npc_plan` (the dear work) | ~0.4-1.1 s on prod, per planning clear | no: its own transaction, before the quay |
| the loop's failed-order test | one `exists` read of `public.orders` per merchant | no (before the quay) |
| the two flags (`set_config` transaction-local) | microseconds per merchant | one read in her step |
| the rule (`npc_clear_due`) | one count of her lap's `NPC_CLEARED` events — the old inline count, plus the `n` JSON object | yes (the old code counted the same rows) |
| a commit per merchant with a failed order | one commit, her own rows only | no |

- Per planning clear, the quay hold falls by the plan's ~0.4-1.1 s; the step that remains is the clear itself (one `NPC_CLEARED` event's count, ~8 ms on prod at 14:07). Per hour that is ~1-2 s of tend hold removed, and the :07 lag should follow.
- The plan pass's cost is now visible: `reconcile_runs.receipt.tend_plan.ms` sums the passes (including the ones that did not plan), and `n` counts the ones that did.

## PROD CHECKS (before the push; read-only, one statement per file)

The live bodies are the ones the hunks were cut against (head 0269):

```sql
select p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', ''))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('npc_tend_route', 'tick_reconcile')
 order by 1
```

Expected:

- `npc_tend_route` `47994dc4d93e010280846ae320d0ffd9`
- `tick_reconcile` `8833ba11e1c6ed9642bf9ba3385f63a7`

`0270` refuses at its own guard if `npc_clear_due` already exists, and at its hunk check if a body differs. Both are run before the push.

## After-check (the next :07 after the deploy; read-only)

**A. The plan pass's tally, per run:**

```sql
select at, receipt->'tend_plan' as tend_plan,
       (receipt->'tend_holds'->>'n')::int as long_holds
  from public.reconcile_runs
 where at > now() - interval '3 hours'
 order by at desc
```

Expect `tend_plan.n` around the number of planning clears of the hour (1-3 a run by the 14-hour record) and `tend_plan.ms` around 0.4-1.1 s per plan.

**B. The tend holds over 200 ms, by what the step did:**

```sql
select r.at, e->>'got' as got, (e->>'held_ms')::numeric as held, (e->>'step_ms')::numeric as step,
       (e->>'check_ms')::numeric as purse_check, (e->>'commit_ms')::numeric as commit, e->'did' as did
  from public.reconcile_runs r, jsonb_array_elements(r.receipt->'tend_holds'->'kept') e
 where r.at > now() - interval '3 hours'
   and (e->>'held_ms')::numeric > 200
 order by held desc
```

Expect no such row whose `did` is `{cleared: 1}`, and the cleared steps' `step_ms` toward the `NPC_CLEARED` event's own ~8 ms.

**C. The :07 lap-start lag, per lap:**

```sql
select date_trunc('minute', l.at) as minute,
       (s->>'fleet') as fleet,
       extract(epoch from ((s->>'open_at')::timestamptz - (s->>'due')::timestamptz)) as lag_s,
       (s->>'plan_ms')::numeric as plan_ms,
       (s->>'wait_ms')::numeric as gap_wait_ms,
       (s->>'late')::boolean as late,
       (s->>'quay_ms')::numeric as open_quay_wait_ms,
       (s->>'open_ms')::numeric as open_ms
  from public.lap_start_runs l, jsonb_array_elements(l.receipt->'steps') s
 where l.at >= date_trunc('hour', now()) + interval '7 minutes'
   and l.at < date_trunc('hour', now()) + interval '8 minutes'
 order by (s->>'open_at')
```

The lag's p50 / p95 / max per :07 minute is the series to compare with the 4.0-7.2 s p95 and 8.4 s max of the 14-hour record.

**Rollback, if needed:** 0270 is a forward migration; the rollback is a forward file that restores the two bodies from `defs_before_0270` (the pre-images are in this file's hunk text) and drops `public.npc_clear_due`. The old bodies re-plan inline, so no state depends on the plan pass.

## What is NOT proven

- The plan pass's cost on prod is not measured locally: the self-assert proves the rows and the receipt, not the timing. `receipt.tend_plan.ms` is the first prod measurement, at the deploy's next :07.
- No two-backend interleaving: PGlite has one connection, and prod is read-only for checks. The lock claim rests on the code (the plan pass takes no quay, her rows NOWAIT, and commits before her step's transaction) and on the self-assert that the quay takers are unchanged.
- The plan pass's exception fallback (a `npc_plan` that raises) is not exercised. Her step would then plan inline, as before; the probe cannot make `npc_plan` raise without changing it.
- The 9th-clear E_CREW_SHORT merchant seen at 14:07 is a separate defect (a re-plan cannot fix crew); 0270 only moves her re-plan out of the quay.
- The probes ran on the chain's fresh world with the probe's own planted orders and events, not on prod's data. The prod after-check above is the live net.
