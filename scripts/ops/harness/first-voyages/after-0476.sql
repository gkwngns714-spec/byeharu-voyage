-- FIRST VOYAGES (0476), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/first-voyages/after-0476.sql
-- `since` below is the last 30 minutes: read it 30 minutes after the deploy (as deployed) or after the owner lights first_voyages_enabled.
-- Expect, AS DEPLOYED (dark): head 20260818000476; knobs first_voyages_enabled false, first_voyages_days 7, ducats_max 5000,
-- reputation_max 50, job_margin 2, and first_voyages_steps deliver / profit / trading / captain / hull with `steps_ducats` 16000;
-- `registered` true; `client_reach` false (no client reaches the table or a server-only function); `rows` {}; `paid` 0.
-- LIT (read 30 minutes after lighting): `rows` by step (a company is on a step once: the primary key); `paid` the VOYAGE_REWARD coin the
-- paid companies have had; `moved_ok` true (the coin of the window left the cities' purses: no new gold); `rep` their first_voyage
-- Reputation; `companies` how many were paid; `old_paid` 0 (no step is paid to a company over 7 days old); `per_company_max` at most 16,000.
-- ROLLBACK if `old_paid` > 0, `per_company_max` > 16,000, `moved_ok` false, or the gate goes red: first_voyages_enabled false (owner).
-- Reads: world_config by key, the catalog (registry, privileges), public.first_voyages (five rows a company at most), those companies'
-- VOYAGE_REWARD ledger rows and Reputation rows, treasury_flows of the window by kind. No function that writes is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
fv as (select * from public.first_voyages),
pd as (
  select l.player_id, l.ducats_delta, l.created_at from public.ledger l
   where l.kind = 'VOYAGE_REWARD' and l.player_id in (select distinct fv.player_id from fv)
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'first\_voyages\_%'),
  'steps_ducats', (select sum((e ->> 'ducats')::bigint) from public.world_config c cross join lateral jsonb_array_elements(c.value) e
                    where c.key = 'first_voyages_steps'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e
                         where e.schema_name = 'world' and e.function_name = 'first_voyages' and e.fn is not null),
  'client_reach', has_table_privilege('authenticated', 'public.first_voyages', 'select')
                  or has_function_privilege('authenticated', 'public.first_voyage_have(uuid,text)', 'execute')
                  or has_function_privilege('authenticated', 'public.first_voyage_job(uuid)', 'execute'),
  'rows', (select coalesce(jsonb_object_agg(s.code, s.n), '{}'::jsonb) from (select fv.code, count(*) as n from fv group by fv.code) s),
  'rows_since', (select count(*) from fv where fv.done_at > (select t from since)),
  'companies', (select count(distinct fv.player_id) from fv),
  'paid', (select coalesce(sum(pd.ducats_delta), 0) from pd),
  'moved_ok', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f
                where f.kind = 'VOYAGE_REWARD' and f.created_at > (select t from since))
              = -(select coalesce(sum(pd.ducats_delta), 0) from pd where pd.created_at > (select t from since)),
  'rep', (select coalesce(sum(b.delta), 0) from public.reputation_book b
           where b.kind = 'first_voyage' and b.player_id in (select distinct fv.player_id from fv)),
  'old_paid', (select count(*) from fv join public.players p on p.id = fv.player_id where fv.done_at > p.created_at + interval '7 days'),
  'per_company_max', (select coalesce(max(q.s), 0) from (select sum(pd.ducats_delta) as s from pd group by pd.player_id) q));
rollback;
