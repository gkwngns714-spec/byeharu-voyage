-- before.sql: READ-ONLY, before 0409. Wanted: head 20260818000408 (0409 = head + 1); none of the five codes; no pirate_hubs; every `hunks` figure true.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pacific-pirates/before.sql
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'hub_codes_taken', (select count(*) from public.ports p where p.code in ('PTC', 'MWY', 'TDC', 'FLO', 'DGA')),
  'pirate_hubs', to_regclass('public.pirate_hubs') is not null,
  'harbours', (select count(*) from public.ports p where p.kind = 'HARBOUR'),
  'places_with_reaches', (select count(*) from public.sea_reaches),
  'pirate_ships', (select jsonb_build_object('n', count(*), 'unable_to_sail', count(*) filter (where f.status = 'UNABLE_TO_SAIL'), 'laid_up', count(*) filter (where n.laid_up_at is not null))
                     from public.pirate_ships n join public.fleets f on f.id = n.fleet_id),
  'refit_waits', (select count(*) from public.npc_refit_waits),
  'hoard', public.pirate_hoard(), 'room_today', public.pirate_spend_room(now()), 'size', public.pirate_size(),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w where w.key in ('pirates_bite', 'pirate_spend_day_pct', 'pirate_pressure', 'navy_build_hours', 'navy_upkeep_day', 'pirate_max', 'pirate_min')),
  'hunks', jsonb_build_object(
    'step_wreck', (select position(E'if public.npc_wrecked(p_fleet) then\n    return ''WRECK'';' in replace(pg_get_functiondef('public.pirate_ship_step(uuid,timestamptz)'::regprocedure), E'\r', '')) > 0),
    'step_duty', (select position('and n.ord <= public.pirate_size();' in pg_get_functiondef('public.pirate_ship_step(uuid,timestamptz)'::regprocedure)) > 0),
    'add_pace', (select position('make_interval(hours => public.wc_int(''navy_build_hours'')) then' in pg_get_functiondef('public.pirate_add(timestamptz)'::regprocedure)) > 0),
    'add_home', (select position('v_home := public.pirate_home_of(v_ord);' in pg_get_functiondef('public.pirate_add(timestamptz)'::regprocedure)) > 0),
    'haunt_reach', (select position('and c.nm <= public.wc_num(''navy_reach_nm'')' in pg_get_functiondef('public.pirate_haunt_of(uuid,integer)'::regprocedure)) > 0),
    'pressure', (select position('public.wc_num(''pirate_pressure'') * count(*), p_now from' in pg_get_functiondef('public.pirate_pressure_write(timestamptz)'::regprocedure)) > 0),
    'refit_step', (select position('or not public.npc_wrecked(p_fleet) then' in pg_get_functiondef('public.npc_refit_step(uuid,timestamptz)'::regprocedure)) > 0),
    'card', (select position('''home'', (select p.code from public.ports p where p.id = n.home_port),' in pg_get_functiondef('world.pirate_ship_card(uuid)'::regprocedure)) > 0))
) as before;
commit;
