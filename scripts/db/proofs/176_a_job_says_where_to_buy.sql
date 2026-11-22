-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 176 - A JOB SAYS WHERE TO BUY, AND YOUR WEEK IS COUNTED LIVE  (migration 0473; docs/design/playable-2026-11-22.md section 5, S4 and S6;
--   docs/dev-log/2026-11-22-requests-source.md)
--
--   Lit, through public.hold_request_post, world.contracts and world.houses_week, rolled back with proof.mjs's transaction. The scene: thirty
--   harbours given room for two more hold jobs each, posted at the first second of today's game day and again a minute before its end; a
--   probe company with a week far above any real house's, its sales after the history job's mark, and a settled rival.
--
-- @pass RS_REACH   lit: every job posted is sold at its source, not at the poster, and a Barca sails to the source and back in half the time it stands
-- @pass RS_TIGHT   lit, a minute before the game day ends: a job posted is still within reach of its shorter time (or none is posted)
-- @pass RS_READ    the read serves a hold job's `from` (code, name, nm, a Barca's sail_seconds) and none on a city's request
-- @pass WL_LIVE    lit: a sale after the mark is in your week at once; your board row is live, your place and the gap are against the others'
-- @pass WL_COST    the live figure's cost: the read timed with 300 of your ledger rows after the mark, and its ledger range's plan
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_ports  uuid[];
  v_p      uuid;
  v_ids    uuid[];
  v_now    timestamptz;
  v_n      int := 0;
  v_tight  int := 0;
  v_mins   numeric[] := '{}';
  c        public.trade_contracts%rowtype;
  v_nm     numeric;
  v_left   numeric;
  v_a      jsonb;
  v_rd     int := 0;
  v_ex     jsonb;
begin
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  update public.world_config set value = 'true'::jsonb where key = 'hold_requests_enabled';
  update public.world_config set value = to_jsonb(1000) where key = 'hold_request_open_max';   -- room at every harbour
  v_ports := array(select p.id from public.ports p where p.kind = 'HARBOUR' order by md5(p.code) limit 30);
  v_ids := array(select t.id from public.trade_contracts t);

  -- ── RS_REACH: at the first second of today's game day ──
  v_now := public.clock_start('game_day', world.game_day()) + interval '1 second';
  foreach v_p in array v_ports loop
    perform public.hold_request_post(v_p, v_now);
    perform public.hold_request_post(v_p, v_now);
  end loop;
  for c in select * from public.trade_contracts t where t.size = 'hold' and t.id <> all (v_ids) loop
    v_nm := (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = c.port_id and sp.id = c.source_port_id);
    v_left := extract(epoch from public.clock_start('game_day', c.expires_day) - v_now);
    if c.source_port_id is null or c.source_port_id = c.port_id or v_nm is null
       or not exists (select 1 from public.port_specialties s where s.port_id = c.source_port_id and s.good_id = c.good_id)
       or exists (select 1 from public.port_specialties s where s.port_id = c.port_id and s.good_id = c.good_id)
       or 2 * v_nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression') > 0.5 * v_left + 0.5 then
      raise exception 'PROOF 176 FAIL: a job not sold at its source, or its source out of reach: % (% nm, % s left)', to_jsonb(c), v_nm, v_left;
    end if;
    v_n := v_n + 1;
    v_mins := v_mins || round(v_nm / public.wc_num('hold_request_speed_kn') * 60 / public.wc_num('time_compression'), 1);
  end loop;
  if v_n < 30 then
    raise exception 'PROOF 176 FAIL: thirty harbours with room posted only % jobs within reach', v_n;
  end if;
  raise notice 'PASS: RS_REACH — % jobs at 30 harbours, each sold at its source; one way for a Barca: min % min, median % min, max % min',
    v_n, (select min(m) from unnest(v_mins) m), (select percentile_cont(0.5) within group (order by m) from unnest(v_mins) m), (select max(m) from unnest(v_mins) m);

  -- ── RS_TIGHT: a minute before the game day ends (the next game day's seqs are fresh, so the posts are new rows) ──
  v_ids := array(select t.id from public.trade_contracts t);
  v_now := public.clock_start('game_day', world.game_day() + 1) - interval '60 seconds';
  foreach v_p in array v_ports[1:10] loop
    v_tight := v_tight + public.hold_request_post(v_p, v_now);
  end loop;
  for c in select * from public.trade_contracts t where t.size = 'hold' and t.id <> all (v_ids) loop
    v_nm := (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = c.port_id and sp.id = c.source_port_id);
    v_left := extract(epoch from public.clock_start('game_day', c.expires_day) - v_now);
    if c.source_port_id is null or 2 * v_nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression') > 0.5 * v_left + 0.5 then
      raise exception 'PROOF 176 FAIL: a job posted late is out of reach of its time: % (% nm, % s left)', to_jsonb(c), v_nm, v_left;
    end if;
  end loop;
  raise notice 'PASS: RS_TIGHT — a minute before the day ends, % of 10 harbours posted, each within reach of the time it stands', v_tight;

  -- ── RS_READ ──
  foreach v_p in array v_ports[1:5] loop
    for v_a in select e from jsonb_array_elements(world.contracts(v_p) -> 'contracts') e loop
      if v_a ->> 'size' = 'hold' and (v_a ->> 'id')::uuid <> all (v_ids) then
        select * into c from public.trade_contracts t where t.id = (v_a ->> 'id')::uuid;
        if c.source_port_id is not null and (v_a -> 'from' ->> 'code' is distinct from (select p.code from public.ports p where p.id = c.source_port_id)
           or v_a -> 'from' ->> 'name' is distinct from (select p.name from public.ports p where p.id = c.source_port_id)
           or (v_a -> 'from' ->> 'sail_seconds')::int is null or (v_a -> 'from' ->> 'nm')::numeric is null) then
          raise exception 'PROOF 176 FAIL: the read serves a hold job''s source wrong: %', v_a;
        end if;
        v_rd := v_rd + 1;
        v_ex := v_a -> 'from';
      elsif v_a ->> 'size' = 'city' and v_a -> 'from' <> 'null'::jsonb then
        raise exception 'PROOF 176 FAIL: a city''s request serves a source: %', v_a;
      end if;
    end loop;
  end loop;
  if v_rd = 0 then
    raise exception 'PROOF 176 FAIL: the read served no hold job at five harbours that posted';
  end if;
  raise notice 'PASS: RS_READ — % hold rows read with their source (e.g. %), none on a city''s request', v_rd, v_ex;
end $p$;

do $p$
declare
  v_week  date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_nat   uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_port  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_me    uuid;
  v_rival uuid;
  v_mark  timestamptz;
  v_r     jsonb;
  v_t     timestamptz;
  v_ms0   numeric;
  v_ms1   numeric;
  v_plan  text;
  v_line  text;
  i       int;
begin
  update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
  -- the history job's mark well before this transaction, so the sales below are after it
  update public.history_mark set ledger_through = now() - interval '10 minutes';
  select m.ledger_through into v_mark from public.history_mark m;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values ('00000000-0176-4000-8000-0000000000c1', 'Casa Viva 176', v_nat, 100000, false) returning id into v_me;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Rivale 176', v_nat, 0, true) returning id into v_rival;
  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
    values (v_rival, 900176, 'prt', 'A probe of proof 176.', 'Probe', v_port, 1000, 0.1);
  insert into public.history_company_day (player_id, day, earned, lost) values
    (v_me, v_week, 4000000000000000, 0), (v_rival, v_week, 4000000000001000, 0)
    on conflict (player_id, day) do update set earned = excluded.earned, lost = excluded.lost;
  perform public.houses_week_settle(now());
  perform cmd.assume_identity('00000000-0176-4000-8000-0000000000c1');

  -- settled: you are second, 1,000 behind the rival
  v_r := world.houses_week();
  if (v_r -> 'you' ->> 'position')::int <> 2 or (v_r -> 'you' -> 'ahead' ->> 'gap')::bigint <> 1000 then
    raise exception 'PROOF 176 FAIL: the settled scene is not as built: %', v_r -> 'you';
  end if;
  -- a +1,485 sale, not settled: first at once, 485 ahead, the board's first row is you at the live figure
  perform public.credit(v_me, 'SELL', 1485);
  v_r := world.houses_week();
  if (v_r -> 'you' ->> 'net')::bigint <> 4000000000001485 or (v_r -> 'you' ->> 'position')::int <> 1 or v_r -> 'you' -> 'ahead' <> 'null'::jsonb
     or not (v_r -> 'board' -> 0 ->> 'is_you')::boolean or (v_r -> 'board' -> 0 ->> 'net')::bigint <> 4000000000001485
     or (v_r -> 'board' -> 1 ->> 'company_name') <> 'Casa Rivale 176'
     or (select count(*) from jsonb_array_elements(v_r -> 'board') e where (e ->> 'is_you')::boolean) <> 1
     or (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_me) <> 4000000000000000 then
    raise exception 'PROOF 176 FAIL: lit, the sale is not in your week at once: % / %', v_r -> 'you', v_r -> 'board' -> 0;
  end if;
  -- a -485 buy: level with the rival, both first, tied
  perform public.credit(v_me, 'BUY', -485);
  v_r := world.houses_week();
  if (v_r -> 'you' ->> 'position')::int <> 1 or not (v_r -> 'you' ->> 'tied')::boolean or (v_r -> 'you' ->> 'net')::bigint <> 4000000000001000 then
    raise exception 'PROOF 176 FAIL: lit, level with the rival is not a tie for first: %', v_r -> 'you';
  end if;
  -- a FOUNDING row (capital) is not profit, as the settle counts it
  perform public.credit(v_me, 'FOUNDING', 50000);
  if (world.houses_week() -> 'you' ->> 'net')::bigint <> 4000000000001000 then
    raise exception 'PROOF 176 FAIL: a FOUNDING row moved your week';
  end if;
  -- the settle, once run, writes the same figure the read served
  update public.history_mark set ledger_through = now() + interval '1 second';
  perform public.history_ledger_add(v_mark, now() + interval '1 second');
  perform public.houses_week_settle(now());
  if (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_me) <> 4000000000001000
     or (world.houses_week() -> 'you' ->> 'net')::bigint <> 4000000000001000 then
    raise exception 'PROOF 176 FAIL: the settle and the live read disagree: % / %', (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_me), world.houses_week() -> 'you';
  end if;
  raise notice 'PASS: WL_LIVE — +1,485 unsettled: #1 at once (was #2, 1,000 behind), board row live; -485: tied first; FOUNDING not counted; the settle then writes the same 4000000000001000';

  -- ── WL_COST: 300 of your rows after the mark (the mark moved back again, so the 1,485 / -485 rows count twice: +1,000 more) ──
  update public.history_mark set ledger_through = now() - interval '10 minutes';
  v_t := clock_timestamp();
  for i in 1..20 loop perform world.houses_week(); end loop;
  v_ms0 := extract(epoch from clock_timestamp() - v_t) * 1000 / 20;
  for i in 1..300 loop perform public.credit(v_me, 'SELL', 1); end loop;
  v_t := clock_timestamp();
  for i in 1..20 loop v_r := world.houses_week(); end loop;
  v_ms1 := extract(epoch from clock_timestamp() - v_t) * 1000 / 20;
  if (v_r -> 'you' ->> 'net')::bigint <> 4000000000002300 then
    raise exception 'PROOF 176 FAIL: 300 rows after the mark did not count: %', v_r -> 'you';
  end if;
  for v_line in execute format('explain select sum(l.ducats_delta) from public.ledger l where l.player_id = %L and l.created_at > %L and public.ledger_is_earning(l.kind)', v_me, v_mark) loop
    v_plan := coalesce(v_plan || ' / ', '') || btrim(v_line);
  end loop;
  if v_plan not like '%ledger_player_created%' then
    raise exception 'PROOF 176 FAIL: your ledger range is not read by its index: %', v_plan;
  end if;
  raise notice 'PASS: WL_COST — the read % ms with 3 of your rows after the mark, % ms with 303 (% houses on the board); the range: %',
    round(v_ms0, 2), round(v_ms1, 2), v_r ->> 'houses', v_plan;
end $p$;
