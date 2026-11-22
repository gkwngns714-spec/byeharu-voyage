-- THE FIRST HOUR (0472), AFTER. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/first-hour/after-0472.sql
-- Expect, DARK (as deployed): head 0472; first_hour_enabled false, first_hour_trading_below 5, first_hour_trip_hours 2,
-- first_hull_order_floor 52000; every hunk's mark present (true); `raised` 0 (dark: no human's order is raised).
-- LIT (only after the owner lights it; the 30-minute after-check): `raised` is the humans whose next Barca at Lisbon would carry
-- `first` (at most one ship, none on order), each `price` the floor less her Trading discount; `orders_since` the hull orders placed
-- since the lighting and their prices (a second hull at the floor or more). Read it with the lighting time in `since` below.
-- Reads: the catalog, world_config by key, about 20 human companies (two counts by player each, and public.hull_order_price: stable),
-- hull_orders since a time. No volatile function is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
lis as (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR'),
hum as (
  select p.id, public.hull_order_price(p.id, (select id from lis), 'barca') as q
    from public.players p where not p.is_npc
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('first_hour_enabled', 'first_hour_trading_below', 'first_hour_trip_hours', 'first_hull_order_floor')),
  'hunks_new', (select jsonb_object_agg(f.fn || ' ' || f.mark, position(f.mark in pg_get_functiondef(to_regprocedure(f.fn))) > 0) from (values
                  ('world.best_sales(uuid,uuid)', '0472 (S1)'), ('world.best_sales(uuid,uuid)', '0472 (S3)'),
                  ('public.hull_order_price(uuid,uuid,text)', '0472 (S2')) f(fn, mark)),
  'raised', (select count(*) from hum h where h.q ? 'first'),
  'raised_prices', (select coalesce(jsonb_agg(distinct (h.q ->> 'price')::bigint), '[]'::jsonb) from hum h where h.q ? 'first'),
  'orders_since', (select coalesce(jsonb_agg(jsonb_build_object('class', o.class_code, 'price', o.price, 'fee', o.fee) order by o.ordered_at), '[]'::jsonb)
                     from public.hull_orders o join public.players p on p.id = o.player_id
                    where not p.is_npc and o.ordered_at > (select t from since)));
rollback;
