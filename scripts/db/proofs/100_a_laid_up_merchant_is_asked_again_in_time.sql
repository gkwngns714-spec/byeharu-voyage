-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 100 - A LAID-UP MERCHANT IS ASKED AGAIN IN TIME  (migration 0405; docs/dev-log/2026-11-14-layup-line.md)
--
--   On the world's own merchants, rolled back with proof.mjs's transaction. 45 merchants in port are laid up by hand: 40 due (their last
--   ask an hour or more back; ten of them with an empty purse, so that some must wait whatever the market) and 5 not due (asked five minutes ago). The job's own pass is run as the job runs it, without commits
--   (public.tick_waiting_asks(false)). Nothing here reads a price, the world's secret or what the planner CHOOSES: a merchant asked either
--   waits on or is resumed, and both are right; what is proved is who is asked, in what order, by which hand, and under which lock.
--
-- @pass LL_OFF       npc_ask_job_ms 0: the job asks nobody and stamps nobody
-- @pass LL_NO_QUAY   the plan step alone, for three merchants: each is stamped and planned and this session holds no advisory lock: the quay is not taken
-- @pass LL_ORDER     a budget of one ask: exactly one merchant is asked, the one whose last ask is oldest
-- @pass LL_ALL       one pass: every merchant still due (39) is asked once and stamped; the receipt counts them; none failed, none busy; nobody is left due
-- @pass LL_OUTCOME   each merchant asked either still waits (laid up) or was resumed (the pause lifted, her lap open); the receipt's counts are her routes' own; the ten staged with no purse all wait on
-- @pass LL_NOT_DUE   the five asked five minutes ago are not asked: their stamps and routes are as they were
-- @pass LL_TWO_HANDS after the job's pass the beat's own hand (public.npc_ask_waiting) finds nobody due; and a second pass of the job asks nobody
-- @pass LL_STAMP     the open step refuses a merchant another hand has asked since (her stamp moved): 0, and she stays laid up; it holds the quay; with her own stamp she goes through the resume door
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_n      int;
  v_r      jsonb;
  v_f      uuid;
  v_old    uuid;
  v_route  uuid;
  v_stamp  timestamptz;
  v_a      int;
  v_bad    text;
  v_k      int := 0;
  r        record;
begin
  -- ── THE SCENE: the merchants lit, every one on her route where she lies; 45 of those in port at their first stop laid up by hand ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  if not public.npc_traders_on() then raise exception 'proof 100: the merchants cannot be lit in this world'; end if;
  update public.world_config set value = to_jsonb(greatest(public.wc_int('npc_fleet_max'), (select count(*)::int from public.npc_fleets))) where key = 'npc_fleet_max';
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  create temp table ll100 on commit drop as
  select ro.fleet_id, ro.route_id, ro.k, row_number() over (order by ro.k) as i, null::timestamptz as stamp0, false as due
    from public.npc_tend_roster() ro
    join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = ro.route_id and sr.fleet_id = ro.fleet_id
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where not exists (select 1 from public.orders o where o.fleet_id = ro.fleet_id and o.status in ('pending', 'failed'))
   order by ro.k limit 45;
  if (select count(*) from ll100) <> 45 then
    raise exception 'proof 100: only % merchants lie in port at their first stop; 45 are wanted', (select count(*) from ll100);
  end if;
  update ll100 set due = i <= 40;
  update public.standing_routes sr set paused_reason = 'laid_up',
         updated_at = now() - make_interval(mins => case when l.due then 60 + l.i::int else 5 end)
    from ll100 l where l.route_id = sr.id;
  update public.npc_fleets nf set asked_at = case when l.due then null else now() - interval '5 minutes' end
    from ll100 l where l.fleet_id = nf.fleet_id;
  update ll100 l set stamp0 = nf.asked_at from public.npc_fleets nf where nf.fleet_id = l.fleet_id;
  -- ten of the due have no purse: every parcel of theirs is sized to nothing (0129), so their plans cannot pay, whatever the market: they must wait on
  update public.players p set ducats = 0 from ll100 l join public.standing_routes sr on sr.id = l.route_id where sr.player_id = p.id and l.i <= 10;
  if (select count(*) from public.npc_waiting_queue(now()) q join ll100 l on l.fleet_id = q.fleet_id where q.due_at <= now()) <> 40
     or (select count(*) from public.npc_waiting_queue(now()) q where q.due_at <= now()) <> 40 then
    raise exception 'proof 100: the scene is not 40 due merchants (the queue reads % due)', (select count(*) from public.npc_waiting_queue(now()) q where q.due_at <= now());
  end if;
  select l.fleet_id into v_old from ll100 l where l.i = 40;   -- her last ask is the oldest (100 minutes back)

  -- ── LL_OFF ──
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_job_ms';
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if (v_r->>'asked')::int <> 0 or (v_r->>'due_left')::int <> 40 or (v_r->>'line')::int <> 45
     or exists (select 1 from ll100 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id where nf.asked_at is distinct from l.stamp0) then
    raise exception 'LL_OFF: off, the job asked or stamped: %', v_r;
  end if;
  raise notice 'PASS: LL_OFF npc_ask_job_ms 0: asked 0, the line 45, due 40, no stamp moved';

  -- ── LL_NO_QUAY ──
  for r in select l.fleet_id from ll100 l where l.due and l.i in (37, 38, 39) order by l.i desc loop
    v_a := public.waiting_ask_plan(r.fleet_id);
    if v_a not in (0, 1) or (select nf.asked_at from public.npc_fleets nf where nf.fleet_id = r.fleet_id) is distinct from now() then
      raise exception 'LL_NO_QUAY: the plan step answered % for a due merchant, or did not stamp her', v_a;
    end if;
    v_k := v_k + 1;
  end loop;
  if exists (select 1 from pg_locks k where k.locktype = 'advisory' and k.pid = pg_backend_pid()) then
    raise exception 'LL_NO_QUAY: the plan step took an advisory lock: the quay, or another';
  end if;
  if public.waiting_ask_plan((select l.fleet_id from ll100 l where l.i = 39)) <> 0 then
    raise exception 'LL_NO_QUAY: a merchant just stamped was planned again';
  end if;
  raise notice 'PASS: LL_NO_QUAY the plan step stamped and planned % merchants and this session holds no advisory lock; asked again at once it answers 0', v_k;
  -- those three go back in the line, due (the plan step never resumes: they are laid up still)
  update public.npc_fleets nf set asked_at = null from ll100 l where l.fleet_id = nf.fleet_id and l.due;
  update public.standing_routes sr set paused_reason = 'laid_up', hold_until = null, updated_at = now() - make_interval(mins => 60 + l.i::int)
    from ll100 l where l.route_id = sr.id and l.due;
  select count(*) into v_n from public.npc_waiting_queue(now()) q where q.due_at <= now();
  if v_n <> 40 then raise exception 'proof 100: the line was not put back (% due)', v_n; end if;

  -- ── LL_ORDER ──
  update public.world_config set value = to_jsonb(1) where key = 'npc_ask_job_ms';
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if (v_r->>'asked')::int <> 1 or (select nf.asked_at from public.npc_fleets nf where nf.fleet_id = v_old) is distinct from now()
     or (select count(*) from ll100 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id where l.due and nf.asked_at = now()) <> 1 then
    raise exception 'LL_ORDER: a budget of one ask did not ask the oldest alone: %', v_r;
  end if;
  raise notice 'PASS: LL_ORDER a budget of 1 ms asked exactly one merchant, the one waiting longest (% ms)', v_r->>'plan_ms';

  -- ── LL_ALL ── (the oldest was asked by LL_ORDER: 39 are due)
  update public.world_config set value = to_jsonb(600000) where key = 'npc_ask_job_ms';
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if (v_r->>'asked')::int <> 39 or (v_r->>'failed')::int <> 0 or (v_r->>'busy')::int <> 0 or (v_r->>'due_left')::int <> 0
     or (v_r->>'waiting')::int + (v_r->>'resumed')::int + (v_r->>'gone')::int <> 39
     or exists (select 1 from ll100 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id where l.due and nf.asked_at is distinct from now()) then
    raise exception 'LL_ALL: the pass did not ask every due merchant once: % (note %)', v_r - 'note', v_r->>'note';
  end if;
  raise notice 'PASS: LL_ALL one pass asked all 39 merchants still due, each stamped: waiting %, resumed %, gone %, failed 0, busy 0, nobody left due; plan % ms (max %), open % ms',
    v_r->>'waiting', v_r->>'resumed', v_r->>'gone', v_r->>'plan_ms', v_r->>'plan_ms_max', v_r->>'open_ms';

  -- ── LL_OUTCOME ──
  select string_agg(l.i::text, ' ') into v_bad
    from ll100 l join public.standing_routes sr on sr.id = l.route_id
   where l.due and not (sr.paused_reason = 'laid_up' or (sr.paused_reason is null and sr.lap_id is not null));
  if v_bad is not null then
    raise exception 'LL_OUTCOME: merchants neither waiting nor sailing a lap after the ask: %', v_bad;
  end if;
  if (select count(*) from ll100 l join public.standing_routes sr on sr.id = l.route_id where l.due and l.i < 40 and sr.paused_reason = 'laid_up') <> (v_r->>'waiting')::int
     or (select count(*) from ll100 l join public.standing_routes sr on sr.id = l.route_id where l.due and l.i < 40 and sr.paused_reason is null) <> (v_r->>'resumed')::int then
    raise exception 'LL_OUTCOME: the receipt (%) does not count her routes', v_r - 'note';
  end if;
  select count(*) into v_n from ll100 l join public.standing_routes sr on sr.id = l.route_id where l.i <= 10 and sr.paused_reason = 'laid_up';
  if v_n <> 10 or (v_r->>'waiting')::int < 10 then
    raise exception 'LL_OUTCOME: of the ten merchants with no purse % wait on (the receipt counts % waiting)', v_n, v_r->>'waiting';
  end if;
  raise notice 'PASS: LL_OUTCOME every merchant asked waits on (%) or sails a lap (%), as the receipt counts them; the ten with no purse all wait on, asked and stamped', v_r->>'waiting', v_r->>'resumed';

  -- ── LL_NOT_DUE ──
  if exists (select 1 from ll100 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id join public.standing_routes sr on sr.id = l.route_id
              where not l.due and (nf.asked_at is distinct from l.stamp0 or sr.paused_reason is distinct from 'laid_up'
                                   or sr.updated_at <> now() - interval '5 minutes')) then
    raise exception 'LL_NOT_DUE: a merchant asked five minutes ago was asked or written';
  end if;
  raise notice 'PASS: LL_NOT_DUE the 5 merchants asked five minutes ago kept their stamps and their routes';

  -- ── LL_TWO_HANDS ──
  v_n := (public.npc_ask_waiting(now(), clock_timestamp() + interval '10 seconds')->>'asked')::int;
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if v_n <> 0 or (v_r->>'asked')::int <> 0 then
    raise exception 'LL_TWO_HANDS: after the pass the beat''s hand asked % and a second pass %', v_n, v_r->>'asked';
  end if;
  raise notice 'PASS: LL_TWO_HANDS after the pass the beat''s hand asks 0 and a second pass asks 0: one queue, one stamp';

  -- ── LL_STAMP ── (a merchant not due is used: her lines are whatever they are; only the door is read)
  select l.fleet_id, l.route_id, l.stamp0 into v_f, v_route, v_stamp from ll100 l where not l.due order by l.i limit 1;
  if public.waiting_ask_open(v_f, v_stamp - interval '1 second') <> 0
     or (select sr.paused_reason from public.standing_routes sr where sr.id = v_route) is distinct from 'laid_up' then
    raise exception 'LL_STAMP: the open step resumed a merchant whose stamp is another hand''s';
  end if;
  if not exists (select 1 from pg_locks k where k.locktype = 'advisory' and k.pid = pg_backend_pid()) then
    raise exception 'LL_STAMP: the open step did not take the quay';
  end if;
  -- with her own stamp the resume door runs (it dates her route); the route's own lap start may then lay her up again (0181): both are right
  v_a := public.waiting_ask_open(v_f, v_stamp);
  if v_a <> 1
     or (select sr.updated_at from public.standing_routes sr where sr.id = v_route) <> now() then
    raise exception 'LL_STAMP: the open step did not put a laid-up merchant with her own stamp through the resume door';
  end if;
  raise notice 'PASS: LL_STAMP the open step answers 0 for a moved stamp (she stays laid up, her route unwritten), holds the quay, and with her own stamp puts her through the resume door';
end $p$;
