# 2026-10-18 — main builds on its own snapshot; the from-zero apply is nightly — `osn-ci-main-incremental`

**The owner's law.** *"CI never starts from scratch; always make CI fast; save everything you
checked."* PR #149 made it bind pull requests (docs/CI.md, "The law"). This PR makes it bind main.

**The problem, measured.** `.github/workflows/migrations-apply-proof.yml`'s `disposable-chain` applied
the WHOLE chain from zero on every push to main. Run 39040210150 (main `d2f8f39`, 2026-10-17): the
job ran 14:27:58 → 15:16:56 UTC, 49 minutes, of which the apply (`Applying migration 0001…` at
14:29:14 to `…0142…` at 15:15:57) was 47. Since #149 every PR's `disposable-chain` waits, bounded, for
main's run on its base before it restores a snapshot — so every PR waited on that one 50-minute
run. Worse: between 14:18 and 15:16 that day twelve commits reached main, and the workflow's
concurrency group (`migrations-apply-proof-refs/heads/main`, `cancel-in-progress: false`) let only
one of them wait — GitHub keeps at most ONE pending run per group and cancels the pending one when a
newer arrives. Ten of the twelve main runs ended "cancelled" without ever starting (39040956168,
39041326187, 39042155908, 39042206654, 39042213199, 39042394640, 39042808245, 39043111012,
39043943306, 39044171666). Those commits got no proof and left no snapshot; a PR based on any of them
found only an older prefix and applied more files than it needed to.

The other main workloads were checked before touching them, and they already build incrementally:
the `pglite-gate` legs restore the previous main entry through `restore-keys: chain-prefix-` (run
39040210150, leg `the rest`: *"restored 133/134 migration(s) … in 3.2 s … applying 1"*, the leg done
in 4m24s), and acceptance's `npc-on-world` and shards on main finished in 4–6 minutes each (run
39044200081), which is a world-image cache hit, not a rebuild (a rebuild is 30+ minutes). Nothing
there changed.

**The fix.**

1. **A push to main restores the longest kept snapshot that is an exact prefix of its chain** — the
   same `scripts/ci/supabase-snapshot.sh choose` a PR uses, by exact key, not "the newest" — applies
   the merged files on it with `supabase migration up`, runs every check unchanged (the recorded
   list equals the directory, the default-ACL and ownership checks, the eight lockdown markers), and
   **keeps the result** as the snapshot the next PR and the next main run restore. `choose` learned
   the branch it works on: `GITHUB_BASE_REF` on a PR, the pushed branch otherwise
   (`BASE_BRANCH="${GITHUB_BASE_REF:-$GITHUB_REF_NAME}"`), and `SNAPSHOT_WAIT_SECONDS=0` means
   "never wait" — main does not wait for a sibling run: the heavy self-asserts (0105–0110) are inside
   every kept prefix, and applying a few more merged files is cheaper than waiting. Simulated
   locally against the live cache list with the push environment: *"chosen:
   sbdb-v1-2.114.0-ef5375de… — the longest kept prefix, 134 of this chain's 140 file(s); 6 to apply
   on top"*. The PR path was simulated too, against the in-progress main run for `60e5263`, and
   found it (*"main's run for the base 60e5263…: 39044200029 in_progress"*).
2. **Every push to main has its own concurrency group** (`migrations-apply-proof-${{ github.sha }}`
   on push; the ref's group for a PR, a dispatch and the schedule). Each merge's run now completes,
   side by side, and leaves the snapshot of its own chain. A snapshot is ~120–140 MB; GitHub evicts
   the least recently used past 10 GB, same as the `chain-prefix-*` and `world-image-*` entries
   already saved per commit.
3. **The from-zero net is one run a day**: `schedule: cron '23 18 * * *'` (03:23 KST), any
   `workflow_dispatch`, and a push to main whose diff changed the chain machinery or an old
   migration — the same `growth.run` set `select-specs.mjs` uses for the PR exemption
   (`src/lib/db/**`, `scripts/db/**`, the preamble, `package(-lock).json`, `vite.config.ts`,
   `tests/frozenChain.ts`, an edited/deleted/renamed migration). The job-level env `FROM_ZERO`
   carries that decision; it skips `choose` and the restore, applies 0001 → head on a fresh volume,
   and keeps the snapshot. A red nightly is reported like any red and read to the last error.
4. **`select` has one diff authority.** A new step `base` names what this run is diffed against:
   the merge commit's first parent on a PR, `github.event.before` on a push (fetched shallow;
   `HEAD^1` would miss the earlier commits of a multi-commit push), nothing on a dispatch, the
   schedule or a push whose previous commit GitHub does not name. `db` and `cold` both read it. A
   push that touches no database path now skips both proof jobs exactly as a PR does — its chain is
   byte-identical to the previous main commit's, whose run keeps that snapshot.
5. **What is kept.** On main every green run's chain, from zero or built on a snapshot; on a PR only
   a from-zero (exempt) run's, as before. An incremental snapshot of chain N+1 is the verified
   snapshot of chain N (`usable` judged it file for file) plus the merged files applied by the CLI's
   own applier with their self-asserts; the nightly from-zero snapshot of the same chain carries the
   same key, so nothing downstream can or needs to tell them apart.

**Expected main wall-clock.** `select` ~10 s; `disposable-chain`: Docker + CLI boot from the
restored volume ~2 min, the merged files' apply (seconds to a minute each for the recent ones; 0105's
class is never re-applied), the checks ~1 min, the snapshot save ~1 min — about 5–8 minutes for a
one-migration merge against 49 before, and nothing but `select` for a merge that touches no
database path. The PR wait on main's run drops by the same amount. These are expectations from the
measured parts (a PR's restore-and-apply of one file took two minutes on #147's re-run); the first
push to main after this merge is the measurement, and it is recorded in DEV_LOG when it lands.

**Trade-off, stated.** Between two nightlies, a snapshot's correctness rests on the chain of
incremental applies plus the checks each run makes. The nightly from-zero run is what re-anchors
it; if it ever disagrees with the snapshots (a self-assert that passes incrementally and fails from
zero, or the reverse), that disagreement is the finding, not a flake to re-run.

**Files.** `.github/workflows/migrations-apply-proof.yml`, `scripts/ci/supabase-snapshot.sh`,
`docs/CI.md`, this file.
