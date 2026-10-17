# 2026-10-17 — a merge to main no longer conflicts every other PR — `osn-no-merge-conflicts`

**The problem.** Every merge to `main` made every other open PR conflict, so GitHub stopped running
their CI and every agent rebased before it could land. Two lines did it: the top of `docs/DEV_LOG.md`
(every PR added its entry there) and the `const LAST = '…'` pin in `tests/db.chain.spec.ts` (every
migration PR bumped it, with its `// And to 0NNN` line).

**The pin.** `tests/db.chain.spec.ts` now reads the end of the chain off the directory —
`newestMigrationOnDisk()` in `src/lib/db/chainSource.node.mjs`, the highest 14-digit version in
`supabase/migrations/`, read by version and not by the loader's whole-name sort. What the pin guarded
is kept: the loader's last file must be that file, the fingerprint test edits that file, the sentence
test transforms that file, and a new migration is still applied with its receipt by
migrations-apply-proof and db.chain's apply tests. A migration PR touches the spec no more.
`scripts/ci/select-specs.mjs` keeps the routine-bump exemption only for its control commits, which
predate this; its rule is otherwise unchanged (any other edit to the spec runs the growth test).

**The log.** New entries are one file each in `docs/dev-log/YYYY-MM-DD-<slug>.md` (this is the first);
`docs/DEV_LOG.md` keeps all history up to today and says so at its top. `.gitattributes` merges
`docs/DEV_LOG.md` as `union`, a belt for the PRs still in flight that add at its top (a local rebase
resolves them without a hand). The places that told a session to add a DEV_LOG entry
(`docs/WORK_PLAN.md`, `docs/NPC_TRADERS.md`, `docs/HANDOFF.md`, `docs/RESUME.md`, `README.md`,
`docs/NEW_MACHINE.md`, `docs/CI.md`, `.github/workflows/acceptance.yml`) now point here.

**Not done.** `supabase/migrations/CHAIN.md` is still one file every migration PR appends to; its
rows land at the bottom, so two PRs conflict there only when both add the last row. Left as is.
