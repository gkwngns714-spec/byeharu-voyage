-- A FLEET THAT GROWS TO FIVE SHIPS (0485), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, with the gate's
-- three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/ship-roles/after-0485.sql
-- Expect, AS DEPLOYED (dark): head 20260818000485; `knobs.ship_roles_enabled` false and 6 knobs; `hunked` 4 (each hunked body holds its
-- new line once); `stable` true (the thirteen reads); `client_reach` false (no core reachable by a client; cmd.set_ship_role for
-- authenticated); `tagged` {} (no hull has a role).
-- LIT (30 minutes after the owner lights ship_roles_enabled): `tagged` the roles set and by how many companies; `companies_with_slot` who
-- can set one; `ship_base_ms` 200 calls on the newest company hulls (tagged ones first); `raids_30m` the RAID battles opened in 30
-- minutes, and those on a fleet with a guard (a guard is struck only within half the reach: fewer, not none); the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, the beat's mean over 2,000 ms, or `ship_base_ms` over ten times the before's:
-- ship_roles_enabled false (owner): every factor is 1, no guard is read, the board as before; the tags stay, inert.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, ships (role not null, and five hulls),
-- players, battles (RAID opened in 30 minutes), battle_sides. Functions called: public.ship_base (STABLE). No function that writes is
-- called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with hulls as materialized (
  select s.id from public.ships s join public.players pl on pl.id = s.player_id where not pl.is_npc order by s.role nulls last, s.created_at desc limit 5
), t0 as materialized (
  select clock_timestamp() as t
), sb as materialized (
  select count(*) as n, clock_timestamp() as t
    from t0 cross join generate_series(1, 40) g cross join hulls h cross join lateral public.ship_base(h.id) b
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'ship\_roles\_%'),
  'hunked', (select count(*) from (values
               ('public.ship_base(uuid)', 'public.ship_role_mult(s.role)'),
               ('public.raid_target(uuid,timestamp with time zone)', 'public.ship_role_guard(r.id)'),
               ('public.hq_board_for(uuid)', 'public.ship_role_moves(p_player)'),
               ('public.client_rpc_entry_points()', '''set_ship_role''')) h(fn, line)
              where position(h.line in pg_get_functiondef(h.fn::regprocedure)) > 0),
  'stable', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where ((n.nspname = 'public' and (p.proname like 'ship\_role\_%' or p.proname in ('ship_roles_on', 'ship_roles_build_below')))
                     or (n.nspname = 'world' and p.proname = 'ship_roles'))
                and p.provolatile = 's') = 13,
  'client_reach', exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and (p.proname like 'ship\_role\_%' or p.proname in ('ship_roles_on', 'ship_roles_build_below'))
                             and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                                  or has_function_privilege('service_role', p.oid, 'execute')))
                  or has_function_privilege('anon', 'cmd.set_ship_role(uuid,text)', 'execute') or has_function_privilege('anon', 'world.ship_roles()', 'execute')
                  or not has_function_privilege('authenticated', 'cmd.set_ship_role(uuid,text)', 'execute'),
  'tagged', (select coalesce(jsonb_object_agg(x.role, jsonb_build_object('hulls', x.n, 'companies', x.c)), '{}'::jsonb)
               from (select s.role, count(*) as n, count(distinct s.player_id) as c from public.ships s where s.role is not null group by s.role) x),
  'companies_with_slot', (select count(*) from (select s.player_id from public.ships s join public.players pl on pl.id = s.player_id
                                                  where not pl.is_npc group by s.player_id having count(*) >= 3) x),
  'ship_base_ms', (select round(extract(epoch from sb.t - t0.t) * 1000, 2) from sb, t0),
  'raids_30m', jsonb_build_object(
    'opened', (select count(*) from public.battles b where b.kind = 'RAID' and b.started_at > now() - interval '30 minutes'),
    'on_guarded', (select count(distinct b.id) from public.battles b join public.battle_sides bs on bs.battle_id = b.id
                    where b.kind = 'RAID' and b.started_at > now() - interval '30 minutes'
                      and exists (select 1 from public.ships s where s.fleet_id = bs.fleet_id and s.role = 'guard')))
) as r;
rollback;
