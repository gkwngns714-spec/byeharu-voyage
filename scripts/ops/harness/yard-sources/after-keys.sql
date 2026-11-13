-- 0358 PROD CHECK (after: the new keys), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/after-keys.sql
-- Run AFTER the deploy. Wanted: goods 4 and goods_with_new_keys 4; items 2 and inputs_per_item [3, 3]; goods_named 7; flax_at RIG; asks_are_the_authority true; old_keys_kept true
-- (the answer less the new keys is what premise.sql printed before the deploy: compare by eye); update_rows 1.
begin transaction read only;
with a as materialized (select world.yard_sources((select id from public.ports where code = 'LIS'), 'barca') as r),
     lines as (select e.value as v, 'good' as kind from a, jsonb_array_elements(a.r -> 'goods') e
               union all
               select u.value, 'input' from a, jsonb_array_elements(a.r -> 'items') i, jsonb_array_elements(i.value -> 'inputs') u)
select jsonb_array_length(a.r -> 'goods') as goods,
       (select count(*) from jsonb_array_elements(a.r -> 'goods') e where e.value ? 'qty' and e.value ? 'bulk' and (e.value ->> 'ask')::numeric > 0) as goods_with_new_keys,
       jsonb_array_length(a.r -> 'items') as items,
       (select jsonb_agg(jsonb_array_length(i.value -> 'inputs')) from jsonb_array_elements(a.r -> 'items') i) as inputs_per_item,
       (select count(distinct l.v ->> 'code') from lines l) as goods_named,
       (select l.v ->> 'port' from lines l where l.kind = 'input' and l.v ->> 'code' = 'flax') as flax_at,
       (select bool_and((l.v ->> 'ask')::numeric = (select pr.ask from public.ports p join public.goods g on g.code = l.v ->> 'code' cross join lateral world.price(p.id, g.id) pr where p.code = l.v ->> 'port'))
          from lines l) as asks_are_the_authority,
       (select bool_and(e.value ? 'code' and e.value ? 'port' and e.value ? 'name' and e.value ? 'miles') from jsonb_array_elements(a.r -> 'goods' || (a.r -> 'items')) e) as old_keys_kept,
       (select round(sum((l.v ->> 'qty')::numeric * (l.v ->> 'ask')::numeric)) from lines l) as goods_cost_now,
       (select round(sum((l.v ->> 'qty')::numeric * (l.v ->> 'bulk')::numeric), 1) from lines l) as tons,
       (select count(*) from public.world_news w where w.key = 'update:0358') as update_rows,
       a.r as answer
  from a;
commit;
