-- 0318 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/regard/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regclass, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` is 1; regard_keys, fine_word, ord_48 are 0; house_regard and regard_of are null.
with h(fn, ord, old) as (values
  ('world.tax_rate(uuid,uuid)'::regprocedure, 1, $h$    return least(v_base * public.country_factor(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$),
  ('public.port_fee(uuid,uuid,numeric)'::regprocedure, 1, $h$                               (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))))::bigint;
$h$),
  ('public.port_dues(uuid,uuid,numeric)'::regprocedure, 1, $h$    'stance', v_stance, 'factor', public.country_factor(v_stance),
$h$),
  ('public.port_dues(uuid,uuid,numeric)'::regprocedure, 2, $h$    'prep_seconds', public.wc_num('port_prep_seconds')));
$h$),
  ('public.donate_for(uuid,uuid,bigint)'::regprocedure, 1, $h$  v_after := public.pay_city(p_player, p_port, 'DONATION', p_coin, v_event);
$h$),
  ('public.invest_for(uuid,uuid,text,integer)'::regprocedure, 1, $h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
$h$),
  ('public.client_rpc_entry_points()'::regprocedure, 1, $h$      ('cmd',         'donate',                'uuid, bigint'),
$h$))
select (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'hunk', h.ord,
          'times', (length(d.t) - length(replace(d.t, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
          from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as t) d) as hunks,
       (select count(*) from public.world_config c where c.key like 'regard%') as regard_keys,
       (select count(*) from public.stats_flow_words w where w.kind = 'FINE') as fine_word,
       (select count(*) from public.stats_flow_words w where w.ord = 48) as ord_48,
       to_regclass('public.house_regard')::text as house_regard,
       to_regprocedure('public.regard_of(uuid,uuid)')::text as regard_of,
       (select max(version) from supabase_migrations.schema_migrations) as head
