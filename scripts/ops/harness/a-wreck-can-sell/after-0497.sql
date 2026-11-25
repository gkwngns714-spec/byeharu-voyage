-- 0497 A WRECK CAN SELL, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/a-wreck-can-sell/after-0497.sql
-- Expect: head 20260818000497; switch false (DARK: nothing changes for a player); new_fns 4; reach false (no new function callable by
--   anon, authenticated or service_role); old_gates 0 and one_gate 3 (the three cargo doors ask public.fleet_alongside).
-- LIT LATER (the owner's switch, never thrown here): `wrecks` lists each player's UNABLE_TO_SAIL fleet with `alongside` (true where
--   she lies in a port with a ship) and her waiting orders: after her next press her SELL / STORE / TAKE rows are gone from
--   `waiting` and her SAILs are still there; `sold_15m` counts the SELL orders such fleets ran in the last 15 minutes.
-- ROLLBACK (forward, owner only): wreck_sells_enabled false; or a migration reversing the eight hunks and dropping the four functions.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, the UNABLE_TO_SAIL fleets (a
--   handful) with their ships, port, player and orders by key. public.fleet_alongside is STABLE. Nothing to roll back.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'wreck_sells_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'wreck_sells_on'), ('public', 'fleet_alongside'), ('public', 'wreck_may'), ('public', 'wreck_order_refusal'))),
  'reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                    or has_function_privilege('service_role', p.oid, 'execute')), false)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'wreck_sells_on'), ('public', 'fleet_alongside'), ('public', 'wreck_may'), ('public', 'wreck_order_refusal'))),
  'old_gates', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'cmd' and p.proname in ('do_sell', 'do_store', 'do_take') and p.prosrc like '%if f.status <> ''DOCKED'' then%'),
  'one_gate', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'cmd' and p.proname in ('do_sell', 'do_store', 'do_take') and p.prosrc like '%if not public.fleet_alongside(p_fleet) then%'),
  'wrecks', (select coalesce(json_agg(json_build_object(
               'fleet', f.name, 'port', (select p.code from public.ports p where p.id = f.port_id), 'alongside', public.fleet_alongside(f.id),
               'purse', pl.ducats, 'cargo', (select json_agg(s.cargo) from public.ships s where s.fleet_id = f.id),
               'waiting', (select json_agg(o.raw_text order by o.seq) from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')))), '[]'::json)
               from public.fleets f join public.players pl on pl.id = f.player_id
              where f.status = 'UNABLE_TO_SAIL' and not pl.is_npc),
  'sold_15m', (select count(*) from public.fleets f join public.players pl on pl.id = f.player_id join public.orders o on o.fleet_id = f.id
                where f.status = 'UNABLE_TO_SAIL' and not pl.is_npc and o.verb = 'SELL' and o.status = 'done' and o.executed_at > now() - interval '15 minutes')
);
rollback;
