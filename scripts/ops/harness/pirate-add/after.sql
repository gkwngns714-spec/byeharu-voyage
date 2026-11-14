-- 0418 PROD CHECK, BEFORE the deploy AND AGAIN AFTER IT (after.sql is this text), read-only, ONE statement: the catalog, one clock row, one spend row, the pirate ships (tens to hundreds of rows).
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-add/after.sql
-- BEFORE, wanted: head 20260818000417; applied false; hunk 1. On 2026-11-14 it would read: roster_built 0, old_pending 6 (ords 8 to 13), next_ord 8, room_today 0: the add asks for ord 8 every minute and the room cannot build her.
-- AFTER, wanted: head 20260818000418; applied true; hunk 1 (the old line stands inside the new text). From the next run of the pirates' job: roster_built rises by one every pirate_add_minutes (10), whatever room_today reads;
--   added_at moves with it. With the room open (after 00:00 UTC) old_pending falls first, one a turn.
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', position('0418' in pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure)) > 0,
  'hunk', (select (length(d.def) - length(replace(d.def, E'  v_ord := public.pirate_next_ord();   -- 0414: 0339''s ships first, then the roster''s fleets, a hub at a time in turn\n', ''))) / 118
             from (select replace(pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure), E'\r', '') as def) d),
  'pirates_on', public.pirates_on(), 'size', public.pirate_size(), 'next_ord', public.pirate_next_ord(),
  'old_pending', (select count(*) from generate_series(1, public.pirate_size()) g(o) where not exists (select 1 from public.pirate_ships_at_work n where n.ord = g.o)),
  'roster', (select count(*) from public.pirate_roster), 'roster_built', (select count(*) from public.pirate_ships n where n.ord > 1000),
  'added_at', (select c.added_at from public.pirate_clock c), 'add_minutes', public.wc_int('pirate_add_minutes'),
  'room_today', public.pirate_spend_room(now()), 'hoard', public.pirate_hoard(),
  'spend_today', (select d.spent from public.pirate_spend_day d where d.day = (now() at time zone 'UTC')::date)
) as r;
commit;
