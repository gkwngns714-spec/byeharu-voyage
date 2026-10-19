begin transaction read only;
select json_build_object(
 'head', (select max(version) from supabase_migrations.schema_migrations),
 'fleet', (select json_build_object('fleet', f.name, 'status', f.status, 'player', nf.player_id) from public.npc_fleets nf join public.fleets f on f.id=nf.fleet_id order by nf.roster_ord limit 1),
 'port', (select p.code from public.port_buildings b join public.port_buildings y on y.port_id = b.port_id and y.kind = 'building_yard' join public.ports p on p.id = b.port_id where b.kind = 'workstation' and b.tier >= 3 order by p.code limit 1),
 'g1', (select k.code from public.item_kinds k join public.item_profile ip on ip.item_code = k.code
         where k.kind = 'fitting' and ip.grade = 1 and k.ws_tier <= 3
           and public.made_only_in(k.code, (select b.port_id from public.port_buildings b join public.port_buildings y on y.port_id = b.port_id and y.kind = 'building_yard' join public.ports p on p.id = b.port_id where b.kind = 'workstation' and b.tier >= 3 order by p.code limit 1)) is null
           and public.requirements_met((select nf.player_id from public.npc_fleets nf order by nf.roster_ord limit 1), 'item', k.code)
           and exists (select 1 from public.item_recipes ir where ir.item_code = k.code) order by k.code limit 1),
 'goldenhind', (select count(*) from public.hull_recipe_items where class_code='goldenhind' and item_code='drakes-culverins'),
 'famous_hulls', (select count(*) from public.class_profile where tech='F'),
 'famous_hri', (select count(*) from public.hull_recipe_items hi join public.class_profile cp on cp.class_code=hi.class_code and cp.tech='F'),
 'other_hri', (select json_agg(hi.item_code) from public.hull_recipe_items hi join public.class_profile cp on cp.class_code=hi.class_code where cp.tech is distinct from 'F'),
 'built_by_0180', (select count(*) from public.events where kind='HULL_LAID_DOWN' and player_id in (select player_id from public.npc_houses) and created_at > '2026-10-18 07:00+00'),
 'surplus_total', (select sum(ducats) from public.treasury_flows where kind='MERCHANT_SURPLUS')
) j;
rollback;
