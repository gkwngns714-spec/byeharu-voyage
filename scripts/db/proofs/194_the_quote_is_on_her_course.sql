-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 194 - THE QUOTE IS ON HER COURSE  (migration 0491; docs/dev-log/2026-11-24-quote-on-her-course.md)
--
--   The fault: the board and the trip quote measured a leg on public.sea_reaches, the SAIL on the course it carries (the sum of
--   voyage.segments_from_course): 19,428 of 32,128 stored courses differed by more than 0.1 %, up to +21.7 %, so a long trip's days, wages
--   and stores were quoted short. 0491 wrote every stored course's own length into the table (both ways), measured by the SAIL's function
--   (scripts/db/gen-0491-sea-lengths.mjs, offline: 64,256 calls take 213 s on PGlite). ONE measure: the table is its stored answer.
--
--   KEEPING IT ONE: this proof pins the stored courses' digest the lengths were measured from and the harbour pairs' digest 0491 wrote.
--   A later migration that writes public.sea_courses (or the pairs) without re-running the generator in the same file fails PQ_PINNED here;
--   one that does re-run it updates the two pins with the generator's digests. PQ_MEASURE re-measures a sample live every run, so a change
--   to voyage.segments_from_course or public.sea_course that moves a length fails too.
--
-- @pass PQ_PINNED   public.sea_courses is the set the lengths were measured on, and the harbour pairs' figures are 0491's (every pair, both ways)
-- @pass PQ_MEASURE  a sample of stored courses (every pair whose codes hash to 00, the longest move ARI-AYU, the most shortened BND-MNG), sailed both ways through voyage.segments_from_course, is the table's figure to the hundredth
-- @pass PQ_DAYS     on that sample at 5, 10, 15 and 17.5 kn, the whole days the quote counts (world.trip_leg: the miles over the speed, every day begun) are the days the SAIL settles (voyage.total_days: its pieces over the speed, every day begun)
-- @pass PQ_SAIL     a probe fleet sails LNG-REY (+2.3 % before 0491, the largest move within a barca's 1,700 nm reach) on the stored course: the voyage's miles are the table's, and its settled days are the quote's (world.trip_leg at her speed, world.trip_cost's leg)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_courses constant text := 'a9b593754530495de24d331cc3be1204';   -- scripts/db/gen-0491-sea-lengths.mjs's courses_md5
  c_pairs   constant text := '8e418cd663c8c3790b94f9c4fe57e2b9';   -- the harbour pairs after 0491 (before-0491.sql / after-0491.sql)
  c_auth    constant uuid := '00000000-0194-4000-8000-0000000000aa';
  v_seen    text;
  v_n       int;
  v_all     int;
  v_bad     text;
  v_pl      uuid;
  v_fl      uuid;
  v_sh      uuid;
  v_from    uuid;
  v_to      uuid;
  v_course  jsonb;
  v_r       jsonb;
  v_voy     record;
  v_nm      numeric;
  v_quote   record;
  v_trip    jsonb;
begin
  -- ══ PQ_PINNED ══
  v_seen := (select md5(string_agg(p.code || ':' || array_to_string(c.tos, ',') || ':' || array_to_string(c.offs, ',') || ':' || md5(c.pts), '|' order by p.code collate "C"))
               from public.sea_courses c join public.ports p on p.id = c.port_id);
  if v_seen is distinct from c_courses then
    raise exception 'PQ_PINNED: public.sea_courses moved (digest %, the lengths were measured on %): re-run scripts/db/gen-0491-sea-lengths.mjs and write the lengths in the same migration', v_seen, c_courses;
  end if;
  v_seen := (select md5(string_agg(a.code || '>' || e.key || '=' || e.value, ',' order by a.code collate "C", e.key collate "C"))
               from public.sea_reaches a join public.ports pa on pa.id = a.port_id and pa.kind = 'HARBOUR'
              cross join lateral jsonb_each_text(a.reaches) e
              where exists (select 1 from public.ports pb where pb.code = e.key and pb.kind = 'HARBOUR'));
  if v_seen is distinct from c_pairs then
    raise exception 'PQ_PINNED: the harbour pairs'' figures (digest %) are not the ones measured from the stored courses (%)', v_seen, c_pairs;
  end if;
  raise notice 'PASS: PQ_PINNED — the stored courses are the ones measured (%), every harbour pair''s figure is their length (%)', c_courses, c_pairs;

  -- ══ PQ_MEASURE ══ (the sample, both ways, through the SAIL's own function)
  create temp table pq_194 on commit drop as
    select pa.code a, pb.code b, (ra.reaches ->> pb.code)::numeric t,
           (select jsonb_agg((g ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(public.sea_course(pa.id, pb.id))) g) ab,
           (select jsonb_agg((g ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(public.sea_course(pb.id, pa.id))) g) ba
      from public.sea_courses c join public.ports pa on pa.id = c.port_id
     cross join lateral unnest(c.tos) u(code)
      join public.ports pb on pb.code = u.code and pb.kind = 'HARBOUR'
      join public.sea_reaches ra on ra.port_id = pa.id
     where left(md5(pa.code || pb.code), 2) = '00' or (pa.code, pb.code) in (('ARI', 'AYU'), ('BND', 'MNG'));
  select count(*), count(*) filter (where q.t is distinct from (select sum(x::numeric) from jsonb_array_elements_text(q.ab) x)
                                       or q.t is distinct from (select sum(x::numeric) from jsonb_array_elements_text(q.ba) x)),
         string_agg(format('%s-%s table %s sailed %s / %s', q.a, q.b, q.t, (select sum(x::numeric) from jsonb_array_elements_text(q.ab) x),
                           (select sum(x::numeric) from jsonb_array_elements_text(q.ba) x)), '; ')
    into v_all, v_n, v_bad from pq_194 q;
  if v_all < 100 or v_n > 0 then
    raise exception 'PQ_MEASURE: % of % sampled course(s) sail another length than the table: %', v_n, v_all, left(v_bad, 800);
  end if;
  raise notice 'PASS: PQ_MEASURE — % stored courses re-measured live both ways: each is the table''s figure to the hundredth', v_all;

  -- ══ PQ_DAYS ══
  select count(*), string_agg(format('%s-%s at %s kn: quoted %s d, settled %s d', d.a, d.b, d.s, d.quoted, d.settled), '; ')
    into v_n, v_bad
    from (select q.a, q.b, s.s,
                 greatest(1, ceil(q.t / s.s / 24)) quoted,                                                                  -- world.trip_leg
                 greatest(1, ceil((select sum(x::numeric / s.s) from jsonb_array_elements_text(w.segs) x) / 24)) settled     -- voyage.total_days (sim_hours)
            from pq_194 q cross join (values (5::numeric), (10), (15), (17.5)) s(s)
           cross join lateral (values (q.ab), (q.ba)) w(segs)) d
   where d.quoted <> d.settled;
  if v_n > 0 then
    raise exception 'PQ_DAYS: % leg(s) quote other days than they settle: %', v_n, left(v_bad, 800);
  end if;
  raise notice 'PASS: PQ_DAYS — % courses x 2 ways x 4 speeds (5, 10, 15, 17.5 kn): the days quoted are the days settled', v_all;

  -- ══ PQ_SAIL ══ (a real departure on the stored course)
  v_from := (select p.id from public.ports p where p.code = 'LNG' and p.kind = 'HARBOUR');
  v_to   := (select p.id from public.ports p where p.code = 'REY' and p.kind = 'HARBOUR');
  v_course := public.sea_course(v_from, v_to);
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 194', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_from);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20) where id = v_sh;
  perform cmd.assume_identity(c_auth);
  v_trip := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LNG', 'to', 'REY')));
  select tl.sea_days, tl.sail_days into v_quote
    from world.trip_leg(voyage.fleet_speed_parts(v_fl), world.trip_hulls(v_fl), (select (sr.reaches ->> 'REY')::numeric from public.sea_reaches sr where sr.port_id = v_from)) tl;
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL REY', 'path', v_course)), null);
  select v.id, v.path into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
  if v_voy.id is null then
    raise exception 'PQ_SAIL: the probe did not leave Longyearbyen for Reykjavik: %', v_r;
  end if;
  v_nm := (select sum((e ->> 'nm')::numeric) from jsonb_array_elements(v_voy.path) e);
  if round(v_nm, 1) is distinct from (v_trip -> 'legs' -> 0 ->> 'nm')::numeric then
    raise exception 'PQ_SAIL: she sails % nm and the quote measured % nm', v_nm, v_trip -> 'legs' -> 0 ->> 'nm';
  end if;
  if v_nm is distinct from (select (sr.reaches ->> 'REY')::numeric from public.sea_reaches sr where sr.port_id = v_from)
     or voyage.total_days(v_voy.id) <> v_quote.sea_days
     or abs(voyage.sim_hours(v_voy.id) / 24 - v_quote.sail_days) > 0.0001 then
    raise exception 'PQ_SAIL: Longyearbyen-Reykjavik sails % nm and settles % d (% h); the table says % nm and the quote % d (% sailing days)', v_nm, voyage.total_days(v_voy.id),
      round(voyage.sim_hours(v_voy.id), 3), (select sr.reaches ->> 'REY' from public.sea_reaches sr where sr.port_id = v_from), v_quote.sea_days, round(v_quote.sail_days, 4);
  end if;
  raise notice 'PASS: PQ_SAIL — Longyearbyen to Reykjavik on the stored course: % nm sailed = the table''s, % d settled = % d quoted (trip_cost leg % nm, % d)',
    v_nm, voyage.total_days(v_voy.id), v_quote.sea_days, v_trip -> 'legs' -> 0 ->> 'nm', v_trip -> 'legs' -> 0 ->> 'days';
end
$p$;
