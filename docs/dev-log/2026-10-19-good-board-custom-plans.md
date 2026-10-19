# 2026-10-19 — 0206: a good board keeps its own plan

**Found in 0205's after-check** (0205 live 04:55 UTC). Timed on prod, read-only (`begin transaction read only … rollback`; every function `provolatile = 's'`), as one docked company that is not the owner's, in ONE session:

| ask | default plans | `force_custom_plan` |
|---|---|---|
| retsina board | 1,456 ms | 2,375 ms |
| reach_passage | 175 ms | 276 ms |
| martaban-jars board | 954 ms | 2,873 ms |
| reach_passage | **8,101 ms** | 268 ms |
| retsina board | **18,161 ms** | 2,379 ms |
| reach_passage | **7,938 ms** | 243 ms |
| barley / smoked-eel / rice-paper boards | (9.4–21.0 s in the first run of six) | 2,141 / 2,016 / 2,018 ms |

PL/pgSQL switched 0205's `reach_passage` statements to a generic plan after a few runs, and that plan is ~40× slower. PostgREST's pooled connections serve many asks each, so players met it after a handful of good switches. Before 0205 a board was 4.3–6.1 s.

**Fix:** `ALTER FUNCTION … SET plan_cache_mode = force_custom_plan` on `world.good_board` and `voyage.reach_passage`. Only `world.good_board` calls `reach_passage` (prod `pg_proc`, 2026-10-19), so arrivals and the merchants are untouched.

**After the push:** re-run the same six-board session timing without the `set local`; every board should hold near 2 s.
