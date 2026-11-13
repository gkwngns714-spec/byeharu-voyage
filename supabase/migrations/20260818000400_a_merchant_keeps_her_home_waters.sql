-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0400 - A MERCHANT KEEPS HER HOME WATERS  (so the merchants' sea light, 0399, can be lit)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the merchants' guard refuses on prod, rightly (scripts/ops/harness/sea-light/before-npc.sql, 2026-11-14 16:04 UTC): `merchants_with_no_open_leg` 8.
--   Eight merchants have NO known leg from home that their hull holds: lit, each would be laid up for ever. The players met the same wall and were given
--   HOME WATERS and THE WAY HOME by 0396 (public.sea_floor, public.sea_judge): a sea of the same rank as the sea she lies in, or as her home's sea, asks
--   her hull no more than that sea asked. This file gives merchants the same two floors. A merchant has no title, so (0397's rule) she is judged on her
--   wave resistance only: the floors raise the wave she is taken to hold in the seas of those two ranks, and nothing else.
--
-- WHAT THIS FILE DOES:
--   1. public.npc_sea_floor(fleet) -> (wave, lie_title, lie_wave, home_title, home_wave)   NEW, STABLE, server-only. Her fleet's wave resistance
--        (public.fleet_wave), what the sea she LIES in asks (public.sea_floor, 0396) and what the sea of her HOME asks: her house's home port
--        (public.npc_houses.home_port_id), else the first stop of her route.
--   2. public.npc_sea_shut(wave, dest, course, lie_title, lie_wave, home_title, home_wave)   NEW overload, STABLE, server-only: 0397's question asked
--        through public.sea_judge (0396) with a null title. The three-argument public.npc_sea_shut of 0397 is not touched.
--   3. FOUR HUNKS, each once and reversing (two on public.npc_feasible_legs):
--        public.npc_feasible_legs    the legs out of a harbour her hull can hold: judged with her floors, read once a call, only while the switch is on
--        public.npc_loop_sea_shut    whether a loop has a leg she cannot hold: the same
--        public.sea_conditions_npc_ready (0399)   `merchants_with_no_open_leg` counts with the same judge, so the guard reads what the planner will do
--   OFF = UNCHANGED: public.npc_feasible_legs reads the floors only while sea_conditions_bite_npc is on (asserted: 40 merchants' legs are the same text
--   before and after this file with the switch off). public.npc_loop_sea_shut is called by the planner only while the switch is on (0397).
--
--   4. THE COAST LEGS (added after the prod read of 2026-11-14 16:19 UTC named the eight: barcas whose loop starts at Cape Coast, where every leg the
--        world remembers crosses The Doldrums (asks 24) although Lagos lies 279 nm along her own coast). A merchant sails only courses the world
--        remembers (public.npc_known_legs), and at seventeen harbours it remembers no leg that stays in water asking no more than the harbour's own
--        sea. public.npc_coast_courses (NEW TABLE, derived here, never hand-written) holds, for each such harbour, the straight course between the
--        two roadsteads to up to three nearest harbours of seas of the same rank, where that line is open water (voyage.path_refusal) and crosses no
--        sea asking more wave than her own. public.npc_coast_legs(port) (NEW) reads them both ways. public.npc_feasible_legs offers them ONLY WHILE
--        THE SWITCH IS ON (one more hunk), and the guard counts them. So a merchant lying at such a harbour has a way along her own coast; she is
--        judged by the same rule as every other.
--
-- WHAT IT DOES NOT DO: it does not light anything; it does not found the far-trader houses (S4); it does not move a merchant. A merchant at sea when the
--   switch is lit finishes her trip (the sail door never asks a merchant, 0107) and is re-planned at her next lap start (0397).
-- LOCKS: CREATE OR REPLACE of three functions, three creates, one small new table and its rows (a few dozen). No existing table is written, no knob.
-- COST: public.npc_feasible_legs, lit: one public.npc_sea_floor a call (two primary-key reads and public.sea_floor), then public.sea_judge a leg in
--   place of public.sea_refusal a leg. Timed below on 20 merchants, lit, before and after.
-- news: none (nothing a player can see changes with this file; the news of the merchants' wall is 0399's step).
-- ROLLBACK (forward, owner only): scripts/ops/harness/sea-merchants/rollback-0400.sql, a draft: the three hunks reversed, the two functions dropped.
--   Or at once: sea_conditions_bite_npc false (it is false).
-- SELF-ASSERT: the hunks once and reversing, grants and volatility unmoved, no other function moved; dark parity on 40 merchants; the judge on pure
--   figures (a sea of her home's rank is held, a sea of another rank is not); no merchant of this world is left without an open leg.
-- BUDGET: ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. The self-assert fails above 45 s.
-- SUPERSEDES by hunk (re-cut, not rewritten): public.npc_feasible_legs and public.npc_loop_sea_shut of 0397, public.sea_conditions_npc_ready of 0399.
--   The new seven-argument public.npc_sea_shut is an overload beside 0397's three-argument one, which stays as it is.
-- VERSION: 0400 = 0399 + 1. Cuts bodies last written by 0397 (npc_feasible_legs, npc_loop_sea_shut) and 0399 (sea_conditions_npc_ready); nothing else has
--   cut them since.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_t1        timestamptz;
  v_def       text;
  v_n         int;
  h           record;
  v_fn_before text;
  v_dark      text;
  v_ms_before numeric;
  v_ms_after  numeric;
  v_lit       boolean;
  v_r         jsonb;
  v_z         record;
  v_other     record;
  v_port      uuid;
  v_port2     uuid;
  v_coast     int;
  v_gap       int;
  v_cap       text;
  c_cut constant text[] := array['public.npc_feasible_legs(uuid,uuid,numeric,integer)', 'public.npc_loop_sea_shut(uuid,jsonb)', 'public.sea_conditions_npc_ready()'];
  c_new constant text[] := array['public.npc_sea_floor(uuid)', 'public.npc_sea_shut(numeric,uuid,jsonb,integer,integer,integer,integer)', 'public.npc_coast_legs(uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.npc_sea_floor(uuid)') is not null then
    raise exception '0400 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut || array['public.sea_floor(uuid,jsonb)', 'public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)',
                                                 'public.npc_sea_shut(numeric,uuid,jsonb)', 'public.npc_course_zones(jsonb)', 'public.sea_conditions_npc_on()']) f
              where to_regprocedure(f) is null) then
    raise exception '0400 refuses: 0396 (the floors), 0397 (the merchants'' rule) or 0399 (the merchants'' step) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0400 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0400
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);
  v_lit := public.sea_conditions_npc_on();
  create temp table probe_0400 on commit drop as
  select nf.fleet_id, greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
         (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home
    from public.npc_fleets nf where nf.route_id is not null order by nf.roster_ord limit 40;
  -- dark, the legs offered to 40 merchants; then lit, the cost before the cut. The switch is turned INSIDE A BLOCK THAT IS ROLLED BACK (the sentinel below):
  -- its row is never left written by this file.
  begin
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  select md5(string_agg(p.fleet_id::text || public.npc_feasible_legs(p.home, p.fleet_id, p.speed, 400)::text, '|' order by p.fleet_id)) into v_dark from probe_0400 p;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  v_t1 := clock_timestamp();
  perform public.npc_feasible_legs(p.home, p.fleet_id, p.speed, 400) from probe_0400 p where p.home is not null order by p.fleet_id limit 20;
  v_ms_before := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 20.0, 1);
  raise exception sqlstate 'BV400';
  exception when sqlstate 'BV400' then null;
  end;

  -- ── 2. THE TWO NEW FUNCTIONS ──
  execute $f$
create function public.npc_sea_floor(p_fleet uuid, out wave numeric, out lie_title integer, out lie_wave integer, out home_title integer, out home_wave integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0400: A MERCHANT'S TWO FLOORS, and her wave. The sea she LIES in is public.sea_floor's reading (0396: her harbour's sea, else where she rides). Her HOME
  -- is her house's home port (public.npc_houses), else the first stop of her route; its sea is its self row in public.sea_leg_asks (0222).
  select public.fleet_wave(p_fleet), fl.title_min, fl.wave_min, z.title_min, z.wave_min
    from public.fleets f
   cross join lateral public.sea_floor(f.id, null) fl
    left join public.npc_fleets nf on nf.fleet_id = f.id
    left join public.npc_houses nh on nh.player_id = f.player_id
    left join public.sea_leg_asks a
           on a.from_port = coalesce(nh.home_port_id, (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1))
          and a.to_port = a.from_port
    left join public.sea_zones z on z.code = a.zones[1]
   where f.id = p_fleet
$body$
  $f$;
  revoke all on function public.npc_sea_floor(uuid) from public, anon, authenticated;
  comment on function public.npc_sea_floor(uuid) is
    '0400: a merchant fleet''s wave resistance and her two floors: what the sea she lies in asks and what her home''s sea asks. Server-only.';

  execute $f$
create function public.npc_sea_shut(p_wave numeric, p_dest uuid, p_course jsonb, p_lie_title integer, p_lie_wave integer, p_home_title integer, p_home_wave integer)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0400: MAY A MERCHANT FLEET SAIL THIS LEG, WITH HER TWO FLOORS (public.npc_sea_floor)? 0397's question (the zones the course crosses and the
  -- destination's own, her title null: the wave alone is judged), asked through public.sea_judge (0396): a sea of the rank of the sea she lies in, or
  -- of her home's sea, asks her hull no more than that sea asked. Nothing is compared here. It does not read the switch: its callers do.
  select public.sea_judge(null, p_wave, public.npc_course_zones(p_course) || array_remove(array[public.harbour_zone(p_dest)], null),
                          p_lie_title, p_lie_wave, p_home_title, p_home_wave)
$body$
  $f$;
  revoke all on function public.npc_sea_shut(numeric, uuid, jsonb, integer, integer, integer, integer) from public, anon, authenticated;
  comment on function public.npc_sea_shut(numeric, uuid, jsonb, integer, integer, integer, integer) is
    '0400: public.npc_sea_shut (0397) asked with a merchant''s two floors through public.sea_judge. Server-only.';

  -- ── 2b. THE COAST LEGS: the table, derived; its reader ──
  create table public.npc_coast_courses (
    from_port uuid not null references public.ports(id),
    to_port   uuid not null references public.ports(id),
    course    jsonb not null,
    nm        numeric not null check (nm > 0),
    primary key (from_port, to_port)
  );
  alter table public.npc_coast_courses enable row level security;
  revoke all on table public.npc_coast_courses from public, anon, authenticated;
  comment on table public.npc_coast_courses is
    '0400: straight courses along her own coast for the harbours where the world remembers no leg that stays in water asking no more than the harbour''s own sea. Derived by 0400; read by public.npc_coast_legs while sea_conditions_bite_npc is on.';
  with hz as materialized (
    select p.id, p.code, z.title_min, z.wave_min, r.roadstead_lat as lat, r.roadstead_lon as lon
      from public.ports p
      join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id
      join public.sea_zones z on z.code = a.zones[1]
      join public.sea_reaches r on r.port_id = p.id
     where p.kind = 'HARBOUR' and not p.is_ice_closed),
  gap as materialized (       -- a harbour with remembered legs, every one of which touches a sea asking more wave than her own sea
    select hh.*
      from hz hh
     where exists (select 1 from public.npc_known_legs(hh.id))
       and not exists (select 1 from public.npc_known_legs(hh.id) l
                        where not exists (select 1 from public.sea_zones z
                                           where z.code = any (public.npc_course_zones(l.course) || array_remove(array[public.harbour_zone(l.to_port)], null))
                                             and z.wave_min > hh.wave_min))),
  cand as (
    select g.id as from_port, b.id as to_port, r.nm as sailed,
           jsonb_build_array(jsonb_build_array(g.lat, g.lon), jsonb_build_array(b.lat, b.lon)) as course,
           row_number() over (partition by g.id order by r.nm, b.code) as k
      from gap g
      join voyage.reach_from(g.id) r on r.nm > 0 and r.nm <= 400
      join hz b on b.id = r.port_id and b.id <> g.id and b.title_min = g.title_min and b.wave_min <= g.wave_min
     where voyage.path_refusal(jsonb_build_array(jsonb_build_array(g.lat, g.lon), jsonb_build_array(b.lat, b.lon)), g.lat, g.lon, b.lat, b.lon, public.wc_num('course_join_nm'), 0, 0) is null
       and not exists (select 1 from public.sea_zones z
                        where z.code = any (public.course_zones(jsonb_build_array(jsonb_build_array(g.lat, g.lon), jsonb_build_array(b.lat, b.lon))))
                          and z.wave_min > g.wave_min))
  insert into public.npc_coast_courses (from_port, to_port, course, nm)
  select c.from_port, c.to_port, c.course, (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(c.course)) x)
    from cand c
   where c.k <= 3
     and (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(c.course)) x) > 0;
  -- their seas are remembered like every merchant course's (0397's memo), both ways; a later refill of the memo forgets them and they are sampled again
  insert into public.npc_course_zones_memo (course_md5, zones)
  select distinct md5(x.course::text), public.course_zones(x.course)
    from (select c.course from public.npc_coast_courses c
          union all
          select jsonb_build_array(c.course -> 1, c.course -> 0) from public.npc_coast_courses c) x
  on conflict (course_md5) do nothing;
  select count(*), count(distinct from_port) into v_coast, v_gap from public.npc_coast_courses;
  select string_agg(b.code, ' ' order by b.code) into v_cap
    from public.npc_coast_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port where a.code = 'CAP';

  execute $f$
create function public.npc_coast_legs(p_port uuid)
returns table (to_port uuid, code text, course jsonb, nm numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0400: THE COAST LEGS out of a harbour (public.npc_coast_courses), both ways (the same line, the same water), less any harbour the world already
  -- remembers a leg to (public.npc_known_legs keeps its own). It does not read the switch: public.npc_feasible_legs does.
  select q.to_port, p.code, q.course, q.nm
    from (select c.to_port, c.course, c.nm from public.npc_coast_courses c where c.from_port = p_port
          union
          select c.from_port, jsonb_build_array(c.course -> 1, c.course -> 0), c.nm from public.npc_coast_courses c
           where c.to_port = p_port and not exists (select 1 from public.npc_coast_courses d where d.from_port = p_port and d.to_port = c.from_port)) q
    join public.ports p on p.id = q.to_port
   where not exists (select 1 from public.npc_known_legs(p_port) k where k.to_port = q.to_port)
$body$
  $f$;
  revoke all on function public.npc_coast_legs(uuid) from public, anon, authenticated;
  comment on function public.npc_coast_legs(uuid) is '0400: the coast legs out of a harbour (public.npc_coast_courses), both ways, less the harbours the world already remembers a leg to. Server-only.';

  -- ── 3. THE FOUR HUNKS: each once on the live body, each reversing to its pre-image ──
  create temp table hunk_0400 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0400 values
      (0, 'public.npc_feasible_legs(uuid,uuid,numeric,integer)',
$h$      from public.npc_known_legs(p_port) l
      join public.ports p on p.id = l.to_port
$h$,
$h$      -- 0400: and, while the switch is on, the coast legs out of this harbour (public.npc_coast_legs): a way along her own coast where the world
      -- remembers only ocean legs. With the switch off they are not read.
      from (select k.to_port, k.code, k.course, k.nm from public.npc_known_legs(p_port) k
            union all
            select c.to_port, c.code, c.course, c.nm from public.npc_coast_legs(p_port) c where (select public.sea_conditions_npc_on())) l
      join public.ports p on p.id = l.to_port
$h$),
      (1, 'public.npc_feasible_legs(uuid,uuid,numeric,integer)',
$h$    from legs l
   where case when (select public.sea_conditions_npc_on())
              then public.npc_sea_shut((select public.fleet_wave(p_fleet)), l.to_port, l.course) is null
              else true end
$h$,
$h$    from legs l
    -- 0400 HOME WATERS: her wave and her two floors (public.npc_sea_floor), read once a call and only while the switch is on: a sea of the rank of
    -- the sea she lies in, or of her home's sea, asks her hull no more than that sea asked (public.sea_judge, as a company is judged since 0396)
    left join lateral (select w.* from public.npc_sea_floor(p_fleet) w where (select public.sea_conditions_npc_on()) offset 0) w on true
   where case when (select public.sea_conditions_npc_on())
              then public.npc_sea_shut(w.wave, l.to_port, l.course, w.lie_title, w.lie_wave, w.home_title, w.home_wave) is null
              else true end
$h$),
      (2, 'public.npc_loop_sea_shut(uuid,jsonb)',
$h$     where public.npc_sea_shut((select public.fleet_wave(p_fleet)), (b.x->>'port_id')::uuid, a.x->'course') is not null)
$h$,
$h$     -- 0400 HOME WATERS: judged with her two floors (public.npc_sea_floor), read once
     cross join (select w.* from public.npc_sea_floor(p_fleet) w offset 0) w
     where public.npc_sea_shut(w.wave, (b.x->>'port_id')::uuid, a.x->'course', w.lie_title, w.lie_wave, w.home_title, w.home_wave) is not null)
$h$),
      (3, 'public.sea_conditions_npc_ready()',
$h$           (select count(*) from jsonb_array_elements(l.legs) x where public.npc_sea_shut(m.wave, (x ->> 'port_id')::uuid, x -> 'course') is null) as open
$h$,
$h$           -- 0400: counted as the planner will judge them, with her two floors (public.npc_sea_floor)
           (select count(*) from jsonb_array_elements(l.legs) x
             where (select public.npc_sea_shut(w.wave, (x ->> 'port_id')::uuid, x -> 'course', w.lie_title, w.lie_wave, w.home_title, w.home_wave)
                      from public.npc_sea_floor(m.fleet_id) w) is null)
           -- and the coast legs out of the harbour her loop starts at, which the planner is offered once the switch is on
           + (select count(*) from public.npc_coast_legs(m.home) c cross join public.npc_sea_floor(m.fleet_id) w
               where public.npc_sea_shut(w.wave, c.to_port, c.course, w.lie_title, w.lie_wave, w.home_title, w.home_wave) is null) as open
$h$);
  for h in select * from hunk_0400 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0400 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0400 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0400 p where p.fn = h.fn) then
      raise exception '0400 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;

  for h in select p.fn, p.def from pre_0400 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0400 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0400 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;

  -- ── 4. THE CATALOG ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0400 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f join pg_proc p on p.oid = f::regprocedure
              where p.provolatile <> 's' or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')) then
    raise exception '0400 self-assert FAIL: a new function is not STABLE and server-only';
  end if;

  if has_table_privilege('authenticated', 'public.npc_coast_courses', 'select') or has_table_privilege('anon', 'public.npc_coast_courses', 'select')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.npc_coast_courses'::regclass) then
    raise exception '0400 self-assert FAIL: public.npc_coast_courses is readable by a client, or has no row security';
  end if;
  if exists (select 1 from public.npc_coast_courses c
              where voyage.path_refusal(c.course, (c.course -> 0 ->> 0)::numeric, (c.course -> 0 ->> 1)::numeric, (c.course -> 1 ->> 0)::numeric, (c.course -> 1 ->> 1)::numeric,
                                        public.wc_num('course_join_nm'), 0, 0) is not null) then
    raise exception '0400 self-assert FAIL: a coast course is not open water';
  end if;

  -- ── 5. LIT: the cost after the cut (the switch turned inside a block that is rolled back) ──
  begin
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  v_t1 := clock_timestamp();
  perform public.npc_feasible_legs(p.home, p.fleet_id, p.speed, 400) from probe_0400 p where p.home is not null order by p.fleet_id limit 20;
  v_ms_after := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 20.0, 1);

  -- ── 6. DARK PARITY: with the switch off the legs offered to the 40 merchants are the same text as before this file ──
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  if (select md5(string_agg(p.fleet_id::text || public.npc_feasible_legs(p.home, p.fleet_id, p.speed, 400)::text, '|' order by p.fleet_id)) from probe_0400 p) is distinct from v_dark then
    raise exception '0400 self-assert FAIL: with sea_conditions_bite_npc off, the legs offered to a merchant moved';
  end if;
  v_r := public.sea_conditions_npc_ready();
  if not (v_r ?& array['lit', 'ready', 'merchants_with_no_open_leg', 'loops_closed', 'closed_at_sea']) then
    raise exception '0400 self-assert FAIL: the merchants'' guard read lost a figure: %', v_r;
  end if;
  raise exception sqlstate 'BV400';
  exception when sqlstate 'BV400' then null;
  end;
  if public.sea_conditions_npc_on() is distinct from v_lit then
    raise exception '0400 self-assert FAIL: the switch was not put back';
  end if;

  -- ── 7. THE JUDGE, on pure figures: a harbour in a sea that asks more wave than a hull of 6 holds ──
  select z.code, z.title_min, z.wave_min into v_z from public.sea_zones z
   where z.wave_min > 6 and exists (select 1 from public.sea_leg_asks a join public.ports p on p.id = a.from_port and p.kind = 'HARBOUR' where a.to_port = a.from_port and a.zones[1] = z.code)
   order by z.wave_min, z.ord limit 1;
  select p.id into v_port from public.ports p join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id where p.kind = 'HARBOUR' and a.zones[1] = v_z.code order by p.code limit 1;
  select z.code, z.title_min, z.wave_min into v_other from public.sea_zones z
   where z.title_min <> v_z.title_min and z.wave_min > 6
     and exists (select 1 from public.sea_leg_asks a join public.ports p on p.id = a.from_port and p.kind = 'HARBOUR' where a.to_port = a.from_port and a.zones[1] = z.code)
   order by z.ord limit 1;
  select p.id into v_port2 from public.ports p join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id where p.kind = 'HARBOUR' and a.zones[1] = v_other.code order by p.code limit 1;
  if v_port is null or v_port2 is null
     or public.npc_sea_shut(6, v_port, null) is null                                                             -- 0397's plain rule refuses her
     or (public.npc_sea_shut(6, v_port, null, null, null, null, null) -> 'figures' ->> 'zone') is distinct from (public.npc_sea_shut(6, v_port, null) -> 'figures' ->> 'zone')   -- no floors: the plain rule's refusal
     or public.npc_sea_shut(6, v_port, null, null, null, v_z.title_min, v_z.wave_min) is not null                -- her home's rank: held
     or public.npc_sea_shut(6, v_port, null, v_z.title_min, v_z.wave_min, null, null) is not null                -- the rank she lies in: held
     or public.npc_sea_shut(6, v_port2, null, null, null, v_z.title_min, v_z.wave_min) is null                   -- a sea of another rank: not held
     or (public.npc_sea_shut(6, v_port2, null, null, null, v_z.title_min, v_z.wave_min) -> 'figures' ->> 'wave')::numeric <> 6 then
    raise exception '0400 self-assert FAIL: the judge with floors: plain %, home rank %, another rank %',
      public.npc_sea_shut(6, v_port, null), public.npc_sea_shut(6, v_port, null, null, null, v_z.title_min, v_z.wave_min),
      public.npc_sea_shut(6, v_port2, null, null, null, v_z.title_min, v_z.wave_min);
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0400 self-assert FAIL: over its budget of 45 s';
  end if;
  raise notice '0400 self-assert ok: A MERCHANT KEEPS HER HOME WATERS. Four hunks, each once and reversing; three new functions and one table (% coast courses out of % harbours; from Cape Coast: %); no other function moved. Dark, the legs offered to 40 merchants are the same text. Lit, a call of npc_feasible_legs: % ms before, % ms after (mean of 20). The guard reads merchants_with_no_open_leg % of % loops closed in this world. A hull of 6 is held by % (asks %) as her home''s or her lying rank, and not by % of another rank. % ms in all.',
    v_coast, v_gap, coalesce(v_cap, 'none'), v_ms_before, v_ms_after, v_r ->> 'merchants_with_no_open_leg', v_r ->> 'loops_closed', v_z.code, v_z.wave_min, v_other.code,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
