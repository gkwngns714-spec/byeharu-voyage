# HANDOFF — picking byeharu-voyage up on another computer

Written 2026-08-18. **Read this first, then `docs/DEV_LOG.md` (decisions D1–D7), then `docs/DESIGN.md`.**

This file is written for a machine that has never seen this project. Everything below was verified on
the machine it was written on; where something is machine-specific it says so, because the previous
project's notes were bitten by paths that only existed on one PC.

---

## 0. What this project is, in four lines

A **text-and-tabs age-of-sail trade and exploration strategy game**. Orders are composed in words on a
**Command tab**; the **Map is a read-only view** that shows where fleets are and where they are going;
the world is the real world, with real ports at real coordinates. It replaces the combat game in the
sibling repo `byeharu`, whose visual combat layer failed. **There is no combat scene here and there
never will be** — danger is a probability table resolved server-side and reported as prose.

- Repo: `https://github.com/gkwngns714-spec/byeharu-voyage` (**private**)
- The old game, `https://github.com/gkwngns714-spec/byeharu`, is **still live and must not be touched**.

---

## 1. Get it running — the whole list

```bash
git clone https://github.com/gkwngns714-spec/byeharu-voyage
cd byeharu-voyage
git config core.autocrlf false        # REQUIRED. See §5.
npm install
npm run dev                           # http://localhost:5173/byeharu-voyage/
```

That is genuinely all. **No database setup, no Docker, no Supabase account, no `.env.local`.** The game
runs against a local Postgres compiled to WebAssembly. A missing cloud project is a normal state, not a
broken one — the app detects it and opens in local mode with no sign-in.

Requirements actually used here: **Node v24.16.0, npm 11.13.0**. Nothing else.

### The commands that matter

| Command | What it does | What green means |
|---|---|---|
| `npm run dev` | Vite dev server, hot reload | — |
| `npm run build` | `tsc -b` then `vite build` | Typechecks and bundles |
| `npm run lint` | ESLint over everything | No findings |
| `npm test` | Playwright specs (pure Node, **no browser needed**) | All specs pass |
| `npm run db:check-versions` | Migration version collisions | No duplicate version prefixes |
| `npm run db:apply` | **Applies the whole chain to real Postgres** | Every migration's self-assert fired |
| `npm run db:proof` | The four proof files | Every named `PASS:` marker appeared |

`db:apply` and `db:proof` are the important ones and they are explained in §2.

---

## 2. The thing that is different from every previous project: SQL runs locally

The predecessor's operating notes said, flatly, that *SQL migrations cannot be run locally — no Docker,
no Supabase CLI, no psql*. Every SQL mistake there cost a push and a CI round trip.

**That is not true here, and it is the single most important thing to understand about this repo.**

`@electric-sql/pglite` is real PostgreSQL compiled to WebAssembly. Proven on 2026-08-18 by running it:

```
PostgreSQL 18.3 (PGlite 0.5.5) on wasm32-unknown-linux-gnu
```

It compiles and executes `plpgsql`, including `SELECT ... INTO` and `RAISE EXCEPTION`. So the chain is
proven in **three** places, in this order:

1. **PGlite, locally** — `npm run db:apply` / `npm run db:proof`, before any push. Seconds, not minutes.
2. **Disposable Supabase in GitHub Actions** — the apply-proof, with Docker, in CI. Still the net.
3. **Supabase cloud** — production, when it exists (§4).

**A migration should never reach CI red.** If it does, it means somebody skipped step 1.

### The chain today

10 migrations, `supabase/migrations/`, all self-asserting. `supabase/migrations/CHAIN.md` lists each one
and what it proves. They define the entire V0 server: the static world and its seed, the market and its
price formation, closed-form voyages, the command parser, the read RPCs and the tick functions.

Four proof files in `scripts/db/proofs/`, 27 PASS markers between them:

| Proof | What it establishes |
|---|---|
| `01_offline_equivalence` | A voyage settled lazily after a 9-hour gap is **byte-identical** to one settled step by step |
| `02_ledger_reconciliation` | `Σ ledger.ducats_delta = players.ducats` after a randomised 500-order soak |
| `03_grant_lockdown` | No client role can write **any** table |
| `04_first_session` | The ten-minute first session actually earns money |

That last one is the game: buy salt at Lisboa, sail 188 nm to Cádiz, sell, buy hides, come home.
**+530 ducats on an 8,000 stake, 6.63%, with all four orders completing unattended.**

---

## 3. Where the work stands

### Done and verified

- **Design** — `docs/DESIGN.md` (1,458 lines). Buildable, not a mood board: 26-verb grammar, 46 error
  codes, closed-form movement, price formation, Appendix 1 data model, Appendix 2 RPC surface.
  `docs/DESIGN_RESEARCH.md` carries the Uncharted Waters Origin research with a source-quality marker
  on every claim.
- **Core reuse audit** — `docs/CORE_REUSE.md` (1,643 lines), 154 cited `path:line` references into the
  old repo. What to carry, what to adapt, what to leave, and a 16-item risk ledger.
- **World data** — 214 ports, 91 countries, 51 seas, 25 regions, 70 goods. **Every coordinate is from
  Wikidata P625 (CC0) and stores the item it came from.** `node scripts/check-ports.mjs` re-verifies
  the lot; worst country-bbox margin 0.0000°. Projection is equirectangular, chosen by measurement
  (Web Mercator stretches Longyearbyen 4.81×, Miller 2.16×, equirectangular 1.00×).
- **Server** — the 10 migrations above.
- **Client shell** — 8 tabs, auth, UI primitives, carried from the old repo's core.
- **Map** — inline SVG over Natural Earth 1:110m. Labels are planned as a *set* with priority and
  8-way placement, so nothing overprints; measured 0 collisions at 390×844.
- **Screens** — Command, Fleets, Port, Market, Ledger.

### In flight when this was written

- **The browser data layer** (`src/lib/db/`, `src/lib/rpc/`) — booting the chain in PGlite in the
  browser, persisted across reloads, behind one typed RPC surface with two backends. **This is the
  piece that turns fixtures into a real game.** Check whether `src/lib/db/README.md` exists; if it
  does, it contains the fixture-field → RPC-field mapping table.
- **Three screen defects** found by screenshotting at 390×844: Fleets clipping its endurance column
  instead of scrolling, prose values wrapping into ragged right-aligned fragments on Ledger and Port,
  and Market burying every price under three rows of chips.

Both may have landed by the time you read this — check `git log` and `docs/DEV_LOG.md`.

### The next real step after those

**Rewiring the five screens from `src/fixtures/v0.ts` to the live RPC surface.** The screens were
deliberately built as pure presentation against typed fixtures so that this rewiring is a mechanical,
one-file-at-a-time job rather than a rewrite.

---

## 4. The database, honestly

**Nothing about the cloud blocks development.** But you will hit this eventually, so know it now:

Creating a Supabase project fails with the real error

> `The following organization members have reached their maximum limits for the number of active free
> projects ... gkwngns714-spec (2 project limit)`

Both free slots are held by `byeharu` (Singapore) and `aqua-chronicles` (Seoul). When this game needs to
go online for other players, it needs **either** pausing `aqua-chronicles` from the Supabase dashboard
(reversible) **or** upgrading the org to Pro. That is the owner's call and is not urgent.

Until then the game is single-player-local and completely playable.

---

## 5. Traps — read before you write code

These are not hypothetical. Each one cost the predecessor real time.

1. **Set `git config core.autocrlf false` on any fresh clone.** CRLF bakes `\r` into SQL that is later
   compared against `pg_get_functiondef` output (which is LF), so it can never match, and the
   production deploy fails. `.gitattributes` pins `* text=auto eol=lf` plus `*.sql`, `*.mjs`, `*.sh`,
   `*.json`, but the local config matters too.
2. **Never let a duplicate migration version through.** A duplicate deploys as a silent no-op. It
   happened four times in the old repo. `npm run db:check-versions` catches it — and the check proves
   itself non-vacuous by detecting a deliberately duplicated version.
3. **Every migration self-asserts, and every assert must be non-vacuous.** Pair each zero-count check
   with a positive control that proves the probe works. A `SELECT` that finds nothing because it was
   spelled wrong looks exactly like a `SELECT` that finds nothing because the bug is fixed.
4. **Clients never write tables.** Migration 0001 revokes client write and then re-checks
   `information_schema.role_table_grants`, because Supabase's default `GRANT ALL` once left `anon` able
   to write a table no migration had widened, and it aborted a production deploy.
5. **Build and lint green does not mean it works.** The app white-screened on boot — `createClient('','')`
   throws at module load — while build and lint were both exit 0. **Open the page.** A Playwright
   chromium is enough: `npx playwright install chromium`, then screenshot at 390×844.
6. **One authority per concept.** If you find yourself writing the same rule twice, hoist it. The old
   repo accumulated 7 and 11 copies of single rules and had to have them ripped out.
7. **The map never accepts an order.** If a map interaction ever mutates game state, the design has
   been violated. Pan, zoom and select are the whole interaction budget.

---

## 6. Machine-specific facts — do NOT assume these transfer

Everything here was true on the Windows 11 PC this was written on, and **may be false on yours**:

- Supabase CLI at `C:\Users\디폴리스\supabase-cli\supabase.exe`, v2.101.0, **already authenticated**
  (`projects list` works with no login). On a new machine you will need `supabase login`. Note v2.101.0
  rejects `--size nano`.
- **No Docker.** That is why CI carries the disposable-Supabase proof and the local loop uses PGlite.
  If your machine *has* Docker, `supabase start` becomes available locally too — a bonus, not a
  requirement.
- `gh` CLI authenticated as `gkwngns714-spec` with `repo` scope.
- The old repo is checked out at `C:\Users\디폴리스\byeharu`. `docs/CORE_REUSE.md` cites paths inside it;
  if you do not have it, clone it read-only rather than guessing what those lines say.
- Playwright's chromium was installed here for screenshot verification. On a new machine:
  `npx playwright install chromium`. The specs themselves are pure Node and do **not** need it.

---

## 7. How to work on this

The method that produced everything above, in one paragraph, because it is the part most easily lost:

Read the spec before writing. Slice by concept, one authority per concept — never a second copy of a
rule. Write the migration, apply it locally, and only then write the next one. Make every assert prove
itself. Never claim something passes without running it and reading the output; paste the real output.
When a document and the code disagree, the code wins and the disagreement gets written down rather than
smoothed over. And **look at the screen** — three of the real defects found on day one were invisible to
the build and obvious in a screenshot.
