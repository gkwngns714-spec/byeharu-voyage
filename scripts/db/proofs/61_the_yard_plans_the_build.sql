-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 61 — THE YARD PLANS THE BUILD  (migration 0358, slice S1 of docs/SECOND_SHIP.md; owner rows 180, 305, 316)
--
--   The migration's self-assert holds the read's new keys to the old answer on as many hulls and yards as fit its
--   clock. This proof (1) holds EVERY hull at EVERY yard, old against new, and (2) plays the errand the sheet now
--   plans, for a new company at Lisbon, through the doors a player uses (cmd.issue for BUY, SAIL, STORE, TAKE, MAKE,
--   BUILD, HIRE; the read voyage.settle runs under). What is real and what is not:
--     * REAL: the timber. She provisions for ten days (PROVISION FULL would put 77 t of supplies in her hold and leave 99 t), sails to Funchal, buys the 40 there, sails home (each voyage's eta moved
--       back, as proof 55 does, and settled by the read). The iron is bought at Lisbon's quay.
--     * PLACED: the five goods of the far north and the Mediterranean (nails, cordage, tar, flax, hemp) are put in
--       her hold by public.fleet_load, the one cargo mover, at the sellers' asks. Riga lies beyond a new company's
--       reach in one leg; six more voyages would prove the sea again, not the yard.
--   Everything rolls back with proof.mjs's transaction. The knobs set here (hazard_p_max 0, as proofs 04 and 55; city_treasury_enabled for the one BUILD)
--   go back with it.
--
-- @pass YARD_PLAN_PARITY      every hull at every build yard: the new answer less its new keys is the answer of the body before 0358 (a pg_temp copy of 0349's text)
-- @pass YARD_PLAN_SEVEN       for the Barca at Lisbon the read names seven goods, each with a seller; the sum of qty x ask is within 5 % of the sum of world.quote's totals for those buys
-- @pass YARD_PLAN_STORE       timber bought at Funchal and carried home: BUILD refuses E_NO_TIMBER with everything in her hold, and names the timber no longer once it is stored
-- @pass YARD_PLAN_MAKE        with the tar stored first MAKE refuses E_NO_MATERIALS; taken back into the hold, MAKE gives both parts out of the hold
-- @pass YARD_PLAN_BUILD       BUILD barca lays her down: the labour leaves her purse and reaches Lisbon's treasury (the treasury switch lit for that one order), the stored goods and the parts are gone, she has 2 ships, Reputation +rep_built
-- @pass YARD_PLAN_CREW        the new ship has no crew: SAIL refuses E_CREW_SHORT; HIRE of her crew_required is taken; SAIL then opens
-- @pass YARD_PLAN_FLEET_FULL  with a third hull's materials ashore a third BUILD refuses E_FLEET_SHIP_MAX, and the storage, the parts and the purse are untouched
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- the body of world.yard_sources BEFORE 0358, verbatim from 0349 (the migration's own self-assert proves its hunks reverse to this text on the live body)
create function pg_temp.yard_sources_old_61(p_port uuid, p_class text)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $body$
  with dist as materialized (
    select p.id, p.code, p.name, p.culture,
           case when p.id = p_port then 0::numeric else (sr.reaches ->> p.code)::numeric end as miles
      from public.ports p
      left join public.sea_reaches sr on sr.port_id = p_port
     where p.kind = 'HARBOUR'),
  sold as materialized (
    select distinct on (g.id) g.id as good_id, d.code, d.name, d.miles
      from public.hull_recipe_goods hg
      join public.goods g on g.id = hg.good_id
      cross join dist d
      join lateral public.port_offered_goods(d.id) o on o.good_id = g.id
     where hg.class_code = p_class
       and not public.culture_refuses(d.culture, g.culture_mask)
     order by g.id, d.miles nulls last, d.name),
  can as materialized (
    select k.code as item, d.id, d.code, d.name, d.miles
      from public.hull_recipe_items hi
      join public.item_kinds k on k.code = hi.item_code
      join public.port_buildings b on b.kind = 'workstation' and b.tier >= k.ws_tier
      join dist d on d.id = b.port_id
     where hi.class_code = p_class),
  made as materialized (
    select distinct on (c.item) c.item, c.code, c.name, c.miles
      from can c
     where public.made_only_in(c.item, c.id) is null
     order by c.item, c.miles nulls last, c.name)
  select jsonb_build_object(
    'port_id', p_port,
    'class', p_class,
    'goods', coalesce((
      select jsonb_agg(jsonb_build_object('code', g.code, 'port', s.code, 'name', s.name, 'miles', round(s.miles)) order by g.code)
        from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
        left join sold s on s.good_id = g.id
       where hg.class_code = p_class), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('code', k.code, 'port', m.code, 'name', m.name, 'miles', round(m.miles)) order by k.code)
        from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
        left join made m on m.item = k.code
       where hi.class_code = p_class), '[]'::jsonb))
$body$;

do $p$
declare
  c_uid   constant uuid := '00000000-0361-4000-8000-000000000001';
  v_pl    uuid;
  v_fl    uuid;
  v_lis   uuid;
  v_fnc   uuid;
  v_t     timestamptz;
  v_r     jsonb;
  v_src   jsonb;
  v_yard  jsonb;
  v_need  jsonb;      -- [{code, qty, ask, port}] one row a good: the hull's count and her parts' counts together
  y       record;
  g       record;
  v_n     int := 0;
  v_parts int := 0;
  v_ms    numeric;
  v_est   numeric;
  v_quote numeric;
  v_purse bigint;
  v_labour bigint;
  v_rep   int;
  v_crew  int;
  v_hire  jsonb;
  v_ship  uuid;
  v_voy   uuid;
  v_nm    numeric;
  v_dest  text;
  v_before text;
  v_flow  bigint;
  v_short text;
  v_kept  jsonb;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';

  -- ── YARD_PLAN_PARITY: every hull at every build yard ──
  v_t := clock_timestamp();
  for y in
    select b.port_id, r.class_code,
           pg_temp.yard_sources_old_61(b.port_id, r.class_code) as o,
           world.yard_sources(b.port_id, r.class_code) as n
      from public.port_buildings b cross join public.hull_recipes r
     where b.kind = 'building_yard'
  loop
    v_n := v_n + 1;
    if jsonb_array_length(y.n -> 'items') > 0 then v_parts := v_parts + 1; end if;
    if jsonb_build_object(
         'port_id', y.n -> 'port_id', 'class', y.n -> 'class',
         'goods', coalesce((select jsonb_agg(e.value - 'qty' - 'bulk' - 'ask' order by e.ord) from jsonb_array_elements(y.n -> 'goods') with ordinality e(value, ord)), '[]'::jsonb),
         'items', coalesce((select jsonb_agg(e.value - 'inputs' order by e.ord) from jsonb_array_elements(y.n -> 'items') with ordinality e(value, ord)), '[]'::jsonb))
       is distinct from y.o
       or exists (select 1 from jsonb_array_elements(y.n -> 'goods') e where not (e.value ? 'qty' and e.value ? 'bulk' and e.value ? 'ask'))
       or exists (select 1 from jsonb_array_elements(y.n -> 'items') e where jsonb_typeof(e.value -> 'inputs') is distinct from 'array') then
      raise exception 'PROOF 61 FAILED: % at yard %: the new answer less its new keys is not the old answer, or a new key is missing. OLD % NEW %', y.class_code, y.port_id, y.o, y.n;
    end if;
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  if v_n <> (select count(*) from public.hull_recipes) * (select count(*) from public.port_buildings where kind = 'building_yard') or v_n < 1 or v_parts < 1 then
    raise exception 'PROOF 61 FAILED: the walk covered % pair(s), % with a part', v_n, v_parts;
  end if;
  raise notice 'PASS: YARD_PLAN_PARITY — % hull x yard pairs (% hulls, % yards; % pairs with a part): the new answer less qty, bulk, ask and inputs is the old answer, in % ms for both bodies',
    v_n, (select count(*) from public.hull_recipes), (select count(*) from public.port_buildings where kind = 'building_yard'), v_parts, v_ms;

  -- ── a new company at Lisbon ──
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  v_pl := public.new_house(c_uid, 'Casa do Estaleiro 61', 'PRT');
  perform cmd.assume_identity(c_uid);
  select id into v_fl from public.fleets where player_id = v_pl;

  -- ── YARD_PLAN_SEVEN ──
  v_src := world.yard_sources(v_lis, 'barca');
  select jsonb_agg(jsonb_build_object('code', x.code, 'qty', x.qty, 'ask', x.ask, 'port', x.port) order by x.code) into v_need
    from (select u.value ->> 'code' as code, sum((u.value ->> 'qty')::numeric) as qty, min((u.value ->> 'ask')::numeric) as ask, min(u.value ->> 'port') as port
            from (select e.value from jsonb_array_elements(v_src -> 'goods') e
                  union all
                  select u2.value from jsonb_array_elements(v_src -> 'items') i cross join jsonb_array_elements(i.value -> 'inputs') u2) u
           group by 1) x;
  if jsonb_array_length(v_need) <> 7 or exists (select 1 from jsonb_array_elements(v_need) e where e.value ->> 'port' is null or (e.value ->> 'ask')::numeric <= 0) then
    raise exception 'PROOF 61 FAILED: the read does not name seven goods, each with a seller and a price: %', v_need;
  end if;
  select sum((e.value ->> 'qty')::numeric * (e.value ->> 'ask')::numeric),
         sum((select q.total from public.ports p join public.goods gd on gd.code = e.value ->> 'code'
                cross join lateral world.quote(p.id, gd.id, (e.value ->> 'qty')::numeric, 'buy', null, v_fl) q where p.code = e.value ->> 'port'))
    into v_est, v_quote from jsonb_array_elements(v_need) e;
  if v_quote is null or v_quote <= 0 or abs(v_est - v_quote) > 0.05 * v_quote then
    raise exception 'PROOF 61 FAILED: the sheet''s estimate (%) is not within 5 %% of the quotes for those buys (%)', v_est, v_quote;
  end if;
  raise notice 'PASS: YARD_PLAN_SEVEN — seven goods, each with a seller: %. The sum of qty x ask is %; world.quote for the same buys totals % (% %% apart)',
    (select string_agg(format('%s %s at %s (%s)', e.value ->> 'qty', e.value ->> 'code', e.value ->> 'port', e.value ->> 'ask'), ', ') from jsonb_array_elements(v_need) e),
    round(v_est), v_quote, round(100 * abs(v_est - v_quote) / v_quote, 2);

  -- ── YARD_PLAN_STORE: the timber, by sea ──
  v_r := cmd.issue(v_fl, 'PROVISION DAYS 10');
  v_r := proof.sail(v_fl, 'FNC');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: SAIL TO FNC was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select v.id, v.total_nm into v_voy, v_nm from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING';
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  perform world.fleets();
  if (select f.port_id from public.fleets f where f.id = v_fl and f.status = 'DOCKED') is distinct from v_fnc then
    raise exception 'PROOF 61 FAILED: she did not make Funchal';
  end if;
  v_r := cmd.issue(v_fl, 'BUY timber 40');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: Funchal did not sell 40 timber: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'PROVISION DAYS 10');
  v_r := proof.sail(v_fl, 'LIS');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: SAIL TO LIS was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select v.id into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING';
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  perform world.fleets();
  if (select f.port_id from public.fleets f where f.id = v_fl and f.status = 'DOCKED') is distinct from v_lis or public.fleet_cargo_qty(v_fl, 'timber') <> 40 then
    raise exception 'PROOF 61 FAILED: she did not come home with 40 timber (% on board)', public.fleet_cargo_qty(v_fl, 'timber');
  end if;
  -- the iron at Lisbon's own quay, through the door; the five far goods placed by the one cargo mover at the sellers' asks
  v_r := cmd.issue(v_fl, 'BUY iron 4');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: Lisbon did not sell 4 iron: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  for g in select e.value ->> 'code' as code, (e.value ->> 'qty')::numeric as qty, (e.value ->> 'ask')::numeric as ask from jsonb_array_elements(v_need) e
            where e.value ->> 'code' not in ('timber', 'iron') loop
    perform public.fleet_load(v_fl, g.code, g.qty, g.ask);
    if public.fleet_cargo_qty(v_fl, g.code) <> g.qty then
      raise exception 'PROOF 61 FAILED: her hold did not take % % (% on board)', g.qty, g.code, public.fleet_cargo_qty(v_fl, g.code);
    end if;
  end loop;
  -- everything she needs is in her hold, and the yard still refuses: it reads the city's storage
  v_r := cmd.issue(v_fl, 'BUILD barca Segunda');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_TIMBER' or v_r ->> 'error_message' not like '%Timber (0. of 40.)%' then
    raise exception 'PROOF 61 FAILED: with the goods in her hold BUILD answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  v_r := cmd.issue(v_fl, 'STORE timber 40');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: STORE timber was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'BUILD barca Segunda');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_TIMBER' or v_r ->> 'error_message' like '%Timber (%' then
    raise exception 'PROOF 61 FAILED: with the timber stored BUILD answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  raise notice 'PASS: YARD_PLAN_STORE — % nm to Funchal, 40 timber bought there and carried home. With all seven goods in her hold BUILD refused E_NO_TIMBER naming the timber (0 of 40); after STORE timber 40 it refused naming only: %',
    round(v_nm), v_r ->> 'error_message';

  -- ── YARD_PLAN_MAKE: parts come out of the hold ──
  v_r := cmd.issue(v_fl, 'STORE tar ALL');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: STORE tar was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'MAKE suit-of-sails');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_MATERIALS' or v_r ->> 'error_message' not like '%Tar%' then
    raise exception 'PROOF 61 FAILED: with the tar stored MAKE answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  v_before := v_r ->> 'error_message';
  v_r := cmd.issue(v_fl, 'TAKE tar 2');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: TAKE tar was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'MAKE suit-of-sails');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: MAKE suit-of-sails was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'MAKE anchor-and-cable');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: MAKE anchor-and-cable was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  if (select count(*) from public.player_items pi where pi.player_id = v_pl and pi.port_id = v_lis and pi.qty = 1 and pi.item_code in ('suit-of-sails', 'anchor-and-cable')) <> 2
     or public.fleet_cargo_qty(v_fl, 'flax') <> 0 or public.fleet_cargo_qty(v_fl, 'hemp') <> 0 or public.fleet_cargo_qty(v_fl, 'iron') <> 0
     or public.fleet_cargo_qty(v_fl, 'tar') <> 0 or public.fleet_cargo_qty(v_fl, 'cordage') <> 6 then
    raise exception 'PROOF 61 FAILED: the two parts were not made out of the hold';
  end if;
  raise notice 'PASS: YARD_PLAN_MAKE — with the tar stored MAKE refused E_NO_MATERIALS (%); with 2 taken back, MAKE gave a Suit of Sails and an Anchor & Cable, and the flax, hemp, iron and that tar left her hold',
    v_before;

  -- ── YARD_PLAN_BUILD ──
  v_r := cmd.issue(v_fl, 'STORE ships-nails 10');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: STORE nails was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fl, 'STORE cordage 6');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: STORE cordage was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_yard := (select h.value from jsonb_array_elements(world.building_yard(v_lis) -> 'hulls') h where h.value ->> 'class' = 'barca');
  if not (v_yard ->> 'buildable')::boolean
     or exists (select 1 from jsonb_array_elements(v_yard -> 'goods' || (v_yard -> 'items')) m where (m.value ->> 'have')::numeric < (m.value ->> 'qty')::numeric) then
    raise exception 'PROOF 61 FAILED: the yard read still says something is short: %', v_yard;
  end if;
  v_labour := public.yard_labour(v_pl, 'barca');
  select ducats into v_purse from public.players where id = v_pl;
  v_rep := coalesce((select balance from public.reputation_balance where player_id = v_pl), 0);
  v_flow := coalesce((select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_pl and tf.kind = 'BUILD'), 0);
  -- the city's treasury is kept for this one order (the switch goes back at once, and with the rollback), so the labour is seen to arrive there
  select value into v_kept from public.world_config where key = 'city_treasury_enabled';
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_r := cmd.issue(v_fl, 'BUILD barca Segunda');
  update public.world_config set value = v_kept where key = 'city_treasury_enabled';
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 61 FAILED: BUILD was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select s.id, s.crew into v_ship, v_crew from public.ships s where s.player_id = v_pl and s.name = 'Segunda';
  if v_ship is null or (select count(*) from public.ships s where s.fleet_id = v_fl) <> 2
     or (select ducats from public.players where id = v_pl) <> v_purse - v_labour or v_labour <= 0
     or exists (select 1 from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis)
     or exists (select 1 from public.player_items pi where pi.player_id = v_pl and pi.port_id = v_lis)
     or coalesce((select balance from public.reputation_balance where player_id = v_pl), 0) - v_rep <> public.wc_int('rep_built')
     or (select k.delta from public.reputation_book k where k.player_id = v_pl and k.key = 'built:' || v_ship) is distinct from public.wc_int('rep_built')
     or coalesce((select sum(tf.ducats) from public.treasury_flows tf where tf.port_id = v_lis and tf.player_id = v_pl and tf.kind = 'BUILD'), 0) - v_flow <> v_labour then
    raise exception 'PROOF 61 FAILED: the build did not pay the labour, empty the storage and the parts, make 2 ships and book rep_built: %', v_r;
  end if;
  raise notice 'PASS: YARD_PLAN_BUILD — Segunda is laid down: % paid for the labour (her purse % -> %) and Lisbon''s treasury took the same % as a BUILD flow, nothing of hers left stored or in parts at Lisbon, 2 ships in the fleet, Reputation +% (built:<ship>)',
    v_labour, v_purse, v_purse - v_labour, v_labour, public.wc_int('rep_built');

  -- ── YARD_PLAN_CREW ──
  if v_crew <> 0 then
    raise exception 'PROOF 61 FAILED: the new ship came with % crew', v_crew;
  end if;
  v_r := cmd.issue(v_fl, 'PROVISION DAYS 10');
  v_r := proof.sail(v_fl, 'FNC');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_CREW_SHORT' then
    raise exception 'PROOF 61 FAILED: with an uncrewed ship SAIL answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  v_short := v_r ->> 'error_message';
  v_crew := (v_yard ->> 'crew_required')::int;
  select ducats into v_purse from public.players where id = v_pl;
  v_hire := cmd.issue(v_fl, 'HIRE ' || v_crew);
  if not (v_hire ->> 'ok')::boolean or (select s.crew from public.ships s where s.id = v_ship) <> v_crew then
    raise exception 'PROOF 61 FAILED: HIRE % did not crew her: % %', v_crew, v_hire ->> 'error_code', v_hire ->> 'error_message';
  end if;

  -- ── YARD_PLAN_FLEET_FULL: before she sails. A third hull's materials ashore (placed: the storage rule and the item store), and the yard refuses on the fleet's room alone ──
  for g in select e.value ->> 'code' as code, (e.value ->> 'qty')::numeric as qty from jsonb_array_elements(v_src -> 'goods') e loop
    perform public.storage_put(v_pl, v_lis, (select id from public.goods where code = g.code), g.qty, 1);
  end loop;
  insert into public.player_items (player_id, port_id, item_code, qty)
  select v_pl, v_lis, e.value ->> 'code', 1 from jsonb_array_elements(v_src -> 'items') e;
  if (select ducats from public.players where id = v_pl) < v_labour then
    raise exception 'PROOF 61 FAILED: her purse (%) no longer covers a third hull''s labour, so the refusal below would be the purse''s', (select ducats from public.players where id = v_pl);
  end if;
  select md5(coalesce((select string_agg(ps.good_id::text || ':' || ps.qty::text, ',' order by ps.good_id) from public.player_storage ps where ps.player_id = v_pl), '') || '|'
          || coalesce((select string_agg(pi.item_code || ':' || pi.qty::text, ',' order by pi.item_code) from public.player_items pi where pi.player_id = v_pl), '') || '|'
          || (select ducats::text from public.players where id = v_pl) || '|' || (select count(*)::text from public.ships where player_id = v_pl)) into v_before;
  v_r := cmd.issue(v_fl, 'BUILD barca Terceira');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_FLEET_SHIP_MAX' then
    raise exception 'PROOF 61 FAILED: a third BUILD answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  if md5(coalesce((select string_agg(ps.good_id::text || ':' || ps.qty::text, ',' order by ps.good_id) from public.player_storage ps where ps.player_id = v_pl), '') || '|'
      || coalesce((select string_agg(pi.item_code || ':' || pi.qty::text, ',' order by pi.item_code) from public.player_items pi where pi.player_id = v_pl), '') || '|'
      || (select ducats::text from public.players where id = v_pl) || '|' || (select count(*)::text from public.ships where player_id = v_pl)) <> v_before
     or (public.earned_caps(v_pl) ->> 'fleet_ship_max')::int <> 2 then
    raise exception 'PROOF 61 FAILED: the refused third BUILD moved her storage, her parts, her purse or her ships (or a new company''s fleet does not hold 2)';
  end if;
  raise notice 'PASS: YARD_PLAN_FLEET_FULL — with a third hull''s goods and parts ashore and % in her purse, BUILD refused E_FLEET_SHIP_MAX (%); her storage, parts, purse and 2 ships are as they were; world.levels() serves the room: fleet_ship_max %',
    (select ducats from public.players where id = v_pl), v_r ->> 'error_message', world.levels() -> 'room' ->> 'fleet_ship_max';

  -- and now, crewed, she sails
  v_r := proof.sail(v_fl, 'FNC');
  if not (v_r ->> 'ok')::boolean or not exists (select 1 from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING') then
    raise exception 'PROOF 61 FAILED: crewed, SAIL was still refused: % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  raise notice 'PASS: YARD_PLAN_CREW — Segunda came with 0 crew and SAIL refused E_CREW_SHORT (%); HIRE % cost % (her purse % -> %); SAIL then opened',
    v_short, v_crew, v_hire -> 'order' -> 'result' ->> 'cost', v_purse, v_purse - (v_hire -> 'order' -> 'result' ->> 'cost')::bigint;
end
$p$;
