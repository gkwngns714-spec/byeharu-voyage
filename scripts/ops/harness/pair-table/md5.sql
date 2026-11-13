-- md5.sql: the pair table's fingerprint, read-only, ONE statement. Used on the cached world to hold the rollback draft to the pre-image (the same md5 before
-- 0403 and after 0403 and the draft); harmless on prod.
begin transaction read only;
select md5(string_agg(a.code || '>' || b.code || ':' || s.wave_min || '/' || s.title_min || '/' || array_to_string(s.zones, ' '), ',' order by a.code, b.code)) as pair_table_md5, count(*) as pair_rows
  from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port;
commit;
