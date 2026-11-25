-- PROOF 241 - UNANSWERED IS NOT "NOTHING PAYS"  (migration 0504; docs/dev-log/2026-11-25-assign-fast.md)
-- @pass UN_CUT      world.best_sales cut by its clock before it answered a usable card: her Best job waits `slow`, nothing issued, not stopped, asked again within two minutes
-- @pass UN_NEXT     the next tick after it, the read answered: she sails
-- @pass UN_SOME     cut with a usable card answered: the best card answered is taken now
-- @pass UN_NOTHING  the read whole and nothing pays: {nothing}, asked again fleet_jobs_wait_s on, as before
-- @pass UN_NEAR     a near round away from her base, cut with no usable card: she waits `slow`, she is not sent home
-- @pass UN_ERROR    a read that raised (`unpriced`) is asked again within two minutes too
-- The clock is planted: world.best_sales' own body with its budget spent before the first good, or after the goods up to a code.
do $p$
declare
  c_a   constant uuid := '00000000-0504-4000-8000-000000000241';
  v_a   uuid;
  v_f   uuid;
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_def text := replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', '');
  v_cut text := 'if clock_timestamp() - v_t0 > c_budget then';
  v_j   record;
  v_p   jsonb;
  v_bs  jsonb;
  v_x   text;
  v_n   int;
begin
  v_a := public.new_house(c_a, 'Casa do Silencio 241', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 60000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('run_guard_enabled', 'jobs_wait_enabled');
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;
  -- a sale that pays, built: every good Lisbon sells is cheap there and dear elsewhere
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1
   where pg.port_id = v_lis and public.port_offers(v_lis, pg.good_id);
  update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0, glut = -0.5, glut_at = now()
   where pg.port_id in (select k.to_port from public.npc_known_legs(v_lis) k) and public.port_offers(v_lis, pg.good_id);
  perform cmd.assume_identity(c_a);
  if (cmd.set_fleet_job(v_f, 'best', '{}'::jsonb)->>'ok')::boolean is not true then
    raise exception 'UN_CUT: the door refused a Best job';
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut);
  if v_n <> 1 then
    raise exception 'UN_CUT: the budget line of world.best_sales is there % times: the planted clock proves nothing', v_n;
  end if;

  -- UN_CUT
  execute replace(v_def, v_cut, 'if true then');
  v_bs := world.best_sales(v_f, v_lis);
  if (v_bs->>'cut')::boolean is not true or jsonb_array_length(v_bs->'goods') <> 0 then
    raise exception 'UN_CUT: the planted clock did not cut the read: %', left(v_bs::text, 200);
  end if;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if v_j.paused_reason is not null or v_j.runs <> 0 or v_j.last->>'wait' is distinct from 'slow' or coalesce(v_j.last->>'sentence', '') = ''
     or v_j.next_at <= now() or v_j.next_at >= now() + interval '2 minutes' or exists (select 1 from public.orders o where o.fleet_id = v_f) then
    raise exception 'UN_CUT: cut with no card, her job did not wait slow within two minutes: %', to_jsonb(v_j);
  end if;
  if (select w #>> '{wait,code}' from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_f::text) is distinct from 'slow' then
    raise exception 'UN_CUT: her row does not say she waits for the read';
  end if;
  raise notice 'PASS: UN_CUT - waits "%", asked again in % s', v_j.last->>'sentence', round(extract(epoch from v_j.next_at - now()));

  -- UN_NEAR
  update public.world_config set value = 'true'::jsonb where key = 'near_round_enabled';
  update public.fleets set port_id = (select k.to_port from public.npc_known_legs(v_lis) k join public.ports p on p.id = k.to_port and p.kind = 'HARBOUR'
                                       where public.fleet_job_course(v_f, k.to_port, v_lis) is not null order by k.nm, k.code limit 1) where id = v_f;
  update public.fleet_jobs set params = '{"within": 1440, "base": "LIS"}'::jsonb, next_at = null where fleet_id = v_f;
  v_p := public.fleet_job_plan(v_f);
  if v_p->>'wait' is distinct from 'slow' then
    raise exception 'UN_NEAR: a near round whose read was cut is not asked again: %', left(v_p::text, 300);
  end if;
  raise notice 'PASS: UN_NEAR - away from her base, cut: %', v_p;
  update public.fleets set port_id = v_lis where id = v_f;
  update public.fleet_jobs set params = '{}'::jsonb where fleet_id = v_f;
  update public.world_config set value = 'false'::jsonb where key = 'near_round_enabled';

  -- UN_SOME: the read stops after the goods up to the first that pays
  execute v_def;
  v_bs := world.best_sales(v_f, v_lis);
  select min(e->>'good') into v_x from jsonb_array_elements(v_bs->'goods') e where (e->>'pays')::boolean and e->'near' is distinct from 'false'::jsonb;
  if v_x is null then
    raise exception 'UN_SOME: the scene built no paying sale: %', left(v_bs::text, 300);
  end if;
  execute replace(v_def, v_cut, format('if gd.code > %L then', v_x));
  v_bs := world.best_sales(v_f, v_lis);
  v_p := public.fleet_job_plan(v_f);
  if (v_bs->>'cut')::boolean is not true or not (v_p ? 'lines') or v_p #>> '{note,good}' <> v_x then
    raise exception 'UN_SOME: cut with a usable card, it is not taken: cut %, %', v_bs->'cut', left(v_p::text, 300);
  end if;
  raise notice 'PASS: UN_SOME - cut after %: the plan takes % to %', v_x, v_p #>> '{note,good}', v_p #>> '{note,to}';
  execute v_def;

  -- UN_NEXT: two minutes on, the read whole
  update public.fleet_jobs set next_at = now() where fleet_id = v_f;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if v_j.runs <> 1 or v_j.paused_reason is not null or not exists (select 1 from public.orders o where o.fleet_id = v_f) then
    raise exception 'UN_NEXT: the read answered, she was not started: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: UN_NEXT - the next tick starts her: runs %', v_j.runs;

  -- UN_ERROR and UN_NOTHING: docked again, nothing queued
  update public.orders set status = 'cancelled' where fleet_id = v_f and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_f and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_lis, ready_at = null, busy_until = null where id = v_f;
  update public.ships set cargo = '{}'::jsonb where fleet_id = v_f;
  update public.fleet_jobs set next_at = null, last_plan = null where fleet_id = v_f;
  execute replace(v_def, v_cut, $q$if 1 / (length(gd.code) - length(gd.code)) = 1 then$q$);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if v_j.last->>'wait' is distinct from 'unpriced' or v_j.next_at >= now() + interval '2 minutes' or v_j.next_at <= now() then
    raise exception 'UN_ERROR: a read that raised is not asked again within two minutes: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: UN_ERROR - waits %, asked again in % s', v_j.last->>'wait', round(extract(epoch from v_j.next_at - now()));
  execute v_def;
  update public.port_goods pg set stock = 0 where pg.port_id = v_lis;
  update public.fleet_jobs set next_at = null where fleet_id = v_f;
  v_bs := world.best_sales(v_f, v_lis);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if (v_bs->>'cut')::boolean is not false or v_j.last->>'wait' is distinct from 'nothing' or v_j.next_at < now() + interval '10 minutes' then
    raise exception 'UN_NOTHING: with the read whole and nothing paying she does not wait as before: cut %, %', v_bs->'cut', to_jsonb(v_j);
  end if;
  raise notice 'PASS: UN_NOTHING - %, asked again in % s', v_j.last->>'wait', round(extract(epoch from v_j.next_at - now()));
end
$p$;
