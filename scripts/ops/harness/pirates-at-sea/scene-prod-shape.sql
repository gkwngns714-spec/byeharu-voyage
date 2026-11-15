-- scene-prod-shape.sql: PROD'S SHAPE BEFORE 0445, on the cached world: the pirates lit and paid, the first fleets built by the pirates' own job and
-- every one lying DOCKED at her haunt (as 112 of prod's 116 did on 2026-11-15). Run BEFORE the file, so 0445's own probe takes "a pirate of this
-- world" (prod's branch; the lowest ord has her home at a harbour whose haunts lie a few miles off):
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirates-at-sea/probe.mjs --pre=scripts/ops/harness/pirates-at-sea/scene-prod-shape.sql --fix
-- LOCAL SCENE (tests/harness.guard.spec.ts): it writes; the guard refuses anywhere but the local PGlite world.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $s$
declare
  v_t0 timestamptz := date_trunc('minute', now());
  i    int;
begin
  perform public.clock_set(288, v_t0);
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'attack_enabled', 'pirates_trade') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 10000000, reserve = 0;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = public.pirate_capital();
  update public.world_config set value = to_jsonb(0.5) where key = 'pirate_spend_day_pct';
  for i in 0..39 loop
    perform public.tick_arrivals(v_t0 + make_interval(mins => i));
    perform public.tick_pirates(v_t0 + make_interval(mins => i));
  end loop;
  perform public.tick_arrivals(v_t0 + interval '3 hours');
  perform public.tick_pirates(v_t0 + interval '3 hours');
  raise notice 'prod shape: % pirate fleets; % docked at their haunt; the lowest ords: %', (select count(*) from public.pirate_ships),
    (select count(*) from public.pirate_ships n join public.fleets f on f.id = n.fleet_id where f.status = 'DOCKED' and f.port_id = n.haunt_port),
    (select jsonb_agg(jsonb_build_object('ord', x.ord, 'home', x.code, 'status', x.status) order by x.ord)
       from (select n.ord, p.code, f.status from public.pirate_ships n join public.fleets f on f.id = n.fleet_id join public.ports p on p.id = n.home_port order by n.ord limit 5) x);
end
$s$;
