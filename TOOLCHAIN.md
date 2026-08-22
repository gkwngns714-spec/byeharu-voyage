# Toolchain

How this repo's build was set up: what was carried over from the sibling `byeharu` project, what
was deliberately left behind, and the real output of the commands that prove it works.

`docs/` is owned by other work, so these notes live here at the root.

Date of this pass: **2026-08-18**. Machine: Windows 11, Node **v24.16.0**, npm **11.13.0**.

---

## 1. What was copied

Read from `C:\Users\디폴리스\byeharu` (read-only; nothing there was modified).

| File | Carried over as | Change |
|---|---|---|
| `package.json` | `package.json` | name → `byeharu-voyage`; scripts cut to six (below); dependency set unchanged |
| `vite.config.ts` | `vite.config.ts` | `base` → `/byeharu-voyage/` |
| `tsconfig.json` / `.app` / `.node` / `.test` | same four | verbatim, except `tsconfig.test.json`'s `include` (one Playwright config here, not two) |
| `eslint.config.js` | `eslint.config.js` | verbatim |
| `playwright.config.ts` | `playwright.config.ts` | base URL defaults to a local preview instead of the old game's Pages site; `/// <reference types="node" />` added (see §4) |
| `index.html` | `index.html` | title, favicon path, base segment; the GitHub-Pages SPA deep-link decoder kept verbatim |
| `public/404.html` | `public/404.html` | same script, new base segment |
| `.env.example` | `.env.example` | verbatim |
| `src/lib/supabase.ts` | same | same shape, same missing-env `console.warn` (message re-tagged `[byeharu-voyage]`) |
| `src/store/authStore.ts` | same | verbatim |
| `src/features/auth/AuthPage.tsx` | same | functionally identical (same store calls, same two modes, same error/notice handling); restyled and re-worded for a ship's-register look |
| `src/app/{App,AppShell,NavBar,RequireAuth,shellState}.tsx` | same | rebuilt around the new eight tabs; see §3 |
| `src/components/ui/*` | see §3 | the generic primitives only |
| `supabase/config.toml` | same | `project_id = "byeharu-voyage"` + a two-line note; everything else byte-for-byte |
| `.github/workflows/build.yml` | same | simplified, and lint now **gates** instead of `continue-on-error` |
| a `*-proof.yml` disposable-Supabase job (pattern from `decks-proof.yml` and ~40 siblings) | `.github/workflows/migrations-apply-proof.yml` | generalised to "apply the whole chain", no project-specific script |

Dependency versions were taken from byeharu's ranges unchanged, so the two projects stay on the
same proven set: React 19, Vite 8, TypeScript 6, Tailwind 4 via `@tailwindcss/vite`, Zustand 5,
`@supabase/supabase-js` 2, react-router-dom 7, Playwright 1.61, ESLint 10.

---

## 2. What was dropped, and why

* **All 50+ `verify:*` scripts** — every one of them shells into `scripts/*.mjs` proving a specific
  byeharu mechanic (`verify:mainship-repair`, `verify:osn3:s1`, `verify:combat…`). None of those
  mechanics exists here, and a script name is a claim about a feature.
* **The knob and db scripts** (`knobs`, `knob:set`, `db:size`, `db:counts`, `db:cleanup*`) — they
  read byeharu's `game_config` table and its production project. There is no schema here yet.
* **`playwright.osnui.config.ts`** and the second test project — a UI-measurement harness for the
  old game's map overlays.
* **`@electric-sql/pglite`** — a devDependency used only by byeharu's local SQL harnesses.
* **125 of byeharu's 127 workflows** — they are per-slice production proofs (`osn3-s4-realchain-proof`,
  `worldeditor-publish-zone-update-proof`, …). Two carried over: build, and the disposable-Supabase
  apply proof. Deploy-to-production is deliberately **not** here: it needs real secrets and a real
  project, and that is a decision to make when there is a schema to deploy.
* **`scripts/check-migration-versions.mjs`** — byeharu's build calls it, but `scripts/` is another
  agent's territory in this repo, so the same guard is inlined as ~15 lines of shell in `build.yml`
  and passes when the migrations directory is empty.
* **Game-specific UI** — `Icon`'s rocket/crosshair/radar glyphs, the combat alert dot in the nav,
  `useGameState`/`useCombat`/`useGalaxyMapData`/`useMainShipSelection` and the `OverlayRail` "reach
  law" machinery that existed to keep command buttons pressable **on the map**. This game's map
  takes no commands, so that whole class of problem is designed out rather than ported.

**Scripts kept:** `dev`, `build`, `typecheck`, `lint`, `preview`, `test`.

---

## 3. What was built on top

* **`src/app/navTabs.ts`** — the eight destinations (Command, Fleets, Port, Market, Map, Ledger,
  Rank, Profile) as one pure table. Eight cells in a single row at 320px would be 40px each, under
  the 44px touch floor, so the bar is 4×2 on a phone and 8×1 from `sm` up. That is stated in the
  file as **arithmetic, not a measurement** — byeharu carried a confident tab-count claim for
  months that turned out to be wrong the first time anyone rendered it, so the file names the proof
  that should be written rather than pretending one exists.
* **`src/app/TabPlaceholder.tsx`** — one authority for "this tab has no content yet". Eight screens
  ship empty; writing the same header + empty card eight times would be eight copies of one
  decision. Each feature screen supplies only its own words and the named things that will live
  there. It is temporary by construction and gets deleted when the last caller stops using it.
* **`src/features/map/MapScreen.tsx`** — states in the UI, in a notice the player can read, that
  the map is a view and not a controller, and that orders are given on Command.
* **`src/features/profile/ProfileScreen.tsx`** — the one screen that is not a placeholder, because
  the session is the one thing that really works: it shows the signed-in email/user id and signs
  out.
* **`src/components/ui/Table.tsx`** — new primitive, and the one the game is actually made of:
  `Table` / `TH` / `TD`. (`ListRow` was deleted on 2026-08-22: it had no caller in the whole
  repo, and dead surface is the soil duplication grows in.) Two structural rules — the table scrolls inside its own box so
  the page never scrolls sideways on a phone, and numeric cells are mono + right-aligned (the mono
  token carries `tabular-nums slashed-zero`, so figures line up).
* ~~`src/components/ui/Sheet.tsx`~~ — **deleted 2026-08-22.** It was carried from byeharu as the
  dismissible overlay and no screen ever mounted it; the map's own corner chrome (`MapPanel` +
  `OverlayPanel`) is what the game actually uses. A primitive nothing calls is not a design system,
  it is inventory.
* **Design tokens (`src/index.css`)** — a dark "ship's ledger" skin: deep chart-blue layers, warm
  parchment text, brass accent. Three type roles — JetBrains Mono for every number/table/micro-label,
  Inter for prose, and a **system serif stack** for display titles (zero bytes downloaded; a heading
  must never be what makes a phone wait).
* **`supabase/migrations/README.md`** — the migration convention observed in byeharu, with the
  filename/numbering scheme, the header format, and the in-migration self-assert pattern quoted
  verbatim from `byeharu/supabase/migrations/20260618000173_econ_seed_multiport_offers.sql:55-109`.

---

## 4. Two real failures, and the fixes

Neither was guessed at; both came out of `npm run build` / `npm run lint` and are recorded because
the fix is a decision, not a formality.

**a. `Table.tsx` — `Type '"text"' is not assignable to type 'never'`.**
`ThHTMLAttributes`/`TdHTMLAttributes` already carry HTML's own deprecated `align`
(`'left' | 'center' | …`); intersecting it with our semantic `'text' | 'num'` collapses to `never`.
Fixed by `Omit<…, 'align'>` so ours is the only `align`.

**b. `playwright.config.ts(5,14): Cannot find name 'process'`.**
`tsconfig.test.json` deliberately keeps `types: ["vite/client"]` — identical to the app project, so
a spec is held to the same rules as the source it imports. Widening it to `["vite/client", "node"]`
would put `process`/`Buffer` in ambient scope for every future spec to satisfy one config file.
Fixed the way that file's own comment prescribes: `/// <reference types="node" />` at the top of
`playwright.config.ts`, granting Node globals to **that file** and nothing else.

**c. lint — `react-refresh/only-export-components` in `Button.tsx`.**
byeharu exports `buttonClasses` from the same file as `Button` and hides the error by running lint
with `continue-on-error: true`. Here lint gates the build, so the helper moved to a pure
`buttonStyles.ts` beside the component — exactly the pattern byeharu already uses for
`screenLayout.ts` and `overlayLayout.ts`. No rule was disabled.

---

## 5. Real command output

### `npm install`

    added 183 packages in 23s

Exit code **0**. Installed top level (`npm ls --depth=0`):

    byeharu-voyage@0.0.0 C:\Users\디폴리스\byeharu-voyage
    +-- @eslint/js@10.0.1
    +-- @fontsource/inter@5.3.0
    +-- @fontsource/jetbrains-mono@5.3.0
    +-- @playwright/test@1.61.0
    +-- @supabase/supabase-js@2.112.3
    +-- @tailwindcss/vite@4.3.3
    +-- @types/node@24.13.3
    +-- @types/react-dom@19.2.4
    +-- @types/react@19.2.18
    +-- @vitejs/plugin-react@6.0.5
    +-- eslint-plugin-react-hooks@7.1.1
    +-- eslint-plugin-react-refresh@0.5.4
    +-- eslint@10.8.1
    +-- globals@17.11.0
    +-- react-dom@19.2.8
    +-- react-router-dom@7.18.2
    +-- react@19.2.8
    +-- tailwindcss@4.3.3
    +-- typescript-eslint@8.67.0
    +-- typescript@6.0.3
    +-- vite@8.2.1
    `-- zustand@5.0.15

Note: `@playwright/test` is installed, but **no browser binaries were downloaded**
(`npx playwright install` has not been run), and there are no specs yet — `npm test` will find no
tests until `tests/` exists.

### `npm run build` — GREEN

    > byeharu-voyage@0.0.0 build
    > tsc -b && vite build

    vite v8.2.1 building client environment for production...
    transforming...
    ✓ 114 modules transformed.
    rendering chunks...
    computing gzip size...
    dist/index.html                                    1.40 kB │ gzip:   0.74 kB
    …  (font assets: Inter 400/500/600, JetBrains Mono 400/500, woff2 + woff)
    dist/assets/index-f_32tDyR.css                    55.86 kB │ gzip:  20.52 kB
    dist/assets/index-7KGl3v5M.js                    456.39 kB │ gzip: 132.92 kB

    ✓ built in 300ms

(Figures from the final run, after `rm -rf dist`. The CSS size moves by a few hundred bytes
between runs because Tailwind 4 scans the repo's text files for class names, so adding prose —
this file included — can add a utility to the sheet.)

`dist/` contains `index.html`, `404.html`, `favicon.svg`, `assets/`. This also exercises
`npm run typecheck` (`tsc -b`), which is the first half of the build command.

### `npm run lint` — GREEN

    > byeharu-voyage@0.0.0 lint
    > eslint .

    (no output)

Exit code **0**.

### Not run — and therefore not claimed

* **`npm test`** — no specs exist and no Playwright browsers are installed.
* **Anything SQL.** `supabase/migrations/` is empty and there is no Docker on this machine, so
  `supabase start` cannot run locally at all. The apply-proof workflow is written and committed;
  whether it goes green will only be known from its first CI run.
* **The app in a browser.** `npm run build` passing means it compiles and bundles; it does not mean
  a screen renders correctly. Nothing here has been opened in a browser.

---

## 6. CI

| Workflow | Trigger | What it proves |
|---|---|---|
| `.github/workflows/build.yml` | push to `main`, every PR, manual | the lockfile installs, ESLint is clean, no duplicate migration versions, `tsc -b` typechecks the whole project graph, `vite build` really produces the bundle |
| `.github/workflows/migrations-apply-proof.yml` | push to `main`, PRs touching `supabase/**`, manual | the **entire** migration chain applies in order to a real PostgreSQL in a disposable Supabase (Docker in the runner) and every in-migration self-assert passes; it then reads `supabase_migrations.schema_migrations` back out of the database |
| `.github/workflows/acceptance.yml` | push to `main`, every PR, manual | the app **runs**: chromium is installed, the production build is served, and every spec in `tests/` runs against it — including `layout.spec.ts`, the one browser spec, which measures at 390×844 that no table shears data off the right edge |
| `.github/workflows/deploy-pages.yml` | push to `main`, manual | the build is published to GitHub Pages — behind a repeat of lint, the duplicate-version check and `npm run build`, so nothing that fails the gate can ship |

Each file's header comment states this in full, including what it does *not* prove. The apply proof
passes gracefully with an empty `supabase/migrations/` and emits a CI notice saying the run proved
the harness, not the schema — so a green tick can never be mistaken for a proven chain that does not
exist yet. It carries no `environment:`, so it cannot reach production secrets even by accident.

Two things about the last two rows are worth knowing before the first run.

**Pages needs one human click, once.** Settings → Pages → "Build and deployment" → Source must be
set to **GitHub Actions**. While it is still "Deploy from a branch", `actions/deploy-pages` fails
with a "Pages site not configured" error and no workflow can fix it. After that switch, every push
to `main` republishes.

**The published build is local-PGlite mode.** `deploy-pages.yml` passes no `VITE_SUPABASE_URL` and
no `VITE_SUPABASE_ANON_KEY`, so `src/lib/rpc/init.ts` picks the local engine: PostgreSQL 18 on
WebAssembly inside the visitor's own tab, the whole chain applied there, the world in IndexedDB.
Every visitor gets a private save file. Publishing a cloud build instead means adding those two
values as repository secrets and exposing them to the build step — a deliberate human act. No
placeholder is committed, because a fake anon key builds a game that white-screens on `createClient`
(HANDOFF §5 trap 5). `acceptance.yml` builds the same way on purpose: a cloud build redirects to
`/auth`, where `layout.spec.ts` has nothing to measure and skips itself, and that job counts a skip
as a failure.
