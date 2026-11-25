-- CAPTAIN WORKS (0527 onward), BEFORE AND AFTER. A PROD CHECK: read-only, ONE statement; the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/captain-works/state.sql
-- Before 0527: switch null, tables null. After 0527: switch false, works 4. After 0528: party_seats 0 while dark.
-- ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'captain_works_enabled'),
  'levels_bite', (select c.value from public.world_config c where c.key = 'levels_bite'),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'tables', json_build_object('captain_works', to_regclass('public.captain_works'), 'captain_work_xp', to_regclass('public.captain_work_xp')),
  'seat_columns', (select json_agg(a.attname) from pg_attribute a where a.attrelid = 'public.captain_seats'::regclass and a.attnum > 0 and not a.attisdropped),
  'companies', (select count(*) from public.players p where not p.is_npc),
  'captains_a_company', (select json_object_agg(z.n, z.c) from (select y.n, count(*) as c from (select count(po.id) as n from public.players p left join public.player_officers po on po.player_id = p.id where not p.is_npc group by p.id) y group by y.n) z)
);
rollback;
