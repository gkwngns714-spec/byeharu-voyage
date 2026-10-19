begin transaction read only;
with l as (select lp.*, sr.id rid from public.standing_route_laps lp join public.standing_routes sr on sr.id=lp.route_id join public.npc_fleets nf on nf.route_id=sr.id where lp.closed_at > now() - interval '2 hours')
select json_build_object(
 'laps', (select count(*) from l), 'le0', (select count(*) from l where net <= 0),
 'no_buy', (select count(*) from l where bought=0), 'empty', (select count(*) from l where bought=0 and sold=0),
 'sum_net', (select sum(net) from l), 'mean_net', (select round(avg(net)) from l),
 'le0_with_trade', (select count(*) from l where net<=0 and (bought>0 or sold>0)),
 'routes', (select count(*) from public.npc_fleets),
 'paused', (select json_object_agg(coalesce(r,'-'), c) from (select sr.paused_reason r, count(*) c from public.standing_routes sr join public.npc_fleets nf on nf.route_id=sr.id group by 1) z),
 'stops', (select json_object_agg(n, c) from (select n, count(*) c from (select count(*) n from public.standing_route_stops s join public.npc_fleets nf on nf.route_id=s.route_id group by s.route_id) a group by 1) b),
 'routes_neg_6laps', (select count(*) from (select lp.route_id from public.standing_route_laps lp join public.npc_fleets nf on nf.route_id=lp.route_id where lp.closed_at > now()-interval '3 hours' group by 1 having count(*) >= 4 and max(net) <= 0) z),
 'sweep', (select json_build_object('n', count(*), 'avg_s', round(avg(extract(epoch from end_time-start_time))::numeric,2), 'p95_s', round(percentile_cont(0.95) within group (order by extract(epoch from end_time-start_time))::numeric,2)) from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname like '%arrivals%' and d.start_time > now()-interval '1 hour'),
 'reconcile', (select json_agg(round(extract(epoch from end_time-start_time)::numeric,1) order by start_time desc) from (select d.* from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname like '%reconcile%' order by d.start_time desc limit 4) z),
 'jobs', (select json_agg(jobname) from cron.job)
) j;
rollback;
