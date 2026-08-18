# The V0 chain

Ten migrations. Each one establishes **one concept**, and each one **proves its own effect in the
same transaction that applies it** — see `README.md` §3 for the self-assert rules this chain follows.

Every migration also re-asserts the grant lockdown of 0001 through the single authority
`public.client_write_grants()`, because a new table is exactly where the predecessor's
`GRANT ALL ON TABLES TO anon` came back.

Run it locally, in about ten seconds, with no Docker:

```
npm run db:check-versions   # no two files share a 14-digit version (a duplicate deploys as a no-op)
npm run db:apply            # apply the whole chain to real PostgreSQL 18 (PGlite) and print every receipt
npm run db:proof            # apply, then run scripts/db/proofs/*.sql and check every declared PASS marker
```

---

| # | File | What it establishes | What it self-asserts |
|---|---|---|---|
| **0001** | `the_world_is_read_only_to_everyone_but_the_server` | The `world`/`cmd`/`voyage` schemas; gap-filling shims for `anon`/`authenticated`/`service_role`/`auth.uid()` so the identical SQL runs on Supabase and on PGlite; `world_config` (36 knobs, every one described, **server-only** because it holds `world_secret`); the one knob reader `wc()`; and THE LOCKDOWN — every write revoked from the client roles on tables, sequences and functions in all four schemas, plus the DEFAULT PRIVILEGES retuned so nothing created later inherits one, **for this role and for every other grantor `pg_default_acl` names** (§5b; see the 2026-08-18 note below). Mints `public.client_write_grants()`, the one authority for "does a client role hold a write?". | `client_write_grants()` is empty — **after** a deliberately-granted probe table proves the query can find one (2 grants found, then revoked). The same zero independently through `information_schema.role_table_grants`. No default ACL grants a client a write or an execute. `world_config` has RLS on and **no** privileges for any client role. All 36 knobs described and readable; `wc()` **raises** on an unknown key rather than inventing a default. `gen_random_uuid()` and `auth.uid()` resolve. |
| **0002** | `the_static_world_exists` | `nations, seas, regions, ports, legs, goods, ship_classes` with RLS and read-only access for signed-in players. `legs` stores each edge **once**, canonically ordered, `UNIQUE` on the unordered pair. And `voyage.gc_distance_nm()` — the haversine of §B.3, IMMUTABLE, the one distance authority. | All seven tables exist, RLS is on all seven, each has **exactly one** SELECT policy, `authenticated` holds SELECT on all seven, lockdown still zero. `gc_distance_nm` reproduces DESIGN §B.3's own published figures: Lisboa–Cádiz **188.40 nm** and Ceuta–Tunis **750.75 nm**; zero on identity; symmetric. The second figure is a negative control — one number could be a stuck constant, two cannot. |
| **0003** | `twelve_ports_and_the_water_between_them` | The §K.1 world, seeded: 4 nations, 8 seas, 4 regions, **12 ports** at §B.2's exact coordinates, **22 legs**, **12 goods**, **3 ship classes**. Leg distances are the haversine times an authored detour factor where the sailed route rounds land; the factor and its reason are written into each leg's `notes`. | Counts against §K.1 (12/22/12/3). Every leg's endpoints resolve. Canonical ordering with no duplicate unordered pair. **No leg is shorter than the great-circle** between its ports, and the worst detour is ×1.604 (Cádiz→Sevilla, up the Guadalquivir) — a positive control, since a worst ratio of 1.000 would mean the detour data never landed. All **five** distances §B.3 publishes match exactly. The leg graph is **connected**: all 12 ports reachable from Lisboa. Every nation's capital resolves. The culture mask both **blocks** (wine refused at 2 Maghrebi ports) and **permits** (open at 10 Latin ones). |
| **0004** | `a_house_its_fleets_and_an_honest_ledger` | `players, fleets, ships` + the append-only `events` and `ledger`. `public.credit()` is the ONE money mover; `emit_event()` the ONE event writer; `current_player_id()` the ONE auth→player translation every RLS policy calls. The purse invariant `Σ ledger.ducats_delta = players.ducats` is a pair of **deferrable constraint triggers** over one check function — not a job that hopes. Structural rules: a composite FK makes a crossed ship/fleet owner impossible, a partial unique index allows at most one flagship, `ducats >= 0` is a CHECK. | Inside a rolled-back probe: `new_house()` opens with 8,000 ducats reconciled on both sides, and **five positive controls all bite** — an unbacked purse write, an UPDATE on the ledger, a DELETE on events, a second flagship, and an overdraft are each REJECTED. The probe then rolls back to zero rows, which is itself asserted. |
| **0005** | `every_price_is_derived_never_stored` | `port_goods` (144 rows: 12 ports × 12 goods of authored affinity, with `stock_target` and `production_rate` **derived** from size and affinity so two numbers cannot disagree), `trade_daily` for the §G.7.1 cap, and the §G.1 price: `world.mid_price(port, good, stock)` — taking stock as a parameter so one function serves both the spot price and every step of a large order — plus `world.spread`, `world.tax_rate`, `world.price`, and `world.quote()`, the stepped 10-tun execution that IS the price impact and also handles limit-order partial fills. | 144 rows; all 144 prices positive, inside the §G.7.3 band, `ask > bid`. **Price impact is real**: 200 tuns average 7.30 d. against 10 tuns at 6.95. **§G.7.4 holds on all 144 pairs**: a same-port round trip loses money everywhere, with the probe asserted to have examined 144 pairs. The §K.1 gradient is real: 60 sal costs 422 d. at Lisboa and fetches 795 d. at Cádiz. A limit fills partially; an impossible limit fills zero. |
| **0006** | `a_voyage_is_a_pure_function_of_time` | `voyages` (with the frozen `speed_profile`) and `voyage_events` keyed `(voyage_id, day_index)`. Routing (`route_direct` + `route` composing hard VIA waypoints), `fleet_speed` (slowest ship then formation), `endurance_days`, `depart()`, and the closed-form `progress_nm`/`position`. `voyage.rng_raw()` is **IMMUTABLE**, so PostgreSQL itself forbids it from reading the clock or a table; the secret is passed in. Delays from CALM/STORM shift the schedule via `delay_before_day()`, and day boundaries are **clamped at the ETA**. | `rng_raw` is structurally IMMUTABLE, repeatable, and varies with day, stream and secret; 2,000 samples inside [0,1) with mean 0.4919. The router finds Lisboa→Tunis, honours a VIA waypoint, and returns NULL off-graph. The starter Barca sails 188 nm at 4.91 kn = **1.59 voyage-days / 4.78 real minutes** (§K.1 quotes 1.6 and 4.7). Progress is 0 at departure, monotonic, pinned at `total_nm` from the ETA on. A 24 sim-hour CALM moves the ETA by **exactly 180 real seconds**. Duplicate `(voyage_id, day_index)` and a second SAILING voyage are both REJECTED. |
| **0007** | `a_fleet_arrives_and_the_queue_runs_itself` | `orders`, the six executable V0 verbs (SAIL, BUY, SELL, PROVISION, HIRE, REPAIR), `cmd.resolve_qty()` (ALL/HALF/n% read at **execution** time), `cmd.advance()` with the §F.3 **halt rule**, `voyage.report_line()` for §E.6 prose, and `voyage.settle()` — the idempotent catch-up whose `resolved_at` is the deterministic day boundary, never `now()`. | The §K.1 session runs as a 4-order queue **with no tick**: bought 50 sal, sailed 188 nm, settled 5 checkpoints lazily, sold, sailed home, docked at Lisboa with 8,275 d. against 8,000. Four more `settle()` calls change nothing. Stores fell and 5 wage payments landed. All six verbs take effect. An impossible order fails with a code and leaves the next order **pending**, not skipped. |
| **0008** | `one_line_of_words_is_the_only_way_in` | `cmd.fold()` (one place where `cadiz` = `Cádiz`), `resolve_port/good/fleet` (prefix-unique, the only source of `E_NO_SUCH_*`/`E_AMBIGUOUS`), `cmd.parse()` — the one grammar — `cmd.verb_schema()` for the tap-builder, `cmd.fixes()` for §F.5's "→ do this instead", `cmd.cancel_at`/`cmd.clear`, and **`cmd.issue()`, the only mutating entry point in the game**. `cmd.preview()` runs the **real executor** in a subtransaction and discards it, so the dry run and the commit share one code path by construction. | `verb_schema` serves exactly the 8 V0 verbs. `cadiz`/`CADIZ`/`Cádiz`/`CAD` all resolve to one port; `8_000` = `8,000` = 8000. `"s"` raises `E_AMBIGUOUS` **naming Safi and Sevilla**; `"zzz"` raises `E_NO_SUCH_PORT`. Noise words are optional. **A preview of `BUY sal 40` estimates 280 d. and leaves the purse and the stock untouched.** `E_STALE`; `E_QUEUE_FULL` at exactly the configured 12; a refusal carries code + sentence + 2 fixes; CANCEL/CLEAR empty the queue with the voyage still at sea. |
| **0009** | `the_world_reads_back` | `world.snapshot()`, `world.market()`, `world.fleets()`, `world.ledger()` — and `world.pct_of_neighbours()`, the §E.4 `%NBR` defined once over ports within 600 nm. Every fleet read calls `voyage.settle()` first: **the read is the catch-up**. `snapshot()` serves an explicit allow-list of knobs, never `world_config` wholesale. | Snapshot carries 12 ports / 22 legs / 12 goods / 3 classes / 8 verbs — and **does not contain the world secret**, asserted by searching the serialised payload for the secret's VALUE, not by trusting a list of key names. `market(Lisboa)` prices all 12 and marks wine UNAVAILABLE at Tunis and available at Lisboa. Salt reads `%NBR` **50.3 at Lisboa and 120.6 at Cádiz** — the §K.1 gradient. `world.fleets()` **alone** settles a 9-hour-stale voyage and reports the fleet docked at Cádiz with no tick having run. |
| **0010** | `the_clock_ticks_for_everyone` | `tick_arrivals` (keyed by `(voyage_id, day_index)`), `tick_market_drift` (keyed by a **drift slot**, so a retried cron run cannot walk the market twice; stock regenerates in **closed form** over elapsed game-days), and `tick_reconcile` (read-only; asserts the purse invariant, the SAILING invariant and the lockdown). Scheduled through pg_cron where the platform has it, reported honestly where it does not. | `tick_arrivals` docks a fleet unattended and a second call touches 0 fleets. `tick_market_drift` steps all 144 rows once per slot and **0 rows on a repeat call in the same slot** — both directions, since idempotence claimed one way is half a claim. After 60 forced slots, 0 rows sit outside the §G.1 clamp. Stock regenerates 263 → 1050 toward a target of 1050 with 0 overshoots. `tick_reconcile` passes on a healthy world **and RAISES on a purse falsified by 4,242 ducats**. |

---

## The four proofs

`scripts/db/proofs/` — run by `npm run db:proof`, each inside a transaction that is rolled back.
Green means **every `-- @pass` marker the file declares actually appeared**; a file that declares
none fails as vacuous.

| Proof | Declares | Establishes |
|---|---|---|
| `01_offline_equivalence.sql` | 5 markers | DESIGN Appendix 2 §1. The **same** voyage — pre-screened to contain a real hazard — is settled day by day, the result captured, the settlement rolled away, and then settled **once, nine hours late**. `(day_index, kind, payload, resolved_at)` match to the character; so do the purse and the ETA. |
| `02_ledger_reconciliation.sql` | 6 markers | DESIGN Appendix 2 §2. 500 randomised orders across 3 houses with time jumping forward underneath them. Requires both successes **and** refusals and money moving both ways, then `purse = Σ ledger.ducats_delta` exactly — and finally falsifies a purse by **one ducat** to prove the check bites. |
| `03_grant_lockdown.sql` | 7 markers | DESIGN Appendix 2 §3. Not a catalogue query: it **becomes** `anon` and then `authenticated` and tries to INSERT into all 18 tables, requiring SQLSTATE **42501** specifically — a writable table would have failed 23502 instead. Also: `world_config` unreadable, RLS on every table, and `service_role` still able to write. |
| `04_first_session.sql` | 9 markers | §K.1's ten minutes, replayed as **typed strings through `cmd.issue()`**. Two honest divergences from the script are asserted rather than papered over: `BUY sal 60` does not fit a 60-tun hold carrying stores, and a laden Barca is slower than the 4.7 minutes quoted for an empty one. The house ends **+506 d. on an 8,000 d. stake**. |

## Two defects these proofs found

Recorded because a proof that has never caught anything is not yet known to work.

1. **`settle()` could dock a fleet with checkpoints unresolved.** A voyage's last day rarely divides
   evenly into 24 sim-hours, so the final boundary could fall after the ETA — and the *number* of
   checkpoints then depended on whether settle ran day by day or once at the end (10 against 12).
   Proof 1 caught it. Fixed by clamping `voyage.day_ends_at()` at the ETA (0006).
2. **`ALL`/`HALF` resolved at parse time** would have frozen a stale quantity into a queued order —
   `SELL cloves ALL`, typed in Lisboa, meant "the number aboard right now" rather than "whatever is
   aboard at Amsterdam". Fixed by `cmd.resolve_qty()` reading the hold at execution time (0007).

## 2026-08-18 — 0001 amended: the revoke had to name the grantor

CI's disposable-Supabase job failed applying 0001, on 0001's own assert:

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

The assert was right; the **revoke** was half a revoke. `ALTER DEFAULT PRIVILEGES ... REVOKE`
without `FOR ROLE` only ever touches the **current role's** defaults. Supabase's
`GRANT ALL ON TABLES/SEQUENCES/FUNCTIONS TO anon, authenticated, service_role` in `public` is
issued by its **own bootstrap role**, not by the role that applies migrations — so 0001 could not
see it, let alone clear it. The 16 are exactly: 12 table entries (`anon` + `authenticated` ×
INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER), 2 sequence entries (UPDATE), 2 function
entries (EXECUTE).

0001 §5b now sweeps them, driven by `pg_default_acl` itself rather than by a guess about which
roles a given Supabase version uses: it loops over every `(grantor, schema, object type)` the
catalogue reports under **the same predicate the assert uses**, and issues
`ALTER DEFAULT PRIVILEGES FOR ROLE <grantor> ... REVOKE ...` for each. It prints the grantors it
swept, and raises with an actionable message — naming the grantor and the membership needed — if a
revoke is refused. **Nothing was deployed anywhere, so 0001 was amended in place; no 0011 patch.**

The assert was **not** weakened. It was strengthened: its failure message now names the grantor,
schema, object type, grantee and privilege of every surviving entry, because "16 entries" cost a
CI round trip to diagnose when the grantor was the whole answer.

**And the local gate was made able to see it.** `npm run db:apply` boots a bare PGlite, which has
no client roles and no default ACLs at all — so this assert, and the whole grant/RLS family with
it, passed **vacuously**: nothing to find. `scripts/db/apply-chain.mjs` now applies
`scripts/db/supabase-preamble.sql` first (a **test fixture, never a migration**), installing those
roles and those default privileges under a foreign grantor. With it in place the unfixed 0001
fails locally with the identical 16-entry message CI reported. The fixture asserts its own effect
and raises if it stops modelling 16.

---

## What is NOT proven here

* **Supabase's own roles.** The preamble is a fixture a human wrote from what CI reported; it can
  drift from the platform, and it models only roles and default ACLs. Supabase creates the roles
  itself, *with* a default `GRANT ALL` — the exact drift that aborted the predecessor's deploy.
  Only the disposable-Supabase job in `.github/workflows/migrations-apply-proof.yml` proves the
  revoke lands against those, and it now re-checks the default ACLs from outside the migration.
* **pg_cron.** The tick functions are proven by being called, not by being scheduled. Nothing here
  shows a cron entry firing on a real Supabase project.
* **PostgREST exposure.** The RPCs live in the `world` / `cmd` / `voyage` schemas, as DESIGN
  Appendix 2 names them. Supabase's PostgREST exposes `public` by default: the project's API
  settings need `world, cmd, voyage` added to the exposed schemas before a browser can call them.
  That is configuration, not a second entry point, and it is deliberately not worked around with
  duplicate `public.` wrappers.
