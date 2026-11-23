-- GOODS MASTERY (0479), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/goods-mastery/before-0479.sql
-- Expect: head 20260818000478; knobs {} (none of the four); table false; fn_absent true; each of the four hunks' OLD text once (old 1) and
-- its new marker absent (new 0): cmd.do_sell, world.quote_terms, world.daily_cap_remaining, public.client_rpc_entry_points.
-- `lit`: economy_closed and city_treasury_enabled as prod runs them (the purse pays a sale's whole total while both are on: the better
-- price is the purse's, W unchanged).
-- THE BACK-FILL the migration writes, read here without writing it (`backfill`): for each company that is not a merchant (players not
-- is_npc), the units of her SOLD events by good (by name or code), and the levels they make on the ladder 1, 100, 250, 500, 1,000, 2,000,
-- 3,500, 6,000, 10,000, 16,000. `sold` is how many SOLD events the migration reads (its time budget). Merchants are not read.
-- Reads: the catalog (four pg_get_functiondef), world_config by key, players (humans), their SOLD events by the (player_id, created_at)
-- index, goods. No function that writes is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('cmd.do_sell(uuid,jsonb)', '      || public.logbook_sale(f.player_id, g.id)));', 'goods_mastery_sale'),
  ('world.quote_terms(uuid,uuid,uuid)', '  q_bidf   := public.city_bid_factor(p_port);', 'goods_mastery_bid'),
  ('world.daily_cap_remaining(uuid,uuid,uuid)', E'  select greatest(0,\n           case when public.pirates_on() and public.pirate_home(p_port)', 'goods_mastery_cap'),
  ('public.client_rpc_entry_points()', '      (''world'',       ''logbook'',               ''''),', '''goods_mastery''')
), d as (select h.fn, h.old, h.new, replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def from h),
hu as (select p.id from public.players p where not p.is_npc),
ev as (select e.player_id, e.payload from hu cross join lateral (select x.player_id, x.payload from public.events x
                                                                  where x.player_id = hu.id and x.kind = 'SOLD') e),
bf as (select ev.player_id, gg.id as good_id, sum((ev.payload ->> 'qty')::numeric) as units
         from ev cross join lateral (select g.id from public.goods g where g.code = ev.payload ->> 'good' or g.name = ev.payload ->> 'good'
                                      order by (g.code = ev.payload ->> 'good') desc, g.code limit 1) gg
        where jsonb_typeof(ev.payload -> 'qty') = 'number'
        group by ev.player_id, gg.id having sum((ev.payload ->> 'qty')::numeric) > 0),
lv as (select bf.*, (select count(*) from unnest(array[1, 100, 250, 500, 1000, 2000, 3500, 6000, 10000, 16000]) t(v) where bf.units >= t.v) as level from bf)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'goods\_mastery\_%'),
  'table', to_regclass('public.goods_mastery') is not null,
  'fn_absent', to_regprocedure('world.goods_mastery()') is null,
  'hunks', (select jsonb_object_agg(d.fn, jsonb_build_object(
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new))) from d),
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('economy_closed', 'city_treasury_enabled', 'logbook_enabled')),
  'companies', (select count(*) from hu),
  'merchants', (select count(*) from public.players p where p.is_npc),
  'sold', (select count(*) from ev),
  'backfill', jsonb_build_object(
    'rows', (select count(*) from lv),
    'companies', (select count(distinct lv.player_id) from lv),
    'levels', (select coalesce(jsonb_object_agg(z.level, z.n), '{}'::jsonb) from (select lv.level, count(*) as n from lv group by lv.level) z),
    'most_units', (select coalesce(max(lv.units), 0) from lv)));
rollback;
