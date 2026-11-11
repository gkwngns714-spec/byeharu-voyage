-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0346 — A ROUTE IS JUDGED LEG BY LEG: world.route_legs(fleet, legs), a read. NO TABLE, NO KNOB, NO SWITCH, NO ROW.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-10-26 (row 209): "in the map, let me click set route, and let me press city, undo, then confirm each visiting city, then press final - something like that."
-- docs/ROUTE_BUILDER.md, slice B1: the map's route builder asks the server, as each city is tapped, whether every leg of the route can be sailed. This
-- file is that read and nothing else. The builder's Final queues the trip through the existing cmd.issue_lines (0175), unchanged.
--
-- WHAT THIS FILE ADDS (read only, STABLE, one function):
--   world.route_legs(p_fleet uuid, p_legs jsonb)   p_legs = [{from, to, course}], harbour CODES (from may be null: she starts at sea), course the
--                                                 client's proposeCourse polyline or null. Answers {legs: [{from, to, nm, days, supplies {days, cost,
--                                                 fits}, shut, via}]}, in the order asked. null when the fleet is not the caller's. Granted to
--                                                 authenticated only, as its sibling world.good_board.
-- THE HUNK (once, reversing): public.client_rpc_entry_points gains the one row, after cmd.issue_lines (the builder's other call).
--
-- ONE LEG JUDGE (docs/ROUTE_BUILDER.md section 3). Nothing here judges a leg: `shut` is voyage.leg_refusal (0231, 0345) — public.passage_gate (her
-- navigation; lit, the seas) and then whether the stores the leg asks fit her stores (public.supply_need, the rule cmd.do_sail tops her up by). The client
-- prints the served code and computes no reach, no endurance and no fit.
--   nm        the course measured as cmd.issue_lines and cmd.do_sail measure it (voyage.segments_from_course); with no course, the sailed miles between
--             the two harbours (voyage.reach_from), as cmd.issue_lines does. A course the server cannot read: nm null and shut E_NO_COURSE.
--   days      nm at her speed now (voyage.fleet_speed), the arithmetic voyage.leg_refusal prints.
--   supplies  public.supply_needs, ONE call for every leg of the route (0225: her hulls read once).
--   via       only for a leg shut by its length or its stores (E_LEG_TOO_FAR, E_ENDURANCE) that leaves from a harbour: the harbours between from
--             voyage.reach_passage (the one pathfinder), capped by the legs her stores cover (public.supply_reach), as world.good_board asks it. Asked
--             at most once per distinct harbour of departure in one call. B3 (the client's "Via N") reads it; B2 does not.
--
-- DECIDED BY DEFAULT (the owner may reverse any of these afterwards):
--   * cmd.issue_lines and cmd.standing_route_save_for are NOT re-cut to ask voyage.leg_refusal here. docs/ROUTE_BUILDER.md section 4 lists those
--     hunks, but they would refuse at plan time (E_ENDURANCE) a plan every player can queue today: a change to live play for players who never
--     open the builder, which this PR may not make. The builder confirms only legs this read calls open, and the SAIL's own gate
--     (voyage.sail_refusal) still refuses at departure. The two hunks are left for their own PR with its own window.
--   * A FLEET NOT YOURS reads null (never an error, never another house's fleet), as world.captain_stats.
--   * "Same city" (a stop equal to the last) is not a rule of the sea; the client does not offer it, and the server is not asked.
--
-- NOT TOUCHED: voyage.leg_refusal, public.passage_gate, public.supply_need(s), voyage.reach_passage, cmd.issue_lines, cmd.standing_route_save_for,
-- every table, every switch, every knob.
-- COST: one ownership read, one speed, one supply_needs call, one leg_refusal per leg (passage_gate + one supply_need), one reach_passage only for a
-- shut leg (O(n^2) over the harbours, about 0.4 to 1.2 s on prod): asked when the player taps a city in route mode, never by a job.
-- ROLLBACK (forward, owner only): a new migration dropping world.route_legs(uuid, jsonb) and reversing the hunk. Nothing else depends on it.
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows (no money moves, no harbour's purse is touched).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- VERSION: 0346 - prod head 0345 (read 2026-11-11). The registry row is anchored on the cmd.issue_lines line (read on prod: once).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t1          timestamptz;
  v_def         text;
  v_pre         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_acl_board   text;
  v_pl          uuid;
  v_fl          uuid;
  v_other       uuid;
  v_lis         uuid;
  v_near        record;
  v_far         record;
  v_mid         record;
  v_reach       numeric;
  v_cap         numeric;
  v_r           jsonb;
  v_leg         jsonb;
  v_need        record;
  v_via         jsonb;
  v_chain       jsonb;
  v_from        text;
  v_mid_seen    boolean := false;
  v_via_seen    boolean := false;
  v_lived       boolean := false;
  v_ms          numeric;
  v_ms_shut     numeric;
  c_uid  constant uuid := '00000000-0346-4000-8000-000000000001';
  c_old  constant text := $h$      ('cmd',         'issue_lines',           'uuid, jsonb, int'),
$h$;
  c_new  constant text := $h$      ('cmd',         'issue_lines',           'uuid, jsonb, int'),
      -- 0346: a route's legs judged as the map's route builder taps them (docs/ROUTE_BUILDER.md B1).
      ('world',       'route_legs',            'uuid, jsonb'),
$h$;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.route_legs(uuid,jsonb)') is not null then
    raise exception '0346 refuses: it has been applied once';
  end if;
  if to_regprocedure('voyage.leg_refusal(uuid,uuid,numeric,jsonb)') is null or to_regprocedure('public.supply_needs(uuid,numeric[])') is null
     or to_regprocedure('voyage.reach_passage(uuid,uuid,uuid,numeric)') is null or to_regprocedure('public.supply_reach(uuid)') is null
     or to_regprocedure('voyage.segments_from_course(jsonb)') is null or to_regprocedure('voyage.reach_from(uuid)') is null
     or to_regprocedure('voyage.fleet_speed(uuid)') is null or to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('cmd.issue_lines(uuid,jsonb,integer)') is null then
    raise exception '0346 refuses: a reader it composes is not in this world (0047 / 0088 / 0175 / 0188 / 0225 / 0231)';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points';
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  select coalesce(p.proacl::text, '') into v_acl_board from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure;

  -- ── 1. THE READ ──
  execute $f$
create function world.route_legs(p_fleet uuid, p_legs jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0346 (owner row 209, docs/ROUTE_BUILDER.md B1): THE LEGS OF A ROUTE, JUDGED. p_legs = [{from, to, course}] (harbour codes; from null when she starts at
-- sea; course a [[lat, lon], ...] polyline or null). Answers {legs: [{from, to, nm, days, supplies {days, cost, fits}, shut, via}]} in the order asked.
-- shut is voyage.leg_refusal (THE leg judge), null when the leg is open. via: the harbours between, for a leg shut by its length or its stores.
-- null when the fleet is not the caller's. Judged against her hold and her speed as they are now; the SAIL's own gate is the last net.
declare
  v_player uuid := public.current_player_id();
  v_speed  numeric;
  v_cap    numeric;
  v_n      int;
  v_in     jsonb;
  v_from   uuid;
  v_to     uuid;
  v_course jsonb;
  v_nm     numeric;
  v_nms    numeric[] := '{}';
  v_rows   jsonb[] := '{}';
  v_shut   jsonb;
  v_via    jsonb;
  v_vias   jsonb := '{}'::jsonb;   -- the passages from each harbour of departure, asked once a call
  v_out    jsonb := '[]'::jsonb;
  v_needs  jsonb;                  -- public.supply_needs, by each distinct length
  i        int;
begin
  if v_player is null or p_fleet is null
     or not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return null;
  end if;
  if p_legs is null or jsonb_typeof(p_legs) <> 'array' then
    return jsonb_build_object('legs', '[]'::jsonb);
  end if;
  v_n := jsonb_array_length(p_legs);
  v_speed := greatest(voyage.fleet_speed(p_fleet), 0.1);

  -- EVERY LEG MEASURED, as cmd.issue_lines measures a SAIL: the course's segments, else the sailed miles between the two harbours
  for i in 1 .. v_n loop
    v_in := p_legs -> (i - 1);
    v_from := (select p.id from public.ports p where p.code = v_in ->> 'from' and p.kind = 'HARBOUR');
    v_to   := (select p.id from public.ports p where p.code = v_in ->> 'to' and p.kind = 'HARBOUR');
    v_course := case when jsonb_typeof(v_in -> 'course') = 'array' then v_in -> 'course' end;
    v_nm := null;
    if v_to is not null then
      if v_course is not null then
        begin
          select sum((s ->> 'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_course)) s;
        exception when others then
          v_nm := null;
        end;
      elsif v_from is not null then
        select r.nm into v_nm from voyage.reach_from(v_from) r where r.port_id = v_to;
      end if;
    end if;
    v_nms := array_append(v_nms, v_nm);
    v_rows := array_append(v_rows, jsonb_build_object('from', v_in -> 'from', 'to', v_in -> 'to', 'from_id', v_from, 'to_id', v_to, 'course', v_course));
  end loop;

  -- THE STORES EVERY LEG ASKS: ONE public.supply_needs call for the whole route (0225: her hulls read once), by each distinct length
  select coalesce(jsonb_object_agg(n.nm::text, jsonb_build_object('days', round(n.days, 1), 'cost', n.cost, 'fits', n.fits)), '{}'::jsonb)
    into v_needs
    from public.supply_needs(p_fleet, v_nms) n
   where n.nm is not null;

  for i in 1 .. v_n loop
    v_nm   := v_nms[i];
    v_to   := (v_rows[i] ->> 'to_id')::uuid;
    v_from := (v_rows[i] ->> 'from_id')::uuid;
    if v_to is null then
      v_shut := cmd.refusal('E_NO_SUCH_PORT', 'there is no harbour by that name', jsonb_build_object('to', v_rows[i] -> 'to'));
    elsif v_nm is null or v_nm <= 0 then
      v_shut := cmd.refusal('E_NO_COURSE', 'no course the server can sail joins those two places', '{}'::jsonb);
    else
      v_shut := voyage.leg_refusal(p_fleet, v_to, v_nm, v_rows[i] -> 'course');   -- THE leg judge
    end if;
    -- THE HARBOURS BETWEEN, for a leg shut by its length or its stores: the one pathfinder from where the leg leaves, once per harbour a call
    v_via := null;
    if v_shut ->> 'code' in ('E_LEG_TOO_FAR', 'E_ENDURANCE') and v_from is not null then
      if not (v_vias ? v_from::text) then
        if v_cap is null then
          select sr.cap_nm into v_cap from public.supply_reach(p_fleet) sr;
        end if;
        v_vias := v_vias || jsonb_build_object(v_from::text,
          coalesce((select jsonb_object_agg(r.port_id::text, to_jsonb(r.stops))
                      from voyage.reach_passage(v_player, p_fleet, v_from, v_cap) r
                     where r.stops is not null and r.nm is not null), '{}'::jsonb));
      end if;
      v_via := v_vias -> v_from::text -> v_to::text;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'from', v_rows[i] -> 'from',
      'to', v_rows[i] -> 'to',
      'nm', case when v_nm > 0 then round(v_nm, 1) end,
      'days', case when v_nm > 0 then round(v_nm / v_speed / 24, 2) end,
      'supplies', case when v_nm > 0 then v_needs -> v_nm::text end,
      'shut', v_shut,
      'via', v_via));
  end loop;
  return jsonb_build_object('legs', v_out);
end
$body$
  $f$;

  revoke all on function world.route_legs(uuid, jsonb) from public, anon;
  grant execute on function world.route_legs(uuid, jsonb) to authenticated;
  comment on function world.route_legs(uuid, jsonb) is
    '0346 (owner row 209, docs/ROUTE_BUILDER.md B1): a route''s legs judged for the caller''s fleet: nm, days, supplies, shut (voyage.leg_refusal, the one leg judge) and via. A read; null for a fleet not yours.';

  -- ── 2. THE HUNK: the registry row (once, and reversing) ──
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_pre := v_def;
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0346 self-assert FAIL: the registry hunk occurs % time(s), not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_def, c_old, c_new);
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0346 self-assert FAIL: the registry hunk is not in the new body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0346 self-assert FAIL: public.client_rpc_entry_points does not reverse to its pre-image';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points'
         and p.oid::regprocedure::text <> 'world.route_legs(uuid,jsonb)') <> v_fn_before then
    raise exception '0346 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0346 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0346 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure)
     is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure) then
    raise exception '0346 self-assert FAIL: the read is not STABLE, definer, with the search path its sibling world.good_board has';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure) <> v_acl_board
     or has_function_privilege('anon', 'world.route_legs(uuid,jsonb)', 'execute') or not has_function_privilege('authenticated', 'world.route_legs(uuid,jsonb)', 'execute') then
    raise exception '0346 self-assert FAIL: the grants are not its sibling''s: the read to authenticated only';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'route_legs' and e.arg_types = 'uuid, jsonb' and e.fn is not null) then
    raise exception '0346 self-assert FAIL: the read is not in the client registry';
  end if;
  if world.route_legs((select f.id from public.fleets f order by f.id limit 1), '[]'::jsonb) is not null then
    raise exception '0346 self-assert FAIL: a caller with no company reads a fleet''s route';
  end if;

  -- ── 4. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. No money moves, no harbour's purse is touched, no knob is written. ──
  begin
    v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Rota 0346', (select n.id from public.nations n where n.code = 'PRT'), 0, false)
    returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Rota', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Rota', true, true);
    perform cmd.assume_identity(c_uid);
    v_reach := public.passage_reach_nm(v_pl);
    select sr.cap_nm into v_cap from public.supply_reach(v_fl) sr;

    -- (a) THE NEAREST HARBOUR SHE MAY SAIL TO: open, measured as reach_from measures it, and its supplies are supply_needs' for that length
    select r.port_id, r.code, r.nm into v_near
      from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm > 0 and voyage.leg_refusal(v_fl, r.port_id, r.nm, null) is null
     order by r.nm limit 1;
    if v_near.port_id is null then
      raise exception '0346 self-assert FAIL: the probe at Lisbon has no harbour it may sail to';
    end if;
    v_r := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code, 'course', null)));
    v_leg := v_r -> 'legs' -> 0;
    select * into v_need from public.supply_needs(v_fl, array[v_near.nm]) n;
    if jsonb_array_length(v_r -> 'legs') <> 1 or v_leg -> 'shut' <> 'null'::jsonb or (v_leg ->> 'nm')::numeric <> round(v_near.nm, 1)
       or (v_leg ->> 'to') <> v_near.code or (v_leg ->> 'from') <> 'LIS'
       or (v_leg -> 'supplies' ->> 'fits')::boolean is distinct from v_need.fits or (v_leg -> 'supplies' ->> 'cost')::bigint is distinct from v_need.cost
       or (v_leg -> 'supplies' ->> 'days')::numeric is distinct from round(v_need.days, 1)
       or (v_leg ->> 'days')::numeric is distinct from round(v_near.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24, 2) then
      raise exception '0346 self-assert FAIL: LIS -> % (% nm) is not open with supply_needs'' supplies: %', v_near.code, round(v_near.nm), v_r;
    end if;

    -- (b) THE FARTHEST HARBOUR: past her navigation, shut E_LEG_TOO_FAR, the very refusal leg_refusal gives it, after an open first leg
    select r.port_id, r.code, r.nm into v_far
      from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm > v_reach
     order by r.nm desc limit 1;
    if v_far.port_id is null then
      raise exception '0346 self-assert FAIL: no harbour lies past the probe''s navigation (% nm)', round(v_reach);
    end if;
    v_r := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', v_far.code)));
    v_leg := v_r -> 'legs' -> 1;
    if (v_leg -> 'shut' ->> 'code') is distinct from 'E_LEG_TOO_FAR'
       or v_leg -> 'shut' is distinct from voyage.leg_refusal(v_fl, v_far.port_id, (select r.nm from voyage.reach_from(v_near.port_id) r where r.port_id = v_far.port_id), null)
       or v_r -> 'legs' -> 0 -> 'shut' <> 'null'::jsonb then
      raise exception '0346 self-assert FAIL: % -> % is not shut E_LEG_TOO_FAR as leg_refusal says, after an open first leg: %', v_near.code, v_far.code, v_r;
    end if;

    -- (c) A LEG HER NAVIGATION REACHES AND HER STORES DO NOT (when this world has one from Lisbon): shut E_ENDURANCE, as leg_refusal says
    if v_cap is not null and v_cap < v_reach then
      select r.port_id, r.code, r.nm into v_mid
        from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
       where p.kind = 'HARBOUR' and r.nm > v_cap * 1.01 + 2 and r.nm <= v_reach
       order by r.nm limit 1;
      if v_mid.port_id is not null then
        v_mid_seen := true;
        v_leg := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_mid.code))) -> 'legs' -> 0;
        if (v_leg -> 'shut' ->> 'code') is distinct from 'E_ENDURANCE' or v_leg -> 'shut' is distinct from voyage.leg_refusal(v_fl, v_mid.port_id, v_mid.nm, null)
           or (v_leg -> 'supplies' ->> 'fits')::boolean is not false then
          raise exception '0346 self-assert FAIL: LIS -> % (% nm, stores cover % nm) is not shut E_ENDURANCE with supplies that do not fit: %', v_mid.code, round(v_mid.nm), round(v_cap), v_leg;
        end if;
      end if;
    end if;

    -- (d) THE HARBOURS BETWEEN: a far city shut by its length names the harbours a passage within her reach calls at, and every leg through them is open
    v_t1 := clock_timestamp();
    v_leg := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_far.code))) -> 'legs' -> 0;
    v_ms_shut := round(extract(epoch from clock_timestamp() - v_t1) * 1000);
    v_via := v_leg -> 'via';
    if v_via is not null and jsonb_typeof(v_via) = 'array' then
      v_via_seen := true;
      v_chain := '[]'::jsonb;
      v_from := 'LIS';
      for v_n in 0 .. jsonb_array_length(v_via) loop
        v_chain := v_chain || jsonb_build_array(jsonb_build_object('from', v_from, 'to', coalesce(v_via ->> v_n, v_far.code)));
        v_from := coalesce(v_via ->> v_n, v_far.code);
      end loop;
      v_r := world.route_legs(v_fl, v_chain);
      if exists (select 1 from jsonb_array_elements(v_r -> 'legs') l where l -> 'shut' <> 'null'::jsonb) then
        raise exception '0346 self-assert FAIL: LIS -> % via % has a leg that is shut: %', v_far.code, v_via, v_r;
      end if;
    end if;

    -- (e) A FLEET NOT YOURS reads null; a leg with no course and no harbour to leave from is shut E_NO_COURSE, an unknown harbour E_NO_SUCH_PORT
    select f.id into v_other from public.fleets f where f.player_id <> v_pl order by f.id limit 1;
    if v_other is not null and world.route_legs(v_other, '[]'::jsonb) is not null then
      raise exception '0346 self-assert FAIL: the probe reads another house''s fleet';
    end if;
    v_r := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', null, 'to', v_near.code, 'course', null),
                                                    jsonb_build_object('from', 'LIS', 'to', 'NO SUCH 0346')));
    if (v_r -> 'legs' -> 0 -> 'shut' ->> 'code') is distinct from 'E_NO_COURSE' or (v_r -> 'legs' -> 1 -> 'shut' ->> 'code') is distinct from 'E_NO_SUCH_PORT'
       or v_r -> 'legs' -> 0 -> 'nm' <> 'null'::jsonb then
      raise exception '0346 self-assert FAIL: an unmeasured leg or an unknown harbour is not shut by its own code: %', v_r;
    end if;

    -- (f) SIX TIMED CALLS in one session of an open two-leg route (out and home), the call a tap makes; the shut arm (reach_passage) is timed once in (d)
    v_t1 := clock_timestamp();
    for v_n in 1 .. 6 loop
      v_r := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 6);
    raise exception using errcode = 'ZX346', message = 'PROBE_ROLLBACK_0346';
  exception when sqlstate 'ZX346' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0346 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Rota 0346' or p.auth_uid = c_uid) then
    raise exception '0346 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0346 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0346 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0346 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0346 self-assert ok: A ROUTE IS JUDGED LEG BY LEG. One read, STABLE, to authenticated only, as world.good_board; one hunk, once and reversing; no other function, knob, table or row moved. Open, E_LEG_TOO_FAR, E_ENDURANCE (%), via (%), E_NO_COURSE, E_NO_SUCH_PORT, not yours: as leg_refusal says. An open two-leg route: % ms a call (6 calls); a shut leg with its via: % ms. % ms.',
    case when v_mid_seen then 'checked' else 'no such leg from Lisbon in this world' end,
    case when v_via_seen then 'every leg open' else 'none served' end,
    v_ms, v_ms_shut, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
