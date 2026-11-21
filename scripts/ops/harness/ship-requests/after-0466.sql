-- PROD CHECK (read only) after 0466 (requests a ship can carry), dark until the owner lights hold_requests_enabled: the knobs as shipped, the
-- column, the writer server-only; hold rows by status (0 while dark); deliveries of a hold job by a company; the wind job's last hour and its
-- 'hold' receipts (lit: at most hold_request_wind_posts a minute). Lit, run it 30 minutes after lighting. One statement.
begin transaction read only;
select (select jsonb_object_agg(w.key, w.value) from public.world_config w where w.key like 'hold_request%') as knobs,                         -- dark: hold_requests_enabled false
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'trade_contracts' and c.column_name = 'size') as size_col,   -- want 1
       (select has_function_privilege('authenticated', 'public.hold_request_post(uuid,timestamp with time zone)', 'execute')) as player_can_post,   -- want false
       (select jsonb_object_agg(x.status, x.n) from (select t.status, count(*) as n from public.trade_contracts t where t.size = 'hold' group by t.status) x) as hold_rows,   -- dark: null
       (select jsonb_build_object('open_city', count(*) filter (where t.size = 'city'), 'open_hold', count(*) filter (where t.size = 'hold'),
                                  'hold_ports', count(distinct t.port_id) filter (where t.size = 'hold'),
                                  'hold_mean_units', round(avg(t.qty) filter (where t.size = 'hold')), 'hold_escrow', sum(t.escrow) filter (where t.size = 'hold'))
          from public.trade_contracts t where t.status = 'open') as open_now,
       (select count(*) from public.contract_deliveries d join public.trade_contracts t on t.id = d.contract_id join public.players p on p.id = d.player_id
         where t.size = 'hold' and not p.is_npc) as hold_deliveries_by_companies,
       (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(r.ms)), 'max_ms', max(r.ms), 'hold_posted', sum(coalesce((r.receipt ->> 'hold')::int, 0)),
                                  'failed', sum(coalesce((r.receipt ->> 'failed')::int, 0)))
          from public.contract_wind_runs r where r.at > now() - interval '1 hour') as wind_1h,
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- want 20260818000466
commit;
