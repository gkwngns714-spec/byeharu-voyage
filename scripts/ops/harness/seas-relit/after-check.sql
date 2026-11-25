-- 0514 AFTER THE LIGHT, at +1, +10 and +30 minutes; read only, ONE statement. Wanted: lit true; trapped 0; failed orders by code: E_SEA_CLOSED only for legs further out;
-- departures not near 0; beat avg under 2,000 ms, errors 0; merchants' switch as before the light.
select now() as read_at, (select value from public.world_config where key = 'sea_conditions_bite') as lit,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as merchants,
       (public.seas_relit_ready() - 'rungs' - 'companies') as totals,
       (select coalesce(jsonb_object_agg(q.code, q.n), '{}'::jsonb) from (select o.error_code as code, count(*) as n from public.orders o join public.players p on p.id = o.player_id and not p.is_npc
          where o.status = 'failed' and o.issued_at >= now() - interval '30 minutes' group by o.error_code) q) as refused_30m,
       (select coalesce(jsonb_object_agg(q.why, q.n), '{}'::jsonb) from (select j.paused_reason as why, count(*) as n from public.fleet_jobs j where j.paused_reason is not null group by 1) q) as jobs_stopped,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.departed_at >= now() - interval '30 minutes') as departures_30m,
       (select jsonb_build_object('n', count(*), 'avg_ms', round(avg(b.ms)::numeric, 1), 'errors', count(*) filter (where b.error is not null))
          from public.arrivals_beats b where b.at >= now() - interval '30 minutes') as beats;
