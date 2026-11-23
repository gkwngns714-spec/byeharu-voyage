-- THE LOGBOOK (0478), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/logbook/after-0478.sql
-- `since` below is the last 30 minutes: read it 30 minutes after the deploy (as deployed) or after the owner lights logbook_enabled.
-- Expect, AS DEPLOYED (dark): head 20260818000478; knobs logbook_enabled false, logbook_set_rep 100, logbook_region_fee_cut 0.25,
-- logbook_kind_fee_cut 0.02; `kind` true; `registered` true; `client_reach` false; `hunked` all true (each of the four bodies carries its
-- 0478 line); `rows` the back-fill only (before-0478's read: harbour 66, good 19, hull 21, captain 1), no region / kind; `merchant_rows` 0;
-- `told` {} (no event carries a logbook word while dark); `paid` 0.
-- LIT (read 30 minutes after lighting): `rows` grows by firsts only; `sets` the finished sets (region / kind rows) and `paid` their
-- Reputation (logbook_set_rep each, once: `paid` = 100 x `sets` while the knob is 100); `told` the VOYAGE_REPORT / SOLD events of the
-- window that carry a logbook word (`found` Discovered moments, `new_goods` first sales); `fee_cut` companies whose dock fee a set cuts.
-- ROLLBACK if `merchant_rows` > 0, `paid` <> 100 x `sets`, `client_reach` true, or the gate goes red: logbook_enabled false (owner).
-- Reads: world_config by key, the catalog (registry, four bodies, privileges), reputation_kinds, public.logbook (small: ~1,200 rows a
-- company at most, companies only), reputation_book by kind for the companies, their events of the window by the (player_id,
-- created_at) index. No function that writes is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
hu as (select p.id from public.players p where not p.is_npc),
lb as (select l.player_id, l.kind from public.logbook l),
ev as (select e.kind, e.payload from hu cross join lateral (select x.kind, x.payload from public.events x
                                                             where x.player_id = hu.id and x.created_at > (select t from since)
                                                               and x.kind in ('VOYAGE_REPORT', 'SOLD')) e)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'logbook\_%'),
  'kind', exists (select 1 from public.reputation_kinds k where k.code = 'logbook'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e
                         where e.schema_name = 'world' and e.function_name = 'logbook' and e.fn is not null),
  'client_reach', has_table_privilege('authenticated', 'public.logbook', 'select')
                  or has_function_privilege('authenticated', 'public.logbook_arrival(uuid,uuid,uuid,timestamp with time zone)', 'execute')
                  or has_function_privilege('authenticated', 'public.logbook_sale(uuid,uuid)', 'execute')
                  or has_function_privilege('authenticated', 'public.logbook_sets_settle(uuid,timestamp with time zone)', 'execute'),
  'hunked', jsonb_build_object(
    'settle', position('logbook_arrival' in pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure)) > 0,
    'do_sell', position('logbook_sale' in pg_get_functiondef('cmd.do_sell(uuid,jsonb)'::regprocedure)) > 0,
    'port_fee', position('logbook_fee_factor' in pg_get_functiondef('public.port_fee(uuid,uuid,numeric)'::regprocedure)) > 0,
    'registry', position('''logbook''' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0),
  'rows', (select coalesce(jsonb_object_agg(s.kind, s.n), '{}'::jsonb) from (select lb.kind, count(*) as n from lb group by lb.kind) s),
  'companies', (select count(distinct lb.player_id) from lb),
  'merchant_rows', (select count(*) from public.logbook l join public.players p on p.id = l.player_id where p.is_npc),
  'sets', (select count(*) from lb where lb.kind in ('region', 'kind')),
  'paid', (select coalesce(sum(b.delta), 0) from hu join public.reputation_book b on b.player_id = hu.id and b.kind = 'logbook'),
  'fee_cut', (select count(distinct lb.player_id) from lb where lb.kind in ('region', 'kind')),
  'told', jsonb_build_object(
    'found', (select count(*) from ev where ev.kind = 'VOYAGE_REPORT' and ev.payload #> '{logbook,found}' is not null),
    'arrival_sets', (select count(*) from ev where ev.kind = 'VOYAGE_REPORT' and ev.payload #> '{logbook,sets}' is not null),
    'new_goods', (select count(*) from ev where ev.kind = 'SOLD' and ev.payload ? 'logbook'),
    'arrivals', (select count(*) from ev where ev.kind = 'VOYAGE_REPORT'),
    'sales', (select count(*) from ev where ev.kind = 'SOLD')));
rollback;
