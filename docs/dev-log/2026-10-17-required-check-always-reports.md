# 2026-10-17 — `disposable-chain` reports on every pull request — `osn-required-check-always`

**The problem.** Branch protection on `main` requires two checks, `build` and `disposable-chain`.
`.github/workflows/migrations-apply-proof.yml` ran on `pull_request` only under a `paths:` filter
(`supabase/**`, `scripts/db/**`, `package.json`, the workflow, `scripts/ci/select-specs.mjs`). A PR
that touches none of those — PR #153 (a chart change), PR #161 (a design doc) — never got a
`disposable-chain` status: GitHub shows a required check that never reported as "Expected", and the
PR can never merge, by hand or by `--auto`.

**The fix.** The `paths:` filter is gone; the workflow runs on every pull request. The `select` job,
which already reads the PR's diff (merge commit against its first parent, `fetch-depth: 2`), gets a
second output, `db`: `'false'` only on a pull request whose diff touches none of `supabase/`,
`scripts/db/`, `scripts/ci/`, `src/lib/db/`, `package.json`, `package-lock.json` or the workflow file
(the former filter, plus what the two jobs actually execute — `supabase-snapshot.sh`, the chain
engine the gate scripts import, the lockfile the gate installs from). `pglite-gate` and
`disposable-chain` each carry a job-level `if:` on it. A skipped job finishes in seconds and GitHub
reports a job skipped by its `if:` as **success** — a required check skipped that way satisfies the
protection (GitHub docs, "Using conditions to control job execution"). The `select` job's log states
which way it went and prints the diff.

**The fail-safe.** `disposable-chain` is the required check, so its condition is
`!cancelled() && needs.select.outputs.db != 'false'`: if `select` itself failed, the output is empty,
the condition holds, and the chain runs as before. A plain `if:` would imply `success()`, and a
failed `select` would then skip the required check — which counts as passing. `pglite-gate` is not
required and keeps the plain form.

**Unchanged.** A PR that touches a database path runs exactly what it ran before (the legs `select`
picks, and `disposable-chain` on main's snapshot). A push to `main` runs everything from zero and
keeps the snapshot. Job names are the same (`select`, `pglite-gate (…)`, `disposable-chain`), so the
protection's contexts still match. This PR edits the workflow, so its own run takes the normal path
(`db=true`); the skip path was checked locally against three main commits: e485257 (docs only) →
no hit, 3814ec9 (migration 0141) → hit, c684665 (CI + chain source) → hit.

**Cost.** `disposable-chain` now waits for `select` (about half a minute) on database PRs.
