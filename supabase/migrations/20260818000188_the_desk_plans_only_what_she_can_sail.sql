-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0188 — THE DESK PLANS ONLY WHAT SHE CAN SAIL  (plan reach, slice 2)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"that leg is 14015 nm and your navigation carries you 1700 nm — study navigation, what
-- is this?"*. The plan builder queued `SAIL MTY` for a NAVIGATION-0 captain: neither world.good_board, the plan
-- builder nor cmd.issue_lines asked public.passage_gate (0107, owner row 113: a leg longer than
-- nav_leg_nm_base × 2^(NAVIGATION − 1) is refused) until the line ran. 0186 stopped the refusal freezing the
-- queue; this file stops the desk planning it, and gives the far market the passage she CAN sail — through
-- harbours within her reach, at the cost of the stops. That is what distance pricing is for: long-haul trade
-- for a captain without top Navigation.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- 1. THE REACH, ONE FORMULA. public.passage_reach_at(level) = nav_leg_nm_base × 2^max(0, level − 1);
--    passage_gate reads it (one hunk, the same arithmetic), and so do:
--      public.passage_reach_nm(player)  — her reach in nm; null for a merchant or nobody (passage_gate's exemption);
--      public.passage_reach(player)     — {navigation, reach_nm} for the desk;
--      public.passage_needs(player, nm) — null when the leg is within reach, else the Navigation it needs
--                                         ({navigation, reach_nm}; navigation null past skill_max_level).
-- 2. voyage.reach_passage(player, from) — NEW. The shortest passage to every harbour with EVERY LEG within her
--    reach: Dijkstra over public.sea_reaches (the one pathfinder's sailed miles, voyage.reach_from's source),
--    where a leg is open when it is ≤ her reach and the harbour it ends at is open to her (passage_gate's region
--    check, asked of passage_gate itself). Returns per harbour: the passage's miles (null if no chain of legs
--    reaches it), the direct miles, and the stops between (each a harbour, where she can PROVISION). A merchant
--    (no reach) gets the direct figures.
-- 3. world.good_board — the figures use the passage she can sail. Its two `reach` CTEs (and the buy city's
--    `reach2`) read voyage.reach_passage instead of voyage.reach_from, so miles, days, arrival, wages and net —
--    and the ranking by net — are the reachable passage's; the dearest REACHABLE cities are the ones priced in full. Every row carries `stops` (the harbours between) and
--    `needs` (the Navigation a DIRECT leg would need, or null), `sailable` (every leg within her reach AND within
--    her stores — voyage.endurance_days against the leg's days × endurance_margin, sail_refusal's own rule; she can
--    PROVISION at every stop, and her present stores are the floor) and `longest_leg` {miles, days}. The board carries
--    `reach` {navigation, reach_nm} and `supplies` {days, margin}. At her own anchor (0183: the nearest harbour is the
--    origin) that harbour is every passage's first stop, and the lead counts as a leg.
-- 4. cmd.issue_lines — every SAIL line is asked of public.passage_gate at PLAN time, from where the line before it
--    leaves her (its course measured exactly as cmd.do_sail measures it; else the sailed miles between the two
--    harbours). A leg she cannot sail refuses the whole plan up front, naming the line.
--
-- ── THE PROOF (own probe company at Lisbon, NAVIGATION 0, rolled back) ──────────────────────────
-- (a) a plan whose first SAIL is beyond her reach is refused up front, line 1, E_LEG_TOO_FAR, nothing queued;
--     (b) a far SAIL as line 2 names line 2; (c) reach_passage reaches a harbour beyond her reach through stops,
--     every leg ≤ her reach and the legs summing to the passage; (d) good_board: the board's reach is 1,700 nm,
--     a far sell city's row carries stops and `needs`, its miles are the passage's; (e) the multi-leg plan
--     built from those stops is accepted; (f) a merchant is exempt; passage_gate reverses to its pre-image;
--     the walls hold.
-- ROLLBACK: reverse the hunks (asserted), drop the five functions.
-- VERSION: 0188 PROVISIONAL — on top of 0186 (plan reach slice 1, live); 0187 is the great powers (#229). Prod head 0186 when renumbered. Pre-images read live.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0188(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0188 on commit drop as
select f.sig, replace(pg_get_functiondef(f.sig::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = f.sig::regprocedure) as acl
  from (values ('public.passage_gate(uuid, numeric, uuid)'),
               ('world.good_board(uuid, uuid, uuid, numeric)'),
               ('cmd.issue_lines(uuid, jsonb, integer)')) f(sig);

create temp table clock_0188 on commit drop as select clock_timestamp() as t0;

do $$
begin
  if to_regprocedure('voyage.reach_passage(uuid, uuid)') is not null
     or to_regprocedure('public.passage_reach_at(integer)') is not null then
    raise exception '0188 self-assert FAIL: the reach functions already exist';
  end if;
end $$;

-- ── 1. THE REACH, ONE FORMULA ─────────────────────────────────────────────────────────────────
create or replace function public.passage_reach_at(p_level int)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0188: owner row 113 — a captain of NAVIGATION n sails a leg of nav_leg_nm_base × 2^(n − 1) (level 0 as 1).
  select public.wc_num('nav_leg_nm_base') * power(2::numeric, greatest(0, coalesce(p_level, 0) - 1))
$$;

create or replace function public.passage_reach_nm(p_player uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0188: her reach in nm; null for nobody and for a merchant — passage_gate's own exemption.
  select case when p_player is null or exists (select 1 from public.players p where p.id = p_player and p.is_npc) then null
              else public.passage_reach_at(public.skill_level(p_player, 'NAVIGATION')) end
$$;

create or replace function public.passage_reach(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when public.passage_reach_nm(p_player) is null then null
              else jsonb_build_object('navigation', public.skill_level(p_player, 'NAVIGATION'),
                                      'reach_nm', round(public.passage_reach_nm(p_player))) end
$$;

create or replace function public.passage_needs(p_player uuid, p_nm numeric)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0188: null when a leg of p_nm is within her reach (or she is exempt); else the least Navigation that sails it,
  -- with that level's reach — navigation null when no level up to skill_max_level does.
  select case when p_nm is null or public.passage_reach_nm(p_player) is null or p_nm <= public.passage_reach_nm(p_player) then null
              else coalesce(
                (select jsonb_build_object('navigation', l, 'reach_nm', round(public.passage_reach_at(l)))
                   from generate_series(greatest(1, public.skill_level(p_player, 'NAVIGATION') + 1), public.wc_int('skill_max_level')) l
                  where public.passage_reach_at(l) >= p_nm order by l limit 1),
                jsonb_build_object('navigation', null, 'reach_nm', round(public.passage_reach_at(public.wc_int('skill_max_level')))))
         end
$$;

-- ── 2. THE PASSAGE SHE CAN SAIL ───────────────────────────────────────────────────────────────
create or replace function voyage.reach_passage(p_player uuid, p_from uuid)
returns table (port_id uuid, code text, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0188: THE SHORTEST PASSAGE TO EVERY HARBOUR WITH EVERY LEG WITHIN HER REACH (owner row 113; 2026-10-18).
-- The miles are public.sea_reaches' — the one pathfinder's, the figures voyage.reach_from serves — and a leg is
-- open when it is no longer than public.passage_reach_nm and the harbour it ends at is open to her
-- (public.passage_gate's region check, asked of passage_gate). Dijkstra, O(n²) over the harbours, float8 arrays
-- (fixed width: O(1) subscripts). `stops` are the harbours between, in order; null when none reaches it.
declare
  v_reach float8 := public.passage_reach_nm(p_player)::float8;
  v_ids   uuid[];
  v_codes text[];
  v_open  boolean[];
  v_n     int;
  v_s     int;
  d       float8[];
  dist    float8[];
  hops    int[];
  maxl    float8[];
  prev    int[];
  done    boolean[];
  u       int;
  best    float8;
  w       float8;
  nd      float8;
  k       int;
  v_path  text[];
begin
  if p_from is null then
    return;
  end if;
  if v_reach is null then
    -- exempt (a merchant, or nobody): every leg is open — the direct figures
    return query
      select r.port_id, r.code, r.nm, r.nm, '{}'::text[], r.nm
        from voyage.reach_from(p_from) r join public.ports p on p.id = r.port_id
       where p.kind = 'HARBOUR';
    return;
  end if;

  select array_agg(p.id order by p.code), array_agg(p.code order by p.code),
         array_agg(p.id = p_from or public.passage_gate(p_player, null, p.id) is null order by p.code)
    into v_ids, v_codes, v_open
    from public.ports p
   where p.kind = 'HARBOUR' or p.id = p_from;
  v_n := coalesce(array_length(v_ids, 1), 0);
  v_s := array_position(v_ids, p_from);
  if v_s is null then
    return;
  end if;

  -- the sailed miles, row-major: d[(i − 1) × n + j] = i → j (null on the diagonal)
  select array_agg((sr.reaches->>b.c)::float8 order by a.i, b.i) into d
    from unnest(v_ids) with ordinality a(id, i)
    join public.sea_reaches sr on sr.port_id = a.id
   cross join unnest(v_codes) with ordinality b(c, i);
  if coalesce(array_length(d, 1), 0) <> v_n * v_n then
    raise exception 'voyage.reach_passage: % harbours but % sailed distances — a harbour has no sea_reaches row', v_n, coalesce(array_length(d, 1), 0);
  end if;

  dist := array_fill(null::float8, array[v_n]);
  hops := array_fill(0, array[v_n]);
  maxl := array_fill(0::float8, array[v_n]);
  prev := array_fill(0, array[v_n]);
  done := array_fill(false, array[v_n]);
  dist[v_s] := 0;
  loop
    u := 0;
    best := null;
    for i in 1 .. v_n loop
      if not done[i] and dist[i] is not null and (best is null or dist[i] < best) then
        u := i;
        best := dist[i];
      end if;
    end loop;
    exit when u = 0;
    done[u] := true;
    for j in 1 .. v_n loop
      if not done[j] and v_open[j] then
        w := d[(u - 1) * v_n + j];
        if w is not null and w <= v_reach then
          nd := best + w;
          if dist[j] is null or nd < dist[j] or (nd = dist[j] and hops[u] + 1 < hops[j]) then
            dist[j] := nd;
            hops[j] := hops[u] + 1;
            maxl[j] := greatest(maxl[u], w);
            prev[j] := u;
          end if;
        end if;
      end if;
    end loop;
  end loop;

  for j in 1 .. v_n loop
    continue when j = v_s;
    v_path := null;
    if dist[j] is not null then
      v_path := '{}';
      k := prev[j];
      while k <> v_s and k <> 0 loop
        v_path := v_codes[k] || v_path;
        k := prev[k];
      end loop;
    end if;
    port_id   := v_ids[j];
    code      := v_codes[j];
    nm        := round(dist[j]::numeric, 1);
    direct_nm := round(d[(v_s - 1) * v_n + j]::numeric, 1);
    stops     := v_path;
    max_leg_nm := case when dist[j] is null then null else round(maxl[j]::numeric, 1) end;
    return next;
  end loop;
end $$;

revoke all on function public.passage_reach_at(int) from public, anon, authenticated;
revoke all on function public.passage_reach_nm(uuid) from public, anon, authenticated;
revoke all on function public.passage_reach(uuid) from public, anon, authenticated;
revoke all on function public.passage_needs(uuid, numeric) from public, anon, authenticated;
revoke all on function voyage.reach_passage(uuid, uuid) from public, anon, authenticated;

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each reverses; ACLs unchanged) ─
create temp table hunks_0188 (sig text, ord int, old_t text, new_t text) on commit drop;
insert into hunks_0188 values
-- passage_gate: the one formula
('public.passage_gate(uuid, numeric, uuid)', 1,
$p1$    v_reach := public.wc_num('nav_leg_nm_base') * power(2::numeric, greatest(0, v_nav - 1));
$p1$,
$p1$    v_reach := public.passage_reach_at(v_nav);   -- 0188: the one formula (the desk's reach reads it too)
$p1$),
-- good_board: declarations
('world.good_board(uuid, uuid, uuid, numeric)', 1,
$g1$  v_where   jsonb;
begin
$g1$,
$g1$  v_where   jsonb;
  v_lead_stops  text[] := '{}';     -- 0188: at her own anchor, the harbour her passages run from is their first stop
  v_end     numeric;                -- 0188: the days her stores carry her now (voyage.endurance_days)
  v_margin  numeric;                -- 0188: endurance_margin, as voyage.sail_refusal applies it
begin
$g1$),
('world.good_board(uuid, uuid, uuid, numeric)', 2,
$g2$  v_wage  := public.fleet_wage(p_fleet, false);
$g2$,
$g2$  v_wage  := public.fleet_wage(p_fleet, false);
  v_end    := voyage.endurance_days(p_fleet);       -- 0188: a leg is sailable when her casks cover it (sail_refusal's rule)
  v_margin := public.wc_num('endurance_margin');
$g2$),
-- good_board: at her own anchor (0183's nearest harbour) the first stop is that harbour
('world.good_board(uuid, uuid, uuid, numeric)', 3,
$g3$      v_where := jsonb_build_object('kind', 'at_sea', 'port', null,
                                    'via', (select code from public.ports where id = v_origin),
$g3$,
$g3$      -- 0188: she sails to that harbour first: it is every passage's first stop, and the lead is a leg her casks must cover
      v_lead_stops := case when v_origin is not null then array[(select code from public.ports where id = v_origin)] else '{}' end;
      v_where := jsonb_build_object('kind', 'at_sea', 'port', null,
                                    'via', (select code from public.ports where id = v_origin),
$g3$),
-- good_board: BUY AT reads the passage she can sail
('world.good_board(uuid, uuid, uuid, numeric)', 4,
$g4$  with reach as materialized (
    select r.port_id, r.nm from voyage.reach_from(v_origin) r
    union all select v_origin, 0 where v_origin is not null
  ), sellers as materialized (
$g4$,
$g4$  with reach as materialized (
    -- 0188: THE PASSAGE HER CAPTAIN CAN SAIL — every leg within her navigation's reach, through harbours
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from voyage.reach_passage(v_player, v_origin) r
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end
     where v_origin is not null
  ), sellers as materialized (
$g4$),
('world.good_board(uuid, uuid, uuid, numeric)', 5,
$g5$           'port', s.code, 'name', s.name, 'here', s.id = f.port_id,
$g5$,
$g5$           'port', s.code, 'name', s.name, 'here', s.id = f.port_id,
           -- 0188: the passage she can sail — its stops, the Navigation a direct leg would need, whether her
           -- captain's reach AND her stores carry every leg (she provisions at each stop), and its longest leg
           'stops', (select to_jsonb(x.stops) from reach x where x.port_id = s.id),
           'needs', (select public.passage_needs(v_player, x.direct_nm) from reach x where x.port_id = s.id),
           'sailable', coalesce((select x.nm is not null and v_speed > 0 and x.max_leg / v_speed / 24 * v_margin <= v_end
                                   from reach x where x.port_id = s.id), false),
           'longest_leg', (select jsonb_build_object('miles', round(x.max_leg), 'days', round(x.max_leg / v_speed / 24, 2))
                             from reach x where x.port_id = s.id and x.max_leg is not null and v_speed > 0),
$g5$),
-- good_board: SELL AT reads the passage she can sail, from where she is or from the buy city
('world.good_board(uuid, uuid, uuid, numeric)', 6,
$g6$  ), reach as materialized (
    select r.port_id, r.nm from voyage.reach_from(v_origin) r
    union all select v_origin, 0 where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm from src cross join lateral voyage.reach_from(src.id) r
    union all select id, 0 from src
  ), cand as materialized (
$g6$,
$g6$  ), reach as materialized (
    -- 0188: the passage she can sail (voyage.reach_passage), as BUY AT reads it
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from voyage.reach_passage(v_player, v_origin) r
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end
     where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm, r.direct_nm, r.stops, r.max_leg_nm as max_leg
      from src cross join lateral voyage.reach_passage(v_player, src.id) r
    union all select id, 0, 0, '{}'::text[], 0 from src
  ), cand as materialized (
$g6$),
('world.good_board(uuid, uuid, uuid, numeric)', 7,
$g7$                else (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) + r2.nm end as nm
$g7$,
$g7$                else (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) + r2.nm end as nm,
           -- 0188: the stops between where she sails this leg from and the sell city, its direct miles, and the
           -- longest leg of the whole passage (to the buy city first, when it must be bought first)
           case when v_basis = 'on_board' then rc.stops else r2.stops end as stops,
           case when v_basis = 'on_board' then rc.direct_nm else r2.direct_nm end as direct_nm,
           case when v_basis = 'on_board' then rc.max_leg
                else greatest((select rc1.max_leg from reach rc1 where rc1.port_id = (select id from src)), r2.max_leg) end as max_leg
$g7$),
('world.good_board(uuid, uuid, uuid, numeric)', 8,
$g8$           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
$g8$,
$g8$           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
           'stops', to_jsonb(r.stops), 'needs', public.passage_needs(v_player, r.direct_nm),   -- 0188
           'sailable', coalesce(r.nm is not null and r.max_leg is not null and v_speed > 0
                                and r.max_leg / v_speed / 24 * v_margin <= v_end, false),
           'longest_leg', case when r.max_leg is not null and v_speed > 0
                               then jsonb_build_object('miles', round(r.max_leg), 'days', round(r.max_leg / v_speed / 24, 2)) end,
$g8$),
('world.good_board(uuid, uuid, uuid, numeric)', 10,
$g10$    select c.*, row_number() over (order by c.mid desc, c.nm nulls last, c.code) as rk from cand c
$g10$,
$g10$    -- 0188: the dearest cities she can REACH are priced first; one no passage within her reach gets to ranks last
    select c.*, row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk from cand c
$g10$),
('world.good_board(uuid, uuid, uuid, numeric)', 9,
$g9$    'quoted', v_quoted,
$g9$,
$g9$    'quoted', v_quoted,
    'reach', public.passage_reach(v_player),   -- 0188: {navigation, reach_nm}
    'supplies', jsonb_build_object('days', round(v_end, 1), 'margin', v_margin),   -- 0188: what `sailable` read
$g9$),
-- issue_lines: declarations
('cmd.issue_lines(uuid, jsonb, integer)', 1,
$i1$  v_fail   jsonb;
begin
$i1$,
$i1$  v_fail   jsonb;
  v_at     uuid;    -- 0188: where the line before leaves her
  v_dest   uuid;
  v_nm     numeric;
  v_gate   jsonb;
  v_lpath  jsonb;
begin
$i1$),
-- issue_lines: the captain's reach at plan time
('cmd.issue_lines(uuid, jsonb, integer)', 2,
$i2$    v_parsed := v_parsed || v_p;
  end loop;
$i2$,
$i2$    v_parsed := v_parsed || v_p;
  end loop;

  -- 0188: THE CAPTAIN'S REACH, AT PLAN TIME (the owner, 2026-10-18: "your navigation carries you 1700 nm"). Every
  -- SAIL is asked of public.passage_gate — the authority cmd.do_sail asks when the line runs — from where the line
  -- before it leaves her: its course measured as do_sail measures it (voyage.segments_from_course), else the
  -- sailed miles between the two harbours (voyage.reach_from). A leg she cannot sail refuses the plan, named.
  v_at := coalesce((select fl.port_id from public.fleets fl where fl.id = p_fleet),
                   (select vo.dest_port_id from public.voyages vo
                     where vo.fleet_id = p_fleet and vo.status = 'SAILING' order by vo.departed_at desc limit 1));
  for i in 1 .. v_n loop
    continue when v_parsed[i]->>'verb' is distinct from 'SAIL';
    v_dest  := nullif(v_parsed[i]->'args'->>'dest', '')::uuid;
    v_lpath := p_lines->(i - 1)->'path';
    v_nm    := null;
    if jsonb_typeof(v_lpath) = 'array' then
      begin
        select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_lpath)) s;
      exception when others then
        v_nm := null;   -- a course the server cannot read is refused when the line runs, as before
      end;
    elsif v_at is not null and v_dest is not null then
      select r.nm into v_nm from voyage.reach_from(v_at) r where r.port_id = v_dest;
    end if;
    v_gate := public.passage_gate(v_player, v_nm, v_dest);
    if v_gate is not null then
      return jsonb_build_object('ok', false, 'error_code', v_gate->>'code', 'line', i,
        'error_message', format('Line %s (%s): %s', i, btrim(coalesce(p_lines->(i - 1)->>'text', '')), v_gate->>'sentence'),
        'figures', v_gate->'figures', 'fixes', cmd.fixes(v_gate->>'code', p_fleet), 'queue', cmd.queue(p_fleet));
    end if;
    v_at := v_dest;
  end loop;
$i2$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for b in select * from before_0188 loop
    v_def := b.def;
    for h in select * from hunks_0188 where sig = b.sig order by ord loop
      if pg_temp.occurs_0188(b.def, h.old_t) <> 1 then
        raise exception '0188 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.ord, b.sig, pg_temp.occurs_0188(b.def, h.old_t);
      end if;
      v_def := replace(v_def, h.old_t, h.new_t);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(b.sig::regprocedure), E'\r', '');
    for h in select * from hunks_0188 where sig = b.sig order by ord desc loop
      if pg_temp.occurs_0188(v_rev, h.new_t) <> 1 then
        raise exception '0188 self-assert FAIL: hunk % of % is not in the new body once', h.ord, b.sig;
      end if;
      v_rev := replace(v_rev, h.new_t, h.old_t);
    end loop;
    if v_rev <> b.def then
      raise exception '0188 self-assert FAIL: % does not reverse to its pre-image', b.sig;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = b.sig::regprocedure), '') <> b.acl then
      raise exception '0188 self-assert FAIL: the ACL of % moved', b.sig;
    end if;
  end loop;
end $$;

-- ── 4. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0188-4000-8000-000000000001';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_t    timestamptz := clock_timestamp();
  v_tp   numeric;
  v_tb   numeric;
  v_p    uuid;
  v_pf   uuid;
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_reach numeric;
  v_good text;
  v_gid  uuid;
  v_far  record;
  v_r    jsonb;
  v_b    jsonb;
  v_row  jsonb;
  v_lines jsonb;
  v_prev text;
  v_leg  numeric;
  v_sum  numeric;
  v_s    text;
  v_out  jsonb;
  v_npc  uuid;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa do Alcance 0188', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0188', 1000000);
    perform cmd.assume_identity(c_uid);
    v_reach := public.passage_reach_nm(v_p);
    if v_reach is distinct from public.wc_num('nav_leg_nm_base') * power(2::numeric, greatest(0, public.skill_level(v_p, 'NAVIGATION') - 1)) then
      raise exception '0188 self-assert FAIL: passage_reach_nm % is not 0107''s formula', v_reach;
    end if;

    -- (c) the farthest harbour beyond her reach that a chain of legs within it reaches
    v_tp := extract(epoch from clock_timestamp());
    select r.* into v_far from voyage.reach_passage(v_p, v_lis) r
     where r.nm is not null and r.direct_nm > 2 * v_reach and array_length(r.stops, 1) >= 1
     order by r.direct_nm desc, r.code limit 1;
    v_tp := round((extract(epoch from clock_timestamp()) - v_tp) * 1000);
    if v_far.code is null then
      raise exception '0188 self-assert FAIL: no harbour beyond her reach is reached through stops';
    end if;
    v_prev := 'LIS'; v_sum := 0;
    foreach v_s in array v_far.stops || v_far.code loop
      select r.nm into v_leg from voyage.reach_from((select id from public.ports where code = v_prev)) r where r.code = v_s;
      if v_leg is null or v_leg > v_reach then
        raise exception '0188 self-assert FAIL: the leg % → % (% nm) is beyond her reach %', v_prev, v_s, v_leg, v_reach;
      end if;
      v_sum := v_sum + v_leg; v_prev := v_s;
    end loop;
    if abs(v_sum - v_far.nm) > 1 then
      raise exception '0188 self-assert FAIL: the legs sum to % nm, the passage says %', v_sum, v_far.nm;
    end if;

    -- (a) the far harbour as the plan's first SAIL: refused up front, named, nothing queued
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(jsonb_build_object('text', format('SAIL %s', v_far.code))));
    if coalesce((v_r->>'ok')::boolean, false) or v_r->>'error_code' <> 'E_LEG_TOO_FAR' or (v_r->>'line')::int <> 1
       or v_r->>'error_message' not like format('Line 1 (SAIL %s): that leg is %%', v_far.code)
       or exists (select 1 from public.orders where fleet_id = v_pf) then
      raise exception '0188 self-assert FAIL: a first leg beyond her reach was not refused up front: %', v_r;
    end if;

    -- (b) …and as line 2
    select g.id, g.code into v_gid, v_good from public.goods g
     where public.port_offers(v_lis, g.id) order by g.code limit 1;
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(
      jsonb_build_object('text', format('BUY %s 1 AT <= 100000', v_good)),
      jsonb_build_object('text', format('SAIL %s', v_far.code))));
    if coalesce((v_r->>'ok')::boolean, false) or (v_r->>'line')::int <> 2 or exists (select 1 from public.orders where fleet_id = v_pf) then
      raise exception '0188 self-assert FAIL: a far second leg was not refused up front, named: %', v_r;
    end if;

    -- (d) the board: her reach; a far sell city's row carries its stops and the Navigation a direct leg needs
    v_tb := extract(epoch from clock_timestamp());
    v_b := world.good_board(v_gid, v_pf);
    v_tb := round((extract(epoch from clock_timestamp()) - v_tb) * 1000);
    if (v_b->'reach'->>'reach_nm')::numeric <> round(v_reach) then
      raise exception '0188 self-assert FAIL: the board''s reach is %, not %', v_b->'reach', round(v_reach);
    end if;
    select e into v_row from jsonb_array_elements(v_b->'sell') e
     where jsonb_array_length(coalesce(e->'stops', '[]')) >= 1 and e->'needs' is not null and e->>'miles' is not null
     order by (e->>'miles')::numeric desc limit 1;
    if v_row is null then
      raise exception '0188 self-assert FAIL: no far sell row carries stops and needs: %',
        (select jsonb_agg(jsonb_build_object('p', e->'port', 'm', e->'miles', 's', e->'stops', 'n', e->'needs')) from jsonb_array_elements(v_b->'sell') e);
    end if;
    -- the sell row is priced from the city it would be bought at (qty.bought_at), the passage there added
    if (v_row->>'miles')::numeric <> round(
         coalesce((select r.nm from voyage.reach_passage(v_p, v_lis) r where r.code = v_b->'qty'->>'bought_at'), 0)
         + (select r.nm from voyage.reach_passage(v_p, coalesce((select id from public.ports where code = v_b->'qty'->>'bought_at'), v_lis)) r
             where r.code = v_row->>'port'))
       or (v_row->'needs'->>'navigation')::int < 2 or jsonb_typeof(v_row->'sailable') <> 'boolean' or v_b->'supplies' is null then
      raise exception '0188 self-assert FAIL: the far row''s miles are not the passage''s, or needs is wrong: %', v_row;
    end if;
    if exists (select 1 from jsonb_array_elements(v_b->'buy') e where not (e ? 'stops') or not (e ? 'needs') or not (e ? 'sailable')) then
      raise exception '0188 self-assert FAIL: a buy row lacks stops/needs';
    end if;

    -- (e) the passage through the stops, as the plan builder queues it, is accepted (every leg within reach)
    select jsonb_agg(jsonb_build_object('text', format('SAIL %s', s)) order by i) into v_lines
      from unnest(v_far.stops || v_far.code) with ordinality x(s, i);
    v_r := cmd.issue_lines(v_pf, v_lines);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0188 self-assert FAIL: the passage within reach (%) was refused: %', v_far.stops || v_far.code, v_r;
    end if;

    raise exception using errcode = 'ZX185', message = jsonb_build_object('far', v_far.code, 'stops', v_far.stops,
      'nm', v_far.nm, 'direct', v_far.direct_nm, 'reach', v_reach, 'row', v_row->'port', 'row_stops', v_row->'stops',
      'needs', v_row->'needs', 'ms_passage', v_tp, 'ms_board', v_tb)::text;
  exception when sqlstate 'ZX185' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0188 self-assert FAIL: the probe company survived its rollback';
  end if;

  -- (f) a merchant is exempt; the walls
  select id into v_npc from public.players where is_npc limit 1;
  if v_npc is not null and (public.passage_reach_nm(v_npc) is not null or public.passage_needs(v_npc, 1e6) is not null) then
    raise exception '0188 self-assert FAIL: a merchant has a reach';
  end if;
  if has_function_privilege('authenticated', 'voyage.reach_passage(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.passage_needs(uuid, numeric)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0188 self-assert FAIL: a reach function is client-callable, or the grant or read wall moved';
  end if;

  raise notice '0188 self-assert ok: THE DESK PLANS ONLY WHAT SHE CAN SAIL (% ms). A first captain (reach % nm) at Lisbon: % lies % nm direct and is reached in % nm through % (every leg within reach, the legs summing to the passage; reach_passage % ms); a plan SAILing straight there was refused up front at line 1, and at line 2; the board (% ms) carries her reach, and its far sell row % carries stops % and needs %, its miles the passage''s; the passage through the stops was accepted whole. passage_gate, good_board and issue_lines reverse to their pre-images, ACLs unchanged.',
    round(extract(epoch from clock_timestamp() - v_t) * 1000), round((v_out->>'reach')::numeric), v_out->>'far',
    round((v_out->>'direct')::numeric), round((v_out->>'nm')::numeric), v_out->'stops', v_out->>'ms_passage',
    v_out->>'ms_board', v_out->>'row', v_out->'row_stops', v_out->'needs';
  raise notice '0188 whole file: % ms', round(extract(epoch from clock_timestamp() - (select t0 from clock_0188)) * 1000);
end $$;
