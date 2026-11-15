-- scene-prod-shape.sql: a world shaped like production BEFORE 0448 (cargo ships, navy, pirates, a battle being fought, a Stats count already
-- written), so the file's re-statement of the newest count and every branch of its probe run. LOCAL PGlite WORLD ONLY: it writes.
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/stats-one/probe.mjs --pre=scripts/ops/harness/stats-one/scene-prod-shape.sql --fix scripts/ops/harness/stats-one/scene-after.sql
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $p$
declare
  v_t timestamptz := now() - interval '5 minutes';
  v_nat uuid; v_capm uuid; v_stn uuid; v_b uuid; o int; r record;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.cargo_fleet_sizes set ships = 5, read_at = now();
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    perform public.cargo_ships_commission(r.nation_id);
  end loop;
  select g.nation_id, public.realm_capital(g.nation_id) into v_nat, v_capm from public.great_powers g
   where not g.pirate and public.realm_capital(g.nation_id) is not null and public.port_nation(public.realm_capital(g.nation_id)) = g.nation_id
     and exists (select 1 from public.cargo_ships c where c.nation_id = g.nation_id) order by g.nation_id limit 1;
  select a.port_id into v_stn from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id <> v_capm and public.refit_yard(a.port_id) is not null order by a.port_id limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_capm;
  perform public.navy_commission(v_nat, 9001, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  perform public.navy_commission(v_nat, 9002, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  update public.port_treasury t set ducats = 975934180 where t.port_id = public.pirate_capital();
  for o in 1 .. 3 loop
    perform public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t - interval '2 days');
  end loop;
  -- prod's shapes: merchants under sail, laid up (and so DOCKED), one unable; a pirate and a merchant held in a fight; retired cargo ships
  update public.fleets f set status = 'SAILING', port_id = null
   where f.id in (select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 700);
  update public.standing_routes x set paused_reason = 'laid_up'
   where x.id in (select nf.route_id from public.npc_fleets nf order by nf.fleet_id desc limit 88);
  update public.cargo_ships c set laid_up_at = now() where c.fleet_id in (select x.fleet_id from public.cargo_ships x order by x.fleet_id limit 20);
  update public.fleets f set status = 'SAILING', port_id = null where f.id in (select p.fleet_id from public.pirate_ships p order by p.fleet_id limit 2);
  insert into public.battles (kind, site, started_at, resolves_at, status)
  values ('RAID', '{"lat": 0, "lon": 0}'::jsonb, now(), now() + interval '1 minute', 'FIGHTING') returning id into v_b;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at)
  select v_b, z.id, 'ATTACKER', now(), now() from (select p.fleet_id as id from public.pirate_ships p order by p.fleet_id limit 1) z
  union all
  select v_b, z.id, 'DEFENDER', now(), now() from (select nf.fleet_id as id from public.npc_fleets nf order by nf.fleet_id limit 1) z;
  perform public.tick_stats(v_t);
end $p$;
select 'BEFORE' as at, jsonb_build_object(
  'ships_tab', (select jsonb_build_object('merchants', v -> 'merchants', 'navy', (v -> 'navy') - 'nations', 'pirates', (v -> 'pirates') - 'homes', 'cargo', v -> 'cargo') from (select world.stats_fleets() as v) x),
  'merchants_tab', (select v - 'list' - 'series' - 'top' - 'bottom' - 'purse' from (select world.stats_merchants(null) as v) x)) as r;
