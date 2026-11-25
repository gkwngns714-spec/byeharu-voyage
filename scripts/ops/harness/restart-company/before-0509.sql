-- 0509 A COMPANY IS RESTARTED, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/restart-company/before-0509.sql
-- Expect: head the version before 0509; new_fns 0; tables 0; hunked 11; companies = with_capital + by_founding + with_neither.
--   HOW MANY COMPANIES HAVE NO HQ: all of them (there is no HQ on record before 0509): `companies`. `would_get` is what each kind gets:
--   country, city, rule, how many. `moves_home`: companies whose capital is NOT their founding port (a changed country): HQ shows the
--   capital; their home (shed, requests, land) stays the founding port until hq_cities_enabled is lit. READ THAT FIGURE BEFORE LIGHTING IT.
--   `fulfilled_old`: rows of trade_contracts a restart could turn to 'spent'. `voyages_rows`: the planner's count (a restart's cascade
--   scans voyages once a fleet). No company's or account's name is printed. No function that writes is called (home_port_of is STABLE).
-- ROLLBACK: nothing to roll back.
begin transaction read only;
with c as (
  select p.id, n.code as nation, cap.code as capital, cap.id as cap_id, public.home_port_of(p.id) as founding
    from public.players p left join public.nations n on n.id = p.nation_id
    left join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR'
   where not p.is_npc)
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
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in
     (('public', 'new_house'), ('world', 'player'), ('public', 'home_port_of'), ('public', 'settle_standings'), ('world', 'stats_me'), ('world', 'town_hall'), ('world', 'city_history'), ('public', 'town_hall_gifts'), ('public', 'flow_is_profit'), ('public', 'ledger_is_earning'), ('public', 'client_rpc_entry_points'))),
  'companies', (select count(*) from c),
  'with_capital', (select count(*) from c where c.cap_id is not null),
  'by_founding', (select count(*) from c where c.cap_id is null and c.founding is not null),
  'with_neither', (select count(*) from c where c.cap_id is null and c.founding is null),
  'moves_home', (select count(*) from c where c.cap_id is not null and c.founding is distinct from c.cap_id),
  'would_get', (select json_agg(g) from (select c.nation, coalesce(c.capital, (select p.code from public.ports p where p.id = c.founding)) as city,
                   case when c.cap_id is not null then 'capital' when c.founding is not null then 'founding port' else 'none' end as rule, count(*) as companies
                   from c group by 1, 2, 3 order by 4 desc, 1) g),
  'fulfilled_old', (select count(*) from public.trade_contracts t where t.status = 'fulfilled'),
  'voyages_rows', (select k.reltuples::bigint from pg_class k where k.oid = 'public.voyages'::regclass)
);
rollback;
