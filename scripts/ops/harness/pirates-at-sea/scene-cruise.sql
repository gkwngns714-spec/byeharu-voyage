-- scene-cruise.sql: THE AT-SEA SHARE OF THE PIRATES, measured the same way before and after 0445. Run by probe.mjs (rolled back):
--   before: BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirates-at-sea/probe.mjs scripts/ops/harness/pirates-at-sea/scene-cruise.sql
--   after:  BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirates-at-sea/probe.mjs --fix scripts/ops/harness/pirates-at-sea/scene-cruise.sql
-- Prod's clock (a day is 300 s), the pirates lit and paid, the whole roster built by the pirates' own job (one fleet a minute), then three hours of
-- the minute job and the arrivals beat. The last hour is measured: who is under sail each minute, voyages begun, rows written, the job's time.
-- LOCAL SCENE (tests/harness.guard.spec.ts): it writes; the guard refuses anywhere but the local PGlite world.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $s$
declare
  v_t0    timestamptz := date_trunc('minute', now());
  v_t     timestamptz;
  i       int;
  v_work  int;
  v_sea   int;
  v_sum   numeric := 0;
  v_minsh numeric := 1;
  v_k     int := 0;
  v_rows0 bigint;
  v_voy0  bigint;
  v_ms    numeric := 0;
  v_maxms numeric := 0;
  v_c     timestamptz;
  v_r     jsonb;
  v_build int := 150;
  v_run   int := 180;
begin
  perform public.clock_set(288, v_t0);
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 10000000, reserve = 0;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = public.pirate_capital();
  update public.world_config set value = to_jsonb(0.5) where key = 'pirate_spend_day_pct';
  -- the roster is built by the job itself, one fleet a minute
  for i in 0..v_build loop
    v_t := v_t0 + make_interval(mins => i);
    perform public.tick_arrivals(v_t);
    perform public.tick_pirates(v_t);
  end loop;
  raise notice 'built: % pirate fleets, % at work, knobs: haunt_hours %, port_minutes %, cruise_nm %', (select count(*) from public.pirate_ships),
    (select count(*) from public.pirate_ships_at_work), (select w.value from public.world_config w where w.key = 'pirate_haunt_hours'), (select w.value from public.world_config w where w.key = 'pirate_port_minutes'), (select w.value from public.world_config w where w.key = 'pirate_cruise_nm');
  for i in 1..v_run loop
    v_t := v_t0 + make_interval(mins => v_build + i);
    if i = v_run - 59 then
      select coalesce(sum(s.n_tup_ins + s.n_tup_upd + s.n_tup_del), 0) into v_rows0 from pg_stat_xact_user_tables s;
      select count(*) into v_voy0 from public.voyages o join public.pirate_ships n on n.fleet_id = o.fleet_id;
    end if;
    perform public.tick_arrivals(v_t);
    v_c := clock_timestamp();
    v_r := public.tick_pirates(v_t);
    if i > v_run - 60 then
      v_ms := v_ms + extract(epoch from clock_timestamp() - v_c) * 1000;
      v_maxms := greatest(v_maxms, extract(epoch from clock_timestamp() - v_c) * 1000);
      select count(*), count(*) filter (where f.status = 'SAILING') into v_work, v_sea
        from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
       where n.laid_up_at is null and n.wrecked_at is null;
      v_sum := v_sum + v_sea::numeric / greatest(v_work, 1);
      v_minsh := least(v_minsh, v_sea::numeric / greatest(v_work, 1));
      v_k := v_k + 1;
    end if;
    if i in (1, 30, v_run) then raise notice 'minute %: % of % under sail; job %', i, (select count(*) from public.pirate_ships n join public.fleets f on f.id = n.fleet_id where f.status = 'SAILING'),
      (select count(*) from public.pirate_ships_at_work), v_r - 'struck' - 'purses' - 'joined'; end if;
  end loop;
  raise notice 'LAST HOUR: at-sea share mean %, lowest %; working %; pirate voyages begun % (% a minute); rows written % a minute (every table, the beat''s too); tick_pirates mean % ms, max % ms',
    round(v_sum / v_k, 3), round(v_minsh, 3), v_work,
    (select count(*) from public.voyages o join public.pirate_ships n on n.fleet_id = o.fleet_id) - v_voy0,
    round(((select count(*) from public.voyages o join public.pirate_ships n on n.fleet_id = o.fleet_id) - v_voy0) / 60.0, 2),
    round(((select coalesce(sum(s.n_tup_ins + s.n_tup_upd + s.n_tup_del), 0) from pg_stat_xact_user_tables s) - v_rows0) / 60.0),
    round(v_ms / v_k, 1), round(v_maxms, 1);
  raise notice 'by home: %', (select jsonb_object_agg(p.code, x.j) from (select n.home_port, jsonb_build_object('fleets', count(*), 'sailing', count(*) filter (where f.status = 'SAILING')) as j
      from public.pirate_ships n join public.fleets f on f.id = n.fleet_id where n.laid_up_at is null group by 1) x join public.ports p on p.id = x.home_port);
  raise notice 'cruises now: %', (select jsonb_build_object('n', count(*), 'nm_p50', round((percentile_cont(0.5) within group (order by o.total_nm))::numeric),
      'min_p50', round((percentile_cont(0.5) within group (order by extract(epoch from o.eta - o.departed_at) / 60))::numeric, 1),
      'min_max', round(max(extract(epoch from o.eta - o.departed_at) / 60)::numeric, 1))
      from public.voyages o join public.pirate_ships n on n.fleet_id = o.fleet_id where o.status = 'SAILING');
end
$s$;
