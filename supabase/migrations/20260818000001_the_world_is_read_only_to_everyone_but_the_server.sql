-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0001 — THE WORLD IS READ-ONLY TO EVERYONE BUT THE SERVER
--        Schemas, the compatibility shims, the knob table, and the grant lockdown — before there
--        is a single game table to leak.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THIS IS MIGRATION 0001 AND NOT 0050 ─────────────────────────────────────────────────────
--   The predecessor project (byeharu) shipped `danger_zones` and Supabase's own default
--   `GRANT ALL ON TABLES TO anon, authenticated` came along with it. Nobody wrote that grant; it
--   was inherited from the database's DEFAULT PRIVILEGES, which is exactly why nobody saw it. It
--   was found only when a much later migration finally asserted the posture — and that migration
--   ABORTED ON ITS OWN SELF-ASSERT in production. See docs/CORE_REUSE.md and the memory note
--   "Prod grant drift: revoke, don't assert".
--
--   The lesson is not "assert grants". It is "REVOKE FIRST, then assert, and do it before the
--   first table exists, so that nothing can ever inherit the default". That is this file.
--
-- ── WHAT THIS MIGRATION ESTABLISHES ─────────────────────────────────────────────────────────────
--   1. The four schemas the design names: public (tables), world / cmd / voyage (the RPC surface,
--      docs/DESIGN.md Appendix 2).
--   2. Gap-filling shims — and ONLY gap-filling. `anon`, `authenticated`, `service_role` and
--      `auth.uid()` exist in Supabase and do NOT exist in a bare PostgreSQL. Each is created here
--      only if absent, so this file is a no-op on Supabase and makes the chain runnable under
--      PGlite locally (DEV_LOG D6). It never overwrites Supabase's own definitions.
--   3. `public.world_config` — the one knob table (DESIGN §L.1: TIME_COMPRESSION must be retunable
--      without a migration). Every knob carries a `description`, so a dead-knob audit can tell the
--      truth. It is SERVER-ONLY: it holds `world_secret`, which seeds the hazard RNG (§B.6), and a
--      client that could read it could predict every storm on every voyage.
--   4. `public.wc_num/wc_int/wc_text` — the ONE knob reader. Fail-closed: a missing key RAISES.
--      No caller may read world_config directly; a second reader is a second authority.
--   5. THE LOCKDOWN: every write privilege revoked from the client roles, on tables AND functions,
--      in all four schemas, plus the DEFAULT PRIVILEGES retuned so nothing created later inherits
--      one — for THIS role (5a) and, driven by pg_default_acl itself, for EVERY OTHER GRANTOR the
--      platform preconfigured (5b). Later migrations grant SELECT explicitly, table by table.
--   6. `public.client_write_grants()` — the ONE authority for "does a client role hold a write?".
--      Migrations 0002-0010 each call it; so does scripts/db/proofs/03_grant_lockdown.sql.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * `client_write_grants()` returns zero rows — AND a deliberately granted probe table proves
--      the query can actually find one (a zero-count assert with no positive control is a check
--      that has never been shown capable of failing).
--   * The same zero, independently, through `information_schema.role_table_grants`.
--   * No DEFAULT ACL in any of the four schemas grants a client role a write.
--   * `anon` and `authenticated` hold NOTHING AT ALL on `world_config`, not even SELECT.
--   * Every seeded knob is readable through the reader, has a non-empty description, and a
--      deliberately absent key RAISES rather than returning null.
--
-- Depends on: nothing. This is the first file in the chain.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. Schemas ─────────────────────────────────────────────────────────────────────────────────
create schema if not exists world;
create schema if not exists cmd;
create schema if not exists voyage;

comment on schema world  is 'Read RPCs: world.snapshot(), world.market(), world.fleets(), world.ledger().';
comment on schema cmd    is 'The ONE mutating entry point: cmd.issue() and its dry-run/cancel siblings.';
comment on schema voyage is 'Closed-form movement, deterministic hazard, and voyage.settle().';

-- ── 2. Gap-filling shims (no-ops on Supabase) ──────────────────────────────────────────────────
-- Supabase creates these roles and this function. A bare PostgreSQL does not. Creating them ONLY
-- when absent is what lets the identical SQL be proven locally under PGlite and then deployed to
-- Supabase without a second, divergent copy of the chain.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'create role anon nologin noinherit';
    raise notice '0001 shim: created role anon (absent — this is not Supabase)';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'create role authenticated nologin noinherit';
    raise notice '0001 shim: created role authenticated';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'create role service_role nologin noinherit bypassrls';
    raise notice '0001 shim: created role service_role';
  end if;
end $$;

do $$
begin
  if to_regprocedure('auth.uid()') is null then
    execute 'create schema if not exists auth';
    execute $f$
      create function auth.uid() returns uuid
      language sql stable
      as $inner$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $inner$
    $f$;
    raise notice '0001 shim: created auth.uid() (absent — this is not Supabase)';
  end if;
end $$;

-- Extensions. gen_random_uuid() is core in PostgreSQL 13+, so the chain does not depend on
-- pgcrypto; the attempt is made because Supabase has it and other extensions may want it, and it
-- is allowed to fail on a build that does not ship it. What is NOT allowed to fail is the
-- CAPABILITY, which is asserted below.
do $$
begin
  begin
    execute 'create extension if not exists pgcrypto';
  exception when others then
    raise notice '0001: pgcrypto unavailable (%) — falling back to core gen_random_uuid()', sqlerrm;
  end;
end $$;

-- ── 3. The knob table ──────────────────────────────────────────────────────────────────────────
create table if not exists public.world_config (
  key         text        primary key,
  value       jsonb       not null,
  description text        not null check (length(btrim(description)) > 0),
  updated_at  timestamptz not null default now()
);

comment on table public.world_config is
  'The one knob table. SERVER-ONLY: holds world_secret, which seeds the hazard RNG (DESIGN B.6). '
  'No client role may read it. Public knobs reach the client through world.snapshot().';

alter table public.world_config enable row level security;
-- Deliberately NO policy: RLS with no policy denies every row to every non-bypassing role. The
-- absence of a policy here is the security decision, stated out loud so nobody "fixes" it.

insert into public.world_config (key, value, description) values
  ('time_compression',        to_jsonb(480),      'DESIGN D.1. 1 real minute = 8 voyage-hours; 1 voyage-day = 3 real minutes.'),
  ('world_secret',            to_jsonb('voyage-v0-seed-6f2a91c4'::text), 'SECRET. Seeds voyage.rng() with (voyage_id, day_index). Never leaves the server.'),
  ('starting_ducats',         to_jsonb(8000),     'DESIGN K.1 first session: a new house opens with 8,000 ducats.'),
  ('price_elasticity',        to_jsonb(0.5),      'DESIGN G.1 exponent on (stock_target/stock).'),
  ('price_band_lo',           to_jsonb(0.35),     'DESIGN G.1/G.7.3 hard clamp floor, as a multiple of base_value.'),
  ('price_band_hi',           to_jsonb(3.50),     'DESIGN G.1/G.7.3 hard clamp ceiling, as a multiple of base_value.'),
  ('spread_base',             to_jsonb(0.06),     'DESIGN G.1 spread = spread_base - spread_per_dev * dev_commerce.'),
  ('spread_per_dev',          to_jsonb(0.002),    'DESIGN G.1 spread reduction per point of dev_commerce.'),
  ('spread_floor',            to_jsonb(0.02),     'DESIGN G.1 spread never falls below this.'),
  ('mid_dev_discount',        to_jsonb(0.004),    'DESIGN G.1: developed ports trade cheaper, mid x (1 - 0.004*dev_commerce).'),
  ('tax_rate_default',        to_jsonb(0.03),     'DESIGN E.4: the market tax a player pays where no Mayor has set one.'),
  ('trade_step_tuns',         to_jsonb(10),       'DESIGN G.2: orders execute in 10-tun steps, each repricing.'),
  ('daily_cap_fraction',      to_jsonb(0.35),     'DESIGN G.7.1: per (player,port,good) daily volume cap = fraction x stock_target.'),
  ('stock_regen_fraction',    to_jsonb(0.15),     'DESIGN G.2: stock += (target - stock) * 0.15 per game-day.'),
  ('drift_theta',             to_jsonb(0.90),     'DESIGN G.1 Ornstein-Uhlenbeck decay: drift <- theta*drift + N(0,sigma).'),
  ('drift_sigma',             to_jsonb(0.04),     'DESIGN G.1 OU step standard deviation.'),
  ('drift_clamp',             to_jsonb(0.25),     'DESIGN G.1: drift is clamped to +/- this.'),
  ('endurance_margin',        to_jsonb(1.15),     'DESIGN C.5: SAIL refuses unless endurance_days >= leg_days * 1.15.'),
  ('order_queue_max',         to_jsonb(12),       'DESIGN F.3: maximum orders in one fleet queue.'),
  ('fleet_max',               to_jsonb(2),        'DESIGN K.1: V0 allows 2 fleets.'),
  ('ship_max',                to_jsonb(4),        'DESIGN K.1: V0 allows 4 ships in total.'),
  ('fleet_ship_max',          to_jsonb(8),        'DESIGN C.4: a fleet is 1-8 ships with exactly one flagship.'),
  ('port_fee_per_ship',       to_jsonb(50),       'DESIGN F.2 DOCK: port fee is 50 ducats per ship.'),
  ('water_per_crew_day',      to_jsonb(0.020),    'DESIGN C.5: tuns of water per crew per voyage-day.'),
  ('food_per_crew_day',       to_jsonb(0.015),    'DESIGN C.5: tuns of food per crew per voyage-day.'),
  ('wage_per_crew_day',       to_jsonb(1),        'DESIGN C.5: ducats of wages per crew per voyage-day.'),
  ('short_rations_wage_mult', to_jsonb(1.5),      'DESIGN B.6 SHORT_RATIONS: wages x1.5 to hold the crew.'),
  ('hazard_p_max',            to_jsonb(0.060),    'DESIGN B.6: per-voyage-day hazard probability is clamped to this ceiling.'),
  ('crew_short_speed_mult',   to_jsonb(0.70),     'DESIGN B.3 M_crew when crew < crew_required.'),
  ('load_speed_penalty',      to_jsonb(0.25),     'DESIGN B.3 M_load = 1 - 0.25 * cargo_fill_fraction.'),
  ('hull_speed_floor',        to_jsonb(0.60),     'DESIGN B.3 M_hull = 0.60 + 0.40 * (durability/max_durability).'),
  ('store_ratio_default',     to_jsonb(0.45),     'DESIGN F.2 PROVISION FULL: fills stores to 45% of hold by default.'),
  ('wind_mult_v0',            to_jsonb(1.00),     'DESIGN K.1: wind is NOT in V0. M_wind is pinned at 1.00 until V1.'),
  ('hire_crew_rate',          to_jsonb(20),       'Ducats per head to hire crew at a port (DESIGN F.2 HIRE; V0 flat rate).'),
  ('repair_rate_per_point',   to_jsonb(2),        'Ducats per durability point restored (DESIGN F.2 REPAIR; V0 flat rate).')
on conflict (key) do nothing;

-- ── 4. The ONE knob reader ─────────────────────────────────────────────────────────────────────
create or replace function public.wc(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v jsonb;
begin
  select value into v from public.world_config where key = p_key;
  if v is null then
    -- Fail CLOSED and LOUD. A knob reader that returns null on a typo mints a silent default,
    -- which is how the predecessor grew an orphan knob no production function ever read.
    raise exception 'world_config key % does not exist', p_key using errcode = '22023';
  end if;
  return v;
end $$;

create or replace function public.wc_num(p_key text) returns numeric
language sql stable security definer set search_path = public, pg_temp
as $$ select (public.wc(p_key))::text::numeric $$;

create or replace function public.wc_int(p_key text) returns integer
language sql stable security definer set search_path = public, pg_temp
as $$ select (public.wc(p_key))::text::numeric::integer $$;

create or replace function public.wc_text(p_key text) returns text
language sql stable security definer set search_path = public, pg_temp
as $$ select (public.wc(p_key)) #>> '{}' $$;

comment on function public.wc(text) is
  'THE ONE reader for world_config. Every knob read in the chain goes through here or its typed '
  'siblings. Raises on an unknown key: a knob reader must never invent a default.';

-- ── 5. THE LOCKDOWN ────────────────────────────────────────────────────────────────────────────
-- Order matters: revoke what already exists, then retune the DEFAULT so nothing created later
-- inherits a write. Both halves are needed. Supabase's stock default privileges are exactly the
-- "GRANT ALL ON TABLES TO anon, authenticated" that produced the predecessor's aborted deploy.

grant usage on schema public  to anon, authenticated, service_role;
grant usage on schema world   to authenticated, service_role;
grant usage on schema cmd     to authenticated, service_role;
grant usage on schema voyage  to service_role;

revoke all on all tables    in schema public, world, cmd, voyage from anon, authenticated;
revoke all on all sequences in schema public, world, cmd, voyage from anon, authenticated;
revoke all on all functions in schema public, world, cmd, voyage from public, anon, authenticated;

-- 5a. The CURRENT role's own defaults. Everything this chain creates is created by this role, so
--     this is the half that governs our own future objects.
alter default privileges in schema public, world, cmd, voyage
  revoke all on tables from anon, authenticated;
alter default privileges in schema public, world, cmd, voyage
  revoke all on sequences from anon, authenticated;
-- Functions default to EXECUTE for PUBLIC. Every RPC in this chain is SECURITY DEFINER, so an
-- inherited PUBLIC execute would hand anon the server's own privileges. Revoked here; each RPC
-- grants EXECUTE explicitly to the role that may call it.
alter default privileges in schema public, world, cmd, voyage
  revoke execute on functions from public, anon, authenticated;

-- 5b. EVERY OTHER GRANTOR'S defaults. This is the half that was missing, and the reason CI's
--     disposable-Supabase job failed this file's own assert (d) with 16 surviving entries while a
--     bare PGlite reported none.
--
--     `ALTER DEFAULT PRIVILEGES ... REVOKE` without `FOR ROLE` only ever touches the CURRENT
--     role's defaults. Supabase's `GRANT ALL ON TABLES/SEQUENCES/FUNCTIONS TO anon, authenticated,
--     service_role` in `public` is issued by its OWN bootstrap role, not by the role that applies
--     migrations — so 5a cannot see it, let alone clear it. Written out by hand it would also be a
--     guess about which roles a given Supabase version uses. It is not a guess here: pg_default_acl
--     names every grantor, and the loop revokes under each one it names.
--
--     The filter is deliberately the SAME predicate assert (d) below uses, so the sweep and the law
--     cannot drift apart. Object types carrying only USAGE (domains, types) never match it and are
--     left alone — revoking USAGE on types from PUBLIC would break composite RPC return values and
--     is not what "no client may WRITE" means.
do $$
declare
  r           record;
  v_stmts     int  := 0;
  v_grantors  text[] := '{}';
begin
  for r in
    select distinct
           d.defaclrole::regrole::text as grantor,
           n.nspname                   as schema_name,
           d.defaclobjtype             as objtype
      from pg_default_acl d
      join pg_namespace n on n.oid = d.defaclnamespace
     cross join lateral aclexplode(d.defaclacl) a
     where n.nspname in ('public', 'world', 'cmd', 'voyage')
       and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
           in ('anon', 'authenticated', 'PUBLIC')
       and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'EXECUTE')
     order by 1, 2, 3
  loop
    begin
      if r.objtype = 'r' then
        execute format(
          'alter default privileges for role %s in schema %I revoke all on tables from anon, authenticated',
          r.grantor, r.schema_name);
      elsif r.objtype = 'S' then
        execute format(
          'alter default privileges for role %s in schema %I revoke all on sequences from anon, authenticated',
          r.grantor, r.schema_name);
      elsif r.objtype = 'f' then
        execute format(
          'alter default privileges for role %s in schema %I revoke all on functions from public, anon, authenticated',
          r.grantor, r.schema_name);
      else
        -- A default ACL object type that can carry a write and that this file does not know how to
        -- revoke must stop the deploy, not be skipped quietly.
        raise exception '0001: pg_default_acl names object type % (grantor %, schema %) carrying a client write, and this migration has no revoke for it',
          r.objtype, r.grantor, r.schema_name;
      end if;
      v_stmts := v_stmts + 1;
      if not (r.grantor = any (v_grantors)) then
        v_grantors := v_grantors || r.grantor;
      end if;
    exception when insufficient_privilege then
      raise exception '0001: cannot clear the default privileges held by grantor % in schema % (object type %). The role applying this migration is %, which is not a member of %, so ALTER DEFAULT PRIVILEGES FOR ROLE is refused. Grant that membership (or have % issue the revoke) — do NOT relax the assert below; those defaults really would hand a client role a write on every object % creates here.',
        r.grantor, r.schema_name, r.objtype, current_user, r.grantor, r.grantor, r.grantor;
    end;
  end loop;

  if v_stmts = 0 then
    raise notice '0001: no foreign-grantor default ACL to clear in public/world/cmd/voyage (expected on a bare PostgreSQL; on Supabase this would mean the platform stopped shipping them)';
  else
    raise notice '0001: cleared foreign-grantor default privileges with % ALTER DEFAULT PRIVILEGES statement(s) under grantor(s): %',
      v_stmts, array_to_string(v_grantors, ', ');
  end if;
end $$;

revoke all on public.world_config from anon, authenticated;

-- The knob reader is security definer over a server-only table; only the server may call it.
revoke all on function public.wc(text)      from public, anon, authenticated;
revoke all on function public.wc_num(text)  from public, anon, authenticated;
revoke all on function public.wc_int(text)  from public, anon, authenticated;
revoke all on function public.wc_text(text) from public, anon, authenticated;

-- ── 6. THE ONE AUTHORITY for "does a client role hold a write?" ────────────────────────────────
create or replace function public.client_write_grants()
returns table (schema_name text, table_name text, grantee text, privilege text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Read the ACL off pg_class rather than information_schema, deliberately:
  -- information_schema.role_table_grants only shows rows whose grantor OR grantee is a currently
  -- enabled role, so a grant made by a role we are not a member of is INVISIBLE there. That is
  -- precisely the shape of the drift this function exists to catch. aclexplode has no such
  -- blind spot. `grantee = 0` is PUBLIC, which reaches anon, so it counts.
  select n.nspname::text,
         c.relname::text,
         (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)::text,
         a.privilege_type::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC')
     and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
$$;

comment on function public.client_write_grants() is
  'THE ONE authority for the grant lockdown. Every migration in this chain calls it in its own '
  'self-assert, and scripts/db/proofs/03_grant_lockdown.sql calls it too. Zero rows is the law.';

revoke all on function public.client_write_grants() from public, anon, authenticated;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_n            int;
  v_probe_found  int;
  v_info         int;
  v_defacl       int;
  v_wc           int;
  v_knobs        int;
  v_missing_desc int;
  v_raised       boolean := false;
begin
  -- (a) POSITIVE CONTROL FIRST. Grant a client role a write on a throwaway table and prove the
  --     authority SEES it. Without this, step (b)'s zero could mean "nothing is wrong" or
  --     "the query is broken" and there would be no way to tell them apart.
  create table public._grant_lockdown_probe (x int);
  grant insert, update on public._grant_lockdown_probe to anon;

  select count(*) into v_probe_found
    from public.client_write_grants()
   where table_name = '_grant_lockdown_probe';
  if v_probe_found <> 2 then
    raise exception '0001 self-assert FAIL: positive control found % write grant(s) on the probe, expected 2 (INSERT+UPDATE). client_write_grants() is not working, so its zero proves nothing.', v_probe_found;
  end if;

  -- The information_schema route must see it too, since we are the grantor.
  select count(*) into v_info
    from information_schema.role_table_grants g
   where g.table_name = '_grant_lockdown_probe'
     and g.grantee in ('anon', 'authenticated')
     and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_info <> 2 then
    raise exception '0001 self-assert FAIL: information_schema positive control saw % grant(s), expected 2', v_info;
  end if;

  revoke all on public._grant_lockdown_probe from anon;
  drop table public._grant_lockdown_probe;

  -- (b) THE LAW: no client role holds a write anywhere in the four schemas.
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception '0001 self-assert FAIL: % client write grant(s) survive the lockdown: %',
      v_n, (select string_agg(schema_name || '.' || table_name || ' ' || grantee || ':' || privilege, ', ')
              from public.client_write_grants());
  end if;

  -- (c) The same zero through information_schema.role_table_grants, independently.
  select count(*) into v_info
    from information_schema.role_table_grants g
   where g.grantee in ('anon', 'authenticated')
     and g.table_schema in ('public', 'world', 'cmd', 'voyage')
     and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER');
  if v_info <> 0 then
    raise exception '0001 self-assert FAIL: information_schema still reports % client write grant(s)', v_info;
  end if;

  -- (d) No DEFAULT ACL hands a future table a write. This is the half that the predecessor missed:
  --     the tables were clean and the DEFAULT was not, so the NEXT table was born wrong.
  select count(*) into v_defacl
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
   cross join lateral aclexplode(d.defaclacl) a
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC')
     and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'EXECUTE');
  if v_defacl <> 0 then
    -- Name them. "16 entries" cost a CI round trip to diagnose because the message did not say
    -- WHOSE defaults they were, and the grantor is the entire answer (see 5b).
    raise exception '0001 self-assert FAIL: % default ACL entr(ies) would grant a client role a write/execute on future objects: %',
      v_defacl,
      (select string_agg(x.grantor || ' -> ' || x.schema_name || ' ' || x.objtype || ' ' || x.grantee || ':' || x.privilege_type, ', ' order by x.grantor, x.schema_name, x.objtype, x.grantee, x.privilege_type)
         from (select d.defaclrole::regrole::text as grantor,
                      n.nspname                  as schema_name,
                      -- ::text is load-bearing: defaclobjtype is "char", and `text || "char"` is
                      -- an ambiguous operator, so without it this message raises 42725 instead of
                      -- itself. Proven by running the assert with the §5b sweep removed.
                      d.defaclobjtype::text      as objtype,
                      (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end) as grantee,
                      a.privilege_type
                 from pg_default_acl d
                 join pg_namespace n on n.oid = d.defaclnamespace
                cross join lateral aclexplode(d.defaclacl) a
                where n.nspname in ('public', 'world', 'cmd', 'voyage')
                  and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
                      in ('anon', 'authenticated', 'PUBLIC')
                  and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'EXECUTE')) x);
  end if;

  -- (e) world_config is server-only: the clients hold NOTHING on it, not even SELECT.
  select count(*) into v_wc
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where n.nspname = 'public' and c.relname = 'world_config'
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC');
  if v_wc <> 0 then
    raise exception '0001 self-assert FAIL: a client role holds % privilege(s) on world_config; it seeds the hazard RNG and must stay unreadable', v_wc;
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.world_config'::regclass) then
    raise exception '0001 self-assert FAIL: RLS is not enabled on world_config';
  end if;

  -- (f) The knobs are all present, described, and reachable through the ONE reader.
  select count(*) into v_knobs from public.world_config;
  if v_knobs < 35 then
    raise exception '0001 self-assert FAIL: only % knob(s) seeded, expected at least 35', v_knobs;
  end if;
  select count(*) into v_missing_desc
    from public.world_config where description is null or btrim(description) = '';
  if v_missing_desc <> 0 then
    raise exception '0001 self-assert FAIL: % knob(s) carry no description; a dead-knob audit could not tell the truth', v_missing_desc;
  end if;
  if public.wc_int('time_compression') <> 480 then
    raise exception '0001 self-assert FAIL: wc_int(time_compression) = %, expected 480',
      public.wc_int('time_compression');
  end if;
  if public.wc_num('price_elasticity') <> 0.5 then
    raise exception '0001 self-assert FAIL: wc_num(price_elasticity) = %, expected 0.5',
      public.wc_num('price_elasticity');
  end if;
  if length(public.wc_text('world_secret')) < 8 then
    raise exception '0001 self-assert FAIL: world_secret is too short to seed anything';
  end if;

  -- (g) The reader FAILS CLOSED on an unknown key. Asserting the happy path only would leave the
  --     silent-default behaviour unproven, which is the failure mode that actually costs money.
  begin
    perform public.wc('a_knob_that_does_not_exist');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '0001 self-assert FAIL: wc() returned quietly for an unknown key instead of raising';
  end if;

  -- (h) gen_random_uuid() is available, from core or from pgcrypto — the chain needs it for keys.
  if gen_random_uuid() is null then
    raise exception '0001 self-assert FAIL: gen_random_uuid() is unavailable';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception '0001 self-assert FAIL: auth.uid() does not resolve';
  end if;

  raise notice '0001 self-assert ok: lockdown holds (0 client write grants, probe proved the query fires on 2), 0 default-ACL leaks, world_config server-only with RLS on and % knobs all described, wc() raises on an unknown key, gen_random_uuid + auth.uid resolve', v_knobs;
end $$;
