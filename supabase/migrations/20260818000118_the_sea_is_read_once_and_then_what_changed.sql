-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0118 — THE SEA IS READ ONCE, AND THEN ONLY WHAT CHANGED
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- With 822 merchants sailing (0114–0117), world.sea_traffic, the map's per-beat window read, cost
-- 2–7 s a call (0117 halved it) against the 8 s `authenticated` statement timeout. Its cost is
-- world.voyage_view per fleet: voyage.progress_nm walks a voyage day by day. The owner wants every
-- ship drawn at any zoom, with no read on a pan.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- world.sea_roster(p_since timestamptz) — THE ROSTER, ONCE, THEN THE DELTA.
--   p_since null: every merchant fleet. p_since set: only the fleets whose state moved at or after
--   it, judged by her route's updated_at (the executor re-dates it at every stop, hold, pause and
--   save — 0092/0096/0101) or a voyage that departed at or after it. The client keeps the roster
--   and asks with an overlap, since a tick that committed late may carry an earlier instant.
--   THE ROW is sea_traffic's row, with the voyage served as its FROZEN FACTS rather than a computed
--   position: `course` (the whole course, voyage.course_of — the polyline voyage_view cuts its
--   segment from), `legs_nm` (each leg's nm off the same frozen path, the figure voyage.position
--   walks), `eta`, `departed_at`, `total_nm`, `to`, `dest_point`. The client places her from those
--   (src/live/seaRoster.ts), linearly in time between departure and the served eta. No
--   progress_nm, no position and no waters are computed here, so the whole roster costs about
--   0.5 s, once, on the server (measured on prod: 291 ms for the rows, 216 ms for the 49 lanes),
--   and a delta costs milliseconds.
--   It is registered in public.client_rpc_entry_points and granted to `authenticated` only, like
--   sea_traffic.
--
-- WHAT IT DOES NOT TOUCH: world.sea_traffic stays as it is for any client still running an older
-- build. The client this file ships with no longer calls it, and its retirement is a later file.
-- world.port_merchants (a tap read) is unchanged.
--
-- SUPERSEDES: public.client_rpc_entry_points (one row added, sliced from its live body).
-- Self-asserts hold AS FOUND (0113); the probes roll back.

create or replace function world.sea_roster(p_since timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0118: every merchant fleet (p_since null), or those whose state moved at or after p_since.
-- The row is world.sea_traffic's row with the voyage served as its frozen facts — see the header.
declare
  v_rows jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false, 'at', now(), 'full', p_since is null, 'fleets', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'company', p.company_name,
           'nation_code', nn.code, 'ink', h.ink,
           'name', f.name, 'status', f.status,
           'ships', (select count(*) from public.ships s where s.fleet_id = f.id),
           'hulls', (select coalesce(jsonb_agg(sc.code order by s.is_flagship desc, s.created_at, s.id), '[]'::jsonb)
                       from public.ships s join public.ship_classes sc on sc.id = s.class_id
                      where s.fleet_id = f.id),
           'port', po.code,
           'roadstead', case when f.port_id is not null
                             then jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) end,
           'anchor', case when f.lat is not null then jsonb_build_array(f.lat, f.lon) end,
           'voyage', (select jsonb_build_object(
                         'to', (select code from public.ports where id = v.dest_port_id),
                         'dest_point', case when v.dest_port_id is null
                                            then v.path->(jsonb_array_length(v.path) - 1)->'b' end,
                         'course', voyage.course_of(v.path),
                         'legs_nm', (select coalesce(jsonb_agg(e->'nm' order by i), '[]'::jsonb)
                                       from jsonb_array_elements(v.path) with ordinality t(e, i)),
                         'eta', v.eta, 'total_nm', v.total_nm, 'departed_at', v.departed_at)
                        from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'),
           'lane', case when (select count(*) from public.ships s where s.fleet_id = f.id)
                             >= greatest(1, public.wc_int('fleet_lane_min_ships'))
                        then public.route_lane(nf.route_id) end,
           'next_lap_at', case when sr.hold_until > now() then sr.hold_until end)
         order by nf.roster_ord, f.id), '[]'::jsonb)
    into v_rows
    from public.fleets f
    join public.players p on p.id = f.player_id and p.is_npc
    join public.npc_houses h on h.player_id = p.id
    left join public.npc_fleets nf on nf.fleet_id = f.id
    left join public.standing_routes sr on sr.id = nf.route_id
    left join public.nations nn on nn.id = p.nation_id
    left join public.ports po on po.id = f.port_id
    left join public.sea_reaches rs on rs.port_id = f.port_id
   where p_since is null
      or sr.updated_at >= p_since
      or exists (select 1 from public.voyages v2
                  where v2.fleet_id = f.id and v2.status = 'SAILING' and v2.departed_at >= p_since);

  return jsonb_build_object('enabled', true, 'at', now(), 'full', p_since is null, 'fleets', v_rows);
end $$;

comment on function world.sea_roster(timestamptz) is
  '0118: the merchant roster — all of it (p_since null) or what moved at or after p_since — with each '
  'voyage served as its frozen facts (course, legs_nm, eta, departed_at, total_nm) for the client to '
  'place in time. The row is world.sea_traffic''s row. Authenticated only.';
revoke all on function world.sea_roster(timestamptz) from public, anon;
grant execute on function world.sea_roster(timestamptz) to authenticated;

-- THE REGISTRY gains the read (sliced from its live body; the hunk must occur exactly once).
do $$
declare
  v_def text := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_old text := $h$      ('world',       'sea_traffic',           'jsonb'),
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception '0118 self-assert FAIL: the registry''s sea_traffic row does not occur exactly once';
  end if;
  execute replace(v_def, v_old, v_old || $h$      -- 0118: the roster once, then what changed (src/live/seaRoster.ts).
      ('world',       'sea_roster',            'timestamptz'),
$h$);
end $$;

do $$
declare
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_full    jsonb;
  v_delta   jsonb;
  v_traffic jsonb;
  v_n       int;
  v_row     jsonb;
  v_route   uuid;
  v_fleet   uuid;
  v_keys    text[];
begin
  -- (a) THE WALL AND THE REGISTRY.
  if not has_function_privilege('authenticated', 'world.sea_roster(timestamptz)', 'execute')
     or has_function_privilege('anon', 'world.sea_roster(timestamptz)', 'execute') then
    raise exception '0118 self-assert FAIL: world.sea_roster is not exactly authenticated-only';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'world' and e.function_name = 'sea_roster' and e.fn is not null) then
    raise exception '0118 self-assert FAIL: world.sea_roster is not a registered entry point';
  end if;

  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select count(*) into v_n from public.fleets f join public.players p on p.id = f.player_id and p.is_npc;

    -- (b) THE FULL ROSTER IS EVERY MERCHANT FLEET, ONCE.
    v_full := world.sea_roster(null);
    if not (v_full->>'enabled')::boolean or not (v_full->>'full')::boolean
       or jsonb_array_length(v_full->'fleets') <> v_n or v_n = 0 then
      raise exception '0118 self-assert FAIL: the full roster served % of % merchant fleets',
        jsonb_array_length(v_full->'fleets'), v_n;
    end if;

    -- (c) THE ROW IS sea_traffic's ROW: the same keys, and every key but `voyage` the same value
    --     for the fleets the world read serves.
    v_traffic := world.sea_traffic(null);
    select array(select k from jsonb_object_keys(v_full->'fleets'->0) k order by k collate "C") into v_keys;
    if jsonb_array_length(v_traffic->'fleets') > 0
       and v_keys <> array(select k from jsonb_object_keys(v_traffic->'fleets'->0) k order by k collate "C") then
      raise exception '0118 self-assert FAIL: the roster row''s keys % are not sea_traffic''s', v_keys;
    end if;
    if exists (select 1 from jsonb_array_elements(v_traffic->'fleets') t
                join jsonb_array_elements(v_full->'fleets') r on r->>'id' = t->>'id'
               where (t - 'voyage') is distinct from (r - 'voyage')) then
      raise exception '0118 self-assert FAIL: a roster row differs from its traffic row outside the voyage';
    end if;
    -- and a served voyage's course is the polyline the traffic's current segment is cut from, its
    -- legs one per segment.
    if exists (select 1 from jsonb_array_elements(v_full->'fleets') r
                where r->'voyage' is not null and r->'voyage' <> 'null'::jsonb
                  and jsonb_array_length(r->'voyage'->'legs_nm') <> jsonb_array_length(r->'voyage'->'course') - 1) then
      raise exception '0118 self-assert FAIL: a voyage''s legs_nm is not one per segment of its course';
    end if;

    -- (d) THE DELTA: since now, nothing; a route touched now, exactly that fleet (positive control).
    v_delta := world.sea_roster(now() + interval '1 second');
    if (v_delta->>'full')::boolean or jsonb_array_length(v_delta->'fleets') <> 0 then
      raise exception '0118 self-assert FAIL: a delta from the future served % fleets', jsonb_array_length(v_delta->'fleets');
    end if;
    select nf.route_id, nf.fleet_id into v_route, v_fleet from public.npc_fleets nf
     where nf.route_id is not null order by nf.roster_ord, nf.fleet_id limit 1;
    if v_route is null then
      raise exception '0118 self-assert FAIL: no merchant route to probe';
    end if;
    update public.standing_routes set updated_at = now() + interval '1 hour' where id = v_route;
    v_delta := world.sea_roster(now() + interval '30 minutes');
    if jsonb_array_length(v_delta->'fleets') <> 1 or v_delta->'fleets'->0->>'id' <> v_fleet::text then
      raise exception '0118 self-assert FAIL: a delta did not serve exactly the fleet whose route moved: %',
        jsonb_array_length(v_delta->'fleets');
    end if;

    -- (e) DARK, NOTHING.
    update public.world_config set value = 'false'::jsonb where key = 'npc_traders_enabled';
    if (world.sea_roster(null)->>'enabled')::boolean or jsonb_array_length(world.sea_roster(null)->'fleets') <> 0 then
      raise exception '0118 self-assert FAIL: dark, the roster still serves fleets';
    end if;
    raise exception 'ROLLBACK_0118';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0118' then raise; end if;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on then
    raise exception '0118 self-assert FAIL: the switch was not left as found';
  end if;

  raise notice '0118 self-assert ok: THE SEA IS READ ONCE, AND THEN ONLY WHAT CHANGED. world.sea_roster is '
    'authenticated-only and registered; full, it served every merchant fleet (% of them), its rows are '
    'sea_traffic''s rows outside the voyage, each voyage''s legs one per segment; a delta from the future served '
    'none and a route moved served exactly her fleet; dark, nothing. Rolled back; switch as found (%).',
    v_n, case when v_was_on then 'lit' else 'dark' end;
end $$;
