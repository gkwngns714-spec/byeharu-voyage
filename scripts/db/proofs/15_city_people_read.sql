-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 15 — THE STATS CITY PAGE'S PEOPLE READER  (migration 0305)
--
--   0305's own self-assert proves the shape, the grants and that nothing else moved. This proof runs two real steps (public.population_tick)
--   and reads the reader over them: it serves exactly the hall's block, a rank that is (people above + 1) of every harbour, and the logged
--   steps in order, each carrying that step's population.
--
-- @pass PEOPLE_HALL      the reader's block equals the hall's `people` block key for key
-- @pass PEOPLE_RANK      rank = harbours with more people + 1, of every harbour; the most populous is rank 1
-- @pass PEOPLE_SERIES    two steps logged: two points, oldest first, the last equal to the population now
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- 0413 (a game day lasts one hour): this proof's instants and amounts are written on the clock as it was before 0413 (the length of a market day, a drift
-- slot and a population step; the drift job's spread; the rates per real day). So the rate is moved back through its one door, public.clock_set, and the
-- anchors are emptied, inside this proof's own rolled-back transaction. What 0413 itself does is proof 110's.
do $c$ begin perform public.clock_set(960, now()); update public.world_config set value = '{}'::jsonb where key in ('clock_anchor', 'market_clock_anchor'); end $c$;
do $$
declare
  c_t0 constant timestamptz := '2030-01-01 00:03:00+00';
  v_lon uuid;
  v_r   jsonb;
  v_h   jsonb;
  v_n   int;
begin
  select id into v_lon from public.ports where code = 'LON';
  perform public.population_tick(c_t0);
  perform public.population_tick(c_t0 + interval '10 minutes');
  select count(*) into v_n from public.port_population;

  v_r := world.stats_city_people(v_lon);
  v_h := world.town_hall(v_lon) -> 'people';
  if (v_r - 'rank' - 'of' - 'series') <> v_h then
    raise exception 'PROOF 15 FAIL: reader % vs hall %', v_r, v_h;
  end if;
  raise notice 'PASS: PEOPLE_HALL — the reader serves the hall block (population %)', v_r ->> 'population';

  if (v_r ->> 'of')::int <> v_n
     or (v_r ->> 'rank')::int <> 1 + (select count(*) from public.port_population o where o.population > (select population from public.port_population where port_id = v_lon))
     or not exists (select 1 from public.port_population pp where pp.population = (select max(population) from public.port_population)
                      and (world.stats_city_people(pp.port_id) ->> 'rank') = '1') then
    raise exception 'PROOF 15 FAIL: rank % of % is wrong', v_r ->> 'rank', v_r ->> 'of';
  end if;
  raise notice 'PASS: PEOPLE_RANK — London #% of %', v_r ->> 'rank', v_r ->> 'of';

  if jsonb_array_length(v_r -> 'series') <> 2
     or (v_r #>> '{series,0,at}') >= (v_r #>> '{series,1,at}')
     or (v_r #>> '{series,1,population}')::bigint <> (v_r ->> 'population')::bigint then
    raise exception 'PROOF 15 FAIL: series %', v_r -> 'series';
  end if;
  raise notice 'PASS: PEOPLE_SERIES — % points, oldest first', jsonb_array_length(v_r -> 'series');
end
$$;
