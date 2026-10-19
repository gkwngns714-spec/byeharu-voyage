# CI — what runs on a pull request, and what runs on main

## The law — CI never rebuilds from scratch (owner, 2026-10-17; extended to main 2026-10-18)

The owner's order: *"avoid doing things from scratch"* in CI, made a law the same day: **a PR's CI
must NEVER rebuild from scratch.** Applying the whole migration chain from 0001 — on the disposable
Supabase, on PGlite for the proofs, or to build the world image — costs 30 to 50 minutes since 0105,
and every one of those files was already applied, green, by main's own run. On 2026-10-18 the owner
restated it for every run: *"CI never starts from scratch; always make CI fast; save everything you
checked"* — so **main builds on its own snapshot too** (point 3 below), and the from-zero apply is
one scheduled run a day. So on a pull request:

1. **Every world is built from a kept snapshot, or the job fails and says why.** It never falls
   back to a from-zero apply.
   - **disposable-chain** (`scripts/ci/supabase-snapshot.sh choose`): the keys of every snapshot
     that could fit are computed from the checkout (the key is the manifest's hash, one per prefix
     length), the repository's kept caches are listed, and the **longest kept prefix** this run may
     restore (main's or this PR's own ref) is restored **by exact key** — never "the newest".
     Before choosing it **waits, bounded** (`SNAPSHOT_WAIT_SECONDS`, 50 min), for main's
     migrations-apply-proof run on the PR's base commit when that run is still going and the base
     chain's snapshot is not kept yet. `usable` then judges the restored bytes as before. Nothing
     usable: the step *"The law — no from-zero apply on a pull request"* fails with
     *"no usable applied-chain snapshot for this chain — refusing to rebuild from zero on a PR;
     re-run after main's migrations-apply-proof finishes"*.
   - **pglite-gate, the acceptance builds (`npc-on-world`, every pool shard) and build.yml**
     (`scripts/db/prefix-cache.mjs`): the build or proof step runs with
     `BYEHARU_PREFIX_CACHE=required`, and a chain with no usable cached prefix **throws** instead of
     applying from zero. No wait is needed there: one `chain-prefix-*` / `world-image-*` entry holds
     the last **four** prefix lengths (plus one every 32), so the previous main entry still fits a
     chain that grew by up to three files, out of order or not, and main saves its entry minutes
     after a merge (the Supabase snapshot keeps one length per entry, which is why it needs the
     lookup and the wait).
2. **The one exemption**: a PR whose diff changed the chain machinery or an old file — exactly the
   set that runs the growth test (`select-specs.mjs`, `growth.run`: `src/lib/db/**`, `scripts/db/**` but
   not `scripts/db/world-guard.mjs`, `scripts/db/proofs/**`, nor the proof runner `scripts/db/proof.mjs` and its fixtures `proof-courses.mjs` / `market-fixture.mjs` — certifiers and the proofs, in no snapshot's key, 2026-10-18/19 —,
   the preamble, `package(-lock).json`, `vite.config.ts`, `tests/frozenChain.ts`, an **edited,
   deleted or renamed** migration). No kept snapshot can be expected to fit such a chain, so a
   from-zero apply is allowed there and **logged as a warning**. `select` prints the reasons.
3. **Main builds on its own snapshot (2026-10-18).** A push to main runs the same `choose` a PR
   runs — the longest kept snapshot that is an exact prefix of main's chain, by exact key, **without
   waiting** (`SNAPSHOT_WAIT_SECONDS=0`: the heavy self-asserts, 0105–0110, are inside every kept
   prefix, and applying a few more merged files costs less than waiting for a sibling run) — applies
   the merged files on it, runs every check, and **keeps the result** as the snapshot the next PR
   and the next main run restore. Main is never refused: with nothing usable it applies from zero
   and says so in a warning. Each push to main has its **own concurrency group** (per sha), so every
   merge's run completes and leaves its snapshot — with one shared group GitHub keeps only one
   *pending* run and cancels the rest, which is what happened to 10 of the 12 main runs between
   14:18 and 15:16 UTC on 2026-10-17. A push whose diff touches no database path skips both proof
   jobs, exactly as a PR does: its chain is byte-identical to the previous main commit's, whose run
   keeps that snapshot already. The PGlite legs and the acceptance / build / deploy world images on
   main already restored the previous main entry (`restore-keys`) before this; measured on run
   39040210150: 133 of 134 files restored in 3.2 s, one applied.
4. **The from-zero net is one run a day**, not every merge: the `schedule` in
   migrations-apply-proof.yml (`23 18 * * *` UTC = 03:23 KST), any `workflow_dispatch`, and a push
   to main whose diff changed the chain machinery or an old migration (the same `growth.run` set as
   the PR exemption). It applies the whole chain from 0001 on a fresh volume, against Supabase's own
   roles, and keeps its snapshot like any other run. **A red nightly is a red:** read it to the last
   error the same day; it means a kept snapshot and a from-zero apply of the same chain disagree, or
   a self-assert is non-deterministic, and either is the finding.

Why it exists: PR #147 (run 39029031472) started at 11:33 UTC, two minutes before main's run saved
the snapshot that matched its chain. The job restored "the newest" kept snapshot, which 0137's
out-of-order merge had made a non-prefix, and applied 132 files from zero for 47 minutes while five
other snapshots sat in the cache. A re-run at 12:21 restored 131 files and applied one in two
minutes. And why main joined it: main's from-zero apply was 47 of its 49 minutes (run 39040210150,
14:28 → 15:16 UTC), every PR since #149 waits for main's run on its base, and with several merges
an hour main's own runs cancelled each other while pending — so every PR waited on one 50-minute run
(docs/dev-log/2026-10-18-main-builds-on-its-snapshot.md).

When the law fails a PR: read the `choose` step (which snapshots were considered, whether main's
run was waited for and how it ended), wait for main's migrations-apply-proof run on the base to
finish, and re-run the failed jobs. If main's run itself is red, that red is the finding.

---

The owner's order, 2026-10-17: *"make CI shorter — CI tests only from where we made something new,
not the whole game."*

| Event | Acceptance (Playwright) | migrations-apply-proof |
|---|---|---|
| **push to `main`** | **every spec**, growth test included; verdict: passed == `playwright test --list` over all of `tests/` | **nothing** when the push touches no database path; otherwise all three pglite legs (on the previous main entry) and disposable-chain **on the longest kept snapshot, no wait**, keeping its result as the next snapshot; from zero only when the chain machinery or an old migration changed |
| **nightly schedule** (03:23 KST), dispatch | — (acceptance has no schedule) | all three pglite legs; disposable-chain **from zero** on a fresh volume — the net — keeping its snapshot |
| **pull request** | only the specs the diff can reach (below); verdict: passed == `--list` count of the **selected** files; every world build from a cached prefix or red (the law) | **nothing** when the diff touches no database path (below); otherwise `the rest` always, `ledger` / `merchants` only when the diff reaches their proof; disposable-chain on the longest kept snapshot, after waiting for main's run on the base — never from zero (the law) |

Main's full run is the safety net. After a batch of merges, check one full Acceptance run on main
before you call the batch done.

## A pull request that does not touch the database

`disposable-chain` is a required check on `main`. migrations-apply-proof therefore runs on **every**
pull request (no `paths:` filter since 2026-10-17; a workflow a filter keeps from running reports no
check at all, and the PR can never merge). Its `select` job decides, from the merge commit against
its first parent, whether the diff touches `supabase/`, `scripts/db/`, `scripts/ci/`, `src/lib/db/`,
`package.json`, `package-lock.json` or the workflow file. When it does not, `pglite-gate` and
`disposable-chain` are skipped by a job-level `if:` on that `db` output, in seconds; GitHub reports
a job skipped by its `if:` as success, and the required check is satisfied. The `select` job's log
says which it was and lists the diff. `disposable-chain`'s condition is `!cancelled() && … != 'false'`,
so a `select` job that failed cannot skip the required check — it runs the chain instead. Since
2026-10-18 a push to `main` is judged by the same diff (against `github.event.before`, the commit
main stood at): a merge that touches none of those paths skips both proof jobs there too, because
its chain is byte-identical to the previous main commit's, whose run keeps that snapshot. A push
whose previous commit GitHub does not name, a dispatch and the schedule have no diff and run
everything, from zero.

## Who decides

`scripts/ci/select-specs.mjs` decides, and nothing else does. Acceptance's `select` job runs it on the PR's
merge commit against its **first parent** (`--base HEAD^1 --head HEAD`). It writes `selection.json`,
which every shard and the verdict read, and it prints each selected spec with the rule that selected
it. The list appears in the `select` job's log and in its step summary. Run it locally against any diff:

```
node scripts/ci/select-specs.mjs --base origin/main            # the working tree vs main
node scripts/ci/select-specs.mjs --base <sha>^1 --head <sha>   # one commit
node scripts/ci/select-specs.mjs self-test                     # the positive controls
```

## The rules

The script header holds the exact patterns.

- **F, full suite.** Any of these triggers it: the Playwright configs, `package(-lock).json`,
  `tsconfig*`, `vite.config.ts`, `index.html`, `src/main.tsx`, `src/lib/db/**`, or
  `scripts/db/{build-image,prefix-cache,apply-chain}.mjs` and `supabase-preamble.sql` (the
  world-image pipeline). So does `tests/appReady.fixture.ts`, the readiness and skip gate that every
  browser spec relies on. An **edited, deleted or renamed** migration also triggers it, because an
  old file changing changes every world.
- **C.** A spec that changed is selected.
- **G, import graph.** A spec is selected if it imports a changed file, directly or transitively,
  through `tests/`, `src/`, `scripts/` or `data/`. A helper fixture (`seaFrame`, `mapWorld`,
  `npcOn` and so on) therefore reaches exactly the specs that import it.
- **N.** A spec that quotes a changed file's base name, for example to `readFileSync` it.
- **T.** A spec that walks a directory (`readdirSync`) is selected when the tree it walks changed.
- **A, app shell.** A change to `src/app/**`, `src/index.css`, `src/components/ui/**` or `public/**`
  selects every browser spec.
- **I, test ids.** A browser spec is selected if it names a `data-testid` that a changed src file
  declares now, or declared before the change.
- **L, faces.** A changed `.tsx` or `.css` file under `src/features`, `src/live` or `src/components`
  selects `layout.spec` and `wide.layout.spec`, because those two measure every tab.
- **S, an added migration.**
  - The names it **defines** select every spec that names them. Defined names are
    `create or replace function`, an altered or dropped function, a re-cut hunk row
    `('s.n(args)', N, …)`, and the tables it creates, alters, writes, indexes or triggers on. A spec
    can name one as `world.market`, as the catalogue key `worldMarket`, or as a bare
    `trade_routes`-style name.
  - A defined name that is in the RPC catalogue also marks the src files that call its wrapper as
    affected, so rules G, I and L follow it into the app.
  - The names it only **mentions** select the specs that name them in qualified form. Tables are
    excluded here: every migration reads `public.players`.
  - A defined `npc_*` name selects the whole npc pool.
  - Every added migration selects `db.chain.spec` and `db.image.spec`.

**The growth test** is db.chain's *"the world grows under a live house"*. Applied from scratch it
took 32 to 78 minutes, 95 % of the db shard. Since 2026-10-18 it applies the growth through the
prefix cache, on its own snapshots of the house-bearing world (the `growth-house-*` cache, saved
even by a cancelled run), so only the files no earlier run applied on that house run
(docs/dev-log/2026-10-18-ci-db-shard.md). A PR runs it only when the chain machinery changed:
`src/lib/db/**`, `tests/frozenChain.ts`, `scripts/db/**`, `package(-lock).json`, `vite.config.ts`,
an edited migration, or `tests/db.chain.spec.ts` (since 2026-10-17 the spec reads the chain's end off
the directory, so a migration PR does not touch it; the old `// And to 0NNN` + `const LAST =` bump
stays exempt for the control commits that predate the change). An edit to `tests/db.chain.spec.ts`
runs the growth test (`growth.test`) but is **not** chain machinery for the law (`growth.run`, read
as `cold`): it is in no snapshot's key, so it never sends disposable-chain from zero. A new migration on its own does not run it. migrations-apply-proof applies that file on main's
snapshot with its self-asserts, db.chain's other tests apply it again, and main's run re-proves the
growth.

**The merchants-on world** (`npc-on-world`) is built only when a selected spec is in the npc pool.

**Zero selected** is green on a PR. Every shard still runs under its required name, plans nothing,
logs *"no affected specs in this pool"* and succeeds. The verdict then says that nothing the PR
changed is reachable by a spec.

## What it cannot see, stated

- A browser spec drives the whole built app, and no static rule can know every face it touches. A
  `src/` change that reaches a browser spec by none of G, I, A or L runs on **main** and not on the
  PR.
- Rule S matches by name. A migration that changes behaviour a spec only observes through another
  function selects that spec only if the migration's text names that function. Re-cuts usually do,
  because their header lists the callers.
- Both gaps close on main's full run. A red there after a green PR means a rule is missing. Add the
  rule, plus a positive control for it, to `select-specs.mjs`.

## The non-vacuity floors

None of these were loosened:

- Every shard fails on any failed, skipped or flaky test. A shard that passed nothing is green only
  if its plan was empty, and only a PR's scoped selection can produce an empty plan.
  `shard-plan.mjs` refuses an empty plan on main.
- The verdict requires all six shards to report. It also requires the passes to sum to a
  denominator counted from `playwright test --list`, never from the shard plan.
- `select` first runs the selector's positive controls against real commits with known answers:
  docs-only selects nothing, 0136 selects the `trade_routes`/`port_offers` specs, #141 selects its
  three map specs, `appReady` and `src/lib/db` select the full suite. A rule change that breaks one
  fails there.
