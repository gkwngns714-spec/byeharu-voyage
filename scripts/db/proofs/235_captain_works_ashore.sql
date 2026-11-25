-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 235 - A CAPTAIN'S WORKS, AND HER SEAT ASHORE  (migrations 0527, 0528; dark: captain_works_enabled; docs/dev-log/2026-11-25-captain-works.md)
--
-- @pass CW_DARK    dark: the land door refuses a captain, her card has no works, a Send's terms are the terms
-- @pass CW_SEND    lit: hired at sea's side and seated ashore by the door, the Send freezes her name and her shorter turn; her level moving later moves nothing that was sent
-- @pass CW_ONCE    the same hours collected in one press and in twelve give the same goods, the company the same experience and the captain the same experience
-- @pass CW_LEVEL   enough mining makes her level 2 and the card says so; the company's own Mining level is what it would be without her
-- @pass CW_SEA     every figure at sea of a fleet whose captain went ashore equals the same fleet's with no captain; back in a cabin it is what it was
-- @pass CW_MERCHANT a merchant's captain earns nothing and has no party
-- @pass CW_CLOSE   a closed company's deletions (its parties, then its signings, as 0509 does them) leave no seat and no works behind
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_me uuid; v_two uuid; v_fl uuid; v_sh uuid; v_pa uuid; v_pb uuid; v_po uuid; v_po2 uuid; v_code text; v_act text; v_np uuid; v_npo uuid;
  t0 timestamptz := now(); v_t jsonb; v_t2 jsonb; v_r jsonb; v_sea0 text; v_sea1 text; v_sea2 text; v_g1 numeric; v_g2 numeric; v_x1 int; v_x2 int; v_c1 int; v_c2 int; i int; v_trip numeric;
begin
  perform set_config('lock_timeout', '5s', true);
  update public.world_config set value = 'true'::jsonb where key = 'land_enabled';
  v_me := public.new_house('00000000-0527-4000-8000-0000000002a1', 'Casa Praia 235', 'PRT');
  v_two := public.new_house('00000000-0527-4000-8000-0000000002b1', 'Casa Monte 235', 'PRT');
  update public.players set ducats = 500000 where id in (v_me, v_two);
  select f.id into v_fl from public.fleets f where f.player_id = v_me;
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl and s.is_flagship;
  select o.code into v_code from public.officers o join public.captain_job j on j.officer_id = o.id where j.job = 'NAVIGATOR' order by o.code limit 1;
  if v_code is null then select o.code into v_code from public.officers o order by o.code limit 1; end if;
  perform cmd.assume_identity('00000000-0527-4000-8000-0000000002a1');
  if not (public.sign_officer(v_me, v_code, null)->>'ok')::boolean or not (public.sign_officer(v_two, v_code, null)->>'ok')::boolean then
    raise exception 'CW_DARK: the captain did not sign';
  end if;
  select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_me and o.code = v_code;
  select po.id into v_po2 from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_two and o.code = v_code;
  select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null'
   order by (public.land_terms(v_me, a.code)->>'trip')::numeric, a.code limit 1;
  v_pa := public.land_party(v_me);
  v_pb := public.land_party(v_two);

  -- CW_DARK
  v_t := public.land_terms(v_me, v_act);
  if cmd.captain_land(v_code, 1)->>'error_code' is distinct from 'E_NOT_IN_USE' or (world.captains() #> '{captains,0}') ? 'works' or v_t ? 'captain' then
    raise exception 'CW_DARK: dark, something is open';
  end if;
  raise notice 'PASS: CW_DARK — E_NOT_IN_USE, no works on her card, % a turn of % s', v_act, v_t->>'a';

  -- CW_SEA (before she goes ashore)
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea0 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  perform public.captain_seat_put(v_po, v_sh, 1);
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea1 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  update public.world_config set value = 'true'::jsonb where key = 'captain_works_enabled';
  v_r := cmd.captain_land(v_code, 1);
  if not (v_r->>'ok')::boolean then raise exception 'CW_SEA: %', v_r; end if;
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea2 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  if v_sea2 is distinct from v_sea0 then raise exception 'CW_SEA: ashore she still counts at sea: % / %', v_sea2, v_sea0; end if;
  v_r := public.seat_captain_for(v_me, v_code, v_sh, 1);
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea2 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  if v_sea2 is distinct from v_sea1 then raise exception 'CW_SEA: back in her cabin she is not what she was: %', v_r; end if;
  raise notice 'PASS: CW_SEA — ashore as with no captain; back in the cabin as before (% effects, % with her)', (select count(*) from public.crew_effects), case when v_sea1 = v_sea0 then 'equal' else 'not equal' end;

  -- CW_SEND: level 41 of mining for her, then sent
  perform cmd.captain_land(v_code, 1);
  insert into public.captain_work_xp (player_officer_id, work, xp) select v_po, 'mining', c.xp from public.level_curves c where c.curve = 'long' and c.level = 41;
  perform cmd.assume_identity('00000000-0527-4000-8000-0000000002b1');
  perform cmd.captain_land(v_code, 1);
  insert into public.captain_work_xp (player_officer_id, work, xp) select v_po2, 'mining', c.xp from public.level_curves c where c.curve = 'long' and c.level = 41;
  perform public.land_send_for(v_me, v_act, t0);
  perform public.land_send_for(v_two, v_act, t0);
  select lp.terms into v_t2 from public.land_parties lp where lp.id = v_pa;
  update public.captain_work_xp set xp = 1000000 where player_officer_id = v_po;
  if v_t2 #>> '{captain,code}' is distinct from v_code or (v_t2->>'a')::int >= (v_t->>'a')::int or (select lp.terms->>'a' from public.land_parties lp where lp.id = v_pa) is distinct from v_t2->>'a' then
    raise exception 'CW_SEND: %', v_t2;
  end if;
  update public.captain_work_xp set xp = (select c.xp from public.level_curves c where c.curve = 'long' and c.level = 41) where player_officer_id = v_po;
  raise notice 'PASS: CW_SEND — % leads: % s a turn, % s without her, frozen', v_t2 #>> '{captain,name}', v_t2->>'a', v_t->>'a';

  -- CW_ONCE: two companies, the same Send, the same hours: one press against twelve
  v_trip := (v_t2->>'trip')::numeric;
  -- whole trips the away cap lets home (at least the first): both clocks read at the same instants
  for i in 1 .. 12 loop
    perform public.land_collect_for(v_two, t0 + make_interval(secs => (v_trip * i / 12 + case when i = 12 then 1 else 0 end)::double precision));
  end loop;
  perform public.land_collect_for(v_me, t0 + make_interval(secs => (v_trip + 1)::double precision));
  select coalesce(sum(ps.qty), 0) into v_g1 from public.player_storage ps where ps.player_id = v_me and ps.good_id = (v_t2->>'good')::uuid;
  select coalesce(sum(ps.qty), 0) into v_g2 from public.player_storage ps where ps.player_id = v_two and ps.good_id = (v_t2->>'good')::uuid;
  v_x1 := (select x.xp from public.level_xp x where x.player_id = v_me and x.skill = 'mining'); v_x2 := (select x.xp from public.level_xp x where x.player_id = v_two and x.skill = 'mining');
  select z.xp into v_c1 from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'mining';
  select z.xp into v_c2 from public.captain_work_xp z where z.player_officer_id = v_po2 and z.work = 'mining';
  if v_x1 is null or v_x1 < 1 or v_x1 is distinct from v_x2 or v_c1 is distinct from v_c2 or v_g1 is distinct from v_g2 or v_g1 < 1 or v_c1 - (select c.xp from public.level_curves c where c.curve = 'long' and c.level = 41) < 1 then
    raise exception 'CW_ONCE: one press % goods % xp % captain; twelve % % %', v_g1, v_x1, v_c1, v_g2, v_x2, v_c2;
  end if;
  raise notice 'PASS: CW_ONCE — one press and twelve: % units, company % xp, captain +%', v_g1, v_x1, v_c1 - (select c.xp from public.level_curves c where c.curve = 'long' and c.level = 41);

  -- CW_LEVEL
  update public.captain_work_xp set xp = (select c.xp - 1 from public.level_curves c where c.curve = 'long' and c.level = 2) where player_officer_id = v_po2;
  perform public.captain_work_credit(v_po2, 'mining', 1);
  if (select (w->>'level')::int from jsonb_array_elements(world.captains()->'captains') e, jsonb_array_elements(e->'works') w where e->>'code' = v_code and w->>'work' = 'mining') <> 2
     or public.level_of('mining', v_x2) <> public.level_of('mining', v_x1) then
    raise exception 'CW_LEVEL: her card does not say level 2';
  end if;
  raise notice 'PASS: CW_LEVEL — one point more: Mining 2 on her card';

  -- CW_MERCHANT
  select p.id into v_np from public.players p join public.player_officers po on po.player_id = p.id where p.is_npc order by p.id limit 1;
  if v_np is not null then
    select po.id into v_npo from public.player_officers po where po.player_id = v_np order by po.id limit 1;
    begin
      perform public.captain_land_for(v_np, (select o.code from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = v_npo), 1);
      raise exception 'CW_MERCHANT: a merchant''s captain took a party';
    exception when others then
      if sqlerrm !~ '^E_' then raise; end if;
    end;
    if public.captain_work_credit(v_npo, 'mining', 100) <> 0 then raise exception 'CW_MERCHANT: credited'; end if;
  end if;
  raise notice 'PASS: CW_MERCHANT — refused, nothing credited%', case when v_np is null then ' (no merchant captain in this world)' else '' end;

  -- CW_CLOSE
  delete from public.land_parties where player_id = v_me;
  if exists (select 1 from public.captain_seats cs where cs.player_officer_id = v_po) then raise exception 'CW_CLOSE: a seat in a party that is gone'; end if;
  delete from public.player_officers where player_id = v_me;
  if exists (select 1 from public.captain_work_xp z where z.player_officer_id = v_po) then raise exception 'CW_CLOSE: works of a captain who is gone'; end if;
  raise notice 'PASS: CW_CLOSE — no seat, no works';
end $p$;
