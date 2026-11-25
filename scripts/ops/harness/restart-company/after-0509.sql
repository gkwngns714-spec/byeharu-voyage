-- 0509 A COMPANY IS RESTARTED, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/restart-company/after-0509.sql
-- Expect: head 20260818000509; new_fns 9; tables 3; switches {restart_enabled false, hq_cities_enabled false}; door true, reach false;
--   companies = hq_rows + before's with_neither; wrong_hq 0; merchant_hq 0; steps 5; closed 0 (until the owner lights the switch and a
--   player presses); still_holding 0 ALWAYS (a closed company with a purse, a fleet, a share, an open contract or request, an account or a
--   country); not_settled 0 ALWAYS (a closed company whose ledger does not close at 0).
-- ROLLBACK (forward, owner only): restart_enabled false; a migration reversing the hunks.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c2.relpages)::numeric * 8192 / 1048576)::int from pg_class c2 where c2.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in
     (('public', 'restart_on'), ('public', 'hq_cities_on'), ('public', 'nation_in_europe'), ('public', 'hq_card'), ('public', 'company_heir'), ('public', 'restart_refusal'), ('public', 'restart_card'), ('public', 'company_retire'), ('cmd', 'restart_company'))),
  'tables', (select count(*) from pg_class k where k.relnamespace = 'public'::regnamespace and k.relname in ('company_hqs', 'hq_steps', 'company_retirements')),
  'switches', (select json_object_agg(w.key, w.value) from public.world_config w where w.key in ('restart_enabled', 'hq_cities_enabled')),
  'door', has_function_privilege('authenticated', 'cmd.restart_company(text,text,text)', 'execute'),
  'reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')
                                    or (n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute'))), false)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in
     (('public', 'restart_on'), ('public', 'hq_cities_on'), ('public', 'nation_in_europe'), ('public', 'hq_card'), ('public', 'company_heir'), ('public', 'restart_refusal'), ('public', 'restart_card'), ('public', 'company_retire'), ('cmd', 'restart_company'))),
  'companies', (select count(*) from public.players p where not p.is_npc and p.retired_at is null),
  'hq_rows', (select count(*) from public.company_hqs h where h.slot = 1),
  'merchant_hq', (select count(*) from public.company_hqs h join public.players p on p.id = h.player_id where p.is_npc),
  'wrong_hq', (select count(*) from public.company_hqs h left join public.ports q on q.id = h.port_id where h.slot = 1 and q.kind is distinct from 'HARBOUR'),
  'steps', (select count(*) from public.hq_steps),
  'closed', (select count(*) from public.players p where p.retired_at is not null),
  'still_holding', (select count(*) from public.players p where p.retired_at is not null and (p.ducats <> 0 or p.auth_uid is not null or p.nation_id is not null
       or exists (select 1 from public.fleets f where f.player_id = p.id) or exists (select 1 from public.city_shares s where s.player_id = p.id)
       or exists (select 1 from public.market_requests m where m.player_id = p.id and m.status = 'open')
       or exists (select 1 from public.courier_contracts c where p.id in (c.poster_id, c.carrier_id) and c.status in ('open', 'taken')))),
  'not_settled', (select count(*) from public.players p where p.retired_at is not null and (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = p.id) <> 0)
);
rollback;
