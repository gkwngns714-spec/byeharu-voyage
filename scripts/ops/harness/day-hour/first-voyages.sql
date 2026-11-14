-- LOCAL SCENE (0412, the day is an hour): a new house's first voyages out of Lisbon, by the game's own reach table and her fleet's own speed, at the clock's rate
-- as it stands. Run it before and after the file: node scripts/ops/harness/day-hour/q.mjs scripts/ops/harness/day-hour/first-voyages.sql [--apply]
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
begin;
select public.new_house('00000000-0000-4000-8000-000000000412'::uuid, 'Casa Hora', 'PRT') as house;
select po.code, po.name, round(r.nm) as nm, round(voyage.fleet_speed(f.id), 2) as knots,
       round(r.nm / voyage.fleet_speed(f.id) / 24, 2) as voyage_days,
       round(r.nm / voyage.fleet_speed(f.id) * 3600 / public.wc_num('time_compression')) as real_seconds,
       round(r.nm / voyage.fleet_speed(f.id) * 60 / public.wc_num('time_compression'), 1) as real_minutes,
       public.wc_num('time_compression') as compression
  from public.players pl
  join public.fleets f on f.player_id = pl.id
  join lateral voyage.reach_from(f.port_id) r on true
  join public.ports po on po.id = r.port_id
 where pl.auth_uid = '00000000-0000-4000-8000-000000000412'::uuid
 order by r.nm limit 12;
rollback;
