-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0018 — ONLY A SIGNED-IN CAPTAIN MAY MOVE ANYTHING
--        The grant hole 0017 found and could not close: every SECURITY DEFINER function in the
--        four schemas is taken off the client by a loop over the CATALOGUE, the eighteen the
--        browser really calls are granted back BY NAME, and the ALTER DEFAULT PRIVILEGES that
--        recorded nothing in 0001 is re-issued in a form that provably records something.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ──────────────────────────────────────────────────────────────
--
-- 1. `0001:240-241` —
--        alter default privileges in schema public, world, cmd, voyage
--          revoke execute on functions from public, anon, authenticated;
--    It ran without error and RECORDED NOTHING. Measured on PostgreSQL 18.3 (PGlite 0.5.5) with
--    the chain applied through 0017 and `scripts/db/supabase-preamble.sql` in place:
--    `pg_default_acl` holds THREE rows, all owned by grantor `supabase_admin`, and NONE owned by
--    the role that applies this chain. So every function created since 0001 that did not carry its
--    own explicit `revoke` was born at PostgreSQL's built-in function default, which is
--    **EXECUTE FOR PUBLIC**, and PUBLIC reaches `anon`.
--
-- 2. `public.client_write_grants()` (0001:291) has honestly read zero throughout. It reads TABLE
--    grants off `pg_class.relacl` and is STRUCTURALLY BLIND to a function ACL. Its zero was never
--    wrong; it was answering a different question. That is why this file mints a second authority
--    rather than "fixing" the first.
--
-- 3. `0017:1122-1135` prints the residue as a NOTICE on every apply. Measured on this machine
--    today, before this file: **17 SECURITY DEFINER functions that WRITE are executable by anon** —
--        cmd.advance, cmd.cancel_at, cmd.clear, cmd.do_hire, cmd.do_repair, cmd.do_sail,
--        cmd.execute_order, cmd.issue, cmd.preview, public.fleet_unload,
--        public.tg_reconcile_from_ledger, public.tg_reconcile_from_player,
--        voyage.assert_sailing_invariant, voyage.depart, voyage.recompute_eta, voyage.settle,
--        world.ledger
--    Because they are SECURITY DEFINER, an anonymous caller reaching one runs as the DEFINER and
--    bypasses RLS entirely. `cmd.execute_order`, `voyage.depart`, `public.fleet_unload` and
--    `cmd.do_sail` take a fleet id and none of them checks who is asking: 0007 and 0008 rely on
--    `cmd.issue` having checked upstream, which is exactly the assumption a direct call breaks.
--    The wider count, same measurement: of 92 SECURITY DEFINER functions in these four schemas,
--    `anon` could execute 55 and `authenticated` 65.
--
--    HOW BAD IT ACTUALLY WAS, MEASURED RATHER THAN ASSUMED — the chain applied through 0017, then
--    `set local role anon` and the call made:
--
--      select public.fleet_unload(null, null, null)   ->  ANSWERED. No error. It writes cargo.
--      select cmd.do_sail(null, null)                 ->  42501 permission denied for SCHEMA cmd
--      select cmd.issue(null, null, null)             ->  42501 permission denied for SCHEMA cmd
--      select world.ledger(null, null)                ->  42501 permission denied for SCHEMA world
--      select voyage.depart(null, null, null)         ->  42501 permission denied for SCHEMA voyage
--
--    `anon` holds USAGE on `public` and on nothing else (0001:222-225), so for three of the four
--    schemas a second door happened to be shut. It was not shut by the lock that was supposed to be
--    doing the job, and it is not shut on `public` — which is the schema PostgREST exposes by
--    default and where `public.fleet_unload`, a SECURITY DEFINER function that WRITES ship cargo,
--    was genuinely reachable by an anonymous caller. Overstating this would be as wrong as
--    understating it: the hole was live in `public` and one revoked schema grant away everywhere
--    else.
--
-- 4. `0017:418-419` granted `world.quote(...)` to `authenticated` — while 0017's OWN header
--    (`:90-91`) records that "the client never calls quote (it is absent from
--    src/lib/rpc/catalog.ts; the composer asks world.buy_capacity instead)". The grant and the
--    header disagreed. The header is right, so the grant goes: `world.quote` is reached only from
--    `public.fleet_buy_capacity`, `cmd.do_buy` and `cmd.do_sell`, all of which run as the definer.
--
-- ── THE CATALOGUE IS THE AUTHORITY FOR THE REVOKE ──────────────────────────────────────────────
-- The revoke is a LOOP over `pg_proc join pg_namespace where prosecdef`, not a hand-typed list of
-- the seventeen names above. A hand-typed list is a second authority: it is correct on the day it
-- is written and stale the day someone adds a function, and nothing would say so. The catalogue
-- cannot go stale, because it IS what a new function lands in.
--
-- ── AND THE GRANT BACK IS BY NAME, FROM ONE LIST ───────────────────────────────────────────────
-- `public.client_rpc_entry_points()` is minted here as the server's statement of what a browser may
-- call — the mirror of `src/lib/rpc/catalog.ts`, which is the only place the client names a
-- function. It carries EIGHTEEN rows, read out of that file (catalog.ts:37-138), every one of them
-- either taking no id at all or reading `auth.uid()` itself:
--
--   world.snapshot()                   catalog.ts:38    cmd.issue(uuid,text,int)        :57
--   world.market(uuid)                 catalog.ts:39    cmd.preview(uuid,text)          :66
--   world.fleets()                     catalog.ts:40    cmd.cancel_at(uuid,int)         :74
--   world.ledger(timestamptz,int)      catalog.ts:41    cmd.clear(uuid,boolean)         :82
--   world.buy_capacity(uuid,uuid)      catalog.ts:49    cmd.verb_schema()               :90
--   world.price_history(uuid,int)      catalog.ts:92    cmd.hire_officer(text,uuid)     :104
--   world.player()                     catalog.ts:101   cmd.post_officer(text,uuid)     :112
--   world.officers()                   catalog.ts:102   cmd.study_skill(text,uuid)      :120
--   world.skills()                     catalog.ts:103   cmd.found_house(text,text)      :130
--
-- `world.ledger` is in the revoke list above AND is a client read; it comes back here. So does
-- `cmd.issue` — THE only mutating entry point in the game (0008). Lose that grant and no order can
-- ever be given again, which is why the list is read out of catalog.ts rather than reasoned about,
-- why `04_first_session` replays a real session through it, and why the self-assert below names
-- every one of the eighteen individually instead of counting to eighteen.
--
-- They are granted to `authenticated` ONLY. `anon` gets nothing: the app mounts every RPC behind
-- `RequireAuth` (src/app/App.tsx:19 — "/auth is the only route outside it"), so no unauthenticated
-- call exists to break. That tightens `world.snapshot`, `world.market`, `world.ledger`,
-- `world.buy_capacity`, `cmd.verb_schema`, `cmd.preview`, `cmd.cancel_at`, `cmd.clear` and
-- `cmd.issue`, all of which anon could reach before this file.
--
-- ── THE ROOT CAUSE: IT IS THE `IN SCHEMA` CLAUSE ───────────────────────────────────────────────
-- Re-issuing 0001's statement verbatim would repeat 0001's mistake, so the fix was MEASURED before
-- it was written. Four variants, each on a fresh PostgreSQL 18.3 (PGlite 0.5.5) holding the client
-- roles and the four schemas, each followed by `create function` in public, world and voyage:
--
--   statement issued as the migration role         pg_default_acl        the function it then bore
--   ─────────────────────────────────────────────  ────────────────────  ─────────────────────────
--   0001:240 verbatim —                            0 rows                proacl null; anon,
--     ... IN SCHEMA public, world, cmd, voyage                           authenticated and
--     revoke execute on functions                                        service_role ALL MAY
--     from public, anon, authenticated                                   EXECUTE
--
--   the same, preceded by a per-schema             4 rows,               proacl null; anon,
--     `grant execute on functions to postgres`     {postgres=X/postgres} authenticated and
--     (so that a row certainly exists)             one per schema        service_role ALL MAY
--                                                                        EXECUTE
--
--   the same statement WITHOUT `IN SCHEMA`         1 row, defacl-        proacl
--     alter default privileges revoke execute      namespace 0           {postgres=X/postgres};
--     on functions from public, anon,              (global),             anon, authenticated and
--     authenticated                                {postgres=X/postgres} service_role ALL DENIED
--
--   the same, preceded by a global                 1 row, identical      identical
--     `grant execute on functions to postgres`
--
-- So the defect in 0001:240 is not the REVOKE and not the role list. It is `IN SCHEMA`: a
-- schema-scoped default ACL is ADDED to what `acldefault()` already gives (which for a function is
-- EXECUTE for PUBLIC), while the schema-less entry REPLACES it. 0001 wrote the one form that cannot
-- express "PUBLIC gets nothing", and it wrote it four schemas at a time, which is why it looked so
-- deliberate.
--
-- THE SECOND ROW OF THAT TABLE IS THE TRAP, and it is why this file does not stop at reading
-- `pg_default_acl` back: four rows appear, they read `{postgres=X/postgres}`, an assert over the
-- catalogue passes — and a function created a line later is still executable by `anon`. A recorded
-- row is not the property. So the assert that governs here is BEHAVIOURAL: section 6 (a) creates a
-- probe function after the fix and requires `has_function_privilege` to say NO for both client
-- roles. The catalogue read is kept beside it as corroboration, never as the proof.
--
-- THE BLAST RADIUS, stated rather than discovered later: without `IN SCHEMA` this governs every
-- schema, not only these four. It still binds ONLY objects created by the role that applies this
-- chain — a `pg_default_acl` row applies to its own grantor's objects and nobody else's (0001 §5b,
-- measured there) — so nothing Supabase's `supabase_admin` creates is touched. What IS touched is
-- anything this role creates anywhere from here on, including a future `create extension`: its
-- functions would be born unreachable by PUBLIC and would need an explicit grant. That is the
-- correct posture for this game ("the world is read-only to everyone but the server", 0001's title)
-- and it is the price of the only form that works.
--
-- CONSEQUENCE FOR FUTURE MIGRATIONS, stated out loud: a function created from 0019 on is born
-- executable by NOBODY but the owner. It needs its own explicit `grant execute ... to
-- authenticated` (and a row in `client_rpc_entry_points`) to reach the client, and its own explicit
-- `grant execute ... to service_role` if a tick calls it — `service_role` loses the PUBLIC ride it
-- has had until now. The four service_role grants already written (0007:1059, 0010:160-162) are
-- untouched: this file revokes from `public, anon, authenticated` and names no other role.
--
-- ── THE AUTHORITY THIS FILE LEAVES BEHIND ──────────────────────────────────────────────────────
-- `public.client_executable_writers()` — the ONE answer to "may a client role execute a SECURITY
-- DEFINER function that writes, other than a declared entry point?". Zero rows is the law, exactly
-- as zero rows is the law for `client_write_grants()`. It is what makes this defect impossible to
-- reintroduce silently: proof 03 asserts it at end of chain, and every migration after this one
-- should call it beside `client_write_grants()`.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────
-- It does not touch the 8 functions in these schemas that are NOT security definer. Seven of them
-- are executable by PUBLIC and stay that way: `cmd.fold`, `cmd.parse_number`,
-- `voyage.gc_distance_nm`, `voyage.report_line`, `voyage.rng_raw`, `world.affinity_at` are all
-- IMMUTABLE pure arithmetic or string folding that run as the CALLER (so RLS applies and they reach
-- no row the caller could not), and `public.forbid_mutation` is a trigger body. `voyage.rng_raw`
-- takes the world secret as a PARAMETER precisely so that calling it discloses nothing — 0006 made
-- it IMMUTABLE so PostgreSQL itself forbids it from reading `world_config`. They are NOTICEd by
-- name on every apply rather than left invisible.
--
-- Depends ONLY on: 0001 (the four schemas, the client roles, client_write_grants) and every
-- function the chain has created through 0017. It creates no table and changes no behaviour that a
-- signed-in captain can observe.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE ROOT CAUSE: the same revoke 0001 wanted, WITHOUT `in schema` ────────────────────────
-- One statement, and the whole difference from 0001:240-241 is the `in schema` clause it omits.
-- See "THE ROOT CAUSE" in the header for the four-variant measurement; section 6 (a) proves the
-- effect on a function created afterwards rather than trusting this line.
alter default privileges revoke execute on functions from public, anon, authenticated;

-- ── 2. THE ONE LIST of what a browser may call ─────────────────────────────────────────────────
-- Read out of src/lib/rpc/catalog.ts. It is stated ONCE and used twice: the grants in §4 are a loop
-- over it, and `client_executable_writers()` subtracts it. So "granted" and "sanctioned" cannot
-- drift apart — there is no second place to forget.
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text')
    ) as t(s, f, a)
$$;

comment on function public.client_rpc_entry_points() is
  'THE ONE server-side list of RPCs a browser may execute — the mirror of src/lib/rpc/catalog.ts, '
  'which is the only place the client names a function. Every one takes no id or reads auth.uid() '
  'itself. 0018 grants EXECUTE to authenticated by looping over this, and '
  'client_executable_writers() subtracts it, so the sanctioned set and the granted set are the '
  'same set. Adding an RPC means adding a row here.';

-- ── 3. THE ONE AUTHORITY for "may a client still reach a definer that writes?" ─────────────────
-- The companion to client_write_grants() (0001:291), which reads TABLE ACLs and is blind to this.
-- `provolatile = 'v'` is the same definition of "WRITE" 0017's NOTICE used, deliberately, so the
-- two counts are comparable. anon is never sanctioned for anything; authenticated is sanctioned
-- only for a declared entry point.
create or replace function public.client_executable_writers()
returns table (schema_name text, function_name text, identity_arguments text, grantee text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select n.nspname::text,
         p.proname::text,
         pg_get_function_identity_arguments(p.oid)::text,
         g.role_name::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   cross join (values ('anon'), ('authenticated')) as g(role_name)
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosecdef
     and p.provolatile = 'v'
     and has_function_privilege(g.role_name, p.oid, 'execute')
     and not (g.role_name = 'authenticated'
              and p.oid in (select e.fn::oid from public.client_rpc_entry_points() e
                             where e.fn is not null))
$$;

comment on function public.client_executable_writers() is
  'THE ONE authority for the EXECUTE half of the lockdown: SECURITY DEFINER functions that WRITE '
  'and that a client role may still execute, excluding the declared client entry points that '
  'authenticated is supposed to hold. Zero rows is the law, the same way zero rows is the law for '
  'client_write_grants(). A SECURITY DEFINER function reached by anon runs as the definer and '
  'bypasses RLS, which is why this is not cosmetic.';

-- ── 4. THE REVOKE — over the CATALOGUE, never a list of names ──────────────────────────────────
-- Every SECURITY DEFINER function in the four schemas, whatever its volatility, comes off the
-- client. `service_role` is not named and keeps the four explicit grants it holds (0007:1059,
-- 0010:160-162); the owner keeps its own implicit rights.
do $$
declare
  r      record;
  v_done int := 0;
begin
  for r in select n.nspname                                   as sch,
                  p.proname                                   as fn,
                  pg_get_function_identity_arguments(p.oid)   as args
             from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'world', 'cmd', 'voyage')
              and p.prosecdef
            order by 1, 2, 3
  loop
    execute format('revoke execute on function %I.%I(%s) from public, anon, authenticated',
                   r.sch, r.fn, r.args);
    v_done := v_done + 1;
  end loop;
  if v_done < 80 then
    raise exception '0018 FAIL: the catalogue sweep touched only % SECURITY DEFINER function(s); the chain has far more, so the loop is not seeing them and the revoke would be a no-op', v_done;
  end if;
  raise notice '0018: EXECUTE revoked from public, anon and authenticated on % SECURITY DEFINER function(s) across public/world/cmd/voyage', v_done;
end $$;

-- ── 5. AND THE GRANT BACK, by name, from the one list ──────────────────────────────────────────
do $$
declare
  e      record;
  v_done int := 0;
begin
  for e in select * from public.client_rpc_entry_points() order by schema_name, function_name loop
    if e.fn is null then
      -- A named entry point that does not resolve would grant nothing and say nothing. The client
      -- would then get 42501 on a real call and the cause would be invisible here.
      raise exception '0018 FAIL: client_rpc_entry_points names %.%(%), which does not exist in this database — the grant loop would have silently granted nothing',
        e.schema_name, e.function_name, e.arg_types;
    end if;
    execute format('grant execute on function %s to authenticated', e.fn::text);
    v_done := v_done + 1;
  end loop;
  if v_done <> 18 then
    raise exception '0018 FAIL: % entry point(s) granted, expected the 18 named in src/lib/rpc/catalog.ts', v_done;
  end if;
  raise notice '0018: EXECUTE granted to authenticated on the % client entry point(s) named by src/lib/rpc/catalog.ts', v_done;
end $$;

-- The two authorities this file mints are themselves SECURITY DEFINER over the catalogue, and §4
-- swept them before they had any grant to lose. Said explicitly anyway, because a later
-- `create or replace` would rebuild their ACL from the (now clean) default and this line is what
-- makes that safe to read.
revoke execute on function public.client_rpc_entry_points()  from public, anon, authenticated;
revoke execute on function public.client_executable_writers() from public, anon, authenticated;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe_anon  boolean;
  v_probe_auth  boolean;
  v_probe_found int;
  v_probe_zero  int;
  v_open        int;
  v_names       text;
  v_defacl      int;
  v_defleak     int;
  v_all_def     int;
  v_anon_def    int;
  v_auth_def    int;
  v_auth_names  text;
  v_grants      int;
  v_nondef      int;
  v_nondef_txt  text;
  v_ep          record;
  v_fn          text;
  v_state       text;
  v_denied      int := 0;
  v_wrong       text := '';
  v_ok_auth     jsonb;
begin
  -- ══ (a) POSITIVE CONTROL, AND THE DEFAULT-PRIVILEGE FIX PROVEN BY BEHAVIOUR ═══════════════════
  -- The probe is created HERE, after §1, so how it is born is itself the measurement: if the
  -- ALTER DEFAULT PRIVILEGES of §1 recorded nothing (0001's failure), this function arrives
  -- executable by PUBLIC and the two checks below fail immediately.
  execute 'create function public._grant_0018_probe(p_x uuid) returns void language plpgsql '
       || 'security definer set search_path = public, pg_temp as $p$ begin '
       || 'raise exception ''0018 probe must never actually run''; end $p$';
  v_probe_anon := has_function_privilege('anon', 'public._grant_0018_probe(uuid)', 'execute');
  v_probe_auth := has_function_privilege('authenticated', 'public._grant_0018_probe(uuid)', 'execute');
  if v_probe_anon or v_probe_auth then
    raise exception '0018 self-assert FAIL: a function created AFTER the default-privilege fix was still born executable by anon=% authenticated=%. ALTER DEFAULT PRIVILEGES recorded nothing again, exactly as it did at 0001:240.',
      v_probe_anon, v_probe_auth;
  end if;

  -- Now hand it to anon on purpose and require the authority to SEE it. Without this, the zero in
  -- (b) could mean "nothing is wrong" or "the query is broken" and there is no way to tell them
  -- apart (0001 assert (a)'s technique, applied to functions).
  grant execute on function public._grant_0018_probe(uuid) to anon;
  select count(*) into v_probe_found
    from public.client_executable_writers() where function_name = '_grant_0018_probe';
  if v_probe_found <> 1 then
    raise exception '0018 self-assert FAIL: positive control found % row(s) for a writer deliberately granted to anon, expected 1. client_executable_writers() is not working, so its zero below would prove nothing.',
      v_probe_found;
  end if;
  revoke execute on function public._grant_0018_probe(uuid) from anon;
  select count(*) into v_probe_zero
    from public.client_executable_writers() where function_name = '_grant_0018_probe';
  if v_probe_zero <> 0 then
    raise exception '0018 self-assert FAIL: the probe was revoked and the authority still reports % row(s) for it', v_probe_zero;
  end if;
  execute 'drop function public._grant_0018_probe(uuid)';

  -- ══ (b) THE LAW ══════════════════════════════════════════════════════════════════════════════
  select count(*), string_agg(schema_name || '.' || function_name || '(' || identity_arguments || ') ' || grantee, ', '
                              order by schema_name, function_name)
    into v_open, v_names
    from public.client_executable_writers();
  if v_open <> 0 then
    raise exception '0018 self-assert FAIL: % SECURITY DEFINER writer(s) are still executable by a client role: %',
      v_open, v_names;
  end if;

  -- ══ (c) EVERY ENTRY POINT STILL WORKS — named one at a time, so the message says WHICH ═══════
  -- THE TRAP THIS GUARDS: lose `cmd.issue` and no order can ever be given again (0008: it is the
  -- only mutating entry point in the game). Counting to eighteen would not have said which.
  for v_ep in select * from public.client_rpc_entry_points() order by schema_name, function_name loop
    if v_ep.fn is null then
      raise exception '0018 self-assert FAIL: entry point %.%(%) does not resolve', v_ep.schema_name, v_ep.function_name, v_ep.arg_types;
    end if;
    if not has_function_privilege('authenticated', v_ep.fn::oid, 'execute') then
      raise exception '0018 self-assert FAIL: authenticated may NOT execute %, which src/lib/rpc/catalog.ts says the client calls — the revoke took it and the grant did not put it back', v_ep.fn::text;
    end if;
    if has_function_privilege('anon', v_ep.fn::oid, 'execute') then
      raise exception '0018 self-assert FAIL: anon may execute %; the entry points are for signed-in captains only', v_ep.fn::text;
    end if;
  end loop;

  -- ══ (d) THE CATALOGUE-WIDE POSTURE ═══════════════════════════════════════════════════════════
  -- Stronger than (b) and free: after this file `anon` may execute NO security definer function at
  -- all, and the set `authenticated` may execute is EXACTLY the eighteen entry points.
  select count(*),
         count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))
    into v_all_def, v_anon_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosecdef;
  if v_anon_def <> 0 then
    raise exception '0018 self-assert FAIL: anon may still execute % SECURITY DEFINER function(s): %',
      v_anon_def,
      (select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosecdef
          and has_function_privilege('anon', p.oid, 'execute'));
  end if;

  select count(*), string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_auth_def, v_auth_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosecdef
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.oid not in (select e.fn::oid from public.client_rpc_entry_points() e where e.fn is not null);
  if v_auth_def <> 0 then
    raise exception '0018 self-assert FAIL: authenticated may execute % SECURITY DEFINER function(s) that src/lib/rpc/catalog.ts does not name: %',
      v_auth_def, v_auth_names;
  end if;

  -- ══ (e) AND THE CATALOGUE AGREES — pg_default_acl read back ══════════════════════════════════
  -- Corroboration, not proof: the header's second measured variant recorded four handsome rows and
  -- changed nothing at all, so (a) above is what actually governs. This says the row exists and is
  -- the SCHEMA-LESS one — `defaclnamespace = 0`, which is the entire fix — and 0001's own assert
  -- (d) cannot see it, because that query inner-joins pg_namespace and a global row has no schema.
  select count(*) into v_defacl
    from pg_default_acl d
   where d.defaclrole = current_user::regrole::oid
     and d.defaclobjtype = 'f'
     and d.defaclnamespace = 0;
  if v_defacl <> 1 then
    raise exception '0018 self-assert FAIL: pg_default_acl holds % schema-less function row(s) owned by %, expected exactly 1. The ALTER DEFAULT PRIVILEGES of section 1 recorded nothing, exactly as 0001:240 did.',
      v_defacl, current_user;
  end if;
  -- And what it recorded hands a client nothing.
  select count(*) into v_defleak
    from pg_default_acl d
   cross join lateral aclexplode(d.defaclacl) a
   where d.defaclrole = current_user::regrole::oid
     and d.defaclobjtype = 'f'
     and d.defaclnamespace = 0
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC');
  if v_defleak <> 0 then
    raise exception '0018 self-assert FAIL: the new default ACL still hands a client role % execute entr(ies) on every function created from here on', v_defleak;
  end if;

  -- ══ (f) THE DATABASE ACTUALLY REFUSES — become anon and try ══════════════════════════════════
  -- The catalogue can be read correctly and reasoned about incorrectly (proof 03's header). One
  -- representative writer per schema, called with all-null arguments so that a call which somehow
  -- got through would refuse on the GAME's terms and write nothing: with a null fleet
  -- `cmd.issue` returns E_NO_SUCH_FLEET before touching a row (0008), `voyage.settle` and
  -- `public.fleet_unload` match no fleet, and `world.ledger` reads a null player.
  --
  -- USAGE on the three closed schemas is granted first and revoked after, so that what is measured
  -- is the FUNCTION grant this file just issued and not `anon`'s missing schema grant from
  -- 0001:222-225 — which returns the same 42501 and would make three of these four checks pass
  -- without looking at a function ACL at all. (`public` needs no such help: anon already holds
  -- USAGE there, which is why `public.fleet_unload` really did answer for anon before this file.)
  grant usage on schema world, cmd, voyage to anon;
  foreach v_fn in array array[
      'select cmd.issue(null::uuid, null::text, null::int)',
      'select world.ledger(null::timestamptz, null::int)',
      'select voyage.settle(null::uuid, null::timestamptz)',
      'select public.fleet_unload(null::uuid, null::text, null::numeric)'] loop
    begin
      execute 'set local role anon';
      begin
        execute v_fn;
        v_wrong := v_wrong || format(' %s(ANSWERED)', v_fn);
      exception when others then
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state = '42501' then
          v_denied := v_denied + 1;
        else
          -- P0001 or 22004 here would mean the call got PAST the permission check.
          v_wrong := v_wrong || format(' %s(sqlstate %s)', v_fn, v_state);
        end if;
      end;
      execute 'set local role none';
    exception when others then
      execute 'set local role none';
      raise;
    end;
  end loop;
  revoke usage on schema world, cmd, voyage from anon;
  if v_wrong <> '' or v_denied <> 4 then
    raise exception '0018 self-assert FAIL: with the schema door deliberately opened, anon was refused 42501 on only % of 4 representative writers; the others answered:%',
      v_denied, v_wrong;
  end if;
  -- and the schema door is shut again, exactly as 0001 left it
  if has_schema_privilege('anon', 'cmd', 'usage') then
    raise exception '0018 self-assert FAIL: the probe left anon holding USAGE on schema cmd';
  end if;

  -- And the other direction, which is the whole trap: `authenticated` must still get IN. A null
  -- fleet is not this role's fleet, so the GAME refuses it — with a refusal object, not a
  -- permission error. That distinction is the proof the grant is live.
  begin
    execute 'set local role authenticated';
    execute 'select cmd.issue(null::uuid, null::text, null::int)' into v_ok_auth;
    execute 'set local role none';
  exception when others then
    execute 'set local role none';
    get stacked diagnostics v_state = returned_sqlstate;
    raise exception '0018 self-assert FAIL: authenticated could not execute cmd.issue (sqlstate %) — the only mutating entry point in the game is gone and no order could ever be given', v_state;
  end;
  if v_ok_auth->>'error_code' <> 'E_NO_SUCH_FLEET' then
    raise exception '0018 self-assert FAIL: authenticated reached cmd.issue but it answered %, not the E_NO_SUCH_FLEET a null fleet should draw', v_ok_auth;
  end if;

  -- ══ (g) The 0001 lockdown is untouched ═══════════════════════════════════════════════════════
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0018 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  -- ══ (h) WHAT IS LEFT OPEN ON PURPOSE, PRINTED RATHER THAN HIDDEN (0001 (d2)'s shape) ═════════
  select count(*), coalesce(string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname), '')
    into v_nondef, v_nondef_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and not p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute');
  if v_nondef > 0 then
    raise notice '0018 NOTE: % function(s) in these schemas are still executable by anon and are NOT security definer, so they run as the CALLER and reach no row RLS would hide: %. Left open deliberately (see the header); every one of them is pure or a trigger body.',
      v_nondef, v_nondef_txt;
  end if;

  raise notice '0018 self-assert ok: EXECUTE swept off public/anon/authenticated across every SECURITY DEFINER function in the four schemas by a loop over pg_proc, and handed back BY NAME to authenticated for the 18 entry points src/lib/rpc/catalog.ts declares — anon may now execute 0 of the % definers here and authenticated exactly those 18 and nothing else (measured 2026-08-22 on the chain this file inherited: anon could reach 55 of them, 17 of those writers, and authenticated 65); client_executable_writers() reads 0 after a probe function deliberately granted to anon proved it reports 1, then 0 again once revoked; that probe was BORN unreachable by both client roles, which is section 1''s default-privilege fix measured rather than claimed — pg_default_acl now holds % SCHEMA-LESS function row(s) owned by % where 0001:240''s `in schema` form left none, and it grants a client nothing; the database itself refused anon on 4 representative writers with SQLSTATE 42501 — with USAGE on world, cmd and voyage deliberately granted first and revoked after, so the refusal is the FUNCTION grant and not 0001''s schema door — while authenticated still reached cmd.issue and was turned away by the GAME (E_NO_SUCH_FLEET), which is the difference between a lockdown and an outage; 0 client write grants',
    v_all_def, v_defacl, current_user;
end $$;
