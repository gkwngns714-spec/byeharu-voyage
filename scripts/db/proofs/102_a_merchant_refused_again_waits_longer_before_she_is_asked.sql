-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 102 - A MERCHANT REFUSED AGAIN WAITS LONGER BEFORE SHE IS ASKED  (migration 0407; docs/dev-log/2026-11-14-ask-backoff.md)
--
--   On the world's own merchants, rolled back with proof.mjs's transaction. Merchants in port are laid up by hand and their last ask and their
--   count of refusals staged. No price and no choice of the planner is asserted: the merchants who MUST be refused are given an empty purse (no
--   parcel can be bought, 0129), and the reset is read on whichever merchants' plans pay.
--
-- @pass BO_STEPS   the due rule by the queue itself: 0 or 1 refusals in a row due 10 minutes after the last ask, 2 due 20, 3 due 40, 4 and 9 due 50 (the cap: the reconcile's 60 less one step); overdue at 60 as before
-- @pass BO_COUNT   the planner is the count's writer: a house with an empty purse planned at her lap start is laid up with 1; asked again by the job she has 2 and is due 20 minutes on, then 3 and 40
-- @pass BO_RESET   a sail resets: of the merchants staged with 3 refusals and asked by the job, every one whose plan pays has 0 and every one refused has 4; some pay (not vacuous)
-- @pass BO_BROKE   a broke house (purse under npc_ask_broke_under) is due at the cap from her first refusal: the job's pass 11 minutes after her ask does not ask her; she is due at 50 and overdue (the reconcile's) at 60; with the knob at 0 she is due at 10
-- @pass BO_NEW     with 200 merchants in the line refused four times and asked 15 minutes ago, a merchant newly laid up and asked 10.5 minutes ago is the one merchant the job's pass asks
-- @pass BO_ONE     the beat's hand reads the same rule: with those 200 in the line and nobody due, public.npc_ask_waiting asks 0; put 51 minutes back, it finds them due
-- @pass BO_QUAY    the job's receipt tells the wait for the quay apart (quay_ms, quay_ms_max)
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_r      jsonb;
  v_n      int;
  v_s      text := '';
  v_k      int;
  v_one    uuid;
  v_one_r  uuid;
  v_one_p  uuid;
  v_new    uuid;
  v_paid   int;
  v_ref    int;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  if not public.npc_traders_on() then raise exception 'proof 102: the merchants cannot be lit in this world'; end if;
  update public.world_config set value = to_jsonb(10) where key = 'npc_replan_every_minutes';
  update public.world_config set value = to_jsonb(60) where key = 'npc_replan_within_minutes';
  update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
  update public.world_config set value = to_jsonb(600000) where key = 'npc_ask_job_ms';
  -- 0423: this proof is of 0407's back-off as written (10, 20, 40, then 50); the half-hour cap is proof 120's
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_wait_max_minutes';
  update public.world_config set value = to_jsonb(greatest(public.wc_int('npc_fleet_max'), (select count(*)::int from public.npc_fleets))) where key = 'npc_fleet_max';
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  create temp table bo102 on commit drop as
  select ro.fleet_id, ro.route_id, sr.player_id, row_number() over (order by ro.k) as i
    from public.npc_tend_roster() ro
    join public.fleets f on f.id = ro.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = ro.route_id and sr.fleet_id = ro.fleet_id
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where not exists (select 1 from public.orders o where o.fleet_id = ro.fleet_id and o.status in ('pending', 'failed'))
     and (select count(*) from public.npc_fleets x where x.player_id = sr.player_id) = 1   -- one fleet a house: her purse is hers alone
   order by ro.k limit 222;
  if (select count(*) from bo102) < 222 then
    raise exception 'proof 102: only % one-fleet merchants lie in port at their first stop; 222 are wanted', (select count(*) from bo102);
  end if;
  update public.players p set ducats = greatest(p.ducats, 5000) from bo102 l where l.player_id = p.id;
  -- i = 1: the steps and the count; 2..11: the reset; 12: the broke house; 13..212: the 200 old refusals; 213: the new lay-up
  select l.fleet_id, l.route_id, l.player_id into v_one, v_one_r, v_one_p from bo102 l where l.i = 1;

  -- ── BO_STEPS ──
  update public.standing_routes set paused_reason = 'laid_up', updated_at = now() - interval '3 hours' where id = v_one_r;
  foreach v_k in array array[0, 1, 2, 3, 4, 9] loop
    update public.npc_fleets set refused = v_k, asked_at = null where fleet_id = v_one;
    v_s := v_s || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_one) || ' ';
  end loop;
  if v_s <> '10 10 20 40 50 50 ' or not (select q.overdue from public.npc_waiting_queue(now()) q where q.fleet_id = v_one) then
    raise exception 'BO_STEPS: the steps are "%", not "10 10 20 40 50 50"; or a merchant asked three hours ago is not overdue', v_s;
  end if;
  update public.standing_routes set updated_at = now() - interval '59 minutes' where id = v_one_r;
  if (select q.overdue from public.npc_waiting_queue(now()) q where q.fleet_id = v_one) then
    raise exception 'BO_STEPS: a merchant asked 59 minutes ago is overdue';
  end if;
  raise notice 'PASS: BO_STEPS refusals 0 1 2 3 4 9 are due % minutes after the last ask; overdue at 60 as before', v_s;

  -- ── BO_COUNT ── (an empty purse: no parcel, so no loop pays, whatever the market)
  update public.players set ducats = 0 where id = v_one_p;
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_broke_under';   -- the count alone, without the broke rule
  update public.standing_routes set paused_reason = null, updated_at = now() - interval '3 hours' where id = v_one_r;
  update public.npc_fleets set refused = 0, asked_at = null where fleet_id = v_one;
  v_r := public.npc_plan(now(), v_one_r);
  if coalesce((v_r->>'waiting')::int, 0) <> 1 or (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_one) <> 1
     or (select sr.paused_reason from public.standing_routes sr where sr.id = v_one_r) is distinct from 'laid_up' then
    raise exception 'BO_COUNT: a house with an empty purse planned at her lap start is not laid up with 1 refusal: %', v_r - 'notes';
  end if;
  for v_k in 2 .. 3 loop
    update public.standing_routes set updated_at = now() - interval '3 hours' where id = v_one_r;
    update public.npc_fleets set asked_at = null where fleet_id = v_one;
    call public.tick_waiting_asks(false, v_one);
    select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
    if (v_r->>'asked')::int <> 1 or (v_r->>'waiting')::int <> 1 or (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_one) <> v_k
       or (select round(extract(epoch from q.due_at - q.asked_at) / 60) from public.npc_waiting_queue(now()) q where q.fleet_id = v_one) <> 10 * power(2, v_k - 1) then
      raise exception 'BO_COUNT: asked by the job, her count is not % or her next ask not % minutes on: receipt %, refused %', v_k, 10 * power(2, v_k - 1), v_r - 'note',
        (select nf.refused from public.npc_fleets nf where nf.fleet_id = v_one);
    end if;
  end loop;
  raise notice 'PASS: BO_COUNT a house with an empty purse: laid up by the planner with 1 refusal; asked by the job, 2 and due 20 minutes on; asked again, 3 and due 40';
  update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
  update public.standing_routes set updated_at = now() where id = v_one_r;   -- out of the way: just asked

  -- ── BO_RESET ── (ten merchants staged with three refusals, due; five of them with an empty purse so that some are refused whatever the market)
  update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - interval '3 hours' from bo102 l where l.route_id = sr.id and l.i between 2 and 11;
  update public.npc_fleets nf set refused = 3, asked_at = null from bo102 l where l.fleet_id = nf.fleet_id and l.i between 2 and 11;
  update public.players p set ducats = 0 from bo102 l where l.player_id = p.id and l.i between 7 and 11;
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_broke_under';
  call public.tick_waiting_asks(false);
  update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  select count(*) filter (where sr.paused_reason is distinct from 'laid_up' or nf.refused = 0), count(*) filter (where sr.paused_reason = 'laid_up' and nf.refused = 4)
    into v_paid, v_ref
    from bo102 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id join public.standing_routes sr on sr.id = l.route_id where l.i between 2 and 11;
  if (v_r->>'asked')::int <> 10 or v_paid + v_ref <> 10 or v_ref < 5 or v_paid < 1
     or exists (select 1 from bo102 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id join public.standing_routes sr on sr.id = l.route_id
                 where l.i between 2 and 11 and ((sr.paused_reason is null and nf.refused <> 0) or (l.i >= 7 and nf.refused <> 4))) then
    raise exception 'BO_RESET: of ten merchants staged at 3 refusals, % have 0 (paid) and % have 4 (refused); wanted every one either, the five with no purse at 4, and at least one paid. Receipt %', v_paid, v_ref, v_r - 'note';
  end if;
  raise notice 'PASS: BO_RESET of ten merchants staged with 3 refusals and asked by the job, % paid and have 0, % were refused and have 4 (the five with no purse among them)', v_paid, v_ref;
  update public.standing_routes sr set updated_at = now() from bo102 l where l.route_id = sr.id and l.i between 2 and 11 and sr.paused_reason = 'laid_up';

  -- ── BO_BROKE ──
  update public.players p set ducats = 99 from bo102 l where l.player_id = p.id and l.i = 12;
  update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - interval '11 minutes' from bo102 l where l.route_id = sr.id and l.i = 12;
  update public.npc_fleets nf set refused = 1, asked_at = null from bo102 l where l.fleet_id = nf.fleet_id and l.i = 12;
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if (v_r->>'asked')::int <> 0
     or (select round(extract(epoch from q.due_at - q.asked_at) / 60) from public.npc_waiting_queue(now()) q join bo102 l on l.fleet_id = q.fleet_id where l.i = 12) <> 50 then
    raise exception 'BO_BROKE: a broke house asked 11 minutes ago was asked by the job, or is not due at 50 minutes: %', v_r - 'note';
  end if;
  update public.standing_routes sr set updated_at = now() - interval '61 minutes' from bo102 l where l.route_id = sr.id and l.i = 12;
  if not (select q.overdue and q.due_at <= now() from public.npc_waiting_queue(now()) q join bo102 l on l.fleet_id = q.fleet_id where l.i = 12) then
    raise exception 'BO_BROKE: a broke house asked 61 minutes ago is not due and overdue (the reconcile''s)';
  end if;
  update public.world_config set value = to_jsonb(0) where key = 'npc_ask_broke_under';
  if (select round(extract(epoch from q.due_at - q.asked_at) / 60) from public.npc_waiting_queue(now()) q join bo102 l on l.fleet_id = q.fleet_id where l.i = 12) <> 10 then
    raise exception 'BO_BROKE: with npc_ask_broke_under 0 a house of 99 d. refused once is not due at 10 minutes';
  end if;
  update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
  update public.standing_routes sr set updated_at = now() from bo102 l where l.route_id = sr.id and l.i = 12;
  raise notice 'PASS: BO_BROKE a house of 99 d. refused once: not asked by the job 11 minutes after her ask, due at 50, overdue at 60; with the knob at 0 due at 10';

  -- ── BO_NEW ──
  update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - interval '15 minutes' from bo102 l where l.route_id = sr.id and l.i between 13 and 212;
  update public.npc_fleets nf set refused = 4, asked_at = null from bo102 l where l.fleet_id = nf.fleet_id and l.i between 13 and 212;
  select l.fleet_id into v_new from bo102 l where l.i = 213;
  update public.standing_routes sr set paused_reason = 'laid_up', updated_at = now() - interval '630 seconds' from bo102 l where l.route_id = sr.id and l.i = 213;
  update public.npc_fleets set refused = 1, asked_at = null where fleet_id = v_new;
  select count(*) into v_n from public.npc_waiting_queue(now()) q;
  call public.tick_waiting_asks(false);
  select w.receipt into v_r from public.waiting_ask_runs w where w.at = now();
  if v_n < 201 or (v_r->>'asked')::int <> 1 or (select nf.asked_at from public.npc_fleets nf where nf.fleet_id = v_new) is distinct from now()
     or exists (select 1 from bo102 l join public.npc_fleets nf on nf.fleet_id = l.fleet_id where l.i between 13 and 212 and nf.asked_at is not null) then
    raise exception 'BO_NEW: with % in the line the pass did not ask the new lay-up alone: %', v_n, v_r - 'note';
  end if;
  raise notice 'PASS: BO_NEW % merchants in the line, 200 of them refused four times and asked 15 minutes ago: the pass asks one merchant, the one newly laid up 10.5 minutes ago', v_n;

  -- ── BO_QUAY ──
  if not (v_r ? 'quay_ms') or not (v_r ? 'quay_ms_max') then
    raise exception 'BO_QUAY: the receipt has no quay_ms: %', v_r - 'note';
  end if;
  raise notice 'PASS: BO_QUAY the receipt carries quay_ms % and quay_ms_max %', v_r->>'quay_ms', v_r->>'quay_ms_max';

  -- ── BO_ONE ──
  v_n := (public.npc_ask_waiting(now(), clock_timestamp() + interval '10 seconds')->>'asked')::int;
  if v_n <> 0 then
    raise exception 'BO_ONE: with nobody due by the rule the beat''s hand asked %', v_n;
  end if;
  update public.standing_routes sr set updated_at = now() - interval '51 minutes' from bo102 l where l.route_id = sr.id and l.i between 13 and 212 and sr.paused_reason = 'laid_up';
  select count(*) into v_n from public.npc_waiting_queue(now()) q where q.due_at <= now();
  if v_n < 190 then
    raise exception 'BO_ONE: put 51 minutes back, only % of the 200 are due', v_n;
  end if;
  v_k := (public.npc_ask_waiting(now(), clock_timestamp() + interval '10 seconds')->>'asked')::int;
  if v_k < 1 then
    raise exception 'BO_ONE: with % due the beat''s hand asked nobody', v_n;
  end if;
  raise notice 'PASS: BO_ONE with 200 refused four times and asked 15 minutes ago the beat''s hand asks 0; put 51 minutes back % are due and it asks %', v_n, v_k;
end $p$;
