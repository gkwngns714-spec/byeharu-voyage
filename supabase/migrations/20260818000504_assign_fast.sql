-- ════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0504 - ASSIGN, FAST, AND UNANSWERED IS NOT "NOTHING PAYS"  (repairs of 0496's world.actions and 0481's Best job; no switch, no knob, no table)
-- ════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER'S LIVE BUG, 2026-11-25: Assign said "the quotes are slow just now: ask again in a moment" (public.sea_actions_for, past 5 s).
--   Measured (docs/dev-log/2026-11-25-assign-fast.md, every harbour, two worlds, local): the read is world.best_sales (a third to a half
--   of it) and 8 to 18 trips, each worked out harbour by harbour: a read judged 248 legs of which 80 were different, asked the pathfinder
--   20 times from 11 harbours, and walked the whole sea chart 477 times (voyage.segments_from_course: 259,200 cells unpacked a call) for a
--   course's MILES alone. Bring home's loop was not it (10 goods at most).
-- WHAT:
--   voyage.course_pieces           the pieces of a course and their miles, moved whole out of voyage.segments_from_course, which reads them
--                                  here (2 hunks); voyage.course_nm: their sum, asked where only the miles are wanted: public.
--                                  fleet_job_leg_shut (1 hunk), world.trip_cost (3 hunks; and her speed's parts read once a trip, not once a
--                                  leg), public.job_trip_memo.
--   public.fleet_job_legs_memo, public.fleet_job_sails_memo, public.job_trip_memo
--                                  the three bodies, moved whole, with what was already judged (a leg's course and its judgement, the ways
--                                  found from a harbour) handed from call to call (0488's way: an argument, one read, one fleet; nothing is
--                                  kept anywhere). public.fleet_job_legs, fleet_job_sails and job_trip ask them with none handed over.
--   public.sea_actions_for         (4 hunks) hands one memo to all its trips.
-- THE BEST JOB (2026-11-25, the owner's fleet idle at Kollam; the cut itself was not seen on prod, it is the likely cause):
--   world.best_sales stops at 2.5 s and says `cut` (the goods after it, by code, are not answered: `order by g.code`; with her passages slow it
--   can stop before the first). public.fleet_job_plan never read `cut`: no card answered read as {nothing}, asked again 15 minutes on.
--   public.fleet_job_plan          (1 hunk) cut, and no usable card: {wait: slow} (a near round is not sent home on it either). Cut WITH a usable
--                                  card: the best card answered is taken now. THAT CUT MAY HAVE HIDDEN A BETTER ONE: it is not asked again for it.
--   public.fleet_job_note          (1 hunk) `slow` and `unpriced` (the read raised) are asked again at the next tick (90 s), not 15 minutes on.
--   A read that is whole and pays nothing waits as before. LOAD: while the read stays cut, one plan (a best_sales) a job in two minutes, not in 15.
-- THE SAME OPTIONS AND FIGURES in Assign, byte for byte: no estimator is added, no rule moves. Its 5 s guard and its rule (a slow machine serves the
--   same list, or says so) stand. public.land_actions_for (the other E_SLOW) is not touched: its terms ask no trip and no quote.
-- NOT CHANGED: every knob and switch; world.best_sales; the tick's own body; any table; any client read's shape.
-- THE HUNKS (12; each once in the live body, each reverses): sea_actions_for x4, segments_from_course x2, trip_cost x3, fleet_job_leg_shut x1,
--   fleet_job_plan x1, fleet_job_note x1.
--   It SUPERSEDES three bodies, replaced whole by their one-line ask (0494's, 0481's and 0496's text is the rollback's; no answer moves). NEW: five functions, server only.
-- ROWS: none. budget: no table, no cron job, no autovacuum or fillfactor change.
-- LOCKS: CREATE FUNCTION x5, CREATE OR REPLACE x9. TIME: a few seconds. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward): a migration reversing the twelve hunks, restoring the three wrapped bodies and dropping the five functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the cut bodies' grants, volatility, definer, search path and owner
--   unmoved; no knob moved; the new functions server only. THE PROBE (rolled back, its own company's rows): from Lisbon to every fortieth harbour
--   and back, the trip and its miles as the old bodies (kept under the session's own schema) work them out, as public.job_trip answers now and
--   with one memo through all of them: the same text; the courses' segments the same text. Her whole read (public.sea_actions_for, old and
--   new) the same text, unless one of the two was cut by a clock (best_sales' 2.5 s, the 5 s guard): then it is said and not judged. Nothing
--   of the market is judged.
-- news: this file posts its own UPDATE row (public.news_update('0504', ...)).
-- VERSION: 0504 (after 0503 `company-name`; written as 0503, numbered when it joined batch 2).
-- ════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.sea_actions_for(uuid,uuid)', 'voyage.segments_from_course(jsonb)',
                                    'public.fleet_job_leg_shut(uuid,uuid,jsonb)', 'world.trip_cost(uuid,jsonb)',
                                    'public.fleet_job_legs(uuid,uuid,uuid)', 'public.fleet_job_sails(uuid,uuid,text[])',
                                    'public.job_trip(uuid,uuid,text[],boolean)',
                                    'public.fleet_job_plan(uuid)', 'public.fleet_job_note(uuid,jsonb)'];
  c_new    constant text[] := array['voyage.course_pieces(jsonb)', 'voyage.course_nm(jsonb)', 'public.fleet_job_legs_memo(uuid,uuid,uuid,jsonb)',
                                    'public.fleet_job_sails_memo(uuid,uuid,text[],jsonb)', 'public.job_trip_memo(uuid,uuid,text[],boolean,jsonb)'];
  c_uid    constant uuid := '00000000-0504-4000-8000-00000000af01';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_me        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_a         jsonb;
  v_r         jsonb;
  v_p         jsonb;
  v_t         jsonb;
  v_memo      jsonb := '{}'::jsonb;
  v_trips     int := 0;
  v_c         timestamptz;
  v_ms0       numeric;
  v_ms1       numeric;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('voyage.course_nm(jsonb)') is not null then
    raise exception '0504 refuses: it has been applied once';
  end if;
  foreach v_q in array c_hunked loop
    if to_regprocedure(v_q) is null then
      raise exception '0504 refuses: % is not in this world', v_q;
    end if;
  end loop;

  -- ── 1. THE PRE-IMAGES ──
  -- the three bodies replaced whole are the ones their moved text was written from (an md5 of the live text)
  for x in select * from (values ('public.fleet_job_legs(uuid,uuid,uuid)', '4da9fd759ae2e20711a2f0cb716515fd'), ('public.fleet_job_sails(uuid,uuid,text[])', 'c5170c7cb8b304085cd56d07169c0f5e'),
                                 ('public.job_trip(uuid,uuid,text[],boolean)', 'ca1d2dc33142f2389aa18532bdb397a3')) w(fn, md5) loop
    if md5(replace((select p.prosrc from pg_proc p where p.oid = x.fn::regprocedure), E'\r', '')) <> x.md5 then
      raise exception '0504 refuses: the body of % is not the one this file moves', x.fn;
    end if;
  end loop;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. WHAT STOOD BEFORE, and the new pieces ──
  -- what stood before, kept for this file's own assert (b2) under the session's schema
  for x in select * from (values ('voyage.segments_from_course(jsonb)'), ('public.fleet_job_leg_shut(uuid,uuid,jsonb)'), ('world.trip_cost(uuid,jsonb)'),
                                 ('public.fleet_job_legs(uuid,uuid,uuid)'), ('public.fleet_job_sails(uuid,uuid,text[])'),
                                 ('public.job_trip(uuid,uuid,text[],boolean)'), ('public.sea_actions_for(uuid,uuid)')) w(fn) loop
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    foreach v_q in array array['voyage.segments_from_course', 'public.fleet_job_leg_shut', 'world.trip_cost', 'public.fleet_job_legs', 'public.fleet_job_sails', 'public.job_trip', 'public.sea_actions_for'] loop
      v_def := replace(v_def, v_q, 'pg_temp.was_0504_' || split_part(v_q, '.', 2));
    end loop;
    execute v_def;
  end loop;

  execute $f$
create function voyage.course_pieces(p_course jsonb, out alat float8, out alon float8, out blat float8, out blon float8, out seg_nm numeric,
                                     out mlat float8, out mlon float8)
returns setof record
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0504: THE PIECES OF A COURSE AND THEIR MILES, moved whole out of voyage.segments_from_course (which reads them here): each sub-leg of
-- the polyline split into equal parts of 500 nm at most, a part of no length left out; its ends, its miles and its midpoint.
declare
  i int; k int; n int; pieces int;
  lat1 float8; lon1 float8; lat2 float8; lon2 float8;
begin
  n := coalesce(jsonb_array_length(p_course), 0);
  for i in 0 .. n - 2 loop
    lat1 := (p_course->i->>0)::float8;     lon1 := (p_course->i->>1)::float8;
    lat2 := (p_course->(i+1)->>0)::float8; lon2 := (p_course->(i+1)->>1)::float8;
    pieces := greatest(1, ceil(voyage.gc_distance_nm(lat1, lon1, lat2, lon2) / 500)::int);
    for k in 0 .. pieces - 1 loop
      alat := lat1 + (lat2 - lat1) * k / pieces;       alon := voyage.lon_lerp(lon1, lon2, k::float8 / pieces);
      blat := lat1 + (lat2 - lat1) * (k + 1) / pieces; blon := voyage.lon_lerp(lon1, lon2, (k + 1)::float8 / pieces);
      seg_nm := round(voyage.gc_distance_nm(alat, alon, blat, blon)::numeric, 2);
      continue when seg_nm <= 0;
      mlat := (alat + blat) / 2; mlon := voyage.lon_lerp(alon, blon, 0.5);
      return next;
    end loop;
  end loop;
end
$body$
  $f$;

  execute $f$
create function voyage.course_nm(p_course jsonb)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0504: THE MILES OF A COURSE: the sum of its pieces' (voyage.course_pieces), which is the sum of voyage.segments_from_course's `nm`,
-- without its sea and shelter (they read the whole chart). Null for a course of no piece, as that sum is.
begin
  return (select sum(p.seg_nm) from voyage.course_pieces(p_course) p);
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_legs_memo(p_fleet uuid, p_from uuid, p_to uuid, p_memo jsonb, out o_legs jsonb, out o_memo jsonb)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0504: public.fleet_job_legs (0494: THE SAILS OF A JOB FROM ONE HARBOUR TO ANOTHER, EACH A LEG SHE CAN SAIL), moved here whole, with what
-- was already judged handed over. p_memo ('{}' or null: nothing yet) is ONE FLEET'S IN ONE READ, as o_memo of the call before: a leg's
-- course and its judgement ('<from>><to>': public.fleet_job_course, public.fleet_job_leg_shut) and the ways found from a harbour
-- ('from <harbour>': voyage.reach_passage's stops by harbour). Nothing else is kept and nothing is worked out here.
-- o_legs: {lines: [{text, path}]}: the one SAIL with the course a job sails when that leg is open; when it is shut by its length or its
-- stores, one SAIL a harbour through the harbours between from voyage.reach_passage (THE pathfinder, capped by the legs her stores
-- cover), each with its own course, each judged the same way. Else {pause, sentence}.
declare
  v_player uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_code   text := (select p.code from public.ports p where p.id = p_to);
  v_c      jsonb;
  v_shut   jsonb;
  v_stops  text[];
  v_at     uuid := p_from;
  v_hop    uuid;
  v_out    jsonb := '[]'::jsonb;
  v_why    text;
  v_key    text;
  x        text;
begin
  o_memo := coalesce(p_memo, '{}'::jsonb);
  v_key := p_from || '>' || p_to;
  if not o_memo ? v_key then
    v_c := public.fleet_job_course(p_fleet, p_from, p_to);
    o_memo := o_memo || jsonb_build_object(v_key, jsonb_build_object('course', v_c, 'shut', case when v_c is not null then public.fleet_job_leg_shut(p_fleet, p_to, v_c) end));
  end if;
  v_c := nullif(o_memo->v_key->'course', 'null'::jsonb);
  if v_c is null then
    o_legs := jsonb_build_object('pause', 'E_NO_COURSE', 'sentence', format('no course the world remembers reaches %s', v_code));
    return;
  end if;
  v_shut := nullif(o_memo->v_key->'shut', 'null'::jsonb);
  if v_shut is null then
    o_legs := jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_code, 'path', v_c)));
    return;
  end if;
  -- too long, or more days than her stores: the harbours between, by the one pathfinder
  v_why := v_shut->>'sentence';
  v_key := 'from ' || p_from;
  if not o_memo ? v_key then
    o_memo := o_memo || jsonb_build_object(v_key, (
      select coalesce(jsonb_object_agg(r.port_id, to_jsonb(r.stops)), '{}'::jsonb)
        from voyage.reach_passage(v_player, p_fleet, p_from, (select sr.cap_nm from public.supply_reach(p_fleet) sr)) r
       where r.nm is not null));
  end if;
  if jsonb_typeof(o_memo->v_key->(p_to::text)) = 'array' then
    v_stops := array(select t.e from jsonb_array_elements_text(o_memo->v_key->(p_to::text)) with ordinality t(e, i) order by t.i);
  end if;
  if coalesce(cardinality(v_stops), 0) > 0 then
    foreach x in array v_stops || v_code loop
      v_hop := (select p.id from public.ports p where p.code = x and p.kind = 'HARBOUR');
      v_key := v_at || '>' || v_hop;
      if not o_memo ? v_key then
        v_c := public.fleet_job_course(p_fleet, v_at, v_hop);
        o_memo := o_memo || jsonb_build_object(v_key, jsonb_build_object('course', v_c, 'shut', case when v_c is not null then public.fleet_job_leg_shut(p_fleet, v_hop, v_c) end));
      end if;
      v_c := nullif(o_memo->v_key->'course', 'null'::jsonb);
      if v_c is null then
        v_why := format('no course the world remembers reaches %s', x);
        v_out := null;
        exit;
      end if;
      if jsonb_typeof(o_memo->v_key->'shut') = 'object' then
        v_out := null;
        exit;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || x, 'path', v_c));
      v_at := v_hop;
    end loop;
    if v_out is not null then
      o_legs := jsonb_build_object('lines', v_out);
      return;
    end if;
  end if;
  o_legs := jsonb_build_object(
    'pause', v_shut->>'code',
    'sentence', format('she cannot sail from %s to %s harbour by harbour: %s',
                       (select p.name from public.ports p where p.id = p_from), (select p.name from public.ports p where p.id = p_to), v_why));
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_sails_memo(p_fleet uuid, p_from uuid, p_codes text[], p_memo jsonb, out o_sails jsonb, out o_memo jsonb)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0504: public.fleet_job_sails (0481: THE SAIL LINES of a job from p_from through each harbour of p_codes in turn), moved here whole, with
-- the memo of public.fleet_job_legs_memo handed through. {lines: [{text, path}]}, or {missing: <code>, ...} for the first harbour no way reaches.
declare
  v_at   uuid := p_from;
  v_to   uuid;
  v_c    jsonb;
  v_out  jsonb := '[]'::jsonb;
  x      text;
begin
  o_memo := p_memo;
  foreach x in array coalesce(p_codes, '{}'::text[]) loop
    v_to := (select p.id from public.ports p where p.code = x and p.kind = 'HARBOUR');
    if v_to is null then
      o_sails := jsonb_build_object('missing', x);
      return;
    end if;
    continue when v_to = v_at;
    -- 0494: harbour by harbour (public.fleet_job_legs); no way through: {missing, pause, sentence}
    select m.o_legs, m.o_memo into v_c, o_memo from public.fleet_job_legs_memo(p_fleet, v_at, v_to, o_memo) m;
    if not (v_c ? 'lines') then
      o_sails := v_c || jsonb_build_object('missing', x);
      return;
    end if;
    v_out := v_out || (v_c->'lines');
    v_at := v_to;
  end loop;
  o_sails := jsonb_build_object('lines', v_out);
end
$body$
  $f$;

  execute $f$
create function public.job_trip_memo(p_fleet uuid, p_from uuid, p_codes text[], p_cost boolean, p_memo jsonb, out o_trip jsonb, out o_memo jsonb)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0504: public.job_trip (0496: A JOB'S SAIL FROM ONE HARBOUR THROUGH OTHERS, AS THE JOB WOULD SAIL IT AND AS THE MAP PRICES IT), moved here
-- whole, with the memo of public.fleet_job_legs_memo handed through: the legs are public.fleet_job_sails_memo's, judged by the leg judge; no
-- way through -> {shut: {code, sentence}}. p_cost: world.trip_cost -> {legs, nm, seconds, wages, stores, dock_fee, total}. Not p_cost: {legs, nm}.
declare
  v_s    jsonb;
  v_legs jsonb := '[]'::jsonb;
  v_at   text := (select p.code from public.ports p where p.id = p_from);
  l      jsonb;
  v_to   text;
  v_c    jsonb;
  v_nm   numeric;
begin
  select m.o_sails, m.o_memo into v_s, o_memo from public.fleet_job_sails_memo(p_fleet, p_from, p_codes, p_memo) m;
  if v_s ? 'missing' then
    o_trip := jsonb_build_object('shut', jsonb_build_object('code', coalesce(v_s->>'pause', 'E_NO_COURSE'),
                'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing'))));
    return;
  end if;
  for l in select e from jsonb_array_elements(v_s->'lines') e loop
    v_to := substr(l->>'text', 6);   -- 'SAIL <code>'
    v_legs := v_legs || jsonb_build_array(jsonb_build_object('from', v_at, 'to', v_to, 'course', l->'path'));
    v_at := v_to;
  end loop;
  if jsonb_array_length(v_legs) = 0 then
    o_trip := jsonb_build_object('shut', jsonb_build_object('code', 'E_SAME_DEST', 'sentence', 'she lies there already'));
    return;
  end if;
  if not p_cost then
    select sum(voyage.course_nm(e->'course')) into v_nm from jsonb_array_elements(v_legs) e;
    o_trip := jsonb_build_object('legs', jsonb_array_length(v_legs), 'nm', round(coalesce(v_nm, 0), 1));
    return;
  end if;
  v_c := world.trip_cost(p_fleet, v_legs);
  if v_c is null or jsonb_typeof(v_c->'days') is distinct from 'number' then
    o_trip := jsonb_build_object('shut', jsonb_build_object('code', 'E_UNPRICED', 'sentence', 'that trip cannot be priced now'));
    return;
  end if;
  o_trip := jsonb_build_object(
    'legs', jsonb_array_length(v_legs),
    'nm', (select round(coalesce(sum((e->>'nm')::numeric), 0), 1) from jsonb_array_elements(v_c->'legs') e),
    'seconds', round((v_c->>'days')::numeric * 86400 / public.wc_num('time_compression')),
    'wages', v_c->'wages', 'stores', v_c->'supplies', 'dock_fee', v_c->'dock_fee', 'total', v_c->'total');
end
$body$
  $f$;

  -- the three, asked with nothing handed over
  execute $f$
create or replace function public.fleet_job_legs(p_fleet uuid, p_from uuid, p_to uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0494: THE SAILS OF A JOB FROM ONE HARBOUR TO ANOTHER, EACH A LEG SHE CAN SAIL. 0504: its body is public.fleet_job_legs_memo, asked here with nothing handed over.
begin
  return (select m.o_legs from public.fleet_job_legs_memo(p_fleet, p_from, p_to, '{}'::jsonb) m);
end
$body$
  $f$;
  execute $f$
create or replace function public.fleet_job_sails(p_fleet uuid, p_from uuid, p_codes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0481: THE SAIL LINES of a job from p_from through each harbour of p_codes in turn. 0504: its body is public.fleet_job_sails_memo, asked here with nothing handed over.
begin
  return (select m.o_sails from public.fleet_job_sails_memo(p_fleet, p_from, p_codes, '{}'::jsonb) m);
end
$body$
  $f$;
  execute $f$
create or replace function public.job_trip(p_fleet uuid, p_from uuid, p_codes text[], p_cost boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: A JOB'S SAIL FROM ONE HARBOUR THROUGH OTHERS. 0504: its body is public.job_trip_memo, asked here with nothing handed over.
begin
  return (select m.o_trip from public.job_trip_memo(p_fleet, p_from, p_codes, p_cost, '{}'::jsonb) m);
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0504 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0504 values
  ('public.sea_actions_for(uuid,uuid)', 1,
$h$  v_t      jsonb;
  v_cut    boolean := false;$h$,
$h$  v_t      jsonb;
  v_memo   jsonb := '{}'::jsonb;   -- 0504: the legs judged and the ways found so far in this read, for this fleet (public.fleet_job_legs_memo)
  v_tb     jsonb;
  v_cut    boolean := false;$h$),
  ('public.sea_actions_for(uuid,uuid)', 2,
$h$      v_t := public.job_trip(p_fleet, v_at, array[v_home, v_code], true);$h$,
$h$      select m.o_trip, m.o_memo into v_t, v_memo from public.job_trip_memo(p_fleet, v_at, array[v_home, v_code], true, v_memo) m;$h$),
  ('public.sea_actions_for(uuid,uuid)', 3,
$h$      v_trips := v_trips || jsonb_build_object(c.port, jsonb_build_object('out', public.job_trip(p_fleet, v_at, array[c.port], false)));$h$,
$h$      select m.o_trip, m.o_memo into v_tb, v_memo from public.job_trip_memo(p_fleet, v_at, array[c.port], false, v_memo) m;
      v_trips := v_trips || jsonb_build_object(c.port, jsonb_build_object('out', v_tb));$h$),
  ('public.sea_actions_for(uuid,uuid)', 4,
$h$      v_t := v_t || jsonb_build_object('back', public.job_trip(p_fleet, v_dest, array[v_code], true));$h$,
$h$      select m.o_trip, m.o_memo into v_tb, v_memo from public.job_trip_memo(p_fleet, v_dest, array[v_code], true, v_memo) m;
      v_t := v_t || jsonb_build_object('back', v_tb);$h$),
  ('voyage.segments_from_course(jsonb)', 1,
$h$  n := coalesce(jsonb_array_length(p_course), 0);
  for i in 0 .. n - 2 loop
    lat1 := (p_course->i->>0)::float8;     lon1 := (p_course->i->>1)::float8;
    lat2 := (p_course->(i+1)->>0)::float8; lon2 := (p_course->(i+1)->>1)::float8;
    pieces := greatest(1, ceil(voyage.gc_distance_nm(lat1, lon1, lat2, lon2) / 500)::int);
    for k in 0 .. pieces - 1 loop
      alat := lat1 + (lat2 - lat1) * k / pieces;       alon := voyage.lon_lerp(lon1, lon2, k::float8 / pieces);
      blat := lat1 + (lat2 - lat1) * (k + 1) / pieces; blon := voyage.lon_lerp(lon1, lon2, (k + 1)::float8 / pieces);
      seg_nm := round(voyage.gc_distance_nm(alat, alon, blat, blon)::numeric, 2);
      continue when seg_nm <= 0;
      mlat := (alat + blat) / 2; mlon := voyage.lon_lerp(alon, blon, 0.5);
      v_row$h$,
$h$    -- 0504: the pieces are voyage.course_pieces' (this body's own loop, moved there whole)
    for alat, alon, blat, blon, seg_nm, mlat, mlon in
      select p.alat, p.alon, p.blat, p.blon, p.seg_nm, p.mlat, p.mlon from voyage.course_pieces(p_course) p
    loop
      v_row$h$),
  ('voyage.segments_from_course(jsonb)', 2,
$h$                            else 1.0 end);
    end loop;
  end loop;$h$,
$h$                            else 1.0 end);
    end loop;$h$),
  ('public.fleet_job_leg_shut(uuid,uuid,jsonb)', 1,
$h$    select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(p_course)) s;$h$,
$h$    v_nm := voyage.course_nm(p_course);   -- 0504: the miles alone$h$),
  ('world.trip_cost(uuid,jsonb)', 1,
$h$          select sum((s ->> 'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_course)) s;$h$,
$h$          v_nm := voyage.course_nm(v_course);   -- 0504: the miles alone$h$),
  ('world.trip_cost(uuid,jsonb)', 2,
$h$  v_hulls  jsonb;
  v_next   jsonb;$h$,
$h$  v_hulls  jsonb;
  v_parts  jsonb;     -- 0504: her voyage.fleet_speed_parts, read once a trip
  v_next   jsonb;$h$),
  ('world.trip_cost(uuid,jsonb)', 3,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days, tl.sail_days into v_hulls, v_w, v_f, v_sea, v_lsail from world.trip_leg(voyage.fleet_speed_parts(p_fleet), v_hulls, v_nm) tl;$h$,
$h$    v_parts := coalesce(v_parts, voyage.fleet_speed_parts(p_fleet));   -- 0504
    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days, tl.sail_days into v_hulls, v_w, v_f, v_sea, v_lsail from world.trip_leg(v_parts, v_hulls, v_nm) tl;$h$),
  ('public.fleet_job_plan(uuid)', 1,
$h$    -- 0502: every sale judged would ruin her: she WAITS$h$,
$h$    -- 0504: the read was cut by its clock and no card it answered is usable: that is no answer, not "nothing pays": asked again at the next tick
    if (v_bs->>'cut')::boolean then
      return jsonb_build_object('wait', 'slow', 'sentence', 'prices are slow: asked again in two minutes');
    end if;
    -- 0502: every sale judged would ruin her: she WAITS$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then$h$,
$h$  elsif p_plan->>'wait' in ('slow', 'unpriced') then
    -- 0504: her sales were not answered (the read was cut, or raised): asked again at the next tick (every two minutes); not stopped
    update public.fleet_jobs
       set next_at = now() + interval '90 seconds',
           last = jsonb_strip_nulls(jsonb_build_object('at', now(), 'wait', p_plan->>'wait', 'sentence', p_plan->>'sentence'))
     where fleet_id = p_fleet and paused_reason is null;
  elsif p_plan->>'wait' in ('nothing', 'identity') then$h$);

  for v_h in select h.fn from hunks_0504 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0504 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0504 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0504 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0504 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0504 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  perform public.news_update('0504', 'Assign shows a fleet''s work sooner, and a fleet on the Best run no longer waits a quarter of an hour when its prices are slow to read',
                             'Assign shows a fleet''s work sooner, and a fleet on the Best run no longer waits a quarter of an hour when its prices are slow to read');

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0504 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0504 self-assert FAIL: the grants, volatility, definer, search path or owner of a cut body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef and p.provolatile = 's') <> 5
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0504 self-assert FAIL: a new function is reachable by a client or service_role, or is not a STABLE definer';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (its own company's rows alone) ──
  begin
    v_me := public.new_house(c_uid, 'Casa Ligeira 0504', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
    perform cmd.assume_identity(c_uid);

    -- A FASTER ASSIGN ANSWERS AS BEFORE: from Lisbon to every fortieth harbour and back, the trip as it was worked out before this file
    -- (the bodies kept above), as public.job_trip answers now, and as it answers with one memo handed through all of them; and the courses'
    -- segments. Nothing is read of the market: a trip is legs, stores, wages and fees.
    for x in
      select q.code, q.id from (select p.code, p.id, row_number() over (order by p.code) as i from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS') q
       where q.i % 40 = 7
    loop
      v_p := pg_temp.was_0504_job_trip(v_fl, v_lis, array[x.code, 'LIS'], true);
      v_r := public.job_trip(v_fl, v_lis, array[x.code, 'LIS'], true);
      select m.o_trip, m.o_memo into v_t, v_memo from public.job_trip_memo(v_fl, v_lis, array[x.code, 'LIS'], true, v_memo) m;
      if v_p::text is distinct from v_r::text or v_p::text is distinct from v_t::text then
        raise exception '0504 self-assert FAIL: the trip to % and back is not what it was: % / % / %', x.code, v_p, v_r, v_t;
      end if;
      v_p := pg_temp.was_0504_job_trip(v_fl, x.id, array['LIS'], false);
      select m.o_trip, m.o_memo into v_t, v_memo from public.job_trip_memo(v_fl, x.id, array['LIS'], false, v_memo) m;
      if v_p::text is distinct from v_t::text then
        raise exception '0504 self-assert FAIL: the miles from % are not what they were: % / %', x.code, v_p, v_t;
      end if;
      v_p := public.fleet_job_course(v_fl, v_lis, x.id);
      if pg_temp.was_0504_segments_from_course(v_p)::text is distinct from voyage.segments_from_course(v_p)::text
         or (select sum((e->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(v_p)) e) is distinct from voyage.course_nm(v_p) then
        raise exception '0504 self-assert FAIL: the segments or the miles of the course to % are not what they were', x.code;
      end if;
      v_trips := v_trips + 1;
    end loop;
    if v_trips < 3 then
      raise exception '0504 self-assert FAIL: % trip(s) compared: the world has fewer harbours than the assert was written for', v_trips;
    end if;

    -- HER WHOLE READ, old and new
    v_c := clock_timestamp();
    v_a := pg_temp.was_0504_sea_actions_for(v_me, v_fl);
    v_ms0 := round(extract(epoch from clock_timestamp() - v_c) * 1000);
    v_c := clock_timestamp();
    v_r := public.sea_actions_for(v_me, v_fl);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_c) * 1000);
    if jsonb_typeof(v_a->'closed') = 'object' or jsonb_typeof(v_r->'closed') = 'object' or (v_a->>'cut')::boolean or (v_r->>'cut')::boolean then
      -- a list past the first eight runs is `cut` by count too: the two are still one text then, unless a clock did it
      v_note := case when v_a::text = v_r::text then 'her read the same' else 'her read was cut by a clock: not judged' end;
    elsif v_a::text is distinct from v_r::text then
      raise exception '0504 self-assert FAIL: her options are not what they were: % / %', left(v_a::text, 900), left(v_r::text, 900);
    else
      v_note := 'her read the same';
    end if;
    v_note := format('%s trips and their miles the same to the letter; %s (%s ms before, %s ms now)', v_trips, v_note, v_ms0, v_ms1);
    raise exception using errcode = 'ZX504', message = 'PROBE_ROLLBACK_0504';
  exception when sqlstate 'ZX504' then
    v_lived := true;
  end;
  -- what stood before, kept for the probe, goes
  for x in select p.oid::regprocedure::text as fn from pg_proc p where p.pronamespace = pg_my_temp_schema() and p.proname like 'was\_0504\_%' loop
    execute 'drop function ' || x.fn;
  end loop;
  if not v_lived then
    raise exception '0504 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa Ligeira 0504' or p.auth_uid = c_uid)
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0504 self-assert FAIL: the probe left something behind, or a knob moved';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0504 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0504 self-assert ok: ASSIGN, FAST. Twelve hunks once and reversing; three bodies wrapped; five new functions server only; no other function moved; no knob moved. Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
