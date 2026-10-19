begin transaction read only;
select json_build_object(
 'hri_writers_endow', (select json_agg(n.nspname||'.'||p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','cmd','voyage','world') and p.prosrc ~ 'hull_recipe_items'),
 'npc_hull_for', (select replace(pg_get_functiondef('public.npc_hull_for(text,uuid)'::regprocedure), E'\r','')),
 'promo_items', (select json_agg(json_build_object('code',k.code,'ws',k.ws_tier,'recipes',(select count(*) from public.item_recipes r where r.item_code=k.code))) from public.item_kinds k where k.kind='promotion'),
 'no_recipe_fittings', (select json_agg(k.code) from public.item_kinds k where k.kind='fitting' and not exists (select 1 from public.item_recipes r where r.item_code=k.code)),
 'promo_held', (select json_agg(json_build_object('item',pi.item_code,'qty',pi.qty)) from public.player_items pi join public.item_kinds k on k.code=pi.item_code where k.kind='promotion'),
 'made_events_promo', (select count(*) from public.events e where e.kind='MADE' and e.payload->>'item' in (select name from public.item_kinds where kind='promotion'))
) j;
rollback;
