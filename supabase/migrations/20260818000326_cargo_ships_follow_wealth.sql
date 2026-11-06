-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0326 — CARGO SHIPS FOLLOW WEALTH: a country keeps 20 ships if it is the poorest great power, 50 if the richest, and the number moves both ways
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-06: *"bigger country with more cash - max 50, min 20"*, then *"the country wealth will change, so will the cargoship numbers."*
--
-- NOT DARK. There is no switch: this is what the owner asked for, and the old flat number is retired, not kept beside it. Once deployed, the job makes ships, convoy_commission_per_run a minute, until every
-- country has its number. About 260 ships in about 26 minutes on the prod numbers of 2026-11-06. No gold moves: hulls are free and a house's purse is 0, as 0308.
--
-- WHAT THIS FILE ADDS:
--   public.convoy_ships_wanted  THE curve. Cash is the summed public.treasury_balance of the harbours under a flag. Log between richest (max) and the larger of the poorest and richest / convoy_ships_span (min).
--   public.cargo_fleet_sizes    The number a country rests at, one row a great power. public.convoy_fleet_settle alone writes it, so the count has one memory and nothing reads the curve for it.
--   public.convoy_ships_of      THE ONE READER of how many ships a country keeps. One row by key, so a body may read it per ship.
--   public.convoy_fleet_settle  Each convoy_size_read_minutes, the rest moves to the curve when it is more than convoy_ships_band away, or outside min..max. Inside the band it stays: the dead band.
--   cargo_ships.laid_up_at      Null: she sails. Set: LAID UP, see below.
--   public.cargo_ships_in_service  THE ships at work: every reader of "the ships" below reads this, and only the kind (public.fleet_kind and the like) and history read the table.
--   public.cargo_ships_retire   Lays up surplus ships, highest ord first, convoy_retire_per_run a run.
--
-- WHY THE LOG IS ANCHORED, measured on prod (docs/dev-log/2026-11-06-cargo-ships-follow-wealth.md): realm cash runs from 12.9 M to 4.38 B. A straight line leaves six countries at 20-24. A bare log spreads them, but it
-- hangs on the poorest realm, which has swung from 0 to 13 M in two days, and the whole world's count then moves by up to 25 ships an hour. Anchored at richest / 100, that noise falls under the floor and the top barely moves.
--
-- A SHIP IS LAID UP, NEVER DELETED. public.convoy_cargo is append-only and its foreign key names (fleet_id, player_id) in public.cargo_ships; events cascade from her house and are append-only too. So a ship's rows stay, all of
-- them: her row here with laid_up_at, her house (purse 0), her fleet DOCKED at her home, her empty hull, her voyages and her book. public.cargo_ships_in_service leaves her out, so she is off the map (public.sea_houses),
-- out of the figures, out of the job, not loaded and not a home. Row growth is therefore bounded: 50 ships a country, ever. A later rise WAKES the laid-up ship in that ord: the same fleet, the same house, so a slot is reused.
--
-- WHEN A SHIP MAY RETIRE (public.cargo_ships_retire): ord above her country's number, DOCKED at her home, no lap, no load open, no funds aboard, no wreck. A surplus ship takes no new load (public.cargo_ships_load), so she
-- reaches that state: one at sea finishes her lap first. public.cargo_ships_load takes her row FOR UPDATE and the retire reads what is aboard only after holding it, so a load and a lay-up cannot cross.
--
-- THE JOB'S COST. Every docked ship took a step a minute, about 10 ms each on prod; ships only sail when loaded, so nearly all new ships would be idle: 330 idle steps, about 3.5 s a minute, and with convoy_rich_enabled lit each one could
-- also read every harbour of her realm (public.cargo_origins), about 16 s. So an idle ship at home with nothing aboard steps one minute in convoy_idle_every (5), by her ord. Nothing is due on such a step but a change of home, so
-- that can run up to 5 minutes later and nothing else changes; a ship with a load, on a lap, away or wrecked steps every minute as before. 330 idle ships then cost what 66 cost, today's job.
--
-- THE RE-CUTS (hunks of the live bodies at head 0324), each occurs once and reverses to its pre-image, supersede the same bodies:
--   public.sea_houses (2), public.cargo_homes (1), public.cargo_figures (1), public.funds_aboard (1): the ships at work.
--   public.cargo_ships_commission (3): the number from public.convoy_ships_of, a laid-up ship in that ord is woken, at most convoy_commission_per_run a run.
--   public.cargo_ships_load (3): the ships at work, inside her country's number, her row held.
--   public.tick_cargo_ships (6): settle and retire inside the lit branch; a country is short by the ords inside its number; idle ships take turns.
--
-- RETIRED: world_config convoy_ships_per_nation is deleted. No live body reads it; the self-assert scans the catalog.
-- W8 (0328) also cuts cargo bodies and must take its pre-images from this file. public.cargo_ships_in_service names its columns at creation: a column added to public.cargo_ships later must be added to it.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob or job; no body names the old knob; every rest inside min..max; nobody laid up.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 35, scripts/db/proofs/35_fleet_follows_wealth.sql.
-- Mutation controls: scripts/ops/harness/fleet-follows-wealth/proof-0326.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): set convoy_ships_min and convoy_ships_max to one number; surplus ships lay themselves up, nothing strands. To remove: swap this file's old and new.
-- VERSION: 0326 - prod head 0324 (2026-11-06). 0325 (Levels) deploys first and touches none of these bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_meta_before text;
  v_cron_before text;
  v_cron_after  text;
  v_min  int;
  v_max  int;
  c_retired constant text := 'convoy_ships_per_nation';
  c_keys constant text[] := array['convoy_ships_min', 'convoy_ships_max', 'convoy_ships_span', 'convoy_ships_band', 'convoy_size_read_minutes',
                                  'convoy_commission_per_run', 'convoy_retire_per_run', 'convoy_idle_every'];
  c_new_fns constant text[] := array['public.convoy_ships_wanted()', 'public.convoy_ships_of(uuid)', 'public.convoy_fleet_settle(timestamp with time zone)', 'public.cargo_ships_retire(uuid,timestamp with time zone)'];
  c_hunked constant text[] := array[
    'public.sea_houses()', 'public.cargo_homes(uuid)', 'public.cargo_figures()', 'public.funds_aboard()', 'public.cargo_ships_commission(uuid)', 'public.cargo_ships_load(jsonb)',
    'public.tick_cargo_ships(timestamp with time zone,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.cargo_fleet_sizes') is not null or to_regprocedure('public.convoy_ships_of(uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys)) then
    raise exception '0326 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.cargo_origins(uuid)') is null or not exists (select 1 from public.world_config c where c.key = c_retired) then
    raise exception '0326 refuses: 0324 (the origins) or the flat number is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key <> c_retired;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('convoy_ships_min', to_jsonb(20), '0326: cargo ships of the poorest great power. public.convoy_ships_wanted.'),
    ('convoy_ships_max', to_jsonb(50), '0326: cargo ships of the richest great power. public.convoy_ships_wanted.'),
    ('convoy_ships_span', to_jsonb(100), '0326: the curve''s low anchor is the richest realm''s cash over this, or the poorest realm if that is more. Below it a realm is at min. Keeps a nearly broke realm from moving every other realm''s number.'),
    ('convoy_ships_band', to_jsonb(3), '0326: a country''s number moves only when the curve is more than this many ships away. Measured on prod: docs/dev-log/2026-11-06-cargo-ships-follow-wealth.md.'),
    ('convoy_size_read_minutes', to_jsonb(60), '0326: minutes between reads of the curve. Hourly is what convoy_ships_band was measured at.'),
    ('convoy_commission_per_run', to_jsonb(10), '0326: ships made or woken in one run of byeharu-voyage:cargo-ships, one country a run.'),
    ('convoy_retire_per_run', to_jsonb(3), '0326: ships laid up in one run of byeharu-voyage:cargo-ships, the world over.'),
    ('convoy_idle_every', to_jsonb(5), '0326: an idle ship at home takes her step one run in this many, by her ord. 1: every run.');
  delete from public.world_config c where c.key = c_retired;

  -- ── 2. THE SHIP LAID UP, THE SHIPS AT WORK, THE NUMBER AT REST ──
  alter table public.cargo_ships add column laid_up_at timestamptz;
  comment on column public.cargo_ships.laid_up_at is '0326: null, she sails. Set, she is laid up at her home, empty: every row of hers stays, for the book and the history, and public.cargo_ships_in_service leaves her out. public.cargo_ships_retire sets it, public.cargo_ships_commission clears it.';

  create view public.cargo_ships_in_service as
    select c.fleet_id, c.player_id, c.nation_id, c.home_port_id, c.ord, c.created_at, c.circuit_id, c.leg, c.out_load, c.based_at
      from public.cargo_ships c where c.laid_up_at is null;
  comment on view public.cargo_ships_in_service is '0326: THE ships at work: public.cargo_ships less the laid up. Server-only.';
  revoke all on table public.cargo_ships_in_service from public, anon, authenticated;

  create table public.cargo_fleet_sizes (
    nation_id  uuid primary key references public.great_powers(nation_id),
    ships      integer not null check (ships >= 1),
    cash       bigint not null,
    set_at     timestamptz not null default now(),
    read_at    timestamptz not null default now()
  );
  comment on table public.cargo_fleet_sizes is '0326: the number of cargo ships a country rests at, and when the curve was last read. public.convoy_fleet_settle alone writes it, public.convoy_ships_of alone reads ships. Server-only.';
  alter table public.cargo_fleet_sizes enable row level security;
  revoke all on table public.cargo_fleet_sizes from public, anon, authenticated;

  -- ── 3. THE READERS ──
  execute $f$
create function public.convoy_ships_wanted()
returns table (nation_id uuid, cash bigint, ships integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0326: THE curve (owner: "bigger country with more cash - max 50, min 20"). Cash: the summed public.treasury_balance of the harbours under a flag, so a bigger country has more. Log from lo to the richest, whole ships.
  -- lo is the larger of the poorest realm and the richest / convoy_ships_span, so the poorest is always min and a realm near nothing cannot stretch the rest. All level: min. Read by public.convoy_fleet_settle alone.
  with c as (
    select g.nation_id,
           coalesce((select sum(public.treasury_balance(a.port_id)) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
                      where a.nation_id = g.nation_id), 0)::bigint as cash
      from public.great_powers g
  ), b as (
    select max(c.cash)::numeric as hi, greatest(min(c.cash)::numeric, max(c.cash)::numeric / public.wc_num('convoy_ships_span'), 1) as lo from c
  )
  select c.nation_id, c.cash,
         case when b.hi <= b.lo then public.wc_int('convoy_ships_min')
              else public.wc_int('convoy_ships_min')
                   + round((public.wc_int('convoy_ships_max') - public.wc_int('convoy_ships_min')) * ln(greatest(c.cash::numeric, b.lo) / b.lo) / ln(b.hi / b.lo))::integer end
    from c cross join b
$$
  $f$;

  execute $f$
create function public.convoy_ships_of(p_nation uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0326: THE ONE READER of how many cargo ships a country keeps: the number it rests at. A power with no row yet: min, until the next read of the curve.
  select coalesce((select s.ships from public.cargo_fleet_sizes s where s.nation_id = p_nation), public.wc_int('convoy_ships_min'))
$$
  $f$;

  execute $f$
create function public.convoy_fleet_settle(p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0326: the one writer of public.cargo_fleet_sizes. Each convoy_size_read_minutes it reads the curve once. A number moves only when the curve is more than convoy_ships_band from it, or it has left min..max: the dead band, so
-- ordinary swings of a purse never turn ships over. Answers how many numbers moved. Between reads: one indexed read.
declare
  v_n int;
begin
  if (select min(s.read_at) from public.cargo_fleet_sizes s) > p_now - make_interval(mins => public.wc_int('convoy_size_read_minutes')) then
    return 0;
  end if;
  with w as (select * from public.convoy_ships_wanted()),
  u as (
    insert into public.cargo_fleet_sizes as s (nation_id, ships, cash, set_at, read_at)
    select w.nation_id, w.ships, w.cash, p_now, p_now from w
    on conflict (nation_id) do update
       set cash = excluded.cash, read_at = p_now,
           ships = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                          or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                        then excluded.ships else s.ships end,
           set_at = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                           or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                         then p_now else s.set_at end
    returning s.set_at
  )
  select count(*) into v_n from u where u.set_at = p_now;
  return v_n;
end
$$
  $f$;

  execute $f$
create function public.cargo_ships_retire(p_only_nation uuid, p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0326: THE one place a ship is laid up: surplus (ord above public.convoy_ships_of), at her home, DOCKED, no lap, nothing open in the book, no wreck. Highest ord first, convoy_retire_per_run a run. A ship at sea finishes first, and
-- a surplus ship takes no load, so she comes to this. Her row is held first and what is aboard is read after, in its own statement: public.cargo_ships_load holds the same row, so a load and a lay-up cannot cross.
-- Writes laid_up_at and nothing else, so no gold moves, and her fleet, hull, house and book all stand. Answers how many.
declare
  r     record;
  v_max int := public.wc_int('convoy_retire_per_run');
  v_n   int := 0;
begin
  for r in select c.fleet_id
             from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id
            where (p_only_nation is null or c.nation_id = p_only_nation) and c.ord > public.convoy_ships_of(c.nation_id)
              and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null and c.circuit_id is null
            order by c.ord desc, c.nation_id loop
    exit when v_n >= v_max;
    perform 1 from public.cargo_ships x where x.fleet_id = r.fleet_id and x.laid_up_at is null for update skip locked;
    continue when not found or exists (select 1 from public.cargo_ship_aboard(r.fleet_id)) or public.npc_wrecked(r.fleet_id);
    update public.cargo_ships x set laid_up_at = p_now where x.fleet_id = r.fleet_id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$$
  $f$;

  revoke all on function public.convoy_ships_wanted() from public, anon, authenticated;
  revoke all on function public.convoy_ships_of(uuid) from public, anon, authenticated;
  revoke all on function public.convoy_fleet_settle(timestamptz) from public, anon, authenticated;
  revoke all on function public.cargo_ships_retire(uuid, timestamptz) from public, anon, authenticated;

  -- every power's number from the first minute: the curve read now, exact
  perform public.convoy_fleet_settle(now());

  -- ── 4. THE HUNKS ──
  create temp table hunks_0326 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0326 values
  -- sea_houses
  ('public.sea_houses()', 1,
$h$  -- merchants' ink. Her `kind` is the same word as public.fleet_kind. No ship: the merchants' houses and nothing else.
$h$,
$h$  -- merchants' ink. Her `kind` is the same word as public.fleet_kind. No ship: the merchants' houses and nothing else.
  -- 0326: the ships at work: a laid-up ship leaves the sea with her house.
$h$),
  ('public.sea_houses()', 2,
$h$         'CARGO_SHIP'
    from public.cargo_ships c
$h$,
$h$         'CARGO_SHIP'
    from public.cargo_ships_in_service c
$h$),
  -- cargo_homes
  ('public.cargo_homes(uuid)', 1,
$h$          select c.home_port_id, 1000 + c.ord from public.cargo_ships c where c.nation_id = p_nation) x
$h$,
$h$          select c.home_port_id, 1000 + c.ord from public.cargo_ships_in_service c where c.nation_id = p_nation) x
$h$),
  -- cargo_figures
  ('public.cargo_figures()', 1,
$h$  select case when exists (select 1 from public.cargo_ships)
              then jsonb_build_object('cargo_ships', (select count(*) from public.cargo_ships), 'funds_at_sea', public.funds_aboard())
$h$,
$h$  select case when exists (select 1 from public.cargo_ships_in_service)
              then jsonb_build_object('cargo_ships', (select count(*) from public.cargo_ships_in_service), 'funds_at_sea', public.funds_aboard())
$h$),
  -- funds_aboard
  ('public.funds_aboard()', 1,
$h$from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a
$h$,
$h$from public.cargo_ships_in_service c cross join lateral public.cargo_ship_aboard(c.fleet_id) a   -- 0326: a laid-up ship holds nothing
$h$),
  -- cargo_ships_commission
  ('public.cargo_ships_commission(uuid)', 1,
$h$-- 0308: THE one place a cargo ship is made: lit, the ships a great power is missing up to convoy_ships_per_nation, each DOCKED at its capital, by the hands every fleet
$h$,
$h$-- 0308: THE one place a cargo ship is made: lit, the ships a great power is missing up to public.convoy_ships_of, each DOCKED at its capital, by the hands every fleet
$h$),
  ('public.cargo_ships_commission(uuid)', 2,
$h$-- 0324: at her origin (public.cargo_origins): the capital until convoy_rich_enabled.
$h$,
$h$-- 0324: at her origin (public.cargo_origins): the capital until convoy_rich_enabled.
-- 0326: at most convoy_commission_per_run a run. An ord held by a laid-up ship wakes her, where she lies: the same fleet and house, so a slot is reused. She counts in the answer.
$h$),
  ('public.cargo_ships_commission(uuid)', 3,
$h$  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
    continue when exists (select 1 from public.cargo_ships c where c.nation_id = p_nation and c.ord = v_n);
$h$,
$h$  for v_n in 1 .. public.convoy_ships_of(p_nation) loop
    exit when v_made >= public.wc_int('convoy_commission_per_run');
    update public.cargo_ships c set laid_up_at = null where c.nation_id = p_nation and c.ord = v_n and c.laid_up_at is not null;
    if found then
      v_made := v_made + 1;
      continue;
    end if;
    continue when exists (select 1 from public.cargo_ships c where c.nation_id = p_nation and c.ord = v_n);
$h$),
  -- cargo_ships_load
  ('public.cargo_ships_load(jsonb)', 1,
$h$-- public.treasury_try_lock, never waited for (0307), and a busy one is left to the next hour. The load is written at her home, and her home never moves with funds aboard (public.cargo_rebase_to).
$h$,
$h$-- public.treasury_try_lock, never waited for (0307), and a busy one is left to the next hour. The load is written at her home, and her home never moves with funds aboard (public.cargo_rebase_to).
-- 0326: a ship at work inside her country's number, so a surplus ship comes home and retires. Her row is held, so public.cargo_ships_retire cannot lay her up as she loads.
$h$),
  ('public.cargo_ships_load(jsonb)', 2,
$h$      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where public.realm_capital(c.nation_id) = k.cap and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null
$h$,
$h$      from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id
     where public.realm_capital(c.nation_id) = k.cap and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null
       and c.ord <= public.convoy_ships_of(c.nation_id)
$h$),
  ('public.cargo_ships_load(jsonb)', 3,
$h$     order by public.cargo_load_room(c.home_port_id, c.nation_id) desc, c.ord
     limit 1;
$h$,
$h$     order by public.cargo_load_room(c.home_port_id, c.nation_id) desc, c.ord
     limit 1
       for update of c skip locked;
$h$),
  -- tick_cargo_ships
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 1,
$h$-- exists still comes home. No ship, no switch: it reads and writes nothing else. p_only_nation narrows a run to one realm: a probe's; the job passes null. Answers {built, made, steps}.
$h$,
$h$-- exists still comes home. No ship, no switch: it reads and writes nothing else. p_only_nation narrows a run to one realm: a probe's; the job passes null. Answers {built, made, steps}.
-- 0326: lit, the number of each country settles, hourly, and surplus ships lay up: {retired}. An idle ship at home steps one run in convoy_idle_every, by her ord: every other ship, every run.
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 2,
$h$  v_made  int := 0;
  v_steps jsonb := '{}'::jsonb;
$h$,
$h$  v_made  int := 0;
  v_out   int := 0;
  v_every int := greatest(1, public.wc_int('convoy_idle_every'));
  v_turn  bigint := floor(extract(epoch from p_now) / 60)::bigint;
  v_steps jsonb := '{}'::jsonb;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 3,
$h$  if public.convoys_on() then
    select g.nation_id, h.port_id into v_nat, v_start   -- 0324: a circuit from each start of a realm: one row off, the capital's
$h$,
$h$  if public.convoys_on() then
    begin
      perform public.convoy_fleet_settle(p_now);
      v_out := public.cargo_ships_retire(p_only_nation, p_now);
    exception when others then
      raise warning 'tick_cargo_ships: the fleet numbers stayed (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
    select g.nation_id, h.port_id into v_nat, v_start   -- 0324: a circuit from each start of a realm: one row off, the capital's
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 4,
$h$            or (select count(*) from public.cargo_ships c where c.nation_id = g.nation_id) < public.wc_int('convoy_ships_per_nation'))
$h$,
$h$            or (select count(*) from public.cargo_ships_in_service c where c.nation_id = g.nation_id and c.ord <= public.convoy_ships_of(g.nation_id)) < public.convoy_ships_of(g.nation_id))
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 5,
$h$  for r in select c.fleet_id from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
            where f.status <> 'SAILING' and (p_only_nation is null or c.nation_id = p_only_nation)
$h$,
$h$  for r in select c.fleet_id from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id
            where f.status <> 'SAILING' and (p_only_nation is null or c.nation_id = p_only_nation)
              and ((c.ord + v_turn) % v_every = 0   -- 0326: idle ships take turns: a step at rest does nothing but look for a new home
                   or f.status <> 'DOCKED' or f.port_id <> c.home_port_id or c.out_load is not null or exists (select 1 from public.cargo_ship_aboard(c.fleet_id)))
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 6,
$h$  return jsonb_build_object('built', v_built, 'made', v_made, 'steps', v_steps);
$h$,
$h$  return jsonb_build_object('built', v_built, 'made', v_made, 'retired', v_out, 'steps', v_steps);
$h$);

  for v_h in select h.fn from hunks_0326 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0326 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0326 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0326 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0326 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0326 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog and stable reads. No game step. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0326 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys || c_retired)) <> v_cfg_before then
    raise exception '0326 self-assert FAIL: a world_config row moved';
  end if;
  if exists (select 1 from public.world_config c where c.key = c_retired)
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and strpos(pg_get_functiondef(p.oid), c_retired) > 0) then
    raise exception '0326 self-assert FAIL: the flat number is still read';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0326 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0326 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if exists (select 1 from public.cargo_ships c where c.laid_up_at is not null) then
    raise exception '0326 self-assert FAIL: a ship is laid up before any job ran';
  end if;
  v_min := public.wc_int('convoy_ships_min');   -- read here, not in the query: the planner weighs a stable read under this block's first snapshot, before these keys
  v_max := public.wc_int('convoy_ships_max');
  if (select count(*) from public.cargo_fleet_sizes) <> (select count(*) from public.great_powers)
     or exists (select 1 from public.cargo_fleet_sizes s where s.ships not between v_min and v_max)
     or exists (select 1 from public.great_powers g where public.convoy_ships_of(g.nation_id) is distinct from (select s.ships from public.cargo_fleet_sizes s where s.nation_id = g.nation_id)) then
    raise exception '0326 self-assert FAIL: a country has no number inside min..max';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.convoy_ships_wanted()'::regprocedure, 'public.convoy_ships_of(uuid)'::regprocedure]::oid[])) <> 'ss' then
    raise exception '0326 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or has_table_privilege('anon', 'public.cargo_ships_in_service', 'select') or has_table_privilege('authenticated', 'public.cargo_ships_in_service', 'select')
     or has_table_privilege('anon', 'public.cargo_fleet_sizes', 'select') or has_table_privilege('authenticated', 'public.cargo_fleet_sizes', 'select') then
    raise exception '0326 self-assert FAIL: a client can reach something new';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0326 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0326 self-assert ok: CARGO SHIPS FOLLOW WEALTH. % hunks once each and reversing; the flat number is gone; % to % ships a country; no other function, knob or job; no game step ran (proof 35 runs them in CI). % ms.',
    (select count(*) from hunks_0326), (select min(s.ships) from public.cargo_fleet_sizes s), (select max(s.ships) from public.cargo_fleet_sizes s), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0326;
end
$m$;
