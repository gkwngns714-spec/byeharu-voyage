-- 0423 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only).
-- FIRST, WITH NO FILE (each alone, each its own old rule exactly; owner only):
--   route_rest_voyage_days 1.333333            her rest at home 600 s again
--   npc_route_neighbours 5, npc_route_trade_candidates 6, npc_route_candidates 16   the planner's loops as before
--   npc_ask_wait_max_minutes 0                 the back-off 10, 20, 40, 50 again (0407's rule alone)
--   convoy_loads_per_run 1, convoy_load_max 0  one ship a capital a run, no cap (0309's load exactly)
--   navy_hunt_hours 6, navy_own_sea_patrol false   the hunt as 0340 wrote it
-- This draft also takes the three bodies back to their pre-images (the nine hunks reversed; each hunk's NEW text must occur once, else it refuses:
-- a later file re-cut those lines and the draft is stale). The four new knobs are left in place and unread.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  z      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0423 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0423 values
  (1, 'public.npc_waiting_queue(timestamp with time zone)',
$h$                      public.wc_int('npc_ask_broke_under') as broke,   -- 0407
                      public.wc_int('npc_ask_wait_max_minutes') as cap) w   -- 0423
$h$,
$h$                      public.wc_int('npc_ask_broke_under') as broke) w   -- 0407
$h$),
  (2, 'public.npc_waiting_queue(timestamp with time zone)',
$h$                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         -- 0423: and never past npc_ask_wait_max_minutes (0: 0407's longest wait alone)
                                                         case when w.cap > 0 then greatest(w.e_min, least(w.cap, w.w_min - w.e_min))
                                                              else greatest(w.e_min, w.w_min - w.e_min) end) end),
$h$,
$h$                                              else least(w.e_min * power(2, least(greatest(nf.refused, 1) - 1, 10))::int,
                                                         greatest(w.e_min, w.w_min - w.e_min)) end),
$h$),
  (3, 'public.cargo_ships_load(jsonb)',
$h$  v_ships  int := 0;
  v_i      int;   -- 0423: the ships loaded for this capital this run
  v_rooms  jsonb := '{}'::jsonb;   -- 0423: what each home may still give THIS RUN: its room as the run first found it, less what it gave
begin
$h$,
$h$  v_ships  int := 0;
begin
$h$),
  (4, 'public.cargo_ships_load(jsonb)',
$h$    -- 0423: UP TO convoy_loads_per_run SHIPS FOR THIS CAPITAL (0309 loaded one), each the load below: the idle ship whose home has the most room,
    -- her row held, her home's purse tried, the need less what every ship of the realm carries read again. A loaded ship is no longer idle.
    for v_i in 1 .. greatest(1, public.wc_int('convoy_loads_per_run')) loop
    v_fleet := null;
    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat
$h$,
$h$    v_fleet := null;
    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat
$h$),
  (5, 'public.cargo_ships_load(jsonb)',
$h$    exit when v_fleet is null or not public.treasury_try_lock(v_home);   -- 0423: no idle ship left, or her home's purse is busy: this capital waits for the next run
$h$,
$h$    continue when v_fleet is null or not public.treasury_try_lock(v_home);
$h$),
  (6, 'public.cargo_ships_load(jsonb)',
$h$    -- 0423: A HOME GIVES ITS ROOM ONCE A RUN, however many ships load there: its room (public.cargo_load_room: a share of what it holds above
    -- its target, 0307) is read the first time and what each ship takes comes off it, so a run never calls a donor past what 0324 allowed.
    if not v_rooms ? v_home::text then
      v_rooms := v_rooms || jsonb_build_object(v_home::text, public.cargo_load_room(v_home, v_nat));
    end if;
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),
                 (v_rooms ->> v_home::text)::bigint,
                 nullif(public.wc_int('convoy_load_max'), 0));   -- 0423: one ship's share at most (0: no cap; least() passes over a null)
    exit when v_a <= 0;   -- 0423: the need is met, or the home with the most room has none
    v_rooms := v_rooms || jsonb_build_object(v_home::text, (v_rooms ->> v_home::text)::bigint - v_a);
$h$,
$h$    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),
                 public.cargo_load_room(v_home, v_nat));
    continue when v_a <= 0;
$h$),
  (7, 'public.cargo_ships_load(jsonb)',
$h$    v_ships := v_ships + 1;
    end loop;   -- 0423
  end loop;
$h$,
$h$    v_ships := v_ships + 1;
  end loop;
$h$),
  (8, 'public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)',
$h$    if t.port_id = p_home then
      -- 0423: HER OWN SEA, UNDER SAIL. She watches it on her station's patrol (its stops are her own waters) instead of lying at her station: the
      -- hunt's fields go and the step goes on to her patrol (public.navy_ship_step). navy_own_sea_patrol false: 0340's lie, below.
      if public.wc('navy_own_sea_patrol') = 'true'::jsonb then
        update public.navy_ships x set mission = case when x.mission = 'HUNT' then 'PATROL' else x.mission end, hunt_port = null, hunt_until = null
         where x.fleet_id = p_fleet and (x.mission = 'HUNT' or x.hunt_port is not null or x.hunt_until is not null);
        return null;
      end if;
      perform public.fleet_mend(p_fleet);
$h$,
$h$    if t.port_id = p_home then
      perform public.fleet_mend(p_fleet);
$h$),
  (9, 'public.cargo_ships_load(jsonb)',
$h$       and c.ord <= public.convoy_ships_of(c.nation_id)
       and coalesce((v_rooms ->> c.home_port_id::text)::bigint, 1) > 0   -- 0423: a home that has given its room this run is passed over
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
$h$,
$h$       and c.ord <= public.convoy_ships_of(c.nation_id)
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
$h$);
  for h in select distinct b.fn from back_0423 b loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for z in select b.ord, b.new, b.old from back_0423 b where b.fn = h.fn order by b.ord desc loop
      v_n := (length(v_def) - length(replace(v_def, z.new, ''))) / length(z.new);
      if v_n <> 1 then
        raise exception 'rollback-0423 refuses: hunk % of % occurs % time(s), not once: a later file re-cut it', z.ord, h.fn, v_n;
      end if;
      v_def := replace(v_def, z.new, z.old);
    end loop;
    execute v_def;
  end loop;
  update public.world_config set value = to_jsonb(1.333333) where key = 'route_rest_voyage_days';
  update public.world_config set value = to_jsonb(5) where key = 'npc_route_neighbours';
  update public.world_config set value = to_jsonb(6) where key = 'npc_route_trade_candidates';
  update public.world_config set value = to_jsonb(16) where key = 'npc_route_candidates';
  update public.world_config set value = to_jsonb(6) where key = 'navy_hunt_hours';
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_wait_max_minutes';
  update public.world_config set value = to_jsonb(1) where key = 'convoy_loads_per_run';
  update public.world_config set value = to_jsonb(0) where key = 'convoy_load_max';
  update public.world_config set value = 'false'::jsonb where key = 'navy_own_sea_patrol';
  raise notice 'rollback-0423: three bodies back to their pre-images, the knobs to their old values';
end $r$;
