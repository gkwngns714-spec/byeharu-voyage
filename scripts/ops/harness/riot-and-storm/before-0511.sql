-- 0511 PROD CHECK, before the deploy; read-only, ONE statement. Wanted: knobs_there 0, kinds_there 0; the four bodies as the chain's at 0510 (the file refuses otherwise).
select (select count(*) from public.world_config where key in ('happenings_bite', 'happenings_terms')) as knobs_there,
       (select count(*) from public.voyage_event_kinds where code in ('RIOT', 'RIOT_HOME')) as kinds_there,
       (select md5(prosrc) from pg_proc where oid = 'voyage.settle(uuid,timestamp with time zone)'::regprocedure) as settle,
       (select md5(prosrc) from pg_proc where oid = 'voyage.forced_home(uuid,integer,uuid)'::regprocedure) as forced_home,
       (select md5(prosrc) from pg_proc where oid = 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure) as depart,
       (select md5(prosrc) from pg_proc where oid = 'voyage.ship_speed_parts(uuid)'::regprocedure) as speed,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.status = 'SAILING') as player_voyages_at_sea;
