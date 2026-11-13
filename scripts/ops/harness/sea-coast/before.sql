-- 0401 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-coast/before.sql
-- Wanted: zones 64; boxes NOR 8, PHI 2, SOU 4; kuroshio_wave 16; guinea_box false (0401 not applied); off_liberia NOR-DOL, off_guianas NOR-DOL,
-- off_luzon PHI, mid_south_atlantic SOU-ANG, mid_atlantic NOR-DOL; paramaribo NOR-DOL; pair_rows = harbours squared; HEAD IT MEETS: 20260818000400.
-- Then run barca-from-lisbon.sql and keep its answer: the same file is read again after the deploy.
begin transaction read only;
select (select count(*) from public.sea_zones) as zones,
       (select jsonb_object_agg(s.code, q.n) from (select b.sea_id, count(*) as n from public.sea_zone_boxes b group by 1) q join public.seas s on s.id = q.sea_id where s.code in ('NOR', 'PHI', 'SOU')) as boxes,
       (select z.wave_min from public.sea_zones z where z.code = 'PHI-JP') as kuroshio_wave,
       exists (select 1 from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR' and b.zone_code = 'GUL') as guinea_box,
       public.sea_zone_at(6, -12) as off_liberia, public.sea_zone_at(8, -55) as off_guianas, public.sea_zone_at(16, 124) as off_luzon,
       public.sea_zone_at(-10, -15) as mid_south_atlantic, public.sea_zone_at(5, -30) as mid_atlantic,
       (select public.harbour_zone(p.id) from public.ports p where p.code = 'PAR') as paramaribo,
       (select count(*) from public.sea_leg_asks) as pair_rows, (select count(*) from public.ports where kind = 'HARBOUR') as harbours,
       (select count(*) from public.npc_course_zones_memo) as memo_rows,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('sea_conditions_bite', 'sea_conditions_bite_npc')) as switches,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
