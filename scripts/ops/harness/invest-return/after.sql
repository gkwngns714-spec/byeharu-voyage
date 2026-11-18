-- PROD CHECK (read only) after 0456: the head, the new function (server only, stable), the 2 re-cut bodies' md5 (CR stripped; compare with
-- docs/dev-log/2026-11-18-invest-return.md), city_coupons no longer reads the rate or the multiplier itself, invest_for answers coupon_day.
-- Expected: head 20260818000456 (or as renumbered); coupon_day_of present, client_can_run false, volatility s; md5s as in the dev log;
-- coupons_reads_rate false; invest_serves_coupon true.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       to_regprocedure('public.coupon_day_of(uuid,uuid,numeric)') is not null as coupon_day_of_present,
       (has_function_privilege('anon', 'public.coupon_day_of(uuid,uuid,numeric)', 'execute')
          or has_function_privilege('authenticated', 'public.coupon_day_of(uuid,uuid,numeric)', 'execute')) as client_can_run,
       (select p.provolatile from pg_proc p where p.oid = 'public.coupon_day_of(uuid,uuid,numeric)'::regprocedure) as volatility,
       md5(replace(pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) as city_coupons_md5,
       md5(replace(pg_get_functiondef('public.invest_for(uuid,uuid,text,integer)'::regprocedure), E'\r', '')) as invest_for_md5,
       (position('v_rate' in pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure)) > 0
          or position('influence_coupon_mult' in pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure)) > 0) as coupons_reads_rate,
       position('''coupon_day'', round(public.coupon_day_of(p_port, p_player, v_cost))' in pg_get_functiondef('public.invest_for(uuid,uuid,text,integer)'::regprocedure)) > 0 as invest_serves_coupon;
commit;
