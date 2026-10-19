begin transaction read only;
select json_build_object(
 'head', (select max(version) from supabase_migrations.schema_migrations),
 'chas', (select json_agg(json_build_object('fleet', f.name, 'route', nf.route_id, 'ord', nf.roster_ord)) from public.npc_fleets nf join public.players pl on pl.id = nf.player_id and pl.company_name = 'Comptoir Chastellain' join public.fleets f on f.id = nf.fleet_id),
 'leh_gda', (select count(*) from public.npc_known_legs((select id from public.ports where code='LEH')) l where l.to_port = (select id from public.ports where code='GDA')),
 'gda_leh', (select count(*) from public.npc_known_legs((select id from public.ports where code='GDA')) l where l.to_port = (select id from public.ports where code='LEH')),
 'roster30', (select count(*) from (select nf.route_id from public.npc_fleets nf where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2 order by nf.roster_ord limit 30) z),
 'knobs', (select json_object_agg(key, value) from public.world_config where key in ('npc_route_far_candidates','npc_route_far_hold_tuns','npc_route_trade_candidates','wage_per_crew_day','npc_route_candidates','npc_buyers_per_good')),
 'readers', (select json_agg(n.nspname||'.'||p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ '(npc_route_far_candidates|npc_route_far_hold_tuns)'),
 'vol', (select json_agg(json_build_array(p.proname, p.provolatile)) from pg_proc p where p.proname in ('npc_known_legs'))
) j;
rollback;
