# The V0 chain

Seventeen migrations. Each one establishes **one concept**, and each one **proves its own effect in the
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
| **0001** | `the_world_is_read_only_to_everyone_but_the_server` | The `world`/`cmd`/`voyage` schemas; gap-filling shims for `anon`/`authenticated`/`service_role`/`auth.uid()` so the identical SQL runs on Supabase and on PGlite; `world_config` (36 knobs, every one described, **server-only** because it holds `world_secret`); the one knob reader `wc()`; and THE LOCKDOWN — every write revoked from the client roles on tables, sequences and functions in all four schemas, plus **this role's** DEFAULT PRIVILEGES retuned so nothing it creates later inherits one (§5a; §5b explains why the platform's own defaults are deliberately left alone). Mints a second authority, `public.objects_not_owned_by()`. Mints `public.client_write_grants()`, the one authority for "does a client role hold a write?". | `client_write_grants()` is empty — **after** a deliberately-granted probe table proves the query can find one (2 grants found, then revoked). The same zero independently through `information_schema.role_table_grants`. No default ACL grants a client a write or an execute. `world_config` has RLS on and **no** privileges for any client role. All 36 knobs described and readable; `wc()` **raises** on an unknown key rather than inventing a default. `gen_random_uuid()` and `auth.uid()` resolve. |
| **0002** | `the_static_world_exists` | `nations, seas, regions, ports, legs, goods, ship_classes` with RLS and read-only access for signed-in players. `legs` stores each edge **once**, canonically ordered, `UNIQUE` on the unordered pair. And `voyage.gc_distance_nm()` — the haversine of §B.3, IMMUTABLE, the one distance authority. | All seven tables exist, RLS is on all seven, each has **exactly one** SELECT policy, `authenticated` holds SELECT on all seven, lockdown still zero. `gc_distance_nm` reproduces DESIGN §B.3's own published figures: Lisboa–Cádiz **188.40 nm** and Ceuta–Tunis **750.75 nm**; zero on identity; symmetric. The second figure is a negative control — one number could be a stuck constant, two cannot. |
| **0003** | `twelve_ports_and_the_water_between_them` | The §K.1 world, seeded: 4 nations, 8 seas, 4 regions, **12 ports** at §B.2's exact coordinates, **22 legs**, **12 goods**, **3 ship classes**. Leg distances are the haversine times an authored detour factor where the sailed route rounds land; the factor and its reason are written into each leg's `notes`. | Counts against §K.1 (12/22/12/3). Every leg's endpoints resolve. Canonical ordering with no duplicate unordered pair. **No leg is shorter than the great-circle** between its ports, and the worst detour is ×1.604 (Cádiz→Sevilla, up the Guadalquivir) — a positive control, since a worst ratio of 1.000 would mean the detour data never landed. All **five** distances §B.3 publishes match exactly. The leg graph is **connected**: all 12 ports reachable from Lisboa. Every nation's capital resolves. The culture mask both **blocks** (wine refused at 2 Maghrebi ports) and **permits** (open at 10 Latin ones). |
| **0004** | `a_house_its_fleets_and_an_honest_ledger` | `players, fleets, ships` + the append-only `events` and `ledger`. `public.credit()` is the ONE money mover; `emit_event()` the ONE event writer; `current_player_id()` the ONE auth→player translation every RLS policy calls. The purse invariant `Σ ledger.ducats_delta = players.ducats` is a pair of **deferrable constraint triggers** over one check function — not a job that hopes. Structural rules: a composite FK makes a crossed ship/fleet owner impossible, a partial unique index allows at most one flagship, `ducats >= 0` is a CHECK. | Inside a rolled-back probe: `new_house()` opens with 8,000 ducats reconciled on both sides, and **five positive controls all bite** — an unbacked purse write, an UPDATE on the ledger, a DELETE on events, a second flagship, and an overdraft are each REJECTED. The probe then rolls back to zero rows, which is itself asserted. |
| **0005** | `every_price_is_derived_never_stored` | `port_goods` (144 rows: 12 ports × 12 goods of authored affinity, with `stock_target` and `production_rate` **derived** from size and affinity so two numbers cannot disagree), `trade_daily` for the §G.7.1 cap, and the §G.1 price: `world.mid_price(port, good, stock)` — taking stock as a parameter so one function serves both the spot price and every step of a large order — plus `world.spread`, `world.tax_rate`, `world.price`, and `world.quote()`, the stepped 10-tun execution that IS the price impact and also handles limit-order partial fills. | 144 rows; all 144 prices positive, inside the §G.7.3 band, `ask > bid`. **Price impact is real**: 200 tuns average 7.30 d. against 10 tuns at 6.95. **§G.7.4 holds on all 144 pairs**: a same-port round trip loses money everywhere, with the probe asserted to have examined 144 pairs. The §K.1 gradient is real: 60 sal costs 422 d. at Lisboa and fetches 795 d. at Cádiz. A limit fills partially; an impossible limit fills zero. |
| **0006** | `a_voyage_is_a_pure_function_of_time` | `voyages` (with the frozen `speed_profile`) and `voyage_events` keyed `(voyage_id, day_index)`. Routing (`route_direct` + `route` composing hard VIA waypoints), `fleet_speed` (slowest ship then formation), `endurance_days`, `depart()`, and the closed-form `progress_nm`/`position`. `voyage.rng_raw()` is **IMMUTABLE**, so PostgreSQL itself forbids it from reading the clock or a table; the secret is passed in. Delays from CALM/STORM shift the schedule via `delay_before_day()`, and day boundaries are **clamped at the ETA**. | `rng_raw` is structurally IMMUTABLE, repeatable, and varies with day, stream and secret; 2,000 samples inside [0,1) with mean 0.4919. The router finds Lisboa→Tunis, honours a VIA waypoint, and returns NULL off-graph. The starter Barca sails 188 nm at 4.91 kn = **1.59 voyage-days / 4.78 real minutes** (§K.1 quotes 1.6 and 4.7). Progress is 0 at departure, monotonic, pinned at `total_nm` from the ETA on. A 24 sim-hour CALM moves the ETA by **exactly 180 real seconds**. Duplicate `(voyage_id, day_index)` and a second SAILING voyage are both REJECTED. |
| **0007** | `a_fleet_arrives_and_the_queue_runs_itself` | `orders`, the six executable V0 verbs (SAIL, BUY, SELL, PROVISION, HIRE, REPAIR), `cmd.resolve_qty()` (ALL/HALF/n% read at **execution** time), `cmd.advance()` with the §F.3 **halt rule**, `voyage.report_line()` for §E.6 prose, and `voyage.settle()` — the idempotent catch-up whose `resolved_at` is the deterministic day boundary, never `now()`. | The §K.1 session runs as a 4-order queue **with no tick**: bought 50 sal, sailed 188 nm, settled 5 checkpoints lazily, sold, sailed home, docked at Lisboa with 8,275 d. against 8,000. Four more `settle()` calls change nothing. Stores fell and 5 wage payments landed. All six verbs take effect. An impossible order fails with a code and leaves the next order **pending**, not skipped. |
| **0008** | `one_line_of_words_is_the_only_way_in` | `cmd.fold()` (one place where `cadiz` = `Cádiz`), `resolve_port/good/fleet` (prefix-unique, the only source of `E_NO_SUCH_*`/`E_AMBIGUOUS`), `cmd.parse()` — the one grammar — `cmd.verb_schema()` for the tap-builder, `cmd.fixes()` for §F.5's "→ do this instead", `cmd.cancel_at`/`cmd.clear`, and **`cmd.issue()`, the only mutating entry point in the game**. `cmd.preview()` runs the **real executor** in a subtransaction and discards it, so the dry run and the commit share one code path by construction. | `verb_schema` serves exactly the 8 V0 verbs. `cadiz`/`CADIZ`/`Cádiz`/`CAD` all resolve to one port; `8_000` = `8,000` = 8000. `"s"` raises `E_AMBIGUOUS` **naming Safi and Sevilla**; `"zzz"` raises `E_NO_SUCH_PORT`. Noise words are optional. **A preview of `BUY sal 40` estimates 280 d. and leaves the purse and the stock untouched.** `E_STALE`; `E_QUEUE_FULL` at exactly the configured 12; a refusal carries code + sentence + 2 fixes; CANCEL/CLEAR empty the queue with the voyage still at sea. |
| **0009** | `the_world_reads_back` | `world.snapshot()`, `world.market()`, `world.fleets()`, `world.ledger()` — and `world.pct_of_neighbours()`, the §E.4 `%NBR` defined once over ports within 600 nm. Every fleet read calls `voyage.settle()` first: **the read is the catch-up**. `snapshot()` serves an explicit allow-list of knobs, never `world_config` wholesale. | Snapshot carries 12 ports / 22 legs / 12 goods / 3 classes / 8 verbs — and **does not contain the world secret**, asserted by searching the serialised payload for the secret's VALUE, not by trusting a list of key names. `market(Lisboa)` prices all 12 and marks wine UNAVAILABLE at Tunis and available at Lisboa. Salt reads `%NBR` **50.3 at Lisboa and 120.6 at Cádiz** — the §K.1 gradient. `world.fleets()` **alone** settles a 9-hour-stale voyage and reports the fleet docked at Cádiz with no tick having run. |
| **0010** | `the_clock_ticks_for_everyone` | `tick_arrivals` (keyed by `(voyage_id, day_index)`), `tick_market_drift` (keyed by a **drift slot**, so a retried cron run cannot walk the market twice; stock regenerates in **closed form** over elapsed game-days), and `tick_reconcile` (read-only; asserts the purse invariant, the SAILING invariant and the lockdown). Scheduled through pg_cron where the platform has it, reported honestly where it does not. | `tick_arrivals` docks a fleet unattended and a second call touches 0 fleets. `tick_market_drift` steps all 144 rows once per slot and **0 rows on a repeat call in the same slot** — both directions, since idempotence claimed one way is half a claim. After 60 forced slots, 0 rows sit outside the §G.1 clamp. Stock regenerates 263 → 1050 toward a target of 1050 with 0 overshoots. `tick_reconcile` passes on a healthy world **and RAISES on a purse falsified by 4,242 ducats**. |
| **0011** | `a_captain_signs_the_book` | `cmd.found_house(name, nation)` — the ONE way a signed-in player gets a house. Takes NO uid: it reads `auth.uid()`, so a caller can only ever found their own. | anon may not execute it and `authenticated` may; an unsigned caller is refused `E_NOT_SIGNED_IN`; a captain opens with the K.1 purse and 1 ship at LIS; and four positive controls BITE — a second house, a taken name, a 1-character name and an unknown nation. |
| **0012** | `the_clock_is_wound` | **When** the ticks run. 0010 owns what a tick DOES; this owns only its cadence, and derives it from `drift_slot_seconds` through `tick_cron_expression()` rather than restating a crontab. | The crontab and the knob agree; a 30-second and a 35-minute slot are both REFUSED rather than rounded; under PGlite it applies cleanly, schedules nothing, and says so. |
| **0013** | `a_price_remembers_what_it_was` | `public.price_history`, keyed `(port, good, slot)` so a retried run is a no-op **by construction**; `public.drift_slot_of()` as the named slot authority; `tick_price_snapshot()` (samples + prunes); and `world.price_history(port, slots)` — ONE call per port, keyed by good CODE, because a market screen draws a line per row. Derivation stays the only way a price is COMPUTED; this only records what it said. | `drift_slot_of()` returns the slot `tick_market_drift()` itself reports — the whole reason a second named authority is allowed to exist. A snapshot writes one row per market pair (**14,980**) and a repeat call in the same slot writes **0**. The recorded mid IS `world.mid_price` of the recorded stock. A row aged past the 288-slot window is **pruned**, proven by ageing one on purpose. |
| **0014** | `a_house_reads_its_own_name` | `world.player()` — the player row, at last, taking **no id** (identity is the JWT's). And `public.player_fame()`: fame **DERIVED** from the append-only record, never a counter, because 0007's verbs are deployed and because a stored total can drift from the ledger it is computed from. Weights are knobs. | A signed-in account with no house reads back `{"player": null}` — a STATE, not a refusal. A founded house reads its own name, nation, purse, counts and port. Fame opens at **0**, and a real purchase of 5,310 d. turnover scores **exactly 53** trade fame at 100 d./point — the stated amount, not merely non-zero — with exploration still 0 because nothing has arrived anywhere. |
| **0015** | `an_officer_signs_on` | `officers` + `player_officers` (the posting lives on the OFFICER's row — SECTIONS.md forbids officer columns on ships/fleets), `fleet_officer_bonus()` as the one reading, `cmd.hire_officer` / `cmd.post_officer`, `world.officers()`. **SUPERSEDES `voyage.fleet_speed()`** so a navigator actually makes the ship faster. | No officer column exists on ships or fleets. An unofficered fleet reads 0006's **exact** speed (4.9125 kn), so the supersede is a no-op without officers. A +8.00% navigator takes it to **5.3055 kn** — the stated amount — and the wage leaves the purse through `public.credit`. The per-fleet cap clamps the sum. Four refusals BITE. `world.officers()` reports `takes_effect` FALSE for the three specialties no rule reads. |
| **0016** | `a_captain_learns_a_trade` | `skills` + `player_skills` (never columns on `players`), `player_skill_bonus()`, `cmd.study_skill()`, `world.skills()`. A skill is **studied for money at a port with an academy** — not earned by XP, because XP means hooking 0007's deployed verbs, and because a derived skill would level itself and stop being a choice. **SUPERSEDES `voyage.endurance_days()`.** `ports.has_academy` finally means something. | At level 0 the endurance is 0006's exact figure, so the supersede is a no-op unstudied. Studying is REFUSED at sea (`E_AT_SEA`) and at a port with no academy (`E_NO_ACADEMY`), and allowed at one that keeps one — taking endurance from 15.000 to 15.900 d at +6.00%. The ceiling BITES (`E_SKILL_MAXED`) after studying to it; `E_NO_SUCH_SKILL` and `E_NOT_ENOUGH_DUCATS` bite too. |

| **0017** | `a_quartermaster_stows_the_hold_and_a_purser_shaves_the_spread` | Two of 0015's three inert specialties, wired. `public.ship_hold_capacity()` — the ONE answer to "how many tuns fit in this hull", the rated `ship_classes.hold` stretched by the fleet's QUARTERMASTERS — replaces the same subtraction hand-copied into four server functions (`fleet_free_hold` 0007:127, `fleet_load` 0007:249, `do_provision` 0007:579/583/609/613, `world.fleets` 0009:183), all of which now compose onto it. `world.quote()` gains ONE appended parameter, `p_fleet`, and a PURSER shaves the spread the quote executes at — `world.spread(port)` stays the port's own one-argument fact, and the three callers that know a fleet pass it. `world.fleets()` serves the STOWED capacity under `hold` (with `hold_rated` and `officer_pct` alongside) so the client's mirrored arithmetic stays true. SURGEON is deliberately left inert. And every function this file re-cut is taken off the client. | With no officer aboard a 60-tun hull reads **60** and the fleet's free hold **matches 0007's own definition recomputed inline**, so the supersede is a no-op; a **+6.00%** quartermaster takes the hull to **63** tuns and the free hold rises by exactly 3 — then `fleet_load` places **every** tun `fleet_free_hold` offered and REFUSES one more, so the check and the placement cannot disagree and no one pays for cargo that never lands. Naming an unpursered fleet reproduces the 0005 quote **to the digit** (ask 4002.70, bid 3674.15); a **+6.00%** purser moves them to **3999.70 / 3677.06** — the stated amounts, recomputed from `world.mid_price`, `world.tax_rate` and `world.spread` — with the bid still under the ask. The world cap **BITES**, on a cap the probe lowers to 5 itself rather than trusting the seeded 25 that two officers can never reach. SURGEON still reports `takes_effect` false, `specialties_read` names exactly three, and 0016's HAGGLING skill is still unread. Seven anon-executable SECURITY DEFINER functions are closed and the **17 still open chain-wide are NOTICEd by name on every apply** — see below. |

---

## 2026-08-22 — 0017 found a grant hole that had been open since 0001

0017's posture assert (README §3: *"assert `REVOKE`d state explicitly; do not assume the default"*)
failed on its first apply, on a claim that should have been free:

```
0017 self-assert FAIL: authenticated may execute public.fleet_free_hold
```

Measured on PostgreSQL 18.3, chain applied through 0016 with `scripts/db/supabase-preamble.sql` in
place: **`pg_default_acl` holds three rows and every one of them is owned by `supabase_admin`.
There is no row for the role that applies this chain.** So 0001 §5a's

```sql
alter default privileges in schema public, world, cmd, voyage
  revoke execute on functions from public, anon, authenticated;
```

recorded nothing, and every function created since which did not carry its own explicit `revoke`
was left at PostgreSQL's built-in function default — **EXECUTE for PUBLIC**.

The tables half of the same statement is harmless by luck: the built-in default for a *table*
grants nobody anything, which is why `client_write_grants()` has honestly read zero all along. It
reads table grants and is blind to this by design. Functions were the exposed half, and **22
`SECURITY DEFINER` functions that WRITE were executable by `anon`** — among them
`public.fleet_load`, `public.fleet_unload`, `cmd.do_buy`, `cmd.do_sail`, `cmd.issue`,
`cmd.execute_order`, `voyage.depart` and `cmd.advance`. None of them checks who is asking, because
0007 and 0008 rely on `cmd.issue` doing that upstream — which is exactly the assumption a direct
call breaks.

**0017 closed the seven it re-cut** (`public.ship_hold_capacity`, `public.fleet_free_hold`,
`public.fleet_load`, `public.fleet_buy_capacity`, `cmd.do_buy`, `cmd.do_sell`, `cmd.do_provision`)
and re-granted the two the client really calls (`world.quote`, `world.fleets`) to `authenticated`.
It did **not** attempt the other 17: a blanket revoke written blind is how a deploy takes the game
offline, and re-granting the chain is its own concept. They are printed as a permanent `NOTICE`,
by name, on every apply — 0001 (d2)'s shape, never swallowed and never fatal, because an assert
that can never pass is pressure to delete the check.

**Still open, and wanting their own migration:** `cmd.advance`, `cmd.cancel_at`, `cmd.clear`,
`cmd.do_hire`, `cmd.do_repair`, `cmd.do_sail`, `cmd.execute_order`, `cmd.issue`, `cmd.preview`,
`public.fleet_unload`, `public.tg_reconcile_from_ledger`, `public.tg_reconcile_from_player`,
`voyage.assert_sailing_invariant`, `voyage.depart`, `voyage.recompute_eta`, `voyage.settle`,
`world.ledger`. (`cmd.issue`, `cmd.preview`, `cmd.cancel_at`, `cmd.clear` and `world.ledger` are
meant to be callable by `authenticated`; the migration that closes this must grant them back
explicitly rather than leaving them on a default. `proofs/03_grant_lockdown.sql` should grow a
ninth marker that fails on a `SECURITY DEFINER` writer reachable by `anon`, or this returns.)

---

## The five proofs

`scripts/db/proofs/` — run by `npm run db:proof`, each inside a transaction that is rolled back.
Green means **every `-- @pass` marker the file declares actually appeared**; a file that declares
none fails as vacuous.

| Proof | Declares | Establishes |
|---|---|---|
| `01_offline_equivalence.sql` | 5 markers | DESIGN Appendix 2 §1. The **same** voyage — pre-screened to contain a real hazard — is settled day by day, the result captured, the settlement rolled away, and then settled **once, nine hours late**. `(day_index, kind, payload, resolved_at)` match to the character; so do the purse and the ETA. |
| `02_ledger_reconciliation.sql` | 6 markers | DESIGN Appendix 2 §2. 500 randomised orders across 3 houses with time jumping forward underneath them. Requires both successes **and** refusals and money moving both ways, then `purse = Σ ledger.ducats_delta` exactly — and finally falsifies a purse by **one ducat** to prove the check bites. |
| `03_grant_lockdown.sql` | 8 markers | DESIGN Appendix 2 §3. Not a catalogue query: it **becomes** `anon` and then `authenticated` and tries to INSERT into all 18 tables, requiring SQLSTATE **42501** specifically — a writable table would have failed 23502 instead. Also: `world_config` unreadable, RLS on every table, `service_role` still able to write, and — at end of chain, where it matters most — **every object in all four schemas owned by the role that applied the chain**, which is what makes Supabase's un-revokable default privileges harmless (see the 2026-08-18 note). |
| `04_first_session.sql` | 9 markers | §K.1's ten minutes, replayed as **typed strings through `cmd.issue()`**. Two honest divergences from the script are asserted rather than papered over: `BUY sal 60` does not fit a 60-tun hold carrying stores, and a laden Barca is slower than the 4.7 minutes quoted for an empty one. The house comes home **richer on an 8,000 d. stake**, by a printed number. |
| `05_first_voyage_balance.sql` | 3 markers | **Balance, measured rather than argued.** The first version of this world paid 32% of the stake for one twenty-five-minute round trip. Across a sample of starting ports it now requires: every port offers a first voyage that pays; the **median return sits inside 4.0–16.0 per cent**; and **the long legs out-earn the short ones**, or there is no reason to leave home waters. The knobs behind it are swept by `scripts/db/tune-balance.mjs` — if this goes red, read that table rather than nudging a constant until the red goes away. |

## Two defects these proofs found

Recorded because a proof that has never caught anything is not yet known to work.

1. **`settle()` could dock a fleet with checkpoints unresolved.** A voyage's last day rarely divides
   evenly into 24 sim-hours, so the final boundary could fall after the ETA — and the *number* of
   checkpoints then depended on whether settle ran day by day or once at the end (10 against 12).
   Proof 1 caught it. Fixed by clamping `voyage.day_ends_at()` at the ETA (0006).
2. **`ALL`/`HALF` resolved at parse time** would have frozen a stale quantity into a queued order —
   `SELL cloves ALL`, typed in Lisboa, meant "the number aboard right now" rather than "whatever is
   aboard at Amsterdam". Fixed by `cmd.resolve_qty()` reading the hold at execution time (0007).

## 2026-08-18 — 0001 amended twice: an over-broad assert, and the honest form of it

CI's disposable-Supabase job failed applying 0001, on 0001's own assert:

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

Supabase ships `GRANT ALL ON TABLES/SEQUENCES/FUNCTIONS TO anon, authenticated, service_role` in
`public`, issued by its own bootstrap role `supabase_admin` — 16 entries once exploded (12 table,
2 sequence, 2 function, for `anon` and `authenticated`). `ALTER DEFAULT PRIVILEGES ... REVOKE`
without `FOR ROLE` only touches the **current** role's defaults, so 0001 could not see them.

**The first attempt was to revoke them under each grantor `pg_default_acl` names.** That is
impossible on the real thing, and CI said so in as many words (run `32122434872`):

```
ERROR: 0001: cannot clear the default privileges held by grantor supabase_admin in schema public
       (object type S). The role applying this migration is postgres, which is not a member of
       supabase_admin, so ALTER DEFAULT PRIVILEGES FOR ROLE is refused.
```

**So the assert itself was wrong — over-broad — and this is the argued case, not a quiet
softening.** The governing fact:

> **A `pg_default_acl` row applies ONLY to objects created by its own grantor.** It is not a
> schema-wide rule.

Measured on PostgreSQL 18.3, with all 16 entries in place and 0001 §5a applied:

| created by | resulting ACL |
|---|---|
| the migration role (`postgres`) | `relacl = null` — **no client privilege at all** |
| `supabase_admin` | `anon` and `authenticated` get INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, SELECT |

Same split for sequences and for functions. So `supabase_admin`'s defaults cannot reach a single
object this game owns, and the old assert demanded control over something the migration cannot
control **and** that does not threaten it — it would have blocked every deploy, forever. An assert
that can never pass is not strictness; it is pressure to delete the check.

**0001 now asserts what it can actually guarantee:**

| | |
|---|---|
| **(d)** | default ACLs **owned by the role applying the chain** grant no client a write or execute. Kept, and narrowed to this — these are the ones that govern every object the chain creates. |
| **(d2)** | default ACLs owned by **any other** grantor are printed as a permanent `NOTICE` on **every apply**, naming the grantor and the object types. Never swallowed, never fatal. |
| **(b)(c)** | no **current** table carries a client write, through `client_write_grants()` and independently through `information_schema`. Unchanged; proof 03 confirms it by actually being `anon`. |
| **(i)** | **NEW.** Every table, sequence, view and function in all four schemas is **owned by the role applying the chain** — so none of them can have inherited a foreign grantor's defaults. This is what converts (d2)'s un-revokable entries from an unprovable claim into an **irrelevant** one. |

(i) has a positive control that needs no privileges: the same authority,
`public.objects_not_owned_by()`, is asked about a role that owns nothing and must return rows,
which proves the scan reaches these schemas and that the owner comparison discriminates. Extension
members are excluded — their owner is the platform's choice, not ours — and the count skipped is
NOTICEd rather than hidden.

**§5b deliberately does not attempt the foreign revoke at all**, not even opportunistically. It
would succeed locally (the harness runs as a superuser) and fail on Supabase, putting the cheap gate
and CI back on different code paths — which is the original defect in this whole episode.

`objects_not_owned_by()` is also asserted at **end of chain** by proof 03's eighth marker,
`GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING`, which CI re-runs against the disposable Supabase; and the
workflow re-checks both claims from raw catalogue queries, independently of the chain's own
authorities.

**Nothing was deployed anywhere, so 0001 was amended in place; no 0011 patch.**

**And the local gate was made able to see any of this.** `npm run db:apply` boots a bare PGlite,
which has no client roles and no default ACLs at all — so this assert, and the whole grant family
with it, passed **vacuously**: nothing to find. `scripts/db/apply-chain.mjs` now applies
`scripts/db/supabase-preamble.sql` first (a **test fixture, never a migration**), installing those
roles and those 16 default privileges under a foreign grantor. With it in place the original 0001
failed locally with the identical 16-entry message CI reported, and the current 0001 prints the
same `NOTE` locally that it will print on Supabase.

---

## What is NOT proven here

* **Supabase's own roles.** The preamble is a fixture a human wrote from what CI reported; it can
  drift from the platform, and it models only roles and default ACLs — not that the migration role
  is a **non-superuser** there, which is precisely what made the first fix impossible. Only the
  disposable-Supabase job in `.github/workflows/migrations-apply-proof.yml` meets the real roles,
  and it now re-checks the default ACLs and the object ownership from outside the migration.
* **That the un-revokable platform defaults stay harmless.** They are harmless *because* nothing
  here is created by `supabase_admin`. If a future migration ever runs `set role`, or an extension
  is installed into one of these four schemas by another role, that stops being true — which is why
  assert (i) and proof 03's `GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING` run on every apply rather than
  being a one-time argument written in a comment.
* **pg_cron.** The tick functions are proven by being called, not by being scheduled. Nothing here
  shows a cron entry firing on a real Supabase project.
* **PostgREST exposure.** The RPCs live in the `world` / `cmd` / `voyage` schemas, as DESIGN
  Appendix 2 names them. Supabase's PostgREST exposes `public` by default: the project's API
  settings need `world, cmd, voyage` added to the exposed schemas before a browser can call them.
  That is configuration, not a second entry point, and it is deliberately not worked around with
  duplicate `public.` wrappers.
