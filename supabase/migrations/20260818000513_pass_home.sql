-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing reads it while sea_conditions_bite is false)
-- 0513 - PASS HOME  (dark: the switch is 0215's sea_conditions_bite, false; this file does not move it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (slide 12): "A FLEET can always sail back home, even if it does not meet the requirement."
--   docs/design/owner-spec-plan-2026-11-25.md 0.2; docs/dev-log/2026-11-25-pass-home.md.
-- WHAT IS THERE (0396): the sea a fleet lies in and the seas of its rank are open to her. Measured on the pair table: that does not bring her home from 137 harbours
--   (the way asks more of her hull than the sea she lies in), nor, with short legs, from 64 (the way calls at harbours of other ranks).
-- THE PASS, AND WHY IT IS NOT TWO NUMBERS ON THE FLEET (the plan's shape; decided by default): a stored level and wave open every sea that asks no more, in EVERY
--   direction (a level-1 barca at Acapulco, pass 8 / 70, could sail anywhere); and it is written once, at the light: a fleet whose hull is sold, worn or swapped
--   far away a week later would be trapped. So it is DERIVED, at every judging, from where she lies, and written nowhere:
--     public.sea_passes(player, from)   the harbours she may make for from a harbour whatever the seas between ask of her hull: the ones NEARER HOME
--        (public.sea_reaches' miles; home is her country's capital, and, from the Atlantic's rungs 1 to 4, Lisbon too when the capital lies outside rung 1), when no sea on the way asks a level above her
--        own, above that of the sea she lies in or of her capital's. Where none of those is within her navigation (today Fremantle with the shortest legs: the long
--        way home runs through Java), the ONE harbour within it that is nearest home.
--     Nothing that is not nearer home is opened: she trades where she lies and goes home, no further out. In her own waters nothing changes (they are open).
--   public.sea_home(player), public.sea_lies(fleet)   home's harbour; the harbour she is judged from (hers; under way, the one she is bound for; at a bare point or a
--        sea place, the nearest).
--   public.sea_beyond(player, fleet)   is the direct way home shut to her? The board reads passes only then.
-- PROVEN (proof 217): from every one of the 254 harbours, for each of the capitals, with legs of 1,700, 3,400 and 6,800 nm, a level-1 company whose hull holds NOTHING
--   reaches home on passes alone wherever she could with no seas asked at all; and once home no pass leaves.
-- WHERE IT IS READ (lit only): public.sea_gate (3 hunks: a refusal to a harbour on her pass is none; the one gate, still public.sea_refusal's answer), voyage.reach_passage
--   (4: edges of her passes are open), public.sea_routes (6: a leg on her pass wears no refusal).
-- A job is not cancelled: a leg the gate shuts is a wait or a stop with the wall's words, as any refused leg (0494). "What a company can reach today stays hers" is 0510's.
-- ROWS: none. No table, no column, no index, no cron, no knob. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Tick: 0 (no beat reads a player's sea). Lit: a REFUSED leg reads sea_passes once (a few ms); a board
--   of a fleet beyond her rung reads the whole set once (proof 217 measures both); a fleet whose way home is open reads neither.
-- LOCKS: CREATE FUNCTION x5; CREATE OR REPLACE x3 by hunks. TIME: about a second. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, sea_conditions_bite false. FULL: the thirteen hunks reversed, the five functions dropped.
-- SELF-ASSERT: each hunk once and reversing; no other function or knob moved; server only; THE PROBE (rolled back; its own level-1 barca of Portugal, lit inside the
--   probe, placed at Acapulco): the capital and only harbours nearer home are on her pass, Lisbon is open at the gate, Manila is shut, and at Lisbon the pass is empty.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.sea_gate(uuid,uuid,uuid,jsonb)', 'voyage.reach_passage(uuid,uuid,uuid,numeric)', 'public.sea_routes(uuid,integer,numeric,jsonb)']::text[];
  c_new    constant text[] := array['public.sea_home(uuid)', 'public.sea_lies(uuid)', 'public.sea_passes(uuid,uuid)', 'public.sea_beyond(uuid,uuid,text[])', 'public.sea_passes_lit(uuid,uuid)']::text[];
  c_gone   constant text[] := array[]::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me   uuid;
  v_fl   uuid;
  v_lis  uuid;
  v_aca  uuid;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0513 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0513 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;


  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  execute $f$
create function public.sea_home(p_player uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0513: HOME, as a harbour's code: the capital of the country she sails for (what public.sea_floor calls home), else Lisbon.
  select coalesce((select cap.code from public.players pl join public.nations n on n.id = pl.nation_id
                     join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR' where pl.id = p_player), 'LIS')
$body$
  $f$;
  revoke all on function public.sea_home(uuid) from public, anon, authenticated, service_role;
  comment on function public.sea_home(uuid) is
    '0513: the harbour a company''s way home leads to. Server only.';
  execute $f$
create function public.sea_lies(p_fleet uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0513: THE HARBOUR SHE IS JUDGED FROM: the one she lies at; under way, the one she is bound for; at a sea place or a bare point of water, the nearest one (a point
  -- she is bound for, when under way to one).
  select case when hp.id is not null then hp.id
              else public.harbour_nearest(coalesce(f.lat, op.lat, (v.path->(jsonb_array_length(v.path)-1)->'b'->>0)::numeric)::float8,
                                          coalesce(f.lon, op.lon, (v.path->(jsonb_array_length(v.path)-1)->'b'->>1)::numeric)::float8) end
    from public.fleets f
    left join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING' and f.status = 'SAILING'
    left join public.ports hp on hp.id = coalesce(f.port_id, v.dest_port_id) and hp.kind = 'HARBOUR'
    left join public.ports op on op.id = coalesce(f.port_id, v.dest_port_id)
   where f.id = p_fleet
$body$
  $f$;
  revoke all on function public.sea_lies(uuid) from public, anon, authenticated, service_role;
  comment on function public.sea_lies(uuid) is
    '0513: the harbour a fleet''s pass home is read from. Server only.';
  execute $f$
create function public.sea_passes(p_player uuid, p_from uuid default null)
returns table (from_port uuid, to_port uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0513: HER PASS HOME, from one harbour (p_from) or from every one (null): the harbours she may make for whatever the seas between ask of her HULL. See 0513's head.
  --   nearer   to home (or, out of a harbour of the first four rungs, to Lisbon, when her capital's sea is not of the first), in public.sea_reach_matrix' miles (0482: the sailed miles)
  --   level    no sea of the way (public.sea_leg_asks' title_min) asks above her own level, the sea she lies in's, or her capital's sea's
  --   none of those within her navigation (public.passage_reach_nm), and she is not home: the one harbour within it nearest home
  -- A merchant, nobody, a harbour the matrix does not hold: none.
  with me as materialized (
    select public.title_level(p_player) as title, public.passage_reach_nm(p_player)::float8 as reach, public.sea_home(p_player) as cap
     where exists (select 1 from public.players pl where pl.id = p_player and not pl.is_npc)),
  m as materialized (
    select x.ids, x.nm, cardinality(x.ids) as n, array_position(x.codes, me.cap) as t1,
           case when z.title_min > 1 then array_position(x.codes, 'LIS') end as t2, array_position(x.ids, p_from) as f,
           greatest(me.title, z.title_min) as title, me.reach
      from public.sea_reach_matrix x cross join me
      join public.ports cap on cap.code = me.cap
      join public.sea_leg_asks o on o.from_port = cap.id and o.to_port = cap.id
      join public.sea_zones z on z.code = o.zones[1]
     where x.id = 1),
  -- home's row (and Lisbon's) and the row of p_from, or all of them: the matrix is read once each, never by its cells one at a time
  h as materialized (
    select u.i::int as i, u.id, z.title_min, u.i = m.t1 as home, coalesce(u.h1, 0) as h1, case when m.t2 is not null then coalesce(u.h2, 0) end as h2
      from m cross join lateral unnest(m.ids, m.nm[(m.t1 - 1) * m.n + 1 : m.t1 * m.n], m.nm[(m.t2 - 1) * m.n + 1 : m.t2 * m.n]) with ordinality u(id, h1, h2, i)
      join public.sea_leg_asks o on o.from_port = u.id and o.to_port = u.id
      join public.sea_zones z on z.code = o.zones[1]),
  d as materialized (
    select case when m.f is not null then m.f else ((u.o - 1) / m.n + 1)::int end as i, ((u.o - 1) % m.n + 1)::int as j, u.v as nm
      from m cross join lateral unnest(case when p_from is null then m.nm else m.nm[(m.f - 1) * m.n + 1 : m.f * m.n] end) with ordinality u(v, o)
     where p_from is null or m.f is not null),
  leg as materialized (
    select a.id as from_port, b.id as to_port, a.home, least(b.h1, b.h2) as b_home, d.nm <= m.reach as within,
           not a.home and (b.h1 < a.h1 or coalesce(a.title_min <= 4 and b.h2 < a.h2, false)) and s.title_min <= greatest(m.title, a.title_min) as way
      from d cross join m
      join h a on a.i = d.i join h b on b.i = d.j and b.i <> a.i
      join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id),
  shut as materialized (select l.from_port from leg l where not l.home group by l.from_port having not bool_or(l.way and l.within))
  select l.from_port, l.to_port from leg l where l.way
  union
  (select distinct on (l.from_port) l.from_port, l.to_port
     from leg l join shut s on s.from_port = l.from_port join public.ports p on p.id = l.to_port
    where l.within order by l.from_port, l.b_home, p.code)
$body$
  $f$;
  revoke all on function public.sea_passes(uuid, uuid) from public, anon, authenticated, service_role;
  comment on function public.sea_passes(uuid, uuid) is
    '0513: the pass home: from a harbour (or every one, null), the harbours a company may make for whatever the seas ask of her hull. Derived, stored nowhere. Server only.';
  execute $f$
create function public.sea_beyond(p_player uuid, p_fleet uuid, p_closed text[] default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0513: IS THE WAY HOME SHUT TO HER? The seas of the course from where she lies to her home (public.sea_leg_asks), against the seas shut to her (public.sea_closed; p_closed when the
  -- caller has read them).
  select coalesce((select a.zones && coalesce(p_closed, public.sea_closed(p_player, p_fleet))
                     from public.sea_leg_asks a join public.ports h on h.id = a.to_port and h.code = public.sea_home(p_player)
                    where a.from_port = public.sea_lies(p_fleet)), false)
$body$
  $f$;
  revoke all on function public.sea_beyond(uuid, uuid, text[]) from public, anon, authenticated, service_role;
  comment on function public.sea_beyond(uuid, uuid, text[]) is
    '0513: whether the direct way home is shut to this fleet. Server only.';
  execute $f$
create function public.sea_passes_lit(p_player uuid, p_fleet uuid)
returns table (from_port uuid, to_port uuid)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0513: WHAT A BOARD READS: every harbour's passes, only while the seas bite and only for a fleet whose way home is shut to her; else no row and no work.
begin
  if p_player is null or p_fleet is null or not public.sea_conditions_on() or not public.sea_beyond(p_player, p_fleet) then
    return;
  end if;
  return query select x.from_port, x.to_port from public.sea_passes(p_player, null) x;
end
$body$
  $f$;
  revoke all on function public.sea_passes_lit(uuid, uuid) from public, anon, authenticated, service_role;
  comment on function public.sea_passes_lit(uuid, uuid) is
    '0513: every pass of a fleet beyond her rung, lit only. Server only.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0513 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0513 values
  ('public.sea_gate(uuid,uuid,uuid,jsonb)', 1,
$h$  v_hz    text;
$h$,
$h$  v_hz    text;
  v_shut  jsonb;   -- 0513
$h$),
  ('public.sea_gate(uuid,uuid,uuid,jsonb)', 2,
$h$  return (select public.sea_judge(public.title_level(p_player)$h$,
$h$  v_shut := (select public.sea_judge(public.title_level(p_player)$h$),
  ('public.sea_gate(uuid,uuid,uuid,jsonb)', 3,
$h$            from public.sea_floor(p_fleet, p_course) fl);
$h$,
$h$            from public.sea_floor(p_fleet, p_course) fl);
  -- 0513 PASS HOME: refused, but the harbour she makes for is on her way home from where she lies (or is the one she lies off): let through
  if v_shut is not null and p_fleet is not null and p_dest is not null
     and (exists (select 1 from public.sea_passes(p_player, public.sea_lies(p_fleet)) x where x.to_port = p_dest)
          or exists (select 1 from public.fleets f where f.id = p_fleet and f.port_id is distinct from p_dest and f.status <> 'SAILING' and public.sea_lies(p_fleet) = p_dest)) then
    return null;
  end if;
  return v_shut;
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 1,
$h$    select array_agg(coalesce(not s.zones && v_closed, true) order by a.i, b.j)
$h$,
$h$    v_beyond := public.sea_beyond(p_player, p_fleet, v_closed);   -- 0513
    select array_agg(coalesce(not s.zones && v_closed, true) or x.to_port is not null order by a.i, b.j)   -- 0513: or on her pass home
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 2,
$h$      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id;   -- 0510: edges
$h$,
$h$      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id   -- 0510: edges
      left join (select p.* from public.sea_passes(p_player, null) p where v_beyond) x on x.from_port = a.id and x.to_port = b.id;   -- 0513: empty unless her way home is shut to her
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 3,
$h$  v_closed text[];   -- 0510: lit, the seas shut to her (public.sea_closed)
$h$,
$h$  v_closed text[];   -- 0510: lit, the seas shut to her (public.sea_closed)
  v_beyond boolean;  -- 0513: lit, her way home is shut to her (public.sea_beyond)
$h$),
  ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 4,
$h$    select array_agg(a.id = p_from or coalesce(not s.zones && v_closed, true) order by a.i)
$h$,
$h$    select array_agg(a.id = p_from or coalesce(not s.zones && v_closed, true) or v_beyond order by a.i)   -- 0513: then the edges alone say
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 1,
$h$           case when public.sea_conditions_on() then s.zones || hb.zone
$h$,
$h$           exists (select 1 from pass x where x.from_port = ha.id and x.to_port = hb.id) as pass,   -- 0513: on her way home
           case when public.sea_conditions_on() then s.zones || hb.zone
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 2,
$h$  leg as materialized (
$h$,
$h$  -- 0513: her pass home, lit and beyond her rung only (one row set a call)
  pass as materialized (select x.from_port, x.to_port from public.sea_passes_lit((select f.player_id from public.fleets f where f.id = p_fleet), p_fleet) x),
  leg as materialized (
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 3,
$h$    select l.i, z.zone from leg l cross join lateral unnest(l.zones) z(zone) where z.zone is not null),
$h$,
$h$    select l.i, z.zone, l.pass from leg l cross join lateral unnest(l.zones) z(zone) where z.zone is not null),
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 4,
$h$    select q.i, q.needs_title, q.needs_wave, zs.zones
$h$,
$h$    select q.i, q.needs_title, q.needs_wave, zs.zones, zs.asked   -- 0513: asked = the seas of her legs that are on no pass
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 5,
$h$      left join (select o.i, array_agg(distinct o.zone order by o.zone) as zones from zone_of o group by o.i) zs on zs.i = q.i),
$h$,
$h$      left join (select o.i, array_agg(distinct o.zone order by o.zone) as zones, array_agg(distinct o.zone) filter (where not o.pass) as asked from zone_of o group by o.i) zs on zs.i = q.i),
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 6,
$h$from seen s where s.zone = any (r.zones) and s.refusal$h$,
$h$from seen s where s.zone = any (r.asked) and s.refusal$h$);

  for v_h in select h.fn from hunks_0513 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0513 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0513 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0513 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0513 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0513 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0513 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0513 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when false then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0513 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array[]::text[])) <> v_cfg_before then
    raise exception '0513 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. THE PROBE (its own company; rolled back) ──
  begin
    v_me := public.new_house('00000000-0513-4000-8000-000000000001', 'Casa do Regresso 0513', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    v_aca := (select p.id from public.ports p where p.code = 'ACA');
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    if exists (select 1 from public.sea_passes(v_me, (select p.id from public.ports p where p.code = public.sea_home(v_me)))) then
      raise exception '0513 self-assert FAIL: at home the pass is not empty';
    end if;
    update public.fleets set port_id = v_aca where id = v_fl;
    if public.sea_lies(v_fl) is distinct from v_aca or public.sea_gate(v_me, v_fl, v_lis, public.sea_course(v_aca, v_lis)) is not null
       or public.sea_gate(v_me, v_fl, (select p.id from public.ports p where p.code = 'MNL'), null) is null
       or exists (select 1 from public.sea_passes(v_me, v_aca) ps join public.ports p on p.id = ps.to_port
                   where (select (sr.reaches ->> p.code)::numeric from public.sea_reaches sr where sr.code = public.sea_home(v_me) and p.code <> public.sea_home(v_me))
                         >= (select (sr.reaches ->> 'ACA')::numeric from public.sea_reaches sr where sr.code = public.sea_home(v_me))) then
      raise exception '0513 self-assert FAIL: a level-1 barca at Acapulco: home %, Manila %', public.sea_gate(v_me, v_fl, v_lis, null),
        public.sea_gate(v_me, v_fl, (select p.id from public.ports p where p.code = 'MNL'), null);
    end if;
    v_note := format('from Acapulco %s harbours on the pass, home among them, Manila shut', (select count(*) from public.sea_passes(v_me, v_aca)));
    raise exception using errcode = 'ZX513', message = 'PROBE_ROLLBACK_0513';
  exception when sqlstate 'ZX513' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.company_name = 'Casa do Regresso 0513') then
    raise exception '0513 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0513 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0513 self-assert ok: PASS HOME (dark: the switch not moved). Every hunk once and reversing; no other function or knob moved; five new functions server only. Probe (rolled back): %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
