-- 0340 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/the-navy-hunts/before.sql
-- Generated from the migration's hunks. Every function read here is STABLE or immutable (pg_get_functiondef, to_regclass, to_regprocedure, replace, length). No game function is called.
-- Wanted: every `times` 1; keys 0; columns 0; fn_pass null; navy_on false; pirates_bite false (W17's knob, present); pirate_objects all present (W17 deployed); navy_ships 0; hunt_rows 0; public_fights 0; head 20260818000339 (W17 deployed, this file not yet).
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.tick_navy(timestamp with time zone,uuid)'::regprocedure, 1, $h$  v_s     text;
begin
$h$),
  ('public.tick_navy(timestamp with time zone,uuid)'::regprocedure, 2, $h$  for r in select n.fleet_id from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
$h$),
  ('public.tick_navy(timestamp with time zone,uuid)'::regprocedure, 3, $h$  return jsonb_build_object('plan', v_plan, 'steps', v_steps, 'added', v_add, 'paid', v_paid);
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$  v_esc   text;   -- 0333
begin
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)'::regprocedure, 1, $h$  update public.ships sh set durability = greatest(0, sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(v_f->'hull_lost'->'a', '{}'::jsonb)) x
          union all
          select x.key::uuid, x.value::numeric from jsonb_each_text(coalesce(v_f->'hull_lost'->'b', '{}'::jsonb)) x) l
   where sh.id = l.id;
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 1, $h$  -- 0334: her country remembers what it did not answer (docs/WORLD_POWERS.md section 5.3): she won, or no ship of it came in time.
$h$),
  ('world.navy_ship_card(uuid)'::regprocedure, 1, $h$                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0333: as a cargo ship's card: the key is served only while attacks are lit
$h$)
), b as (
  select h.fn, h.ord, h.old, replace(pg_get_functiondef(h.fn), E'\r', '') as def from h
)
select (select jsonb_object_agg(b.fn::text || ' ' || b.ord, (length(b.def) - length(replace(b.def, b.old, ''))) / length(b.old)) from b) as times,
       (select count(*) from public.world_config c where c.key in ('navy_hunt_hours', 'navy_hunts_per_run', 'regard_pirate_beaten')) as keys,
       (select count(*) from pg_attribute a where a.attrelid = 'public.navy_ships'::regclass and a.attname in ('fought_at', 'fought', 'hunt_port', 'hunt_until') and not a.attisdropped) as columns,
       to_regprocedure('public.navy_hunt_pass(timestamp with time zone,uuid)') as fn_pass,
       (select c.value from public.world_config c where c.key = 'navy_enabled') as navy_on,
       (select c.value from public.world_config c where c.key = 'pirates_bite') as pirates_bite,
       jsonb_build_object('table', to_regclass('public.pirate_ships')::text, 'in_sea', to_regprocedure('public.pirate_ship_in_sea(uuid)')::text,
                          'on', to_regprocedure('public.pirates_on()')::text, 'power', to_regprocedure('public.pirate_power(uuid)')::text,
                          'fought_at', (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.pirate_ships') and a.attname = 'fought_at' and not a.attisdropped)) as pirate_objects,
       (select count(*) from public.navy_ships) as navy_ships,
       (select count(*) from public.navy_ships n where n.mission = 'HUNT') as hunt_rows,
       (select count(*) from public.events e where e.player_id is null and e.kind = 'NAVY_FIGHT') as public_fights,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
