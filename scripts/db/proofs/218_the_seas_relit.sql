-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 218 - THE SEAS RELIT  (migration 0514; docs/dev-log/2026-11-25-seas-relit.md)
--
--   The read before the light, its step, and what a company meets after it. Three companies of its own beside whatever companies this world holds; the light is played
--   here and rolled back by proof.mjs. Nothing asks a price, a die or the world's age; the counts of this world's companies are read, never assumed.
--
-- @pass SR_READ     the read names every human company and every fleet once, a level-1 barca at Lisbon inside her rung, one at Acapulco beyond it on a pass, one bound there
--                   read where she is bound; the table's harbours and the openings by rung are the approved counts; nothing is written
-- @pass SR_GUARD    a wrong mark, and no mark, light nothing and say why
-- @pass SR_LIGHT    with the table's mark the switch is lit and one news row written; a second time refuses
-- @pass SR_LIVE     lit: home waters sail, Africa is refused by its level with the figures, the barca at Acapulco sails home and nowhere further, the one under way arrives;
--                   no fleet of any company of this world is without a way home
-- @pass SR_LONGWAY  lit, a company at the level of rung 6 with a hull that holds the Cape is offered Busan by the pathfinder with no sealed sea on the way; at level 5 not
-- @pass SR_WORD     the wall says Wave resistance
-- @pass SR_BACK     the switch false again: nothing is refused for a sea
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_a uuid; v_b uuid; v_c uuid; v_fa uuid; v_fb uuid; v_fc uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS'); v_aca uuid := (select id from public.ports where code = 'ACA'); v_bus uuid := (select id from public.ports where code = 'BUS');
  v jsonb; v_x jsonb; v_g jsonb; v_t timestamptz; v_ms numeric; v_cfg text; v_news bigint; v_voy uuid; r record; v_bad text; v_n int; v_path text[];
begin
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
  v_a := public.new_house('00000000-0514-4000-8000-0000000002a1', 'Casa Dentro 218', 'PRT');
  v_b := public.new_house('00000000-0514-4000-8000-0000000002a2', 'Casa Fora 218', 'PRT');
  v_c := public.new_house('00000000-0514-4000-8000-0000000002a3', 'Casa Vela 218', 'PRT');
  select id into v_fa from public.fleets where player_id = v_a;
  select id into v_fb from public.fleets where player_id = v_b;
  select id into v_fc from public.fleets where player_id = v_c;
  update public.fleets set port_id = v_aca where id = v_fb;
  update public.ships s set crew = c.crew_required, water_t = 1000, food_t = 1000 from public.ship_classes c where c.id = s.class_id and s.fleet_id in (v_fa, v_fb, v_fc);
  v_voy := voyage.depart(v_fc, jsonb_build_array(jsonb_build_object('a', '[16.6,-100.2]'::jsonb, 'b', '[16.7,-99.95]'::jsonb, 'nm', voyage.fleet_speed(v_fc) * 12, 'hazard_mult', 0,
             'sea_id', (select sea_id from public.ports where id = v_aca))), v_lis, v_aca, now());

  -- ── SR_READ ──
  select md5(string_agg(c.key || c.value::text, ',' order by c.key)) into v_cfg from public.world_config c;
  select count(*) into v_news from public.world_news;
  v_t := clock_timestamp();
  v := public.seas_relit_ready();
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  select e into v_x from jsonb_array_elements(v->'companies') e where e->>'company' = 'Casa Fora 218';
  if (v->>'company_count')::int <> (select count(*) from public.players where not is_npc)
     or (v->>'fleets')::int <> (select count(*) from public.fleets f join public.players p on p.id = f.player_id and not p.is_npc)
     or v_x->'fleets'->0->>'at' <> 'ACA' or (v_x->'fleets'->0->>'inside')::boolean or v_x->'fleets'->0->>'way_home' <> 'pass' or (v_x->>'rung')::int <> 1
     or (v_x->'fleets'->0->>'sea_rung')::int <> 8 or (v->>'trapped')::int <> 0 or (v->>'beyond')::int < 2
     or (select e->'fleets'->0->>'at' from jsonb_array_elements(v->'companies') e where e->>'company' = 'Casa Vela 218') <> 'ACA'
     or (select (e->'fleets'->0->>'inside')::boolean and e->'fleets'->0->>'way_home' = 'home' from jsonb_array_elements(v->'companies') e where e->>'company' = 'Casa Dentro 218') is not true
     or (select jsonb_agg(e->'harbours') from jsonb_array_elements(v->'rungs') e) <> '[89, 28, 21, 6, 33, 48, 5, 24]'::jsonb
     or v->'open_by_rung' <> '{"1": 89, "2": 117, "3": 138, "4": 144, "5": 177, "6": 225, "7": 230, "8": 254}'::jsonb then
    raise exception 'PROOF 218 FAIL: the read: % / %', v_x, v - 'companies' - 'rungs';
  end if;
  if (select md5(string_agg(c.key || c.value::text, ',' order by c.key)) from public.world_config c) <> v_cfg or (select count(*) from public.world_news) <> v_news then
    raise exception 'PROOF 218 FAIL: the read wrote something';
  end if;
  raise notice 'PASS: SR_READ - % companies, % fleets, % beyond their rung, % without a way home; harbours by rung and openings as approved', v->>'company_count', v->>'fleets', v->>'beyond', v->>'trapped';
  raise notice 'TIMING: the read % ms, % ms a fleet', round(v_ms), round(v_ms / greatest(1, (v->>'fleets')::int));

  -- ── SR_GUARD ──
  for r in select * from (values ('wrong'), (null)) q(m) loop
    begin
      perform public.seas_relit_light(r.m);
      raise exception 'PROOF 218 FAIL: lit with the mark %', r.m;
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'seas_relit_light refuses:%mark%' then raise; end if;
    end;
  end loop;
  if public.sea_conditions_on() then raise exception 'PROOF 218 FAIL: lit by a refused step'; end if;
  raise notice 'PASS: SR_GUARD - a wrong mark and no mark are refused, nothing is lit';

  -- ── SR_LIGHT ──
  v_x := public.seas_relit_light(v->>'mark');
  if not public.sea_conditions_on() or (v_x->>'lit')::boolean is not true or (select count(*) from public.world_news) <> v_news + 1 then
    raise exception 'PROOF 218 FAIL: the light: %', v_x;
  end if;
  begin
    perform public.seas_relit_light(v->>'mark');
    raise exception 'PROOF 218 FAIL: lit twice';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'seas_relit_light refuses: the seas are lit already%' then raise; end if;
  end;
  raise notice 'PASS: SR_LIGHT - lit with the table''s mark, one news row; a second time refuses';

  -- ── SR_LIVE ──
  v_g := public.sea_gate(v_a, v_fa, (select id from public.ports where code = 'LPA'), null);
  if public.sea_gate(v_a, v_fa, (select id from public.ports where code = 'AMS'), public.sea_course(v_lis, (select id from public.ports where code = 'AMS'))) is not null
     or v_g->'figures'->>'zone' is distinct from 'NOR-MAC' or (v_g->'figures'->>'needs_title')::int <> 2 or (v_g->'figures'->>'title')::int <> 1
     or public.sea_gate(v_b, v_fb, v_lis, public.sea_course(v_aca, v_lis)) is not null or public.sea_gate(v_b, v_fb, (select id from public.ports where code = 'MNL'), null) is null then
    raise exception 'PROOF 218 FAIL: lit: Africa %, Acapulco home %', v_g, public.sea_gate(v_b, v_fb, v_lis, public.sea_course(v_aca, v_lis));
  end if;
  perform voyage.settle(v_fc, (select eta from public.voyages where id = v_voy) + interval '1 minute');
  if (select status from public.voyages where id = v_voy) <> 'ARRIVED' or (select port_id from public.fleets where id = v_fc) <> v_aca then
    raise exception 'PROOF 218 FAIL: the voyage under way at the light did not arrive';
  end if;
  v := public.seas_relit_ready();
  if (v->>'trapped')::int <> 0 then
    raise exception 'PROOF 218 FAIL: fleets without a way home after the light';
  end if;
  raise notice 'PASS: SR_LIVE - Amsterdam sails, Las Palmas is refused at level 1 of 2; from Acapulco home and not Manila; the one under way arrived; % of this world''s fleets have a way home',
    v->>'fleets';

  -- ── SR_LONGWAY ── (a level cannot be given: the seas' asks are lowered by 5 for this fleet's level 1 instead, and her hull is planted strong)
  begin
    update public.sea_zones set title_min = greatest(1, title_min - 5), wave_min = 0 where title_min <= 6 or title_min = 7;
    perform public.sea_leg_asks_keep();
    update public.world_config set value = '6800'::jsonb where key = 'nav_leg_nm_base';
    select x.stops || 'BUS'::text into v_path from voyage.reach_passage(v_a, v_fa, v_lis, null) x where x.code = 'BUS' and x.nm is not null;
    if v_path is null then raise exception 'PROOF 218 FAIL: rung 6 does not reach Busan'; end if;
    select string_agg(q.a || '-' || q.b, ' ') into v_bad
      from (select x as b, coalesce(lag(x) over (order by o), 'LIS') as a from unnest(v_path) with ordinality u(x, o)) q
      join public.ports pa on pa.code = q.a join public.ports pb on pb.code = q.b join public.sea_leg_asks s on s.from_port = pa.id and s.to_port = pb.id
     where s.zones && array(select z.code from public.sea_zones z where z.title_was is not null and z.title_min = 8);
    if v_bad is not null then raise exception 'PROOF 218 FAIL: the way to Busan crosses a sealed sea: %', v_bad; end if;
    update public.sea_zones set title_min = 2 where code in ('KOR', 'YEL', 'EAS', 'SFJ', 'TAI', 'SOA', 'STR', 'SET', 'PHI-JP', 'NRT-JP', 'JAV', 'AND', 'GND', 'GIN', 'VIS', 'MAK', 'MOL', 'BAN');
    perform public.sea_leg_asks_keep();
    if exists (select 1 from voyage.reach_passage(v_a, v_fa, v_lis, null) x where x.code = 'BUS' and x.nm is not null) then raise exception 'PROOF 218 FAIL: a rung short reaches Busan'; end if;
    raise exception using errcode = 'ZY218', message = 'x';
  exception when sqlstate 'ZY218' then null; end;
  raise notice 'PASS: SR_LONGWAY - at rung 6 the pathfinder reaches Busan from Lisbon by % with no sealed sea; one rung short it does not', v_path;

  -- ── SR_WORD, SR_BACK ──
  v_g := public.sea_refusal(1, 12, array['NOR-MID']);
  if v_g->>'sentence' not like '%Wave resistance 12 / 30.%' then raise exception 'PROOF 218 FAIL: %', v_g; end if;
  raise notice 'PASS: SR_WORD - %', v_g->>'sentence';
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  if public.sea_gate(v_a, v_fa, (select id from public.ports where code = 'LPA'), null) is not null or public.sea_gate(v_b, v_fb, (select id from public.ports where code = 'MNL'), null) is not null then
    raise exception 'PROOF 218 FAIL: the switch back, a sea still refuses';
  end if;
  raise notice 'PASS: SR_BACK - the switch false again: no sea refuses';
end
$p$;
