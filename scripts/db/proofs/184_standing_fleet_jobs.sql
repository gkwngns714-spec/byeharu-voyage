-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 184 - STANDING FLEET JOBS  (migration 0481; docs/design/hq-command-2026-11-23.md section 2, v2 "Standing fleet jobs";
--             docs/dev-log/2026-11-23-fleet-jobs.md)
--
--   The migration's self-assert never asks world.best_sales and plays one run of a fixed job and a land job. This proof plays the jobs
--   as a company lives them: a `best` job's run, her arrival and its next turn; a fixed route out, home and out again; a plan that failed
--   when it ran stopping the job, and a set starting it again; the run's budget; the cost of a run. Rolled back by proof.mjs.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: a best run is checked for its own shape (its lines, her voyage to the harbour its
--   note names), never against a second world.best_sales answer. THE DAY: proof.mjs runs this file in ONE transaction (now() is one
--   instant); the report's window starts at 00:00 UTC of the day it runs, so no scene straddles a UTC midnight. A voyage is brought home
--   by moving its clock back (proof 4's way), and the read that follows settles her.
--
-- @pass FJ_DARK      dark: the tick writes nothing and the read is {"on": false}, a job's row standing
-- @pass FJ_BEST      lit: a best job sends BUY / SAIL (each with the world's course) / SELL ALL for a paying sale, and she sails for it
-- @pass FJ_LAP       she arrives and sells; her report counts the run and her fleet's coin as her ledger has it; the next run acts again
-- @pass FJ_FIXED     a fixed route: out (BUY ALL, SAIL, SELL ALL), home (SAIL back), out again: three runs
-- @pass FJ_STOP      a plan that failed when it ran stops the job on that order's code; it is not due; set again, it is
-- @pass FJ_BUDGET    fleet_jobs_budget_ms 0: a run starts the first due job only and names the rest left
-- @pass FJ_COST      one run with one best job, timed: the plan (world.best_sales and the courses) and the open (cmd.issue_lines)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0481-4000-8000-0000000001a1';
  c_b     constant uuid := '00000000-0481-4000-8000-0000000001b1';
  v_day   timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_b     uuid;
  v_fa    uuid;
  v_fb    uuid;
  v_sell  text;
  v_sid   uuid;
  v_g     text;
  v_j     record;
  v_rep   jsonb;
  v_r     jsonb;
  v_rc    jsonb;
  v_texts text;
  v_led   bigint;
  v_n     int;
  v_t     timestamptz;
  v_ms    numeric;
  k       int;
begin
  v_a := public.new_house(c_a, 'Casa da Lida 184', 'PRT');
  v_b := public.new_house(c_b, 'Casa da Rota 184', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  update public.players p set ducats = 60000 where p.id in (v_a, v_b);

  -- FJ_DARK: a job row standing (written past the dark door), the switch off: nothing moves
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fa, v_a, 'best', '{}'::jsonb, v_day, v_day);
  perform cmd.assume_identity(c_a);
  call public.tick_fleet_jobs(false);
  if exists (select 1 from public.fleet_job_runs) or exists (select 1 from public.orders o where o.fleet_id = v_fa)
     or (select j.runs from public.fleet_jobs j where j.fleet_id = v_fa) <> 0 or world.away_report() is distinct from '{"on": false}'::jsonb then
    raise exception 'FJ_DARK: dark, the tick or the read moved';
  end if;
  delete from public.fleet_jobs;
  raise notice 'PASS: FJ_DARK — dark, a job standing: the tick wrote nothing, no order, the read {"on": false}';

  -- FJ_BEST + FJ_COST: one run, one best job (the only one due)
  update public.world_config set value = 'true'::jsonb where key = 'fleet_jobs_enabled';
  v_r := cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb);
  update public.fleet_jobs set seen_at = v_day where fleet_id = v_fa;
  v_t := clock_timestamp();
  call public.tick_fleet_jobs(false);
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  select r.receipt into v_rc from public.fleet_job_runs r;
  select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
  if (v_r->>'ok')::boolean is not true or v_j.runs <> 1 or (v_j.last->>'ok')::boolean is not true or (v_j.last->>'profit')::numeric <= 0
     or v_texts !~ ('^(BUY ' || (v_j.last->>'good') || ' [0-9.]+ / )?(SAIL [A-Z]+ / )+SELL ' || (v_j.last->>'good') || ' ALL$')
     or v_texts !~ ('SAIL ' || (v_j.last->>'to') || ' / SELL')
     or exists (select 1 from public.orders o where o.plan_id = v_j.last_plan and o.verb = 'SAIL' and jsonb_typeof(o.args->'path') <> 'array')
     or not exists (select 1 from public.voyages v join public.ports p on p.id = v.dest_port_id
                     where v.fleet_id = v_fa and v.status = 'SAILING' and (p.code = v_j.last->>'to'
                       or p.code = (select substring(o.raw_text from 6) from public.orders o where o.plan_id = v_j.last_plan and o.verb = 'SAIL' order by o.seq limit 1))) then
    raise exception 'FJ_BEST: the best job did not send a paying run with courses and sail: % / % / % (%)', v_r, v_texts, v_j.last,
      (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
  end if;
  raise notice 'PASS: FJ_BEST — % : % from %, %+% in % s (coin an hour %)', v_texts, v_j.last->>'good', v_j.last->>'from', v_j.last->>'to',
    v_j.last->>'profit', v_j.last->>'seconds', round((v_j.last->>'profit')::numeric * 3600 / greatest((v_j.last->>'seconds')::numeric, 1));
  raise notice 'PASS: FJ_COST — one run, one best job: % ms (plan % ms: world.best_sales, board_passages and the courses; open % ms: cmd.issue_lines under the quay)',
    v_ms, v_rc #>> '{steps,0,plan_ms}', v_rc #>> '{steps,0,open_ms}';

  -- FJ_LAP: she comes home (every leg), sells; her report: one run, working until she lies idle, the coin her ledger has; the next run acts
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  v_rep := world.away_report();
  v_led := (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_a and l.fleet_id = v_fa and l.created_at > v_day
              and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_');
  if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa) is distinct from v_j.last->>'to'
     or exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status in ('pending', 'active', 'failed'))
     or (v_rep #>> '{jobs,0,runs}')::int <> 1 or v_rep #>> '{jobs,0,state}' <> 'waiting' or (v_rep #>> '{jobs,0,earned}')::bigint <> v_led
     or (v_rep->>'earned')::bigint <> v_led then
    raise exception 'FJ_LAP: she did not arrive at % and sell, or her report is not her ledger''s (% against %): %', v_j.last->>'to',
      v_rep #>> '{jobs,0,earned}', v_led, left(v_rep::text, 400);
  end if;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if not (v_j.runs = 2 or (v_j.last->>'wait' = 'nothing' and v_j.next_at > now())) then
    raise exception 'FJ_LAP: lying idle at her sale''s harbour, the next run neither started nor waited: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: FJ_LAP — arrived and sold, her report % (her ledger % since 00:00 UTC), then the next run: %', v_rep #>> '{jobs,0,earned}', v_led,
    case when v_j.runs = 2 then format('%s to %s', v_j.last->>'good', v_j.last->>'to') else 'nothing paying with a remembered course: asked again in 900 s' end;

  -- FJ_FIXED: house B, a fixed route from Lisbon to her nearest remembered harbour that buys a good Lisbon offers
  perform cmd.assume_identity(c_b);
  select k2.code, k2.to_port, g.code into v_sell, v_sid, v_g
    from public.npc_known_legs(v_lis) k2
    join public.port_goods pg on pg.port_id = v_lis
    join public.goods g on g.id = pg.good_id
    join public.port_goods ps on ps.port_id = k2.to_port and ps.good_id = g.id
   where public.port_offers(v_lis, g.id)
     and not public.culture_refuses((select p.culture from public.ports p where p.id = k2.to_port), g.culture_mask)
   order by k2.nm, pg.stock_target desc, g.code limit 1;
  v_r := cmd.set_fleet_job(v_fb, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', v_sell));
  v_n := 0;
  for k in 1 .. 3 loop
    call public.tick_fleet_jobs(false);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fb;
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fb and o.plan_id = v_j.last_plan;
    if v_j.runs <> k or v_texts is distinct from (case when k = 2 then 'SAIL LIS' else format('BUY %s ALL / SAIL %s / SELL %s ALL', v_g, v_sell, v_g) end) then
      raise exception 'FJ_FIXED: run % of the fixed route LIS-% sent % (job %; set %)', k, v_sell, v_texts, to_jsonb(v_j), v_r;
    end if;
    for v_n in 1 .. 12 loop
      exit when (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING';
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fb and status = 'SAILING';
      perform world.fleets();
    end loop;
    exit when k = 3;
    if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fb) is distinct from (case when k = 1 then v_sell else 'LIS' end)
       or exists (select 1 from public.orders o where o.fleet_id = v_fb and o.status in ('pending', 'active', 'failed')) then
      raise exception 'FJ_FIXED: after run % she lies at % with %', k,
        (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fb),
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fb);
    end if;
  end loop;
  raise notice 'PASS: FJ_FIXED — % from LIS to %: out, home, out again: % runs, she lies at %', v_g, v_sell, v_j.runs,
    (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fb);

  -- FJ_STOP: the third run's SELL is marked failed as it ran (cmd.release_failed's state); the job stops on its code at the next run
  update public.orders o set status = 'failed', error_code = 'E_PROBE_184', error_message = 'probe: the sale was refused'
   where o.fleet_id = v_fb and o.plan_id = v_j.last_plan and o.verb = 'SELL';
  call public.tick_fleet_jobs(false);
  v_rep := world.away_report();
  if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fb) is distinct from 'E_PROBE_184'
     or v_rep #>> '{jobs,0,state}' <> 'stopped' or v_rep #>> '{jobs,0,last,code}' <> 'E_PROBE_184'
     or exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fb) then
    raise exception 'FJ_STOP: a failed plan did not stop the job on its code: %', left(v_rep::text, 400);
  end if;
  v_r := cmd.set_fleet_job(v_fb, 'fixed', jsonb_build_object('good', v_g, 'buy', 'LIS', 'sell', v_sell));
  if (v_r->>'ok')::boolean is not true or not exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fb) then
    raise exception 'FJ_STOP: set again, the job is not due: %', v_r;
  end if;
  raise notice 'PASS: FJ_STOP — a SELL that failed as it ran stopped the job (E_PROBE_184, "stopped" in her report, not due); set again, it is due';

  -- FJ_BUDGET: two jobs due, fleet_jobs_budget_ms 0: the first runs, the second is left for the next run
  perform cmd.assume_identity(c_a);
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  update public.fleet_jobs set next_at = null, paused_reason = null where fleet_id = v_fa;
  update public.world_config set value = to_jsonb(0) where key = 'fleet_jobs_budget_ms';
  if (select count(*) from public.fleet_jobs_due()) <> 2 then
    raise exception 'FJ_BUDGET: two jobs are not due: %', (select jsonb_agg(to_jsonb(d)) from public.fleet_jobs_due() d);
  end if;
  call public.tick_fleet_jobs(false);
  select r.receipt into v_rc from public.fleet_job_runs r order by r.at desc limit 1;
  if jsonb_array_length(v_rc->'steps') <> 1 or (v_rc->>'left')::int <> 1 then
    raise exception 'FJ_BUDGET: budget 0 did not stop after the first job: %', v_rc;
  end if;
  raise notice 'PASS: FJ_BUDGET — budget 0 ms: one job planned (%), one left for the next run', v_rc #>> '{steps,0,kind}';
end
$p$;
