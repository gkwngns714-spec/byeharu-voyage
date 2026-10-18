# 2026-10-18 — main's acceptance db shard: 78 min → 4 min — `osn-ci-db-shard` (CI only, no migration)

**The cost, measured.** On main the `acceptance-shard (db)` job took 33–78 min. Recent runs:
39092641268 78 min, 39097978019 78 min, 39088373678 78 min, 39083181051 78 min, 39078615762 52 min,
39095043069 33 min. All the other shards took 4–7 min. One test made up almost all of that time.
From run 39092641268's log:

| part of the db shard | time |
|---|---|
| setup: npm ci, world-image restore (485 MB, ~3 s), build | 25 s |
| the other 21 db tests (db.image, db.prefixCache, the rest of db.chain), on worker 1 | 3.5 min |
| **db.chain › "the world grows under a live house"**, on worker 2 | **1.2 h** (31.7 min on 39095043069) |

That test applied all 134 growth files (0041 → the head) to a fresh PGlite on every run. Its 360 s
budget never fired: a timer cannot run inside a synchronous wasm statement.

**The fix: save what was checked.** After file N commits, the database that holds the house is a
pure function of the base and growth files 1..N. That is exactly what `scripts/db/prefix-cache.mjs`
caches, so the growth now applies through it as its own variant, `growth-house`:

- **The base.** The frozen pre-growth chain, plus the house founded through `new_house` and a real
  BUY. Its id hashes `create()`'s own source, `houseSnapshot` and the frozen chain's key, so an edit
  to the setup misses the cache.
- **Restore.** The longest growth prefix that an earlier run applied on that same house is restored
  and digest-verified on load. Only the files after it run, through the same applier, each with its
  self-assert.
- **The base's facts** are the pre-growth counts and the house before the growth. They travel inside
  the snapshot as a database setting (`byeharu_growth.base` in `pg_db_role_setting`). No schema,
  table or row that a migration can see is added, and the facts cannot come apart from their snapshot.
- **The assertions are unchanged** and run on the end state on every run. A broken house stays
  broken in the snapshot, so a cache cannot turn a red green.

No file in `scripts/db/**` or `src/lib/db/**` changed, so no snapshot key moved and the change is
not chain machinery.

**CI.** `.github/actions/acceptance-pool` restores and saves the `growth-house-*` cache in the db
pool:

- The cache key covers the chain, the spec, `frozenChain`, the applier, the cache module and the
  lockfile.
- A green run saves under the exact key.
- A failed or **cancelled** run saves its progress under `…-partial-<run>`, and `restore-keys` finds
  it. A cancelled run's finished growth files are not applied again.

**The selector.** Before this change, an edit to `tests/db.chain.spec.ts` counted as "chain
machinery" (`growth.run`, read as `cold`). That would have sent main's disposable-chain from zero
for about 50 min on this very merge. The file is in no snapshot key. It now sets `growth.test`
(the growth test runs) and not `cold`. All 7 positive controls still pass.

**The budget.** The first cold run on CI (39107062920) failed at 6.2 min with "timeout 360000ms".
The cache writes give the event loop turns, so the timer can now fire, and it threw that run's
progress away. The budget is now 100 min, which holds the cold path and sits under the job's 120.

**Measured (workflow_dispatch on this branch):**

| run | db shard | growth test | whole workflow | tests |
|---|---|---|---|---|
| main 39092641268 (before) | 78.4 min | 1.2 h | 79 min | 462 listed |
| 39107806852 (cold, fills the cache) | 68.3 min | 1.1 h (134 applied; snapshots 48.9 s) | 68 min | 462 listed, 462 planned, db 22/22 |
| **39112184706 (warm)** | **4.0 min** | **4.0 s** (134/134 restored in 3.5 s) | **11.4 min** | **462 of 462 passed**, db 22/22, 0 skipped |
| local, one new migration (133 restored + 1 applied) | — | 8.2 s | — | — |

No spec was lost: 462 tests listed and 22 db tests before and after. The db.chain spec still has
10 tests.

**Not split.** Warm, the db shard (4.0 min) finishes before the plain shards (5–6.5 min) and the
npc chain (npc-on-world plus npc shards, ~11 min), which is now the workflow's critical path. A
second db runner would add setup time and save nothing. `tests/shard-weights.json` re-weights the
growth test to 10 s.

**Concurrency on main: kept (no cancel-in-progress).** I measured 30 h of main (10-17 00:00 →
10-18 06:54):

- 68 pushes made 68 runs: 21 finished and 45 were cancelled.
- Every one of the 45 had run zero jobs. They were pending runs that a newer push replaced, so no
  finished shard was ever wasted.
- Finished runs took 48–119 min (median 78), and that length is what lost the verdicts.
- Push gaps: median 13.6 min, p25 5.2, p10 1.3; 21 of 67 came under 8 min.

With an ~11-min run, most pushes get their own verdict, and the newest push always gets the next
one. Cancel-in-progress would kill a nearly finished run on each of those 21 close pushes.

**Seen, not mine.** The plain browser shards were red on main and here with *different* tests each
run: layout.spec on 39097978019 and 39107062920, trade.ceiling on 39107806852. Green on 39112184706.
That pattern looks non-deterministic. It is left for its owner; this change does not touch the
browser pools.

**After merge.** Main cannot read a branch's caches, and #212 edited 0137/0156 inside the growth. So
main's first run applies the growth cold (~68 min) once and saves it. Every main run after that
applies only its new files.
