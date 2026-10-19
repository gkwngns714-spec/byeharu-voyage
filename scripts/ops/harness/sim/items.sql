begin transaction read only;
select json_build_object(
 'cols', (select json_agg(json_build_array(table_name, column_name, is_nullable, data_type) order by table_name, ordinal_position) from information_schema.columns where table_schema='public' and table_name in ('item_kinds','item_recipes','item_profile','hull_recipe_items','hull_recipes')),
 'readers_recipes', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'item_recipes'),
 'readers_wstier', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'ws_tier'),
 'writers_items', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~* 'insert into public.(player_items|fitted_units)'),
 'readers_hri', (select json_agg(n.nspname||'.'||p.proname order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'hull_recipe_items'),
 'famous_items', (select json_agg(json_build_object('code', k.code, 'ws', k.ws_tier, 'recipe', (select count(*) from public.item_recipes r where r.item_code=k.code))) from public.item_kinds k where k.code in ('madre-de-deus-holds','san-martin-tercio','batavia-double-planking','drakes-culverins','couronne-battery','duodo-bow-guns','turgut-reis-swivels','rahimi-pilgrim-holds','zheng-he-bulkheads','date-masamune-charts','dragon-head-cannon')),
 'held', (select json_agg(json_build_object('item', pi.item_code, 'qty', pi.qty)) from public.player_items pi where pi.item_code in ('madre-de-deus-holds','san-martin-tercio','batavia-double-planking','drakes-culverins','couronne-battery','duodo-bow-guns','turgut-reis-swivels','rahimi-pilgrim-holds','zheng-he-bulkheads','date-masamune-charts','dragon-head-cannon')),
 'fitted', (select count(*) from public.fitted_units u where u.item_code in ('madre-de-deus-holds','san-martin-tercio','batavia-double-planking','drakes-culverins','couronne-battery','duodo-bow-guns','turgut-reis-swivels','rahimi-pilgrim-holds','zheng-he-bulkheads','date-masamune-charts','dragon-head-cannon')),
 'famous_ships', (select count(*) from public.ships s join public.ship_classes c on c.id=s.class_id join public.class_profile cp on cp.class_code=c.code where cp.tech='F'),
 'famous_skill_holders', (select count(*) from public.player_skills ps join public.skills sk on sk.id=ps.skill_id where sk.code='FAMOUS_SHIPS'),
 'skills_bite', (select value from public.world_config where key='skills_bite')
) j;
rollback;
