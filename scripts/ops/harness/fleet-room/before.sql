-- 0321 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/fleet-room/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regclass, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` is 1; room_keys 0; house_room and move_ship null; empty_fleets 0; most_in_fleet at or under 7; fleet_ship_max 8; move_verbs 0.
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.earned_caps(uuid)'::regprocedure, 1, $h$  select case when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
$h$),
  ('public.house_ship_max(uuid)'::regprocedure, 1, $h$  select public.wc_int('ship_max')
$h$),
  ('public.house_ship_max(uuid)'::regprocedure, 2, $h$                else 0 end
$h$),
  ('cmd.enqueue(uuid,jsonb,text,jsonb,uuid)'::regprocedure, 1, $h$  select count(*) into v_depth from public.orders
   where fleet_id = v_fleet and status in ('pending', 'active');
$h$),
  ('public.tow_for(uuid,uuid)'::regprocedure, 1, $h$  if f.port_id is null then
$h$),
  ('world.fleets()'::regprocedure, 1, $h$    'speed_kn', voyage.fleet_speed(f.id),
$h$),
  ('public.client_rpc_entry_points()'::regprocedure, 1, $h$      ('cmd',         'tow',                   'uuid, int'),
$h$))
select (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'hunk', h.ord,
          'times', (length(d.t) - length(replace(d.t, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
          from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as t) d) as hunks,
       (select count(*) from public.world_config c
         where c.key in ('fleet_room_bite', 'fleet_hard_max', 'fleet_ship_top', 'fleet_room_levels', 'fleet_room_prices', 'ship_room_prices')) as room_keys,
       to_regclass('public.house_room')::text as house_room,
       to_regprocedure('public.move_ship(uuid,uuid,uuid,text)')::text as move_ship,
       (select count(*) from public.fleets f where not exists (select 1 from public.ships s where s.fleet_id = f.id)) as empty_fleets,
       (select max(n) from (select count(*) as n from public.ships group by fleet_id) x) as most_in_fleet,
       (select c.value from public.world_config c where c.key = 'fleet_ship_max') as fleet_ship_max,
       (select count(*) from public.events e where e.kind = 'SHIP_MOVED' and e.created_at > now() - interval '1 day') as move_verbs,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
