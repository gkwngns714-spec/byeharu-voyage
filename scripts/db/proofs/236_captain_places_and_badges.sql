-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 236 - CAPTAIN PLACES AND HONOR BADGES  (migrations 0529, 0530; dark: captain_places_enabled, honor_enabled; docs/dev-log/2026-11-25-captain-works.md)
--
-- @pass CP_DARK   dark: a founding signs nobody and the Inn hires a third
-- @pass CP_LIGHT  the light step tops every player's company to two and leaves the one with four at four; again, nobody; no purse moves
-- @pass CP_INN    lit, full: the Inn's own door refuses in plain words and takes nothing; one let go, the same door hires; a merchant's signing asks no place
-- @pass CP_BOARD  lit, full: the HQ board offers no captain to hire
-- @pass CP_OPEN   a priced third place opens for its level, Reputation and coin: the coin is the home city's, the Reputation is booked, and a third is hired
-- @pass HB_BOOK   badges earned, spent and refused past their balance; not Reputation, not coin
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_a uuid; v_b uuid; v_lis uuid; v_r jsonb; v_c text; v_d0 numeric; v_p bigint; v_t0 bigint; v_t1 bigint; v_rep int; v_np uuid; v_n int; v_tl int; v_k jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('reputation_on', 'hq_board_enabled');
  v_a := public.new_house('00000000-0529-4000-8000-0000000002a1', 'Casa Lugar 236', 'PRT');
  v_b := public.new_house('00000000-0529-4000-8000-0000000002b1', 'Casa Quatro 236', 'PRT');
  select f.port_id into v_lis from public.fleets f where f.player_id = v_a;
  update public.players set ducats = 500000 where id in (v_a, v_b);
  perform cmd.assume_identity('00000000-0529-4000-8000-0000000002b1');
  -- CP_DARK
  if exists (select 1 from public.player_officers po where po.player_id in (v_a, v_b)) then raise exception 'CP_DARK: a founding signed somebody'; end if;
  v_n := 0;
  for v_c in select o.code from public.officers o where world.inn_present(o.id, v_lis, world.inn_shift()) order by o.wage_ducats, o.code limit 3 loop
    v_r := cmd.hire_officer(v_c, null);
    if not (v_r->>'ok')::boolean then raise exception 'CP_DARK: %', v_r; end if;
    v_n := v_n + 1;
  end loop;
  for v_c in select o.code from public.officers o where not exists (select 1 from public.player_officers po where po.player_id = v_b and po.officer_id = o.id) order by o.code limit 4 - v_n loop
    perform public.sign_officer(v_b, v_c, null);
  end loop;
  raise notice 'PASS: CP_DARK — nobody at the founding; the Inn at Lisbon hired % of % asked', v_n, v_n;

  -- CP_BOARD, first dark: the board offers one
  if not exists (select 1 from jsonb_array_elements(coalesce(public.hq_board_for(v_a)->'moves', '[]'::jsonb)) m where m->>'kind' = 'crew') then
    raise exception 'CP_BOARD: dark, no captain is offered: the scene proves nothing';
  end if;
  -- CP_LIGHT
  select sum(ducats) into v_d0 from public.players where id in (v_a, v_b);
  v_r := public.captain_places_light();
  v_k := public.captain_places_light();
  if (select count(*) from public.player_officers po where po.player_id = v_a) <> 2 or (select count(*) from public.player_officers po where po.player_id = v_b) <> 4
     or (v_k->>'signed')::int <> 0 or not (v_k->>'on')::boolean or (select sum(ducats) from public.players where id in (v_a, v_b)) <> v_d0 then
    raise exception 'CP_LIGHT: % then %', v_r, v_k;
  end if;
  raise notice 'PASS: CP_LIGHT — % signed in this world, then 0; four kept; no purse moved', v_r->>'signed';

  -- CP_INN
  perform cmd.assume_identity('00000000-0529-4000-8000-0000000002a1');
  select o.code into v_c from public.officers o where world.inn_present(o.id, v_lis, world.inn_shift())
     and not exists (select 1 from public.player_officers po where po.player_id = v_a and po.officer_id = o.id) order by o.wage_ducats, o.code limit 1;
  if v_c is null then raise exception 'CP_INN: nobody is in the room at Lisbon: the scene proves nothing'; end if;
  select ducats into v_p from public.players where id = v_a;
  v_r := cmd.hire_officer(v_c, null);
  if v_r->>'error_code' is distinct from 'E_CAPTAIN_ROOM' or (select ducats from public.players where id = v_a) <> v_p then raise exception 'CP_INN: full, %', v_r; end if;
  -- CP_BOARD
  if exists (select 1 from jsonb_array_elements(coalesce(public.hq_board_for(v_a)->'moves', '[]'::jsonb)) m where m->>'kind' = 'crew') then
    raise exception 'CP_BOARD: the board offers a captain she cannot hire';
  end if;
  raise notice 'PASS: CP_BOARD — no captain offered';
  v_k := cmd.captain_dismiss((select o.code from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_a order by o.code limit 1));
  if not (v_k->>'ok')::boolean then raise exception 'CP_INN: %', v_k; end if;
  v_k := cmd.hire_officer(v_c, null);
  if not (v_k->>'ok')::boolean then raise exception 'CP_INN: a place free, %', v_k; end if;
  select p.id into v_np from public.players p where p.is_npc order by p.id limit 1;
  if v_np is not null and public.captain_places_full(v_np) is null then raise exception 'CP_INN: a merchant'; end if;
  raise notice 'PASS: CP_INN — "%"; one let go, % hired', v_r->>'error_message', v_c;

  -- CP_OPEN
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_tl := (select sum((s->>'level')::int) from jsonb_array_elements(public.level_skills_card(v_a, public.player_progress(v_a))->'skills') s);
  update public.captain_places set total_level = v_tl, reputation = 60, ducats = 25000 where place = 3;
  perform public.reputation_credit(v_a, 'level', 75, 'proof-236');
  select b.balance into v_rep from public.reputation_balance b where b.player_id = v_a;
  select ducats into v_p from public.players where id = v_a;
  v_t0 := public.treasury_balance(public.home_port_of(v_a));
  v_k := world.captains()->'places';
  v_r := cmd.captain_place();
  v_t1 := public.treasury_balance(public.home_port_of(v_a));
  if not (v_r->>'ok')::boolean or (select ducats from public.players where id = v_a) <> v_p - 25000 or (select b.balance from public.reputation_balance b where b.player_id = v_a) <> v_rep - 60
     or v_t1 is distinct from v_t0 + 25000 or public.captain_places_full(v_a) then
    raise exception 'CP_OPEN: % (treasury % to %)', v_r, v_t0, v_t1;
  end if;
  select o.code into v_c from public.officers o where not exists (select 1 from public.player_officers po where po.player_id = v_a and po.officer_id = o.id) order by o.wage_ducats, o.code limit 1;
  if not (public.sign_officer(v_a, v_c, null)->>'ok')::boolean then raise exception 'CP_OPEN: a third did not sign'; end if;
  raise notice 'PASS: CP_OPEN — card %; the home city +25,000, Reputation -60, a third signed', v_k->'next';

  -- HB_BOOK
  update public.world_config set value = 'true'::jsonb where key = 'honor_enabled';
  select b.balance into v_rep from public.reputation_balance b where b.player_id = v_a;
  select ducats into v_p from public.players where id = v_a;
  perform public.honor_credit(v_a, 'land', 12, 'land:proof');
  perform public.honor_credit(v_a, 'captain_upgrade', -10);
  begin
    perform public.honor_credit(v_a, 'captain_upgrade', -3);
    raise exception 'HB_BOOK: spent past the balance';
  exception when others then
    if sqlerrm !~ '^E_NOT_ENOUGH_HONOR' then raise; end if;
    v_c := sqlerrm;
  end;
  if (world.captains()->>'honor')::int <> 2 or (select b.balance from public.reputation_balance b where b.player_id = v_a) <> v_rep or (select ducats from public.players where id = v_a) <> v_p then
    raise exception 'HB_BOOK: the badges are not 2, or Reputation or coin moved';
  end if;
  raise notice 'PASS: HB_BOOK — 12 earned, 10 spent, 2 left; "%"', v_c;
end $p$;
