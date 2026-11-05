-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0309 — A CARGO SHIP CARRIES FUNDS: the capital loads, she sails the realm's circuit, each city is topped up, the rest comes home, dark
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: step 3 of the REVIEW at the top of docs/CITY_CONVOYS.md, the slice after 0308. Funds only. 5 ships a realm, one circuit: capital, every city, capital.
--
-- DARK: convoys_enabled stays false and no ship exists. public.crown_aid, public.port_fee, public.tick_stats and public.stats_live_fold each take a hunk, and each
-- behaves as it did: the crown_aid branch is behind public.convoys_on(), the port_fee term and the two funds_aboard terms read public.cargo_ships and public.convoy_cargo,
-- which are empty. The new minute job, public.tick_cargo_ships, walks no ship and writes nothing. No switch is lit and no ship is made by this file on any world.
--
-- EXACTLY ONE PATH PER STATE OF THE SWITCH. public.crown_aid decides who is short, as 0306 and 0307 do, and the capital still draws on its nation (public.crown_call).
--   OFF: the aid pays out instantly, as today. No ship delivers; a ship already out sails home without paying and returns all she carries.
--   ON:  the same roster goes to public.cargo_ships_load instead of the instant loop. No CROWN_AID is written.
--
-- LIT, ON A PROBE ONLY (docs/dev-log/2026-11-05-cargo-funds.md):
--   1. LOAD (public.cargo_ships_load, inside public.crown_aid, the hourly :37 run): per capital, one ship lying idle at home takes what the roster needs, less what her
--      realm's ships already carry, up to the capital's surplus. One ship a run: that alone spaces them about an hour apart, and it needs no fleet lock in the city run.
--   2. SAIL (public.cargo_ship_step, in public.tick_cargo_ships, pg_cron byeharu-voyage:cargo-ships, every minute, never in the beat): she takes the next leg of the circuit
--      she started on through voyage.depart. voyage.settle docks her, as anyone.
--   3. DELIVER: at each stop, public.convoy_book tops the city up to public.city_aid_target, keeping the rest aboard.
--   4. RETURN: back at the capital what is left goes into its purse.
--   public.convoy_book is the one writer of all three: the flow, the book row and the live figure move together. Nothing is minted; every kind is moved.
--
-- THE CIRCUIT (public.cargo_circuit_plan, STABLE, then public.cargo_circuit_build): the server finds no path, so the graph is public.npc_courses in both directions, shortest
--   paths by Bellman-Ford, the tour nearest neighbour then 2-opt, as the sizing was. Each leg is a chain of courses, one voyage. A city no course reaches is named in left_out.
--   Flags change (public.tick_influence), so a realm's circuit is rebuilt after any flag change; a ship finishes the lap she began on; a city that left is passed, not paid.
--
-- THE V2 LIST of docs/dev-log/2026-11-05-cargo-ships.md:
--   FUNDS ABOARD count in set_aside, the figure for gold in no purse (open escrow, coupons). public.funds_aboard, one term in public.tick_stats and public.stats_live_fold.
--   THE DOCK FEE: public.port_fee answers 0 for a cargo ship's house: a crown's own ship calling on her own crown's cities. She owes nothing and moves no gold; she keeps her port time.
--   HULL WEAR: the crown mends her free at the capital after every lap. A ship that docks wrecked (UNABLE_TO_SAIL) delivers, lies convoy_wreck_seconds, is patched and sails on:
--     delayed, not lost. No gold moves, so nothing is minted.
--
-- LOCKS: public.cargo_ships_load runs under public.crown_aid's locks (a city, then its capital) and takes no other: it only reads the fleet. A step takes her fleet row, SKIP LOCKED,
--   and no purse lock: CONVOY_DELIVER and CONVOY_RETURN are positive moved kinds, which public.treasury_post writes with no lock and public.mint_guard does not gate.
--
-- SELF-ASSERT (a probe nation of four rolled-back harbours and three probe courses; no real city, no real game step, per docs/OPS_HEALTH.md section 4): dark equals the pre-image of
-- public.crown_aid and public.port_fee, scene by scene; every hunk reverses; nothing else moved. Lit: the plan, the load, one ship a run, no CROWN_AID; delivery exact; rest returned;
-- wreck delayed; the switch off mid-lap; the sum of purses and funds aboard never moves. THE REAL VOYAGE ENGINE, THE REAL public.city_day AND THE STATS FOLD ARE PROVED IN CI, not here:
-- proof 19, scripts/db/proofs/19_cargo_funds.sql. Mutation controls: scripts/ops/harness/cargo-ships/proof-0309.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: one knob, two tables, three columns, eight functions, six hunks, one cron row, catalog reads, one probe.
--   Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): nothing is lit, so none is needed. Lit later: convoys_enabled false puts the instant path back on the next :37 run; ships at sea come home and return what they carry.
-- VERSION: 0309 - prod head 0308 (2026-11-05).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn    text[];
  v_old   text[];
  v_new   text[];
  v_oids  oid[];
  v_def0  jsonb := '{}'::jsonb;
  v_acl0  jsonb := '{}'::jsonb;
  v_cur   jsonb := '{}'::jsonb;
  v_def   text;
  v_i     int;
  v_n     int;
  v_fn_before   text;
  v_cfg_before  text;
  v_word_before text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_t0    timestamptz := clock_timestamp();
  v_mark  bigint;
  v_nat   uuid;
  v_cap   uuid;
  v_fl    uuid;
  v_fl2   uuid;
  v_pl    uuid;
  v_other uuid;
  v_s1    uuid;
  v_s2    uuid;
  v_sum   bigint;
  v_day   timestamptz;
  v_all   jsonb;
  v_res   jsonb := '{}'::jsonb;
  v_x     jsonb := '{}'::jsonb;
  v_a     jsonb;
  v_b     jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.cargo_ships') is null or to_regclass('public.convoy_cargo') is null or to_regprocedure('public.crown_call(jsonb)') is null
     or to_regprocedure('public.cargo_ships_commission(uuid)') is null or to_regclass('public.npc_courses') is null then
    raise exception '0309 refuses: 0307 / 0308 (the call, the ships, the book) are not in this world';
  end if;
  if to_regprocedure('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)') is not null or to_regclass('public.cargo_circuits') is not null
     or exists (select 1 from public.world_config c where c.key = 'convoy_wreck_seconds') then
    raise exception '0309 refuses: it has been applied once';
  end if;
  if public.convoys_on() or exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo) then
    raise exception '0309 refuses: it is cut for a dark world with no ship';
  end if;

  v_fn := array[
    'public.crown_aid(uuid)', 'public.crown_aid(uuid)', 'public.port_fee(uuid,uuid,numeric)', 'public.tick_stats(timestamp with time zone)',
    'public.stats_live_fold(timestamp with time zone,boolean)', 'public.tg_convoy_cargo_closes()'];

  select array_agg(p.oid) into v_oids
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in (select f::regprocedure::oid from unnest(v_fn) f);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before from pg_proc p where p.oid = any (v_oids);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_word_before from public.stats_flow_words w;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def0 := v_def0 || jsonb_build_object(v_fn[v_i], replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', ''));
    v_acl0 := v_acl0 || jsonb_build_object(v_fn[v_i], (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
                                                         from pg_proc p where p.oid = v_fn[v_i]::regprocedure));
  end loop;
  v_cur := v_def0;

  -- ── 1. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('convoy_wreck_seconds', to_jsonb(600),
     '0309: real seconds a cargo ship that docks wrecked (UNABLE_TO_SAIL) lies in that port before she sails on, patched by the crown. Delayed, not lost.');

  -- ── 2. THE CIRCUIT AND WHERE SHE IS ON IT ──
  create table public.cargo_circuits (
    id        bigint generated always as identity primary key,
    nation_id uuid not null references public.great_powers(nation_id),
    built_at  timestamptz not null default now(),
    left_out  jsonb not null default '[]'::jsonb
  );
  create index cargo_circuits_nation on public.cargo_circuits (nation_id, id desc);
  comment on table public.cargo_circuits is
    '0309: one circuit of a realm: capital, every city, capital. The newest of a nation is the current one; a ship out on an older one finishes it. left_out: the city codes no course reaches. Written by public.cargo_circuit_build alone. Server-only.';
  create table public.cargo_circuit_legs (
    circuit_id bigint not null references public.cargo_circuits(id) on delete cascade,
    ord        integer not null check (ord >= 1),
    to_port    uuid not null references public.ports(id),
    nm         numeric not null,
    segments   jsonb not null,
    primary key (circuit_id, ord)
  );
  comment on table public.cargo_circuit_legs is
    '0309: the legs of a circuit in sailing order, each one voyage: the chain of courses to its stop, as voyage.depart takes it. The last leg ends at the capital. Server-only.';
  alter table public.cargo_circuits enable row level security;
  alter table public.cargo_circuit_legs enable row level security;
  revoke all on table public.cargo_circuits, public.cargo_circuit_legs from public, anon, authenticated;
  revoke all on sequence public.cargo_circuits_id_seq from public, anon, authenticated;

  alter table public.cargo_ships
    add column circuit_id bigint references public.cargo_circuits(id),
    add column leg        integer not null default 0,
    add column out_load   bigint references public.convoy_cargo(id);
  comment on column public.cargo_ships.circuit_id is '0309: the circuit of her lap, kept to its end even if a newer one is built.';
  comment on column public.cargo_ships.leg is '0309: the last leg of that circuit she took. 0 at home.';
  comment on column public.cargo_ships.out_load is '0309: the load she left the capital with, null while she lies at home. Set at departure, cleared when she is back; it is what tells a load about to sail from one come home. public.cargo_ship_step alone writes these three.';

  -- ── 3. WHAT IS ABOARD ──
  execute $f$
create function public.cargo_ship_aboard(p_fleet uuid)
returns table(load_id bigint, aboard bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0309: THE reading of what a ship carries: her newest load less its closing rows. No row when it is all closed. A ship holds one open load (public.tg_convoy_cargo_closes),
  -- so this walks her last lap's rows and no more, however long the book grows.
  select l.id, x.left_d
    from (select c.id, c.ducats from public.convoy_cargo c where c.fleet_id = p_fleet and c.stage = 'LOADED' order by c.id desc limit 1) l
   cross join lateral (select l.ducats - coalesce(sum(k.ducats), 0)::bigint as left_d from public.convoy_cargo k where k.load_id = l.id) x
   where x.left_d > 0
$body$
  $f$;
  revoke all on function public.cargo_ship_aboard(uuid) from public, anon, authenticated;

  execute $f$
create function public.funds_aboard()
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0309: THE funds at sea, world-wide: one term of set_aside (public.tick_stats, public.stats_live_fold). Bounded by the ships, not by the book. No ship, 0.
  select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a
$body$
  $f$;
  revoke all on function public.funds_aboard() from public, anon, authenticated;

  -- ── 4. THE ONE WRITER OF FUNDS MOVING ──
  execute $f$
create function public.convoy_book(p_stage text, p_fleet uuid, p_player uuid, p_port uuid, p_ducats bigint, p_load bigint default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0309: funds move between a purse and a ship here and nowhere else, three things together: the flow (public.treasury_post, a moved kind), the book row, the live figure. So a purse
-- falls by what set_aside rises by and the world total never moves. Funds aboard are already city money, so a delivery or return is written whatever the purses' switch says
-- (p_always, as a returned escrow), and funds can never be lost to a dark purse. Answers the book row.
declare
  v_id bigint;
begin
  perform public.treasury_post(p_port,
    case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
    case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');
  insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id)
  values (p_stage, p_fleet, p_player, p_port, p_ducats, p_load)
  returning id into v_id;
  perform public.stats_live_add(jsonb_build_object('set_aside', case when p_stage = 'LOADED' then p_ducats else -p_ducats end));
  return v_id;
end
$body$
  $f$;
  revoke all on function public.convoy_book(text, uuid, uuid, uuid, bigint, bigint) from public, anon, authenticated;

  -- ── 5. THE CIRCUIT ──
  execute $f$
create function public.cargo_circuit_plan(p_nation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0309: THE circuit a realm would sail today, read only, so a prod check can ask it. The graph: public.npc_courses, both ways. Shortest paths from the capital and each city by
-- Bellman-Ford over flat arrays, row s of (stops x vertices). The tour: nearest neighbour from the capital, then 2-opt on those distances. Each leg walks the path back and chains
-- its courses. Answers {capital, nm, legs: [{to, code, nm, course}], left_out: [codes no course reaches]}; the last leg ends at the capital. A realm with no city has no legs.
declare
  v_cap   uuid;
  v_ids   uuid[];     -- vertex -> port
  v_ix    jsonb;      -- port -> vertex
  v_s     int[];      -- stop -> vertex; stop 1 is the capital
  v_a     int[];      -- edge: from, to, length, whether it is a stored course read backwards
  v_b     int[];
  v_w     float8[];
  v_rev   boolean[];
  v_d     float8[];   -- row s, vertex v: v_d[(s - 1) * vn + v]
  v_p     int[];      -- the edge that reached it
  vn      int;
  en      int;
  sn      int;
  o       int;
  s       int;
  t       int;
  i       int;
  j       int;
  h       int;
  k       int;
  v_x     float8;
  v_best  float8;
  v_more  boolean;
  v_tour  int[] := array[1];
  v_open  int[] := '{}';
  v_chain int[];
  v_left  jsonb := '[]'::jsonb;
  v_legs  jsonb := '[]'::jsonb;
  v_c     jsonb;
  v_part  jsonb;
  v_nm    float8 := 0;
begin
  select p.id into v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
    raise exception 'E_NO_CAPITAL: nation % is not a great power with a harbour for a capital', p_nation using errcode = 'P0001';
  end if;
  select array_agg(x.id order by x.id) into v_ids
    from (select c.from_port as id from public.npc_courses c union select c.to_port from public.npc_courses c union select v_cap
          union select p.id from public.ports p where p.kind = 'HARBOUR' and public.city_capital(p.id) = v_cap) x;
  select jsonb_object_agg(u.id::text, u.n) into v_ix from unnest(v_ids) with ordinality u(id, n);
  vn := cardinality(v_ids);
  v_s := array[(v_ix ->> v_cap::text)::int]
         || array(select (v_ix ->> p.id::text)::int from public.ports p
                   where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code);
  sn := cardinality(v_s);
  select array_agg((v_ix ->> e.f::text)::int), array_agg((v_ix ->> e.t::text)::int), array_agg(e.nm::float8), array_agg(e.rev)
    into v_a, v_b, v_w, v_rev
    from (select c.from_port as f, c.to_port as t, c.nm, false as rev from public.npc_courses c
          union all select c.to_port, c.from_port, c.nm, true from public.npc_courses c) e;
  en := coalesce(cardinality(v_a), 0);
  v_d := array_fill('Infinity'::float8, array[sn * vn]);
  v_p := array_fill(0, array[sn * vn]);
  for s in 1 .. sn loop
    o := (s - 1) * vn;
    v_d[o + v_s[s]] := 0;
    loop
      v_more := false;
      for i in 1 .. en loop
        v_x := v_d[o + v_a[i]] + v_w[i];
        if v_x < v_d[o + v_b[i]] then
          v_d[o + v_b[i]] := v_x;
          v_p[o + v_b[i]] := i;
          v_more := true;
        end if;
      end loop;
      exit when not v_more;
    end loop;
  end loop;

  for t in 2 .. sn loop
    if v_d[v_s[t]] < 'Infinity'::float8 then
      v_open := v_open || t;
    else
      v_left := v_left || to_jsonb((select p.code from public.ports p where p.id = v_ids[v_s[t]]));
    end if;
  end loop;
  while cardinality(v_open) > 0 loop
    s := v_tour[cardinality(v_tour)];
    v_best := 'Infinity'::float8;
    foreach t in array v_open loop
      v_x := v_d[(s - 1) * vn + v_s[t]];
      if v_x < v_best then
        v_best := v_x;
        h := t;
      end if;
    end loop;
    v_tour := v_tour || h;
    v_open := array_remove(v_open, h);
  end loop;

  k := cardinality(v_tour);
  v_more := k > 3;
  while v_more loop
    v_more := false;
    for i in 2 .. k - 1 loop
      for j in i + 1 .. k loop
        h := case when j = k then 1 else v_tour[j + 1] end;
        if v_d[(v_tour[i - 1] - 1) * vn + v_s[v_tour[j]]] + v_d[(v_tour[i] - 1) * vn + v_s[h]] + 0.01
           < v_d[(v_tour[i - 1] - 1) * vn + v_s[v_tour[i]]] + v_d[(v_tour[j] - 1) * vn + v_s[h]] then
          v_tour := v_tour[1 : i - 1] || array(select v_tour[g] from generate_series(j, i, -1) g) || v_tour[j + 1 : k];
          v_more := true;
        end if;
      end loop;
    end loop;
  end loop;

  if k > 1 then
    for i in 1 .. k loop
      s := v_tour[i];
      t := case when i = k then 1 else v_tour[i + 1] end;
      o := (s - 1) * vn;
      v_chain := '{}';
      h := v_s[t];
      while h <> v_s[s] loop
        j := v_p[o + h];
        v_chain := j || v_chain;
        h := v_a[j];
      end loop;
      v_c := '[]'::jsonb;
      foreach j in array v_chain loop
        if v_rev[j] then
          select jsonb_agg(e.v order by e.n desc) into v_part
            from public.npc_courses c cross join lateral jsonb_array_elements(c.course) with ordinality e(v, n)
           where c.from_port = v_ids[v_b[j]] and c.to_port = v_ids[v_a[j]];
        else
          select c.course into v_part from public.npc_courses c where c.from_port = v_ids[v_a[j]] and c.to_port = v_ids[v_b[j]];
        end if;
        v_c := v_c || v_part;
      end loop;
      v_x := v_d[o + v_s[t]];
      v_nm := v_nm + v_x;
      v_legs := v_legs || jsonb_build_array(jsonb_build_object('to', v_ids[v_s[t]], 'code', (select p.code from public.ports p where p.id = v_ids[v_s[t]]),
                                                               'nm', round(v_x::numeric, 2), 'course', v_c));
    end loop;
  end if;
  return jsonb_build_object('capital', v_cap, 'nm', round(v_nm::numeric, 2), 'legs', v_legs, 'left_out', v_left);
end
$body$
  $f$;
  revoke all on function public.cargo_circuit_plan(uuid) from public, anon, authenticated;

  execute $f$
create function public.cargo_circuit_build(p_nation uuid)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0309: THE one writer of a circuit: public.cargo_circuit_plan written down, a leg's segments read once here (voyage.segments_from_course). Older circuits go when no ship is out on one.
declare
  v_plan jsonb := public.cargo_circuit_plan(p_nation);
  v_id   bigint;
begin
  insert into public.cargo_circuits (nation_id, left_out) values (p_nation, v_plan -> 'left_out') returning id into v_id;
  insert into public.cargo_circuit_legs (circuit_id, ord, to_port, nm, segments)
  select v_id, l.n, (l.v ->> 'to')::uuid, (l.v ->> 'nm')::numeric, voyage.segments_from_course(l.v -> 'course')
    from jsonb_array_elements(v_plan -> 'legs') with ordinality l(v, n);
  delete from public.cargo_circuits c
   where c.nation_id = p_nation and c.id <> v_id
     and not exists (select 1 from public.cargo_ships s where s.circuit_id = c.id);
  return v_id;
end
$body$
  $f$;
  revoke all on function public.cargo_circuit_build(uuid) from public, anon, authenticated;

  -- ── 6. THE LOAD ──
  execute $f$
create function public.cargo_ships_load(p_short jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0309: p_short is public.crown_aid's roster, every city and capital in it already locked, public.crown_call done. Per capital: what its cities need, less what its ships carry,
-- up to its surplus, onto one idle ship of its realm, the lowest ord. One ship a run. No idle ship, or nothing to send: nothing, and the next hourly run asks again. Answers {loaded, ships}.
declare
  k        record;
  v_fleet  uuid;
  v_player uuid;
  v_a      bigint;
  v_loaded bigint := 0;
  v_ships  int := 0;
begin
  for k in select x.cap, sum(x.target - public.treasury_balance(x.port_id))::bigint as need
             from jsonb_to_recordset(p_short) as x(port_id uuid, target bigint, cap uuid)
            group by x.cap
            order by x.cap loop
    v_fleet := null;
    select c.fleet_id, c.player_id into v_fleet, v_player
      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where c.home_port_id = k.cap and f.status = 'DOCKED' and f.port_id = k.cap and c.out_load is null
       and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
       and exists (select 1 from public.cargo_circuit_legs l
                    where l.circuit_id = (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1))
     order by c.ord
     limit 1;
    continue when v_fleet is null;
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.home_port_id = k.cap),
                 greatest(0, public.city_surplus(k.cap)));
    continue when v_a <= 0;
    perform public.convoy_book('LOADED', v_fleet, v_player, k.cap, v_a);
    v_loaded := v_loaded + v_a;
    v_ships := v_ships + 1;
  end loop;
  return jsonb_build_object('loaded', v_loaded, 'ships', v_ships);
end
$body$
  $f$;
  revoke all on function public.cargo_ships_load(jsonb) from public, anon, authenticated;

  -- ── 7. ONE SHIP'S STEP ──
  execute $f$
create function public.cargo_ship_step(p_fleet uuid, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0309: what a cargo ship does in port, in one place. Answers BUSY, AWAY, IDLE, HOME, IN_PORT or SAILED.
--   A wreck: patched where she lies, and she waits convoy_wreck_seconds. Delayed, not lost.
--   A city, the switch on: topped up to public.city_aid_target from what she carries, if it is still of her realm. Off: nothing; funds move by one path.
--   The capital: back from a lap, she returns what is left and is mended. A load not yet gone sails if the switch is on, and comes straight back ashore if it is off.
--   Then, port time done (fleets.ready_at), the next leg. Off she still sails: she is carrying funds home, and the circuit is the only way she knows.
declare
  f       public.fleets%rowtype;
  c       public.cargo_ships%rowtype;
  l       public.cargo_circuit_legs%rowtype;
  v_lit   boolean := public.convoys_on();
  v_load  bigint;
  v_left  bigint;
  v_give  bigint;
  v_cir   bigint;
  v_leg   int;
begin
  select * into f from public.fleets x where x.id = p_fleet for update skip locked;
  if f.id is null then
    return 'BUSY';
  end if;
  if f.status not in ('DOCKED', 'UNABLE_TO_SAIL') then
    return 'AWAY';
  end if;
  select * into c from public.cargo_ships x where x.fleet_id = p_fleet;
  if c.fleet_id is null then
    raise exception 'E_NOT_A_CARGO_SHIP: fleet %', p_fleet using errcode = 'P0001';
  end if;
  select a.load_id, a.aboard into v_load, v_left from public.cargo_ship_aboard(p_fleet) a;
  v_left := coalesce(v_left, 0);

  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
  end if;

  if f.port_id = c.home_port_id then
    if c.out_load is not null or (v_load is not null and not v_lit) then
      if v_left > 0 then
        perform public.convoy_book('RETURNED', p_fleet, c.player_id, f.port_id, v_left, v_load);
      end if;
      update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
      update public.cargo_ships x set out_load = null, circuit_id = null, leg = 0 where x.fleet_id = p_fleet;
      return 'HOME';
    end if;
    if v_load is null then
      return 'IDLE';
    end if;
    v_cir := (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1);
    v_leg := 1;
  else
    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then
      v_give := least(public.city_aid_target(f.port_id) - public.treasury_balance(f.port_id), v_left);
      if v_give > 0 then
        perform public.convoy_book('DELIVERED', p_fleet, c.player_id, f.port_id, v_give, v_load);
      end if;
    end if;
    v_cir := c.circuit_id;
    v_leg := c.leg + 1;
  end if;

  if f.ready_at is not null and f.ready_at > p_now then
    return 'IN_PORT';
  end if;
  select * into l from public.cargo_circuit_legs x where x.circuit_id = v_cir and x.ord = v_leg;
  if l.circuit_id is null then
    raise exception 'E_CARGO_NO_LEG: fleet % has no leg % on circuit %', p_fleet, v_leg, v_cir using errcode = 'P0001';
  end if;
  perform voyage.depart(p_fleet, l.segments, f.port_id, l.to_port, p_now);
  update public.cargo_ships x set circuit_id = v_cir, leg = v_leg, out_load = coalesce(x.out_load, v_load) where x.fleet_id = p_fleet;
  return 'SAILED';
end
$body$
  $f$;
  revoke all on function public.cargo_ship_step(uuid, timestamptz) from public, anon, authenticated;

  -- ── 8. THE MINUTE JOB ──
  execute $f$
create function public.tick_cargo_ships(p_now timestamptz default now(), p_only_nation uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0309: pg_cron byeharu-voyage:cargo-ships, every minute, never in the beat. Lit: one realm a run gets its circuit (none yet, or older than the newest flag change) and any ship it is
-- missing. Then every cargo ship not at sea takes her step, in a block of her own, so one that raises is warned of and the rest go on. Off: no circuit, no ship is made, but a ship that
-- exists still comes home. No ship, no switch: it reads and writes nothing else. p_only_nation narrows a run to one realm: a probe's; the job passes null. Answers {built, made, steps}.
declare
  r       record;
  v_nat   uuid;
  v_built bigint;
  v_made  int := 0;
  v_steps jsonb := '{}'::jsonb;
  v_s     text;
begin
  if public.convoys_on() then
    select g.nation_id into v_nat
      from public.great_powers g
      join public.nations n on n.id = g.nation_id
      join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
      left join lateral (select x.built_at from public.cargo_circuits x where x.nation_id = g.nation_id order by x.id desc limit 1) k on true
     where (p_only_nation is null or g.nation_id = p_only_nation)
       and (k.built_at is null or k.built_at < (select max(a.since) from public.port_allegiance a)
            or (select count(*) from public.cargo_ships c where c.nation_id = g.nation_id) < public.wc_int('convoy_ships_per_nation'))
     order by n.code
     limit 1;
    if v_nat is not null then
      begin
        if not exists (select 1 from public.cargo_circuits x where x.nation_id = v_nat
                        and x.id = (select max(y.id) from public.cargo_circuits y where y.nation_id = v_nat)
                        and x.built_at >= (select max(a.since) from public.port_allegiance a)) then
          v_built := public.cargo_circuit_build(v_nat);
        end if;
        v_made := public.cargo_ships_commission(v_nat);
      exception when others then
        raise warning 'tick_cargo_ships: nation % was not built (SQLSTATE %: %)', v_nat, sqlstate, sqlerrm;
      end;
    end if;
  end if;
  for r in select c.fleet_id from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
            where f.status <> 'SAILING' and (p_only_nation is null or c.nation_id = p_only_nation)
            order by c.nation_id, c.ord loop
    begin
      v_s := public.cargo_ship_step(r.fleet_id, p_now);
      v_steps := v_steps || jsonb_build_object(v_s, coalesce((v_steps ->> v_s)::int, 0) + 1);
    exception when others then
      raise warning 'tick_cargo_ships: fleet % stayed (SQLSTATE %: %)', r.fleet_id, sqlstate, sqlerrm;
      v_steps := v_steps || jsonb_build_object('ERROR', coalesce((v_steps ->> 'ERROR')::int, 0) + 1);
    end;
  end loop;
  return jsonb_build_object('built', v_built, 'made', v_made, 'steps', v_steps);
end
$body$
  $f$;
  revoke all on function public.tick_cargo_ships(timestamptz, uuid) from public, anon, authenticated;

  -- ── 9. THE HUNKS: each occurs once ──
  v_old := array[
$h$-- call passes null. Called with the purses lit (public.city_day). Answers {aided, aid, called, donors}.
$h$,
$h$  v_call := public.crown_call(v_short);
$h$,
$h$  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
$h$,
$h$+ coalesce((select sum(s.accrued) from public.city_shares s), 0),   -- 0224: OPEN requests only (a lapsed escrow went back to the city)
$h$,
$h$            + (select coalesce(sum(sh.accrued), 0) from public.city_shares sh))::bigint as set_aside,
$h$,
$h$  if new.load_id is null then
    return new;
  end if;
$h$];
  v_new := array[
$h$-- call passes null. Called with the purses lit (public.city_day). Answers {aided, aid, called, donors}.
-- 0309: cargo ships lit, the same roster and the same call, then the capital loads a ship (public.cargo_ships_load) and this run pays nobody: one path per state of the switch.
$h$,
$h$  v_call := public.crown_call(v_short);
  if public.convoys_on() then
    return jsonb_build_object('aided', 0, 'aid', 0) || v_call || public.cargo_ships_load(v_short);
  end if;
$h$,
$h$  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or exists (select 1 from public.cargo_ships c where c.player_id = p_player)   -- 0309: a crown's cargo ship docks free in her own crown's cities; she has no purse
$h$,
$h$+ coalesce((select sum(s.accrued) from public.city_shares s), 0) + public.funds_aboard(),   -- 0224: OPEN requests only (a lapsed escrow went back to the city); 0309: and funds aboard a cargo ship
$h$,
$h$            + (select coalesce(sum(sh.accrued), 0) from public.city_shares sh) + public.funds_aboard())::bigint as set_aside,   -- 0309: funds aboard a cargo ship are in no purse
$h$,
$h$  if new.load_id is null then
    if exists (select 1 from public.cargo_ship_aboard(new.fleet_id)) then
      raise exception 'E_CARGO_OPEN: fleet % still carries a load', new.fleet_id using errcode = '23514';   -- 0309: one open load a ship, so public.cargo_ship_aboard stays one load's walk
    end if;
    return new;
  end if;
$h$];
  for v_i in 1 .. array_length(v_old, 1) loop
    v_def := v_cur ->> v_fn[v_i];
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0309 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fn[v_i], v_n;
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_old[v_i], v_new[v_i]));
  end loop;
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i = 2;    -- crown_aid's two hunks are one body
    execute v_cur ->> v_fn[v_i];
  end loop;

  -- ── 10. THE JOB. It runs dark and does nothing, so lighting the switch needs no second step and can never leave a load with no ship sailing ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:cargo-ships', '* * * * *', 'select public.tick_cargo_ships()')$q$;
  end if;

  -- ── 11. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i = 2;
    v_def := replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', '');
    if v_def <> v_cur ->> v_fn[v_i] then
      raise exception '0309 self-assert FAIL: % is not the body this file wrote', v_fn[v_i];
    end if;
  end loop;
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    v_def := v_cur ->> v_fn[v_i];
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0309 self-assert FAIL: hunk % is not in the new body of % exactly once', v_i, v_fn[v_i];
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_new[v_i], v_old[v_i]));
  end loop;
  if v_cur <> v_def0 then
    raise exception '0309 self-assert FAIL: a body does not reverse to its pre-image';
  end if;
  if position('public.funds_aboard()' in pg_get_functiondef('public.tick_stats(timestamp with time zone)'::regprocedure)) = 0
     or position('public.funds_aboard()' in pg_get_functiondef('public.stats_live_fold(timestamp with time zone,boolean)'::regprocedure)) = 0 then
    raise exception '0309 self-assert FAIL: a count of the world leaves out the funds aboard';
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fn[v_i]::regprocedure) <> v_acl0 ->> v_fn[v_i] then
      raise exception '0309 self-assert FAIL: the grants or settings of % moved', v_fn[v_i];
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (v_oids)) <> v_fn_before then
    raise exception '0309 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'convoy_wreck_seconds') <> v_cfg_before then
    raise exception '0309 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w) <> v_word_before then
    raise exception '0309 self-assert FAIL: a word moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0309 self-assert FAIL: a trigger moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:cargo-ships'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0309 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:cargo-ships' and j.schedule = '* * * * *' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0309 self-assert FAIL: the job is not scheduled';
    end if;
  end if;
  if public.convoys_on() or exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo) or exists (select 1 from public.cargo_circuits) or public.funds_aboard() <> 0 then
    raise exception '0309 self-assert FAIL: this world is not dark and empty';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.cargo_circuits'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.cargo_circuit_legs'::regclass) then
    raise exception '0309 self-assert FAIL: a new table has no row security';
  end if;
  if has_table_privilege('anon', 'public.cargo_circuits', 'select') or has_table_privilege('authenticated', 'public.cargo_circuits', 'select')
     or has_table_privilege('anon', 'public.cargo_circuit_legs', 'select') or has_table_privilege('authenticated', 'public.cargo_circuit_legs', 'select') then
    raise exception '0309 self-assert FAIL: a client can reach a circuit';
  end if;
  if exists (select 1 from unnest(array['public.cargo_ship_aboard(uuid)', 'public.funds_aboard()', 'public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)', 'public.cargo_circuit_plan(uuid)',
                                        'public.cargo_circuit_build(uuid)', 'public.cargo_ships_load(jsonb)', 'public.cargo_ship_step(uuid,timestamp with time zone)',
                                        'public.tick_cargo_ships(timestamp with time zone,uuid)']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0309 self-assert FAIL: a client can reach a new function';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.proname) from pg_proc p
       where p.oid in ('public.cargo_circuit_plan(uuid)'::regprocedure, 'public.cargo_ship_aboard(uuid)'::regprocedure, 'public.funds_aboard()'::regprocedure)) <> 'sss' then
    raise exception '0309 self-assert FAIL: a read is not stable';
  end if;

  -- ── 12. THE SELF-ASSERT: a probe realm, every row rolled back ──
  execute replace(v_def0 ->> 'public.crown_aid(uuid)', 'FUNCTION public.crown_aid(', 'FUNCTION pg_temp.crown_aid_0308(');
  execute replace(v_def0 ->> 'public.port_fee(uuid,uuid,numeric)', 'FUNCTION public.port_fee(', 'FUNCTION pg_temp.port_fee_0308(');

  execute $f$
create function pg_temp.purse_0309(p_code text, p_d bigint) returns bigint language sql as $b$
  select public.treasury_post(p.id, 'CROWN_CALL', p_d - public.treasury_balance(p.id), null, null, true) from public.ports p where p.code = p_code
$b$
  $f$;
  execute $f$
create function pg_temp.dock_0309(p_fleet uuid, p_port uuid) returns void language sql as $b$
  update public.voyages set status = 'ARRIVED' where fleet_id = p_fleet and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = p_port, ready_at = null, version = version + 1 where id = p_fleet
$b$
  $f$;
  execute $f$
create function pg_temp.sum_0309(p_nat uuid) returns bigint language sql as $b$
  select coalesce(sum(public.treasury_balance(a.port_id)), 0)::bigint + public.funds_aboard() from public.port_allegiance a where a.nation_id = p_nat
$b$
  $f$;
  execute $f$
create function pg_temp.flows_0309(p_mark bigint) returns jsonb language sql as $b$
  select coalesce(jsonb_object_agg(x.k, x.d), '{}'::jsonb)
    from (select f.kind || ':' || p.code as k, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
           where f.id > p_mark and f.created_at = now() and p.code like 'QW_' group by 1) x
$b$
  $f$;
  execute $f$
create function pg_temp.purses_0309() returns jsonb language sql as $b$
  select jsonb_object_agg(p.code, public.treasury_balance(p.id)) from public.ports p where p.code like 'QW_'
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX9', 'Probe 0309', 'Z', 'QWA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QWA'), ('QWB'), ('QWC'), ('QWD')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap := (select p.id from public.ports p where p.code = 'QWA');
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code like 'QW_';
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) select p.id, 0, 0, world.game_day() from public.ports p where p.code like 'QW_';
    -- A to B, C to B (held the other way round, so it is read backwards), C to A. QWD has no course: left out.
    insert into public.npc_courses (from_port, to_port, course, nm)
    select a.id, b.id, x.course::jsonb, x.nm
      from (values ('QWA', 'QWB', '[[30,-40],[30.5,-40.5]]', 40.0), ('QWC', 'QWB', '[[31,-41],[30.5,-40.5]]', 41.0), ('QWC', 'QWA', '[[31,-41],[30,-40]]', 80.0)) x(f, t, course, nm)
      join public.ports a on a.code = x.f join public.ports b on b.code = x.t;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0309 house', v_nat, 0, true) returning id into v_other;

    -- ── DARK: this file's bodies against the pre-images, one pass each, scene by scene ──
    for v_i in 1 .. 2 loop
      begin
        perform pg_temp.purse_0309('QWA', 200000);
        perform pg_temp.purse_0309('QWB', 1000);
        perform pg_temp.purse_0309('QWC', 100);
        perform pg_temp.purse_0309('QWD', 10000000);
        v_a := case when v_i = 1 then public.crown_aid(v_cap) else pg_temp.crown_aid_0308(v_cap) end;
        v_b := public.tick_cargo_ships(now(), v_nat);
        raise exception using errcode = 'ZX309', message = jsonb_build_object('answer', v_a, 'flows', pg_temp.flows_0309(v_mark), 'purses', pg_temp.purses_0309(),
          'tick', v_b, 'fee', public.port_fee(v_cap, v_other, 1000), 'fee_old', pg_temp.port_fee_0308(v_cap, v_other, 1000),
          'circuits', (select count(*) from public.cargo_circuits), 'ships', (select count(*) from public.cargo_ships), 'book', (select count(*) from public.convoy_cargo))::text;
      exception when sqlstate 'ZX309' then v_res := v_res || jsonb_build_object(case when v_i = 1 then 'dark' else 'dark_old' end, sqlerrm::jsonb); end;
    end loop;

    -- ── LIT: the job builds the circuit and makes the ships ──
    update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
    v_a := public.tick_cargo_ships(now(), v_nat);
    v_fl  := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
    v_fl2 := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 2);
    v_pl  := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl);
    v_x := v_x || jsonb_build_object('tick', v_a, 'ships', (select count(*) from public.cargo_ships c where c.nation_id = v_nat),
      'stops', (select jsonb_agg(p.code order by l.ord) from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id join public.ports p on p.id = l.to_port where k.nation_id = v_nat),
      'left_out', (select k.left_out from public.cargo_circuits k where k.nation_id = v_nat),
      'segments', (select min(jsonb_array_length(l.segments)) from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat));
    v_s1 := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat and l.ord = 1);
    v_s2 := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat and l.ord = 2);

    -- the fee of her house, with the economy closed; a real port call owes nothing and keeps her port time; another house still pays what it did
    v_x := v_x || jsonb_build_object('fee_ship', public.port_fee(v_s1, v_pl, 1000), 'fee_house', public.port_fee(v_s1, v_other, 1000), 'fee_house_old', pg_temp.port_fee_0308(v_s1, v_other, 1000));
    v_a := public.port_call(v_fl, v_cap, v_pl, now(), now());
    v_x := v_x || jsonb_build_object('call', v_a, 'debts', (select count(*) from public.port_fee_debts d where d.player_id = v_pl));
    update public.fleets set ready_at = null where id = v_fl;

    -- ── THE LOAD: the same roster, no CROWN_AID, the world's sum unmoved ──
    perform pg_temp.purse_0309('QWA', 1000000);
    perform pg_temp.purse_0309('QWB', 1000);
    perform pg_temp.purse_0309('QWC', 100);
    perform pg_temp.purse_0309('QWD', 60000);
    v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
    v_sum := pg_temp.sum_0309(v_nat);
    v_day := clock_timestamp();
    v_a := public.crown_aid(v_cap);
    v_b := public.crown_aid(v_cap);
    v_x := v_x || jsonb_build_object('load', v_a, 'load_flows', pg_temp.flows_0309(v_mark), 'again', v_b, 'load_sum', pg_temp.sum_0309(v_nat) - v_sum,
      'load_aboard', (select a.aboard from public.cargo_ship_aboard(v_fl) a), 'load_other', (select count(*) from public.cargo_ship_aboard(v_fl2)), 'funds', public.funds_aboard(),
      'journal_aside', (select count(*) from public.stats_live_deltas d where d.at >= v_day and d.set_aside = 98900),
      'journal_city', (select count(*) from public.stats_live_deltas d where d.at >= v_day and d.cities = -98900));
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('LOADED', v_fl, v_pl, v_cap, 1);
      v_x := v_x || '{"second_load":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('second_load', sqlerrm); end;

    -- ── SHE SAILS, DELIVERS, COMES HOME ──
    v_x := v_x || jsonb_build_object('step_out', public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('step_other', public.cargo_ship_step(v_fl2));
    v_x := v_x || jsonb_build_object('step_at_sea', public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('out_status', (select f.status from public.fleets f where f.id = v_fl), 'out_load', (select (c.out_load is not null) from public.cargo_ships c where c.fleet_id = v_fl),
      'voyage_to', (select p.code from public.voyages o join public.ports p on p.id = o.dest_port_id where o.fleet_id = v_fl and o.status = 'SAILING'));
    perform pg_temp.dock_0309(v_fl, v_s1);
    update public.fleets set ready_at = now() + interval '1 hour' where id = v_fl;
    v_a := to_jsonb(public.cargo_ship_step(v_fl));
    v_b := to_jsonb(public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('step_stop', v_a, 'step_stop2', v_b, 'stop_purse', public.treasury_balance(v_s1), 'stop_sum', pg_temp.sum_0309(v_nat) - v_sum,
      'stop_rows', (select count(*) from public.convoy_cargo k where k.stage = 'DELIVERED' and k.port_id = v_s1));
    update public.fleets set ready_at = null where id = v_fl;
    v_x := v_x || jsonb_build_object('step_on', public.cargo_ship_step(v_fl));
    perform pg_temp.dock_0309(v_fl, v_s2);
    perform pg_temp.purse_0309((select p.code from public.ports p where p.id = v_s2), 60000);    -- a sale filled it meanwhile
    v_sum := pg_temp.sum_0309(v_nat);
    v_x := v_x || jsonb_build_object('step_full', public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('full_rows', (select count(*) from public.convoy_cargo k where k.stage = 'DELIVERED' and k.port_id = v_s2));
    perform pg_temp.dock_0309(v_fl, v_cap);
    update public.ships s set durability = 1 where s.fleet_id = v_fl;
    v_a := to_jsonb(public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('step_home', v_a, 'home_left', (select count(*) from public.cargo_ship_aboard(v_fl)), 'home_sum', pg_temp.sum_0309(v_nat) - v_sum,
      'home_flow', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.created_at = now() and f.kind = 'CONVOY_RETURN' and f.port_id = v_cap),
      'home_hull', (select bool_and(s.durability = (select b.durability from public.ship_base(s.id) b)) from public.ships s where s.fleet_id = v_fl),
      'home_state', (select jsonb_build_object('out', c.out_load, 'leg', c.leg, 'circuit', c.circuit_id) from public.cargo_ships c where c.fleet_id = v_fl));
    v_x := v_x || jsonb_build_object('step_idle', public.cargo_ship_step(v_fl));

    -- ── A WRECK: she delivers, is patched, waits, and is not lost ──
    perform pg_temp.purse_0309((select p.code from public.ports p where p.id = v_s1), 1000);
    perform public.crown_aid(v_cap);
    perform public.cargo_ship_step(v_fl);
    perform pg_temp.dock_0309(v_fl, v_s1);
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fl;
    update public.ships s set durability = 0 where s.fleet_id = v_fl;
    v_a := to_jsonb(public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('step_wreck', v_a, 'wreck_status', (select f.status from public.fleets f where f.id = v_fl),
      'wreck_wait', (select round(extract(epoch from f.ready_at - now())) from public.fleets f where f.id = v_fl),
      'wreck_hull', (select bool_and(s.durability = (select b.durability from public.ship_base(s.id) b)) from public.ships s where s.fleet_id = v_fl),
      'wreck_purse', public.treasury_balance(v_s1));
    perform pg_temp.dock_0309(v_fl, v_cap);
    perform public.cargo_ship_step(v_fl);

    -- ── A CITY THAT CHANGED ITS FLAG MID-LAP IS PASSED, NOT PAID ──
    perform pg_temp.purse_0309((select p.code from public.ports p where p.id = v_s1), 1000);
    perform public.crown_aid(v_cap);
    perform public.cargo_ship_step(v_fl);
    perform pg_temp.dock_0309(v_fl, v_s1);
    update public.port_allegiance set nation_id = (select g.nation_id from public.great_powers g where g.nation_id <> v_nat order by g.nation_id limit 1) where port_id = v_s1;
    v_a := to_jsonb(public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('flag_step', v_a, 'flag_purse', public.treasury_balance(v_s1));
    update public.port_allegiance set nation_id = v_nat where port_id = v_s1;
    perform pg_temp.dock_0309(v_fl, v_cap);
    perform public.cargo_ship_step(v_fl);

    -- ── THE SWITCH GOES OFF MID-LAP: she pays nobody, carries it home, and the instant path pays ──
    perform pg_temp.purse_0309((select p.code from public.ports p where p.id = v_s1), 1000);
    perform public.crown_aid(v_cap);
    perform public.cargo_ship_step(v_fl);
    update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
    perform pg_temp.dock_0309(v_fl, v_s1);
    v_a := to_jsonb(public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('off_step', v_a, 'off_purse', public.treasury_balance(v_s1), 'off_aboard', (select a.aboard from public.cargo_ship_aboard(v_fl) a));
    perform pg_temp.dock_0309(v_fl, v_cap);
    v_x := v_x || jsonb_build_object('off_home', public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('off_left', (select count(*) from public.cargo_ship_aboard(v_fl)));
    v_a := public.crown_aid(v_cap);
    v_x := v_x || jsonb_build_object('off_aid', v_a);
    v_x := v_x || jsonb_build_object('off_paid', public.treasury_balance(v_s1));

    -- ── THE SWITCH GOES OFF WITH A LOAD NOT YET GONE: it comes straight back ashore ──
    update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
    perform pg_temp.purse_0309((select p.code from public.ports p where p.id = v_s1), 1000);
    perform public.crown_aid(v_cap);
    update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
    v_x := v_x || jsonb_build_object('unsailed', public.cargo_ship_step(v_fl));
    v_x := v_x || jsonb_build_object('unsailed_left', (select count(*) from public.cargo_ship_aboard(v_fl)),
      'unsailed_status', (select f.status from public.fleets f where f.id = v_fl));
    update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';

    -- ── THE CAPITAL STILL DRAWS ON ITS NATION, AND A SHORT PURSE LOADS ONLY WHAT IT HOLDS ──
    perform pg_temp.purse_0309('QWA', 12000);
    perform pg_temp.purse_0309('QWD', 10000000);
    v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
    v_a := public.crown_aid(v_cap);
    v_x := v_x || jsonb_build_object('draw', v_a, 'draw_flows', pg_temp.flows_0309(v_mark));
    perform pg_temp.dock_0309(v_fl, v_cap);
    update public.cargo_ships c set out_load = (select a.load_id from public.cargo_ship_aboard(v_fl) a) where c.fleet_id = v_fl;
    perform public.cargo_ship_step(v_fl);
    perform pg_temp.purse_0309('QWA', 10000);
    perform pg_temp.purse_0309('QWD', 60000);
    update public.world_config set value = '0'::jsonb where key = 'crown_call_share';
    v_x := v_x || jsonb_build_object('poor', public.crown_aid(v_cap));
    v_x := v_x || jsonb_build_object('poor_purse', public.treasury_balance(v_cap));

    -- a flag change makes the realm's circuit stale; the ship keeps the lap she began
    perform public.cargo_ship_step(v_fl);
    update public.port_allegiance set since = clock_timestamp() + interval '1 minute' where port_id = v_s2;
    v_a := public.tick_cargo_ships(now(), v_nat);
    v_x := v_x || jsonb_build_object('rebuilt', v_a, 'circuits_now', (select count(*) from public.cargo_circuits k where k.nation_id = v_nat));

    raise exception using errcode = 'ZX309', message = (v_x || v_res)::text;
  exception when sqlstate 'ZX309' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.crown_aid_0308(uuid);
  drop function pg_temp.port_fee_0308(uuid, uuid, numeric);
  drop function pg_temp.purse_0309(text, bigint);
  drop function pg_temp.dock_0309(uuid, uuid);
  drop function pg_temp.sum_0309(uuid);
  drop function pg_temp.flows_0309(bigint);
  drop function pg_temp.purses_0309();

  -- dark: byte for byte the pre-images
  if v_all -> 'dark' -> 'answer' <> v_all -> 'dark_old' -> 'answer' or v_all -> 'dark' -> 'flows' <> v_all -> 'dark_old' -> 'flows' or v_all -> 'dark' -> 'purses' <> v_all -> 'dark_old' -> 'purses'
     or v_all #>> '{dark,flows,CROWN_AID:QWA}' is null then
    raise exception '0309 self-assert FAIL: dark, public.crown_aid is not its pre-image: % %', v_all -> 'dark', v_all -> 'dark_old';
  end if;
  if (v_all #>> '{dark,fee}') <> (v_all #>> '{dark,fee_old}') or (v_all #>> '{dark,fee}')::bigint <= 0 then
    raise exception '0309 self-assert FAIL: dark, public.port_fee is not its pre-image: %', v_all -> 'dark';
  end if;
  if (v_all #>> '{dark,circuits}')::int <> 0 or (v_all #>> '{dark,ships}')::int <> 0 or (v_all #>> '{dark,book}')::int <> 0 or v_all #> '{dark,tick,steps}' <> '{}'::jsonb then
    raise exception '0309 self-assert FAIL: dark, the job did something: %', v_all -> 'dark';
  end if;
  -- the circuit
  if (v_all ->> 'ships')::int <> public.wc_int('convoy_ships_per_nation') or v_all -> 'left_out' <> '["QWD"]'::jsonb
     or v_all -> 'stops' not in ('["QWB", "QWC", "QWA"]'::jsonb, '["QWC", "QWB", "QWA"]'::jsonb) or (v_all ->> 'segments')::int < 1 then
    raise exception '0309 self-assert FAIL: the circuit is not capital, every city, capital: %', v_all;
  end if;
  -- the fee
  if (v_all ->> 'fee_ship')::bigint <> 0 or (v_all ->> 'fee_house') <> (v_all ->> 'fee_house_old') or (v_all ->> 'fee_house')::bigint <= 0 then
    raise exception '0309 self-assert FAIL: a cargo ship paid a dock fee, or another house stopped paying: %', v_all;
  end if;
  if (v_all #>> '{call,owed}')::bigint <> 0 or (v_all ->> 'debts')::int <> 0 or v_all #>> '{call,ready_at}' is null then
    raise exception '0309 self-assert FAIL: a port call left her owing, or took her port time: %', v_all;
  end if;
  -- the load
  if (v_all #>> '{load,aided}')::int <> 0 or (v_all #>> '{load,aid}')::bigint <> 0 or (v_all #>> '{load,loaded}')::bigint <> 98900 or (v_all #>> '{load,ships}')::int <> 1 then
    raise exception '0309 self-assert FAIL: the capital did not load the roster''s need onto one ship: %', v_all;
  end if;
  if v_all -> 'load_flows' <> '{"CONVOY_LOAD:QWA": -98900}'::jsonb then
    raise exception '0309 self-assert FAIL: two paths paid: %', v_all -> 'load_flows';
  end if;
  if (v_all #>> '{again,loaded}')::bigint <> 0 then
    raise exception '0309 self-assert FAIL: a second run loaded what is already aboard: %', v_all -> 'again';
  end if;
  if (v_all ->> 'load_sum')::bigint <> 0 or (v_all ->> 'load_aboard')::bigint <> 98900 or (v_all ->> 'funds')::bigint <> 98900 or (v_all ->> 'load_other')::int <> 0 then
    raise exception '0309 self-assert FAIL: funds aboard are not counted to the ducat: %', v_all;
  end if;
  if (v_all ->> 'journal_aside')::int <> 1 or (v_all ->> 'journal_city')::int <> 1 then
    raise exception '0309 self-assert FAIL: the live figures did not move with the funds: %', v_all;
  end if;
  if v_all ->> 'second_load' not like '%E_CARGO_OPEN%' then
    raise exception '0309 self-assert FAIL: a ship took a second load: %', v_all ->> 'second_load';
  end if;
  -- she sails
  if v_all ->> 'step_out' <> 'SAILED' or v_all ->> 'step_other' <> 'IDLE' or v_all ->> 'step_at_sea' <> 'AWAY' or v_all ->> 'out_status' <> 'SAILING'
     or not (v_all ->> 'out_load')::boolean or v_all ->> 'voyage_to' not in ('QWB', 'QWC') then
    raise exception '0309 self-assert FAIL: she did not take the first leg: %', v_all;
  end if;
  -- delivery
  if (v_all ->> 'stop_purse')::bigint <> 50000 or (v_all ->> 'stop_rows')::int <> 1 or (v_all ->> 'stop_sum')::bigint <> 0 or v_all ->> 'step_stop' <> 'IN_PORT' or v_all ->> 'step_stop2' <> 'IN_PORT' then
    raise exception '0309 self-assert FAIL: the stop was not topped up exactly once to its target: %', v_all;
  end if;
  if v_all ->> 'step_on' <> 'SAILED' or v_all ->> 'step_full' <> 'SAILED' or (v_all ->> 'full_rows')::int <> 0 then
    raise exception '0309 self-assert FAIL: she paid a full city, or did not sail on: %', v_all;
  end if;
  -- home
  if v_all ->> 'step_home' <> 'HOME' or (v_all ->> 'home_left')::int <> 0 or (v_all ->> 'home_sum')::bigint <> 0 or (v_all ->> 'home_flow')::bigint not in (49000, 49900)
     or not (v_all ->> 'home_hull')::boolean or v_all ->> 'step_idle' <> 'IDLE' or v_all #>> '{home_state,out}' is not null or (v_all #>> '{home_state,leg}')::int <> 0 then
    raise exception '0309 self-assert FAIL: what was left did not come home, or she was not mended: %', v_all;
  end if;
  -- the wreck
  if v_all ->> 'step_wreck' <> 'IN_PORT' or v_all ->> 'wreck_status' <> 'DOCKED' or (v_all ->> 'wreck_wait')::numeric <> public.wc_num('convoy_wreck_seconds')
     or not (v_all ->> 'wreck_hull')::boolean or (v_all ->> 'wreck_purse')::bigint <> 50000 then
    raise exception '0309 self-assert FAIL: a wreck was lost, or not delayed: %', v_all;
  end if;
  -- the flag
  if v_all ->> 'flag_step' <> 'SAILED' or (v_all ->> 'flag_purse')::bigint <> 1000 then
    raise exception '0309 self-assert FAIL: a city of another flag was paid: %', v_all;
  end if;
  -- off
  if v_all ->> 'off_step' <> 'SAILED' or (v_all ->> 'off_purse')::bigint <> 1000 or (v_all ->> 'off_aboard')::bigint <> 49000 then
    raise exception '0309 self-assert FAIL: off, a ship paid a city, or stayed: %', v_all;
  end if;
  if v_all ->> 'off_home' <> 'HOME' or (v_all ->> 'off_left')::int <> 0 or (v_all #>> '{off_aid,aid}')::bigint <> 49000 or (v_all ->> 'off_paid')::bigint <> 50000 then
    raise exception '0309 self-assert FAIL: off, the funds did not come home, or the instant path did not pay: %', v_all;
  end if;
  if v_all ->> 'unsailed' <> 'HOME' or (v_all ->> 'unsailed_left')::int <> 0 or v_all ->> 'unsailed_status' <> 'DOCKED' then
    raise exception '0309 self-assert FAIL: off, a load not yet gone did not come back ashore: %', v_all;
  end if;
  -- the draw and the short purse
  if (v_all #>> '{draw,called}')::bigint <= 0 or (v_all -> 'draw_flows' ->> 'CROWN_CALL:QWD')::bigint >= 0 or (v_all #>> '{draw,loaded}')::bigint <> 49000 then
    raise exception '0309 self-assert FAIL: lit, the capital did not draw on its nation: %', v_all;
  end if;
  if (v_all #>> '{poor,called}')::bigint <> 0 or (v_all #>> '{poor,loaded}')::bigint <> 10000 or (v_all ->> 'poor_purse')::bigint <> 0 then
    raise exception '0309 self-assert FAIL: a capital loaded what it does not hold: %', v_all;
  end if;
  if (v_all #>> '{rebuilt,built}') is null or (v_all ->> 'circuits_now')::int <> 2 then
    raise exception '0309 self-assert FAIL: a flag change did not rebuild the circuit, or dropped the one a ship is on: %', v_all;
  end if;

  -- nothing of the probe survives; dark
  if exists (select 1 from public.ports p where p.code like 'QW_') or exists (select 1 from public.nations n where n.code = 'QX9')
     or exists (select 1 from public.players p where p.company_name like 'Crown Cargo %' or p.company_name = 'Probe 0309 house')
     or exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo) or exists (select 1 from public.cargo_circuits)
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0309 self-assert FAIL: the probe left rows behind';
  end if;
  if public.convoys_on() then
    raise exception '0309 self-assert FAIL: the probe left the switch lit';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0309 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0309 self-assert ok: A CARGO SHIP CARRIES FUNDS, DARK. Six hunks on five bodies, each reversed, grants unmoved; nothing else moved; no ship exists. Dark: public.crown_aid and public.port_fee equal their pre-images in a probe scene; the job does nothing. Lit on a probe: stops %, left out %; % d. loaded onto one ship, no CROWN_AID, the sum of purses and funds aboard unmoved; a second run loaded nothing; a stop topped up exactly once, a full city paid nothing, % d. came home, she was mended; no dock fee owed; a wreck delayed, not lost; the switch off mid-lap paid no city and brought the funds home, and the instant path paid; the draw on the nation stands. The real voyage engine, city_day and the stats fold: proof 19, in CI. Printed, never asserted: % ms.',
    v_all -> 'stops', v_all -> 'left_out', v_all #>> '{load,loaded}', v_all ->> 'home_flow', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
