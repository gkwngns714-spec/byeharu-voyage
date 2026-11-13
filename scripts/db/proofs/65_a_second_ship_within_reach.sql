-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 65 — A SECOND SHIP WITHIN REACH  (migration 0363, slice S2 of docs/SECOND_SHIP.md; owner rows 180, 305, 316; touches row 58)
--
--   0363 takes the Barca's two parts out of her recipe. This proof plays the WHOLE errand of a first second ship, for a
--   new company at Lisbon, through the doors a player uses and nothing else: cmd.issue for PROVISION, SAIL, BUY, STORE,
--   BUILD and HIRE. Every good is bought at its own port; nothing is placed in her hold. Each voyage's eta is moved back
--   and settled by the read (world.fleets), as proofs 55 and 61 do; its length in real time is read off the voyage
--   BEFORE that (eta - departed_at). Storms are off for the measurement (hazard_p_max 0, as proofs 04, 55 and 61).
--   Then the same errand is played as it was BEFORE 0363, by a second new company, with the Barca's two rows put back
--   for it (the forward rollback's own rows): seven goods from six ports, the parts made from her hold. The two are
--   printed side by side: that is the measurement of this recipe change, on the local world (prices on prod differ).
--   And a company that was midway through the OLD errand loses nothing.
--   Everything rolls back with proof.mjs's transaction.
--
-- @pass SECOND_SHIP_RECIPE   the Barca takes four hull goods and no part; the Caravela latina, the Nau and the 11 famous ships keep theirs; the yard's two reads at Lisbon serve no part for her and a seller for each good
-- @pass SECOND_SHIP_ERRAND   a new company, by the real commands: timber bought at Funchal and stored; nails at La Rochelle, cordage at Portsmouth, tar at Bergen, stored; BUILD barca; HIRE; two crewed ships in one fleet that sails. Miles, real minutes and coin printed
-- @pass SECOND_SHIP_KEEPS    a company midway through the old errand (part goods in her hold, a part made) builds her Barca at once and keeps every part and part good; the part still fits a ship, the goods still make a part and still sell
-- @pass SECOND_SHIP_BEFORE   with the two rows put back the yard refuses a Barca for her parts (E_NO_FITTINGS); the old errand by the real commands is seven goods from six ports; it costs more miles, minutes and coin than the new one
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- One leg: provision, sail (a course proposed as a client proposes it), read the voyage, bring her in. Returns the miles and the real seconds the voyage was to take.
create function pg_temp.leg_65(p_fleet uuid, p_dest text, out nm numeric, out secs numeric)
language plpgsql
as $f$
declare
  v_r   jsonb;
  v_voy uuid;
begin
  v_r := cmd.issue(p_fleet, 'PROVISION DAYS 10');
  -- topped up to ten days where there is less (a refusal here is 'the casks are already full': SAIL below is what refuses a voyage she cannot feed)
  v_r := proof.sail(p_fleet, p_dest);
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: SAIL TO % was refused: % %', p_dest, v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select v.id, v.total_nm, extract(epoch from v.eta - v.departed_at) into v_voy, nm, secs from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING';
  if v_voy is null or nm <= 0 or secs <= 0 then raise exception 'PROOF 65 FAILED: no voyage to % was opened', p_dest; end if;
  update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute' where id = v_voy;
  perform world.fleets();
  if not exists (select 1 from public.fleets f join public.ports p on p.id = f.port_id where f.id = p_fleet and f.status = 'DOCKED' and p.code = p_dest) then
    raise exception 'PROOF 65 FAILED: she did not make %', p_dest;
  end if;
end $f$;

-- A tour: the stops in order; at each stop the goods to buy there ({"FNC": {"timber": 40}}). Returns the miles, the real seconds and what the goods cost her.
create function pg_temp.tour_65(p_player uuid, p_fleet uuid, p_stops text[], p_buys jsonb, out nm numeric, out secs numeric, out goods bigint, out bought int)
language plpgsql
as $f$
declare
  v_stop  text;
  l       record;
  b       record;
  v_r     jsonb;
  v_purse bigint;
begin
  nm := 0; secs := 0; goods := 0; bought := 0;
  foreach v_stop in array p_stops loop
    select * into l from pg_temp.leg_65(p_fleet, v_stop);
    nm := nm + l.nm; secs := secs + l.secs;
    for b in select e.key as code, e.value::text::numeric as qty from jsonb_each(coalesce(p_buys -> v_stop, '{}'::jsonb)) e order by e.key loop
      select pl.ducats into v_purse from public.players pl where pl.id = p_player;
      v_r := cmd.issue(p_fleet, format('BUY %s %s', b.code, b.qty));
      if not (v_r ->> 'ok')::boolean or public.fleet_cargo_qty(p_fleet, b.code) < b.qty then
        raise exception 'PROOF 65 FAILED: % did not sell % %: % %', v_stop, b.qty, b.code, v_r ->> 'error_code', v_r ->> 'error_message';
      end if;
      goods := goods + v_purse - (select pl.ducats from public.players pl where pl.id = p_player);
      bought := bought + 1;
    end loop;
  end loop;
end $f$;

do $p$
declare
  c_uid_a  constant uuid := '00000000-0365-4000-8000-000000000001';
  c_uid_b  constant uuid := '00000000-0365-4000-8000-000000000002';
  c_uid_c  constant uuid := '00000000-0365-4000-8000-000000000003';
  v_lis    uuid;
  v_a      uuid;  v_fa uuid;
  v_b      uuid;  v_fb uuid;
  v_c      uuid;  v_fc uuid;
  v_r      jsonb;
  v_src    jsonb;
  v_yard   jsonb;
  t        record;
  g        record;
  v_start  bigint;
  v_purse  bigint;
  v_labour bigint;
  v_crew   int;
  v_ship   uuid;
  v_txt    text;
  v_before text;
  -- the two errands, side by side
  a_nm numeric := 0; a_secs numeric := 0; a_goods bigint := 0; a_labour bigint; a_hire bigint; a_all bigint; a_ports int; a_kinds int := 0;
  b_nm numeric := 0; b_secs numeric := 0; b_goods bigint := 0; b_labour bigint; b_hire bigint; b_all bigint; b_ports int; b_kinds int := 0;
begin
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';

  -- ── SECOND_SHIP_RECIPE ──
  if (select count(*) from public.hull_recipe_items hi where hi.class_code = 'barca') <> 0
     or (select coalesce(jsonb_agg(g2.code order by g2.code), '[]'::jsonb) from public.hull_recipe_goods hg join public.goods g2 on g2.id = hg.good_id where hg.class_code = 'barca')
          <> '["cordage", "ships-nails", "tar", "timber"]'::jsonb
     or (select r.note from public.hull_recipes r where r.class_code = 'barca') like '%fitting%' then
    raise exception 'PROOF 65 FAILED: the Barca''s recipe is not four hull goods and no part';
  end if;
  if (select count(*) from public.hull_recipe_items hi where hi.class_code = 'carlat') <> 4 or (select count(*) from public.hull_recipe_items hi where hi.class_code = 'nau') <> 5
     or (select count(distinct hi.class_code) from public.hull_recipe_items hi) <> 13
     or (select count(distinct hi.class_code) from public.hull_recipe_items hi join public.class_profile cp on cp.class_code = hi.class_code and cp.tech = 'F') <> 11 then
    raise exception 'PROOF 65 FAILED: the other hulls with a part are not the Caravela latina (4 kinds), the Nau (5) and 11 famous ships: %',
      (select jsonb_object_agg(x.class_code, x.n) from (select hi.class_code, count(*) as n from public.hull_recipe_items hi group by 1) x);
  end if;
  v_a := public.new_house(c_uid_a, 'Casa do Segundo 65', 'PRT');
  perform cmd.assume_identity(c_uid_a);
  select id into v_fa from public.fleets where player_id = v_a;
  v_src := world.yard_sources(v_lis, 'barca');
  v_yard := (select h.value from jsonb_array_elements(world.building_yard(v_lis) -> 'hulls') h where h.value ->> 'class' = 'barca');
  if v_src -> 'items' <> '[]'::jsonb or jsonb_array_length(v_src -> 'goods') <> 4 or v_yard -> 'items' <> '[]'::jsonb or not (v_yard ->> 'buildable')::boolean
     or exists (select 1 from jsonb_array_elements(v_src -> 'goods') e where e.value ->> 'port' is null or (e.value ->> 'ask')::numeric <= 0) then
    raise exception 'PROOF 65 FAILED: the yard''s reads do not serve a Barca of four goods, each with a seller, and no part: % / %', v_src, v_yard;
  end if;
  if (select jsonb_object_agg(e.value ->> 'code', e.value ->> 'port') from jsonb_array_elements(v_src -> 'goods') e)
       <> '{"timber": "FNC", "ships-nails": "LAR", "cordage": "PTH", "tar": "BER"}'::jsonb then
    raise exception 'PROOF 65 FAILED: the four sellers are not Funchal, La Rochelle, Portsmouth and Bergen (the errand below is written for them): %', v_src -> 'goods';
  end if;
  raise notice 'PASS: SECOND_SHIP_RECIPE — the Barca takes cordage, nails, tar and timber and no part; 13 other hulls keep a part (Caravela latina 4 kinds, Nau 5, 11 famous ships). At Lisbon the sheet names: %',
    (select string_agg(format('%s %s at %s %s nm (%s)', e.value ->> 'qty', e.value ->> 'code', e.value ->> 'name', e.value ->> 'miles', e.value ->> 'ask'), ', ' order by e.value ->> 'code') from jsonb_array_elements(v_src -> 'goods') e);

  -- ── SECOND_SHIP_ERRAND: the whole errand, the real commands, nothing placed ──
  select pl.ducats into v_start from public.players pl where pl.id = v_a;
  -- voyage 1: Funchal and back, the timber
  select * into t from pg_temp.tour_65(v_a, v_fa, array['FNC', 'LIS'], '{"FNC": {"timber": 40}}');
  a_nm := a_nm + t.nm; a_secs := a_secs + t.secs; a_goods := a_goods + t.goods; a_kinds := a_kinds + t.bought;
  v_r := cmd.issue(v_fa, 'BUILD barca Segunda');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_TIMBER' then
    raise exception 'PROOF 65 FAILED: with the timber in her hold BUILD answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  v_r := cmd.issue(v_fa, 'STORE timber 40');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: STORE timber was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_yard := (select h.value from jsonb_array_elements(world.building_yard(v_lis) -> 'hulls') h where h.value ->> 'class' = 'barca');
  if (select count(*) from jsonb_array_elements(v_yard -> 'goods') m where (m.value ->> 'have')::numeric >= (m.value ->> 'qty')::numeric) <> 1 then
    raise exception 'PROOF 65 FAILED: after the first voyage the yard does not read 1 line of 4 ready: %', v_yard -> 'goods';
  end if;
  -- voyage 2: the northern loop
  select * into t from pg_temp.tour_65(v_a, v_fa, array['LAR', 'PTH', 'BER', 'LIS'], '{"LAR": {"ships-nails": 10}, "PTH": {"cordage": 6}, "BER": {"tar": 8}}');
  a_nm := a_nm + t.nm; a_secs := a_secs + t.secs; a_goods := a_goods + t.goods; a_kinds := a_kinds + t.bought;
  for g in select * from (values ('ships-nails', 10), ('cordage', 6), ('tar', 8)) x(code, qty) loop
    v_r := cmd.issue(v_fa, format('STORE %s %s', g.code, g.qty));
    if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: STORE % was refused: % %', g.code, v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  end loop;
  select pl.ducats into v_purse from public.players pl where pl.id = v_a;
  v_labour := public.yard_labour(v_a, 'barca');
  v_r := cmd.issue(v_fa, 'BUILD barca Segunda');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: BUILD was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  a_labour := v_purse - (select pl.ducats from public.players pl where pl.id = v_a);
  select s.id, s.crew into v_ship, v_crew from public.ships s where s.player_id = v_a and s.name = 'Segunda';
  if v_ship is null or v_crew <> 0 or a_labour <> v_labour or (select count(*) from public.ships s where s.fleet_id = v_fa) <> 2
     or exists (select 1 from public.player_storage ps where ps.player_id = v_a) or exists (select 1 from public.player_items pi where pi.player_id = v_a) then
    raise exception 'PROOF 65 FAILED: the build did not give a second, uncrewed ship for the labour and the four stored goods: %', v_r;
  end if;
  v_crew := (v_yard ->> 'crew_required')::int;
  select pl.ducats into v_purse from public.players pl where pl.id = v_a;
  v_r := cmd.issue(v_fa, 'HIRE ' || v_crew);
  if not (v_r ->> 'ok')::boolean or (select s.crew from public.ships s where s.id = v_ship) <> v_crew then
    raise exception 'PROOF 65 FAILED: HIRE % did not crew her: % %', v_crew, v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  a_hire := v_purse - (select pl.ducats from public.players pl where pl.id = v_a);
  a_all := v_start - (select pl.ducats from public.players pl where pl.id = v_a);
  a_ports := 4;
  -- the fleet of two sails
  v_r := cmd.issue(v_fa, 'PROVISION DAYS 10');
  v_r := proof.sail(v_fa, 'FNC');
  if not (v_r ->> 'ok')::boolean or not exists (select 1 from public.voyages v where v.fleet_id = v_fa and v.status = 'SAILING') then
    raise exception 'PROOF 65 FAILED: with two crewed ships SAIL was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  if a_kinds <> 4 then raise exception 'PROOF 65 FAILED: the errand bought % kinds of good, not 4', a_kinds; end if;
  raise notice 'PASS: SECOND_SHIP_ERRAND — AFTER 0363, a new company at Lisbon, real commands only: 4 goods from 4 ports (Funchal; La Rochelle, Portsmouth, Bergen) in 2 voyages, % nm, % real minutes at sea. Coin: purse % -> % (% in all): goods %, the yard''s labour %, crew of % for %, provisions and port calls %. She has 2 crewed ships in one fleet, and it sails.',
    round(a_nm), round(a_secs / 60, 1), v_start, v_start - a_all, a_all, a_goods, a_labour, v_crew, a_hire, a_all - a_goods - a_labour - a_hire;

  -- ── SECOND_SHIP_KEEPS: a company midway through the OLD errand loses nothing ──
  v_c := public.new_house(c_uid_c, 'Casa do Meio 65', 'PRT');
  perform cmd.assume_identity(c_uid_c);
  select id into v_fc from public.fleets where player_id = v_c;
  -- what she had gathered under the old recipe: the goods of BOTH parts in her hold, and the four hull goods stored at Lisbon
  for g in select * from (values ('flax', 6), ('hemp', 4), ('iron', 4), ('tar', 2), ('cordage', 2)) x(code, qty) loop
    perform public.fleet_load(v_fc, g.code, g.qty, 50);
  end loop;
  for g in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'barca' loop
    perform public.storage_put(v_c, v_lis, g.good_id, g.qty, 1);
  end loop;
  -- she had already made one of the two parts
  v_r := cmd.issue(v_fc, 'MAKE anchor-and-cable');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: MAKE anchor-and-cable was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  -- the yard takes her order at once, and takes no part and no part good
  v_r := cmd.issue(v_fc, 'BUILD barca Metade');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: midway through the old errand BUILD was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  if (select pi.qty from public.player_items pi where pi.player_id = v_c and pi.port_id = v_lis and pi.item_code = 'anchor-and-cable') is distinct from 1
     or public.fleet_cargo_qty(v_fc, 'flax') <> 6 or public.fleet_cargo_qty(v_fc, 'cordage') <> 2 or public.fleet_cargo_qty(v_fc, 'tar') <> 1
     or exists (select 1 from public.player_storage ps where ps.player_id = v_c) or (select count(*) from public.ships s where s.fleet_id = v_fc) <> 2 then
    raise exception 'PROOF 65 FAILED: the build took a part or a part good of hers, or left hull goods behind';
  end if;
  -- the goods still make the other part
  v_r := cmd.issue(v_fc, 'MAKE suit-of-sails');
  if not (v_r ->> 'ok')::boolean or (select pi.qty from public.player_items pi where pi.player_id = v_c and pi.port_id = v_lis and pi.item_code = 'suit-of-sails') is distinct from 1 then
    raise exception 'PROOF 65 FAILED: her flax, cordage and tar no longer make a Suit of Sails: % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  -- a part she keeps still fits a ship
  v_r := cmd.issue(v_fc, 'FIT suit-of-sails Metade');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: FIT suit-of-sails was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_txt := v_r -> 'order' ->> 'result';
  if exists (select 1 from public.player_items pi where pi.player_id = v_c and pi.item_code = 'suit-of-sails')
     or (select pi.qty from public.player_items pi where pi.player_id = v_c and pi.item_code = 'anchor-and-cable') is distinct from 1 then
    raise exception 'PROOF 65 FAILED: the fitted sails did not leave her store, or the anchor did';
  end if;
  -- and a good she bought for a part still sells (hemp was all used by the anchor; she buys and sells iron at Lisbon's own market)
  v_r := cmd.issue(v_fc, 'BUY iron 2');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: BUY iron was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select pl.ducats into v_purse from public.players pl where pl.id = v_c;
  v_r := cmd.issue(v_fc, 'SELL iron 2');
  if not (v_r ->> 'ok')::boolean or (select pl.ducats from public.players pl where pl.id = v_c) <= v_purse then
    raise exception 'PROOF 65 FAILED: a part good no longer sells: % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  raise notice 'PASS: SECOND_SHIP_KEEPS — midway through the old errand (both parts'' goods in her hold, an Anchor & Cable made, the four hull goods stored) BUILD laid her Barca down at once; the Anchor & Cable is still hers, her flax 6, cordage 2 and tar stayed in her hold; they then made a Suit of Sails, which FIT took onto the new ship; a part good still sells for coin (% -> %)',
    v_purse, (select pl.ducats from public.players pl where pl.id = v_c);

  -- ── SECOND_SHIP_BEFORE: the two rows put back (the forward rollback's own rows), and the errand as it was ──
  insert into public.hull_recipe_items (class_code, item_code, qty) values ('barca', 'suit-of-sails', 1), ('barca', 'anchor-and-cable', 1);
  v_b := public.new_house(c_uid_b, 'Casa de Antes 65', 'PRT');
  perform cmd.assume_identity(c_uid_b);
  select id into v_fb from public.fleets where player_id = v_b;
  select pl.ducats into v_start from public.players pl where pl.id = v_b;
  if v_start <> (select 40000) then raise exception 'PROOF 65 FAILED: a new company starts with %, not 40000', v_start; end if;
  -- voyage 1: Naples for the hemp, Funchal for the timber, home; the iron at Lisbon's own quay
  select * into t from pg_temp.tour_65(v_b, v_fb, array['NAP', 'FNC', 'LIS'], '{"NAP": {"hemp": 4}, "FNC": {"timber": 40}}');
  b_nm := b_nm + t.nm; b_secs := b_secs + t.secs; b_goods := b_goods + t.goods; b_kinds := b_kinds + t.bought;
  select pl.ducats into v_purse from public.players pl where pl.id = v_b;
  v_r := cmd.issue(v_fb, 'BUY iron 4');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: Lisbon did not sell 4 iron: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  b_goods := b_goods + v_purse - (select pl.ducats from public.players pl where pl.id = v_b); b_kinds := b_kinds + 1;
  v_r := cmd.issue(v_fb, 'STORE timber 40');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: STORE timber (before) was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  -- voyage 2: the northern loop, now with Riga for the flax (Riga lies past one leg from Lisbon: it is reached from Portsmouth)
  select * into t from pg_temp.tour_65(v_b, v_fb, array['LAR', 'PTH', 'RIG', 'BER', 'LIS'], '{"LAR": {"ships-nails": 10}, "PTH": {"cordage": 8}, "RIG": {"flax": 6}, "BER": {"tar": 10}}');
  b_nm := b_nm + t.nm; b_secs := b_secs + t.secs; b_goods := b_goods + t.goods; b_kinds := b_kinds + t.bought;
  -- with the four hull goods stored and no part, the yard refuses for the parts: the rule as it was
  for g in select * from (values ('ships-nails', 10), ('cordage', 6), ('tar', 8)) x(code, qty) loop
    v_r := cmd.issue(v_fb, format('STORE %s %s', g.code, g.qty));
    if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: STORE % (before) was refused: % %', g.code, v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  end loop;
  v_r := cmd.issue(v_fb, 'BUILD barca Antiga');
  if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' <> 'E_NO_FITTINGS' then
    raise exception 'PROOF 65 FAILED: with the two rows put back and no part BUILD answered % %', v_r ->> 'error_code', v_r ->> 'error_message';
  end if;
  v_before := v_r ->> 'error_message';
  v_r := cmd.issue(v_fb, 'MAKE suit-of-sails');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: MAKE suit-of-sails (before) was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  v_r := cmd.issue(v_fb, 'MAKE anchor-and-cable');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: MAKE anchor-and-cable (before) was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  select pl.ducats into v_purse from public.players pl where pl.id = v_b;
  v_r := cmd.issue(v_fb, 'BUILD barca Antiga');
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: BUILD (before) was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  b_labour := v_purse - (select pl.ducats from public.players pl where pl.id = v_b);
  if exists (select 1 from public.player_items pi where pi.player_id = v_b) then
    raise exception 'PROOF 65 FAILED: with the two rows put back the build did not take her two parts';
  end if;
  select pl.ducats into v_purse from public.players pl where pl.id = v_b;
  v_r := cmd.issue(v_fb, 'HIRE ' || v_crew);
  if not (v_r ->> 'ok')::boolean then raise exception 'PROOF 65 FAILED: HIRE (before) was refused: % %', v_r ->> 'error_code', v_r ->> 'error_message'; end if;
  b_hire := v_purse - (select pl.ducats from public.players pl where pl.id = v_b);
  b_all := v_start - (select pl.ducats from public.players pl where pl.id = v_b);
  b_ports := 6;
  if b_kinds <> 7 then raise exception 'PROOF 65 FAILED: the old errand bought % kinds of good, not 7', b_kinds; end if;
  if not (a_nm < b_nm and a_secs < b_secs and a_all < b_all and a_labour = b_labour and a_hire = b_hire) then
    raise exception 'PROOF 65 FAILED: the new errand is not shorter and cheaper than the old one with the same labour and crew: after % nm, % s, % d.; before % nm, % s, % d.', a_nm, a_secs, a_all, b_nm, b_secs, b_all;
  end if;
  raise notice 'PASS: SECOND_SHIP_BEFORE — BEFORE 0363 (the two rows put back; the yard refused: %): 7 goods from 6 ports (Naples, Funchal; La Rochelle, Portsmouth, Riga, Bergen; iron at Lisbon) in 2 voyages, % nm, % real minutes at sea, % in all (goods %, labour %, crew %, provisions and port calls %). AFTER: 4 goods from 4 ports, % nm, % real minutes, % in all (goods %, labour %, crew %, provisions and port calls %). Saved: % nm, % real minutes, % d.',
    v_before, round(b_nm), round(b_secs / 60, 1), b_all, b_goods, b_labour, b_hire, b_all - b_goods - b_labour - b_hire,
    round(a_nm), round(a_secs / 60, 1), a_all, a_goods, a_labour, a_hire, a_all - a_goods - a_labour - a_hire,
    round(b_nm - a_nm), round((b_secs - a_secs) / 60, 1), b_all - a_all;
end
$p$;
