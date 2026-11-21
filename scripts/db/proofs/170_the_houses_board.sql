-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 170 - THE HOUSES' BOARD  (migration 0467; docs/design/content-plan-2026-11.md 5.3 item 5, 5.6; docs/dev-log/2026-11-22-houses-board.md)
--
--   Dark and lit, through public.houses_week_settle, world.houses_week, public.settle_standings and the history job (public.tick_history),
--   rolled back with proof.mjs's transaction. The scene: three probe merchant houses and two probe companies, one with a login (the shim's
--   one sign-in) and one test company (an id no login matches), each with a figure this week far above any real house's.
--
-- @pass HB_DARK      dark: the read answers {"on": false}, the settle writes nothing, the history job's run writes no board row
-- @pass HB_BOARD     lit: the board's top is the probe merchants in profit order, competition-ranked; a company row says it is a company
-- @pass HB_YOU       lit: your place, tied, figure, the house just ahead and the gap, and "of N" = every house on this week's board
-- @pass HB_TEST_OFF  lit: the test company is on neither board (houses' and Captains'); the company with a login is on both
-- @pass HB_WEEKS     lit: last week is counted under its own key, a week older than the last is deleted, a house gone from the roster leaves
-- @pass HB_JOB       lit: the history job's run settles the board (its receipt's phases name it) and a figure that moved is rewritten
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_uid   constant uuid := '00000000-0000-4000-8000-000000000a17';   -- the shim's one sign-in (0467)
  v_week  date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_nat   uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_port  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_live  uuid;
  v_test  uuid;
  m1 uuid; m2 uuid; m3 uuid;
  v_r     jsonb;
  v_n     int;
begin
  if to_regclass('auth.users') is null or not exists (select 1 from auth.users u where u.id = c_uid) then
    raise exception 'PROOF 170 FAIL: the shim''s sign-in is not in auth.users';
  end if;
  select p.id into v_live from public.players p where p.auth_uid = c_uid;
  if v_live is null then
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_uid, 'Casa Viva 170', v_nat, 0, false) returning id into v_live;
  end if;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values ('00000000-0170-4000-8000-0000000000c1', 'Casa Prova 170', v_nat, 0, false) returning id into v_test;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Uno 170', v_nat, 0, true) returning id into m1;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Due 170', v_nat, 0, true) returning id into m2;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Tre 170', v_nat, 0, true) returning id into m3;
  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience) values
    (m1, 900170, 'prt', 'A probe of proof 170.', 'Probe', v_port, 1000, 0.1),
    (m2, 900171, 'prt', 'A probe of proof 170.', 'Probe', v_port, 1000, 0.1),
    (m3, 900172, 'prt', 'A probe of proof 170.', 'Probe', v_port, 1000, 0.1);
  -- this week: the test company highest, then m1, m2, then you level with m3; last week: m1 alone
  insert into public.history_company_day (player_id, day, earned, lost) values
    (v_test, v_week, 9000000000000000, 0),
    (m1, v_week, 5000000000000000, 0),
    (m2, v_week, 3000000000000000, 0),
    (m3, v_week, 2500000000000000, 500000000000000),
    (v_live, v_week, 2000000000000000, 0),
    (m1, v_week - 7, 50, 0)
  on conflict (player_id, day) do update set earned = excluded.earned, lost = excluded.lost;

  -- ── DARK ──
  if public.wc('houses_board_enabled') <> 'false'::jsonb then
    raise exception 'PROOF 170 FAIL: the switch is not dark in the shipped world';
  end if;
  perform cmd.assume_identity(c_uid);
  if world.houses_week() <> '{"on": false}'::jsonb or public.houses_week_settle(now()) is not null then
    raise exception 'PROOF 170 FAIL: dark, the read or the settle answered: %', world.houses_week();
  end if;
  v_r := public.tick_history(now());
  if exists (select 1 from public.houses_week) or (v_r -> 'phases' ? 'houses') and v_r -> 'phases' -> 'houses' <> 'null'::jsonb then
    raise exception 'PROOF 170 FAIL: dark, the history job wrote the board: %', v_r -> 'phases';
  end if;
  raise notice 'PASS: HB_DARK — {"on": false}, the settle null, the job''s run wrote no row';

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
  -- a week older than the last, written by hand, must go
  insert into public.houses_week (week, player_id, net) values (v_week - 14, m1, 7);
  v_r := public.houses_week_settle(now());
  if v_r is null or (v_r ->> 'written')::int < 1 then
    raise exception 'PROOF 170 FAIL: lit, the settle wrote nothing: %', v_r;
  end if;

  v_r := world.houses_week();
  if (v_r ->> 'on')::boolean is not true or (v_r ->> 'week')::date <> v_week
     or v_r -> 'board' -> 0 ->> 'company_name' <> 'Casa Uno 170' or (v_r -> 'board' -> 0 ->> 'position')::int <> 1 or (v_r -> 'board' -> 0 ->> 'net')::bigint <> 5000000000000000
     or (v_r -> 'board' -> 0 ->> 'company')::boolean or v_r -> 'board' -> 1 ->> 'company_name' <> 'Casa Due 170' or (v_r -> 'board' -> 1 ->> 'position')::int <> 2
     or (v_r -> 'board' -> 2 ->> 'position')::int <> 3 or (v_r -> 'board' -> 3 ->> 'position')::int <> 3 or not (v_r -> 'board' -> 2 ->> 'tied')::boolean
     or (select count(*) from jsonb_array_elements(v_r -> 'board') e where (e ->> 'is_you')::boolean and (e ->> 'company')::boolean) <> 1
     or jsonb_array_length(v_r -> 'board') > (v_r ->> 'board_size')::int then
    raise exception 'PROOF 170 FAIL: lit, the board''s top is not the probes in order: %', v_r -> 'board';
  end if;
  raise notice 'PASS: HB_BOARD — Casa Uno 1st (5e15), Casa Due 2nd, you and Casa Tre both 3rd (tied), your row a company, % rows of %', jsonb_array_length(v_r -> 'board'), v_r ->> 'board_size';

  select count(*) into v_n from public.houses_week w where w.week = v_week;
  if (v_r -> 'you' ->> 'position')::int <> 3 or not (v_r -> 'you' ->> 'tied')::boolean or (v_r -> 'you' ->> 'net')::bigint <> 2000000000000000
     or v_r -> 'you' -> 'ahead' ->> 'name' <> 'Casa Due 170' or (v_r -> 'you' -> 'ahead' ->> 'gap')::bigint <> 1000000000000000
     or (v_r ->> 'houses')::int <> v_n
     or v_n <> (select count(*) from public.npc_houses) + (select count(*) from public.players p join auth.users u on u.id = p.auth_uid where not p.is_npc) then
    raise exception 'PROOF 170 FAIL: lit, your line is wrong: % of % (%)', v_r -> 'you', v_r ->> 'houses', v_n;
  end if;
  raise notice 'PASS: HB_YOU — #3 (tied) of %, net 2e15, next Casa Due 170 +1e15 ahead', v_n;

  perform public.settle_standings('2099-01-01 00:00:00+00');
  if exists (select 1 from public.houses_week w where w.player_id = v_test)
     or exists (select 1 from jsonb_array_elements(v_r -> 'board') e where e ->> 'company_name' = 'Casa Prova 170')
     or exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:00:00+00') and s.player_id = v_test)
     or not exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:00:00+00') and s.player_id = v_live) then
    raise exception 'PROOF 170 FAIL: lit, the test company is on a board, or the company with a login is off the Captains board';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'houses_board_enabled';
  perform public.settle_standings('2099-01-01 00:10:00+00');
  if not exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:10:00+00') and s.player_id = v_test) then
    raise exception 'PROOF 170 FAIL: dark, the Captains board is not today''s (the test company left it)';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
  raise notice 'PASS: HB_TEST_OFF — the test company on neither board lit (and on Captains dark), the company with a login on both';

  if (select w.net from public.houses_week w where w.week = v_week - 7 and w.player_id = m1) is distinct from 50
     or exists (select 1 from public.houses_week w where w.week < v_week - 7) then
    raise exception 'PROOF 170 FAIL: last week is not kept under its own key, or an older week survived';
  end if;
  delete from public.npc_houses where player_id = m3;
  perform public.houses_week_settle(now());
  if exists (select 1 from public.houses_week w where w.player_id = m3) then
    raise exception 'PROOF 170 FAIL: a house gone from the roster is still on the board';
  end if;
  raise notice 'PASS: HB_WEEKS — last week m1 = 50 under its own key, the week before deleted, a house gone from the roster removed';

  update public.history_company_day set earned = earned + 1 where player_id = v_live and day = v_week;
  v_r := public.tick_history(now());
  if v_r -> 'phases' -> 'houses' is null or jsonb_typeof(v_r -> 'phases' -> 'houses') <> 'object'
     or (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_live) <> 2000000000000001 then
    raise exception 'PROOF 170 FAIL: lit, the history job did not settle the board: %', v_r -> 'phases';
  end if;
  raise notice 'PASS: HB_JOB — the job''s run settled it (%), your figure moved to 2000000000000001', v_r -> 'phases' -> 'houses';
end $p$;
