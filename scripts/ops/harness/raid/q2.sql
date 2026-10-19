begin transaction read only;
select json_build_object(
 'vol', (select json_agg(p.oid::regprocedure::text||'='||p.provolatile::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname::text||'.'||p.proname::text in ('world.ship_stats','voyage.escort_score','public.crew_pct','public.crew_terms','voyage.fight','voyage.fight_resolve','public.raid_crew_lost','voyage.rng','public.armour_soak','voyage.hazard_roll','world.ship_stat')),
 'rcl', (select pg_get_functiondef('public.raid_crew_lost(uuid, numeric, numeric)'::regprocedure)),
 'esc', (select pg_get_functiondef('voyage.escort_score(uuid)'::regprocedure)));
rollback;
