# byeharu-voyage: instructions for Claude, on any computer

A **LIVE** text-and-tabs age-of-sail trading game with real players.
- Repo: `gkwngns714-spec/byeharu-voyage`.
- Site: https://gkwngns714-spec.github.io/byeharu-voyage/.
- Database: the Supabase project **byeharu-voyage**, ref `olaquvizoavjeiricyxk` (Seoul).
- The old space game "byeharu" is a different project (`dlkbwztrdvnnjlvaydut`). Never touch it from this repo.

## First, every session
1. **New computer?** Do `docs/NEW_COMPUTER.md` once. It covers the gh login, clone, `npm ci`, the Supabase login + link, and `~/bin/bv-deploy.sh`.
2. Read **`docs/WORK_QUEUE.md`**, the owner's live list. Its "Deploy order" header is the current state: what is live, what is open, what is next.
3. Read the owner's memory: the `claude-memory` repo, the newest `byeharu-voyage-resume-*` file, and the hard rules in its `MEMORY.md`. They bind.
4. Check the facts before acting on them:
   - `gh pr list` and `gh pr checks <n>` (ALL checks, not only the required ones);
   - the prod head: `npx --yes supabase@2.120.0 db query --linked "select max(version) from supabase_migrations.schema_migrations"`;
   - main's suite: `gh run list --workflow="Acceptance (the whole spec suite, against a served build)" --branch main -L 3`.
5. Background agents and timers from another computer do NOT carry over. Resume each "in progress" item from its queue entry or its open PR. Recreate the 10-minute status reminder.

## How the owner wants work done
- **Never stop, never ask permission.** Decide, record it as "decided by default", and the owner may reverse it. Write in English, plainly, with no jargon.
- **Every 10 minutes, a SHORT status:** what's being done now and what's left, in queue order. After each queue edit, run `~/bin/bv-queue-push.sh` so the other computer sees it.
- **Pipeline the builds:** build the next slices in parallel worktrees while one deploys. Give each change that alters live play its own measured window.
- Use Fable agents for mechanical, docs and watcher work, and Opus for hard design or debugging. Browsers are **headless only**: the owner may be using the PC.

## Hard rules for this repo
- **Deploy only with `~/bin/bv-deploy.sh <pr>`** (source: `scripts/ops/bv-deploy.sh`). It pushes the migration and merges ONLY if the push landed at the expected head.
  - Migrations go in strict number order, renumbered to the prod head + 1 at push.
  - Never merge a migration PR by hand: a merge auto-publishes the client.
- **Prod is read-only for checks.** Wrap them in `begin transaction read only`, and call only functions whose `provolatile` is 's' or 'i'. Never run EXPLAIN ANALYZE on a volatile function.
- **A migration's self-assert counts only its own probe rows.** Its selections run read-only on prod BEFORE the PR. It never DELETEs from append-only tables (`events`, ledger); clean-up is by rollback.
  - Sliced live bodies: each hunk occurs exactly once and reverses to its pre-image.
  - Never edit an applied migration: that forces CI to rebuild from zero.
- **CI never rebuilds from scratch on a PR.** It tests only what changed; the full suite runs on main. A red on main goes to the top of the queue. Read every red to its last error.
- **Changes that alter live play** (lighting a switch, the fight) get a 30-minute after-check, with a forward rollback ready. For the fight, use `scripts/ops/harness/raid/after-check.sh <start> <end>`.
- Close finished worktrees and shells, but only AFTER the agent using them has reported.

## Where things are
- `supabase/migrations/`: the chain. `docs/dev-log/`: one file per slice, with measurements.
- `docs/OWNER_REQUESTS.md`: every owner instruction. `docs/OWNER_AUDIT_2026-10-18.md`: its audit.
- `scripts/ops/`: the deploy script, the queue push, and the measurement harness (see its README).
- `docs/research/`: price and history research, with its audit.
