# A realm reads its own harbours (migration 0336, performance only, no behaviour change)

Found by the main session while W7 (`convoy_rich_enabled`, 0324) waits to be lit: `public.cargo_origins` asks `public.crown_call_room` of every harbour in the world before it asks whose the harbour is. Lit, it takes a large part of the cargo job's minute (figures below). This slice moves the realm test ahead of the room test. It changes the plan and not one row of any answer.

**State: built, dark, PR open, not merged, not deployed.** `convoy_rich_enabled` is false and stays false. No switch, knob, table, job or other function is touched. One function is re-cut, by one hunk.

## The cause

`public.cargo_origins(p_nation)` (0324, `supabase/migrations/20260818000324_rich_cities_send_the_ships.sql:147-169`) is `stable`. Its lit arm reads the harbours of one realm. The planner runs it like this (prod, ESP, the biggest realm; the main session's `EXPLAIN ANALYZE` of 2026-11-07 about 01:45 UTC):

```
Seq Scan on ports h  (actual time=7.014..325.219 rows=27 loops=1)
  Filter: ((kind = 'HARBOUR') AND (crown_call_room(id) > 0) AND (port_nation(id) = (InitPlan 1).col1))
  Rows Removed by Filter: 233
Planning Time: 5.399 ms
Execution Time: 366.538 ms
```

`crown_call_room(id) > 0` is tested before `port_nation(id) = ...`, so the room (a read of the purse and its unrolled flows) is worked out for all 246 harbours, and the realm is tested afterwards. I did not look for why the planner prefers that order. The fix does not depend on it: it fixes the order by structure.

Who calls it when W7 is lit, from the main session's reading of the cargo job: `public.cargo_rebase_to` (0324:250) once for every idle ship (about 64 ships in the first five minutes), and `public.tick_cargo_ships` through `public.cargo_homes` (0324:181) ten times a minute; `public.cargo_ships_commission` reads it once a run too (0324:513). Measured by the main session: one call 343 to 1,022 ms, 2.4 to 9.7 s a minute for the ten great powers, 22 to 65 s in the first lit minutes, for a job that must fit its minute (fail line 55 s). Those figures are the main session's. I did not repeat them.

## The fix, one hunk

The realm test goes into a select of its own, closed with `offset 0`, so the planner cannot fold it back into its parent. It runs first; `public.crown_call_room` is then asked of the realm's own harbours only.

```
before                                              after
from public.ports h                                 from (select p.id, p.code from public.ports p
cross join lateral (select crown_call_room(h.id))        -- 0336 comment
where h.kind = 'HARBOUR'                                 where p.kind = 'HARBOUR' and public.port_nation(p.id) = p_nation offset 0) h
  and public.port_nation(h.id) = p_nation           cross join lateral (select crown_call_room(h.id)) x
  and x.room > 0                                    where x.room > 0
  and exists (course ...)                             and exists (course ...)
```

The order (`room desc, code`), the limit (`convoy_rich_ports`), the course test, the room test and the fallback to the capital are the same lines as before. The off arm (`array[realm_capital]`) is untouched. ACL, `stable`, `security definer` and `search_path` are exactly as live (`{postgres=X/postgres,service_role=X/postgres}`).

## Measured

**Prod, planned and not run** (`plan-old.sql`, `plan-new.sql`: a plain `EXPLAIN`, never `ANALYZE`, run by me 2026-11-07 against head 0335):

```
OLD  Aggregate (cost=165.12..165.13)                          NEW  Aggregate (cost=99.74..99.75)
       -> Seq Scan on ports h                                       -> Subquery Scan on h
            Filter: (kind = 'HARBOUR') AND                               Filter: (crown_call_room(h.id) > 0)
                    (crown_call_room(id) > 0) AND                        -> Seq Scan on ports p
                    (port_nation(id) = (InitPlan 1).col1)                     Filter: (kind = 'HARBOUR') AND
                                                                                      (port_nation(id) = (InitPlan 1).col1)
```

The old plan is the one the main session measured (same shape, same cost 165.12). In the new plan the realm filter stands on the inner scan, and the room filter on the node above it, which sees only the realm's rows.

**Prod, run by the main session, ESP, three runs each:** old 343 / 411 / 1,022 ms, new 75 / 84 / 152 ms, and the two arrays equal. Mine to add: I did not run `EXPLAIN ANALYZE` on prod, because the repo's `CLAUDE.md` says never. If the owner wants my own timings, that rule is the one-time thing to lift.

**Prod, live data, all ten great powers** (`equal.sql`, a pure `SELECT` of stable functions, about 10 s): the old shape and the new shape, written out as queries, give the same array for every realm: `realms 10, unequal 0, empty 0`. The lists, in order: ENG ARP VAR TRO; ESP PLO PAN SVQ; FRA GOA NAN MRS; JOS ZAN BUS HOR; JPN SAK HOI TSU; MNG MAL BNT PTT; MUG BSR KIL SRT; NLD COP ROT VIS; OTT VLL REY DBR; PRT OLD LIS ISL. (The function itself answers the capital today, because the switch is off; this compares the two shapes of the lit arm.)

**Local, the same planner (PGlite is Postgres 18 compiled to wasm), ESP, 40 of the world's 246 harbours, `--cost`:** the plan text is the same as prod's. Calls that `public.crown_call_room` receives in one lit read: **0324's body 274, 206 of them for harbours of other realms; the fenced body 68, none for another realm.** (The 68 are 40 in the filter and 28 for the sort key: a harbour that passes is asked twice. Computing the room once inside the fence would halve that. It is not built: the shape measured on prod is the shape shipped.) Local clock, two runs on a busy PC: 35.3 and 64.9 ms against 11.3 and 21.7 ms. The calls are the portable figure; the milliseconds are only a local reading.

## What is pinned, and how

The migration's own self-assert (45 s budget, 131 to 199 ms on the local world):

1. The hunk occurs once in the live body, the new hunk once in the new body, and the new body reverses to the pre-image byte for byte.
2. No other function moved (md5 over every function of `public`, `cmd`, `world`, `voyage`); ACL, volatility, definer and config of `public.cargo_origins` unmoved; it is still `stable`.
3. **The fence stands in the live body** (`offset 0) h` must be in it). See "What no result can see" below.
4. A probe realm of its own rolled-back rows (two nations, eight harbours and a sea place, five courses, nine purses), the switch set inside the transaction. The OLD body is the live pre-image itself, renamed into `pg_temp` and never retyped, so the reference cannot drift from what prod ran. Five scenes, each held to the OLD body and to the answer it was built to ask (a scene whose OLD answer is not the designed one fails as "proves nothing"):

   | scene | switch | limit | answer | what it can catch |
   |---|---|---|---|---|
   | dark | off | 9 | the capital | the off arm, a switch ignored |
   | all | lit | 9 | QYC QYD QYA QYE QYB | order by room then code, a tie, the room test (room 1 in, room 0 out), the course test at either end, another realm's richer harbour out, a richer sea place out, a richer harbour on no course out |
   | cut3 | lit | 3 | QYC QYD QYA | the limit; the inner order, which shows only where the limit cuts |
   | cut1 | lit | 1 | QYC | the limit cutting a tie by the lower code |
   | none | lit | 3 | the capital | the fallback when no harbour has room |

5. The probe left no row (ports, nations, courses), no `world_config` row moved (md5 with `updated_at`), and the run took under 45 s.

Proof 43 (`scripts/db/proofs/43_a_realm_reads_its_own.sql`, run by CI's "the rest" leg, which takes every proof but 02 and 12 by construction), four markers on the real chain:

- `OF_DARK`: the switch off, ten realms, every origin the capital, with purses that would have said otherwise.
- `OF_SAME`: lit, every great power, limits 1, 2, 3 and 5, spread purses, a tie, a bare realm (Joseon): the same array as 0324's statement (typed in the proof as the reference).
- `OF_SCENES`: the same probe scenes as the migration, with the explicit answers.
- `OF_FENCE`: **the count.** A `stable` wrapper notes each harbour `public.crown_call_room` is asked about. The fenced read never asks about a harbour of another realm (68 calls for Spain's 40 harbours); 0324's statement does (282 calls, 214 for others; the proof's world also holds the eight probe harbours), which is the positive control that lets the count tell a fence from none.

## Runs (this PC, prefix cache, nothing from zero)

- `node scripts/ops/harness/origins-fence/proof-0336.mjs --with=19,20,30,32,35,36 --cost`: **red first** (proof 43 with no file fails, at `OF_FENCE`, with 282 calls and 214 outside: the other three markers pass on the unfenced body, which is the point); **dark parity** (`rich-cities/dark-scene.sql` 15 lines and `armed-cargo/dark-scene.sql` 5 lines, equal before and after); the real file and proof 43 green; proofs 19, 20, 30, 32, 35, 36 green on the file; **46 mutations red, 0 wrong**.
- `node scripts/db/proof.mjs 43_` (the official runner, on the final file): chain of 320 migrations, 320 receipts, world guard ok, `4/4 PASS markers in 3.6 s`; `18_` on the final file: 6/6. `32_`, `35_` and `36_` (13/13, 9/9, 17/17) went through the same runner on the file as it stood before one last cleanup (the probe no longer writes `earned_day`, so the self-assert no longer names `world.game_day`); that change touches no applied function, and the harness above ran the three again on the final file.
- `tsc --noEmit` and `tsc -b`, `node --check` on each of the three `.mjs` files (`eslint` was run on them too, but the repo's config lints only `.ts` and `.tsx`, so it had nothing to say about them), `tests/duplication.spec.ts` and `tests/sections.spec.ts` (19 tests, including "every migration proves itself" and "a migration that re-cuts declares the supersede"), `db:check-versions`: all clean.

### The mutations (`scripts/ops/harness/origins-fence/mutations-0336.mjs`)

Forty-six, each required to fail for its own reason. 29 are `SELF`: injected into the file right after it has cut the function and before it judges it, so the self-assert faces a function that is wrong. 17 run after the file and only proof 43 can see them.

- **The probe scenes of the self-assert caught all 16 wrong live bodies**, each by the scene shown in the table: the realm test dropped; another realm instead of this one; the sea-place test dropped; the course test dropped, or counted only at its start, or only at its end; the room test dropped; room 1 not counting; the roster ordered by the least room (only `cut3` sees it: the outer aggregate re-sorts whatever the limit left); a tie cut at the higher code (only `cut1`); the limit always 3; no limit; the limit read from the wrong knob; no fallback; the off arm not the capital; the switch ignored. Proof 43 caught the same 16 after the file (`OF_SAME`, `OF_SCENES` or `OF_DARK`).
- The file's machinery: the body not what the file was cut against; a hunk that does not reverse; the function turned `volatile`; a grant to `anon`; its `search_path` moved; another function moved; a knob moved; a nation left behind by the probe; a probe purse that drifts from the room it was built for; an OLD reference that is not the pre-image; a scene run with the other switch. All red.
- **"Remove the fence" cannot change any result, and no scene of equality sees it.** It is a plan. It is pinned by the text test in the self-assert (red when the fence is taken out of the hunk's text or out of the live body) and, on the real engine, by proof 43's call count (red after the file). The cost evidence above is what shows the fence is worth having; the pins only hold it in place.

## What is NOT proved

- **The cost on prod after the deploy.** The main session reads that. What I have is the plan on prod, the calls on a local world, and the main session's own timings.
- **The self-assert's time on prod.** It reads the OLD body lit four times (about 0.34 to 1.0 s each, by the main session's figures) and scans every function twice: a projection of 2 to 5 s against a budget of 45 s, not a measurement.
- **PGlite is not prod's Postgres.** The plan text matches and the calls are the same kind of count, but the real engine for this file is CI's `disposable-chain`.
- **The lit function itself on prod data.** It cannot run there (the switch is off). `equal.sql` compares the two shapes as queries on live data, which is the same statement without the function around it.
- **One mutant no scene can see:** dropping the code from the outer `array_agg(... order by y.room desc, y.code)`. The inner select already hands the aggregate its rows in `room desc, code` order and the aggregate sorts them stably in practice, so the answer is the same. I did not build a scene for a difference that cannot be seen.
- Proof 41 (red locally on this PC, known, before this work) was not run here; `tests/db.chain.spec.ts` was not run locally. CI runs both.

## The same pattern elsewhere (named, not touched)

- **`public.crown_donors`**: `supabase/migrations/20260818000335_a_realm_pays_for_its_navy.sql:99-102`. `cross join lateral (select public.crown_call_room(h.id) as room)` with the realm test (`public.city_capital(h.id) = p_capital`) in the same `where`. Live today.
- **`public.crown_call`**: its text no longer holds the pattern. 0335 lifted the donor read out of it into `public.crown_donors`; the live body now reads `from public.crown_donors(k.cap)`. The pattern's older home is `supabase/migrations/20260818000307_a_capital_draws_on_its_nation.sql:144-148` (frozen history, the pre-image that 0335's hunk 2 quotes). So of the two the brief named, only `crown_donors` carries it now. The other callers of `crown_call_room` (`cargo_load_room`, and `crown_call`'s per-donor `v_c := least(...)`) ask about one harbour and scan nothing.
- When `crown_donors` gets the same fence it is its own slice with its own proof; `crown_call_share` 0 stops both.

## Decided by default

- One hunk, one function. The comment that explains `offset 0` lives inside the body, so a later tidy cannot remove the fence unseen, and the self-assert would catch it if it did.
- The OLD reference is the live pre-image renamed, not a second copy of the rule in the file. Proof 43 types 0324's statement once, as the oracle it is held to, and says so.
- The probe sets `convoys_enabled` and `convoy_rich_enabled` inside a rolled-back sub-transaction (the brief asked for the switch set inside the transaction). The `world_config` md5 afterwards proves nothing stayed changed.

## PROD CHECKS

Run from the main clone (`cd ~/dev/byeharu-voyage`), each one read-only statement:

- **Before deploy:** `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/origins-fence/before.sql`. Run by me 2026-11-07, head 0335:
  `{"head":"20260818000335","hunk_times":1,"body_md5":"def287f3dddbd58407122cee2ca04f5b","fence_in_body":false,"volatility":"s","definer":true,"acl":"{postgres=X/postgres,service_role=X/postgres}","config":"{\"search_path=public, pg_temp\"}","overloads":1,"switch":false,"rich_on":false,"probe_codes":0}`
- **After deploy:** `scripts/ops/harness/origins-fence/after.sql`. Wanted: head `20260818000336`; `body_is_new` true (`body_md5` `81997c67fc00c74f748aeab9c0bf2695`, the live body of `before.sql` with the one hunk in it and nothing else); `hunk_old_times` 0; `fence_in_body` true; `volatility` `s`; `definer` true; `acl`, `config` and `overloads` as above; `switch` false; `rich_on` false; `off_capital` 0; `probe_codes` 0. Dry run before the deploy (the shape and the types run; the values are the old ones): `body_is_new` false, `hunk_old_times` 1, `off_capital` 0, the rest as above.
- **Plan and equality, any time:** `plan-old.sql`, `plan-new.sql` (planned, not run) and `equal.sql` (`realms 10, unequal 0`).
- `bash scripts/ops/health.sh`.

## Rollback

Forward, owner only, a new migration: swap this file's hunk (new for old). No data, knob or switch moved, so there is nothing else to undo.

## Rows for the coordinator (not written here)

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-07 **A REALM READS ITS OWN HARBOURS - migration 0336, DARK, PR open, NOT deployed, follows 0335 (prod head 0335):** public.cargo_origins asked crown_call_room of all 246 harbours before it asked whose they were (prod plan: Filter crown_call_room(id) > 0 before port_nation(id) = ..., 343 to 1,022 ms a call for ESP); one hunk, offset 0, puts the realm first; same answer (equal.sql: 10 realms, 0 unequal), plan on prod 165.12 -> 99.74, calls on a local world 274 -> 68. W7 can be lit after it deploys without the cargo job missing its minute. crown_donors holds the same pattern (0335:99-102), not touched. Dev-log docs/dev-log/2026-11-07-origins-fence.md.`
