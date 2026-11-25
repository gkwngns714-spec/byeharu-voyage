-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 222 - ROUNDS, THE CORE  (migration 0518; docs/design/rounds-2026-11-25.md)
--
--   A round has a cost and a log line; the run stops by arithmetic, and one settle books it from time passed. Its own company, work, stores and
--   hands: no market, dice or other company. Rolled back by proof.mjs.
--
-- @pass RC_DARK   dark (as deployed): a Send is refused, no work exists
-- @pass RC_OUT    lit: she is out; she reads `sea` (the one rule), no order runs, a purchase is refused, her base is kept
-- @pass RC_STOP   the stop is the least of food, water, crew, the number set and the 12 hours, and says which
-- @pass RC_MIN    her hands never fall under MIN, whatever is left to do; the stores never under the reserve
-- @pass RC_READ   a read long after the stop (cmd.advance) books everything once and lays her DOCKED in her base, with one ROUNDS_DONE
-- @pass RC_HOME   called in, the rounds passed are kept and the one under way is given up
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a  constant uuid := '00000000-0222-4000-8000-0000000000a1';
  v_a  uuid; v_f uuid; v_lis uuid; v_t timestamptz := now(); t jsonb; r jsonb; v_c int; v_n int; v_why text := ''; k text; x jsonb; v_e text;
begin
  v_a := public.new_house(c_a, 'Casa da Prova 222', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  perform cmd.assume_identity(c_a);
  begin
    perform public.round_send_for(v_a, v_f, 'w_probe', '{}', v_t);
  exception when sqlstate 'P0001' then v_e := sqlerrm;
  end;
  if v_e !~ '^E_NOT_IN_USE' or exists (select 1 from public.round_works) then
    raise exception 'RC_DARK: %', v_e;
  end if;
  raise notice 'PASS: RC_DARK - %', v_e;

  update public.world_config set value = 'true'::jsonb where key = 'rounds_enabled';
  insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct) values ('w_probe', 1, 'sea', 'Probe', 'exploration', 600, 0.4, 0.4, 2);
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 60 where s.fleet_id = v_f;

  -- RC_STOP
  foreach x in array array['{"rounds": 3}', '{"crew": 19}', '{}'] ::jsonb[] loop
    t := public.round_terms(v_f, 'w_probe', x);
    v_why := v_why || format(' %s=%s/%s', x, t->>'most', t->>'why');
    if (x ? 'rounds' and (t->>'why' <> 'rounds' or (t->>'most')::int <> 3)) or (x ? 'crew' and t->>'why' <> 'crew') then
      raise exception 'RC_STOP: % %', x, t;
    end if;
  end loop;
  update public.ships s set food_t = 0.5 where s.fleet_id = v_f;
  if public.round_terms(v_f, 'w_probe', '{"days": 0}')->>'why' <> 'food' then raise exception 'RC_STOP food %', public.round_terms(v_f, 'w_probe', '{"days": 0}'); end if;
  update public.ships s set food_t = 30, water_t = 0.5 where s.fleet_id = v_f;
  if public.round_terms(v_f, 'w_probe', '{"days": 0}')->>'why' <> 'water' then raise exception 'RC_STOP water'; end if;
  update public.ships s set water_t = 60 where s.fleet_id = v_f;
  update public.round_works set crew_pct = 0, food_days = 0, water_days = 0;
  t := public.round_terms(v_f, 'w_probe', '{}');
  if t->>'why' <> 'cap' or (t->>'most')::int <> 72 then raise exception 'RC_STOP cap %', t; end if;
  update public.round_works set crew_pct = 2, food_days = 0.4, water_days = 0.4;
  raise notice 'PASS: RC_STOP -% ; food, water and 72 rounds (12 h) too', v_why;

  -- RC_OUT
  r := public.round_send_for(v_a, v_f, 'w_probe', '{"crew": 15, "days": 1}', v_t);
  v_e := null;
  begin
    perform cmd.do_buy(v_f, jsonb_build_object('good', (select pg.good_id from public.port_goods pg where pg.port_id = v_lis limit 1), 'qty', 1));
  exception when sqlstate 'P0001' then v_e := sqlerrm;
  end;
  if public.fleet_state(v_f) <> 'sea' or coalesce(v_e, '') !~ '^E_' or cmd.advance(v_f, v_t) <> 0
     or (select f.status || f.port_id::text from public.fleets f where f.id = v_f) <> 'ROUNDS' || v_lis::text then
    raise exception 'RC_OUT: % %', public.fleet_state(v_f), v_e;
  end if;
  raise notice 'PASS: RC_OUT - she reads sea; a purchase: %', v_e;

  -- RC_READ, RC_MIN
  perform world.fleets();
  if (select q.state from public.round_runs q where q.fleet_id = v_f) <> 'out' then raise exception 'RC_READ: settled before its stop'; end if;
  perform cmd.advance(v_f, v_t + interval '3 days');
  perform cmd.advance(v_f, v_t + interval '3 days');
  select sum(s.crew) into v_c from public.ships s where s.fleet_id = v_f;
  if (select q.state || q.booked || q.ended from public.round_runs q where q.fleet_id = v_f) <> 'home' || (r #>> '{terms,most}') || (r #>> '{terms,why}')
     or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' or (select count(*) from public.events e where e.player_id = v_a and e.kind = 'ROUNDS_DONE') <> 1 then
    raise exception 'RC_READ: %', (select to_jsonb(q) from public.round_runs q where q.fleet_id = v_f);
  end if;
  if v_c < 15 or exists (select 1 from public.ships s where s.fleet_id = v_f and (s.food_t < 0 or s.water_t < 0)) then
    raise exception 'RC_MIN: %', v_c;
  end if;
  raise notice 'PASS: RC_READ - % rounds, why %, DOCKED, one ROUNDS_DONE', r #>> '{terms,most}', r #>> '{terms,why}';
  raise notice 'PASS: RC_MIN - % hands left of a MIN of 15', v_c;

  -- RC_HOME
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 60 where s.fleet_id = v_f;
  perform public.round_send_for(v_a, v_f, 'w_probe', '{"days": 0}', v_t);
  r := public.round_home_for(v_a, v_f, v_t + interval '1500 seconds');
  if (r->>'rounds')::int <> 2 or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED' or (select q.ended from public.round_runs q where q.fleet_id = v_f) <> 'called' then
    raise exception 'RC_HOME: %', r;
  end if;
  raise notice 'PASS: RC_HOME - called in after 25 minutes: 2 rounds kept';
end $p$;
