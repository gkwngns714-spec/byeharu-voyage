-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 71 — FLEET ROOM, LIT, AND SIX FLEETS  (migration 0370 lights fleet_room_bite and raises fleet_hard_max 5 -> 6; 0321 and 0354 built it)
--
--   Proofs 29 and 57 prove the rules from a world they set dark and light themselves. This proof does NOT set the switch or the top: it reads them as the chain left
--   them (0370) and walks what a company can now do, through the doors the client calls (cmd.buy_room, cmd.move_ship, world.house_room, world.ship_moves,
--   and, where 0367 is in the chain, cmd.armada_form), signed in as a probe company. Everything is rolled back by proof.mjs.
--
--   Her Trading level cannot be raised by a proof, so the two level rungs are reached the way proofs 29 and 57 reach them: the knob `fleet_room_levels` is set to
--   [1, 1] for this transaction (every company is at Trading 1 or more). The prices, the top and the switch are the chain's own.
--
-- @pass LIT_BY_0370        the chain left fleet_room_bite true and fleet_hard_max 6, nobody holds bought room, and 0370's news row is one row
-- @pass LIT_ROOM_READ      world.house_room says on, top 6 for fleets and 7 for ships, the first prices, and the same steps a new company saw dark
-- @pass LIT_SECOND_FLEET   a new company (two free fleets) moves her second ship into a NEW fleet through cmd.move_ship; world.ship_moves offered it; no gold moved
-- @pass LIT_BUY_ORDER      two presses of Buy one after another pay the first price and then the second, never one price twice; the house row is locked before the steps are read
-- @pass LIT_SIX_FLEETS     with both rungs and both steps she forms six fleets; the room read says 6 of 6 and full; the seventh is refused; a buy at the top is refused E_ROOM_TOP
-- @pass LIT_SIX_AS_ONE     (where 0367 is in the chain) her six fleets form ONE armada through cmd.armada_form
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0370-4000-8000-0000000000aa';
  v_lis   uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl    uuid;
  v_f1    uuid;
  v_fl    uuid[];
  v_s     uuid;
  v_room  jsonb;
  v_r     jsonb;
  v_gold  bigint;
  v_p1    bigint := (public.wc('fleet_room_prices') ->> 0)::bigint;
  v_p2    bigint := (public.wc('fleet_room_prices') ->> 1)::bigint;
  v_src   text;
  i       int;
begin
  -- AS THE CHAIN LEFT IT
  if not public.fleet_room_on() or (select c.value from public.world_config c where c.key = 'fleet_room_bite') is distinct from 'true'::jsonb
     or public.wc_int('fleet_hard_max') <> 6 or exists (select 1 from public.house_room)
     or (select count(*) from public.world_news w where w.key = 'update:0370') <> 1 then
    raise exception 'PROOF 71 FAIL: the chain did not leave fleet_room_bite true, fleet_hard_max 6, no bought room and one news row of 0370';
  end if;
  raise notice 'PASS: LIT_BY_0370 — fleet_room_bite true, fleet_hard_max 6, no bought room, one news row "update:0370"';

  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 71', (select n.id from public.nations n where n.code = 'PRT'), 2000000, false) returning id into v_pl;
  v_f1 := public.form_fleet(v_pl, 'Primeira 71', v_lis);
  perform public.commission_ship(v_pl, v_f1, 'barca', 'Capitania 71', true, true);
  perform public.commission_ship(v_pl, v_f1, 'barca', 'Segunda 71', false, true);
  perform cmd.assume_identity(c_auth);

  -- ── THE ROOM READ, LIT ──
  v_room := world.house_room();
  if (v_room ->> 'on')::boolean is not true
     or (v_room -> 'fleets' ->> 'top')::int <> 6 or (v_room -> 'fleets' ->> 'have')::int <> 2 or (v_room -> 'fleets' ->> 'used')::int <> 1
     or (v_room -> 'fleets' ->> 'price')::bigint <> v_p1 or (v_room -> 'fleets' ->> 'full')::boolean
     or (v_room -> 'ships' ->> 'top')::int <> public.wc_int('fleet_ship_top') or (v_room -> 'ships' ->> 'used')::int <> 2
     or (select jsonb_agg(case when s.value ->> 'how' = 'level' then s.value ->> 'level' else s.value ->> 'price' end order by s.ord)
           from jsonb_array_elements(v_room -> 'fleets' -> 'steps') with ordinality s(value, ord))
        is distinct from (select jsonb_agg(x.v order by x.o) from (select l.value as v, l.ord as o from jsonb_array_elements_text(public.wc('fleet_room_levels')) with ordinality l(value, ord)
                                                                   union all select g.value, 100 + g.ord from jsonb_array_elements_text(public.wc('fleet_room_prices')) with ordinality g(value, ord)) x)
     or (select count(*) from jsonb_array_elements(v_room -> 'fleets' -> 'steps') s where s.value ->> 'how' = 'gold' and (s.value ->> 'next')::boolean) <> 1 then
    raise exception 'PROOF 71 FAIL: lit, the room read: %', v_room;
  end if;
  raise notice 'PASS: LIT_ROOM_READ — on; fleets 1 of 2, top 6, next price %; ships 2 of %, top %; the fleet steps are the knob''s rungs % and prices %',
    v_p1, v_room -> 'ships' ->> 'have', v_room -> 'ships' ->> 'top', public.wc('fleet_room_levels'), public.wc('fleet_room_prices');

  -- ── A SECOND FLEET, with the two free fleets and no gold ──
  select ducats into v_gold from public.players where id = v_pl;
  select s.id into v_s from public.ships s where s.fleet_id = v_f1 and not s.is_flagship;
  v_r := world.ship_moves(v_f1);
  if (v_r ->> 'on')::boolean is not true or (v_r ->> 'can_new')::boolean is not true then
    raise exception 'PROOF 71 FAIL: lit, world.ship_moves does not offer a new fleet: %', v_r;
  end if;
  v_r := cmd.move_ship(v_s, null, 'Segunda Frota 71');
  if (v_r ->> 'ok')::boolean is not true or not (v_r ->> 'new_fleet')::boolean
     or (select count(*) from public.fleets f where f.player_id = v_pl) <> 2
     or not exists (select 1 from public.fleets f where f.id = (v_r ->> 'fleet_id')::uuid and f.name = 'Segunda Frota 71' and f.status = 'DOCKED' and f.port_id = v_lis)
     or (select ducats from public.players where id = v_pl) <> v_gold then
    raise exception 'PROOF 71 FAIL: lit, her second ship did not start a second fleet for nothing: %', v_r;
  end if;
  v_fl := array[v_f1, (v_r ->> 'fleet_id')::uuid];
  raise notice 'PASS: LIT_SECOND_FLEET — cmd.move_ship formed "Segunda Frota 71" at Lisbon, DOCKED, her ship its flagship; the purse did not move';

  -- ── TWO PRESSES OF BUY: the first price, then the second ──
  v_src := (select p.prosrc from pg_proc p where p.oid = 'public.buy_room_for(uuid,text)'::regprocedure);
  if position('for update' in v_src) = 0 or position('for update' in v_src) > position('from public.house_room' in v_src)
     or position('for update' in v_src) > position('public.fleet_room_caps(p_player)' in v_src) then
    raise exception 'PROOF 71 FAIL: public.buy_room_for does not lock the house row before it reads her caps and her bought steps';
  end if;
  v_r := cmd.buy_room('FLEET');
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'step')::int <> 1 or (v_r ->> 'price')::bigint <> v_p1 then
    raise exception 'PROOF 71 FAIL: the first press: %', v_r;
  end if;
  v_r := cmd.buy_room('FLEET');
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'step')::int <> 2 or (v_r ->> 'price')::bigint <> v_p2 then
    raise exception 'PROOF 71 FAIL: the second press: %', v_r;
  end if;
  if (select ducats from public.players where id = v_pl) <> v_gold - v_p1 - v_p2
     or (select array_agg(-l.ducats_delta order by -l.ducats_delta) from public.ledger l where l.player_id = v_pl and l.kind = 'SLOT') is distinct from array[v_p1, v_p2]
     or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'ROOM_OPENED') <> 2 then
    raise exception 'PROOF 71 FAIL: two presses did not pay % then %, one SLOT row and one event each', v_p1, v_p2;
  end if;
  raise notice 'PASS: LIT_BUY_ORDER — two presses paid % then % (two SLOT rows, two events); the door locks the house row (for update) before it reads the caps and the steps, so a second session waits and pays the next price', v_p1, v_p2;

  -- ── SIX FLEETS ──
  update public.world_config set value = '[1, 1]'::jsonb where key = 'fleet_room_levels';   -- both rungs reached, for this transaction (see the header)
  if (public.earned_caps(v_pl) ->> 'fleet_max')::int <> 6 then
    raise exception 'PROOF 71 FAIL: both rungs and both steps give % fleets, not 6', public.earned_caps(v_pl) ->> 'fleet_max';
  end if;
  for i in 3 .. 6 loop
    perform public.commission_ship(v_pl, v_f1, 'barca', format('Navio %s 71', i), false, true);
    select s.id into v_s from public.ships s where s.fleet_id = v_f1 and not s.is_flagship;
    v_r := cmd.move_ship(v_s, null, format('Frota %s 71', i));
    if (v_r ->> 'ok')::boolean is not true then
      raise exception 'PROOF 71 FAIL: fleet % was not formed: %', i, v_r;
    end if;
    v_fl := v_fl || (v_r ->> 'fleet_id')::uuid;
  end loop;
  v_room := world.house_room();
  if (select count(*) from public.fleets f where f.player_id = v_pl) <> 6 or (v_room -> 'fleets' ->> 'used')::int <> 6 or (v_room -> 'fleets' ->> 'have')::int <> 6
     or not (v_room -> 'fleets' ->> 'full')::boolean or v_room -> 'fleets' -> 'price' <> 'null'::jsonb
     or exists (select 1 from jsonb_array_elements(v_room -> 'fleets' -> 'steps') s where not (s.value ->> 'open')::boolean) then
    raise exception 'PROOF 71 FAIL: six fleets formed, and the room read says: %', v_room -> 'fleets';
  end if;
  -- the seventh: no room
  perform public.commission_ship(v_pl, v_f1, 'barca', 'Navio 7 71', false, true);
  select s.id into v_s from public.ships s where s.fleet_id = v_f1 and not s.is_flagship;
  v_r := cmd.move_ship(v_s, null, 'Frota 7 71');
  if coalesce((v_r ->> 'ok')::boolean, false) or (select count(*) from public.fleets f where f.player_id = v_pl) <> 6 or v_r ->> 'error_code' is null then
    raise exception 'PROOF 71 FAIL: a seventh fleet was not refused: %', v_r;
  end if;
  if cmd.buy_room('FLEET') ->> 'error_code' is distinct from 'E_ROOM_TOP' then
    raise exception 'PROOF 71 FAIL: a buy at six fleets answered: %', cmd.buy_room('FLEET');
  end if;
  raise notice 'PASS: LIT_SIX_FLEETS — six fleets at Lisbon; the room read says 6 of 6, full, no price, every step open; the seventh is refused %; a buy at the top is refused E_ROOM_TOP', v_r ->> 'error_code';

  -- ── SIX AS ONE (0367) ──
  if to_regprocedure('cmd.armada_form(jsonb,text)') is not null and public.armada_on() then
    v_r := cmd.armada_form(to_jsonb(v_fl), 'Armada Real 71');
    if (v_r ->> 'ok')::boolean is not true then
      raise exception 'PROOF 71 FAIL: her six fleets did not form one armada: %', v_r;
    end if;
    raise notice 'PASS: LIT_SIX_AS_ONE — cmd.armada_form took all six fleets as one armada';
  else
    raise notice 'PASS: LIT_SIX_AS_ONE — not judged: 0367 (armadas) is not in this chain or is not on';
  end if;
end
$$;
