-- scene-prod-shape.sql: production's shape at 13:48 UTC 2026-11-14 (after.sql), rebuilt in the local world, then the pirates' job run minute by minute.
-- LOCAL ONLY, inside probe.mjs's rolled-back transaction. Seven of 0339's ships (ords 1-7) wrecked at their homes, five of them unpaid, the day's room spent (4,215,000 against about 2.34 M),
-- the hoard 975.9 M, pirate_clock.added_at a day old. Phase A: 40 minutes of today. Phase B: the next UTC day from 00:00, 120 minutes.
-- Prints one row: per phase, the roster fleets built, the 0339 ships built, what each minute's run answered when it added, and the wrecks' fate.
create temp table if not exists rf_log (phase text, t timestamptz, r jsonb, room bigint, roster int, old int, wrecks int, laid int);
do $s$
declare
  v_cap uuid;
  v_t0 timestamptz := date_trunc('minute', now());
  v_day1 timestamptz;
  i int;
  o int;
  v_f uuid;
  v_r jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'economy_closed');
  v_cap := public.pirate_capital();
  update public.port_treasury t set ducats = 975934180 where t.port_id = v_cap;
  for o in 1 .. 7 loop   -- 0339's ships, built while the room was whole
    v_f := public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t0 - interval '2 days');
    if v_f is null then raise exception 'scene: ship % not built', o; end if;
  end loop;
  update public.ships s set durability = 0 where s.fleet_id in (select n.fleet_id from public.pirate_ships n);
  update public.pirate_ships n set wrecked_at = v_t0 - interval '21 minutes', unpaid_since = case when n.ord in (2, 3, 4, 6, 7) then v_t0 - interval '68 minutes' end;
  update public.pirate_clock set added_at = v_t0 - interval '20 hours', paid_at = v_t0 - interval '8 minutes', gifted_at = v_t0 - interval '16 minutes';
  delete from public.pirate_spend_day d where d.day >= (v_t0 at time zone 'UTC')::date - 1;
  insert into public.pirate_spend_day (day, spent) values ((v_t0 at time zone 'UTC')::date, 4215000);
  raise notice 'scene: t0 % size % next_ord % room % hoard %', v_t0, public.pirate_size(), public.pirate_next_ord(), public.pirate_spend_room(v_t0), public.pirate_hoard();
  for i in 0 .. 40 loop
    v_r := public.tick_pirates(v_t0 + make_interval(mins => i));
    insert into rf_log select 'A', v_t0 + make_interval(mins => i), v_r, public.pirate_spend_room(v_t0 + make_interval(mins => i)),
      (select count(*) from public.pirate_ships n where n.ord > 1000), (select count(*) from public.pirate_ships n where n.ord < 1000),
      (select count(*) from public.pirate_ships n where n.wrecked_at is not null), (select count(*) from public.pirate_ships n where n.laid_up_at is not null);
  end loop;
  v_day1 := date_trunc('day', v_t0 at time zone 'UTC') at time zone 'UTC' + interval '1 day';
  for i in 0 .. 120 loop
    v_r := public.tick_pirates(v_day1 + make_interval(mins => i));
    insert into rf_log select 'B', v_day1 + make_interval(mins => i), v_r, public.pirate_spend_room(v_day1 + make_interval(mins => i)),
      (select count(*) from public.pirate_ships n where n.ord > 1000), (select count(*) from public.pirate_ships n where n.ord < 1000),
      (select count(*) from public.pirate_ships n where n.wrecked_at is not null), (select count(*) from public.pirate_ships n where n.laid_up_at is not null);
  end loop;
end
$s$;
select l.phase, to_char(l.t at time zone 'UTC', 'HH24:MI') as utc, l.r->>'added' as added, l.r->'steps' as steps, l.r->>'paid' as paid, l.room, l.roster, l.old, l.wrecks, l.laid
  from rf_log l where l.r->>'added' is not null or l.r->'steps' <> '{}'::jsonb or (l.r->>'paid')::bigint > 0 or l.t = (select max(t) from rf_log x where x.phase = l.phase) order by l.t;
