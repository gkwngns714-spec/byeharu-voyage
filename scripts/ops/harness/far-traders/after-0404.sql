-- 0404 PROD CHECK, AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/far-traders/after-0404.sql
-- 24 rows, the far traders. Wanted on every row: hull as founded, purse near her capital (40,000 or 60,000) and moving once she trades, paused null or
-- 'laid_up' (never 'dark': dark means npc_fleet_max is under the roster), stops 2 or more with her home first. paid_by: the city that paid her starting
-- money (her country's capital, or the harbour its realm called); null if the economy was open. Read it at +15 minutes and at +6 hours (laps closed).
begin transaction read only;
select pl.company_name as house, hp.code as home, c.code as hull, nh.capital, pl.ducats as purse, sr.paused_reason as paused,
       (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = nf.route_id) as stops,
       (select count(*) from public.standing_route_laps l where l.route_id = nf.route_id and l.closed_at is not null) as laps_closed,
       (select string_agg(distinct pp.code, ' ') from public.treasury_flows f join public.ports pp on pp.id = f.port_id
         where f.player_id = pl.id and f.kind = 'FOUNDING' and f.ducats < 0) as paid_by,
       (select value from public.world_config where key = 'npc_fleet_max') as npc_fleet_max,
       (select count(*) from public.npc_fleets) as fleets
  from public.npc_houses nh
  join public.players pl on pl.id = nh.player_id
  join public.ports hp on hp.id = nh.home_port_id
  join public.npc_fleets nf on nf.player_id = nh.player_id
  join public.standing_routes sr on sr.id = nf.route_id
  join public.ships s on s.fleet_id = nf.fleet_id
  join public.ship_classes c on c.id = s.class_id
 where c.code in ('taforeia', 'retour', 'nao', 'hourque', 'indiaman', 'naucarr')
 order by hp.code, pl.company_name;
commit;
