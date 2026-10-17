# CI — what runs on a pull request, and what runs on main

The owner's order, 2026-10-17: *"make CI shorter — CI tests only from where we made something new,
not the whole game."*

| Event | Acceptance (Playwright) | migrations-apply-proof |
|---|---|---|
| **push to `main`**, dispatch | **every spec**, growth test included; verdict: passed == `playwright test --list` over all of `tests/` | all three pglite legs; disposable-chain from zero (keeps the snapshot PRs build on) |
| **pull request** | only the specs the diff can reach (below); verdict: passed == `--list` count of the **selected** files | **nothing** when the diff touches no database path (below); otherwise `the rest` always, `ledger` / `merchants` only when the diff reaches their proof, disposable-chain on main's snapshot (unchanged) |

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
so a `select` job that failed cannot skip the required check — it runs the chain instead. A push to
`main` always runs everything, from zero, as before.

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

**The growth test** is db.chain's *"the world grows under a live house"*, and it takes 45 to 65
minutes. A PR runs it only when the chain machinery changed: `src/lib/db/**`,
`tests/frozenChain.ts`, `scripts/db/**`, `package(-lock).json`, `vite.config.ts`, an edited
migration, or `tests/db.chain.spec.ts` (since 2026-10-17 the spec reads the chain's end off the
directory, so a migration PR does not touch it; the old `// And to 0NNN` + `const LAST =` bump stays
exempt for the control commits that predate the change). A new migration on its own does not run it. migrations-apply-proof applies that file on main's
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
