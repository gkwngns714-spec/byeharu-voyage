-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 202 - FIT TO SAIL  (migration 0499; docs/dev-log/2026-11-25-fit-to-sail.md)
--
--   The lead's prod facts: a company's one fleet, towed to Island of Mozambique after a ransom, her flagship's hull at 0; her land job
--   was retried, seven SAILs issued and a run counted, the first SAIL refused E_FLAGSHIP_DISABLED, the job stopped for ever. This proof
--   plays her through the real tick, the real job door and the real yard (cmd.preview / cmd.issue 'REPAIR', cmd.advance).
--   Rolled back by proof.mjs.
--
-- @pass FS_WAIT     wrecked at ISL, her job WAITS with E_FLAGSHIP_DISABLED and the sail's sentence: no order issued, no run counted, not stopped; the next run asks nothing
-- @pass FS_ROW      world.workers: state waiting, wait {code E_FLAGSHIP_DISABLED, sentence, retry_at}, no stop, worker_state wrecked (the one state rule)
-- @pass FS_DOOR     the job door refuses a new job for her with the same code and sentence, and the job she has is untouched
-- @pass FS_PURSE    an empty purse cannot pay the yard (E_INSUFFICIENT_FUNDS, the price in its figures), nothing is mended, she still waits; REPAIR TO a small per cent is cheaper
-- @pass FS_QUEUE_AT a refused order's row in the served queue (cmd.queue) carries `at`, when it was refused; an order that waits carries null
-- @pass FS_REPAIR   the yard's quote (cmd.preview) is the price cmd.issue 'REPAIR' takes; in the yard she is not asked; out of it the very next run starts her, harbour by harbour, one run
-- @pass FS_STOPPED  a job ALREADY stopped on E_FLAGSHIP_DISABLED (prod's row) is not asked while she is wrecked and goes on at the first run after her repair
-- @pass FS_CREW     short of crew (the same class): where crew can be hired her job WAITS with E_CREW_SHORT ("Crew 7 / 8"), nothing issued; the Inn's quote (cmd.preview 'HIRE n') is the price cmd.issue takes; manned, the very next run starts her
-- @pass FS_NO_HANDS short of crew where no crew can be hired (the quay has no hands: the hire door's own E_CREW_POOL) her job STOPS on E_CREW_SHORT with nothing issued, is not asked while she is short, and goes on once manned
-- @pass FS_ONE_RULE voyage.sail_refusal and public.fleet_unfit give one answer, wrecked and fit; a dead flagship beside a live escort is unfit too
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0499-4000-8000-0000000002a1';
  v_isl   uuid := (select p.id from public.ports p where p.code = 'ISL' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_fa    uuid;
  v_r     jsonb;
  v_q     jsonb;
  v_q1    jsonb;
  v_w     jsonb;
  v_j     record;
  v_o     uuid;
  v_cost  bigint;
  v_purse bigint;
  v_n     bigint;
  v_texts text;
begin
  v_a := public.new_house(c_a, 'Casa do Reparo 202', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;
  perform cmd.assume_identity(c_a);
  perform public.land_party(v_a);
  if not public.port_has_shipyard(v_isl) then
    raise exception 'FS_WAIT: Island of Mozambique has no shipyard in this world: the scene proves nothing';
  end if;
  update public.fleets set port_id = v_isl, status = 'DOCKED', ready_at = null where id = v_fa;
  v_r := cmd.set_fleet_job(v_fa, 'land', '{"to": "CAD"}'::jsonb);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'FS_WAIT: the door refused a healthy fleet: %', v_r;
  end if;

  -- FS_WAIT: every hull at 0 (as the ransom and the tow left her: DOCKED at a yard)
  update public.ships set durability = 0 where fleet_id = v_fa;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.paused_reason is not null or v_j.runs <> 0 or v_j.last->>'wait' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_j.last->>'sentence' is distinct from 'the flagship is not fit to sail' or v_j.next_at is null or v_j.next_at <= now()
     or exists (select 1 from public.orders o where o.fleet_id = v_fa)
     or (select r.receipt #>> '{steps,0,wait}' from public.fleet_job_runs r where r.at = now()) is distinct from 'unfit' then
    raise exception 'FS_WAIT: the wrecked fleet''s job did not wait with nothing issued: % / %', to_jsonb(v_j), (select r.receipt from public.fleet_job_runs r where r.at = now());
  end if;
  call public.tick_fleet_jobs(false);
  if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 0 then
    raise exception 'FS_WAIT: a job waiting for her repair was asked again by the very next run';
  end if;
  raise notice 'PASS: FS_WAIT — runs %, no order, not stopped, waits "%"; the next run asks nothing', v_j.runs, v_j.last->>'sentence';

  -- FS_ROW
  v_w := (select w from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text);
  if v_w->>'state' is distinct from 'waiting' or v_w #>> '{wait,code}' is distinct from 'E_FLAGSHIP_DISABLED'
     or v_w #>> '{wait,sentence}' is distinct from 'the flagship is not fit to sail' or (v_w #>> '{wait,retry_at}')::timestamptz is null
     or v_w->'stop' <> 'null'::jsonb or v_w->>'worker_state' is distinct from 'wrecked' or public.fleet_state(v_fa) is distinct from 'wrecked' then
    raise exception 'FS_ROW: her row does not say she waits for her repair: %', v_w;
  end if;
  raise notice 'PASS: FS_ROW — state %, wait %, worker_state %', v_w->>'state', v_w->'wait', v_w->>'worker_state';

  -- FS_DOOR
  v_r := cmd.set_fleet_job(v_fa, 'best', '{}'::jsonb);
  if (v_r->>'ok')::boolean is not false or v_r->>'error_code' is distinct from 'E_FLAGSHIP_DISABLED' or v_r->>'error_message' not ilike '%the flagship is not fit to sail%'
     or (select j.kind || ':' || (j.last->>'wait') from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'land:E_FLAGSHIP_DISABLED' then
    raise exception 'FS_DOOR: the door did not refuse her: %', v_r;
  end if;
  raise notice 'PASS: FS_DOOR — % "%"; fixes %', v_r->>'error_code', v_r->>'error_message', v_r->'fixes';

  -- FS_PURSE: the yard's quote, then an empty purse
  v_q := cmd.preview(v_fa, 'REPAIR');
  v_cost := (v_q #>> '{estimate,cost}')::bigint;
  if (v_q->>'ok')::boolean is not true or v_cost is null or v_cost <= 0 then
    raise exception 'FS_PURSE: the yard gave no quote for her: %', v_q;
  end if;
  update public.players set ducats = 0 where id = v_a;
  v_r := cmd.preview(v_fa, 'REPAIR');
  v_q1 := cmd.issue(v_fa, 'REPAIR', null, null);
  if v_r->>'error_code' is distinct from 'E_INSUFFICIENT_FUNDS'
     or exists (select 1 from public.ships s where s.fleet_id = v_fa and s.durability > 0)
     or (select f.status from public.fleets f where f.id = v_fa) <> 'DOCKED' then
    raise exception 'FS_PURSE: an empty purse was not refused: % / %', v_r, left(v_q1::text, 400);
  end if;
  -- FS_QUEUE_AT: that refused REPAIR stands in her served queue with its time
  if (select count(*) from jsonb_array_elements(cmd.queue(v_fa)) q
       where q->>'status' = 'failed' and q->>'error_code' = 'E_INSUFFICIENT_FUNDS' and (q->>'at')::timestamptz = now()) <> 1
     or exists (select 1 from jsonb_array_elements(cmd.queue(v_fa)) q where not (q ? 'at'))
     or exists (select 1 from jsonb_array_elements(cmd.queue(v_fa)) q where q->>'status' = 'pending' and q->>'at' is not null) then
    raise exception 'FS_QUEUE_AT: the served queue does not say when her refused order ran: %', cmd.queue(v_fa);
  end if;
  raise notice 'PASS: FS_QUEUE_AT — %', (select jsonb_agg(jsonb_build_object('text', q->'text', 'status', q->'status', 'at', q->'at')) from jsonb_array_elements(cmd.queue(v_fa)) q);
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active', 'failed');
  call public.tick_fleet_jobs(false);
  if (select j.paused_reason is not null or j.runs <> 0 from public.fleet_jobs j where j.fleet_id = v_fa) then
    raise exception 'FS_PURSE: she does not still wait after the yard refused her purse';
  end if;
  update public.players set ducats = 5000000 where id = v_a;
  v_q1 := cmd.preview(v_fa, 'REPAIR TO 10');
  if (v_q1->>'ok')::boolean is not true or (v_q1 #>> '{estimate,cost}')::bigint >= v_cost then
    raise exception 'FS_PURSE: REPAIR TO 10 is not cheaper than the whole repair: % against %', v_q1, v_cost;
  end if;
  raise notice 'PASS: FS_PURSE — the whole repair costs %; an empty purse: % "%" (%); REPAIR TO 10 costs %', v_cost, v_r->>'error_code', v_r->>'error_message', v_r->'figures', v_q1 #>> '{estimate,cost}';

  -- FS_REPAIR: the real yard
  v_purse := (select ducats from public.players where id = v_a);
  v_r := cmd.issue(v_fa, 'REPAIR', null, null);
  if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fa) <> 'REPAIRING'
     or v_purse - (select ducats from public.players where id = v_a) <> v_cost then
    raise exception 'FS_REPAIR: the yard did not take her at the quoted price %: % (purse % -> %)', v_cost, left(v_r::text, 400), v_purse, (select ducats from public.players where id = v_a);
  end if;
  call public.tick_fleet_jobs(false);
  if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 0 then
    raise exception 'FS_REPAIR: she was asked while in the yard';
  end if;
  update public.fleets set busy_until = now() - interval '1 second' where id = v_fa;
  perform cmd.advance(v_fa);
  if (select f.status from public.fleets f where f.id = v_fa) <> 'DOCKED' or public.fleet_unfit(v_fa) is not null then
    raise exception 'FS_REPAIR: she did not come out of the yard fit';
  end if;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  select string_agg(o.raw_text, ' / ' order by o.seq), count(*) into v_texts, v_n from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
  if v_j.paused_reason is not null or v_j.runs <> 1 or v_n < 2 or v_texts not like 'SAIL % / SAIL LIS'
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'FS_REPAIR: mended, she did not go on by herself at the next run: % / %', to_jsonb(v_j), v_texts;
  end if;
  raise notice 'PASS: FS_REPAIR — quote % = paid %; not asked in the yard; out of it the next run: % (% legs), runs %', v_cost, v_cost, v_texts, v_n, v_j.runs;

  -- FS_STOPPED: prod's row: stopped on the code, its failed plan behind it, she wrecked at ISL
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl, ready_at = null where id = v_fa;
  update public.ships set durability = 0 where fleet_id = v_fa;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code, error_message)
  values (v_fa, v_a, (select coalesce(max(o.seq), 0) + 1 from public.orders o where o.fleet_id = v_fa), 'SAIL SOF', 'SAIL', '{}'::jsonb, 'failed',
          'E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail') returning id into v_o;
  update public.orders set plan_id = v_o where id = v_o;
  update public.fleet_jobs set paused_reason = 'E_FLAGSHIP_DISABLED', last_plan = v_o, next_at = null,
         last = jsonb_build_object('at', now() - interval '1 day', 'ok', false, 'code', 'E_FLAGSHIP_DISABLED', 'sentence', 'the flagship is not fit to sail')
   where fleet_id = v_fa;
  v_n := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  v_w := (select w from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text);
  if (select j.paused_reason from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_FLAGSHIP_DISABLED'
     or (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 0
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_n
     or v_w->>'state' is distinct from 'stopped' or v_w #>> '{stop,code}' is distinct from 'E_FLAGSHIP_DISABLED' then
    raise exception 'FS_STOPPED: a job stopped on the code was asked while she is wrecked, or her row lost its stop: %', v_w;
  end if;
  v_r := cmd.issue(v_fa, 'REPAIR', null, null);
  update public.fleets set busy_until = now() - interval '1 second' where id = v_fa;
  perform cmd.advance(v_fa);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if (v_r->>'ok')::boolean is not true or v_j.paused_reason is not null or v_j.runs <> 2 or v_j.last_plan is not distinct from v_o
     or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'FS_STOPPED: the stopped job did not go on after her repair: % / %', to_jsonb(v_j), left(v_r::text, 300);
  end if;
  raise notice 'PASS: FS_STOPPED — stopped on the code: not asked while wrecked (her row: stop); repaired: the next run starts her, runs %', v_j.runs;

  -- FS_CREW: docked at ISL, fit, one hand short of what her flagship needs; hands on the quay
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl, ready_at = null where id = v_fa;
  update public.ports set crew_pool = 50 where id = v_isl;
  update public.ships s set crew = c.crew_required - 1 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fa;
  v_n := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  v_w := (select w from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text);
  if v_j.paused_reason is not null or v_j.runs <> 2 or v_j.last->>'wait' is distinct from 'E_CREW_SHORT' or v_j.last->>'sentence' not like 'Crew % / %'
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_n
     or v_w->>'state' is distinct from 'waiting' or v_w #>> '{wait,code}' is distinct from 'E_CREW_SHORT' or v_w->'stop' <> 'null'::jsonb
     or voyage.sail_refusal(v_fa, null, null, 0) is distinct from public.fleet_unfit(v_fa) then
    raise exception 'FS_CREW: short of crew, her job did not wait with nothing issued: % / %', to_jsonb(v_j), v_w;
  end if;
  v_q := cmd.preview(v_fa, 'HIRE 1');
  v_cost := (v_q #>> '{estimate,cost}')::bigint;
  v_purse := (select ducats from public.players where id = v_a);
  v_r := cmd.issue(v_fa, 'HIRE 1', null, null);
  if (v_q->>'ok')::boolean is not true or v_cost is null or (v_r->>'ok')::boolean is not true
     or v_purse - (select ducats from public.players where id = v_a) <> v_cost or public.fleet_unfit(v_fa) is not null then
    raise exception 'FS_CREW: the Inn did not man her at the quoted price %: % / %', v_cost, v_q, left(v_r::text, 300);
  end if;
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_j.paused_reason is not null or v_j.runs <> 3 or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'FS_CREW: manned, she did not go on at the next run: %', to_jsonb(v_j);
  end if;
  raise notice 'PASS: FS_CREW — waits "%" (%), no order; HIRE 1 quote % = paid %; manned, the next run starts her, runs %', v_w #>> '{wait,sentence}', v_w #>> '{wait,code}', v_cost, v_cost, v_j.runs;

  -- FS_NO_HANDS: the same, and the quay has no hands
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl, ready_at = null where id = v_fa;
  update public.ports set crew_pool = 0 where id = v_isl;
  update public.ships s set crew = c.crew_required - 1 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fa;
  v_n := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  v_w := (select w from jsonb_array_elements(world.workers()->'workers') w where w->>'fleet' = v_fa::text);
  v_q := cmd.preview(v_fa, 'HIRE 1');
  if v_j.paused_reason is distinct from 'E_CREW_SHORT' or v_j.runs <> 3 or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_n
     or v_w->>'state' is distinct from 'stopped' or v_w #>> '{stop,code}' is distinct from 'E_CREW_SHORT' or v_w #>> '{stop,sentence}' not like 'Crew % / %'
     or v_q->>'error_code' is distinct from 'E_CREW_POOL' or public.port_hires(v_isl) then
    raise exception 'FS_NO_HANDS: with no hands on the quay her job did not stop with nothing issued: % / % / %', to_jsonb(v_j), v_w, v_q;
  end if;
  call public.tick_fleet_jobs(false);
  if (select jsonb_array_length(r.receipt->'steps') from public.fleet_job_runs r where r.at = now()) <> 0 then
    raise exception 'FS_NO_HANDS: a job stopped for want of crew was asked while she is short';
  end if;
  update public.ports set crew_pool = 50 where id = v_isl;
  v_r := cmd.issue(v_fa, 'HIRE 1', null, null);
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
  if (v_r->>'ok')::boolean is not true or v_j.paused_reason is not null or v_j.runs <> 4 or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING' then
    raise exception 'FS_NO_HANDS: manned, the stopped job did not go on: % / %', to_jsonb(v_j), left(v_r::text, 300);
  end if;
  raise notice 'PASS: FS_NO_HANDS — no hands: stopped on % ("%"), the hire door %; not asked while short; manned: runs %', v_w #>> '{stop,code}', v_w #>> '{stop,sentence}', v_q->>'error_code', v_j.runs;

  -- FS_ONE_RULE
  update public.orders set status = 'cancelled' where fleet_id = v_fa and status in ('pending', 'active');
  update public.voyages set status = 'ARRIVED' where fleet_id = v_fa and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_isl, ready_at = null where id = v_fa;
  if voyage.sail_refusal(v_fa, null, null, 0) is not null or public.fleet_unfit(v_fa) is not null then
    raise exception 'FS_ONE_RULE: a fit fleet is refused: % / %', voyage.sail_refusal(v_fa, null, null, 0), public.fleet_unfit(v_fa);
  end if;
  -- a live escort beside a dead flagship: the state rule says port (a hull is above 0), the fitness rule says she cannot sail
  insert into public.ships (fleet_id, player_id, class_id, name, durability, crew, is_flagship)
  select s.fleet_id, s.player_id, s.class_id, 'Escolta 202', s.durability, s.crew, false from public.ships s where s.fleet_id = v_fa and s.is_flagship;
  update public.ships set durability = 0 where fleet_id = v_fa and is_flagship;
  if voyage.sail_refusal(v_fa, null, null, 0) is distinct from public.fleet_unfit(v_fa) or public.fleet_unfit(v_fa)->>'code' is distinct from 'E_FLAGSHIP_DISABLED'
     or public.fleet_unfit(v_fa)->>'sentence' is distinct from 'the flagship is not fit to sail' or public.fleet_state(v_fa) is distinct from 'port' then
    raise exception 'FS_ONE_RULE: the sail and the rule disagree: % / % (state %)', voyage.sail_refusal(v_fa, null, null, 0), public.fleet_unfit(v_fa), public.fleet_state(v_fa);
  end if;
  call public.tick_fleet_jobs(false);
  if (select j.last->>'wait' from public.fleet_jobs j where j.fleet_id = v_fa) is distinct from 'E_FLAGSHIP_DISABLED' then
    raise exception 'FS_ONE_RULE: a fleet with a dead flagship and a live escort was planned';
  end if;
  raise notice 'PASS: FS_ONE_RULE — one answer, fit (null) and wrecked (%); a dead flagship beside a live escort: state %, not planned', public.fleet_unfit(v_fa)->>'code', public.fleet_state(v_fa);
end
$p$;
