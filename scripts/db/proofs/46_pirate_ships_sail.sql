-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 46 — PIRATE SHIPS SAIL  (migration 0339, slice W17 of docs/WORLD_POWERS.md Part 5; owner row 284: "npcs that attack these ships as well as merchants")
--
--   0339's own self-assert reads the catalog, stable reads and arithmetic only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lights pirates_bite and runs the REAL job, the REAL voyage
--   engine, the REAL fight (public.fight_sides through voyage.settle's PIRATES arm), the REAL market regen, the REAL purses and the REAL attack door, on probe fleets, all rolled back by proof.mjs. The sea is stubbed on
--   one setting as proof 37's and 38's: '' quiet, 'PIRATES' a raid of magnitude 0.5, 'REAL' the real roll. The economy is CLOSED and the purses lit, as on prod. It owns every switch it needs and writes them here.
--
-- @pass PIR_DARK        off: the job writes nothing; a departure's frozen path is voyage.freeze_danger's byte for byte (no raider); a PIRATES day is today's anonymous figure with no pirate key; kinds, origins, wages, fees stand; no PIRATE on the sea; the card refuses a company
-- @pass PIR_NEEDS_PURSES the switch with the purses dark lights nothing
-- @pass PIR_BROKE       lit, a hoard at 0 builds none: no hull, no flow, no event, room 0
-- @pass PIR_SIZE        the size follows the hoard through the real reader: 4 at 0, 7 at 300 M
-- @pass PIR_BUILD       the hoard pays the moment it can: BUILD_NAVY, capital to the nearest yard, two moved rows, nothing minted; one crewless hull of the raider's class at her home; her house PIR, purse 0, no ledger row; one a day; the spend written
-- @pass PIR_SPEND       the one cap: a payee (W18's shape) is paid whole from the room or not at all; the room falls by what was paid; nothing minted
-- @pass PIR_KIND        she is PIRATE, her origin her home, a crown house, no wage, no dock fee, on the sea as kind PIRATE; merchants', cargo ships' and companies' answers stand
-- @pass PIR_CRUISE      at home she sails for the most dangerous haunt in reach: her sea is the haunt's, mission CRUISE, public.pirate_ship_in_sea names her; at the haunt she lies pirate_haunt_hours, then sails home; home, her sea is null and she sails again
-- @pass PIR_PRESSURE    her sea carries pirate_pressure while she cruises and voyage.sea_danger moves by it; the row goes when she heads home; off, the table empties
-- @pass PIR_RAID        a fleet leaving while she cruises has her name frozen on the segment of her sea; a real PIRATES day through voyage.settle fights her at voyage.pirate_strength; plundered, the goods land in her home's stock up to 2 x target and the rest is lost; the payload names her
-- @pass PIR_LOOT        a cargo ship plundered loses the day's share of her funds aboard: her book closes LOOTED, her home's purse takes it (LOOT), set aside falls by it
-- @pass PIR_RANSOM      paid off through the real settle: ransom_share of the cargo's cost basis moves from the company's purse to her home (RANSOM); a purse that cannot pay pays what it holds; a hoard at the cap takes nothing
-- @pass PIR_REGEN       lit, a pirate home's stock neither regenerates nor decays, a control city's does; off, the home regenerates as any
-- @pass PIR_PAY         an hour of upkeep: the hoard pays the harbour she lies at, two rows, moved; once an hour; at the capital nothing moves; unpaid, she goes home and is laid up; money back, she wakes (WOKEN), the same fleet
-- @pass PIR_OFF         switch off with her out: she sails home and is laid up; a new departure through her sea names nobody; nothing is built or paid
-- @pass PIR_WRECK       wrecked at home with the refit rule dark she is patched free; lit, her home pays the refit, moved
-- @pass PIR_CARD        her card serves what she is (home, haunt, mission) and refuses anything else; it is a client entry point
-- @pass PIR_ATTACK      attacks lit: a player at sea may attack her (regard_pirate with the Brethren, reason ATTACK_PIRATE); the battle resolves; no WANTED row is written for the pirates
-- @pass PIR_MONEY       W (purses + companies + funds aboard) is unchanged to the ducat across everything above
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_46() returns numeric language sql as $b$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$b$;

-- a probe's hand on a purse: every reader below takes its mark after this
create function pg_temp.purse(p_port uuid, p_d bigint) returns void language plpgsql as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = 0 where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);
  end if;
end
$b$;

-- she sails to the end of her voyage through the real settle; answers when she got there
create function pg_temp.reach_port(p_fleet uuid) returns timestamptz language plpgsql as $b$
declare
  v_v uuid;
  v_e timestamptz;
begin
  select o.id, o.eta into v_v, v_e from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
  if v_v is null then
    return now();
  end if;
  loop
    perform voyage.settle(p_fleet, v_e);
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING';
    v_e := (select o.eta from public.voyages o where o.id = v_v);
  end loop;
  update public.fleets f set ready_at = null where f.id = p_fleet;   -- port time is a minute of her life and not what this proof reads
  return v_e;
end
$b$;

create function pg_temp.flows(p_mark bigint, p_kind text) returns jsonb language sql as $b$
  select coalesce(jsonb_agg(jsonb_build_array(p.code, f.ducats) order by f.ducats, p.code), '[]'::jsonb)
    from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark and f.kind = p_kind
$b$;

-- a path of p_days voyage-days, every day in sea p_sea (0 nm of real water: the voyage engine reads nm, the sea and the frozen keys)
create function pg_temp.through(p_fleet uuid, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', round(voyage.fleet_speed(p_fleet) * 24, 2), 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

-- ── the sea on one setting (proof 37's and 38's stub): '' quiet, 'PIRATES' a raid of magnitude 0.5, 'REAL' the real roll ──
do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_46;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  if v_s = 'REAL' then
    return query select * from voyage.hazard_roll_real_46(p_voyage, p_day);
    return;
  end if;
  return query select v_s <> '', nullif(v_s, ''), 0.5::numeric, 1::numeric;
end
$b$
  $f$;
end
$$;

do $$
declare
  v_t     timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' + interval '2 hours';   -- 02:00 UTC today: every offset below stays inside one UTC day (the spend book is by UTC day)
  v_w0    numeric;
  v_pir   uuid;
  v_por   uuid;
  v_lis   uuid;
  v_prt   uuid;
  v_hum   uuid;
  v_hfl   uuid;
  v_war   uuid;   -- the company's war fleet (an empty hold, guns)
  v_mer   uuid;
  v_cfl   uuid;   -- a crown's cargo ship, the LOOT victim
  v_cpl   uuid;
  v_her   uuid;   -- the pirate ship
  v_house uuid;
  v_yard  uuid;
  v_sea   uuid;   -- her sea
  v_haunt uuid;
  v_voy   uuid;
  v_good  text;
  v_gid   uuid;
  v_mark  bigint;
  v_led   bigint;
  v_ev    bigint;
  v_n     int;
  v_i     int;
  v_r     jsonb;
  v_p     jsonb;
  v_s     text;
  v_cost  bigint := (select c.build_cost from public.ship_classes c where c.code = public.wc_text('pirate_ship_class'));
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_room  bigint;
  v_a     numeric;
  v_b     numeric;
  v_stock numeric;
  v_tgt   numeric;
  v_aboard bigint;
  v_take  bigint;
  v_purse bigint;
  v_hit   boolean;
  v_bat   uuid;
  v_d     numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'navy_enabled', 'pirates_bite', 'attack_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 0, reserve = 0;
  update public.ports p set crew_pool = 500;
  v_pir := public.pirate_nation();
  v_por := public.pirate_capital();
  select g.nation_id, p.id into v_prt, v_lis from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  if v_pir is null or v_por is null or (select p.code from public.ports p where p.id = v_por) <> 'POR' then
    raise exception 'PROOF 46 FAIL: the Brethren or their capital Port Royal are not in this world';
  end if;
  perform pg_temp.purse(v_lis, 50000000);
  insert into public.players (company_name, nation_id, ducats) values ('Proof 46 house', v_prt, 300000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 46 fleet', v_lis);
  perform public.commission_ship(v_hum, v_hfl, 'jacht', 'Proof 46 hull', true, true);   -- a gunless hull: one xebec closes on her (a navire's guns drive it off nine times in ten)
  v_war := public.form_fleet(v_hum, 'Proof 46 war', v_lis);
  perform public.commission_ship(v_hum, v_war, 'navire', 'Proof 46 guns', true, true);
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id = v_war;
  update public.ships s set water_t = 20, food_t = 20 where s.fleet_id = v_hfl;   -- room in her hold for a parcel; enough for her two-day probes
  v_mer := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  perform pg_temp.purse(v_por, 300000000);   -- a hoard that COULD build, so a job that built dark would be seen

  -- ── OFF ──
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_ev := (select count(*) from public.events);
  v_r := public.tick_pirates(v_t);
  if v_r <> jsonb_build_object('steps', '{}'::jsonb, 'pressure', 0, 'added', null, 'paid', 0) or public.pirates_on()
     or exists (select 1 from public.pirate_ships) or exists (select 1 from public.pirate_spend_day) or exists (select 1 from public.sea_pressure)
     or exists (select 1 from public.treasury_flows f where f.id > v_mark) or (select count(*) from public.events) <> v_ev then
    raise exception 'PROOF 46 FAIL: off, the job wrote something: %', v_r;
  end if;
  v_sea := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  v_p := pg_temp.through(v_hfl, v_sea, 2);
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t);
  if (select o.path from public.voyages o where o.id = v_voy)::text <> voyage.freeze_danger(v_p, v_t)::text or (select o.path -> 0 ? 'raider' from public.voyages o where o.id = v_voy) then
    raise exception 'PROOF 46 FAIL: off, a departure''s path is not freeze_danger''s byte for byte';
  end if;
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform voyage.settle(v_hfl, voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
  if v_r is null or v_r ? 'pirate' or (v_r ->> 'raider')::numeric <> round(voyage.leg_danger(v_p -> 0) * 40 * (0.5 + 0.5), 2) then
    raise exception 'PROOF 46 FAIL: off, a PIRATES day is not today''s anonymous raid: %', v_r;
  end if;
  perform pg_temp.reach_port(v_hfl);
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id) where s.fleet_id = v_hfl;
  if public.fleet_kind(v_hfl) <> 'COMPANY' or public.fleet_kind(v_mer) <> 'MERCHANT' or public.fleet_origin(v_hfl) is not null or public.fleet_origin(v_mer) is null
     or public.crown_house(v_hum) or exists (select 1 from public.sea_houses() h where h.kind = 'PIRATE') or public.cargo_figures() ? 'pirate_ships' then
    raise exception 'PROOF 46 FAIL: off, a kind, an origin, a house or the sea moved';
  end if;
  begin
    perform world.pirate_ship_card(v_hfl);
    raise exception 'PROOF 46 FAIL: the card served a company';
  exception when others then
    if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
  end;
  raise notice 'PASS: PIR_DARK — nothing written, the path is freeze_danger''s, the raid anonymous at %', v_r ->> 'raider';

  -- ── THE SWITCH WITH NO PURSES ──
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  v_r := public.tick_pirates(v_t);
  if public.pirates_on() or v_r -> 'added' <> 'null'::jsonb or exists (select 1 from public.pirate_ships) then
    raise exception 'PROOF 46 FAIL: with no purses the knob lit something: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  raise notice 'PASS: PIR_NEEDS_PURSES — nothing';

  -- ── BROKE: a hoard at 0 ──
  perform pg_temp.purse(v_por, 0);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_ev := (select count(*) from public.events);
  v_r := public.tick_pirates(v_t);
  if public.pirate_hoard() <> 0 or public.pirate_spend_room(v_t) <> 0 or v_r -> 'added' <> 'null'::jsonb or exists (select 1 from public.pirate_ships)
     or exists (select 1 from public.treasury_flows f where f.id > v_mark) or (select count(*) from public.events) <> v_ev then
    raise exception 'PROOF 46 FAIL: a hoard at 0 built: % (hoard %, room %)', v_r, public.pirate_hoard(), public.pirate_spend_room(v_t);
  end if;
  raise notice 'PASS: PIR_BROKE — hoard 0, room 0, no hull, no flow';

  -- ── SIZE ──
  if public.pirate_size() <> 4 then
    raise exception 'PROOF 46 FAIL: size at hoard 0 is %, not 4', public.pirate_size();
  end if;
  perform pg_temp.purse(v_por, 300000000);
  v_w0 := pg_temp.w_46();   -- the mark: after the probe's own hand on the purses, before anything of the file moves gold
  if public.pirate_hoard() <> 300000000 or public.pirate_size() <> 7 or public.pirate_spend_room(v_t) <> 1500000 then
    raise exception 'PROOF 46 FAIL: hoard % size % room %', public.pirate_hoard(), public.pirate_size(), public.pirate_spend_room(v_t);
  end if;
  raise notice 'PASS: PIR_SIZE — 4 at 0, 7 at 300 M, room 1,500,000';

  -- ── BUILD ──
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_led := (select count(*) from public.ledger);
  v_yard := public.refit_yard(v_por);
  v_r := public.tick_pirates(v_t);
  if v_r ->> 'added' <> 'BUILT' or (select count(*) from public.pirate_ships) <> 1 then
    raise exception 'PROOF 46 FAIL: the hoard did not build: %', v_r;
  end if;
  select n.fleet_id, n.player_id into v_her, v_house from public.pirate_ships n;
  if pg_temp.flows(v_mark, 'BUILD_NAVY') <> jsonb_build_array(jsonb_build_array('POR', -v_cost), jsonb_build_array((select p.code from public.ports p where p.id = v_yard), v_cost))
     or (select count(*) from public.treasury_flows f where f.id > v_mark) <> 2 or (select count(*) from public.ledger) <> v_led then
    raise exception 'PROOF 46 FAIL: the build is not one class, capital to the yard, moved: %', pg_temp.flows(v_mark, 'BUILD_NAVY');
  end if;
  if (select count(*) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_her and c.code = public.wc_text('pirate_ship_class') and s.crew = 0 and s.is_flagship) <> 1
     or (select count(*) from public.ships s where s.fleet_id = v_her) <> 1
     or (select f.port_id from public.fleets f where f.id = v_her) <> v_por
     or (select p.nation_id = v_pir and p.ducats = 0 and p.is_npc from public.players p where p.id = v_house) is not true
     or (select n.ord = 1 and n.home_port = v_por and n.sea_id is null and n.mission = 'HOME' and n.laid_up_at is null from public.pirate_ships n where n.fleet_id = v_her) is not true
     or (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date) <> v_cost
     or public.pirate_hoard() <> 300000000 - v_cost
     or public.pirate_spend_room(v_t) <> floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct')) - v_cost then   -- the hoard fell by what it paid, and the room with it
    raise exception 'PROOF 46 FAIL: she is not one crewless hull of the class at her home, her house PIR at 0, the spend written';
  end if;
  update public.fleets f set ready_at = v_t + interval '1 day' where f.id = v_her;   -- her port time: she stays for the next checks
  v_r := public.tick_pirates(v_t + interval '1 minute');
  if v_r -> 'added' <> 'null'::jsonb or (select count(*) from public.pirate_ships) <> 1 or v_r -> 'steps' <> '{}'::jsonb then
    raise exception 'PROOF 46 FAIL: two ships in a day: %', v_r;
  end if;
  raise notice 'PASS: PIR_BUILD — % d. POR -> %, one xebec at Port Royal, one a day', v_cost, (select p.code from public.ports p where p.id = v_yard);

  -- ── THE ONE CAP (W18's shape: a payee house) ──
  v_room := public.pirate_spend_room(v_t);
  v_purse := (select p.ducats from public.players p where p.id = v_hum);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  if public.pirate_pay('NPC_FOUND', v_room + 1, v_t, null, v_hum) <> 0 or (select p.ducats from public.players p where p.id = v_hum) <> v_purse
     or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 46 FAIL: a payee was paid above the room';
  end if;
  v_take := public.pirate_pay('NPC_FOUND', 1000000, v_t, null, v_hum);
  if v_take <> 1000000 or (select p.ducats from public.players p where p.id = v_hum) <> v_purse + 1000000
     or public.pirate_spend_room(v_t) <> floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct')) - (v_cost + 1000000)
     or (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date) <> v_cost + 1000000
     or pg_temp.flows(v_mark, 'NPC_FOUND') <> jsonb_build_array(jsonb_build_array('POR', -1000000)) then
    raise exception 'PROOF 46 FAIL: a payee inside the room was not paid whole from the capital: paid %, purse % (was %), room % -> %, spent %, flows %',
      v_take, (select p.ducats from public.players p where p.id = v_hum), v_purse, v_room, public.pirate_spend_room(v_t),
      (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date), pg_temp.flows(v_mark, 'NPC_FOUND');
  end if;
  if public.pirate_pay('NPC_FOUND', v_room - 1000000 + 1, v_t, null, v_hum) <> 0 or public.pirate_pay('BUILD_NAVY', 0, v_t, v_yard, null) <> 0 or public.pirate_pay('BUILD_NAVY', 10, v_t, null, null) <> 0 then
    raise exception 'PROOF 46 FAIL: the room was overdrawn, or a nothing was paid';
  end if;
  -- the capital's reserve: a room that allows and a surplus that does not pays nothing
  update public.port_treasury t set reserve = public.treasury_balance(v_por) - 10 where t.port_id = v_por;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_take := public.pirate_pay('NPC_FOUND', 1000, v_t, null, v_hum);
  if v_take <> 0 or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 46 FAIL: the capital paid below its reserve: %', v_take;
  end if;
  update public.port_treasury t set reserve = 0 where t.port_id = v_por;
  if pg_temp.w_46() <> v_w0 then
    raise exception 'PROOF 46 FAIL: W moved by the build or the pay: % -> %', v_w0, pg_temp.w_46();
  end if;
  raise notice 'PASS: PIR_SPEND — whole or nothing, the room % -> %', v_room, public.pirate_spend_room(v_t);

  -- ── KIND ──
  if public.fleet_kind(v_her) is distinct from 'PIRATE' or public.fleet_origin(v_her) is distinct from v_por or not public.crown_house(v_house) or public.crown_nation(v_her) is distinct from v_pir
     or public.fleet_wage(v_her, false, 35) <> 0 or public.port_fee(v_lis, v_house, 100000) <> 0
     or (select h.kind from public.sea_houses() h where h.player_id = v_house) <> 'PIRATE'
     or public.fleet_kind(v_hfl) <> 'COMPANY' or public.fleet_kind(v_mer) <> 'MERCHANT' or public.crown_house(v_hum) or public.fleet_wage(v_hfl, false) <= 0
     or (public.cargo_figures() ->> 'pirate_ships')::int <> 1
     or not exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_her::text and e ->> 'kind' = 'PIRATE') then
    raise exception 'PROOF 46 FAIL: the kind, the origin, the house, the wage, the fee or the sea';
  end if;
  raise notice 'PASS: PIR_KIND — PIRATE, home Port Royal, a crown house, no wage, no fee, on the sea';

  -- ── CRUISE ──
  select h.port_id, h.sea_id into v_haunt, v_sea from public.pirate_haunt_of(v_por, 1) h;
  if v_haunt is null then
    raise exception 'PROOF 46 FAIL: Port Royal has no haunt in reach';
  end if;
  if (select voyage.sea_danger(p.sea_id, null) from public.ports p where p.id = v_haunt)
     < (select max(voyage.sea_danger(p.sea_id, null)) from public.npc_courses c join public.ports p on p.id = c.to_port where c.from_port = v_por and c.nm <= public.wc_num('navy_reach_nm')
          and exists (select 1 from public.npc_courses b where b.from_port = c.to_port and b.to_port = v_por)) then
    raise exception 'PROOF 46 FAIL: the haunt is not the most dangerous sea in reach';
  end if;
  update public.fleets f set ready_at = null where f.id = v_her;
  v_r := public.tick_pirates(v_t + interval '2 minutes');
  if v_r -> 'steps' <> '{"SAILED": 1}'::jsonb
     or (select n.sea_id = v_sea and n.mission = 'CRUISE' and n.haunt_port = v_haunt and n.last_port = v_por from public.pirate_ships n where n.fleet_id = v_her) is not true
     or (select f.status from public.fleets f where f.id = v_her) <> 'SAILING'
     or (select v.dest_port_id from public.voyages v where v.fleet_id = v_her and v.status = 'SAILING') <> v_haunt
     or public.pirate_ship_in_sea(v_sea) <> v_her
     or (select s.crew from public.ships s where s.fleet_id = v_her) <= 0 then
    raise exception 'PROOF 46 FAIL: she did not sail for her haunt: %', v_r;
  end if;
  if exists (select 1 from public.voyages v cross join lateral jsonb_array_elements(v.path) e where v.fleet_id = v_her and v.status = 'SAILING' and e ? 'raider') then
    raise exception 'PROOF 46 FAIL: her own voyage names a raider';
  end if;
  raise notice 'PASS: PIR_CRUISE — for % in sea %, named in it', (select p.code from public.ports p where p.id = v_haunt), (select s.code from public.seas s where s.id = v_sea);

  -- ── PRESSURE ──
  v_d := (select s.piracy_index from public.seas s where s.id = v_sea);
  if (select sp.value from public.sea_pressure sp where sp.sea_id = v_sea) <> public.wc_num('pirate_pressure') or (select count(*) from public.sea_pressure) <> 1
     or voyage.sea_danger(v_sea, v_t + interval '2 minutes') <> round(least(1, v_d * (1 + public.wc_num('pirate_pressure'))), 4) or voyage.sea_danger(v_sea, null) <> v_d then
    raise exception 'PROOF 46 FAIL: her sea carries no pressure, or the figure is wrong: % vs %', voyage.sea_danger(v_sea, v_t + interval '2 minutes'), round(least(1, v_d * 1.5), 4);
  end if;
  raise notice 'PASS: PIR_PRESSURE — % x 1.5 = %', v_d, voyage.sea_danger(v_sea, v_t + interval '2 minutes');

  -- ── THE RAID: a company's fleet leaves while she cruises; a real PIRATES day; plundered, the goods stow at her home ──
  v_good := (select g.code from public.goods g join public.port_goods pg on pg.good_id = g.id where pg.port_id = v_por order by g.code limit 1);
  v_gid := (select g.id from public.goods g where g.code = v_good);
  update public.port_goods pg set stock = greatest(0, 2 * pg.stock_target - 3) where pg.port_id = v_por and pg.good_id = v_gid;
  select pg.stock, pg.stock_target into v_stock, v_tgt from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid;
  v_hit := false;
  for v_i in 1 .. 40 loop
    update public.ships s set water_t = 20, food_t = 20 where s.fleet_id = v_hfl;
    perform public.fleet_load(v_hfl, v_good, 30, 10);
    update public.ships s set crew = 0, durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_hfl;
    if public.fleet_cargo_qty(v_hfl, v_good) <> 30 then
      raise exception 'PROOF 46 FAIL: the probe hull did not take her load: % aboard, cargo %', public.fleet_cargo_qty(v_hfl, v_good), (select jsonb_agg(s.cargo) from public.ships s where s.fleet_id = v_hfl);
    end if;
    v_p := pg_temp.through(v_hfl, v_sea, 2);
    v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '3 minutes');
    if (select (o.path -> 0 ->> 'raider')::uuid from public.voyages o where o.id = v_voy) is distinct from v_her then
      raise exception 'PROOF 46 FAIL: the frozen segment of her sea does not name her: %', (select o.path -> 0 from public.voyages o where o.id = v_voy);
    end if;
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    perform voyage.settle(v_hfl, voyage.day_ends_at(v_voy, 1));
    perform set_config('byeharu.proof_sea', '', true);
    v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
    if v_r is null or (v_r ->> 'raider')::numeric <> round(voyage.pirate_strength(v_her), 2) or (v_r #>> '{pirate,fleet}')::uuid <> v_her or v_r #>> '{pirate,home}' <> 'POR' then
      raise exception 'PROOF 46 FAIL: the raid is not hers: %', v_r;
    end if;
    perform pg_temp.reach_port(v_hfl);
    perform public.fleet_unload(v_hfl, v_good, public.fleet_cargo_qty(v_hfl, v_good));
    v_n := v_i;
    if v_r ->> 'outcome' in ('PLUNDERED', 'STRIPPED') then
      v_hit := true;
      exit;
    end if;
  end loop;
  if not v_hit then
    raise exception 'PROOF 46 FAIL: 40 raids on a crewless hull and none was plundered';
  end if;
  v_take := (v_r -> 'cargo_lost' ->> v_good)::numeric;
  if v_take < 7 or (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid) <> 2 * v_tgt
     or (v_r -> 'pirate' -> 'stowed' ->> v_good)::numeric <> 2 * v_tgt - v_stock then
    raise exception 'PROOF 46 FAIL: the stow is not capped at 2 x target: took %, stock % -> %, target %, stowed %; the day: %', v_take, v_stock, (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid), v_tgt, v_r #> '{pirate,stowed}', v_r - 'rounds';
  end if;
  raise notice 'PASS: PIR_RAID — raid % of %: % at her strength %, took % %, stowed % (cap 2 x %)', v_n, 40, v_r ->> 'outcome', v_r ->> 'raider', v_take, v_good, v_r -> 'pirate' -> 'stowed' ->> v_good, v_tgt;

  -- ── LOOT: a crown's cargo ship with funds aboard ──
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  perform public.tick_cargo_ships(v_t, v_prt);
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
  select c.fleet_id, c.player_id into v_cfl, v_cpl from public.cargo_ships c where c.nation_id = v_prt order by c.ord limit 1;
  if v_cfl is null then
    raise exception 'PROOF 46 FAIL: no cargo ship of Portugal to rob';
  end if;
  perform pg_temp.reach_port(v_cfl);
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, ready_at = null where f.id = v_cfl;
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id = v_cfl;
  if not exists (select 1 from public.cargo_ship_aboard(v_cfl)) then
    perform public.convoy_book('LOADED', v_cfl, v_cpl, v_lis, 1000000);
  end if;
  select a.aboard into v_aboard from public.cargo_ship_aboard(v_cfl) a;
  v_purse := public.treasury_balance(v_por);
  v_hit := false;
  for v_i in 1 .. 40 loop
    update public.ships s set crew = 0, durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_cfl;
    v_p := pg_temp.through(v_cfl, v_sea, 2);
    v_voy := voyage.depart(v_cfl, v_p, v_lis, v_lis, v_t + interval '4 minutes');
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    perform voyage.settle(v_cfl, voyage.day_ends_at(v_voy, 1));
    perform set_config('byeharu.proof_sea', '', true);
    v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
    perform pg_temp.reach_port(v_cfl);
    if v_r ->> 'outcome' in ('PLUNDERED', 'STRIPPED') then
      v_hit := true;
      exit;
    end if;
  end loop;
  if not v_hit then
    raise exception 'PROOF 46 FAIL: 40 raids on a crewless cargo ship and none was plundered';
  end if;
  v_take := (v_r #>> '{pirate,booked}')::bigint;
  if v_take <= 0 or v_take <> floor(v_aboard * least(1, voyage.plunder_share(v_voy, 1, v_r ->> 'outcome')))
     or public.treasury_balance(v_por) <> v_purse + v_take
     or (select coalesce(a.aboard, 0) from public.cargo_ship_aboard(v_cfl) a) <> v_aboard - v_take
     or (select count(*) from public.convoy_cargo c where c.fleet_id = v_cfl and c.stage = 'LOOTED' and c.ducats = v_take) <> 1
     or not exists (select 1 from public.treasury_flows f where f.port_id = v_por and f.kind = 'LOOT' and f.ducats = v_take) then
    raise exception 'PROOF 46 FAIL: the cargo ship''s gold did not land at her home: booked %, aboard % -> %, purse % -> %', v_take, v_aboard, (select a.aboard from public.cargo_ship_aboard(v_cfl) a), v_purse, public.treasury_balance(v_por);
  end if;
  if pg_temp.w_46() <> v_w0 then
    raise exception 'PROOF 46 FAIL: W moved by the loot: % -> %', v_w0, pg_temp.w_46();
  end if;
  raise notice 'PASS: PIR_LOOT — % of % aboard, LOOTED on her book, LOOT at Port Royal', v_take, v_aboard;

  -- ── RANSOM: through the real settle, a company that is paid off; then the edges ──
  update public.players p set ducats = 50000 where p.id = v_hum;
  v_hit := false;
  for v_i in 1 .. 60 loop
    update public.ships s set water_t = 20, food_t = 20 where s.fleet_id = v_hfl;
    perform public.fleet_load(v_hfl, v_good, 20, 50000);   -- basis 1,000,000: the ransom asks 80,000, the purse holds 50,000
    -- a crew that boards near even: (crew x fight_hand_value 0.15 + tier x 3) by the hull left, against one xebec's (35 x 0.15 + 6); swept 60..149 so the rounds' luck lands in the RANSOM band
    update public.ships s set crew = 60 + (v_i * 13) % 90, durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_hfl;
    v_p := pg_temp.through(v_hfl, v_sea, 2);
    v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '5 minutes');
    v_purse := public.treasury_balance(v_por);
    v_led := (select count(*) from public.ledger l where l.player_id = v_hum and l.kind = 'RANSOM');
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    perform voyage.settle(v_hfl, voyage.day_ends_at(v_voy, 1));
    perform set_config('byeharu.proof_sea', '', true);
    v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
    perform pg_temp.reach_port(v_hfl);
    perform public.fleet_unload(v_hfl, v_good, public.fleet_cargo_qty(v_hfl, v_good));
    v_n := v_i;
    if v_r ->> 'outcome' = 'RANSOM' then
      v_hit := true;
      exit;
    end if;
    if (v_r #>> '{pirate,ransom}')::bigint <> 0 or public.treasury_balance(v_por) <> v_purse then
      raise exception 'PROOF 46 FAIL: a ransom moved on a % day', v_r ->> 'outcome';
    end if;
    update public.players p set ducats = 50000 where p.id = v_hum;
  end loop;
  if not v_hit then
    raise exception 'PROOF 46 FAIL: 60 raids and none was paid off';
  end if;
  if (v_r #>> '{pirate,ransom}')::bigint <> 50000 or (select p.ducats from public.players p where p.id = v_hum) <> 0 or public.treasury_balance(v_por) <> v_purse + 50000
     or (select count(*) from public.ledger l where l.player_id = v_hum and l.kind = 'RANSOM' and l.ducats_delta = -50000) <> v_led + 1
     or not exists (select 1 from public.treasury_flows f where f.port_id = v_por and f.kind = 'RANSOM' and f.ducats = 50000 and f.player_id = v_hum) then
    raise exception 'PROOF 46 FAIL: the ransom is not what the purse held, company to Port Royal: %', v_r #> '{pirate}';
  end if;
  update public.players p set ducats = 1000000 where p.id = v_hum;
  v_purse := public.treasury_balance(v_por);
  v_take := public.pirate_ransom(v_her, v_hum, 1000000, null);
  if v_take <> public.ransom_take(1000000) or (select p.ducats from public.players p where p.id = v_hum) <> 1000000 - public.ransom_take(1000000)
     or public.treasury_balance(v_por) <> v_purse + public.ransom_take(1000000) then
    raise exception 'PROOF 46 FAIL: the direct ransom is not ransom_share of the basis: took % (asked %), purse %, Port Royal % -> %', v_take, public.ransom_take(1000000),
      (select p.ducats from public.players p where p.id = v_hum), v_purse, public.treasury_balance(v_por);
  end if;
  v_purse := public.treasury_balance(v_por);
  perform pg_temp.purse(v_por, public.wc_num('pirate_hoard_cap')::bigint);
  v_take := public.pirate_ransom(v_her, v_hum, 1000000, null);
  v_aboard := public.pirate_loot_book(v_her, v_cfl, 0.5, null);
  if v_take <> 0 or v_aboard <> 0 then
    raise exception 'PROOF 46 FAIL: a hoard at the cap took gold: ransom %, loot %', v_take, v_aboard;
  end if;
  perform pg_temp.purse(v_por, v_purse);
  update public.players p set ducats = 300000 where p.id = v_hum;   -- the probe's purse, set by hand: W is marked again below
  raise notice 'PASS: PIR_RANSOM — raid % of %: 50,000 of the 80,000 asked, company to Port Royal; direct % on 1,000,000; nothing at the cap', v_n, 60, public.ransom_take(1000000);
  v_w0 := pg_temp.w_46();

  -- ── REGEN OFF AT A PIRATE HOME (a stock well under the day's target: Port Royal's depth 0.5 halves its target, and a stock above it is kept whatever the switch, 0263) ──
  update public.port_goods pg set stock = 50 where pg.port_id in (v_por, v_lis) and pg.good_id = v_gid;
  v_stock := (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid);
  v_a := (select pg.stock from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_gid);
  perform public.tick_market_drift(v_t + interval '1 day', v_por);
  perform public.tick_market_drift(v_t + interval '1 day', v_lis);
  if (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid) <> v_stock
     or (select pg.stock from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_gid) <= v_a then
    raise exception 'PROOF 46 FAIL: lit, Port Royal''s stock moved (% -> %) or Lisbon''s did not (% -> %)', v_stock, (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid), v_a, (select pg.stock from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_gid);
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  perform public.tick_market_drift(v_t + interval '2 days', v_por);
  if (select pg.stock from public.port_goods pg where pg.port_id = v_por and pg.good_id = v_gid) <= v_stock then
    raise exception 'PROOF 46 FAIL: off, Port Royal''s stock did not regenerate';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  raise notice 'PASS: PIR_REGEN — lit, Port Royal held at %, Lisbon moved; off, Port Royal moved', v_stock;

  -- ── PAY: she docks at her haunt; an hour of upkeep goes there ──
  perform pg_temp.reach_port(v_her);
  if (select f.port_id from public.fleets f where f.id = v_her) <> v_haunt then
    raise exception 'PROOF 46 FAIL: she did not reach her haunt';
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_room := (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date);
  v_take := public.pirate_pay_hour(v_t + interval '1 hour');
  if v_take <> v_slice
     or pg_temp.flows(v_mark, 'NAVY_PAY') <> jsonb_build_array(jsonb_build_array('POR', -v_slice), jsonb_build_array((select p.code from public.ports p where p.id = v_haunt), v_slice))
     or (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date) <> v_room + v_slice
     or public.pirate_spend_room(v_t) <> floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct')) - (v_room + v_slice)
     or (select n.unpaid_since from public.pirate_ships n where n.fleet_id = v_her) is not null then
    raise exception 'PROOF 46 FAIL: the hour''s pay: paid % (slice %), flows %, spent % -> %, room % against %, unpaid %', v_take, v_slice, pg_temp.flows(v_mark, 'NAVY_PAY'), v_room,
      (select d.spent from public.pirate_spend_day d where d.day = (v_t at time zone 'UTC')::date), public.pirate_spend_room(v_t),
      floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct')) - (v_room + v_slice), (select n.unpaid_since from public.pirate_ships n where n.fleet_id = v_her);
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_take := public.pirate_pay_hour(v_t + interval '90 minutes');   -- (a volatile call is never a term of an `if`: SQL may read the other terms first)
  if v_take <> 0 or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 46 FAIL: paid twice in an hour';
  end if;
  update public.pirate_ships n set last_port = v_por where n.fleet_id = v_her;
  update public.fleets f set port_id = v_por where f.id = v_her;
  v_take := public.pirate_pay_hour(v_t + interval '3 hours');
  if v_take <> 0 or exists (select 1 from public.treasury_flows f where f.id > v_mark) or (select n.unpaid_since from public.pirate_ships n where n.fleet_id = v_her) is not null then
    raise exception 'PROOF 46 FAIL: at the capital something moved, or she was marked unpaid';
  end if;
  update public.fleets f set port_id = v_haunt where f.id = v_her;
  update public.pirate_ships n set last_port = v_haunt where n.fleet_id = v_her;
  -- unpaid: the hoard cannot pay; she goes home and is laid up; money back, she wakes
  v_purse := public.treasury_balance(v_por);   -- the probe's hand on the purse is put back exactly, so W reads the file's moves alone
  perform pg_temp.purse(v_por, 0);
  v_take := public.pirate_pay_hour(v_t + interval '5 hours');
  if v_take <> 0 or (select n.unpaid_since from public.pirate_ships n where n.fleet_id = v_her) is null then
    raise exception 'PROOF 46 FAIL: a hoard at 0 paid (%), or she was not marked unpaid', v_take;
  end if;
  update public.fleets f set ready_at = null where f.id = v_her;
  v_s := public.pirate_ship_step(v_her, v_t + interval '5 hours');
  if v_s <> 'SAILED' or (select v.dest_port_id from public.voyages v where v.fleet_id = v_her and v.status = 'SAILING') <> v_por
     or (select n.sea_id is null and n.mission = 'HOME' from public.pirate_ships n where n.fleet_id = v_her) is not true then
    raise exception 'PROOF 46 FAIL: unpaid, she did not sail home: %', v_s;
  end if;
  perform pg_temp.reach_port(v_her);
  v_s := public.pirate_ship_step(v_her, v_t + interval '6 hours');
  if v_s <> 'LAID_UP' or (select n.laid_up_at from public.pirate_ships n where n.fleet_id = v_her) is null
     or exists (select 1 from public.sea_houses() h where h.player_id = v_house) or exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_her::text) then
    raise exception 'PROOF 46 FAIL: unpaid at home she was not laid up and off the sea: %', v_s;
  end if;
  perform pg_temp.purse(v_por, v_purse);
  update public.pirate_clock set added_at = null;
  v_r := public.tick_pirates(v_t + interval '7 hours');
  if v_r ->> 'added' <> 'WOKEN' or (select count(*) from public.pirate_ships) <> 1 or (select n.laid_up_at is null and n.unpaid_since is null from public.pirate_ships n where n.fleet_id = v_her) is not true then
    raise exception 'PROOF 46 FAIL: money back, she did not wake: %', v_r;
  end if;
  raise notice 'PASS: PIR_PAY — % d. to %, once an hour, nothing at the capital; unpaid she went home and was laid up; woken', v_slice, (select p.code from public.ports p where p.id = v_haunt);

  -- ── OFF with her out ──
  update public.fleets f set ready_at = null where f.id = v_her;
  v_r := public.tick_pirates(v_t + interval '8 hours');
  if v_r -> 'steps' <> '{"SAILED": 1}'::jsonb or (select n.sea_id from public.pirate_ships n where n.fleet_id = v_her) is distinct from v_sea then
    raise exception 'PROOF 46 FAIL: woken, she did not sail for her haunt: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_bite';
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_pirates(v_t + interval '8 hours 1 minute');
  v_p := pg_temp.through(v_hfl, v_sea, 1);
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '8 hours 2 minutes');
  if (select o.path -> 0 ? 'raider' from public.voyages o where o.id = v_voy) or exists (select 1 from public.sea_pressure) or v_r -> 'added' <> 'null'::jsonb or (v_r ->> 'paid')::bigint <> 0 then
    raise exception 'PROOF 46 FAIL: off, a departure named her, the pressure stood, or the job paid: %', v_r;
  end if;
  perform pg_temp.reach_port(v_hfl);
  perform pg_temp.reach_port(v_her);
  v_s := public.pirate_ship_step(v_her, v_t + interval '9 hours');
  if v_s <> 'SAILED' or (select v.dest_port_id from public.voyages v where v.fleet_id = v_her and v.status = 'SAILING') <> v_por then
    raise exception 'PROOF 46 FAIL: off, at her haunt she did not sail home: %', v_s;
  end if;
  perform pg_temp.reach_port(v_her);
  v_s := public.pirate_ship_step(v_her, v_t + interval '10 hours');
  if v_s <> 'LAID_UP' or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind in ('NAVY_PAY', 'BUILD_NAVY', 'LOOT', 'RANSOM')) then
    raise exception 'PROOF 46 FAIL: off, at home she was not laid up, or the pirates paid or took something: %', v_s;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  raise notice 'PASS: PIR_OFF — home, laid up, nobody named, nothing paid';

  -- ── WRECK ──
  update public.pirate_ships n set laid_up_at = null, unpaid_since = null where n.fleet_id = v_her;
  update public.ships s set durability = 0 where s.fleet_id = v_her;
  update public.fleets f set status = 'UNABLE_TO_SAIL', ready_at = null where f.id = v_her;
  v_s := public.pirate_ship_step(v_her, v_t + interval '11 hours');
  if v_s <> 'IN_PORT' or (select f.status = 'DOCKED' and f.ready_at > v_t + interval '11 hours' from public.fleets f where f.id = v_her) is not true
     or (select s.durability from public.ships s where s.fleet_id = v_her) <= 0 then
    raise exception 'PROOF 46 FAIL: refits dark, she was not patched free: %', v_s;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  update public.ships s set durability = 0 where s.fleet_id = v_her;
  update public.fleets f set status = 'UNABLE_TO_SAIL', ready_at = null where f.id = v_her;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_s := public.pirate_ship_step(v_her, v_t + interval '12 hours');
  v_a := (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'REFIT' and f.port_id = v_por);
  perform public.npc_refit_step(v_her, v_t + interval '12 hours');
  v_a := (select coalesce(-sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'REFIT' and f.port_id = v_por);
  if v_s <> 'WRECK' or v_a <= 0 or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'REFIT') <> 0 then
    raise exception 'PROOF 46 FAIL: refits lit, her home did not pay the refit, moved: % (% d.)', v_s, v_a;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  raise notice 'PASS: PIR_WRECK — patched free dark; lit, Port Royal paid % d. REFIT, moved', v_a;

  -- ── CARD ──
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_her;
  update public.fleets f set status = 'DOCKED', port_id = v_por, ready_at = null where f.id = v_her;
  update public.pirate_ships n set sea_id = null, mission = 'HOME', haunt_port = null, haunt_since = null where n.fleet_id = v_her;
  v_s := public.pirate_ship_step(v_her, v_t + interval '13 hours');
  v_r := world.pirate_ship_card(v_her);
  if v_s <> 'SAILED' or v_r ->> 'home' <> 'POR' or v_r ->> 'mission' <> 'CRUISE' or v_r ->> 'haunt' <> (select p.code from public.ports p where p.id = v_haunt) or v_r ->> 'nation_code' <> 'PIR'
     or (v_r ->> 'laid_up')::boolean or v_r ->> 'to' <> (select p.code from public.ports p where p.id = v_haunt) or jsonb_array_length(v_r -> 'ships') <> 1 or v_r ? 'attack'
     or (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'pirate_ship_card') <> 1 then
    raise exception 'PROOF 46 FAIL: the card: %', v_r;
  end if;
  raise notice 'PASS: PIR_CARD — home POR, haunt %, CRUISE, one hull', v_r ->> 'haunt';

  -- ── ATTACK: a war fleet at sea beside her ──
  update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'regard_enabled');
  perform pg_temp.reach_port(v_her);
  update public.fleets f set ready_at = null where f.id in (v_her, v_war);
  v_voy := voyage.depart(v_her, pg_temp.through(v_her, v_sea, 3), v_haunt, v_por, v_t + interval '14 hours');
  v_voy := voyage.depart(v_war, pg_temp.through(v_war, v_sea, 3), v_lis, v_lis, v_t + interval '14 hours');
  v_a := coalesce((select r.points from public.house_regard r where r.player_id = v_hum and r.nation_id = v_pir), 0);
  v_ev := (select count(*) from public.events);
  v_r := public.attack_for(v_hum, v_war, v_her, null, v_t + interval '14 hours 1 minute');
  v_bat := (v_r ->> 'battle_id')::uuid;
  if v_bat is null or v_r ->> 'nation' <> 'PIR'
     or (select r.points from public.house_regard r where r.player_id = v_hum and r.nation_id = v_pir) <> v_a + public.wc_num('regard_pirate')
     or not exists (select 1 from public.events e where e.player_id = v_hum and e.kind = 'REGARD_CHANGED' and e.payload ->> 'reason' = 'ATTACK_PIRATE' and e.payload ->> 'nation' = 'PIR') then
    raise exception 'PROOF 46 FAIL: the attack door: %', v_r;
  end if;
  perform public.tick_battles(v_t + interval '14 hours 12 minutes');
  if (select b.status from public.battles b where b.id = v_bat) <> 'RESOLVED' or exists (select 1 from public.wanted w where w.nation_id = v_pir) then
    raise exception 'PROOF 46 FAIL: the battle did not resolve, or the pirates wrote a WANTED row';
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled');
  raise notice 'PASS: PIR_ATTACK — % at sea, regard % with the Brethren, resolved, no WANTED', (select b.result ->> 'outcome' from public.battles b where b.id = v_bat), public.wc_num('regard_pirate');

  -- ── MONEY ──
  if pg_temp.w_46() <> v_w0 then
    raise exception 'PROOF 46 FAIL: W moved: % -> %', v_w0, pg_temp.w_46();
  end if;
  raise notice 'PASS: PIR_MONEY — W % unchanged across the raid, the pay, the wreck and the attack', v_w0;
end
$$;
