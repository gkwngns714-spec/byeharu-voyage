-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 118 - THE WORLD IS COUNTED AND READ MORE OFTEN  (migration 0421; docs/dev-log/2026-11-15-pace-up.md)
--
--   0421 is settings only: two knobs and the Stats job's schedule (pg_cron, which this world has not). What a player meets of it here is the
--   pirates' roster filling at the new pace, through the pirates' own job (public.tick_pirates), lit, rolled back with proof.mjs's transaction.
--   The scene is proof 115's (production's shape at 13:48 UTC on 2026-11-14: 0339's ships wrecked, the day's room spent, the add's clock due),
--   run at the knob as 0421 ships it, not pinned.
--
-- @pass PU_KNOBS   pirate_add_minutes 5 and contract_wind_retry_minutes 30, each description naming the value it replaced (10, 60)
-- @pass PU_ROSTER  with the room spent and the wrecks waiting, the job builds a roster fleet every 5 minutes: six in 25 minutes (proof 115 counts
--                  three at 10), each outside the room (nothing written to the day), the hoard above the 400 M floor; the 0339 hull still waits
-- ═══════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_cap   uuid;
  v_t0    timestamptz := date_trunc('minute', now());
  v_head  int;
  v_spent bigint := 4215000;
  v_n     int;
  o       int;
  i       int;
  v_r     jsonb;
begin
  -- PU_KNOBS
  if public.wc_int('pirate_add_minutes') <> 5 or public.wc_int('contract_wind_retry_minutes') <> 30
     or not exists (select 1 from public.world_config wc where wc.key = 'pirate_add_minutes' and wc.description like '%10 before 0421%')
     or not exists (select 1 from public.world_config wc where wc.key = 'contract_wind_retry_minutes' and wc.description like '%60 before 0421%') then
    raise exception 'PROOF 118 FAIL: the knobs are not 0421''s (pirate_add_minutes %, contract_wind_retry_minutes %)',
      public.wc_int('pirate_add_minutes'), public.wc_int('contract_wind_retry_minutes');
  end if;
  raise notice 'PASS: PU_KNOBS — pirate_add_minutes 5 (was 10), contract_wind_retry_minutes 30 (was 60), the old values written into their descriptions';

  -- PU_ROSTER: proof 115's scene, at the live pace
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'economy_closed');
  v_cap := public.pirate_capital();
  update public.port_treasury t set ducats = 975934180 where t.port_id = v_cap;
  delete from public.pirate_spend_day d where d.day >= (v_t0 at time zone 'UTC')::date - 1;
  for o in 1 .. 7 loop
    if public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t0 - interval '2 days') is null then
      raise exception 'PROOF 118 FAIL: the scene could not build 0339 ship %', o;
    end if;
  end loop;
  update public.ships s set durability = 0 where s.fleet_id in (select n.fleet_id from public.pirate_ships n);
  update public.pirate_ships n set wrecked_at = v_t0 - interval '61 minutes', unpaid_since = case when n.ord in (2, 3, 4, 6, 7) then v_t0 - interval '68 minutes' end;
  update public.pirate_clock set added_at = v_t0 - interval '20 hours', paid_at = v_t0 - interval '8 minutes', gifted_at = v_t0 - interval '16 minutes';
  insert into public.pirate_spend_day (day, spent) values ((v_t0 at time zone 'UTC')::date, v_spent);
  v_head := public.pirate_next_ord();
  if public.pirate_spend_room(v_t0) <> 0 or v_head is null or exists (select 1 from public.pirate_roster r where r.ord = v_head) then
    raise exception 'PROOF 118 FAIL: the scene is not prod''s shape (room %, head %)', public.pirate_spend_room(v_t0), v_head;
  end if;

  for i in 0 .. 25 loop
    v_r := public.tick_pirates(v_t0 + make_interval(mins => i));
  end loop;
  v_n := (select count(*) from public.pirate_ships n where n.ord > 1000);
  if v_n <> 6 or (select d.spent from public.pirate_spend_day d where d.day = (v_t0 at time zone 'UTC')::date) <> v_spent
     or exists (select 1 from public.pirate_ships n where n.ord = v_head) or public.pirate_hoard() < 400000000 then
    raise exception 'PROOF 118 FAIL: at pirate_add_minutes 5 the job built % roster fleets in 25 minutes (want 6), spent today %, head % built %, hoard %', v_n,
      (select d.spent from public.pirate_spend_day d where d.day = (v_t0 at time zone 'UTC')::date), v_head, exists (select 1 from public.pirate_ships n where n.ord = v_head),
      public.pirate_hoard();
  end if;
  raise notice 'PASS: PU_ROSTER — room 0, seven wrecks waiting, ord % at the head: % roster fleets built in 25 minutes at one in 5, nothing written to the day, hoard %',
    v_head, v_n, public.pirate_hoard();
end
$p$;
