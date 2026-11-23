-- A FLEET THAT GROWS TO FIVE SHIPS (0485), BEFORE. A PROD CHECK: read-only, ONE statement. It carries the gate's own three figures (the
-- arrivals beat's mean over 5 minutes, the database by the catalog, the sessions waiting on the disk), so it is the builder's one prod read.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/ship-roles/before-0485.sql
-- Expect: head 20260818000484; `knobs` {} (no ship_roles_*); `absent` true (no public.ships.role, no public.ship_role* function, no
-- cmd.set_ship_role, no world.ship_roles); `anchors` n 1 for each of the eight hunks and `new_absent` true (each hunk's anchor once in
-- prod's live body, its new text nowhere); `bodies` the md5 of the four hunked bodies.
-- THE PROBE'S SELECTIONS, as the self-assert makes them: `probe.lis` Lisbon a harbour, `probe.barca` the class, `probe.armadas` the armada
-- tables: none may be false.
-- THE WORLD THE ROLES SEE: `companies_by_ships` her hulls (1, 2, 3, 4, 5+: who would have a slot when lit); `room` the knobs that cap her
-- hulls (a fleet's hulls and her fleets: five hulls need the room); `raids` the switch and reach raid_target reads, and the RAID battles
-- kept now with a company's fleet on a side (what the pick's `raids` counts).
-- THE COST IT WOULD ADD (all STABLE reads): `ship_base_ms` 200 calls of public.ship_base on the newest company hulls (the body the hunk
-- touches: a null role adds nothing); `raid_target_ms` one raid_target for a pirate ship (the pirates' job asks it at most 8 a minute;
-- lit, a guard adds one indexed probe a candidate).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog (pg_proc, information_schema.columns),
-- ports, ship_classes, ships of the companies, players, fleets, battles (RAID, kept 48 h), battle_sides, pirate_ships (one row). Functions
-- called: public.ship_base and public.raid_target (both STABLE). No function that writes is called. ROLLBACK: nothing to roll back (read
-- only; ends with rollback).
begin transaction read only;
with bodies as materialized (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as d, f.anchor, f.added
    from (values
      ('public.ship_base(uuid)', '  select floor(c.hold       * s.roll_hold),' || E'\n' || '         round(c.speed_kn   * s.roll_speed, 2),', 'ship_role_mult'),
      ('public.raid_target(uuid,timestamp with time zone)', '  v_w     numeric := coalesce(public.wc_num(''raid_company_weight''), 1);                        -- 0464: lit, a company''s miles are weighed by this', 'v_roles'),
      ('public.raid_target(uuid,timestamp with time zone)', '              c.nm * case when v_lit and public.fleet_kind(c.id) = ''COMPANY'' then v_w else 1 end, c.id', 'ship_role_guard'),
      ('public.raid_target(uuid,timestamp with time zone)', '    if v_nm <= v_reach then', 'ship_role_guard(r.id)'),
      ('public.hq_board_for(uuid)', '  v_moves := v_moves || public.courier_moves(p_player, v_purse);', 'ship_role_moves'),
      ('public.hq_board_for(uuid)', '     and (select count(*) from public.ships sh where sh.player_id = p_player) < coalesce(public.wc_int(''hq_board_build_below''), 2)', 'ship_roles_build_below'),
      ('public.hq_board_for(uuid)', '      v_moves := v_moves || jsonb_build_array(v_best);', 'ship_role_yard'),
      ('public.client_rpc_entry_points()', '      (''world'',       ''nation_race'',           ''''),', 'set_ship_role')) f(fn, anchor, added)
), hulls as materialized (
  select s.id from public.ships s join public.players pl on pl.id = s.player_id where not pl.is_npc order by s.created_at desc limit 5
), t0 as materialized (
  select clock_timestamp() as t
), sb as materialized (
  select count(*) as n, clock_timestamp() as t
    from t0 cross join generate_series(1, 40) g cross join hulls h cross join lateral public.ship_base(h.id) b
), pir as materialized (
  select n.fleet_id from public.pirate_ships n order by n.fleet_id limit 1
), t1 as materialized (
  select clock_timestamp() as t from sb
), rt as materialized (
  select public.raid_target(p.fleet_id, now()) as target, clock_timestamp() as t from t1, pir p
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'beats', (select count(*) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'ship\_roles\_%'),
  'absent', not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'ships' and c.column_name = 'role')
            and to_regprocedure('world.ship_roles()') is null and to_regprocedure('cmd.set_ship_role(uuid,text)') is null
            and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'ship\_role%'),
  'anchors', (select jsonb_agg(jsonb_build_object('fn', b.fn, 'n', (length(b.d) - length(replace(b.d, b.anchor, ''))) / length(b.anchor))) from bodies b),
  'new_absent', (select bool_and(position(b.added in b.d) = 0) from bodies b),
  'bodies', (select jsonb_object_agg(x.fn, md5(x.d)) from (select distinct b.fn, b.d from bodies b) x),
  'probe', jsonb_build_object('lis', exists (select 1 from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR'),
                              'barca', exists (select 1 from public.ship_classes c where c.code = 'barca'),
                              'armadas', to_regclass('public.armadas') is not null and to_regclass('public.armada_fleets') is not null),
  'companies_by_ships', (select jsonb_object_agg(x.k, x.n) from (select case when y.n >= 5 then '5+' else y.n::text end as k, count(*) as n
                                                                   from (select pl.id, count(s.id) as n from public.players pl
                                                                           left join public.ships s on s.player_id = pl.id
                                                                          where not pl.is_npc group by pl.id) y group by 1) x),
  'room', (select jsonb_object_agg(c.key, c.value) from public.world_config c
            where c.key in ('fleet_room_bite', 'fleet_max', 'fleet_ship_max', 'fleet_ship_base', 'fleet_ship_top', 'fleet_hard_max', 'hq_board_build_below', 'yard_order_enabled')),
  'raids', jsonb_build_object(
    'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c
                  where c.key in ('raid_companies_enabled', 'raid_company_title_min', 'raid_company_weight', 'attack_reach_nm', 'pirate_strike_tries_per_run')),
    'kept', (select count(*) from public.battles b where b.kind = 'RAID'),
    'with_company', (select count(distinct b.id) from public.battles b join public.battle_sides bs on bs.battle_id = b.id
                       join public.fleets f on f.id = bs.fleet_id join public.players pl on pl.id = f.player_id
                      where b.kind = 'RAID' and not pl.is_npc)),
  'ship_base_ms', (select round(extract(epoch from sb.t - t0.t) * 1000, 2) from sb, t0),
  'ship_base_calls', (select sb.n from sb),
  'raid_target_ms', (select round(extract(epoch from rt.t - t1.t) * 1000, 2) from rt, t1),
  'raid_target_found', (select rt.target is not null from rt)
) as r;
rollback;
