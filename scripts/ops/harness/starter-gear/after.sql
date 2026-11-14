-- 0425 AFTER-CHECK (a PROD CHECK: read-only, ONE static statement). Run after the deploy, once, and again ~30 minutes later.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/starter-gear/after.sql
-- WANT: head 425; the three pieces with their prices; the door and the read registered; the news row; and, as players buy, the
--   pieces fitted, the buys and the ducats paid to the cities (kind GEAR) by the last hour, and the highest count of one piece on one
--   hull (stacked_max must be 1: a hull carries one of each).
-- Reads the new 3-row table, the catalogue, the registry, and fitted_units / treasury_flows / ledger by their item code or kind and
-- time: the ledger and the flows are read for the last hour only (created_at). Nothing volatile.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select jsonb_object_agg(sg.item_code, sg.price) from public.starter_gear sg) as pieces,
       (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('starter_gear', 'buy_starter') and e.fn is not null) as registered,
       (select count(*) from public.world_news w where w.key = 'update:0425') as news,
       (select count(*) from public.fitted_units u where u.item_code like 'starter-%') as fitted,
       (select coalesce(max(n), 0) from (select count(*) as n from public.fitted_units u where u.item_code like 'starter-%' group by u.ship_id, u.item_code) x) as stacked_max,
       (select count(*) from public.ledger l where l.kind = 'GEAR' and l.created_at > now() - interval '1 hour') as buys_hour,
       (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.kind = 'GEAR' and t.created_at > now() - interval '1 hour') as paid_to_cities_hour,
       (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l where l.kind = 'GEAR' and l.created_at > now() - interval '1 hour') as paid_by_players_hour;
commit;
