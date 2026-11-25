-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights rounds_enabled)
-- 0518 - ROUNDS, THE CORE  (dark: the owner's switch rounds_enabled, false. Slice `rounds-core`, docs/design/rounds-2026-11-25.md)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R3, R5): an expedition and a combat are the same repeating activity: a ROUND has a cost (food, water, crew), a
--   yield and a log line; it stops at the MIN or at the number set, and she goes to the nearest city with what she has.
--
-- ONE SHAPE, ONE SETTLE FROM TIME:
--   public.round_works     what can be done, as data: the kind (combat, sea), the skill and its level, a round's seconds, its food and water
--                          (days of her crew), its crew loss (per cent, less a little a level, never under a floor), and the switch it waits
--                          for. EMPTY here: 0521 and 0523 write the works. No figure of a round is written in a function.
--   public.round_runs      one row a fleet that is out (or was last out): what was frozen at Send (`terms`), the rounds booked, the log. A run's
--                          state is this row and the clock alone.
--   public.round_clock     HOW MANY WHOLE ROUNDS HAVE PASSED: e = the seconds from the start to the instant or the stop, n = floor(e / a round's),
--                          u = what is left. THE LAND'S OWN ARITHMETIC (0455, public.land_progress) is moved here, so a trip ashore and a round at
--                          sea are counted by one function (two hunks; its answers are asserted equal to the letter).
--   public.round_terms     what a Send would freeze: the cost of one round and THE MOST ROUNDS by arithmetic: the food and the water above the
--                          reserve, the hands above MIN, the number she set, the 12 h away cap: the least of them, and why. So a late settle and a
--                          prompt one give one answer, and nothing needs asking on a clock.
--   public.round_settle    THE ONE WRITER: books the rounds that have passed and are not booked (stores, hands, the log) in one write, and past the
--                          last one she lies in her base harbour again, DOCKED.
-- WHERE SHE IS. She works the sea of the harbour she puts out from (her base: so it is the nearest city, and the passage out is none). Her status is
--   ROUNDS (a new word of fleets_status_check; port_id stays her base): every door that asks for a docked fleet refuses her as it does one in the
--   yard (REPAIRING), no order runs, no merchant or pirate reads her as sailing; public.fleet_census says `sea` through the one rule
--   (public.fleet_state_of, one hunk). cmd.advance (the catch-up of every read of hers) settles her when her stop time has passed (one hunk).
-- NOT HERE (0519): the doors, the served read, the stop settings as a job, the jobs' tick. Nothing is wired to a beat: tick_arrivals is not touched.
-- AN ALLOWANCE, NOT A COST: a round's yield is `carry` in the row, empty until 0522 to 0524.
-- ROWS. Dark: none. Lit: one round_runs row a fleet that was ever sent (bounded by the fleets a company may own), one row update a settle, one
--   ROUNDS_DONE event a run. -- budget: 1 to 3 row updates and 1 event a run; 0 rows a minute while nobody presses; no cron job, no index beyond the
--   primary key. -- retention: none, bounded by construction: one row a fleet, gone with it.
-- LOCKS: fleets_status_check dropped and added (ACCESS EXCLUSIVE on fleets for a check of about a thousand rows), CREATE TABLE x2 (a foreign key to
--   fleets), CREATE FUNCTION x9, CREATE OR REPLACE x3 by hunks. TIME: a second. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): rounds_enabled false: no Send; a fleet that is out is called in by its own settle. FULL: a migration reversing the
--   hunks, dropping the functions and tables, and the old check (refused while a fleet's status is ROUNDS).
-- SELF-ASSERT: hunks once and reversing; no other function moved; grants unmoved; the new functions server only; the clock the land's, over 3,000
--   instants of seeded arithmetic; the land's progress of a probe party, before and after, equal. THE PROBE (rolled back; its own company, its own
--   work, its own stores and hands): no dice, market or other company is asked anything. Proof 222 plays it.
-- VERSION: 0518 (after 0517; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.land_progress(uuid,timestamp with time zone)', 'public.fleet_census(uuid)', 'cmd.advance(uuid,timestamp with time zone)'];
  c_new    constant text[] := array['public.rounds_on()', 'public.round_clock(timestamptz,numeric,timestamptz,timestamptz)', 'public.round_level(uuid,text)',
                                    'public.round_terms(uuid,text,jsonb)', 'public.round_progress(uuid,timestamptz)', 'public.round_settle(uuid,timestamptz)',
                                    'public.round_send_for(uuid,uuid,text,jsonb,timestamptz)', 'public.round_home_for(uuid,uuid,timestamptz)', 'public.round_stores(uuid,numeric,numeric,integer)'];
  c_knobs  constant text[] := array['rounds_enabled', 'round_away_hours'];
  c_ua     constant uuid := '00000000-0518-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or to_regclass('public.round_runs') is not null then
    raise exception '0518 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.level_of(text,numeric)', 'public.ship_base(uuid)', 'public.fleet_state_of(boolean,boolean,boolean,boolean)']) f
              where to_regprocedure(f) is null) then
    raise exception '0518 refuses: the land (0455) or the census (0448) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0518 (fn text primary key, def text) on commit drop;
  insert into pre_0518 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE LAND'S SUM, before and after (a temp function: a probe party with set terms, read at set instants) ──
  execute $f$
create function pg_temp.land_0518(p_uid uuid)
returns jsonb
language plpgsql
as $body$
declare
  v_pl  uuid;
  v_id  uuid;
  v_out jsonb := '[]'::jsonb;
  v_t   constant timestamptz := '2026-11-25 00:00:00+00';
  k     numeric;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0518', 'PRT');
  v_id := public.land_party(v_pl);
  update public.land_parties set action = (select a.code from public.land_actions a order by a.ord limit 1), region_id = (select r.id from public.regions r order by r.code limit 1),
         started_at = v_t, touched_at = v_t, booked = 3,
         terms = '{"s": 40, "m": 15, "a": 7.3, "p": 5, "trip": 146.5, "xp": 1, "carry": 2}'::jsonb
   where id = v_id;
  foreach k in array array[-5, 0, 39, 54.9, 60, 120, 146.4, 146.5, 147, 1000, 9999.25, 43199, 43200, 43201, 90000] loop
    v_out := v_out || jsonb_build_array(public.land_progress(v_id, v_t + make_interval(secs => k::double precision)));
  end loop;
  update public.land_parties set terms = terms || '{"last": 4}'::jsonb where id = v_id;
  foreach k in array array[100, 585.9, 586, 5000] loop
    v_out := v_out || jsonb_build_array(public.land_progress(v_id, v_t + make_interval(secs => k::double precision)));
  end loop;
  update public.land_parties set terms = terms || jsonb_build_object('home_at', v_t + interval '300 seconds') where id = v_id;
  foreach k in array array[100, 301] loop
    v_out := v_out || jsonb_build_array(public.land_progress(v_id, v_t + make_interval(secs => k::double precision)));
  end loop;
  return v_out;
end
$body$
  $f$;
  begin
    raise exception using errcode = 'ZX518', message = pg_temp.land_0518(c_ua)::text;
  exception when sqlstate 'ZX518' then v_b := sqlerrm::jsonb;
  end;

  -- ── 3. THE KNOBS, THE STATUS, THE TABLES ──
  insert into public.world_config (key, value, description) values
    ('rounds_enabled', 'false'::jsonb,
     '0518: THE SWITCH (the owner''s). true: a fleet may be sent on rounds (public.round_works: combat, sea expeditions; each work waits for its own switch too). false: no Send; a fleet that is out comes in by its own stop.'),
    ('round_away_hours', to_jsonb(12), '0518: the most hours a fleet stays out on rounds after a Send (the land''s 12).');
  alter table public.fleets drop constraint fleets_status_check,
    add constraint fleets_status_check check (status = any (array['DOCKED', 'ANCHORED', 'SAILING', 'REPAIRING', 'ADRIFT', 'UNABLE_TO_SAIL', 'IN_BATTLE', 'ROUNDS'])),
    add constraint fleets_rounds_have_a_base check (status <> 'ROUNDS' or port_id is not null);
  -- retention: none, bounded by construction: data, a handful of rows
  create table public.round_works (
    code       text primary key check (code ~ '^[a-z_]+$'),
    ord        int not null,
    kind       text not null check (kind in ('combat', 'sea')),
    word       text not null,
    skill      text not null references public.level_skills(code),
    level      int not null default 1 check (level >= 1),
    seconds    int not null check (seconds >= 60),
    food_days  numeric not null check (food_days >= 0),
    water_days numeric not null check (water_days >= 0),
    crew_pct   numeric not null check (crew_pct >= 0 and crew_pct <= 20),
    crew_less  numeric not null default 0 check (crew_less >= 0),
    crew_least numeric not null default 0 check (crew_least >= 0),
    yield      jsonb not null default '{}',
    lit_by     text
  );
  comment on table public.round_works is
    '0518: WHAT A FLEET MAY DO IN ROUNDS, as data (docs/design/rounds-2026-11-25.md). A round takes `seconds`; it eats food_days and water_days of her crew; it loses crew_pct per cent of the crew she left with, less crew_less a level of `skill`, never under crew_least. `yield` is what later slices read. lit_by: the switch it waits for. Server only.';
  -- retention: none, bounded by construction: one row a fleet, gone with it
  create table public.round_runs (
    fleet_id   uuid primary key references public.fleets(id) on delete cascade,
    player_id  uuid not null,
    work       text not null references public.round_works(code),
    sea_id     uuid not null,
    state      text not null check (state in ('out', 'home')),
    sent_at    timestamptz not null,
    stop_at    timestamptz not null,
    booked     int not null default 0 check (booked >= 0),
    terms      jsonb not null,
    stop       jsonb not null default '{}',
    carry      jsonb not null default '{}',
    log        jsonb not null default '[]' check (jsonb_array_length(log) <= 20),
    ended      text,
    updated_at timestamptz not null default now()
  );
  comment on table public.round_runs is
    '0518: A FLEET ON ROUNDS: one row a fleet, all the state there is. terms: frozen at Send (seconds, food, water and crew a round, most: the most rounds, why: what stops them). booked: the rounds settled. log: the last 20 rounds, newest last ({r, at, crew, ...}). ended: why the last run ended. One writer: public.round_send_for, round_settle, round_home_for.';
  alter table public.round_works enable row level security;
  alter table public.round_runs enable row level security;
  revoke all on table public.round_works, public.round_runs from public, anon, authenticated;

  -- ── 4. THE RULES ──
  execute $f$
create function public.rounds_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0518: THE SWITCH, read once: world_config rounds_enabled.
  select public.wc('rounds_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_clock(p_start timestamptz, p_secs numeric, p_at timestamptz, p_stop timestamptz)
returns table (e numeric, n bigint, u numeric)
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0518: HOW MANY WHOLE TURNS HAVE PASSED (0455's sum, moved here): e = the seconds from the start to the instant, or to the stop, never under 0;
  -- n = the whole turns of p_secs in it; u = the seconds into the next. public.land_progress (a trip ashore) and public.round_progress read it.
  select z.e, floor(z.e / p_secs)::bigint, z.e - floor(z.e / p_secs) * p_secs
    from (select greatest(0, extract(epoch from least(p_at, p_stop) - p_start)) as e) z
$body$
  $f$;
  execute $f$
create function public.round_level(p_player uuid, p_skill text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0518: her company's level in a work's skill: a level counted from the record at the level she was last paid for (public.house_level_marks, as
  -- 0468 reads one), a level raised by doing on its own curve. A company with neither: 1.
  select coalesce(case when s.kept = 'record' then (select m.level from public.house_level_marks m where m.player_id = p_player and m.track = p_skill)
                       else (select public.level_of(p_skill, x.xp) from public.level_xp x where x.player_id = p_player and x.skill = p_skill) end, 1)
    from public.level_skills s where s.code = p_skill
$body$
  $f$;
  execute $f$
create function public.round_terms(p_fleet uuid, p_work text, p_stop jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0518: WHAT A SEND WOULD FREEZE for this fleet, as she is: {seconds, crew0, crew (hands a round, a fraction), food, water (tuns a round), min (the
-- hands she keeps), most (the most rounds), why (food | water | crew | rounds | cap: what stops them), level}. The most rounds is arithmetic: what is
-- aboard above the reserve (p_stop.days days of stores, default 2) over a round's cost; the hands above MIN (p_stop.crew, never under what her hulls
-- ask) over a round's loss; p_stop.rounds; the away cap. Writes nothing.
declare
  w       public.round_works%rowtype;
  v_pl    uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_crew  int;
  v_need  int;
  v_food  numeric;
  v_water numeric;
  v_lv    int;
  v_min   int;
  v_days  numeric := greatest(0, coalesce((p_stop->>'days')::numeric, 2));
  v_c     numeric;
  v_fr    numeric;
  v_wr    numeric;
  v_fd    numeric := public.wc_num('food_per_crew_day');
  v_wd    numeric := public.wc_num('water_per_crew_day');
  v_most  numeric;
  v_why   text;
begin
  select * into w from public.round_works x where x.code = p_work;
  if w.code is null or v_pl is null then
    return null;
  end if;
  select coalesce(sum(s.crew), 0), coalesce(sum(c.crew_required), 0), coalesce(sum(s.food_t), 0), coalesce(sum(s.water_t), 0)
    into v_crew, v_need, v_food, v_water
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;
  v_lv  := public.round_level(v_pl, w.skill);
  v_min := greatest(v_need, coalesce((p_stop->>'crew')::int, 0));
  v_c   := round(v_crew * greatest(w.crew_least, w.crew_pct - w.crew_less * (v_lv - 1)) / 100, 4);
  v_fr  := round(v_crew * v_fd * w.food_days, 4);
  v_wr  := round(v_crew * v_wd * w.water_days, 4);
  select m.n, m.why into v_most, v_why
    from (values (case when v_fr > 0 then floor(greatest(0, v_food - v_days * v_crew * v_fd) / v_fr) end, 'food', 1),
                 (case when v_wr > 0 then floor(greatest(0, v_water - v_days * v_crew * v_wd) / v_wr) end, 'water', 2),
                 (case when v_c > 0 then floor(greatest(0, v_crew - v_min) / v_c) end, 'crew', 3),
                 ((p_stop->>'rounds')::numeric, 'rounds', 4),
                 (floor(public.wc_num('round_away_hours') * 3600 / w.seconds), 'cap', 5)) m(n, why, o)
   where m.n is not null order by m.n, m.o limit 1;
  return jsonb_build_object('work', w.code, 'kind', w.kind, 'seconds', w.seconds, 'crew0', v_crew, 'crew', v_c, 'food', v_fr, 'water', v_wr,
                            'min', v_min, 'days', v_days, 'most', v_most::int, 'why', v_why, 'level', v_lv);
end
$body$
  $f$;
  execute $f$
create function public.round_progress(p_fleet uuid, p_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0518: WHERE A RUN STANDS at an instant: {state, rounds (passed), new (not booked), most, next_at (the next round's end), stop_at, over, why}. The
-- rounds are public.round_clock's, never past the run's stop. Writes nothing.
declare
  r   public.round_runs%rowtype;
  c   record;
begin
  select * into r from public.round_runs x where x.fleet_id = p_fleet;
  if r.fleet_id is null then
    return null;
  end if;
  if r.state = 'home' then
    return jsonb_build_object('state', 'home', 'rounds', r.booked, 'new', 0, 'ended', r.ended);
  end if;
  select * into c from public.round_clock(r.sent_at, (r.terms->>'seconds')::numeric, p_at, r.stop_at);
  return jsonb_build_object('state', 'out', 'rounds', c.n, 'new', greatest(0, c.n - r.booked), 'most', (r.terms->>'most')::int,
                            'next_at', case when p_at < r.stop_at then r.sent_at + make_interval(secs => ((c.n + 1) * (r.terms->>'seconds')::numeric)::double precision) end,
                            'stop_at', r.stop_at, 'over', p_at >= r.stop_at, 'why', r.terms->>'why');
end
$body$
  $f$;
  execute $f$
create function public.round_stores(p_fleet uuid, p_food numeric, p_water numeric, p_crew integer)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0518: THE COST OF THE ROUNDS BOOKED, taken from her hulls: food and water in proportion to what each holds, the hands from the hull with the most
-- above what she asks (so no hull falls under it while the fleet stays above MIN). Never under nought.
declare
  v_f    numeric;
  v_w    numeric;
  v_left int := p_crew;
  h      record;
begin
  select coalesce(sum(s.food_t), 0), coalesce(sum(s.water_t), 0) into v_f, v_w from public.ships s where s.fleet_id = p_fleet;
  if p_food > 0 or p_water > 0 then
    update public.ships s
       set food_t = case when v_f > 0 then greatest(0, round(s.food_t - p_food * s.food_t / v_f, 3)) else s.food_t end,
           water_t = case when v_w > 0 then greatest(0, round(s.water_t - p_water * s.water_t / v_w, 3)) else s.water_t end
     where s.fleet_id = p_fleet;
  end if;
  if v_left > 0 then
    for h in select s.id, s.crew - c.crew_required as over from public.ships s join public.ship_classes c on c.id = s.class_id
              where s.fleet_id = p_fleet order by s.crew - c.crew_required desc, s.id loop
      exit when v_left <= 0 or h.over <= 0;
      update public.ships s set crew = s.crew - least(v_left, h.over) where s.id = h.id;
      v_left := v_left - least(v_left, h.over);
    end loop;
  end if;
end
$body$
  $f$;
  execute $f$
create function public.round_settle(p_fleet uuid, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0518: THE ONE WRITER OF A RUN. Books the rounds that have passed and are not booked (public.round_progress): food, water and hands
-- (public.round_stores; the hands by the running fraction, so n rounds at once or one by one lose the same), and one log line a round (the last 20
-- kept). Past the last round: the run is over, she lies DOCKED in her base, and one ROUNDS_DONE event says what it took. A run that is home: nothing.
declare
  r      public.round_runs%rowtype;
  p      jsonb;
  v_n    int;
  v_c    numeric;
  v_hand int;
  v_log  jsonb;
  v_over boolean;
begin
  select * into r from public.round_runs x where x.fleet_id = p_fleet for update;
  if r.fleet_id is null or r.state <> 'out' then
    return jsonb_build_object('new', 0, 'over', false);
  end if;
  p := public.round_progress(p_fleet, p_at);
  v_n := (p->>'new')::int;
  v_over := (p->>'over')::boolean;
  if v_n > 0 then
    v_c := (r.terms->>'crew')::numeric;
    v_hand := (floor(v_c * (r.booked + v_n)) - floor(v_c * r.booked))::int;
    perform public.round_stores(p_fleet, (r.terms->>'food')::numeric * v_n, (r.terms->>'water')::numeric * v_n, v_hand);
    select coalesce(jsonb_agg(z.l order by z.o), '[]'::jsonb) into v_log
      from (select q.l, q.o from (
              select e.l, e.o from jsonb_array_elements(r.log) with ordinality e(l, o)
              union all
              select jsonb_build_object('r', g, 'at', r.sent_at + make_interval(secs => (g * (r.terms->>'seconds')::numeric)::double precision),
                                        'crew', (floor(v_c * g) - floor(v_c * (g - 1)))::int), 1000000 + g
                from generate_series(greatest(r.booked + 1, r.booked + v_n - 19), r.booked + v_n) g) q
             order by q.o desc limit 20) z;
    r.booked := r.booked + v_n;
    r.log := v_log;
  end if;
  if v_n = 0 and not v_over then
    return jsonb_build_object('new', 0, 'over', false);
  end if;
  update public.round_runs set booked = r.booked, log = r.log, state = case when v_over then 'home' else 'out' end,
         ended = case when v_over then r.terms->>'why' else ended end, updated_at = now()
   where fleet_id = p_fleet;
  if v_over then
    update public.fleets set status = 'DOCKED', busy_until = null, version = version + 1 where id = p_fleet and status = 'ROUNDS';
    perform public.emit_event(r.player_id, 'ROUNDS_DONE', jsonb_build_object('fleet', (select f.name from public.fleets f where f.id = p_fleet), 'work', r.work,
              'rounds', r.booked, 'why', r.terms->>'why', 'food', round((r.terms->>'food')::numeric * r.booked, 2), 'water', round((r.terms->>'water')::numeric * r.booked, 2),
              'crew', floor((r.terms->>'crew')::numeric * r.booked)));
  end if;
  return jsonb_build_object('new', v_n, 'over', v_over, 'hands', coalesce(v_hand, 0));
end
$body$
  $f$;
  execute $f$
create function public.round_send_for(p_player uuid, p_fleet uuid, p_work text, p_stop jsonb, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0518: SEND A FLEET ON ROUNDS (server only; the door is 0519's). Every check, then one row and her status. Refusals raise 'E_CODE: sentence'. The sea
-- she works is her harbour's own; the rounds there can be are public.round_terms'; none at all is refused with what is short.
declare
  f   public.fleets%rowtype;
  w   public.round_works%rowtype;
  t   jsonb;
  v_sea uuid;
begin
  if not public.rounds_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'rounds are not open yet');
  end if;
  select * into f from public.fleets x where x.id = p_fleet for update;
  if f.id is null or f.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  select * into w from public.round_works x where x.code = p_work;
  if w.code is null or (w.lit_by is not null and public.wc(w.lit_by) is distinct from 'true'::jsonb) then
    perform cmd.refuse('E_NOT_IN_USE', 'that work is not open yet');
  end if;
  v_sea := (select h.sea_id from public.ports h where h.id = f.port_id and h.kind = 'HARBOUR');
  if f.status <> 'DOCKED' or v_sea is null then
    perform cmd.refuse('E_NOT_DOCKED', format('%s must lie in a harbour of the sea she is to work', f.name));
  end if;
  if exists (select 1 from public.orders o where o.fleet_id = p_fleet and o.status in ('pending', 'active')) or exists (select 1 from public.standing_routes r where r.fleet_id = p_fleet) then
    perform cmd.refuse('E_BUSY', format('%s has orders waiting', f.name));
  end if;
  if not exists (select 1 from public.ships s where s.fleet_id = p_fleet) or exists (select 1 from public.ships s where s.fleet_id = p_fleet and s.is_flagship and s.durability <= 0) then
    perform cmd.refuse('E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail');
  end if;
  if exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet and s.crew < c.crew_required) then
    perform cmd.refuse('E_CREW_SHORT', format('%s is short of crew', f.name));
  end if;
  if public.round_level(p_player, w.skill) < w.level then
    perform cmd.refuse('E_LEVEL', format('%s asks %s level %s', w.word, w.skill, w.level));
  end if;
  t := public.round_terms(p_fleet, p_work, coalesce(p_stop, '{}'::jsonb));
  if (t->>'most')::int < 1 then
    perform cmd.refuse('E_ROUND_SHORT', case t->>'why' when 'food' then 'not enough food for one round' when 'water' then 'not enough water for one round'
                                                       when 'crew' then 'not enough crew above the least for one round' else 'no round to do' end);
  end if;
  insert into public.round_runs as r (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, booked, terms, stop)
  values (p_fleet, p_player, p_work, v_sea, 'out', p_at, p_at + make_interval(secs => ((t->>'most')::int * (t->>'seconds')::numeric)::double precision), 0, t, coalesce(p_stop, '{}'::jsonb))
  on conflict (fleet_id) do update set player_id = excluded.player_id, work = excluded.work, sea_id = excluded.sea_id, state = 'out', sent_at = excluded.sent_at,
        stop_at = excluded.stop_at, booked = 0, terms = excluded.terms, stop = excluded.stop, carry = '{}', log = '[]', ended = null, updated_at = now();
  update public.fleets set status = 'ROUNDS', busy_until = p_at + make_interval(secs => ((t->>'most')::int * (t->>'seconds')::numeric)::double precision), version = version + 1
   where id = p_fleet;
  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'terms', t);
end
$body$
  $f$;
  execute $f$
create function public.round_home_for(p_player uuid, p_fleet uuid, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0518: CALL HER IN (server only): the rounds that have passed are booked and she lies in her base (her base is in the sea she works: no passage).
-- A round under way is given up. Not out: refused.
declare
  r public.round_runs%rowtype;
  v_n int;
begin
  select * into r from public.round_runs x where x.fleet_id = p_fleet and x.player_id = p_player for update;
  if r.fleet_id is null or r.state <> 'out' then
    perform cmd.refuse('E_NOT_SAILING', 'she is not out on rounds');
  end if;
  perform public.round_settle(p_fleet, p_at);
  select x.booked into v_n from public.round_runs x where x.fleet_id = p_fleet;
  update public.round_runs set state = 'home', ended = coalesce(ended, 'called'), updated_at = now() where fleet_id = p_fleet;
  update public.fleets set status = 'DOCKED', busy_until = null, version = version + 1 where id = p_fleet and status = 'ROUNDS';
  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'rounds', v_n);
end
$body$
  $f$;
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNKS ──
  create temp table hunks_0518 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0518 values
  ('public.land_progress(uuid,timestamp with time zone)', 1,
$h$  v_e := greatest(0, extract(epoch from least(p_at, v_stop) - lp.started_at));
  v_trips := floor(v_e / v_trip);
$h$,
$h$  select c.e, c.n, c.u into v_e, v_trips, v_u from public.round_clock(lp.started_at, v_trip, p_at, v_stop) c;   -- 0518: the one sum of turns passed
$h$),
  ('public.land_progress(uuid,timestamp with time zone)', 2,
$h$  v_u := v_e - v_trips * v_trip;
$h$,
$h$  -- 0518: v_u is the clock's
$h$),
  ('public.fleet_census(uuid)', 1,
$h$                               f.status = 'SAILING'),
$h$,
$h$                               f.status in ('SAILING', 'ROUNDS')),   -- 0518: a fleet on rounds is at sea
$h$),
  ('cmd.advance(uuid,timestamp with time zone)', 1,
$h$    if f.status = 'REPAIRING' then
$h$,
$h$    if f.status = 'ROUNDS' then   -- 0518: her rounds are settled once their stop has passed; till then nothing runs
      exit when f.busy_until is null or f.busy_until > p_now;
      perform public.round_settle(p_fleet, p_now);
      exit when exists (select 1 from public.fleets x where x.id = p_fleet and x.status = 'ROUNDS');
      continue;
    end if;
    if f.status = 'REPAIRING' then
$h$);

  for x in select distinct h.fn from hunks_0518 h loop
    v_pre := (select p.def from pre_0518 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0518 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0518 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0518 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0518 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0518 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0518 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0518 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.rounds_on() then
    raise exception '0518 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0518 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 7. THE LAND'S SUM IS ITSELF; the probe ──
  begin
    raise exception using errcode = 'ZX518', message = pg_temp.land_0518(c_ua)::text;
  exception when sqlstate 'ZX518' then v_d := sqlerrm::jsonb;
  end;
  drop function pg_temp.land_0518(uuid);
  if v_d is distinct from v_b or jsonb_array_length(v_b) <> 21 then
    raise exception '0518 self-assert FAIL: the land''s sum moved: % / %', left(v_b::text, 600), left(v_d::text, 600);
  end if;
  if exists (select 1 from generate_series(1, 3000) g cross join lateral (select g * 37.77 as s, 60 + (g % 900) as t) z
              cross join lateral public.round_clock('2026-01-01Z', z.t, '2026-01-01Z'::timestamptz + make_interval(secs => z.s::double precision), '2026-01-01Z'::timestamptz + interval '20 hours') c
             where c.e <> least(z.s, 72000) or c.n <> floor(least(z.s, 72000) / z.t) or c.u <> least(z.s, 72000) - c.n * z.t) then
    raise exception '0518 self-assert FAIL: the clock';
  end if;
  begin
    declare
      v_pl uuid; v_fl uuid; t jsonb; a jsonb; b jsonb; v_t timestamptz := now(); r record; v_c0 int; v_f0 numeric; v_w0 numeric; v_f1 numeric; v_w1 numeric; i int; v_c1 int;
      v_state text; v_dark text;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0518', 'PRT');
      select f.id into v_fl from public.fleets f where f.player_id = v_pl;
      insert into public.round_works (code, ord, kind, word, skill, seconds, food_days, water_days, crew_pct, crew_less, crew_least)
      values ('probe_work', 1, 'sea', 'Probe', 'exploration', 600, 0.4, 0.4, 2, 0.05, 0.3);
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 10, water_t = 20 where s.fleet_id = v_fl;
      begin
        perform public.round_send_for(v_pl, v_fl, 'probe_work', '{}', v_t);
      exception when sqlstate 'P0001' then v_dark := sqlerrm;
      end;
      update public.world_config set value = 'true'::jsonb where key = 'rounds_enabled';
      select sum(s.crew), sum(s.food_t), sum(s.water_t) into v_c0, v_f0, v_w0 from public.ships s where s.fleet_id = v_fl;
      t := public.round_terms(v_fl, 'probe_work', '{"rounds": 25, "days": 0}');
      -- 25 rounds at once, and 25 one by one, from the same world: the same stores, hands, log
      for i in 1 .. 2 loop
        begin
          perform public.round_send_for(v_pl, v_fl, 'probe_work', '{"rounds": 25, "days": 0}', v_t);
          v_state := public.fleet_state(v_fl);
          if i = 2 then
            for k in 1 .. (t->>'most')::int loop
              perform public.round_settle(v_fl, v_t + make_interval(secs => k * 600.0));
            end loop;
          end if;
          perform cmd.advance(v_fl, v_t + make_interval(secs => ((t->>'most')::int * 600 + 30)::double precision));
          select zr.* into r from public.round_runs zr where zr.fleet_id = v_fl;
          select sum(s.crew), sum(s.food_t), sum(s.water_t) into v_c1, v_f1, v_w1 from public.ships s where s.fleet_id = v_fl;
          a := jsonb_build_object('state', r.state, 'booked', r.booked, 'crew', v_c1, 'food', round(v_f1, 1), 'water', round(v_w1, 1), 'log', jsonb_array_length(r.log), 'last', r.log->-1->'r',
                                  'logcrew', (select sum((e->>'crew')::int) from jsonb_array_elements(r.log) e), 'status', (select f.status from public.fleets f where f.id = v_fl), 'fstate', v_state, 'ended', r.ended);
          raise exception using errcode = 'ZY518', message = a::text;
        exception when sqlstate 'ZY518' then
          if i = 1 then b := sqlerrm::jsonb; else a := sqlerrm::jsonb; end if;
        end;
      end loop;
      raise exception using errcode = 'ZX518', message = jsonb_build_object('terms', t, 'one', b, 'many', a, 'c0', v_c0, 'f0', v_f0, 'w0', v_w0, 'dark', v_dark)::text;
    end;
  exception when sqlstate 'ZX518' then v_l := sqlerrm::jsonb;
  end;
  if v_l->>'dark' !~ '^E_NOT_IN_USE' or (v_l #>> '{terms,most}')::int < 1 or (v_l #>> '{terms,most}')::int > 25
     or v_l->'one' is distinct from v_l->'many' or v_l #>> '{one,state}' <> 'home' or v_l #>> '{one,status}' <> 'DOCKED' or v_l #>> '{one,fstate}' <> 'sea'
     or v_l #>> '{one,booked}' <> v_l #>> '{terms,most}' or v_l #>> '{one,ended}' <> v_l #>> '{terms,why}'
     or (v_l #>> '{one,log}')::int <> least(20, (v_l #>> '{terms,most}')::int)
     or (v_l->>'c0')::int - (v_l #>> '{one,crew}')::int <> floor((v_l #>> '{terms,crew}')::numeric * (v_l #>> '{terms,most}')::int)
     or abs((v_l->>'f0')::numeric - (v_l #>> '{one,food}')::numeric - (v_l #>> '{terms,food}')::numeric * (v_l #>> '{terms,most}')::int) > 0.3 then
    raise exception '0518 self-assert FAIL: the probe run: %', v_l;
  end if;

  -- ── 8. NOTHING OF THE PROBE SURVIVES ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0518') or public.rounds_on() or exists (select 1 from public.round_works)
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0518 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0518 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0518 self-assert ok: ROUNDS, THE CORE (dark). Four hunks once and reversing in three bodies; no other function moved; nine new functions server only. The land''s sum equal over 21 readings. Probe (rolled back): % rounds (why %) at once or one by one leave the same: %. % ms.',
    v_l #>> '{terms,most}', v_l #>> '{terms,why}', v_l->'one', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0518;
  drop table pre_0518;
end $m$;
