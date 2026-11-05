-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 26 — A DAY IS A DAY  (migration 0317)
--
--   0317's own self-assert runs on probe rows (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof reads the real doors as a
--   signed-in company and runs the REAL public.tick_city and public.tick_buff_calendar over the WHOLE world, at both clocks, each pass rolled back.
--
-- @pass ADAY_REPORT   Today and Week are real UTC days, the same at 60 s and at 2880 s, and All is a bar a day
-- @pass ADAY_PAID     dividends today and yesterday are real UTC days, a whole yesterday included
-- @pass ADAY_HALL     the Town hall's day is the last 24 hours of the newest count, by kind
-- @pass ADAY_MARKET   the market's volume is the last 24 hours, not the minute
-- @pass ADAY_HAGGLE   three bargains a real day: a change of the clock gives no fourth and keeps the bargain won
-- @pass ADAY_FAIR     a fair runs 3.2 hours in a real day, and the calendar drawn is the same at both clocks
-- @pass ADAY_CROWN    the crown takes its whole share of TAX an hour old, at both clocks, once
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_uid  constant uuid := '00000000-0317-4000-8000-0000000000d1';
  v_rday int := public.real_day(now());
  v_start timestamptz := to_timestamp(public.real_day(now()) * 86400.0);
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_p    uuid;
  v_f    uuid;
  v_bal  bigint;
  v_good uuid;
  v_city uuid;
  v_cap  uuid;
  v_gds  int;
  v_d    jsonb;
  v_w    jsonb;
  v_a    jsonb;
  v_h    jsonb;
  v_r    jsonb;
  v_x    jsonb;
  v_all  jsonb := '{}'::jsonb;
  v_base numeric;
  v_share numeric := public.wc_num('crown_tax_share');
begin
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  v_p := public.new_house(c_uid, 'Casa do Dia 0317', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  select p.ducats into v_bal from public.players p where p.id = v_p;
  perform cmd.assume_identity(c_uid);

  -- ── THE LEDGER: today, the last second of yesterday, the first second of yesterday, the first second of 6 days ago, the first second of 7 days ago ──
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
    (v_p, 'TOW',      100, v_bal, now()),
    (v_p, 'TOW',       10, v_bal, v_start - interval '1 second'),
    (v_p, 'TOW',     1000, v_bal, to_timestamp((v_rday - 6) * 86400.0)),
    (v_p, 'TOW',     5000, v_bal, to_timestamp((v_rday - 7) * 86400.0)),
    (v_p, 'DIVIDEND',  77, v_bal, now()),
    (v_p, 'DIVIDEND',  33, v_bal, to_timestamp((v_rday - 1) * 86400.0)),
    (v_p, 'DIVIDEND',   9, v_bal, to_timestamp((v_rday - 1) * 86400.0) - interval '1 second');

  -- ── THE COUNT, AS THE HALL AND THE MARKET FIND IT ──
  select pg.good_id into v_good from public.port_goods pg where pg.port_id = v_lis and pg.stock > 50 order by pg.good_id limit 1;
  v_base := (world.price_why(v_lis, v_good) -> 'volume' ->> 'units')::numeric;
  insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, day) values
    (v_lis, 9100000000000, now() - interval '20 minutes', 0, 0, 0, 0, 0, 0, 0, '{}'::jsonb, jsonb_build_object('kinds', jsonb_build_object('SELL', 1)));
  insert into public.stats_city (port_id, slot, at, purse, income, spending, taxes, works, sold, bought, flows, day) values
    (v_lis, 9100000000001, now() - interval '5 minutes', 0, 0, 0, 0, 0, 0, 0, '{}'::jsonb, jsonb_build_object('kinds', jsonb_build_object('BUY', 900, 'SELL', -500, 'TAX', 40)));
  insert into public.stats_city_good (port_id, good_id, slot, at, sold, bought, sold_ducats, bought_ducats) values
    (v_lis, v_good, 9100000000002, now() - interval '1 hour', 7, 4, 0, 0),
    (v_lis, v_good, 9100000000003, now() - interval '23 hours', 20, 0, 0, 0),
    (v_lis, v_good, 9100000000004, now() - interval '25 hours', 1000, 1000, 0, 0);

  foreach v_gds in array array[60, 2880] loop
    update public.world_config set value = to_jsonb(v_gds) where key = 'game_day_seconds';
    v_d := world.report('day');
    v_w := world.report('week');
    v_a := world.report('all');
    v_h := world.holdings();
    v_r := world.town_hall(v_lis);
    v_x := world.price_why(v_lis, v_good);
    if (v_d ->> 'total')::bigint <> 177 or (v_d ->> 'day')::int <> v_rday or jsonb_array_length(v_d -> 'days') <> 1 or (v_d #>> '{days,0,day}')::int <> v_rday then
      raise exception 'PROOF 26 FAIL: Today at % s: %', v_gds, v_d;
    end if;
    if (v_w ->> 'total')::bigint <> 1229 or jsonb_array_length(v_w -> 'days') <> 7 or (v_w #>> '{days,0,day}')::int <> v_rday - 6
       or (v_w #>> '{days,0,net}')::bigint <> 1000 or (v_w #>> '{days,5,net}')::bigint <> 43 or (v_w #>> '{days,6,net}')::bigint <> 177 then
      raise exception 'PROOF 26 FAIL: Week at % s: %', v_gds, v_w;
    end if;
    if (v_a #>> '{days,0,day}')::int > v_rday - 7 or jsonb_array_length(v_a -> 'days') > 400 then
      raise exception 'PROOF 26 FAIL: All at % s is not a bar a day: % bars', v_gds, jsonb_array_length(v_a -> 'days');
    end if;
    if (v_h #>> '{paid,today}')::bigint <> 77 or (v_h #>> '{paid,yesterday}')::bigint <> 33 or (v_h ->> 'day')::int <> v_rday then
      raise exception 'PROOF 26 FAIL: paid at % s: %', v_gds, v_h -> 'paid';
    end if;
    if v_r -> 'day' <> '{"in": {"BUY": 900, "TAX": 40}, "out": {"SELL": 500}}'::jsonb then
      raise exception 'PROOF 26 FAIL: the hall at % s: %', v_gds, v_r -> 'day';
    end if;
    if (v_x -> 'volume' ->> 'units')::numeric - v_base <> 31 or v_x -> 'volume' ? 'houses' then
      raise exception 'PROOF 26 FAIL: the market at % s: %', v_gds, v_x -> 'volume';
    end if;
  end loop;
  raise notice 'PASS: ADAY_REPORT — Today 177, Week 1,229 over 7 bars, All % bars, the same at 60 s and 2880 s', jsonb_array_length(v_a -> 'days');
  raise notice 'PASS: ADAY_PAID — today 77, yesterday 33, the row before yesterday left out';
  raise notice 'PASS: ADAY_HALL — in %, out %', v_r #> '{day,in}', v_r #> '{day,out}';
  raise notice 'PASS: ADAY_MARKET — 31 units in 24 hours, the 2,000 of 25 hours ago left out';

  -- ── A BARGAIN ──
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_base_success';
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_success_max';
  update public.world_config set value = to_jsonb(3) where key = 'haggle_attempts_per_day';
  update public.world_config set value = to_jsonb(60) where key = 'game_day_seconds';
  for i in 1 .. 3 loop
    v_r := cmd.haggle(v_f, v_good, 'buy');
    if (v_r ->> 'ok')::boolean is not true then
      raise exception 'PROOF 26 FAIL: bargain % refused: %', i, v_r;
    end if;
  end loop;
  v_base := public.haggle_concession(v_p, v_lis, v_good);
  update public.world_config set value = to_jsonb(2880) where key = 'game_day_seconds';   -- the game day number moves by millions, as it does each minute by one
  v_r := cmd.haggle(v_f, v_good, 'buy');
  if v_r ->> 'error_code' is distinct from 'E_HAGGLE_SPENT' then
    raise exception 'PROOF 26 FAIL: a new game day gave a fourth bargain: %', v_r;
  end if;
  if v_base <= 0 or public.haggle_concession(v_p, v_lis, v_good) <> v_base or (world.haggle_state(v_f, v_good) ->> 'attempts_left')::int <> 0 then
    raise exception 'PROOF 26 FAIL: a new game day took the bargain away: % -> %', v_base, public.haggle_concession(v_p, v_lis, v_good);
  end if;
  raise notice 'PASS: ADAY_HAGGLE — 3 tries, the 4th refused, the bargain held at %', v_base;

  -- ── A FAIR ──
  foreach v_gds in array array[60, 2880] loop
    begin
      update public.world_config set value = to_jsonb(v_gds) where key = 'game_day_seconds';
      delete from public.active_buffs;
      perform public.tick_buff_calendar(now());
      raise exception using errcode = 'ZX326', message = jsonb_build_object(
        'n', (select count(*) from public.active_buffs),
        'bad', (select count(*) from public.active_buffs b where b.ends_at - b.starts_at <> interval '11520 seconds' or b.season <> v_rday
                   or b.starts_at < v_start or b.ends_at > v_start + interval '1 day'),
        'digest', (select md5(string_agg(b.subject_id::text || b.starts_at::text, ',' order by b.subject_id)) from public.active_buffs b))::text;
    exception when sqlstate 'ZX326' then
      v_all := v_all || jsonb_build_object(v_gds::text, sqlerrm::jsonb);
    end;
  end loop;
  if (v_all #>> '{60,n}')::int < 1 or (v_all #>> '{60,bad}')::int <> 0 or (v_all #>> '{2880,bad}')::int <> 0 or v_all #>> '{60,digest}' <> v_all #>> '{2880,digest}' then
    raise exception 'PROOF 26 FAIL: the fairs: %', v_all;
  end if;
  raise notice 'PASS: ADAY_FAIR — % fairs of 3.2 hours inside today, the same at both clocks', v_all #>> '{60,n}';

  -- ── THE CROWN ──
  select p.id, public.city_capital(p.id) into v_city, v_cap from public.ports p
   where p.kind = 'HARBOUR' and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id order by p.code limit 1;
  if v_city is null then
    raise exception 'PROOF 26 FAIL: no harbour with a crown, so the crown''s check would be vacuous';
  end if;
  v_all := '{}'::jsonb;
  foreach v_gds in array array[60, 2880] loop
    begin
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
      update public.world_config set value = to_jsonb(v_gds) where key = 'game_day_seconds';
      update public.world_config set value = '0'::jsonb where key = 'works_level_max';
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      perform public.treasury_post(v_city, 'BUY', 10000000, null, null);
      perform public.tick_city(now());
      update public.port_treasury set earned_day = world.game_day() - 2;
      insert into public.treasury_flows (port_id, kind, ducats, created_at) values          -- past the daybook's 30 game days at the 60 s clock
        (v_city, 'TAX', 1000000, now() - interval '50 minutes'),
        (v_city, 'TAX',  500000, now() - interval '1 minute'),
        (v_city, 'BUY',  700000, now() - interval '1 minute');                              -- not tax
      v_r := public.tick_city(now());
      v_x := jsonb_build_object('errors', v_r -> 'errors',
        'city', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_TAX' and f.port_id = v_city and f.created_at = now() and f.ducats < 0),
        'left', (select t.tax_unshared from public.port_treasury t where t.port_id = v_city));
      update public.port_treasury set earned_day = world.game_day() - 2;
      v_r := public.tick_city(now());
      v_x := v_x || jsonb_build_object('errors2', v_r -> 'errors',   -- the first share has rolled: a flow here is a second one
        'city2', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_TAX' and f.port_id = v_city and f.ducats < 0));
      raise exception using errcode = 'ZX326', message = v_x::text;
    exception when sqlstate 'ZX326' then
      v_all := v_all || jsonb_build_object(v_gds::text, sqlerrm::jsonb);
    end;
  end loop;
  foreach v_gds in array array[60, 2880] loop
    v_x := v_all -> v_gds::text;
    if v_x -> 'errors' <> '{}'::jsonb or v_x -> 'errors2' <> '{}'::jsonb then
      raise exception 'PROOF 26 FAIL: the tick''s receipt at % s: %', v_gds, v_x;
    end if;
    if (v_x ->> 'city')::bigint is distinct from -round(1500000 * v_share)::bigint then
      raise exception 'PROOF 26 FAIL: the crown''s share at % s is not its share of the whole tax: %', v_gds, v_x;
    end if;
    if (v_x ->> 'left')::bigint <> 0 or v_x ->> 'city2' is not null then
      raise exception 'PROOF 26 FAIL: the crown''s share was taken twice at % s: %', v_gds, v_x;
    end if;
  end loop;
  raise notice 'PASS: ADAY_CROWN — 1,500,000 d. of TAX, 1,000,000 of it 50 minutes old: % at 60 s, % at 2880 s, nothing a second time', v_all #>> '{60,city}', v_all #>> '{2880,city}';
end
$$;
