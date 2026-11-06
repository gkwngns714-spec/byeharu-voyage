-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0331 — A COUNTRY HAS A NAVY: real ships at regional stations, paid by the capital, sized by the purse, on patrol. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 285, slice W12 of docs/WORLD_POWERS.md (Part 6): *"each country will also have battle ships. they defend or attack pirates"*.
-- This slice gives the ships and their patrol. They call at no battle (W13), hunt nobody (W14, W19) and cannot be attacked yet: public.attack_for still takes a cargo ship only.
--
-- DARK: `navy_enabled` false, read by public.navy_on() alone. public.tick_navy reads that knob, finds no ship, and stops. No ship, station, realm row or flow exists until the owner lights it, so public.navy_ships is empty
-- and every hunk below reads an empty table: the sea reads, the kind, the origin, the wage, the dock fee and the money figures are what they were. Parity is proved, not argued: scripts/ops/harness/navy/dark-scene.sql beside the
-- rich-cities and armed-cargo scenes, before and after this file, every line equal, the map's rows byte for byte.
-- W12 NEEDS W5's CODE ONLY. docs/WORLD_POWERS.md lists W9 (armed cargo lit) as a dependency for money reasons; this builds dark regardless.
--
-- HOW A NAVY SHIP EXISTS: as a cargo ship (0308). A real fleets row with one hull, owned by a house of her own (is_npc, purse 0), a row in public.navy_ships, none in npc_houses or npc_fleets, so she is never tended, invested,
-- gifted or refunded. The voyage engine takes her with no fork. Her class is navy_ship_class (`galion`). As an armed cargo ship (0328): hands from the quay (public.fleet_hands), free stores, no wage, no dock fee.
--
-- SIZE: public.navy_size_for: navy_min + floor(sqrt(purse / navy_purse_unit)), at most navy_max. Purse: public.realm_purse, lifted from public.convoy_ships_wanted, so it has one copy. Read daily into public.navy_realms.
-- A ship above her country's number is NOT scrapped: she finishes, goes home and is laid up. A rising number adds one ship a realm a day (navy_build_hours): the laid-up ship in that ord wakes, else a new hull is built.
-- STATIONS: public.navy_station_plan, STABLE, greedy over public.sea_reaches for the cities the power holds, the capital first. Re-run after any flag change, one realm a run, as 0309 does for circuits. Ship ord n serves station rank n, wrapping.
-- PATROL: public.navy_patrol_build writes one short circuit a station: the navy_patrol_stops nearest harbours within navy_reach_nm, its own flag first, and home. Each leg is read from public.cargo_circuit_plan, the one walker of the
--   course graph, so no second path finder exists. One station a run. public.navy_ship_step sails it.
-- MONEY: nothing is minted, every flow is two sides of a moved kind.
--   BUILD_NAVY  the class's build cost, capital to public.refit_yard(capital), only from public.city_surplus. A CAPITAL THAT CANNOT PAY JUST WAITS: no row, no error, no event; the job asks again next minute. Never a debt, never minted.
--   NAVY_PAY    navy_upkeep_day / 24 a ship, one realm a run, hourly, capital to the harbour she lies at or last called at. Paying herself (she is at the capital) moves nothing.
--   A capital short of the slice pays the ships its surplus covers, lowest ord first. The rest are UNPAID: she goes home and is laid up. Never in debt. No E_CITY_BROKE can be raised by a navy: every outflow is judged from the surplus
--   under the harbour's lock, and a busy capital is simply asked next minute (public.treasury_try_lock, 0307's rule).
-- A WRECK: public.fleet_origin answers her station, so public.npc_wrecked, public.npc_refit_step and voyage.npc_wreck take her with no change: REFIT from the station's purse. Hands and stores come at her next departure.
--
-- THE JOB, BOUNDED FROM THE START (docs/OPS_HEALTH.md section 3). public.tick_navy, pg_cron byeharu-voyage:navy, every minute, never in the beat. At most navy_steps_per_run ships a run, turned by the minute so none starves; one plan step, one
-- ship added and one realm paid a run. Purses are touched last, so a capital's lock is held for the commit only. Cost measured and projected against 75 hulls: docs/dev-log/2026-11-06-a-country-has-a-navy.md.
--
-- THE RE-CUTS (hunks of the live bodies, read on prod at head 0328, and 0330 cuts none of them), each occurs once and reverses to its pre-image; these supersede the same bodies of 0308, 0309, 0310, 0322, 0326 and 0328:
--   public.fleet_kind (2):             she answers NAVY, after the merchant test, so a merchant's read is what it was.
--   public.fleet_origin (2):           her station, third, so a cargo ship's and a merchant's read are what they were.
--   public.sea_houses (2):             her house, kind NAVY, while in service. world.sea_roster and world.sea_traffic need no change: they serve `kind` from here.
--   public.fleet_wage (1):             her upkeep is her hands' wage, as a cargo ship's.
--   public.port_fee (1), public.stats_live_track (1), public.stats_live_fold (1): public.crown_house replaces three copies of one test.
--   public.convoy_ships_wanted (1):    the purse lifted into public.realm_purse. Same statement.
--   public.cargo_upkeep (2):           the stores loop lifted into public.fleet_stores. Same statements.
--   public.cargo_ship_step (1):        the patch lifted into public.fleet_patched. Same statements.
--   public.cargo_figures (1):          the count of navy ships, served only while one is at work, for the Codex.
--   public.client_rpc_entry_points (1): the card.
--
-- NEW: public.navy_ships, navy_ships_in_service (view), navy_realms, navy_stations, navy_patrol_legs. Knobs below. Words BUILD_NAVY, NAVY_PAY (moved). Cron byeharu-voyage:navy. Card world.navy_ship_card.
--
-- SELF-ASSERT: the catalog, stable reads and arithmetic on a probe purse only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob, word or job; the switch off; no row written.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 37, scripts/db/proofs/37_a_country_has_a_navy.sql. Mutation controls: scripts/ops/harness/navy/proof-0331.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `navy_enabled` false: nothing is paid or built, each ship finishes her leg, sails to her station and is laid up. Hulls remain. Nothing strands, no gold moves.
-- VERSION: 0331 - follows W15, 0330 (#536), which is deployed first. It re-cuts voyage.depart, voyage.hazard_roll, voyage.settle, risk_quote, waters_ahead and voyage.sea_mix, none of which this file cuts.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_words_before text;
  v_cron_before  text;
  v_cron_after   text;
  v_class text;
  c_keys constant text[] := array['navy_enabled', 'navy_ship_class', 'navy_max', 'navy_min', 'navy_purse_unit', 'navy_size_read_minutes', 'navy_build_hours',
                                  'navy_upkeep_day', 'navy_reach_nm', 'navy_patrol_stops', 'navy_store_days', 'navy_steps_per_run'];
  c_words constant text[] := array['BUILD_NAVY', 'NAVY_PAY'];
  c_new_fns constant text[] := array[
    'public.navy_on()', 'public.realm_purse(uuid)', 'public.crown_house(uuid)', 'public.fleet_stores(uuid,numeric)', 'public.fleet_patched(uuid,timestamp with time zone)',
    'public.navy_size_for(bigint)', 'public.navy_size_of(uuid)', 'public.navy_read(timestamp with time zone)', 'public.navy_station_plan(uuid)', 'public.navy_station_of(uuid,integer)',
    'public.navy_stations_build(uuid,timestamp with time zone)', 'public.navy_patrol_build(bigint,timestamp with time zone)', 'public.navy_plan_step(timestamp with time zone,uuid)',
    'public.navy_commission(uuid,integer,uuid,uuid,uuid,timestamp with time zone)', 'public.navy_add(timestamp with time zone,uuid)', 'public.navy_pay(timestamp with time zone,uuid)',
    'public.navy_sail(uuid,uuid,jsonb,uuid,bigint,integer,timestamp with time zone)', 'public.navy_ship_step(uuid,timestamp with time zone)', 'public.tick_navy(timestamp with time zone,uuid)',
    'world.navy_ship_card(uuid)'];
  c_hunked constant text[] := array[
    'public.fleet_kind(uuid)', 'public.fleet_origin(uuid)', 'public.sea_houses()', 'public.fleet_wage(uuid,boolean,integer)',
    'public.port_fee(uuid,uuid,numeric)', 'public.stats_live_track()', 'public.stats_live_fold(timestamp with time zone,boolean)', 'public.convoy_ships_wanted()',
    'public.cargo_upkeep(uuid,uuid)', 'public.cargo_ship_step(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()', 'public.cargo_figures()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.navy_ships') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.stats_flow_words w where w.kind = any (c_words)) then
    raise exception '0331 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.cargo_upkeep(uuid,uuid)') is null or to_regprocedure('public.refit_yard(uuid)') is null or to_regprocedure('public.fleet_hands(uuid,uuid)') is null then
    raise exception '0331 refuses: 0322 / 0328 (the refit yard, the upkeep, the quay) are not in this world';
  end if;
  if not exists (select 1 from public.ship_classes c where c.code = 'galion' and c.attack > 0 and c.crew_required > 0 and c.build_cost > 0) then
    raise exception '0331 refuses: no armed class galion with a price in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before
    from public.stats_flow_words w;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS AND THE WORDS ──
  insert into public.world_config (key, value, description) values
    ('navy_enabled', 'false'::jsonb, '0331: THE switch of the navies. False: nothing is built or paid, and a ship finishes her leg, sails to her station and is laid up. Needs the city purses lit. Owner only.'),
    ('navy_ship_class', to_jsonb('galion'::text), '0331: public.ship_classes.code of a navy ship. Her build cost is what a capital pays (BUILD_NAVY).'),
    ('navy_max', to_jsonb(24), '0331: the most ships a country keeps, whatever its purse.'),
    ('navy_min', to_jsonb(2), '0331: the ships every great power is allowed to keep before its purse counts.'),
    ('navy_purse_unit', to_jsonb(25000000), '0331: ships = navy_min + floor(sqrt(realm purse / this)), at most navy_max (public.navy_size_for).'),
    ('navy_size_read_minutes', to_jsonb(1440), '0331: minutes between reads of every country''s purse into public.navy_realms.'),
    ('navy_build_hours', to_jsonb(24), '0331: a country adds at most one ship in this many hours, built or woken.'),
    ('navy_upkeep_day', to_jsonb(60000), '0331: ducats a day a ship, paid hourly by her capital to the harbour she last called at. Moved, kind NAVY_PAY. Her wages and stores count as paid by it.'),
    ('navy_reach_nm', to_jsonb(2400), '0331: sailed miles a station covers (public.navy_station_plan) and a patrol may reach (public.navy_patrol_build).'),
    ('navy_patrol_stops', to_jsonb(3), '0331: harbours on a station''s patrol circuit, before she sails home.'),
    ('navy_store_days', to_jsonb(90), '0331: days of stores a navy ship is topped up to, free, at each departure. Proof 37 checks it against her longest leg and her longest move between stations.'),
    ('navy_steps_per_run', to_jsonb(40), '0331: the most ships public.tick_navy steps in a run. The rest take the next run: the ships are turned by the minute, so none starves.');
  insert into public.stats_flow_words (kind, side, word, ord) values
    ('BUILD_NAVY', 'moved', 'Navy build', 52),
    ('NAVY_PAY', 'moved', 'Navy pay', 53);

  -- ── 2. THE TABLES ──
  create table public.navy_realms (
    nation_id   uuid primary key references public.great_powers(nation_id),
    ships       integer not null default 0 check (ships >= 0),
    purse       bigint,
    read_at     timestamptz,
    stations_at timestamptz,
    added_at    timestamptz,
    paid_at     timestamptz
  );
  comment on table public.navy_realms is '0331: one row a great power: the number it rests at (public.navy_read alone writes `ships`), and when its stations, its last added ship and its last pay were. Server-only.';
  alter table public.navy_realms enable row level security;
  revoke all on table public.navy_realms from public, anon, authenticated;

  create table public.navy_stations (
    id         bigserial primary key,
    nation_id  uuid not null references public.great_powers(nation_id),
    port_id    uuid not null references public.ports(id),
    rank       integer not null check (rank >= 1),
    legs_at    timestamptz,
    retired_at timestamptz
  );
  create unique index navy_stations_current on public.navy_stations (nation_id, port_id) where retired_at is null;
  comment on table public.navy_stations is '0331: where a country bases its ships, in coverage order. retired_at set: the flags moved it off the plan; the row goes when no ship is out on its patrol. Server-only.';
  alter table public.navy_stations enable row level security;
  revoke all on table public.navy_stations from public, anon, authenticated;
  revoke all on sequence public.navy_stations_id_seq from public, anon, authenticated;

  create table public.navy_patrol_legs (
    station_id bigint not null references public.navy_stations(id) on delete cascade,
    ord        integer not null check (ord >= 1),
    to_port    uuid not null references public.ports(id),
    nm         numeric not null,
    segments   jsonb not null,
    primary key (station_id, ord)
  );
  comment on table public.navy_patrol_legs is '0331: a station''s patrol circuit, written once by public.navy_patrol_build. The last leg ends at the station. Server-only.';
  alter table public.navy_patrol_legs enable row level security;
  revoke all on table public.navy_patrol_legs from public, anon, authenticated;

  create table public.navy_ships (
    fleet_id     uuid primary key references public.fleets(id) on delete cascade,
    player_id    uuid not null unique references public.players(id) on delete cascade,
    nation_id    uuid not null references public.great_powers(nation_id),
    ord          integer not null check (ord >= 1),
    station_port uuid not null references public.ports(id),
    mission      text not null default 'PATROL',
    patrol       bigint references public.navy_stations(id),
    leg          integer not null default 0,
    last_port    uuid not null references public.ports(id),
    unpaid_since timestamptz,
    laid_up_at   timestamptz,
    created_at   timestamptz not null default now(),
    unique (nation_id, ord),
    unique (fleet_id, player_id)
  );
  comment on table public.navy_ships is '0331: THE kind. A row here is a navy ship. Laid up is never deleted: her fleet, hull, house and voyages stand, so a slot is reused. Server-only.';
  alter table public.navy_ships enable row level security;
  revoke all on table public.navy_ships from public, anon, authenticated;

  create view public.navy_ships_in_service as
    select n.fleet_id, n.player_id, n.nation_id, n.ord, n.station_port, n.mission, n.patrol, n.leg, n.last_port, n.unpaid_since, n.created_at
      from public.navy_ships n where n.laid_up_at is null;
  comment on view public.navy_ships_in_service is '0331: THE ships at work: public.navy_ships less the laid up. Server-only.';
  revoke all on table public.navy_ships_in_service from public, anon, authenticated;

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.navy_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: THE one reader of navy_enabled. It needs the purses: with no purse to pay from there is no navy, so a hull can never be unpaid for.
  select public.wc('navy_enabled') = 'true'::jsonb and public.city_treasury_on()
$$
  $f$;

  execute $f$
create function public.realm_purse(p_nation uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: THE cash of a country: the summed public.treasury_balance of the harbours under its flag. public.convoy_ships_wanted's own lines, lifted.
  select coalesce((select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
                    where a.nation_id = p_nation), 0)::bigint
$$
  $f$;

  execute $f$
create function public.crown_house(p_player uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: THE answer to whether a house is a crown's own ship, not a merchant and not a company: a cargo ship's (0308) or a navy ship's. Three bodies each held half of this. No dock fee; no merchant in the count.
  select exists (select 1 from public.cargo_ships c where c.player_id = p_player) or exists (select 1 from public.navy_ships n where n.player_id = p_player)
$$
  $f$;

  execute $f$
create function public.fleet_stores(p_fleet uuid, p_days numeric)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: every hull of a crown's fleet topped up to p_days of stores, free (public.stores_topup, the one top-up). public.cargo_upkeep's own lines, lifted.
declare
  s record;
begin
  for s in select x.id, t.water_t, t.food_t
             from public.ships x
            cross join lateral (select public.ship_hold_capacity(x.id) as cap offset 0) hc
            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, hc.cap, p_days, hc.cap * x.store_ratio) t
            where x.fleet_id = p_fleet loop
    if s.water_t > 0 or s.food_t > 0 then
      update public.ships x set water_t = x.water_t + s.water_t, food_t = x.food_t + s.food_t where x.id = s.id;
    end if;
  end loop;
end
$$
  $f$;

  execute $f$
create function public.fleet_patched(p_fleet uuid, p_now timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: a crown's ship that docked wrecked with the refit rule dark: she lies convoy_wreck_seconds, patched free. Delayed, not lost. public.cargo_ship_step's own lines, lifted. Answers when she may sail.
declare
  v_ready timestamptz := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
begin
  update public.fleets set status = 'DOCKED', ready_at = v_ready, version = version + 1 where id = p_fleet;
  perform public.fleet_mend(p_fleet);   -- 0322: the one line
  return v_ready;
end
$$
  $f$;

  execute $f$
create function public.navy_size_for(p_purse bigint)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: THE formula, docs/WORLD_POWERS.md section 6.2: a root, so a realm 720 x as rich keeps 7.5 x the ships. Owner's knobs. A purse below 0 counts as nothing.
  select least(public.wc_int('navy_max'), public.wc_int('navy_min') + floor(sqrt(greatest(p_purse, 0)::numeric / public.wc_num('navy_purse_unit')))::integer)
$$
  $f$;

  execute $f$
create function public.navy_size_of(p_nation uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: THE ONE READER of how many ships a country keeps: the number it rests at. No row yet: 0, until the first read.
  select coalesce((select r.ships from public.navy_realms r where r.nation_id = p_nation), 0)
$$
  $f$;

  execute $f$
create function public.navy_read(p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: the one writer of navy_realms.ships. Every navy_size_read_minutes, every great power's purse is read once. Between reads: one indexed read. Answers how many rows it read.
declare
  v_n int;
begin
  if (select min(r.read_at) from public.navy_realms r) > p_now - make_interval(mins => public.wc_int('navy_size_read_minutes')) then
    return 0;
  end if;
  with w as (select g.nation_id, public.realm_purse(g.nation_id) as purse from public.great_powers g),
  u as (
    insert into public.navy_realms as r (nation_id, ships, purse, read_at)
    select w.nation_id, public.navy_size_for(w.purse), w.purse, p_now from w
    on conflict (nation_id) do update set ships = excluded.ships, purse = excluded.purse, read_at = p_now
    returning 1
  )
  select count(*) into v_n from u;
  return v_n;
end
$$
  $f$;

  execute $f$
create function public.navy_station_plan(p_nation uuid)
returns table (port_id uuid, rank integer, covers integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0331: THE stations a country would keep today, read only, so a prod check can ask it. Greedy over public.sea_reaches for the harbours it holds: its capital first, if it holds it, then whichever harbour covers the most cities
-- not yet covered, by sailed miles within navy_reach_nm; ties by code. It stops when every city is covered. `covers`: the new cities each adds, itself included. No harbour held: no row.
#variable_conflict use_column
declare
  v_cap  uuid := public.realm_capital(p_nation);
  v_ids  uuid[];
  v_code text[];
  v_left text[];
  v_cov  jsonb;
  v_pick uuid;
  v_new  int;
  v_rank int := 0;
begin
  select array_agg(p.id order by p.code), array_agg(p.code order by p.code) into v_ids, v_code
    from public.ports p
   where p.kind = 'HARBOUR' and not p.is_ice_closed and public.port_nation(p.id) = p_nation;
  if v_ids is null then
    return;
  end if;
  v_left := v_code;
  select jsonb_object_agg(a.id::text, (select jsonb_agg(c.code) from unnest(v_code) c(code)
                                        where c.code = a.code or ((s.reaches ->> c.code)::numeric <= public.wc_num('navy_reach_nm'))))
    into v_cov
    from unnest(v_ids, v_code) a(id, code) join public.sea_reaches s on s.port_id = a.id;
  loop
    exit when cardinality(v_left) = 0;
    select c.id, k.n into v_pick, v_new
      from unnest(v_ids, v_code) c(id, code)
      cross join lateral (select count(*)::int as n from jsonb_array_elements_text(v_cov -> c.id::text) e(code) where e.code = any (v_left)) k
     where k.n > 0
     order by (v_rank = 0 and c.id is not distinct from v_cap) desc, k.n desc, c.code
     limit 1;
    exit when v_pick is null;
    v_rank := v_rank + 1;
    port_id := v_pick;
    rank := v_rank;
    covers := v_new;
    return next;
    v_left := array(select l from unnest(v_left) l where not (v_cov -> v_pick::text) ? l);
  end loop;
end
$$
  $f$;

  execute $f$
create function public.navy_station_of(p_nation uuid, p_ord integer)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0331: which station a country's ship of this ord serves: ord n, rank n, wrapping. So a power mans its first min(ships, stations), and the rest double up from the top. Null: no stations yet.
  select s.port_id
    from public.navy_stations s
   where s.nation_id = p_nation and s.retired_at is null
   order by s.rank
   offset (p_ord - 1) % greatest(1, (select count(*) from public.navy_stations x where x.nation_id = p_nation and x.retired_at is null))
   limit 1
$$
  $f$;

  execute $f$
create function public.navy_stations_build(p_nation uuid, p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: public.navy_station_plan written down. The one writer of navy_stations. A station the plan keeps keeps its id and patrol; one it drops is retired, and goes when no ship is out on it. Answers how many stations stand.
declare
  v_ports uuid[];
  v_ranks int[];
begin
  select coalesce(array_agg(x.port_id), '{}'), coalesce(array_agg(x.rank), '{}') into v_ports, v_ranks from public.navy_station_plan(p_nation) x;
  update public.navy_stations s set retired_at = p_now
   where s.nation_id = p_nation and s.retired_at is null and not s.port_id = any (v_ports);
  insert into public.navy_stations as s (nation_id, port_id, rank)
  select p_nation, x.port, x.rank from unnest(v_ports, v_ranks) x(port, rank)
  on conflict (nation_id, port_id) where retired_at is null do update set rank = excluded.rank;
  delete from public.navy_stations s
   where s.nation_id = p_nation and s.retired_at is not null and not exists (select 1 from public.navy_ships n where n.patrol = s.id);
  insert into public.navy_realms as r (nation_id, stations_at) values (p_nation, p_now)
  on conflict (nation_id) do update set stations_at = p_now;
  return cardinality(v_ports);
end
$$
  $f$;

  execute $f$
create function public.navy_patrol_build(p_station bigint, p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: THE one writer of a patrol: from a station to its navy_patrol_stops nearest open harbours within navy_reach_nm, the country's own first, nearest next, and home. Each leg is public.cargo_circuit_plan's, the one walker of the
-- course graph, read once here. A stop no course reaches is skipped. No stop at all: no legs, and she lies at her station. Answers the legs written.
declare
  s      public.navy_stations%rowtype;
  v_from uuid;
  v_to   uuid;
  v_leg  jsonb;
  v_n    int := 0;
begin
  select * into s from public.navy_stations x where x.id = p_station;
  v_from := s.port_id;
  for v_to in select r.port_id
                from voyage.reach_from(s.port_id) r join public.ports p on p.id = r.port_id
               where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> s.port_id and r.nm <= public.wc_num('navy_reach_nm')
               order by coalesce(public.port_nation(r.port_id) = s.nation_id, false) desc, r.nm, r.code
               limit public.wc_int('navy_patrol_stops') loop
    v_leg := public.cargo_circuit_plan(s.nation_id, v_from, v_to) #> '{legs,0}';
    continue when v_leg is null;
    v_n := v_n + 1;
    insert into public.navy_patrol_legs (station_id, ord, to_port, nm, segments)
    values (p_station, v_n, v_to, (v_leg ->> 'nm')::numeric, voyage.segments_from_course(v_leg -> 'course'));
    v_from := v_to;
  end loop;
  if v_n > 0 then
    v_leg := public.cargo_circuit_plan(s.nation_id, v_from, s.port_id) #> '{legs,0}';
    v_n := v_n + 1;
    insert into public.navy_patrol_legs (station_id, ord, to_port, nm, segments)
    values (p_station, v_n, s.port_id, (v_leg ->> 'nm')::numeric, voyage.segments_from_course(v_leg -> 'course'));
  end if;
  update public.navy_stations x set legs_at = p_now where x.id = p_station;
  return v_n;
end
$$
  $f$;

  execute $f$
create function public.navy_plan_step(p_now timestamptz, p_only_nation uuid default null)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: one piece of planning a run: a country whose stations predate the newest flag change, else one station with no patrol yet. Answers STATIONS, PATROL or null. Nothing to do: two indexed reads.
declare
  v_nat uuid;
  v_st  bigint;
begin
  select g.nation_id into v_nat
    from public.great_powers g join public.nations n on n.id = g.nation_id
    left join public.navy_realms r on r.nation_id = g.nation_id
   where (p_only_nation is null or g.nation_id = p_only_nation)
     and (r.stations_at is null or r.stations_at < (select max(a.since) from public.port_allegiance a))
   order by n.code
   limit 1;
  if v_nat is not null then
    perform public.navy_stations_build(v_nat, p_now);
    return 'STATIONS';
  end if;
  select s.id into v_st from public.navy_stations s
   where s.retired_at is null and s.legs_at is null and (p_only_nation is null or s.nation_id = p_only_nation)
   order by s.nation_id, s.rank
   limit 1;
  if v_st is not null then
    perform public.navy_patrol_build(v_st, p_now);
    return 'PATROL';
  end if;
  return null;
end
$$
  $f$;

  execute $f$
create function public.navy_commission(p_nation uuid, p_ord integer, p_capital uuid, p_yard uuid, p_station uuid, p_now timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: THE one place a navy ship is made: the capital pays the yard the class's build cost, moved, and she is laid at her station by the hands every fleet is made by (public.form_fleet, public.commission_ship), crewless: her first
-- departure brings hands and stores. The caller holds the capital's lock and has read the surplus. Her house's purse is 0 and no ledger row is written. Answers her fleet.
declare
  v_class  text := public.wc_text('navy_ship_class');
  v_cost   bigint := (select c.build_cost from public.ship_classes c where c.code = v_class);
  v_code   text := (select n.code from public.nations n where n.id = p_nation);
  v_player uuid;
  v_fleet  uuid;
begin
  perform public.treasury_post(p_capital, 'BUILD_NAVY', -v_cost, null, null);
  perform public.treasury_post(p_yard, 'BUILD_NAVY', v_cost, null, null);
  insert into public.players (company_name, nation_id, ducats, is_npc)
  values (format('Crown Navy %s %s', v_code, p_ord), p_nation, 0, true)
  returning id into v_player;
  v_fleet := public.form_fleet(v_player, format('Navy ship %s', p_ord), p_station);
  perform public.commission_ship(v_player, v_fleet, v_class, format('Navy ship %s', p_ord), true, false);
  insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at)
  values (v_fleet, v_player, p_nation, p_ord, p_station, p_station, p_now);
  return v_fleet;
end
$$
  $f$;

  execute $f$
create function public.navy_add(p_now timestamptz, p_only_nation uuid default null)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: at most one ship added a run, and one a country in navy_build_hours. The lowest ord inside its number that is not at work: laid up, she WAKES where she lies, when her capital can pay her next slice; otherwise a new hull is
-- BUILT, when her capital's surplus covers the class and a yard can be reached. A CAPITAL THAT CANNOT PAY JUST WAITS: nothing is written, and it is asked again next run, so a hull appears the run its capital can pay, and never before.
-- The surplus is read twice: once with no lock, so a poor capital is never locked, and again under the lock, which is what counts. A busy capital is passed over. Answers BUILT, WOKEN or null.
declare
  r       record;
  v_cost  bigint := (select c.build_cost from public.ship_classes c where c.code = public.wc_text('navy_ship_class'));
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_ord   int;
  v_cap   uuid;
  v_st    uuid;
  v_yard  uuid;
  v_need  bigint;
  v_up    boolean;
begin
  for r in select x.nation_id, x.ships
             from public.navy_realms x
            where x.ships > 0 and (p_only_nation is null or x.nation_id = p_only_nation)
              and (x.added_at is null or x.added_at <= p_now - make_interval(hours => public.wc_int('navy_build_hours')))
            order by x.added_at nulls first, x.nation_id loop
    select min(o) into v_ord from generate_series(1, r.ships) o
     where not exists (select 1 from public.navy_ships_in_service n where n.nation_id = r.nation_id and n.ord = o);
    continue when v_ord is null;
    v_up := exists (select 1 from public.navy_ships n where n.nation_id = r.nation_id and n.ord = v_ord);
    v_need := case when v_up then v_slice else v_cost end;
    v_cap := public.realm_capital(r.nation_id);
    v_st := public.navy_station_of(r.nation_id, v_ord);
    continue when v_cap is null or v_st is null or public.city_surplus(v_cap) < v_need;
    continue when not public.treasury_try_lock(v_cap);
    continue when public.city_surplus(v_cap) < v_need;
    if v_up then
      update public.navy_ships n set laid_up_at = null, unpaid_since = null where n.nation_id = r.nation_id and n.ord = v_ord;
    else
      v_yard := public.refit_yard(v_cap);
      continue when v_yard is null;
      perform public.navy_commission(r.nation_id, v_ord, v_cap, v_yard, v_st, p_now);
    end if;
    update public.navy_realms x set added_at = p_now where x.nation_id = r.nation_id;
    return case when v_up then 'WOKEN' else 'BUILT' end;
  end loop;
  return null;
end
$$
  $f$;

  execute $f$
create function public.navy_pay(p_now timestamptz, p_only_nation uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: one country's hour of upkeep a run, the one longest unpaid. Its capital pays each ship at work navy_upkeep_day / 24, to the harbour she lies at or last called at, in order of ord, as far as its surplus goes. A ship it cannot pay
-- is marked unpaid, and she goes home and is laid up (public.navy_ship_step). A ship paid again is marked paid. Never a debt: no slice is owed or carried, and a run that missed an hour is one slice. Paying herself at the capital moves
-- nothing. One row out and one row a harbour, so 46 stations write about 1,300 rows a day, whatever the ships. A busy capital is asked again next run. Answers the ducats moved.
declare
  v_nat   uuid;
  v_cap   uuid;
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_can   bigint;
  v_to    uuid[];
  v_total bigint := 0;
  t       record;
begin
  select r.nation_id into v_nat
    from public.navy_realms r
   where (p_only_nation is null or r.nation_id = p_only_nation)
     and (r.paid_at is null or r.paid_at <= p_now - interval '1 hour')
     and exists (select 1 from public.navy_ships_in_service n where n.nation_id = r.nation_id)
   order by r.paid_at nulls first, r.nation_id
   limit 1;
  if v_nat is null then
    return 0;
  end if;
  v_cap := public.realm_capital(v_nat);
  if not public.treasury_try_lock(v_cap) then
    return 0;
  end if;
  v_can := floor(greatest(public.city_surplus(v_cap), 0) / v_slice);
  with p as (
    select n.fleet_id, row_number() over (order by n.ord) as k, coalesce(f.port_id, n.last_port) as to_port
      from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
     where n.nation_id = v_nat
  ), u as (
    update public.navy_ships n
       set unpaid_since = case when p.k <= v_can then null else coalesce(n.unpaid_since, p_now) end
      from p where p.fleet_id = n.fleet_id
    returning 1
  )
  select coalesce(array_agg(p.to_port) filter (where p.k <= v_can and p.to_port <> v_cap), '{}') into v_to from p;
  v_total := cardinality(v_to) * v_slice;
  if v_total > 0 then
    perform public.treasury_post(v_cap, 'NAVY_PAY', -v_total, null, null);
    for t in select x.port, count(*) * v_slice as d from unnest(v_to) x(port) group by x.port order by x.port loop
      perform public.treasury_post(t.port, 'NAVY_PAY', t.d, null, null);
    end loop;
  end if;
  update public.navy_realms r set paid_at = p_now where r.nation_id = v_nat;
  return v_total;
end
$$
  $f$;

  execute $f$
create function public.navy_sail(p_fleet uuid, p_port uuid, p_segments jsonb, p_to uuid, p_patrol bigint, p_leg integer, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: every leg of a navy ship: hands from the quay above its floor (public.fleet_hands), stores to navy_store_days, then voyage.depart, as every ship. No gold: her upkeep is their price. A quay at its floor gives none and she sails short.
begin
  perform public.fleet_hands(p_fleet, p_port);
  perform public.fleet_stores(p_fleet, public.wc_num('navy_store_days'));
  perform voyage.depart(p_fleet, p_segments, p_port, p_to, p_now);
  update public.navy_ships n set patrol = p_patrol, leg = p_leg, last_port = p_port where n.fleet_id = p_fleet;
  return 'SAILED';
end
$$
  $f$;

  execute $f$
create function public.navy_ship_step(p_fleet uuid, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: what a navy ship does in port, in one place. Answers BUSY, AWAY, WRECK, IN_PORT, IDLE, LAID_UP or SAILED.
--   A wreck: she waits for her station to pay (public.npc_refit_step), or, the refit rule dark, she is patched free where she lies (public.fleet_patched), as a cargo ship.
--   ON DUTY means the switch is on, she is paid, and her ord is inside her country's number. On duty she sails the next leg of her patrol; a patrol done, she is mended free at her station and starts the next.
--   OFF DUTY she leaves her patrol and sails straight to her station, and there she is laid up. So a ship above the number, an unpaid ship and every ship with the switch off end the same way, by one path.
--   Off her patrol's line (a wreck's respawn at her station): the patrol is forgotten. A station that has left the plan: her next home is read as she leaves, so an origin is always a station she is sailing for.
declare
  f       public.fleets%rowtype;
  n       public.navy_ships%rowtype;
  l       public.navy_patrol_legs%rowtype;
  v_duty  boolean;
  v_home  uuid;
  v_st    bigint;
  v_leg   jsonb;
begin
  select * into f from public.fleets x where x.id = p_fleet for update skip locked;
  if f.id is null then
    return 'BUSY';
  end if;
  if f.status not in ('DOCKED', 'UNABLE_TO_SAIL') then
    return 'AWAY';
  end if;
  select * into n from public.navy_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null then
    raise exception 'E_NOT_A_NAVY_SHIP: fleet %', p_fleet using errcode = 'P0001';
  end if;
  if public.npc_wrecked(p_fleet) then
    return 'WRECK';
  end if;
  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := public.fleet_patched(p_fleet, p_now);
  end if;
  if f.ready_at is not null and f.ready_at > p_now then
    return 'IN_PORT';
  end if;
  v_duty := public.navy_on() and n.unpaid_since is null and n.ord <= public.navy_size_of(n.nation_id);

  if n.patrol is not null then
    if v_duty and exists (select 1 from public.navy_patrol_legs x where x.station_id = n.patrol and x.ord = n.leg and x.to_port = f.port_id) then
      select * into l from public.navy_patrol_legs x where x.station_id = n.patrol and x.ord = n.leg + 1;
      if l.station_id is not null then
        return public.navy_sail(p_fleet, f.port_id, l.segments, l.to_port, n.patrol, n.leg + 1, p_now);
      end if;
      perform public.fleet_mend(p_fleet);   -- her patrol is done, at her station: the crown mends her free, as a cargo ship's lap
    end if;
    update public.navy_ships x set patrol = null, leg = 0 where x.fleet_id = p_fleet;
    delete from public.navy_stations s where s.id = n.patrol and s.retired_at is not null
      and not exists (select 1 from public.navy_ships y where y.patrol = s.id);
  end if;

  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
  if f.port_id is distinct from v_home then
    v_leg := public.cargo_circuit_plan(n.nation_id, f.port_id, v_home) #> '{legs,0}';
    if v_leg is null then
      return 'IDLE';   -- no course reaches it: she stays
    end if;
    perform public.navy_sail(p_fleet, f.port_id, voyage.segments_from_course(v_leg -> 'course'), v_home, null, 0, p_now);
    update public.navy_ships x set station_port = v_home where x.fleet_id = p_fleet;   -- her origin moves as she leaves, so a wreck on the way is at the station she was bound for
    return 'SAILED';
  end if;
  if not v_duty then
    perform public.fleet_mend(p_fleet);
    update public.navy_ships x set laid_up_at = p_now where x.fleet_id = p_fleet;
    return 'LAID_UP';
  end if;
  select s.id into v_st from public.navy_stations s where s.nation_id = n.nation_id and s.port_id = v_home and s.retired_at is null;
  select * into l from public.navy_patrol_legs x where x.station_id = v_st and x.ord = 1;
  if l.station_id is null then
    return 'IDLE';   -- her patrol is not written yet, or nothing is in reach
  end if;
  update public.navy_ships x set station_port = v_home where x.fleet_id = p_fleet and x.station_port <> v_home;
  return public.navy_sail(p_fleet, f.port_id, l.segments, l.to_port, v_st, 1, p_now);
end
$$
  $f$;

  execute $f$
create function public.tick_navy(p_now timestamptz default now(), p_only_nation uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0331: pg_cron byeharu-voyage:navy, every minute, never in the beat. Lit: the daily read, one piece of planning, then each ship not at sea and past her port time takes her step, in a block of her own, at most navy_steps_per_run, turned by
-- the minute so none starves. Last, while the run is nearly over, one ship added and one country paid: a capital's lock is held only to the commit. Off: nothing is planned, built or paid, but a ship that exists still goes home.
-- No ship, no switch: one knob read and one read of an empty table. p_only_nation narrows a run to one realm: a probe's; the job passes null. Answers {plan, steps, added, paid}.
declare
  r       record;
  v_lit   boolean := public.navy_on();
  v_turn  bigint := floor(extract(epoch from p_now) / 60)::bigint;
  v_max   int := public.wc_int('navy_steps_per_run');
  v_n     int := 0;
  v_plan  text;
  v_add   text;
  v_paid  bigint := 0;
  v_steps jsonb := '{}'::jsonb;
  v_s     text;
begin
  if v_lit then
    begin
      perform public.navy_read(p_now);
      v_plan := public.navy_plan_step(p_now, p_only_nation);
    exception when others then
      raise warning 'tick_navy: the plan stayed (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
  end if;
  for r in select n.fleet_id from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
            where f.status <> 'SAILING' and (f.ready_at is null or f.ready_at <= p_now) and (p_only_nation is null or n.nation_id = p_only_nation)
            order by (n.ord + v_turn) % greatest(1, v_max), n.nation_id, n.ord loop
    exit when v_n >= v_max;
    v_n := v_n + 1;
    begin
      v_s := public.navy_ship_step(r.fleet_id, p_now);
      v_steps := v_steps || jsonb_build_object(v_s, coalesce((v_steps ->> v_s)::int, 0) + 1);
    exception when others then
      raise warning 'tick_navy: fleet % stayed (SQLSTATE %: %)', r.fleet_id, sqlstate, sqlerrm;
      v_steps := v_steps || jsonb_build_object('ERROR', coalesce((v_steps ->> 'ERROR')::int, 0) + 1);
    end;
  end loop;
  if v_lit then
    begin
      v_add := public.navy_add(p_now, p_only_nation);
    exception when others then
      raise warning 'tick_navy: no ship was added (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
    begin
      v_paid := public.navy_pay(p_now, p_only_nation);
    exception when others then
      raise warning 'tick_navy: nobody was paid (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
  end if;
  return jsonb_build_object('plan', v_plan, 'steps', v_steps, 'added', v_add, 'paid', v_paid);
end
$$
  $f$;

  execute $f$
create function world.navy_ship_card(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0331: EVERYTHING A PLAYER MAY KNOW ABOUT ONE NAVY SHIP, read at a tap. Refuses E_NOT_FOUND for any fleet that is not one, in the same words as for a uuid that names nothing. `to` and `eta` while she sails; `next` her patrol's stops
-- after this one; `mission` is the server's word. Laid up: `laid_up` true. No id of a station or a voyage, and no purse.
declare
  n public.navy_ships%rowtype;
  f public.fleets%rowtype;
  w record;
begin
  select x.* into n from public.navy_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null then
    raise exception 'E_NOT_FOUND: there is no such navy ship' using errcode = 'P0001';
  end if;
  select x.* into f from public.fleets x where x.id = p_fleet;
  select * into w from voyage.where_now(p_fleet);
  return jsonb_build_object(
    'fleet', jsonb_build_object('id', f.id, 'name', f.name, 'status', w.status, 'port', (select p.code from public.ports p where p.id = w.port_id)),
    'nation_code', (select x.code from public.nations x where x.id = n.nation_id),
    'station', (select p.code from public.ports p where p.id = n.station_port),
    'mission', n.mission,
    'laid_up', n.laid_up_at is not null,
    'to', (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.id = w.voyage_id),
    'eta', w.eta,
    'next', (select coalesce(jsonb_agg(x.code order by x.ord), '[]'::jsonb)
               from (select p.code, l.ord from public.navy_patrol_legs l join public.ports p on p.id = l.to_port
                      where l.station_id = n.patrol and l.ord > n.leg order by l.ord limit 5) x),
    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet));
end
$$
  $f$;
  comment on function world.navy_ship_card(uuid) is '0331: one navy ship, read at a tap: her station, mission, where she is bound, her patrol''s next stops, her hull. Refuses E_NOT_FOUND for any other fleet.';

  revoke all on function public.navy_on() from public, anon, authenticated;
  revoke all on function public.realm_purse(uuid) from public, anon, authenticated;
  revoke all on function public.crown_house(uuid) from public, anon, authenticated;
  revoke all on function public.fleet_stores(uuid, numeric) from public, anon, authenticated;
  revoke all on function public.fleet_patched(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_size_for(bigint) from public, anon, authenticated;
  revoke all on function public.navy_size_of(uuid) from public, anon, authenticated;
  revoke all on function public.navy_read(timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_station_plan(uuid) from public, anon, authenticated;
  revoke all on function public.navy_station_of(uuid, integer) from public, anon, authenticated;
  revoke all on function public.navy_stations_build(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_patrol_build(bigint, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_plan_step(timestamptz, uuid) from public, anon, authenticated;
  revoke all on function public.navy_commission(uuid, integer, uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_add(timestamptz, uuid) from public, anon, authenticated;
  revoke all on function public.navy_pay(timestamptz, uuid) from public, anon, authenticated;
  revoke all on function public.navy_sail(uuid, uuid, jsonb, uuid, bigint, integer, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_ship_step(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.tick_navy(timestamptz, uuid) from public, anon, authenticated;
  revoke all on function world.navy_ship_card(uuid) from public, anon;
  grant execute on function world.navy_ship_card(uuid) to authenticated;

  -- ── 4. THE HUNKS ──
  create temp table hunks_0331 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0331 values
  ('public.fleet_kind(uuid)', 1,
$h$  -- 0308: THE answer to what a fleet is: CARGO_SHIP (public.cargo_ships), MERCHANT (public.npc_fleets), else COMPANY, a player's. Null for no such fleet.
$h$,
$h$  -- 0308: THE answer to what a fleet is: CARGO_SHIP (public.cargo_ships), MERCHANT (public.npc_fleets), else COMPANY, a player's. Null for no such fleet.
  -- 0331: NAVY (public.navy_ships), after the merchant test, so a merchant's read is what it was.
$h$),
  ('public.fleet_kind(uuid)', 2,
$h$              when exists (select 1 from public.npc_fleets n where n.fleet_id = f.id) then 'MERCHANT'
$h$,
$h$              when exists (select 1 from public.npc_fleets n where n.fleet_id = f.id) then 'MERCHANT'
              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
$h$),
  ('public.fleet_origin(uuid)', 1,
$h$  -- 0322: THE answer to where an NPC ship is from (docs/WORLD_POWERS.md section 3.3): a cargo ship's home, else her merchant house's. Null for a human's fleet. Navies and pirates join here, W12 and W17.
$h$,
$h$  -- 0322: THE answer to where an NPC ship is from (docs/WORLD_POWERS.md section 3.3): a cargo ship's home, else her merchant house's. Null for a human's fleet. 0331: else a navy ship's station. Pirates join here, W17.
$h$),
  ('public.fleet_origin(uuid)', 2,
$h$                  (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet))
$h$,
$h$                  (select h.home_port_id from public.fleets f join public.npc_houses h on h.player_id = f.player_id where f.id = p_fleet),
                  (select n.station_port from public.navy_ships n where n.fleet_id = p_fleet))
$h$),
  ('public.sea_houses()', 1,
$h$  -- 0326: the ships at work: a laid-up ship leaves the sea with her house.
$h$,
$h$  -- 0326: the ships at work: a laid-up ship leaves the sea with her house.
  -- 0331: a navy ship's house too, kind NAVY: the same row, the same ink.
$h$),
  ('public.sea_houses()', 2,
$h$         'CARGO_SHIP'
    from public.cargo_ships_in_service c
$h$,
$h$         c.kind
    from (select x.player_id, x.nation_id, 'CARGO_SHIP'::text as kind from public.cargo_ships_in_service x
          union all
          select y.player_id, y.nation_id, 'NAVY' from public.navy_ships_in_service y) c
$h$),
  ('public.fleet_wage(uuid,boolean,integer)', 1,
$h$  if v_crew > 0 and public.fleet_kind(p_fleet) = 'CARGO_SHIP' then
$h$,
$h$  if v_crew > 0 and public.fleet_kind(p_fleet) in ('CARGO_SHIP', 'NAVY') then   -- 0331: a navy ship's hands are paid by her upkeep too (public.navy_pay)
$h$),
  ('public.port_fee(uuid,uuid,numeric)', 1,
$h$     or exists (select 1 from public.cargo_ships c where c.player_id = p_player)   -- 0309: a crown's cargo ship docks free in her own crown's cities; she has no purse
$h$,
$h$     or public.crown_house(p_player)   -- 0309: a crown's ship docks free; she has no purse. 0331: a cargo ship's or a navy ship's
$h$),
  ('public.stats_live_track()', 1,
$h$      select p.is_npc and not exists (select 1 from public.cargo_ships c where c.player_id = p.id) into v_npc from public.players p   -- 0310: a cargo ship is at sea, and no merchant
$h$,
$h$      select p.is_npc and not public.crown_house(p.id) into v_npc from public.players p   -- 0310: a crown's ship is at sea, and no merchant
$h$),
  ('public.stats_live_fold(timestamp with time zone,boolean)', 1,
$h$               and not exists (select 1 from public.cargo_ships c where c.player_id = p.id))::bigint as at_sea_merchants   -- 0310: a cargo ship is at sea, and no merchant
$h$,
$h$               and not public.crown_house(p.id))::bigint as at_sea_merchants   -- 0310: a crown's ship is at sea, and no merchant
$h$),
  ('public.convoy_ships_wanted()', 1,
$h$           coalesce((select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
                      where a.nation_id = g.nation_id), 0)::bigint as cash
$h$,
$h$           public.realm_purse(g.nation_id) as cash   -- 0331: lifted
$h$),
  ('public.cargo_upkeep(uuid,uuid)', 1,
$h$  v_pay  bigint;
  s      record;
begin
$h$,
$h$  v_pay  bigint;
begin
$h$),
  ('public.cargo_upkeep(uuid,uuid)', 2,
$h$  for s in select x.id, t.water_t, t.food_t
             from public.ships x
            cross join lateral (select public.ship_hold_capacity(x.id) as cap offset 0) hc
            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, hc.cap, public.wc_num('convoy_store_days'), hc.cap * x.store_ratio) t
            where x.fleet_id = p_fleet loop
    if s.water_t > 0 or s.food_t > 0 then
      update public.ships x set water_t = x.water_t + s.water_t, food_t = x.food_t + s.food_t where x.id = s.id;
    end if;
  end loop;
$h$,
$h$  perform public.fleet_stores(p_fleet, public.wc_num('convoy_store_days'));   -- 0331: these lines, lifted
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);
    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;
    perform public.fleet_mend(p_fleet);   -- 0322: the one line
$h$,
$h$    f.ready_at := public.fleet_patched(p_fleet, p_now);   -- 0331: these lines, lifted
$h$),
  ('public.cargo_figures()', 1,
$h$              else '{}'::jsonb end
$h$,
$h$              else '{}'::jsonb end
         || case when exists (select 1 from public.navy_ships_in_service)   -- 0331: the Codex's navy entry. No ship: nothing, so the read is what it was
                 then jsonb_build_object('navy_ships', (select count(*) from public.navy_ships_in_service)) else '{}'::jsonb end
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'cargo_ship_card',       'uuid'),
$h$,
$h$      ('world',       'cargo_ship_card',       'uuid'),
      -- 0331: one navy ship's card, read at a tap. At the head, as above.
      ('world',       'navy_ship_card',        'uuid'),
$h$);

  for v_h in select h.fn from hunks_0331 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0331 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0331 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0331 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0331 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0331 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE JOB ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:navy', '* * * * *', 'select public.tick_navy()')$q$;
  end if;

  -- ── 6. THE SELF-ASSERT: the catalog, stable reads and arithmetic. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0331 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0331 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> all (c_words)) <> v_words_before then
    raise exception '0331 self-assert FAIL: a flow word moved';
  end if;
  if (select count(*) from public.stats_flow_words w where w.kind = any (c_words) and w.side = 'moved') <> 2 then
    raise exception '0331 self-assert FAIL: a navy flow kind is not moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0331 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:navy'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0331 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:navy' and j.schedule = '* * * * *' and j.command = 'select public.tick_navy()' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0331 self-assert FAIL: the job is not scheduled';
    end if;
  end if;
  if (select c.value from public.world_config c where c.key = 'navy_enabled') <> 'false'::jsonb then
    raise exception '0331 self-assert FAIL: the switch is not off';
  end if;
  if exists (select 1 from public.navy_ships) or exists (select 1 from public.navy_stations) or exists (select 1 from public.navy_realms) or exists (select 1 from public.navy_patrol_legs) then
    raise exception '0331 self-assert FAIL: a row was written dark';
  end if;
  v_class := (select c.value #>> '{}' from public.world_config c where c.key = 'navy_ship_class');   -- from the table: the planner folds a STABLE read on this block's older snapshot, which has no such key yet
  if not exists (select 1 from public.ship_classes k where k.code = v_class and k.attack > 0 and k.crew_required > 0) then
    raise exception '0331 self-assert FAIL: navy_ship_class has no guns or needs no hands';
  end if;
  -- The formula on probe purses, docs/WORLD_POWERS.md section 6.2, with the knobs as they ship. Arithmetic only.
  if (select string_agg(public.navy_size_for(x)::text, ',' order by x)
        from unnest(array[-5, 0, 24999999, 25000000, 100000000, 74000000, 4400000000, 25000000000000]::bigint[]) x) <> '2,2,2,3,3,4,15,24' then
    raise exception '0331 self-assert FAIL: the size formula: %', (select string_agg(public.navy_size_for(x)::text, ',' order by x)
        from unnest(array[-5, 0, 24999999, 25000000, 100000000, 74000000, 4400000000, 25000000000000]::bigint[]) x);
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.navy_on()'::regprocedure, 'public.realm_purse(uuid)'::regprocedure, 'public.crown_house(uuid)'::regprocedure, 'public.navy_size_for(bigint)'::regprocedure,
                                'public.navy_size_of(uuid)'::regprocedure, 'public.navy_station_plan(uuid)'::regprocedure, 'public.navy_station_of(uuid,integer)'::regprocedure, 'world.navy_ship_card(uuid)'::regprocedure]::oid[])) <> 'ssssssss' then
    raise exception '0331 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where f <> 'world.navy_ship_card(uuid)' and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))) then
    raise exception '0331 self-assert FAIL: a new function can be called from a client';
  end if;
  if not has_function_privilege('authenticated', 'world.navy_ship_card(uuid)', 'execute') or has_function_privilege('anon', 'world.navy_ship_card(uuid)', 'execute') then
    raise exception '0331 self-assert FAIL: the card is not exactly authenticated-only';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'navy_ship_card' and e.fn is not null) <> 1 then
    raise exception '0331 self-assert FAIL: the card is not registered';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0331 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0331 self-assert ok: A COUNTRY HAS A NAVY, dark behind navy_enabled. % hunks once each and reversing; no other function, knob, word or job; no row written; no game step ran (proof 37 runs them in CI). % ms.',
    (select count(*) from hunks_0331), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0331;
end
$m$;
