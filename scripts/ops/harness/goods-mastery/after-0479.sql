-- GOODS MASTERY (0479), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/goods-mastery/after-0479.sql
-- `since` below is the last 30 minutes: read it 30 minutes after the deploy (as deployed) or after the owner lights goods_mastery_enabled.
-- Expect, AS DEPLOYED (dark): head 20260818000479; knobs goods_mastery_enabled false, goods_mastery_units [1, 100, 250, 500, 1000, 2000,
-- 3500, 6000, 10000, 16000], goods_mastery_price_step 0.005, goods_mastery_cap_step 0.05; `registered` true; `client_reach` false;
-- `hunked` all true (each of the four bodies carries its 0479 line); `rows` the back-fill only (before-0479's `backfill`: its rows, its
-- companies, its levels); `merchant_rows` 0; `told` 0 (no SOLD event carries a mastery word while dark); `bad_level` 0.
-- LIT (read 30 minutes after lighting): `told` the window's SOLD events that carry mastery (every company sale: `told` = `sales`), `ups`
-- those whose level rose; `rows` grows by one a company and a new good; `bad_level` 0 (every row's level is the one its units make).
-- ROLLBACK if `merchant_rows` > 0, `bad_level` > 0, `client_reach` true, or the gate goes red: goods_mastery_enabled false (owner).
-- Reads: world_config by key, the catalog (registry, four bodies, privileges), public.goods_mastery (small: at most 629 rows a company,
-- companies only), the companies' SOLD events of the window by the (player_id, created_at) index. No function that writes is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
hu as (select p.id from public.players p where not p.is_npc),
gm as (select m.player_id, m.units, m.level from public.goods_mastery m),
ev as (select e.payload from hu cross join lateral (select x.payload from public.events x
                                                     where x.player_id = hu.id and x.created_at > (select t from since) and x.kind = 'SOLD') e)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'goods\_mastery\_%'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e
                         where e.schema_name = 'world' and e.function_name = 'goods_mastery' and e.fn is not null),
  'client_reach', has_table_privilege('authenticated', 'public.goods_mastery', 'select')
                  or has_function_privilege('authenticated', 'public.goods_mastery_sale(uuid,uuid,numeric)', 'execute')
                  or has_function_privilege('authenticated', 'public.goods_mastery_bid(uuid,uuid,numeric)', 'execute')
                  or has_function_privilege('authenticated', 'public.goods_mastery_cap(uuid,uuid)', 'execute'),
  'hunked', jsonb_build_object(
    'do_sell', position('goods_mastery_sale' in pg_get_functiondef('cmd.do_sell(uuid,jsonb)'::regprocedure)) > 0,
    'quote_terms', position('goods_mastery_bid' in pg_get_functiondef('world.quote_terms(uuid,uuid,uuid)'::regprocedure)) > 0,
    'daily_cap', position('goods_mastery_cap' in pg_get_functiondef('world.daily_cap_remaining(uuid,uuid,uuid)'::regprocedure)) > 0,
    'registry', position('''goods_mastery''' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0),
  'rows', (select count(*) from gm),
  'companies', (select count(distinct gm.player_id) from gm),
  'levels', (select coalesce(jsonb_object_agg(z.level, z.n), '{}'::jsonb) from (select gm.level, count(*) as n from gm group by gm.level) z),
  'bad_level', (select count(*) from gm
                 where gm.level <> (select count(*) from jsonb_array_elements_text((select c.value from public.world_config c where c.key = 'goods_mastery_units')) t(v)
                                     where gm.units >= t.v::numeric)),
  'merchant_rows', (select count(*) from public.goods_mastery m join public.players p on p.id = m.player_id where p.is_npc),
  'told', (select count(*) from ev where ev.payload ? 'mastery'),
  'ups', (select count(*) from ev where (ev.payload #>> '{mastery,up}')::boolean),
  'sales', (select count(*) from ev));
rollback;
