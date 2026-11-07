-- 0326 before: every hunk's pre-image occurs exactly once in the body deployed. A pure SELECT, one statement, stable catalog reads only. Generated from the migration's hunks.
begin transaction read only;
select h.fn::regprocedure::text as fn, h.n,
       (length(d.body) - length(replace(d.body, h.old, ''))) / length(h.old) as occurs
  from (values
  ('public.sea_houses()'::regprocedure, 1, $h$  -- merchants' ink. Her `kind` is the same word as public.fleet_kind. No ship: the merchants' houses and nothing else.
$h$),
  ('public.sea_houses()'::regprocedure, 2, $h$         'CARGO_SHIP'
    from public.cargo_ships c
$h$),
  ('public.cargo_homes(uuid)'::regprocedure, 1, $h$          select c.home_port_id, 1000 + c.ord from public.cargo_ships c where c.nation_id = p_nation) x
$h$),
  ('public.cargo_figures()'::regprocedure, 1, $h$  select case when exists (select 1 from public.cargo_ships)
              then jsonb_build_object('cargo_ships', (select count(*) from public.cargo_ships), 'funds_at_sea', public.funds_aboard())
$h$),
  ('public.funds_aboard()'::regprocedure, 1, $h$from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 1, $h$-- 0308: THE one place a cargo ship is made: lit, the ships a great power is missing up to convoy_ships_per_nation, each DOCKED at its capital, by the hands every fleet
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 2, $h$-- 0324: at her origin (public.cargo_origins): the capital until convoy_rich_enabled.
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 3, $h$  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
    continue when exists (select 1 from public.cargo_ships c where c.nation_id = p_nation and c.ord = v_n);
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 1, $h$-- public.treasury_try_lock, never waited for (0307), and a busy one is left to the next hour. The load is written at her home, and her home never moves with funds aboard (public.cargo_rebase_to).
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 2, $h$      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where public.realm_capital(c.nation_id) = k.cap and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null
$h$),
  ('public.cargo_ships_load(jsonb)'::regprocedure, 3, $h$     order by public.cargo_load_room(c.home_port_id, c.nation_id) desc, c.ord
     limit 1;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 1, $h$-- exists still comes home. No ship, no switch: it reads and writes nothing else. p_only_nation narrows a run to one realm: a probe's; the job passes null. Answers {built, made, steps}.
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 2, $h$  v_made  int := 0;
  v_steps jsonb := '{}'::jsonb;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 3, $h$  if public.convoys_on() then
    select g.nation_id, h.port_id into v_nat, v_start   -- 0324: a circuit from each start of a realm: one row off, the capital's
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 4, $h$            or (select count(*) from public.cargo_ships c where c.nation_id = g.nation_id) < public.wc_int('convoy_ships_per_nation'))
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 5, $h$  for r in select c.fleet_id from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
            where f.status <> 'SAILING' and (p_only_nation is null or c.nation_id = p_only_nation)
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)'::regprocedure, 6, $h$  return jsonb_build_object('built', v_built, 'made', v_made, 'steps', v_steps);
$h$)
  ) h(fn, n, old)
  cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as body) d
 order by 1, 2;
commit;
