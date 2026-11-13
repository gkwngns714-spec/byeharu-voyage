-- 0401 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add its news line and deploy
-- it as any migration (owner only). It takes out the three coastal boxes and the ocean box and puts the Kuroshio back at 16. The Guinea coast, the Guianas and the
-- Philippines' Pacific side are then inside their oceans again and a barca of Sakai cannot leave the Seto Inland Sea. data/sea-zones.json must be put back in the
-- same change (the world guard holds the tables to it). AFTER this block the derivations must be re-run as 0401 runs them: the zone raster by the statement of
-- 0401 section 2 (copied from 0215), then the pair table and the merchants' memo (0401 section 3). They are not repeated here: a draft must not carry a second
-- copy of the raster's build.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  if not exists (select 1 from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR' and b.zone_code = 'GUL') then
    raise exception '0401 rollback refuses: 0401 is not applied in this world';
  end if;
  update public.sea_zones set wave_min = 16 where code = 'PHI-JP';
  delete from public.sea_zone_boxes b using public.seas s
   where s.id = b.sea_id and ((s.code = 'NOR' and b.zone_code in ('GUL', 'CAR')) or (s.code = 'PHI' and b.zone_code = 'VIS') or (s.code = 'SOU' and b.zone_code = 'NOR-DOL'));
  update public.sea_zone_boxes b set ord = b.ord - 2 from public.seas s where s.id = b.sea_id and s.code = 'NOR' and b.ord >= 9;
  update public.sea_zone_boxes b set ord = b.ord - 1 from public.seas s where s.id = b.sea_id and s.code = 'PHI' and b.ord >= 3;
  update public.sea_zone_boxes b set ord = b.ord - 1 from public.seas s where s.id = b.sea_id and s.code = 'SOU';
  raise notice '0401 rollback draft: the boxes and the ask are back. Now re-run the derivations (0401 sections 2 and 3).';
end
$r$;
