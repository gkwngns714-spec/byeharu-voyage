-- 0465 PROD CHECK, AFTER the deploy (DARK), read-only, one SELECT inside `begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-order/after-0465.sql
-- One row, one jsonb column `r`. Calls only stable functions (public.hull_order_card, world.hull_quote: provolatile 's', read below).
-- Wanted: applied true; orders 0 (nobody can order while dark); knobs {yard_order_enabled: false, yard_order_fee_pct: 50,
--   yard_order_minutes_per_hour: 1.25}; new_hunks {1: 1, 2: 3}; card_dark {} (the yard read serves no `order`: dark it is as before);
--   quote_dark {"on": false}; stable true; core_private true (no client role nor service_role executes a core); doors_authenticated
--   true (the quote and the two doors execute for authenticated, not anon); rls true; table_private true.
-- WHEN LIT (the owner's switch; then once, an hour on): orders_open / orders_launched count rows, and `newest` the last five orders
--   (class, price, minutes waited, launched or not). Read-only either way.
begin transaction read only;
select jsonb_build_object(
  'applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20260818000465'),
  'orders', (select count(*) from public.hull_orders),
  'orders_open', (select count(*) from public.hull_orders o where o.launched_at is null),
  'orders_launched', (select count(*) from public.hull_orders o where o.launched_at is not null),
  'newest', (select coalesce(jsonb_agg(x), '[]'::jsonb)
               from (select o.class_code, o.price, round(extract(epoch from o.ready_at - o.ordered_at) / 60) as minutes,
                            o.launched_at is not null as launched, o.ordered_at
                       from public.hull_orders o order by o.ordered_at desc limit 5) x),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('yard_order_enabled', 'yard_order_fee_pct', 'yard_order_minutes_per_hour')),
  'new_hunks', jsonb_build_object(
     '1', (select (length(d) - length(replace(d, 'public.hull_order_card(v_player, p_port);', ''))) / length('public.hull_order_card(v_player, p_port);')
             from (select replace(pg_get_functiondef('world.building_yard(uuid)'::regprocedure), E'\r', '') d) z),
     '2', (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('hull_quote', 'order_hull', 'launch_hull'))),
  'card_dark', public.hull_order_card(null, (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR')),
  'quote_dark', world.hull_quote((select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR'), 'barca'),
  'stable', (select bool_and(p.provolatile = 's') from pg_proc p
              where p.oid in ('public.hull_order_card(uuid,uuid)'::regprocedure, 'world.hull_quote(uuid,text)'::regprocedure,
                              'world.building_yard(uuid)'::regprocedure, 'public.hull_order_price(uuid,uuid,text)'::regprocedure)),
  'core_private', not exists (select 1 from unnest(array['public.hull_order_price(uuid,uuid,text)', 'public.hull_order_card(uuid,uuid)',
                    'public.hull_order_for(uuid,uuid,text,timestamp with time zone)', 'public.hull_launch_for(uuid,uuid,text,timestamp with time zone)']) f
                    cross join unnest(array['anon', 'authenticated', 'service_role']) r
                   where has_function_privilege(r, f::regprocedure, 'execute')),
  'doors_authenticated', (select bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute') and not has_function_privilege('anon', f::regprocedure, 'execute'))
                            from unnest(array['world.hull_quote(uuid,text)', 'cmd.order_hull(uuid,text)', 'cmd.launch_hull(uuid,text)']) f),
  'rls', (select c.relrowsecurity from pg_class c where c.oid = 'public.hull_orders'::regclass),
  'table_private', not (has_table_privilege('authenticated', 'public.hull_orders', 'select,insert,update,delete')
                        or has_table_privilege('anon', 'public.hull_orders', 'select,insert,update,delete'))
) as r;
commit;
