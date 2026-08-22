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
