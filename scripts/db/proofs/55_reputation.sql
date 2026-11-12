-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 55 — EVERY SUCCESS EARNS REPUTATION  (migration 0352, slice R1 of docs/REPUTATION.md, owner row 317)
--
--   The migration's self-assert proves the arithmetic on stubs. This proof plays the doors: fifty real merchant sales,
--   a real first voyage through cmd.issue and voyage.settle, real sales at the far quay. Every figure is held to the
--   rule worked out here from the knobs and from what the door itself answered (the amount, not "more than nothing").
--   Everything rolls back with proof.mjs's transaction. The one knob set here (hazard_p_max 0, as proof 04: a hazard
--   that strands the fleet is the halt rule working, and not what this file is about) goes back with it.
--
-- @pass REP_MERCHANT_NOTHING  fifty real merchant sales at a gain through cmd.do_sell write no tuple to the three Reputation tables (pg_stat_xact_user_tables, asked first in this transaction)
-- @pass REP_NOT_GOLD          a credit and a sale's points move no purse, no ledger row, no stats_live figure and write no event; the balance is the only thing that moved
-- @pass REP_CHAIN             credits are rows 1..n and the balance is the last row's; a wrong row, an update and a delete are refused; a balance moved without a row fails the deferred check
-- @pass REP_CAP               at 590 of the day's 600 a 28 books 10; the next books 0 and writes no row; a kind outside the cap still books
-- @pass REP_ARRIVAL           a new house's first real voyage settles through the read: her miles (1 a 100 nm) and a first landfall of 25, by key; world.player() serves the balance; a starter barca's real speed is printed
-- @pass REP_ONCE              the same arrival settled again books nothing; a second voyage to the same port earns its miles and no second landfall
-- @pass REP_SALE_GAIN_ONLY    a real sale at a gain books floor(profit / 250); a real sale at a loss and one of unknown cost book nothing and write no row
-- @pass REP_CARRY             a lot sold in two halves earns what the sum of the two profits earns, to the point, and carries the remainder
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_h     constant uuid := '00000000-0355-4000-8000-000000000001';
  c_a     constant uuid := '00000000-0355-4000-8000-000000000002';
  c_tabs  constant text[] := array['reputation_kinds', 'reputation_balance', 'reputation_book'];
  v_per   constant numeric := public.wc_num('rep_profit_per_point');
  v_npc   uuid;
  v_nfl   uuid;
  v_h     uuid;
  v_a     uuid;
  v_fleet uuid;
  v_lis   uuid;
  v_dest  uuid;
  v_dest_code text;
  v_good  uuid;
  v_good_code text;
  v_mgood uuid;
  v_mcode text;
  v_qty   numeric;
  v_voy   uuid;
  v_nm    numeric;
  v_min   numeric;
  v_w     bigint;
  v_n     int;
  v_m     int;
  v_ok    boolean;
  v_r     jsonb;
  v_r2    jsonb;
  v_b     record;
  v_gold  text;
  v_live  text;
  v_ev    bigint;
  v_led   bigint;
  v_t     timestamptz;
  v_ms    numeric;
  v_miles int;
  v_fight int;
  v_arr   int;
  v_p1    numeric;
  v_p2    numeric;
  v_sale  int;
  v_before int;
  v_carry numeric;
  v_today int := public.real_day(now());
begin
  select id into v_lis from public.ports where code = 'LIS';

  -- ── REP_MERCHANT_NOTHING: first, before anything of a player's is written in this transaction ──
  v_npc := public.new_house(null, 'Casa Mercante 55', 'PRT', p_ducats => 20000, p_is_npc => true);
  select id into v_nfl from public.fleets where player_id = v_npc;
  select g.id, g.code into v_mgood, v_mcode
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  v_n := 0;
  for i in 1 .. 50 loop
    perform public.fleet_load(v_nfl, v_mcode, 10, 1);   -- cost 1 a tun: every sale is at a gain, so the merchant goes as far into reputation_sale as a merchant can
    delete from public.trade_daily td where td.player_id = v_npc;
    v_r := cmd.do_sell(v_nfl, jsonb_build_object('good', v_mgood, 'qty', 10));
    if (v_r ->> 'profit')::numeric > 0 then v_n := v_n + 1; end if;
  end loop;
  v_w := (select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) from pg_stat_xact_user_tables where schemaname = 'public' and relname = any (c_tabs));
  if v_n <> 50 or v_w <> 0 or exists (select 1 from public.reputation_balance where player_id = v_npc) then
    raise exception 'PROOF 55 FAILED: % of 50 merchant sales were at a gain and they wrote % tuple(s) to the Reputation tables', v_n, v_w;
  end if;
  raise notice 'PASS: REP_MERCHANT_NOTHING — 50 real merchant sales of % at a gain wrote % tuples to reputation_kinds, reputation_balance and reputation_book', v_mcode, v_w;

  -- ── REP_NOT_GOLD ──
  v_h := public.new_house(c_h, 'Casa da Fama 55', 'PRT');
  select md5(p.ducats::text || ':' || p.version::text) into v_gold from public.players p where p.id = v_h;
  select md5(coalesce(string_agg(to_jsonb(s)::text, ',' order by to_jsonb(s)::text), '')) into v_live from public.stats_live s;
  select count(*) into v_ev from public.events e where e.player_id = v_h;
  select count(*) into v_led from public.ledger l where l.player_id = v_h;
  v_n := public.reputation_credit(v_h, 'landfall', 25, 'probe:55');
  v_m := public.reputation_sale(v_h, 7200, '{}');
  if v_n <> 25 or v_m <> 28 or (select balance from public.reputation_balance where player_id = v_h) <> 53 then
    raise exception 'PROOF 55 FAILED: a landfall and 7,200 of profit did not book 25 and 28 (% and %)', v_n, v_m;
  end if;
  if (select md5(p.ducats::text || ':' || p.version::text) from public.players p where p.id = v_h) <> v_gold
     or (select md5(coalesce(string_agg(to_jsonb(s)::text, ',' order by to_jsonb(s)::text), '')) from public.stats_live s) <> v_live
     or (select count(*) from public.events e where e.player_id = v_h) <> v_ev
     or (select count(*) from public.ledger l where l.player_id = v_h) <> v_led then
    raise exception 'PROOF 55 FAILED: booking Reputation moved a purse, a ledger row, a live figure or wrote an event';
  end if;
  raise notice 'PASS: REP_NOT_GOLD — 53 Reputation booked; her purse, her % ledger rows, stats_live and her % events are as they were', v_led, v_ev;

  -- ── REP_CHAIN ──
  v_n := public.reputation_credit(v_h, 'built', 100, 'built:probe55');
  select * into v_b from public.reputation_balance where player_id = v_h;
  if v_b.seq <> 3 or v_b.balance <> 153
     or (select string_agg(k.seq || ':' || k.kind || ':' || k.delta || ':' || k.balance_after, ',' order by k.seq) from public.reputation_book k where k.player_id = v_h)
        <> '1:landfall:25:25,2:sale:28:53,3:built:100:153' then
    raise exception 'PROOF 55 FAILED: the book is not a chain of three rows ending at the balance';
  end if;
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  v_m := 0;
  begin
    insert into public.reputation_book (player_id, seq, kind, delta, balance_after) values (v_h, 4, 'built', 1, 999);
  exception when sqlstate '23514' then v_m := v_m + 1;
  end;
  begin
    update public.reputation_book set delta = 1 where player_id = v_h and seq = 1;
  exception when sqlstate '42501' then v_m := v_m + 1;
  end;
  begin
    delete from public.reputation_book where player_id = v_h and seq = 3;
  exception when sqlstate '42501' then v_m := v_m + 1;
  end;
  begin
    update public.reputation_balance set balance = balance + 1000 where player_id = v_h;
    set constraints public.reputation_reconciles immediate;
  exception when sqlstate '23514' then v_m := v_m + 1;
  end;
  set constraints public.reputation_reconciles deferred;
  if v_m <> 4 or (select balance from public.reputation_balance where player_id = v_h) <> 153 then
    raise exception 'PROOF 55 FAILED: % of 4 forgeries were refused (a wrong row, an update, a delete, a balance with no row)', v_m;
  end if;
  raise notice 'PASS: REP_CHAIN — rows 1..3 end at the balance (153); a wrong row, an update, a delete and a balance moved with no row were refused (4 of 4)';

  -- ── REP_CAP ──
  update public.reputation_balance set day = v_today, day_earned = 590, carry = 0 where player_id = v_h;
  v_n := public.reputation_sale(v_h, 7000, '{}');
  v_before := (select seq from public.reputation_balance where player_id = v_h);
  v_m := public.reputation_sale(v_h, 7000, '{}');
  if v_n <> 10 or v_m <> 0 or (select seq from public.reputation_balance where player_id = v_h) <> v_before
     or (select day_earned from public.reputation_balance where player_id = v_h) <> public.wc_int('rep_day_cap') then
    raise exception 'PROOF 55 FAILED: at 590 of 600 a 28 booked %, and the next booked % (wanted 10 and 0, and no row)', v_n, v_m;
  end if;
  v_n := public.reputation_credit(v_h, 'landfall', 25, 'probe:55b');
  if v_n <> 25 then
    raise exception 'PROOF 55 FAILED: a kind outside the cap was stopped by it';
  end if;
  raise notice 'PASS: REP_CAP — at 590 of % a 28 booked 10; the next booked 0 and the book stayed at row %; a landfall still booked 25', public.wc_int('rep_day_cap'), v_before;

  -- ── REP_ARRIVAL: a new house's first voyage, through the doors ──
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  v_a := public.new_house(c_a, 'Casa da Viagem 55', 'PRT');
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
    raise exception 'PROOF 55 FAILED: the quay at Lisbon names no trade a starter can sail';
  end if;
  v_qty := v_qty - (v_qty % 2);   -- two equal halves at the far quay
  v_r := cmd.issue(v_fleet, 'BUY ' || v_good_code || ' ' || v_qty::int);
  if not (v_r ->> 'ok')::boolean then
    raise exception 'PROOF 55 FAILED: the cargo did not go aboard: %', v_r;
  end if;
  v_r := proof.sail(v_fleet, v_dest_code);
  if not (v_r ->> 'ok')::boolean then
    raise exception 'PROOF 55 FAILED: SAIL was refused: %', v_r;
  end if;
  select v.id, v.total_nm, extract(epoch from (v.eta - v.departed_at)) / 60 into v_voy, v_nm, v_min
    from public.voyages v where v.fleet_id = v_fleet and v.status = 'SAILING';
  if exists (select 1 from public.reputation_book k where k.player_id = v_a) then
    raise exception 'PROOF 55 FAILED: a buy or a departure earned Reputation';
  end if;
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  v_t := clock_timestamp();
  perform world.fleets();   -- the read is the catch-up: voyage.settle runs here
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  if (select f.status from public.fleets f where f.id = v_fleet) <> 'DOCKED' or (select f.port_id from public.fleets f where f.id = v_fleet) <> v_dest then
    raise exception 'PROOF 55 FAILED: she did not make %', v_dest_code;
  end if;
  v_miles := least(floor(v_nm / public.wc_num('rep_nm_per_point')), public.wc_int('rep_miles_max'))::int;
  v_fight := floor((select x.combat from public.voyage_xp_tracks(v_voy) x) * public.wc_num('rep_per_fight_point'))::int;
  v_arr := v_miles + v_fight + public.wc_int('rep_landfall');
  select * into v_b from public.reputation_balance where player_id = v_a;
  if v_b.balance <> v_arr or v_b.day_earned <> v_miles + v_fight
     or coalesce((select k.delta from public.reputation_book k where k.player_id = v_a and k.key = 'miles:' || v_voy), 0) <> v_miles
     or coalesce((select k.delta from public.reputation_book k where k.player_id = v_a and k.key = 'landfall:' || v_dest_code), 0) <> public.wc_int('rep_landfall')
     or coalesce((select k.delta from public.reputation_book k where k.player_id = v_a and k.key = 'pirates:' || v_voy), 0) <> v_fight
     or exists (select 1 from public.events e where e.player_id = v_a and e.kind ilike '%REPUTATION%') then
    raise exception 'PROOF 55 FAILED: % nm to % should book % miles, % for pirates and a landfall of %: the balance is %', v_nm, v_dest_code, v_miles, v_fight, public.wc_int('rep_landfall'), v_b.balance;
  end if;
  v_r2 := world.player() -> 'player' -> 'reputation';
  if (v_r2 ->> 'balance')::int <> v_arr or (v_r2 ->> 'today')::int <> v_miles + v_fight or (v_r2 ->> 'cap')::int <> public.wc_int('rep_day_cap')
     or (v_r2 ->> 'seq')::int <> v_b.seq or jsonb_array_length(v_r2 -> 'recent') <> v_b.seq or (v_r2 -> 'recent' -> 0 ->> 'seq')::int <> v_b.seq then
    raise exception 'PROOF 55 FAILED: world.player() does not serve her Reputation: %', v_r2;
  end if;
  raise notice 'PASS: REP_ARRIVAL — % nm from Lisbon to % in a starter barca: % real minutes laden (% nm a real minute). The arrival, settled by the read in % ms, booked % for her miles, % for pirates and % for the first landfall = %; world.player() serves it',
    v_nm, v_dest_code, round(v_min, 2), round(v_nm / v_min), round(v_ms), v_miles, v_fight, public.wc_int('rep_landfall'), v_arr;

  -- ── REP_ONCE ──
  v_n := public.reputation_arrival(v_a, v_voy);
  perform voyage.settle(v_fleet, now());
  if v_n <> 0 or (select balance from public.reputation_balance where player_id = v_a) <> v_arr then
    raise exception 'PROOF 55 FAILED: the same arrival booked twice';
  end if;
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_fleet, v_a, '[]', 250, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_dest);
  v_n := public.reputation_arrival(v_a, v_voy);
  if v_n <> 2 or (select count(*) from public.reputation_book k where k.player_id = v_a and k.kind = 'landfall') <> 1 then
    raise exception 'PROOF 55 FAILED: a second voyage of 250 nm to % booked % (wanted 2 for its miles and no second landfall)', v_dest_code, v_n;
  end if;
  raise notice 'PASS: REP_ONCE — the arrival settled again booked 0; a second voyage of 250 nm to % booked 2 for its miles and no second landfall', v_dest_code;

  -- ── REP_CARRY and REP_SALE_GAIN_ONLY: real sales at the far quay ──
  select balance, carry into v_before, v_carry from public.reputation_balance where player_id = v_a;
  v_r  := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', v_qty / 2));
  v_n  := (select balance from public.reputation_balance where player_id = v_a) - v_before;
  v_r2 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', v_qty / 2));
  v_m  := (select balance from public.reputation_balance where player_id = v_a) - v_before - v_n;
  v_p1 := greatest(coalesce((v_r ->> 'profit')::numeric, 0), 0);
  v_p2 := greatest(coalesce((v_r2 ->> 'profit')::numeric, 0), 0);
  if (v_r ->> 'qty')::numeric <> v_qty / 2 or (v_r2 ->> 'qty')::numeric <> v_qty / 2 then
    raise exception 'PROOF 55 FAILED: the far quay did not take the two halves whole (% and % of %)', v_r ->> 'qty', v_r2 ->> 'qty', v_qty / 2;
  end if;
  if v_n <> least(floor((v_carry + v_p1) / v_per), public.wc_int('rep_sale_max'))
     or v_n + v_m <> floor((v_carry + v_p1 + v_p2) / v_per)
     or (select carry from public.reputation_balance where player_id = v_a) <> (v_carry + v_p1 + v_p2) - floor((v_carry + v_p1 + v_p2) / v_per) * v_per then
    raise exception 'PROOF 55 FAILED: two halves with profits % and % booked % and % (wanted % in all, the remainder carried)', v_p1, v_p2, v_n, v_m, floor((v_carry + v_p1 + v_p2) / v_per);
  end if;
  v_sale := v_n + v_m;
  raise notice 'PASS: REP_CARRY — % tuns of % sold at % in two halves, profits % and %: % + % = % Reputation, what their sum earns, and % carried. THE FIRST SESSION (the design worked 28 + 12 + 25 = 65 from 7,200 of profit over 1,200 nm): this house earned % for the sale + % for % nm + % for the landfall + % for pirates = % Reputation',
    v_qty, v_good_code, v_dest_code, v_p1, v_p2, v_n, v_m, v_sale, (select carry from public.reputation_balance where player_id = v_a),
    v_sale, v_miles, v_nm, public.wc_int('rep_landfall'), v_fight, v_sale + v_arr;

  -- a gain books; a loss and an unknown cost book nothing and write no row
  delete from public.trade_daily td where td.player_id = v_a;
  perform public.fleet_load(v_fleet, v_good_code, 1, 1);
  select balance, seq, carry into v_b from public.reputation_balance where player_id = v_a;
  v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 1));
  v_n := (select balance from public.reputation_balance where player_id = v_a) - v_b.balance;
  if (v_r ->> 'profit')::numeric <= 0 or v_n <> floor((v_b.carry + (v_r ->> 'profit')::numeric) / v_per) then
    raise exception 'PROOF 55 FAILED: a sale at a gain of % (carried %) booked %', v_r ->> 'profit', v_b.carry, v_n;
  end if;
  v_p1 := (v_r ->> 'profit')::numeric;
  perform public.fleet_load(v_fleet, v_good_code, 1, 100000000);
  select balance, seq, carry into v_b from public.reputation_balance where player_id = v_a;
  v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 1));
  perform public.fleet_load(v_fleet, v_good_code, 1, null);
  v_r2 := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 1));
  if (v_r ->> 'profit')::numeric >= 0 or (v_r2 ->> 'profit') is not null
     or (select md5(balance::text || ':' || seq::text || ':' || carry::text) from public.reputation_balance where player_id = v_a) <> md5(v_b.balance::text || ':' || v_b.seq::text || ':' || v_b.carry::text) then
    raise exception 'PROOF 55 FAILED: a sale at a loss (%) or of unknown cost (%) moved her Reputation', v_r ->> 'profit', v_r2 ->> 'profit';
  end if;
  raise notice 'PASS: REP_SALE_GAIN_ONLY — a real sale at a gain of % booked %; a real sale at a loss of % and one of unknown cost booked nothing and wrote no row', v_p1, v_n, v_r ->> 'profit';
end
$p$;
