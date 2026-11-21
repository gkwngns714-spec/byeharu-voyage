-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 169 - REQUESTS A SHIP CAN CARRY  (migration 0466; docs/design/content-plan-2026-11.md 5.3 item 4; docs/dev-log/2026-11-22-ship-requests.md)
--
--   Lit and dark, through public.hold_request_post, the wind job (public.tick_contract_wind, one pass in this transaction, at one harbour),
--   world.contracts, cmd.fulfil and public.contracts_expire, rolled back with proof.mjs's transaction. A new company (the starter hull, 'barca')
--   at Lisbon, the city's purse lit.
--
-- @pass SR_DARK      dark (0466's knobs as shipped): the writer, the read and the wind job post no hold job
-- @pass SR_PURSE     lit, a harbour whose surplus does not cover the bonus posts none
-- @pass SR_SIZE      lit, the wind job tops the harbour up one a pass to hold_request_open_max hold jobs (receipt 'hold'), each in its bounds, beside the city's own
-- @pass SR_ESCROW    lit purses: each job's budget is its escrow, and left the city as a BOUNTY flow of the same figure
-- @pass SR_READ      the read serves size 'hold' and total = units x (today's bid + the bonus); the bonus is 20-30 % of the mid
-- @pass SR_FITS      the whole lot goes aboard the starter hull, empty
-- @pass SR_DELIVER   the company delivers the whole lot: the bonus is the whole budget, the job is spent, Reputation and the book of deliveries move
-- @pass SR_MERCHANTS merchants are never offered a hold job, even with contract_npc_after_hours 0
-- @pass SR_EXPIRE    past its deadline the other job expires and its escrow goes home (BOUNTY_LAPSED); a real day later its row is pruned
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.surplus_169(p_port uuid, p_surplus bigint) returns void language plpgsql as $f$
begin
  perform public.treasury_post(p_port, 'CROWN_CALL', p_surplus - public.city_surplus(p_port), null, null, true);
end $f$;

do $p$
declare
  v_uid   uuid := '00000000-0466-4000-8000-000000000169';
  v_hp    uuid;
  v_f     uuid;
  v_port  uuid;
  v_day   int := world.game_day();
  v_n     int;
  v_r     jsonb;
  v_a     jsonb;
  v_b     jsonb;
  c       public.trade_contracts%rowtype;
  v_id    uuid;
  v_id2   uuid;
  v_code  text;
  v_bid   numeric;
  v_bal   bigint;
  v_load  numeric;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';   -- a founding is refused on a closed economy
  v_hp := public.new_house(v_uid, 'Casa do Porão 169', 'PRT', 'LIS');
  select f.id, f.port_id into v_f, v_port from public.fleets f where f.player_id = v_hp;
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_f;
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) values (v_port) on conflict (port_id) do nothing;
  update public.port_treasury set reserve = 0 where port_id = v_port;
  delete from public.trade_contracts where port_id = v_port;

  -- ── SR_DARK ──
  if public.wc('hold_requests_enabled') is distinct from 'false'::jsonb or public.wc_int('hold_request_open_max') <> 2 then
    raise exception 'PROOF 169 FAIL: the knobs are not 0466''s';
  end if;
  perform pg_temp.surplus_169(v_port, 1000000000);
  v_n := public.hold_request_post(v_port, now());
  perform world.contracts(v_port);
  call public.tick_contract_wind(false, v_port);
  if v_n <> 0 or exists (select 1 from public.trade_contracts t where t.size = 'hold') then
    raise exception 'PROOF 169 FAIL: dark, a hold job was posted';
  end if;
  raise notice 'PASS: SR_DARK — dark: the writer, the read and the wind job posted no hold job';

  -- ── SR_PURSE ──
  update public.world_config set value = 'true'::jsonb where key = 'hold_requests_enabled';
  perform pg_temp.surplus_169(v_port, 0);
  if public.hold_request_post(v_port, now()) <> 0 or exists (select 1 from public.trade_contracts t where t.size = 'hold') then
    raise exception 'PROOF 169 FAIL: lit, a harbour with no surplus posted a hold job';
  end if;
  raise notice 'PASS: SR_PURSE — lit, no surplus: no hold job';

  -- ── SR_SIZE ──
  perform pg_temp.surplus_169(v_port, 1000000000);
  v_bal := public.treasury_balance(v_port);
  -- a minute asks a harbour for one hold job at most (the order turns each minute), so two passes fill it, and a third finds it full
  for v_n in 1 .. 3 loop
    call public.tick_contract_wind(false, v_port);
    v_r := (select w.receipt from public.contract_wind_runs w order by w.at desc limit 1);
    if (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'hold') <> least(v_n, 2)
       or (v_r ->> 'hold')::int <> (case when v_n <= 2 then 1 else 0 end) then
      raise exception 'PROOF 169 FAIL: lit, pass % of the wind job did not top the harbour up one hold job, to at most 2: %', v_n, v_r;
    end if;
  end loop;
  if (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'city') > public.wc_int('contract_open_max') then
    raise exception 'PROOF 169 FAIL: the city''s own board passed its cap';
  end if;
  for c in select * from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' loop
    if c.seq <= 100 or c.qty < 10 or c.qty > 250 or c.qty * (select g.bulk from public.goods g where g.id = c.good_id) > 150
       or c.qty * c.mid_at_post > 24000 or c.expires_day <= v_day
       or (c.expires_day - v_day - 1) * public.wc_num('game_day_seconds') > 6 * 3600
       or exists (select 1 from public.port_offered_goods(v_port) o where o.good_id = c.good_id) then
      raise exception 'PROOF 169 FAIL: a hold job out of its bounds: %', to_jsonb(c);
    end if;
  end loop;
  raise notice 'PASS: SR_SIZE — lit: the wind job posted 2 hold jobs beside the city''s own (%)',
    (select string_agg(t.qty || ' ' || g.code || ' (' || round(t.qty * g.bulk) || ' t)', ', ') from public.trade_contracts t join public.goods g on g.id = t.good_id where t.port_id = v_port and t.size = 'hold');

  -- ── SR_ESCROW ──
  if exists (select 1 from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' and (t.escrow <> t.premium_ducats or t.premium_ducats <> ceil(t.premium_per_unit * t.qty)))
     or (select count(*) from public.trade_contracts t where t.port_id = v_port and t.size = 'hold'
           and exists (select 1 from public.treasury_flows fl where fl.port_id = v_port and fl.kind = 'BOUNTY' and fl.ducats = -t.escrow)) <> 2 then
    raise exception 'PROOF 169 FAIL: a hold job''s escrow is not its budget, or did not leave the city';
  end if;
  raise notice 'PASS: SR_ESCROW — each budget is its escrow and left the city as BOUNTY';

  -- ── SR_READ ──
  select t.id into v_id from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' order by t.seq limit 1;
  select t.id into v_id2 from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' and t.id <> v_id;
  select * into c from public.trade_contracts t where t.id = v_id;
  select g.code into v_code from public.goods g where g.id = c.good_id;
  v_a := (select e from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e where e ->> 'id' = v_id::text);
  v_bid := (select q.bid from world.price(v_port, c.good_id) q);
  if v_a ->> 'size' <> 'hold' or (v_a ->> 'qty')::numeric <> c.qty
     or (v_a ->> 'total')::bigint <> round(c.qty * (v_bid + c.premium_per_unit))::bigint
     or c.premium_per_unit < 0.2 * c.mid_at_post - 0.01 or c.premium_per_unit > 0.3 * c.mid_at_post + 0.01
     or exists (select 1 from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e where e ->> 'size' = 'city' and e ->> 'total' is not null) then
    raise exception 'PROOF 169 FAIL: the read: %', v_a;
  end if;
  raise notice 'PASS: SR_READ — % x %: pays % (a plain sale %), bonus % a unit on a mid of %', c.qty, v_code, v_a ->> 'total', round(c.qty * v_bid), c.premium_per_unit, c.mid_at_post;

  -- ── SR_FITS ──
  v_load := public.fleet_load(v_f, v_code, c.qty);
  if v_load <> c.qty then
    raise exception 'PROOF 169 FAIL: the starter hull took % of %', v_load, c.qty;
  end if;
  raise notice 'PASS: SR_FITS — the starter hull took the whole lot (% %)', c.qty, v_code;

  -- ── SR_DELIVER ──
  perform pg_temp.surplus_169(v_port, 1000000000);   -- the sale itself must not be short
  perform cmd.assume_identity(v_uid);
  v_b := cmd.fulfil(v_f, v_id, null);
  if not coalesce((v_b ->> 'ok')::boolean, true) or v_b ? 'error_code'
     or (v_b #>> '{totals,premium}')::bigint <> c.premium_ducats or (v_b #>> '{lines,0,qty}')::numeric <> c.qty then
    raise exception 'PROOF 169 FAIL: the delivery: %', v_b;
  end if;
  if (select t.status from public.trade_contracts t where t.id = v_id) <> 'spent'
     or not exists (select 1 from public.contract_deliveries d where d.contract_id = v_id and d.player_id = v_hp and d.bonus = c.premium_ducats)
     or (public.wc('reputation_on') = 'true'::jsonb and not exists (select 1 from public.reputation_book b where b.player_id = v_hp and b.key = 'request:' || v_id)) then
    raise exception 'PROOF 169 FAIL: after the delivery the job is not spent, or the books did not move';
  end if;
  raise notice 'PASS: SR_DELIVER — the whole lot landed, bonus % (the whole budget), the job spent, Reputation and the book moved', c.premium_ducats;

  -- ── SR_MERCHANTS ──
  update public.world_config set value = to_jsonb(0) where key = 'contract_npc_after_hours';
  if exists (select 1 from public.contract_asks(v_port) a where a.id = v_id2) then
    raise exception 'PROOF 169 FAIL: a merchant is offered a hold job';
  end if;
  raise notice 'PASS: SR_MERCHANTS — no hold job among the asks merchants answer';

  -- ── SR_EXPIRE ──
  select * into c from public.trade_contracts t where t.id = v_id2;
  perform public.contracts_expire(v_port, public.clock_start('game_day', c.expires_day));
  if (select t.status from public.trade_contracts t where t.id = v_id2) <> 'expired'
     or not exists (select 1 from public.treasury_flows fl where fl.port_id = v_port and fl.kind = 'BOUNTY_LAPSED' and fl.ducats >= c.escrow) then
    raise exception 'PROOF 169 FAIL: past its deadline the job did not expire, or its escrow did not go home';
  end if;
  perform public.contracts_expire(v_port, public.clock_start('game_day', c.expires_day + ceil(86400 / public.wc_num('game_day_seconds'))::int + 1));
  if exists (select 1 from public.trade_contracts t where t.id = v_id2) then
    raise exception 'PROOF 169 FAIL: a real day past its deadline the hold job was not pruned';
  end if;
  raise notice 'PASS: SR_EXPIRE — expired, escrow % home, pruned a real day later', c.escrow;
end
$p$;
