-- 0332 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/crown-ships/after.sql
-- Every function read here is STABLE: public.crown_classes, world.snapshot. No game function is called.
-- Wanted: crown {galion: NAVY, navire: CARGO, qpinnace: CARGO}; marked_in_snapshot the same three; classes the same count as before; head 0332.
select jsonb_build_object(
  'crown', (select jsonb_object_agg(c.class_code, c.crown) from public.crown_classes() c),
  'marked_in_snapshot', (select jsonb_object_agg(s ->> 'code', s ->> 'crown') from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ? 'crown'),
  'classes', (select count(*) from public.ship_classes),
  'head', (select max(version) from supabase_migrations.schema_migrations)
)::text as j;
