-- PROD CHECK (read only) before 0456: the 2 bodies 0456 re-cuts are the chain's at 0454 (md5 of each live definition, CR stripped), each of its
-- 3 hunks occurs exactly once, its new name is free, and what its probe needs is there. Compare each md5 with docs/dev-log/2026-11-18-invest-return.md.
-- Expected: city_coupons and invest_for md5 as in the dev log; hunks 1 / 1 / 1; new_name_free true; probe_needs_there true.
begin transaction read only;
select f.fn, md5(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) as md5,
       case f.fn
         when 'public.city_coupons(uuid,timestamp with time zone)' then
           array[(length(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) - length(replace(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', ''),
                   $h$  v_rate   numeric := public.wc_num('works_coupon_day');
$h$, ''))) / length($h$  v_rate   numeric := public.wc_num('works_coupon_day');
$h$),
                 (length(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) - length(replace(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', ''),
                   $h$           round(s.paid * v_rate * least(v_rday - v_last, greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400))   -- 0413: the real days between the two day numbers, by the counter's own inverse (it was their difference x the knob)
                 * public.influence_coupon_mult(p_port, s.player_id))::bigint as due   -- 0148 (D10)
$h$, ''))) / length($h$           round(s.paid * v_rate * least(v_rday - v_last, greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400))   -- 0413: the real days between the two day numbers, by the counter's own inverse (it was their difference x the knob)
                 * public.influence_coupon_mult(p_port, s.player_id))::bigint as due   -- 0148 (D10)
$h$)]
         else
           array[(length(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', '')) - length(replace(replace(pg_get_functiondef(to_regprocedure(f.fn)), E'\r', ''),
                   $h$                            'purse', v_after);
$h$, ''))) / length($h$                            'purse', v_after);
$h$)]
       end as hunk_occurrences,
       to_regprocedure('public.coupon_day_of(uuid,uuid,numeric)') is null as new_name_free,
       (select count(*) from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') = 1
         and (select count(*) from public.nations n where n.code = 'PRT') = 1
         and exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id where p.code = 'LIS')
         and exists (select 1 from public.world_config c where c.key = 'works_coupon_day') as probe_needs_there
  from unnest(array['public.city_coupons(uuid,timestamp with time zone)', 'public.invest_for(uuid,uuid,text,integer)']) f(fn)
 order by f.fn;
commit;
