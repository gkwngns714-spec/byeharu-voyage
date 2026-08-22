# Migration convention

This directory is **empty on purpose**. The schema starts here, and every rule below is carried
over from `byeharu` (the sibling project), where it was learned the expensive way. Sources are
cited so nothing on this page has to be taken on trust.

The database is the game. The client renders and requests; **every state change is an RPC**. A
migration is therefore not "a schema change" — it is how a rule enters the world.

---

## 1. Filename and numbering

    supabase/migrations/<version>_<snake_case_name>.sql

`<version>` is a **14-digit timestamp-shaped integer**, `YYYYMMDDHHMMSS`, and it is what Supabase
records in `supabase_migrations.schema_migrations`. Observed in byeharu (333 files):

    20260616000001_init_profiles.sql
    20260616000002_world_map.sql
    ...
    20260618000173_econ_seed_multiport_offers.sql
    20260618000351_the_fleet_fires_as_one.sql

Two things are true of that list and both are deliberate:

* **The version is a monotonic counter, not a real clock.** After the first day byeharu froze the
  date part (`20260618`) and simply incremented the tail: `…000173`, `…000174`, `…000351`. The last
  four digits are the migration's short number — "0173", "0351" — and that short number is how
  migrations are referred to everywhere: in headers, in commit messages, in the dev log.
* **The name is a sentence, in plain words.** `the_fleet_fires_as_one`, `one_way_to_die`,
  `a_fleet_comes_home_together`. It says what changed for the player, not which table was altered.
  `add_column_x` names the mechanism and hides the decision.

### Versions must be unique — this has bitten before

A duplicate version deploys as a **silent no-op**: `schema_migrations` keys on the version, so the
second file is recorded as already-applied and skipped, and everything stays green. byeharu hit
this four times and caught it by hand each time, then made it a required CI check
(`.github/workflows/build.yml`, step "Migration versions are unique"). The same guard runs in this
repo's `build.yml`.

### Never edit an applied migration

Once a migration has run anywhere it is history. A change goes in a **new** file that supersedes
the old one. (Related: this repo's `.gitattributes` forces LF on `*.sql`. CRLF baked into a
function body can never match what `pg_get_functiondef` returns, and a deploy that slices an
existing function will fail on a Windows checkout. Do not defeat that setting.)

---

## 2. Header comment format

Every migration opens with a block comment that a person can read six months later. The house
shape, from `byeharu/supabase/migrations/20260618000351_the_fleet_fires_as_one.sql`:

```sql
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0351 — THE FLEET FIRES AS ONE  (one point, one reach, one circle — and the circle IS the gate)
--        plus: the attack interval becomes 5 seconds, on both sides, as DATA
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ─────────────────────────────────────────────────────────────────────────
--   "the fleet range shape is like a cloud, make it circle."
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- The reach is drawn as the UNION OF PER-HULL DISCS (src/features/map/combatActors.ts:198 …)
--
-- ── SO THE RULE CHANGES, NOT THE PICTURE ────────────────────────────────────────────────────────
-- …
```

The parts that matter, in order:

1. **Short number + title** — the title is the rule in plain words.
2. **Why now** — the request or the defect, quoted verbatim where there is a quote.
3. **What currently says the opposite, named with `file:line` or a function name.** A migration
   that adds a rule without deleting the thing that contradicted it creates a second authority.
4. **What this migration does, and what it deliberately does not.** Dark/lit state of any flag;
   whether the change is additive.
5. **Evidence** — numbers that were actually measured, with where they were measured. Never a
   number recalled from memory. byeharu's 0351 header cites a read-only production measurement
   with the encounter id and the distances; that is the standard.

Another shape worth copying, from `20260618000173_econ_seed_multiport_offers.sql`, is the
dependency line: `-- Depends ONLY on: locations (0066 …), trade_goods (0073), market_offers (0085).`

---

## 3. The in-migration self-assert

**A migration proves itself, in the same transaction that applies it.** The final statement of a
migration is a `DO $$ … $$` block that re-reads what was just written and raises an exception if it
is not what the header promised. The migration then either lands correct or does not land at all.

Verbatim, from `byeharu/supabase/migrations/20260618000173_econ_seed_multiport_offers.sql:55-109`:

```sql
do $$
declare
  c_haven constant uuid := 'b1a00001-0066-4a00-8a00-000000000001';
  c_slag  constant uuid := 'b1a00002-0066-4a00-8a00-000000000002';
  c_drift constant uuid := 'b1a00003-0066-4a00-8a00-000000000003';
  v_goods constant text[] := array['textiles','ore','provisions','reagents','machinery','luxury_goods'];
  v_n int;
  v_profit numeric;
begin
  -- 1. Completeness: each of the three ports carries exactly one ACTIVE offer per seeded good (6 each).
  select count(*) into v_n from unnest(array[c_haven, c_slag, c_drift]) p
    where (select count(*) from public.market_offers o
             where o.location_id = p and o.good_id = any(v_goods) and o.active) <> 6;
  if v_n <> 0 then
    raise exception 'ECON-SEED-1 self-assert FAIL: % starter port(s) do not carry exactly 6 active offers', v_n;
  end if;

  -- 2. Anti-pump invariant on EVERY seeded row (belt-and-braces beside the table CHECK constraint).
  select count(*) into v_n from public.market_offers
    where location_id in (c_haven, c_slag, c_drift) and good_id = any(v_goods)
      and sell_price < buy_price;
  if v_n <> 0 then
    raise exception 'ECON-SEED-1 self-assert FAIL: % seeded row(s) violate sell_price >= buy_price', v_n;
  end if;

  -- 3. Three CONCRETE profitable routes, recomputed from the seeded rows (dest.buy > origin.sell):
  --    (a) ore:       buy at Slagworks sell 12 → sell at Haven buy 16      (+4/unit)
  select h.buy_price - s.sell_price into v_profit
    from public.market_offers s, public.market_offers h
    where s.location_id = c_slag  and s.good_id = 'ore'
      and h.location_id = c_haven and h.good_id = 'ore';
  if v_profit is null or v_profit <= 0 then
    raise exception 'ECON-SEED-1 self-assert FAIL: ore route Slagworks→Haven not profitable (profit=%)', v_profit;
  end if;

  raise notice 'ECON-SEED-1 self-assert ok: 3 ports x 6 active offers; anti-pump holds on all rows; 3 concrete profitable routes …';
end $$;
```

The rules that block reads out of it:

* **Message format:** `'<SLICE-ID> self-assert FAIL: <what is wrong>, %'` with the offending count
  or value interpolated. The `FAIL` token is greppable across the whole chain.
* **Assert the PROPERTY, not the statement you just ran.** Count rows back, recompute the profit,
  re-read the flag. `select 1` proves nothing.
* **Every assert must be able to fail.** An assert over an empty set passes vacuously and is worse
  than none, because it reports safety it never checked. byeharu shipped a vacuous assert and it
  cost a broken production deploy; if a check can only run against rows that may not exist, assert
  the row count first.
* **Close with a `raise notice … self-assert ok: …`** naming what was proven. That line is the
  human-readable receipt in the deploy log.
* **Assert the posture too**, not just the data: whether a flag is dark
  (`salvage_market_enabled is not false at seed time` → exception), and — learned from byeharu's
  prod grant drift — that client roles do **not** hold write grants they should never have. Assert
  `REVOKE`d state explicitly; do not assume the default.
* **Posture has two halves, and a migration must assert both.** `public.client_write_grants()`
  (0001) answers "does a client role hold a write on a TABLE?"; `public.client_executable_writers()`
  (0018) answers "may a client role EXECUTE a `SECURITY DEFINER` function that writes?". The second
  exists because the first read an honest zero for seventeen migrations while `anon` could call
  `public.fleet_unload` directly — a `SECURITY DEFINER` function runs as its definer and reaches no
  table ACL on the way. Both must read zero. A new RPC the client is meant to call needs a row in
  `public.client_rpc_entry_points()` (the server-side mirror of `src/lib/rpc/catalog.ts`) and an
  explicit `grant execute ... to authenticated`; since 0018 nothing is executable by default.
* **A catalogue row is not the property.** 0018's first draft proved its default-privilege fix by
  reading `pg_default_acl` back and finding the rows it expected — while functions created a line
  later were still executable by `anon`. Where a behavioural check is available, make it the
  governing assert and keep the catalogue read beside it as corroboration: create the object and ask
  `has_function_privilege`, `set local role` and try the call. See CHAIN.md, 2026-08-22.

---

## 4. Where SQL is actually proven

**There is no Docker on the dev machine.** SQL is therefore never proven locally. The only place
the chain runs against a real Postgres is CI:
`.github/workflows/migrations-apply-proof.yml` boots a disposable Supabase with
`supabase start`, which applies **every** migration in order and fails the job the moment any
self-assert raises. A green run there is the proof; anything else is a claim.
