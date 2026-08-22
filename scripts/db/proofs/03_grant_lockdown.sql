-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 3 — GRANT LOCKDOWN  (DESIGN Appendix 2, CI apply-proof requirement 3)
--
--   "No client role can write any table."
--
-- WHY THIS PROOF IS NOT JUST A CATALOGUE QUERY
--   Migration 0001 asserts the CATALOGUE is clean. This proof asserts the DATABASE actually
--   refuses, by becoming `anon` and then becoming `authenticated` and trying to INSERT into every
--   single table in every schema this chain owns. The difference matters: a catalogue can be read
--   correctly and still be reasoned about incorrectly, and the predecessor lost a production
--   deploy to a grant nobody had written and nobody could see.
--
-- THE SQLSTATE IS THE POINT
--   Each attempt must fail with 42501 — INSUFFICIENT PRIVILEGE. Not "some error". If a table were
--   writable the same statement would fail with 23502 (not-null violation) or 23503 (foreign key)
--   instead, because permission is checked BEFORE constraints. So a proof that accepted any error
--   would pass on a table that is wide open, and would have found nothing.
--
-- AND THE OTHER DIRECTION
--   `service_role` must still be able to work. A lockdown that also locked out the server would
--   be "secure" and useless, so both directions are asserted, exactly as the predecessor's
--   pirate-zone lockdown proof did.
--
-- AND THE OWNERSHIP LAW, CHECKED AT THE END OF THE CHAIN
--   Supabase ships `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO anon, authenticated` under
--   its own bootstrap role, and the migration role cannot revoke those (migration 0001 §5b). They
--   are harmless only while every object here is owned by the role that applied the chain, because
--   a default ACL binds at CREATE time to the object's OWNER. 0001 asserts that for the objects
--   that existed at 0001. This proof asserts it for the FINISHED chain — all ten migrations' worth
--   of tables, sequences, views and functions — and CI runs this same file against the disposable
--   Supabase, which is the only place the claim meets the platform's real roles.
--
-- @pass GRANT_LOCKDOWN_PROBE_PROVES_QUERY  the catalogue query is shown to detect a real grant
-- @pass GRANT_LOCKDOWN_NO_WRITE_GRANTS     client_write_grants() is empty across all four schemas
-- @pass GRANT_LOCKDOWN_ANON_DENIED         anon: INSERT denied 42501 on every table
-- @pass GRANT_LOCKDOWN_AUTHENTICATED_DENIED  authenticated: INSERT denied 42501 on every table
-- @pass GRANT_LOCKDOWN_SECRET_UNREADABLE   neither client role can SELECT world_config
-- @pass GRANT_LOCKDOWN_RLS_ON_EVERY_TABLE  RLS is enabled on every table in public
-- @pass GRANT_LOCKDOWN_SERVICE_ROLE_RETAINED  the server itself can still write
-- @pass GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING  no object here was created by another grantor
-- @pass GRANT_LOCKDOWN_ANON_CANNOT_EXECUTE    anon: EXECUTE denied 42501 on every SECURITY DEFINER writer
-- @pass GRANT_LOCKDOWN_NO_CALLER_GAPS      caller_evaluated_functions() is empty, with a control proving it sees a real gap
-- @pass GRANT_LOCKDOWN_CLIENT_READS_OWN    authenticated: a plain SELECT succeeds on every RLS-protected private table
-- @pass GRANT_LOCKDOWN_RLS_ISOLATES        two houses partition every one of those tables: neither sees the other's rows
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- AND THE OTHER HALF OF THE LOCKDOWN, ADDED 2026-08-22 WITH MIGRATION 0018
--   A table grant is not the only way in. A SECURITY DEFINER function runs as its DEFINER, so a
--   client role that can EXECUTE one bypasses RLS entirely and never touches a table ACL on the
--   way — which is why `client_write_grants()` read an honest zero for seventeen migrations while
--   `anon` could call `cmd.issue`, `voyage.depart` and `cmd.execute_order` directly (0017's NOTICE
--   named all 17; 0018's header records how the hole was opened). Marker (h) below sweeps the
--   catalogue for SECURITY DEFINER functions that WRITE, becomes `anon`, and calls every one of
--   them with all-null arguments, requiring SQLSTATE 42501 each time — the same "not just some
--   error" discipline as the INSERT sweep, for the same reason: a reachable one would have failed
--   P0001 or 22004 from inside its own body instead.
--
--   Its positive control is the trap it exists to guard. The identical call is then made as
--   `authenticated` against `cmd.issue` — THE only mutating entry point in the game — and must NOT
--   be refused with 42501. A lockdown that also took that grant would leave every captain unable to
--   give an order for ever, and this proof would then pass on a game nobody can play.

do $$
declare
  v_n        int;
  v_probe    int;
  v_tables   text[];
  t          text;
  v_role     text;
  v_denied   int;
  v_wrong    text := '';
  v_state    text;
  v_norls    text;
  v_ok       boolean;
  v_player   uuid;
  v_owned_probe int;
  v_owned_wrong int;
  v_calls    text[];
  v_trig     int;
begin
  -- ── (a) POSITIVE CONTROL. Prove the catalogue query can see a grant before trusting its zero.
  create table public._lockdown_proof_probe (x int);
  grant insert, update, delete on public._lockdown_proof_probe to authenticated;
  select count(*) into v_probe from public.client_write_grants() where table_name = '_lockdown_proof_probe';
  if v_probe <> 3 then
    raise exception 'PROOF 3 FAILED: the probe granted 3 write privileges and client_write_grants() reported %', v_probe;
  end if;
  revoke all on public._lockdown_proof_probe from authenticated;
  drop table public._lockdown_proof_probe;
  raise notice 'PASS: GRANT_LOCKDOWN_PROBE_PROVES_QUERY — the query reported all 3 deliberately granted writes, so its zero below means something';

  -- ── (b) The catalogue is clean.
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception 'PROOF 3 FAILED: % client write grant(s): %', v_n,
      (select string_agg(schema_name || '.' || table_name || ' ' || grantee || ':' || privilege, ', ')
         from public.client_write_grants());
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_NO_WRITE_GRANTS — 0 write grants for anon/authenticated/PUBLIC across public, world, cmd, voyage';

  select array_agg(c.relname order by c.relname) into v_tables
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r';
  if array_length(v_tables, 1) < 12 then
    raise exception 'PROOF 3 FAILED: only % table(s) found in public; the sweep would prove almost nothing', array_length(v_tables, 1);
  end if;

  -- ── (c) The database actually refuses. Twice, once as each client role.
  foreach v_role in array array['anon', 'authenticated'] loop
    v_denied := 0;
    v_wrong  := '';
    foreach t in array v_tables loop
      begin
        execute format('set local role %I', v_role);
        begin
          execute format('insert into public.%I default values', t);
          v_wrong := v_wrong || format(' %s(ACCEPTED THE INSERT)', t);
        exception when others then
          get stacked diagnostics v_state = returned_sqlstate;
          if v_state = '42501' then
            v_denied := v_denied + 1;
          else
            -- 23502 / 23503 here would mean the INSERT got past the permission check.
            v_wrong := v_wrong || format(' %s(sqlstate %s)', t, v_state);
          end if;
        end;
        execute 'set local role none';
      exception when others then
        execute 'set local role none';
        raise;
      end;
    end loop;

    if v_wrong <> '' or v_denied <> array_length(v_tables, 1) then
      raise exception 'PROOF 3 FAILED: role % was denied on % of % tables; the others answered:%',
        v_role, v_denied, array_length(v_tables, 1), v_wrong;
    end if;
    if v_role = 'anon' then
      raise notice 'PASS: GRANT_LOCKDOWN_ANON_DENIED — anon INSERT refused with SQLSTATE 42501 on all % tables in public', v_denied;
    else
      raise notice 'PASS: GRANT_LOCKDOWN_AUTHENTICATED_DENIED — authenticated INSERT refused with SQLSTATE 42501 on all % tables in public', v_denied;
    end if;
  end loop;

  -- ── (d) The hazard seed is unreadable by any client role.
  foreach v_role in array array['anon', 'authenticated'] loop
    v_ok := false;
    begin
      execute format('set local role %I', v_role);
      begin
        execute 'select count(*) from public.world_config';
        v_ok := false;
      exception when others then
        get stacked diagnostics v_state = returned_sqlstate;
        v_ok := (v_state = '42501');
      end;
      execute 'set local role none';
    exception when others then
      execute 'set local role none';
      raise;
    end;
    if not v_ok then
      raise exception 'PROOF 3 FAILED: role % can SELECT world_config, which holds the hazard seed', v_role;
    end if;
  end loop;
  raise notice 'PASS: GRANT_LOCKDOWN_SECRET_UNREADABLE — neither anon nor authenticated may SELECT world_config (42501)';

  -- ── (e) RLS is on everywhere, so even a future SELECT grant cannot hand over another player's rows.
  select string_agg(c.relname, ', ' order by c.relname) into v_norls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_norls is not null then
    raise exception 'PROOF 3 FAILED: RLS is NOT enabled on: %', v_norls;
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_RLS_ON_EVERY_TABLE — row level security is enabled on all % tables in public',
    array_length(v_tables, 1);

  -- ── (f) THE OTHER DIRECTION: the server can still work. A lockdown that locks out the server is
  --       not a lockdown, it is an outage.
  v_player := public.new_house('00000000-0f03-4000-8000-000000000001', 'Casa Chave', 'PRT');
  if v_player is null or (select ducats from public.players where id = v_player) <= 0 then
    raise exception 'PROOF 3 FAILED: the server itself could not create a house — the lockdown went too far';
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_SERVICE_ROLE_RETAINED — the server still writes: a house was founded with % ducats',
    (select ducats from public.players where id = v_player);

  -- ── (g) Nothing here was created by another grantor, so nothing here inherited another grantor's
  --       default privileges. Positive control first: the same authority, asked about a role that
  --       owns nothing, must return rows — otherwise its zero is just a broken scan.
  select count(*) into v_owned_probe from public.objects_not_owned_by('anon');
  if v_owned_probe = 0 then
    raise exception 'PROOF 3 FAILED: objects_not_owned_by(anon) found 0 objects across four schemas holding a finished chain. The ownership scan is not working, so its zero below would prove nothing.';
  end if;

  select count(*) into v_owned_wrong from public.objects_not_owned_by(current_user::text);
  if v_owned_wrong <> 0 then
    raise exception 'PROOF 3 FAILED: % object(s) are owned by a role other than %, and may therefore carry that role''s default GRANTs: %',
      v_owned_wrong, current_user,
      (select string_agg(o.schema_name || '.' || o.object_name || ' (' || o.kind || ', owned by ' || o.owner || ')', ', ' order by o.schema_name, o.object_name)
         from public.objects_not_owned_by(current_user::text) o);
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING — all % object(s) in public/world/cmd/voyage are owned by %, so none can have inherited a foreign grantor''s default privileges (the scan proved it discriminates by finding % not owned by anon)',
    (select count(*) from public.objects_not_owned_by('a_role_that_owns_nothing_here')), current_user, v_owned_probe;

  -- ── (h) THE EXECUTE HALF. The database refusing FIRST, the catalogue authority second — the
  --       same order, and for the same reason, as this file's header gives for the table sweep.
  --
  -- Every SECURITY DEFINER function that WRITES, from the catalogue, called with all-null
  -- arguments of the right types. Trigger bodies are excluded and counted separately: they cannot
  -- be invoked as a statement at all (0A000 comes back before any ACL is consulted), and no client
  -- role can attach a trigger here to reach one. `client_executable_writers()` above still covers
  -- them, so nothing is dropped — only this behavioural sweep skips them, and says how many.
  select count(*) into v_trig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and p.prosecdef and p.provolatile = 'v' and p.prorettype = 'trigger'::regtype;

  select array_agg(call order by call) into v_calls
    from (select format('select %I.%I(%s)', n.nspname, p.proname,
                        -- ORDER BY the ordinality, not by luck: string_agg over an unordered
                        -- input may reorder, and (uuid, text, int) reordered is a type error.
                        (select coalesce(string_agg(format('null::%s', u.atype::regtype), ', ' order by u.i), '')
                           from unnest(p.proargtypes) with ordinality as u(atype, i))) as call
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'world', 'cmd', 'voyage')
             and p.prosecdef and p.provolatile = 'v'
             and p.prorettype <> 'trigger'::regtype) s;
  if array_length(v_calls, 1) < 25 then
    raise exception 'PROOF 3 FAILED: the writer sweep found only % callable SECURITY DEFINER writer(s) in four schemas holding a finished chain; it would prove almost nothing',
      coalesce(array_length(v_calls, 1), 0);
  end if;

  -- THE OUTER DOOR IS OPENED FIRST, ON PURPOSE. `anon` holds no USAGE on world, cmd or voyage
  -- (0001:222-225 grants it only on public) — measured, applied through 0017: `select
  -- cmd.do_sail(null,null)` as anon answers "42501 permission denied for SCHEMA cmd". So a sweep
  -- run as-is would collect its 42501s from the schema door and would still be green with EXECUTE
  -- handed back to anon on every function in three of the four schemas. Granting USAGE here — in a
  -- transaction this file's runner throws away — is what makes the FUNCTION ACL the thing under
  -- test. It also matches what `public` already is: anon has USAGE there, which is why
  -- `public.fleet_unload(null,null,null)` really did ANSWER for anon before 0018.
  grant usage on schema world, cmd, voyage to anon;

  v_denied := 0;
  v_wrong  := '';
  foreach t in array v_calls loop
    begin
      execute 'set local role anon';
      begin
        execute t;
        v_wrong := v_wrong || format(' %s(ANSWERED)', t);
      exception when others then
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state = '42501' then
          v_denied := v_denied + 1;
        else
          -- P0001 / 22004 here would mean the call got PAST the permission check and ran.
          v_wrong := v_wrong || format(' %s(sqlstate %s)', t, v_state);
        end if;
      end;
      execute 'set local role none';
    exception when others then
      execute 'set local role none';
      raise;
    end;
  end loop;
  revoke usage on schema world, cmd, voyage from anon;
  if v_wrong <> '' or v_denied <> array_length(v_calls, 1) then
    raise exception 'PROOF 3 FAILED: with the schema door deliberately opened, anon was refused 42501 on only % of % SECURITY DEFINER writers; the others answered:%',
      v_denied, array_length(v_calls, 1), v_wrong;
  end if;

  -- THE POSITIVE CONTROL, and the trap this whole marker guards: the same sweep, as the role that
  -- is SUPPOSED to get in, against the one function without which no order can ever be given.
  v_ok := false;
  begin
    execute 'set local role authenticated';
    begin
      execute 'select cmd.issue(null::uuid, null::text, null::int)';
      v_ok := true;          -- reached it; the game refuses a null fleet by returning a refusal
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      v_ok := (v_state <> '42501');
    end;
    execute 'set local role none';
  exception when others then
    execute 'set local role none';
    raise;
  end;
  if not v_ok then
    raise exception 'PROOF 3 FAILED: authenticated was refused 42501 on cmd.issue — the only mutating entry point in the game. The lockdown went too far and no captain could give an order.';
  end if;

  -- And the catalogue authority, which sees what the anon sweep structurally cannot: a writer
  -- handed to `authenticated` that src/lib/rpc/catalog.ts never named. `client_executable_writers()`
  -- (0018) is to functions what `client_write_grants()` is to tables, and it is asserted here at
  -- END OF CHAIN — where a later migration's new RPC shows up — not only inside the migration that
  -- minted it.
  select count(*) into v_n from public.client_executable_writers();
  if v_n <> 0 then
    raise exception 'PROOF 3 FAILED: % SECURITY DEFINER writer(s) are executable by a client role and are not declared entry points: %',
      v_n,
      (select string_agg(schema_name || '.' || function_name || '(' || identity_arguments || ') ' || grantee, ', ')
         from public.client_executable_writers());
  end if;

  raise notice 'PASS: GRANT_LOCKDOWN_ANON_CANNOT_EXECUTE — anon was refused with SQLSTATE 42501 on all % callable SECURITY DEFINER writers with USAGE on all four schemas deliberately granted first, so the refusal is the FUNCTION grant and not the schema door (% trigger body/bodies excluded, unreachable as a statement in any case); authenticated still reached cmd.issue, so this is a lockdown and not an outage; and client_executable_writers() is empty across all four schemas',
    v_denied, v_trig;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- THE OTHER WALL — added 2026-08-23 with migration 0023
--
--   Everything above this line tests the WRITE wall: become a client role, try to INSERT, require
--   42501. Not one line of it ever did a SELECT. So when migration 0018 swept EXECUTE off
--   `public.current_player_id()` — the body of ELEVEN row level security policies — every private
--   read in the game began failing with "permission denied for function current_player_id", and
--   this proof stayed green on every run, because a broken read wall is invisible to a file that
--   only tests writes. It survived from 0018 to 0023 that way, on a LIVE production project.
--
--   A lockdown has two walls, and a proof that checks one of them reports a safety it never
--   examined. So the read side is tested here the way the write side is: by BECOMING the role and
--   doing the thing, never by reading a catalogue.
--
--   THE PROPERTY IS A PARTITION, NOT AN EMPTY SET. "The other house sees zero rows" is the wrong
--   assertion — it is wrong on every table where both houses legitimately own rows, and it was the
--   first draft of this check in 0023, where it went red on four correct tables. What must hold is
--   that the two houses' visible rows ADD UP to the whole table and neither sees the other's. With
--   RLS off entirely each would see the total, and the sums would be double.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_a      constant uuid := '00000000-0f03-4000-8000-00000000000a';
  c_b      constant uuid := '00000000-0f03-4000-8000-00000000000b';
  v_a      uuid;
  v_b      uuid;
  v_fleet  uuid;
  v_gaps   int;
  v_ctrl   int;
  v_tables int := 0;
  v_read   int := 0;
  v_iso    int := 0;
  v_iso_n  int := 0;
  v_own    int;
  v_other  int;
  v_all    int;
  v_bad    text := '';
  v_state  text;
  r        record;
begin
  -- ── (i) THE CATALOGUE AUTHORITY, AT END OF CHAIN ─────────────────────────────────────────────
  -- 0023 asserts this inside itself; it is asserted again HERE because this is where a LATER
  -- migration's new policy — calling some new function nobody granted — shows up. The control
  -- comes first, so that a zero below means the query can see something rather than that it is
  -- looking nowhere.
  create function public.probe03_gap(x int) returns boolean language sql immutable as $c$ select x > 0 $c$;
  revoke all on function public.probe03_gap(int) from public, anon, authenticated;
  create table public.probe03_t (x int check (public.probe03_gap(x)));
  grant select on public.probe03_t to authenticated;
  select count(*) into v_ctrl from public.caller_evaluated_functions()
   where function_name = 'probe03_gap';
  drop table public.probe03_t;
  drop function public.probe03_gap(int);

  select count(*) into v_gaps from public.caller_evaluated_functions();
  if v_ctrl <> 1 then
    raise exception 'PROOF 3 FAILED: caller_evaluated_functions() did not report a CHECK constraint deliberately built to be unreachable, so its zero below proves nothing';
  end if;
  if v_gaps <> 0 then
    raise exception 'PROOF 3 FAILED: % expression(s) will be evaluated as a client role that may not execute them: %',
      v_gaps,
      (select string_agg(role_name || ' -> ' || object_kind || ' on ' || table_name ||
                         ' needs ' || schema_name || '.' || function_name, '; ')
         from public.caller_evaluated_functions());
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_NO_CALLER_GAPS — 0 policy bodies, CHECK constraints, column defaults, generated columns or index expressions call a function the evaluating client role may not execute; the positive control (a CHECK built on purpose to be unreachable) WAS reported, so the zero is a finding and not a blind spot';

  -- ── (ii) TWO HOUSES, AND A REAL READ AS A REAL ROLE ──────────────────────────────────────────
  v_a := public.new_house(c_a, 'Casa Alfa P3', 'PRT');
  v_b := public.new_house(c_b, 'Casa Beta P3', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_a;

  -- House A gets a row in the tables new_house does not touch, so the isolation half is not
  -- vacuous on them. An assert over an empty table reports a safety it never examined.
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  select v_a, f.port_id, g.id, world.game_day(), 1
    from public.fleets f, public.goods g where f.id = v_fleet order by g.code limit 1;
  insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession)
  select v_a, f.port_id, g.id, world.game_day(), 1, 0, 0
    from public.fleets f, public.goods g where f.id = v_fleet order by g.code limit 1;
  insert into public.player_skills (player_id, skill_id, level)
  select v_a, s.id, 1 from public.skills s order by s.code limit 1;
  insert into public.player_officers (player_id, officer_id, fleet_id)
  select v_a, o.id, v_fleet from public.officers o order by o.code limit 1;
  perform cmd.assume_identity(c_a);
  perform cmd.issue(v_fleet, 'PROVISION FULL');

  -- EVERY private table with RLS and a SELECT grant to authenticated, DERIVED FROM THE CATALOGUE
  -- rather than typed here, so a table a later migration adds is covered the day it lands.
  for r in
    select (n.nspname || '.' || c.relname) as t
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
       and has_table_privilege('authenticated', c.oid, 'select')
       and exists (select 1 from pg_policy pol
                    join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = pol.oid
                                    and d.refclassid = 'pg_proc'::regclass
                    join pg_proc p on p.oid = d.refobjid
                   where pol.polrelid = c.oid and p.proname = 'current_player_id')
     order by 1
  loop
    v_tables := v_tables + 1;
    begin
      execute 'set local role authenticated';
      begin
        execute format('select count(*) from %s', r.t) into v_own;
        v_read := v_read + 1;
      exception when others then
        get stacked diagnostics v_state = returned_sqlstate;
        v_bad := v_bad || format(' %s(%s)', r.t, v_state);
      end;
      execute 'set local role none';
    exception when others then execute 'set local role none'; raise; end;
  end loop;

  if v_tables < 8 then
    raise exception 'PROOF 3 FAILED: only % private table(s) were found to read; the sweep is looking in the wrong place and would pass over a broken wall', v_tables;
  end if;
  if v_read <> v_tables or v_bad <> '' then
    raise exception 'PROOF 3 FAILED: as `authenticated`, % of % private table(s) could be read. These refused:%. The schema GRANTS select on them, so this is a read the catalogue promises and the database denies', v_read, v_tables, v_bad;
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_CLIENT_READS_OWN — `authenticated` did a plain SELECT on all % RLS-protected private table(s) whose policy calls current_player_id, with no 42501; the write wall above and this read wall are now both tested by DOING, not by reading a catalogue',
    v_tables;

  -- ── (iii) AND NEITHER HOUSE SEES THE OTHER'S ROWS ────────────────────────────────────────────
  -- Note there is a THIRD house in this transaction, founded by the service-role marker above.
  -- That is a feature: the rule below must hold regardless of who else is in the world.
  v_bad := '';
  for r in select t from unnest(array['public.fleets', 'public.ships', 'public.ledger',
                                      'public.events', 'public.orders', 'public.trade_daily',
                                      'public.haggle_daily', 'public.player_skills',
                                      'public.player_officers']) t loop
    v_iso_n := v_iso_n + 1;
    -- THE EXACT RULE, not a sum. A first draft required A + B to equal the whole table, and it
    -- went red here on four correct tables because an EARLIER block of this same proof
    -- (GRANT_LOCKDOWN_SERVICE_ROLE_RETAINED) founds a third house in the same transaction. Two
    -- houses cannot account for three. What must hold has nothing to do with who else exists:
    --   A sees EXACTLY the rows A owns, and A sees NONE of B's.
    execute format('select count(*) from %s where player_id = %L', r.t, v_a) into v_all;
    perform cmd.assume_identity(c_a);
    begin
      execute 'set local role authenticated';
      begin
        execute format('select count(*) from %s', r.t) into v_own;
        execute format('select count(*) from %s where player_id = %L', r.t, v_b) into v_other;
      exception when others then v_own := -1; v_other := -1; end;
      execute 'set local role none';
    exception when others then execute 'set local role none'; raise; end;
    if v_all >= 1 and v_own = v_all and v_other = 0 then
      v_iso := v_iso + 1;
    else
      v_bad := v_bad || format(' %s(A-sees=%s A-owns=%s of-B-visible-to-A=%s)', r.t, v_own, v_all, v_other);
    end if;
  end loop;
  perform cmd.assume_identity(c_a);

  if v_iso <> v_iso_n then
    raise exception 'PROOF 3 FAILED: row level security partitioned only % of % table(s); the rest did not add up, which means a house saw rows that are not its own — or owned none, which makes the check vacuous:%',
      v_iso, v_iso_n, v_bad;
  end if;
  raise notice 'PASS: GRANT_LOCKDOWN_RLS_ISOLATES — on all % table(s) house A saw EXACTLY the rows it owns and ZERO of house B''s, with a third house also present in this transaction to make sure the rule is about ownership and not about arithmetic; with RLS off A would have seen every row of all three',
    v_iso_n;
end $$;
