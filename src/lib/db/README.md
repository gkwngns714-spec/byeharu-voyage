# `src/lib/db` + `src/lib/rpc` — the data seam

**The game runs on real PostgreSQL in the browser tab.** Not a mock, not a fixture, not a
simulator: PGlite is PostgreSQL 18 compiled to WebAssembly, and the SQL it runs is
`supabase/migrations/*.sql` — the same ten files CI applies to a disposable Supabase and the same
ten `npm run db:apply` applies in Node. That is DEV_LOG **D6**: one chain, three places.

```
        a screen
           │  worldFleets() · cmdIssue(fleet, "BUY sal 50", version) · …
           ▼
  src/lib/rpc/index.ts        the typed surface — 9 functions, RpcResult<T>, no SQL
           │
  src/lib/rpc/backend.ts      ONE dispatcher, ONE installed backend, no per-call branching
           │
     ┌─────┴─────┐
     ▼           ▼
  local        cloud          ← chosen ONCE, in src/lib/rpc/init.ts, from `hasCloud`
  PGlite       supabase.rpc
     │
  src/lib/db   boots the engine, applies the chain, persists it, seeds the K.1 house
```

---

## 1. What a screen has to do

```ts
// once, at app boot (before any screen reads anything)
import { initRpc } from '../lib/rpc'
await initRpc()                       // → 'local' | 'cloud'

// anywhere
import { worldFleets, cmdIssue } from '../lib/rpc'

const fleets = await worldFleets()
if (!fleets.ok) return <Notice code={fleets.refusal.code}>{fleets.refusal.sentence}</Notice>
const gaivota = fleets.value[0]

const issued = await cmdIssue(gaivota.id, 'BUY sal 50', gaivota.version)
if (!issued.ok) {
  // A refusal is DATA. code + sentence + fixes, exactly as DESIGN F.5 promises.
  showRefusal(issued.refusal.code, issued.refusal.sentence, issued.refusal.fixes)
}
```

Rules that fall out of that:

* **Nothing throws.** Every function returns `RpcResult<T>` = `{ok:true, value}` or
  `{ok:false, refusal}`. Faults (a dead network, a missing RPC, a constraint violation) arrive in
  the same shape with `refusal.source === 'fault'`, so a screen has exactly one failure path.
* **No screen imports `supabase`, `PGlite`, or `hasCloud`.** If one does, the seam has failed.
* **A read is the catch-up.** `world.fleets()` settles every voyage before it answers, so the way
  to advance time is to *read again*. There is no tick loop to write on the client.
* **Carry the version.** Pass `fleet.version` into `cmdIssue`; a mismatch comes back as `E_STALE`
  rather than as a duplicated order (DESIGN F.3).
* **IDs are uuids, not codes.** `worldMarket()` takes `SnapshotPort.id`. Ports and goods are
  identified by code *in text the player types*, and by uuid in every RPC argument.

### Boot progress

`openLocalDb()` publishes to `bootChannel` (`src/lib/db/bootState.ts`), and `useDbBoot()` is the
React subscription:

```tsx
const boot = useDbBoot()      // {phase, message, migration, progress, error, rebuilt, elapsedMs}
if (boot.phase === 'failed') return <Fatal>{boot.error}</Fatal>
if (boot.phase !== 'ready')  return <Progress value={boot.progress}>{boot.message}</Progress>
```

`idle → booting → applying → seeding → ready`, or `failed` with an error. **`failed` must be
rendered as a failure.** A spinner that keeps spinning is what a swallowed exception looks like.

---

## 2. Measured cost (this machine, production build, Chromium)

| | measured |
|---|---|
| **Cold boot** (empty IndexedDB) | **5,513 ms** to `ready` — 133 ms start, 2,234 ms WASM + initdb, **2,732 ms** applying 10 migrations (10 self-assert receipts), 167 ms seeding |
| **Warm boot** (reload, world in IndexedDB) | **1,039 ms** to `ready`, chain not re-applied |
| First `world.fleets()` after boot | 57 ms |
| Chain apply under Node (`npm run db:apply`) | ~1.3–2.4 s |

Bundle cost, measured by building the seam as its own app-mode entry (nothing else imports it
yet, so today's `dist/` is unchanged at 376 kB):

| asset | raw | gzip |
|---|---|---|
| `pglite.wasm` | 10,087,563 | 3,396,111 |
| `pglite.data` | 6,293,225 | 1,875,469 |
| PGlite JS glue | 601,731 | 138,659 |
| `initdb.wasm` | 395,059 | 144,898 |
| **the db chunk** (adapter + the 10 migrations inlined as text) | 284,368 | 70,956 |
| the RPC surface + boot hook + supabase client | ~15,000 | ~6,200 |
| **total** | **17.69 MB** | **≈5.64 MB** |

**That is the honest number: local mode costs about 5.6 MB gzipped on first load.** All of it sits
behind a dynamic `import()` in `init.ts`, so a build configured with a cloud project downloads
none of it. The wasm and data are immutable, hashed assets, so a second visit is browser-cache
only, and the world itself is not rebuilt.

Two things that could be made cheaper later, neither done yet: fingerprinting the chain at build
time (so the 71 kB of SQL is fetched only when a rebuild is actually needed), and running PGlite
in a worker (so a 2.7 s apply does not sit on the main thread).

---

## 3. How the local engine behaves

* **The SQL has one home.** `chainSource.ts` uses `import.meta.glob('../../../supabase/migrations/
  *.sql', {query:'?raw', eager:true})`, resolved by Vite at build time. There is no generated copy
  of the SQL and no second chain. A Node process (the specs) reads the same directory through
  `chainSource.node.mjs`. Two transports, one source.
* **It persists.** `idb://byeharu-voyage-v0`. Closing the tab does not sink the fleet.
* **It never applies half a chain.** The applied chain's fingerprint is stored in `app_local.chain`
  *inside the database*. On boot: same fingerprint → reuse; different → **demolish and rebuild from
  0001**, saying so in the console. Applying six new migrations onto a four-migration database
  would produce a schema that exists in no repository.
* **It seeds through the chain's own founding function.** `public.new_house(uid, 'Casa de Aveiro',
  'PRT')` — §K.1's opening: 8,000 ducats, one Barca named *Gaivota*, docked at Lisboa. No INSERT is
  written here; the purse arrives through the ledger, past the same triggers that guard every later
  ducat.
* **One local captain**, `LOCAL_AUTH_UID`, recorded in the database beside the data it owns.
  `cmd.assume_identity()` is called inside the same transaction as every RPC, because it is
  transaction-local by design.
* **RLS is bypassed locally.** PGlite runs single-user as superuser. The lockdown and the policies
  are proven by `npm run db:proof` (which deliberately *becomes* `anon`) and by CI's disposable
  Supabase. Local play proves the RULES, not the WALLS.

Cloud mode is written and typed but **has never made a round trip** (DEV_LOG D7: no free Supabase
slot). When it does, the project's API settings must expose the `world` and `cmd` schemas —
PostgREST serves `public` only by default.

---

## 4. Fixture → RPC: the rewiring table

`src/fixtures/v0.ts` builds a `V0World`; the RPCs return the payloads below. This table is
field-for-field. **`—` means the RPC does not serve it at all**, and every one of those is a
decision to make, not an oversight to fix silently.

### 4.1 Top level

| `V0World` | RPC | note |
|---|---|---|
| `nowMs` | — | the client's own clock. The server's answers are already settled to now. |
| `calendarEpochMs`, `epochYear` | — | not served. `config.time_compression` (480) is; the calendar epoch is a client constant. |
| `player` | `worldLedger().ducats` only | see 4.2 — the biggest gap. |
| `ports` | `worldSnapshot().ports` | 4.3 |
| `legs` | `worldSnapshot().legs` | 4.4 |
| `goods` | `worldSnapshot().goods` | 4.5 |
| `shipClasses` | `worldSnapshot().ship_classes` | 4.6 |
| `fleets` | `worldFleets()` | 4.7 — ships, queue and voyage are NESTED inside each fleet |
| `ships` | `worldFleets()[i].ships` | no flat ship list |
| `orders` | `worldFleets()[i].queue` | no flat order list; only pending/active/failed are returned |
| `portGoods` | `worldMarket(portId).goods` | one port per call, priced — 4.9 |
| `ledger` | `worldLedger().events` | 4.10 |
| `currentPort` | — | client UI state. The natural default is `fleets[0].port`. |

### 4.2 Player — **NOT SERVED**

| fixture `Player` | RPC | note |
|---|---|---|
| `ducats` | `worldLedger().ducats` | also `ledger_sum`, which must equal it |
| `companyName` | — | in `public.players`, no RPC reads it. Locally it is always `Casa de Aveiro`. |
| `nation` | — | in `public.players.nation_id`, not served |
| `companyLevel` | — | column exists (`company_level`), not served |
| `maxFleets`, `maxShips` | `worldSnapshot().config.fleet_max` / `.ship_max` | **global knobs, not per-player caps** |
| `taxRelief`, `reputation`, `reputationLabel` | — | no reputation system in the V0 chain at all |

→ A PROFILE/RANK screen cannot be driven by V0 RPCs. It needs a `world.player()` RPC (a migration),
or those fields stay on fixtures and are visibly marked as not-yet-real.

### 4.3 Port

| fixture `Port` | `SnapshotPort` | note |
|---|---|---|
| — | `id` | **uuid — the argument `worldMarket()` takes** |
| `code`, `name`, `country`, `nation`, `lat`, `lon`, `sea`, `culture` | same names | `sea` is the sea's NAME; `nation` is the nation CODE |
| `sizeTier` | `size_tier` | |
| `devIndustry` / `devCommerce` / `devMilitary` | `dev_industry` / `dev_commerce` / `dev_military` | |
| `maxDraft` | `max_draft` | |
| `hasYard`, `yardTier` | `has_yard`, `yard_tier` | |
| `marketTaxRate` | `tax_rate` | **renamed** |
| `crewPool` | `crew_pool` | |
| — | `region`, `has_academy`, `is_ice_closed` | new; `region` is the region CODE |
| `crewPoolMax` | — | not served |
| `crewRate`, `waterPrice`, `foodPrice`, `repairRate` | — | **not served.** The server prices HIRE / PROVISION / REPAIR when the order runs; a screen cannot pre-quote them without `cmdPreview()`. |
| `specialties` | — | derive it: the goods with the highest `affinity`… which is also not served. Use `worldMarket()`'s `advice`/`pct_nbr` instead. |
| `languages` | — | not in the schema |
| `fleetsDocked` | — | not served (J.3 presence is V1) |

### 4.4 Leg

| fixture `Leg` | `SnapshotLeg` | note |
|---|---|---|
| `from`, `to` | `from`, `to` | port CODES, canonically ordered, stored once — the graph is undirected |
| `hazardMult` | `hazard_mult` | |
| `notes` | `notes` | |
| — | `id`, **`nm`** | the AUTHORED sailed distance. The fixture had no distance and the client computed a great circle (`features/command/geo.ts`); the server's `nm` includes the detour factor and **is the number the game uses**. Prefer it. |

### 4.5 Good

| fixture `Good` | `SnapshotGood` | note |
|---|---|---|
| `code`, `name`, `category`, `bulk` | same | |
| `baseValue` | `base_value` | |
| `perishablePctDay` | `perishable_pct_day` | |
| `forbiddenCultures` | `culture_mask` | **renamed**; same meaning (cultures that will NOT trade it) |
| — | `id` | uuid |
| `english` | — | not in the schema |
| `stockTargetBase` | — | superseded: stock targets are per (port, good) — `worldMarket().goods[].stock_target` |

### 4.6 Ship class

| fixture `ShipClass` | `SnapshotShipClass` | note |
|---|---|---|
| `code`, `name`, `rig`, `hold`, `guns`, `draft` | same | |
| `crewRequired`, `crewMax` | `crew_required`, `crew_max` | |
| `speedKn` | `speed_kn` | |
| `maxDurability` | `durability` | **renamed** — on a *class* it is the maximum |
| `role` | — | not served; `family` + `tier` are |
| — | `id`, `family`, `tier`, `build_hours`, `build_cost` | new |

### 4.7 Fleet

| fixture `Fleet` | `FleetView` | note |
|---|---|---|
| `id`, `name`, `status` | same | statuses are the identical six |
| `portCode` | `port` | **renamed**; port CODE, null while SAILING |
| `busyUntilMs` | `busy_until` | **ISO string, not ms.** `Date.parse()` it. |
| `voyage` | `voyage` | different shape — 4.8 |
| — | `version` | pass into `cmdIssue` |
| — | `speed_kn`, `endurance_days` | **server-computed.** `features/fleets/fleetMath.ts` computes these client-side today; the server's numbers are the ones the game obeys. |
| — | `ships[]`, `queue[]` | nested here, not separate collections |

### 4.8 Voyage — **shape change, read this one**

| fixture `Voyage` | `FleetVoyage` | note |
|---|---|---|
| `id` | `id` | |
| `path: PortCode[]` | — | **not served.** Only the CURRENT leg is: `position.from_code` → `position.to_code`. A map that draws the whole planned route has no data for the legs beyond the current one. |
| `departedAtMs` | — | not served; `eta` (ISO) is |
| `speedKn` | — | frozen server-side in `voyages.speed_profile`; the fleet's current `speed_kn` is served instead |
| — | `eta`, `total_nm`, `nm_done` | progress is a server number, not a client interpolation |
| — | `position` | `{leg_index, from_code, to_code, leg_frac, nm_done, total_nm, lat, lon}` — **the closed-form position**. Draw the ship at `lat`/`lon`; do not re-derive it. |

### 4.9 Ship and cargo

| fixture `Ship` | `FleetShip` | note |
|---|---|---|
| `id`, `name`, `crew` | same | |
| `classCode` | `class` | **the class NAME (`Barca`), not the code.** Join to `ship_classes` by `name`, or match on `name`. |
| `fleetId` | — | implied by nesting |
| `isFlagship` | `is_flagship` | |
| `durability` | `durability` (+ `max_durability`) | the ratio no longer needs a class lookup |
| `waterT`, `foodT` | `water_t`, `food_t` | |
| `cargo: CargoLot[]` | `cargo: Record<goodCode, tuns>` | **shape change: a map, not a list.** |
| `CargoLot.avgCost` | — | **not served.** The Fleets tab's average-cost column has no source. Purchase prices are in the ledger's `BOUGHT` events (`avg_price`), so it can be reconstructed — or dropped. |
| — | `hold`, `cargo_tuns`, `crew_required`, `crew_max` | free space = `hold - cargo_tuns` |

### 4.10 Order queue

| fixture `QueuedOrder` | `QueuedOrder` | note |
|---|---|---|
| `id`, `seq`, `status` | same | statuses identical |
| `raw` | `text` | **renamed** |
| `fleetId` | — | implied by nesting |
| `errorCode` | `error_code` | plus `error_message` (a sentence) |
| — | `verb`, `result` | `result` is the verb-shaped outcome of a completed order |

`cmd.issue()`'s own `order` field is smaller than this — no `text`, no `verb` (see `IssuedOrder`);
the `queue` in the same response carries both.

### 4.11 Market

| fixture `PortGood` | `MarketGood` | note |
|---|---|---|
| `port`, `good` | `good_id` + the port in `MarketView.port` | one port per call |
| `stock`, `stockTarget` | `stock`, `stock_target` | plus `stock_band` (0–6, ready for the meter) |
| — | `buy`, `sell`, `mid` | **the prices, derived server-side.** `features/market/prices.ts` computes these today; delete that path rather than reconciling two price authorities. |
| — | `pct_nbr` | the §E.4 %NBR, defined once, over ports within 600 nm |
| — | `advice` | `'buy'` / `'hold'` / `'sell'` — what the MARKET tab sorts on |
| — | `available` | false where the port's culture refuses the good (wine at Tunis) |
| `affinity`, `drift`, `seasonMod` | — | authored server-side, deliberately not served — they are the price, and the client is told the price |
| `history7` | — | **not served.** `Sparkline` has no data. Either a migration stores a price history, or the sparkline is not V0. |
| `event` | — | G.6 market events are not in the V0 chain |

### 4.12 Ledger

| fixture `LedgerEntry` | `LedgerEvent` | note |
|---|---|---|
| `id` | `id` | |
| `atMs` | `at` | **ISO string, not ms** |
| `kind` | `kind` | **different vocabulary.** Server kinds: `FOUNDED`, `BOUGHT`, `SOLD`, `DEPARTED`, `VOYAGE_REPORT`, `PROVISIONED`, `HIRED`, `REPAIRING`, `REPAIRED`. The fixture's `TRADE`/`VOYAGE`/`PORT`/… do not exist. |
| `ducatsDelta` | `ducats_delta` | null when the event moved no money |
| `balanceAfter` | `balance_after` | null likewise |
| `actor` | `payload.fleet` | inside the payload |
| `headline` | — | **not served.** The client composes it from `kind` + `payload`. |
| `report` | `payload.lines` (on `VOYAGE_REPORT`) | `string[]` of prose, `"Day 1. A quiet watch; nothing to report."` — already sentences, not codes |
| `lines` | — | the itemised block is not served |
| `unread` | — | client-side state |

Payloads by kind: `FOUNDED {company, port}` · `BOUGHT`/`SOLD` `{fleet, good, qty, avg_price,
total}` · `DEPARTED {fleet, voyage_id, total_nm, legs, eta}` · `VOYAGE_REPORT {fleet, voyage_id,
from, to, total_nm, lines[]}`.

**An honest gap, asserted in `tests/rpc.firstSession.spec.ts`:** `WAGES` and some other costs are
credited *without* an event behind them, so they reconcile inside `ducats` but never appear as a
row in `events`. **Summing the rendered rows will not equal the printed balance.** Print
`balance_after`, never a running total the screen adds up.

---

## 5. Files

| file | what it is |
|---|---|
| `db/chain.ts` | ordering, the LF/version preconditions, the fingerprint. Pure. |
| `db/chainSource.ts` | **browser** transport: `import.meta.glob` over `supabase/migrations/` |
| `db/chainSource.node.mjs` (+`.d.mts`) | **Node** transport, for specs. Plain JS so a spec never gets Node globals in ambient scope. |
| `db/applyChain.ts` | applies the files; loud, file-named, SQLSTATE-carrying failure |
| `db/bootState.ts` | the boot state machine and its observable |
| `db/useDbBoot.ts` | `useSyncExternalStore` over it |
| `db/localDb.ts` | opens PGlite, persists, rebuilds on chain change, seeds, `callAs()` |
| `db/index.ts` | browser entry: `startLocalDb()`, one engine, idempotent |
| `rpc/types.ts` | the payload contract, typed from the SQL |
| `rpc/catalog.ts` | the 9 RPCs, named once; both backends are built from it |
| `rpc/result.ts` | `RpcResult`, `Refusal`, and the mapping from anything thrown |
| `rpc/backend.ts` | the registry and THE call path |
| `rpc/localBackend.ts` / `rpc/cloudBackend.ts` | the two implementations |
| `rpc/init.ts` | **the one place that reads `hasCloud`** |
| `rpc/index.ts` | the typed surface a screen imports |

Proofs: `tests/db.chain.spec.ts`, `tests/rpc.surface.spec.ts`, `tests/rpc.firstSession.spec.ts` —
pure Node, no browser, real Postgres.

## 6. Known gaps

1. **`@electric-sql/pglite` is a devDependency.** It is now shipped to the browser and belongs in
   `dependencies`. Not moved here: `package.json` is outside this domain and other agents are
   editing the repo concurrently. One line, and it must happen before a deploy that installs with
   `--omit=dev`.
2. **The cloud backend has never made a round trip** (no Supabase project — D7). Its shape is
   proven; its behaviour is not.
3. **No player RPC** (§4.2), **no voyage path** (§4.8), **no price history** (§4.11), **no cargo
   average cost** (§4.9). Each needs a migration or a screen decision.
4. **The chain is downloaded on every boot** (71 kB gzipped) even when the stored world is current,
   because the fingerprint is computed from the text. A build-time fingerprint would remove that.
5. **PGlite runs on the main thread.** A 2.7 s chain apply blocks it. A worker build exists
   upstream (`@electric-sql/pglite/worker`) and is untried here.
