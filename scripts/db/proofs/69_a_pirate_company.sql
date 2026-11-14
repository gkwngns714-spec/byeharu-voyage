-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 69 — A PIRATE COMPANY, PLAYED  (migrations 0380 and 0381; owner row 284: a player may join the pirates, "yes they can"; row 324: "do all, make everything work")
--
--   Proof 45 proves the Brethren as a power and the door's two answers. This one PLAYS a company under the skull through the real commands, in a closed economy with the crowns' regard lit (as production
--   runs), beside a company of a crown: she is founded, she is quoted at her homes and at a crown's harbour, she buys, sails, sells and is taxed, she is offered targets and refused the ones the law forbids,
--   she leaves and may not come back at once. It owns every switch it needs and writes them here, whatever the chain left them at; all of it is rolled back with proof.mjs's transaction.
--   NO OUTCOME OF A ROLL IS ASSERTED: a storm may delay her and a raid may take her cargo. What she is ASKED (the tax rate, the dock fee, the war factor) is asserted from the knobs; what she is PAID is
--   asserted only against what the sale itself reports.
--
-- @pass PIRATE_PICKER    the knob false: the snapshot offers the crowns and not the Brethren, and names the Brethren the pirates (0380's key) on exactly one nation; the knob true: it offers every great power
-- @pass PIRATE_FOUNDED   cmd.found_house under the skull: a company of the Brethren, one fleet docked at Port Royal, the starting money, and every purse plus every company holds the gold it held (Port Royal paid)
-- @pass PIRATE_HOME      at each of the four homes she is asked tax 0 and dock fee 0, as a crown's company is; her stance there is home
-- @pass PIRATE_AT_WAR    at a crown's harbour her stance is war with every crown, her dues factor is the war factor times her regard band's factor (both read from the knobs), her tax rate and dock fee are above a home company's and never under any other company's
-- @pass PIRATE_TRADES    she buys at Port Royal untaxed, sails to a crown's harbour through the real voyage, and what she still carries she sells: the sale's own tax is public.profit_tax at her rate, and her purse moves by the sale's net
-- @pass PIRATE_NO_PVP    attacks lit: she is refused a company as a target and a company is refused her (E_HUMAN_TARGET, both ways); a merchant is no target (E_NOT_A_TARGET); a ship of the Brethren is her own country's (E_YOUR_OWN_COUNTRY)
-- @pass PIRATE_LEAVES    she changes country to a crown at once (her first change) and is no longer at war there; going back is refused E_TOO_SOON; the knob false again: she stays what she is, and a new founding under the skull is refused E_MINOR_POWER
-- ═══════════════════════════════════════════════════════════════════════════════

-- 0413 (a game day lasts one hour): this proof's instants and amounts are written on the clock as it was before 0413 (the length of a market day, a drift
-- slot and a population step; the drift job's spread; the rates per real day). So the rate is moved back through its one door, public.clock_set, and the
-- anchors are emptied, inside this proof's own rolled-back transaction. What 0413 itself does is proof 110's.
do $c$ begin perform public.clock_set(960, now()); update public.world_config set value = '{}'::jsonb where key in ('clock_anchor', 'market_clock_anchor'); end $c$;
create function pg_temp.w_69() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;

do $$
declare
  c_uid_p constant uuid := '00000000-0f69-4000-8000-000000000001';
  c_uid_c constant uuid := '00000000-0f69-4000-8000-000000000002';
  c_uid_x constant uuid := '00000000-0f69-4000-8000-000000000003';
  v_pir   uuid := (select g.nation_id from public.great_powers g where g.pirate);
  v_code  text := (select n.code from public.nations n join public.great_powers g on g.nation_id = n.id where g.pirate);
  v_por   uuid := (select p.id from public.ports p join public.nations n on n.capital_port_code = p.code join public.great_powers g on g.nation_id = n.id where g.pirate);
  v_hav   uuid := (select p.id from public.ports p where p.code = 'HAV');
  v_crown uuid;
  v_ccode text;
  v_me    uuid;
  v_ctl   uuid;
  v_fl    uuid;
  v_cfl   uuid;
  v_r     jsonb;
  v_x     jsonb;
  v_w0    numeric;
  v_w1    numeric;
  v_good  text;
  v_gid   uuid;
  v_p0    bigint;
  v_p1    bigint;
  v_n     int;
  v_tax   numeric;
  v_ctax  numeric;
  v_war   numeric;
  v_band  numeric;
  v_voy   record;
  v_have  numeric;
  v_t     uuid;
  h       record;
begin
  if v_pir is null or v_por is null or v_hav is null then
    raise exception 'PROOF 69 FAIL: this world has no pirate power with a capital, or no Havana';
  end if;
  v_crown := public.port_nation(v_hav);
  if v_crown is null or public.pirate_power(v_crown) or not public.great_power(v_crown) then
    raise exception 'PROOF 69 FAIL: Havana is not held by a crown in this world; the proof needs a crown harbour a course reaches from Port Royal';
  end if;
  v_ccode := (select n.code from public.nations n where n.id = v_crown);
  -- the control: a company of the crown that holds Havana, founded while the economy is open (the world's purses are empty here)
  v_ctl := public.new_house(c_uid_c, 'Casa de Control 0f69', v_ccode, (select n.capital_port_code from public.nations n where n.id = v_crown));
  v_cfl := (select f.id from public.fleets f where f.player_id = v_ctl);
  -- the switches production runs on, and the two this proof is about; every one written here, whatever the chain left
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed', 'regard_enabled', 'pirate_ports_free');
  update public.world_config set value = 'false'::jsonb where key in ('pirates_joinable', 'attack_enabled');
  update public.port_treasury set ducats = 100000000 where port_id in (v_por, v_hav);   -- Port Royal pays the founding; Havana must be able to pay for her cargo

  -- ── THE PICKER ──
  v_x := world.snapshot() -> 'nations';
  if (select count(*) from jsonb_array_elements(v_x) e where (e ->> 'pirate')::boolean) <> 1
     or (select e ->> 'code' from jsonb_array_elements(v_x) e where (e ->> 'pirate')::boolean) <> v_code
     or exists (select 1 from jsonb_array_elements(v_x) e where (e ->> 'joinable')::boolean and (e ->> 'pirate')::boolean)
     or (select count(*) from jsonb_array_elements(v_x) e where (e ->> 'joinable')::boolean) <> (select count(*) from public.great_powers g where not g.pirate) then
    raise exception 'PROOF 69 FAIL: knob false, the snapshot does not offer the crowns alone and name one pirate power';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'pirates_joinable';
  v_x := world.snapshot() -> 'nations';
  if (select count(*) from jsonb_array_elements(v_x) e where (e ->> 'joinable')::boolean) <> (select count(*) from public.great_powers)
     or not (select (e ->> 'joinable')::boolean from jsonb_array_elements(v_x) e where (e ->> 'pirate')::boolean) then
    raise exception 'PROOF 69 FAIL: knob true, the snapshot does not offer every great power';
  end if;
  raise notice 'PASS: PIRATE_PICKER — knob false: % crowns offered, the Brethren named the pirates and not offered; knob true: % offered', (select count(*) from public.great_powers g where not g.pirate), (select count(*) from public.great_powers);

  -- ── FOUNDED ──
  v_w0 := pg_temp.w_69();
  perform cmd.assume_identity(c_uid_p);
  v_r := cmd.found_house('Skull Company 0f69', v_code);
  if (v_r ->> 'ok') is distinct from 'true' then
    raise exception 'PROOF 69 FAIL: found_house under the skull answered %', v_r;
  end if;
  v_me := (v_r ->> 'player_id')::uuid;
  v_fl := (select f.id from public.fleets f where f.player_id = v_me);
  v_w1 := pg_temp.w_69();
  if (select pl.nation_id from public.players pl where pl.id = v_me) <> v_pir
     or (select count(*) from public.fleets f where f.player_id = v_me and f.port_id = v_por and f.status = 'DOCKED') <> 1
     or (select pl.ducats from public.players pl where pl.id = v_me) <> public.wc_int('starting_ducats')
     or (world.player() -> 'player' ->> 'nation') <> v_code or (world.player() -> 'player' ->> 'lying_at') <> (select p.code from public.ports p where p.id = v_por)
     or v_w1 <> v_w0 then
    raise exception 'PROOF 69 FAIL: the company is not a company of the Brethren docked at Port Royal with the starting money, or gold was made: W % -> %', v_w0, v_w1;
  end if;
  raise notice 'PASS: PIRATE_FOUNDED — a company of the Brethren, one fleet docked at Port Royal, % d., paid by Port Royal (W unchanged)', public.wc_int('starting_ducats');

  -- ── HOME ──
  for h in select p.id, p.code from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = v_pir and public.port_is_free(p.id) order by p.code loop
    if world.tax_rate(h.id, v_me) <> 0 or public.port_fee(h.id, v_me, 40000) <> 0 or world.tax_rate(h.id, v_ctl) <> 0 or public.port_fee(h.id, v_ctl, 40000) <> 0
       or (public.port_dues(h.id, v_me, 40000) -> 'dues' ->> 'stance') <> 'home' then
      raise exception 'PROOF 69 FAIL: at her home % she is asked tax % and fee %, or her stance is not home', h.code, world.tax_rate(h.id, v_me), public.port_fee(h.id, v_me, 40000);
    end if;
    v_n := coalesce(v_n, 0) + 1;
  end loop;
  if coalesce(v_n, 0) <> 4 then
    raise exception 'PROOF 69 FAIL: the Brethren hold % free homes, not four', coalesce(v_n, 0);
  end if;
  raise notice 'PASS: PIRATE_HOME — at the four homes she is asked tax 0 and dock fee 0, as the crown''s company is; her stance is home';

  -- ── AT WAR ──
  if exists (select 1 from public.great_powers g where not g.pirate and public.power_stance(v_pir, g.nation_id) <> 'war') then
    raise exception 'PROOF 69 FAIL: the Brethren are not at war with every crown';
  end if;
  v_war  := (public.wc('country_tax_factor') ->> 'war')::numeric;
  v_band := (public.regard_band(public.regard_of(v_me, v_crown)) ->> 'factor')::numeric;
  v_x := public.port_dues(v_hav, v_me, 40000) -> 'dues';
  v_tax  := world.tax_rate(v_hav, v_me);
  v_ctax := world.tax_rate(v_hav, v_ctl);
  if (v_x ->> 'stance') <> 'war' or (v_x ->> 'factor')::numeric <> v_war * v_band
     or public.regard_of(v_me, v_crown) <> (public.wc('regard_stance_base') ->> 'war')::numeric
     or not (v_tax > v_ctax) or not (public.port_fee(v_hav, v_me, 40000) > public.port_fee(v_hav, v_ctl, 40000))
     or exists (select 1 from public.players pl where not pl.is_npc and pl.id <> v_me and world.tax_rate(v_hav, pl.id) > v_tax) then
    raise exception 'PROOF 69 FAIL: at % her dues are %, tax % against the home company''s %; wanted war, factor % x %', v_ccode, v_x, v_tax, v_ctax, v_war, v_band;
  end if;
  if (select count(*) from jsonb_array_elements(world.levels() -> 'regard') e) <> (select count(*) from public.great_powers g where not g.pirate)
     or exists (select 1 from jsonb_array_elements(world.levels() -> 'regard') e where (e ->> 'score')::numeric <> (public.wc('regard_stance_base') ->> 'war')::numeric) then
    raise exception 'PROOF 69 FAIL: her Levels page does not list every crown at the war base: %', world.levels() -> 'regard';
  end if;
  raise notice 'PASS: PIRATE_AT_WAR — at % stance war, dues factor % (war % x band %), tax % against a home company''s %; every crown at the war base on her Levels page', v_ccode, v_war * v_band, v_war, v_band, v_tax, v_ctax;

  -- ── SHE TRADES ──
  select e ->> 'code', (e ->> 'good_id')::uuid into v_good, v_gid
    from jsonb_array_elements(world.market(v_por) -> 'goods') e
   where (e ->> 'offered')::boolean and (e ->> 'available')::boolean and (e ->> 'stock')::numeric >= 20
     and exists (select 1 from public.port_goods pg where pg.port_id = v_hav and pg.good_id = (e ->> 'good_id')::uuid)
   order by (e ->> 'buy')::numeric limit 1;
  if v_good is null then
    raise exception 'PROOF 69 FAIL: Port Royal offers nothing Havana takes';
  end if;
  v_p0 := (select pl.ducats from public.players pl where pl.id = v_me);
  v_r := proof.issue(v_fl, 'BUY ' || v_good || ' 10');
  if (v_r ->> 'ok') is distinct from 'true' or (v_r -> 'order' -> 'result' ->> 'tax_total')::numeric <> 0
     or (select pl.ducats from public.players pl where pl.id = v_me) <> v_p0 - (v_r -> 'order' -> 'result' ->> 'total')::bigint then
    raise exception 'PROOF 69 FAIL: her buy at Port Royal answered %', v_r;
  end if;
  v_r := proof.sail(v_fl, 'HAV');
  if (v_r ->> 'ok') is distinct from 'true' then
    raise exception 'PROOF 69 FAIL: her SAIL for Havana answered %', v_r;
  end if;
  for v_n in 1 .. 60 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING' or (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_hav then
    raise exception 'PROOF 69 FAIL: she did not make Havana: %', (select to_jsonb(f) from public.fleets f where f.id = v_fl);
  end if;
  v_have := coalesce((select sum((s.cargo ->> v_good)::numeric) from public.ships s where s.fleet_id = v_fl), 0);
  if v_have > 0 then
    v_p0 := (select pl.ducats from public.players pl where pl.id = v_me);
    v_r := proof.issue(v_fl, 'SELL ' || v_good || ' ALL');
    v_x := v_r -> 'order' -> 'result';
    v_p1 := (select pl.ducats from public.players pl where pl.id = v_me);
    if (v_r ->> 'ok') is distinct from 'true' or (v_r -> 'order' ->> 'status') <> 'done' then
      raise exception 'PROOF 69 FAIL: her sale at Havana answered %', v_r;
    end if;
    if (v_x ->> 'tax')::numeric <> public.profit_tax(v_hav, (v_x ->> 'profit')::numeric, v_me)
       or ((v_x ->> 'profit')::numeric > 0 and (v_x ->> 'tax')::numeric <= 0)
       or v_p1 - v_p0 <> (v_x ->> 'net')::bigint - coalesce((v_x ->> 'debt_paid')::bigint, 0) then
      raise exception 'PROOF 69 FAIL: her sale at Havana: tax % against public.profit_tax %, purse % -> %, the sale %', v_x ->> 'tax', public.profit_tax(v_hav, (v_x ->> 'profit')::numeric, v_me), v_p0, v_p1, v_x;
    end if;
    raise notice 'PASS: PIRATE_TRADES — bought % untaxed at Port Royal, sailed to Havana, sold % there: profit %, tax % (public.profit_tax at her rate), purse by the net', v_good, v_have, v_x ->> 'profit', v_x ->> 'tax';
  else
    raise notice 'PASS: PIRATE_TRADES — bought % untaxed at Port Royal and sailed to Havana through the real voyage; the sea took her cargo on the way (a roll), so there was no sale to check', v_good;
  end if;

  -- ── NO PVP ──
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  v_r := cmd.preview_attack(v_fl, v_cfl);
  perform cmd.assume_identity(c_uid_c);
  v_x := cmd.preview_attack(v_cfl, v_fl);
  perform cmd.assume_identity(c_uid_p);
  if (v_r ->> 'error_code') is distinct from 'E_HUMAN_TARGET' or (v_x ->> 'error_code') is distinct from 'E_HUMAN_TARGET' then
    raise exception 'PROOF 69 FAIL: a company was not refused as a target, both ways: % / %', v_r, v_x;
  end if;
  select f.id into v_t from public.fleets f join public.npc_houses nh on nh.player_id = f.player_id order by f.id limit 1;
  if v_t is not null and (cmd.preview_attack(v_fl, v_t) ->> 'error_code') is distinct from 'E_NOT_A_TARGET' then
    raise exception 'PROOF 69 FAIL: a merchant was not refused as a target: %', cmd.preview_attack(v_fl, v_t);
  end if;
  -- a ship of the Brethren: a probe row of public.pirate_ships on a probe fleet (the registry's own row: the reader public.crown_nation asks nothing else)
  update public.world_config set value = 'true'::jsonb where key = 'pirates_bite';
  perform public.tick_pirates(now());
  select x.fleet_id into v_t from public.pirate_ships x order by x.fleet_id limit 1;
  if v_t is null then
    raise exception 'PROOF 69 FAIL: with pirates_bite lit and a hoard of 100 M the Brethren laid down no ship to offer her as a target';
  end if;
  v_r := cmd.preview_attack(v_fl, v_t);
  if (v_r ->> 'error_code') is distinct from 'E_YOUR_OWN_COUNTRY' then
    raise exception 'PROOF 69 FAIL: a ship of the Brethren was not refused her as her own country''s: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'pirates_bite');
  raise notice 'PASS: PIRATE_NO_PVP — a company is no target for her and she is none for a company (E_HUMAN_TARGET, both ways); a merchant is none (E_NOT_A_TARGET); a ship of the Brethren is her own country''s (E_YOUR_OWN_COUNTRY)';

  -- ── SHE LEAVES ──
  v_r := cmd.change_country(v_ccode);
  if (v_r ->> 'ok') is distinct from 'true' or (select pl.nation_id from public.players pl where pl.id = v_me) <> v_crown
     or (public.port_dues(v_hav, v_me, 40000) -> 'dues' ->> 'stance') <> 'home' then
    raise exception 'PROOF 69 FAIL: her first change of country answered %', v_r;
  end if;
  v_r := cmd.change_country(v_code);
  if (v_r ->> 'error_code') is distinct from 'E_TOO_SOON' then
    raise exception 'PROOF 69 FAIL: going back under the skull at once answered %', v_r;
  end if;
  -- the knob false again: a company of the Brethren stays one; nobody new is let in
  update public.players set nation_id = v_pir where id = v_me;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable';
  perform cmd.assume_identity(c_uid_x);
  v_r := cmd.found_house('Late Company 0f69', v_code);
  perform cmd.assume_identity(c_uid_p);
  if (v_r ->> 'error_code') is distinct from 'E_MINOR_POWER' or (world.player() -> 'player' ->> 'nation') <> v_code
     or (public.port_dues(v_por, v_me, 40000) -> 'dues' ->> 'stance') <> 'home' then
    raise exception 'PROOF 69 FAIL: the knob false again: a new founding answered %, or the company that joined is no longer of the Brethren', v_r;
  end if;
  raise notice 'PASS: PIRATE_LEAVES — her first change to % is at once and ends the war there; back under the skull is E_TOO_SOON; the knob false again, she stays of the Brethren and a new founding is E_MINOR_POWER', v_ccode;
end $$;
