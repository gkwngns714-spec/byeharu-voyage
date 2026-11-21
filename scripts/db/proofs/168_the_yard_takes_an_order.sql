-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 168 - THE YARD TAKES AN ORDER  (migration 0465; docs/design/content-plan-2026-11.md 5.3 item 3, 5.4 row C;
--   docs/dev-log/2026-11-22-yard-order.md). A hull ordered for coin and time, paid to the city, built in real time, launched into a
--   fleet lying at the yard. Behind yard_order_enabled (false). Everything rolls back (proof.mjs).
--
-- @pass ORDER_DARK        dark: the yard read serves no `order`, the quote is {on: false}, the order door refuses E_NOT_IN_USE and writes nothing
-- @pass ORDER_PRICE       lit: the quote is the yard's labour + every good (the hull's and her parts') at the nearest seller's ask now + half again; the Barca's wait is 30 minutes, the biggest hull's 450; the order costs more than the materials route, by the fee
-- @pass ORDER_PAID        the order takes exactly the quote from the purse into the city (one BUILD ledger row, and its treasury flow to that city while the city purses are lit; a HULL_ORDERED event); the yard read serves it open and not ready
-- @pass ORDER_GATES       refused before anything moves: too little coin (E_NO_FUNDS, with figures), a second order at the same yard (E_YARD_BUSY), a foreign hull (E_WRONG_YARD), a yard too small (E_YARD_TOO_SMALL), a city with no yard (E_NO_BUILDING_YARD)
-- @pass ORDER_LAUNCH      not ready: E_NOT_READY; a bad name: E_PARSE; at ready she joins the fleet docked there, uncrewed, with a Shipbuilding gain; the order is closed and the yard is free again
-- @pass ORDER_ELSEWHERE   an order at another yard is served under `elsewhere`, and a fleet at this yard cannot launch it (E_NO_ORDER)
-- @pass ORDER_DARK_LAUNCH an order paid while lit still launches after the switch goes off
-- @pass ORDER_RETENTION   the next order deletes the company's launched orders older than 7 days and keeps the younger
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_uid  constant uuid := '00000000-0468-4000-8000-000000000001';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_mac  uuid := (select p.id from public.ports p where p.code = 'MAC' and p.kind = 'HARBOUR');
  v_set  uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_pl   uuid;
  v_fl   uuid;
  v_r    jsonb;
  v_q    jsonb;
  v_src  jsonb;
  v_x    numeric;
  v_n    int;
  v_order uuid;
  v_ready timestamptz;
  v_treas bigint;
  v_xp   numeric;
  v_ev   int;
begin
  v_pl := public.new_house(c_uid, 'Estaleiro 168', 'PRT');
  perform cmd.assume_identity(c_uid);
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  if v_lis is null or v_mac is null or v_set is null or v_fl is null then
    raise exception 'PROOF 168 FAILED: the fixture (Lisbon, Macau, Setubal, a new company''s fleet) is not in this world';
  end if;

  -- ── ORDER_DARK ──
  v_r := cmd.order_hull(v_lis, 'barca');
  if world.building_yard(v_lis) ? 'order' or world.hull_quote(v_lis, 'barca') <> '{"on": false}'::jsonb
     or v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or exists (select 1 from public.hull_orders o where o.player_id = v_pl)
     or exists (select 1 from public.ledger l where l.player_id = v_pl and l.kind = 'BUILD') then
    raise exception 'PROOF 168 FAILED: dark, the yard served an order or the door opened: %', v_r;
  end if;
  raise notice 'PASS: ORDER_DARK — no order key, quote {on: false}, the door says %', v_r ->> 'error_code';

  update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';

  -- ── ORDER_PRICE ──
  v_q := world.hull_quote(v_lis, 'barca');
  v_src := world.yard_sources(v_lis, 'barca');
  select ceil(sum((e ->> 'qty')::numeric * (e ->> 'ask')::numeric)) into v_x from jsonb_array_elements(v_src -> 'goods') e;
  if (v_q ->> 'materials')::numeric <> v_x or (v_q ->> 'labour')::bigint <> public.yard_labour(v_pl, 'barca')
     or (v_q ->> 'fee')::bigint <> round(((v_q ->> 'labour')::numeric + v_x) / 2)
     or (v_q ->> 'price')::bigint <> (v_q ->> 'labour')::bigint + (v_q ->> 'materials')::bigint + (v_q ->> 'fee')::bigint
     or (v_q ->> 'minutes')::int <> 30 or (v_q ->> 'on')::boolean is not true then
    raise exception 'PROOF 168 FAILED: the Barca''s quote is not labour + the sheet''s materials + half again in 30 minutes: % (materials %)', v_q, v_x;
  end if;
  -- a hull with parts: her parts' goods are counted too
  v_src := world.yard_sources(v_lis, 'carlat');
  select ceil(sum(x.q)) into v_x from (
    select (e ->> 'qty')::numeric * (e ->> 'ask')::numeric q from jsonb_array_elements(v_src -> 'goods') e
    union all
    select (i ->> 'qty')::numeric * (i ->> 'ask')::numeric from jsonb_array_elements(v_src -> 'items') it cross join lateral jsonb_array_elements(it -> 'inputs') i) x;
  if jsonb_array_length(v_src -> 'items') = 0 or (world.hull_quote(v_lis, 'carlat') ->> 'materials')::numeric <> v_x then
    raise exception 'PROOF 168 FAILED: the Caravela latina''s quote does not count her parts'' goods: % vs %', world.hull_quote(v_lis, 'carlat'), v_x;
  end if;
  if (public.hull_order_price(v_pl, v_lis, (select c.code from public.hull_recipes h join public.ship_classes c on c.code = h.class_code
                                             order by c.build_hours desc, c.code limit 1)) ->> 'minutes')::int <> 450 then
    raise exception 'PROOF 168 FAILED: the biggest hull''s wait is not 7.5 hours';
  end if;
  raise notice 'PASS: ORDER_PRICE — Barca % = labour % + materials % + fee %, 30 min; the materials route costs % less',
    v_q ->> 'price', v_q ->> 'labour', v_q ->> 'materials', v_q ->> 'fee', v_q ->> 'fee';

  -- ── ORDER_GATES (part one: before any order) ──
  update public.players set ducats = (v_q ->> 'price')::bigint - 1 where id = v_pl;
  v_r := cmd.order_hull(v_lis, 'barca');
  if v_r ->> 'error_code' is distinct from 'E_NO_FUNDS' or (v_r -> 'figures' ->> 'need')::numeric <> (v_q ->> 'price')::numeric
     or exists (select 1 from public.hull_orders o where o.player_id = v_pl) then
    raise exception 'PROOF 168 FAILED: too little coin was not refused with its figures: %', v_r;
  end if;
  update public.players set ducats = 10000000 where id = v_pl;
  if cmd.order_hull(v_lis, 'almiranta') ->> 'error_code' is distinct from 'E_WRONG_YARD'
     or cmd.order_hull(v_mac, (select h.class_code from public.hull_recipes h where h.yard_tier = 3
                                 and public.yard_wrong_country(v_mac, h.class_code) is null order by h.class_code limit 1)) ->> 'error_code' is distinct from 'E_YARD_TOO_SMALL'
     or cmd.order_hull(v_set, 'barca') ->> 'error_code' is distinct from 'E_NO_BUILDING_YARD'
     or exists (select 1 from public.hull_orders o where o.player_id = v_pl) then
    raise exception 'PROOF 168 FAILED: a foreign hull, a small yard or a city with no yard was not refused';
  end if;

  -- ── ORDER_PAID ──
  select coalesce(sum(l.ducats_delta), 0) into v_treas from public.ledger l where l.player_id = v_pl;
  select count(*) into v_ev from public.events e where e.player_id = v_pl and e.kind = 'HULL_ORDERED';
  v_r := cmd.order_hull(v_lis, 'barca');
  select o.id, o.ready_at into v_order, v_ready from public.hull_orders o where o.player_id = v_pl and o.launched_at is null;
  if not coalesce((v_r ->> 'ok')::boolean, false) or v_order is null
     or (select p.ducats from public.players p where p.id = v_pl) <> 10000000 - (v_q ->> 'price')::bigint
     or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'BUILD' and l.ducats_delta = -(v_q ->> 'price')::bigint) <> 1
     or (public.city_treasury_on() and (select count(*) from public.treasury_flows t where t.player_id = v_pl and t.port_id = v_lis and t.kind = 'BUILD' and t.ducats = (v_q ->> 'price')::bigint) <> 1)
     or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'HULL_ORDERED') <> v_ev + 1
     or v_ready <> now() + interval '30 minutes'
     or world.building_yard(v_lis) -> 'order' -> 'open' ->> 'class' is distinct from 'barca'
     or (world.building_yard(v_lis) -> 'order' -> 'open' ->> 'ready')::boolean is distinct from false then
    raise exception 'PROOF 168 FAILED: the order was not paid whole to Lisbon and served open: % / %', v_r, world.building_yard(v_lis) -> 'order';
  end if;
  raise notice 'PASS: ORDER_PAID — % paid to Lisbon (one BUILD ledger row; a treasury flow while the city purses are lit), ready at +30 min, served open', v_q ->> 'price';

  -- ── ORDER_GATES (part two) ──
  v_r := cmd.order_hull(v_lis, 'barca');
  if v_r ->> 'error_code' is distinct from 'E_YARD_BUSY' or (select count(*) from public.hull_orders o where o.player_id = v_pl) <> 1 then
    raise exception 'PROOF 168 FAILED: a second order at the same yard was not refused: %', v_r;
  end if;
  raise notice 'PASS: ORDER_GATES — E_NO_FUNDS (need %), E_YARD_BUSY, E_WRONG_YARD, E_YARD_TOO_SMALL, E_NO_BUILDING_YARD; nothing written', v_q ->> 'price';

  -- ── ORDER_ELSEWHERE: an order at Macau (any country builds a Barca) ──
  v_r := cmd.order_hull(v_mac, 'barca');
  if not coalesce((v_r ->> 'ok')::boolean, false)
     or (select count(*) from jsonb_array_elements(world.building_yard(v_lis) -> 'order' -> 'elsewhere') e where e ->> 'port' = 'MAC' and e ->> 'class' = 'barca') <> 1
     or world.building_yard(v_mac) -> 'order' -> 'open' ->> 'class' is distinct from 'barca' then
    raise exception 'PROOF 168 FAILED: the order at Macau is not served under elsewhere at Lisbon: %', v_r;
  end if;

  -- ── ORDER_LAUNCH ──
  v_r := cmd.launch_hull(v_fl, 'Encomenda');
  if v_r ->> 'error_code' is distinct from 'E_NOT_READY' then
    raise exception 'PROOF 168 FAILED: she launched before she was ready: %', v_r;
  end if;
  begin
    perform public.hull_launch_for(v_pl, v_fl, 'No', v_ready + interval '1 second');
    raise exception 'PROOF 168 FAILED: a two-letter name was taken';
  exception when others then
    if sqlerrm not like 'E_PARSE:%' then raise; end if;
  end;
  select coalesce(sum(x.xp), 0) into v_xp from public.level_xp x where x.player_id = v_pl;
  v_r := public.hull_launch_for(v_pl, v_fl, 'Encomenda', v_ready + interval '1 second');
  if not coalesce((v_r ->> 'ok')::boolean, false)
     or (select count(*) from public.ships s where s.fleet_id = v_fl) <> 2
     or (select s.crew from public.ships s where s.fleet_id = v_fl and s.name = 'Encomenda') <> 0
     or (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fl and s.name = 'Encomenda') <> 'barca'
     or (select o.ship_id from public.hull_orders o where o.id = v_order) is distinct from (v_r ->> 'ship')::uuid
     or (select coalesce(sum(x.xp), 0) from public.level_xp x where x.player_id = v_pl) <= v_xp
     or world.building_yard(v_lis) -> 'order' -> 'open' <> 'null'::jsonb
     or not exists (select 1 from public.events e where e.player_id = v_pl and e.kind = 'HULL_LAUNCHED') then
    raise exception 'PROOF 168 FAILED: at ready she did not join the fleet uncrewed with a Shipbuilding gain, the order closed: %', v_r;
  end if;
  raise notice 'PASS: ORDER_LAUNCH — E_NOT_READY before, E_PARSE for a short name; at ready the Encomenda joins her fleet with 0 crew; the yard is free';

  -- ── ORDER_ELSEWHERE (the launch side): the fleet lies at Lisbon, the Macau hull is not hers to launch here ──
  delete from public.ships s where s.fleet_id = v_fl and s.name = 'Encomenda';   -- room for the next launch (rolled back)
  update public.hull_orders set ordered_at = now() - interval '31 minutes', ready_at = now() - interval '1 minute' where player_id = v_pl and port_id = v_mac and launched_at is null;
  v_r := cmd.launch_hull(v_fl, 'Macaense');
  if v_r ->> 'error_code' is distinct from 'E_NO_ORDER' then
    raise exception 'PROOF 168 FAILED: a fleet at Lisbon launched the Macau order: %', v_r;
  end if;
  raise notice 'PASS: ORDER_ELSEWHERE — the Macau order is served at Lisbon under elsewhere; Lisbon''s fleet is told E_NO_ORDER';

  -- ── ORDER_DARK_LAUNCH: lit to order, dark to launch ──
  v_r := cmd.order_hull(v_lis, 'barca');
  update public.world_config set value = 'false'::jsonb where key = 'yard_order_enabled';
  v_r := public.hull_launch_for(v_pl, v_fl, 'Tardia', now() + interval '31 minutes');
  if not coalesce((v_r ->> 'ok')::boolean, false) or world.building_yard(v_lis) ? 'order' then
    raise exception 'PROOF 168 FAILED: an order paid while lit did not launch dark: %', v_r;
  end if;
  raise notice 'PASS: ORDER_DARK_LAUNCH — the switch off, the paid order still launched (%)', v_r ->> 'name';
  update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';

  -- ── ORDER_RETENTION ──
  update public.hull_orders set launched_at = now() - interval '8 days' where player_id = v_pl and ship_id = (select s.id from public.ships s where s.name = 'Tardia' and s.player_id = v_pl);
  select count(*) into v_n from public.hull_orders o where o.player_id = v_pl and o.launched_at is not null;
  delete from public.ships s where s.fleet_id = v_fl and s.name = 'Tardia';
  v_r := cmd.order_hull(v_lis, 'barca');
  if not coalesce((v_r ->> 'ok')::boolean, false) or v_n <> 2
     or (select count(*) from public.hull_orders o where o.player_id = v_pl and o.launched_at is not null) <> 1
     or not exists (select 1 from public.hull_orders o where o.id = v_order) then
    raise exception 'PROOF 168 FAILED: the next order did not delete the launched order 8 days old and keep the younger: % (% launched before)', v_r, v_n;
  end if;
  raise notice 'PASS: ORDER_RETENTION — of 2 launched orders the one 8 days old went at the next order, the younger stayed';
end
$p$;
