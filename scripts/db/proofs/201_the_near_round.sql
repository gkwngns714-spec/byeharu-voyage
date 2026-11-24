-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 201 - THE NEAR ROUND  (migration 0498, dark: near_round_enabled; docs/dev-log/2026-11-25-near-round.md)
--
--   A `best` job with {within: nm}: each run the best paying sale within those miles, never at a loss; nothing pays: she sails to
--   her base and waits there as 0497 waits. The best plan extended, no second planner. Rolled back by proof.mjs.
--
-- @pass NR_DARK     dark: the door refuses `within` (E_NOT_IN_USE) and world.actions starts with the Best run
-- @pass NR_OFFER    lit: world.actions offers the near round first (sea:near, "Trade near Lisbon", no rate, basis none); the door takes it as {within 1440, base LIS}; her row is it
-- @pass NR_ROUND    the real tick runs it: four runs, each a paying sale within 1,440 nm (or the sail home), one plan a tick, every SAIL with its course
-- @pass NR_HOME     nothing within her round, away from her base: the tick sails her home with nothing bought
-- @pass NR_WAIT     nothing within her round, at her base: she waits (not stopped, no order, asked again 600 s on); her row says "prices low" and when
-- @pass NR_RESUME   her round wide again and her time come: the tick starts her by itself
-- @pass NR_COST     the plan's time, from the tick's own receipts (printed; fails past 2.5 s)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0498-4000-8000-0000000002a1';
  v_a    uuid;
  v_fa   uuid;
  v_lis  uuid;
  v_o    jsonb;
  v_r    jsonb;
  v_w    jsonb;
  v_rc   jsonb;
  v_j    public.fleet_jobs%rowtype;
  v_said text := '';
  v_ms   numeric := 0;
  v_n    int := 0;
  v_orders bigint;
  k      int;
  i      int;
begin
  v_a := public.new_house(c_a, 'Casa da Ronda 201', 'PRT');
  select f.id, f.port_id into v_fa, v_lis from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 40000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'jobs_wait_enabled');
  perform cmd.assume_identity(c_a);

  -- ── NR_DARK ──
  v_r := cmd.set_fleet_job(v_fa, 'best', jsonb_build_object('within', 1440));
  v_o := world.actions('fleet:' || v_fa);
  if (v_r->>'ok')::boolean is not false or v_r::text not like '%E_NOT_IN_USE%' or v_o #>> '{options,0,id}' <> 'sea:best'
     or exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fa) then
    raise exception 'NR_DARK: dark, the door took a near round or world.actions offers one: % / %', v_r, v_o #> '{options,0}';
  end if;
  raise notice 'PASS: NR_DARK — dark: `within` refused (E_NOT_IN_USE), world.actions starts with the Best run';

  -- ── NR_OFFER ──
  update public.world_config set value = 'true'::jsonb where key = 'near_round_enabled';
  v_o := world.actions('fleet:' || v_fa);
  v_r := cmd.set_fleet_job(v_fa, v_o #>> '{options,0,job,kind}', v_o #> '{options,0,job,params}');
  v_w := world.workers() #> '{workers,0}';
  if v_o #>> '{options,0,id}' <> 'sea:near' or v_o #>> '{options,0,sentence}' <> 'Trade near Lisbon' or v_o #>> '{options,0,basis}' <> 'none'
     or jsonb_typeof(v_o #> '{options,0,per_hour}') <> 'null' or v_o #>> '{options,1,id}' <> 'sea:best'
     or (v_r->>'ok')::boolean is not true or v_r->'params' <> jsonb_build_object('within', 1440, 'base', 'LIS')
     or v_w #>> '{action,id}' <> 'sea:near' or v_w #>> '{action,sentence}' <> 'Trade near Lisbon' then
    raise exception 'NR_OFFER: the near round is not offered first, taken, or her row: % / % / %', v_o #> '{options,0}', v_r, v_w;
  end if;
  raise notice 'PASS: NR_OFFER — offered first: % ("%", no rate); the door kept %; her row: %', v_o #>> '{options,0,id}', v_o #>> '{options,0,sentence}', v_r->'params', v_w #>> '{action,sentence}';

  -- ── NR_ROUND: four runs by the real tick ──
  for i in 1 .. 4 loop
    update public.fleet_jobs set next_at = null where fleet_id = v_fa;
    call public.tick_fleet_jobs(false);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
    select r.receipt into v_rc from public.fleet_job_runs r order by r.at desc limit 1;
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    if v_j.paused_reason is not null
       or (select count(*) from jsonb_array_elements(v_rc->'steps') s where s->>'fleet' = v_fa::text) <> 1
       or (v_j.last->>'leg' is distinct from 'home' and coalesce((v_j.last->>'profit')::numeric, 0) <= 0)
       or exists (select 1 from public.orders o where o.plan_id = v_j.last_plan and o.verb = 'SAIL' and jsonb_typeof(o.args->'path') <> 'array')
       or (select coalesce(sum((s->>'nm')::numeric), 0) from public.orders o
            cross join lateral jsonb_array_elements(voyage.segments_from_course(o.args->'path')) s
           where o.plan_id = v_j.last_plan and o.verb = 'SAIL') > 1440 then
      raise exception 'NR_ROUND: run % is not a paying sale within 1,440 nm by one plan with its courses: job % / receipt %', i, to_jsonb(v_j), v_rc;
    end if;
    v_ms := greatest(v_ms, coalesce((select max((s->>'plan_ms')::numeric) from jsonb_array_elements(v_rc->'steps') s where s->>'fleet' = v_fa::text), 0));
    v_n := v_n + 1;
    v_said := v_said || format('%s%s %s-%s%s', case when v_said = '' then '' else '; ' end, coalesce(v_j.last->>'good', 'home'), v_j.last->>'from', v_j.last->>'to',
                               case when v_j.last ? 'profit' then ' +' || (v_j.last->>'profit') else '' end);
    for k in 1 .. 12 loop
      exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fa and status = 'SAILING';
      perform world.fleets();
    end loop;
  end loop;
  if v_n < 2 or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status = 'failed') then
    raise exception 'NR_ROUND: fewer than two runs started, or an order failed: % (%)', v_said,
      (select jsonb_agg(jsonb_build_array(o.raw_text, o.status, o.error_code) order by o.issued_at, o.seq) from public.orders o where o.fleet_id = v_fa and o.status = 'failed');
  end if;
  raise notice 'PASS: NR_ROUND — % runs by the tick, one plan each: %', v_n, v_said;

  -- ── NR_HOME: away from her base with a round too small to reach anything (written past the door's floor, on her own job's row) ──
  update public.fleets f set port_id = (select k2.to_port from public.npc_known_legs(v_lis) k2 join public.ports p on p.id = k2.to_port
                                         where p.kind = 'HARBOUR' and public.fleet_job_course(v_fa, k2.to_port, v_lis) is not null order by k2.nm, k2.code limit 1),
                              status = 'DOCKED'
   where f.id = v_fa and f.port_id = v_lis;
  update public.fleet_jobs set params = jsonb_build_object('within', 1, 'base', 'LIS'), next_at = null where fleet_id = v_fa;
  select count(*) into v_orders from public.orders o where o.fleet_id = v_fa and o.verb in ('BUY', 'SELL');
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' or v_j.last->>'leg' <> 'home' or v_j.last->>'to' <> 'LIS'
     or (select count(*) from public.orders o where o.fleet_id = v_fa and o.verb in ('BUY', 'SELL')) <> v_orders then
    raise exception 'NR_HOME: with nothing within her round she did not sail home empty: %', to_jsonb(v_j);
  end if;
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fa) is distinct from v_lis then
    raise exception 'NR_HOME: she did not make her base';
  end if;
  raise notice 'PASS: NR_HOME — nothing within her round at %: she sailed home to Lisbon, nothing bought', v_j.last->>'from';

  -- ── NR_WAIT ──
  update public.fleet_jobs set next_at = null where fleet_id = v_fa;
  select count(*) into v_orders from public.orders o where o.fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  v_w := world.workers() #> '{workers,0}';
  if v_j.paused_reason is not null or v_j.last->>'wait' <> 'low' or v_j.next_at < now() + interval '600 seconds'
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders
     or v_w->>'state' <> 'waiting' or v_w #>> '{wait,sentence}' <> 'prices low' or (v_w #>> '{wait,retry_at}')::timestamptz <> v_j.next_at
     or exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fa) then
    raise exception 'NR_WAIT: at her base with nothing within her round she did not wait as written: job % / row %', to_jsonb(v_j), v_w;
  end if;
  raise notice 'PASS: NR_WAIT — at her base: not stopped, no order, asked again % s on; her row: "%"', round(extract(epoch from v_j.next_at - now())), v_w #>> '{wait,sentence}';

  -- ── NR_RESUME ──
  update public.fleet_jobs set params = jsonb_build_object('within', 1440, 'base', 'LIS'), next_at = now() - interval '1 second' where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' and v_j.last->>'wait' is distinct from 'low' then
    raise exception 'NR_RESUME: her round wide again, she neither started nor waited for a price: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: NR_RESUME — her round wide again and her time come: %', case when v_j.last ? 'good' then format('the tick started her (%s to %s)', v_j.last->>'good', v_j.last->>'to')
                                                                                else 'nothing pays yet after her own runs: she waits for a price (asked again by itself)' end;

  if v_ms > 2500 then
    raise exception 'NR_COST: a near round''s plan took % ms', v_ms;
  end if;
  raise notice 'PASS: NR_COST — a near round''s plan: at most % ms here (one plan a tick; its one world.best_sales read is most of it)', v_ms;
end $p$;
