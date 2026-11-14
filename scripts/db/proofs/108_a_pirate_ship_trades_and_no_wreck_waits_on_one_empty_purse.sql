-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 108 - A PIRATE SHIP TRADES; THE PIRATE CITIES FUND AN EMPTY PURSE; NO WRECK WAITS ON ONE EMPTY PURSE  (migration 0415; docs/dev-log/2026-11-14-pirate-trade.md)
--
--   Lit as prod is (purses, the closed economy, the pirates, the refit rule), through the pirates' own job and the merchants' refit job, rolled back with proof.mjs's transaction.
--   A pirate ship's arrival is set by hand (her voyage ended, she docked where she was bound): the proof is of what she does in port, not of the passage.
--
-- @pass PT_GIFT     the house of a pirate ship with an empty purse is given her capital (half her hulls' build cost) by her HOME city when it can, else by ANOTHER pirate city, else by the HOARD; whole, moved (the world total unchanged), written to the day's spend; she is not on the merchants' hourly roster
-- @pass PT_WEEK     the gift's own cooldown and weekly limit hold for her (none inside gift_cooldown_hours; gift_max_per_week in seven days and no more); a gift never takes the room the rest of the day's pay needs: short of it she waits and nothing is written
-- @pass PT_PLAN     her trading side cannot PLAN a sale the sink cannot pay for: bound for a harbour with no purse she plans and buys nothing; with a short purse every plan is within it; with a rich one within what her house holds above the gift's broke line (so buying never makes her broke, and a house at the line buys nothing)
-- @pass PT_DOOR     nor MAKE one: a cargo bought for a harbour whose purse then runs short is sold only as far as that purse pays (it never goes below nothing) and the rest stays aboard; no sale of hers is below what the goods cost her
-- @pass PT_DAY      over a simulated day (home, haunt, home, haunt; six fleets of two hubs) the fleets that trade end with more (purse plus cargo at cost) than the same fleets with trading off, every one of them at no loss; the world total does not move
-- @pass PT_JOB      through the pirates' own job: a run steps no more ships after one that traded (her market rows and her harbour's purse are held to the commit) and leaves the pay and the gift to a later minute; a run with no trade pays and gifts
-- @pass PT_REFIT_M  a MERCHANT wrecked with her home's purse empty is mended by the hourly job, paid for by another city of her country; with every city of her country dry she is not mended unpaid and not silent (a row in npc_refit_waits, a REFIT_WAITING event); a purse back, the job mends her
-- @pass PT_REFIT_N  a NAVY ship wrecked with her station's purse empty is mended the same way, her realm's capital paying
-- ═══════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_108() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;
-- a pirate ship's worth: her house's purse and her hold at what it cost
create function pg_temp.worth_108(p_fleets uuid[]) returns numeric language sql as $f$
  select (select coalesce(sum(pl.ducats), 0) from public.players pl where pl.id in (select n.player_id from public.pirate_ships n where n.fleet_id = any (p_fleets)))::numeric
       + (select coalesce(sum(public.fleet_stock_at_cost(x)), 0) from unnest(p_fleets) x)::numeric
$f$;
-- she arrives: the voyage her step began is ended and she lies docked where she was bound
create function pg_temp.arrive_108(p_fleet uuid) returns void language plpgsql as $f$
declare
  v_to uuid;
begin
  select v.dest_port_id into v_to from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' order by v.departed_at desc limit 1;
  if v_to is null then
    return;
  end if;
  update public.voyages set status = 'ABORTED' where fleet_id = p_fleet and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_to, lat = null, lon = null, ready_at = null where id = p_fleet;
end
$f$;
-- one simulated day of the proof's fleets: every hour each takes her step and, if she sailed, arrives. Answers what they are worth after it, less before.
create function pg_temp.day_108(p_fleets uuid[], p_from timestamptz) returns numeric language plpgsql as $f$
declare
  v_w0 numeric := pg_temp.worth_108(p_fleets);
  i    int;
  x    uuid;
begin
  for i in 0 .. 25 loop
    foreach x in array p_fleets loop
      if public.pirate_ship_step(x, p_from + make_interval(hours => i)) = 'SAILED' then
        perform pg_temp.arrive_108(x);
        perform public.pirate_ship_step(x, p_from + make_interval(hours => i, mins => 1));   -- she is at her haunt (her haunt clock starts) or at home
      end if;
    end loop;
  end loop;
  return pg_temp.worth_108(p_fleets) - v_w0;
end
$f$;

do $p$
declare
  v_now    timestamptz := date_trunc('day', now()) + interval '1 day 1 hour';   -- early in a UTC day no spend has reached
  v_pir    uuid := public.pirate_nation();
  v_cap    uuid := public.pirate_capital();
  v_hub    uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_hub2   uuid := (select p.id from public.ports p where p.code = 'FLO');
  v_city   uuid := (select p.id from public.ports p where p.code = 'DJE');
  v_fl     uuid[] := '{}';
  v_f      uuid;
  v_f1     uuid;
  v_f4     uuid;
  v_f6     uuid;
  v_h1     uuid;
  v_h4     uuid;
  v_h6     uuid;
  v_haunt  uuid;
  v_w0     numeric;
  v_b0     bigint;
  v_b1     bigint;
  v_s0     bigint;
  v_n      int;
  v_r      jsonb;
  v_plan   jsonb;
  v_ctl    numeric;
  v_net    numeric;
  v_min    numeric;
  v_s      text;
  r        record;
  v_m      uuid;
  v_home   uuid;
  v_nat    uuid;
  v_capm   uuid;
  v_third  uuid;
  v_navy   uuid;
  v_stn    uuid;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'pirates_bite', 'npc_refits_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
  if not public.pirates_on() or not public.npc_refits_on() or not public.economy_closed() or public.wc('pirates_trade') <> 'true'::jsonb then
    raise exception 'PROOF 108 FAIL: the pirates, the refit rule or the closed economy could not be lit in this world';
  end if;
  update public.port_treasury t set ducats = 2000000;                                            -- every city can pay for a cargo
  update public.port_treasury t set ducats = 0 where t.port_id in (select port_id from public.pirate_hubs);   -- the hubs as 0409 founds them
  update public.port_treasury t set ducats = 900000000 where t.port_id = v_cap;
  update public.pirate_ships set laid_up_at = v_now where laid_up_at is null;                    -- the proof's own fleets only are at work
  for r in select q.ord from public.pirate_roster q where q.hub_port in (v_hub, v_hub2) and q.ord % 1000 in (1, 4, 6) order by q.ord loop
    v_f := public.pirate_commission_fleet(r.ord, public.refit_yard((select q.hub_port from public.pirate_roster q where q.ord = r.ord)), v_now);
    if v_f is null then
      raise exception 'PROOF 108 FAIL: roster fleet % was not built', r.ord;
    end if;
    v_fl := v_fl || v_f;
  end loop;
  select n.fleet_id, n.player_id into v_f1, v_h1 from public.pirate_ships n where n.home_port = v_hub and n.ord % 1000 = 1;   -- a lone brigantin
  select n.fleet_id, n.player_id into v_f4, v_h4 from public.pirate_ships n where n.home_port = v_hub and n.ord % 1000 = 4;   -- a lone xebec
  select n.fleet_id, n.player_id into v_f6, v_h6 from public.pirate_ships n where n.home_port = v_hub and n.ord % 1000 = 6;   -- a squadron of four
  if public.pirate_house_capital(v_h1) <> 40000 or public.pirate_house_capital(v_h4) <> 80000 or public.pirate_house_capital(v_h6) <> 708000 then
    raise exception 'PROOF 108 FAIL: the capitals are %, %, %, not half the hulls'' build cost (40,000 / 80,000 / 708,000)',
      public.pirate_house_capital(v_h1), public.pirate_house_capital(v_h4), public.pirate_house_capital(v_h6);
  end if;

  -- ── PT_GIFT ── her home holds 100,000 (pays the brigantin's 40,000, then is short of the xebec's 80,000); Djerba is the richest other pirate city; nobody but the hoard holds the squadron's 708,000
  update public.port_treasury t set ducats = 0 where t.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = v_pir and a.port_id <> v_cap);
  update public.port_treasury t set ducats = 100000 where t.port_id = v_hub;
  update public.port_treasury t set ducats = 500000 where t.port_id = v_city;
  update public.pirate_ships set laid_up_at = v_now where fleet_id <> all (array[v_f1, v_f4, v_f6]);
  v_w0 := pg_temp.w_108();
  v_b0 := public.treasury_balance(v_cap);
  v_s0 := coalesce((select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date), 0);
  if exists (select 1 from public.capital_gift_roster(v_now, null) g join public.pirate_ships n on n.player_id = g.player_id) then
    raise exception 'PROOF 108 FAIL: the house of a pirate ship is on the merchants'' hourly roster';
  end if;
  v_n := public.pirate_gift_hour(v_now);
  if v_n <> 3 or (select pl.ducats from public.players pl where pl.id = v_h1) <> 40000 or (select pl.ducats from public.players pl where pl.id = v_h4) <> 80000
     or (select pl.ducats from public.players pl where pl.id = v_h6) <> 708000
     or public.treasury_balance(v_hub) <> 60000 or public.treasury_balance(v_city) <> 420000 or v_b0 - public.treasury_balance(v_cap) <> 708000
     or (select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date) - v_s0 <> 828000
     or (select count(*) from public.capital_gifts g where g.player_id in (v_h1, v_h4, v_h6) and g.created_at = v_now) <> 3
     or pg_temp.w_108() <> v_w0 then
    raise exception 'PROOF 108 FAIL: gifts % (purses % % %; home % Djerba % hoard fell %; spent %; world % then %)', v_n,
      (select pl.ducats from public.players pl where pl.id = v_h1), (select pl.ducats from public.players pl where pl.id = v_h4), (select pl.ducats from public.players pl where pl.id = v_h6),
      public.treasury_balance(v_hub), public.treasury_balance(v_city), v_b0 - public.treasury_balance(v_cap),
      (select d.spent from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date), v_w0, pg_temp.w_108();
  end if;
  raise notice 'PASS: PT_GIFT — three houses with empty purses were given 40,000 (by her home), 80,000 (her home short: by Djerba, the richest other pirate city) and 708,000 (by the hoard); the day''s spend 828,000; none on the merchants'' roster; the world total stayed %', v_w0;

  -- ── PT_WEEK ──
  update public.players set ducats = 0 where id = v_h1;
  update public.port_treasury t set ducats = 2000000 where t.port_id = v_hub;
  if public.pirate_gift_hour(v_now + interval '30 minutes') <> 0 or public.pirate_gift_hour(v_now + interval '2 hours') <> 0 then
    raise exception 'PROOF 108 FAIL: a second gift inside the hour, or inside gift_cooldown_hours';
  end if;
  if public.pirate_gift_hour(v_now + interval '25 hours') <> 1 then raise exception 'PROOF 108 FAIL: no second gift a day later'; end if;
  update public.players set ducats = 0 where id = v_h1;
  if public.pirate_gift_hour(v_now + interval '50 hours') <> 1 then raise exception 'PROOF 108 FAIL: no third gift'; end if;
  update public.players set ducats = 0 where id = v_h1;
  if public.pirate_gift_hour(v_now + interval '75 hours') <> 0 or (select pl.ducats from public.players pl where pl.id = v_h1) <> 0 then
    raise exception 'PROOF 108 FAIL: a fourth gift inside seven days (gift_max_per_week %)', public.wc_int('gift_max_per_week');
  end if;
  if public.pirate_gift_hour(v_now + interval '7 days 1 hour') <> 1 then raise exception 'PROOF 108 FAIL: no gift when the first is seven days old'; end if;
  -- the pay's room: the day's room is made smaller than what the rest of the day's pay of three fleets needs plus her capital
  update public.players set ducats = 0 where id = v_h4;
  update public.world_config set value = to_jsonb(0.0001) where key = 'pirate_spend_day_pct';   -- about 90,000 of room; three fleets' pay to the day's end is more than 10,000 of it
  v_s0 := coalesce((select sum(d.spent) from public.pirate_spend_day d), 0);
  v_n := public.pirate_gift_hour(v_now + interval '9 days');
  if v_n <> 0 or (select pl.ducats from public.players pl where pl.id = v_h4) <> 0 or coalesce((select sum(d.spent) from public.pirate_spend_day d), 0) <> v_s0
     or public.pirate_spend_room(v_now + interval '9 days') < 80000 then
    raise exception 'PROOF 108 FAIL: a gift took the room the day''s pay needs (gifts %, room %, purse %)', v_n, public.pirate_spend_room(v_now + interval '9 days'), (select pl.ducats from public.players pl where pl.id = v_h4);
  end if;
  update public.world_config set value = to_jsonb(0.012) where key = 'pirate_spend_day_pct';
  raise notice 'PASS: PT_WEEK — none inside the cooldown, three in seven days and no fourth, one again when the first is seven days old; with a room of % that covers her 80,000 but not the day''s pay as well she waits and nothing is written',
    floor(public.pirate_hoard() * 0.0001);

  -- ── PT_PLAN ── the xebec at her home, bound for her haunt
  update public.players set ducats = 80000 where id = v_h4;
  select h.port_id into v_haunt from public.pirate_ships n cross join lateral public.pirate_haunt_of(n.home_port, n.ord) h where n.fleet_id = v_f4;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.treasury_balance(t.port_id)) from public.port_treasury t where t.port_id = v_haunt and public.treasury_balance(t.port_id) > 0;
  v_r := public.pirate_trade(v_f4, v_haunt, v_now);
  if public.pirate_cargo_plan(v_f4, v_haunt) <> '[]'::jsonb or (v_r ->> 'bought')::bigint <> 0 or public.fleet_stock_at_cost(v_f4) <> 0 then
    raise exception 'PROOF 108 FAIL: bound for a harbour with no purse she planned % and bought %', public.pirate_cargo_plan(v_f4, v_haunt), v_r;
  end if;
  update public.port_treasury t set ducats = t.ducats + 3000 where t.port_id = v_haunt;
  v_plan := public.pirate_cargo_plan(v_f4, v_haunt);
  if jsonb_array_length(v_plan) = 0 or (select sum((x ->> 'due')::numeric) from jsonb_array_elements(v_plan) x) > 3000 then
    raise exception 'PROOF 108 FAIL: with a purse of 3,000 at the sink she plans % (nothing, or sales worth more than the purse)', v_plan;
  end if;
  v_n := jsonb_array_length(v_plan);
  update public.port_treasury t set ducats = t.ducats + 50000000 where t.port_id = v_haunt;
  v_plan := public.pirate_cargo_plan(v_f4, v_haunt);
  if jsonb_array_length(v_plan) = 0 or (select sum((x ->> 'cost')::numeric) from jsonb_array_elements(v_plan) x) > 80000 - 16000
     or exists (select 1 from jsonb_array_elements(v_plan) x where (x ->> 'net')::numeric <= 0) then
    raise exception 'PROOF 108 FAIL: with a rich sink she plans % (nothing, more than she holds above the broke line, or a parcel that does not pay)', v_plan;
  end if;
  update public.players set ducats = 16000 where id = v_h4;
  if public.pirate_cargo_plan(v_f4, v_haunt) <> '[]'::jsonb then
    raise exception 'PROOF 108 FAIL: a house at the broke line (16,000 of 80,000) plans a cargo: %', public.pirate_cargo_plan(v_f4, v_haunt);
  end if;
  update public.players set ducats = 80000 where id = v_h4;
  raise notice 'PASS: PT_PLAN — no purse at the sink: no plan, nothing bought; a purse of 3,000: % parcel(s) worth no more than it there; a rich sink: % parcel(s) costing % of the 64,000 she holds above the broke line of 16,000; at the line she plans nothing',
    v_n, jsonb_array_length(v_plan), (select sum((x ->> 'cost')::numeric) from jsonb_array_elements(v_plan) x);

  -- ── PT_DOOR ── she buys for the rich sink; the sink's purse runs short before she arrives
  v_w0 := pg_temp.w_108();
  v_r := public.pirate_trade(v_f4, v_haunt, v_now);
  v_b0 := public.fleet_stock_at_cost(v_f4);
  if (v_r ->> 'bought')::bigint <= 0 or v_b0 <= 0 or (select pl.ducats from public.players pl where pl.id = v_h4) < 16000
     or exists (select 1 from public.capital_gift_roster(v_now + interval '30 days', v_h4)) then
    raise exception 'PROOF 108 FAIL: she bought nothing for a rich sink, or buying made her broke: %', v_r;
  end if;
  update public.fleets set port_id = v_haunt where id = v_f4;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.treasury_balance(t.port_id) - 1500) from public.port_treasury t where t.port_id = v_haunt and public.treasury_balance(t.port_id) - 1500 > 0;
  v_w0 := pg_temp.w_108();
  v_r := public.pirate_trade(v_f4, null, v_now);
  if (v_r ->> 'sold')::bigint > 1500 or public.treasury_balance(v_haunt) < 0 or public.fleet_stock_at_cost(v_f4) <= 0 or pg_temp.w_108() <> v_w0 then
    raise exception 'PROOF 108 FAIL: into a purse of 1,500 she sold % (purse now %, cargo left at cost %, world % then %)', v_r, public.treasury_balance(v_haunt), public.fleet_stock_at_cost(v_f4), v_w0, pg_temp.w_108();
  end if;
  v_b1 := (v_r ->> 'sold')::bigint;
  update public.port_treasury t set ducats = t.ducats + 50000000 where t.port_id = v_haunt;
  v_r := public.pirate_trade(v_f4, null, v_now);
  if exists (select 1 from public.events e where e.player_id = v_h4 and e.kind = 'SOLD' and (e.payload ->> 'profit')::numeric < 0)
     or not exists (select 1 from public.events e where e.player_id = v_h4 and e.kind = 'SOLD') then
    raise exception 'PROOF 108 FAIL: a sale of hers below cost, or no sale at all (%).', v_r;
  end if;
  raise notice 'PASS: PT_DOOR — a cargo of % at cost met a purse of 1,500: she was paid % and kept the rest aboard, the purse never under nothing; the purse back she sold % more; none of her % sale(s) below cost',
    v_b0, v_b1, (v_r ->> 'sold')::bigint, (select count(*) from public.events e where e.player_id = v_h4 and e.kind = 'SOLD');

  -- ── PT_DAY ── six fleets (a brigantin, a xebec, a squadron of each of two hubs), each house with her capital, the hubs' purses at 0 as 0409 founds them
  update public.voyages set status = 'ABORTED' where fleet_id = any (v_fl) and status = 'SAILING';
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = any (v_fl);
  update public.fleets f set status = 'DOCKED', lat = null, lon = null, ready_at = null, port_id = (select n.home_port from public.pirate_ships n where n.fleet_id = f.id) where f.id = any (v_fl);
  update public.pirate_ships set laid_up_at = null, unpaid_since = null, wrecked_at = null, sea_id = null, haunt_port = null, haunt_since = null, mission = 'HOME' where fleet_id = any (v_fl);
  update public.players pl set ducats = public.pirate_house_capital(pl.id) where pl.id in (select n.player_id from public.pirate_ships n where n.fleet_id = any (v_fl));
  update public.port_treasury t set ducats = 2000000;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.treasury_balance(t.port_id)) from public.port_treasury t where t.port_id in (v_hub, v_hub2) and public.treasury_balance(t.port_id) > 0;
  begin   -- the same day with trading off, rolled back
    update public.world_config set value = 'false'::jsonb where key = 'pirates_trade';
    raise exception using errcode = 'ZD108', message = pg_temp.day_108(v_fl, v_now + interval '20 days')::text;
  exception when sqlstate 'ZD108' then
    v_ctl := sqlerrm::numeric;
  end;
  v_w0 := pg_temp.w_108();
  create temp table day_108 on commit drop as select x as fleet_id, pg_temp.worth_108(array[x]) as w0, 0::numeric as w1 from unnest(v_fl) x;
  v_net := pg_temp.day_108(v_fl, v_now + interval '20 days');
  update day_108 d set w1 = pg_temp.worth_108(array[d.fleet_id]);
  select min(d.w1 - d.w0) into v_min from day_108 d;
  if v_ctl <> 0 or v_net <= 0 or v_min < 0 or pg_temp.w_108() <> v_w0
     or exists (select 1 from public.events e join public.pirate_ships n on n.player_id = e.player_id where n.fleet_id = any (v_fl) and e.kind = 'SOLD' and (e.payload ->> 'profit')::numeric < 0)
     or (select count(*) from public.pirate_ships n where n.fleet_id = any (v_fl) and n.mission = 'CRUISE') = 0 then
    raise exception 'PROOF 108 FAIL: the day: trading off nets %, trading on nets % (the worst fleet %); world % then %; %', v_ctl, v_net, v_min, v_w0, pg_temp.w_108(),
      (select jsonb_agg(d.w1 - d.w0) from day_108 d);
  end if;
  raise notice 'PASS: PT_DAY — over the day the six fleets that trade net % d. together (each: %); the same fleets with trading off net %; the hubs'' purses went from 0 to % and %; % sales, none below cost; the world total stayed',
    v_net, (select jsonb_agg(d.w1 - d.w0 order by d.fleet_id) from day_108 d), v_ctl, public.treasury_balance(v_hub), public.treasury_balance(v_hub2),
    (select count(*) from public.events e join public.pirate_ships n on n.player_id = e.player_id where n.fleet_id = any (v_fl) and e.kind = 'SOLD');

  -- ── PT_JOB ── the six at home again, each with her capital and an empty hold, all ready
  update public.voyages set status = 'ABORTED' where fleet_id = any (v_fl) and status = 'SAILING';
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = any (v_fl);
  update public.fleets f set status = 'DOCKED', lat = null, lon = null, ready_at = null, port_id = (select n.home_port from public.pirate_ships n where n.fleet_id = f.id) where f.id = any (v_fl);
  update public.pirate_ships set laid_up_at = null, unpaid_since = null, wrecked_at = null, sea_id = null, haunt_port = null, haunt_since = null, mission = 'HOME' where fleet_id = any (v_fl);
  update public.players pl set ducats = public.pirate_house_capital(pl.id) where pl.id in (select n.player_id from public.pirate_ships n where n.fleet_id = any (v_fl));
  update public.port_treasury t set ducats = 2000000;
  update public.pirate_clock set paid_at = v_now, gifted_at = v_now;
  v_r := public.tick_pirates(v_now + interval '40 days');
  if (select count(*) from unnest(v_fl) x where public.fleet_stock_at_cost(x) > 0) <> 1 or (select c.paid_at from public.pirate_clock c) <> v_now or (select c.gifted_at from public.pirate_clock c) <> v_now then
    raise exception 'PROOF 108 FAIL: a run of the job went on after a ship traded, or paid and gifted behind her locks: % (% fleets with cargo)', v_r, (select count(*) from unnest(v_fl) x where public.fleet_stock_at_cost(x) > 0);
  end if;
  v_r := public.tick_pirates(v_now + interval '40 days 1 minute');
  if (select count(*) from unnest(v_fl) x where public.fleet_stock_at_cost(x) > 0) <> 2 then
    raise exception 'PROOF 108 FAIL: the next minute did not step the next trader: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_trade';
  v_r := public.tick_pirates(v_now + interval '40 days 2 minutes');
  update public.world_config set value = 'true'::jsonb where key = 'pirates_trade';
  if (select c.paid_at from public.pirate_clock c) <> v_now + interval '40 days 2 minutes' or (select c.gifted_at from public.pirate_clock c) <> v_now + interval '40 days 2 minutes'
     or exists (select 1 from public.fleets f where f.id = any (v_fl) and f.status <> 'SAILING') then
    raise exception 'PROOF 108 FAIL: a run with no trade did not step every ship, pay and gift: %', v_r;
  end if;
  raise notice 'PASS: PT_JOB — six fleets ready to trade: the first run stopped after one had traded and left the pay and the gift; the next minute took the next; a run with no trade stepped the rest, paid and gifted: %', v_r;

  -- ── PT_REFIT_M ── a merchant whose country has a capital that is neither her home nor her yard
  for r in select f.id, h.home_port_id, pl.nation_id, cp.id as cap
             from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.npc_houses h on h.player_id = f.player_id
             join public.players pl on pl.id = f.player_id join public.nations na on na.id = pl.nation_id
             join public.ports cp on cp.code = na.capital_port_code and cp.kind = 'HARBOUR'
            where f.status = 'DOCKED' and cp.id <> h.home_port_id and not public.pirate_power(pl.nation_id) and public.port_nation(cp.id) = pl.nation_id
              and exists (select 1 from public.ships s where s.fleet_id = f.id)
            order by h.roster_ord limit 40 loop
    continue when public.refit_yard(r.home_port_id) is null or public.refit_yard(r.home_port_id) = r.cap
                  or (select count(*) from public.port_allegiance a where a.nation_id = r.nation_id and a.port_id not in (r.home_port_id, r.cap, public.refit_yard(r.home_port_id))) = 0;
    v_m := r.id; v_home := r.home_port_id; v_nat := r.nation_id; v_capm := r.cap;
    exit;
  end loop;
  if v_m is null then
    raise exception 'PROOF 108 FAIL: no merchant to wreck in this world';
  end if;
  select a.port_id into v_third from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id not in (v_home, v_capm, public.refit_yard(v_home)) order by a.port_id limit 1;
  update public.ships set durability = 0 where fleet_id = v_m;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_m;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.city_surplus(t.port_id)) from public.port_treasury t where t.port_id = v_home and public.city_surplus(t.port_id) > 0;
  v_w0 := pg_temp.w_108();
  v_b0 := public.treasury_balance(v_home);
  v_b1 := public.treasury_balance(v_capm);
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_m and s.durability <= 0) or public.treasury_balance(v_home) <> v_b0
     or v_b1 - public.treasury_balance(v_capm) <> public.npc_refit_cost(v_m) or pg_temp.w_108() <> v_w0
     or not exists (select 1 from public.events e where e.kind = 'REFITTED' and e.player_id = (select f.player_id from public.fleets f where f.id = v_m)
                       and e.payload ->> 'paid_by' = (select p.code from public.ports p where p.id = v_capm)) then
    raise exception 'PROOF 108 FAIL: a merchant wrecked with her home''s purse empty was not mended by her capital (home % then %, capital fell %, cost %; the fault of 2026-11-14, for a merchant)',
      v_b0, public.treasury_balance(v_home), v_b1 - public.treasury_balance(v_capm), public.npc_refit_cost(v_m);
  end if;
  -- every city of her country dry
  update public.ships set durability = 0 where fleet_id = v_m;
  update public.fleets set status = 'UNABLE_TO_SAIL', ready_at = null where id = v_m;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.city_surplus(t.port_id)) from public.port_treasury t where t.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = v_nat) and public.city_surplus(t.port_id) > 0;
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_m and s.durability > 0) or not exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_m)
     or not exists (select 1 from public.events e where e.kind = 'REFIT_WAITING' and e.player_id = (select f.player_id from public.fleets f where f.id = v_m) and e.payload ->> 'why' = 'broke') then
    raise exception 'PROOF 108 FAIL: with every city of her country dry she was mended unpaid, or waits with no row and no event (a silent wreck)';
  end if;
  update public.port_treasury t set ducats = t.ducats + 5000000 where t.port_id = v_third;
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_m and s.durability <= 0) or exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_m) then
    raise exception 'PROOF 108 FAIL: a purse back in a third city of her country, the job did not mend her';
  end if;
  raise notice 'PASS: PT_REFIT_M — a merchant wrecked with her home''s purse empty was mended, her capital % paying %; every city of her country dry she waited with a row and a REFIT_WAITING event, no hull restored unpaid; a purse back at %, the job mended her',
    (select p.code from public.ports p where p.id = v_capm), public.npc_refit_cost(v_m), (select p.code from public.ports p where p.id = v_third);

  -- ── PT_REFIT_N ── a navy ship stationed away from her realm's capital
  select g.nation_id, public.realm_capital(g.nation_id) into v_nat, v_capm from public.great_powers g
   where not g.pirate and public.realm_capital(g.nation_id) is not null and public.port_nation(public.realm_capital(g.nation_id)) = g.nation_id order by g.nation_id limit 1;
  select a.port_id into v_stn from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id <> v_capm and public.refit_yard(a.port_id) is not null and public.refit_yard(a.port_id) <> v_capm order by a.port_id limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_capm;
  v_navy := public.navy_commission(v_nat, 9001, v_capm, public.refit_yard(v_capm), v_stn, v_now);
  if v_navy is null or public.fleet_kind(v_navy) <> 'NAVY' or public.fleet_origin(v_navy) <> v_stn then
    raise exception 'PROOF 108 FAIL: no navy ship could be built for the proof';
  end if;
  update public.ships set durability = 0 where fleet_id = v_navy;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_navy;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.city_surplus(t.port_id)) from public.port_treasury t where t.port_id = v_stn and public.city_surplus(t.port_id) > 0;
  v_w0 := pg_temp.w_108();
  v_b1 := public.treasury_balance(v_capm);
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_navy and s.durability <= 0) or v_b1 - public.treasury_balance(v_capm) <> public.npc_refit_cost(v_navy) or pg_temp.w_108() <> v_w0 then
    raise exception 'PROOF 108 FAIL: a navy ship wrecked with her station''s purse empty was not mended by her realm''s capital (capital fell %, cost %)', v_b1 - public.treasury_balance(v_capm), public.npc_refit_cost(v_navy);
  end if;
  update public.ships set durability = 0 where fleet_id = v_navy;
  update public.fleets set status = 'UNABLE_TO_SAIL', ready_at = null where id = v_navy;
  insert into public.treasury_flows (port_id, kind, ducats) select t.port_id, 'REFIT', -(public.city_surplus(t.port_id)) from public.port_treasury t where t.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = v_nat) and public.city_surplus(t.port_id) > 0;
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_navy and s.durability > 0) or not exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_navy) then
    raise exception 'PROOF 108 FAIL: with every city of her realm dry a navy ship was mended unpaid, or waits with no row';
  end if;
  raise notice 'PASS: PT_REFIT_N — a navy ship wrecked with her station''s purse empty was mended, her realm''s capital paying %; every city of her realm dry she waits with a row, no hull restored unpaid', public.npc_refit_cost(v_navy);
end
$p$;
