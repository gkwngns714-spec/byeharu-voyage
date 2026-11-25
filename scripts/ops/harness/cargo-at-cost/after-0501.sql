-- 0501 CARGO AT COST, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-at-cost/after-0501.sql
-- Expect, AS DEPLOYED (dark): head 20260818000501; switch false; since = the deploy's instant; new_fns 2, client_reach false, stable 2;
--   bodies = the chain's world at 0501: settle 1809e424046a2dfb321f8345659702cd, forced_home 99e30283333001752a30dc5a664ee93e,
--   navy_meets 96e74ac773b2508071c35a64537aadaf, company_rate_for 1891ecfda6170d9a434166e253ea2df3;
--   untouched = the before read's three digests, unmoved (the loss itself is the same statements).
--   days_with_loss: of the days resolved since the deploy that lost cargo, every one carries cargo_lost_cost (rows = with_cost_key),
--   none of them negative; days before the deploy carry none.
--   rate (put a company's name in place of the text between the quotes): dark, no `cargo` key and all lines summing to all_24h.
-- LIT (read 30 minutes after the owner lights cargo_at_cost_enabled): rate.cargo is present; sums_hold true (the running lines sum
--   to net_24h, and net_24h + one_time_24h + cargo.net_24h = all_24h); cargo.exact false until 24 hours after `since`.
-- ROLLBACK if client_reach is true, a body digest differs, a day since the deploy that lost cargo lacks the key or has it negative,
--   sums_hold is false, or the gate goes red: QUICK, cargo_at_cost_enabled false (owner; the rate is 0493's again). Full (forward): a
--   migration reversing the thirteen hunks.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, voyage_events of the last
--   24 hours, one players row by name, that company's rate (public.company_rate_for: STABLE, writes nothing). No function that
--   writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with me as (
  select p.id from public.players p where p.company_name = 'PUT THE COMPANY NAME HERE' and not p.is_npc limit 1
), r as (
  select public.company_rate_for(me.id) as rate from me
), k as (
  select (c.value #>> '{}')::timestamptz as since from public.world_config c where c.key = 'cargo_at_cost_since'
)
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'cargo_at_cost_enabled'),
  'since', (select k.since from k),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('cargo_at_cost_on', 'cargo_rate_for')),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('cargo_at_cost_on', 'cargo_rate_for')),
  'stable', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('cargo_at_cost_on', 'cargo_rate_for') and p.provolatile = 's'),
  'bodies', json_build_object(
    'settle', md5(replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '')),
    'forced_home', md5(replace(pg_get_functiondef('voyage.forced_home(uuid,integer,uuid)'::regprocedure), E'\r', '')),
    'navy_meets', md5(replace(pg_get_functiondef('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)'::regprocedure), E'\r', '')),
    'company_rate_for', md5(replace(pg_get_functiondef('public.company_rate_for(uuid)'::regprocedure), E'\r', ''))),
  'untouched', json_build_object(
    'lose_hold', md5(replace(pg_get_functiondef('voyage.lose_hold(uuid)'::regprocedure), E'\r', '')),
    'raid_takes', md5(replace(pg_get_functiondef('voyage.raid_takes(uuid,integer,uuid,text)'::regprocedure), E'\r', '')),
    'fleet_unload', md5(replace(pg_get_functiondef('public.fleet_unload(uuid,text,numeric)'::regprocedure), E'\r', ''))),
  'days_with_loss', (select json_build_object(
                              'since_deploy', count(*) filter (where ve.resolved_at >= k.since),
                              'since_deploy_with_cost_key', count(*) filter (where ve.resolved_at >= k.since and ve.payload ? 'cargo_lost_cost'),
                              'negative', count(*) filter (where (ve.payload->>'cargo_lost_cost')::numeric < 0),
                              'before_deploy_with_cost_key', count(*) filter (where ve.resolved_at < k.since and ve.payload ? 'cargo_lost_cost'),
                              'by_kind', (select coalesce(json_object_agg(x.kind, x.n), '{}'::json)
                                            from (select v2.kind, count(*) as n from public.voyage_events v2
                                                   where v2.resolved_at > now() - interval '24 hours' and v2.payload ? 'cargo_lost_cost' group by v2.kind) x))
                       from public.voyage_events ve cross join k
                      where ve.resolved_at > now() - interval '24 hours' and ve.payload ? 'cargo_lost'),
  'rate', (select r.rate from r),
  'sums_hold', (select (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(r.rate->'lines') e where not (e->>'one_time')::boolean) = (r.rate->>'net_24h')::numeric
                   and (r.rate->>'net_24h')::numeric + (r.rate->>'one_time_24h')::numeric + coalesce((r.rate #>> '{cargo,net_24h}')::numeric, 0)
                       = (r.rate->>'all_24h')::numeric
                  from r)
);
rollback;
