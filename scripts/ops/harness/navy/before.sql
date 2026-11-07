-- 0331 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/navy/before.sql
-- Generated from the migration's hunks. Every function read here is STABLE (pg_get_functiondef, to_regclass, replace). No game function is called.
-- Wanted: every `times` 1; navy_keys 0; navy_words 0; navy_table null; class_ok 1; head 0330.
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.fleet_kind(uuid)'::regprocedure, 1, $h$  -- 0308: THE answer to what a fleet is: CARGO_SHIP (public.cargo_ships), MERCHANT (public.npc_fleets), else COMPANY, a player's. Null for no such fleet.
$h$),
  ('public.fleet_kind(uuid)'::regprocedure, 2, $h$              when exists (select 1 from public.npc_fleets n where n.fleet_id = f.id) then 'MERCHANT'
$h$),
  ('public.fleet_origin(uuid)'::regprocedure, 1, $h$  -- 0322: THE answer to where an NPC ship is from (docs/WORLD_POWERS.md section 3.3): a cargo ship's home, else her merchant house's. Null for a human's fleet. Navies and pirates join here, W12 and W17.
$h$),
  ('public.fleet_origin(uuid)'::regprocedure, 2, $h$                  (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet))
$h$),
  ('public.sea_houses()'::regprocedure, 1, $h$  -- 0326: the ships at work: a laid-up ship leaves the sea with her house.
$h$),
  ('public.sea_houses()'::regprocedure, 2, $h$         'CARGO_SHIP'
    from public.cargo_ships_in_service c
$h$),
  ('public.fleet_wage(uuid,boolean,integer)'::regprocedure, 1, $h$  if v_crew > 0 and public.fleet_kind(p_fleet) = 'CARGO_SHIP' then
$h$),
  ('public.port_fee(uuid,uuid,numeric)'::regprocedure, 1, $h$     or exists (select 1 from public.cargo_ships c where c.player_id = p_player)   -- 0309: a crown's cargo ship docks free in her own crown's cities; she has no purse
$h$),
  ('public.stats_live_track()'::regprocedure, 1, $h$      select p.is_npc and not exists (select 1 from public.cargo_ships c where c.player_id = p.id) into v_npc from public.players p   -- 0310: a cargo ship is at sea, and no merchant
$h$),
  ('public.stats_live_fold(timestamp with time zone,boolean)'::regprocedure, 1, $h$               and not exists (select 1 from public.cargo_ships c where c.player_id = p.id))::bigint as at_sea_merchants   -- 0310: a cargo ship is at sea, and no merchant
$h$),
  ('public.convoy_ships_wanted()'::regprocedure, 1, $h$           coalesce((select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
                      where a.nation_id = g.nation_id), 0)::bigint as cash
$h$),
  ('public.cargo_upkeep(uuid,uuid)'::regprocedure, 1, $h$  v_pay  bigint;
  s      record;
begin
$h$),
  ('public.cargo_upkeep(uuid,uuid)'::regprocedure, 2, $h$  for s in select x.id, t.water_t, t.food_t
             from public.ships x
            cross join lateral (select public.ship_hold_capacity(x.id) as cap offset 0) hc
            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, hc.cap, public.wc_num('convoy_store_days'), hc.cap * x.store_ratio) t
            where x.fleet_id = p_fleet loop
    if s.water_t > 0 or s.food_t > 0 then
      update public.ships x set water_t = x.water_t + s.water_t, food_t = x.food_t + s.food_t where x.id = s.id;
    end if;
  end loop;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    perform public.fleet_mend(p_fleet);   -- 0322: the one line
$h$),
  ('public.cargo_figures()'::regprocedure, 1, $h$              else '{}'::jsonb end
$h$),
  ('public.client_rpc_entry_points()'::regprocedure, 1, $h$      ('world',       'cargo_ship_card',       'uuid'),
$h$)
)
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'ord', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d),
  'navy_keys', (select count(*) from public.world_config c where c.key like 'navy%'),
  'navy_words', (select count(*) from public.stats_flow_words w where w.kind in ('BUILD_NAVY', 'NAVY_PAY')),
  'navy_table', to_regclass('public.navy_ships'),
  'class_ok', (select count(*) from public.ship_classes k where k.code = 'galion' and k.attack > 0 and k.crew_required > 0 and k.build_cost > 0),
  'word_ords', (select count(*) from public.stats_flow_words w where w.ord in (52, 53)),
  'head', (select max(version) from supabase_migrations.schema_migrations)
) as checks;
commit;
