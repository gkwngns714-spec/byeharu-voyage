-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 186 - COURIER CONTRACTS  (migration 0483; docs/design/roadmap-2026-11-23.md slice 14; docs/dev-log/2026-11-23-contracts.md)
--
--   The migration's self-assert places every arrival by hand and posts one house contract through the tick. This proof plays contracts
--   as a company lives them: the houses post to their cap over several runs; HQ's board offers one with its risk and act; one press takes
--   it; her voyage is settled by the game's own read (proof 184's way: the voyage's clock moved back) and she delivers it by the door; a
--   contract taken far from A sails SAIL A / TAKE / SAIL B and the tick delivers it; a company posts and takes her post down; the cost of
--   a run and of her cards. Rolled back by proof.mjs.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: world.hq_board (world.best_sales inside) is asked once, for its contract cards alone.
--   THE DAY: proof.mjs runs this file in ONE transaction (now() is one instant); every clock is set from now() or from 00:00 UTC of the
--   day it runs, so no scene straddles a UTC midnight.
--
-- @pass CC_DARK      dark: the tick writes nothing, the read is {"on": false} and no card shows
-- @pass CC_POST      lit: three runs post as houses (and only houses: the city purses dark), never past the cap, each lot sane and escrowed
-- @pass CC_BOARD     HQ's served board offers a house contract at Lisbon as a `contract` card: reward, coin an hour, risk, the take act
-- @pass CC_DELIVER   one press takes it; the game's read brings her in; the deliver door pays the reward and returns the collateral
-- @pass CC_REMOTE    taken away from A: SAIL A / TAKE / SAIL B; she sails it all and the tick delivers it
-- @pass CC_CANCEL    a company posts from her Storage and takes it down: the reward and her goods come back
-- @pass CC_COST      one lit run of the tick and one read of her cards, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0483-4000-8000-0000000001a1';
  c_b     constant uuid := '00000000-0483-4000-8000-0000000001b1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_b     uuid;
  v_fb    uuid;
  v_to    uuid;
  v_tocode text;
  v_good  uuid;
  v_gcode text;
  v_house uuid;
  v_c     uuid;
  v_r     jsonb;
  v_hq    jsonb;
  v_card  jsonb;
  v_tick  jsonb;
  v_texts text;
  v_p0    bigint;
  v_n     int;
  v_t     timestamptz;
  v_ms    numeric;
  v_ms2   numeric;
  k       int;
begin
  -- THE SEA IS CALMED for this transaction (hazard_p_max 0, as proofs 04, 11, 157 and 184): a voyage's days are rolled on its own id, new
  -- every run, and a storm, a calm or a raid on a leg moves her days, her stores, her hold or her crew (about one sea-day in 70 meets
  -- something; with a raid on every day this proof went red, 2026-11-25). What is proved here is not the weather.
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  if public.wc_num('hazard_p_max') <> 0 then
    raise exception 'PROOF 186: the sea was not calmed (hazard_p_max %)', public.wc_num('hazard_p_max');
  end if;
  v_a := public.new_house(c_a, 'Casa do Porte 186', 'PRT');
  v_b := public.new_house(c_b, 'Casa da Carga 186', 'PRT');
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  update public.players p set ducats = 200000 where p.id in (v_a, v_b);
  update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_fb;
  select g.id, g.code into v_good, v_gcode
    from public.port_offered_goods(v_lis) o join public.goods g on g.id = o.good_id
    join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id
   where g.bulk > 0 order by g.bulk, g.code limit 1;
  select r.port_id, r.code into v_to, v_tocode
    from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
    join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = v_good
   where r.nm >= 150 and public.sea_course(v_lis, r.port_id) is not null and public.storage_cap(r.port_id) > 0
   order by r.nm, r.code limit 1;
  select h.player_id into v_house from public.npc_houses h join public.players p on p.id = h.player_id order by p.ducats desc, h.roster_ord limit 1;

  -- CC_DARK
  perform cmd.assume_identity(c_b);
  if public.tick_courier_contracts() is distinct from '{"on": false}'::jsonb or world.courier_contracts() is distinct from '{"on": false}'::jsonb
     or public.courier_moves(v_b, 200000) <> '[]'::jsonb or exists (select 1 from public.courier_contracts) then
    raise exception 'CC_DARK: dark, the tick, the read or the cards moved';
  end if;
  raise notice 'PASS: CC_DARK — dark: the tick wrote nothing, the read {"on": false}, no card';

  -- CC_POST: three runs, three posts a run at most, never past the cap; each lot sane and escrowed to the ducat
  update public.world_config set value = 'true'::jsonb where key in ('contracts_enabled', 'sea_courses_enabled', 'hq_board_enabled');
  for k in 1 .. 3 loop
    v_tick := public.tick_courier_contracts(now() + make_interval(mins => k));
    if (v_tick->>'posted')::int > 3 or (v_tick->>'open')::int > (v_tick->>'cap')::int then
      raise exception 'CC_POST: run % posted past its limits: %', k, v_tick;
    end if;
  end loop;
  v_n := (select count(*) from public.courier_contracts);
  if v_n = 0 or v_n > 9 or exists (select 1 from public.courier_contracts c where c.poster_kind <> 'house')
     or exists (select 1 from public.courier_contracts c
                 where c.from_port = c.to_port or c.nm < public.wc_num('contracts_nm_min') or c.nm > public.wc_num('contracts_nm_max')
                    or c.collateral < c.value or c.reward <= 0 or c.window_s < public.wc_int('contracts_window_min_s')
                    or c.from_port <> (select h.home_port_id from public.npc_houses h where h.player_id = c.poster_id)
                    or (select l.ducats_delta from public.ledger l join public.events e on e.id = l.ref_event_id
                         where l.player_id = c.poster_id and l.kind = 'CONTRACT_ESCROW' and e.payload->>'contract' = c.id::text) is distinct from -c.reward)
     or (select count(distinct c.poster_id) from public.courier_contracts c) <> v_n then
    raise exception 'CC_POST: the posts are not sane, not escrowed, or a house posted twice: %',
      (select jsonb_agg(to_jsonb(c)) from public.courier_contracts c);
  end if;
  raise notice 'PASS: CC_POST — three runs posted % house contracts (cap %), each its house''s home harbour to a harbour %..% miles away, collateral over the value, escrowed', v_n,
    v_tick->>'cap', public.wc_num('contracts_nm_min'), public.wc_num('contracts_nm_max');

  -- CC_BOARD: a house contract from Lisbon; her served board offers it to her idle fleet there
  v_c := public.courier_post('house', v_house, v_lis, v_to, v_good, 10, 800, 4000, 7200, now());
  v_hq := world.hq_board();
  select e into v_card from jsonb_array_elements(v_hq->'moves') e
   where e->>'kind' = 'contract' and (e #>> '{act,args,contract}')::uuid = v_c and (e #>> '{act,args,fleet}')::uuid = v_fb;
  if v_card is null or v_card #>> '{act,rpc}' <> 'cmd.take_contract' or (v_card->>'profit')::bigint <> 800 or (v_card->>'band')::int <> 1
     or (v_card->>'score')::numeric <= 0 or (v_card->>'seconds')::numeric <= 0 or v_card #>> '{needs,from}' <> 'LIS' or v_card #>> '{needs,to}' <> v_tocode
     or (v_card #>> '{needs,collateral}')::bigint <> 4000 or (v_card #>> '{risk,danger}')::int is null then
    raise exception 'CC_BOARD: her board does not offer the Lisbon contract: %', left((v_hq->'moves')::text, 800);
  end if;
  raise notice 'PASS: CC_BOARD — the board''s card: % % LIS->%, +% in % s (% an hour), collateral %, danger %', v_card #>> '{needs,units}', v_gcode, v_tocode,
    v_card->>'profit', v_card->>'seconds', v_card->>'score', v_card #>> '{needs,collateral}', v_card #>> '{risk,danger}';

  -- CC_DELIVER: the card's act in one press; she sails, the game's read brings her in, the deliver door pays
  v_p0 := (select p.ducats from public.players p where p.id = v_b);
  v_r := cmd.take_contract((v_card #>> '{act,args,fleet}')::uuid, (v_card #>> '{act,args,contract}')::uuid, (v_card #>> '{act,args,version}')::int);
  if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING' or public.fleet_cargo_qty(v_fb, v_gcode) <> 10 then
    raise exception 'CC_DELIVER: the one press did not take it and sail: %', v_r;
  end if;
  for k in 1 .. 6 loop
    exit when (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fb and status = 'SAILING';
    perform world.fleets();
  end loop;
  if public.courier_state(v_c) <> 'deliver' then
    raise exception 'CC_DELIVER: she did not come in to % with the goods: % at %, % aboard', v_tocode, (select f.status from public.fleets f where f.id = v_fb),
      (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fb), public.fleet_cargo_qty(v_fb, v_gcode);
  end if;
  if not exists (select 1 from jsonb_array_elements(public.courier_moves(v_b, 200000)) e where e #>> '{act,rpc}' = 'cmd.deliver_contract') then
    raise exception 'CC_DELIVER: lying at % with the goods, her board offers no Deliver card', v_tocode;
  end if;
  v_r := cmd.deliver_contract(v_c);
  if (v_r->>'ok')::boolean is not true or (select c.status from public.courier_contracts c where c.id = v_c) <> 'delivered'
     or public.fleet_cargo_qty(v_fb, v_gcode) <> 0
     or (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_b and l.kind like 'CONTRACT\_%') <> 800 then
    raise exception 'CC_DELIVER: the door did not deliver to the ducat: %', v_r;
  end if;
  raise notice 'PASS: CC_DELIVER — one press took it, she sailed LIS->% and came in by the read; delivered: +800 reward, collateral 4,000 back (her purse % -> %)',
    v_tocode, v_p0, (select p.ducats from public.players p where p.id = v_b);

  -- CC_REMOTE: a contract from Lisbon taken at B: SAIL LIS / TAKE / SAIL B; she sails it all; the tick delivers it
  v_c := public.courier_post('house', v_house, v_lis, v_to, v_good, 7, 500, 3000, 14400, now());
  v_r := cmd.take_contract(v_fb, v_c, (select f.version from public.fleets f where f.id = v_fb));
  select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fb and o.status in ('pending', 'active', 'done')
     and o.plan_id = (select o2.plan_id from public.orders o2 where o2.fleet_id = v_fb order by o2.issued_at desc, o2.seq desc limit 1);
  if (v_r->>'ok')::boolean is not true or v_texts is distinct from format('SAIL LIS / TAKE %s 7 / SAIL %s', v_gcode, v_tocode) then
    raise exception 'CC_REMOTE: the plan is not SAIL LIS / TAKE / SAIL B: % / %', v_r, v_texts;
  end if;
  for k in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fb) <> 'SAILING'
          and not exists (select 1 from public.orders o where o.fleet_id = v_fb and o.status in ('pending', 'active'));
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fb and status = 'SAILING';
    perform world.fleets();
  end loop;
  v_tick := public.tick_courier_contracts(now());
  if (select c.status from public.courier_contracts c where c.id = v_c) <> 'delivered' or (v_tick->>'delivered')::int < 1 then
    raise exception 'CC_REMOTE: the tick did not deliver it: % / % (%)', v_tick, (select c.status from public.courier_contracts c where c.id = v_c),
      (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fb);
  end if;
  raise notice 'PASS: CC_REMOTE — taken at %: % ; she sailed it all and the tick delivered it', v_tocode, v_texts;

  -- CC_CANCEL: a company posts from her Storage and takes it down
  perform cmd.assume_identity(c_a);
  perform public.storage_put(v_a, v_lis, v_good, 12, 0);
  v_p0 := (select p.ducats from public.players p where p.id = v_a);
  v_r := cmd.post_contract(v_lis, v_to, v_good, 12, 600, 2400, 6);
  if (v_r->>'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_a) <> v_p0 - 600
     or exists (select 1 from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = v_good)
     or (world.courier_contracts() #>> '{posted,0,status}') <> 'open' then
    raise exception 'CC_CANCEL: the post did not hold the reward and the goods: %', v_r;
  end if;
  v_r := cmd.cancel_contract((v_r->>'contract')::uuid);
  if (v_r->>'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_a) <> v_p0
     or (select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = v_good) <> 12
     or (world.courier_contracts() #>> '{posted,0,status}') <> 'cancelled' then
    raise exception 'CC_CANCEL: taken down, the reward and the goods did not come back: %', v_r;
  end if;
  raise notice 'PASS: CC_CANCEL — posted 12 % for 600, taken down: 600 and the 12 back in her shed', v_gcode;

  -- CC_COST: one lit run (the open contracts to their cap, none to settle) and one read of her cards at Lisbon
  update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_fb;
  update public.orders set status = 'cancelled' where fleet_id = v_fb and status in ('pending', 'active');
  v_t := clock_timestamp();
  v_tick := public.tick_courier_contracts(now() + interval '10 minutes');
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  perform cmd.assume_identity(c_b);
  v_t := clock_timestamp();
  v_r := public.courier_moves(v_b, 200000);
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  raise notice 'PASS: CC_COST — one run % ms (%); her cards % ms (% cards, % open contracts)', v_ms, v_tick, v_ms2, jsonb_array_length(v_r),
    (select count(*) from public.courier_contracts c where c.status = 'open');
end
$p$;
