-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 115 - THE ROSTER DOES NOT WAIT ON THE DAY'S ROOM  (migration 0418; docs/dev-log/2026-11-14-roster-fix.md)
--
--   Production's shape at 13:48 UTC on 2026-11-14, rebuilt here: 0339's ships 1-7 wrecked at their homes (five unpaid), the day's room spent, the hoard 975.9 M, the add's clock due.
--   The pirates' own job (public.tick_pirates) is run minute by minute, lit, rolled back with proof.mjs's transaction. On the chain before 0418 it adds nothing (roster 0).
--
-- @pass RF_ROSTER     with the room spent, the wrecks waiting and a 0339 hull at the head of the queue, the job builds a roster fleet every pirate_add_minutes (three in 25 minutes), each outside the room (nothing written to the day), the hoard above the 400 M floor; the 0339 hull still waits on the room
-- @pass RF_ROOM_FIRST with the room whole again, the 0339 hull at the head of the queue is built first, inside the room, as before 0418
-- ═══════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_cap   uuid;
  v_t0    timestamptz := date_trunc('minute', now());
  v_day1  timestamptz;
  v_head  int;
  v_spent bigint;
  v_n     int;
  o       int;
  i       int;
  v_r     jsonb;
begin
  -- 0421 moved pirate_add_minutes 10 -> 5. This proof counts three roster fleets in 25 minutes at 10: pinned to 10 here, rolled back with the
  -- proof. Proof 118 is the same scene at the live pace (six in 25 minutes).
  update public.world_config set value = to_jsonb(10) where key = 'pirate_add_minutes';
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'economy_closed');
  v_cap := public.pirate_capital();
  update public.port_treasury t set ducats = 975934180 where t.port_id = v_cap;
  delete from public.pirate_spend_day d where d.day >= (v_t0 at time zone 'UTC')::date - 1;
  for o in 1 .. 7 loop
    if public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t0 - interval '2 days') is null then
      raise exception 'PROOF 115 FAIL: the scene could not build 0339 ship %', o;
    end if;
  end loop;
  update public.ships s set durability = 0 where s.fleet_id in (select n.fleet_id from public.pirate_ships n);
  update public.pirate_ships n set wrecked_at = v_t0 - interval '61 minutes', unpaid_since = case when n.ord in (2, 3, 4, 6, 7) then v_t0 - interval '68 minutes' end;
  update public.pirate_clock set added_at = v_t0 - interval '20 hours', paid_at = v_t0 - interval '8 minutes', gifted_at = v_t0 - interval '16 minutes';
  insert into public.pirate_spend_day (day, spent) values ((v_t0 at time zone 'UTC')::date, 4215000);
  v_head := public.pirate_next_ord();
  v_spent := 4215000;
  if public.pirate_spend_room(v_t0) <> 0 or v_head is null or exists (select 1 from public.pirate_roster r where r.ord = v_head) then
    raise exception 'PROOF 115 FAIL: the scene is not prod''s shape (room %, head %)', public.pirate_spend_room(v_t0), v_head;
  end if;

  for i in 0 .. 25 loop
    v_r := public.tick_pirates(v_t0 + make_interval(mins => i));
  end loop;
  v_n := (select count(*) from public.pirate_ships n where n.ord > 1000);
  if v_n <> 3 or (select d.spent from public.pirate_spend_day d where d.day = (v_t0 at time zone 'UTC')::date) <> v_spent
     or exists (select 1 from public.pirate_ships n where n.ord = v_head) or public.pirate_hoard() < 400000000
     or (select count(*) from public.pirate_ships n where n.ord < 1000 and n.wrecked_at is not null) <> 7 then
    raise exception 'PROOF 115 FAIL: with the room spent the job built % roster fleets in 25 minutes (want 3), spent today %, head % built %, wrecks %', v_n,
      (select d.spent from public.pirate_spend_day d where d.day = (v_t0 at time zone 'UTC')::date), v_head, exists (select 1 from public.pirate_ships n where n.ord = v_head),
      (select count(*) from public.pirate_ships n where n.ord < 1000 and n.wrecked_at is not null);
  end if;
  raise notice 'PASS: RF_ROSTER — room 0, seven wrecks waiting, ord % at the head: % roster fleets built in 25 minutes, nothing written to the day', v_head, v_n;

  v_day1 := date_trunc('day', v_t0 at time zone 'UTC') at time zone 'UTC' + interval '1 day';
  v_r := public.tick_pirates(v_day1);
  if v_r ->> 'added' is distinct from 'BUILT' or not exists (select 1 from public.pirate_ships n where n.ord = v_head)
     or (select count(*) from public.pirate_ships n where n.ord > 1000) <> v_n
     or coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_day1 at time zone 'UTC')::date), 0) < (select c.build_cost from public.ship_classes c where c.code = public.wc_text('pirate_ship_class')) then
    raise exception 'PROOF 115 FAIL: with the room whole the 0339 hull % was not built first inside the room (%)', v_head, v_r;
  end if;
  raise notice 'PASS: RF_ROOM_FIRST — the next UTC day the room renews and ord % is built first, inside the room', v_head;
end
$p$;
