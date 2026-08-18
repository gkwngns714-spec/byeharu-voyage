# CORE_REUSE — what `byeharu-voyage` inherits from `byeharu`

> **Audit date:** 2026-08-18. Every claim below was produced by reading the file at
> `C:\Users\디폴리스\byeharu`. Nothing is inferred from memory. Anything that could not be
> established by reading is marked **unverified** in place.
>
> **Verdicts:** **CARRY** (copy near-verbatim) · **ADAPT** (the rule is right, the content is
> wrong) · **LEAVE** (dropped, with the reason) · **DISCIPLINE** (a law, not a file).
>
> Source paths are absolute into `byeharu`. Target paths are relative to `byeharu-voyage/`.

---

## 0. The one-paragraph verdict

What is worth taking from `byeharu` is **not the game**. It is the scaffold (Vite/TS/Tailwind 4/
Zustand), the Supabase client + auth store + route guard, the tab shell, the design-system
primitives, the migration conventions (numbering, non-vacuous self-asserts, slicing generators),
the CI apply-proof machinery, the knob tooling, the reason-message / availability-mirror idiom —
and above all the written law that kept 333 migrations from rotting. Measured: `src/features/map`
is **11,992 LOC**, `src/features/worldeditor` **14,929 LOC**, `src/features/combat` **2,555 LOC** —
**29,476 lines, 79% of the audited feature code, all of it dropped.** That is not a loss. The new
game (read-only map, typed commands, no battlefield) is a *smaller* problem than the one those
29k lines were solving.

---

# 1. CARRY OVER — verbatim or near-verbatim

## 1.1 Supabase client — `src/lib/supabase.ts` (20 lines) · CARRY

`byeharu\src\lib\supabase.ts:15-19` creates the singleton from
`import.meta.env.VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` with
`{ auth: { persistSession: true, autoRefreshToken: true } }`, and warns at `:9-12` when the env is
missing so a missing `.env.local` is obvious in dev instead of a cryptic network error later.

**Why it survives:** it contains nothing about space. Anon-key-only is the whole client security
posture — the browser never holds a service key.
**Change:** the warning prefix `'[byeharu]'` → `'[voyage]'`. Nothing else.
**Carry `.env.example` with it** (`byeharu\.env.example:1-6`): six lines, two variables, and the
comment *"never commit real keys."*

## 1.2 Auth store — `src/store/authStore.ts` (47 lines) · CARRY VERBATIM

`byeharu\src\store\authStore.ts:17-46`. Zustand store: `session`, `user`, `loading`, plus `signUp`,
`signIn`, `signOut`, `init`. `init()` (`:36-46`) calls `getSession()` once, subscribes with
`onAuthStateChange`, and **returns the unsubscribe function** so the caller owns the lifetime.
`loading` starts `true` and is what `RequireAuth` gates on — that is what stops a one-frame
redirect to `/auth` on every reload. **Change:** none.

## 1.3 Auth screen — `src/features/auth/AuthPage.tsx` (107 lines) · CARRY

`byeharu\src\features\auth\AuthPage.tsx:13-45`. One component, one `Mode = 'signin' | 'signup'`,
one shared `INPUT_CLASSES` (`:7-9`, `min-h-11` = touch-sized), busy state, `Notice` for the error.
On signup success it does **not** auto-navigate — it flips back to signin with a message (`:39-43`),
which is correct when email confirmation may be on. **Change:** wording only.

## 1.4 The tab shell — `src/app/*` (6 files, 363 lines) · CARRY. **The most directly relevant thing in the repo.**

The new game is tab-driven. This *is* a tab shell, already argued into shape over months.

| File | Lines | What it does |
|---|---|---|
| `byeharu\src\app\App.tsx` | 74 | `BrowserRouter basename={import.meta.env.BASE_URL}` (`:32`) so it works under a Pages sub-path; `/auth` public; every play route nested under ONE `<RequireAuth><AppShell/></RequireAuth>` element route (`:35-50`); legacy paths `Navigate`-redirect so bookmarks resolve (`:64-70`); `init()` subscribed once for the app lifetime (`:25-29`). |
| `byeharu\src\app\AppShell.tsx` | 60 | The persistent frame: `flex h-[100dvh] flex-col`, a slim header whose only control is the account affordance (`:41-44`), `<main className="min-h-0 flex-1 overflow-hidden"><Outlet/></main>` (`:46-48`), `NavBar` at the bottom. The polled data hooks mount **here exactly once** and reach every destination through context (`:10-14`) — destinations never mount their own. |
| `byeharu\src\app\shellState.ts` | 30 | `ShellStateContext` + `useShellState()` which **throws** outside the shell (`:26-29`). `:8-10` records why it is a separate non-component module: the react-refresh lint rule forbids exporting hooks from a component file. |
| `byeharu\src\app\NavBar.tsx` | 58 | The one bottom bar, deliberately extracted from `AppShell` so it can be **rendered and measured alone** (`:5-10`). `min-h-14` cells; labels are `whitespace-nowrap` with `truncate` deliberately absent (`:45-48`) so an overflowing label *fails a proof* instead of hiding. |
| `byeharu\src\app\navTabs.ts` | 110 | The tab table as **pure data + policy, no React**: `NAV_TABS` (`:81-83`), `navGridClass(count)` (`:90-92`). Gating filters an `ALL_TABS` array on an `enabled` boolean (`:62-78`) — a dark feature's tab is **absent**, never a tab leading to an empty screen (`:8-9`). |
| `byeharu\src\app\RequireAuth.tsx` | 31 | Redirects to `/auth` unless `session`; while `loading`, a `Skeleton` stack with `sr-only role="status"` (`:14-23`). |

**Three rules to carry with it:**

1. **Static Tailwind literals only.** `navGridClass` returns `'grid-cols-5' | 'grid-cols-6'` as
   literals rather than an interpolated class, because Tailwind must see every class as a literal
   or it tree-shakes it out (`byeharu\src\app\navTabs.ts:85-92`).
2. **The tab table is spec-pinned.** `byeharu\tests\navTabs.spec.ts:17-50` asserts the exact label
   list, the exact route list, that every tab icon exists in the icon set, and that testids and
   routes are unique.
3. **The tab count is MEASURED, never argued.** `byeharu\tests\navFits.uispec.ts` (143 lines)
   renders `NavBar` at a 320px viewport and asserts per cell width ≥ 44, height ≥ 44, and label
   `scrollWidth ≤ clientWidth`. The comment at `byeharu\src\app\navTabs.ts:28-51` is the reason:
   the old ceiling ("five; six would start clipping labels") **was an estimate in a comment that
   had never been rendered, and it was wrong.** Six fits — each cell measured 53.33 × 56px.
   > **The rule, not the number:** a new destination either keeps the render-and-measure proof
   > green at its new count, or it merges into an existing tab.

**Changes for voyage:** replace the table contents (Map/Ships/Fleet/Assets/Port/Mission → the
voyage set from `docs/DESIGN.md`; the new game needs at minimum **Command**, **Map**, **Fleets**,
**Ports**, **Ledger**, **Log**); drop `COMBAT_TAB_TO` and the combat alert dot in `NavBar.tsx:20-43`
**or** repoint the same mechanism at "a fleet has arrived / a report is waiting" — it is the only
chrome present on every screen, which is why the alert lives there (`navTabs.ts:94-101`).

## 1.5 Design-system primitives — `src/components/ui/*` (1,020 lines incl. README) · CARRY

`byeharu\src\components\ui\README.md:3-6` states the rule: *"screens compose primitives, never
re-define styles"*, with colours coming only from the `@theme` tokens in `src/index.css`.

| Primitive | Lines | Verdict |
|---|---|---|
| `Button.tsx` + `buttonClasses` | 58 | **CARRY.** 6 variants × 3 sizes, `busy`/`busyLabel`. `buttonClasses` is exported so router `<Link>`s wear the same skin with no wrapper (`:25-35`). |
| `Card.tsx` / `CardHeader` | 69 | **CARRY.** `<section>` + tone tints; spreads `data-testid`/aria. |
| `Badge` 22 · `Meter` 28 · `Notice` 27 · `SectionLabel` 8 · `StatRow` 24 · `Skeleton` 9 · `EmptyState` 35 · `PageHeader` 33 | | **CARRY all.** A text-heavy tab game needs exactly these. |
| `Screen.tsx` + `screenLayout.ts` | 23 + 29 | **CARRY.** `Screen` owns the scroll and the `space-y-4` rhythm (`Screen.tsx:47-51`). `screenSplitClass()` / `screenRailClass()` are the desktop two-rail split, **flex not grid on purpose**: a rail marked `empty:hidden` disappears when all its children render null, which is the dark-gate posture — no phantom gap in production (`screenLayout.ts:9-18`). |
| `Collapsible.tsx` + `collapsibleState.ts` | 159 + 44 | **CARRY — high value.** The one disclosure implementation: real `<button>` header (keyboard-native) with `aria-expanded`/`aria-controls`, controlled *and* uncontrolled, optional `storageKey` persisting the fold to localStorage (`:6-21`). A text-and-tabs game is mostly folds. Keep the stated constraint: *"the header button must contain NO interactive children"* (`:20-21`) — nested buttons are invalid HTML. |
| `Icon.tsx` + `icons.ts` | 34 + 93 | **CARRY the mechanism, replace the glyphs.** `ICON_NAMES` is a const tuple, `IconName` derives from it (`icons.ts:6-27`); paths are `currentColor` strokes so icons wear token text colours. `tests\uiPrimitives.spec.ts:10-29` proves every name resolves to path data starting with `M`/`m` and that name set and path-map keys match exactly. `anchor` (`icons.ts:42`) and `compass` (`:65`) already exist; voyage adds sail/coin/crate/scroll. |
| `OverlayPanel.tsx` + `overlayLayout.ts` | 80 + 145 | **CARRY the LAW; probably not the component.** See below. |

### There is no `<Modal>` problem here — and the thing that replaces it

**There is no React `<Modal>` anywhere in this codebase and no modal-dialog primitive at all.** The
overlay story is `OverlayPanel` / `OverlayRail`
(`byeharu\src\components\ui\OverlayPanel.tsx:23-79`): absolutely positioned, corner-slotted,
`bg-surface/90 + backdrop-blur` panels designed to float **over the map**, with pure class builders
in `overlayLayout.ts`. They are not dialogs — nothing traps focus, nothing takes over the screen.
A tabs-and-text game with a read-only map may not need them at all.

What **must** cross over is **THE REACH LAW**, stated once at
`byeharu\src\components\ui\overlayLayout.ts:54-83`:

> ***"An action may never live inside a region that can scroll or clip it."***

The story (same comment block): the owner, playing the live game, wrote *"right now i can't press
hunt."* The button was not disabled. Measured at 1440×675, "Hunt at Snare" occupied y 391→435 inside
a rail capped `max-h-[60%] overflow-y-auto` **at the call site**, which ended at y=399 —
**8 of its 44 pixels were on screen.** The fix is structural:

- `overlayAccountClass()` (`:86-88`) — the capped, scrollable **information** region.
- `overlayReachClass()` (`:93-95`) — never capped, never scrolled: the **controls**.
- `OverlayRail` gives the account region `shrink-[999]` (`OverlayPanel.tsx:69`) so information
  collapses to nothing before one pixel of a button is taken — *"the LAW made arithmetic."*
- A caller may **not** cap or scroll a rail: `tests\actionsAreReachable.spec.ts` fails the build if
  a call site passes `overflow`/`max-h` (`overlayLayout.ts:81-83`), because a scroll ancestor above
  the reach region defeats it silently — *"which is exactly how this defect survived a green UI
  proof."*

Carry the rule and the habit of **rendering and measuring** rather than arguing.

## 1.6 Design tokens — `src/index.css` · CARRY the structure, re-skin by values

`byeharu\src\index.css:28-59` is the one `@theme` block: layer ramp (`app` < `surface` <
`surface-2`, `edge`), text (`ink` / `ink-muted` / `ink-faint`), one accent family plus
success/warning/danger, each with a `-hover` step and a `color-mix`-derived `-soft` alpha tint
(`:50-55`) so retuning one token drags its tints along. Fonts are self-hosted via `@fontsource`,
imported in `byeharu\src\main.tsx:6-10` — **no CDN**, works offline and on Pages.

The README rule (`byeharu\src\components\ui\README.md:20`): *"Re-skins happen ONLY by retuning token
values in `src/index.css`; token names never change."* Voyage wants parchment / ink / brass rather
than graphite-teal / cyan. That is a **values edit**, and every primitive follows for free.

## 1.7 Build & type configuration

| File | Verdict | Notes |
|---|---|---|
| `byeharu\vite.config.ts` (11) | **CARRY** | `base: '/byeharu/'` → `'/byeharu-voyage/'`. Plugins: `@vitejs/plugin-react` + `@tailwindcss/vite`. That is the whole file. |
| `byeharu\tsconfig.json` (8) | **CARRY** | Solution file, three project references: app / node / test. |
| `byeharu\tsconfig.app.json` (25) | **CARRY VERBATIM** | `target es2023`, `moduleResolution: "bundler"`, `verbatimModuleSyntax`, `erasableSyntaxOnly`, `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`, `noEmit`. |
| `byeharu\tsconfig.node.json` (23) | **CARRY** | Same shape, `types: ["node"]`, includes `vite.config.ts` only. |
| `byeharu\tsconfig.test.json` (39) | **CARRY, and read its comments** | Deliberately **identical** to the app config, including `types: ["vite/client"]` and *not* `node`. `:6-11`: carrying `node` put `process`/`Buffer`/`__dirname` in ambient scope for every spec, *"holding tests to a LOOSER bar than src on exactly the axis the 'same rules as the source it imports' argument exists to rule out."* And `:33-38`: **both** playwright configs are in `include`, because the second is a live CI entrypoint. |
| `byeharu\eslint.config.js` (21) | **CARRY VERBATIM** | Flat config: `js.recommended` + `tseslint.recommended` + `react-hooks` + `react-refresh/vite`, ignoring `dist`. |
| `byeharu\playwright.config.ts` (20) | **ADAPT** | Defaults to the deployed Pages URL. Start voyage with the pure-Node spec runner; add a live-site config when there is a live site. |
| `byeharu\playwright.osnui.config.ts` (44) | **CARRY the idea** | `testMatch: '**/*.uispec.ts'` so the default config never picks these up; `webServer` starts a test-only Vite server with **dummy Supabase env** — the panels take injected deps, so nothing connects (`:3-7`). This is how real components get rendered and measured in CI with no database. |

**`package.json` scripts** (`byeharu\package.json:6-58`): carry `dev`, `build` (`tsc -b && vite
build`), `lint`, `preview` — and the *naming convention* of the rest: `verify:<system>`,
`knobs` / `knobs:dead` / `knob:set`, `db:size` / `db:counts`, `db:cleanup:dry-run` / `db:cleanup`.
Do **not** carry the 40 concrete `verify:*` entries; add one per system as the system lands.

**Dependencies** (`byeharu\package.json:60-86`), all relevant: runtime — `@supabase/supabase-js`,
`react` 19, `react-dom`, `react-router-dom` 7, `zustand` 5, `@fontsource/inter`,
`@fontsource/jetbrains-mono`; dev — **`@electric-sql/pglite`** (the offline SQL gate, §1.10),
`@playwright/test`, `@tailwindcss/vite` + `tailwindcss` 4, `typescript`, `typescript-eslint`,
`vite`, `@types/node`.

## 1.8 `.gitattributes` — CARRY FIRST, BEFORE ANY SQL EXISTS

`byeharu\.gitattributes:1-23`. Voyage already pins `* text=auto eol=lf` and `*.sql text eol=lf`.
**Add `*.mjs` and `*.sh`** — byeharu added them (`:17-21`) because the *generators* read migration
text, normalised it on read, and git handed the file back as CRLF anyway. The header is the reason,
quoted:

```
# LF IS NOT A STYLE PREFERENCE HERE — IT IS A DEPLOY PRECONDITION
# 293 of 323 migrations were CRLF in the Windows working tree while LF in the index …
# Migrations since 0299 rewrite deployed function bodies by SLICING them: a literal `old_t` must
# match text returned by pg_get_functiondef(), and Postgres returns LF-only. A CRLF `old_t` matches
# ZERO occurrences, the migration's own guard raises "guard text occurs 0 time(s)", and the whole
# deploy rolls back.
```

`:10-13` adds the part that made it survive so long: *"it only bites a local `supabase db push`
from Windows, because CI checks out the LF index and never sees it. That is exactly why it
survived: the machine that hits it is the machine with no CI to catch it."*

## 1.9 `.gitignore` — CARRY (`byeharu\.gitignore`)

Beyond the defaults: `.env` / `.env.*` with `!.env.example`; `supabase/.secrets.env`;
`/test-results/`, `/playwright-report/`, `/playwright/.cache/`; and
`.claude/worktrees/` + `scratchpad/` — *"agent worktrees (isolation:worktree) — never part of the
repo."*

## 1.10 `scripts/check-plpgsql-parse.mjs` — the offline SQL gate · CARRY. **Highest priority.**

**This machine has no Docker** (`byeharu-voyage\docs\DEV_LOG.md`, D5), so this is the *only* place
SQL is executed before CI. Three independent checks
(`byeharu\scripts\check-plpgsql-parse.mjs:25-58`):

- **(A) Parse + compile against a real PostgreSQL.** `@electric-sql/pglite` — **WASM Postgres, no
  Docker, no server** — is instantiated at `:376-377`
  (`const { PGlite } = await import('@electric-sql/pglite'); db = await new PGlite()`). Every
  statement is lexed by the real scanner (catching dollar-quoting, unterminated literals, statement
  splitting), and every `do $tag$ … $tag$;` block is re-wrapped as `create or replace function
  pg_temp._chkN() returns void language plpgsql as …` and handed to `plpgsql_compile` (`:405-411`).
  It catches missing `end if` / `end loop` / `end case`, malformed `DECLARE`, bad assignment syntax,
  and **RAISE parameter arity in both directions**.
- **(B) Surgery-hunk balance.** For each `(old_t, new_t)` pair in a generated migration it compares
  the **net block-depth delta** of `if`/`end if` and `loop`/`end loop` and fails when they differ
  (rationale `:50-65`; run loop `:446-453`). `CASE` and `BEGIN` are deliberately out of scope —
  a bare `end` closes three different things and counting them produces false reds.
- **(C) Assemble the surgery chain and compile the result** (`:67-77`): walk migrations in version
  order, reset a body on a top-level `create or replace`, apply every later hunk, compile the
  assembly. Every needle must match **exactly once**.

Two design rules to carry with it:

1. **The honest boundary is printed, not implied** (`:27-36`): *"It does NOT mean the migration will
   apply. This gate has no schema, so it resolves no table, column, function, constraint or
   permission; it does not run a single self-assert … Only CI's disposable matrix is the apply
   proof."* Blocks it cannot decide (a `%ROWTYPE` declare needing a real schema) are **counted and
   listed** (`:425-427`), never silently skipped.
2. **Non-vacuity floors** (`:53-58`, `:78-83`): `--require-files N` / `--require-blocks N` /
   `--require-hunks N` make the gate **red when it found less than it was told to expect**.
   *"a check that cannot fail is not a check."* If PGlite cannot start, the tool says so and
   **fails** whenever `--require-blocks` was asked for (`:370-374`) rather than becoming half a gate.

The three failures it was written for are worth reading verbatim (`:6-23`): a lone `$` used as a
dollar-quote delimiter (rejected at *parse* time, so a whole suite died before one assert ran, and
the `.sh` grep selftest was green on it); a surgery hunk whose replacement dropped one `end if`; and
— the one only check (C) sees — a bare `case when … then … end` inside an IF condition, where
plpgsql scans for the first `THEN` at paren-depth 0, the CASE supplies one, and the function ends
with the parser still open.

## 1.11 `scripts/check-migration-versions.mjs` — CARRY VERBATIM. 70 lines, enormous value.

`byeharu\scripts\check-migration-versions.mjs` checks exactly two things (`:17-21`): no two
migration files share a 14-digit version prefix, and every filename matches
`/^(\d{14})_([A-Za-z0-9_.-]+)\.sql$/` (`:27`).

**Why** (`:8-11`, quoting the repo's own commit message): *"A duplicate version is not a merge
conflict git would surface: both files land, `schema_migrations` keys on the VERSION, so whichever
applies second is recorded as already-applied and SILENTLY SKIPPED on production. The whole slice
would deploy as a no-op."* Green CI, merged PR, deployed nothing. It happened **four times** in
byeharu — `b813fa9`, `90b075b`, `43065d1`, `11acbfc` — and a human eye caught every one (`:4-6`).

It deliberately does **not** enforce contiguity: *"A gap is a decision; a collision is a bug"*
(`:20-21`). It runs inside the `build` job (`byeharu\.github\workflows\build.yml:43-44`)
deliberately, because `build` is the only required status check on `main` and therefore the only
place a guard can actually block a merge rather than merely notify (`:13-15`).

## 1.12 The verify-script harness — `scripts/lib/*` · CARRY the harness, write new verifiers

`byeharu\scripts\lib\verify-harness.mjs` (53 lines) is the canonical copy of the three blocks every
verifier used to inline (`:1-16`): `resolveEnv()` (re-exported from `./env.mjs`, `:25`),
`createReporter()` → `{counts, ok, bad}` (`:32-39`), and `createUserFactory()` which signs up a
throwaway user and pushes its id into a caller-owned array **immediately**, so a `finally` teardown
sees it even if a later step dies (`:44-52`).

The header also carries an **adoption/retirement plan** (`:9-16`): 7 of 27 verifiers had adopted it;
the other 20 *"MUST adopt this module the next time each is meaningfully touched"*; new verifiers
import it from day one; *"Retirement condition: this plan is discharged when all 27 import the
harness."* That is how a half-finished refactor is recorded honestly instead of pretending to be
done. **Carry the habit.**

### `scripts/lib/require-disposable-db.mjs` (89 lines) — CARRY VERBATIM. Read it before writing any verifier.

*"THE ONE AUTHORITY for 'this verifier may not point at the live game.'"* Six verifiers shrank the
global travel knobs so a round trip finished in seconds:

```
set_game_config('travel_scale', 0.001)      -- a journey takes 1/1000th of its real time
set_game_config('min_travel_seconds', 2)
```

`game_config` is **global** (`:5-18`): while they ran, *every fleet in the game* travelled 1000×
faster, for everyone. Each restored the captured originals in a `finally`, which covers a thrown
exception and nothing else — a Ctrl-C, a cancelled workflow, a killed container, or a pre-capture
that quietly returned `undefined` all end with the override still committed. **The audit that
produced this module found movement rows on production whose arithmetic is only possible under
those values. These scripts had already run against the live game.**

The fix is a **hard refusal**, not a better `finally`, and the reason is stated (`:20-24`): Node
cannot trap `SIGKILL`, so any wrapper would be best-effort while *reading* as a guarantee, *"and
claiming a safety that does not hold is worse than the bug."* There is **no environment-variable
escape hatch, deliberately** (`:37-41`): *"An `ALLOW_LIVE_DB=1` style override would be set once in a
workflow and the hole would be back, silently, exactly as `grant execute … to authenticated` on
`send_fleet_to_location` survived twenty migrations by being copied forward."* `isLocalHost()`
(`:47-53`) accepts loopback, `.local`/`.internal`, RFC1918 and docker hostnames; everything else
`exit(2)`.

### The verifier shape, from two representatives

Both are **dark-posture** verifiers — they prove a finished but unlit system is correctly inert.

**`byeharu\scripts\verify-ranking.mjs` (186 lines).** Header (`:5-23`) enumerates exactly what is
proved. Body: one `admin` client (service key, **teardown only**) + one `anon` client (`:47-48`);
`const { counts, ok, bad } = createReporter()` (`:50`); **numbered sections** printed as they run
(`1. Dark rejection`, `2. Public-read posture (anon)`, …); each assertion a ternary
`cond ? ok('…') : bad('…', detail)` (`:70-83`).

**The anti-probe assertion is the clever part** (`:76-82`): the RPC is called with a *syntactically
valid* uuid and a *real* dimension, precisely so that the identical `feature_disabled` answer proves
the gate fires **before** any validation. Any other code (`unknown_season`, `invalid_dimension`)
would mean validation ran first and the dark surface leaks information.

**`byeharu\scripts\verify-location-investment.mjs` (173 lines).** Same skeleton, and it documents a
**deliberate deviation** from its own brief (`:21-25`): the brief said "anon direct select returns 0
rows", but the shipped grant is `select … to authenticated` only, so an anon select is **denied**.
*"Denial is the STRONGER, truthful proof of the owner-read (NOT public) posture."* Ranking's tables
are public-read and its verifier asserts the opposite. **Assert what the code actually does, and say
so when that differs from the instruction.**

Both carry a **NO-FLAG-WRITE / NO-LIT-PATH stance** (`verify-ranking.mjs:25-33`): never write
`game_config`, never flip the flag, and defer lit-path verification to a human's activation
checklist on a dev database.

## 1.13 The knobs triangle — CARRY ALL THREE, on day one

An economy game is nothing *but* knobs (freight rates, port spreads, seasonal wind multipliers,
investment decay). This is more valuable to voyage than it was to byeharu.

**Client fold — `byeharu\src\lib\gameConfigFold.ts` (37 lines).** One export:

```ts
export function strictConfigFlag(rows: GameConfigFoldRow[], key: string): boolean {
  return new Map(rows.map((r) => [r.key, r.value])).get(key) === true
}
```
(`:35-37`). The semantics are the point (`:18-22`): `game_config.value` is `jsonb`, activation
scripts write jsonb `true`, and **only jsonb `true` reads as lit.** Everything else fails **closed**
— absent row, the *string* `'true'`, jsonb `1`, or a failed read collapsed to `[]`. It is
**last-wins** on duplicate keys rather than any-true-wins, because *"an any-true-wins scan would
diverge fail-OPEN on that shape, and a gate helper must never carry a fail-open branch"* (`:31-34`).
Pure — no React/DOM/fetch — so it runs in the pure spec battery. `:7-16` names the two call sites
deliberately *not* routed through it and why, which is how you record an exception without it
becoming drift.

**`scripts/list-knobs.mjs` (126 lines).** `node scripts/list-knobs.mjs [filter] [--tiers] [--dead]`
(`:26-33`). `--tiers` reports which production functions read each key and whether a change is LIVE
or FROZEN until the next tick; `--dead` shows only keys **no production function and no file under
`src/` reads**. *"READ-ONLY. This tool has no write path at all"* (`:13`).

**`scripts/set-knob.mjs` (154 lines).** `<key> <value> [--dry-run] [--create] [--force] [--why]`.
It (`:10-16`) reads the row first and prints current value/description/last-change; prints the
LIVE/FROZEN tier; **refuses** the write if the key does not exist (unless `--create`) or if the new
value's JSON type differs from the stored one (unless `--force`); writes through
`public.set_game_config` — *"the owned writer, never a raw table write"*; then **re-reads and exits
non-zero if the stored value does not match.**

The refusal is not paranoia (`:18-20`): `set_game_config` is a bare UPSERT with no key whitelist,
so **a typo does not fail — it mints a new row that nothing reads.** Production still carries one
such orphan (`combat_hit_variance_pct`, description NULL, seeded by no migration). And `:22-24`:
*"THIS IS A DEV TOOL, NOT GAME CODE … Production is a live multiplayer game: a knob write here is
visible to every player immediately (LIVE) or at their next fight (FROZEN)."*

> **Voyage rule:** give every knob a `description` at seed time, so `--dead` can tell the truth.

## 1.14 The three panel-guard mechanisms — `src/lib/useActivityPanelGuards.ts` (118 lines) · CARRY

`byeharu\src\lib\useActivityPanelGuards.ts` exports three things, and it is the extracted version of
an idiom three panels each carried as a local copy (`:3-9`):

- `useActivityPanelGuards()` (`:26`) — mounted + in-flight refs. `:16-24` explains the synchronous
  double-submit guard: two clicks in one render tick both read a stale `pending === false` and mint
  distinct request ids the server will not dedup.
- `runGuardedCommand<R extends {ok:boolean}>({…})` (`:65`).
- `isServerLit<T extends { ok: boolean }>(result: T | null | undefined): result is Extract<T, {ok:
  true}>` (`:112-119`) — *"the shared fail-closed check for SERVER-LIT panels only — surfaces that
  render NOTHING unless the server affirmatively lit the feature ({ok:true}); the dark envelope and
  any other failure collapse to null the same way"* (`:105-111`).

### The gating mechanisms, ranked for voyage

| # | Mechanism | Where | Verdict |
|---|---|---|---|
| **3** | **Server-driven visibility.** Panel renders nothing unless the server returned `{ok:true}`. | `isServerLit` at `useActivityPanelGuards.ts:112`; used at `src\features\ranking\RankingPanel.tsx:87` and `src\features\investment\InvestmentPanel.tsx:103` | **PREFER THIS.** Zero client/server drift, one code path, no constant to forget. |
| **2** | **Runtime strict `game_config` fold.** | `strictConfigFlag` at `src\lib\gameConfigFold.ts:35`; used at `src\features\port\salvageMarket.ts:77`, `src\features\port\shipyard.ts:70` | **Use when** the panel must decide before any feature RPC exists. Rows come from direct public-read selects (`salvageApi.ts:21`, `shipyardApi.ts:25`), not RPCs. |
| **1** | **Compile-time mirror constants.** | `src\features\map\osnReleaseGates.ts:14,41,45,57` | **Use only with a guard spec.** Documented drift hazard — see §5.7. |

The runtime-read law is stated at `byeharu\src\lib\catalog.ts:80-88`, and it is the reason
mechanism 2 exists at all:

> *"This MUST stay a RUNTIME read, never a compile constant: Pages deploys AHEAD of the
> approval-gated migrations … so only a runtime read lets the flag flip switch the already-deployed
> client atomically with the server. Absent / unreadable / any non-true shape → OFF (fail-closed)."*

## 1.15 CI workflows — carry three, plus the proof pattern

### `byeharu\.github\workflows\build.yml` (50 lines) — CARRY

Node 22, `npm ci`, lint with `continue-on-error: true` (*"style != compile"*, `:33`), **the
migration-version guard** (`:43-44`), `npx tsc -b`, `npx vite build`. Concurrency cancels
in-progress runs on the same ref.

### `byeharu\.github\workflows\frontend-tests.yml` (117 lines) — CARRY, both jobs

Two jobs because two kinds of proof need different machines (`:9-18`):

- **`frontend-tests`** — pure Node/TS specs. **No browser binary installed**, so it stays fast:
  `npx playwright test $(find tests -maxdepth 1 -name '*.spec.ts' ! -name 'galaxy.spec.ts' | sort)`
  (`:56`).
- **`rendered-ui`** — installs chromium, runs `npx playwright test --config
  playwright.osnui.config.ts` (`:109`), serving `tests/harness` through Vite and driving the **real
  components**. *"They are the only tests that can see a defect living between the DOM and the
  code."*

The header records the gap that created this file (`:4-7`): `build.yml` only typechecked and the DB
proofs only covered Postgres — **the whole `tests/*.spec.ts` suite never ran in CI, so a red
frontend spec was able to land on `main` uncaught.**

### `byeharu\.github\workflows\deploy-migrations.yml` (116 lines) — CARRY, comments included

Triggers on push to `main` under `paths: supabase/migrations/**`. The properties that matter
(`:14-20`):

- `environment: production` on the job ⇒ **GitHub HALTS the job for a required reviewer's approval
  BEFORE checkout / link / db push run.** That approval record **is** the production-deployment
  authorization; *"it is NOT implied by a PR merge."*
- `concurrency: { group: prod-migrations-deploy, cancel-in-progress: false }` — no overlap, no
  auto-cancel mid-deploy.
- `permissions: contents: read` (least privilege). Production secrets live **only** in the
  `production` Environment scope, so no ungated workflow can read them (`:20`).
- checkout of `ref: ${{ github.sha }}` — the **immutable triggering commit**, not a floating branch.
- a non-secret job summary: commit, run id, migrations introduced by this push, pre/post migration
  lists, outcome.
- `supabase db push --include-all` (`:93`), because (`:90-92`) an independent dark migration can
  deploy ahead of an earlier-numbered one, and without `--include-all` `db push` skips anything
  older than the applied max.

It also states its own safety scope **honestly** (`:9-13`): it prevents overlapping and unapproved
deploys; it does **not** make `supabase db push` transaction-atomic — *"database atomicity and
partial-apply / operator-cancellation recovery are a SEPARATE, unproven property of the CLI/DB path
… they are not assumed here."*

### How the SQL chain actually gets proven in CI — the "disposable matrix"

**81 of the 118 workflow files run `supabase start`.** They all follow one shape; the cleanest
example is `byeharu\.github\workflows\canonical-coord-authority-proof.yml` (72 lines):

```yaml
jobs:
  disposable-matrix:                                    # :32
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - name: Start disposable local Supabase           # :40-41
        run: supabase start                             #   ← applies the FULL migration chain
      - name: Export disposable DB_URL (no secrets)     # :42-45
        run: supabase status -o env | tee /tmp/sbenv >/dev/null
      - name: <NAME> proof                              # :46-69
        run: |
          set -a; . /tmp/sbenv; set +a
          : "${DB_URL:?DB_URL (disposable stack) required}"
          out="$(psql "$DB_URL" -v ON_ERROR_STOP=1 -f scripts/<name>-proof.sql 2>&1)"
          code=$?; echo "$out"
          [ "$code" -ne 0 ] && { echo "PROOF psql FAILED"; exit 1; }
          for marker in PASS_A PASS_B … 'PROOF PASSED'; do
            echo "$out" | grep -q "$marker" || { echo "MISSING PASS MARKER: $marker"; exit 1; }
          done
      - name: Stop disposable stack (always)            # :70-72
        if: always()
        run: supabase stop --no-backup || true
```

**Four properties make this the real net**, each stated in the workflow's own header (`:3-15`):

1. **`supabase start` applies the whole chain**, so **every migration's own self-assert runs against
   real Postgres.** A regression *aborts `supabase start`* — red before the proof script even runs.
2. **The proof script is self-rolling-back** (`begin; … rollback;`) — flips no committed flag,
   mutates no persisted row.
3. **`NO environment: on any job ⇒ none can read production secrets.`** The proof physically cannot
   reach prod.
4. **Green is not "psql exited 0" — it is "every named PASS marker appeared in the output."** A
   proof that silently stopped emitting markers fails. Same non-vacuity discipline as §1.10.

`byeharu\scripts\pirate-zone-grant-lockdown-proof.sql` (40 lines) is a compact example of the SQL
side: one `do $$ … end $$;` that raises on each forbidden condition and emits
`raise notice 'ZONE_LOCKDOWN_PASS_CLIENT_REVOKED'` / `…_PASS_SERVICE_ROLE_RETAINED` / a final
`PIRATE-ZONE GRANT LOCKDOWN PROOF PASSED` — exactly the markers the workflow greps for. It asserts
**both directions** (`:16-37`): the client roles must **not** have execute, and `service_role` must
**still** have it.

> **Voyage has no Docker locally.** `check-plpgsql-parse.mjs` (offline, WASM) plus a
> disposable-matrix workflow in CI are the **only two places** SQL gets executed before production.
> Stand both up before migration `0002`.

## 1.16 The rendered-UI harness — `tests/harness/*` · CARRY the mechanism

`byeharu\tests\harness\vite.config.ts:8-40` — a test-only Vite server whose entries are plain
`.html` files, each mounting a **real component from `src/`** with **injected** dependencies so
nothing connects to a database. One critical detail (`:35-39`): the harness pages import
`./harness.css`, **not** `src/index.css` directly, because with `root: tests/harness` Tailwind v4's
source auto-detection sees only `tests/harness/**` — `harness.css`'s explicit `@source '../../src'`
is what makes the app's utilities exist at all. *"Importing `src/index.css` directly yields a
stylesheet with none of the app's classes in it, and a measurement taken against that is measuring
nothing."*

## 1.17 Small pure helpers worth copying outright

| Source | Lines | Verdict |
|---|---|---|
| `byeharu\src\lib\time.ts` | 43 | **CARRY, with one change.** Header `:1-3`: *"Display-only time formatting. NOT game logic: never authoritative … All helpers are null/undefined-safe and only reformat values the server already produced."* Four total functions: `formatShortTime` (`:5`), `formatDateTime` (`:12`), `formatDuration` (`:19` — `'—'` unless finite and ≥ 0, then `Xh Ym` / `Xm SSs` / `Xs`), `formatCountdown` (`:33` — returns **`null`** when missing/invalid/elapsed *"so callers pick the verb + fallback"*). **THE CHANGE:** `formatCountdown` reads `Date.now()` internally at `:37`; every other clock-dependent module in the repo takes `nowMs` as a parameter. **Inject the clock.** There is no `tests/time.spec.ts` — write one. |
| `byeharu\src\lib\rewardBundle.ts` | 15 | **CARRY.** Types `PendingBundleItem` (`:6`) and `PendingBundle` (`:12`) — the *"pending rewards, then secure them"* envelope. `:1-4`: *"Display typing only: the server owns all bundle math and validation."* Any game with a "cargo/loot is pending until it lands" loop reuses this shape verbatim. Voyage has exactly that loop. |
| `byeharu\src\features\map\smoothPolygon.ts` | 73 | **CARRY if you draw coastlines/regions.** `smoothClosedPathD(ring): string \| null` (Catmull-Rom → cubic Bézier closed SVG `d`; `<3` finite points → null), `straightClosedPathD`, `ringCentroid`, `ringApproxRadius`. Zero game coupling. No spec exists — write one. |
| `byeharu\src\features\map\galaxyCamera.ts` | 160 | **CARRY.** Pure pan/zoom camera math: `zoomCameraAbout(cam, factor, anchor)` (`:66`), `fitCameraToWorldPoints(points)` (`:80`), `clampPan` (`:39`), `clampK` (`:34`), `sameCamera` (`:131`). Header `:3-9`: *"pure camera math … derives ONLY presentation camera state `{k, tx, ty}` … Framework-free + pure, so it is unit-tested directly."* Spec: `tests\galaxyCamera.spec.ts`. A read-only world map still needs pan and zoom. |
| `byeharu\src\features\map\mapBackground.ts` | 46 | **CARRY the lesson.** `:1-7` — *"THE ONE AUTHORITY for 'did this pointer event land on the map's NAVIGABLE BACKGROUND?'"* It retired an `e.target !== svg` identity check that broke the moment layers were added. |

---

# 2. ADAPT — the pattern is right, the content is wrong

## 2.0 The feature-folder shape — ADOPT THIS AS THE HOUSE LAYOUT

Every feature folder in `byeharu` follows one strict 4-layer split. Adopt it for voyage unchanged:

1. **`<name>Types.ts`** — pure types + player-facing copy. Discriminated-union RPC envelopes
   (`{ok:true, …} | {ok:false, reason|code}`). No React/DOM/fetch.
2. **`<name>Api.ts`** — thin `supabase.rpc(...)` wrappers that **never throw into render**; a
   transport error collapses to a fail-closed value (`{ok:false}` or
   `{ok:false, code:'unavailable'}`).
3. **`<name>.ts`** — pure policy: availability mirrors, block/advise predicates, view-model folds,
   formatters. No React/DOM/fetch/clock (clocks are **injected**).
4. **`<Name>Panel.tsx` / `<Name>Screen.tsx`** — React, mounted only after a gate.

The cleanest reference implementation of all four layers is
`byeharu\src\features\portentry\` (5 files, 550 lines):
`portEntry.ts` (pure: `parseCommissionResult(raw: unknown): CommissionResult` `:49`,
`derivePortEntryAffordance(state): PortEntryAffordance` `:118`, `COMMISSION_REASON_COPY` `:148`) →
`portEntryCommand.ts` (`createPortEntryController(deps): PortEntryCommandController` `:45` — a
**framework-free submit state machine**, `PortEntryPhase = 'idle'|'submitting'|'success'|'error'`
`:16`) → `usePortEntry.ts:37` (a thin, dependency-injectable React wrapper) →
`PortEntryPanel.tsx:22`.

The smallest complete reference is the exploration/mining twin (294 + 266 LOC):
`byeharu\src\features\exploration\explorationTypes.ts:1-7` states the whole posture —
*"PURE, framework-free types + player-facing copy … Mirrors the server contracts exactly … DARK:
the server rejects every exploration RPC while `exploration_enabled` is false; the panel renders
nothing on that envelope — the UI is never the control (fail-closed law), and no client-side flag
constant gates visibility (server-driven)."*

## 2.1 Reason→message maps — ADAPT the map, CARRY the idiom

There are **eight** instances of one idiom in `byeharu`. That is not spaghetti; it is a *type* with
eight instances, each owning its own domain's copy.

| Path:line | Signature | Fallback |
|---|---|---|
| `src\features\port\haulReasonMessage.ts:26` | `haulReasonMessage(reason: string): string` | `'Contract unavailable.'` |
| `src\features\port\salvageReasonMessage.ts:23` | `salvageReasonMessage(reason: string): string` | `'Sale unavailable.'` |
| `src\features\port\shipyardReasonMessage.ts:33` | `shipyardReasonMessage(reason: string): string` | `'Shipyard unavailable.'` |
| `src\features\inventory\transferReasonMessage.ts:28` | `transferReasonMessage(reason: string): string` | `'Move unavailable.'` |
| `src\features\command\teamReasonMessage.ts:137` | `teamReasonMessage(reason: string): string` | `'Fleet order unavailable.'` (66-entry map at `:18-134`) |
| `src\features\port\portShop.ts:149` | `portShopReasonMessage(reason: string): string` | `MESSAGES.unavailable` |
| `src\features\investment\investmentTypes.ts:91` | `investErrorMessage(code: string): string` | `'You cannot invest right now.'` |
| `src\features\portentry\portEntry.ts:159` | `commissionReasonMessage(reason: CommissionReason): string` | `COMMISSION_REASON_COPY.malformed` |

The shared invariants, stated in every header — quoting
`byeharu\src\features\port\haulReasonMessage.ts:1-7`:

> *"pure, fail-closed reason→message map … Maps the ACTUAL server reason strings (migrations 0179 +
> 0181) plus the haulApi transport fallback ('unavailable') to short player-facing text; any
> unmapped/unknown reason degrades to a generic "Contract unavailable." so the UI never surfaces a
> raw code and never throws. No React/DOM/state — unit-testable directly … The `haulBoard.ts`
> availability mirrors reuse these exact reason names, so display-only prechecks and real server
> rejects share ONE copy source."*

**Why this matters more in voyage than it did in byeharu:** the new game is *text*. The
after-action report, the refusal, the arrival notice — these ARE the game. A raw
`insufficient_cargo` reaching the player is not a cosmetic bug in a text game; it is the game
failing to speak.

**One extra move worth copying:** `byeharu\src\features\combat\combatReasonMessage.ts:37-43` carries
a **prefix-match branch** for a *parameterised* `RAISE` (e.g. `request_retreat: presence not active
(is retreating)`), and `:12-18` records the decision **not** to fold two different wire contracts
(a RAISE producing a message vs an `{ok:false, reason}` envelope producing a token) into one map.

**Rewrite for voyage:** the reason vocabulary. `not_docked` survives literally. `wrong_port`,
`deadline_passed`, `insufficient_cargo`, `too_many_active`, `already_accepted_other` survive
literally. Everything combat-shaped goes.

## 2.2 Availability mirrors — ADAPT. **The single most transferable client pattern in the repo.**

The shape: `xAvailability(input): { canX: boolean; reason: XReason }` plus a **separate**
`xBlocks(reason): boolean`.

| Path:line | Signature |
|---|---|
| `src\features\port\haulBoard.ts:60` | `haulAcceptAvailability({serverLit, shipResolved, dockedAtOrigin, offerFresh, activeCount, maxActive}): {canAccept, reason: HaulAcceptReason}` |
| `src\features\port\haulBoard.ts:93` | `haulDeliverAvailability({serverLit, shipResolved, docked, atDestination, deadlineAhead, hasCargo}): {canDeliver, reason}` |
| `src\features\port\portShop.ts:90` / `:121` | `buyAvailability(…): {canBuy, reason: BuyReason}` / `buyBlocks(reason): boolean` |
| `src\features\port\salvageMarket.ts:117` / `:153` | `salvageSellAvailability(…)` / `salvageSellBlocks(reason)` |
| `src\features\port\shipyard.ts:160` / `:223` | `shipyardOrderAvailability(…): {canOrder, reason, itemId?}` / `shipyardOrderBlocks(reason)` |
| `src\features\command\teamMove.ts:22`, `teamStop.ts:19`, `teamCombat.ts:51`, `teamSend.ts:32`, `teamMutations.ts:13`/`:32`, `teamCaptains.ts:56`, `teamAutoExit.ts:50` | same shape |

**Three rules they all share**, each written out in the source:

1. **Mirror the server's own reject ORDER, gate first.** (`haulBoard.ts:54-59`,
   `shipyard.ts:144-159`, `portShop.ts:84-89`, `salvageMarket.ts:109-116`.) The client's precheck
   answers in the same sequence the server will, so the precheck and the real refusal never
   disagree about *which* thing is wrong.
2. **The null-cap idiom: a `null` input SKIPS its clause.** "Unknown ≠ failing" — let the server
   answer. (`shipyard.ts:159`: *"EVERY null input SKIPS its clause (unknown ≠ failing — the server
   answers itself; the `haulAcceptAvailability` null-cap idiom)."*)
3. **`canX` is NOT "button disabled".** That is a separate policy. Structure blocks; stale player
   state advises. `shipyardOrderBlocks` (`shipyard.ts:232-234`) goes furthest — it is literally
   `return reason === 'feature_disabled'`, and `:222-231` explains: *"balances/credits can be
   STALE-LOW … the queue count can be stale-high … a hard disable could block a genuinely-valid
   order. The hint shows through the ONE reason mapper and the SERVER is the enforcement."*

**Voyage rewrites:** `dockedAtOrigin` / `atDestination` / `deadlineAhead` / `hasCargo` /
`affordable` all survive as concepts. The inputs change from ship-and-zone to fleet-and-port.

## 2.3 Movement / travel-time resolution — ADAPT the rule, replace the geometry

**The reusable RULE, verbatim from the source:**

`byeharu\supabase\migrations\20260616000007_movement_system.sql:65-67`:
> *"movement_create: server computes distance, travel time, arrival. Caller passes resolved
> coordinates + the fleet's speed. NEVER trusts client-supplied travel time."*

The whole computation (`:102-107`):
```sql
v_scale   := coalesce(cfg_num('travel_scale'), 1.0);
v_min     := coalesce(cfg_num('min_travel_seconds'), 1.0);
v_dist    := sqrt(power(p_target_x - p_origin_x, 2) + power(p_target_y - p_origin_y, 2));
v_seconds := greatest(v_min, v_dist / p_speed * v_scale);
```
and the row it writes carries `depart_at`, `arrive_at = now() + make_interval(secs => v_seconds)`,
`travel_distance`, `travel_seconds`, `speed_used` (`:108-121`).

**The four properties that survive the pivot, all from `byeharu\docs\ARCHITECTURE.md:89-107`:**

- *"A trip is one `fleet_movements` row. **Do not** store/update live `fleet_x/y` every second.
  Store `origin_x/y`, `target_x/y`, `depart_at`, `arrive_at`."* (`:91-92`)
- *"Visual position is interpolated **client-side** for animation:
  `progress = (now - depart_at) / (arrive_at - depart_at)`."* (`:93-94`)
- *"The server only needs to know **not arrived** vs **arrived**."* (`:95`)
- *"Slowest-unit-speed creates the 'fast & weak vs slow & strong' strategic choice."* (`:103`)

The client half is `byeharu\src\features\map\movementInterpolation.ts` — **ADAPT.** Its generic core
is `segmentProgress(seg: TimedSegment, nowMs): number | null` (`:59`) and
`interpolateSegment(seg: TimedSegment, nowMs): {x,y} | null` (`:67`) over plain millisecond bounds;
`movementProgress` (`:126`) and `interpolateMovementPoint` (`:116`) are thin ISO-timestamp adapters
that parse and delegate (`:15-18`). Header `:3-5`: *"Pure display math ONLY: it renders the
server-committed movement segment at a point in time; it derives NO ETA/arrival truth … Any
missing/invalid input → null (never a guessed position)."* `nowMs` is **injected**. Specs:
`tests\movementProgress.spec.ts`, `tests\movementInFlight.spec.ts`.
**Take the `TimedSegment` half; rewrite the ISO adapter against voyage's own movement row.**

**Arrival resolution — `byeharu\supabase\migrations\20260616000009_movement_processor.sql`.**
The pattern to adapt (`:1-10`):
> *"OWNERSHIP: part of the Movement system (writes only `fleet_movements`). On arrival it hands off
> via other systems' functions — it never writes their tables … IDEMPOTENT & CONCURRENCY-SAFE:
> selects only `status='moving'` due rows with `FOR UPDATE SKIP LOCKED` and flips status to
> `'arrived'` in the same transaction, so overlapping cron runs can't double-resolve, double-merge,
> or double-create."*

The loop (`:24-59`): `for m in select * from fleet_movements where status='moving' and arrive_at <=
now() for update skip locked` → branch on `target_type` → `update … set status='arrived',
resolved_at=now()` → **`perform` another system's function** (`fleet_set_present`,
`presence_create`, `base_merge_units`, `fleet_complete`) → an unknown target is marked `'failed'`
rather than looped forever (`:56-58`).

**What voyage must rewrite:**
- **Geometry.** Euclidean distance on an abstract ±10000 plane becomes **great-circle distance
  between real port coordinates**, along a sea route — a straight line between Lisbon and Calicut
  crosses Africa. The route is a **polyline of waypoints**, not a segment, so `travel_seconds` sums
  per-leg distances and `interpolateSegment` runs per leg. **This is the single largest server-side
  rewrite in the pivot.**
- **Speed.** `fleet_speed()` = slowest ship survives *conceptually and should be kept* — it is what
  makes fleet composition a decision. Add the age-of-sail modifiers (hull class, cargo load,
  season/wind) as **knobs folded in one function**, never as a second formula (see §4.4).
- **Handoff targets.** `fleet_set_present` / `presence_create` become "the fleet is docked at this
  port and exposed to its market/services".
- **Client mirror: NEVER.** See §5.9.

## 2.4 Port docking — ADAPT. The berth model is the right idea, stated as schema.

`byeharu\supabase\migrations\20260618000216_berth_model.sql:1-16` — **the model, verbatim:**

> *"A ship is in EXACTLY ONE of two mutually exclusive states:
> **FLEETED** — `group_id` NON-NULL, `berth_location_id` NULL. Its location is its group's fleet's
> location.
> **BERTHED** — `group_id` NULL, `berth_location_id` NON-NULL. Its location is that port — shown as
> INFO ('Docked at <port>'), never a map marker. Only fleets are map markers.
> The XOR is a CHECK constraint, not a convention: no writer can produce a ship that is both, or
> neither. ONE location resolver: fleeted → the fleet; else → berth."*

`byeharu\docs\HOW_ITS_BUILT.md:42-50` records what it replaced: *"Before it, a ship's location could
be read three or four different ways depending on which code path asked … A ghost dock (a ship
simultaneously 'flying' and 'docked and trading') becomes **structurally impossible**, not just
discouraged by convention."*

**And the second half of the lesson — `byeharu\supabase\migrations\20260618000306_empty_fleet_dock_authority.sql:25-29`:**

> *"THE SPAGHETTI (the owner's actual complaint). 'The fleet is docked' is the conjunction
> `status = 'present' AND location_mode = 'location' AND current_location_id IS NOT NULL`, and it is
> hand-copied **ELEVEN** times with no authority — THREE of them inside `assign_ship_to_group`
> alone."*

The fix (`:31-42`): mint `public.fleet_docked_location(fleets)` as **THE** docked authority — pure
over a row already in hand (IMMUTABLE, reads nothing, so folding the copies adds no second
snapshot) — and rewrite the copies by **slicing the deployed text**, nothing retyped.

**Voyage rewrites:** the vocabulary. A ship is **AT SEA WITH ITS FLEET** xor **BERTHED AT A PORT**.
The XOR CHECK constraint, the single resolver, and the "only fleets appear on the map" rule all
transfer intact — and the read-only map makes the second one *easier*, not harder.

**Also carry the deadlock lesson.** `0306:6-23` documents an emptied fleet that bricked itself:
removing the last ship left a member-less group owning a live fleet pinned at a port, and *every*
exit was closed (assign → co-location fails; move → `empty_group`; dock → verb dark; delete →
needs the fleet docked). **When you write voyage's fleet-membership writers, ask on day one: what
happens to a fleet whose last ship leaves?**

## 2.5 Investment — ADAPT. The ledger design is exactly right for "invest in cities".

`byeharu\supabase\migrations\20260618000132_location_invest_p18_flag_and_ledger.sql:16-46` records
five locked decisions. All five transfer:

1. **Persistent state is DERIVED from an append-only ledger**, never a denormalized aggregate
   column: *"PERSISTENT STATE = the all-time SUM of contributions per location (its 'development')
   — DERIVED from this append-only ledger (sum by `location_id`), monotonic, never deleted. There is
   NO denormalized aggregate column/table (no second write path to keep in sync)."* (`:18-21`)
2. **The seasonal window is derived deterministically from config**, with **no season table and no
   season-open writer** — Investment deliberately does *not* duplicate Ranking's season machinery
   (`:22-29`). *"'Reset by season, not deletion' is honored STRUCTURALLY: a new window resets the
   windowed SCORE read while the ledger is never touched."*
3. **One-way sink, no exploit.** `amount` is `CHECK (> 0)`; the command debits credits via the
   internal `wallet_debit` and appends a row. *"There is NO withdrawal path and NO payout returning
   value, so score/development can never be farmed in a loop."* (`:30-34`)
4. **Owner-read rows, public aggregates.** RLS on, one owner-read policy (`player_id = auth.uid()`),
   `grant select to authenticated` only — no insert/update/delete policy, no write grant. Per-city
   development and leaderboards are exposed **later** via `SECURITY DEFINER` aggregate RPCs, because
   *"an aggregate leaks no other player's raw rows."* (`:35-42`)
5. **Idempotency by receipt.** `unique (player_id, request_id)`, *"mirrored POINT-FOR-POINT from
   `module_craft_receipts`"* (`:48-52`). A replayed request is a no-op, never a double debit.

Client side: `byeharu\src\features\investment\` (3 files, 380 lines) — `investmentApi.ts`
(`getLocationDevelopment` `:18`, `getLocationInvestmentLeaderboard` `:25`,
`getMyLocationInvestments` `:38`, `investInLocation` `:49`), `investmentTypes.ts`
(`investErrorMessage` `:91` over `INVEST_ERROR_COPY` `:81-90`), `InvestmentPanel.tsx:28` gated by
`if (!isServerLit(development)) return null` at `:103`.

**Voyage rewrite:** `location` → `port city`; add what byeharu never had — **what the investment
BUYS** (warehouse capacity, shipyard tier, a price-spread improvement, a reputation level). Keep
the one-way-sink property while doing it: a benefit that returns credits is a farm loop.

## 2.6 Ranking — ADAPT. Take the accrual design verbatim.

`byeharu\supabase\migrations\20260618000128_ranking_p17_standings_schema.sql:16-44`, five decisions:

1. **The score dimension maps 1:1 to the read source, with NO translation layer** (`:18-27`):
   `dimension` is exactly the `reward_grants.source_type` domain. *"The scoring fn will read a
   grant's `source_type` and fold it into the row of the SAME literal — no lookup, no mapping."*
2. **One score row per `(season_id, player_id, dimension)`; OVERALL is derived at read time**
   (`:28-31`) — *"NEVER a stored denormalized row — so there is no second write path to keep in
   sync."*
3. **Incremental, idempotent accrual via a `last_counted_at` high-water mark** (`:32-36`): accrue
   only grants with `granted_at > last_counted_at`, advancing the mark in the same write, *"so a
   re-run never double-counts and never re-reads old events."*
4. **No writer in the schema slice.** Table lands with RLS + a public-read select policy + no write
   grant; the sole writer arrives in a later slice, `SECURITY DEFINER`, client-revoked (`:37-40`).
5. **Reset by season, never by deletion** (`:41-44`): a reset is a **new** `season_id` scoping a
   fresh standings set; old standings and the finalized grants they came from are never deleted.

Client: `byeharu\src\features\ranking\` (3 files, 254 lines) — note `RankingPanel.tsx:10-11`
deliberately has **no `get_my_standing` RPC**; own standing is derived client-side from the returned
rows.

**Voyage rewrite:** the dimensions. `('combat','trade','exploration','mining')` becomes something
like `('trade','exploration','investment','discovery')` — and rule 1 means **whatever the reward
source column's domain is, the ranking dimension must be that exact literal set, changed in
lockstep.**

## 2.7 Port UI — ADAPT. `src/features/port` (20 files, 3,406 lines) is the richest reuse source.

The pure-policy modules are the take:

- **`byeharu\src\features\port\portShop.ts` (151)** — `buyAvailability(…)` `:90`,
  `buyBlocks(reason)` `:121`, `buyTotal(qty, unitPrice)` `:127`,
  `portShopReasonMessage(reason)` `:149`, `offerStatChips(offer)` `:56`.
- **`byeharu\src\features\port\haulBoard.ts` (128)** — the freight-contract board:
  `haulAcceptAvailability` `:60`, `haulDeliverAvailability` `:93`,
  `haulDeadlineLabel(ts, nowMs)` `:116` (**clock injected**). *A haul contract is a voyage-game
  freight contract with the serial numbers filed off.*
- **`byeharu\src\features\port\salvageMarket.ts` (202)** — `salvageSellAvailability` `:117`,
  `salvageSellBlocks` `:153`, `salvageConfigFromRows` `:72` (uses `strictConfigFlag` at `:77`),
  `clampSellQty(raw, balance)` `:164`, `sellTotal(qty, unit)` `:176`,
  `salvageWalletDisplay(...)` `:86`, `foldStartingCredits(value: unknown)` `:67`.
- **`byeharu\src\features\port\shipyard.ts` (377)** — the fullest example.
  `shipyardOrderAvailability(…)` `:160` takes eleven inputs (flag, required hull, owned hulls,
  required captain level, best captain level, queued count, max orders, ingredient bill, balances,
  credits cost, credits) and returns `{canOrder, reason, itemId?}`; `shipyardOrderBlocks` `:223`;
  `hullGateState` `:104`; `hullOrderViews` `:288`; `activeOrderCount` `:306`.
  **This is a build-queue UI model. Voyage's shipyard is the same model with a different bill.**
- **`byeharu\src\features\port\portPicker.ts` (99)** — `derivePortsWithShips` `:49`,
  `dockedShipIds` `:69`, `resolveChosenShipId` `:85`, `portOfShip` `:96`. **Directly reusable**: a
  multi-port game needs "which of my ports has ships in it, and which one am I looking at."

**Note the misfiled economy code in `src/features/map`** — pull it out before deleting that folder:
`tradeApi.ts` (247), `MarketPanel.tsx` (276), `tradeReasonMessage.ts` (27), `dockServices.ts` (55),
`dockStore.ts` (91), `useDockServices.ts` (50), `useDockStore.ts` (45). `dockServices.ts:1-7` is a
*"PURE, framework-free … strict validator that accepts ONLY the documented states and treats
anything malformed as NOT DOCKED (never throws, never invents a dock)"* — that posture is exactly
right for voyage.

## 2.8 Command UI — ADAPT the envelope-reading, drop most of the rest

`byeharu\src\features\command` is 22 files / 3,588 lines, and the big component
(`TeamRosterPanel.tsx`, 779 lines) does not survive — voyage issues orders on a **command tab in
words**, not through a roster panel with buttons. What does survive:

- **`byeharu\src\features\command\fleetOrderOutcome.ts` (102)** — `readFleetOrderOutcome(envelope:
  FleetOrderEnvelope): FleetOrderOutcome` `:72`, `routeOrderOutcomeMessage(envelope): string` `:85`,
  `fleetGoOrderOutcomeMessage(envelope, fleetName): string | null` `:97`. Every envelope field is
  typed `unknown` and **compared, never cast** (`:43-61`), and it degrades across three server
  versions — an unrecognised value is treated as *absent*, never as an error. **A command tab is
  nothing but "read the server's answer and say it in a sentence." This is that function.**
- **`byeharu\src\features\command\teamApi.ts` (362)** — the only fetch layer for the whole feature,
  with one shared envelope type `TeamRpcResult = {ok:true; [k:string]:unknown} | {ok:false;
  reason:string}` at `:140`. **Carry the single-envelope-type discipline.**
- **`byeharu\src\features\command\howAFightStarts.ts` (64)** — `HOW_A_FIGHT_STARTS` `:47`,
  `A_ZONE_IS_NOT_A_HUNT` `:58`, `huntSiteActionLabel(siteName)` `:62`, composed *into*
  `teamReasonMessage` (imported `teamReasonMessage.ts:16`, used `:89`). The content dies; **the
  "one sentence, one home, composed by every surface that says it" idiom is the thing to keep** —
  and in a text game it is load-bearing.
- **`byeharu\src\features\command\teamRoster.ts` (383)** — `FLEET_MAX_SHIPS = 8` `:265`,
  `fleetCapacityState({memberCount, fleetControlEnabled}): {atCap, remaining, max}` `:288`,
  `canToggleCommandShip({shipGroupId, isCommand})` `:303`, `nextTeamSlot` `:84`,
  `buildTeamRoster(groups, ships)` `:45`. **Fleet composition rules transfer directly** — a fleet
  cap, a flagship, a next-free-slot allocator are all age-of-sail concepts.
- **`byeharu\src\features\command\teamSkillset.ts:123` `aggregateTeamStats`** and
  **`teamRollup.ts:39` `deriveDockedTeamRollups`** — "fold N ships into one fleet's numbers" is
  exactly what a fleet cargo/speed/crew readout needs.

## 2.9 Fleets — ADAPT, and **fix the throwing**

`byeharu\src\features\fleets` (2 files, 107 lines) is the oldest layer in the repo and the odd one
out: **no RPCs at all**, only direct PostgREST table selects (`fetchFleets` `:7`, `fetchFleetUnits`
`:16`, `fetchActiveMovements` `:22`, `fetchActivePresences` `:42`), and unlike everything else in
the codebase **they throw** (`throw new Error(error.message)` at `:12, :18, :37, :45`) rather than
failing closed.

One load-bearing detail worth carrying: `byeharu\src\features\fleets\fleetApi.ts:35` uses
`.select('*, fleets!fleet_id(group_id)')` — **without the `!fleet_id` column hint PostgREST fails
`PGRST201`** because there are two FK paths. Voyage will hit the same thing the first time a table
has two FKs to `fleets`.

**Voyage:** keep the read-only-select approach for genuinely public reference data; make every
fetcher **fail closed, never throw into render** (the §2.0 layer-2 rule); route every mutation
through an RPC.

## 2.10 Other feature folders worth transplanting nearly whole

| Folder | LOC | Verdict |
|---|---|---|
| `byeharu\src\features\assets` (6 files) | 1,253 | **ADAPT — high value.** `assetLedger.ts` (352) is a pure valuation core: `buildPriceIndex(rows)` `:76`, `priceAt(index, locationId, refId): number \| null` `:95`, `valueStack` `:121`, `totalIsPartial(t)` `:193`, `NO_PRICE_HERE = 'No price here'` `:294`, `totalParts(t): {value, caveat}` `:339`. `useAssetLedger.ts:38-42` encodes the key economic law: **a hold in transit is priced at nothing, never "nearest port."** And there is a rendered proof (`tests\assetsLedger.uispec.ts`) that a missing price reaches the screen as *words* and never as a `0` — *"a fabricated valuation is the worst thing an assets screen can render."* A trade game lives or dies on this. |
| `byeharu\src\features\inventory` (5 files) | 350 | **ADAPT.** `hold.ts` — `parseHold(raw: unknown): Hold` `:69`, `holdMeter(hold)` `:128`, `stackFits(hold, volumeM3, qty)` `:140`, `maxUnitsThatFit(hold, volumeM3, available)` `:151`, `normalizeMoveQty(raw, available)` `:160`, `formatM3` `:118`. **Volume-based cargo (m³) is exactly right for sail.** |
| `byeharu\src\features\captains` (7 files) | 1,008 | **ADAPT — zero coupling to combat/map/coordinates.** An RPG crew layer bolted onto ships; transplants cleanly as officers/navigators. Note `captainProgress.ts:1-5` knowingly duplicates the server XP curve (`level = 1 + floor(sqrt(xp/100))`) for bar rendering — that duplication is a **choice**, and if you copy it, copy the acknowledgement. |
| `byeharu\src\features\modules` (3 files) | 563 | **ADAPT.** Crafting + fitting against public-read catalogs. Becomes ship upgrades (rigging, hull sheathing, guns-as-cargo-protection). |
| `byeharu\src\features\ship` (22 files) | 3,753 | **ADAPT most.** Dense small pure selectors: `repairEconomy.ts` (211) mirrors the repair knob + reject order; `meterPair.ts` (50) is the shield/hull bar view-model — *"never a second copy of the bar math"*; `shipName.ts` (41) mirrors the rename RPC's validation; `shipRecovery.ts` (199) handles the wrecked-ship softlock. **Only `shipLocation.ts` (157) has map coupling.** |
| `byeharu\src\features\events` (3 files) | 161 | **ADAPT.** A read-only world-events feed, *"Purely presentational — no actions/buttons"* (`WorldEventsPanel.tsx:10-16`). Becomes the voyage news/rumour tab. |
| `byeharu\src\features\uiassets` (3 files) | 71 | **ADAPT.** `assetGlyphs.ts:1-9`: the **server** owns the icon vocabulary (`ui_asset_catalog` keys + a stable `asset_ref`); this file owns the rendered glyph *"as tiny inline emoji so ZERO binary assets ship."* Also the naming ruling worth stealing: *"'assets' in this game means the PLAYER'S assets … These are UI ICON keys. One name, one meaning."* |
| `byeharu\src\features\dashboard\useGameState.ts` | 139 | **ADAPT the shape.** `useGameState(pollMs = 3000)` `:63` composes eleven feature APIs; a `staticRef` (`:65`) caches never-changing catalog/world/config reads so only dynamic state re-fetches (`:129-131`); one `Promise.all` wave (`:86-96`); a non-fatal read is `.catch(() => null)` inline (`:93`). |
| `byeharu\src\features\account\AccountMenu.tsx` | 141 | **CARRY the pattern.** Zero new fetches — it composes shell state. Wallet state is a **4-way union** `number \| null \| 'error' \| undefined` (`:29`) so *"unknown" never renders as `0`.* Same law as `NO_PRICE_HERE`. |
| `byeharu\src\features\onboarding\firstOrders.ts` | 176 | **ADAPT — do this early.** `deriveFirstOrders(input): FirstOrderStep[]` `:61`, `firstOrdersComplete(steps)` `:119`. Hard constraint at `:4-12`: **zero new server surface** — every done-condition is derived from state the shell already polls. And it is flag-aware: *a step for a dark feature is omitted, never greyed* (`:14-15`). A text game with typed commands needs a first-orders card more than a click game does. |
| `byeharu\src\features\base` (2 files) | 45 | **LEAVE.** Vestigial — `baseApi.ts:13-14` admits the feature is gone. Voyage's NO-HOME law (ports are the only base) makes it moot from day one. |

---

# 3. LEAVE BEHIND

## 3.1 `src/features/combat` — 2,555 LOC, 23 files · DROP

**Why:** the owner's founding decision (`byeharu-voyage\docs\DEV_LOG.md`, D3): *"The visual combat
layer is the thing that failed, visually and in code. This game has no battlefield … There is no
scene to render, so there is no scene to break."*

Structurally the whole folder is a read-only mirror welded to combat tables that will not exist.
`combatTypes.ts:1-3`: *"client-side row types (read-only mirror). `combat_ticks` are the
authoritative log; `combat_events` are cosmetic. The client never computes any of these values."*
Every module is a fold over specific `combat_encounters` / `combat_units` / `combat_ticks` columns:
`combatPhase.ts` (status + `enemy_integrity_current` → one of three phases),
`reinforcementClock.ts`, `autoExitLine.ts`, `repositionCourse.ts`, `encounterAnchor.ts`,
`fightHaul.ts`, `combatFeed.ts`, `combatLabels.ts`.

### Genuinely worth salvaging out of it — three things

1. **`byeharu\src\features\combat\combatReasonMessage.ts` (63)** — `retreatErrorMessage(raw)` `:29`,
   `fleeErrorMessage(raw)` `:61`. **Salvage the idiom, not the map.** `:6-10` records why it exists:
   both verbs were leaking raw Postgres text to players (`request_retreat: presence not active (is
   retreating)`) and a bare token (`no_pending`). The prefix-match branch at `:37-43` handles a
   parameterised RAISE. It is one of *three* instances of this idiom in the repo (with
   `map\tradeReasonMessage.ts` and `ship\repairReasonMessage.ts`) — three instances confirm it is
   the house style, not an accident.
2. **`byeharu\src\features\combat\useCombat.ts:26-36` — the polling contract.** Quote it into
   voyage's own polling hook:
   > *"The poll had no in-flight guard and no sequence token. Six requests go out per cycle; the
   > interval fires every 1.5s regardless of whether the previous cycle has come back … cycle N
   > could resolve AFTER cycle N+1 and overwrite fresher rows with older ones, so hull bars jumped
   > backwards, dead ships reappeared and splats replayed a tick that had already passed. Two
   > mechanisms, both needed: `inFlight` stops a new cycle starting while one is still out; `seq`
   > stamps each cycle and a late reply whose stamp is not the newest one is DROPPED before it can
   > call setState."*

   Refs at `:47-49`, plus a once-per-key **ask-ledger** (`:53-54`, documented `:50-52`) — *"a record
   of what has already been ASKED — including keys that came back unreadable, so a failing read is
   retried by the next mount rather than hammered every 1.5s."* **Voyage will poll fleet positions
   and arrivals. This is that hook's spine.**
3. **`byeharu\src\features\combat\reportFold.ts` (35)** — `newestReportId(reports)` `:19`,
   `reportRowOpen(…)` `:29`. Generic list-fold UX policy: the newest report starts open, older ones
   collapsed; row state is deliberately **not** persisted to localStorage because per-row keys are
   per-encounter uuids (unbounded growth) (`:1-10`); and the newest is *"Derived, never assumed from
   array order — the RPC's ordering is not a client contract"* (`:18`). **Voyage's after-action log
   tab is exactly this.**

**Borderline:** `rewardPayload.ts` — `resolveRewardEntries(payload)` `:60`, type `RewardPayload =
Record<string, unknown> | null | undefined` `:40`. `:14-22` records a real production bug: every
reader typed `{"metal": N, "items": [...]}` as `Record<string, number>` and mapped entries straight
into a chip, so one surface rendered `Items ×[object Object]` and another **silently dropped every
looted item** (`v > 0` is false for an array). Survives *iff* voyage's reward envelope is still "a
scalar key beside an array key". Otherwise take the lesson.

**One more policy worth lifting** — `retreatCountdown.ts:17-22`: *"AN UNKNOWN RENDERS AS NO CLAIM,
NEVER AS A PLAUSIBLE NUMBER … There is deliberately NO arithmetic path from a missing config value
to a displayed number here."*

## 3.2 `src/features/map` — 11,992 LOC, 60 files · DROP ~9,000, SALVAGE ~550

**Why:** the map is now an **output device**. `byeharu-voyage\docs\DEV_LOG.md` D4: *"The map tab
shows where fleets are and where they are heading. It **never accepts an order.** All orders are
composed on the Command tab."* Roughly 3,500 LOC of the folder is combat rendering
(`spatialCombatLayer.ts` 886, `combatMotion.ts` 601, `CombatMapCard.tsx` 426, `fightingFleetStats.ts`
292, `fleetFightPosition.ts` 270, `combatActors.ts` 230, `useCombatMotion.ts` 145,
`ambushEncounterNotice.ts` 88, `nearMissNotice.ts` 109) and ~1,400 LOC is coordinate-movement
*command* (`FleetCommandPanel.tsx` 580, `fleetCommandModel.ts` 354, `fleetGoTarget.ts` 154,
`spaceMoveCommand.ts` 44, `SpaceMoveTarget.tsx` 46, `PirateInterceptPanel.tsx` 145,
`pirateApi.ts` 146). **A read-only map deletes both categories outright.**

### Salvage list (verified pure — none of these imports `react` or `lib/supabase`)

| Module | LOC | Take |
|---|---|---|
| `byeharu\src\features\map\openSpaceTransform.ts` | 183 | **The best-engineered file in the audit.** `worldToViewBox` `:74`, `viewBoxToWorld` `:82`, `viewBoxToScreen` `:115`, `screenToViewBox` `:134`, `screenDeltaToViewBox` `:151`, `worldToScreen` `:158`, `screenToWorld` `:165`, `isWithinOpenSpaceBounds` `:174`; types `WorldCoord` `:45`, `ViewBoxCoord` `:49`, `ScreenCoord` `:53`, `Camera` `:58`, `Viewport` `:65`. Header `:1-33`: *"PURE logic only. No DOM, no React, no SVG element, no events, no fetch, no state,"* three **explicitly named** coordinate spaces, and the safeguard at `:24-33` — *"It NEVER clamps … Out-of-domain inputs convert to out-of-range outputs … they are NOT snapped to an edge … Bounds validation is a SEPARATE concern — use `isWithinOpenSpaceBounds()`. A command / target-validation path MUST use that predicate and MUST NOT infer validity from a conversion result."* **ADAPT the domain** (±10000 abstract → lon/lat with a real projection); **carry the structure, the naming, and the no-hidden-clamping law verbatim.** Spec: `tests\openSpaceTransform.spec.ts`. |
| `byeharu\src\features\map\galaxyCamera.ts` | 160 | **CARRY** (see §1.17). |
| `byeharu\src\features\map\markerStyle.ts` | 199 | **ADAPT — this is the "marker policy" module.** `markerStyle(l: MarkerStyleInputs): MarkerStyle` `:101`, `labelVisible(l, k): boolean` `:196`, `markerHitRadius(style)` `:133`, `markerImportance` `:47`, `labelTier` `:191`. Header `:4-6`: *"the PURE marker-hierarchy + label-declutter policy. No React, no DOM: props in, a style/visibility decision out, so LocationMarker stays a thin renderer and this file is unit-tested directly."* Colours are design-token references (`var(--color-*)`), never literals (`:9-15`). **The shape — 3-tier importance, zoom-gated label reveal, a minimum hit radius for touch — transplants directly to a world map crowded with port cities.** Spec: `tests\markerStyle.spec.ts`. |
| `byeharu\src\features\map\movementInterpolation.ts` | 129 | **ADAPT** — see §2.3. |
| `byeharu\src\features\map\smoothPolygon.ts` | 73 | **CARRY** if you draw coastlines or trade-region outlines. |
| `byeharu\src\features\map\locationDisplay.ts` | 64 | **ADAPT the pattern.** `dangerLabel(difficulty: number): string` `:30`, `rewardLabel(tier: number): string` `:44`. `:3-6`: *"PURE player-facing display mappings … numbers/enums in, plain player words out … ONE home (moved out of MapScreen's inline block)."* The bands are byeharu's economy; the *"numbers never reach the player raw"* rule is voyage's too — arguably more so. |
| `byeharu\src\features\map\territoryAt.ts` | 55 | **Retype, don't copy.** `territoryAt<L>(point, locations): L \| null` `:34` — radius containment with a documented total tie-break (nearest centre → smallest radius → lowest id, `:20-33`). The tie-break discipline is the valuable half. |
| `byeharu\src\features\map\mapBackground.ts` | 46 | **CARRY the lesson** (see §1.17). |
| `byeharu\src\features\map\routeGeometry.ts` | 91 | **Mostly LEAVE.** `pointInRing(point, ring)` `:19` (ray-cast even-odd) survives if the read-only map hit-tests hazard regions on hover. `segmentIntersectsRing` `:49` and `suggestDetourWaypoint(...)` `:70` are movement-command logic. `:1-12` notes it is a display-only client mirror of PostGIS `ST_Intersects` that *"never decides gameplay, only whether to flash a warning."* No spec exists. |

**Explicitly dead on arrival:** `osnReleaseGates.ts:5-13` self-declares — *"RETIRED as a UI
authority … the per-ship coordinate surface it once gated was DELETED outright in 4A-POST … No
component imports this constant."* `combatMotion.ts` (601) is pure and well-engineered (injected
clock, `tests\combatMotion.spec.ts`) but 100% combat animation. `shipVisual.ts` (297) is pure —
*"No React, no DOM, no fetch, no clock"* (`:3-4`) — but describes combat-ship glyph forms.

**Pull out before deleting:** `tradeApi.ts`, `MarketPanel.tsx`, `tradeReasonMessage.ts`,
`dockServices.ts`, `dockStore.ts`, `useDockServices.ts`, `useDockStore.ts`,
`mainshipStatusLabel.ts` — **economy code that was never map code** (see §2.7).

## 3.3 `src/features/worldeditor` — 14,929 LOC, 99 files · DROP ENTIRELY

The single largest area in the audit, and it authors **exactly the content types voyage is
dropping**: pirate zones, mining fields, exploration sites, enemy archetypes, fleet templates,
encounter profiles, location→encounter bindings. It is owner-only behind
`dev_zone_editor_enabled` + an `is_owner()` RPC, mounted at a hidden `/dev/world` route
(`byeharu\src\app\App.tsx:51-63`).

**The one genuinely domain-agnostic thing inside it** is the draft framework —
`draftModel.ts` (218) + `draftTypes.ts` (104) + `draftValidation.ts` (66) + `useDrafts.ts` (303)
≈ **690 LOC**. `draftTypes.ts:1-4`: *"the draft lifecycle — create / fork-edit / patch / dirtiness /
staleness / persistence / preview / advisory validation — is domain-agnostic. A domain … binds
itself to the core through exactly ONE descriptor."* Drafts are client-side only, mirrored to
localStorage (`useDrafts.ts:1-4`). Four domains bind to it.

**Verdict: LEAVE it, and revisit only if voyage grows an owner authoring tool.** It is a
localStorage-backed edit-buffer pattern that only pays for itself if there is something to author.
Voyage's world is **real geography loaded from `data/*.json`** — there is nothing to draw.

**One thing to steal without the folder:**
`byeharu\src\features\worldeditor\commandContract.ts` (392) — `:1-4`: *"no React, no DOM, no
supabase, no network IO of any kind."* A **typed server-command contract module** with zero IO is
exactly the shape voyage's Command tab needs: the tab parses text into a typed command object, the
contract module validates and shapes it, and only then does an api module send it.

## 3.4 `src/game` — 19 LOC · DROP, but **read the header first**

`byeharu\src\game\movement\travelPreview.ts` is the entire folder. Its body is three lines
(`:17-19`): `export function distance(ax, ay, bx, by) { return Math.hypot(bx - ax, by - ay) }`.
Its header (`:1-15`) is the most important text in this section:

> *"This file used to be a second travel-time authority. Alongside `distance` it exported a client
> mirror of the server's movement formula — `previewTravelSeconds`, `slowestSpeed`,
> `countdownClock`, and its OWN hardcoded `DEFAULT_TRAVEL_SCALE = 1.0` / `DEFAULT_MIN_TRAVEL_SECONDS
> = 5`. Production runs `travel_scale` and `min_travel_seconds` out of `game_config`, so those
> constants were the server's numbers copied into TypeScript and then left behind. Nothing imported
> any of it … They are deleted rather than kept 'in case' — a dormant second formula with stale
> defaults is exactly what the no-spaghetti rule forbids, and reading this file was enough to
> believe the client still computed ETAs.*
>
> *If a preview ETA is ever wanted again, it must come from the server (an RPC that resolves the
> same speed the mover will use), never from arithmetic re-implemented here."*

**Voyage law, taken from this file:** the Command tab will want to show *"Lisbon → Calicut, about 9
days."* **That number comes from an RPC.** Never from TypeScript.

## 3.5 `src/lib/osnState.ts` — 16 LOC · DROP

The whole export (`:11-16`):
```ts
export function isSettledInSpace(input: {
  spatialState: string | null | undefined
  status: string | null | undefined
}): boolean {
  return input.spatialState === 'in_space' && input.status === 'stationary'
}
```
`'in_space'` is precisely the concept being dropped. Its two consumers — `ExplorationPanel.tsx:2`
and `MiningPanel.tsx:2` — both need a new gate (`dockedAtPort`, most likely).
**What generalises is the header's one-line law** (`:1-4`), not the function:

> *"display/enablement only, NEVER authoritative: these drive button enabled-states; the server
> re-validates every command and rejects anything else (fail-closed law)."*

## 3.6 `src/lib/catalog.ts` — 156 LOC · ADAPT ~20 lines, DROP the rest

Two things in one file. **(i) Reference-data reads** — generic in shape, combat-schema in content:
`UnitType` (`:7-19`, attack/defense/hull/speed/cargo) goes. **(ii) Nine feature-flag readers**
(`:46, :61, :74, :88, :101, :111, :127, :140`) plus `fetchIsOwner` (`:152`) — every one gates
something being dropped.

**⚠ Do not carry `fetchGameConfig` (`:33-41`) as written.** It builds `out[row.key] =
Number(row.value)` over whatever rows returned, so **a missing key is indistinguishable from a
failed read**, and `error` throws rather than degrading.
`byeharu\src\features\combat\retreatCountdown.ts:11-12` names this as the root of a real production
defect: *"`??` cannot tell 'missing' from 'never fetched'."* The cure lives *outside* the file — an
explicit `fold…(value: unknown): number | null` at `retreatCountdown.ts:37`. **If you carry the
reader, carry the fold discipline with it.**

Carry the **~20 lines of pattern**: runtime-read-never-compile-constant (`:80-88`, quoted in §1.14),
strict-fold semantics (`:56-64`), and `fetchIsOwner`'s posture (`:146-155`) — *"The client call adds
NO authority; it only decides whether to RENDER the owner-only surface. FAIL-CLOSED: any transport
error or non-true result … resolves to false."*

---

# 4. THE DISCIPLINE — the house rules voyage inherits

## 4.1 The no-spaghetti law — the root of everything else

`byeharu\docs\HOW_ITS_BUILT.md:24-25`, recorded verbatim from the owner at the top of
`docs\MOVEMENT_UNIFICATION_CHARTER.md`:

> ***"If work is or becomes spaghetti, rip it out and redo it clean. One authority per concept.
> Compose, don't fork. Ship dark first. Retire the old once the new one is proven."***

Four rules. Each has a real case in the codebase.

### One authority per concept

`byeharu\docs\SYSTEM_BOUNDARIES.md:6-17` is the enforced record — *"the law of separation,"* approved
2026-06-16:

> *"Each system owns only its own responsibility and communicates through clear server-side
> functions — **never** by directly changing another system's tables.*
> *— **No system secretly controls another.** No spaghetti logic.*
> *— **One sole writer per table.** Everyone else goes through that system's functions.*
> *— **The cross-system call graph is acyclic.**
> *— **No direct client writes** to game state — only `SECURITY DEFINER` RPCs.*
> *— **No reward duplication.** No hidden state changes."*

It is implemented as a literal **table → sole-writer matrix** (`:21-60+`), and it survives
column-level growth: when two independent things get added to one table over time, the document
states in writing **which single function owns which column**
(`byeharu\docs\HOW_ITS_BUILT.md:36-40`).

**Voyage must start `docs/SYSTEM_BOUNDARIES.md` at migration 0001, with one row.** Retrofitting it
onto 300 migrations is what byeharu had to do.

### Compose, don't fork

`byeharu\docs\HOW_ITS_BUILT.md:54-61`: when the unified fleet mover needed to release a fleet to
`idle` before redirecting, the first draft hand-rolled the transition inline, and CI caught the bug
(`fleet_set_moving: fleet not in idle state`). *"The fix wasn't a patch on the hand-rolled code; it
was composing the **existing** primitive that already knew how to do this correctly."*

### Dark-first — ship behind a flag, byte-identical until lit

`byeharu\docs\HOW_ITS_BUILT.md:65-80`: *"land the schema and the function bodies fully built, gated
behind a `game_config` flag seeded `false`, and prove — by **extracting the function's source and
diffing it byte-for-byte against its previous head** — that the dark branch changes nothing for a
live player. The recurring phrase across dozens of DEV_LOG entries is 'byte-identical' or
'extract-and-diff verified.'"*

> *"This is why the system can ship large, structurally serious changes — like retiring an entire
> movement layer — without a big-bang release: the risky code exists in production, provably inert,
> long before anyone depends on it."*

The server-side idiom is: **check the flag FIRST, reject before any read.** From
`byeharu\supabase\migrations\20260618000132_location_invest_p18_flag_and_ledger.sql:43-46` —
*"the exact 0097/0102/0107/0117/0124/0127 slice-0 flag idiom, including the server-side
`feature_disabled` rejection posture EVERY future Investment RPC must adopt (check FIRST,
reject-before-any-read while false)."* That is what makes the anti-probe verifier assertion in
§1.12 possible.

### Retire the old, once the new one is proven

`byeharu\docs\HOW_ITS_BUILT.md:84-94`: *"Dark-first only works as an anti-spaghetti discipline if
the old path is actually deleted once the new one is live — otherwise 'dark-first' quietly becomes
'two paths forever.'"* The retire arc is concrete: delete the dead client, drop the legacy functions
under a **drain-assert** (a migration that `RAISE`s rather than proceeds if any row still depends on
the thing being dropped), narrow the columns, delete the now-pointless cron. Byeharu did it —
`0231` dropped the spatial columns and `0232` dropped **20** legacy movement functions
(`:317-320`).

The charter's closing rule (`:91-94`): *"Before touching movement: re-read §12 + this charter. If a
change adds a per-command readiness branch or a new movement path, it is spaghetti — **stop**."*

## 4.2 Server-authoritative — the client never writes game state

`byeharu\docs\ARCHITECTURE.md:20-22`:

> ***"The client only displays what the server says. The server owns: fleet location, arrival time,
> unit quantities, combat results, rewards, retreat timing, and death/survival. The client may
> animate, but the server decides the truth."***

`byeharu\docs\ARCHITECTURE.md:184-190`:

> *"The client **never** writes important game state. No direct client writes to: `base_units`,
> `fleets`, `fleet_units`, `fleet_movements`, `location_presence`, `combat_encounters`,
> `combat_rounds`, `combat_reports`, `zone_state`, `location_state`, `base_resources`, rewards.*
> *The client only calls RPCs. The server validates and decides results. **Frontend formulas are
> previews only; server formulas are authority.**"*

`:192-195` lists what **every** player RPC validates: ownership (`auth.uid()`), availability and
positivity, target validity/active/unlocked, action allowed there, fleet limit,
not-already-assigned, timing, and **legal state-machine transitions** — *"Reject impossible
transitions."*

`:200-208` is the RLS matrix: reference/world tables are **public read, server/admin write**;
everything owned by a player is **owner read, server RPC write only (`SECURITY DEFINER`)**.

## 4.3 The one sentence in `ARCHITECTURE.md` that predicts this whole pivot

`byeharu\docs\ARCHITECTURE.md:24-26`, written at the very beginning of the project:

> ***"Do not build free-moving ships that chase/fight from live positions — that path is bug-prone.
> Use discrete states: choose destination → validate → travel → arrive → present → activity →
> resolve."***

and `:28-30`:

> ***"Most important rule: build the game around location presence, not directly around combat.
> Movement decides arrival; presence decides exposure; activity decides what happens; combat is only
> one activity; reports show the result."***

Byeharu spent 2026 walking away from that rule (OSN, free coordinate travel, spatial combat) and
`byeharu-voyage` is walking back to it. **This is voyage's core loop, unchanged:**

```
Map  →  Port  →  Voyage  →  Arrival  →  Activity  →  Report
```

## 4.4 New capability is new DATA, not a new engine

`byeharu\docs\HOW_ITS_BUILT.md:276-288`: Mk-II modules were *"two new `module_types` rows plus
recipe rows against the fitting adapter built for MOD2-1 — 'no new stat path.'"* The shipyard reuses
the **existing** build-order queue engine originally built for unit training — *"never a second
timer system,"* widened with a nullable FK rather than forked. And the standing law from
`byeharu\docs\ARCHITECTURE.md:284-285`:

> ***"don't replace the engine — replace the source of expedition stats"***

> *"Each new stat contributor is a new fold inside one function, not a competing calculation living
> somewhere else."*

**For voyage:** wind, season, hull class, cargo load and crew quality all fold into **one**
`calculate_voyage_stats()`. Never a second speed formula.

## 4.5 Migrations: numbering, naming, and the self-assert

### Numbering

`byeharu\supabase\migrations\` holds **333 files**, named `<14-digit version>_<snake_name>.sql`,
enforced by `/^(\d{14})_([A-Za-z0-9_.-]+)\.sql$/`
(`byeharu\scripts\check-migration-versions.mjs:27`). The version is a fixed date prefix plus a
zero-padded ordinal — `20260616000001_init_profiles.sql` … `20260618000351_the_fleet_fires_as_one.sql`
— and everything in the docs, comments and proofs refers to a migration by the **last four digits**:
`0001`, `0216`, `0305`, `0351`. Gaps are legal and deliberate: *"the chain has 15 legitimate gaps
(192, 223-225, 251, 253, 321-329) … A gap is a decision; a collision is a bug"*
(`check-migration-versions.mjs:20-21`).

**The naming convention is a sentence, not a noun.** Recent examples straight from `ls`:
`0332_a_wreck_can_always_come_home`, `0333_items_have_a_place`,
`0335_one_way_to_repair`, `0337_reposition_is_a_move`, `0340_stats_have_one_authority`,
`0349_a_fleet_comes_home_together`, `0351_the_fleet_fires_as_one`.
**Each name states the RULE the migration establishes.** Carry this — it makes a 300-file chain
readable by `ls` alone.

**One system per file** (`byeharu\docs\ARCHITECTURE.md:324-327`), **forward-only**, never edit an
applied migration.

### The self-assert — 150 of 333 migrations carry one

The block is fenced with a banner, and the banner states the contract
(`byeharu\supabase\migrations\20260618000349_a_fleet_comes_home_together.sql:535`):

```sql
-- ═══ SELF-ASSERTS — the whole file rolls back if any of these fails ══════════════════════════════
```

**Assert (a) — the vocabulary is read out of the schema, never typed into the assert** (`:537-581`):

```sql
do $a$
declare v_def text; v_vals text[]; v_v text; v_live int := 0; v_dead int := 0;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint where conrelid = 'public.fleets'::regclass and conname = 'fleets_status_check';
  if v_def is null then
    raise exception '0349 ASSERT (a) FAIL: fleets_status_check is absent — the status vocabulary has no authority to check against';
  end if;
  select array_agg(m.parts[1] order by m.parts[1]) into v_vals
    from regexp_matches(v_def, '''([a-z_]+)''::text', 'g') as m(parts);
  if v_vals is null or array_length(v_vals, 1) <> 6 then
    raise exception '0349 ASSERT (a) FAIL: fleets_status_check admits % value(s) (want the 6 this file classifies: %). A status was added or removed and public.fleet_is_live was not revisited.', …;
  end if;
  …
  -- named, both ways — a count alone would pass a predicate that classified the wrong four.
  if not (public.fleet_is_live('idle') and public.fleet_is_live('moving')
          and public.fleet_is_live('present') and public.fleet_is_live('returning')) then
    raise exception '0349 ASSERT (a) FAIL: a live status is classified terminal — ''idle'' being on the wrong side of this line IS the owner''s bug';
  end if;
  if public.fleet_is_live(null) then
    raise exception '0349 ASSERT (a) FAIL: fleet_is_live(NULL) is true — an orphan probe would read a NULL-status fleet as live';
  end if;
  if not public.fleet_is_live('a_status_invented_after_0349') then
    raise exception '0349 ASSERT (a) FAIL: an unknown status reads as TERMINAL. The predicate must be the complement of the terminal set, so that a future omission declines to reconcile rather than scattering a fleet.';
  end if;
end $a$;
```

Note four things: the vocabulary is **read from the `CHECK` constraint**, so a seventh status added
later fails this on the next apply (`:539-542`); classification is asserted **by name in both
directions**, because *"a count alone would pass a predicate that classified the wrong four"*
(`:568`); `NULL` and an unknown value are both tested; and the fail-safe **direction** is asserted,
not just the happy path.

**Assert (b) — written so it CANNOT pass vacuously** (`:583-620+`). Its own header states the
technique (`:584-589`):

> *"This is the assert the brief asks for, and it is written so it CANNOT pass vacuously:*
> *· a CONTROL string carrying the banned shape is counted first, and the block raises if the
> counting expression fails to find it — so a zero on the real bodies means "absent", never "the
> probe is broken";*
> *· every zero-count is paired with a POSITIVE count on the same body … so an empty or missing
> body cannot satisfy it either."*

In code: the probe is first run against a control string that **must** match (`:601-607`); then, for
each target function, the body is fetched from `pg_proc.prosrc` with **line comments stripped**
(`regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')`, `:611-613`), rejected as *"absent
or implausibly short"* if under 500 chars (`:614-616`), and a **positive control** confirms the new
authority is actually composed in that body (`:618-621`) before any zero-count is trusted.

**These four moves — read the vocabulary from the schema, assert both directions, prove the probe
works on a control, and pair every zero with a positive — are the whole technique. Carry them.**

## 4.6 The per-slice build loop

`byeharu\docs\HOW_ITS_BUILT.md:100-106`:

```
architect (read-only)  →  implementer (own worktree)  →  adversarial reviewer
       →  real-Postgres CI apply-proof  →  owner-gated deploy
```

1. **Architect — read-only, cites `file:line`, re-derives the inventory by grep** (`:108-118`). The
   movement charter's own inventory of *"four copies of the dock-read logic"* was actually **five**;
   the fifth used no table alias and matched no grep any architect had written. *"**A charter
   inventory is a CLAIM, not evidence — re-derive it by grep at the head of any slice that consumes
   it.**"* The charter records being wrong about its own numbers **eight times**, and that is
   treated as expected, not embarrassing.
2. **Implementer — its own git worktree** (`:120-125`). *"Concurrent slices never share a working
   tree (two writers stomping the same git state is exactly the kind of accidental coupling the
   no-spaghetti law forbids at the process level, not just the code level)."*
3. **Adversarial reviewer — whose explicit job is to break it** (`:127-138`). Not *"does this look
   reasonable"* but *"how does this fail."* A 5-agent recon found **two real bugs that thirteen
   green CI markers had missed.** The lesson, verbatim: *"**A proof pins the property you thought
   of; it says nothing about the one you didn't. 13 green markers and two real bugs coexisted
   comfortably.**"* And the review's job extends to auditing the guards themselves: *"verifying that
   a guard FAILS is not optional … only the mutation tests exposed it."*
4. **Real-Postgres CI apply-proof** (`:140-167`) — §1.15.
5. **Owner-gated deploy** (`:169-179`). *"CI green does not mean production changes."*
   `byeharu\docs\PROD_GATE_APPROVAL_POLICY.md:29-40` is the policy, written after the boundary was
   tested for real: **(1)** approval of any `production` gate is a human responsibility and the
   assistant must never approve on its own initiative; **(2)** *"Explicit, per-run delegation only …
   A general or standing 'you handle approvals from now on' is **not** sufficient"*; **(3)**
   *"Waiting/visibility states are never permission."*

## 4.7 Verify-first, and never assume

`byeharu\docs\HOW_ITS_BUILT.md:185-198`: a prior session's notes claimed the assistant only held the
anon key. The next session **tested it** instead of repeating the claim, found `.env.local` carried
working service credentials, and recorded the lesson: *"a handoff note claiming 'the assistant lacks
X' is a point-in-time guess and **decays** — spend the 30 seconds to TEST access before believing
it."*

The same discipline produced a production finding a synthetic fixture could never surface: four
ships sat at `status='traveling'` with nothing holding them; live queries established from the
actual rows that **zero** `fleet_movements` were unresolved and every stuck ship's own fleet was
already `present` at a real port — *"the ship's `status` field was lying, and the fleet layer
already knew the truth."*

## 4.8 Constraints, locking, idempotency

`byeharu\docs\ARCHITECTURE.md:226-237` — carry all four verbatim:

- **DB constraints, not just app logic** — `quantity >= 0`, `travel_seconds > 0`,
  `arrive_at > depart_at`; enums/CHECKs for statuses.
- **Uniqueness via partial unique indexes** — one active movement per fleet, one active presence per
  fleet. *"(A fleet can't be in two places … at once.)"*
- **Row locking** — *"all processors use `FOR UPDATE SKIP LOCKED` (cron jobs can overlap → would
  otherwise double-arrive / double-reward … / dup return)."*
- **Idempotency** — *"every processor safe to run twice. Guard with `resolved_at`, `ended_at`,
  `report_created_at`, `reward_granted_at`, `return_movement_id`."*

Plus the per-row isolation lesson (`byeharu\docs\HOW_ITS_BUILT.md:252-261`): a 7-agent audit found
the two hottest crons ran every row in one transaction with no per-row exception isolation, so
**one failing row aborted the entire tick, for every player, forever, on every re-run.** The fix
applied the same per-row `begin/exception` subtransaction the build-queue engine already used
(compose, don't fork). It shipped with **no flag at all**, *"because a strictly-safer error path
with a byte-identical success path needs no dark gate — it's simply correct."*

## 4.9 Repoint → soak → drop, for anything irreversible

`byeharu\docs\HOW_ITS_BUILT.md:210-218`: *"Dropping a column or a function that's still load-bearing
is a one-way door, so the retirement sequence is deliberately ordered to make the door safe before
it's used: repoint every read/write onto the new authority first (each repoint its own small,
reversible migration, byte-parity checked), let production run on the new path for a real soak
period so any missed caller surfaces as a live error rather than a silent gap, and only then drop
the old schema — itself gated by a drain-assert that refuses to run if anything still depends on
what's being dropped."*

## 4.10 Never retype a live function body — SLICE it

`byeharu\docs\HOW_ITS_BUILT.md:239-247`:

> *"When one rule had to be replaced inside five large deployed functions at once, none of them were
> retyped. A generator (`scripts/gen-0305-sortie-authority.mjs`) **slices** each guard's exact text
> out of the migration that currently defines it; the migration then finds that text in
> `pg_get_functiondef`, asserts it occurs **exactly once**, replaces it, asserts the length delta
> equals the hunk delta, and re-executes. Body parity outside the hunk becomes a property of the
> method instead of a review promise, and a miss raises and rolls the whole deploy back. This exists
> because `0303` recorded the opposite: a hand re-creation of the intercept resolver silently
> dropped a progress gate, the cancel-pending calls and a fleet-identity revalidation — it would
> have **reintroduced the bug it claimed to fix**."*

The generator itself: `byeharu\scripts\gen-0306-dock-authority.mjs:4-8` restates it, and `:28-40`
shows the mechanism — a `slice(from, to, startsWith, endsWith)` helper that **asserts the fence
lines**, so source drift fails loudly instead of silently slicing the wrong text.

**And the CRLF rule lives here** (`gen-0306-dock-authority.mjs:21-26`):
> *"LINE ENDINGS ARE PART OF THE CONTRACT. The hunks below are matched against `pg_get_functiondef`,
> whose text comes from the migration as APPLIED — always LF. A Windows checkout (`core.autocrlf`)
> hands this script CRLF, so slicing naively bakes `\r` into every `old_t` and the rewrite can then
> never find its hunk: the migration fails the deploy with 'expected exactly 1'. **Normalise on
> read** and refuse to emit anything carrying a CR."*

Implementation: `const lines = readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n').split('\n')`
(`:26`).

## 4.11 Activation is a human act, and it is documented

`byeharu\docs\ACTIVATION_GUIDE.md:3-9`: the `scripts/activate-*.{sql,sh}` scripts each flip an
already-built, already-deployed dark system live. *"They are **human tools** — never CI, nothing
flips at build/deploy time; each run is the recorded human go decision. Every `[D]` number below is
**OWNER-TUNABLE**."* And the shape: *"Every script is one all-or-nothing `begin … commit`
transaction, precondition-guarded (running it on an unready substrate RAISES, never corrupts), with
a commented rollback and a green `.sh` selftest."*

The guide also records **flip-order dependencies** (`:46-53`) — e.g. the deck-affinity knob is
hard-gated on captains being lit, because *"the bonus scales a captain's contribution and is a dead
knob while captains are dark"*; and the shipyard flip runs *"a per-ingredient reachability check
that RAISES if any recipe ingredient has no live faucet."*

**The lesson byeharu paid for** (`byeharu\docs\HOW_ITS_BUILT.md:328-336`): a whole category of
finished-but-dormant systems sat behind flags waiting on human decisions, and the shipyard flip is
singled out as *"the #1 audit gap"* — the closed valve (`blueprint_fragment_drop_rate` seeded at
zero) that made two whole hull classes *"technically craftable but practically unbuildable until a
human deliberately opened the faucet."*

> **Voyage rule:** a dark system's activation script and its **preconditions** are part of the slice
> that builds it, not a later chore. And a knob seeded at zero is a closed valve — write it down.

---

# 5. RISK LEDGER — the traps this codebase learned the hard way

## 5.1 CRLF silently corrupts sliced SQL and fails the deploy

**Found:** `byeharu\.gitattributes:1-21`; `byeharu\scripts\gen-0306-dock-authority.mjs:21-26`.
**The trap:** 293 of 323 migrations were CRLF in the Windows working tree while LF in the index.
Slicing bakes `\r` into `old_t`; `pg_get_functiondef` returns LF-only; the hunk matches zero
occurrences; the migration's own guard raises *"guard text occurs 0 time(s)"* and the whole deploy
rolls back. It only bites a local `db push` from Windows, **because CI checks out the LF index and
never sees it — the machine that hits it is the machine with no CI to catch it.**
**Prevention in voyage:** `.gitattributes` before any SQL exists (done), extended to `*.mjs` and
`*.sh`; every generator normalises on read and refuses to emit a CR.

## 5.2 Prod GRANT drift — `anon`/`authenticated` can write a table no migration ever opened

**Found:** `byeharu\supabase\migrations\20260618000254_worldeditor_publish_zone_create.sql:404-411`;
posture note at `byeharu\supabase\config.toml:19-24`.
**The trap, in the migration's own words:**
> *"`danger_zones` is THIS command's write target: revoke any client direct-write grant so the ONLY
> write path is the SECURITY DEFINER body. **Supabase project defaults (GRANT ALL on new public
> tables) can leave INSERT/UPDATE/DELETE open on the table even though no migration widened it**;
> every sibling publish slice revokes its own table."*

The line that closes it:
```sql
revoke insert, update, delete on table public.danger_zones from anon, authenticated;
```
Two properties make it safe: **SELECT is preserved** because the flag-gated read depends on it (and
a self-assert verifies SELECT survives), and it is **idempotent** — revoking a privilege the role
does not hold is a silent no-op, so a fresh-chain CI apply-proof stays green.
**Prevention in voyage:** every migration that creates a table **explicitly REVOKEs client
table-write in the same file**, and asserts it. Do not rely on the project default; `config.toml`
notes that `auto_expose_new_tables` is deprecated and the field is removed 2026-10-30 — **do not
depend on either behaviour.** Write the REVOKE.

## 5.3 A vacuous assert reads as coverage and is worse than no check

**Found:** `byeharu\supabase\migrations\20260618000349_a_fleet_comes_home_together.sql:584-621`;
`byeharu\scripts\check-plpgsql-parse.mjs:53-58`; `byeharu\docs\HOW_ITS_BUILT.md:220-237`.
**The trap:** an assert that searches a function body for a banned token passes trivially if the
probe is broken, the body is missing, or the search expression stops working.
**Prevention:** the four moves in §4.5 (control string, minimum-length rejection, positive control,
both-directions naming); plus `--require-*` non-vacuity floors on any scanning tool. *"a check that
cannot fail is not a check."*

## 5.4 Four ways a proof lies by staying green

**Found:** `byeharu\docs\HOW_ITS_BUILT.md:220-237`. All four were hit in one afternoon on slice
`0305`, so they are written down rather than re-learned:

1. **Probe code, not prose.** A self-assert searched `pg_proc.prosrc` for a table name to prove a
   retired guard was gone, and went red on a function whose *explanatory comment* mentioned the
   table. Any "this token must be absent" check has to `regexp_replace` the SQL line comments away
   first.
2. **A writer is not a copy.** The next version forbade *any* mention of the table — and condemned
   the table's legitimate **sole writer**. *"'Is this the retired rule?' means a **read**
   (`from`/`join`), never a mention."*
3. **A green check can assert a rule the code no longer has.** A shell runner demanded the retired
   guard inside a *historical* migration's body. Because that file never changes, the check would
   have stayed green **forever** while the live behaviour was the opposite. *"That reads as coverage
   and is worse than no check at all — when a rule is retired, its proofs are part of the change."*
4. **A green on an old chain is not evidence.** A red proof was nearly dismissed by pointing at two
   green runs from the day before — which turned out to be on a branch cut ten days earlier, whose
   migration chain stopped 70 migrations back. ***"Compare the chain, not the colour."***

## 5.5 N copies of one rule — the spaghetti signature

Three documented instances, each with a count:

| Slice | Copies | The rule | Source |
|---|---|---|---|
| `0305` | **7 copies, 5 functions, 4 shapes, 3 different key sets** | *"is this group on a sortie?"* | `20260618000305_one_sortie_authority.sql:17-23` |
| `0306` | **11 copies, 3 of them inside one function** | *"is this fleet docked?"* | `20260618000306_empty_fleet_dock_authority.sql:25-29` |
| `0349` | **3 readers, each having grown its own private defence against the same rot** | *"is this fleet's recorded return port still meaningful?"* | `20260618000349_…sql:43-54` |

The `0305` header names the tell (`:20-23`): *"One comment even reads 'the mover/brake guard
VERBATIM', recording the copy as if that made it safe. **A rule with seven authors has no
author.**"* The `0349` header names the disease (`:52-54`): *"**N readers defending against a fact
nobody owns.** This file does not add a fourth defence. It gives the fact ONE owner."*

**And the cost, in the owner's own words** (`0349:8-9`): *"Everything is messed up when we make or
change one thing, spaghetti. What is the point of having law and rules?"*

**Prevention in voyage:** when a predicate is about to be written a second time, it becomes a
function. When it is found a third time, stop the feature and fold it — **the same turn**.

## 5.6 A duplicate migration version deploys as a silent no-op

**Found:** `byeharu\scripts\check-migration-versions.mjs:2-21`. **Happened four times**
(`b813fa9` 0332/0333, `90b075b` 0318/0319, `43065d1` 0251/0253, `11acbfc` 0317/0331), and a human
eye caught every one; nothing in `.github/workflows` or `scripts` checked for it.
**Prevention:** carry the guard, and put it in the **required** status check — otherwise it merely
notifies (`:13-15`).

## 5.7 A dark client gate against a lit server flag is invisible to every proof

**Found:** `byeharu\src\features\map\osnReleaseGates.ts:24-29`:
> *"a gate left dark AFTER its server flag was lit is invisible to every proof in the repo — the
> client suite cannot see production's `game_config`, and the server proofs cannot see a
> compile-time constant. `TRADE_MARKET_ENABLED` sat false for weeks against a lit
> `trade_market_enabled`, and the only symptom was a player who could accept haul contracts and
> never source the goods."*

`:34-40` gives the full damage: `market_buy` was the only producer of `ship_cargo_lots` a player
could reach, so with the panel unmounted **production held ZERO cargo lots in the entire game**,
which made every accepted haul contract undeliverable (`insufficient_cargo`).
**Prevention:** prefer `isServerLit` (mechanism 3, §1.14). If a compile-time mirror is unavoidable,
pair it with a spec — byeharu's is `tests\portTradeSurface.spec.ts` — that makes a dark mirror gate
an **explicit, named decision** instead of a silent default.

## 5.8 A number in a comment is not a measurement

**Found:** `byeharu\src\app\navTabs.ts:28-51`. The nav's "five tabs maximum" ceiling was an estimate
that had never been rendered — and it was wrong (six fits, measured 53.33 × 56px). The comment cites
the precedent that made this a rule rather than an anecdote: *"a stale numeric justification is
exactly how the reposition-teleport bug survived (`0311` justified a teleport with 'weapon range
120+'; `0316` cut every range to 5-6; the comment was never revisited)."*
Even the corrected paragraph draws its own boundary (`:46-51`): seven cells is *"ARITHMETIC ON A
MEASURED DIVISOR, not a rendered result — seven has never been rendered."*
**Prevention:** if a number gates a decision, a proof produces it.

## 5.9 A client mirror of a server formula rots into a second authority

**Found:** `byeharu\src\game\movement\travelPreview.ts:1-15` (quoted in §3.4). The client carried
`previewTravelSeconds` with its own `DEFAULT_TRAVEL_SCALE = 1.0` / `DEFAULT_MIN_TRAVEL_SECONDS = 5`
while production ran those values out of `game_config`. Nothing imported it — *"and reading this
file was enough to believe the client still computed ETAs."*
**Prevention:** a preview ETA comes from an RPC that resolves the same speed the mover will use.
Delete dormant formulas rather than keeping them "in case."

## 5.10 A verifier that writes global config can wreck a live game

**Found:** `byeharu\scripts\lib\require-disposable-db.mjs:5-18` (§1.12). Six verifiers wrote global
`travel_scale`/`min_travel_seconds`; **the audit found production movement rows whose arithmetic is
only possible under those values.**
**Prevention:** carry `require-disposable-db.mjs` verbatim and call it **before the first write of
any kind**. No environment-variable escape hatch — ever.

## 5.11 An action can be invisible while every proof is green

**Found:** `byeharu\src\components\ui\overlayLayout.ts:54-83` (§1.5). *"right now i can't press
hunt"* — 8 of 44 pixels on screen, because the height cap lived at the call site, above the control.
**Prevention:** the reach law, the account/reach split, and a **build-failing** lint that forbids a
call site from capping or scrolling a container that holds controls.

## 5.12 A missing config key is indistinguishable from a failed read

**Found:** `byeharu\src\lib\catalog.ts:33-41`, called out by name at
`byeharu\src\features\combat\retreatCountdown.ts:11-12`: `fetchGameConfig` builds a plain record from
whatever rows came back, *"so a key is simply ABSENT on a partial read — `??` cannot tell 'missing'
from 'never fetched'."*
**Prevention:** every config consumer takes `value: unknown` and returns `T | null`, and a `null`
renders as **no claim**, never as a plausible number (`retreatCountdown.ts:17-22`).

## 5.13 A polling hook without an in-flight guard and a sequence token reorders reality

**Found:** `byeharu\src\features\combat\useCombat.ts:26-36` (quoted in §3.1). Both mechanisms are
needed; neither alone is sufficient.
**Prevention:** voyage's fleet-position poll gets `inFlight` + `seq` + an ask-ledger from its first
commit.

## 5.14 Production is a live multiplayer game — never canary with a real asset

**Found:** `byeharu\scripts\set-knob.mjs:22-24` (*"a knob write here is visible to every player
immediately"*); `byeharu\.github\workflows\deploy-migrations.yml:9-13`;
`byeharu\supabase\migrations\20260618000306_empty_fleet_dock_authority.sql:44-48` — the **blast
radius** paragraph, which states exactly which rows the backfill touches and why no player asset can
be inside one.
**Prevention:** every migration that backfills or mutates existing rows states its blast radius in
its own header, in writing, before the SQL.

## 5.15 A whole test suite can be absent from CI without anyone noticing

**Found:** `byeharu\.github\workflows\frontend-tests.yml:4-7`: *"the `tests/*.spec.ts` suite … never
ran in CI, so a red frontend spec was able to land on `main` uncaught."*
And `byeharu\scripts\check-migration-versions.mjs:13-15`: *"As of 2026-08-04 `build` is the ONLY
required status check on main … **Every other proof in this repo can go red and the merge still
proceeds.**"*
**Prevention:** in voyage, make `build` + `frontend-tests` + the offline SQL gate **all required**
from the first PR, while the cost of doing so is zero.

## 5.16 An inventory is a claim, not evidence

**Found:** `byeharu\docs\HOW_ITS_BUILT.md:108-118`. A charter's own inventory of "four copies" was
five; the fifth used no table alias and matched no grep anyone had written. The charter *"records
being wrong about its own numbers **eight times** over its life."*
**Prevention:** **re-derive by grep at the head of every slice.** Never carry a count forward from a
document — including this one.

---

## Appendix A — the order to build in

1. `.gitattributes` (extended), `.gitignore`, `.env.example`, `package.json`, the four `tsconfig`s,
   `vite.config.ts`, `eslint.config.js`. — §1.7–1.9
2. `src/index.css` tokens (re-skinned), `src/components/ui/*` (all primitives), `src/lib/supabase.ts`,
   `src/store/authStore.ts`, `src/features/auth/AuthPage.tsx`. — §1.1–1.6
3. `src/app/*` with a voyage tab table + `tests/navTabs.spec.ts` + `tests/navFits.uispec.ts`. — §1.4
4. `scripts/check-migration-versions.mjs`, `scripts/check-plpgsql-parse.mjs`,
   `.github/workflows/build.yml` + `frontend-tests.yml` + a first disposable-matrix proof workflow.
   **Before migration 0002.** — §1.10, §1.11, §1.15
5. `docs/SYSTEM_BOUNDARIES.md` with one row, and migration `0001` with a self-assert. — §4.1, §4.5
6. `scripts/lib/verify-harness.mjs` + `require-disposable-db.mjs` + `env.mjs`;
   `src/lib/gameConfigFold.ts`; `scripts/list-knobs.mjs` + `set-knob.mjs`. — §1.12, §1.13
7. `.github/workflows/deploy-migrations.yml` with the `production` environment gate, and
   `docs/PROD_GATE_APPROVAL_POLICY.md`. — §1.15, §4.6

## Appendix B — measured sizes (for scale)

| Area in `byeharu` | Files | LOC | Verdict |
|---|---:|---:|---|
| `src/features/worldeditor` | 99 | 14,929 | LEAVE (salvage ~0) |
| `src/features/map` | 60 | 11,992 | LEAVE ~9,000 · salvage ~550 |
| `src/features/ship` | 22 | 3,753 | ADAPT most |
| `src/features/command` | 22 | 3,588 | ADAPT ~700 |
| `src/features/port` | 20 | 3,406 | ADAPT — richest source |
| `src/features/combat` | 23 | 2,555 | LEAVE (salvage 3 modules) |
| `src/features/assets` | 6 | 1,253 | ADAPT |
| `src/features/captains` | 7 | 1,008 | ADAPT |
| `src/components/ui` | 20 | 1,020 | **CARRY** |
| `src/features/modules` | 3 | 563 | ADAPT |
| `src/features/portentry` | 5 | 550 | **CARRY the shape** |
| `src/lib` (7 files) | 7 | 405 | mixed — §1.13, §1.14, §1.17, §3.5, §3.6 |
| `src/features/inventory` | 5 | 350 | ADAPT |
| `src/features/investment` | 3 | 380 | ADAPT |
| `src/features/exploration` + `mining` | 6 | 560 | **exemplar template** |
| `src/app` | 6 | 363 | **CARRY** |
| `src/features/ranking` | 3 | 254 | ADAPT |
| `src/features/events` | 3 | 161 | ADAPT |
| `src/features/auth` | 1 | 107 | **CARRY** |
| `src/features/fleets` | 2 | 107 | ADAPT (fix the throwing) |
| `src/features/uiassets` | 3 | 71 | ADAPT |
| `src/store` | 1 | 47 | **CARRY** |
| `src/features/base` | 2 | 45 | LEAVE |
| `src/game` | 1 | 19 | LEAVE (read the header) |
| `supabase/migrations` | 333 | — | conventions only; **chain starts at 0001** |
