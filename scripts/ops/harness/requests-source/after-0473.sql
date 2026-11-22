-- REQUESTS SAY WHERE TO BUY, YOUR WEEK LIVE (0473), AFTER. A PROD CHECK: read-only, ONE statement, small. Read the gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/requests-source/after-0473.sql
-- Run it once right after the deploy (the backfill: every open hold job has a source) and once 30 minutes later (the jobs posted since are
-- within reach). Reads: world_config, the open hold jobs (about 500 rows), the poster's sea_reaches row (one jsonb lookup a job), the history
-- mark, and for the companies with a login (about 5) their history_company_day this week and their ledger since the mark by
-- ledger_player_created (the live figure's own range). Only stable / immutable functions (now, world.game_day, public.clock_start,
-- public.history_bucket, public.ledger_is_earning). No name, no address.
begin transaction read only;
with k as (
  select (select (value #>> '{}')::numeric from public.world_config where key = 'time_compression') as tc,
         (select (value #>> '{}')::numeric from public.world_config where key = 'hold_request_speed_kn') as kn,
         (select (value #>> '{}')::numeric from public.world_config where key = 'hold_request_trip_share') as share
), j as (
  select t.id, t.posted_day, t.source_port_id,
         (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = t.port_id and sp.id = t.source_port_id) as nm,
         extract(epoch from public.clock_start('game_day', t.expires_day) - now()) as left_s,
         t.created_at > now() - interval '25 minutes' as recent
    from public.trade_contracts t
   where t.status = 'open' and t.size = 'hold'
), s as (
  select j.*, j.nm / k.kn * 3600 / k.tc as sail_s, k.share from j, k
), me as (
  select p.id from public.players p where not p.is_npc and exists (select 1 from auth.users u where u.id = p.auth_uid)
), wk as (
  select public.history_bucket((now() at time zone 'UTC')::date, 'week') as w, (select m.ledger_through from public.history_mark m) as mark
)
select jsonb_build_object(
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('hold_requests_enabled', 'houses_board_enabled', 'hold_request_speed_kn', 'hold_request_trip_share', 'time_compression', 'game_day_seconds')),
  'source_col', (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'trade_contracts' and c.column_name = 'source_port_id'),   -- want 1
  'open_hold', (select count(*) from s),
  'no_source', (select count(*) from s where s.source_port_id is null),                                                   -- want 0 (a good no harbour sells: none)
  'sail_minutes', (select jsonb_build_object('p50', round((percentile_cont(0.5) within group (order by s.sail_s) / 60)::numeric, 1),
                                             'p90', round((percentile_cont(0.9) within group (order by s.sail_s) / 60)::numeric, 1),
                                             'max', round(max(s.sail_s) / 60, 1)) from s),
  -- posted in the last 25 minutes (by 0473's writer): want 0 out of reach (there and back over share x the time it had when posted; now is later, so this is loose)
  'recent', (select jsonb_build_object('n', count(*), 'out_of_reach_now', count(*) filter (where 2 * s.sail_s > s.share * (s.left_s + 1500))) from s where s.recent),
  'week_live_cost', (select jsonb_build_object('companies', count(*), 'max_ledger_rows_after_mark', max(x.led), 'mean_ledger_rows_after_mark', round(avg(x.led), 1),
                                               'max_history_rows_this_week', max(x.hist), 'mark_age_s', (select round(extract(epoch from now() - wk.mark)) from wk))
                       from (select me.id,
                                    (select count(*) from public.ledger l, wk where l.player_id = me.id and l.created_at > greatest(wk.mark, wk.w::timestamp at time zone 'UTC')
                                        and public.ledger_is_earning(l.kind)) as led,
                                    (select count(*) from public.history_company_day h, wk where h.player_id = me.id and h.day >= wk.w and h.day < wk.w + 7) as hist
                               from me) x),
  'head', (select max(version) from supabase_migrations.schema_migrations));                                             -- want 20260818000473
rollback;
