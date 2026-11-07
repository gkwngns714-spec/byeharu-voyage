-- 0330 PROD CHECK AFTER DEPLOY, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-danger/after.sql
-- voyage.sea_danger, voyage.freeze_danger, voyage.sea_band and world.sea_danger are STABLE and write nothing (provolatile read in the row `volatile`, which must be all 's' before anything here is trusted). No game function is called.
-- Wanted: head 0330; pressure_rows 0; seas 51; off_by_a_digit 0; levels_moved 0; piracy_readers exactly voyage.sea_danger; volatile 'ssss'; frozen_wrong 0 (voyages that departed after the file, frozen on another figure).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'pressure_rows', (select count(*) from public.sea_pressure),
  'seas', (select count(*) from public.seas),
  'volatile', (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
                where p.oid in ('voyage.sea_danger(uuid,timestamp with time zone)'::regprocedure, 'voyage.freeze_danger(jsonb,timestamp with time zone)'::regprocedure,
                                'voyage.sea_band(numeric)'::regprocedure, 'world.sea_danger()'::regprocedure)),
  'off_by_a_digit', (select count(*) from public.seas s where voyage.sea_danger(s.id, now())::text <> s.piracy_index::text),
  'levels_moved', (select count(*) from jsonb_to_recordset(world.sea_danger()) x(sea_code text, level int) join public.seas s on s.code = x.sea_code where x.level <> s.danger_level),
  'piracy_readers', (select jsonb_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%piracy_index%'),
  'sailing', (select count(*) from public.voyages v where v.status = 'SAILING'),
  'sailing_frozen', (select count(*) from public.voyages v where v.status = 'SAILING' and v.path->0 ? 'danger'),
  'frozen_wrong', (select count(*) from public.voyages v cross join lateral jsonb_array_elements(v.path) e join public.seas s on s.id = (e->>'sea_id')::uuid
                    where v.status = 'SAILING' and e ? 'danger' and e->>'danger' <> s.piracy_index::text)
) as check_0330;
commit;
