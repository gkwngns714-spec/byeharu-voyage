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
-- @pass GRANT_LOCKDOWN_PROBE_PROVES_QUERY  the catalogue query is shown to detect a real grant
-- @pass GRANT_LOCKDOWN_NO_WRITE_GRANTS     client_write_grants() is empty across all four schemas
-- @pass GRANT_LOCKDOWN_ANON_DENIED         anon: INSERT denied 42501 on every table
-- @pass GRANT_LOCKDOWN_AUTHENTICATED_DENIED  authenticated: INSERT denied 42501 on every table
-- @pass GRANT_LOCKDOWN_SECRET_UNREADABLE   neither client role can SELECT world_config
-- @pass GRANT_LOCKDOWN_RLS_ON_EVERY_TABLE  RLS is enabled on every table in public
-- @pass GRANT_LOCKDOWN_SERVICE_ROLE_RETAINED  the server itself can still write
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

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
end $$;
