-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 239 - WOODCUTTING  (migration 0531, dark: land_wood_enabled; docs/dev-log/2026-11-25-captain-works.md)
--
-- @pass WO_DARK    dark: the Land read, the Levels card, Send and the workers' actions know no wood; Mining's and Smithing's reads are the text they were
-- @pass WO_FACE    lit: the Land read serves Woodcutting's 31 jobs with the lands they lie on, and the Levels card its line; Mining's jobs are the text they were
-- @pass WO_TRIP    a company of Lisbon cuts Timber: goods in Storage at a cost of 0, experience to Woodcutting alone; Cork asks level 5; the same trip collected in one press and in eight
-- @pass WO_CAPTAIN the party's captain earns Woodcutting, and her level shortens her turn in the woods and not in the mine
-- @pass WO_EXPED   an expedition gathers wood: its card, the load home, the company's and the captain's Woodcutting
-- @pass WO_LOAD    gathering's load at 10, 20 and 48 hands under the figures of today and of the proposal (printed; a proposal, nothing is set)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_me uuid; v_two uuid; v_pt uuid; v_code text; v_po uuid; v_m0 jsonb; v_m1 jsonb; v_w jsonb; v_t jsonb; v_t2 jsonb; v_r jsonb; v_at timestamptz := now(); v_a int; v_b int; v_x1 int; v_x2 int; v_q1 numeric; v_q2 numeric; i int;
  x record; v_txt text; v_c0 int; v_c1 int; v_q0 numeric;
begin
  v_me := public.new_house('00000000-0531-4000-8000-0000000002a1', 'Casa da Lenha 239', 'PRT');
  v_two := public.new_house('00000000-0531-4000-8000-0000000002b1', 'Casa do Pinho 239', 'PRT');
  v_pt := public.home_port_of(v_me);
  update public.players set ducats = 400000 where id in (v_me, v_two);
  update public.ports set crew_pool = 400 where id = v_pt;
  perform cmd.assume_identity('00000000-0531-4000-8000-0000000002a1');
  update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'land_smith_enabled', 'captain_works_enabled', 'rounds_enabled', 'land_expedition_enabled');
  update public.world_config set value = '[48, 2]'::jsonb where key = 'land_crew_cap';
  perform public.land_party(v_me); perform public.land_party(v_two);

  -- WO_DARK
  v_m0 := world.land('mining') - 'now' - 'skills';
  if (world.land('mining')->'skills') ? 'woodcutting' or world.land('woodcutting') <> '{"enabled": true, "company": false}'::jsonb
     or cmd.land_send('timber')->>'error_code' is distinct from 'E_NOT_IN_USE'
     or exists (select 1 from jsonb_array_elements(public.level_skills_card(v_me, public.player_progress(v_me))->'skills') e where e->>'code' = 'woodcutting')
     or public.land_actions_for(v_me, 1)::text like '%woodcutting%' then
    raise exception 'WO_DARK: wood is open: %', world.land('woodcutting');
  end if;
  raise notice 'PASS: WO_DARK';

  -- WO_FACE
  update public.world_config set value = 'true'::jsonb where key = 'land_wood_enabled';
  v_m1 := world.land('mining') - 'now' - 'skills';
  v_w := world.land('woodcutting');
  if v_m1 is distinct from v_m0 or jsonb_array_length(v_w->'jobs') <> 31 or v_w #>> '{skill,code}' <> 'woodcutting' or (v_w #>> '{skill,top}')::int <> 100
     or exists (select 1 from jsonb_array_elements(v_w->'jobs') j where (j->>'open')::boolean and j->>'region' is null)
     or not exists (select 1 from jsonb_array_elements(public.level_skills_card(v_me, public.player_progress(v_me))->'skills') e where e->>'code' = 'woodcutting' and e->>'word' = 'Woodcutting') then
    raise exception 'WO_FACE: %', left(v_w::text, 400);
  end if;
  select string_agg(format('%s (%s)', j->>'code', j->>'level'), ', ') into v_txt from (select j from jsonb_array_elements(v_w->'jobs') j where (j->>'home')::boolean limit 6) z;
  raise notice 'PASS: WO_FACE — 31 jobs; at home in Lisbon: %', v_txt;

  -- WO_TRIP
  if jsonb_typeof(public.land_terms(v_me, 'cork')->'short') <> 'object' then raise exception 'WO_TRIP: cork is open at level 1'; end if;
  v_t := public.land_terms(v_me, 'timber');
  perform public.land_send_for(v_me, 'timber', v_at);
  perform public.land_send_for(v_two, 'timber', v_at);
  perform public.land_collect_for(v_me, v_at + make_interval(secs => (v_t->>'trip')::double precision + 1));
  for i in 1 .. 8 loop
    perform public.land_collect_for(v_two, v_at + make_interval(secs => ((v_t->>'trip')::numeric * i / 8 + case when i = 8 then 1 else 0 end)::double precision));
  end loop;
  select z.xp into v_x1 from public.level_xp z where z.player_id = v_me and z.skill = 'woodcutting';
  select z.xp into v_x2 from public.level_xp z where z.player_id = v_two and z.skill = 'woodcutting';
  select sum(ps.qty), max(ps.basis) into v_q1, v_q0 from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_me and g.code = 'timber';
  select sum(ps.qty) into v_q2 from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_two and g.code = 'timber';
  if v_x1 is null or v_x1 <> v_x2 or v_q1 <> v_q2 or coalesce(v_q0, 0) <> 0 or exists (select 1 from public.level_xp z where z.player_id = v_me and z.skill = 'mining')
     or public.level_of('woodcutting', v_x1) < 2 then
    raise exception 'WO_TRIP: % / % xp, % / % timber at %', v_x1, v_x2, v_q1, v_q2, v_q0;
  end if;
  update public.level_xp z set xp = public.level_begins('woodcutting', 5)::int where z.player_id = v_me and z.skill = 'woodcutting';
  if jsonb_typeof(public.land_terms(v_me, 'cork')->'short') <> 'null' then raise exception 'WO_TRIP: cork is shut at level 5'; end if;
  update public.level_xp z set xp = v_x1 where z.player_id = v_me and z.skill = 'woodcutting';
  raise notice 'PASS: WO_TRIP — % Timber and % xp a trip of % s; Cork at 5', v_q1, v_x1, v_t->>'trip';

  -- WO_CAPTAIN
  update public.land_parties set action = null, terms = null, started_at = null, region_id = null, touched_at = null, booked = 0 where player_id = v_me;
  select o.code into v_code from public.officers o order by o.code limit 1;
  perform public.sign_officer(v_me, v_code, null);
  select po.id into v_po from public.player_officers po where po.player_id = v_me;
  perform cmd.captain_land(v_code, 1);
  v_a := (public.land_terms(v_me, 'timber')->>'a')::int;
  v_b := (public.land_terms(v_me, 'iron')->>'a')::int;
  insert into public.captain_work_xp (player_officer_id, work, xp) select v_po, 'woodcutting', c.xp from public.level_curves c where c.curve = 'long' and c.level = 41;
  if (public.land_terms(v_me, 'timber')->>'a')::int <> round(v_a * 0.9)::int or (public.land_terms(v_me, 'iron')->>'a')::int <> v_b then raise exception 'WO_CAPTAIN: her turn'; end if;
  select z.xp into v_c0 from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'woodcutting';
  v_t2 := public.land_terms(v_me, 'timber');
  perform public.land_send_for(v_me, 'timber', v_at);
  v_r := public.land_collect_for(v_me, v_at + make_interval(secs => (v_t2->>'trip')::double precision + 1));
  -- (the experience of two trips within land_book_minutes is booked together: the writer is asked again past it)
  v_r := public.land_collect_for(v_me, v_at + make_interval(secs => (v_t2->>'trip')::double precision + 3000));
  select z.xp into v_c1 from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'woodcutting';
  if v_c1 <= v_c0 then raise exception 'WO_CAPTAIN: she earned nothing: %', v_r; end if;
  raise notice 'PASS: WO_CAPTAIN — % s a turn, % s with her at 41; +% Woodcutting', v_a, v_t2->>'a', v_c1 - v_c0;

  -- WO_EXPED
  update public.land_parties set action = null, terms = null, started_at = null, region_id = null, touched_at = null, booked = 0, waiting = 0, waiting_good = null where player_id = v_me;
  v_r := world.land_expedition(v_code, '{"work": "land_gather", "target": "timber", "crew": 20}');
  if not exists (select 1 from jsonb_array_elements(v_r->'targets') t where t->>'target' = 'timber' and (t->>'open')::boolean) or v_r->'card' ? 'short' then raise exception 'WO_EXPED: %', v_r->'card'; end if;
  v_t := v_r->'card';
  select z.xp into v_x1 from public.level_xp z where z.player_id = v_me and z.skill = 'woodcutting';
  select coalesce(sum(ps.qty), 0) into v_q1 from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_me and g.code = 'timber';
  v_r := public.land_expedition_send_for(v_me, v_code, '{"work": "land_gather", "target": "timber", "crew": 20}', v_at - interval '13 hours');
  perform public.land_expedition_settle((select rr.party_id from public.round_runs rr where rr.player_id = v_me), v_at);
  select z.xp into v_x2 from public.level_xp z where z.player_id = v_me and z.skill = 'woodcutting';
  select coalesce(sum(ps.qty), 0) into v_q2 from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_me and g.code = 'timber';
  select z.xp into v_c0 from public.captain_work_xp z where z.player_officer_id = v_po and z.work = 'woodcutting';
  if v_q2 - v_q1 <> (v_t->>'most')::int * (v_t->>'units')::int or v_x2 <= v_x1 or v_c0 <= v_c1 then raise exception 'WO_EXPED: % timber, % xp, % captain', v_q2 - v_q1, v_x2 - v_x1, v_c0 - v_c1; end if;
  raise notice 'PASS: WO_EXPED — 20 hands: % rounds (%), % Timber home', v_t->>'most', v_t->>'why', v_q2 - v_q1;

  -- WO_LOAD: the stop rule on the same terms, the carry and the stores as the only figures moved
  perform cmd.captain_land(v_code, null);
  for x in select t.target, c.crew, f.name, f.carry, f.base, f.man, f.share
             from (values ('timber'), ('coal')) t(target) cross join (values (10), (20), (48)) c(crew)
            cross join (values ('today', 1.0, 0.3, 0.01, 0.5), ('A', 2.0, 0.3, 0.01, 0.35), ('B', 3.0, 0.3, 0.02, 0.35)) f(name, carry, base, man, share) order by 1, 2, 3 loop
    update public.world_config set value = to_jsonb(x.carry) where key = 'land_crew_carry';
    update public.world_config set value = to_jsonb(x.base) where key = 'land_round_stores';
    update public.world_config set value = to_jsonb(x.man) where key = 'land_round_stores_crew';
    v_t := public.land_expedition_terms(v_me, v_po, jsonb_build_object('work', 'land_gather', 'target', x.target, 'crew', x.crew, 'stores', round(x.crew * x.carry * x.share, 1)), '00000000-0531-4000-8000-000000000239');
    raise notice 'TIMING: % crew % figures %: % rounds (%), % units, % h, bill %', x.target, x.crew, x.name, v_t->>'most', v_t->>'why', (v_t->>'most')::int * (v_t->>'units')::int,
      round(((v_t->>'most')::int * (v_t->>'seconds')::numeric) / 3600, 1), v_t->>'total';
  end loop;
  raise notice 'PASS: WO_LOAD — printed';
end $p$;
