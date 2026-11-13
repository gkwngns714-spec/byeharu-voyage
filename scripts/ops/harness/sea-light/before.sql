-- 0398 PROD CHECK (before lighting sea_conditions_bite), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before.sql
-- Run volatility.sql first (public.sea_conditions_ready must read 's'). THE GUARDS OF THE STEP, as it will judge them, and the baseline of the window.
-- Wanted before the light: guards.ready true. That is: lit false, wall_reads_in true (0396 deployed), fleet_room true (fleet_room_bite lit first),
-- route_legs_closed 0. capitals_closed is TOLD, not a guard (home waters, 0396: prod read 1 on 2026-11-14, a company of Japan). HEAD IT MEETS: 20260818000397. fleets_in_closed_seas is TOLD, not a guard (the way home, 0396, carries them:
-- prod read 1 on 2026-11-13, Casa Estaleiro at Acapulco). queued_sails_closed is told, not a guard: each such SAIL fails with its reason when it runs.
-- Not ready: do NOT light; the step would refuse anyway, naming the same figures. scripts/ops/harness/sea-conditions/impact.sql says which company and why.
-- The baseline: failed orders by code over the last hour (a plan refused at the press is written nowhere and is not in it), departures over the last hour, the arrivals beat over the last 30 minutes (after-check.sql reads the same).
begin transaction read only;
select now() as read_at,
       (select max(version) from supabase_migrations.schema_migrations) as head,
       public.sea_conditions_ready() as guards,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as switch_merchants,
       (select coalesce(jsonb_object_agg(q.code, q.n), '{}'::jsonb)
          from (select o.error_code as code, count(*) as n from public.orders o join public.players p on p.id = o.player_id and not p.is_npc
                 where o.status = 'failed' and o.issued_at >= now() - interval '1 hour' group by o.error_code) q) as refusals_1h,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.departed_at >= now() - interval '1 hour') as departures_1h,
       (select jsonb_build_object('n', count(*), 'avg_ms', round(avg(b.ms)::numeric, 1), 'p95_ms', round((percentile_cont(0.95) within group (order by b.ms))::numeric, 1),
                                  'errors', count(*) filter (where b.error is not null))
          from public.arrivals_beats b where b.at >= now() - interval '30 minutes') as beats;
commit;
