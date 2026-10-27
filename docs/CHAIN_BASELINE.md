# The chain baseline — fold 0001..N into one file (DESIGN, not built)

Status: design for the owner, 2026-10-27. Nothing here is built. Prod head at writing: **0247**
(236 rows in `supabase_migrations.schema_migrations`, 0001..0247 — read-only query, 2026-10-27).

## 0. The problem, in numbers

| | today |
|---|---|
| chain | 236 `.sql` files, 19 MB (`supabase/migrations/`) |
| from-zero apply | ~47–50 min on CI's disposable Supabase (docs/CI.md, run 39040210150); ~36+ min on PGlite locally |
| machinery that exists only to avoid it | prefix cache (`scripts/db/prefix-cache.mjs`, 602 lines), Supabase volume snapshots (`scripts/ci/supabase-snapshot.sh`, `choose`/wait logic), the "PR CI never from zero" law (docs/CI.md), `src/lib/db/frozenAsserts.ts` (#353), `tests/frozenChain.ts` (`GROWTH_SPLIT`), `growth-house-*` / `world-image-*` / `chain-prefix-*` caches, the nightly from-zero net |
| failures it causes | 0019 random-roll flake, 0108 stopwatch, shared-cache pruning, stale world images, PRs refused while main's run saves its snapshot |

A baseline turns "replay 236 files" into "load one file + the tail". From zero becomes cheap, so
every cache that exists to avoid from-zero becomes optional.

## 1. Producing the baseline so it is exactly the chain's state at N

### 1.1 Source: apply the chain once, then dump it — not a dump of prod

| option | schema | data | verdict |
|---|---|---|---|
| A. `supabase db dump --linked` (prod) | prod's real catalog | **prod's data is live**: 1,897 MB in the four game schemas (read-only size query 2026-10-27) — players, NPC fleets that moved, drifted `port_goods` prices, ledger, price history. Not seed data. | **No** as the source. Also: `db dump` runs `pg_dump` in Docker (not on this PC) and its passwordless path creates a temporary login role on prod ("Initialising login role…", the same as every `db query --linked`). Not run for this design. |
| B. apply 0001..N from zero on CI's disposable Supabase (what the nightly already does), then `pg_dump` that database | the chain's catalog | the chain's own seed state (ports, goods, ships, sea raster, NPC roster as 0105.. seeded it) | **Yes.** It is what every fresh environment gets today, byte for byte, just pre-computed. Prod is the *comparison target* (1.3), not the source. |

Why not prod's data: a fresh database must start where the chain starts it, not where 30 live
players and the closed economy have pushed prod since. Prod's uuids also differ from a fresh
apply (`gen_random_uuid()` keys, `src/lib/db/rescue.ts` header) — that is true today and stays true.

### 1.2 What goes in, what stays out

| in the baseline | how |
|---|---|
| schemas `public`, `world`, `cmd`, `voyage`: tables, constraints, indexes, views, sequences (with positions), functions, triggers, policies, RLS flags | `pg_dump --schema=public --schema=world --schema=cmd --schema=voyage` on the chain-applied DB, owners kept (SECURITY DEFINER functions run as their owner) |
| every GRANT and REVOKE as they stand at N, incl. the lockdown 0001/0018 built and every later publish migration's REVOKE (memory: prod grant drift) | `pg_dump` emits the final ACLs (`GRANT`/`REVOKE` lines; 728 in the trial dump) — the *end state*, not the history |
| `ALTER DEFAULT PRIVILEGES` state | per-schema entries: the dump emits them. The **schema-less** entry (0018's "no function executable by PUBLIC") it does **not** — measured, section 4 — so the builder writes it explicitly and the closing self-assert proves it behaviourally |
| reference / seed rows (ports, goods, `port_goods`, `sea_leg_asks`, ship classes, skills, gear, NPC houses/fleets the chain seeds, `world_config` knobs) | data section of the same dump. Rows are what the chain left; `scripts/db/world-guard.mjs` must pass on the loaded baseline exactly as on the chain |
| the PGlite shims | 0001's conditional blocks copied **verbatim** as the baseline's prelude: `auth.uid()` shim only `if to_regprocedure('auth.uid()') is null`, `pgcrypto` attempt with fallback. The `auth` schema itself is **not** dumped (on Supabase it is GoTrue's) |
| pg_cron jobs | not in a schema dump (`cron.job` lives in `cron`). The baseline ends with ONE guarded block in 0012's shape (`if exists pg_available_extensions 'pg_cron'`), scheduling the 9 jobs prod has now — `arrivals` (`1 seconds`), `buff-calendar`, `city`, `cron-purge`, `drift`, `influence`, `price-snapshot`, `reconcile`, `stats` (read-only `select jobname, schedule from cron.job`, 2026-10-27) — read from the chain-applied Supabase's `cron.job`, never retyped. Jobs start inactive, as the chain leaves them, and `public.wind_the_clock()` (0078) remains the one switch |
| one closing self-assert | the house rule (README §3): `client_write_grants()` = 0, `client_executable_writers()` = 0, row counts of the seed tables equal the manifest, and a `raise notice '… self-assert ok: …'` receipt so the receipt floor in `apply-chain.mjs` still holds |

| NOT in the baseline | why |
|---|---|
| `auth`, `storage`, `realtime`, `extensions`, `cron`, `vault`, `supabase_migrations`, `graphql*` | platform-owned; Supabase creates them |
| roles (`anon`, `authenticated`, `service_role`, `supabase_admin`) | platform-owned on Supabase; `scripts/db/supabase-preamble.sql` keeps modelling them on PGlite |
| prod's player/economy rows, `cron.job_run_details`, price history beyond the seed | live state (1.1) |
| any prod-only hand-made object | if 1.3 finds one, it is a finding, fixed by a migration before the cut — never baked in silently |

Format: `pg_dump --inserts --rows-per-insert=500` (one file both Postgres and PGlite execute;
PGlite's `exec` cannot read `COPY … FROM stdin`). LF only, so `assertChainIsSane` still passes.
Header in the house shape (README §2): what it replaces, the N it equals, the digests below.

### 1.3 Proof: three databases, two empty diffs

Build, in one CI job: **D-chain** = 0001..N applied from zero on Supabase; **D-base** = the baseline
loaded on a fresh Supabase; **D-pglite** = the baseline loaded on PGlite + preamble.

| check | between | tool | must be |
|---|---|---|---|
| schema diff | D-chain vs D-base | `supabase db diff` (migra) between the two local DBs | empty |
| catalog + content digest, exact | D-chain vs D-base | `contentLines()` in `scripts/db/prefix-cache.mjs:247` — every row, sequence, function body md5, relation/function ACL, RLS flag, policy, default ACL. Already proven as the snapshot round-trip check | equal (the dump came from D-chain, so even uuids match) |
| same digest, `stableOnly` | D-base vs D-pglite | same function, uuid/clock columns dropped | equal except the lines PGlite cannot have (pg_cron, platform roles) — the allowed list is written down and fails if it grows |
| catalog digest vs **prod** | D-base vs prod | the catalog half of `contentLines()` (functions, ACLs, relations, policies, default ACLs, namespaces), run on prod through `supabase db query --linked`: plain `pg_catalog` selects + `pg_get_functiondef` (STABLE). No table rows, no volatile call, no EXPLAIN | equal. Counts already agree in the trial (section 4): tables public/world/voyage 127/5/1 and routines public/cmd/voyage/world 364/90/55/94 in both the chain dump and prod — counts only, not yet a digest |
| seed data vs prod, static tables only | D-base vs prod | `world-guard.mjs` is the authority for "the world equals `data/*.json`"; run its read-only queries against prod for the static tables (ports, goods, ship lines, skills, gear) by code, excluding columns the game owns (crew_pool, prices, stocks) | equal |
| the tail still applies | D-base + N+1..head vs D-chain + N+1..head | the same exact digest | equal |

The prod-catalog check is the one that can find something new (0003 was once edited after prod
applied it — world-guard header). A red there is fixed **before** the cut by an ordinary migration.

## 2. Prod's `schema_migrations`

Supabase CLI 2.120 rules that matter:
* `db push` refuses when prod's history holds a version with **no local file** ("Remote migration
  versions not found…", it tells you to `migration repair`).
* It applies local files whose version prod lacks; one *older* than prod's head needs `--include-all`.
* `migration squash` exists but dumps **schema only** (drops inserts and cron) — it cannot make this baseline.

Plan:
1. The baseline file takes **N's own version**: `supabase/migrations/20260818000NNN_the_world_as_it_stood_at_NNNN.sql`.
   Prod already records N, so `db push` sees it as applied and never runs it on prod.
2. Files 0001..N move to `supabase/archive/migrations/` (outside the directory the CLI reads),
   with `CHAIN.md` and the breaktests/generators that replay them. History stays in git and on disk.
3. Before repair, save prod's history rows (`select version, name from supabase_migrations.schema_migrations`)
   to `supabase/archive/schema_migrations-at-NNNN.json`.
4. `supabase migration repair --linked --status reverted <0001 … N-1>` — one call. It deletes those
   bookkeeping rows only; no schema object is touched. Prod keeps N.
5. Gate: `supabase db push --linked --dry-run` prints **nothing to apply**, and
   `supabase migration list --linked` shows local = remote = {N}.
6. `bv-deploy.sh` keeps working: it reads `max(version)` and versions > 0100 (only N and newer remain).

Rollback of this step: `migration repair --status applied` the saved versions (rows return) and
`git revert` the move. Nothing in prod's schema changed, so nothing else to undo.

## 3. What happens to each piece of machinery

| piece | fate | why |
|---|---|---|
| `scripts/db/prefix-cache.mjs`, `byeharu-chain-prefix`, `tests/db.prefixCache.spec.ts` | **delete** after S3 (keep `contentLines()` — move it to `scripts/db/digest.mjs`; it becomes the baseline proof) | applying baseline + tail is minutes; nothing to cache |
| `scripts/ci/supabase-snapshot.sh`, the `choose`/wait/usable steps, `SNAPSHOT_WAIT_SECONDS` | **delete** | disposable-chain applies baseline + tail from zero on every run |
| the "PR CI never from zero" law (docs/CI.md) | **retired, satisfied by construction**: from zero *is* fast. Owner to confirm the wording | the law's goal (fast CI) is kept; its mechanism is no longer needed |
| `src/lib/db/frozenAsserts.ts`, `tests/db.frozenAsserts.spec.ts` | **delete** | both patched files (0019, 0108) are archived; the baseline has no probes |
| `tests/frozenChain.ts` (`GROWTH_SPLIT` = 0041) | **replace**: the "frozen prefix" is the baseline itself | |
| growth test ("the world grows under a live house"), `growth-house-*` cache | **keep the test, delete the cache**: house on the baseline, then N+1..head applied under it | the property still matters for every new migration |
| nightly from-zero net | **simplify**: every run is from zero now; keep one nightly as the same job on main (cheap) | |
| `world-image-*` cache, `scripts/db/build-image.mjs`, the image in `dist/` | **keep the image** (browser boot), **drop the prefix dependency**: image = baseline + tail, built every `npm run build` | |
| self-asserts and receipts of 0001..N | **archived with their files**. The baseline carries one closing self-assert; new files keep the full convention | |
| `scripts/db/breaktest-00xx.mjs`, `build-npc-0098/0105.mjs` (`stopBefore`) | **archive** | they replay files that no longer run |
| `world-guard.mjs`, proofs (`scripts/db/proofs/*`), `supabase-preamble.sql`, `check-versions.mjs`, `fingerprintChain`, `rescue.ts`, `assertChainIsSane`, version-uniqueness check | **keep, unchanged** | they judge the result, not the route |
| `select-specs.mjs` rule "edited/deleted/renamed migration → full suite" | **keep**; add: an edit to the baseline file is refused outright (it is applied history) | |

One-time side effect: `fingerprintChain()` moves, so every **local** PGlite save is demolished once
(the rescue runs and says so). Cloud players are not affected.

## 4. PGlite

* **Can it load it?** Yes, measured below. Roles come from `supabase-preamble.sql` (unchanged);
  `auth.uid()` from the verbatim 0001 shim; `pgcrypto` fallback as 0001; pg_cron absent → the
  guarded block reports and schedules nothing (0012's posture, unchanged).
* **Measured on this PC, 2026-10-27** (PGlite 0.5.5 + `@electric-sql/pglite-tools` 0.4.5, scratch dir;
  input: the local prefix snapshot of 236 files, `preamble-p0236`):

| step | result |
|---|---|
| restore the 236-file data-dir snapshot (the source) | 2.0 s |
| `pg_dump` of public/world/cmd/voyage/auth (single-row INSERTs; 238,515 rows, 139k of them `port_goods`) | 1.5 s → **57.9 MB** of SQL |
| load that dump into a fresh PGlite + preamble (one `exec`) | **17.3 s** (after dropping the dump's `CREATE SCHEMA public`, which PGlite already has) |
| `checkpoint` + `dumpDataDir` of the loaded DB (= the world image) | 3.8 s, 36 MB gz |
| `contentLines()` source vs loaded | every table's rows, every sequence, every function body md5, policies, roles, namespaces **equal** |

Two differences the digest found, both fixed in the builder, not hidden:
1. **88 relations** (83 tables, 3 sequences, 2 views) whose ACL is owner-only (`{postgres=arwdDxtm/postgres}`)
   come back as `NULL`. pg_dump omits an ACL equal to the default, so effective access is the same;
   the builder re-emits the explicit ACL so the digest is exact rather than normalised.
2. **One real loss:** the schema-less default ACL `postgres - f {postgres=X/postgres}` — 0018's
   "no new function is executable by PUBLIC" — is **not emitted** by a `--schema`-filtered pg_dump.
   Without it every function N+1 creates would be PUBLIC-executable. The baseline must issue
   `alter default privileges for role postgres revoke execute on functions from public` itself, and its
   self-assert must check it behaviourally (create a probe function, `has_function_privilege`).
   This is exactly why the proof is a digest and not "it loaded".

* **Expected times** (from the above; CI numbers are estimates until S1 measures them):

| where | today (from zero) | baseline + tail |
|---|---|---|
| local PGlite build (`npm run build`, cold cache) | ~36+ min | **~20 s** world (17.3 s load + 3.8 s image, measured) + the tail's files |
| CI disposable-chain | ~47–50 min | est. 2–4 min (`supabase start` ~1.5 min + load; real Postgres loads INSERTs far faster than wasm) |
| CI pglite legs / world image | snapshot restore ~3 s when the cache fits; 36+ min when it does not | ~20–40 s every time (runner slower than this PC), no cache to miss |

## 5. Risks, rollback, slices, cost

| risk | guard |
|---|---|
| baseline differs from the chain in a way the digest does not see (e.g. a column default calling a function, a trigger's enabled state) | migra schema diff **and** the digest; add `pg_trigger.tgenabled`, `pg_attrdef`, `pg_constraint` lines to `contentLines()` in S1. The trial already caught one real loss (the global default ACL, section 4) |
| prod differs from the chain (a hand fix, an edited old file) — counts match, bodies/ACLs not yet compared | prod catalog check (1.3) is a gate; fix by migration before the cut |
| a deploy lands between dump and repair | freeze: S2 runs with no deploy in flight; N = prod head at that moment (0248 is fine — N is a parameter) |
| repair run against the wrong project / wrong versions | one command, versions generated from the archived JSON, `--dry-run` push before and after, ref checked = `olaquvizoavjeiricyxk` |
| an open PR adds an old-numbered file (< N) | `check-versions.mjs` already refuses; add "version must be > baseline" |
| PGlite and Supabase load the baseline differently | D-pglite digest check with a written allow-list |
| the archive is applied by someone | it is outside `supabase/migrations/`; the CLI never reads it |

**Rollback** at any slice: S1 is dark (artifact only). S2: `repair --status applied` + `git revert`;
prod's schema never changes. S3: `git revert`; the old caches rebuild from the archive (one 50-min run).

| slice | what | gate |
|---|---|---|
| S0 | this design | owner approves |
| S1 | `scripts/db/baseline.mjs` + a CI job (dispatch/nightly only): chain from zero → dump → D-base, D-pglite; all six checks of 1.3; baseline uploaded as an artifact, **not committed** | two green runs on different days give the same exact digest; prod catalog diff empty |
| S2 | the cut, at a quiet moment: commit the baseline as version N, move 0001..N to the archive, save history JSON, `migration repair`, dry-run push | dry-run empty; `migration list` = {N}; full Acceptance green on main; disposable-chain green on baseline alone |
| S3 | delete the machinery (section 3), rewrite docs/CI.md, keep one nightly | CI on a migration PR < 10 min end to end; local `npm run build` world step cold < 1 min + the tail |
| S4 (policy) | re-baseline when the tail passes ~60 files or its apply passes ~10 min | owner sets the threshold |

**One-time cost:** S1 ~4–6 agent-hours + ~4 CI runs (2 × ~55 min from-zero runs, 2 short);
S2 ~2 agent-hours + 2 CI runs, one 10-min prod window (one repair call, no schema change);
S3 ~4–6 agent-hours + ~3 CI runs. Total ≈ 10–14 agent-hours, ~9 CI runs.

**Ongoing savings:**

| | today | after |
|---|---|---|
| migration PR, disposable-chain | 2–5 min on a fitting snapshot; **47 min or a refusal** when none fits (#147) | 2–4 min, always |
| PR waiting for main's snapshot | up to 50 min (`SNAPSHOT_WAIT_SECONDS`) | 0 |
| local `npm run build` after a pruned cache | 36+ min, plus the 0108/0019 failures | ~20 s + the tail |
| nightly | ~50 min | ~5 min |
| code | ~1,100 lines of cache/snapshot/patch machinery + 3 specs | gone; one ~200-line builder |

## 6. Recommendation

**Do it — now, starting with S1 (dark).** Reasons: (1) every recent CI incident (0019 flake, 0108
stopwatch, pruned caches, stale images, #147's refusal) is a symptom of replaying history, and each
fix so far added machinery; the baseline removes the cause. (2) S1 touches nothing live and its
proof reuses a digest that is already trusted. (3) The only prod write is one bookkeeping
`migration repair`, reversible from a saved JSON, with no schema change. (4) The tail grows ~10
files a day; the longer it waits, the bigger the first from-zero run and the more caches to retire.
Do S2 only after S1 is green twice and the prod catalog diff is empty.

### Open questions for the owner

1. The law "PR CI never from zero" — retire it once from zero takes minutes, or keep the words?
2. Approve one `supabase migration repair --status reverted 0001..N-1` on prod (bookkeeping rows only, saved first)?
3. Local PGlite saves are demolished once at the cut (rescue runs). Acceptable?
4. Re-baseline policy (S4): by file count, by apply time, or by hand?
5. Archive location: `supabase/archive/migrations/` in this repo (proposed), or a tag only?
