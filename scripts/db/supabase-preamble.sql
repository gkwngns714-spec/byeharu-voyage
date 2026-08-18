-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- supabase-preamble.sql — a TEST FIXTURE. NOT A MIGRATION. NEVER DEPLOY THIS.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT IT IS ─────────────────────────────────────────────────────────────────────────────────
--   The hostile starting state a real Supabase project hands migration 0001, reproduced on a bare
--   PostgreSQL so that `npm run db:apply` starts where CI starts. It is applied by
--   scripts/db/apply-chain.mjs BEFORE the first migration file, and by nothing else. It lives in
--   scripts/, not in supabase/migrations/, precisely so that it can never be deployed: the CLI
--   only ever reads supabase/migrations/, and this file is not in it.
--
-- ── WHY IT HAD TO EXIST ────────────────────────────────────────────────────────────────────────
--   On 2026-08-18 `npm run db:apply` and `npm run db:proof` were green on this machine while CI's
--   disposable-Supabase job failed applying 0001:
--
--       ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
--              write/execute on future objects (SQLSTATE P0001)
--
--   The assert was right and the local gate was blind. A bare PGlite has no `anon`, no
--   `authenticated`, and — the part that mattered — no `ALTER DEFAULT PRIVILEGES` entries at all.
--   0001's lockdown therefore had NOTHING TO REVOKE locally, and its "no default ACL grants a
--   client a write" assert had NOTHING TO FIND. It passed vacuously. On Supabase it had 16 things
--   to find. Every grant / default-ACL assert in this chain was in that same position.
--
--   This file removes the vacuity: with it applied, the local run has exactly the same 16 entries
--   to fight.
--
-- ── HOW ITS CONTENTS WERE DERIVED (evidence, not memory) ───────────────────────────────────────
--   1. CI named the number: 16 assert-visible default-ACL entries survive 0001's own revoke.
--   2. The arithmetic was then reproduced on real PostgreSQL 18.3 (PGlite 0.5.5). Issuing the
--      three ALTER DEFAULT PRIVILEGES statements below UNDER A GRANTOR THAT IS NOT THE MIGRATION
--      ROLE stores exactly:
--
--        grantor        schema  objtype  defaclacl
--        supabase_admin public  r        {postgres=arwdDxtm/…,anon=arwdDxtm/…,authenticated=…,service_role=…}
--        supabase_admin public  S        {postgres=rwU/…,anon=rwU/…,authenticated=rwU/…,service_role=rwU/…}
--        supabase_admin public  f        {postgres=X/…,anon=X/…,authenticated=X/…,service_role=X/…}
--
--      which explodes, through 0001 assert (d)'s own predicate, to exactly 16 rows:
--        * tables    — anon + authenticated x {INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER} = 12
--        * sequences — anon + authenticated x {UPDATE}                                               =  2
--        * functions — anon + authenticated x {EXECUTE}                                              =  2
--      (SELECT, USAGE and MAINTAIN are not writes, so the assert does not count them; and
--      PostgreSQL does not store a PUBLIC=X entry for a function default ACL created this way,
--      which is why the total is 16 and not 17.)
--   3. The grantor MUST differ from the role applying the chain. That is the entire mechanism:
--      `ALTER DEFAULT PRIVILEGES ... REVOKE` without `FOR ROLE` only ever touches the CURRENT
--      role's own defaults, so a revoke written by the migration author cannot see, let alone
--      clear, the entries Supabase's own bootstrap role left behind. If these statements were
--      issued as `postgres` here, 0001's pre-existing revoke would clear them and this fixture
--      would prove nothing.
--
-- ── NON-VACUITY ────────────────────────────────────────────────────────────────────────────────
--   This file asserts its own effect at the bottom: if it does not leave exactly 16 assert-visible
--   default-ACL entries, it RAISES. A fixture that silently stopped modelling the hostile state
--   would put the local gate straight back where it was, and nobody would know.
--
-- ── WHAT IT STILL DOES NOT MODEL ───────────────────────────────────────────────────────────────
--   Supabase's `auth` schema and its real `auth.uid()` (0001 shims those); GoTrue, PostgREST,
--   Realtime and Storage; `pg_cron`; the hosted project's extensions; and the fact that on
--   Supabase the migration role is not a superuser. The disposable-Supabase job in
--   .github/workflows/migrations-apply-proof.yml remains the only place those are tested. This
--   fixture narrows the gap; it does not close it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. The roles Supabase ships ────────────────────────────────────────────────────────────────
-- The chain references exactly three (`anon`, `authenticated`, `service_role`); `supabase_admin`
-- is here because it is the GRANTOR of the default privileges, which is the whole point.
-- Created only if absent, so applying this fixture twice, or on top of anything, is safe.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'create role anon nologin noinherit';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'create role authenticated nologin noinherit';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'create role service_role nologin noinherit bypassrls';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    -- Supabase's bootstrap role. It must be able to own default privileges; nothing in the chain
    -- ever runs as it.
    execute 'create role supabase_admin nologin noinherit bypassrls createrole createdb';
  end if;
end $$;

-- Supabase grants the Data API roles USAGE on `public`. 0001 re-grants this itself, but a fixture
-- that started without it would let a later "did 0001 do this?" assert pass for the wrong reason.
grant usage on schema public to anon, authenticated, service_role;

-- ── 2. The default privileges a real Supabase project ships ────────────────────────────────────
-- Issued FOR ROLE supabase_admin — see the derivation note above; this is what makes the fixture
-- hostile rather than decorative.
alter default privileges for role supabase_admin in schema public
  grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public
  grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public
  grant all on functions to postgres, anon, authenticated, service_role;

-- ── 3. THE FIXTURE PROVES ITSELF ───────────────────────────────────────────────────────────────
do $$
declare
  v_n int;
  v_roles int;
begin
  select count(*) into v_roles from pg_roles
   where rolname in ('anon', 'authenticated', 'service_role', 'supabase_admin');
  if v_roles <> 4 then
    raise exception 'supabase-preamble FAIL: only % of the 4 Supabase roles exist', v_roles;
  end if;

  -- The same predicate migration 0001's assert (d) uses, verbatim.
  select count(*) into v_n
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
   cross join lateral aclexplode(d.defaclacl) a
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC')
     and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'EXECUTE');
  if v_n <> 16 then
    raise exception 'supabase-preamble FAIL: modelled % assert-visible default ACL entr(ies), expected the 16 CI reports. This fixture has stopped reproducing the real hostile state and the local gate is blind again.', v_n;
  end if;

  -- And the grantor is NOT the role that will apply the chain — otherwise 0001's existing
  -- grantor-blind revoke would clear it and the fixture would be a no-op in disguise.
  if exists (
    select 1 from pg_default_acl d
     join pg_namespace n on n.oid = d.defaclnamespace
    where n.nspname = 'public' and d.defaclrole = current_user::regrole::oid
  ) then
    raise exception 'supabase-preamble FAIL: the modelled default privileges are owned by %, the role that applies the chain. 0001 would clear them trivially and prove nothing.', current_user;
  end if;

  raise notice 'supabase-preamble ok: 4 Supabase roles present; 16 assert-visible default ACL entries installed under grantor supabase_admin (12 table + 2 sequence + 2 function), reproducing the CI starting state';
end $$;
