-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 59 — A LEVEL CROSSED IS A MOMENT  (migration 0356, slice R4 of docs/REPUTATION.md, owner row 317)
--
--   The migration's self-assert crosses levels by miles on stubs. This proof plays the doors: a new house buys at the
--   quay (turnover), calls cmd.level_up, sails a real voyage that voyage.settle lands, sells at the far quay, closes
--   real standing-route laps. Every gift is held to the rule (rep_level_per_level x the level), every crossing to ONE
--   event and ONE book row, and the levels themselves to public.player_progress, byte for byte.
--   Everything rolls back with proof.mjs's transaction, the knobs set here with it (hazard_p_max 0 as proofs 04 and 55;
--   levels_bite, reputation_on and rep_level_per_level are each set and put back inside their own marker).
--
-- @pass LEVEL_MERCHANT_NOTHING  a merchant's settle, arrival and real laps closed at a gain: null, no write to the marks or the Reputation tables, and public.player_progress is not called once (pg_stat_xact_user_functions; a human's settle is the positive control)
-- @pass LEVEL_ONCE              a new house's first session through the doors: each level crossed is ONE LEVEL_UP event and ONE book row of 10 x the level; the door and the arrival called again write nothing; the first session's levels and Reputation are printed
-- @pass LEVEL_NO_BACKPAY        a house with history whose marks are seeded as the migration seeds them is paid nothing by the door or by an arrival; her next crossing pays that level alone
-- @pass LEVEL_STAYS_DERIVED     public.player_progress and world.levels() are byte-equal before and after a settle that pays, and after a mark is moved by hand; only the settle and the card name the marks table (pg_proc scan); a sale does not call the settle
-- @pass LEVEL_COMBAT_PLAYABLE   while combat is not playable her fights make no mark and no event; lit, each combat level crossed fires once
-- @pass LEVEL_SWITCHES          reputation_on false: the settle writes nothing and pays when it is lit again; rep_level_per_level 0: the event fires with reputation 0 and no book row
-- @pass LEVEL_LAP               a real standing-route lap closed at a gain pays rep_lap once (key lap:<lap id>, inside the day's cap); a lap closed at a loss pays nothing
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0359-4000-8000-000000000001';
  c_b     constant uuid := '00000000-0359-4000-8000-000000000002';
  c_c     constant uuid := '00000000-0359-4000-8000-000000000003';
  c_tabs  constant text[] := array['house_level_marks', 'reputation_kinds', 'reputation_balance', 'reputation_book'];
  v_gift  constant int := public.wc_int('rep_level_per_level');
  v_lap_pay constant int := public.wc_int('rep_lap');
  v_npc   uuid;
  v_nfl   uuid;
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_fleet uuid;
  v_bfl   uuid;
  v_lis   uuid;
  v_dest  uuid;
  v_dest_code text;
  v_good  uuid;
  v_good_code text;
  v_mcode text;
  v_qty   numeric;
  v_voy   uuid;
  v_nm    numeric;
  v_route uuid;
  v_nroute uuid;
  v_lap   uuid;
  v_w     bigint;
  v_calls bigint;
  v_n     int;
  v_m     int;
  v_seq   int;
  v_ev    int;
  v_r     jsonb;
  v_r2    jsonb;
  v_pp    jsonb;
  v_pp2   jsonb;
  v_lv    text;
  v_t     timestamptz;
  v_ms    numeric;
  v_want  int;
  v_t_lv  int;
  v_e_lv  int;
  v_names text;
  v_first text := '';
  v_nm4   numeric := greatest(public.wc_num('level_points_per_step') * 9 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point');
  v_nm2   numeric := greatest(public.wc_num('level_points_per_step') * 1 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point');
begin
  if v_gift <> 10 or v_lap_pay <> 10 then
    raise exception 'PROOF 59 FAILED: the knobs are not the chain''s (rep_level_per_level %, rep_lap %)', v_gift, v_lap_pay;
  end if;
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  set local track_functions = 'pl';

  -- ── LEVEL_MERCHANT_NOTHING (asked first: the counters are this transaction's) ──
  v_npc := public.new_house(null, 'Casa Mercante 59', 'PRT', 'LIS', 'Mercante', 'barca', 'Mercante', 5000000, true);
  select id into v_nfl from public.fleets where player_id = v_npc;
  select g.code into v_mcode
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0
   order by pg.stock_target desc, g.code limit 1;
  insert into public.events (player_id, kind, payload) values (v_npc, 'VOYAGE_REPORT', jsonb_build_object('to', 'P59', 'total_nm', v_nm4));   -- the miles of level 4 behind her
  if public.level_marks_settle(v_npc) is not null then
    raise exception 'PROOF 59 FAILED: a merchant''s settle did not answer null';
  end if;
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_nfl, v_npc, '[]', 1200, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
  if public.reputation_arrival(v_npc, v_voy) <> 0 then
    raise exception 'PROOF 59 FAILED: a merchant''s arrival booked something';
  end if;
  insert into public.standing_routes (player_id, name, fleet_id) values (v_npc, 'Rota 59 M', v_nfl) returning id into v_nroute;
  v_n := 0;
  for i in 1 .. 20 loop
    perform public.fleet_load(v_nfl, v_mcode, 1, 100);   -- more aboard than the lap before: every lap closes at a gain, so she goes as far into reputation_lap as a merchant can
    insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_nroute, i, now()) returning id into v_lap;
    update public.standing_routes set lap_id = v_lap, lap_no = i where id = v_nroute;
    perform cmd.standing_route_close_lap(v_nroute, now());
    if (select x.net from public.standing_route_laps x where x.id = v_lap) > 0 then v_n := v_n + 1; end if;
  end loop;
  v_w := (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables where schemaname = 'public' and relname = any (c_tabs));
  v_calls := coalesce((select sum(f.calls) from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = 'player_progress'), 0);
  if v_n <> 20 or v_w <> 0 or v_calls <> 0
     or (select count(*) from public.events e where e.player_id = v_npc and e.kind = 'ROUTE_LAP') <> 20
     or exists (select 1 from public.events e where e.player_id = v_npc and e.kind = 'LEVEL_UP') then
    raise exception 'PROOF 59 FAILED: % of 20 merchant laps closed at a gain; the merchant wrote % tuple(s) to the marks and Reputation tables and read player_progress % time(s)', v_n, v_w, v_calls;
  end if;
  -- the positive control: a human's settle is counted by the same view
  v_c := public.new_house(c_c, 'Casa do Controle 59', 'PRT');
  v_calls := coalesce((select sum(f.calls) from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = 'player_progress'), 0);
  perform public.level_marks_settle(v_c);
  v_calls := coalesce((select sum(f.calls) from pg_stat_xact_user_functions f where f.schemaname = 'public' and f.funcname = 'player_progress'), 0) - v_calls;
  if v_calls <> 1 then
    raise exception 'PROOF 59 FAILED: the control counted % player_progress read(s) for a human''s settle, not one (the merchant''s zero proves nothing)', v_calls;
  end if;
  raise notice 'PASS: LEVEL_MERCHANT_NOTHING — a merchant with the miles of level 4: her settle answered null, her arrival booked 0, her 20 real laps closed at a gain; % tuples written to house_level_marks and the Reputation tables, player_progress called 0 times (a human''s settle: % time)', v_w, v_calls;

  -- ── LEVEL_ONCE: a new house's first session, through the doors ──
  v_a := public.new_house(c_a, 'Casa do Nivel 59', 'PRT');
  perform cmd.assume_identity(c_a);
  select id into v_fleet from public.fleets where player_id = v_a;
  perform cmd.issue(v_fleet, 'PROVISION FULL');
  v_r := world.trade_routes(v_lis, v_fleet, 1700, null);
  select (e -> 'to' ->> 'id')::uuid, e -> 'to' ->> 'code', (e ->> 'good_id')::uuid, e ->> 'code', floor((e ->> 'qty')::numeric)
    into v_dest, v_dest_code, v_good, v_good_code, v_qty
    from jsonb_array_elements(v_r -> 'routes') e join public.goods g on g.code = e ->> 'code'
   where g.bulk <= 1.0 and (e ->> 'qty')::numeric >= 2 and (e ->> 'nm')::numeric >= public.wc_num('rep_nm_per_point')
   order by (e ->> 'profit')::numeric desc, e ->> 'code' limit 1;
  if v_good is null then
    raise exception 'PROOF 59 FAILED: the quay at Lisbon names no trade a starter can sail';
  end if;
  v_r := cmd.level_up();
  if (v_r ->> 'ok')::boolean is not true or jsonb_array_length(v_r -> 'levels') <> 0 or exists (select 1 from public.house_level_marks m where m.player_id = v_a) then
    raise exception 'PROOF 59 FAILED: a new house at level 1 was paid or marked: %', v_r;
  end if;
  v_r := cmd.issue(v_fleet, 'BUY ' || v_good_code || ' ' || v_qty::int);
  if not (v_r ->> 'ok')::boolean then
    raise exception 'PROOF 59 FAILED: the cargo did not go aboard: %', v_r;
  end if;
  -- the buy is turnover: the level is derived at once, and nothing is paid until the door is called (a buy is not a caller)
  v_pp := public.player_progress(v_a);
  v_t_lv := (v_pp -> 'trading' ->> 'level')::int;
  if exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP') or exists (select 1 from public.reputation_book k where k.player_id = v_a) then
    raise exception 'PROOF 59 FAILED: a buy paid a level by itself';
  end if;
  if ((world.player() -> 'player' -> 'reputation' -> 'level_marks' ->> 'trading')::int) <> 1
     or ((world.player() -> 'player' -> 'levels' -> 'trading' ->> 'level')::int) <> v_t_lv then
    raise exception 'PROOF 59 FAILED: world.player() does not serve her Trading level % over a mark of 1', v_t_lv;
  end if;
  v_r := cmd.level_up();
  v_want := v_gift * (v_t_lv * (v_t_lv + 1) / 2 - 1);   -- 10 x (2 + ... + level)
  if jsonb_array_length(v_r -> 'levels') <> v_t_lv - 1
     or coalesce((select sum(k.delta) from public.reputation_book k where k.player_id = v_a and k.kind = 'level'), 0) <> v_want
     or coalesce((select b.balance from public.reputation_balance b where b.player_id = v_a), 0) <> v_want
     or coalesce((select m.level from public.house_level_marks m where m.player_id = v_a and m.track = 'trading'), 1) <> v_t_lv then
    raise exception 'PROOF 59 FAILED: after a buy that made Trading level %, the door did not pay % for % crossing(s): %', v_t_lv, v_want, v_t_lv - 1, v_r;
  end if;
  v_first := format('the buy of %s %s made Trading level %s: +%s', v_qty, v_good_code, v_t_lv, v_want);
  select count(*) into v_ev from public.events e where e.player_id = v_a;
  select b.seq into v_seq from public.reputation_balance b where b.player_id = v_a;
  v_r := cmd.level_up();
  if jsonb_array_length(v_r -> 'levels') <> 0 or (select count(*) from public.events e where e.player_id = v_a) <> v_ev
     or coalesce((select b.seq from public.reputation_balance b where b.player_id = v_a), 0) is distinct from coalesce(v_seq, 0) then
    raise exception 'PROOF 59 FAILED: the door called again wrote something: %', v_r;
  end if;
  -- she sails; the arrival settles in the read, and the crossing her arrival made is in the same transaction as its report
  v_r := proof.sail(v_fleet, v_dest_code);
  if not (v_r ->> 'ok')::boolean then
    raise exception 'PROOF 59 FAILED: SAIL was refused: %', v_r;
  end if;
  select v.id, v.total_nm into v_voy, v_nm from public.voyages v where v.fleet_id = v_fleet and v.status = 'SAILING';
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  v_t := clock_timestamp();
  perform world.fleets();   -- the read is the catch-up: voyage.settle runs here
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  if (select f.status from public.fleets f where f.id = v_fleet) <> 'DOCKED' then
    raise exception 'PROOF 59 FAILED: she did not make %', v_dest_code;
  end if;
  v_pp := public.player_progress(v_a);
  v_e_lv := (v_pp -> 'exploration' ->> 'level')::int;
  if v_e_lv < 2
     or coalesce((select m.level from public.house_level_marks m where m.player_id = v_a and m.track = 'exploration'), 1) <> v_e_lv
     or coalesce((select sum(k.delta) from public.reputation_book k where k.player_id = v_a and k.kind = 'level' and k.key like 'level:exploration:%'), 0)
        <> v_gift * (v_e_lv * (v_e_lv + 1) / 2 - 1) then
    raise exception 'PROOF 59 FAILED: the arrival (% nm, one port) made Exploration level % and did not pay its crossing(s)', v_nm, v_e_lv;
  end if;
  v_first := v_first || format('; the arrival at %s (%s nm) made Exploration level %s: +%s, settled with the voyage in %s ms', v_dest_code, v_nm, v_e_lv, v_gift * (v_e_lv * (v_e_lv + 1) / 2 - 1), round(v_ms));
  -- the far quay: two sales. A sale does not settle (cmd.do_sell is not a caller); the door does.
  select count(*) into v_ev from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP';
  v_r  := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', floor(v_qty / 2)));
  v_r2 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', v_qty - floor(v_qty / 2)));
  if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP') <> v_ev then
    raise exception 'PROOF 59 FAILED: a sale settled a level by itself';
  end if;
  v_n := (public.player_progress(v_a) -> 'trading' ->> 'level')::int;
  v_r := cmd.level_up();
  if jsonb_array_length(v_r -> 'levels') <> v_n - v_t_lv then
    raise exception 'PROOF 59 FAILED: the sales made Trading level % from % and the door paid % crossing(s)', v_n, v_t_lv, jsonb_array_length(v_r -> 'levels');
  end if;
  v_first := v_first || format('; the sale made Trading level %s: +%s', v_n, v_gift * (v_n * (v_n + 1) / 2 - v_t_lv * (v_t_lv + 1) / 2));
  v_t_lv := v_n;
  -- ONE event and ONE book row a crossing, each of 10 x its level, and nothing else of the kind
  v_want := v_gift * ((v_t_lv * (v_t_lv + 1) / 2 - 1) + (v_e_lv * (v_e_lv + 1) / 2 - 1));
  if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP') <> (v_t_lv - 1) + (v_e_lv - 1)
     or (select count(distinct (e.payload ->> 'track') || ':' || (e.payload ->> 'level')) from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP') <> (v_t_lv - 1) + (v_e_lv - 1)
     or exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'LEVEL_UP'
                 and ((e.payload ->> 'reputation')::int <> v_gift * (e.payload ->> 'level')::int
                      or not exists (select 1 from public.reputation_book k where k.player_id = v_a and k.kind = 'level'
                                      and k.key = 'level:' || (e.payload ->> 'track') || ':' || (e.payload ->> 'level') and k.delta = (e.payload ->> 'reputation')::int)))
     or (select count(*) from public.reputation_book k where k.player_id = v_a and k.kind = 'level') <> (v_t_lv - 1) + (v_e_lv - 1)
     or (select sum(k.delta) from public.reputation_book k where k.player_id = v_a and k.kind = 'level') <> v_want
     or (select string_agg(m.track || ':' || m.level, ',' order by m.track) from public.house_level_marks m where m.player_id = v_a)
        is distinct from format('exploration:%s,trading:%s', v_e_lv, v_t_lv) then
    raise exception 'PROOF 59 FAILED: Trading % and Exploration % are not % event(s) and % book row(s) of 10 x the level, totalling %', v_t_lv, v_e_lv, (v_t_lv - 1) + (v_e_lv - 1), (v_t_lv - 1) + (v_e_lv - 1), v_want;
  end if;
  -- again, by every caller: the door, the arrival's own function, voyage.settle
  select count(*) into v_ev from public.events e where e.player_id = v_a;
  select b.seq into v_seq from public.reputation_balance b where b.player_id = v_a;
  v_r := cmd.level_up();
  perform public.reputation_arrival(v_a, v_voy);
  perform voyage.settle(v_fleet, now());
  if jsonb_array_length(v_r -> 'levels') <> 0 or (select count(*) from public.events e where e.player_id = v_a) <> v_ev
     or (select b.seq from public.reputation_balance b where b.player_id = v_a) <> v_seq then
    raise exception 'PROOF 59 FAILED: a second settle by the door, the arrival or voyage.settle wrote something';
  end if;
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  raise notice 'PASS: LEVEL_ONCE — THE FIRST SESSION of a new house (40,000 ducats, one barca): %. Level gifts in all: % Reputation for % crossing(s), each ONE event and ONE book row of 10 x its level; her whole balance after the session is % (the gifts and R1''s sale, miles and landfall). The door, the arrival and voyage.settle called again wrote nothing',
    v_first, v_want, (v_t_lv - 1) + (v_e_lv - 1), (select b.balance from public.reputation_balance b where b.player_id = v_a);

  -- ── LEVEL_STAYS_DERIVED ──
  -- a settle that pays moves no level: player_progress and world.levels() are byte-equal across it
  insert into public.events (player_id, kind, payload) values (v_a, 'VOYAGE_REPORT', jsonb_build_object('to', 'P59', 'total_nm', v_nm4 * 4));
  v_pp := public.player_progress(v_a);
  v_lv := world.levels()::text;
  v_r := cmd.level_up();
  v_pp2 := public.player_progress(v_a);
  if jsonb_array_length(v_r -> 'levels') < 1 or v_pp2::text <> v_pp::text or world.levels()::text <> v_lv then
    raise exception 'PROOF 59 FAILED: a settle that paid % crossing(s) moved her derived levels', jsonb_array_length(v_r -> 'levels');
  end if;
  -- a mark moved by hand moves no level either: nothing reads a level from it
  update public.house_level_marks set level = 19 where player_id = v_a and track = 'trading';
  if public.player_progress(v_a)::text <> v_pp::text or world.levels()::text <> v_lv
     or (world.player() -> 'player' -> 'levels')::text <> v_pp::text
     or (world.player() -> 'player' -> 'reputation' -> 'level_marks' ->> 'trading')::int <> 19 then
    raise exception 'PROOF 59 FAILED: a mark moved by hand moved a level, or the card does not serve the mark';
  end if;
  update public.house_level_marks set level = v_t_lv where player_id = v_a and track = 'trading';
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) into v_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind in ('f', 'p') and p.prosrc like '%house_level_marks%';
  if v_names is distinct from 'public.level_marks_settle,public.reputation_card' then
    raise exception 'PROOF 59 FAILED: the marks table is named by: %', v_names;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'cmd' and p.proname like 'do\_sell%' and (p.prosrc like '%level_marks_settle%' or p.prosrc like '%player_progress%')) then
    raise exception 'PROOF 59 FAILED: a sale names the level settle or player_progress';
  end if;
  raise notice 'PASS: LEVEL_STAYS_DERIVED — a settle that paid % crossing(s) left player_progress and world.levels() byte-equal; a mark set to 19 by hand moved no level; the marks table is named by % alone; no cmd.do_sell body names the settle or player_progress',
    jsonb_array_length(v_r -> 'levels'), v_names;

  -- ── LEVEL_NO_BACKPAY ──
  v_b := public.new_house(c_b, 'Casa Antiga 59', 'PRT');
  select id into v_bfl from public.fleets where player_id = v_b;
  insert into public.events (player_id, kind, payload) values (v_b, 'VOYAGE_REPORT', jsonb_build_object('to', 'P59', 'total_nm', v_nm4));   -- a history: Exploration level 4
  -- the seed, as the migration writes it: every track at the level player_progress reads now
  v_pp := public.player_progress(v_b);
  insert into public.house_level_marks (player_id, track, level)
  select v_b, x.track, greatest((v_pp -> x.track ->> 'level')::int, 1) from unnest(array['trading', 'exploration', 'combat']) x(track);
  perform cmd.assume_identity(c_b);
  v_r := cmd.level_up();
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_bfl, v_b, '[]', 50, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, null);
  v_n := public.reputation_arrival(v_b, v_voy);
  if (v_pp -> 'exploration' ->> 'level')::int <> 4 or jsonb_array_length(v_r -> 'levels') <> 0 or v_n <> 0
     or exists (select 1 from public.events e where e.player_id = v_b and e.kind = 'LEVEL_UP')
     or exists (select 1 from public.reputation_book k where k.player_id = v_b) then
    raise exception 'PROOF 59 FAILED: a house seeded at Exploration level 4 was paid back: %', v_r;
  end if;
  -- her next crossing pays level 5 alone
  insert into public.events (player_id, kind, payload) values (v_b, 'VOYAGE_REPORT', jsonb_build_object('to', 'Q59', 'total_nm', v_nm4));
  v_n := (public.player_progress(v_b) -> 'exploration' ->> 'level')::int;
  v_r := cmd.level_up();
  if v_n <> 5 or (v_r -> 'levels') is distinct from jsonb_build_array(jsonb_build_object('track', 'exploration', 'level', 5, 'reputation', v_gift * 5))
     or (select b.balance from public.reputation_balance b where b.player_id = v_b) <> v_gift * 5 then
    raise exception 'PROOF 59 FAILED: the crossing after the seed (level %) did not pay level 5 alone: %', v_n, v_r;
  end if;
  raise notice 'PASS: LEVEL_NO_BACKPAY — a house at Exploration level 4 with her marks seeded: the door and an arrival paid 0 and fired no event; her next crossing paid level 5 alone (+%)', v_gift * 5;

  -- ── LEVEL_COMBAT_PLAYABLE ──
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_bfl, v_b, '[]', 1, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
  insert into public.voyage_events (voyage_id, day_index, kind, payload)
  select v_voy, g, 'PIRATES', jsonb_build_object('outcome', 'DRIVEN_OFF') from generate_series(1, 4) g;
  insert into public.events (player_id, kind, payload) values (v_b, 'VOYAGE_REPORT', jsonb_build_object('to', 'P59', 'total_nm', 0, 'voyage_id', v_voy));
  v_r := cmd.level_up();
  if (public.player_progress(v_b) -> 'combat' ->> 'playable')::boolean or jsonb_array_length(v_r -> 'levels') <> 0
     or (select m.level from public.house_level_marks m where m.player_id = v_b and m.track = 'combat') <> 1
     or exists (select 1 from public.events e where e.player_id = v_b and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'combat') then
    raise exception 'PROOF 59 FAILED: combat is not playable and was settled: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
  v_n := (public.player_progress(v_b) -> 'combat' ->> 'level')::int;
  v_r := cmd.level_up();
  v_r2 := cmd.level_up();
  if v_n < 2 or jsonb_array_length(v_r -> 'levels') <> v_n - 1 or jsonb_array_length(v_r2 -> 'levels') <> 0
     or exists (select 1 from jsonb_array_elements(v_r -> 'levels') x where x ->> 'track' <> 'combat' or (x ->> 'reputation')::int <> v_gift * (x ->> 'level')::int)
     or (select m.level from public.house_level_marks m where m.player_id = v_b and m.track = 'combat') <> v_n then
    raise exception 'PROOF 59 FAILED: combat lit at level % and its crossings were not each paid once: %', v_n, v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  raise notice 'PASS: LEVEL_COMBAT_PLAYABLE — four raiders driven off: while combat is not playable, no mark moved and no event fired; lit, Combat level % paid its % crossing(s) once each', v_n, v_n - 1;

  -- ── LEVEL_SWITCHES ──
  update public.world_config set value = 'false'::jsonb where key = 'reputation_on';
  insert into public.events (player_id, kind, payload) values (v_b, 'VOYAGE_REPORT', jsonb_build_object('to', 'R59', 'total_nm', v_nm4 * 2));
  v_n := (public.player_progress(v_b) -> 'exploration' ->> 'level')::int;
  select count(*) into v_ev from public.events e where e.player_id = v_b and e.kind = 'LEVEL_UP';
  select b.seq into v_seq from public.reputation_balance b where b.player_id = v_b;
  v_r := cmd.level_up();
  if v_n < 6 or jsonb_array_length(v_r -> 'levels') <> 0
     or (select count(*) from public.events e where e.player_id = v_b and e.kind = 'LEVEL_UP') <> v_ev
     or (select b.seq from public.reputation_balance b where b.player_id = v_b) <> v_seq
     or (select m.level from public.house_level_marks m where m.player_id = v_b and m.track = 'exploration') <> 5 then
    raise exception 'PROOF 59 FAILED: with reputation_on false the settle wrote something: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
  v_r := cmd.level_up();
  if jsonb_array_length(v_r -> 'levels') <> v_n - 5
     or (select b.balance from public.reputation_balance b where b.player_id = v_b)
        <> (select sum(k.delta) from public.reputation_book k where k.player_id = v_b)
     or (select m.level from public.house_level_marks m where m.player_id = v_b and m.track = 'exploration') <> v_n then
    raise exception 'PROOF 59 FAILED: lit again, the crossings made in the dark were not paid: %', v_r;
  end if;
  v_m := v_n;
  update public.world_config set value = to_jsonb(0) where key = 'rep_level_per_level';
  insert into public.events (player_id, kind, payload) values (v_b, 'VOYAGE_REPORT', jsonb_build_object('to', 'S59', 'total_nm', v_nm4 * 3));
  v_n := (public.player_progress(v_b) -> 'exploration' ->> 'level')::int;
  select b.seq into v_seq from public.reputation_balance b where b.player_id = v_b;
  v_r := cmd.level_up();
  if v_n <= v_m or jsonb_array_length(v_r -> 'levels') <> v_n - v_m
     or exists (select 1 from jsonb_array_elements(v_r -> 'levels') x where (x ->> 'reputation')::int <> 0)
     or (select b.seq from public.reputation_balance b where b.player_id = v_b) <> v_seq
     or (select count(*) from public.events e where e.player_id = v_b and e.kind = 'LEVEL_UP' and (e.payload ->> 'reputation')::int = 0) <> v_n - v_m
     or (select m.level from public.house_level_marks m where m.player_id = v_b and m.track = 'exploration') <> v_n
     or (world.player() -> 'player' -> 'reputation' ->> 'level_gift')::int <> 0 then
    raise exception 'PROOF 59 FAILED: with the gift at 0 a crossing booked something or did not fire: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(10) where key = 'rep_level_per_level';
  raise notice 'PASS: LEVEL_SWITCHES — reputation_on false: % crossing(s) wrote nothing, and were paid when it was lit again; rep_level_per_level 0: % crossing(s) fired LEVEL_UP with reputation 0 and no book row, and the card served a gift of 0',
    v_m - 5, v_n - v_m;

  -- ── LEVEL_LAP: real laps of a human's route ──
  if public.fleet_load(v_bfl, v_mcode, 5, 100) <> 5 then
    raise exception 'PROOF 59 FAILED: the probe''s cargo did not go aboard';
  end if;
  insert into public.standing_routes (player_id, name, fleet_id) values (v_b, 'Rota 59', v_bfl) returning id into v_route;
  select b.seq, b.day_earned into v_seq, v_m from public.reputation_balance b where b.player_id = v_b;
  insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 1, now()) returning id into v_lap;
  update public.standing_routes set lap_id = v_lap, lap_no = 1 where id = v_route;
  perform cmd.standing_route_close_lap(v_route, now());
  v_n := public.reputation_lap(v_b, v_lap, 500, 'Rota 59', 1);   -- the same lap again
  if (select x.net from public.standing_route_laps x where x.id = v_lap) <= 0 or v_n <> 0
     or (select b.seq from public.reputation_balance b where b.player_id = v_b) <> v_seq + 1
     or (select b.day_earned from public.reputation_balance b where b.player_id = v_b) <> (case when (select b.day from public.reputation_balance b where b.player_id = v_b) = public.real_day(now()) then v_m else 0 end) + v_lap_pay
     or (select k.kind || ':' || k.delta || ':' || k.key from public.reputation_book k where k.player_id = v_b and k.seq = v_seq + 1)
        is distinct from 'lap:' || v_lap_pay || ':lap:' || v_lap then
    raise exception 'PROOF 59 FAILED: a real lap closed at a gain of % did not pay % once, inside the day''s cap', (select x.net from public.standing_route_laps x where x.id = v_lap), v_lap_pay;
  end if;
  v_w := (select x.net from public.standing_route_laps x where x.id = v_lap);
  update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_bfl;   -- the cargo is gone: the next lap closes at a loss
  insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 2, now()) returning id into v_lap;
  update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_route;
  perform cmd.standing_route_close_lap(v_route, now());
  if (select x.net from public.standing_route_laps x where x.id = v_lap) >= 0
     or (select b.seq from public.reputation_balance b where b.player_id = v_b) <> v_seq + 1
     or exists (select 1 from public.reputation_book k where k.player_id = v_b and k.key = 'lap:' || v_lap) then
    raise exception 'PROOF 59 FAILED: a real lap closed at a loss (%) paid', (select x.net from public.standing_route_laps x where x.id = v_lap);
  end if;
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  raise notice 'PASS: LEVEL_LAP — a real lap closed at a gain of % paid % once (key lap:<lap id>, counted in today''s capped earnings) and the same lap again paid 0; a real lap closed at a loss of % paid nothing',
    v_w, v_lap_pay, (select x.net from public.standing_route_laps x where x.id = v_lap);
end
$p$;
