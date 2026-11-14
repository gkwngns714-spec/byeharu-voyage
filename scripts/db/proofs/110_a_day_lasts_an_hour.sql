-- ══════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 110 - A DAY LASTS AN HOUR  (migration 0413; docs/dev-log/2026-11-14-day-hour.md)
--
--   On probe houses put to sea Lisbon to Setubal, rolled back with proof.mjs's transaction. The clock's rate is moved through its one door,
--   public.clock_set, at instants passed in (nothing waits): forward as the migration moved it, and back as a rollback would.
--
-- @pass DH_KNOB     the one authority: time_compression 192; a voyage-day 450 s; a day of the clock clock_voyage_days (8) of them, 3,600 s, derived; world.snapshot() serves the three; no player may call the door or the counters
-- @pass DH_ANCHOR   the clock does not jump: from the clock as it was drawn before 0413, the anchor at 2026-11-14 10:00:10 UTC reads day 2652.01388889 (the date 13 May 1507 as printed, the hour 00:20 as it stood); from an anchor, half a day's seconds later is half a day on, at either rate
-- @pass DH_SAIL     a voyage under way keeps her mile at the switch and sails what is left five times as long; the eta's own authority agrees; her next day boundary is five times as far off
-- @pass DH_DAYS     no day is settled twice and none is skipped: on a five-day passage switched in her third day, the days complete at the switch are the same 2; voyage.settle at the switch settles nothing new; at her new third boundary, exactly one
-- @pass DH_HOLD     a voyage held by a battle across the switch stands where she stood until the hold's own end, then sails the rest five times as long
-- @pass DH_BACK     the rollback is continuous too: moved back to 960 at the same instant, departure and arrival return to what they were (within a millisecond) and so does every mile
-- @pass DH_MARKET_SAME  THE INVARIANT: per voyage-day the market regenerates and drifts exactly as much as before. One harbour's rows, staged the same, stepped by public.tick_market_drift 100 voyage-days on at the old rate (9,000 s) and 100 voyage-days on after the switch (45,000 s), with the walk's noise at 0: every row's drift, stock, press, slots stepped and days regenerated are the same, to the digit; and per real time a fifth as many slots and days pass
-- @pass DH_MARKET_CONT  nothing steps twice or five at once, nothing stops: at the switch the drift job steps no row and regenerates none; a hair before the slot's re-timed end, none; a hair after it every row once, by ONE slot's step (theta x drift, not theta to the fifth); a hair after the day's re-timed end every row is regenerated ONE day
-- @pass DH_COUNTERS    the four counters (game day, drift slot, want period, population slot) each read the same count at the switch, the same count for an instant three days back, end their period five times as far off, and come back to the same next start when the clock is moved back at the same instant
-- @pass DH_REQUEST     an open request keeps its day number: the read serves its end five times as far off as it was (the same number of voyage-days); public.contracts_expire a second before that end leaves it open, a second after it expires it
-- @pass DH_DIVIDEND    a share stamped six hours before the switch is due, at the first coupon after it, a fifth of what it was due before (the rate per real day is a fifth; the real days it is paid for are the same): not five times, and not nothing
-- @pass DH_RATES       the economy's rates per real time are a fifth and its half-lives five times: navy_upkeep_day, works_coupon_day, pirate_spend_day_pct, population_tax_per_1000; glut_half_life_hours, invested_half_life_hours; moved back, each is what it was; drift_spread_runs NOT moved (0420: a pace in real minutes)
-- @pass DH_STAYS    what paces a person stays in real time: port_prep_seconds, battle_seconds, attack_cooldown_minutes, gift_cooldown_hours, loot_per_company_day, skill_sp_per_hour, regard_half_life_hours, contract_npc_after_hours; and contract_deadline_days stays a count of market days
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_at     constant timestamptz := '2026-11-14 10:00:10+00';
  v_r      jsonb;
  v_cfg    jsonb;
  v_lis    uuid;
  v_set    uuid;
  v_segs   jsonb;
  v_course jsonb;
  v_h      uuid;
  v_fa     uuid;
  v_fb     uuid;
  v_fc     uuid;
  v_va     uuid;
  v_vb     uuid;
  v_vc     uuid;
  v_dep    timestamptz := now();
  v_dep0   timestamptz;
  v_eta_a  timestamptz;
  v_eta_b  timestamptz;
  v_eta_c  timestamptz;
  v_at     timestamptz;
  v_a      timestamptz;
  v_b      timestamptz;
  v_mid    timestamptz;
  v_post   timestamptz;
  v_pa_at  numeric;
  v_pa_mid numeric;
  v_pb_at  numeric;
  v_pb_post numeric;
  v_pc_at  numeric;
  v_d3     timestamptz;
  v_e      timestamptz;
  v_keep   jsonb;
  v_n      int;
  v_note   text;
  v_note2  text;
  c_stay   constant text[] := array['port_prep_seconds', 'battle_seconds', 'attack_cooldown_minutes', 'gift_cooldown_hours', 'loot_per_company_day', 'skill_sp_per_hour',
                                    'regard_half_life_hours', 'contract_npc_after_hours', 'contract_deadline_days'];
  c_move   constant text[] := array['game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds', 'drift_spread_runs', 'glut_half_life_hours',
                                    'invested_half_life_hours', 'navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000'];
  c_kinds  constant text[] := array['game_day', 'drift_slot', 'want_period', 'population_slot'];
  v_new_k  jsonb;
  v_old_k  jsonb;
  v_k      text;
  v_s0     bigint;
  v_d0     int;
  v_rows   int;
  v_ma     text;
  v_mb     text;
  v_j      jsonb;
  v_c0     jsonb := '{}'::jsonb;
  v_left   numeric;
  v_good   uuid;
  v_con    uuid := gen_random_uuid();
  v_e0     timestamptz;
  v_e1     timestamptz;
  v_due0   bigint;
  v_due1   bigint;
  v_t      timestamptz;
begin
  -- ── DH_KNOB ──
  v_cfg := world.snapshot()->'config';
  if public.wc_num('time_compression') <> 192 or public.wc_num('clock_voyage_days') <> 8
     or 86400 / public.wc_num('time_compression') <> 450 or 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression') <> 3600
     or (v_cfg->>'time_compression')::numeric <> 192 or (v_cfg->>'clock_voyage_days')::numeric <> 8
     or v_cfg->'clock_anchor' is distinct from (select value from public.world_config where key = 'clock_anchor')
     or (v_cfg->'clock_anchor'->>'was')::numeric <> 960 or (v_cfg->'clock_anchor'->>'is')::numeric <> 192 or v_cfg->'clock_anchor'->>'at' is null
     or has_function_privilege('anon', 'public.clock_set(integer,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.clock_set(integer,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.clock_count(text,timestamp with time zone)', 'execute') or has_function_privilege('anon', 'public.clock_start(text,bigint)', 'execute') then
    raise exception 'proof 110 DH_KNOB: the clock is not one authority served (config %)', v_cfg;
  end if;
  raise notice 'PASS: DH_KNOB — time_compression 192, a voyage-day 450 s, a day of the clock 8 of them = 3,600 s; served: %', v_cfg->'clock_anchor';

  select jsonb_object_agg(key, value) into v_keep from public.world_config where key = any (c_stay);
  select jsonb_object_agg(key, value) into v_new_k from public.world_config where key = any (c_move);

  -- ── DH_ANCHOR: the clock put back through its door, and its anchor emptied by hand: the clock as the client drew it before 0413 ──
  perform public.clock_set(960, now());
  update public.world_config set value = '{}'::jsonb where key = 'clock_anchor';
  v_r := public.clock_set(192, c_at);
  if round((v_r->>'clock_day')::numeric, 8) <> 2652.01388889 or (v_r->>'clock_day_seconds')::numeric <> 3600 then
    raise exception 'proof 110 DH_ANCHOR: the anchor at % is %, not day 2652.01388889 of an hour', c_at, v_r;
  end if;
  v_r := public.clock_set(96, c_at + interval '1800 seconds');      -- half an hour on at 192: half a day
  if abs((v_r->>'clock_day')::numeric - (2652.01388889 + 0.5)) > 0.0000001 then
    raise exception 'proof 110 DH_ANCHOR: half an hour at 192 is not half a day (%)', v_r;
  end if;
  v_r := public.clock_set(192, c_at + interval '5400 seconds');     -- an hour on at 96 (a day of two hours): half a day
  if abs((v_r->>'clock_day')::numeric - (2652.01388889 + 1.0)) > 0.0000001 then
    raise exception 'proof 110 DH_ANCHOR: an hour at 96 is not half a day (%)', v_r;
  end if;
  if (public.clock_set(192, c_at)->>'moved')::boolean then
    raise exception 'proof 110 DH_ANCHOR: the same rate was written again';
  end if;
  raise notice 'PASS: DH_ANCHOR — day 2652.01388889 at 2026-11-14 10:00:10 UTC from the clock as it was; +0.5 after 1,800 s at 192; +0.5 after 3,600 s at 96; the same rate writes nothing';

  -- ── THE WORLD AS IT WAS BEFORE 0413: the rate moved back through the door (every length and rate with it), then both anchors emptied by hand ──
  perform public.clock_set(960, v_dep);
  update public.world_config set value = '{}'::jsonb where key in ('clock_anchor', 'market_clock_anchor');
  select jsonb_object_agg(key, value) into v_old_k from public.world_config where key = any (c_move);
  -- 0420: drift_spread_runs is a pace in real minutes; the door no longer moves it
  if exists (select 1 from unnest(array['game_day_seconds', 'drift_slot_seconds', 'want_period_seconds', 'population_slot_seconds', 'glut_half_life_hours', 'invested_half_life_hours']) k
              where (v_new_k ->> k)::numeric <> 5 * (v_old_k ->> k)::numeric)
     or (v_new_k ->> 'drift_spread_runs')::numeric <> (v_old_k ->> 'drift_spread_runs')::numeric
     or exists (select 1 from unnest(array['navy_upkeep_day', 'works_coupon_day', 'pirate_spend_day_pct', 'population_tax_per_1000']) k
                 where (v_new_k ->> k)::numeric * 5 <> (v_old_k ->> k)::numeric)
     or world.game_day(v_dep) <> floor(extract(epoch from v_dep) / public.wc_num('game_day_seconds'))::int then
    raise exception 'proof 110 DH_RATES: the lengths are not five times and the rates a fifth of what the door puts back (after 0413 %, back %)', v_new_k, v_old_k;
  end if;
  raise notice 'PASS: DH_RATES — after 0413 %; moved back through the door %', v_new_k, v_old_k;

  -- ── THE MARKET. Lisbon's rows staged: every drift 0.1, on the slot and the day of now, stock at three tenths of its target, a press of 0.5; the walk's noise 0 ──
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
  update public.world_config set value = to_jsonb(0.9) where key = 'drift_theta';
  v_s0 := public.drift_slot_of(v_dep);
  v_d0 := world.game_day(v_dep);
  update public.port_goods pg set drift = 0.1, drift_slot = v_s0, last_regen_day = v_d0, stock = round(coalesce(pg.stock_target, 100) * 0.3), glut = 0.5, glut_at = v_dep
   where pg.port_id = v_lis;
  get diagnostics v_rows = row_count;
  if v_rows < 5 then raise exception 'proof 110: Lisbon has % market rows', v_rows; end if;
  foreach v_k in array c_kinds loop
    v_c0 := v_c0 || jsonb_build_object(v_k, jsonb_build_object('now', public.clock_count(v_k, v_dep), 'past', public.clock_count(v_k, v_dep - interval '3 days'),
              'next', extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_dep) + 1) - v_dep)));
  end loop;

  -- ── DH_MARKET_SAME: (A) 100 voyage-days on at the old rate, rolled back; (B) the switch, then 100 voyage-days on, rolled back ──
  begin
    v_j := public.tick_market_drift(v_dep + make_interval(secs => (100 * 86400 / public.wc_num('time_compression'))::double precision), v_lis);
    select md5(string_agg(pg.good_id || ':' || pg.drift || ':' || pg.stock || ':' || pg.glut || ':' || (pg.drift_slot - v_s0) || ':' || (pg.last_regen_day - v_d0), ',' order by pg.good_id)),
           min(pg.drift_slot - v_s0) || ' slots, ' || min(pg.last_regen_day - v_d0) || ' days, drift ' || min(pg.drift) || ', stock of the first row ' || (array_agg(pg.stock order by pg.good_id))[1]
      into v_ma, v_note from public.port_goods pg where pg.port_id = v_lis;
    if (v_j ->> 'drifted')::int <> v_rows or (v_j ->> 'regenerated')::int <> v_rows then raise exception 'proof 110 DH_MARKET_SAME: at the old rate the job stepped % of % rows', v_j, v_rows; end if;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  begin
    perform public.clock_set(192, v_dep);
    v_j := public.tick_market_drift(v_dep + make_interval(secs => (100 * 86400 / public.wc_num('time_compression'))::double precision), v_lis);
    select md5(string_agg(pg.good_id || ':' || pg.drift || ':' || pg.stock || ':' || pg.glut || ':' || (pg.drift_slot - v_s0) || ':' || (pg.last_regen_day - v_d0), ',' order by pg.good_id)),
           min(pg.drift_slot - v_s0) || ' slots, ' || min(pg.last_regen_day - v_d0) || ' days, drift ' || min(pg.drift) || ', stock of the first row ' || (array_agg(pg.stock order by pg.good_id))[1]
      into v_mb, v_note2 from public.port_goods pg where pg.port_id = v_lis;
    -- per real time a fifth: the 9,000 s that were 100 voyage-days hold a fifth of the slots and of the days (to the whole period)
    v_n := (public.drift_slot_of(v_dep + interval '9000 seconds') - v_s0)::int;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  if v_ma is null or v_ma is distinct from v_mb or v_note is distinct from v_note2 or v_note like '0 slots%' or v_note like '%drift 0.1,%' then
    raise exception 'proof 110 DH_MARKET_SAME: 100 voyage-days on, the harbour is not the same before (%) and after the switch (%)', v_note, v_note2;
  end if;
  if v_n > ceil(split_part(v_note, ' ', 1)::numeric / 5) or v_n < floor(split_part(v_note, ' ', 1)::numeric / 5) then
    raise exception 'proof 110 DH_MARKET_SAME: in the same 9,000 s % slots pass after the switch, not a fifth of %', v_n, v_note;
  end if;
  raise notice 'PASS: DH_MARKET_SAME — % rows of Lisbon, 100 voyage-days on (9,000 s before, 45,000 s after): % in both, every row''s drift, stock, press, slots and days equal as text; in the same 9,000 real seconds after the switch: % slot(s)', v_rows, v_note, v_n;

  -- ── DH_MARKET_CONT and DH_COUNTERS: the switch at v_dep, rolled back ──
  begin
    perform public.clock_set(192, v_dep);
    v_j := public.tick_market_drift(v_dep, v_lis);
    if (v_j ->> 'drifted')::int <> 0 or (v_j ->> 'regenerated')::int <> 0 then raise exception 'proof 110 DH_MARKET_CONT: at the switch the job stepped %', v_j; end if;
    v_left := 5 * (v_c0 -> 'drift_slot' ->> 'next')::numeric;
    v_j := public.tick_market_drift(v_dep + make_interval(secs => least(v_left, 5 * (v_c0 -> 'game_day' ->> 'next')::numeric)::double precision - 0.01), v_lis);
    if (v_j ->> 'drifted')::int <> 0 or (v_j ->> 'regenerated')::int <> 0 then raise exception 'proof 110 DH_MARKET_CONT: a hair before the period''s re-timed end the job stepped %', v_j; end if;
    v_j := public.tick_market_drift(v_dep + make_interval(secs => (5 * (v_c0 -> 'game_day' ->> 'next')::numeric)::double precision + 0.01), v_lis);
    if (v_j ->> 'regenerated')::int <> v_rows or exists (select 1 from public.port_goods pg where pg.port_id = v_lis and pg.last_regen_day <> v_d0 + 1) then
      raise exception 'proof 110 DH_MARKET_CONT: a hair after the day''s re-timed end not every row is regenerated one day (%)', v_j;
    end if;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  begin
    perform public.clock_set(192, v_dep);
    v_left := 5 * (v_c0 -> 'drift_slot' ->> 'next')::numeric;
    v_j := public.tick_market_drift(v_dep + make_interval(secs => v_left::double precision + 0.01), v_lis);
    if (v_j ->> 'drifted')::int <> v_rows or exists (select 1 from public.port_goods pg where pg.port_id = v_lis and (pg.drift_slot <> v_s0 + 1 or pg.drift <> 0.09)) then
      raise exception 'proof 110 DH_MARKET_CONT: a hair after the slot''s re-timed end not every row is stepped once by one slot (%; a drift of %)', v_j, (select min(pg.drift) from public.port_goods pg where pg.port_id = v_lis);
    end if;
    -- the counters
    foreach v_k in array c_kinds loop
      if public.clock_count(v_k, v_dep) <> (v_c0 -> v_k ->> 'now')::bigint or public.clock_count(v_k, v_dep - interval '3 days') <> (v_c0 -> v_k ->> 'past')::bigint
         or abs(extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_dep) + 1) - v_dep) - 5 * (v_c0 -> v_k ->> 'next')::numeric) > 0.001 then
        raise exception 'proof 110 DH_COUNTERS: % is not counted on across the switch (before %)', v_k, v_c0 -> v_k;
      end if;
    end loop;
    if world.game_day(v_dep) <> v_d0 or public.drift_slot_of(v_dep) <> v_s0 or public.want_period(v_dep) <> (v_c0 -> 'want_period' ->> 'now')::bigint then
      raise exception 'proof 110 DH_COUNTERS: a counter''s own name moved at the switch';
    end if;
    perform public.clock_set(960, v_dep);
    foreach v_k in array c_kinds loop
      if public.clock_count(v_k, v_dep) <> (v_c0 -> v_k ->> 'now')::bigint
         or abs(extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_dep) + 1) - v_dep) - (v_c0 -> v_k ->> 'next')::numeric) > 0.001 then
        raise exception 'proof 110 DH_COUNTERS: moved back at the same instant % does not come back to its next start (before %, now % s off)', v_k, v_c0 -> v_k,
          extract(epoch from public.clock_start(v_k, public.clock_count(v_k, v_dep) + 1) - v_dep);
      end if;
    end loop;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  raise notice 'PASS: DH_MARKET_CONT — at the switch the job steps 0 rows and regenerates 0; a hair before the re-timed end 0; a hair after the slot''s end % rows once, drift 0.1 -> 0.09 (one slot); a hair after the day''s end % rows, one day each', v_rows, v_rows;
  raise notice 'PASS: DH_COUNTERS — %: the same count at the switch and three days back, the next start five times as far off, and back where it was when the clock is moved back', v_c0;

  -- ── DH_REQUEST: a probe request at Lisbon that ends two market days on ──
  select pg.good_id into v_good from public.port_goods pg where pg.port_id = v_lis order by pg.good_id limit 1;
  insert into public.trade_contracts (id, port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow)
  values (v_con, v_lis, v_good, v_d0, 9110, 10, 0.1, 10, 1, 10, v_d0 + 2, 'open', 0);
  v_e0 := public.clock_start('game_day', v_d0 + 2);
  if v_e0 <> to_timestamp(((v_d0 + 2) * public.wc_num('game_day_seconds'))::double precision) then raise exception 'proof 110 DH_REQUEST: before the switch its end is not the day number x the length'; end if;
  begin
    perform public.clock_set(192, v_dep);
    v_e1 := (select (c ->> 'expires_at')::timestamptz from jsonb_array_elements(world.contracts(v_lis) -> 'contracts') c where (c ->> 'id')::uuid = v_con);
    if v_e1 is null or abs(extract(epoch from v_e1 - (v_dep + (v_e0 - v_dep) * 5))) > 0.001 then
      raise exception 'proof 110 DH_REQUEST: the read serves its end at %, not five times as far off as % (from %)', v_e1, v_e0, v_dep;
    end if;
    perform public.contracts_expire(v_lis, v_e0 + interval '1 second');   -- its OLD end has passed: it must not expire early
    perform public.contracts_expire(v_lis, v_e1 - interval '1 second');
    if (select status from public.trade_contracts where id = v_con) <> 'open' then raise exception 'proof 110 DH_REQUEST: it expired before its end'; end if;
    perform public.contracts_expire(v_lis, v_e1 + interval '1 second');
    if (select status from public.trade_contracts where id = v_con) <> 'expired' then raise exception 'proof 110 DH_REQUEST: it did not expire at its end'; end if;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  raise notice 'PASS: DH_REQUEST — a request ending two market days on: % s off before, % s off after (five times; the same voyage-days); open a second after its old end and a second before its new one, expired a second after', round(extract(epoch from v_e0 - v_dep)), round(extract(epoch from v_e1 - v_dep));

  -- ── DH_DIVIDEND: a probe share at Lisbon, stamped six hours ago; the city's last coupon yesterday ──
  v_h := public.new_house('00000000-0000-4000-8000-00000000110d'::uuid, 'Casa Cupao', 'PRT');
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values (v_lis, 'docks', v_h, 1, 10000000, 0, world.game_day(v_dep - interval '6 hours'));
  update public.port_treasury t set coupon_day = public.real_day(v_dep) - 1, profit = 1000000000 where t.port_id = v_lis;
  begin
    v_due0 := (public.city_coupons(v_lis, v_dep) ->> 'due')::bigint;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  begin
    perform public.clock_set(192, v_dep);
    v_due1 := (public.city_coupons(v_lis, v_dep) ->> 'due')::bigint;
    raise exception sqlstate 'PF110';
  exception when sqlstate 'PF110' then null;
  end;
  if coalesce(v_due0, 0) <= 0 or abs(v_due1 * 5 - v_due0) > 5 then
    raise exception 'proof 110 DH_DIVIDEND: the share was due % before the switch and % at the first coupon after it (wanted a fifth)', v_due0, v_due1;
  end if;
  raise notice 'PASS: DH_DIVIDEND — a share of 10,000,000 d. stamped six hours ago: due % d. before the switch, % d. at the first coupon after it (a fifth: the rate per real day is a fifth, the real days are the same)', v_due0, v_due1;

  -- ── THE SCENE AT SEA: three houses at the OLD rate. A plain; B held by a battle; C on a five-day passage ──
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_set from public.ports where code = 'SET';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_course from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_set;
  v_segs := voyage.segments_from_course(v_course);
  v_h := public.new_house('00000000-0000-4000-8000-00000000110a'::uuid, 'Casa Hora', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_h limit 1;
  v_h := public.new_house('00000000-0000-4000-8000-00000000110b'::uuid, 'Casa Relogio', 'PRT');
  select f.id into v_fb from public.fleets f where f.player_id = v_h limit 1;
  v_h := public.new_house('00000000-0000-4000-8000-00000000110c'::uuid, 'Casa Dias', 'PRT');
  select f.id into v_fc from public.fleets f where f.player_id = v_h limit 1;
  v_va := voyage.depart(v_fa, v_segs, v_lis, v_set, v_dep);
  v_vb := voyage.depart(v_fb, v_segs, v_lis, v_set, v_dep);
  v_vc := voyage.depart(v_fc, v_segs, v_lis, v_set, v_dep);
  select eta into v_eta_a from public.voyages where id = v_va;
  -- C's water is stretched to five days of sailing (her row only: the miles of each segment and their sum), her days quiet
  update public.voyages v
     set path = (select jsonb_agg(e || jsonb_build_object('nm', (e->>'nm')::numeric * x.k, 'hazard_mult', 0) order by o) from jsonb_array_elements(v.path) with ordinality t(e, o)),
         total_nm = v.total_nm * x.k
    from (select 5 * 24 / voyage.sim_hours(v_vc) as k) x
   where v.id = v_vc;
  perform voyage.recompute_eta(v_vc);
  select eta into v_eta_c from public.voyages where id = v_vc;
  if round(extract(epoch from v_eta_c - v_dep)) <> 450 then
    raise exception 'proof 110: the five-day passage is % s at 960, not 450', extract(epoch from v_eta_c - v_dep);
  end if;
  v_a  := v_dep + (v_eta_a - v_dep) * 0.2;
  v_b  := v_a + (v_eta_a - v_dep) * 0.4;
  v_at := v_a + (v_eta_a - v_dep) * 0.1;
  perform voyage.hold(v_fb, v_b, v_a);
  select eta into v_eta_b from public.voyages where id = v_vb;
  v_mid  := v_at + (v_eta_a - v_at) / 2;
  v_post := v_b + (v_eta_b - v_b) / 2;
  v_pa_at := voyage.progress_nm(v_va, v_at);  v_pa_mid := voyage.progress_nm(v_va, v_mid);
  v_pb_at := voyage.progress_nm(v_vb, v_at);  v_pb_post := voyage.progress_nm(v_vb, v_post);

  -- ── DH_DAYS, first half: C is switched 2.6 days in (234 s at 960). The clock is moved at THAT instant for C's proof, in its own sub-transaction ──
  begin
    declare
      v_t   timestamptz := v_dep + interval '234 seconds';
      v_s0  int;
    begin
      if voyage.days_complete(v_vc, v_t) <> 2 then
        raise exception 'proof 110 DH_DAYS: % day(s) complete 2.6 days in, not 2', voyage.days_complete(v_vc, v_t);
      end if;
      perform voyage.settle(v_fc, v_t);
      select last_settled_day into v_s0 from public.voyages where id = v_vc;
      v_pc_at := voyage.progress_nm(v_vc, v_t);
      v_d3 := voyage.day_ends_at(v_vc, 3);
      if v_s0 <> 2 or round(extract(epoch from v_d3 - v_t)) <> 36 then
        raise exception 'proof 110 DH_DAYS: before the switch % day(s) are settled and the third ends in % s (wanted 2 and 36)', v_s0, extract(epoch from v_d3 - v_t);
      end if;
      perform public.clock_set(192, v_t);
      if voyage.days_complete(v_vc, v_t) <> 2 or abs(voyage.progress_nm(v_vc, v_t) - v_pc_at) > 0.01 then
        raise exception 'proof 110 DH_DAYS: at the switch % day(s) are complete and she is at % nm (wanted 2 and %)', voyage.days_complete(v_vc, v_t), voyage.progress_nm(v_vc, v_t), v_pc_at;
      end if;
      perform voyage.settle(v_fc, v_t);
      if (select last_settled_day from public.voyages where id = v_vc) <> 2 then
        raise exception 'proof 110 DH_DAYS: a day was settled at the switch itself';
      end if;
      if abs(extract(epoch from voyage.day_ends_at(v_vc, 3) - v_t) - 180) > 0.01 or (select abs(extract(epoch from due_at - v_t) - 180) > 0.01 from public.voyages where id = v_vc) then
        raise exception 'proof 110 DH_DAYS: her third day ends % s after the switch, not 180 (five times the 36 that were left)', extract(epoch from voyage.day_ends_at(v_vc, 3) - v_t);
      end if;
      perform voyage.settle(v_fc, v_t + interval '179 seconds');
      v_n := (select last_settled_day from public.voyages where id = v_vc);
      perform voyage.settle(v_fc, v_t + interval '181 seconds');
      if v_n <> 2 or (select last_settled_day from public.voyages where id = v_vc) <> 3 then
        raise exception 'proof 110 DH_DAYS: around her new third boundary % then % day(s) are settled (wanted 2 then 3)', v_n, (select last_settled_day from public.voyages where id = v_vc);
      end if;
      -- she arrives five times what was left after the switch: 216 s at 960 are 1,080 s
      if abs(extract(epoch from (select eta from public.voyages where id = v_vc) - v_t) - 1080) > 0.01 then
        raise exception 'proof 110 DH_DAYS: she arrives % s after the switch, not 1,080', extract(epoch from (select eta from public.voyages where id = v_vc) - v_t);
      end if;
      raise exception sqlstate 'PF110';
    end;
  exception when sqlstate 'PF110' then null;
  end;
  raise notice 'PASS: DH_DAYS — switched 2.6 days into a five-day passage: 2 days complete before and after; settle at the switch settles none; her third day ends 180 s on (36 s were left); settle 179 s on: 2 days, 181 s on: 3; she arrives 1,080 s on (216 s were left)';

  -- ── DH_SAIL, DH_HOLD: the switch at v_at ──
  select departed_at into v_dep0 from public.voyages where id = v_va;
  v_r := public.clock_set(192, v_at);
  select eta into v_e from public.voyages where id = v_va;
  if abs(voyage.progress_nm(v_va, v_at) - v_pa_at) > 0.01
     or abs(extract(epoch from v_e - (v_at + (v_eta_a - v_at) * 5))) > 0.005 or abs(extract(epoch from voyage.recompute_eta(v_va) - v_e)) > 0.005
     or abs(voyage.progress_nm(v_va, v_at + (v_mid - v_at) * 5) - v_pa_mid) > 0.01
     or abs(voyage.progress_nm(v_va, v_at + (v_mid - v_at)) - (v_pa_at + (v_pa_mid - v_pa_at) / 5)) > 0.01 then
    raise exception 'proof 110 DH_SAIL: the plain voyage moved or is mis-timed (at the switch % nm, was %; eta %, wanted %)', voyage.progress_nm(v_va, v_at), v_pa_at, v_e, v_at + (v_eta_a - v_at) * 5;
  end if;
  raise notice 'PASS: DH_SAIL — % nm at the switch before and after; % s were left, % s are; the same mile five times later; a fifth of the way in the same wait', v_pa_at,
    round(extract(epoch from v_eta_a - v_at), 2), round(extract(epoch from v_e - v_at), 2);

  select eta into v_e from public.voyages where id = v_vb;
  if (v_r->>'holds')::int < 1 or abs(voyage.progress_nm(v_vb, v_at) - v_pb_at) > 0.01 or abs(voyage.progress_nm(v_vb, v_b) - v_pb_at) > 0.01
     or abs(voyage.progress_nm(v_vb, v_at + (v_b - v_at) / 2) - v_pb_at) > 0.01
     or abs(extract(epoch from v_e - (v_b + (v_eta_b - v_b) * 5))) > 0.05
     or abs(voyage.progress_nm(v_vb, v_b + (v_post - v_b) * 5) - v_pb_post) > 0.01 then
    raise exception 'proof 110 DH_HOLD: the held voyage moved inside her hold or is mis-timed after it (% / % nm, was %; eta %, wanted %)',
      voyage.progress_nm(v_vb, v_at), voyage.progress_nm(v_vb, v_b), v_pb_at, v_e, v_b + (v_eta_b - v_b) * 5;
  end if;
  raise notice 'PASS: DH_HOLD — she stands at % nm from the switch to the hold''s own end, then sails the rest five times as long', v_pb_at;

  -- ── DH_BACK: the rollback, at the same instant ──
  perform public.clock_set(960, v_at);
  if (select abs(extract(epoch from v.departed_at - v_dep0)) > 0.001 or abs(extract(epoch from v.eta - v_eta_a)) > 0.001 from public.voyages v where v.id = v_va)
     or abs(voyage.progress_nm(v_va, v_mid) - v_pa_mid) > 0.01
     or (select abs(extract(epoch from v.eta - v_eta_b)) > 0.05 from public.voyages v where v.id = v_vb)
     or abs(voyage.progress_nm(v_vb, v_post) - v_pb_post) > 0.01 or abs(voyage.progress_nm(v_vb, v_b) - v_pb_at) > 0.01 then
    raise exception 'proof 110 DH_BACK: moved back to 960 the voyages are not where they were (A eta %, was %; B eta %, was %)',
      (select eta from public.voyages where id = v_va), v_eta_a, (select eta from public.voyages where id = v_vb), v_eta_b;
  end if;
  raise notice 'PASS: DH_BACK — back at 960 at the same instant: departures, arrivals and miles are what they were';

  -- ── DH_STAYS ──
  if (select jsonb_object_agg(key, value) from public.world_config where key = any (c_stay)) is distinct from v_keep then
    raise exception 'proof 110 DH_STAYS: a real-time knob moved with the clock';
  end if;
  raise notice 'PASS: DH_STAYS — %', v_keep;
end $p$;
