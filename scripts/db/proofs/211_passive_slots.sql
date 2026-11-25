-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 211 - PASSIVE SLOTS  (migration 0509, dark: passive_slots_enabled; docs/design/owner-spec-plan-2026-11-25.md 0.3;
--             the owner, 2026-11-25: "trading 3 is good. Number of fleet you can choose to passive trading.")
--
--   The migration's self-assert walks the ladder. This proof lives it: jobs running when the switch is lit, the real tick over them, the
--   door's every way round the limit (a single run, a haul of another kind, a fixed run, a change of kind), and the two reads.
--   Independent of the market (pinned), the dice (hazard_p_max 0) and the world's age; no price is judged. Rolled back by proof.mjs.
--
-- @pass PS_DARK    dark: three passive fleets at Trading 1, no `passive` in world.workers, no option of world.actions locked
-- @pass PS_KEEP    lit at Trading 1: the three keep their jobs through the real tick (none stopped by it, each acted), and each may be changed
-- @pass PS_REFUSE  lit: a fourth is refused E_PASSIVE_SLOTS with the levels in plain words, nothing written; at Trading 3 the same (over her level)
-- @pass PS_ONCE    lit at Trading 1: a single run (times 1) is taken; turned into a repeating one on the same fleet it is refused
-- @pass PS_OPEN    at Trading 11 the fourth is taken; a job cleared gives its slot back to another fleet
-- @pass PS_READ    world.workers names level, used, max and the next level; world.actions locks the Best run of a fleet with no slot
--                  (a single run stays open), and locks nothing for a fleet that holds one
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0509-4000-8000-0000000002a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_fl   uuid[];
  v_id   uuid;
  v_good text;
  v_sell text;
  v_fix  jsonb;
  v_r    jsonb;
  v_s    jsonb;
  v_w    jsonb;
  v_n    int;
begin
  if (proof.pin_market('00000000-0509-4000-8000-000000000211'::uuid, 'proof-211') ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 211: the market was not pinned';
  end if;
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'assign_home_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('jobs_wait_enabled', 'fleet_room_bite');
  update public.world_config set value = '6'::jsonb where key in ('fleet_max', 'fleet_jobs_per_tick');
  update public.world_config set value = '60000'::jsonb where key = 'fleet_jobs_budget_ms';
  if public.passive_slots_on() then
    raise exception 'PROOF 211: the switch is not dark in the shipped world';
  end if;
  v_a := public.new_house(c_a, 'Casa das Vagas 211', 'PRT');
  update public.players set ducats = 5000000 where id = v_a;
  select array[f.id] into v_fl from public.fleets f where f.player_id = v_a;
  update public.ships s set crew = c.crew_max, water_t = 0, food_t = 0 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl[1];
  for v_n in 2 .. 5 loop
    insert into public.fleets (player_id, name, port_id) select f.player_id, format('Vaga 211 %s', v_n), f.port_id from public.fleets f where f.id = v_fl[1]
    returning id into v_id;
    insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, is_flagship)
    select s.player_id, v_id, s.class_id, format('Vaga 211 %s', v_n), s.durability, s.crew, true from public.ships s where s.fleet_id = v_fl[1] and s.is_flagship;
    v_fl := v_fl || v_id;
  end loop;
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 1)
    on conflict (player_id, track) do update set level = excluded.level;
  perform cmd.assume_identity(c_a);
  -- a pair from static rows: a good Lisbon offers and her nearest remembered harbour that takes it
  select g.code, k.code into v_good, v_sell
    from public.npc_known_legs(v_lis) k
    join public.port_goods ps on ps.port_id = k.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id) and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
   order by k.nm, g.code limit 1;
  v_fix := jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell);

  -- ── PS_DARK ──
  for v_n in 1 .. 3 loop
    v_r := cmd.set_fleet_job(v_fl[v_n], 'fixed', v_fix);
    if (v_r->>'ok')::boolean is not true then
      raise exception 'PS_DARK: a repeating run was refused dark: %', v_r;
    end if;
  end loop;
  v_r := world.actions('fleet:' || v_fl[4]);
  if world.workers() ? 'passive' or exists (select 1 from jsonb_array_elements(v_r->'options') o where o ? 'locked') then
    raise exception 'PS_DARK: the reads are not as before: % / %', world.workers()->'passive', left(v_r::text, 300);
  end if;
  raise notice 'PASS: PS_DARK — three fleets on % LIS to % at Trading 1; no passive key, no option locked of %', v_good, v_sell, jsonb_array_length(v_r->'options');

  -- ── PS_KEEP ──
  update public.world_config set value = 'true'::jsonb where key = 'passive_slots_enabled';
  -- the tick over her three jobs alone, the quay's own door: each plan opened as the tick opens it
  for v_n in 1 .. 3 loop
    if public.fleet_job_open(v_fl[v_n], public.fleet_job_plan(v_fl[v_n])) <> 1 then
      raise exception 'PS_KEEP: lit, a job already held did not start: %', (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fl[v_n]);
    end if;
  end loop;
  call public.tick_fleet_jobs(false);
  if (select count(*) from public.fleet_jobs j where j.player_id = v_a and j.paused_reason is null and j.runs >= 1) <> 3
     or exists (select 1 from public.orders o where o.fleet_id = any (v_fl) and o.status = 'failed') then
    raise exception 'PS_KEEP: a job already held was stopped: %', (select jsonb_agg(to_jsonb(j)) from public.fleet_jobs j where j.player_id = v_a);
  end if;
  v_r := cmd.set_fleet_job(v_fl[3], 'fixed', v_fix || '{"times": 7}'::jsonb);
  v_s := cmd.set_fleet_job(v_fl[3], 'best', '{}'::jsonb);
  if (v_r->>'ok')::boolean is not true or (v_s->>'ok')::boolean is not true then
    raise exception 'PS_KEEP: a fleet that holds a passive job could not change it: % / %', v_r, v_s;
  end if;
  raise notice 'PASS: PS_KEEP — lit at Trading 1 (none may): three jobs held, three runs opened, none stopped; one changed twice';

  -- ── PS_REFUSE ──
  v_r := cmd.set_fleet_job(v_fl[4], 'best', '{}'::jsonb);
  v_s := cmd.set_fleet_job(v_fl[4], 'fixed', v_fix);
  if v_r->>'error_code' is distinct from 'E_PASSIVE_SLOTS' or v_s->>'error_code' is distinct from 'E_PASSIVE_SLOTS'
     or v_r->>'error_message' is distinct from 'passive trading opens at Trading 3; yours is 1; Trading 11 allows 4'
     or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fl[4]) then
    raise exception 'PS_REFUSE: at Trading 1: % / %', v_r, v_s;
  end if;
  update public.house_level_marks set level = 3 where player_id = v_a and track = 'trading';
  v_s := cmd.set_fleet_job(v_fl[4], 'best', '{}'::jsonb);
  if v_s->>'error_message' is distinct from '3 fleets trade passively; Trading 3 allows 1; Trading 11 allows 4' then
    raise exception 'PS_REFUSE: at Trading 3, over her level: %', v_s;
  end if;
  raise notice 'PASS: PS_REFUSE — "%", "%"; nothing written', v_r->>'error_message', v_s->>'error_message';

  -- ── PS_ONCE ──
  update public.house_level_marks set level = 1 where player_id = v_a and track = 'trading';
  v_r := cmd.set_fleet_job(v_fl[4], 'fixed', v_fix || '{"times": 1}'::jsonb);
  v_s := cmd.set_fleet_job(v_fl[4], 'fixed', v_fix);
  if (v_r->>'ok')::boolean is not true or v_s->>'error_code' is distinct from 'E_PASSIVE_SLOTS'
     or (select j.params->>'times' from public.fleet_jobs j where j.fleet_id = v_fl[4]) is distinct from '1'
     or (public.passive_slots(v_a)->>'used')::int <> 3 then
    raise exception 'PS_ONCE: a single run % / made repeating %', v_r, v_s;
  end if;
  raise notice 'PASS: PS_ONCE — a single run taken and not counted; made repeating it is refused and the single run stands';

  -- ── PS_READ ──
  v_w := world.workers()->'passive';
  v_r := world.actions('fleet:' || v_fl[5]);
  v_s := public.passive_options(v_a, v_fl[1], v_r);
  if v_w is distinct from jsonb_build_object('level', 1, 'used', 3, 'max', 0, 'next', 11, 'next_max', 4)
     or not exists (select 1 from jsonb_array_elements(v_r->'options') o where o->>'id' = 'sea:best' and o #>> '{locked,code}' = 'E_PASSIVE_SLOTS')
     or exists (select 1 from jsonb_array_elements(v_r->'options') o where o #>> '{job,kind}' = 'fixed' and (o ? 'locked' is false or o->>'once' is distinct from 'true'))
     or exists (select 1 from jsonb_array_elements(world.actions('fleet:' || v_fl[1])->'options') o where o ? 'locked') then
    raise exception 'PS_READ: workers % / actions %', v_w, left(v_r::text, 500);
  end if;
  raise notice 'PASS: PS_READ — workers: %; a fleet with no slot: % of % options locked; a fleet that holds one: none', v_w,
    (select count(*) from jsonb_array_elements(v_r->'options') o where o ? 'locked'), jsonb_array_length(v_r->'options');

  -- ── PS_OPEN ──
  update public.house_level_marks set level = 11 where player_id = v_a and track = 'trading';
  v_r := cmd.set_fleet_job(v_fl[4], 'fixed', v_fix);
  v_s := cmd.set_fleet_job(v_fl[5], 'best', '{}'::jsonb);
  if (v_r->>'ok')::boolean is not true or v_s->>'error_message' is distinct from '4 fleets trade passively; Trading 11 allows 4; Trading 14 allows 5' then
    raise exception 'PS_OPEN: at Trading 11: % / %', v_r, v_s;
  end if;
  perform cmd.clear_fleet_job(v_fl[4]);
  v_r := cmd.set_fleet_job(v_fl[5], 'best', '{}'::jsonb);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'PS_OPEN: a cleared job did not give its slot back: %', v_r;
  end if;
  raise notice 'PASS: PS_OPEN — at Trading 11 the fourth is taken, the fifth refused; a cleared slot taken by another fleet';
end $p$;
