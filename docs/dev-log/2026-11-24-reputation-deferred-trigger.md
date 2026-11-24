# 2026-11-24 — Reputation's deferred check runs as its owner (0489, proof 192)

## The fault

The owner, playing the live game, kept getting `permission denied for table reputation_balance`.

`public.reputation_reconciles()` (0352) is the function of two constraint triggers, `DEFERRABLE INITIALLY DEFERRED`:
after insert on `public.reputation_book`, and after insert or update of `balance, seq` on `public.reputation_balance`.
It is plpgsql, owner `postgres`, and was NOT `SECURITY DEFINER`. It selects both tables. Only `postgres` and
`service_role` may read them (RLS on, no policy).

A deferred trigger fires at COMMIT. Prod runs PostgreSQL 17.6, which runs it as the role current at commit. For a
signed-in player's request that is `authenticated`, not the security-definer door that wrote the row. So every
transaction of a signed-in player that wrote a Reputation book row (an earn or a spend) failed at commit with 42501
and rolled back whole. Merchant houses write no Reputation (`public.reputation_credit` leaves at the players probe),
and the cron runs as `postgres`, so nothing else showed it.

PostgreSQL 18 runs a deferred trigger as the role that queued it. PGlite (every local proof and the pglite-gate) is
18.3, so no proof ever saw the fault.

## Prod, before (read-only, `scripts/ops/harness/reputation/before-0489.sql`, 2026-11-24 ~00:30 UTC)

Gate first: beat 151 ms mean / 654 ms p95, db 779 MB, io waits 0.

| field | value |
|---|---|
| head | 20260818000488 |
| server | 17.6 |
| fn_definer | false |
| fn_config | null |
| fn_owner | postgres |
| fn_acl | `{postgres=X/postgres,service_role=X/postgres}` |
| fn_md5 | 3d25b3b1ff9d7eea7b6d9d92544c4d34 |
| triggers | reputation_balance and reputation_book, both deferrable, initially deferred, on reputation_reconciles() |
| invoker_deferred | reputation_reconciles() (the only one) |
| auth_reads_balance | false |

The local chain (PGlite) has the same md5 for the body.

## The fix (0489)

`alter function public.reputation_reconciles() security definer set search_path = public, pg_temp` (the same
`proconfig` as `public.reputation_credit`), and `revoke all ... from public, anon, authenticated, service_role`.
The body is not touched (md5 asserted before and after). No switch: a fault fix.

## What was verified, and how

- **0489 self-assert, PGlite 18.3 (local apply):** the probe as `authenticated` (a probe house's jwt claims): a
  security-definer door earns 40, then `set constraints public.reputation_reconciles immediate` fires the queued checks
  still as `authenticated`. Before the fix: `ok` (this engine runs it as the queuing role). After: `ok`, book and
  balance reconcile. Catalog asserts green. 204 ms.
- **0489 with prod's pre-image planted (local, rolled back):** function set back to invoker, `service_role` EXECUTE
  granted, `alter default privileges ... to service_role` planted; the file ran green and left
  `{postgres=X/postgres}`.
- **Proof 192 (PGlite):** PO_SHAPE (the catalog property) and PO_SCENE: as `authenticated`,
  `cmd.captain_skill_up('elcano','navigator')` booked -50 (a spend: the same book row and the same triggers as an earn),
  the deferred checks fired as `authenticated` and passed, balance 1000 -> 950, rows 1..2 chained.
- **Proof 03 (PGlite):** the new marker GRANT_LOCKDOWN_DEFERRED_AS_OWNER: 4 deferrable triggers in the four schemas,
  all security definer; its control (an invoker-rights deferrable trigger built on purpose) was seen.

## What the local engine cannot show

On PostgreSQL 18 the pre-fix failure cannot happen by role, so no local proof can make it fail. The failure is
reproduced where the engine is 17:

- CI's `disposable-chain` job runs Supabase with `[db].major_version = 17` (`supabase/config.toml`). It applies 0489,
  whose self-assert REQUIRES, on an engine before 18, that the scene fails with 42501 on `reputation_balance` before
  the fix. So that job reproduces the fault and then shows the fix. (It also re-runs proof 03 with the new guard.)
- Prod's push runs the same self-assert on 17.6: the push notice says what the scene did before the fix.

## The guard for the future

Proof 03 (grant lockdown) gained GRANT_LOCKDOWN_DEFERRED_AS_OWNER: no deferrable trigger in public, world, cmd or
voyage may run a function without SECURITY DEFINER. Proof 03 runs on every PR in `disposable-chain` (a required check,
PostgreSQL 17) and in its pglite leg. It is not a `build` (file-reading) spec: a trigger's function and its rights are
a catalog fact, so the check lives where the catalog is.

## Prod, after

Read with `after-0489.sql` after the deploy; the figures are in the PR's comment and the WORK_QUEUE line.

## Proof 169 on this PR (not 0489's)

`pglite-gate (the rest)` failed twice (run 45299732427, first run and one diagnostic re-run) at proof 169 SR_SIZE pass 1, receipt
`{hold 0, tried 0, failed 0, note null}`: the wind job's hold step posted nothing at Lisbon. A hold job is drawn from
(harbour, game day, seq) (`public.hold_request_post`, `voyage.rng`); on CI's world, game day 623238 (2026-11-24 00:00-04:00 UTC)
draws Lisbon a lot under `hold_request_units_min`. Main ran proof 169 green on game day 623237 (21:38 UTC). The local world draws
differently (Lisbon posts 1+1 on game days 623232-623244 locally), so the CI day could not be shown locally. The same dice met 0466's
frozen self-assert (#839, `src/lib/db/frozenAsserts.ts`). Proof 169 now runs at the first harbour, LIS first, whose two hold
jobs post today (tried in a rolled-back block), as #839 did for the self-assert. Locally: 9/9 at LIS, and 9/9 with LIS excluded
(it ran at ACC), so the other-harbour path is proven.
