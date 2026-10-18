# 2026-10-18 — the plain shards' "different test each run" reds: one race, two layers — `osn-flaky-specs`

**Defect:** main's acceptance plain shards went red with a different test each time:
- run 39097978019 (30bff0c): `layout.spec` "the haggle is a thread…" and "the Trend row opens…";
- run 39107062920 (e335b97): `layout.spec` "a line staged onto the basket…";
- run 39107806852 (91dbb7e): `trade.ceiling` "Trade (sell): count first…";
- run 39112184706 (91dbb7e, the SAME commit as the previous one): green.

Every one of the four failures is the same line: `no ledger rows — is PORT open on its Trade face
with a fleet docked?` — `expect(rows.count()).toBeGreaterThan(1)` received 0. The red-then-green on
91dbb7e is the finding: the specs were non-deterministic.

## Cause — read from the CI traces, then reproduced

Trace of run 39107806852 (times from the test's first step):

| ms | what |
|---:|---|
| 348 | `goto('command')` |
| 532 | `ready()` returns — 50 ms after `domcontentloaded` |
| 2149 | screencast: COMMAND reads **"Loading…"** |
| 4675 | console `[db] ready in 3694 ms` — the world is only now open |
| 5658 | `world.market(p_port)` asked for; the City face shows a **Skeleton** where Trade will be |
| 5668 | the spec's fixed `waitForTimeout(1200)` |
| 7424 | rows counted: **0** — screencast at 7385 still the Skeleton |

Run 39107062920's trace has the same shape (count at 9.3 s, Skeleton on screen).

Two layers, both in the shared test apparatus:
1. **`ready()` waited for an ABSENCE** — no `.animate-pulse`, no "Opening the world" — and absence is
   true of an empty page. It returned before React had drawn anything. On COMMAND the boot shows as
   CommandScreen's own "Loading…" row and on the map as "opening the chart…", neither of which it
   looked for. #209's `chartOpen` patched the same race on the map route only.
2. **After opening COMMAND · City, the specs slept 1200 ms and counted once.** City opens on Trade,
   which stands a `Skeleton` until the quay's market read lands. On a loaded runner that read took
   longer than 1200 ms.

The City click's auto-wait usually absorbed layer 1 (the tabs appear once the world is up), which is
why it passed most runs; the 1200 ms was then a coin-toss against the market read.

## Fix (tests + one attribute; no migration, no behaviour change)
- `src/app/AppShell.tsx`: the shell root carries `data-world={phase}` — the world store's load phase,
  the one authority every screen gates on. Nothing in the app reads it.
- `tests/appReady.fixture.ts`:
  - `ready()` waits for `data-world="ready"` (or `/auth` for a cloud build, which still skips), THEN for
    no Skeleton and no "Opening the world". A `failed` phase throws with the page's own sentence
    instead of timing out. Fixed once, for every route.
  - New `settled(scope)`: no Skeleton left inside a panel, with the named `WORLD_BOOT_MS` budget.
- `tests/desk.fixture.ts`: `openCityFace` returns only once the City face has `settled`.
- The eight `waitForTimeout(1200)` that followed `openCityFace` (7 in `layout.spec`, 1 in
  `trade.ceiling`) are deleted. No assertion changed.
- `tests/seaFrame.fixture.ts`: `chartOpen` uses `WORLD_BOOT_MS`; its comment says `ready()` now covers
  the boot and what it still guards (the view sheet it reads).

## Proof
Local build without `.env.local`, `vite preview` on localhost:4295. A scratch spec (not committed)
runs the failing path — `goto('command')`, `ready()`, `openCityFace`, count `trade-row` — with the CPU
throttled through CDP (`Emulation.setCPUThrottlingRate`).

- **Before, layer 1** (rate 6, 3 runs): 3/3 failed — `ready()` returned at ~990 ms with COMMAND still
  reading "Loading…" and `[db] ready` not yet logged.
- **Before, the CI error itself** (old sleep, layer-1 check off): rate 4 → 2 of 3 failed, rate 6 → 3 of
  3 failed, each with "no ledger rows", 0 rows counted.
- **After** (rate 6, 5 consecutive runs): 5/5 passed — `ready()` returned after `[db] ready` every
  time, COMMAND not "Loading…", 10 rows counted.
- **The four CI-failing tests, unthrottled, `--repeat-each=5 --workers=4`:** 20/20 passed.
- **The whole plain pool once** (53 files — every spec not `db.*` and not importing `npcOn.fixture` — 4 workers): 391 passed, 0 failed, 0 skipped, 4.9 min.
- `tsc -b` and `eslint` clean.

## Not this slice
Run 39107062920 also failed the db shard: `db.chain` "the world grows under a live house" hit its
360 s timeout. That is the growth test #215 cut from 78 min to 4 min, not this race.
