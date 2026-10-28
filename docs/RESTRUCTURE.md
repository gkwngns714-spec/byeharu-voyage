# The restructure: every rule in one place, every object in one file (DESIGN, not built)

Status: design for the owner, 2026-10-28. **Nothing here is built and nothing on prod changed.**
Prod head at writing: **0265** (254 rows in `supabase_migrations.schema_migrations`; read-only query).
Every count below was re-measured for this design: the live function bodies were read from prod with
one read-only catalog SELECT (`pg_get_functiondef`, all `provolatile = 's'`), the client from this branch.
Line numbers like `world.good_board:180` are lines of the LIVE body as `pg_get_functiondef` prints it.

The owner's order (2026-10-28): *"make the game organized, make it so that it doesn't entangle. This is
the big time for you to undergo core changes of the game, codewise, structure, so that it will be
organized, and later development will not bump into one another."* The law it serves:
`docs/NO_SPAGHETTI.md` — one authority per concept; compose, don't copy; retire the old path in the same
slice; delete rather than add.

Already approved and built on: `docs/CHAIN_BASELINE.md` (S1 merged as #365: the builder and its proof
job). The owner approved the prod `migration repair`, retiring the never-from-zero law at S3, wiping local
saves once, and re-baselining by hand. This design puts S2 and S3 first (section 6).

---

## 0. The short version

1. The game's server rules live only as patches on patches. No file shows a function as it runs today:
   194 of the 254 migrations read a live body and splice text into it, and every one of the newest 29 does.
2. Because nobody can see a whole function, the same rule got copied: sea days are worked out 12 times in
   7 functions, the voyage clock in 11 functions, a tax switch twice, a price mark two different ways.
3. Fix the root first: after the chain is folded into one baseline (S2, S3, already approved), every
   function, table and view gets ONE file, filed by game area ("domain"), under `supabase/domains/`.
4. A change is made by editing that file. A tool writes the migration from it, with its safety checks.
   Reviews then show the real old and new body.
5. Then each copied rule gets one named function, every caller uses it, and the copies are deleted.
   Each of these slices proves the game gives exactly the same results before and after.
6. The client gets the same treatment: the knob copies and the client's own day sums go, the hand-typed
   RPC list is generated, and the 983-line store is split by area.
7. Checks that fail the build stop it from tangling again. Today the two guard specs do not block a merge.
8. 16 slices, in order, each small and shippable on its own. Several run side by side because no two
   touch the same file.
9. Players see nothing change. There are about 10 short deploys over roughly a week and a half
   (estimate). Local browser saves are wiped once, at the cut, as already approved.
10. Three questions for the owner are at the end. Each has a default, so nothing waits on them.

---

## 1. What is tangled, re-measured on 2026-10-28

| # | tangle | where (live body lines at prod 0265, or `file:line`) | fixed in |
|---|---|---|---|
| 1 | **sea days `nm / speed / 24`, 12 copies in 7 functions**, with three roundings (2 dp, 1 dp, exact) and two speed floors (`greatest(speed, 0.1)` vs `speed > 0`) | `cmd.do_sail:142` · `voyage.leg_refusal:35` · `voyage.stores_need_days:10` · `world.trade_routes:159,161` · `world.good_board:180,189,284,306,321` · `public.npc_plan:214` · `public.npc_leg_lines:114`. Sailing hours from `nm / speed` also in `voyage.depart:32`, `world.good_board:102,159,286`, `public.npc_plan:218`. Client copy `daysAt`: `src/domain/passage/legs.ts:19`, used at `planLines.ts:149`, `PlanVoyage.tsx:137`, `TradeMap.tsx:264,290`, `useShipPath.ts:62` | A1, C4 |
| 2 | **the voyage clock** (sim-hours or voyage-days to real seconds through `time_compression`) **in 11 functions** | `cmd.do_repair:62` · `cmd.run_standing_route:116` · `public.npc_plan:45` · `voyage.arrival_at:30,35` · `voyage.day_end_from:14` · `voyage.day_ends_at:24` · `voyage.depart:38` · `voyage.keep_due_at:12` · `voyage.recompute_eta:16` · `world.good_board:102,159,286` · inverse in `voyage.progress_nm:24`. Client: the mirror `src/lib/format/time.ts:25,28`, plus inline twins `src/live/orderCheck.tsx:96` and `src/app/AppShell.tsx:52` | A1, C4 |
| 3 | **the tax-in-price switch, the same line twice** | `world.price_terms:12` and `world.quote_terms:22` | A2 |
| 4 | **the press (glut mark), two formulas.** The dark arm of `cmd.do_sell` restates the rule without its `−glut_max` floor. Its two knobs are read by every caller | `cmd.do_sell:120-124` vs `public.press_after:8-9`. Knobs read at `cmd.do_buy:84`, `cmd.do_sell:122-124`, `world.quote_priced:49-50` | A3 |
| 5 | **stores a crew eats per day**, multiplied in 5 functions beside the one price (`public.stores_cost`) | `public.npc_plan:216-217` · `public.npc_loop_candidates:54` · `public.stores_topup:15-16` · `voyage.endurance_days:15-16` · `voyage.settle:62-63` | A4 |
| 6 | **hazard effects hard-coded** next to the one hazard catalogue (`public.voyage_event_kinds`, 0035), which has no effect columns | `voyage.settle:225` (FOUL_WATER: `0.10 + 0.25 × magnitude` of the water) · `voyage.settle:242` (SHOAL: `0.04 + 0.11 ×` of the hull) · `voyage.storm_hull_lost:17,19` (STORM `0.08 + 0.17 ×`, written twice) · `voyage.day_delay_hours:11-13` (STORM 36 h, CALM, FAIR_WIND) | A5 |
| 7 | **longitude wrap, 6 sites in 4 functions, three idioms** | `public.lon_in_view:14-15` · `public.sea_leg_asks_derive:31,43` · `voyage.lon_lerp:13-14` · `world.sea_traffic:47,51` | A6 |
| 8 | **client copies of server values** | `TIME_COMPRESSION` `time.ts:25` with `REAL_MS_PER_VOYAGE_DAY` `:28` and `GAME_CLOCK_RATE` `:253` derived from it · `GAME_DAYS_PER_MONTH` `:213` (the served `game_day_seconds` restated as 30) · `CALENDAR_EPOCH_MS` / `CALENDAR_YEAR_0` `:223-224` ("the server keeps no epoch") · `LEVEL_CAP = 20` `src/features/you/YouScreen.tsx:95` (the server hard-codes the same 20 at `public.level_from_points:6`) · per-hull hold `src/domain/fleet/derive.ts:151,165` restates `public.fleet_free_hold:7-8` | C4 |
| 9 | **the client surface written four times**, and the four already disagree | the grants · `public.client_rpc_entry_points()` (a hand VALUES list) · `src/lib/rpc/catalog.ts` (81 entries) · `src/lib/rpc/index.ts` (794 lines, 81 exported functions) + `types.ts` (3,310 lines, 210 types). 4 functions are executable by clients but absent from the catalog: `cmd.fold`, `cmd.parse_number`, `world.affinity_at`, `world.sea_traffic` | C2 |
| 10 | **ROOT: live bodies exist only as stacked hunks**, and nothing checks the server for copies | 194 of 254 migration files read `pg_get_functiondef`. All 29 of the newest (0236–0265) do. `voyage.settle` (385 lines live) is named by 32 files, 4 of which re-create it whole. `tests/duplication.spec.ts` checks `src/` and the migrations' shape (a self-assert, the supersede word), and never compares function bodies | R1, R2, G2 |
| 11 | **the guards do not block a merge.** `tests/sections.spec.ts` and `tests/duplication.spec.ts` run only in Acceptance, which is not a required check (`acceptance.yml:88-89`, CLAUDE.md) | — | C1 |
| 12 | small: 2 import cycles · 5 dead exports · un-i18n'd text · the stats country filter ×3 · `worldStore.ts` 983 lines | cycles `src/domain/order/trip.ts:12` ↔ `index.ts:58`, `src/domain/passage/legs.ts:7` ↔ `index.ts`. Dead: `components/ui/collapsibleState.ts:16,26`, `features/profile/appearance.ts:54`, `lib/db/rescue.ts:211`, `lib/trade/index.ts:56`. The audit's sixth, `authDict`, is a code example inside a comment (`lib/i18n/define.ts:3`): not dead code. i18n: the audit counted 5; re-found by hand `features/command/Queue.tsx:94` (an English sentence built in JSX); the guard lists the rest. Filter: `features/stats/Cities.tsx:48-51`, `Me.tsx:67-70`, `Merchants.tsx:86-88` | C1, C3 |
| 13 | `hold_the_quay` pasted 4× in `tick_reconcile` | **resolved by 0265, live**: the body now calls the one lock at `:53` and `:68`, and the beat calls it once. Nothing to do | — |

Scale, for the plan: 629 functions (cmd 90, public 387, voyage 55, world 97; 482 SECURITY DEFINER),
138 tables, 2 views, 10 cron jobs; 91 functions executable by `authenticated`. 82 of the 85 client-callable
`world`/`cmd` functions return `jsonb`. 266 knob keys are read at 472 places.

---

## 2. A — the server's source of truth

### 2.1 Decision: the repo's own generator, not the Supabase CLI's declarative schemas

Supabase CLI 2.120 has a declarative workflow: `db schema declarative generate` (export a database into
a tree) and `... sync` (diff the tree against the migrations and write a migration). It was weighed first.

| | Supabase CLI declarative | our generator (`db:emit`, on PGlite) |
|---|---|---|
| runs on this PC | **no.** Both commands set up a shadow database (their help text: "force fresh shadow database setup"), which the CLI runs as a local Docker container, and `docker` is not installed here (checked). Every change would have to go to CI to get its migration | **yes.** PGlite, no Docker. The baseline loads in 4.6–6.5 s (S1 dev-log) |
| grants, default ACLs, policies | the diff engine "can leave objects unmanaged" (`--strict-coverage` exists for that case). Its coverage of this repo's grants and default ACLs is **not verified** here (no Docker) | rendered from the catalog exactly (`aclexplode`) and compared on every PR. The lockdown is the oldest law in the chain (0001, 0018) |
| self-asserts and receipts (enforced by `tests/duplication.spec.ts` §4) | not part of a schema diff, so added by hand to every generated file | generated: the pre-image guard, the post-image check and the receipt. The author adds only the behaviour probe |
| folders | the CLI picks the tree's layout | **the folder is the domain** (section 3) |
| repeatable output | pinned CLI; the 2.120 engine choices include an experimental one (pg-delta) | pinned PGlite + pglite-tools, one renderer |
| data rows, pg_cron | out of its scope | data stays in a migration's hand part; cron gets its own file in `clock/` |

**Decided: our own generator.** The folder is named `supabase/domains/`, not `supabase/schemas/`, so the
CLI's default declarative path stays empty and nobody runs the CLI's tool over our files by mistake.
`config.toml` keeps `schema_paths = []`. A guard checks both.

### 2.2 The tree

```
supabase/domains/
  voyage/   voyage.settle.fn.sql   voyage.depart.fn.sql   public.voyages.table.sql   ...
  market/   world.quote_terms.fn.sql   public.press_after.fn.sql   public.port_goods.table.sql   ...
  clock/    public.tick_reconcile.fn.sql   cron.jobs.sql   ...
  ...       (18 domains: section 3.1; every object: Appendix A)
```

* **One file per (schema, name, kind).** A function file holds every overload of that name (one concept).
  A table file holds the table and everything that belongs to it: sequences, defaults, constraints,
  indexes, triggers (the trigger function has its own file), the RLS flag, policies, comments and its ACL.
  768 object files at today's head (628 function names, 138 tables, 2 views), plus `clock/cron.jobs.sql`.
  Measured: no table and function share a schema and name.
* **The text is canonical, rendered from the database, never typed freehand.**
  * Functions and procedures: `pg_get_functiondef(oid)`. This is the text every hunk migration already
    matches against. S1 measured it equal on Supabase (Postgres 17) and PGlite (Postgres 18): the
    allow-list holds no routine line.
  * Tables, views, types, sequences: `pg_dump --schema-only --table=…` through
    `@electric-sql/pglite-tools`, pinned. CHAIN_BASELINE §4 measured pg_dump of PGlite this way with
    0.4.5 on PGlite 0.5.5.
  * ACL lines: rendered from `aclexplode` as explicit `revoke all` + `grant` lines, never pg_dump's
    relative form. S1 found that form loses explicit-default ACLs (88 relations) and 0018's schema-less
    default.
  * `npm run db:fmt <file>` re-renders a hand-edited file: it applies the file to a scratch head in a
    rolled-back transaction and writes back what the catalog says. A hand edit always ends as canonical
    text.
* **What is not in the tree.** Data is not in the tree: seed rows, `world_config` values, the static world.
  The baseline carries them at N. A later data change goes in a migration's hand part.
  `scripts/db/world-guard.mjs` stays the authority for "the world equals `data/*.json`".
* LF only (`.gitattributes` already has `*.sql text eol=lf`), and the renderer refuses a `\r`: the CRLF
  trap that broke slice migrations on this PC before.

### 2.3 How a change is made (the author's whole loop)

1. Edit `supabase/domains/<domain>/<object>.sql`, or add a file.
2. `npm run db:emit -- <name>` boots the head (baseline + tail) in PGlite, renders every object, compares
   with the tree, and writes `supabase/migrations/20260818000NNN_<name>.sql` (NNN = head + 1).
3. Write the hand part between its markers: data changes, and the behaviour probe.
4. `npm run db:apply` applies the tail on PGlite (about 20 s after S3), with its self-assert and the parity check.
5. Push. CI runs `db:emit --check` (the generated sections equal a fresh emission against main's head)
   and parity in `build`, then `disposable-chain` on Supabase. Both are required checks.
6. Deploy exactly as today: `~/bin/bv-deploy.sh <pr>`. If another migration landed first,
   `npm run db:emit -- --renumber` re-emits on the new head. Its pre-images are re-read, so a stale
   emission cannot reach prod.

### 2.4 What an emitted migration contains

```sql
-- ═══ 0270 — <the author's sentence, as today> ═══
-- @generated from supabase/domains at <git sha> by scripts/db/domains/emit.mjs
-- Objects (whole definitions): voyage.days (new), voyage.leg_refusal, cmd.do_sail.  Dropped: none.
-- <the author's header: why, what it proves, rollback — README §2, unchanged>

do $pre$ begin  -- @generated PRE-IMAGE GUARD: refuse unless each object is the body this was emitted against
  perform set_config('search_path', 'public, extensions', true);
  if md5(pg_get_functiondef('voyage.leg_refusal(uuid,uuid,numeric,jsonb)'::regprocedure)) <> '<md5 at head 0269>' then
    raise exception '0270 refuses: voyage.leg_refusal is not the body this file was emitted against (head 0269)';
  end if;  -- … one block per replaced object; for a new object: it must not exist
end $pre$;

-- @generated PRE-IMAGES FOR THE PROBE (only with --keep-old): pg_temp.voyage__leg_refusal__old(…) = the old body
-- @generated OBJECTS: create function voyage.days …; create or replace function voyage.leg_refusal …;
--                     revoke all … ; grant … ; comment on function … ;

-- ── hand-written: data changes (if any) ──

do $assert$ begin
  -- @generated POST-IMAGE: each object equals its tree file (md5 rendered on PGlite at emit time)
  -- ── hand-written: the behaviour probe (old vs new on rolled-back rows, README §3) ──
  raise notice '0270 self-assert ok: 3 objects equal the tree; 3,249 answers old = new';
end $assert$;
```

* The **pre-image guard replaces "each hunk occurs exactly once"**, and it is stronger: it checks the
  whole body, not a fragment. A prod body that drifted makes the push refuse instead of being overwritten.
* **A new function** is emitted as `create function` (not `or replace`), so a name clash fails loudly.
  **A changed signature** emits `drop` + `create` and re-issues the grants (`NO_SPAGHETTI.md` §3, "when
  create or replace is not enough").
* **A deleted file** emits `drop function` only when no other tree file and no client contract names the
  function. Otherwise it refuses and prints the callers. The old path is retired in the same slice by
  construction. Tables are never dropped by the tool: the author writes that by hand and passes
  `--allow-drop-table <name>`.

### 2.5 Tables, views, types, cron

* **Generated:** functions, procedures, views, policies, triggers, grants, comments. A view uses
  `create or replace` while it only appends columns. Otherwise it is dropped and re-created, and the tool
  refuses if anything depends on it.
* **Tables, types, sequences: the author writes the ALTER, the tool proves it.** The author edits the
  table file AND writes the `alter table …` in the hand part. `emit --check` and parity stay red until the
  head renders exactly the edited file, and the message says which line differs. Diffing tables is where
  every diff tool fails, and most of this chain's migrations change functions, not tables.
* **Cron:** `clock/cron.jobs.sql` lists the 10 jobs (name, schedule, command, active state as defined).
  A change emits 0012's guarded `cron.schedule` / `cron.alter_job` block. Parity for this file runs on
  Supabase only, because PGlite has no pg_cron (0012's posture, unchanged).

### 2.6 How every proof survives

| proof | today | after R1/R2 |
|---|---|---|
| a migration proves itself | hand self-assert + receipt | the same, plus the generated pre-image guard and post-image check |
| nothing else moved | per-file "kept" md5 lists (0265 pins 14 functions by hand) | **global:** after every PR, every object in the head equals its tree file (parity in the required `build` job). An unintended change anywhere fails |
| old vs new give the same results | hand-written `pg_temp` copies, plus scratch harnesses (0256's 129-table end to end, `scripts/ops/harness/arrfast`) | `emit --keep-old` writes the `pg_temp` pre-images. `scripts/db/probe/same-world.mjs` (R2) makes the arrfast paired arms one command: same world, arm A = head, arm B = head + migration, N beats from K starts, ties broken by id, every game table digested with uuids blanked, plus a negative control |
| PGlite = Supabase | S1's catalog compare (written allow-list) | the same on baseline + tail, in `disposable-chain` |
| Supabase = prod | S1's `prod-compare`, run by hand | `bv-deploy.sh` runs it read-only after every push (`catalog.sql`, one SELECT) against the tree's render |
| proofs 01–12 (`scripts/db/proofs/`), `world-guard.mjs`, grant lockdown | unchanged | unchanged |

Prod differs from a fresh apply in three named places (S1). All three stay named exceptions of the prod
check: `service_role`'s platform grants in `public`, `public.forbid_mutation`'s explicit-default ACL, and the
instant 0076 wrote into `voyage.assert_paths_water`'s body. That last one means the tree holds the
baseline's instant, not prod's. A slice that ever touches that function must carry prod's literal.

### 2.7 PGlite

* PGlite applies **the migrations (baseline + tail), exactly as today** (`applyChain`). It never applies
  the tree. The browser bundle never carries the tree either.
* For `emit`, `fmt` and parity it renders the head: pglite-tools `pg_dump --schema-only` plus catalog reads.
  Expected cost: the ~5 s load (S1) plus the render (not measured yet; R1 measures it, and the gate is under
  30 s).
* `@electric-sql/pglite-tools` becomes a devDependency (R1). Both it and `@electric-sql/pglite` (today
  `^0.5.5`) get exact versions, so the renderer cannot change under a lock-file refresh. `package.json`
  changing selects the full suite once (rule F of `select-specs.mjs`). That is R1's cost.

### 2.8 Review

* The reviewer reads **the tree diff: the real old and new text of each changed object**, in its domain folder.
* The migration is generated except its marked hand part. CI proves the generated part equals a fresh
  emission, so a reviewer reads only the hand part: the data change and the probe.

### 2.9 What R2 retires, in the same slice

* **The hunk method.** It goes, along with everything built around it: the LF trap, the per-file kept-md5
  lists, and the "say supersede or re-cut" header rule (`tests/duplication.spec.ts` §4). A guard enforces
  it: a migration after the baseline may call `pg_get_functiondef` only inside `@generated` blocks.
* **The text that teaches it is rewritten in R2:**
  * CLAUDE.md: "Sliced live bodies: each hunk…" becomes "Edit the tree, emit the migration".
  * `supabase/migrations/README.md`.
  * `docs/NO_SPAGHETTI.md` §3.
  * `docs/SECTIONS.md`: "Existing migrations are not reorganised" becomes "the tree is organised by
    domain; migrations are delivery".
  * The memory files that teach hunks are marked superseded.
* **What stays:**
  * Never edit an applied migration. It is history.
  * Strict numbering, one migration PR at a time.
  * `db push` before merge (`bv-deploy.sh`).
  * Self-asserts on rolled-back probes; never delete from append-only tables.
  * Prod is read-only for checks.

---

## 3. B — the server domain map

### 3.1 The 18 domains

The Postgres schemas keep their job, which is **who may see it**: `world` holds client reads, `cmd`
client verbs, `voyage` and `public` server internals. `config.toml` exposes them, so renaming them would
change every caller for no game value. **The domain is the folder.** Function names do not change.

| domain | owns | fns | tables |
|---|---|---|---|
| `auth` | who may call what: identity, the client surface, the grant proofs, the append-only guard | 8 | 0 |
| `config` | knobs (`world_config`, `wc*`), feature flags (`*_on`, `*_lit`) and the owner's switches | 24 | 1 |
| `clock` | when things run: the cron schedule, the beats, the quay lock, beat profiles, the game day | 16 | 3 |
| `geo` | the static world and its water: ports, seas, regions, raster, distance, roadsteads, longitude, the snapshot read | 14 | 7 |
| `voyage` | a passage in time: depart, settle, position, ETA, delays, reach, the sail gates, sea days, the voyage clock | 35 | 2 |
| `danger` | what can befall her: hazard kinds and effects, fights, raids, escort, sea conditions, insurance, the dice | 27 | 6 |
| `fleet` | hulls and what they carry: ships, fleets, classes, speed, slots, gear, wear, repair, yards, items, hold, storage | 71 | 26 (+1 view) |
| `supplies` | water and food, provisioning and presets, endurance, crew numbers, wages, running costs | 29 | 3 |
| `people` | captains, officers, skills, traits, cabins, languages, xp and promotion, the inn | 69 | 31 (+1 view) |
| `market` | prices and trading: mid, spread, quote, tax in the price, the press, depth/restock/drift, buffs, tastes, haggling, buy/sell, cost basis, price history | 80 | 17 |
| `city` | a city's economy: treasury and purses, works and buildings, investment and shares, influence and mayor, wants, contracts, port fees | 58 | 13 |
| `powers` | nations and great powers: allegiance, stance, country factor, rulers | 12 | 4 |
| `ledger` | money and the record: credit, ledger, events, reconciliation, debts, gifts, worth | 17 | 3 |
| `houses` | companies: founding, levels, fame, titles, requirements, standings | 17 | 3 |
| `orders` | the command language: parse, issue, queue, preview, refusal, fixes, manifest, divert, tow | 33 | 1 |
| `routes` | standing routes, laps, the route board | 30 | 4 |
| `npc` | merchant companies: found, plan, tend, compact, roster, the traffic reads | 49 | 6 |
| `stats` | folds, windows, live stats, the money feed, the watchlist | 39 | 8 |

Appendix A lists every object. It is a proposal. **R1 finalises it**, and its guard requires every catalog
object to be in exactly one folder. A domain's tick lives in that domain (`tick_market_drift` in `market`,
`tick_city` in `city`). `clock` owns only *when* they run. This is 0010/0012's split (`docs/SECTIONS.md`):
one file owns what a tick does, another owns when it runs.

### 3.2 The shape every authority takes

1. **One concept, one function**, in that concept's domain folder, named for the concept.
2. **A pure leaf.** `language sql`, one SELECT, `immutable` (or `stable` if it reads a table), no
   `security definer`, no `set` clause, every name schema-qualified. Postgres's planner can inline a
   function of that shape into the query that calls it, so composing it costs about what the inline copy
   cost. That is the documented planner rule; **A1 measures it** (beat timing gate). Today's functions are
   mostly `security definer set search_path`, which cannot be inlined, so the shape matters.
3. **A rule's knobs are read by the rule's own knob reader, once per caller, and passed in.** The pattern is
   `public.press_after(…, p_per, p_max)`. The hot paths already hoist knob reads (0264 did it on purpose),
   and this keeps that.
4. **Authorities never round.** A number is rounded only where it is shown (a payload field or a sentence),
   at the precision that field has today. Decisions (gates, scores, ETAs) use exact values. At the 12
   sea-day sites they already do (checked): every rounded value there is a payload field or a sentence.
5. **A caller composes the authority and never restates its arithmetic.** Guard D2 fails a restatement.

### 3.3 The authorities, and every caller to convert

**1. Sea days and sailing hours (A1).** `voyage.sail_hours(p_nm, p_kn)` = `p_nm / p_kn` (null when
`p_kn <= 0`), and `voyage.days(p_nm, p_kn)` = `voyage.sail_hours(p_nm, p_kn) / 24`. They are one concept in
two units, the second composing the first in the order every `(nm / speed) / 24` site already uses.
* Callers: `cmd.do_sail:142` · `voyage.leg_refusal:35` · `voyage.stores_need_days:10` (folds into
  `voyage.days × endurance_margin`) · `world.trade_routes:159,161` · `world.good_board:180,189,284,306,321`
  and its hours at `:102,159,286` · `public.npc_plan:214,218` · `public.npc_leg_lines:114` ·
  `voyage.depart:32`.
* Speed floors (`greatest(speed, 0.1)`) stay at the call site: they are the caller's input, not the rule.
* **Byte-identity risk, said up front.** Two sites associate differently: `npc_plan:214` is `nm / (speed * 24)`
  and `npc_leg_lines:114` is `x * nm / (speed * 24)`. Postgres `numeric` division can then differ in the last
  digits. A1's probe compares exactly those values on the full question set and the paired sim. If one
  differs, it is reported and measured as a change, never shipped as "identical".

**2. The voyage clock (A1).** `voyage.clock_rate()` is the ONE reader of `time_compression`.
`voyage.real_seconds(p_sim_hours, p_rate)` = `p_sim_hours * 3600 / p_rate`, and its inverse is
`voyage.sim_hours_in(p_real_seconds, p_rate)`.
* Callers: `cmd.do_repair:62` · `cmd.run_standing_route:116` · `public.npc_plan:44-45` · `voyage.arrival_at:26,30,35`
  · `voyage.day_end_from:14` (already takes the rate as a parameter) · `voyage.day_ends_at:24` ·
  `voyage.days_complete:22` (reads the knob to pass it on) · `voyage.depart:38` · `voyage.keep_due_at:12` ·
  `voyage.recompute_eta:16` · `world.good_board:24,102,159,286` · `voyage.progress_nm:24` (inverse).
* `world.snapshot:71` keeps serving the knob, through `voyage.clock_rate()::int`. That is the same value,
  and it leaves one reader of the knob, not 12 (measured: 12 functions read it today).

**3. Tax inside a price (A2).** `world.price_tax(p_port)` =
`case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end`.
* Callers: `world.price_terms:12`, `world.quote_terms:22`.
* The lit half stays `public.profit_tax` (the one charge on profit).

**4. The press (A3).** `public.press_after` stays the rule, and `public.press_knobs()` is new (the one
reader of `glut_per_depth` and `glut_max`).
* Callers: `cmd.do_sell:120-124` (its dark arm becomes `press_after(…, 'sell')`) · `cmd.do_buy:82-85` ·
  `world.quote_priced:32-34,49-50,103`.
* The dark arm equals the rule only while every `port_goods.glut ≥ −glut_max`. On prod today (read-only,
  2026-10-28): `price_impact` is false, `glut_max` is 0.30, the smallest glut is 0.0000, and no row is
  negative. **A3 re-reads this before its PR**, because the flag may be lit by then.

**5. Stores per crew-day (A4).** `public.stores_per_day(p_crew)` gives `(water_t, food_t)`, and
`public.stores_cost_days(p_player, p_crew, p_days)` composes `stores_per_day` with `public.stores_cost`
(the one price, 0142).
* Callers: `public.npc_plan:216-217` · `public.npc_loop_candidates:54` · `public.stores_topup:15-16` ·
  `voyage.endurance_days:15-16` · `voyage.settle:62-63`.
* `world.snapshot:77-79` also serves these knobs and `wage_per_crew_day`, but no client code reads them.
  Only `src/lib/rpc/types.ts:185-187` declares them and `tests/rpc.surface.spec.ts:180-182` pins them.
  C4, which owns the served config, deletes all three with their type and pin.

**6. Hazard effects (A5).** `public.voyage_event_kinds` gains effect columns: delay base and per-magnitude
hours, hull base and per-magnitude share, stores base and per-magnitude share. The values are exactly
today's numbers. `voyage.hazard_effect(p_kind, p_magnitude)` reads them.
* Callers: `voyage.settle:225,242` · `voyage.storm_hull_lost:17,19` · `voyage.day_delay_hours:11-13`.
* Proof 01 (offline equivalence) must stay green: the dice do not move, only where the numbers live.

**7. Longitude (A6).** There are three meanings, so three leaves, each written once:
* `voyage.lon_wrap(x)` into [−180, 180): callers `world.sea_traffic:51`, and the `case` wraps in
  `voyage.lon_lerp:13` and `public.sea_leg_asks_derive:43`.
* `voyage.lon_delta(a, b)`, the short way round: callers `voyage.lon_lerp:14`, `public.sea_leg_asks_derive:31`.
* `voyage.lon_span(a, b)` into [0, 360): callers `public.lon_in_view:14-15`, `world.sea_traffic:47`.
* **Boundary risk.** The `case` idiom keeps 180 as 180. The floor idiom turns it into −180. A6's probe walks
  a grid that includes ±180 and ±540, and every stored path. If the idioms disagree on a value the world
  actually holds, A6 stops and reports it before choosing.

**8. The client surface (C2).** The one declaration is the `grant execute … to authenticated` line in each
function's tree file. Two things are generated from it: `public.client_rpc_entry_points()`'s body, and the
client catalog and wrappers (section 4.3). Proof 03 keeps its two-key check: the database's real grants
must equal the generated registry, so a grant made outside the tree still fails.

**9. The calendar and the level cap (C4).**
* `world_config` gains `calendar_epoch` (2026-08-18 UTC) and `calendar_year0` (1500): today's client
  constants, which become the server's, served in `world.snapshot().config`. `game_day_seconds` is already
  served there.
* `level_max` (20) replaces the literal in `public.level_from_points:6` and is served too.

**10. Days for a course the player draws (C4).** `world.passage_days(p_fleet, p_nms numeric[])` is a stable
read composing `voyage.days` with `voyage.fleet_speed`. It replaces the client's `daysAt`.

**11. The room left in one hull (C4).** `public.ship_free_hold(p_ship)` is the per-hull term
`fleet_free_hold:7-8` already sums. The fleet total composes it, and `world.fleets` serves
`ships[].free_hold`. That retires the client's restatement in `domain/fleet/derive.ts:151,165`.

---

## 4. C — the client

### 4.1 The layers, in one table

```
lib/*          machinery (rpc, db, format, geo, sea, i18n, text, json)       may import: lib
components/ui  the design system, one entrance                                may import: lib
domain/*       rules READ from served payloads; pure, no React              may import: lib, domain (by entrance)
chart          how the world is drawn, one entrance                          may import: lib, domain, components
live           the world in memory: the store slices and data hooks          may import: lib, domain  (from C5;
                                                                             until then live still holds faces and
                                                                             imports components, and worldStore.ts
                                                                             calls the chart's registerHullClasses)
faces/*        a part of a screen that two screens draw (new, C5)            may import: lib, domain, chart, components, live
features/*     a screen; never another screen                                may import: all of the above
store, app     session UI state; the shell                                    as today
```

**Enforced by the existing sections spec, turned into one table, not by eslint-plugin-boundaries.**
* The spec already holds these rules, with explanatory messages, at zero findings.
* A second rule system would be two authorities for one boundary.
* A plugin cannot do the other checks below (cycles, dead exports, i18n, client-derives).

C1 moves the rules into `scripts/guards/layers.mjs`, driven by one `LAYERS` table, and runs every guard
inside `npm run lint`. The required `build` job and `deploy-pages` already run lint (`build.yml:115`,
`deploy-pages.yml:110`), so **the guards block a merge from C1 on, with no workflow edit.** The cost is no
editor squiggles.

### 4.2 One vocabulary

The server's domain names are the names everywhere a domain shows up:
* RPC contracts: `src/lib/rpc/contracts/<domain>.ts`
* store slices: `src/live/world/<domain>.ts`
* shared faces: `src/faces/<domain>/`

A change to the market then touches `supabase/domains/market/`, `contracts/market.ts`, `live/world/market.ts`
and `faces/market/`. Anyone can see which work overlaps before it starts. The existing `src/domain/*`
sections keep their names to avoid churn. Each states in its header which server domain it reads.

### 4.3 RPC: generated where the schema knows, hand-written where it cannot

* **Generated (C2) from the tree's grants and the head catalog:**
  * `src/lib/rpc/catalog.gen.ts`: every RPC's schema, name, argument names and casts. This replaces the
    81-entry hand table. Keys are `camel(schema_fn)`: 80 of the 81 already are. The one exception,
    `cmdCancel` for `cmd.cancel_at`, is renamed with its callers.
  * The 4 functions clients may execute but the catalog never lists (`cmd.fold`, `cmd.parse_number`,
    `world.affinity_at`, `world.sea_traffic`) are either given a contract or have their grant revoked.
    C2 decides each one from evidence (a grep of every caller) and says which.
  * `src/lib/rpc/calls.gen.ts`: one typed wrapper per RPC, replacing the 81 hand wrappers.
  * The server registry `public.client_rpc_entry_points()`.
* **Not feasible from the schema:** 82 of the 85 client RPCs return `jsonb`, and the catalog cannot say
  what is inside. So the payload types stay hand-written, but they are split by domain into
  `src/lib/rpc/contracts/<domain>.ts` (no 3,310-line file), and a `Contracts` map names each RPC's type.
  A guard requires the map's keys to equal the client-callable set exactly. `tests/rpc.surface.spec.ts`
  keeps asserting real payloads against them.
* Wrappers that do more than call (for example `readManifestReceipt`) stay as small hand adapters over
  the generated call. `src/lib/rpc/index.ts` stays the one entrance, so no screen's import changes.
* **Byte-identical:** C2 asserts the generated catalog deep-equals the hand table before deleting it, and
  that every wrapper calls the same key with the same argument order.

### 4.4 The store, split by domain (C3)

`useWorld` stays ONE zustand store, the same subscription surface and the same selectors, built from slices
by zustand's slices pattern:
* `src/live/world/core.ts`: snapshot, fleets, refresh, the lookups
* `market.ts`: markets, series, reach, buffs, watch
* `orders.ts`: issue, lines, manifest, fulfil, preview, cancel, clear, divert, haggle, refusal
* `routes.ts`
* `people.ts`: officers, skills, hire, enrol, queue
* `houses.ts`: player, standings, allegiance
* `traffic.ts`

`worldStore.ts` becomes the composer, about 60 lines. The 983-line file goes. A spec pins the store's key
set: the same keys before and after.

### 4.5 The client never derives a server figure (C4)

| copy today | after C4 |
|---|---|
| `TIME_COMPRESSION` mirror and its two derived constants (`time.ts:25,28,253`), plus inline twins `orderCheck.tsx:96`, `AppShell.tsx:52` | `src/live/clock.ts`, set once from `snapshot.config`. The format functions take the served clock. `GAME_CLOCK_RATE` stays a client presentation rule (the owner's Sun pace, which no server function reads), computed from the served rate |
| `GAME_DAYS_PER_MONTH = 30` (`time.ts:213`) | read from the served `game_day_seconds` |
| `CALENDAR_EPOCH_MS`, `CALENDAR_YEAR_0` (`time.ts:223-224`) | served (`calendar_epoch`, `calendar_year0`) |
| `LEVEL_CAP = 20` (`YouScreen.tsx:95`) | served `level_max` |
| `daysAt` (`legs.ts:19`) at five call sites | served `days` where a read already carries it (`good_board`, `trade_routes`, a SAIL preview). For a drawn course, `world.passage_days`. Until it answers, the screen shows the miles, never a guessed day count (`NO_SPAGHETTI.md` §7C) |
| `shipHoldUsed` / `shipHoldFree` (`derive.ts:151,165`) | served `ships[].free_hold` |
| `water_per_crew_day`, `food_per_crew_day`, `wage_per_crew_day`, served (`world.snapshot:77-79`) and read by no client code | deleted from the snapshot, from `types.ts:185-187` and from the pin in `rpc.surface.spec.ts:180-182` |

**The rule from C4 on:** the client may hold a number only if no server function reads the same concept.
D3 enforces it. C4 lands **server and client together**, one slice (`never-ship-half-a-slice`).

### 4.6 Shared faces leave `src/live` (C5)

`src/live` holds 80 files and mixes the store, data hooks and React faces that two screens draw
(`PortInn`, `MerchantSheet`, `PriceTray`, …: `docs/SECTIONS.md`). C5 moves the faces into
`src/faces/<domain>/`. `live/` then holds only data, and two features working on the port and the market
stop editing the same folder. It is a pure move with the imports rewritten. The one data-to-drawing call
goes too: `worldStore.ts` registers hull classes into the chart (`registerHullClasses`); after C5 the
chart's caller passes them in as a parameter. Gates: the guards, typecheck, build, headless screenshots of
the moved faces (phone and wide) equal before and after, and the full Acceptance on main.

---

## 5. D — the guards that stop it re-tangling

All the static guards run in `npm run lint`, so they block in the required `build` job from C1 on. Total
expected time is under 15 s; each guard prints the fix in its message, as the current specs do.

| guard | checks | lands in |
|---|---|---|
| D1 layers | the `LAYERS` table: every import points down; one entrance per section, chart and design system; no screen imports a screen. These are `tests/sections.spec.ts`'s rules, moved | C1 |
| D2 server formulas | over `supabase/domains/**` (static, no database): **(a) named rules**, one file per rule in `scripts/guards/server/`, holding the authority, a pattern over comment-stripped, whitespace-collapsed SQL, and a pinned debt that only shrinks. For example, `voyage-days` fails a `nm / speed / 24` outside `voyage.days`. **(b) fingerprints:** normalised arithmetic windows (locals replaced, literals and knob keys kept, 9 tokens, at least 2 operators) appearing in 2 or more files. Today's collisions are measured and pinned at G2, so a new copy of any formula fails. **(c) knob ownership:** a knob owned by a rule (`glut_max`, `water_per_crew_day`, `time_compression`, …) is read only by that rule's reader. A planted copy is the negative control | G2; each A-slice zeroes its rule's debt |
| D3 client derives | no `const` in `src/` named after a `world_config` key (`TIME_COMPRESSION`, …); no client arithmetic for a rule the server owns (miles over speed over 24; voyage-days to real time). The message names the served field to read | C1 (with a debt ledger) → zero in C4 |
| D4 cycles | Tarjan's strongly connected components over `src/`'s import graph: none, including `index.ts` cycles inside a folder | C1 |
| D5 dead exports | an export that nothing in `src/`, `tests/` or `scripts/` imports and its own file does not use (comment text ignored, unlike the audit's probe) | C1 (`readRescue` stays as one debt entry until S3, which owns `src/lib/db`) |
| D6 i18n literals | JSX text and literal UI props (`label`, `title`, `placeholder`, `aria-label`, `heading`, `hint`, `alt`) in features/live/faces/app/chart/components go through `t()`. Allow-list: the game's name; the design-system gallery (`/ui`, linked from nowhere) | C1 |
| D7 recipes, palette, sizes, skins | `tests/duplication.spec.ts` §1–3, 5, 6, moved unchanged | C1 |
| D8 the tree | **(a, R1)** every catalog object is in exactly one tree file in one domain folder; `schema_paths = []`; no `supabase/schemas/` folder. **(b, R2)** `db:emit --check`; no `pg_get_functiondef` outside `@generated` blocks in a migration after the baseline; the receipt rule (`duplication.spec` §4 tag rule, kept) | R1, R2 |
| D9 parity | the head (baseline + tail on PGlite) renders exactly the tree. It needs the database, so it runs as a step of the required `build` job, not in lint | R1 |
| D10 the client surface | `Contracts` keys = the client-callable set; `catalog.gen.ts` / `calls.gen.ts` equal a fresh generation | C2 |

---

## 6. E — the slices

### 6.1 Order

```
S2 ─► S3 ─► R1 ─► R2 ──┬─► A2 · A3 · A5 · A6 · A1   (built side by side; deployed one at a time)
            │          │                         └─► A4 (after A1 and A5)
            └─► G2 ────┘
C1 ─┬─(during S2/S3)────────────────────────────────────────────────►
C3 ─┘                         C2 (after R2, beside the A-slices) ─► C4 (after A1, C2, C3) ─► C5 (last, alone)
```

**S2 and S3 come first.** R1 renders the tree from a head that loads in seconds with no prefix cache. Before
S2, that head is a 254-file replay behind the caches S3 deletes, and the tree would have to be re-proved
after the cut anyway.

### 6.2 The slices

Costs are **estimates**, scaled from CHAIN_BASELINE §5's own estimates for S1–S3. CI after S3 is
CHAIN_BASELINE's target: a migration PR in under 10 minutes. "Byte-identical" is proved by each slice's
own gate.

| slice | what | owns (no other open slice touches these) | gate | cost (est.) | runs beside |
|---|---|---|---|---|---|
| **S2** the cut (CHAIN_BASELINE §5) | the baseline committed as version N = prod head at the cut; 0001..N archived; history saved; one `migration repair`; the world secret regenerated at load, so no secret is in git (decided by default, S1 note 3) | `supabase/migrations/**`, `supabase/archive/**`, `scripts/db/check-versions.mjs`, `scripts/db/apply-chain.mjs`, `src/lib/db/{applyChain,chain,chainSource}.ts`, `tests/db.chain.spec.ts`. The baseline's receipt follows today's tag rule, so it does not touch `duplication.spec` | dry-run push empty; `migration list` = {N}; `disposable-chain` green on the baseline alone; full Acceptance green on main. Deploy freeze during the cut | 2–3 h, 2 CI runs (one from zero, ~55 min), one 10-min prod window | C1, C3 |
| **S3** the machinery out | prefix cache to `digest.mjs`; snapshots, frozen asserts and their specs deleted; docs/CI.md rewritten; **the never-from-zero law retired** (owner-approved) | `scripts/db/prefix-cache.mjs`, `scripts/ci/**`, `.github/workflows/{migrations-apply-proof,acceptance,build,chain-baseline}.yml`, `src/lib/db/frozenAsserts.ts`, `src/lib/db/rescue.ts` (dead `readRescue`), `tests/{db.frozenAsserts,db.prefixCache}.spec.ts`, `tests/frozenChain.ts`, `docs/CI.md`, CLAUDE.md's CI lines | a migration PR's CI < 10 min end to end; a cold local build's world step < 1 min + the tail; nightly green | 4–6 h, 3 CI runs | C1, C3 |
| **C1** client hygiene + the guard runner | D1, D3–D7 guards; the 2 cycles cut (the shared helpers move into leaf files); 4 dead exports deleted; the un-i18n'd text through `t()`; one `useCountryFilter` in `stats/statsFilters.ts` for the three copies; `lint` runs the guards | `scripts/guards/**` (new), `tests/sections.spec.ts`, `tests/duplication.spec.ts` §1–3, 5, 6, `package.json`'s `lint` line, `src/domain/{order,passage}/**`, the dead-export files outside `src/lib/db`, `src/features/stats/**`, `src/features/command/Queue.tsx`, the other files the i18n guard lists, `src/lib/i18n/dict/**` | guards at zero (D3 and D5 at their pinned debt); tsc, eslint, build; touched specs; screens identical (English strings byte-equal) | 4–5 h, 1–2 CI runs | S2, S3, C3 |
| **C3** the store by domain | `useWorld` from slices (4.4) | `src/live/worldStore.ts`, `src/live/world/**` (new) | the store's key set pinned equal; tsc, eslint, build; full Acceptance on main | 3–4 h, 1 CI run | S2, S3, C1 |
| **R1** one file per object | explode the head into `supabase/domains/**` (18 folders, Appendix A finalised); render, `db:fmt`, parity (D8a, D9) | `supabase/domains/**` (new), `scripts/db/domains/**` (new), `package.json` + lock (pglite-tools, pinned), the parity step in `build.yml` | tree = PGlite head (byte); PGlite = Supabase (catalog); Supabase = prod (read-only, the three named exceptions only). **No migration: the game is untouched** | 6–8 h, 2 CI runs (one is the full suite: `package.json` changed) | — |
| **R2** emitted migrations; hunks retired | `db:emit` (+ `--check`, `--renumber`, `--keep-old`, safe drop); `same-world` probe; D8b; the rule text of 2.9; `bv-deploy.sh` runs the prod catalog check after each push. **Proof of tool:** one emitted migration that re-creates `world.game_day()` unchanged (pre-image = post-image) | `scripts/db/domains/emit.mjs`, `scripts/db/probe/**` (new), `tests/duplication.spec.ts` §4, `supabase/migrations/README.md`, `docs/NO_SPAGHETTI.md` §3, `docs/SECTIONS.md` (server part), CLAUDE.md's migration lines, `scripts/ops/bv-deploy.sh` (then re-copied to `~/bin` with this PC's path edit) | `emit --check` green; the proof migration applies on PGlite and Supabase with its receipt; the push lands via `bv-deploy`; prod check equal after | 8–10 h, 3 CI runs, 1 deploy | G2 |
| **G2** server formula guards | D2 with its 7 named rules + fingerprints + knob ownership, debts pinned at today's counts | `scripts/guards/server/**` (new; one file per rule, so each A-slice edits only its own) | zero new findings; a planted copy goes red | 4 h, 1 CI run | R2 |
| **A2** tax in a price | `world.price_tax` | `market/world.price_terms`, `market/world.quote_terms`, `market/world.price_tax` (new), rule `price-tax` | every quote, lit and dark, old = new; paired sim 0 tables different | 1–2 h, 1 CI run, 1 deploy | A1, A3, A5, A6, C2 |
| **A3** the press | `public.press_knobs`; `do_sell`'s dark arm composes `press_after` | `cmd.do_sell`, `cmd.do_buy`, `world.quote_priced`, `public.press_after`, `public.press_knobs` (new), rule `press` | prod read-only: `min(glut) ≥ −glut_max`; buy and sell probes, lit and dark, old = new; paired sim 0 different; beat timing within ±5 % | 2–3 h, 2 CI runs, 1 deploy + beat watch | A1, A2, A5, A6, C2 |
| **A5** hazard effects as data | effect columns on `voyage_event_kinds`; `voyage.hazard_effect` | `danger/public.voyage_event_kinds.table`, `voyage.settle` (until A4), `voyage.storm_hull_lost`, `voyage.day_delay_hours`, `voyage.hazard_effect` (new), rule `hazard-effect` | every kind × magnitude grid old = new; proof 01 green; paired sim 0 different; beat timing | 3–4 h, 2 CI runs, 1 deploy + beat watch | A1, A2, A3, A6, C2 |
| **A6** longitude | `lon_wrap`, `lon_delta`, `lon_span` | `public.lon_in_view`, `public.sea_leg_asks_derive`, `voyage.lon_lerp`, `world.sea_traffic`, the three leaves (new), rule `lon-wrap` | grid incl. ±180/±540 and every stored path old = new (boundary report first) | 1–2 h, 1 CI run, 1 deploy | A1, A2, A3, A5, C2 |
| **A1** sea days + the voyage clock | `sail_hours`, `days`, `clock_rate`, `real_seconds`, `sim_hours_in` | the 18 functions of 3.3 §1–2 (incl. `public.npc_plan` until A4, and `world.snapshot`'s one serving line until C4), the 5 leaves (new), rules `voyage-days`, `voyage-clock` | the question set (every `good_board` / `trade_routes` / `leg_refusal` answer for N fleets × M goods; 40 SAILs; every sailing voyage's ETA recomputed, rolled back) old = new; paired sim 0 different; **beat timing within ±5 %**; 30-min beat watch on prod | 6–8 h, 2 CI runs, 1 deploy + beat watch | A2, A3, A5, A6, C2 |
| **A4** stores per crew-day | `stores_per_day`, `stores_cost_days` | `public.stores_topup`, `public.npc_loop_candidates`, `voyage.endurance_days`, `public.stores_cost`, the stores lines of `public.npc_plan` and `voyage.settle` (handed over by A1 and A5), rule `stores-per-day` | provision/top-up probes; endurance of every fleet; paired sim 0 different; beat timing | 3–4 h, 2 CI runs, 1 deploy + beat watch | C2 |
| **C2** the generated client surface | 4.3, the server registry generated, and the 4 uncatalogued grants decided | `scripts/db/domains/gen-client.mjs` (new), `src/lib/rpc/**`, `auth/public.client_rpc_entry_points`, the tree files of the 4 grants, `scripts/db/proofs/03_grant_lockdown.sql` if it names the list, `tests/rpc.surface.spec.ts` | generated catalog deep-equals the old table (after the one rename); the same calls; the registry's rows set-equal (minus any grant C2 revokes, named); proof 03 green; D10 | 8–10 h, 2 CI runs, 1 deploy | the A-slices |
| **C4** served clock, days and hold | 3.3 §9–11 + 4.5 (and the three served knobs nothing reads deleted), **server and client in one slice** | `geo/world.snapshot`, `houses/public.level_from_points`, `voyage/world.passage_days` (new), `fleet/public.ship_free_hold` (new), `fleet/public.fleet_free_hold`, `fleet/world.fleets`, `src/lib/format/time.ts`, `src/live/clock.ts` (new), `src/live/world/core.ts`, the call sites of 4.5, `tests/format.spec.ts` | served values equal the old constants (asserted); every printed day, date, clock and hold figure identical on the canary world at fixed instants (headless, phone + wide); D3 at zero | 6–8 h, 2 CI runs, 1 deploy | — |
| **C5** faces out of live | 4.6 | `src/live/*.tsx` → `src/faces/**`, every importer, `registerHullClasses` and its callers in `src/chart/`, the `LAYERS` table | guards; tsc, eslint, build; screenshots equal; full Acceptance on main | 4–6 h, 1–2 CI runs | — (alone: it touches many importers) |

### 6.3 Rules that hold across the slices

* **Bugs first** (owner, 2026-10-28). A bug outranks a queued slice. If a bug fix needs a function a slice
  has checked out, the fix goes first and the slice re-emits on top. The pre-image guard makes a stale slice
  refuse instead of overwriting the fix.
* **Checkouts.** Each A-slice lists its functions at the top of `docs/WORK_QUEUE.md` while it is open.
  Feature work on those functions waits (Q1 below).
* **Deploys, one at a time, in number order**, as today. **A slice whose functions run in the beat** (A1, A3,
  A4, A5) gets its own measured window: a 30-minute beat watch (p95, errors), the same pattern as every
  live-play change (Q2 below). A2, A6, C2 and C4 share windows.
* **The switch-over at R2.** From R2's merge, every migration is emitted. A hunk migration still in flight
  lands before R2 merges, or is re-made through the tree.
* **Models:** Opus for R1, R2, A1, A4, A5, C2, C4 (live-chain or judgement work); Fable for C1, C3, C5, A2,
  A6, G2 (Sonnet while Fable is out). One adversarial review per slice. Headless browsers only.

### 6.4 Total

About **65–90 agent-hours, ~30 CI runs and 10 prod touches** (S2's repair, R2's proof, six A-slices, C2,
C4). None of them changes what a player sees. Wall-clock with two or three lanes: **about 7–9 working
days.** This is an estimate, not a measurement.

---

## 7. F — risks, rollback, questions

### 7.1 Risks

| risk | guard |
|---|---|
| the renderer or emitter silently changes a body | the post-image check in the same transaction; global parity on every PR; the `same-world` paired arms; a negative control in every probe |
| one authority costs speed in the beat (an extra call per row) | the leaf shape (3.2: inlinable SQL, knobs passed in); A1 measures before and after; a ±5 % beat gate; the 30-min watch. 0262's per-function profile is the instrument |
| a different association changes numeric's last digits (A1: `npc_plan:214`, `npc_leg_lines:114`) | compared exactly in the probe; any difference is reported as a measured change, never called identical |
| longitude idioms disagree at exactly ±180 (A6) | the boundary report comes before the choice |
| two slices touch one function | disjoint ownership (6.2); the pre-image guard refuses a stale emission; `--renumber` re-reads pre-images |
| PGlite (Postgres 18) and Supabase/prod (17) render differently | one pinned renderer for the tree; PGlite vs Supabase compared by catalog with S1's written allow-list (which fails on a stale entry); `pg_get_functiondef` measured equal across both (S1) |
| prod drifts by a hand fix | `bv-deploy.sh`'s read-only prod check after every push; the pre-image guard on the next touch |
| habit: agents keep writing hunks | the rule text is rewritten in R2 itself (2.9); D8b fails a hunk |
| larger migrations (whole bodies rather than hunks) | they still load fast after S3; re-baseline by hand (owner-approved) when the tail grows |
| the client's served clock is missing at boot | the shell already waits for the snapshot (`WorldGate`); a missing served value is an error, never a silent constant (`NO_SPAGHETTI.md` §7C) |

### 7.2 Rollback

* **S2, S3:** as CHAIN_BASELINE §5. Prod's schema never changes; `migration repair --status applied` restores
  the history rows from the saved JSON.
* **R1, G2, C1, C3, C5:** `git revert`. No prod state.
* **R2:** `git revert` the tooling. Migrations already applied are ordinary SQL and stay valid.
* **A-slices, C2, C4:** forward rollback. Revert the tree change and emit: the old bodies are in git, and
  the emitter writes the migration that puts them back. Each PR body carries that command and the prod
  check that proves it.

### 7.3 Questions for the owner (each has a default; nothing waits on them)

1. **While a slice converts a function, do your requests that touch the same function wait until it
   merges?** Default: **yes**, for a day or two per slice. Bugs never wait: a bug fix goes first and the
   slice is re-made on top.
2. **Keep a 30-minute speed watch after each of the four slices that touch the arrivals beat (A1, A3, A4,
   A5)?** They are proven identical, and the watch is only for speed. Default: **keep it.**
3. **Day counts on screen keep exactly today's precision** (one decimal in most places, two in a few
   server sentences). Default: **keep it as it is**; one decimal everywhere is a one-line change later, if
   you want it.

---

## Appendix A — every server object by domain (proposed; R1 finalises it)

Prod head 0265, read-only catalog: 768 objects (628 function names, one with two overloads; 138 tables;
2 views). Classified by name rules, then reviewed by hand. R1's guard (D8a) requires every object in exactly
one folder, so whatever this list gets wrong is caught there.

**`auth/`**: 8 functions
- functions: `cmd.assume_identity`, `public.caller_evaluated_functions`, `public.client_executable_writers`, `public.client_rpc_entry_points`, `public.client_write_grants`, `public.current_player_id`, `public.forbid_mutation`, `public.objects_not_owned_by`

**`config/`**: 24 functions, 1 table
- tables: `public.world_config`
- functions: `public.city_treasury_on`, `public.city_treasury_switch`, `public.combat_bite_on`, `public.credit_on`, `public.crew_bite_on`, `public.depth_lit`, `public.economy_close_switch`, `public.economy_closed`, `public.gear_wear_on`, `public.influence_on`, `public.influence_switch`, `public.levels_bite_on`, `public.npc_traders_on`, `public.npc_traders_switch`, `public.price_impact_lit`, `public.restock_lit`, `public.sea_conditions_on`, `public.skills_bite_on`, `public.standing_routes_on`, `public.wants_lit`, `public.wc`, `public.wc_int`, `public.wc_num`, `public.wc_text`

**`clock/`**: 16 functions, 3 tables (+ `cron.jobs.sql`, the 10 jobs)
- tables: `public.arrivals_beats`, `public.compact_runs`, `public.reconcile_runs`
- functions: `public.beat_fn_diff`, `public.beat_fn_reads`, `public.beat_ms`, `public.beat_reads`, `public.beat_reads_diff`, `public.clock_jobs`, `public.hold_the_quay`, `public.tick_arrivals`, `public.tick_arrivals_each_second`, `public.tick_compact`, `public.tick_cron_expression`, `public.tick_reconcile`, `public.unwind_the_clock`, `public.wind_the_clock`, `voyage.due_at_follows_the_clock`, `world.game_day`

**`geo/`**: 14 functions, 7 tables
- tables: `public.ports`, `public.regions`, `public.sea_cells`, `public.sea_raster`, `public.sea_reaches`, `public.seas`, `voyage.channels`
- functions: `public.lon_in_view`, `public.region_area`, `public.sea_cell_col`, `public.sea_cell_row`, `voyage.assert_paths_water`, `voyage.channel_foot`, `voyage.gc_distance_nm`, `voyage.lon_lerp`, `voyage.sea_at`, `voyage.sea_near`, `voyage.water_roadstead`, `voyage.water_snap_nm`, `world.sea_raster`, `world.snapshot`

**`voyage/`**: 35 functions, 2 tables
- tables: `public.voyage_events`, `public.voyages`
- functions: `cmd.do_sail`, `public.passage_gate`, `public.passage_reach`, `public.passage_reach_at`, `public.passage_reach_nm`, `public.port_call`, `public.port_time_wake`, `voyage.arrival_at`, `voyage.assert_sailing_invariant`, `voyage.course_of`, `voyage.day_end_from`, `voyage.day_ends_at`, `voyage.days_complete`, `voyage.delay_before_day`, `voyage.depart`, `voyage.keep_due_at`, `voyage.leg_at_day`, `voyage.leg_refusal`, `voyage.path_nm`, `voyage.path_refusal`, `voyage.position`, `voyage.progress_nm`, `voyage.reach_from`, `voyage.reach_passage`, `voyage.recompute_eta`, `voyage.sail_refusal`, `voyage.segments_from_course`, `voyage.settle`, `voyage.sim_hours`, `voyage.total_days`, `voyage.waters_ahead`, `voyage.where_now`, `world.fleets`, `world.reach`, `world.voyage_view`

**`danger/`**: 27 functions, 6 tables
- tables: `public.insured_voyages`, `public.sea_leg_asks`, `public.sea_zone_boxes`, `public.sea_zone_cells`, `public.sea_zones`, `public.voyage_event_kinds`
- functions: `public.course_zones`, `public.fight_points`, `public.harbour_zone`, `public.insurance_claim`, `public.insurance_price`, `public.insure_voyage`, `public.raid_crew_lost`, `public.sea_gate`, `public.sea_leg_asks_derive`, `public.sea_refusal`, `public.sea_zone_at`, `voyage.day_delay_for`, `voyage.day_delay_hours`, `voyage.escort_score`, `voyage.fight`, `voyage.fight_resolve`, `voyage.hazard_roll`, `voyage.raid_takes`, `voyage.report_line`, `voyage.risk_quote`, `voyage.rng`, `voyage.rng_raw`, `voyage.sea_mix`, `voyage.storm_hull_lost`, `world.insurance`, `world.roll_raw`, `world.sea_conditions`

**`fleet/`**: 71 functions, 26 tables, 1 view
- tables: `public.class_profile`, `public.class_slot_unlocks`, `public.class_slots`, `public.fitted_units`, `public.fleets`, `public.gear_racks`, `public.gear_set_bonuses`, `public.gear_set_names`, `public.hull_recipe_goods`, `public.hull_recipe_items`, `public.hull_recipes`, `public.item_city`, `public.item_effects`, `public.item_kinds`, `public.item_line`, `public.item_profile`, `public.item_recipes`, `public.item_unmade`, `public.item_use`, `public.perks`, `public.player_items`, `public.player_storage`, `public.ship_classes`, `public.ship_lines`, `public.ship_xp`, `public.ships`
- views: `public.ship_fittings`
- functions: `cmd.augment_fitting`, `cmd.do_build`, `cmd.do_fit`, `cmd.do_make`, `cmd.do_repair`, `cmd.do_store`, `cmd.do_take`, `cmd.do_unfit`, `cmd.resolve_class`, `cmd.resolve_item`, `public.armour_soak`, `public.armour_turns`, `public.augment_fitting_for`, `public.class_budget`, `public.commission_ship`, `public.fitting_lock`, `public.fleet_buy_capacity`, `public.fleet_cargo_qty`, `public.fleet_free_hold`, `public.fleet_load`, `public.fleet_repair_due`, `public.fleet_unload`, `public.fleet_wave`, `public.form_fleet`, `public.gear_repair_quote`, `public.house_ship_max`, `public.hull_labour`, `public.hull_unmade`, `public.item_not_made`, `public.item_recipe_value`, `public.mount_fitting`, `public.perk_fits`, `public.perk_ranks`, `public.perk_unit_cost`, `public.perk_wear_mult`, `public.port_has_shipyard`, `public.repair_units_for`, `public.ship_cargo_tuns`, `public.ship_hold_capacity`, `public.ship_set_bonus`, `public.ship_set_hands_pct`, `public.ship_set_pieces`, `public.storage_cap`, `public.storage_used`, `public.unit_augmentable`, `public.unit_perk_card`, `public.unit_perk_deltas`, `public.unit_repair_cost`, `public.unit_wear_card`, `public.unmount_fitting`, `public.wear_factor`, `public.wear_units_for`, `public.worn_delta`, `public.yard_labour`, `public.yard_wrong_country`, `voyage.fleet_speed`, `voyage.fleet_speed_at`, `voyage.ship_speed`, `voyage.ship_speed_at`, `world.building_yard`, `world.buy_capacity`, `world.ship_budget`, `world.ship_racks`, `world.ship_seats`, `world.ship_set_card`, `world.ship_slots`, `world.ship_stat`, `world.ship_stats`, `world.ship_view`, `world.warehouse`, `world.workstation`

**`supplies/`**: 29 functions, 3 tables
- tables: `public.fleet_wages`, `public.provision_preset_backup_0225`, `public.provision_presets`
- functions: `cmd.do_dismiss`, `cmd.do_hire`, `cmd.do_provision`, `cmd.provision_preset_apply`, `cmd.provision_preset_apply_for`, `cmd.provision_preset_delete`, `cmd.provision_preset_save`, `cmd.provision_preset_save_for`, `public.crew_hire_cost`, `public.crew_wages`, `public.fleet_crew_shortfall`, `public.fleet_wage`, `public.owe_wages`, `public.passage_needs`, `public.pay_wages`, `public.provision_presets_cap`, `public.running_cost_mult`, `public.sail_refused_days`, `public.stores_cost`, `public.stores_topup`, `public.supply_need`, `public.supply_needs`, `public.supply_reach`, `public.wages_from_profit`, `voyage.endurance_days`, `voyage.endurance_mult`, `voyage.stores_need_days`, `world.crew_cost`, `world.provision_presets`

**`people/`**: 69 functions, 31 tables, 1 view
- tables: `public.cabin_kinds`, `public.cabin_rotation`, `public.captain_active`, `public.captain_grades`, `public.captain_languages`, `public.captain_profile`, `public.captain_seats`, `public.captain_state`, `public.captain_traits`, `public.captain_xp`, `public.class_cabins`, `public.crew_effects`, `public.languages`, `public.officers`, `public.player_officers`, `public.player_skills`, `public.port_language`, `public.promotion_items`, `public.promotion_progress`, `public.skill_effects`, `public.skill_groups`, `public.skill_prereqs`, `public.skill_profile`, `public.skill_queue`, `public.skill_requirements`, `public.skill_sp`, `public.skill_sp_grants`, `public.skills`, `public.trait_effects`, `public.trait_foci`, `public.traits`
- views: `public.captain_job`
- functions: `cmd.captain_traits_set`, `cmd.hire_officer`, `cmd.promote_captain`, `cmd.seat_captain`, `cmd.skill_enroll`, `cmd.skill_queue_set`, `cmd.study_skill`, `public.cabin_focus`, `public.captain_level`, `public.captain_level_mult`, `public.captain_seat_pick`, `public.captain_seat_put`, `public.captain_traits_set_for`, `public.captain_wage`, `public.captain_xp_credit`, `public.crew_pct`, `public.crew_speaker`, `public.crew_terms`, `public.drilled_hands`, `public.house_skill_scopes`, `public.perk_rank_words`, `public.player_skill_bonus`, `public.promote_captain_for`, `public.promotion_credit`, `public.promotion_next`, `public.raise_skill`, `public.seat_captain_for`, `public.ship_crew_terms`, `public.sign_officer`, `public.skill_answers`, `public.skill_effect_words`, `public.skill_enrol_cost`, `public.skill_enrol_refusal`, `public.skill_enroll_for`, `public.skill_is_enrolled`, `public.skill_level`, `public.skill_level_at`, `public.skill_level_word`, `public.skill_lock`, `public.skill_queue_now`, `public.skill_queue_refusal`, `public.skill_queue_set_for`, `public.skill_refused`, `public.skill_scale`, `public.skill_sp_bonus_today`, `public.skill_sp_for`, `public.skill_sp_grant_for`, `public.skill_study_for`, `public.skill_taught_at`, `public.skill_taught_place`, `public.trait_effect_words`, `public.trait_in_use`, `public.voyage_xp`, `public.voyage_xp_tracks`, `voyage.skill_pct_at_departure`, `world.captain_card`, `world.captains`, `world.crew_bonuses`, `world.inn`, `world.inn_chance`, `world.inn_present`, `world.inn_shift`, `world.officer_scarcity`, `world.officers`, `world.skill_bonuses`, `world.skill_bonuses_at`, `world.skill_pct`, `world.skill_pct_at`, `world.skills`

**`market/`**: 80 functions, 17 tables
- tables: `public.active_buffs`, `public.buff_kinds`, `public.goods`, `public.haggle_daily`, `public.port_goods`, `public.port_specialties`, `public.price_history`, `public.price_history_day`, `public.price_history_hour`, `public.price_rollup`, `public.price_watch`, `public.trade_daily`, `world.culture_faith`, `world.faith_demand`, `world.faiths`, `world.port_faith_override`, `world.region_demand`
- functions: `cmd.do_buy`, `cmd.do_sell`, `cmd.haggle`, `cmd.preview_basket`, `cmd.trade_basket`, `cmd.watch_price`, `public.blend_basis`, `public.buff_multiplier`, `public.buff_season_of`, `public.cargo_haul`, `public.culture_refuses`, `public.depth_day`, `public.depth_formula`, `public.depth_mult`, `public.depth_stock`, `public.depth_target`, `public.drift_moments`, `public.drift_slot_of`, `public.fleet_cargo_basis`, `public.fleet_cargo_basis_map`, `public.fleet_stock_at_cost`, `public.good_rarity`, `public.haggle_concession`, `public.haggle_odds`, `public.made_only_in`, `public.next_drift_change_at`, `public.outlook_best`, `public.port_offered_goods`, `public.port_offers`, `public.press_after`, `public.price_history_window`, `public.price_history_window_for`, `public.price_path`, `public.price_record_pairs`, `public.profit_tax`, `public.quay_shows`, `public.rarity_from_producers`, `public.rarity_scale`, `public.restock_day`, `public.restock_formula`, `public.restock_rate`, `public.stock_after`, `public.tg_buff_needs_a_quay`, `public.tick_buff_calendar`, `public.tick_market_drift`, `public.tick_market_drift_each_port`, `public.tick_price_snapshot`, `public.traded_today`, `world.affinity_at`, `world.affinity_for`, `world.buffs`, `world.daily_cap_remaining`, `world.demand_for`, `world.faith_taste`, `world.fleet_trades`, `world.good_board`, `world.haggle_state`, `world.haul_at`, `world.haul_rows`, `world.market`, `world.market_depth_at`, `world.mid_from_terms`, `world.mid_price`, `world.mid_terms`, `world.port_faith`, `world.price`, `world.price_outlook`, `world.price_series`, `world.price_sides`, `world.price_terms`, `world.price_why`, `world.quote`, `world.quote_priced`, `world.quote_terms`, `world.region_taste`, `world.spread`, `world.spread_effective`, `world.spread_effective_pair`, `world.tax_rate`, `world.trade_routes`

**`city/`**: 58 functions, 13 tables
- tables: `public.building_kinds`, `public.city_shares`, `public.city_want_fills`, `public.city_wants`, `public.city_works`, `public.port_buildings`, `public.port_fee_debts`, `public.port_influence`, `public.port_mayor`, `public.port_treasury`, `public.trade_contracts`, `public.treasury_daybook`, `public.treasury_flows`
- functions: `cmd.donate`, `cmd.fulfil`, `cmd.invest`, `cmd.preview_donate`, `cmd.preview_fulfil`, `cmd.preview_invest`, `cmd.run_fulfil`, `cmd.set_tax`, `public.city_bid_factor`, `public.city_can_spend`, `public.city_capital`, `public.city_day`, `public.city_earnings`, `public.city_level`, `public.city_offered`, `public.city_pays`, `public.city_seed_amount`, `public.city_sell_outflow`, `public.city_standing`, `public.city_surplus`, `public.collect_coupons`, `public.contract_draw`, `public.donate_for`, `public.furnish_harbours`, `public.harbour_buildings`, `public.influence_coupon_mult`, `public.influence_next_count`, `public.influence_post`, `public.influence_shares`, `public.influence_weight`, `public.invest_for`, `public.invested_decay`, `public.investor_rank`, `public.investor_shave`, `public.pay_city`, `public.port_dues`, `public.port_fee`, `public.port_fee_collect`, `public.tg_treasury_append_only`, `public.tick_city`, `public.tick_contracts`, `public.tick_influence`, `public.town_hall_gifts`, `public.treasury_balance`, `public.treasury_lock`, `public.treasury_post`, `public.treasury_reserve`, `public.want_period`, `public.wants_draw`, `public.works_factor`, `public.works_share_price`, `world.city_good_trades`, `world.city_wants_now`, `world.contracts`, `world.holdings`, `world.town_hall`, `world.town_hall_influence`, `world.want_left`

**`powers/`**: 12 functions, 4 tables
- tables: `public.great_powers`, `public.nations`, `public.port_allegiance`, `public.power_relations`
- functions: `cmd.change_country`, `public.country_factor`, `public.great_power`, `public.nation_change_next_at`, `public.port_allegiance_guard`, `public.port_countries`, `public.port_nation`, `public.port_ruler`, `public.power_stance`, `public.stance_mult`, `world.allegiance`, `world.nation_standings`

**`ledger/`**: 17 functions, 3 tables
- tables: `public.capital_gifts`, `public.events`, `public.ledger`
- functions: `public.assert_ledger_reconciles`, `public.capital_gift_pass`, `public.capital_pays`, `public.company_debt_key`, `public.company_owed`, `public.credit`, `public.debt_owe`, `public.emit_event`, `public.founding_credit`, `public.ledger_sum`, `public.mint_guard`, `public.player_gift`, `public.player_worth`, `public.tg_reconcile_from_ledger`, `public.tg_reconcile_from_player`, `world.books`, `world.ledger`

**`houses/`**: 17 functions, 3 tables
- tables: `public.players`, `public.standings`, `public.title_names`
- functions: `cmd.found_house`, `public.assert_house_caps`, `public.keep_level_met`, `public.level_from_points`, `public.level_in_force`, `public.level_points`, `public.new_house`, `public.player_fame`, `public.player_progress`, `public.requirements_met`, `public.requirements_refusal`, `public.requirements_unmet`, `public.settle_standings`, `public.tg_house_caps`, `public.title_level`, `world.player`, `world.standings`

**`orders/`**: 33 functions, 1 table
- tables: `public.orders`
- functions: `cmd.advance`, `cmd.cancel_at`, `cmd.clear`, `cmd.clear_for`, `cmd.divert`, `cmd.enqueue`, `cmd.execute_order`, `cmd.figures`, `cmd.fixes`, `cmd.fold`, `cmd.issue`, `cmd.issue_lines`, `cmd.manifest_line_caught`, `cmd.manifest_refused`, `cmd.parse`, `cmd.parse_number`, `cmd.preview`, `cmd.preview_tow`, `cmd.queue`, `cmd.refusal`, `cmd.refusal_caught`, `cmd.refuse` (2 overloads), `cmd.refused_envelope`, `cmd.release_failed`, `cmd.resolve_fleet`, `cmd.resolve_good`, `cmd.resolve_port`, `cmd.resolve_qty`, `cmd.run_manifest`, `cmd.tow`, `cmd.verb_schema`, `public.preparing_refusal`, `public.tow_for`

**`routes/`**: 30 functions, 4 tables
- tables: `public.standing_route_laps`, `public.standing_route_lines`, `public.standing_route_stops`, `public.standing_routes`
- functions: `cmd.run_standing_provision`, `cmd.run_standing_route`, `cmd.standing_route_assign`, `cmd.standing_route_assign_for`, `cmd.standing_route_close_lap`, `cmd.standing_route_delete`, `cmd.standing_route_lines`, `cmd.standing_route_note_skip`, `cmd.standing_route_pause`, `cmd.standing_route_pause_for`, `cmd.standing_route_refusal`, `cmd.standing_route_save`, `cmd.standing_route_save_for`, `cmd.standing_route_set_paused`, `cmd.standing_route_tail`, `public.lap_trades`, `public.lap_trades_view`, `public.route_earnings`, `public.route_lane`, `public.route_nm`, `public.route_requirement`, `public.sea_route_stops`, `public.sea_routes`, `public.standing_route_lines_cap`, `public.standing_route_max_for`, `public.standing_route_state`, `public.standing_route_stops_cap`, `public.standing_routes_cap`, `world.route_board`, `world.standing_routes`

**`npc/`**: 49 functions, 6 tables
- tables: `public.npc_courses`, `public.npc_fleets`, `public.npc_houses`, `public.npc_hull_conversions`, `public.npc_line_hulls`, `public.npc_loadouts`
- functions: `public.earned_caps`, `public.famous_held`, `public.merchant_doing_at`, `public.npc_affordable`, `public.npc_ask_slot`, `public.npc_ask_waiting`, `public.npc_buy_budget`, `public.npc_buy_ceiling`, `public.npc_casks_blocked`, `public.npc_closest_race`, `public.npc_compact`, `public.npc_compact_house`, `public.npc_compact_houses`, `public.npc_compact_locked`, `public.npc_compact_orders`, `public.npc_feasible_legs`, `public.npc_fit_loadout`, `public.npc_fix_hull_skills`, `public.npc_fix_level`, `public.npc_found`, `public.npc_hull_for`, `public.npc_invest`, `public.npc_known_legs`, `public.npc_last_gift`, `public.npc_leg_days`, `public.npc_leg_lines`, `public.npc_loop_beats`, `public.npc_loop_candidates`, `public.npc_loop_switches`, `public.npc_loop_tier`, `public.npc_plan`, `public.npc_provision_for`, `public.npc_step_failed`, `public.npc_tend`, `public.npc_tend_houses`, `public.npc_tend_roster`, `public.npc_tend_route`, `public.npc_tend_sum`, `public.npc_upkeep_scope`, `public.npc_upkeep_spent`, `public.npc_waiting_queue`, `public.npc_worth`, `public.roster_rng`, `public.roster_target_count`, `public.tg_npc_is_a_merchant`, `world.npc_fleet_card`, `world.port_merchants`, `world.sea_roster`, `world.sea_traffic`

**`stats/`**: 39 functions, 8 tables
- tables: `public.stats_city`, `public.stats_city_good`, `public.stats_flow_words`, `public.stats_good`, `public.stats_live`, `public.stats_live_deltas`, `public.stats_merchants`, `public.stats_world`
- functions: `public.standings_slot_of`, `public.stat_words`, `public.stats_bucket`, `public.stats_compact`, `public.stats_flow_lines`, `public.stats_fold`, `public.stats_fold_day`, `public.stats_live_add`, `public.stats_live_fold`, `public.stats_live_track`, `public.stats_map_sum`, `public.stats_merchant_fleets`, `public.stats_merchants_add`, `public.stats_merchants_board`, `public.stats_merchants_window`, `public.stats_sides`, `public.stats_span_since`, `public.stats_span_unit`, `public.stats_watch`, `public.stats_watch_read`, `public.stats_window_cities`, `public.stats_window_city_goods`, `public.stats_window_city_trades`, `public.stats_window_flows`, `public.stats_window_founded`, `public.stats_window_goods`, `public.stats_window_kinds`, `public.stats_window_totals`, `public.stats_window_trades`, `public.tick_stats`, `world.money_feed`, `world.stats_cities`, `world.stats_city`, `world.stats_markets`, `world.stats_me`, `world.stats_merchants`, `world.stats_now`, `world.stats_overview`, `world.watchlist`

---

## Appendix B — how the numbers were measured (to re-derive, not to trust)

* **Prod catalog** (read-only; one SELECT per file through `npx supabase@2.120.0 db query --linked -f`):
  * the head: `select max(version), count(*) from supabase_migrations.schema_migrations`;
  * every function in `public`, `world`, `cmd`, `voyage`: `pg_get_functiondef`,
    `pg_get_function_identity_arguments`, `provolatile`, `prosecdef`, `has_function_privilege('authenticated' | 'anon', oid, 'execute')`.
    Every function called was first checked to be `provolatile = 's'`;
  * relations (`pg_class`), and `cron.job` (name, schedule, active).
* **Formula sites:** regular expressions over those live bodies (`/ 24` beside a speed, `3600` and
  `time_compression`, `water_per_crew_day`, `city_treasury_on() then 0`, `glut`, `360`, `magnitude`
  coefficients). Each hit was then read in its body, not counted blind.
* **Migrations:** `grep -l pg_get_functiondef supabase/migrations/*.sql` (194 of 254). Files naming
  `voyage.settle` by signature (32), and re-creating it whole (4).
* **Client:**
  * imports: a strongly-connected-components pass over `src/`;
  * dead exports: each export without an importer, re-checked with `grep -w` across `src`, `tests` and
    `scripts`. That re-check is what showed `authDict` is a comment;
  * copies: 5-line identical windows (the stats filter);
  * mirrors: `grep` for every served-knob name.
* **Not measured, labelled as estimates:** the slice costs, the wall-clock, the render time of the tree on
  PGlite (R1 measures it), and the inlining cost of an authority in the beat (A1 measures it).
