-- 0465 PROD CHECK, BEFORE the deploy (the yard takes an order, content plan slice C, DARK behind yard_order_enabled), read-only, one
--   SELECT inside `begin transaction read only; ... commit;`:  npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-order/before-0465.sql
-- One row, one jsonb column `r`. Reads the catalog, world_config and three small tables (ports, port_buildings, hull_recipes): no
--   volatile function is called.
-- Wanted: head 20260818000464 (0463 and 0464 deployed first; 0465 goes in number order); applied false; table false; knobs 0 (none of
--   the three yet); old_hunks every count 1 and new_hunks every count 0 (else a deploy since re-cut a body: 0465 refuses); deps true
--   (every function 0465 calls); lis_yard 3 and barca_recipe true (its self-assert orders a Barca at Lisbon); fns_new 0.
begin transaction read only;
with hk(ord, fn, old, new) as (values
  (1, 'world.building_yard(uuid)', $h$public.hull_unmade(c.code) as unmade) yw));$h$, $h$public.hull_order_card(v_player, p_port);$h$),
  (2, 'public.client_rpc_entry_points()', $h$      ('world',       'crew_cost',           'uuid, int'),
$h$, $h$'order_hull'$h$))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from supabase_migrations.schema_migrations where version = '20260818000465'),
  'table', to_regclass('public.hull_orders') is not null,
  'knobs', (select count(*) from public.world_config c where c.key in ('yard_order_enabled', 'yard_order_fee_pct', 'yard_order_minutes_per_hour')),
  'old_hunks', (select jsonb_object_agg(hk.ord, (length(d.def) - length(replace(d.def, hk.old, ''))) / length(hk.old))
                  from hk cross join lateral (select replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '') as def) d),
  'new_hunks', (select jsonb_object_agg(hk.ord, (length(d.def) - length(replace(d.def, hk.new, ''))) / length(hk.new))
                  from hk cross join lateral (select replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '') as def) d),
  'deps', (select bool_and(to_regprocedure(f) is not null) from unnest(array[
             'world.yard_sources(uuid,text)', 'public.yard_labour(uuid,text)', 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)',
             'public.pay_city(uuid,uuid,text,bigint,uuid)', 'public.hull_unmade(text)', 'public.yard_wrong_country(uuid,text)',
             'public.requirements_met(uuid,text,text)', 'public.requirements_refusal(uuid,text,text)', 'public.famous_held(uuid,text)',
             'public.reputation_built(uuid,uuid,jsonb)', 'public.level_grant(uuid,text,numeric,text)', 'cmd.refused_envelope(text,text)',
             'cmd.figures(numeric,numeric,text)']) f),
  'lis_yard', (select b.tier from public.port_buildings b join public.ports p on p.id = b.port_id where p.code = 'LIS' and p.kind = 'HARBOUR' and b.kind = 'building_yard'),
  'barca_recipe', exists (select 1 from public.hull_recipes h where h.class_code = 'barca'),
  'fns_new', (select count(*) from unnest(array['public.hull_order_price(uuid,uuid,text)', 'public.hull_order_card(uuid,uuid)', 'world.hull_quote(uuid,text)',
                                                'cmd.order_hull(uuid,text)', 'cmd.launch_hull(uuid,text)']) f where to_regprocedure(f) is not null)
) as r;
commit;
