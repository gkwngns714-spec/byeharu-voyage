# Picking byeharu-voyage up on another computer

Written 2026-08-25, at the end of the session that landed migrations 0051–0056.

**This file is the MACHINE procedure only — how to get a working checkout that can build, apply
the chain and run the gates.** What the project *is*, what state the work is in, and what to do
next live in `docs/RESUME.md`, and that is the one authority for it. Read this file to get the
machine ready; read RESUME to know what you are doing.

---

## 0. The two things that cannot travel in the repo

`.gitignore:5` ignores `*.local`. So these two files exist only on the old machine and **git will
not bring them**:

| File | What it is | Without it |
|---|---|---|
| `.env.local` | `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` | `npm run dev` builds in **local PGlite mode** — no account, no server, a world that dies with the browser's storage. It still runs; it is just not the online game. |
| `supabase.credentials.local` | `SUPABASE_PROJECT_REF` and `SUPABASE_DB_PASSWORD` | You cannot push migrations to production. Nothing else breaks. |

**Either copy both files across by hand** (USB, password manager, encrypted note — not a chat
window), **or recreate them**:

- `.env.local` — both values are on the Supabase dashboard under Project Settings → API, and the
  same two values are already stored as this repo's GitHub Actions secrets
  (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`). The anon key is public by design; it ships
  inside the deployed bundle. Format is `KEY=value`, one per line, no quotes. See `.env.example`.
- `supabase.credentials.local` — the project ref is in the dashboard URL. The database password
  is **not recoverable**; if you do not have it, reset it at Project Settings → Database → Reset
  database password and write the new one here. Nothing but the CLI reads it.

> There is also a standing security item recorded in `docs/OWNER_REQUESTS.md`: the Supabase
> access token was pasted into a chat transcript on 2026-08-23 and expires around 2026-09-23.
> Moving machines is a good moment to rotate it.

---

## 1. Install

Only two things. **There is no Docker requirement** — this project runs real PostgreSQL 18 in
Node via PGlite, which is what makes `npm run db:apply` work anywhere.

| Tool | Version | Why that version |
|---|---|---|
| Git | any current | |
| Node.js | **24.x** | Both workflows pin `node-version: 24`. Node scripts import `src/lib/sea/*.ts` directly and rely on type stripping, default since 23.6 — on an older Node the sea scripts fail to parse. Verified working here on v24.16.0 / npm 11.13.0. |

Optional, only if you intend to deploy migrations to production:

- **Supabase CLI** — not currently installed on the old machine either; `npm run db:apply` and
  `npm run db:proof` do not need it.
- **GitHub CLI (`gh`)** — used to read CI results.

---

## 2. Clone and install

```bash
git clone https://github.com/gkwngns714-spec/byeharu-voyage.git
cd byeharu-voyage
npm ci
npx playwright install chromium
```

Then drop `.env.local` and `supabase.credentials.local` into the repo root (step 0).

---

## 3. Prove the machine is good before trusting anything it tells you

Run these in order. Every one of them passed on the old machine at commit `8ce55f4`.

```bash
npm run db:check-versions   # seconds  — no duplicate migration versions
npm run typecheck           # seconds
npm run lint                # seconds
npm run db:apply            # ~2-4 min — applies all 50 migrations to a real Postgres, then
                            #            world-guard certifies the world EQUALS data/*.json
npm run db:proof            # ~3-6 min — 9 proof files, 61 PASS markers
npm run build               # first run ~2-6 min: it APPLIES THE CHAIN ONCE to emit the
                            #   pre-built world image. After that it is cached and ~1 s.
npx playwright test         # 25-60 min on a quiet machine
```

What "good" looks like:

- `db:apply` ends with `CHAIN APPLIED: 50 migration(s), 50 self-assert receipt(s)` and
  `world-guard ok: … (positive control: a planted dropped-harbour and bent-good-value were both
  seen)`. **The positive control matters** — a guard that cannot see planted drift certifies
  nothing.
- `db:proof` ends with `PROOFS PASSED: 9 file(s), 61/61 PASS markers seen`.
- `build` prints `world image: certified — … chain <fingerprint>`.

---

## 4. Run the game

```bash
npm run dev
```

With `.env.local` present this is the **cloud** build and asks you to sign in. Without it, it is
the local PGlite build and builds a world in your tab.

First cloud-mode cold boot should now be **about 7 seconds**, not the 171 seconds it was before
the pre-built world image landed. If it takes minutes, the image was not built or was refused —
look for `IMAGE REFUSED` or `NO PRE-BUILT WORLD FOR THIS CHAIN` in the browser console. Both are
loud on purpose, and both degrade safely to applying the chain in the tab.

---

## 5. Traps this project has already paid for

Each of these cost a wasted run or a false green. They are machine-level, so they follow you to
the new computer.

- **Use `localhost`, never the `127.0.0.1` literal, for any Playwright base URL.** `vite preview`
  binds the IPv6 loopback `[::1]` only, so the v4 address answers nothing and Playwright
  **silently SKIPS** every browser spec — a green with a shrunken denominator. Fixed as the
  default in `playwright.config.ts:12`, but pass `PLAYWRIGHT_BASE_URL` correctly if you override
  it. **Always read the passed + skipped + failed counts, not just "0 failed".** The full suite
  is ~186 tests; a much smaller total means specs vanished rather than passed.
- **Give parallel agents explicit distinct ports.** Two `vite preview` servers both bound 4173 on
  Windows without complaint, so one agent's suite tested another agent's build and reported
  `27 failed / 147 passed`. That number described no codebase that exists.
- **`db.chain.spec.ts` and `layout.spec.ts` time out under CPU contention** — bare
  `Test timeout of Nms exceeded` with no assertion failure. They pass on re-run once the machine
  is quiet. Do not chase them as defects.
- **A stray `vite preview` can survive its task and hold `node_modules/lightningcss…node`,
  breaking a later `npm ci` with `EPERM: unlink`.** If `npm ci` fails that way, kill leftover
  node processes first.
- **Never edit a migration that has been applied.** Editing does not re-run it, so the repo and
  production silently diverge with everything green. That is the D23 defect — see
  `docs/DEV_LOG.md`. A change goes in a NEW file that says the word "supersede" in its header.
- **`tests/db.chain.spec.ts` has a `const LAST = '…'` pin** naming the last migration by
  filename. Every new migration must move it, and parallel branches conflict there on purpose.
  Resolve it to whichever file actually sorts last.

---

## 6. The one piece of work that is NOT done

**Migrations 0051–0056 are merged and pushed, but they are NOT applied to the production
database.** This repo has a migrations *apply-proof* workflow, not a migrations *deploy*
workflow — production is upgraded by hand.

So after the frontend deploy, the live site runs new client code against the old schema. Two of
the six matter especially:

- **0053** re-cuts `world.market`'s pricing path (proven byte-identical in value, but it is a
  real function replacement).
- **0056** changes `drift_sigma` from 0.040 to 0.020 — **a live economy**, affecting every
  player, not a sandbox.

Deploying them is a deliberate, verified step of its own. Read `docs/RESUME.md` for where that
stands before doing anything to production, and confirm what the live project is actually running
rather than assuming — an anon-key probe against a known column distinguishes `42501 permission
denied` (exists) from `42703 does not exist` (absent) without executing anything.

---

## 7. Resuming with Claude Code

```bash
cd byeharu-voyage
claude
```

Then say: **"read docs/RESUME.md and docs/NEW_MACHINE.md, then continue."**

Claude's memory store does not live in this repo — it is under
`~/.claude/projects/<project-dir>/memory/` on each machine, and the new computer starts without
it. The project-specific knowledge that matters has been written into `docs/` deliberately for
this reason, so the docs are the handover, not the memory.
