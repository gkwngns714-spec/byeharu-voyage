# Working on byeharu-voyage from another computer

Everything needed is in two GitHub repos and the owner's logins. Nothing has to be copied from the old PC.

| What | Where it lives |
|---|---|
| Code, migrations, docs, **the live work list** (`docs/WORK_QUEUE.md`), deploy script, ops harness | this repo, `gkwngns714-spec/byeharu-voyage` |
| Claude's memory: the owner's rules, resume anchors, recorded mistakes | `gkwngns714-spec/claude-memory` (private); see its `SETUP.md` |
| Supabase access, GitHub access | the owner's own logins (never in a repo) |

## One-time setup (Git Bash on Windows)

You need Node 22+ (match the CI version), Git, the GitHub CLI and Claude Code.

```bash
# 1. GitHub
gh auth login

# 2. The game
mkdir -p ~/dev && cd ~/dev
git clone https://github.com/gkwngns714-spec/byeharu-voyage.git
cd byeharu-voyage && npm ci

# 3. Supabase (the LIVE project, byeharu-voyage, Seoul). The login opens a browser; link asks for the database password.
npx --yes supabase@2.120.0 login
npx --yes supabase@2.120.0 link --project-ref olaquvizoavjeiricyxk

# 4. The deploy script, at the path the memory and the queue name
mkdir -p ~/bin && cp scripts/ops/bv-deploy.sh ~/bin/ && chmod +x ~/bin/bv-deploy.sh

# 5. Optional: .env.local makes localhost talk to the cloud (LIVE) instead of local PGlite.
#    VITE_SUPABASE_URL=https://olaquvizoavjeiricyxk.supabase.co
#    VITE_SUPABASE_ANON_KEY=<from: npx supabase@2.120.0 projects api-keys --project-ref olaquvizoavjeiricyxk>
#    Without it, `npm run dev` runs a private local world (see memory: byeharu-voyage-canary-world).
```

Then set up Claude's memory as `claude-memory/SETUP.md` says.

**Start Claude Code from the same folder every time.** The memory folder's name comes from the working folder. On the old PC that is `C:\Windows\System32` → `C--Windows-System32`. Either start from the same path, or clone the memory into the slug of the folder you use.

## Resume from 2026-11-05

The old PC was shut down on purpose, with nothing lost: everything is on GitHub. The game runs on Supabase and needs no PC. PRs on auto-merge finish without one.

On the next PC, in a Git Bash shell:

```bash
cd ~/byeharu-voyage && git status -sb && git pull     # clone it first if it is a new PC (section above)
cd ~/claude-memory 2>/dev/null && git pull            # or the memory repo at its project slug: SETUP.md
gh auth status
npx --yes supabase@2.120.0 db query --linked "select max(version) from supabase_migrations.schema_migrations"
bash ~/byeharu-voyage/scripts/ops/health.sh | tail -5
```

Expect head 20260818000314 or later. `supabase` is not a command on PATH: always `npx --yes supabase@2.120.0`. Run `~/bin/bv-deploy.sh` from a checkout on `main`, and if `~/bin` is missing copy it from `scripts/ops/`.

Then tell Claude: **continue byeharu-voyage**. It reads the top of `docs/WORK_QUEUE.md` (the HAND-OFF block lists the exact order) and the memory note `byeharu-voyage-resume-2026-11-05.md`.

If that PC's memory folder is not a git repo, the hooks exit silently and notes never sync: check `git -C <memory folder> status`. This happened on PC 디폴리스: its project memory was not a clone, and `~/claude-memory` lagged behind it.

## Resuming

1. Open Claude Code and say "continue byeharu-voyage". It reads `docs/WORK_QUEUE.md` and the newest `RESUME` memory, then picks up the queue.
2. Background agents and timers from the old PC do **not** move over. Anything listed "in progress" in the queue that has no open PR is restarted from the queue entry. An open PR is picked up as is.
3. The 10-minute status reminder is per session; Claude recreates it.

## Rules that still apply on any machine
- Deploy only with `~/bin/bv-deploy.sh <pr>`. It merges only after the push lands. Migrations go in strict number order.
- Prod is read-only for checks: `begin transaction read only`, and only `provolatile` 's'/'i' functions.
- Headless browsers only when the owner is using that PC.
