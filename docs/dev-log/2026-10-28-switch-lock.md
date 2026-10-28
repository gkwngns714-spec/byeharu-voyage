# 2026-10-28: the switch reads the world with no coin in flight (`osn-switch-lock`, migration 0268)

Bug (owner shown, hand-off 2026-10-28): the closed economy's stamp is 138 ducats below the real world total. Owner: leave the 138 and `economy_closed_total` alone; fix the race only.

## Measured (prod, read-only, head 0267, 2026-10-28 12:22-12:29 UTC)

- `economy_closed_total` = **1,986,693,521**, `economy_closed_at` = 2026-10-26 06:52:21.857924 UTC; `world.stats_now()` total = **1,986,693,659**: +138, the whole of what has moved since the close (stats_now is STABLE, 67 ms).
- One `ECONOMY_SWITCH` event ever (06:52:21). 0 positive minted flows (IMPORT_DEMAND / EARNINGS / SEED / GRANT) with `created_at` after the close, and none in the 20 s before it either: the flow rows of 10-26 are no longer in `treasury_flows`, so the 138's attribution to one do_sell IMPORT_DEMAND premium (0174 :184-186) is the hand-off's, **not re-measured here**. (A flow's `created_at` is its transaction's start, which is why a straddling sale would read as "before the close".)
- Lock posture: `default_transaction_isolation` read committed, `deadlock_timeout` 1 s. `mint_guard` provolatile `s`, `economy_close_switch` `v`, `world.stats_now` `s`. `port_treasury` rows with `invested` null: 0 of 246.
- Last 30 min: 1,639 beats, p95 1,031 ms, 0 errors.

## The cause (0240, read)

- `economy_close_switch` takes no lock: the flag is read in its DECLARE (:354), the total at :368, then the flag flips. A transaction that began under the open rules and commits after that reading has its new money outside the stamp.
- `mint_guard` is STABLE (:239): a STABLE plpgsql function runs on its caller's snapshot, so a mint asked for after the flip committed is still judged by the flag as it stood when the calling statement began.

## The fix (0268)

- `public.mint_gate(exclusive)`: one transaction-scoped advisory lock (`hashtextextended('byeharu.mint_gate', 268)`), the one authority of the key. Server-only.
- `mint_guard` superseded, VOLATILE: a positive minted kind takes the gate SHARED, then reads the flags in a new statement (a snapshot taken after the gate is held). Same verdict as 0240.
- `economy_close_switch` superseded: `hold_the_quay()` first, then the gate EXCLUSIVE, then every reading (the flag left the DECLARE; the total, purses and knobs after). The rows it writes are locked NOWAIT first (the three `economy_*` knobs, the harbours whose `invested` is null). Same writes and answers as 0240.
- **Why both locks.** The quay alone does not cover the race: it is held by the beat, the tend / companies steps and the lap-open step only. A player's sale (`cmd.issue` → `do_sell`), a sign-up's FOUNDING and `city_day`'s EARNINGS (pg_cron :37) mint without it. The gate sits at the guard, which every new coin passes through (`credit`, `treasury_post`). The quay is taken too, first, so no beat is cut by the flip: a beat that began open commits whole before the switch reads, and the next one reads "closed" from its first statement.
- **No new deadlock** (the 0265 / 0267 order, quay first, is kept). The switch waits only for the quay (holding nothing) and for the gate (holding only the quay). After the gate it never waits: its two row locks are NOWAIT (a busy row = 55P03, the switch rolls back whole and is asked again), its one insert has a fresh uuid, and the only trigger it can fire (world_config's) needs `key = 'time_compression'`. A cycle through its gate wait would need a gate holder waiting for the quay, but every quay taker takes the quay first in its transaction (beat, tend, companies, lap open), so nobody holds the gate when they ask for the quay. Shared holders never wait for each other. A new shared request queued behind the waiting exclusive is a soft edge, which the deadlock check resolves by reordering the queue (worst case: one 1 s `deadlock_timeout` wait, once per hand-flipped switch). The minters' own order (house row → harbour lock → gate) is unchanged.

## Local (PGlite, cached chain → 0267; purses dark, economy open, 246 harbours with `invested` null)

- 0268 self-assert ok, 121 ms. **OLD = NEW: 464 guard verdicts** (every flow kind + BUY + an unknown kind × −7 / 0 / 7 / null × the four (closed, lit) states, 6 E_NO_NEW_GOLD). The switch run as the world is (refused, E_PURSES_DARK, both) and with the purses lit (no-op, flip, back, no-op: same answers, events, knobs, `invested`; the stamp equals its own total).
- **In flight (rolled back):** IMPORT_DEMAND 777 made open and not committed → gate held `ShareLock`, quay not held. The switch closes holding quay `ExclusiveLock` and gate `ExclusiveLock,ShareLock`. Totals: 26,244,857 before the mint, 26,245,634 after it, **stamp 26,245,634** (= its answer), 26,245,634 after the switch. The next IMPORT_DEMAND is refused E_NO_NEW_GOLD. Neither lock is held after the rollback.
- **The self-assert catches the bug back (four negative controls, each a mutated copy of the file):** the switch without the quay → FAIL (order); the flag read before the locks → FAIL (order); the guard STABLE → FAIL (volatility); the guard reading the flag before the gate → FAIL (guard order).
- **Not proven by a run:** the two-backend interleaving itself (a second session's sale in flight while the switch waits). PGlite has one backend and there is no real Postgres on this machine, so that claim rests on the construction above and the order the self-assert checks on the bodies.

## PROD CHECKS (read-only, before the deploy)

Run them in the 10 minutes before the push. Read-only = only tables, the catalog and functions with provolatile `s` / `i` (`world.stats_now` is `s`).

1. Head is 0267: `select max(version) from supabase_migrations.schema_migrations` → `20260818000267`.
2. The bodies 0268 supersedes are 0240's: `md5(replace(pg_get_functiondef('public.mint_guard(text,bigint)'::regprocedure), E'\r', ''))` = `6c6c5199da7aa5233b645334573b35e6`, the switch = `0dea1b674be08c5c7cbbe74ec18cebcf` (checked 12:22 UTC; the guard block refuses otherwise).
3. `economy_closed` = true, `economy_closed_total` = 1986693521, `world.stats_now()->>'total'` − stamp = 138 (or the change is explained).
4. `select count(*) from public.port_treasury where invested is null` → 0 (the switch's NOWAIT seed then has nothing to lock).
5. The time is not :06-:08 (the reconcile's quay steps) or :36-:38 (`tick_city`: `invested` rolls, and the probe compares the old and new switch's `invested` within one transaction). The self-assert takes the quay in rolled-back sub-transactions, under `lock_timeout` 5 s. **Nothing it flips is committed**: every flip is inside a sub-transaction that raises and rolls back.

## After the deploy (read-only)

- `mint_guard` provolatile `v`; `mint_gate(boolean)` exists, not executable by anon / authenticated.
- `economy_closed` still true; `economy_closed_total` still 1,986,693,521; `economy_closed_at` unchanged; still exactly one `ECONOMY_SWITCH` event.
- Beats over 30 min: 0 errors, p95 within the before band (~1.0 s). While closed the gate is taken only for a refused minted credit, so beats should not see it.
- **Never flip the switch on prod to test this.** The owner flips it.
