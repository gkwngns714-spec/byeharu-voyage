-- 0497 A WRECK CAN SELL, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/a-wreck-can-sell/before-0497.sql
-- Expect: head 20260818000496; switch null (no row yet); new_fns 0; hunked 7 (the seven bodies 0497 hunks are there); old_gates 3 (the
--   three cargo doors still ask `status <> 'DOCKED'` themselves). `wrecks`: every player's fleet that is UNABLE_TO_SAIL today, with
--   where she lies, whether that port has a yard, her purse, her cargo (each ship's, as stored) and her waiting orders: the companies this is for.
--   `founding`: the migration's probe founds a company at Lisbon (public.new_house), as every probe does: with economy_closed true
--   and Lisbon's purse under 40,000 that founding is refused (E_NO_NEW_GOLD) and the push fails with nothing applied.
-- Reads: port_treasury (Lisbon's row), arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, the UNABLE_TO_SAIL fleets (a
--   handful) with their ships, port, player and orders by key. No function that writes is called. Nothing to roll back.
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
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('cmd', 'do_sell'), ('cmd', 'do_store'), ('cmd', 'do_take'), ('public', 'quay_shows'), ('cmd', 'advance'), ('cmd', 'preview'), ('cmd', 'issue'))),
  'old_gates', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'cmd' and p.proname in ('do_sell', 'do_store', 'do_take') and p.prosrc like '%if f.status <> ''DOCKED'' then%'),
  'founding', json_build_object('economy_closed', (select c.value from public.world_config c where c.key = 'economy_closed'),
                                'lisbon_purse', (select t.ducats from public.port_treasury t join public.ports p on p.id = t.port_id where p.code = 'LIS')),
  'wrecks', (select coalesce(json_agg(json_build_object(
               'fleet', f.name, 'port', (select p.code from public.ports p where p.id = f.port_id),
               'yard_here', (select public.port_has_shipyard(f.port_id)), 'ships', (select count(*) from public.ships s where s.fleet_id = f.id),
               'purse', pl.ducats, 'cargo', (select json_agg(s.cargo) from public.ships s where s.fleet_id = f.id),
               'waiting', (select json_agg(o.raw_text order by o.seq) from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')))), '[]'::json)
               from public.fleets f join public.players pl on pl.id = f.player_id
              where f.status = 'UNABLE_TO_SAIL' and not pl.is_npc)
);
rollback;
