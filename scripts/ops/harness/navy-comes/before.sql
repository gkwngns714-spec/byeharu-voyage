-- 0333 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/navy-comes/before.sql
-- Generated from the migration's hunks. Every function read here is STABLE or immutable (pg_get_functiondef, to_regclass, replace, length). No game function is called.
-- Wanted: every `times` 1; keys 0; how_column 0; fn_call null; attack_on false; navy_on false; ships 0; battles_attack 0; sides_rows as read; head 0332.
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure, 1, $h$    if (select f.status from public.fleets f where f.id = v_fleet) = 'SAILING' then
      perform voyage.hold(v_fleet, v_until, p_now);
    else
      update public.fleets set status = 'IN_BATTLE', busy_until = v_until, version = version + 1 where id = v_fleet;
    end if;
$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure, 2, $h$  end loop;
  return v_id;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)'::regprocedure, 1, $h$  for s in select bs.fleet_id, bs.side from public.battle_sides bs where bs.battle_id = p_battle order by bs.joined_at, bs.fleet_id loop
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)'::regprocedure, 2, $h$    v_spoils := public.attack_close(p_battle, v_f, p_now);
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)'::regprocedure, 3, $h$      v_rep := public.battle_words(v_f, v_b);
$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 1, $h$  v_battle uuid;
begin$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 2, $h$  if v_kind <> 'CARGO_SHIP' then$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 3, $h$  select * into c from public.cargo_ships x where x.fleet_id = p_target;

  if c.nation_id is not distinct from (select pl.nation_id from public.players pl where pl.id = p_player) then$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 4, $h$  if d.status = 'IN_BATTLE' or d.busy_until is not null then$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 5, $h$  if c.last_attacked_lap is not distinct from coalesce(c.out_load, 0) then
    perform cmd.refuse('E_SHIP_FOUGHT_THIS_LAP', format('%s has fought this lap', d.name));
  end if;$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure, 6, $h$  perform public.regard_add(p_player, c.nation_id, public.wc_num('regard_attack_cargo'), 'ATTACK_CARGO');
  return jsonb_build_object('battle_id', v_battle, 'fleet', a.name, 'target', d.name, 'nm', round(v_nm),
    'nation', (select n.code from public.nations n where n.id = c.nation_id),$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 1, $h$  v_lost    bigint := 0;
begin$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 2, $h$  select bs.fleet_id into v_d from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER';
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 3, $h$  select * into c from public.cargo_ships x where x.fleet_id = v_d;

  if v_out in ('PLUNDERED', 'RANSOM') then$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 4, $h$  if exists (select 1 from public.ships s where s.fleet_id = v_d)
     and not exists (select 1 from public.ships s where s.fleet_id = v_d and s.durability > 0) then
    perform public.regard_add(v_a.player_id, c.nation_id, public.wc_num('regard_sink'), 'SINK_CARGO');
    if public.npc_wrecked(v_d) then
      select * into v_voyage from public.voyages v where v.fleet_id = v_d and v.status = 'SAILING';
      perform voyage.npc_wreck(v_d, v_voyage.id, v_voyage.last_settled_day + 1);
    end if;
  end if;
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$  v_leg   jsonb;
begin$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$  v_duty := public.navy_on() and n.unpaid_since is null and n.ord <= public.navy_size_of(n.nation_id);
$h$),
  ('world.navy_ship_card(uuid)'::regprocedure, 1, $h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet));$h$),
  ('world.fleets()'::regprocedure, 1, $h$    || case when f.ready_at > now() then jsonb_build_object('ready_at', f.ready_at) else '{}'::jsonb end
$h$)
), b as (
  select h.fn, h.ord, h.old, replace(pg_get_functiondef(h.fn), E'\r', '') as def from h
)
select (select jsonb_object_agg(b.fn::text || ' ' || b.ord, (length(b.def) - length(replace(b.def, b.old, ''))) / length(b.old)) from b) as times,
       (select count(*) from public.world_config c where c.key in ('navy_call_ships', 'navy_escorts', 'regard_attack_navy', 'attack_ship_minutes')) as keys,
       (select count(*) from pg_attribute a where a.attrelid = 'public.battle_sides'::regclass and a.attname = 'how') as how_column,
       to_regprocedure('public.navy_call(uuid,uuid,timestamp with time zone,timestamp with time zone)') as fn_call,
       (select c.value from public.world_config c where c.key = 'attack_enabled') as attack_on,
       (select c.value from public.world_config c where c.key = 'navy_enabled') as navy_on,
       (select count(*) from public.navy_ships) as ships,
       (select count(*) from public.battles b2 where b2.kind = 'ATTACK') as battles_attack,
       (select count(*) from public.battle_sides) as sides_rows,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
