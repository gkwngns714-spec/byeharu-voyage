-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 185 - SEA COURSES AND A FASTER LISBON READ  (migration 0482; docs/dev-log/2026-11-23-sea-courses.md)
--
--   The migration's self-assert decodes three courses, asks the door of the courses from Lisbon to every fourth harbour, compares the
--   Lisbon read's pieces with and without the change, and sails one fixed job by a stored course. This proof plays the rest: the table
--   against every harbour pair, the door both ways from two harbours, the kept matrix from several harbours and caps, the pieces from a
--   second harbour and a fleet with a captain, a `best` run and an HQ card's served lines, and the cost.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: world.best_sales and world.hq_board are each checked for their own shape, never against
--   a second answer; the sameness of the read is proved on its pieces (voyage.reach_passage, world.board_legs, world.board_trips,
--   world.board_sell: none of them budgeted). THE DAY: proof.mjs runs this file in ONE transaction (now() is one instant); every scene
--   starts at 00:00 UTC of the day it runs (before 23:30 UTC), so none straddles a UTC midnight.
--
-- @pass SC_TABLE     every harbour pair has a stored course but the pairs whose two harbours share one roadstead; sampled both ways, each is the other reversed
-- @pass SC_DOOR      the door (voyage.path_refusal, cmd.do_sail's question) takes every stored course from Lisbon and from a second harbour, both ways
-- @pass SC_MATRIX    voyage.reach_passage answers the same with the kept matrix and without it, from five harbours at three caps; the trigger keeps it
-- @pass SC_SAME      the Lisbon read's pieces (board_legs, board_trips, board_sell for every good) are the same with the hoisted context, at Seville and with a captain
-- @pass SC_DARK      dark, a best job finds no course where no lane runs, and the board's card carries no lines
-- @pass SC_BEST      lit, every paying sale from Lisbon has its lines; a best job sails her best one by its course and she departs
-- @pass SC_BOARD     lit, an HQ trade card carries its lines whole (each SAIL with a course); sent as they are, she departs
-- @pass SC_COST      the costs, timed: world.best_sales at Lisbon; reach_passage with the kept matrix and without; a stored course decoded
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0482-4000-8000-0000000001a1';
  c_b     constant uuid := '00000000-0482-4000-8000-0000000001b1';
  c_c     constant uuid := '00000000-0482-4000-8000-0000000001c1';
  v_day   timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_fa    uuid;
  v_fb    uuid;
  v_fc    uuid;
  v_n     int;
  v_m     int;
  v_shared int;
  v_cr    jsonb;
  v_rv    jsonb;
  v_r     jsonb;
  v_bs    jsonb;
  v_board jsonb;
  v_move  jsonb;
  v_o     jsonb;
  v_ctx   jsonb;
  v_hoist jsonb;
  v_legs  jsonb;
  v_note  jsonb;
  v_first uuid;
  v_d     float8[];
  v_t     timestamptz;
  v_ms    numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  x       record;
  g       record;
  a       record;
  v_at    uuid;
begin
  -- SC_TABLE: the stored courses against every pair of harbours
  select count(*) into v_m from public.ports p where p.kind = 'HARBOUR';
  select count(*) into v_shared
    from public.ports p join public.sea_reaches s on s.port_id = p.id
    join public.ports q on q.kind = 'HARBOUR' and q.code collate "C" > p.code collate "C"
    join public.sea_reaches t on t.port_id = q.id and t.roadstead_lat = s.roadstead_lat and t.roadstead_lon = s.roadstead_lon
   where p.kind = 'HARBOUR';
  if (select sum(cardinality(c.tos)) from public.sea_courses c) <> v_m * (v_m - 1) / 2 - v_shared then
    raise exception 'SC_TABLE: % stored courses, not every pair of % harbours less the % sharing a roadstead', (select sum(cardinality(c.tos)) from public.sea_courses c), v_m, v_shared;
  end if;
  v_n := 0;
  for x in
    select a1.id as a, b1.id as b, a1.code as ac, b1.code as bc
      from (select p.id, p.code, row_number() over (order by p.code collate "C") as k from public.ports p where p.kind = 'HARBOUR') a1
      join public.ports b1 on b1.kind = 'HARBOUR' and b1.id <> a1.id
     where a1.k % 32 = 1
  loop
    v_cr := public.sea_course(x.a, x.b);
    v_rv := public.sea_course(x.b, x.a);
    continue when v_cr is null and v_rv is null and exists (
      select 1 from public.sea_reaches s join public.sea_reaches t on t.port_id = x.b where s.port_id = x.a and s.roadstead_lat = t.roadstead_lat and s.roadstead_lon = t.roadstead_lon);
    if v_cr is null or jsonb_array_length(v_cr) < 2
       or v_rv is distinct from (select jsonb_agg(u.p order by u.i desc) from jsonb_array_elements(v_cr) with ordinality u(p, i)) then
      raise exception 'SC_TABLE: % to % has no stored course, or the other way is not it reversed', x.ac, x.bc;
    end if;
    v_n := v_n + 1;
  end loop;
  if public.sea_course(v_lis, v_lis) is not null or public.sea_course(v_lis, (select p.id from public.ports p where p.kind <> 'HARBOUR' limit 1)) is not null then
    raise exception 'SC_TABLE: a course to the same harbour or to a place that is not a harbour';
  end if;
  raise notice 'PASS: SC_TABLE — % stored courses = every pair of % harbours less % sharing a roadstead; % sampled (8 origins, both ways) each the other reversed',
    v_m * (v_m - 1) / 2 - v_shared, v_m, v_shared, v_n;

  -- SC_DOOR: cmd.do_sail's question of every stored course from Lisbon and from the harbour first by code, both ways
  v_n := 0;
  for x in
    select o.id as oid, p.id, p.code, a0.roadstead_lat as olat, a0.roadstead_lon as olon, b0.roadstead_lat as dlat, b0.roadstead_lon as dlon
      from (select v_lis as id union all select (select p1.id from public.ports p1 where p1.kind = 'HARBOUR' order by p1.code collate "C" limit 1)) o
      join public.sea_reaches a0 on a0.port_id = o.id
      join public.ports p on p.kind = 'HARBOUR' and p.id <> o.id
      join public.sea_reaches b0 on b0.port_id = p.id
     where public.sea_course(o.id, p.id) is not null
  loop
    if voyage.path_refusal(public.sea_course(x.oid, x.id), x.olat, x.olon, x.dlat, x.dlon, public.wc_num('course_join_nm'), 25, 25) is not null
       or voyage.path_refusal(public.sea_course(x.id, x.oid), x.dlat, x.dlon, x.olat, x.olon, public.wc_num('course_join_nm'), 25, 25) is not null then
      raise exception 'SC_DOOR: the door refuses the stored course to %: %', x.code,
        voyage.path_refusal(public.sea_course(x.oid, x.id), x.olat, x.olon, x.dlat, x.dlon, public.wc_num('course_join_nm'), 25, 25);
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n < 2 * (v_m - 2) then
    raise exception 'SC_DOOR: only % courses asked', v_n;
  end if;
  raise notice 'PASS: SC_DOOR — the door takes % stored courses from two harbours, both ways', v_n;

  -- the companies: A at Lisbon (best run, board), B at Seville (the pieces), C at Lisbon with a captain seated (the pieces)
  v_a := public.new_house(c_a, 'Casa das Rotas 185', 'PRT');
  v_b := public.new_house(c_b, 'Casa de Sevilla 185', 'ESP', 'SVQ');
  v_c := public.new_house(c_c, 'Casa do Piloto 185', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.id into v_fc from public.fleets f where f.player_id = v_c;
  update public.players p set ducats = 60000 where p.id in (v_a, v_b, v_c);
  declare
    v_po uuid;
    o record;
  begin
    for o in select ox.id from public.officers ox join public.captain_profile cp on cp.officer_id = ox.id order by ox.code limit 1 loop
      insert into public.player_officers (player_id, officer_id) values (v_c, o.id) returning id into v_po;
      insert into public.captain_active (player_officer_id, trait) select v_po, ct.trait from public.captain_traits ct where ct.officer_id = o.id on conflict do nothing;
      perform public.captain_seat_put(v_po, (select s.id from public.ships s where s.fleet_id = v_fc order by s.is_flagship desc, s.id limit 1), 1);
    end loop;
  end;

  -- SC_MATRIX: reach_passage with the kept matrix and without, from five harbours at three caps; the trigger keeps it
  perform cmd.assume_identity(c_a);
  select m.nm into v_d from public.sea_reach_matrix m where m.id = 1;
  v_n := 0;
  for x in select p.id, p.code from public.ports p where p.kind = 'HARBOUR' and p.code in ('LIS', 'SVQ', 'MAC', 'CPT', 'VER') loop
    for v_ms in select unnest(array[null::numeric, 600, 2500]) loop
      v_r := (select jsonb_agg(to_jsonb(r) order by r.code) from voyage.reach_passage(v_a, v_fa, x.id, v_ms) r);
      delete from public.sea_reach_matrix;
      if v_r is null or v_r is distinct from (select jsonb_agg(to_jsonb(r) order by r.code) from voyage.reach_passage(v_a, v_fa, x.id, v_ms) r) then
        raise exception 'SC_MATRIX: reach_passage from % at % answers differently with the kept matrix', x.code, v_ms;
      end if;
      update public.sea_reaches set reaches = reaches where port_id = x.id;
      v_n := v_n + 1;
    end loop;
  end loop;
  if v_n <> 15 or (select m.nm from public.sea_reach_matrix m where m.id = 1) is distinct from v_d then
    raise exception 'SC_MATRIX: % passages compared, or the trigger did not keep the matrix', v_n;
  end if;
  raise notice 'PASS: SC_MATRIX — reach_passage the same with the kept matrix and without from LIS, SVQ, MAC, CPT, VER at no cap, 600 and 2,500 nm; each write to the miles rebuilt it';

  -- SC_SAME: the Lisbon read's pieces, with the hoisted context and without: B at Seville, C at Lisbon with a captain
  v_n := 0;
  for x in select v_b as pid, c_b as uid, v_fb as fid union all select v_c, c_c, v_fc loop
    perform cmd.assume_identity(x.uid);
    v_at := (select f.port_id from public.fleets f where f.id = x.fid);
    v_o := world.board_origin(x.fid);
    v_hoist := jsonb_build_object('trip_fleet', x.fid, 'trip_hulls', world.trip_hulls(x.fid), 'speed_parts', voyage.fleet_speed_parts(x.fid));
    v_legs := null;
    for g in
      select gd.id, gd.code from public.port_goods pg join public.goods gd on gd.id = pg.good_id
       where pg.port_id = v_at and public.port_offers(v_at, gd.id) order by gd.code
    loop
      select * into a from world.board_amount(x.fid, g.id, null);
      v_ctx := v_o || jsonb_build_object(
                 'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                 'src', jsonb_build_object('code', case when a.basis <> 'on_board' then (select p.code from public.ports p where p.id = v_at) end),
                 'src_cut', false, 'src_name', null, 'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', null);
      if v_legs is null then
        v_legs := world.board_legs(x.fid, v_ctx || jsonb_build_object('only', '[]'::jsonb));
        -- board_legs and board_trips answer a row a harbour in no fixed order (their readers join by id): compared by id
        if (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(v_legs) e)
             is distinct from (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(world.board_legs(x.fid, v_ctx || v_hoist || jsonb_build_object('only', '[]'::jsonb))) e) then
          raise exception 'SC_SAME: board_legs answers differently with the hoisted context';
        end if;
      end if;
      if world.board_sell(g.id, x.fid, v_ctx || jsonb_build_object('legs', v_legs))
           is distinct from world.board_sell(g.id, x.fid, v_ctx || v_hoist || jsonb_build_object('legs', v_legs))
         or (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(world.board_trips(x.fid, v_ctx || jsonb_build_object('buy', jsonb_build_object('units', 20, 'bulk', 1.5)), v_legs)) e)
           is distinct from (select jsonb_agg(e order by e->>'id') from jsonb_array_elements(world.board_trips(x.fid, v_ctx || v_hoist || jsonb_build_object('buy', jsonb_build_object('units', 20, 'bulk', 1.5)), v_legs)) e) then
        raise exception 'SC_SAME: board_sell or board_trips answers differently for % with the hoisted context', g.code;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  if v_n < 4 then
    raise exception 'SC_SAME: only % goods compared', v_n;
  end if;
  raise notice 'PASS: SC_SAME — board_legs, board_trips and board_sell the same with the hoisted context for % goods (Seville; Lisbon with a captain seated)', v_n;

  -- SC_DARK: a best job's courses and the board's card, dark
  perform cmd.assume_identity(c_a);
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'hq_board_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'sea_courses_enabled';
  select p.id into v_at from public.ports p join public.sea_reaches sr on sr.port_id = v_lis
   where p.kind = 'HARBOUR' and p.id <> v_lis and public.fleet_job_course(v_fa, v_lis, p.id) is null and public.sea_course(v_lis, p.id) is not null
   order by (sr.reaches->>p.code)::numeric, p.code limit 1;
  v_board := world.hq_board();
  if v_at is null or exists (select 1 from jsonb_array_elements(v_board->'moves') m where m->>'kind' = 'trade' and m->'act'->'args' ? 'lines') then
    raise exception 'SC_DARK: no harbour lacks a remembered course, or a dark card carries lines: %', left(v_board::text, 300);
  end if;
  raise notice 'PASS: SC_DARK — dark, % has no course a job sails from Lisbon, and no trade card carries lines', (select p.code from public.ports p where p.id = v_at);

  -- SC_BEST: lit, every paying sale from Lisbon has its lines; the best job sails her best by its course
  update public.world_config set value = 'true'::jsonb where key = 'sea_courses_enabled';
  if public.fleet_job_course(v_fa, v_lis, v_at) is distinct from public.sea_course(v_lis, v_at) then
    raise exception 'SC_BEST: lit, the course a job sails is not the stored course';
  end if;
  v_bs := world.best_sales(v_fa, v_lis);
  v_r := world.board_passages(v_a, v_fa, v_lis, (select sr.cap_nm from public.supply_reach(v_fa) sr));
  select count(*), count(*) filter (where public.sale_lines(v_fa, v_lis, g2.e,
           (select e->'stops' from jsonb_array_elements(v_r) e join public.ports p on p.id = (e->>'port_id')::uuid where p.code = g2.e->>'port' limit 1)) ? 'lines')
    into v_n, v_m
    from jsonb_array_elements(v_bs->'goods') g2(e) where (g2.e->>'pays')::boolean and g2.e->>'port' is not null;
  if v_n = 0 or v_m <> v_n then
    raise exception 'SC_BEST: % of % paying sales have their lines', v_m, v_n;
  end if;
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fa, v_a, 'best', '{}'::jsonb, v_day, v_day);
  call public.tick_fleet_jobs(false);
  select j.last, j.last_plan into v_note, v_first from public.fleet_jobs j where j.fleet_id = v_fa;
  if v_first is null or (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING'
     or exists (select 1 from public.orders o where o.plan_id = v_first and o.verb = 'SAIL' and jsonb_typeof(o.args->'path') <> 'array')
     or not exists (select 1 from public.orders o where o.plan_id = v_first and o.verb = 'SELL') then
    raise exception 'SC_BEST: the best job did not sail by a course: % (%)', v_note,
      (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
  end if;
  raise notice 'PASS: SC_BEST — lit, % of % paying sales from Lisbon have their lines; the best job sent % and she departs',
    v_m, v_n, (select string_agg(o.raw_text, ' / ' order by o.seq) from public.orders o where o.plan_id = v_first);

  -- SC_BOARD: lit, a card's lines whole; sent as they are (C at Lisbon, idle)
  perform cmd.assume_identity(c_c);
  v_board := world.hq_board();
  select m into v_move from jsonb_array_elements(v_board->'moves') m where m->>'kind' = 'trade' and m->'act'->'args' ? 'lines' limit 1;
  if v_move is null or exists (select 1 from jsonb_array_elements(v_move #> '{act,args,lines}') l where l->>'text' like 'SAIL %' and jsonb_typeof(l->'path') <> 'array') then
    raise exception 'SC_BOARD: lit, no trade card carries its lines with courses: %', left(v_board::text, 400);
  end if;
  v_r := cmd.issue_lines(v_fc, v_move #> '{act,args,lines}', (v_move #>> '{act,args,version}')::int);
  if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fc) <> 'SAILING' then
    raise exception 'SC_BOARD: the card''s lines were refused or she did not sail: % / %', v_r,
      (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fc);
  end if;
  raise notice 'PASS: SC_BOARD — lit, the card % carries %; sent as they are, she departs', v_move->>'id',
    (select string_agg(l->>'text', ' / ') from jsonb_array_elements(v_move #> '{act,args,lines}') l);

  -- SC_COST: timed, for the dev-log (never compared)
  perform cmd.assume_identity(c_b);
  v_t := clock_timestamp();
  v_bs := world.best_sales(v_fb, (select f.port_id from public.fleets f where f.id = v_fb));
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  v_t := clock_timestamp();
  perform count(*) from voyage.reach_passage(v_b, v_fb, v_lis, null);
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  delete from public.sea_reach_matrix;
  v_t := clock_timestamp();
  perform count(*) from voyage.reach_passage(v_b, v_fb, v_lis, null);
  v_ms3 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  v_t := clock_timestamp();
  for x in select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 100 loop
    perform public.sea_course(v_lis, x.id);
  end loop;
  raise notice 'PASS: SC_COST — world.best_sales from Seville % ms (cut %); reach_passage from Lisbon % ms with the kept matrix, % ms without; 100 stored courses decoded in % ms',
    v_ms, v_bs->'cut', v_ms2, v_ms3, round(extract(epoch from clock_timestamp() - v_t) * 1000);
end
$p$;
