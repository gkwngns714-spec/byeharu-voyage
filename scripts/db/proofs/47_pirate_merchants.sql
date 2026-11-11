-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 47 — PIRATE MERCHANTS  (migration 0341, slice W18 of docs/WORLD_POWERS.md; owner row 284: "pirates are like countries - power, where they can also invest. pirate merchants too")
--
--   0341's own self-assert reads the catalog and cheap pure functions only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs the REAL job, founding, payer, gift roster,
--   invest pass, daily count, route planner, day cap and sail door on a world it lights itself (purses, closed economy, merchants, influence, the pirates' switch), all rolled back with proof.mjs's transaction.
--   It owns every switch it needs and writes them here. The hoard is Port Royal's purse, funded by a probe company founded while the economy is open (its money is minted then, before W is taken).
--
-- @pass PM_DARK        pirates_bite false (as shipped): the job answers enabled false and founds nobody; pirate_found says dark; no house of the pirates exists; the planner rule is the identity and a crown merchant near a pirate home is offered a loop through it; the day cap at a home is the base
-- @pass PM_FOUNDED     lit: ONE run founds ONE merchant of the pirates at the capital (slot 1, Port Royal): a merchant house in ink pir, nation PIR, capital 250,000, one carlat docked at Port Royal, a two-stop route out and back, her purse her capital; named by the first FREE spelling (two companies already hold the slot's name and its ' II'), nothing tried and refused; pirate_merchant true for her and for nobody else
-- @pass PM_PAID        her founding is paid by Port Royal's purse as PIRATE_FOUND and nothing else: her ledger holds PIRATE_FOUND credits equal to the purse's PIRATE_FOUND outflow, 0339's spend book holds the same, no FOUNDING ledger row of hers, no CROWN_CALL, and W is unchanged to the ducat
-- @pass PM_GATES       the gates, each said: a run a minute later is paced; pirate_merchants_max reached is full; the merchant roster full is no_berth; the day's room spent is room, and so is a room just under what founding_credit really pays (capital + tuition, 252,500) plus the ships' reserve; and a founding the hoard cannot pay is refused WHOLE (E_HOARD_SHORT) leaving no house
-- @pass PM_SECOND      two hours later the second (slot 2) is founded at Goto: its home in the ring, Djerba, refuses (its courses pointed off the sphere: E_BAD_PATH inside npc_found) and the SAME run passes it over, saying what it tried
-- @pass PM_NO_GIFT     a broke merchant of the pirates is not on the capital's gift roster; a broke crown merchant is
-- @pass PM_INVESTS     lit she is on the invest roster and her turn in the real pass gives for the pirates at the closest race on her loop (a port_influence row under PIR, by her); dark she is off the roster
-- @pass PM_COUNT       the daily count runs with 11 powers: the free city she gave to flies the skull, she is its mayor, the Countries board counts it won; the city is NOT free (tax quoted, dock fee charged, no crown)
-- @pass PM_PLANNER     lit: the crown merchant's loops hold no pirate home; the pirate merchant's loops out of her home are offered, every destination a harbour that is no pirate home, her way home kept
-- @pass PM_DAY_CAP     lit: at Port Royal a company's day cap in a good is the lesser of the base and 5 % of twice the target; at a control city it is the base; dark it is the base at both
-- @pass PM_NO_INSURER  she sails through the one sail door and is not insured (why pirate, no insured_voyages row); a crown merchant's voyage is not refused for that reason
-- @pass PM_MONEY       W (purses + companies + funds aboard) is unchanged to the ducat across the two foundings, the gift, the stake, the count, the sails and every quote above
-- ═══════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_47() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;

do $$
declare
  c_uid1   constant uuid := '00000000-0f47-4000-8000-000000000001';
  v_pir    uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_por    uuid := (select p.id from public.ports p where p.code = 'POR');
  v_dje    uuid := (select p.id from public.ports p where p.code = 'DJE');
  v_got    uuid := (select p.id from public.ports p where p.code = 'GOT');
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_rich   uuid;
  v_t0     timestamptz := now();
  v_r      jsonb;
  v_m1     uuid;
  v_m2     uuid;
  v_f1     uuid;
  v_route1 uuid;
  v_dest   uuid;
  v_dest_code text;
  v_w0     numeric;
  v_n      int;
  v_x      int;
  v_fleet_max int;
  v_spent  bigint;
  v_room   bigint;
  v_reserve bigint;
  v_cap    numeric;
  v_base   numeric;
  v_good   uuid;
  v_hour   timestamptz;
  v_voy    uuid;
  v_ctl    record;   -- the crown merchant near a pirate home: her house, fleet, route, home, hold and speed
  v_ctl_voy uuid;
  v_pirate_stop boolean;
  v_ord    int;
  v_day    date;
  v_pay_day date;     -- the UTC day the payer books a founding on: the wall clock's (founding_credit hands public.pirate_pay now()), not the gate's p_now
  v_pay_spent bigint;
begin
  if v_pir is null or v_por is null or v_dje is null then
    raise exception 'PROOF 47 FAIL: the pirates or their homes are not in this world (0338)';
  end if;

  -- ── 1 SETUP: purses lit; a rich probe founded while the economy is OPEN (minted, before W is taken) funds Port Royal (TAX, moved); then closed, merchants on, influence on ──
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_rich := public.new_house(c_uid1, 'Casa Rica 0f47', 'PRT', 'LIS', 'Rica', 'barca', 'Rica', 2000000000, false);
  perform public.pay_city(v_rich, v_por, 'TAX', 1000000000);
  -- two companies already hold slot 1's name and its second spelling: a taken name must never block the slot (the spec picks the first free spelling)
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Brethren of the Coast', (select n.id from public.nations n where n.code = 'PRT'), 0, false), ('Brethren of the Coast II', (select n.id from public.nations n where n.code = 'PRT'), 0, false);
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'influence_enabled');
  if public.pirates_on() then
    raise exception 'PROOF 47 FAIL: pirates_bite is on as shipped';
  end if;
  v_fleet_max := public.wc_int('npc_fleet_max');
  v_w0 := pg_temp.w_47();
  -- the crown merchant whose home has a known leg to a pirate home (the planner's control), the first by roster
  select h.player_id, nf.fleet_id, nf.route_id, h.home_port_id, p.code as home,
         public.fleet_free_hold(nf.fleet_id) as hold, greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
         (select q.code from public.npc_known_legs(h.home_port_id) l join public.ports q on q.id = l.to_port where public.pirate_home(q.id) order by l.nm limit 1) as pirate_leg
    into v_ctl
    from public.npc_houses h join public.npc_fleets nf on nf.player_id = h.player_id join public.ports p on p.id = h.home_port_id
   where exists (select 1 from public.npc_known_legs(h.home_port_id) l where public.pirate_home(l.to_port))
   order by h.roster_ord
   limit 1;
  if v_ctl.player_id is null then
    raise exception 'PROOF 47 FAIL: no crown merchant''s home has a known leg to a pirate home (the planner control needs one)';
  end if;

  -- ── 2 DARK ──
  v_r := public.tick_pirate_merchants(v_t0);
  if (v_r->>'enabled')::boolean or v_r ? 'founded' then
    raise exception 'PROOF 47 FAIL: dark, the job answered %', v_r;
  end if;
  v_r := public.pirate_found(v_t0);
  if v_r->>'why' <> 'dark' or v_r->>'founded' is not null then
    raise exception 'PROOF 47 FAIL: dark, pirate_found answered %', v_r;
  end if;
  if exists (select 1 from public.npc_houses h join public.players pl on pl.id = h.player_id where pl.nation_id = v_pir)
     or exists (select 1 from public.npc_houses h where public.pirate_merchant(h.player_id)) then
    raise exception 'PROOF 47 FAIL: dark, a merchant of the pirates exists';
  end if;
  select bool_or(exists (select 1 from jsonb_array_elements(c.stops) s where public.pirate_home((s->>'port_id')::uuid)))
    into v_pirate_stop
    from public.npc_loop_candidates(v_ctl.route_id, v_ctl.fleet_id, v_ctl.home_port_id, v_ctl.hold, v_ctl.speed) c;
  if not coalesce(v_pirate_stop, false) then
    raise exception 'PROOF 47 FAIL: dark, the crown merchant at % is offered no loop through the pirate home % (the control is vacuous)', v_ctl.home, v_ctl.pirate_leg;
  end if;
  select g.id into v_good from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_por and pg.stock_target > 0 order by g.code limit 1;
  v_base := world.daily_cap_remaining(v_rich, v_por, v_good);
  if v_base is distinct from (select greatest(0, public.daily_cap_base(v_rich, v_por) * pg.stock_target) from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_good) or v_base <= 0 then
    raise exception 'PROOF 47 FAIL: dark, the day cap at Port Royal is %, not the base', v_base;
  end if;
  raise notice 'PASS: PM_DARK — job enabled false, pirate_found dark, no pirate merchant, the crown merchant at % is offered a loop through %, the day cap at Port Royal is the base %', v_ctl.home, v_ctl.pirate_leg, v_base;

  -- ── 3 LIT: the first founding ──
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  v_r := public.tick_pirate_merchants(v_t0);
  v_m1 := (v_r->>'founded')::uuid;
  if v_m1 is null or v_r->>'why' <> 'founded' or (v_r->>'slot')::int <> 1 or v_r->>'home' <> 'POR'
     or v_r->>'company' <> 'Brethren of the Coast 3' or jsonb_array_length(v_r->'tried') <> 0
     or not exists (select 1 from public.players pl where pl.id = v_m1 and pl.company_name = 'Brethren of the Coast 3') then
    raise exception 'PROOF 47 FAIL: lit, the first run answered % (slot 1 at Port Royal, named by the first free spelling, nothing tried and refused)', v_r;
  end if;
  select nf.fleet_id, nf.route_id into v_f1, v_route1 from public.npc_fleets nf where nf.player_id = v_m1;
  select count(*) into v_n from public.standing_route_stops st where st.route_id = v_route1;
  select st.port_id into v_dest from public.standing_route_stops st where st.route_id = v_route1 and st.ord = 1;
  select p.code into v_dest_code from public.ports p where p.id = v_dest;
  if not exists (select 1 from public.players pl where pl.id = v_m1 and pl.is_npc and pl.nation_id = v_pir and pl.ducats = 250000)
     or not exists (select 1 from public.npc_houses h where h.player_id = v_m1 and h.ink = 'pir' and h.home_port_id = v_por and h.capital = 250000)
     or not public.pirate_merchant(v_m1)
     or (select count(*) from public.npc_houses h where public.pirate_merchant(h.player_id)) <> 1
     or v_f1 is null or v_route1 is null or v_n <> 2
     or (select count(*) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_f1 and c.code = 'carlat') <> 1
     or (select f.port_id from public.fleets f where f.id = v_f1) <> v_por
     or public.fleet_kind(v_f1) <> 'MERCHANT' or public.fleet_origin(v_f1) <> v_por or public.crown_house(v_m1)
     or v_dest is null or public.pirate_home(v_dest)
     or not exists (select 1 from public.npc_known_legs(v_por) l where l.to_port = v_dest) then
    raise exception 'PROOF 47 FAIL: the first pirate merchant is not as the plan says (stops %, dest %)', v_n, v_dest_code;
  end if;
  raise notice 'PASS: PM_FOUNDED — % (slot 1) founded at Port Royal: ink pir, nation PIR, capital 250,000, one carlat at POR, a two-stop loop POR -> % -> POR, a MERCHANT by fleet_kind with origin POR', v_r->>'company', v_dest_code;

  -- the money of the founding
  v_day := (v_t0 at time zone 'UTC')::date;
  select coalesce(sum(l.ducats_delta), 0) into v_spent from public.ledger l where l.player_id = v_m1 and l.kind = 'PIRATE_FOUND';
  if v_spent < 250000
     or v_spent <> -(select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = v_por and f.kind = 'PIRATE_FOUND')
     or v_spent <> (select coalesce(sum(d.spent), 0) from public.pirate_spend_day d where d.day = v_day)
     or exists (select 1 from public.ledger l where l.player_id = v_m1 and l.kind in ('FOUNDING', 'CAPITAL_GIFT') and l.ducats_delta > 0)
     or exists (select 1 from public.treasury_flows f where f.kind = 'CROWN_CALL' and f.created_at >= v_t0)
     or exists (select 1 from public.treasury_flows f where f.kind = 'PIRATE_FOUND' and f.port_id <> v_por)
     or pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: the founding''s money is not Port Royal''s PIRATE_FOUND alone (ledger % d., W % -> %)', v_spent, v_w0, pg_temp.w_47();
  end if;
  raise notice 'PASS: PM_PAID — PIRATE_FOUND % d. from Port Royal''s purse to her ledger, the same in the spend book, no FOUNDING or gift row of hers, no CROWN_CALL, W unchanged (% d.)', v_spent, v_w0;

  -- ── 4 THE GATES ──
  v_r := public.pirate_found(v_t0 + interval '1 minute');
  if v_r->>'why' <> 'paced' or v_r->>'founded' is not null then
    raise exception 'PROOF 47 FAIL: a minute later the founding was not paced: %', v_r;
  end if;
  update public.world_config set value = '1'::jsonb where key = 'pirate_merchants_max';
  v_r := public.pirate_found(v_t0 + interval '3 hours');
  update public.world_config set value = '30'::jsonb where key = 'pirate_merchants_max';
  if v_r->>'why' <> 'full' then
    raise exception 'PROOF 47 FAIL: at pirate_merchants_max 1 the founding was not full: %', v_r;
  end if;
  update public.world_config set value = to_jsonb((select count(*) from public.npc_fleets)) where key = 'npc_fleet_max';
  v_r := public.pirate_found(v_t0 + interval '3 hours');
  update public.world_config set value = to_jsonb(v_fleet_max) where key = 'npc_fleet_max';
  if v_r->>'why' <> 'no_berth' then
    raise exception 'PROOF 47 FAIL: with the merchant roster full the founding was not no_berth: %', v_r;
  end if;
  -- the day's room spent (0339's book, this proof's own row for a day three hours on)
  v_day := ((v_t0 + interval '3 hours') at time zone 'UTC')::date;
  select coalesce(d.spent, 0) into v_spent from public.pirate_spend_day d where d.day = v_day;
  v_spent := coalesce(v_spent, 0);
  insert into public.pirate_spend_day (day, spent) values (v_day, floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct'))::bigint)
  on conflict (day) do update set spent = excluded.spent;
  v_room := public.pirate_spend_room(v_t0 + interval '3 hours');
  v_r := public.pirate_found(v_t0 + interval '3 hours');
  if v_room <> 0 or v_r->>'why' <> 'room' or v_r->>'founded' is not null then
    raise exception 'PROOF 47 FAIL: with the day''s room spent (room %) the founding was not refused for room: %', v_room, v_r;
  end if;
  -- and the payer itself, asked directly through the one founding path: refused WHOLE, nothing of her stays
  -- THE PAYER'S DAY IS THE WALL CLOCK'S: public.founding_credit pays through public.pirate_pay(..., now(), ...), so its room is the room of now()'s UTC day, whatever hour the gate above was asked about.
  -- From 21:00 UTC on, v_t0 + 3 hours is TOMORROW: the row spent above is then not the payer's, the payer still had its whole day's room, and the probe house was founded (nightly runs 42418402614,
  -- 42529316649 and 42923963630, all started after 21:00 UTC). So the room is spent on the payer's own day too, shown to be 0 by the one reader, and put back after the probe.
  v_pay_day := (now() at time zone 'UTC')::date;
  if v_pay_day <> v_day then
    select d.spent into v_pay_spent from public.pirate_spend_day d where d.day = v_pay_day;
    insert into public.pirate_spend_day (day, spent) values (v_pay_day, floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct'))::bigint)
    on conflict (day) do update set spent = excluded.spent;
  end if;
  if public.pirate_spend_room(now()) <> 0 then
    raise exception 'PROOF 47 FAIL: the payer''s own day (%) still has % d. of room: the probe below would prove nothing', v_pay_day, public.pirate_spend_room(now());
  end if;
  select count(*) into v_n from public.players;
  begin
    perform public.new_house(null, 'Probe Corsair 0f47', 'PIR', 'POR', 'Probe', 'carlat', 'Probe', 250000, true);
    raise exception 'PROOF 47 FAIL: a pirate merchant was founded with no room in the hoard';
  exception when others then
    if sqlerrm !~ '^E_HOARD_SHORT' then raise; end if;
  end;
  if (select count(*) from public.players) <> v_n or exists (select 1 from public.players pl where pl.company_name = 'Probe Corsair 0f47') then
    raise exception 'PROOF 47 FAIL: a refused founding left a house behind';
  end if;
  if v_pay_day <> v_day then
    update public.pirate_spend_day d set spent = coalesce(v_pay_spent, 0) where d.day = v_pay_day;
  end if;
  -- the room just under what founding_credit really pays (her capital AND her tuition, 252,500) plus the ships' reserve: refused for room by the gate, never handed to the payer to refuse
  v_reserve := ceil(public.pirate_size() * public.wc_int('navy_upkeep_day')
                    * extract(epoch from (date_trunc('day', (v_t0 + interval '3 hours') at time zone 'UTC') + interval '1 day' - ((v_t0 + interval '3 hours') at time zone 'UTC'))) / 86400)::bigint;
  update public.pirate_spend_day d set spent = floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct'))::bigint - (252500 - 1000 + v_reserve) where d.day = v_day;
  v_room := public.pirate_spend_room(v_t0 + interval '3 hours');
  v_r := public.pirate_found(v_t0 + interval '3 hours');
  if v_room <> 252500 - 1000 + v_reserve or v_r->>'why' <> 'room' or (v_r->>'cost')::bigint <> 252500 or v_r->>'founded' is not null then
    raise exception 'PROOF 47 FAIL: with the room just under her cost (room %, reserve %) the founding was not refused for room: %', v_room, v_reserve, v_r;
  end if;
  update public.pirate_spend_day d set spent = v_spent where d.day = v_day;
  if pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: the gates moved money: W % -> %', v_w0, pg_temp.w_47();
  end if;
  raise notice 'PASS: PM_GATES — paced a minute later; full at max 1; no_berth with the roster full; room with the day spent (room 0) and with the room just under her cost of 252,500 plus the ships'' reserve of % d.; E_HOARD_SHORT refused whole, no house left, W unchanged', v_reserve;

  -- ── 5 THE SECOND, two hours on: slot 2's home in the ring is Djerba, and Djerba REFUSES (its only courses are pointed off the sphere, so the route door answers E_BAD_PATH inside npc_found) ──
  -- a home that refuses must not hold the roster: the same run passes it over and founds at the next home, Goto, saying what it tried
  update public.npc_courses c set course = '[[999, 999], [999, 999]]'::jsonb where c.from_port = v_dje or c.to_port = v_dje;
  v_r := public.tick_pirate_merchants(v_t0 + interval '3 hours');
  v_m2 := (v_r->>'founded')::uuid;
  if v_m2 is null or (v_r->>'slot')::int <> 2 or v_r->>'home' <> 'GOT'
     or jsonb_array_length(v_r->'tried') <> 1 or v_r->'tried'->0->>'home' <> 'DJE' or v_r->'tried'->0->>'error' !~ 'E_BAD_PATH'
     or not exists (select 1 from public.npc_houses h where h.player_id = v_m2 and h.home_port_id = v_got and h.ink = 'pir')
     or (select count(*) from public.npc_houses h where public.pirate_merchant(h.player_id)) <> 2
     or exists (select 1 from public.players pl where pl.is_npc and pl.nation_id = v_pir and pl.id not in (v_m1, v_m2) and exists (select 1 from public.npc_houses h where h.player_id = pl.id))
     or pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: the second founding is not slot 2 at Goto after Djerba refused: % (W % -> %)', v_r, v_w0, pg_temp.w_47();
  end if;
  raise notice 'PASS: PM_SECOND — % (slot 2) founded at Goto three hours on: Djerba refused (%) and was passed over in the same run; W unchanged', v_r->>'company', v_r->'tried'->0->>'error';

  -- ── 6 NO GIFT: the second is made broke (her purse to Goto, moved); a crown merchant made broke the same way is on the roster, she is not ──
  perform public.pay_city(v_m2, v_got, 'TAX', 245000);
  perform public.pay_city(v_ctl.player_id, v_ctl.home_port_id, 'TAX', (select pl.ducats - 1000 from public.players pl where pl.id = v_ctl.player_id));
  if (select pl.ducats from public.players pl where pl.id = v_m2) <> 5000
     or exists (select 1 from public.capital_gift_roster(v_t0 + interval '4 hours', v_m2) g)
     or exists (select 1 from public.capital_gift_roster(v_t0 + interval '4 hours') g where g.player_id = v_m2)
     or not exists (select 1 from public.capital_gift_roster(v_t0 + interval '4 hours', v_ctl.player_id) g) then
    raise exception 'PROOF 47 FAIL: the broke pirate merchant is gifted, or the broke crown merchant is not';
  end if;
  -- the pass itself, run for her alone: nothing gifted, nothing waiting, nothing failed
  v_r := public.capital_gift_pass(v_t0 + interval '4 hours', v_m2);
  if (v_r->>'gifted')::int <> 0 or (v_r->>'gift_waiting')::int <> 0 or (v_r->>'failed')::int <> 0 then
    raise exception 'PROOF 47 FAIL: the gift pass touched the pirate merchant: %', v_r;
  end if;
  raise notice 'PASS: PM_NO_GIFT — the broke pirate merchant (5,000 d. of 250,000) is on no gift roster and the pass gives her nothing; the broke crown merchant is on it';

  -- ── 7 INVESTS: the first, made rich by her capital (a probe move, moved), is on the invest roster lit; her real turn gives at the closest race on her loop ──
  perform public.city_pays(v_por, v_m1, 'CAPITAL_GIFT', 2000000);
  if not exists (select 1 from public.npc_invest_roster() r where r.player_id = v_m1) then
    raise exception 'PROOF 47 FAIL: lit, the rich pirate merchant is not on the invest roster';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  if exists (select 1 from public.npc_invest_roster() r where r.player_id = v_m1) then
    raise exception 'PROOF 47 FAIL: dark, the pirate merchant is still on the invest roster';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  -- a race for the pirates at her second stop (a free city): a small gift of hers makes it a claim race (under influence_claim_min)
  if public.port_nation(v_dest) is not null then
    raise exception 'PROOF 47 FAIL: her second stop % is held (the claim race needs a free city)', v_dest_code;
  end if;
  v_r := public.donate_for(v_m1, v_dest, 5000);
  select h.roster_ord into v_ord from public.npc_houses h where h.player_id = v_m1;
  v_hour := (date_trunc('day', v_t0 at time zone 'UTC') + make_interval(hours => v_ord % 24)) at time zone 'UTC';   -- her hour of the day (public.npc_share_budget)
  v_r := public.npc_invest_one(v_hour, v_m1);
  if (v_r->>'failed')::int <> 0 or (v_r->>'donated')::int + (v_r->>'invested')::int < 1 then
    raise exception 'PROOF 47 FAIL: her turn in the invest pass gave nothing: %', v_r;
  end if;
  if not exists (select 1 from public.port_influence i where i.port_id = v_dest and i.nation_id = v_pir and i.player_id = v_m1 and i.points >= public.wc_num('influence_claim_min'))
     or (select h.invested_at from public.npc_houses h where h.player_id = v_m1) is distinct from v_hour
     or pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: her gift did not land under PIR at % with enough to claim (W % -> %)', v_dest_code, v_w0, pg_temp.w_47();
  end if;
  raise notice 'PASS: PM_INVESTS — on the roster lit, off it dark; her turn gave at % for the pirates (%), points % under PIR, W unchanged',
    v_dest_code, v_r, (select round(i.points) from public.port_influence i where i.port_id = v_dest and i.nation_id = v_pir and i.player_id = v_m1);

  -- ── 8 THE COUNT with 11 powers ──
  v_r := public.tick_influence(v_t0 + interval '1 day');
  if (v_r->>'claimed')::int < 1 or jsonb_array_length(v_r->'errors') <> 0
     or public.port_nation(v_dest) is distinct from v_pir
     or (select a.home from public.port_allegiance a where a.port_id = v_dest)
     or public.pirate_home(v_dest) or public.port_is_free(v_dest)
     or world.tax_rate(v_dest) <= 0 or public.port_fee(v_dest, v_rich, 1000000) <= 0
     or public.city_capital(v_dest) is not null
     or (select m.player_id from public.port_mayor m where m.port_id = v_dest) is distinct from v_m1
     or (select (c->>'won')::int from jsonb_array_elements(world.nation_standings()->'countries') c where c->>'code' = 'PIR') <> 1
     or pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: the count did not hand % to the pirates as a won city that keeps its tax: % (held by %)', v_dest_code, v_r,
      (select n.code from public.nations n where n.id = public.port_nation(v_dest));
  end if;
  raise notice 'PASS: PM_COUNT — the count claimed % for the pirates (11 powers ranked: claimed %); she is its mayor; the board counts 1 won; it is not free: tax % and a dock fee of % d. for a company of Portugal; no crown',
    v_dest_code, v_r->>'claimed', world.tax_rate(v_dest), public.port_fee(v_dest, v_rich, 1000000);

  -- ── 9 THE PLANNER, lit ──
  select bool_or(exists (select 1 from jsonb_array_elements(c.stops) s where public.pirate_home((s->>'port_id')::uuid))), count(*)
    into v_pirate_stop, v_n
    from public.npc_loop_candidates(v_ctl.route_id, v_ctl.fleet_id, v_ctl.home_port_id, v_ctl.hold, v_ctl.speed) c;
  if coalesce(v_pirate_stop, false) or v_n = 0 then
    raise exception 'PROOF 47 FAIL: lit, the crown merchant at % is still offered a loop through a pirate home (% loops)', v_ctl.home, v_n;
  end if;
  select count(*), bool_or(exists (select 1 from jsonb_array_elements(c.stops) with ordinality s(x, o) where o > 1 and public.pirate_home((s.x->>'port_id')::uuid)))
    into v_x, v_pirate_stop
    from public.npc_loop_candidates(v_route1, v_f1, v_por, public.fleet_free_hold(v_f1), greatest(coalesce(voyage.fleet_speed_at(v_f1, 1), 0), 0.1)) c;
  if v_x = 0 or coalesce(v_pirate_stop, false)
     or exists (select 1 from public.npc_loop_candidates(v_route1, v_f1, v_por, public.fleet_free_hold(v_f1), greatest(coalesce(voyage.fleet_speed_at(v_f1, 1), 0), 0.1)) c
                 where (c.stops->0->>'port_id')::uuid <> v_por) then
    raise exception 'PROOF 47 FAIL: lit, the pirate merchant at Port Royal is offered % loops, or one through another pirate home, or one not from her home', v_x;
  end if;
  raise notice 'PASS: PM_PLANNER — lit, the crown merchant at % has % loops and none through %; the pirate merchant at Port Royal has % loops, every one from her home to harbours that are no pirate home',
    v_ctl.home, v_n, v_ctl.pirate_leg, v_x;

  -- ── 10 THE DAY CAP at a home, lit and dark ──
  v_cap := world.daily_cap_remaining(v_rich, v_por, v_good);
  if v_cap is distinct from (select greatest(0, least(public.daily_cap_base(v_rich, v_por) * pg.stock_target, public.wc_num('pirate_port_day_cap') * 2 * pg.stock_target))
                               from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_good)
     or v_cap >= v_base
     or world.daily_cap_remaining(v_rich, v_lis, v_good) is distinct from
        (select greatest(0, public.daily_cap_base(v_rich, v_lis) * pg.stock_target) from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good) then
    raise exception 'PROOF 47 FAIL: lit, the day cap at Port Royal is % (base %), or Lisbon''s moved', v_cap, v_base;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  if world.daily_cap_remaining(v_rich, v_por, v_good) is distinct from v_base then
    raise exception 'PROOF 47 FAIL: dark again, the day cap at Port Royal is not the base';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  raise notice 'PASS: PM_DAY_CAP — lit, Port Royal caps a company''s day in a good at % (base %); Lisbon''s cap is the base; dark the base again', v_cap, v_base;

  -- ── 11 NO INSURER: she sails through the one sail door; a crown merchant sails too ──
  begin
    v_r := cmd.do_sail(v_f1, jsonb_build_object('dest', v_dest, 'path', (select st.course from public.standing_route_stops st where st.route_id = v_route1 and st.ord = 0)));
  exception when others then
    raise exception 'PROOF 47 FAIL: the pirate merchant could not sail POR -> %: %', v_dest_code, sqlerrm;
  end;
  select v.id into v_voy from public.voyages v where v.fleet_id = v_f1 and v.status = 'SAILING';
  if v_voy is null then
    raise exception 'PROOF 47 FAIL: the sail door answered % but she is not at sea', v_r;
  end if;
  v_r := public.insure_voyage(v_voy, true);
  if v_r->>'why' <> 'pirate' or (v_r->>'insured')::boolean
     or exists (select 1 from public.insured_voyages iv where iv.fleet_id = v_f1) then
    raise exception 'PROOF 47 FAIL: the pirate merchant''s voyage was insured: %', v_r;
  end if;
  begin
    v_r := cmd.do_sail(v_ctl.fleet_id, jsonb_build_object('dest', (select st.port_id from public.standing_route_stops st where st.route_id = v_ctl.route_id and st.ord = 1),
                                                           'path', (select st.course from public.standing_route_stops st where st.route_id = v_ctl.route_id and st.ord = 0)));
  exception when others then
    raise exception 'PROOF 47 FAIL: the crown merchant at % could not sail her first leg: %', v_ctl.home, sqlerrm;
  end;
  select v.id into v_ctl_voy from public.voyages v where v.fleet_id = v_ctl.fleet_id and v.status = 'SAILING';
  if v_ctl_voy is null then
    raise exception 'PROOF 47 FAIL: the crown merchant is not at sea after the sail door';
  end if;
  v_r := public.insure_voyage(v_ctl_voy, true);
  if v_r->>'why' = 'pirate' then
    raise exception 'PROOF 47 FAIL: the crown merchant''s voyage was refused insurance as a pirate''s: %', v_r;
  end if;
  raise notice 'PASS: PM_NO_INSURER — she sailed POR -> % through cmd.do_sail and is not insured (why pirate, no row); the crown merchant''s voyage answers % to the insurer', v_dest_code, v_r->>'why';

  -- ── 12 MONEY ──
  if pg_temp.w_47() <> v_w0 then
    raise exception 'PROOF 47 FAIL: W moved across the proof: % -> %', v_w0, pg_temp.w_47();
  end if;
  raise notice 'PASS: PM_MONEY — W % d. unchanged to the ducat across two foundings, a gift, a stake, the count, two sails and every quote', v_w0;
end $$;
