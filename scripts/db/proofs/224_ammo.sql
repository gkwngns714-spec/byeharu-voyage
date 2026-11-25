-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 224 - AMMO  (migration 0520; docs/design/rounds-2026-11-25.md section 6)
--
--   A round that shoots spends Gunpowder and Shot and Ball by her attack; the hold bounds the run; a job buys them. Its own company, an armed hull, its
--   own work, stock and purse. Rolled back by proof.mjs.
--
-- @pass AM_DARK   dark: the work costs no ammo
-- @pass AM_BOUND  lit: by her attack; the most rounds is the less of the two goods over a round's
-- @pass AM_SPENT  the run spends whole units of each, to the unit, and stops on ammo with the rest aboard
-- @pass AM_NONE   none aboard: the Send is refused with the reason, and the job waits
-- @pass AM_BUYS   a job that holds ammo buys both where they are sold, no more than it lacks
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a  constant uuid := '00000000-0224-4000-8000-0000000000a1';
  v_a  uuid; v_f uuid; v_lis uuid; v_att numeric; t jsonb; q jsonb; v_port uuid; v_n int; v_e text; v_k numeric; c text;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 224', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  update public.ships s set class_id = (select k.id from public.ship_classes k where k.code = 'xebec') where s.fleet_id = v_f;
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 60, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_f;
  update public.players set ducats = 10000000 where id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate');
  insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct, ammo) values ('w_probe', 99, 'sea', 'Probe', 'exploration', 600, 0, 0, 0, 4);
  perform cmd.assume_identity(c_a);
  select sum((world.ship_stats(s.id)->>'attack')::numeric) into v_att from public.ships s where s.fleet_id = v_f;
  if v_att <= 0 or (public.round_terms(v_f, 'w_probe', '{}')->>'ammo')::numeric <> 0 then raise exception 'AM_DARK: attack %', v_att; end if;
  raise notice 'PASS: AM_DARK - attack %, no ammo asked', v_att;

  update public.world_config set value = 'true'::jsonb where key = 'ammo_enabled';
  v_k := round(4 * v_att / 100, 4);
  v_e := null;
  begin
    perform public.round_send_for(v_a, v_f, 'w_probe', '{}', now());
  exception when sqlstate 'P0001' then v_e := sqlerrm;
  end;
  perform cmd.set_fleet_job(v_f, 'round', '{"work": "w_probe"}');
  q := public.fleet_job_plan(v_f);
  if v_e is distinct from 'E_ROUND_SHORT: not enough ammo for one round' or q->>'wait' is distinct from 'range' or q->>'sentence' is distinct from 'not enough ammo for a round' then
    raise exception 'AM_NONE: % %', v_e, q;
  end if;
  raise notice 'PASS: AM_NONE - "%"; the job: "%"', v_e, q->>'sentence';

  perform public.fleet_load(v_f, 'gunpowder', 30, 1);
  perform public.fleet_load(v_f, 'shot-and-ball', 20, 1);
  t := public.round_terms(v_f, 'w_probe', '{}');
  if (t->>'ammo')::numeric <> v_k or (t->>'most')::int <> least(72, floor(public.round_ammo_aboard(v_f) / v_k)) or ((t->>'most')::int < 72 and t->>'why' <> 'ammo') then
    raise exception 'AM_BOUND: % (a round %)', t, v_k;
  end if;
  raise notice 'PASS: AM_BOUND - % of each a round, % rounds (%)', v_k, t->>'most', t->>'why';
  perform public.round_send_for(v_a, v_f, 'w_probe', '{}', now());
  v_n := (t->>'most')::int;
  perform public.round_settle(v_f, now() + interval '601 seconds');
  perform cmd.advance(v_f, now() + interval '2 days');
  if public.fleet_cargo_qty(v_f, 'gunpowder') <> 30 - floor(v_k * v_n) or public.fleet_cargo_qty(v_f, 'shot-and-ball') <> 20 - floor(v_k * v_n) or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' then
    raise exception 'AM_SPENT: % %', public.fleet_cargo_qty(v_f, 'gunpowder'), public.fleet_cargo_qty(v_f, 'shot-and-ball');
  end if;
  raise notice 'PASS: AM_SPENT - % rounds: % gunpowder and % shot left', v_n, public.fleet_cargo_qty(v_f, 'gunpowder'), public.fleet_cargo_qty(v_f, 'shot-and-ball');

  -- AM_BUYS: a harbour that sells one of them (whichever the world's roster has there)
  select h.id, g.code into v_port, c from public.ports h join public.goods g on g.code in ('gunpowder', 'shot-and-ball')
   where h.kind = 'HARBOUR' and h.sea_id is not null and public.port_offers(h.id, g.id) and exists (select 1 from public.port_goods pg where pg.port_id = h.id and pg.good_id = g.id)
     and not public.culture_refuses(h.culture, g.culture_mask) order by h.code limit 1;
  if v_port is null then raise exception 'AM_BUYS: no harbour sells ammo'; end if;
  update public.fleets set port_id = v_port where id = v_f;
  update public.port_goods pg set stock = 5000, stock_target = 5000 from public.goods g where g.id = pg.good_id and pg.port_id = v_port and g.code in ('gunpowder', 'shot-and-ball');
  q := cmd.set_fleet_job(v_f, 'round', jsonb_build_object('work', 'w_probe', 'ammo', 40));
  q := public.fleet_job_plan(v_f);
  if not exists (select 1 from jsonb_array_elements(q->'lines') e where e->>'text' ~ ('^BUY ' || c || ' [0-9]+$')
                  and split_part(e->>'text', ' ', 3)::numeric between 1 and 40 - public.fleet_cargo_qty(v_f, c)) then
    raise exception 'AM_BUYS: % %', c, q;
  end if;
  raise notice 'PASS: AM_BUYS - %', (select string_agg(e->>'text', ', ') from jsonb_array_elements(q->'lines') e);
end $p$;
