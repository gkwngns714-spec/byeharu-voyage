-- PROD CHECK (read only) before 0466 (requests a ship can carry): the five bodies are the chain's at 0464: each OLD text of 0466's eight hunks
-- once, the marker 0 times; no 0466 knob, no trade_contracts.size column; and THE MEASURE before: open requests (count, mean units), deliveries
-- by a company in 48 h, and the wind job's last hour (mean and worst ms). Calls no function but pg_proc reads. One statement.
begin transaction read only;
with b(fn, s) as (
       select f, replace(p.prosrc, E'\r', '') from (values ('public.tick_contracts(uuid,timestamp with time zone)'), ('public.tick_contract_wind(boolean,uuid)'),
         ('world.contracts(uuid)'), ('public.contract_asks(uuid)'), ('public.contracts_expire(uuid,timestamp with time zone)')) v(f)
       join pg_proc p on p.oid = to_regprocedure(v.f)),
     h(k, fn, t) as (values
       ('tc1', 'public.tick_contracts(uuid,timestamp with time zone)', $h$  if (select count(*) from public.trade_contracts where port_id = p_port and status = 'open') >= v_max then$h$),
       ('tw1', 'public.tick_contract_wind(boolean,uuid)', $h$  v_note   text;$h$),
       ('tw2', 'public.tick_contract_wind(boolean,uuid)', $h$     cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open') o$h$),
       ('tw3', 'public.tick_contract_wind(boolean,uuid)', $h$  delete from public.contract_deliveries d where d.at < now() - interval '2 days';$h$),
       ('tw4', 'public.tick_contract_wind(boolean,uuid)', $h$'posted', v_posted, 'failed', v_failed, 'note', v_note))$h$),
       ('wc1', 'world.contracts(uuid)', $h$  perform public.tick_contracts(p_port, now());$h$),
       ('wc2', 'world.contracts(uuid)', $h$        'premium_ducats', c.premium_ducats,$h$),
       ('ca1', 'public.contract_asks(uuid)', $h$     and c.premium_per_unit > 0 and c.premium_ducats >= c.premium_per_unit$h$),
       ('ce1', 'public.contracts_expire(uuid,timestamp with time zone)', $h$   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;$h$))
select (select jsonb_object_agg(h.k, (length(b.s) - length(replace(b.s, h.t, ''))) / length(h.t)) from h join b on b.fn = h.fn) as hunks,   -- want every one 1
       (select count(*) from b where b.s like '%0466%') as marked,                                                                          -- want 0
       (select count(*) from b) as bodies,                                                                                                  -- want 5
       (select count(*) from public.world_config w where w.key like 'hold_request%') as knobs,                                              -- want 0
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'trade_contracts' and c.column_name = 'size') as size_col,   -- want 0
       (select jsonb_build_object('rows', count(*), 'open', count(*) filter (where t.status = 'open'), 'open_mean_units', round(avg(floor(t.premium_ducats / t.premium_per_unit)) filter (where t.status = 'open')))
          from public.trade_contracts t) as requests,
       (select count(*) from public.contract_deliveries d join public.players p on p.id = d.player_id where not p.is_npc and d.at > now() - interval '48 hours') as company_deliveries_48h,   -- 0 so far
       (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(r.ms)), 'max_ms', max(r.ms)) from public.contract_wind_runs r where r.at > now() - interval '1 hour') as wind_1h,
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- want 20260818000464 or 20260818000465
commit;
