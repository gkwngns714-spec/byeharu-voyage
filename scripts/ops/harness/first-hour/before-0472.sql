-- THE FIRST HOUR (0472), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/first-hour/before-0472.sql
-- Expect: head 0471; knobs {} (none of the four); each of the six hunks' OLD text once (old 1) and its NEW text absent (new 0) in the
-- live body; yard_order_fee_pct 50; starting_ducats 40000; yard_order_enabled true; level_unlocks_enabled true. `second_hull`: the human
-- companies that hold at most one ship and have no hull on order (the ones whose next order the floor would raise, once lit).
-- Reads: the catalog (pg_get_functiondef of two functions: stable), world_config by key, and for about 20 human companies two counts by
-- player (ships, hull_orders). No game function is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('world.best_sales(uuid,uuid)', '  v_i       int;' || chr(10), '0472 (THE FIRST HOUR'),
  ('world.best_sales(uuid,uuid)', 'v_short := v_u is not null and v_u <= 0 and v_cap->>''bound_by'' = ''purse'';   -- her purse buys not one', '0472 (S1)'),
  ('world.best_sales(uuid,uuid)', 'order by (c.profit > 0) desc, case when c.profit > 0 then c.profit / c.secs end desc nulls last,', '0472 (S3)'),
  ('public.hull_order_price(uuid,uuid,text)', '  v_min   int;' || chr(10), '0472: the floor of a company'),
  ('public.hull_order_price(uuid,uuid,text)', 'v_fee := round((v_lab + v_mat) * public.wc_num(''yard_order_fee_pct'') / 100.0 * (1 - public.level_perk(p_player, ''yard_fee'') / 100))::bigint;', '0472 (S2'),
  ('public.hull_order_price(uuid,uuid,text)', '''price'', v_lab + v_mat::bigint + v_fee, ''minutes'', greatest(coalesce(v_min, 0), 1), ''short'', v_short);', '0472: the second hull')
), d as (
  select h.fn, h.old, h.new, case when to_regprocedure(h.fn) is null then null else replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') end as def from h
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c
             where c.key in ('first_hour_enabled', 'first_hour_trading_below', 'first_hour_trip_hours', 'first_hull_order_floor')),
  'kept', (select jsonb_object_agg(c.key, c.value) from public.world_config c
            where c.key in ('yard_order_fee_pct', 'starting_ducats', 'yard_order_enabled', 'level_unlocks_enabled', 'trade_step_tuns')),
  'hunks', (select jsonb_agg(jsonb_build_object('fn', d.fn,
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new))) from d),
  'second_hull', (select count(*) from public.players p where not p.is_npc
                    and (select count(*) from public.ships s where s.player_id = p.id)
                        + (select count(*) from public.hull_orders o where o.player_id = p.id and o.launched_at is null) <= 1));
rollback;
