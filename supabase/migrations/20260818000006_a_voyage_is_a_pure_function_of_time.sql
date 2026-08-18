-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0006 — A VOYAGE IS A PURE FUNCTION OF TIME
--        Routing, frozen speed profiles, closed-form position, and a hazard roll seeded by
--        (voyage_id, day_index, world_secret) — never by the wall clock.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE CENTRAL ARCHITECTURAL DECISION (DESIGN §D.2) ────────────────────────────────────────────
--   "A fleet's position is a PURE FUNCTION, not a simulated state ... No tick can ever drift,
--   stall or double-apply. There is no position to corrupt."
--
--   So there is no `fleet_x`, no `current_nm`, no per-second update job. A voyage row carries
--   `departed_at`, the `path`, and a `speed_profile` FROZEN at departure, and every question about
--   where a fleet is — now, an hour ago, at the moment day 43 elapsed — is answered by evaluating
--   voyage.progress_nm() at that timestamp. A fleet that departs while the player sleeps arrives at
--   exactly the right moment whether or not any job ran.
--
-- ── AND THE HARD REQUIREMENT THAT MAKES OFFLINE CORRECTNESS TRUE, NOT APPROXIMATE (§B.6) ────────
--   "rng = hash_seed( voyage_id || day_index || world_secret ) — a pure function of the voyage and
--   the day index, NOT of when the tick happened to run."
--
--   `voyage.rng_raw()` is declared IMMUTABLE. That is not decoration: an IMMUTABLE function may
--   not read a table and may not read the clock, so the determinism is enforced by the DATABASE,
--   not by a reviewer noticing. The secret is passed IN, by the STABLE `voyage.rng()` wrapper that
--   fetches it from the server-only world_config of 0001. Whether the server evaluates day 43 as
--   it occurs or four hours later, the outcome is byte-identical — which is what
--   scripts/db/proofs/01_offline_equivalence.sql exists to demonstrate end to end.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   voyage.route_direct(a,b)   — THE shortest path between two ports over the leg graph.
--   voyage.route(a,b,via[])    — composes route_direct through hard VIA waypoints (§B.3).
--   voyage.fleet_speed(fleet)  — THE v_fleet of §B.3: slowest ship, then formation.
--   voyage.endurance_days(fleet) — THE endurance of §C.5.
--   voyage.depart(fleet,nodes) — THE only way a voyage row is born; freezes the speed profile.
--   voyage.progress_nm(v, at)  — THE closed-form position. Everything else derives from it.
--   voyage.hazard_roll(v, day) — THE hazard decision. Pure. Writes nothing. 0007 applies its result.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * rng_raw is structurally IMMUTABLE (provolatile = 'i'), repeats exactly, and decorrelates
--     across day / stream / voyage; 2,000 samples stay inside [0,1) with a mean near 0.5.
--   * progress is 0 at departure, monotonic, and exactly total_nm at the ETA and after it.
--   * THE TIME MODEL closes on itself on the world's own leg: voyage-days = nm / knots / 24 and
--     real minutes = voyage-days / time_compression. (DESIGN §K.1 quotes 188 nm for Lisboa→Cádiz;
--     that is the straight line, and the sailed leg round Cape St Vincent is ~248 nm. The rule is
--     asserted, not the quotation — see 0003's header.)
--   * voyage_events is unique on (voyage_id, day_index) — the idempotency guarantee for settle()
--     — proven by a REJECTED duplicate insert, not by reading the DDL.
--   * A fleet cannot hold two SAILING voyages at once — proven by a REJECTED second insert.
--   * The router finds Lisboa→Tunis, honours a VIA waypoint by producing a strictly longer path,
--     and returns nothing for a port that is not in the graph.
--
-- Depends ONLY on: 0001 (knobs), 0002 (ports/legs/classes + gc_distance_nm), 0003 (seed),
--                  0004 (players/fleets/ships), 0005 (game_day).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── Tables ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.voyages (
  id               uuid primary key default gen_random_uuid(),
  fleet_id         uuid not null references public.fleets(id) on delete cascade,
  player_id        uuid not null references public.players(id) on delete cascade,
  path             jsonb not null,
  total_nm         numeric(10,1) not null check (total_nm > 0),
  speed_profile    jsonb not null,
  departed_at      timestamptz not null default now(),
  eta              timestamptz not null,
  status           text not null default 'SAILING' check (status in ('SAILING','ARRIVED','ABORTED')),
  last_settled_day int not null default 0 check (last_settled_day >= 0),
  delay_hours      numeric(10,3) not null default 0 check (delay_hours >= 0),
  origin_port_id   uuid not null references public.ports(id),
  dest_port_id     uuid not null references public.ports(id),
  created_at       timestamptz not null default now(),
  constraint voyages_eta_after_departure check (eta > departed_at)
);
comment on column public.voyages.delay_hours is
  'DESIGN B.6: STORM adds +1.5 voyage-days and CALM 1-4. A delay is SIM-HOURS ADDED TO THE '
  'SCHEDULE, never a change to a leg distance or a frozen speed. It is the sum of the '
  'delay_hours recorded on this voyage''s events, so the schedule stays derivable from the '
  'deterministic checkpoint record and nothing else.';

comment on column public.voyages.speed_profile is
  'DESIGN D.2: "v_fleet per leg is FROZEN at departure into voyages.speed_profile jsonb." A jsonb '
  'array of knots, one per leg of `path`. An ETA quoted at departure never moves.';

-- DESIGN Appendix 1: "fleets.status = SAILING <=> exactly one voyages row with status=SAILING."
-- The "at most one" half is structural, here. The "at least one" half is asserted by
-- voyage.assert_sailing_invariant(), which 0010's tick and the proofs both call.
create unique index if not exists voyages_one_sailing_per_fleet
  on public.voyages (fleet_id) where status = 'SAILING';

create table if not exists public.voyage_events (
  voyage_id   uuid not null references public.voyages(id) on delete cascade,
  day_index   int  not null check (day_index >= 1),
  kind        text not null,
  payload     jsonb not null default '{}'::jsonb,
  resolved_at timestamptz not null default now(),
  primary key (voyage_id, day_index)
);
comment on table public.voyage_events is
  'DESIGN Appendix 1: "unique on (voyage_id, day_index) — the idempotency guarantee for settle()." '
  'A checkpoint resolved twice is the same row, so a late tick and a lazy catch-up cannot disagree.';

alter table public.voyages       enable row level security;
alter table public.voyage_events enable row level security;

create policy voyages_read_own on public.voyages for select to authenticated
  using (player_id = public.current_player_id());
create policy voyage_events_read_own on public.voyage_events for select to authenticated
  using (exists (select 1 from public.voyages v
                  where v.id = voyage_events.voyage_id and v.player_id = public.current_player_id()));

grant select on public.voyages, public.voyage_events to authenticated;

-- ── THE deterministic hazard RNG (DESIGN §B.6) ─────────────────────────────────────────────────
create or replace function voyage.rng_raw(p_voyage uuid, p_day int, p_stream text, p_secret text)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 60 bits of md5 over (voyage, day, stream, secret), mapped into [0, 1).
  -- IMMUTABLE is load-bearing: PostgreSQL forbids an immutable function from reading a table or
  -- the clock, so this cannot become time-dependent by accident. The secret arrives as an argument
  -- precisely so this property can be kept.
  select (('x' || substr(md5(p_voyage::text || ':' || p_day::text || ':' || p_stream || ':' || p_secret), 1, 15))::bit(60)::bigint)::numeric
         / 1152921504606846976::numeric
$$;

create or replace function voyage.rng(p_voyage uuid, p_day int, p_stream text default 'hazard')
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select voyage.rng_raw(p_voyage, p_day, p_stream, public.wc_text('world_secret')) $$;

comment on function voyage.rng(uuid, int, text) is
  'THE hazard seed of DESIGN B.6. Pure in (voyage_id, day_index, stream, world_secret) and in '
  'NOTHING else — in particular not in now(). This is what makes offline settlement byte-identical '
  'to tick-by-tick settlement.';

-- ── Routing over the leg graph (DESIGN §B.3) ───────────────────────────────────────────────────
create or replace function voyage.route_direct(p_from uuid, p_to uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids    uuid[];
  v_start  int[];     -- v_start[u] = first index in the edge arrays belonging to node u
  v_deg    int[];
  v_to     int[];
  v_nm     numeric[];
  v_dist   numeric[];
  v_prev   int[];
  v_done   boolean[];
  v_n      int;
  v_e      int;
  v_src    int;
  v_dst    int;
  v_u      int;
  v_v      int;
  v_best   numeric;
  v_alt    numeric;
  v_i      int;
  v_nodes  uuid[];
  INF      constant numeric := 1e18;
begin
  if p_from = p_to then
    return array[p_from];
  end if;

  -- DIJKSTRA. The first version of this function enumerated every simple path and took the
  -- cheapest, which is exact and instant on the twelve-port world it was written for — and took
  -- THIRTY MINUTES on the real one (214 ports, 782 legs), because the number of simple paths in a
  -- graph of mean degree seven is astronomical. Measured, not guessed: 0006 applied in 1,811
  -- seconds. This is the same answer computed properly, in milliseconds.
  --
  -- The graph is small enough that the classic O(n²) form — scan for the nearest unvisited node,
  -- relax its edges — beats maintaining a heap in plpgsql. Edges are laid out sorted by their
  -- source with a start index per node, so relaxing a node touches only its own ~7 edges.
  select array_agg(p.id order by p.id) into v_ids from public.ports p;
  v_n := coalesce(array_length(v_ids, 1), 0);
  v_src := array_position(v_ids, p_from);
  v_dst := array_position(v_ids, p_to);
  if v_src is null or v_dst is null then
    return null;                   -- a port outside the graph: the caller raises E_NO_ROUTE
  end if;

  -- Both directions from each stored row: the leg table is undirected and stored once (0002).
  select array_agg(e.b order by e.a, e.b), array_agg(e.nm order by e.a, e.b)
    into v_to, v_nm
    from (
      select array_position(v_ids, l.from_port_id) as a,
             array_position(v_ids, l.to_port_id)   as b,
             l.distance_nm                          as nm
        from public.legs l
      union all
      select array_position(v_ids, l.to_port_id),
             array_position(v_ids, l.from_port_id),
             l.distance_nm
        from public.legs l
    ) e;
  v_e := coalesce(array_length(v_to, 1), 0);
  if v_e = 0 then
    return null;
  end if;

  -- Degrees, then a running start index — one pass each, no per-node query.
  v_deg := array_fill(0, array[v_n]);
  select array_agg(cnt order by a) into v_deg from (
    select a, count(*)::int as cnt from (
      select array_position(v_ids, l.from_port_id) as a from public.legs l
      union all
      select array_position(v_ids, l.to_port_id) from public.legs l
    ) x group by a
    union all
    select g.i, 0 from generate_series(1, v_n) g(i)
     where not exists (select 1 from public.legs l
                        where l.from_port_id = v_ids[g.i] or l.to_port_id = v_ids[g.i])
  ) d;
  v_start := array_fill(0, array[v_n]);
  v_i := 1;
  for v_u in 1 .. v_n loop
    v_start[v_u] := v_i;
    v_i := v_i + v_deg[v_u];
  end loop;

  v_dist := array_fill(INF, array[v_n]);
  v_prev := array_fill(0, array[v_n]);
  v_done := array_fill(false, array[v_n]);
  v_dist[v_src] := 0;

  loop
    v_u := 0;
    v_best := INF;
    for v_i in 1 .. v_n loop
      if not v_done[v_i] and v_dist[v_i] < v_best then
        v_best := v_dist[v_i];
        v_u := v_i;
      end if;
    end loop;
    exit when v_u = 0 or v_u = v_dst;
    v_done[v_u] := true;
    for v_i in v_start[v_u] .. v_start[v_u] + v_deg[v_u] - 1 loop
      v_v := v_to[v_i];
      if not v_done[v_v] then
        v_alt := v_dist[v_u] + v_nm[v_i];
        if v_alt < v_dist[v_v] then
          v_dist[v_v] := v_alt;
          v_prev[v_v] := v_u;
        end if;
      end if;
    end loop;
  end loop;

  if v_dist[v_dst] >= INF then
    return null;                   -- unreachable: 0003 asserts this cannot happen, but say it anyway
  end if;

  -- Walk the predecessors back and turn them the right way round.
  v_nodes := array[]::uuid[];
  v_u := v_dst;
  while v_u <> 0 loop
    v_nodes := array[v_ids[v_u]] || v_nodes;
    exit when v_u = v_src;
    v_u := v_prev[v_u];
  end loop;

  return v_nodes;   -- NULL when no path exists: the caller raises E_NO_ROUTE (DESIGN F.5).
end $$;

create or replace function voyage.route(p_from uuid, p_to uuid, p_via uuid[] default '{}')
returns uuid[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_stops uuid[] := array[p_from] || coalesce(p_via, '{}'::uuid[]) || array[p_to];
  v_nodes uuid[] := array[]::uuid[];
  v_seg   uuid[];
  i       int;
begin
  -- VIA waypoints are HARD intermediate nodes (DESIGN B.3), so the route is the concatenation of
  -- the shortest path between consecutive stops — not the shortest path that happens to pass near.
  for i in 1 .. array_length(v_stops, 1) - 1 loop
    v_seg := voyage.route_direct(v_stops[i], v_stops[i + 1]);
    if v_seg is null then
      return null;
    end if;
    if array_length(v_nodes, 1) is null then
      v_nodes := v_seg;
    else
      v_nodes := v_nodes || v_seg[2:array_length(v_seg, 1)];
    end if;
  end loop;
  if array_length(v_nodes, 1) < 2 then
    return null;   -- from = to with no VIA: there is no voyage to make.
  end if;
  return v_nodes;
end $$;

create or replace function voyage.path_from_nodes(p_nodes uuid[])
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'leg_id', l.id, 'from_id', a.id, 'to_id', b.id,
           'from_code', a.code, 'to_code', b.code, 'nm', l.distance_nm,
           'hazard_mult', l.hazard_mult, 'sea_id', b.sea_id
         ) order by i), '[]'::jsonb)
    from generate_subscripts(p_nodes, 1) i
    join public.ports a on a.id = p_nodes[i]
    join public.ports b on b.id = p_nodes[i + 1]
    join public.legs  l on (l.from_port_id = a.id and l.to_port_id = b.id)
                        or (l.from_port_id = b.id and l.to_port_id = a.id)
$$;

-- ── Fleet speed and endurance (DESIGN §B.3, §C.5) ──────────────────────────────────────────────
create or replace function voyage.ship_speed(p_ship uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  s     public.ships%rowtype;
  c     public.ship_classes%rowtype;
  v_fill    numeric;
  v_hull    numeric;
  v_load    numeric;
  v_crew    numeric;
  v_cargo_t numeric;
begin
  select * into s from public.ships where id = p_ship;
  select * into c from public.ship_classes where id = s.class_id;
  if s.id is null then
    raise exception 'E_NO_SUCH_SHIP: %', p_ship using errcode = 'P0001';
  end if;

  -- Cargo is weighted by goods.bulk (DESIGN G.3: bullion is dense and cheap to carry, timber is not).
  select coalesce(sum((e.value)::text::numeric * g.bulk), 0) into v_cargo_t
    from jsonb_each(s.cargo) e join public.goods g on g.code = e.key;

  v_fill := least(1.0, (v_cargo_t + s.water_t + s.food_t) / c.hold);
  v_hull := public.wc_num('hull_speed_floor')
          + (1 - public.wc_num('hull_speed_floor')) * least(1.0, s.durability / c.durability);
  v_load := 1 - public.wc_num('load_speed_penalty') * v_fill;
  v_crew := case when s.crew >= c.crew_required then 1.0 else public.wc_num('crew_short_speed_mult') end;

  -- M_wind is pinned at 1.00 and M_officer at 1.00: wind and officers are explicitly out of V0
  -- (DESIGN K.1). The knob `wind_mult_v0` exists so V1 changes a value, not this formula.
  return round(c.speed_kn * v_hull * v_load * v_crew * public.wc_num('wind_mult_v0'), 4);
end $$;

create or replace function voyage.fleet_speed(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_min   numeric;
  v_ships int;
  v_form  numeric;
begin
  select min(voyage.ship_speed(s.id)), count(*) into v_min, v_ships
    from public.ships s where s.fleet_id = p_fleet;
  if v_ships = 0 then
    raise exception 'E_NO_SHIPS: fleet % has no ships', p_fleet using errcode = 'P0001';
  end if;
  -- DESIGN B.3: M_formation 1.00 for <=3 ships, 0.98 for 4-6, 0.95 for 7+.
  v_form := case when v_ships <= 3 then 1.00 when v_ships <= 6 then 0.98 else 0.95 end;
  return round(v_min * v_form, 4);
end $$;

create or replace function voyage.endurance_days(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- DESIGN C.5: the SHORTEST-ranged ship sets the fleet's endurance. Stores are pooled per hull.
  select coalesce(min(least(
           case when s.crew = 0 then 9999 else s.water_t / (s.crew * public.wc_num('water_per_crew_day')) end,
           case when s.crew = 0 then 9999 else s.food_t  / (s.crew * public.wc_num('food_per_crew_day'))  end
         )), 0)
    from public.ships s where s.fleet_id = p_fleet
$$;

-- ── Departure: the ONE place a voyage is born ──────────────────────────────────────────────────
create or replace function voyage.depart(p_fleet uuid, p_nodes uuid[], p_at timestamptz default now())
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_path    jsonb;
  v_speed   numeric;
  v_total   numeric;
  v_hours   numeric := 0;
  v_profile jsonb := '[]'::jsonb;
  v_player  uuid;
  v_voyage  uuid;
  e         jsonb;
begin
  select player_id into v_player from public.fleets where id = p_fleet;
  if v_player is null then
    raise exception 'E_NO_SUCH_FLEET: %', p_fleet using errcode = 'P0001';
  end if;

  v_path  := voyage.path_from_nodes(p_nodes);
  if jsonb_array_length(v_path) = 0 then
    raise exception 'E_NO_ROUTE: the node list does not compose into legs' using errcode = 'P0001';
  end if;
  v_speed := voyage.fleet_speed(p_fleet);

  -- FREEZE. One entry per leg, all equal in V0 because M_wind is 1.00 everywhere; the SHAPE is
  -- per-leg so V1's seasonal wind changes the seeded values and not this code.
  select sum((e2->>'nm')::numeric) into v_total from jsonb_array_elements(v_path) e2;
  for e in select * from jsonb_array_elements(v_path) loop
    v_profile := v_profile || to_jsonb(v_speed);
    v_hours   := v_hours + (e->>'nm')::numeric / v_speed;
  end loop;

  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta,
                              origin_port_id, dest_port_id)
  values (p_fleet, v_player, v_path, v_total, v_profile, p_at,
          p_at + make_interval(secs => (v_hours * 3600 / public.wc_num('time_compression'))::double precision),
          (v_path->0->>'from_id')::uuid,
          (v_path->(jsonb_array_length(v_path) - 1)->>'to_id')::uuid)
  returning id into v_voyage;

  update public.fleets
     set status = 'SAILING', port_id = null, version = version + 1
   where id = p_fleet;

  return v_voyage;
end $$;

-- ── Closed-form position (DESIGN §D.2) ─────────────────────────────────────────────────────────
create or replace function voyage.sim_hours(p_voyage uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum((e.value->>'nm')::numeric / (v.speed_profile->(e.ordinality::int - 1))::text::numeric), 0)
    from public.voyages v
   cross join lateral jsonb_array_elements(v.path) with ordinality e(value, ordinality)
   where v.id = p_voyage
$$;

create or replace function voyage.total_days(p_voyage uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select greatest(1, ceil((voyage.sim_hours(p_voyage)
                       + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int) $$;

-- THE ONE statement of "how much delay had this voyage accrued before day N began".
-- Everything about the schedule derives from this, so a delay cannot be counted twice or missed.
create or replace function voyage.delay_before_day(p_voyage uuid, p_day int)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(coalesce((ve.payload->>'delay_hours')::numeric, 0)), 0)
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index < p_day
$$;

create or replace function voyage.day_ends_at(p_voyage uuid, p_day int)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- A voyage-day is 24 SAILING sim-hours, which is 24*3600/TIME_COMPRESSION real seconds (180 s at
  -- 480), pushed later by whatever delay the earlier days already cost. Day N's boundary depends
  -- only on days < N, so the schedule is never circular and never needs the clock.
  --
  -- AND IT IS CLAMPED AT THE ETA, which is not cosmetic. A voyage's last day rarely divides evenly
  -- into 24 sim-hours, so the final checkpoint's unclamped boundary can fall AFTER the arrival.
  -- Without the clamp, settle() would dock the fleet with checkpoints still unresolved — and it
  -- would resolve a different NUMBER of them depending on whether it was called day by day or once
  -- at the end. scripts/db/proofs/01_offline_equivalence.sql caught exactly that: 10 checkpoints
  -- tick-by-tick against 12 lazily. Clamping makes the trailing days land ON the arrival instant,
  -- so both settlement paths resolve every one of them before the fleet docks.
  select least(v.eta,
               v.departed_at + make_interval(secs =>
                 ((p_day * 24 + voyage.delay_before_day(p_voyage, p_day)) * 3600
                  / public.wc_num('time_compression'))::double precision))
    from public.voyages v where v.id = p_voyage
$$;

create or replace function voyage.days_complete(p_voyage uuid, p_at timestamptz default now())
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_cap int;
  d     int := 0;
begin
  -- Bounded by the voyage's own length: a query far past the ETA must not walk forever.
  v_cap := greatest(1, ceil((voyage.sim_hours(p_voyage)
                             + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int) + 1;
  while d < v_cap and voyage.day_ends_at(p_voyage, d + 1) <= p_at loop
    d := d + 1;
  end loop;
  return d;
end $$;

-- When a checkpoint adds delay, the arrival moves. ONE place recomputes it, from the events.
create or replace function voyage.recompute_eta(p_voyage uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_delay numeric;
  v_eta   timestamptz;
begin
  select coalesce(sum(coalesce((ve.payload->>'delay_hours')::numeric, 0)), 0) into v_delay
    from public.voyage_events ve where ve.voyage_id = p_voyage;
  update public.voyages v
     set delay_hours = v_delay,
         eta = v.departed_at + make_interval(secs =>
                 ((voyage.sim_hours(p_voyage) + v_delay) * 3600
                  / public.wc_num('time_compression'))::double precision)
   where v.id = p_voyage
  returning v.eta into v_eta;
  return v_eta;
end $$;

create or replace function voyage.progress_nm(p_voyage uuid, p_at timestamptz default now())
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v         public.voyages%rowtype;
  v_hours   numeric;
  v_done    numeric := 0;
  i         int := 0;
  e         jsonb;
  v_leg_h   numeric;
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null then
    raise exception 'E_NO_SUCH_VOYAGE: %', p_voyage using errcode = 'P0001';
  end if;

  -- DESIGN D.2: progress(t) = clamp((t - departed_at) x TIME_COMPRESSION x v_fleet / 3600, 0, total_nm)
  -- generalised two ways: a per-leg speed profile, and the delay already suffered. Elapsed sim-
  -- hours minus delay = SAILING hours, and sailing hours are consumed leg by leg. Still closed
  -- form: nothing here is a stored position, and re-evaluating at any t gives the same answer.
  v_hours := greatest(0, extract(epoch from (p_at - v.departed_at))) * public.wc_num('time_compression') / 3600
           - voyage.delay_before_day(p_voyage, voyage.days_complete(p_voyage, p_at) + 1);
  v_hours := greatest(0, v_hours);

  for e in select * from jsonb_array_elements(v.path) loop
    v_leg_h := (e->>'nm')::numeric / (v.speed_profile->i)::text::numeric;
    if v_hours >= v_leg_h then
      v_done  := v_done + (e->>'nm')::numeric;
      v_hours := v_hours - v_leg_h;
    else
      v_done  := v_done + v_hours * (v.speed_profile->i)::text::numeric;
      v_hours := 0;
      exit;
    end if;
    i := i + 1;
  end loop;

  return least(round(v_done, 4), v.total_nm);
end $$;

create or replace function voyage.position(p_voyage uuid, p_at timestamptz default now())
returns table (leg_index int, from_code text, to_code text, leg_frac numeric,
               nm_done numeric, total_nm numeric, lat numeric, lon numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v       public.voyages%rowtype;
  v_done  numeric;
  v_acc   numeric := 0;
  i       int := 0;
  e       jsonb;
  a       public.ports%rowtype;
  b       public.ports%rowtype;
begin
  select * into v from public.voyages where id = p_voyage;
  v_done := voyage.progress_nm(p_voyage, p_at);

  for e in select * from jsonb_array_elements(v.path) loop
    if v_done <= v_acc + (e->>'nm')::numeric or i = jsonb_array_length(v.path) - 1 then
      select * into a from public.ports where id = (e->>'from_id')::uuid;
      select * into b from public.ports where id = (e->>'to_id')::uuid;
      leg_index := i;
      from_code := a.code;
      to_code   := b.code;
      leg_frac  := round(least(1, greatest(0, (v_done - v_acc) / (e->>'nm')::numeric)), 6);
      nm_done   := v_done;
      total_nm  := v.total_nm;
      -- The MAP is an output device (DESIGN E.5 / law 3): this is display geometry, linear along
      -- the leg. It is not used by any rule; distance is always the authored leg distance.
      lat := round(a.lat + (b.lat - a.lat) * leg_frac, 4);
      lon := round(a.lon + (b.lon - a.lon) * leg_frac, 4);
      return next;
      return;
    end if;
    v_acc := v_acc + (e->>'nm')::numeric;
    i := i + 1;
  end loop;
end $$;

create or replace function voyage.leg_at_day(p_voyage uuid, p_day int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v      public.voyages%rowtype;
  v_done numeric;
  v_acc  numeric := 0;
  e      jsonb;
begin
  select * into v from public.voyages where id = p_voyage;
  v_done := voyage.progress_nm(p_voyage, voyage.day_ends_at(p_voyage, p_day));
  for e in select * from jsonb_array_elements(v.path) loop
    v_acc := v_acc + (e->>'nm')::numeric;
    if v_done <= v_acc then
      return e;
    end if;
  end loop;
  return v.path->(jsonb_array_length(v.path) - 1);
end $$;

-- ── THE hazard decision (DESIGN §B.6). Pure: it writes nothing. ────────────────────────────────
create or replace function voyage.hazard_roll(p_voyage uuid, p_day int)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_leg    jsonb;
  v_base   numeric;
  v_piracy numeric;
  v_p      numeric;
  r_occur  numeric;
  r_kind   numeric;
  r_mag    numeric;
begin
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  select s.hazard_base, s.piracy_index into v_base, v_piracy
    from public.seas s where s.id = (v_leg->>'sea_id')::uuid;

  -- DESIGN B.6. season_mult, escort_score and lookout_expertise are all 1.0/0 in V0: seasons and
  -- officers are out of scope (K.1), and escorts need guns the V0 hulls barely carry. The shape of
  -- the formula is kept so V1 supplies coefficients rather than a second formula.
  v_p := least(public.wc_num('hazard_p_max'),
               greatest(0, v_base * (v_leg->>'hazard_mult')::numeric));

  r_occur := voyage.rng(p_voyage, p_day, 'occur');
  r_kind  := voyage.rng(p_voyage, p_day, 'kind');
  r_mag   := voyage.rng(p_voyage, p_day, 'magnitude');

  occurred  := r_occur < v_p;
  p_hazard  := round(v_p, 6);
  magnitude := round(r_mag, 6);
  -- V0 hazard table (DESIGN K.1): STORM, CALM, PIRATES, SHORT_RATIONS. SHORT_RATIONS is NOT rolled
  -- — it is a CONDITION of the stores, decided by settle() from what is actually aboard.
  kind := case
            when not occurred then null
            when r_kind < 0.40 then 'STORM'
            when r_kind < 0.75 then 'CALM'
            else 'PIRATES'
          end;
  -- The piracy index of the sea shifts the mix toward raiders on the Barbary run without needing
  -- a second roll: a high-piracy sea converts some storms into pirates.
  if occurred and kind = 'STORM' and r_kind < 0.40 * v_piracy then
    kind := 'PIRATES';
  end if;
  return next;
end $$;

-- ── The invariant of Appendix 1, stated once ───────────────────────────────────────────────────
create or replace function voyage.assert_sailing_invariant()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.fleets f
    full join (select fleet_id from public.voyages where status = 'SAILING') v on v.fleet_id = f.id
   where (f.status = 'SAILING') is distinct from (v.fleet_id is not null);
  if v_bad <> 0 then
    raise exception 'SAILING INVARIANT VIOLATED on % fleet(s): fleets.status = SAILING must hold exactly when one SAILING voyage exists',
      v_bad using errcode = '23514';
  end if;
end $$;

grant execute on function voyage.progress_nm(uuid, timestamptz) to authenticated;
grant execute on function voyage.position(uuid, timestamptz)    to authenticated;
grant execute on function voyage.fleet_speed(uuid)              to authenticated;
grant execute on function voyage.endurance_days(uuid)           to authenticated;
grant usage on schema voyage to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0006-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_cad     uuid;
  v_tun     uuid;
  v_fnc     uuid;
  v_nodes   uuid[];
  v_via     uuid[];
  v_voyage  uuid;
  v         public.voyages%rowtype;
  v_speed   numeric;
  v_days    numeric;
  v_mins    numeric;
  v_p0      numeric;
  v_pmid    numeric;
  v_peta    numeric;
  v_plate   numeric;
  v_a       numeric;
  v_b       numeric;
  v_mean    numeric;
  v_out     int;
  v_vol     char;
  n         int;
  -- findings that survive the rolled-back subtransaction
  f_speed_ok  boolean := false;
  f_prog_ok   boolean := false;
  f_dup_pk    boolean := false;
  f_two_sail  boolean := false;
  f_delay_ok  boolean := false;
  v_eta0      timestamptz;
  v_bnd0      timestamptz;
  v_prog0     numeric;
  f_route_ok  boolean := false;
  f_via_ok    boolean := false;
  f_noroute   boolean := false;
  v_grants    int;
begin
  -- (a) STRUCTURAL: rng_raw is IMMUTABLE, so it CANNOT read the clock or a table.
  select provolatile into v_vol from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'voyage' and p.proname = 'rng_raw';
  if v_vol is distinct from 'i' then
    raise exception '0006 self-assert FAIL: voyage.rng_raw is volatility "%", not IMMUTABLE — its determinism is then only a promise', v_vol;
  end if;

  -- (b) Determinism, decorrelation and a uniformity sanity check over 2,000 samples.
  if voyage.rng_raw(v_probe, 7, 'occur', 'secret') <> voyage.rng_raw(v_probe, 7, 'occur', 'secret') then
    raise exception '0006 self-assert FAIL: rng_raw is not repeatable';
  end if;
  if voyage.rng_raw(v_probe, 7, 'occur', 'secret') = voyage.rng_raw(v_probe, 8, 'occur', 'secret') then
    raise exception '0006 self-assert FAIL: rng_raw does not vary with day_index';
  end if;
  if voyage.rng_raw(v_probe, 7, 'occur', 'secret') = voyage.rng_raw(v_probe, 7, 'kind', 'secret') then
    raise exception '0006 self-assert FAIL: rng_raw does not vary with the stream';
  end if;
  if voyage.rng_raw(v_probe, 7, 'occur', 'secret') = voyage.rng_raw(v_probe, 7, 'occur', 'other') then
    raise exception '0006 self-assert FAIL: rng_raw does not vary with the world secret';
  end if;
  select avg(x), count(*) filter (where x < 0 or x >= 1)
    into v_mean, v_out
    from (select voyage.rng_raw(v_probe, g, 'occur', 'secret') x from generate_series(1, 2000) g) s;
  if v_out <> 0 then
    raise exception '0006 self-assert FAIL: % of 2000 rng samples fell outside [0,1)', v_out;
  end if;
  if v_mean < 0.45 or v_mean > 0.55 then
    raise exception '0006 self-assert FAIL: rng mean over 2000 samples is %, expected near 0.5', v_mean;
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_tun from public.ports where code = 'TUN';
  select id into v_fnc from public.ports where code = 'FNC';

  begin
    v_player := public.new_house(v_probe, 'Casa Rota', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;

    -- (c) The router.
    v_nodes := voyage.route(v_lis, v_tun);
    if v_nodes is not null and array_length(v_nodes, 1) >= 3
       and v_nodes[1] = v_lis and v_nodes[array_length(v_nodes, 1)] = v_tun then
      f_route_ok := true;
    end if;
    -- A hard VIA waypoint must produce a path that is not shorter than the free one; sending a
    -- Lisboa->Cádiz run via Funchal must actually go to Funchal.
    v_via := voyage.route(v_lis, v_cad, array[v_fnc]);
    if v_via is not null and v_fnc = any(v_via)
       and array_length(v_via, 1) > array_length(voyage.route(v_lis, v_cad), 1) then
      f_via_ok := true;
    end if;
    -- NEGATIVE control: a port outside the graph is unroutable, not silently routed.
    if voyage.route(v_lis, gen_random_uuid()) is null then
      f_noroute := true;
    end if;

    -- (d) THE TIME MODEL, checked against ITSELF rather than against a quoted number.
    --
    -- DESIGN §K.1 says the opening voyage is "188 nm, 1.6 voyage-days, about 4.7 real minutes".
    -- 188 nm is the STRAIGHT LINE from Lisboa to Cádiz, and a ship cannot sail it: Cape St
    -- Vincent is in the way, so the real world's leg is ~248 nm round the cape. Asserting 188
    -- would be asserting a number that was never sailable — see the note in 0003.
    --
    -- What is checked instead is the RULE, on whatever leg the world actually has: hours are
    -- distance over speed, a voyage-day is 24 of them, and real time is voyage time divided by
    -- the compression knob. Those three hold for every leg in the world, not just this one.
    v_speed  := voyage.fleet_speed(v_fleet);
    v_voyage := voyage.depart(v_fleet, voyage.route(v_lis, v_cad), now());
    select * into v from public.voyages where id = v_voyage;
    v_days := round(voyage.sim_hours(v_voyage) / 24, 2);
    v_mins := round(extract(epoch from (v.eta - v.departed_at))::numeric / 60, 2);
    if v.total_nm >= voyage.gc_distance_nm(38.71, -9.14, 36.53, -6.29)                     -- >= the straight line
       and abs(v_days - v.total_nm / v_speed / 24) < 0.02                                   -- days = nm / kn / 24
       and abs(v_mins - v_days * 1440 / public.wc_num('time_compression')) < 0.05           -- real = voyage / 480
       and v_days between 1.0 and 4.0 then                                                  -- and it is still a short first hop
      f_speed_ok := true;
    end if;

    -- (e) Closed-form progress: 0 at departure, monotonic, exactly total_nm at and after the ETA.
    v_p0    := voyage.progress_nm(v_voyage, v.departed_at);
    v_a     := voyage.progress_nm(v_voyage, v.departed_at + interval '1 minute');
    v_b     := voyage.progress_nm(v_voyage, v.departed_at + interval '2 minutes');
    v_pmid  := voyage.progress_nm(v_voyage, v.departed_at + (v.eta - v.departed_at) / 2);
    v_peta  := voyage.progress_nm(v_voyage, v.eta);
    v_plate := voyage.progress_nm(v_voyage, v.eta + interval '9 hours');
    if v_p0 = 0 and v_a > 0 and v_b > v_a and v_pmid > v_a and v_pmid < v.total_nm
       and abs(v_peta - v.total_nm) < 0.01 and v_plate = v.total_nm then
      f_prog_ok := true;
    end if;

    -- (f) DELAY MOVES THE SCHEDULE, by exactly what the checkpoint recorded and nothing more.
    v_eta0  := v.eta;
    v_bnd0  := voyage.day_ends_at(v_voyage, 2);
    -- Sampled AFTER day 1's boundary (180 real seconds in), because a delay recorded on day 1
    -- must not retroactively slow the ship before day 1 ended. Sampling before it would prove
    -- nothing and passing there would be the bug.
    v_prog0 := voyage.progress_nm(v_voyage, v.departed_at + interval '4 minutes');

    -- (f) POSITIVE CONTROL: (voyage_id, day_index) is unique — settle()'s idempotency guarantee.
    insert into public.voyage_events (voyage_id, day_index, kind, payload)
    values (v_voyage, 1, 'PROBE', jsonb_build_object('delay_hours', 24));
    perform voyage.recompute_eta(v_voyage);
    select * into v from public.voyages where id = v_voyage;
    -- 24 sim-hours at TIME_COMPRESSION 480 is exactly 180 real seconds.
    if abs(extract(epoch from (v.eta - v_eta0)) - 180) < 0.001
       and abs(extract(epoch from (voyage.day_ends_at(v_voyage, 2) - v_bnd0)) - 180) < 0.001
       and voyage.progress_nm(v_voyage, v.departed_at + interval '4 minutes') < v_prog0 then
      f_delay_ok := true;
    end if;
    begin
      insert into public.voyage_events (voyage_id, day_index, kind) values (v_voyage, 1, 'PROBE_AGAIN');
    exception when others then f_dup_pk := true;
    end;

    -- (g) POSITIVE CONTROL: a fleet cannot hold two SAILING voyages.
    begin
      insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, eta,
                                  origin_port_id, dest_port_id)
      values (v_fleet, v_player, v.path, v.total_nm, v.speed_profile, now() + interval '1 hour',
              v.origin_port_id, v.dest_port_id);
    exception when others then f_two_sail := true;
    end;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_route_ok then raise exception '0006 self-assert FAIL: the router did not find Lisboa -> Tunis'; end if;
  if not f_via_ok   then raise exception '0006 self-assert FAIL: a VIA waypoint was not honoured as a hard intermediate node'; end if;
  if not f_noroute  then raise exception '0006 self-assert FAIL: routing to a port outside the graph returned a path'; end if;
  if not f_speed_ok then
    raise exception '0006 self-assert FAIL: the starter Barca on Lisboa->Cádiz gives % voyage-days / % real minutes at % kn over % nm, which does not satisfy days = nm/kn/24 and real = voyage/time_compression',
      v_days, v_mins, v_speed, v.total_nm;
  end if;
  if not f_prog_ok then
    raise exception '0006 self-assert FAIL: progress is not closed-form (t0=%, +1m=%, +2m=%, mid=%, eta=%, eta+9h=%, total=%)',
      v_p0, v_a, v_b, v_pmid, v_peta, v_plate, v.total_nm;
  end if;
  if not f_dup_pk   then raise exception '0006 self-assert FAIL: a duplicate (voyage_id, day_index) was ACCEPTED — settle() would double-apply'; end if;
  if not f_delay_ok then
    raise exception '0006 self-assert FAIL: a 24 sim-hour delay recorded on day 1 did not move the ETA and day-2 boundary by exactly 180 real seconds, or did not slow progress';
  end if;
  if not f_two_sail then raise exception '0006 self-assert FAIL: a fleet was allowed two SAILING voyages at once'; end if;

  select count(*) into n from public.voyages;
  if n <> 0 then raise exception '0006 self-assert FAIL: % voyage row(s) survived the probe subtransaction', n; end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0006 self-assert FAIL: the voyage tables minted % client write grant(s)', v_grants; end if;

  raise notice '0006 self-assert ok: rng_raw is IMMUTABLE, repeatable, and varies with day/stream/secret (2000 samples in [0,1), mean %); router finds Lisboa-Tunis, honours a VIA waypoint and returns NULL off-graph; the starter Barca sails % nm Lisboa-Cádiz (round Cape St Vincent; the straight line is 188) at % kn = % voyage-days / % real minutes, and days = nm/kn/24 to within 0.02; progress is 0 at departure, monotonic, and pinned at total_nm from the ETA onward; a 24 sim-hour CALM recorded on day 1 moved the ETA and the day-2 boundary by exactly 180 real seconds and slowed progress; duplicate (voyage_id, day_index) and a second SAILING voyage both REJECTED; 0 client write grants',
    round(v_mean, 4), v.total_nm, v_speed, v_days, v_mins;
end $$;
