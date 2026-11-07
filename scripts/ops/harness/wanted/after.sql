-- 0334 AFTER DEPLOY, read-only, one statement. Wanted: head 0334; hunt 0; wanted_rows 0; side_rows 0; navy_days 0; marked_paths 0.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'hunt', (select c.value from public.world_config c where c.key = 'navy_hunt_per_day'),
  'wanted_rows', (select count(*) from public.wanted),
  'side_rows', (select count(*) from public.voyage_hostile),
  'navy_days', (select count(*) from public.voyage_events e where e.kind = 'NAVY'),
  'marked_paths', (select count(*) from public.voyages v where v.status = 'SAILING' and v.path::text like '%"navy"%')
) as checks;
commit;
