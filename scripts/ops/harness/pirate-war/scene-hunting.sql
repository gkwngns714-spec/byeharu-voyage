-- scene-hunting.sql: LOCAL ONLY. Before 0427 on the cached head world: lights the pirates and attacks, builds one roster xebec of Tortuga lying
-- at her haunt (hunting) and anchors a company's merchant beside her, so 0427's own rolled-back probe takes its lit branch (as on prod).
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/pirate-war/probe.mjs --pre=scripts/ops/harness/pirate-war/scene-hunting.sql --fix
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $s$
declare
  v_hub uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf  uuid;
  v_m   uuid;
  r     record;
  pt    record;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'pirates_bite', 'attack_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 2000000000 where t.port_id = public.pirate_capital();
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 4;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), now());
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = now() where x.fleet_id = v_pf;
  select p.lat, p.lon into pt from voyage.fleet_point(v_pf, now()) p;
  select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and f.status = 'DOCKED' and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = pt.lat, lon = pt.lon, busy_until = null where f.id = v_m;
  -- put the switches back as the cached world had them: 0427's probe lights them itself, inside its rolled-back block
  update public.world_config set value = 'false'::jsonb where key in ('city_treasury_enabled', 'pirates_bite');
  raise notice 'scene-hunting: pirate % hunting at %, merchant % anchored beside her', v_pf, (select p.code from public.ports p where p.id = r.port_id), v_m;
end $s$;
