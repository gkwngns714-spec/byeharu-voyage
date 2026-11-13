-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0402: TRADE'S SEA TAG IS THE DOOR'S OWN ANSWER  (docs/SEA_CONDITIONS_AND_REGIONS.md 10.6, row S7; docs/dev-log/2026-11-14-trades-sea-tag.md)
--
-- THE GAP (live since the seas were lit): a Trade row's `sea` tag (public.sea_routes, written into world.good_board's buy and sell rows) took a title
--   and a wave, not a fleet, and asked the plain rule. 0396 gave every fleet two floors (the sea she lies in, her capital's sea); the sail door
--   (public.sea_gate), the pathfinder and world.sea_conditions read them, the tag did not. So a row for a harbour of her home rank, or of the rank of
--   the far sea she lies in, could say "Shut" while its passage was offered and the door let her sail.
--
-- WHAT THIS DOES
--   1. public.sea_routes GAINS THE FLEET: (p_fleet, p_title, p_wave, p_routes). The new body is the live body with three hunks, each once:
--        a. the signature;
--        b. LIT, a leg brings what the door asks on that line: the zones of the straight line between the two roadsteads and the zone of the harbour
--           she makes for (public.sea_gate's own set). Dark, the zones are chosen as before;
--        c. LIT, the verdict is public.sea_judge with the fleet's floors (public.sea_floor, read ONCE a call), asked once per DISTINCT SEA of the
--           board (64 at most), not per row; a route wears the answer of its first refusing sea, in the judge's order. Dark, public.sea_refusal
--           once per distinct set of seas, as before.
--      The old three-argument function is dropped: the board was its one reader, and a tag has one authority.
--   2. world.good_board (TWO HUNKS, the two calls): the buy rows and the sell rows pass the fleet in hand.
--   world.best_sales does not read the tag (it calls no sea function and serves no `sea` key): not cut.
--
-- WHAT IT DOES NOT DO: change a row's figures, its passage, its price, or any key but the `sea` tag; change the door, the pathfinder or the rule;
--   re-derive public.sea_leg_asks from sailed courses (10.6 "the board and the door": the door samples the course she really sails, the board the
--   straight line; that difference stays, and the door still says why at the press).
-- DARK (sea_conditions_bite false): every board row is the same text as before (asserted here on a probe, and in proof 97).
-- COST: one public.sea_floor a call of public.sea_routes (two a board) and one ask of the judge a distinct sea of the board. Timed below.
-- NEWS: this file posts its own UPDATE row, public.news_update('0402', ...) (0347's law): a player in home waters sees rows open that said Shut.
-- ROLLBACK (forward, owner only): scripts/ops/harness/sea-tag/rollback-0402.sql, a draft: the three-argument function back, the two calls back.
-- PROD CHECKS (read-only, one statement each): scripts/ops/harness/sea-tag/before-0402.sql, then after-0402.sql.
-- SELF-ASSERT: the hunks once and reversing, the catalog, then a probe of its own rolled-back rows (the switch is turned INSIDE the probe only).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, lock_timeout 5 s. The self-assert fails above 45 s.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_t1         timestamptz;
  v_def        text;
  v_new_def    text;
  v_n          int;
  v_fn_before  text;
  h            record;
  v_pl         uuid;
  v_fl         uuid;
  v_port       uuid;
  v_far        uuid;
  v_ocode      text;
  v_title      int;
  v_wave       numeric;
  v_routes     jsonb;
  v_old        jsonb;
  v_new        jsonb;
  v_rows       int;
  v_bad        int;
  v_opened     int;
  v_shut       int;
  v_brows      int := 0;
  v_ms_old     numeric := 0;
  v_ms_new     numeric := 0;
  v_calls      int := 0;
  v_report     text;
  gd           record;
  i            int;
  c_uid     constant uuid := '00000000-0402-4000-8000-000000000001';
  c_old     constant text := 'public.sea_routes(integer,numeric,jsonb)';
  c_new     constant text := 'public.sea_routes(uuid,integer,numeric,jsonb)';
  c_board   constant text := 'world.good_board(uuid,uuid,uuid,numeric)';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_new) is not null then
    raise exception '0402 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(array[c_old, c_board, 'public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 'public.sea_floor(uuid,jsonb)',
                                        'public.sea_gate(uuid,uuid,uuid,jsonb)', 'public.sea_conditions_on()', 'public.news_update(text,text,text)']) f
              where to_regprocedure(f) is null) then
    raise exception '0402 refuses: the board''s sea tag (0219, 0222), the two floors (0396) or the news (0347) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0402 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0402
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(array[c_old, c_board]) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid not in (c_old::regprocedure, c_board::regprocedure);
  -- the two pre-images under pg_temp names, for the dark identity and the timing
  execute replace((select def from pre_0402 where fn = c_old), 'FUNCTION public.sea_routes(', 'FUNCTION pg_temp.sea_routes_old_0402(');
  execute replace(replace((select def from pre_0402 where fn = c_board), 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_old_0402('),
                  'public.sea_routes(', 'pg_temp.sea_routes_old_0402(');

  -- ── 2. THE HUNKS: each once on the live body, each reversing to its pre-image ──
  create temp table hunks_0402 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunks_0402 values
    (1, c_old,
$h$FUNCTION public.sea_routes(p_title integer, p_wave numeric, p_routes jsonb)
$h$,
$h$FUNCTION public.sea_routes(p_fleet uuid, p_title integer, p_wave numeric, p_routes jsonb)
$h$),
    (2, c_old,
$h$           case when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$,
$h$           -- 0402: LIT, a leg brings what the door asks on that line (public.sea_gate): the line's zones and the zone of the harbour she makes for
           case when public.sea_conditions_on() then s.zones || hb.zone
                when coalesce(s.title_min > greatest(coalesce(ha.title_min, 0), coalesce(hb.title_min, 0))
$h$),
    (3, c_old,
$h$  judged as materialized (
    select r.i, r.needs_title, r.needs_wave, r.zones, v.refusal
      from route r
      join (select d.zones, public.sea_refusal(p_title, p_wave, d.zones) as refusal
              from (select distinct zones from route) d) v on v.zones is not distinct from r.zones)
$h$,
$h$  -- 0402: LIT, THE DOOR'S OWN ANSWER FOR THE FLEET IN HAND. Each DISTINCT SEA of the board is asked once of public.sea_judge with her two floors
  -- (public.sea_floor, read once a call); a route wears the answer of the first of its seas that refuses, in the judge's own order (the seas of
  -- another rank than both floors, then of the rank she lies in, then of her capital's; requirement order within each). Nothing is judged here.
  seen as materialized (
    select z.code as zone, z.ord, case when z.title_min = fl.title_min then 1 when z.title_min = fl.home_title then 2 else 0 end as lot,
           public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) as refusal
      from (select distinct o.zone from zone_of o where public.sea_conditions_on()) d
      join public.sea_zones z on z.code = d.zone
     cross join (select * from public.sea_floor(p_fleet, null) offset 0) fl),
  -- Dark, the plain rule once per distinct set of seas, as before (the tag is then a reading).
  judged as materialized (
    select r.i, r.needs_title, r.needs_wave, r.zones,
           case when public.sea_conditions_on()
                then (select s.refusal from seen s where s.zone = any (r.zones) and s.refusal is not null order by s.lot, s.ord limit 1)
                else v.refusal end as refusal
      from route r
      left join (select d.zones, public.sea_refusal(p_title, p_wave, d.zones) as refusal
                   from (select distinct zones from route where not public.sea_conditions_on()) d) v on v.zones is not distinct from r.zones)
$h$),
    (4, c_board,
$h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when
$h$,
$h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(public.sea_route_stops(v_ocode, case when
$h$),
    (5, c_board,
$h$    join jsonb_array_elements(public.sea_routes(v_title, v_wave,
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)
$h$,
$h$    join jsonb_array_elements(public.sea_routes(p_fleet, v_title, v_wave,   -- 0402: judged for the fleet in hand, with her floors
           (select coalesce(jsonb_agg(coalesce(v_bpart, '[]'::jsonb)
$h$);
  -- a hunk's text may not end in the middle of a line that another hunk needs: 4 and 5 are told apart by their second line
  update hunks_0402 set old = rtrim(old, E'\n'), new = rtrim(new, E'\n') where ord in (4, 5);

  for h in select fn, (select p.def from pre_0402 p where p.fn = t.fn) as def from (select distinct fn from hunks_0402) t loop
    v_new_def := h.def;
    for i in select ord from hunks_0402 where fn = h.fn order by ord loop
      select (length(v_new_def) - length(replace(v_new_def, k.old, ''))) / length(k.old) into v_n from hunks_0402 k where k.ord = i;
      if v_n <> 1 then
        raise exception '0402 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', i, h.fn, v_n;
      end if;
      select replace(v_new_def, k.old, k.new) into v_new_def from hunks_0402 k where k.ord = i;
    end loop;
    execute v_new_def;   -- for public.sea_routes this makes the four-argument function beside the old one; for the board it replaces the body
  end loop;
  revoke all on function public.sea_routes(uuid, integer, numeric, jsonb) from public, anon, authenticated;
  comment on function public.sea_routes(uuid, integer, numeric, jsonb) is
    '0402: what each route''s seas ask, judged for the fleet in hand: lit, public.sea_judge with her two floors over the zones the door asks; dark, the plain rule (0219, 0222). Read by world.good_board. Server-only.';

  -- each new body holds its hunks once and reverses to its pre-image (last first); grants, volatility, definer, path and owner did not move
  for h in select p.fn, p.def, p.meta, case when p.fn = c_old then c_new else p.fn end as now_fn from pre_0402 p loop
    v_def := replace(pg_get_functiondef(h.now_fn::regprocedure), E'\r', '');
    for i in select ord from hunks_0402 where fn = h.fn order by ord desc loop
      select (length(v_def) - length(replace(v_def, k.new, ''))) / length(k.new) into v_n from hunks_0402 k where k.ord = i;
      if v_n <> 1 then
        raise exception '0402 self-assert FAIL: hunk % of % is in the new body % time(s), not once', i, h.fn, v_n;
      end if;
      select replace(v_def, k.new, k.old) into v_def from hunks_0402 k where k.ord = i;
    end loop;
    if v_def <> h.def then
      raise exception '0402 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.now_fn::regprocedure) <> h.meta then
      raise exception '0402 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.now_fn;
    end if;
  end loop;

  -- ── 3. THE OLD FUNCTION GOES; THE CATALOG ──
  drop function public.sea_routes(integer, numeric, jsonb);
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sea_routes') <> 1
     or has_function_privilege('authenticated', c_new, 'execute') or has_function_privilege('anon', c_new, 'execute') then
    raise exception '0402 self-assert FAIL: public.sea_routes is not one function, server-only';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid not in (c_new::regprocedure, c_board::regprocedure)) <> v_fn_before then
    raise exception '0402 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%public.sea_routes(%' and p.oid <> c_board::regprocedure) then
    raise exception '0402 self-assert FAIL: a function other than the board calls public.sea_routes';
  end if;

  -- ── 4. THE PROBE: a title-1 company of Portugal in a barca, at Lisbon and then lying at Acapulco. Rolled back whole. ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    v_pl := public.new_house(c_uid, 'Casa da Etiqueta 0402', 'PRT', 'LIS', 'Etiqueta', 'barca', 'Etiqueta', null, false);
    select f.id, f.port_id into v_fl, v_port from public.fleets f where f.player_id = v_pl;
    v_far := (select id from public.ports where code = 'ACA' and kind = 'HARBOUR');
    v_title := public.title_level(v_pl);
    v_wave := public.fleet_wave(v_fl);
    if v_port is null or v_far is null or v_title <> 1 then
      raise exception '0402 self-assert FAIL: the probe is not a title-1 company at a harbour, or Acapulco is not in this world';
    end if;
    perform cmd.assume_identity(c_uid);

    -- (a) DARK: the tag and the whole board are the same text as before, at home and lying far
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    for i in 1 .. 2 loop
      update public.fleets set port_id = case when i = 1 then v_port else v_far end where id = v_fl;
      v_ocode := (select code from public.ports where id = case when i = 1 then v_port else v_far end);
      v_routes := (select jsonb_agg(jsonb_build_array(v_ocode, p.code) order by p.code) from public.ports p where p.kind = 'HARBOUR');
      if public.sea_routes(v_fl, v_title, v_wave, v_routes)::text is distinct from pg_temp.sea_routes_old_0402(v_title, v_wave, v_routes)::text then
        raise exception '0402 self-assert FAIL: dark, the tag from % is not the text it was', v_ocode;
      end if;
      for gd in select g.id, g.code from public.goods g order by g.code limit 2 loop
        v_old := pg_temp.good_board_old_0402(gd.id, v_fl, null, null);
        v_new := world.good_board(gd.id, v_fl, null, null);
        if v_old is null or v_new::text is distinct from v_old::text then
          raise exception '0402 self-assert FAIL: dark, the % board from % is not the text it was', gd.code, v_ocode;
        end if;
      end loop;
    end loop;

    -- (b) LIT, LYING AT ACAPULCO: every harbour's direct row is the door's own answer for the straight line (public.sea_gate, asked here for the
    -- same fleet). Rows the plain rule shut are open (the way home), and seas of another rank are shut still.
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    select count(*), count(*) filter (where nullif(t.sea -> 'refusal', 'null'::jsonb) is distinct from g.gate),
           count(*) filter (where g.gate is null and nullif(o.sea -> 'refusal', 'null'::jsonb) is not null), count(*) filter (where g.gate is not null)
      into v_rows, v_bad, v_opened, v_shut
      from (select row_number() over (order by p.code) as i, p.code,
                   case when p.id <> v_far then
                     public.sea_gate(v_pl, v_fl, p.id, jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))) end as gate
              from public.ports p join public.sea_reaches b on b.port_id = p.id join public.sea_reaches a on a.port_id = v_far
             where p.kind = 'HARBOUR') g
      join jsonb_array_elements(public.sea_routes(v_fl, v_title, v_wave, v_routes)) with ordinality t(sea, i) on t.i = g.i
      join jsonb_array_elements(pg_temp.sea_routes_old_0402(v_title, v_wave, v_routes)) with ordinality o(sea, i) on o.i = g.i;
    if v_rows < 100 or v_bad <> 0 or v_opened < 1 or v_shut < 1 then
      raise exception '0402 self-assert FAIL: lit, lying at Acapulco: of % direct rows % differ from the door; % opened by the way home (want 1 or more), % shut still (want 1 or more)',
        v_rows, v_bad, v_opened, v_shut;
    end if;
    -- the board's own rows: a buy row with no stops between is the door's answer too
    for gd in select g.id, g.code from public.goods g order by g.code limit 2 loop
      v_new := world.good_board(gd.id, v_fl, null, null);
      select count(*), count(*) filter (where nullif(e -> 'sea' -> 'refusal', 'null'::jsonb) is distinct from
               public.sea_gate(v_pl, v_fl, b.port_id, jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))))
        into v_n, v_bad
        from jsonb_array_elements(v_new -> 'buy') e
        join public.sea_reaches b on b.code = e ->> 'port' and b.port_id <> v_far
        join public.sea_reaches a on a.port_id = v_far
       where jsonb_typeof(e -> 'miles') <> 'number' or jsonb_array_length(e -> 'stops') = 0;
      if v_bad <> 0 then
        raise exception '0402 self-assert FAIL: lit, the % board at Acapulco: % of % direct buy rows wear a tag that is not the door''s answer', gd.code, v_bad, v_n;
      end if;
      v_brows := v_brows + v_n;
    end loop;

    -- (c) THE COST, lit, at Lisbon: the board before and after, turn about (notice only)
    update public.fleets set port_id = v_port where id = v_fl;
    for i in 1 .. 3 loop
      for gd in select g.id from public.goods g order by g.code limit 2 loop
        v_t1 := clock_timestamp(); v_old := pg_temp.good_board_old_0402(gd.id, v_fl, null, null); v_ms_old := v_ms_old + extract(epoch from clock_timestamp() - v_t1) * 1000;
        v_t1 := clock_timestamp(); v_new := world.good_board(gd.id, v_fl, null, null); v_ms_new := v_ms_new + extract(epoch from clock_timestamp() - v_t1) * 1000;
        v_calls := v_calls + 1;
      end loop;
    end loop;
    raise exception using errcode = 'BV402', message = format(
      'Dark, the tag and two boards are the same text at Lisbon and at Acapulco. Lit, lying at Acapulco: %s direct rows are the door''s own answer, %s that the plain rule shut are open, %s are shut still; %s direct buy rows of two boards agree with the door. A board, lit, at Lisbon: %s ms before, %s ms after (mean of %s).',
      v_rows, v_opened, v_shut, v_brows, round(v_ms_old / v_calls, 1), round(v_ms_new / v_calls, 1), v_calls);
  exception when sqlstate 'BV402' then
    v_report := sqlerrm;
  end;
  if v_report is null or exists (select 1 from public.players where id = v_pl) then
    raise exception '0402 self-assert FAIL: the probe did not run, or did not roll back';
  end if;

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0402', 'Trade shows home waters open', '교역 화면: 본국 바다 열림');

  drop function pg_temp.good_board_old_0402(uuid, uuid, uuid, numeric);
  drop function pg_temp.sea_routes_old_0402(integer, numeric, jsonb);
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0402 self-assert FAIL: the file ran % s, over its 45 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0402 self-assert ok: TRADE''S SEA TAG IS THE DOOR''S OWN ANSWER. Five hunks, each once and reversing; public.sea_routes takes the fleet and is one function; no other function moved. % % ms in all.',
    v_report, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
