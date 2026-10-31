# CACHE ONCE — a tab switch downloads nothing it already holds (2026-10-31)

Owner row 250: *"make it download one time, then keep it even though you move from tab to tab."*
Branch `cache-keep`, **client-only**. Base: origin/main **5952edfd** — the HQ · Market IA (#423).
The before column was measured on that same commit in a throwaway worktree; the after column on this
branch. Both from served local builds at 390×844.

## The measurement, first

A probe (`tests/cache.once.spec.ts`) walks the CURRENT navigation twice — **Market → Stats → Map →
Codex → HQ → Market** — wrapping the one `[rpc]` line `src/lib/rpc/backend.ts` prints per ask (the
counter `tests/trade.ceiling.spec.ts` uses). The desk has no tab since #423: its door is the City's
Market building (`city-building-market`), whose face composes the trade face (`PortTrade`). Stats and
Map are the shell's live tabs; Codex is the catalogue; HQ returns to the City that owns the Market
door. Each cycle starts just after a world beat, so a beat is not counted as a tab-switch ask. The
table below is the MOUNT burst (press → screen up); the 500 ms that followed added no cached
resource except the shell's own beat.

**BEFORE (origin/main 5952edfd, same IA, no cache):**

| visit | mount burst |
|---|---|
| cycle 1 · Map | `world.fleets` 1 · `world.player` 1 (the first-want beat followed with `standing_routes`, `sea_roster`) |
| cycle 1 · Codex | **`world.officers` 1** |
| cycle 1 · HQ | `world.town_hall` 1 |
| cycle 1 · Market | **`world.market` 1** · `world.contracts` 1 |
| cycle 1 · Stats | `world.stats_overview` 1 · `world.stats_now` 1 (the 1-second live feed) |
| cycle 2 · Map | `world.standing_routes` 1 (beat timing) |
| cycle 2 · Codex | **`world.officers` 1** |
| cycle 2 · HQ | `world.town_hall` 1 |
| cycle 2 · Market | **`world.market` 1** · `world.contracts` 1 |
| cycle 2 · Stats | `world.stats_overview` 1 · `world.stats_now` 1 |
| session totals (cached resources) | `world.snapshot` **1** · `world.sea_raster` **1** · `world.officers` **2** · `world.market` **2** · `world.town_hall` **2** · `world.contracts` **2**; the Stats live feed ran 17× over the ~27 s probe |

The officer catalogue was downloaded on every Codex mount; the market on every Market-building
mount. The snapshot and the sea raster were already once. `world.price_series` was already once per
(port, good, span) — the store held those — and is not the defect.

**AFTER (this branch, same probe, same IA):**

| visit | mount burst |
|---|---|
| cycle 1 · Map | none (the first-want beat followed with `standing_routes`, `sea_roster`) |
| cycle 1 · Codex | `world.officers` 1 (the first ask) |
| cycle 1 · HQ | `world.town_hall` 1 |
| cycle 1 · Market | `world.market` 1 · `world.contracts` 1 |
| cycle 1 · Stats | `world.stats_overview` 1 · `world.stats_now` 1 (live feed) |
| cycle 2 · Map | `world.standing_routes` 1 (beat timing) |
| cycle 2 · Codex | **none** |
| cycle 2 · HQ | `world.town_hall` 1 |
| cycle 2 · Market | `world.contracts` 1 (its one-beat lifetime had passed) |
| cycle 2 · Stats | `world.stats_overview` 1 · `world.stats_now` 1 |
| session totals (cached resources) | snapshot **1** · sea raster **1** · officers **1** · **market 1** · town_hall **2** · contracts **2**; the live feed ran 16× over ~30 s |

The probe prints `CACHE market on Market-building opens=[1,0]`. The deltas that matter:
**officers 2 → 1**, **market 2 → 1** (the second Market-building open **1 → 0**), snapshot and sea
raster **1 each** before and after. The town hall and the request board stay 2 in both columns
because their existing rule is one world beat and the two visits are ~13 s apart — the cache did
not add a refetch, it just did not invent a longer lifetime than the beat. The Stats one-second
feed and the Map's traffic beat are untouched, as they must be.

## The mechanism: ONE cache, three lifetimes

`src/store/resourceCache.ts` is now the ONE freshness authority for a mounted served read. It is
keyed `name|subject|question` (the RPC name is load-bearing: `useMerchantCard(fleetId)` and
`useFleetTrades(fleetId)` share a subject string), returns a fresh answer synchronously on a
remount, joins an ask already on the wire, and never keeps a refusal.

A caller states the lifetime, and there are exactly three kinds:

- **`SESSION_MS`** — the static catalogues. The officer roster and the skill book (via
  `worldStore.loadOfficers` / `loadSkills`), sea conditions, every reach, every price series, and
  the route board (asked once, then left alone). The world snapshot and the sea raster were
  already once-per-open; they are kept in the store, not copied a second time here.
- **the served edge** — `msUntilEdge(v.clock)` for the market and the desk's `world.good_board` /
  `world.price_why`. The payload carries the instant the whole market next steps, so a remount
  inside that slot draws the kept prices and the edge still refreshes them on the normal schedule.
- **one world beat** (the default) — anything that rides `readAt`: the shed, the inn, the yard,
  the workstation, the forge, the town hall, holdings, books, insurance, captains, standings,
  buffs, the request board, merchants. The beat's own re-ask still forces on a mounted screen,
  because the beat is how time passes; only a REMOUNT inside the beat is served from the cache.

Two deliberate exclusions:

- **A dry run is never cached** (`cache: false`): `cmd.preview`, `cmd.preview_basket`,
  `cmd.preview_fulfil`, `cmd.preview_tow`, `cmd.preview_invest`, `cmd.preview_donate`. It is a
  real write rolled back and depends on the state it would change.
- **The Stats tab's one-second feed is not cached.** It is a live stream by the owner's order
  (row 213), not a resource; freezing it would be the opposite of what was asked.

## Mutations still refresh what they must

Every verb that changes the world is flagged on its catalogue row (`src/lib/rpc/catalog.ts`):
`mutates: true`, plus `invalidates` for the SESSION entries it changes. `src/lib/rpc/backend.ts`
announces a successful mutating call through **one mutation signal**; the cache subscribes to it
(`setMutationListener`) and drops every finite-lifetime answer, plus the named session entries.
A trade, invest, sail, forge or gift therefore makes the next read ask; a hire drops the officer
roster; a study drops the skill book; a captain verb drops the captains; a change of country or a
gift drops the flags.

The signal is the layering fix `tests/sections.spec.ts` demanded: **lib may never import store**
(it caught the first cut pointing `lib/rpc/backend.ts -> store/resourceCache`). The cache imports
DOWN into lib and subscribes there; the dispatcher knows nothing about the cache.

Previews and `cmd.verb_schema` are deliberately not mutating. `cmd.watch_price` writes a watch row
but moves no live figure; the price-series cache already keeps its answer for the session.

## What was deleted, not left beside it

`src/live/servedMemo.ts` and `tests/servedMemo.spec.ts` are gone. The desk's remembered answers
(`useDesk`/`useEdgeRead`) now go through the one cache with the served edge as their lifetime;
`useServedRead` names every read and defaults to one beat. The old `MAX_FRESH_MS` cap became
`MAX_EDGE_MS`, applied only to an edge reading.

`src/app/readClock.ts` moved to `src/domain/readClock.ts`: AppShell arms the beat from it and
writes `worldStore.readEveryMs`, which `useServedRead` reads as the default lifetime. One
authority for "how often the world is read" and "how long an answer is kept".

## Verification

- `npm run typecheck` clean, `npm run lint` clean, `npm run build` clean (forced `tsc -b --force`
  + `vite build` after the rebase, so the shared incremental file could not mask a change).
- `tests/cache.once.spec.ts` **1/1** — the same-IA two-cycle probe above, asserting the snapshot
  and sea raster once, the officer catalogue asked on the first Codex visit and NOT on the second,
  and printing the per-visit table on every run. The market is reported (`[1,0]`), not asserted to
  zero: its lifetime is the served edge, and a probe that straddles one is the price refresh the
  owner asked for.
- `tests/resourceCache.spec.ts` **7/7** — dedupe, force, refusals, zero freshness, session-vs-finite
  mutation invalidation, a named session drop (a hire), a pre-mutation in-flight answer that cannot
  poison the cache, and the edge arithmetic.
- `tests/sections.spec.ts` **8/8**, `tests/duplication.spec.ts` **11/11**,
  `tests/i18n.keys.spec.ts` **4/4**, `tests/rpc.surface.spec.ts` **29/29** — 59/59 in 12 s on the
  rebased build. The first sections run caught the lib→store import; the fix is above.
- `tests/command.buySell.spec.ts` **2/2** (1440×900 and 390×844: the docked city's goods, Buy 1,
  then Sell it back) and `tests/trade.ceiling.spec.ts` **3/3** (the Max row and stepper hold still
  across three world reads; the sell tray prints no "checking" line and one unit is sold three
  ways; an open on-board list makes **0** `cmd.preview` asks and an open sell tray at most one per
  beat). A real trade therefore still re-reads what it changed, and the cache added no dry run to
  the beat. Both ran against the rebased build; the specs themselves are unchanged by #423 (they
  drive `/command` directly, which the route table keeps).

## Note on the base

main's Acceptance was red at the original base (d207ad5b) on `desk.plantab.spec.ts`; #423 fixed that
timeout in its own slice. The Acceptance run at the rebased head (5952edfd) was still in progress
when this branch was measured, so this slice's evidence is the local served-build probes and specs
above.
