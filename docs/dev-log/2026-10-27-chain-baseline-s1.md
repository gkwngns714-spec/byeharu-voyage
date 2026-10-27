# 2026-10-27: chain baseline S1, the builder and its proof job (dark)

> **This PR touches CI machinery:** it adds a workflow (`.github/workflows/chain-baseline.yml`) and
> one rule in `scripts/ci/select-specs.mjs`: `scripts/db/baseline/**` is **not** chain machinery.
> Like `world-guard.mjs` and `proofs/**`, it reads a database the chain already built and is in no
> snapshot key. No migration changes, no prefix key or snapshot moves, nothing touches prod.

Design: `docs/CHAIN_BASELINE.md` (#355). The owner approved it on 2026-10-27. This is slice S1 only.
The baseline is uploaded as an **artifact** and is **not committed**. No file is archived, and prod's
`schema_migrations` is untouched (that is S2).

## What was built

| file | what |
|---|---|
| `scripts/db/baseline/baseline.mjs` | `build` (pg_dump of D-chain + the repairs), `lines`, `pglite`, `compare`, `prod-lines`, `prod-compare` |
| `scripts/db/baseline/catalog.sql` | ONE pure SELECT: the catalog of the 4 game schemas, a line per object (schemas, relations, columns + defaults, constraints, triggers + `tgenabled`, routines, types, policies, the migration role's default ACLs). It runs the same way on prod and on every CI database |
| `scripts/db/baseline/default-acl-proof.sql` | 0018's rule checked by behaviour: probe functions in `world`, `public` and a non-game schema must not be executable by PUBLIC, anon or authenticated. Positive control: undo the rule on purpose, and the same check must see PUBLIC execute |
| `scripts/db/baseline/pglite-allow.txt` | the written PGlite-vs-Supabase differences, by section. A stale entry FAILS |
| `.github/workflows/chain-baseline.yml` | nightly 04:47 KST + dispatch (`chain: zero` is the gate; `snapshot` uses main's kept snapshot, for debugging). Not required, no PR trigger |

The baseline file: header (N, the D-chain digests), prelude, dump, repairs, closing self-assert.
- **Prelude:** 0001's shims copied VERBATIM out of 0001. pg_cron when the platform has it (0012's
  guard). The migration role's own default ACLs in the game schemas are cleared.
- **Dump:** `pg_dump --schema public/world/cmd/voyage --inserts --rows-per-insert=500` (PG 17.6).
  Dropped from it: 2 `\restrict` lines and the 12 `ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin`
  lines (they belong to the platform, which already has them, and postgres may not set them).
- **Repairs:** 5 explicit-default ACLs re-issued. 11 policy role lists put back in the chain's order.
  **0018's schema-less default ACL** rebuilt from D-chain's own row:
  `ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;`.
  The 9 pg_cron jobs, read from D-chain's `cron.job` with their active flags.
- **Closing self-assert:** a probe created after the rule must not be executable by PUBLIC, anon or
  authenticated (positive control included). `client_write_grants()` = 0 and
  `client_executable_writers()` = 0. All 134 tables hold the chain's row counts. Receipt:
  `baseline 0248 self-assert ok: …`.

## Defects the digest found while building (each one fixed, none hidden)

1. pg_dump writes a policy's `TO` list in pg_roles order, not the stored order. 11 policies written
   `to anon, authenticated` came back `authenticated, anon`. Repaired with an `ALTER POLICY … TO` in the chain's order.
2. The dump's `SET client_min_messages = warning` hid every notice after it, including the receipt.
   The tail now resets it.
3. A volume restored from a snapshot survives `supabase stop --no-backup`, so D-base silently booted the
   OLD database. The job now deletes the volume, and fails if `start` says "from backup".
4. pg_dump also emits the platform's `supabase_admin` default ACLs, and postgres may not set them
   (42501). They are dropped and listed in `build.json`.

## The gate: two from-zero runs on the same chain (head 0248, 237 files, commit b84f0ff / d800c45)

| | run 40510624409 | run 40510679437 |
|---|---|---|
| D-chain = D-base, exact (catalog, every row incl. uuids and clocks, sequences, ACLs, policies, default ACLs, roles, cron) | EQUAL | EQUAL |
| default-ACL proof (2 markers) + proof 03 (8+5 markers) on D-base | PASS | PASS |
| D-base = D-pglite (stable rows, catalog), beyond the allow-list | EQUAL | EQUAL |
| PGlite receipt (`baseline 0248 self-assert ok: …`) | 134 tables / 238,502 rows | 134 tables / 238,492 rows |
| **catalog digest** | **f50c3f9e4b80a0e61dab46e61913c794c4746611a9f2293fdb226bf183aef29a** | **f50c3f9e4b80a0e61dab46e61913c794c4746611a9f2293fdb226bf183aef29a** |
| cron digest | d8fa17bf…5fe5 | d8fa17bf…5fe5 |
| rows_stable digest | 7fe32102…e5f0 | 633d9942…73c7 |

**The catalog digest is the same, and it is also the same on all four snapshot-mode runs.** The
row digest is NOT the same, and it cannot be: **the chain's own seed state is random.** It changes
from one from-zero apply to the next even with uuid and clock columns dropped. 14 tables differ:
- `world_config` (the world secret);
- `port_goods`, `price_history`, `players`, `ships`, `orders`, `ledger`, `events`,
  `trade_contracts`, `stats_live`, `captain_state`, `captain_active`;
- `active_buffs` (23 rows vs 26 in a snapshot-built chain) and `fitted_units` (2,526 vs 2,557);
- plus `treasury_flows_id_seq`.

So there is no row digest two applies could share. Each run's baseline is exactly ITS chain
(the exact digest, uuids included, is equal D-chain vs D-base in every run). That is the property S2
needs.

## Prod: the catalog diff (read-only)

`supabase db query --linked -f scripts/db/baseline/catalog.sql` (one SELECT, pg_catalog, stable
functions only, ~4.5 s). It returns 2,562 lines, the same count as the chain. Compared with
`baseline.mjs prod-compare` against D-base of both gate runs:
**EQUAL after two named platform normalisations, nothing else.**
1. **service_role grants in public (650 ACL items).** Prod's stock `postgres` default privileges give
   `service_role` everything (`D postgres public r {…,service_role=arwdDxtm/postgres}`). A fresh CLI
   2.114 Supabase gives `Dxtm` / `w` / nothing. The chain never names service_role there, so every
   table, sequence and function in public differs by it.
   **No migration causes this, and no fresh environment (chain or baseline) has prod's service_role
   grants.**
2. `public.forbid_mutation()`: prod writes out its ACL as exactly the default
   (`{=X/postgres,postgres=X/postgres}`), the chain leaves it NULL. They mean the same.

And one thing catalog.sql reads on purpose: **0076 writes the instant it applied into
`voyage.assert_paths_water`'s body** (its roadstead cutoff, `now()::text`). Every apply carries a
different literal: prod has 2026-09-04 09:09:59 UTC, each CI run has its own time. The catalog line
reads a timestamptz literal in a body as `'<applied>'`. The exact digest still compares that body
byte for byte, D-chain vs D-base.

Not done in S1: the design's seed-data-vs-prod check via `world-guard.mjs` (the static tables).

## Measured

| step | time |
|---|---|
| D-chain from zero (`supabase start` applying 237 files) | 50m17s / 64m47s |
| D-chain from main's snapshot + `migration up` (debug mode) | 84–101 s |
| pg_dump (inside the db container) | 1.1–1.5 s, 49.6 MB |
| build step total (dump + repairs + row manifest) | 6 s; baseline 49.6 MB |
| D-base: fresh `supabase start` applying the baseline as its only migration | 52–71 s for the whole step (stack boot included) |
| D-pglite: load into PGlite + preamble | 4.6–6.5 s (step with lines: 17–20 s) |
| whole job, from zero | 53m01s / 67m40s |
| whole job, snapshot mode | ~6 min |

## What S2 needs to know

1. **Freeze deploys while S2 runs**, and take N = prod head at that moment. 0249 may land first.
   The builder takes whatever the head is.
2. **Commit the baseline from a from-zero run of the exact N**, not a snapshot-mode run. Snapshot runs
   pass the same gates, but their seed rows are a different random sample.
3. **The committed baseline freezes ONE random sample** of the chain's seed state, including a
   `world_config` world secret (a dev one, not prod's). After S2 every fresh environment gets the
   same seeds, where today each gets its own. Decide whether a fixed dev secret in git is acceptable,
   or have the baseline regenerate it at load (it is in `world_config`).
4. **The tail check was not run**: N = head, so the tail is empty. S2's gate "disposable-chain green
   on baseline + the next file" is its first real test.
5. **The CLI stores a migration's statements** in `supabase_migrations.schema_migrations.statements`.
   A 50 MB file is stored on every fresh Supabase; prod never applies it (it already records N).
6. **The PGlite appliers** (`src/lib/db/applyChain.ts`, `scripts/db/apply-chain.mjs`) must accept the
   file: `SET` lines and a 50 MB single `exec`. `baseline.mjs pglite` already does this, in 5 s.
   Their receipt floor matches `self-assert ok:`, and the baseline prints one.
7. **service_role's grants on prod differ from every fresh Supabase** (above). They are not a
   baseline defect. If S2 wants prod = fresh, that needs a migration.
8. Moving `contentLines()` to `scripts/db/digest.mjs` (S3) should fold catalog.sql in as its catalog
   half. Today the two overlap on routines, relations, policies and default ACLs.
