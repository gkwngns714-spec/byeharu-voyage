-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0376 - A WALL SAYS WHAT IS SHORT: the player-side reads of the sea conditions, completed. DARK. NO TABLE, NO KNOB, NO SWITCH.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY: owner row 166 (2026-10-20): "in order to sail far distance, one needs better ship and levels", a hard wall per sea (docs/SEA_CONDITIONS_AND_REGIONS.md).
--   Owner row 324 (2026-11-13): "do all, make everything work. open them if everything is built and is workable." The wall (0215, 0216, 0219, 0222) is on
--   prod and dark behind sea_conditions_bite. Before it can be lit a player must be able to SEE it: which seas are closed to which of her fleets, which of
--   the two asks (title, wave resistance) she is short of, where each sea lies on the map, and that a company is never founded inside a sea closed to it.
--   This file serves those four things. It lights nothing: sea_conditions_bite is not written.
--
-- WHAT THIS FILE DOES:
--   1. public.sea_refusal(int, numeric, text[])   ONE HUNK. Its `figures` gain `short_title` and `short_wave`, booleans: true when that ask is above hers,
--        false when her figure is null (a merchant has no title; a fleet with no hull has no wave). The sentence, the order and the six old figures do not
--        move. This function is THE ONE PLACE the comparison is written (0215); the two new figures are written there and nowhere else.
--   2. public.far_powers() -> text[]   NEW, STABLE, internal (no grant). The codes of the nations whose capital harbour's own sea asks a title above 1,
--        in code order. The harbour's sea is read from its self row in public.sea_leg_asks (zones[1], 0222: the roadstead's zone as public.harbour_zone read
--        it at derivation; one primary-key probe a nation, no raster read). Today: AYU BAN GUJ JOS JPN MLB MNG MUG PER PIR RUS.
--   3. cmd.found_house(text, text)   ONE HUNK, after the E_MINOR_POWER door and before the house is made. WHILE public.sea_conditions_on(), founding under a
--        nation of public.far_powers() is refused in this function's own shape: {ok: false, error_code: 'E_FAR_POWER', error_message, fixes, figures
--        {nation, capital, zone, zone_name, needs_title}}. A company at title 1 founded there could not leave its own quay. The fixes name the powers a
--        company may join whose capital lies in open water. Dark, the block is not entered: every founding answers as before.
--   4. world.sea_conditions()   THREE HUNKS. Each zones[] row gains `harbours` (how many harbours lie in it). Each fleets[] row gains `port` (the code of
--        the harbour she lies at, null at sea) and `seas`: an object keyed by zone code holding ONLY the zones that refuse her, each the whole
--        `figures` of public.sea_refusal(title, wave, array[code]): {zone, zone_name, needs_title, title, needs_wave, wave, short_title, short_wave}.
--        The top level gains `far_powers`. `seas` is served
--        whether or not the switch bites; `bite` (unchanged) says if it binds. The fleet's wave is now read once a fleet (it feeds `wave` and `seas`).
--   5. world.sea_zone_map() -> jsonb   NEW registered read, STABLE, to authenticated only, as world.sea_conditions. WHERE EACH SEA LIES, for the map's
--        shading: {cols, rows, cell_deg, codes, runs}. public.sea_zone_cells (0215) holds one byte a 0.25 degree cell, 720 rows of 1440, row 0 the north
--        edge and column 0 at -180, exactly the client's sea raster (0038). A byte is the zone's public.sea_zones.ord; 0 is land or water with no zone.
--        `runs[row]` is that row run-length coded as "value:count,value:count,..."; `codes[value]` is the zone's code, and codes[0] is null. World data,
--        the same for every caller. One registry hunk on public.client_rpc_entry_points, after the world.sea_conditions row.
--   6. world.route_legs(uuid, jsonb)   ONE HUNK. Each leg row gains `sea`. The gate judges a leg's length before its seas (public.passage_gate; the
--        order is NOT changed), so a far city behind a closed sea is shut "too far" and voyage.reach_passage then finds no harbours between. For exactly
--        that leg (the conditions bite, shut E_LEG_TOO_FAR or E_ENDURANCE, `via` null) `sea` is public.sea_gate(player, fleet, to, the leg's course):
--        the sea on the direct course that refuses her, or null when no sea does. In every other case, and always while dark, `sea` is null.
--   7. cmd.refusal_caught(text, text)   ONE HUNK. The one catcher of a raised refusal (cmd.preview, cmd.issue, cmd.issue_lines, cmd.execute_order and so
--        public.orders.error_figures, the armada verbs) kept a DETAIL's figures only in cmd.figures' shape {have, need, unit} and dropped every other, so
--        an order refused E_SEA_CLOSED reached the client with its sentence and no figures. It now ALSO keeps the sea rule's shape (an object whose `zone`
--        is a string and whose `needs_title` and `needs_wave` are numbers). The {have, need, unit} test is the same text; every other shape is still
--        dropped; the function stays IMMUTABLE. No other function filters figures (searched: it is the only body that reads ->'have').
--
-- DECIDED BY DEFAULT (the owner may reverse any of these afterwards):
--   * public.far_powers() lists EVERY nation whose capital's sea asks a title, the minor ones too. Who may be joined stays public.nation_joinable's answer.
--   * cmd.change_country is not cut: the design keeps it open to all (section 5.1). A company that changes country keeps its fleets where they lie.
--   * The far-power door is behind sea_conditions_bite itself, not a switch of its own: it exists only because of the wall, and falls with it.
--   * The map is served run-length coded and computed at each call (about 60 KB; the client keeps it for the session). No table is added to hold it.
--
-- NOT TOUCHED: public.sea_gate, public.passage_gate, public.sea_routes, voyage.reach_passage, world.good_board (re-cut by 0361), voyage.settle (0362, 0367),
--   every merchant reader, every table, every knob. Asserted below: no other function, no world_config row, no relation moves.
-- OVERLAPS: cmd.refusal_caught was written whole by 0050 and not cut since. world.route_legs was written whole by 0346 and not cut since (0360 and 0361 read beside it). public.sea_refusal and world.sea_conditions were last written by 0215 (whole). cmd.found_house was last cut by 0338 (the E_MINOR_POWER door);
--   0354 calls it and does not cut it. public.client_rpc_entry_points was last cut by 0367 (the armada rows) and before it 0360; this file's anchor is the
--   world.sea_conditions row (0215).
-- LOCKS: CREATE OR REPLACE of six small functions and two creates. No ALTER, no table lock, no row written but the probe's (rolled back).
-- COST: world.sea_conditions: one grouped read of the 249 harbour self rows, and per fleet one fleet_wave (as before) and 64 calls of the pure rule.
--   Timed below on a probe company of five fleets. world.sea_zone_map: 720 rows of 1440 bytes walked once; timed below.
-- news: none (nothing a player can see changes with this file: the screens that read these keys, and the news of the wall, come with the client and the
--   file that lights sea_conditions_bite).
-- ROLLBACK (forward, owner only): scripts/ops/harness/sea-wall/rollback-0376.sql, a draft: it reverses the eight hunks and drops the two new functions.
--   Safe at any time while dark; lit, it also removes the far-power door. A client that reads the new keys treats them as optional.
-- SELF-ASSERT: the catalog, the hunks once and reversing, then a probe of its own rolled-back rows (the switch is turned INSIDE the rolled-back probe only).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. The self-assert fails above 45 s.
-- VERSION: 0376. 0364 to 0375 are held by other branches (fight rings, ships, armada, five lights, attacks); none cuts a body this file cuts except
--   public.client_rpc_entry_points, where each anchors on its own line.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t1          timestamptz;
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  h             record;
  v_r           jsonb;
  v_r2          jsonb;
  v_before      jsonb;
  v_pl          uuid;
  v_fl          uuid;
  v_lis         uuid;
  v_far         text[];
  v_lived       boolean := false;
  v_ms_before   numeric;
  v_ms_after    numeric;
  v_ms_map      numeric;
  v_map         jsonb;
  v_bad         text;
  v_caught      text;
  i             int;
  c_uid   constant uuid := '00000000-0376-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0376-4000-8000-000000000002';
  c_uid3  constant uuid := '00000000-0376-4000-8000-000000000003';
  c_cut   constant text[] := array['public.sea_refusal(integer,numeric,text[])', 'cmd.found_house(text,text)', 'world.sea_conditions()',
                                   'public.client_rpc_entry_points()', 'world.route_legs(uuid,jsonb)', 'cmd.refusal_caught(text,text)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.far_powers()') is not null or to_regprocedure('world.sea_zone_map()') is not null then
    raise exception '0376 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut || array['public.sea_conditions_on()', 'public.title_level(uuid)', 'public.fleet_wave(uuid)', 'public.nation_joinable(uuid)',
                                                 'public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'cmd.assume_identity(uuid)',
                                                 'public.form_fleet(uuid,text,uuid)', 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)']) f
              where to_regprocedure(f) is null)
     or to_regclass('public.sea_zone_cells') is null or to_regclass('public.sea_leg_asks') is null then
    raise exception '0376 refuses: the sea conditions (0215, 0222) or an authority this file composes is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0376 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0376
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  v_before := world.sea_conditions();   -- nobody is signed in here: the zones and the names
  -- the catcher's answers before the cut: cmd.figures' shape, another shape, a PostgreSQL DETAIL, none, a message with no code, half the sea's shape
  v_caught := concat_ws('|', cmd.refusal_caught('E_INSUFFICIENT_FUNDS: you hold 5 d. and it costs 9 d.', '{"have": 5, "need": 9, "unit": "d."}')::text,
                             cmd.refusal_caught('E_ENDURANCE: too long', '{"nm": 500, "leg_days": 3}')::text,
                             cmd.refusal_caught('E_NAME_TAKEN: taken', 'Key (id)=(1) already exists')::text,
                             cmd.refusal_caught('E_X: none', null)::text, cmd.refusal_caught('no code here', '{"have": 1, "need": 2, "unit": "t"}')::text,
                             cmd.refusal_caught('E_SEA_CLOSED: half a shape', '{"zone": "NOR-MID", "needs_title": 4}')::text);

  -- ── 2. THE TWO NEW FUNCTIONS ──
  execute $f$
create function public.far_powers()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0376: THE NATIONS WHOSE CAPITAL LIES IN A SEA THAT ASKS A TITLE (above 1), in code order. The capital's sea is its harbour's self row in
  -- public.sea_leg_asks (zones[1], the roadstead's zone, 0222). Read by cmd.found_house (lit: no company is founded there) and world.sea_conditions.
  select coalesce(array_agg(q.code order by q.code), '{}'::text[])
    from (select n.code,
                 (select a.zones[1] from public.ports p join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id
                   where p.code = n.capital_port_code and p.kind = 'HARBOUR') as zone
            from public.nations n) q
    join public.sea_zones z on z.code = q.zone
   where z.title_min > 1
$body$
  $f$;
  revoke all on function public.far_powers() from public, anon, authenticated;
  comment on function public.far_powers() is
    '0376: the codes of the nations whose capital harbour''s own sea asks a title above 1. Lit, no company is founded under one (cmd.found_house).';

  execute $f$
create function world.sea_zone_map()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0376: WHERE EACH SEA LIES (the map's shading). public.sea_zone_cells (0215): one byte a 0.25 degree cell, row 0 the north edge, column 0 at -180;
-- a byte is the zone's public.sea_zones.ord, 0 is land or water with no zone. Answers {cols, rows, cell_deg, codes, runs}: runs[row] is that row
-- run-length coded "value:count,value:count,..."; codes[value] is the zone's code and codes[0] is null. World data, the same for every caller.
declare
  r      record;
  v_runs text[] := '{}';
  v_len  int;
  v_cols int := 0;
  v_s    text;
  v_prev int;
  v_cur  int;
  v_n    int;
  i      int;
begin
  for r in select c.row_idx, c.zones from public.sea_zone_cells c order by c.row_idx loop
    v_len := length(r.zones);
    v_cols := greatest(v_cols, v_len);
    v_s := '';
    v_prev := get_byte(r.zones, 0);
    v_n := 1;
    for i in 1 .. v_len - 1 loop
      v_cur := get_byte(r.zones, i);
      if v_cur = v_prev then
        v_n := v_n + 1;
      else
        v_s := v_s || v_prev || ':' || v_n || ',';
        v_prev := v_cur;
        v_n := 1;
      end if;
    end loop;
    v_runs := v_runs || (v_s || v_prev || ':' || v_n);
  end loop;
  return jsonb_build_object(
    'cols', v_cols,
    'rows', coalesce(array_length(v_runs, 1), 0),
    'cell_deg', case when v_cols > 0 then (360.0 / v_cols)::float8 end,
    'codes', (select jsonb_agg(z.code order by g.o)
                from generate_series(0, (select coalesce(max(ord), 0) from public.sea_zones)) g(o)
                left join public.sea_zones z on z.ord = g.o),
    'runs', to_jsonb(v_runs));
end
$body$
  $f$;
  revoke all on function world.sea_zone_map() from public, anon;
  grant execute on function world.sea_zone_map() to authenticated;
  comment on function world.sea_zone_map() is
    '0376: where each sea lies: the zone raster (0.25 degree cells, row 0 north, column 0 at -180) run-length coded by row, with the zone code of each byte value (0 = land or no zone). A read.';

  -- ── 3. THE EIGHT HUNKS: each once on the live body, each reversing to its pre-image ──
  for h in
    select * from (values
      (1, 'public.sea_refusal(integer,numeric,text[])',
$h$                              'needs_wave', z.wave_min, 'wave', p_wave))
$h$,
$h$                              'needs_wave', z.wave_min, 'wave', p_wave,
                              -- 0376: WHICH OF THE TWO IS SHORT, written here beside the rule and nowhere else (false when her figure is null)
                              'short_title', coalesce(z.title_min > p_title, false), 'short_wave', coalesce(z.wave_min > p_wave, false)))
$h$),
      (2, 'cmd.found_house(text,text)',
$h$  -- The constraints on public.players are the authority. Let them bite, and say what they meant.
$h$,
$h$  -- 0376 (docs/SEA_CONDITIONS_AND_REGIONS.md): WHILE THE SEA CONDITIONS BITE, no company is founded under a country whose capital lies in a sea that
  -- asks a title (public.far_powers): at title 1 she could not leave her own quay. Dark, this block is not entered.
  if public.sea_conditions_on() and v_nation = any (public.far_powers()) then
    return (
      select jsonb_build_object(
               'ok', false, 'error_code', 'E_FAR_POWER',
               'error_message', format('%s lies in %s, which asks title %s. Found your company in open water and sail there.', n.name, z.name, z.title_min),
               'fixes', (select coalesce(jsonb_agg(format('(sail under %s — %s)', o.code, o.name) order by o.code), '[]'::jsonb)
                           from public.nations o where public.nation_joinable(o.id) and not (o.code = any (public.far_powers()))),
               'figures', jsonb_build_object('nation', n.code, 'capital', p.code, 'zone', z.code, 'zone_name', z.name, 'needs_title', z.title_min))
        from public.nations n
        join public.ports p on p.code = n.capital_port_code
        join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id
        join public.sea_zones z on z.code = a.zones[1]
       where n.code = v_nation);
  end if;

  -- The constraints on public.players are the authority. Let them bite, and say what they meant.
$h$),
      (3, 'world.sea_conditions()',
$h$  v_title  int  := public.title_level(public.current_player_id());
begin
$h$,
$h$  v_title  int  := public.title_level(public.current_player_id());
  -- 0376: how many harbours lie in each sea (a harbour's sea is its self row in public.sea_leg_asks, 0222), read once
  v_harb   jsonb := (select coalesce(jsonb_object_agg(q.zone, q.n), '{}'::jsonb)
                       from (select (select a.zones[1] from public.sea_leg_asks a where a.from_port = p.id and a.to_port = p.id) as zone, count(*) as n
                               from public.ports p where p.kind = 'HARBOUR' group by 1) q
                      where q.zone is not null);
begin
$h$),
      (4, 'world.sea_conditions()',
$h$                'code', z.code, 'name', z.name, 'title_min', z.title_min, 'wave_min', z.wave_min, 'ord', z.ord,
$h$,
$h$                'code', z.code, 'name', z.name, 'title_min', z.title_min, 'wave_min', z.wave_min, 'ord', z.ord,
                'harbours', coalesce((v_harb ->> z.code)::int, 0),   -- 0376
$h$),
      (5, 'world.sea_conditions()',
$h$    'fleets', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'wave', public.fleet_wave(f.id))
                                         order by f.created_at), '[]'::jsonb)
                 from public.fleets f where v_player is not null and f.player_id = v_player));
$h$,
$h$    -- 0376: + `port` (where she lies; null at sea) and `seas`: ONLY the zones that refuse her, keyed by zone code, each the whole `figures` of
    -- public.sea_refusal for that zone (the one rule, asked a zone at a time): nothing is compared here. Served dark and lit: `bite` says if it binds.
    'fleets', (select coalesce(jsonb_agg(jsonb_build_object(
                          'id', f.id, 'name', f.name, 'wave', w.wave,
                          'port', (select p.code from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR'),
                          'seas', (select coalesce(jsonb_object_agg(z.code, r.x -> 'figures'), '{}'::jsonb)
                                     from public.sea_zones z
                                    cross join lateral (select public.sea_refusal(v_title, w.wave, array[z.code]) as x) r
                                    where r.x is not null))
                                         order by f.created_at), '[]'::jsonb)
                 from public.fleets f cross join lateral (select public.fleet_wave(f.id) as wave offset 0) w   -- offset 0: her wave is read ONCE a fleet, not once a zone
                where v_player is not null and f.player_id = v_player),
    'far_powers', to_jsonb(public.far_powers()));   -- 0376: the countries no company is founded under while the conditions bite
$h$),
      (6, 'public.client_rpc_entry_points()',
$h$      ('world',       'sea_conditions',        ''),
$h$,
$h$      ('world',       'sea_conditions',        ''),
      -- 0376: where each sea lies, for the map's shading (the zone raster, run-length coded).
      ('world',       'sea_zone_map',          ''),
$h$),
      (7, 'world.route_legs(uuid,jsonb)',
$h$      'via', v_via));
$h$,
$h$      'via', v_via,
      -- 0376: WHEN IT IS A SEA THAT STOPS HER. The gate judges a leg's length before its seas (public.passage_gate, unchanged), so a city behind a
      -- closed sea reads "too far" and no chain of harbours opens it. Lit, for such a leg (shut by its length or its stores, no harbours between),
      -- `sea` is public.sea_gate's own refusal on the direct course, or null when the seas are not what stops her. Dark: always null.
      'sea', case when v_via is null and v_shut ->> 'code' in ('E_LEG_TOO_FAR', 'E_ENDURANCE') and public.sea_conditions_on()
                  then public.sea_gate(v_player, p_fleet, v_to, v_rows[i] -> 'course') end));
$h$),
      (8, 'cmd.refusal_caught(text,text)',
$h$    if v_figs is null
$h$,
$h$    -- 0376: THE SEA RULE'S FIGURES ARE KEPT TOO (public.sea_refusal: an object whose `zone` is a string and whose `needs_title` and `needs_wave` are
    -- numbers), so an order refused E_SEA_CLOSED reaches the client with what the sea asks and what she holds. Every other shape is dropped as before.
    if v_figs is not null and jsonb_typeof(v_figs) = 'object' and jsonb_typeof(v_figs->'zone') = 'string'
       and jsonb_typeof(v_figs->'needs_title') = 'number' and jsonb_typeof(v_figs->'needs_wave') = 'number' then
      null;
    elsif v_figs is null
$h$)) as t(ord, fn, old, new)
    order by 1
  loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0376 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0376 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
  end loop;
  -- each cut body reverses to its pre-image (the hunks of one function are undone last first), and its ACL, volatility, definer, path and owner did not move
  for h in select p.fn, p.def, p.meta from pre_0376 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if h.fn = 'public.sea_refusal(integer,numeric,text[])' then
      v_def := replace(v_def, $h$                              'needs_wave', z.wave_min, 'wave', p_wave,
                              -- 0376: WHICH OF THE TWO IS SHORT, written here beside the rule and nowhere else (false when her figure is null)
                              'short_title', coalesce(z.title_min > p_title, false), 'short_wave', coalesce(z.wave_min > p_wave, false)))
$h$, $h$                              'needs_wave', z.wave_min, 'wave', p_wave))
$h$);
    elsif h.fn = 'cmd.found_house(text,text)' then
      v_def := substr(v_def, 1, position('  -- 0376 (docs/SEA_CONDITIONS_AND_REGIONS.md): WHILE THE SEA CONDITIONS BITE' in v_def) - 1)
               || substr(v_def, position('  -- The constraints on public.players are the authority.' in v_def));
    elsif h.fn = 'world.sea_conditions()' then
      v_def := substr(v_def, 1, position('  -- 0376: how many harbours lie in each sea' in v_def) - 1) || substr(v_def, position(E'begin\n  return jsonb_build_object(' in v_def));
      v_def := replace(v_def, $h$                'harbours', coalesce((v_harb ->> z.code)::int, 0),   -- 0376
$h$, '');
      v_def := substr(v_def, 1, position('    -- 0376: + `port` (where she lies; null at sea)' in v_def) - 1)
               || $h$    'fleets', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'wave', public.fleet_wave(f.id))
                                         order by f.created_at), '[]'::jsonb)
                 from public.fleets f where v_player is not null and f.player_id = v_player));
$h$ || substr(v_def, position(E'end $function$' in v_def));
    elsif h.fn = 'cmd.refusal_caught(text,text)' then
      v_def := substr(v_def, 1, position($h$    -- 0376: THE SEA RULE'S FIGURES ARE KEPT TOO$h$ in v_def) - 1)
               || $h$    if v_figs is null
$h$ || substr(v_def, position($h$       or jsonb_typeof(v_figs) is distinct from 'object'$h$ in v_def));
    elsif h.fn = 'world.route_legs(uuid,jsonb)' then
      v_def := substr(v_def, 1, position($h$      'via', v_via,
      -- 0376: WHEN IT IS A SEA THAT STOPS HER$h$ in v_def) - 1)
               || $h$      'via', v_via));
$h$ || substr(v_def, position($h$  end loop;
  return jsonb_build_object('legs', v_out);$h$ in v_def));
    else
      v_def := replace(v_def, $h$      -- 0376: where each sea lies, for the map's shading (the zone raster, run-length coded).
      ('world',       'sea_zone_map',          ''),
$h$, '');
    end if;
    if v_def <> h.def then
      raise exception '0376 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> h.meta then
      raise exception '0376 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;

  -- ── 4. THE CATALOG ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut || array['public.far_powers()', 'world.sea_zone_map()']) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0376 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0376 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.sea_zone_map()'::regprocedure)
     is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.sea_conditions()'::regprocedure)
     or has_function_privilege('anon', 'world.sea_zone_map()', 'execute') or not has_function_privilege('authenticated', 'world.sea_zone_map()', 'execute') then
    raise exception '0376 self-assert FAIL: world.sea_zone_map is not STABLE, definer, to authenticated only, as its sibling world.sea_conditions';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.far_powers()'::regprocedure) <> 's'
     or has_function_privilege('authenticated', 'public.far_powers()', 'execute') or has_function_privilege('anon', 'public.far_powers()', 'execute') then
    raise exception '0376 self-assert FAIL: public.far_powers is not STABLE and internal';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'sea_zone_map' and e.arg_types = '' and e.fn is not null) then
    raise exception '0376 self-assert FAIL: world.sea_zone_map is not in the client registry';
  end if;

  -- ── 5. THE RULE: the two new figures, and nothing else moved ──
  v_r := public.sea_refusal(1, 12, array['NOR-MID']);
  if v_r is null or (v_r -> 'figures') <> jsonb_build_object('zone', 'NOR-MID', 'zone_name', z.name, 'needs_title', z.title_min, 'title', 1, 'needs_wave', z.wave_min, 'wave', 12,
                                                              'short_title', true, 'short_wave', true)
     or v_r ->> 'code' <> 'E_SEA_CLOSED'
     or v_r ->> 'sentence' <> format('%s asks title %s and wave resistance %s — you are title 1 and your fleet holds 12', z.name, z.title_min, z.wave_min)
     from public.sea_zones z where z.code = 'NOR-MID' then
    raise exception '0376 self-assert FAIL: the rule at title 1, wave 12 on the Western Ocean: %', v_r;
  end if;
  v_r := public.sea_refusal((select title_min from public.sea_zones where code = 'NOR-MID'), 12, array['NOR-MID']);
  v_r2 := public.sea_refusal(1, (select wave_min from public.sea_zones where code = 'NOR-MID'), array['NOR-MID']);
  if (v_r -> 'figures' ->> 'short_title')::boolean or not (v_r -> 'figures' ->> 'short_wave')::boolean
     or not (v_r2 -> 'figures' ->> 'short_title')::boolean or (v_r2 -> 'figures' ->> 'short_wave')::boolean then
    raise exception '0376 self-assert FAIL: one ask short: wave only %, title only %', v_r, v_r2;
  end if;
  v_r := public.sea_refusal(null, 12, array['NOR-MID']);   -- a merchant: no title
  v_r2 := public.sea_refusal(1, null, array['NOR-MID']);   -- a title-only ask
  if (v_r -> 'figures' -> 'short_title') <> 'false'::jsonb or (v_r -> 'figures' -> 'short_wave') <> 'true'::jsonb
     or (v_r2 -> 'figures' -> 'short_title') <> 'true'::jsonb or (v_r2 -> 'figures' -> 'short_wave') <> 'false'::jsonb then
    raise exception '0376 self-assert FAIL: a null figure is not "not short": % and %', v_r, v_r2;
  end if;
  if public.sea_refusal(11, 99, (select array_agg(code) from public.sea_zones)) is not null then
    raise exception '0376 self-assert FAIL: title 11 and wave 99 are refused somewhere';
  end if;

  -- the catcher: every old answer is the same text; the sea rule's figures are kept whole; it is still IMMUTABLE
  if concat_ws('|', cmd.refusal_caught('E_INSUFFICIENT_FUNDS: you hold 5 d. and it costs 9 d.', '{"have": 5, "need": 9, "unit": "d."}')::text,
                             cmd.refusal_caught('E_ENDURANCE: too long', '{"nm": 500, "leg_days": 3}')::text,
                             cmd.refusal_caught('E_NAME_TAKEN: taken', 'Key (id)=(1) already exists')::text,
                             cmd.refusal_caught('E_X: none', null)::text, cmd.refusal_caught('no code here', '{"have": 1, "need": 2, "unit": "t"}')::text,
                             cmd.refusal_caught('E_SEA_CLOSED: half a shape', '{"zone": "NOR-MID", "needs_title": 4}')::text) is distinct from v_caught
     or cmd.refusal_caught('E_ENDURANCE: too long', '{"nm": 500, "leg_days": 3}') ? 'figures'
     or cmd.refusal_caught('E_SEA_CLOSED: half a shape', '{"zone": "NOR-MID", "needs_title": 4}') ? 'figures'
     or (cmd.refusal_caught('E_INSUFFICIENT_FUNDS: short', '{"have": 5, "need": 9, "unit": "d."}') -> 'figures') is distinct from '{"have": 5, "need": 9, "unit": "d."}'::jsonb then
    raise exception '0376 self-assert FAIL: cmd.refusal_caught moved an old answer, or keeps a shape that is not the sea rule''s whole';
  end if;
  v_r := public.sea_refusal(1, 12, array['NOR-MID']);
  if cmd.refusal_caught('E_SEA_CLOSED: ' || (v_r ->> 'sentence'), (v_r -> 'figures')::text) is distinct from v_r
     or (select p.provolatile from pg_proc p where p.oid = 'cmd.refusal_caught(text,text)'::regprocedure) <> 'i' then
    raise exception '0376 self-assert FAIL: a caught sea refusal is not the rule''s own refusal back, or the catcher is no longer IMMUTABLE';
  end if;

  -- ── 6. THE FAR POWERS: the derivation, said a second way through the raster reading (public.harbour_zone) ──
  v_far := public.far_powers();
  if v_far is distinct from (select coalesce(array_agg(n.code order by n.code), '{}'::text[])
                               from public.nations n join public.ports p on p.code = n.capital_port_code
                               join public.sea_zones z on z.code = public.harbour_zone(p.id)
                              where z.title_min > 1)
     or 'PRT' = any (v_far) or cardinality(v_far) = 0 then
    raise exception '0376 self-assert FAIL: public.far_powers answers %, not the nations whose capital''s roadstead lies in a sea asking a title', v_far;
  end if;

  -- ── 7. THE CONDITIONS READ, nobody signed in: the old keys are the old values; the new keys are there ──
  v_r := world.sea_conditions();
  if (v_r - 'far_powers' - 'zones') <> (v_before - 'zones')
     or (select jsonb_agg(z - 'harbours' order by (z ->> 'ord')::int) from jsonb_array_elements(v_r -> 'zones') z) <> (v_before -> 'zones')
     or (v_r -> 'far_powers') <> to_jsonb(v_far)
     or (select sum((z ->> 'harbours')::int) from jsonb_array_elements(v_r -> 'zones') z) <> (select count(*) from public.ports where kind = 'HARBOUR')
     or exists (select 1 from jsonb_array_elements(v_r -> 'zones') z where not (z ? 'harbours')) then
    raise exception '0376 self-assert FAIL: world.sea_conditions for nobody: an old key moved, or `harbours` does not add up to the harbours, or `far_powers` is not the function''s';
  end if;

  -- ── 8. THE MAP: every row decodes to the stored bytes; the codes are the zones by ord ──
  v_t1 := clock_timestamp();
  v_map := world.sea_zone_map();
  v_ms_map := round(extract(epoch from clock_timestamp() - v_t1) * 1000);
  if (v_map ->> 'cols')::int <> 1440 or (v_map ->> 'rows')::int <> 720 or (v_map ->> 'cell_deg')::numeric <> 0.25
     or jsonb_array_length(v_map -> 'runs') <> 720 or (v_map -> 'codes' -> 0) <> 'null'::jsonb
     or jsonb_array_length(v_map -> 'codes') <> (select max(ord) + 1 from public.sea_zones)
     or exists (select 1 from public.sea_zones z where (v_map -> 'codes' ->> z.ord) is distinct from z.code) then
    raise exception '0376 self-assert FAIL: the map''s shape: cols %, rows %, cell %, % codes', v_map ->> 'cols', v_map ->> 'rows', v_map ->> 'cell_deg', jsonb_array_length(v_map -> 'codes');
  end if;
  select min(c.row_idx)::text into v_bad
    from public.sea_zone_cells c
   where (select string_agg(repeat(chr(65 + split_part(t.run, ':', 1)::int), split_part(t.run, ':', 2)::int), '' order by t.k)
            from unnest(string_to_array(v_map -> 'runs' ->> c.row_idx, ',')) with ordinality t(run, k))
         is distinct from (select string_agg(chr(65 + get_byte(c.zones, g)), '' order by g) from generate_series(0, length(c.zones) - 1) g)
     and c.row_idx % 9 = 0;   -- every ninth row decoded whole (80 rows, 115,200 cells): the coder is one loop, the same for every row
  if v_bad is not null then
    raise exception '0376 self-assert FAIL: row % of the map does not decode to the stored bytes', v_bad;
  end if;
  if exists (select 1 from public.sea_zone_cells c
              where (select sum(split_part(t.run, ':', 2)::int) from unnest(string_to_array(v_map -> 'runs' ->> c.row_idx, ',')) t(run)) <> length(c.zones)) then
    raise exception '0376 self-assert FAIL: a row of the map does not count to its width';
  end if;

  -- ── 9. THE PROBE: its own rows, rolled back ──
  begin
    v_lis := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
    -- (a) DARK: founding under a far power answers as before (Japan is let in)
    if public.sea_conditions_on() then
      update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    end if;
    perform cmd.assume_identity(c_uid);
    v_r := cmd.found_house('Casa Longe 0376', 'JPN');
    if (v_r ->> 'ok') <> 'true' or (v_r ->> 'nation') <> 'JPN' then
      raise exception '0376 self-assert FAIL: dark, founding under Japan answered %', v_r;
    end if;
    -- (b) LIT: Japan is refused with the figures and the open powers; Portugal is let in
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    perform cmd.assume_identity(c_uid2);
    v_r := cmd.found_house('Casa Longe B 0376', 'JPN');
    if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error_code') <> 'E_FAR_POWER'
       or (v_r -> 'figures' ->> 'nation') <> 'JPN' or (v_r -> 'figures' ->> 'capital') <> (select capital_port_code from public.nations where code = 'JPN')
       or (v_r -> 'figures' ->> 'needs_title')::int <= 1 or (v_r -> 'figures' ->> 'zone_name') is null
       or (v_r ->> 'error_message') !~ '^Japan lies in .+, which asks title [0-9]+\. Found your company in open water and sail there\.$'
       or jsonb_array_length(v_r -> 'fixes') = 0 or (v_r -> 'fixes')::text ~ 'JPN' or (v_r -> 'fixes')::text !~ 'PRT'
       or exists (select 1 from public.players p where p.auth_uid = c_uid2) then
      raise exception '0376 self-assert FAIL: lit, founding under Japan answered %', v_r;
    end if;
    v_r := cmd.found_house('Casa Perto 0376', 'PRT');
    if (v_r ->> 'ok') <> 'true' then
      raise exception '0376 self-assert FAIL: lit, founding under Portugal answered %', v_r;
    end if;
    v_pl := (v_r ->> 'player_id')::uuid;
    -- the doors before it still answer first: a minor power, a nobody
    perform cmd.assume_identity(c_uid3);
    if (cmd.found_house('Casa Menor 0376', 'VEN') ->> 'error_code') <> 'E_MINOR_POWER' or (cmd.found_house('Casa Menor 0376', 'ZZZ') ->> 'error_code') <> 'E_NO_SUCH_NATION' then
      raise exception '0376 self-assert FAIL: lit, the doors before the far-power door moved';
    end if;

    -- (c) HER CONDITIONS: a title-1 company at Lisbon with the ship it was founded with
    perform cmd.assume_identity(c_uid2);
    v_r := world.sea_conditions();
    select f.id into v_fl from public.fleets f where f.player_id = v_pl order by f.created_at limit 1;
    if jsonb_array_length(v_r -> 'fleets') < 1 or (v_r -> 'fleets' -> 0 ->> 'port') <> 'LIS'
       or (v_r -> 'fleets' -> 0 ->> 'wave')::numeric is distinct from public.fleet_wave(v_fl)
       or (v_r -> 'fleets' -> 0 -> 'seas') ? 'NOR-EU' or (v_r -> 'fleets' -> 0 -> 'seas') ? 'MED'
       or not ((v_r -> 'fleets' -> 0 -> 'seas') ? 'NOR-MID')
       -- every zone is in `seas` exactly when the rule refuses it, with the rule's own flags
       or exists (select 1 from public.sea_zones z
                   cross join lateral (select public.sea_refusal(public.title_level(v_pl), public.fleet_wave(v_fl), array[z.code]) as x) q
                   where ((v_r -> 'fleets' -> 0 -> 'seas') ? z.code) is distinct from (q.x is not null)
                      or (q.x is not null and (v_r -> 'fleets' -> 0 -> 'seas' -> z.code) <> (q.x -> 'figures'))) then
      raise exception '0376 self-assert FAIL: her conditions: the port, the wave, or `seas` is not the rule''s verdict a zone: %', v_r -> 'fleets' -> 0;
    end if;

    -- (c1) AN ORDER REFUSED BY THE SEA carries the rule's figures: the real preview of SAIL LPA (Las Palmas, Macaronesia: title 2) at title 1
    v_r := cmd.preview(v_fl, 'SAIL LPA', null);
    if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error_code') is distinct from 'E_SEA_CLOSED'
       or (v_r -> 'figures' ->> 'zone') is distinct from 'NOR-MAC' or (v_r -> 'figures' ->> 'needs_title')::int is distinct from 2
       or (v_r -> 'figures' ->> 'title')::int is distinct from 1
       or (v_r -> 'figures' -> 'short_title') is distinct from 'true'::jsonb or (v_r -> 'figures' -> 'short_wave') is distinct from 'false'::jsonb then
      raise exception '0376 self-assert FAIL: lit, the preview of SAIL LPA at title 1: %', v_r;
    end if;

    -- (c2) THE LEGS: lit, a far city behind a closed sea names the sea; a near city and a leg with harbours between say none. Dark: never.
    v_r := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', 'HNL'), jsonb_build_object('from', 'LIS', 'to', 'OPO'),
                                                    jsonb_build_object('from', 'LIS', 'to', 'STO'), jsonb_build_object('from', 'LIS', 'to', 'NAG')));
    if (v_r -> 'legs' -> 0 -> 'shut' ->> 'code') not in ('E_LEG_TOO_FAR', 'E_ENDURANCE') or (v_r -> 'legs' -> 0 -> 'via') <> 'null'::jsonb
       or (v_r -> 'legs' -> 0 -> 'sea' ->> 'code') is distinct from 'E_SEA_CLOSED'
       or (v_r -> 'legs' -> 0 -> 'sea') is distinct from public.sea_gate(v_pl, v_fl, (select id from public.ports where code = 'HNL'), null)
       or (v_r -> 'legs' -> 1 -> 'shut') <> 'null'::jsonb or (v_r -> 'legs' -> 1 -> 'sea') <> 'null'::jsonb
       or exists (select 1 from jsonb_array_elements(v_r -> 'legs') l
                   where not (l ? 'sea') or ((l -> 'sea') <> 'null'::jsonb and ((l -> 'via') <> 'null'::jsonb or (l -> 'shut' ->> 'code') not in ('E_LEG_TOO_FAR', 'E_ENDURANCE')))) then
      raise exception '0376 self-assert FAIL: lit, the legs from Lisbon (Honolulu, Porto, Stockholm, Nagasaki): %', v_r;
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    v_r2 := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', 'HNL'), jsonb_build_object('from', 'LIS', 'to', 'OPO'),
                                                     jsonb_build_object('from', 'LIS', 'to', 'STO'), jsonb_build_object('from', 'LIS', 'to', 'NAG')));
    if exists (select 1 from jsonb_array_elements(v_r2 -> 'legs') l
                where (l -> 'sea') <> 'null'::jsonb
                   or (select array_agg(k order by k) from jsonb_object_keys(l) k) <> array['days', 'from', 'nm', 'sea', 'shut', 'supplies', 'to', 'via']) then
      raise exception '0376 self-assert FAIL: dark, a leg names a sea or its keys moved: %', v_r2;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';

    -- (d) THE COST, a company of five fleets: the old body's fleets read against the new
    update public.world_config set value = '5'::jsonb where key = 'fleet_max';   -- the probe's own room, rolled back with it
    for i in 2 .. 5 loop
      perform public.commission_ship(v_pl, public.form_fleet(v_pl, 'Frota ' || i, v_lis), 'barca', 'Barca ' || i, true, true);
    end loop;
    v_t1 := clock_timestamp();
    for i in 1 .. 5 loop
      perform (select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'wave', public.fleet_wave(f.id)) order by f.created_at)
                 from public.fleets f where f.player_id = v_pl);
    end loop;
    v_ms_before := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 5, 1);
    v_t1 := clock_timestamp();
    for i in 1 .. 5 loop
      v_r := world.sea_conditions();
    end loop;
    v_ms_after := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 5, 1);
    if jsonb_array_length(v_r -> 'fleets') <> 5 then
      raise exception '0376 self-assert FAIL: the probe''s five fleets read as %', jsonb_array_length(v_r -> 'fleets');
    end if;
    raise exception using errcode = 'ZX376', message = 'PROBE_ROLLBACK_0376';
  exception when sqlstate 'ZX376' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0376 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid in (c_uid, c_uid2, c_uid3) or p.company_name like '% 0376') then
    raise exception '0376 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0376 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0376 self-assert FAIL: a world_config row moved: this file sets no knob, and the probe''s switch did not roll back';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0376 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0376 self-assert ok: A WALL SAYS WHAT IS SHORT. Eight hunks, each once and reversing; two new functions; no other function, knob or relation moved. The rule''s figures gain short_title and short_wave. Far powers: %. Dark, Japan founds as before; lit, E_FAR_POWER with figures, Portugal founds. world.sea_conditions: `harbours` adds up, `seas` is the rule''s verdict a zone; a leg behind a closed sea names it (lit only); an order the sea refuses carries the rule''s figures; five fleets: fleets read % ms before, whole read % ms after. world.sea_zone_map: % ms, % bytes. % ms in all.',
    array_to_string(v_far, ' '), v_ms_before, v_ms_after, v_ms_map, length(v_map::text), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
