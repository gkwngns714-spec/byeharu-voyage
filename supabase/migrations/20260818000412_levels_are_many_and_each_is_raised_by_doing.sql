-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0412 - LEVELS ARE MANY, AND EACH IS RAISED BY DOING  (docs/LEVELS.md; the first cut: the mechanism and ten levels)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE OWNER, 2026-11-14: "levels we only have trading, exploration, combat. like rs3, i want diverse skills related to this game"
-- and: "with exp table, exp info, with benefits when leveling up, what activity needs done etc."
--
-- WHAT THIS FILE MAKES
--   THE LIST      public.level_skills (data): every level a company has, in the order the page shows them. Ten rows:
--                 trading, exploration, combat (kept 'record': counted by public.player_progress from the append-only record, 0069, and
--                 NOT moved: that reader stays the one authority for them and every gate that asks them is untouched), and seven new ones
--                 (kept 'book'): supplies, weather, shipbuilding, requests, craft, routes, investment.
--   THE RATES     public.level_activities (data): what raises each level and by how much. A 'record' level's figures are the knobs
--                 public.player_progress already reads (named in xp_knob / per_knob, so no figure is typed twice); a 'book' level's
--                 figures are the row's own. public.level_activity_terms() is the one reading of both: the writer and the page use it.
--   THE BOOK      public.level_xp (a company's experience in a 'book' level, and what it earned today) and public.level_book
--                 (append-only, a chain: every grant, with what gave it; the once-ever key lives here).
--   THE WRITER    public.level_grant(player, activity, units, key): THE ONE WRITER of experience. A merchant leaves after one players
--                 probe; level_skills_on false: nothing. floor(units / per x xp), at most the row's most_xp, inside the level's cap a
--                 day (public.real_day, the one day); past the cap nothing is written. A level crossed pays the same gift a Trading
--                 level pays (rep_level_per_level x the level, public.reputation_credit kind 'level', key level:<code>:<L>) and
--                 emits the same LEVEL_UP event {track, level, reputation} (0356).
--   THE ARRIVAL   public.level_arrival(player, voyage): one read of the voyage's own days (public.voyage_events, by its key):
--                 days fed (no short-rations day, at least voyage_nm miles, into a port), storm days, rough days. Keyed by voyage.
--   THE READ      public.level_skills_card(player, progress) and public.level_benefits(code): for every level its points, level, where
--                 the next begins, today against the cap, the activities with their figures, what each level gives, and the five newest
--                 grants; and the curve once (the experience at which each level begins). Served by world.levels(), the page's one read.
--   THE HOOKS     nine hunks, one line each, sliced from the live bodies (pg_get_functiondef at head 0407, LF), each once and reversing:
--                 voyage.settle (inside 0127's players-only block: a merchant's arrival gains nothing), cmd.do_build, cmd.do_repair,
--                 cmd.run_fulfil, cmd.do_make, cmd.forge_good, cmd.standing_route_close_lap, public.invest_for, world.levels.
--                 cmd.do_sell and cmd.do_buy are NOT cut: a sale and a buy cost what they cost before.
--   THE KNOB      level_skills_on true. False stops every grant at once (the rollback with no file).
--
-- WHAT A LEVEL GIVES, AND ONLY WHAT IS APPLIED: the Reputation gift (above) for all ten; and, served from the rules that already apply
--   them, for the three counted from the record: the ceiling of her captains' level in that track (public.captain_level), the level a
--   captain's promotion asks (captain_grades.promote_level), a fleet at the Trading rungs (fleet_room_levels), and the title
--   (the lower of Trading and Exploration; title_names, and the seas a title opens). No new stat bonus is made here: see docs/LEVELS.md.
-- NO BACK-PAY: a 'book' level starts at nothing for everyone at this deploy (as 0352 and 0356 decided). The three old levels keep theirs.
-- ANTI-ABUSE: a merchant earns nothing. Every 'book' level has a cap a day. A hull and a lap pay once (the key). A lap pays only at a
--   gain. Days fed pay only for a voyage of 100 nm into a port with no hungry day. Repairs, shares, requests, made and forged goods cost
--   coin or cargo that does not come back.
-- COST: a sale, a buy: nothing. A merchant's arrival: nothing. A merchant's lap, repair or share: one more call that leaves after one
--   players probe (a lap with no gain: before any read). A human arrival: one read of her voyage's days and up to three grants.
--   world.levels(): ten small rows. The self-assert measures each and prints it; docs/dev-log/2026-11-14-levels.md has the numbers.
-- LOCKS: CREATE TABLE x4; CREATE OR REPLACE x9 by hunks; the two foreign keys to public.players are added LAST (a brief SHARE ROW
--   EXCLUSIVE on players under lock_timeout 5 s, as 0356).
-- ROLLBACK (forward, owner only): scripts/ops/harness/levels/rollback-0412.sql, a draft. At once, with no file: level_skills_on false.
-- SELF-ASSERT: the catalog, then probe houses of this file's own rows, rolled back by a raised sentinel. No table is counted or summed.
-- NEWS: this file posts its own UPDATE row once, outside the rolled-back probe (0347's law, tests/news.lint.spec.ts).
-- BUDGET: ONE DO block, statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- VERSION: 0412. 0408 to 0411 (merchants' and pirates' own functions) are in flight ahead of it: see the PR for the heads it was built on.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array[
    'voyage.settle(uuid,timestamp with time zone)', 'cmd.do_build(uuid,jsonb)', 'cmd.do_repair(uuid,jsonb)', 'cmd.run_fulfil(uuid,uuid)',
    'cmd.do_make(uuid,jsonb)', 'cmd.forge_good(uuid,uuid,integer)', 'cmd.standing_route_close_lap(uuid,timestamp with time zone)',
    'public.invest_for(uuid,uuid,text,integer)', 'world.levels()'];
  c_new constant text[] := array[
    'public.level_activity_terms()', 'public.level_grant(uuid,text,numeric,text)', 'public.level_arrival(uuid,uuid)',
    'public.level_benefits(text,integer)', 'public.level_skills_card(uuid,jsonb)', 'public.level_book_chains()'];
  c_tabs constant text[] := array['level_skills', 'level_activities', 'level_xp', 'level_book'];
  c_uid  constant uuid := '00000000-0412-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_t         timestamptz;
  t1          timestamptz;
  t2          timestamptz;
  t3          timestamptz;
  h           record;
  d           record;
  v_def       text;
  v_n         int;
  v_m         int;
  v_fn_before text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_pl        uuid;
  v_npc       uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_voy       uuid;
  v_r         jsonb;
  v_s         jsonb;
  v_gift      int;
  v_cap       int;
  v_l         int;
  v_fed       numeric;
  v_storm     numeric;
  v_rough     numeric;
  v_hull      numeric;
  v_old_def   text;
  v_npc_us    numeric;
  v_arr_ms    numeric;
  v_old_ms    numeric := 0;
  v_new_ms    numeric := 0;
  v_pairs     int := 0;
  v_ms_make   numeric;
  v_ms_probe  numeric;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_tabs) x where to_regclass('public.' || x) is not null)
     or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null)
     or exists (select 1 from public.world_config c where c.key = 'level_skills_on') then
    raise exception '0412 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null)
     or to_regprocedure('public.player_progress(uuid)') is null or to_regprocedure('public.level_line(numeric)') is null
     or to_regprocedure('public.level_points(integer)') is null or to_regprocedure('public.level_from_points(numeric)') is null
     or to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null or to_regprocedure('public.emit_event(uuid,text,jsonb)') is null
     or to_regprocedure('public.real_day(timestamp with time zone)') is null or to_regprocedure('public.forbid_mutation()') is null
     or to_regprocedure('public.fleet_room_on()') is null or to_regprocedure('public.client_write_grants()') is null
     or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regclass('public.trait_foci') is null or to_regclass('public.captain_grades') is null or to_regclass('public.title_names') is null
     or to_regclass('public.sea_zones') is null
     or not exists (select 1 from public.reputation_kinds k where k.code = 'level' and k.sign = 1 and not k.capped)
     or (select count(*) from public.world_config c where c.key in ('fame_ducats_per_point', 'fame_per_port', 'fame_nm_per_point', 'fame_per_mayor_day',
           'xp_evaded_points', 'xp_driven_off_points', 'rep_level_per_level', 'reputation_on', 'fleet_room_levels', 'title_max', 'level_points_per_step')) <> 11 then
    raise exception '0412 refuses: a function, table, kind or knob it calls, cuts or serves is not in this world (0069 / 0127 / 0162 / 0215 / 0321 / 0325 / 0352 / 0356)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0412 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0412
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE TABLES AND THEIR DATA ──
  v_t := clock_timestamp();
  create table public.level_skills (
    code    text primary key check (code ~ '^[a-z_]+$'),
    ord     int  not null unique,
    word    text not null,
    kept    text not null check (kept in ('record', 'book')),
    day_cap int  check (day_cap > 0),
    check ((kept = 'book') = (day_cap is not null))
  );
  comment on table public.level_skills is
    '0412: every level a company has, in the page''s order (docs/LEVELS.md). kept record: counted by public.player_progress from the append-only record (trading, exploration, combat: that function stays their one authority). kept book: granted by public.level_grant into public.level_xp, at most day_cap experience a day. word is the server''s English name.';
  alter table public.level_skills enable row level security;
  revoke all on table public.level_skills from public, anon, authenticated;
  insert into public.level_skills (code, ord, word, kept, day_cap) values
    ('trading',      1,  'Trading',      'record', null),
    ('exploration',  2,  'Exploration',  'record', null),
    ('combat',       3,  'Combat',       'record', null),
    ('supplies', 4,  'Supplies', 'book',   300),
    ('weather',      5,  'Weather',      'book',   300),
    ('shipbuilding', 6,  'Shipbuilding', 'book',   300),
    ('requests',    7,  'Requests',    'book',   300),
    ('craft',     8,  'Craft',     'book',   300),
    ('routes',       9,  'Routes',       'book',   300),
    ('investment',   10, 'Investment',   'book',   300);

  create table public.level_activities (
    code      text primary key check (code ~ '^[a-z_]+$'),
    skill     text not null references public.level_skills(code),
    ord       int  not null,
    word      text not null,
    unit      text not null check (unit in ('each', 'ducats', 'nm', 'day')),
    xp        numeric not null check (xp > 0),
    per       numeric not null check (per > 0),
    xp_knob   text,
    per_knob  text,
    most_xp   int check (most_xp > 0),
    once      boolean not null default false,
    at_gain   boolean not null default false,
    voyage_nm numeric check (voyage_nm > 0),
    unique (skill, ord)
  );
  comment on table public.level_activities is
    '0412: what raises a level: xp experience for every per units (unit says of what). xp_knob / per_knob name the world_config knob that holds the figure instead (the three levels public.player_progress counts: the knob is the authority and xp / per here are not read). most_xp: at most this much a grant. once: paid once ever for its thing. at_gain: only when it made a gain. voyage_nm: only on a voyage of at least this many miles into a port. Read through public.level_activity_terms() alone.';
  alter table public.level_activities enable row level security;
  revoke all on table public.level_activities from public, anon, authenticated;
  insert into public.level_activities (code, skill, ord, word, unit, xp, per, xp_knob, per_knob, most_xp, once, at_gain, voyage_nm) values
    ('trade',      'trading',      1, 'Goods bought or sold',            'ducats', 1,  1,    null,                   'fame_ducats_per_point', null, false, false, null),
    ('give',       'trading',      2, 'Coin invested in or donated to a city', 'ducats', 1, 1, null,                   'fame_ducats_per_point', null, false, false, null),
    ('mayor',      'trading',      3, 'A day as mayor',                  'day',    1,  1,    'fame_per_mayor_day',   null,                    null, false, false, null),
    ('port',       'exploration',  1, 'A port reached',                  'each',   1,  1,    'fame_per_port',        null,                    null, true,  false, null),
    ('miles',      'exploration',  2, 'Miles sailed',                    'nm',     1,  1,    null,                   'fame_nm_per_point',     null, false, false, null),
    ('evaded',     'combat',       1, 'Pirates evaded',                  'each',   1,  1,    'xp_evaded_points',     null,                    null, false, false, null),
    ('driven_off', 'combat',       2, 'Pirates driven off',              'each',   1,  1,    'xp_driven_off_points', null,                    null, false, false, null),
    ('fed',        'supplies', 1, 'A day at sea with enough supplies',    'day',    2,  1,    null,                   null,                    null, false, false, 100),
    ('storm',      'weather',      1, 'A storm day come through',        'day',    25, 1,    null,                   null,                    null, false, false, null),
    ('rough',      'weather',      2, 'A day of calm, foul water or shoal water', 'day', 10, 1, null,                null,                    null, false, false, null),
    ('hull',       'shipbuilding', 1, 'A ship built',                'each',   60, 1,    null,                   null,                    null, true,  false, null),
    ('repair',     'shipbuilding', 2, 'Coin paid for repairs', 'ducats', 1,  100,  null,                   null,                    null, false, false, null),
    ('request',    'requests',    1, 'A request fulfilled, by its premium', 'ducats', 1, 100, null,          null,                    100,  false, false, null),
    ('made',       'craft',     1, 'An item made at a workshop', 'each',   5,  1,    null,                   null,                    null, false, false, null),
    ('forged',     'craft',     2, 'A good produced',             'each',   1,  1,    null,                   null,                    null, false, false, null),
    ('lap',        'routes',       1, 'A route lap closed at a gain', 'each', 10, 1, null,                  null,                    null, true,  true,  null),
    ('share',      'investment',   1, 'Coin invested in a city',  'ducats', 1,  1000, null,                   null,                    null, false, false, null);

  create table public.level_xp (
    player_id  uuid not null,
    skill      text not null references public.level_skills(code),
    xp         int  not null default 0 check (xp >= 0),
    seq        int  not null default 0 check (seq >= 0),
    day        int  not null default 0,
    day_earned int  not null default 0 check (day_earned >= 0),
    primary key (player_id, skill)
  );
  comment on table public.level_xp is
    '0412: a company''s experience in one book level (public.level_skills.kept = book). xp is the newest book row''s xp_after (seq names it). day is public.real_day of day_earned, what it earned that day against the level''s day_cap. Written by public.level_grant alone. A merchant never has a row. The level is public.level_from_points(xp): the one curve.';
  alter table public.level_xp enable row level security;
  revoke all on table public.level_xp from public, anon, authenticated;

  create table public.level_book (
    player_id  uuid not null,
    skill      text not null references public.level_skills(code),
    seq        int  not null check (seq >= 1),
    activity   text not null references public.level_activities(code),
    xp         int  not null check (xp > 0),
    xp_after   int  not null check (xp_after >= 0),
    key        text,
    created_at timestamptz not null default now(),
    primary key (player_id, skill, seq)
  );
  create unique index level_book_once on public.level_book (player_id, key) where key is not null;
  comment on table public.level_book is
    '0412: every grant of experience, APPEND-ONLY (public.forbid_mutation) and a chain: each row follows the row before it (level_book_chains). key is the once-ever guard (hull:<ship>, lap:<lap>, fed:<voyage>). Written by public.level_grant alone. Bounded by the caps: at most day_cap rows a level a company a day.';
  alter table public.level_book enable row level security;
  revoke all on table public.level_book from public, anon, authenticated;

  insert into public.world_config (key, value, description) values
    ('level_skills_on', 'true'::jsonb,
     '0412: the levels raised by doing (public.level_skills, kept book) earn experience. false = public.level_grant writes nothing and the page shows them as not counted; what was earned is kept. It does not touch Trading, Exploration or Combat, which public.player_progress counts.');

  -- ── 3. THE FUNCTIONS ──
  execute $f$
create function public.level_book_chains()
returns trigger
language plpgsql
as $body$
-- 0412: a book row follows the row before it. One primary-key probe; no sum.
begin
  if new.seq = 1 then
    if new.xp_after <> new.xp then
      raise exception 'level_book: row 1 of % in % opens at %, not at its own %', new.player_id, new.skill, new.xp_after, new.xp using errcode = '23514';
    end if;
  elsif not exists (select 1 from public.level_book b
                     where b.player_id = new.player_id and b.skill = new.skill and b.seq = new.seq - 1 and b.xp_after + new.xp = new.xp_after) then
    raise exception 'level_book: row % of % in % does not follow row %', new.seq, new.player_id, new.skill, new.seq - 1 using errcode = '23514';
  end if;
  return new;
end
$body$
  $f$;
  create trigger level_book_append_only
    before update or delete on public.level_book
    for each row execute function public.forbid_mutation();
  create trigger level_book_chains
    before insert on public.level_book
    for each row execute function public.level_book_chains();

  execute $f$
create function public.level_activity_terms()
returns table (code text, skill text, ord int, word text, unit text, xp numeric, per numeric, most_xp int, once boolean, at_gain boolean, voyage_nm numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0412: THE ONE READING of what raises a level and by how much: the row's own figures, or the knob the row names (the three
  -- levels public.player_progress counts keep their figures in its knobs). The writer and the page both read this.
  select a.code, a.skill, a.ord, a.word, a.unit,
         case when a.xp_knob is null then a.xp else public.wc_num(a.xp_knob) end,
         case when a.per_knob is null then a.per else public.wc_num(a.per_knob) end,
         a.most_xp, a.once, a.at_gain, a.voyage_nm
    from public.level_activities a
$body$
  $f$;

  execute $f$
create function public.level_grant(p_player uuid, p_activity text, p_units numeric, p_key text default null)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0412: THE ONE WRITER of a level's experience (docs/LEVELS.md). Returns what was granted (0 when nothing was).
-- Nothing asked: 0 before any read. A merchant: 0 after one players probe. level_skills_on false: 0.
-- floor(units / per x xp), at most the activity's most_xp, inside the level's cap a day; past the cap nothing is written.
-- A key pays once ever. A level crossed pays rep_level_per_level x the level (public.reputation_credit, kind level, key
-- level:<code>:<L>) and emits LEVEL_UP {track, level, reputation}: the moment 0356 made for Trading, Exploration and Combat.
declare
  a        record;
  v_kept   text;
  v_cap    int;
  x        public.level_xp%rowtype;
  v_amount numeric;
  v_today  int;
  v_earned int;
  v_l0     int;
  v_l1     int;
  v_per    int;
  v_got    int;
begin
  if p_player is null or p_units is null or p_units <= 0 then
    return 0;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('level_skills_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  select * into a from public.level_activity_terms() t where t.code = p_activity;
  if a.code is null then
    raise exception 'level_grant: no activity is called %', p_activity using errcode = '22023';
  end if;
  select s.kept, s.day_cap into v_kept, v_cap from public.level_skills s where s.code = a.skill;
  if v_kept <> 'book' then
    raise exception 'level_grant: % is counted from the record by public.player_progress and is never granted', a.skill using errcode = '22023';
  end if;
  v_amount := floor(p_units / a.per * a.xp);
  if a.most_xp is not null then
    v_amount := least(v_amount, a.most_xp);
  end if;
  if v_amount < 1 then
    return 0;
  end if;
  if p_key is not null and exists (select 1 from public.level_book b where b.player_id = p_player and b.key = p_key) then
    return 0;
  end if;
  insert into public.level_xp (player_id, skill) values (p_player, a.skill) on conflict (player_id, skill) do nothing;
  select * into x from public.level_xp lx where lx.player_id = p_player and lx.skill = a.skill for update;
  -- under the lock, the key again: two calls at one instant both pass the read above, and only one may book
  if p_key is not null and exists (select 1 from public.level_book b where b.player_id = p_player and b.key = p_key) then
    return 0;
  end if;
  v_today  := public.real_day(now());
  v_earned := case when x.day = v_today then x.day_earned else 0 end;
  v_amount := least(v_amount, v_cap - v_earned);
  if v_amount < 1 then
    return 0;
  end if;
  insert into public.level_book (player_id, skill, seq, activity, xp, xp_after, key)
  values (p_player, a.skill, x.seq + 1, a.code, v_amount::int, x.xp + v_amount::int, p_key);
  update public.level_xp
     set xp = x.xp + v_amount::int, seq = x.seq + 1, day = v_today, day_earned = v_earned + v_amount::int
   where player_id = p_player and skill = a.skill;
  v_l0 := public.level_from_points(x.xp);
  v_l1 := public.level_from_points(x.xp + v_amount);
  if v_l1 > v_l0 then
    v_per := case when public.wc('reputation_on') = 'true'::jsonb then coalesce(public.wc_int('rep_level_per_level'), 0) else 0 end;
    for v_l in v_l0 + 1 .. v_l1 loop
      v_got := 0;
      if v_per > 0 then
        v_got := public.reputation_credit(p_player, 'level', v_per * v_l, 'level:' || a.skill || ':' || v_l,
                                          jsonb_build_object('track', a.skill, 'level', v_l));
      end if;
      perform public.emit_event(p_player, 'LEVEL_UP', jsonb_build_object('track', a.skill, 'level', v_l, 'reputation', v_got));
    end loop;
  end if;
  return v_amount::int;
end
$body$
  $f$;

  execute $f$
create function public.level_arrival(p_player uuid, p_voyage uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0412: WHAT A VOYAGE THAT HAS ENDED TAUGHT HER COMPANY (voyage.settle calls it for a player, beside public.reputation_arrival).
-- ONE read of the voyage's own days (public.voyage_events, by its key): the storm days and the rough days (calm, foul water, shoal
-- water) she came through, and the days at sea. Days fed count only when she made a port, sailed at least the activity's voyage_nm
-- and no day was on short rations. Each is keyed by the voyage, so settling twice grants once. Returns what was granted.
declare
  v_nm    numeric;
  v_dest  uuid;
  v_days  int;
  v_storm int;
  v_rough int;
  v_short boolean;
  v_n     int := 0;
begin
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('level_skills_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  select v.total_nm, v.dest_port_id into v_nm, v_dest from public.voyages v where v.id = p_voyage and v.player_id = p_player;
  if not found then
    return 0;
  end if;
  select count(*) filter (where ve.kind not in ('LANDFALL', 'FORCED_HOME')),
         count(*) filter (where ve.kind = 'STORM'),
         count(*) filter (where ve.kind in ('CALM', 'FOUL_WATER', 'SHOAL_WATER')),
         coalesce(bool_or(ve.kind in ('SHORT_RATIONS', 'FORCED_HOME') or coalesce((ve.payload ->> 'short_rations')::boolean, false)), false)
    into v_days, v_storm, v_rough, v_short
    from public.voyage_events ve where ve.voyage_id = p_voyage;
  if v_storm > 0 then
    v_n := v_n + public.level_grant(p_player, 'storm', v_storm, 'storm:' || p_voyage);
  end if;
  if v_rough > 0 then
    v_n := v_n + public.level_grant(p_player, 'rough', v_rough, 'rough:' || p_voyage);
  end if;
  if v_dest is not null and v_days > 0 and not v_short
     and v_nm >= coalesce((select t.voyage_nm from public.level_activity_terms() t where t.code = 'fed'), 0) then
    v_n := v_n + public.level_grant(p_player, 'fed', v_days, 'fed:' || p_voyage);
  end if;
  return v_n;
end
$body$
  $f$;

  execute $f$
create function public.level_benefits(p_skill text, p_gift int)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0412: WHAT A LEVEL GIVES, and only what a rule already applies. level null = every level. Each row is read from the rule's own
  -- table or knob, so the page cannot promise what the server does not do:
  --   gift         p_gift x the level in Reputation, once a level (0356; public.level_grant for a book level): the caller passes
  --                rep_level_per_level while reputation_on, else 0 (public.level_skills_card reads it once for every level)
  --   captain_cap  a captain's level in this track is never above the company's (public.captain_level, 0160): the three tracks of trait_foci
  --   promote      a captain's promotion to this grade asks this level of her, so of the company (captain_grades.promote_level, 0162)
  --   fleet        one more fleet at this Trading level (fleet_room_levels, public.fleet_room_caps, 0321), while the room is counted
  --   title        the title of this level, held at the lower of Trading and Exploration (public.title_level, 0215); `opens` are the
  --                seas that ask it (sea_zones.title_min), while sea_conditions_bite
  select coalesce(jsonb_agg(b.j order by b.lvl nulls first, b.o), '[]'::jsonb)
    from (
      select null::int as lvl, 0 as o, jsonb_build_object('level', null, 'kind', 'gift', 'n', p_gift) as j
       where coalesce(p_gift, 0) > 0
      union all
      select null, 1, jsonb_build_object('level', null, 'kind', 'captain_cap')
       where exists (select 1 from public.trait_foci tf where tf.code = p_skill)
      union all
      select g.promote_level, 2, jsonb_build_object('level', g.promote_level, 'kind', 'promote', 'grade', g.code)
        from public.captain_grades g
       where g.promote_level is not null and exists (select 1 from public.trait_foci tf where tf.code = p_skill)
      union all
      select r.value::int, 3, jsonb_build_object('level', r.value::int, 'kind', 'fleet')
        from jsonb_array_elements_text(public.wc('fleet_room_levels')) r
       where p_skill = 'trading' and public.fleet_room_on()
      union all
      select t.level, 4, jsonb_build_object('level', t.level, 'kind', 'title', 'name', t.name,
               'with', case p_skill when 'trading' then 'exploration' else 'trading' end,
               'opens', case when public.wc('sea_conditions_bite') = 'true'::jsonb
                             then (select coalesce(jsonb_agg(z.name order by z.ord), '[]'::jsonb) from public.sea_zones z where z.title_min = t.level)
                             else '[]'::jsonb end)
        from public.title_names t
       where p_skill in ('trading', 'exploration') and t.level between 2 and public.wc_int('title_max')
    ) b
$body$
  $f$;

  execute $f$
create function public.level_skills_card(p_player uuid, p_pp jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0412: THE LEVELS, ALL OF THEM, FOR THE PAGE (world.levels() serves it and passes the public.player_progress it has already read:
  -- nothing is counted twice). curve[L-1] is the experience at which level L begins (public.level_points, the one curve), to `top`.
  -- Each level: public.level_line of its points (a record level's are public.player_progress's; a book level's are public.level_xp's),
  -- counted (false: combat while it is not playable; a book level while level_skills_on is false), today against cap (book levels),
  -- activities (public.level_activity_terms, read once), benefits (public.level_benefits, with the gift read once) and the five newest grants (book levels; null for a
  -- record level, whose points are recounted from the whole record and have no grant rows).
  with k as materialized (
    select public.wc('level_skills_on') = 'true'::jsonb as sw,
           public.level_from_points(1000000000000) as top,
           public.real_day(now()) as today,
           case when public.wc('reputation_on') = 'true'::jsonb then coalesce(public.wc_int('rep_level_per_level'), 0) else 0 end as gift
  ), acts as materialized (
    select a.skill, jsonb_agg(jsonb_build_object(
             'code', a.code, 'word', a.word, 'unit', a.unit, 'xp', a.xp, 'per', a.per, 'most', a.most_xp,
             'once', a.once, 'at_gain', a.at_gain, 'voyage_nm', a.voyage_nm) order by a.ord) as j
      from public.level_activity_terms() a group by a.skill
  )
  select jsonb_build_object(
    'on', k.sw,
    'top', k.top,
    'curve', (select jsonb_agg(public.level_points(g) order by g) from generate_series(1, k.top) g),
    'skills', (select jsonb_agg(
                 public.level_line(z.points) || jsonb_build_object(
                   'code', s.code, 'word', s.word, 'kept', s.kept,
                   'counted', case when s.kept = 'book' then k.sw else coalesce((p_pp -> s.code ->> 'playable')::boolean, true) end,
                   'today', case when s.kept = 'book' then case when x.day = k.today then x.day_earned else 0 end end,
                   'cap', s.day_cap,
                   'activities', coalesce(acts.j, '[]'::jsonb),
                   'benefits', public.level_benefits(s.code, k.gift),
                   'recent', case when s.kept = 'book' then
                               coalesce((select jsonb_agg(jsonb_build_object('activity', r.activity, 'xp', r.xp, 'at', r.created_at) order by r.seq desc)
                                           from (select b.seq, b.activity, b.xp, b.created_at from public.level_book b
                                                  where b.player_id = p_player and b.skill = s.code order by b.seq desc limit 5) r), '[]'::jsonb) end)
                 order by s.ord)
                 from public.level_skills s
                 left join acts on acts.skill = s.code
                 left join public.level_xp x on x.player_id = p_player and x.skill = s.code
                cross join lateral (select case when s.kept = 'book' then coalesce(x.xp, 0)::numeric
                                                else coalesce((p_pp -> s.code ->> 'points')::numeric, 0) end as points) z))
    from k
$body$
  $f$;

  revoke all on function public.level_book_chains() from public, anon, authenticated;
  revoke all on function public.level_activity_terms() from public, anon, authenticated;
  revoke all on function public.level_grant(uuid, text, numeric, text) from public, anon, authenticated;
  revoke all on function public.level_arrival(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.level_benefits(text, int) from public, anon, authenticated;
  revoke all on function public.level_skills_card(uuid, jsonb) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each OLD text once in its live body; each NEW is OLD and one line more) ──
  create temp table hunk_0412 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0412 values
  (1, c_cut[1],
$h$      perform public.reputation_arrival(f.player_id, v.id);
$h$,
$h$      perform public.reputation_arrival(f.player_id, v.id);
      -- 0412: and her company's levels raised by doing: days fed, storms and rough days come through (public.level_arrival)
      perform public.level_arrival(f.player_id, v.id);
$h$),
  (2, c_cut[2],
$h$  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object('class', c.code));
$h$,
$h$  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object('class', c.code));
  perform public.level_grant(f.player_id, 'hull', 1, 'hull:' || v_ship);   -- 0412: Shipbuilding, once a ship
$h$),
  (3, c_cut[3],
$h$  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
$h$,
$h$  perform public.level_grant(f.player_id, 'repair', v_cost);   -- 0412: Shipbuilding, by the coin the yard was paid (a merchant leaves after one players probe)
  return jsonb_build_object('points', round(v_points, 1), 'cost', v_cost, 'sim_hours', round(v_hours, 1))
$h$),
  (4, c_cut[4],
$h$  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object('port', v_port.code, 'good', g.code));
$h$,
$h$  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object('port', v_port.code, 'good', g.code));
  perform public.level_grant(f.player_id, 'request', v_pay);   -- 0412: Requests, by the bonus this delivery was paid
$h$),
  (5, c_cut[5],
$h$    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));
$h$,
$h$    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));
  perform public.level_grant(f.player_id, 'made', v_qty);   -- 0412: Craft, by the fittings made
$h$),
  (6, c_cut[6],
$h$      'product', v_product.name, 'qty', v_qty, 'spent', v_spent));
$h$,
$h$      'product', v_product.name, 'qty', v_qty, 'spent', v_spent));
    perform public.level_grant(v_player, 'forged', v_qty);   -- 0412: Craft, by the goods forged
$h$),
  (7, c_cut[7],
$h$  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);
$h$,
$h$  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);
  perform public.level_grant(sr.player_id, 'lap', case when l.net > 0 then 1 else 0 end, 'lap:' || l.id);   -- 0412: Routes, once a lap at a gain (no gain: 0 units, and the writer leaves before any read)
$h$),
  (8, c_cut[8],
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
$h$,
$h$  v_after := public.pay_city(p_player, p_port, 'SHARE', v_cost, v_event);
  perform public.level_grant(p_player, 'share', v_cost);   -- 0412: Investment, by the coin paid for shares (a merchant leaves after one players probe)
$h$),
  (9, c_cut[9],
$h$    'bite', public.levels_bite_on(),
$h$,
$h$    'bite', public.levels_bite_on(),
    -- 0412: every level, raised by doing: points, the curve, activities, benefits, recent grants (public.level_skills_card, on the progress read above)
    'level_skills', public.level_skills_card(v_id, v_pp),
$h$);
  for h in select * from hunk_0412 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0412 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0412 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0412 p where p.fn = h.fn) then
      raise exception '0412 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  v_ms_make := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  for d in select p.fn, p.def from pre_0412 p loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select x.old, x.new from hunk_0412 x where x.fn = d.fn order by x.ord desc loop
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0412 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0412 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'level_skills_on') <> v_cfg_before
     or public.wc('level_skills_on') is distinct from 'true'::jsonb then
    raise exception '0412 self-assert FAIL: an existing world_config row moved, or this file''s knob is not true';
  end if;
  if exists (select 1 from unnest(c_new) f cross join unnest(array['anon', 'authenticated']) r(role) where has_function_privilege(r.role, f, 'execute')) then
    raise exception '0412 self-assert FAIL: a client may call a function of this file';
  end if;
  if exists (select 1 from unnest(c_tabs) x cross join unnest(array['anon', 'authenticated']) r(role)
              where has_table_privilege(r.role, 'public.' || x, 'select,insert,update,delete'))
     or exists (select 1 from unnest(c_tabs) x where not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || x)::regclass)) then
    raise exception '0412 self-assert FAIL: a client can read or write a table of this file, or one has no row level security';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0412 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  -- THE DATA: every level has an activity; a record level is a track public.player_progress serves and every figure of it is a knob
  -- that exists; a book level's figures are its own; and no activity is granted that is not a book level's (the hooks' seven names).
  if exists (select 1 from public.level_skills s where not exists (select 1 from public.level_activities a where a.skill = s.code))
     or exists (select 1 from public.level_skills s where s.kept = 'record' and not (public.player_progress(null) ? s.code))
     or exists (select 1 from public.level_activities a join public.level_skills s on s.code = a.skill
                 where (s.kept = 'record') <> (a.xp_knob is not null or a.per_knob is not null))
     or exists (select 1 from public.level_activities a cross join lateral (values (a.xp_knob), (a.per_knob)) k(key)
                 where k.key is not null and not exists (select 1 from public.world_config c where c.key = k.key))
     or exists (select 1 from public.level_activity_terms() t where t.xp is null or t.per is null or t.xp <= 0 or t.per <= 0)
     or (select string_agg(a.code, ',' order by a.code) from public.level_activities a join public.level_skills s on s.code = a.skill where s.kept = 'book')
        is distinct from 'fed,forged,hull,lap,made,repair,request,rough,share,storm' then
    raise exception '0412 self-assert FAIL: the levels'' data is not whole (a level with no activity, a record level player_progress does not serve, a knob that is not there, or a book activity no hook names)';
  end if;
  -- THE HOT PATHS THIS FILE DOES NOT TOUCH: a sale and a buy name nothing of it; and the writer has no caller but the hooks and the arrival
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'cmd' and (p.proname like 'do\_sell%' or p.proname = 'do_buy') and p.prosrc like '%level\_grant%') then
    raise exception '0412 self-assert FAIL: a sale or a buy names the level writer';
  end if;
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind in ('f', 'p') and p.prosrc like '%level\_grant(%';
  if v_def is distinct from 'cmd.do_build,cmd.do_make,cmd.do_repair,cmd.forge_good,cmd.run_fulfil,cmd.standing_route_close_lap,public.invest_for,public.level_arrival' then
    raise exception '0412 self-assert FAIL: the writer''s callers are %', v_def;
  end if;
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind in ('f', 'p') and (p.prosrc like '%insert into public.level\_xp%' or p.prosrc like '%insert into public.level\_book%' or p.prosrc like '%update public.level\_xp%');
  if v_def is distinct from 'public.level_grant' then
    raise exception '0412 self-assert FAIL: the experience has other writers than public.level_grant: %', v_def;
  end if;

  -- ── 6. THE SELF-ASSERT: probe houses of this file's own rows, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa dos Niveis 0412', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0412', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on' and value is distinct from 'true'::jsonb;
    v_gift := coalesce(public.wc_int('rep_level_per_level'), 0);
    select t.xp into v_hull from public.level_activity_terms() t where t.code = 'hull';
    select t.xp / t.per into v_fed from public.level_activity_terms() t where t.code = 'fed';
    select t.xp into v_storm from public.level_activity_terms() t where t.code = 'storm';
    select t.xp into v_rough from public.level_activity_terms() t where t.code = 'rough';
    select s.day_cap into v_cap from public.level_skills s where s.code = 'investment';

    -- (a) NOTHING ASKED, A MERCHANT, AN UNKNOWN NAME, A RECORD LEVEL
    if public.level_grant(null, 'hull', 1) <> 0 or public.level_grant(v_pl, 'hull', 0) <> 0 or public.level_grant(v_pl, 'hull', -3) <> 0
       or public.level_grant(v_npc, 'hull', 1, 'hull:npc') <> 0 or public.level_grant(v_npc, 'share', 1000000) <> 0
       or public.level_arrival(v_npc, gen_random_uuid()) <> 0 or public.level_arrival(null, gen_random_uuid()) <> 0
       or exists (select 1 from public.level_xp x where x.player_id in (v_pl, v_npc)) or exists (select 1 from public.level_book b where b.player_id in (v_pl, v_npc)) then
      raise exception '0412 self-assert FAIL: nothing asked or a merchant was granted, or a row was written';
    end if;
    begin
      perform public.level_grant(v_pl, 'no_such_thing', 1);
      raise exception '0412 self-assert FAIL: an unknown activity was granted';
    exception when sqlstate '22023' then null;
    end;
    begin
      perform public.level_grant(v_pl, 'miles', 5000);
      raise exception '0412 self-assert FAIL: a level counted from the record was granted';
    exception when sqlstate '22023' then null;
    end;

    -- (b) A HULL: its experience once, the levels it crosses each ONE event and ONE gift, and the key pays once
    v_l := public.level_from_points(v_hull);
    v_n := public.level_grant(v_pl, 'hull', 1, 'hull:probe');
    v_m := public.level_grant(v_pl, 'hull', 1, 'hull:probe');
    if v_n <> v_hull or v_m <> 0
       or (select x.xp || ':' || x.seq || ':' || x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'shipbuilding') is distinct from v_hull || ':1:' || v_hull
       or (select b.activity || ':' || b.xp || ':' || b.xp_after || ':' || b.key from public.level_book b where b.player_id = v_pl and b.skill = 'shipbuilding' and b.seq = 1)
          is distinct from 'hull:' || v_hull || ':' || v_hull || ':hull:probe'
       or exists (select 1 from public.level_book b where b.player_id = v_pl and b.skill = 'shipbuilding' and b.seq = 2) then
      raise exception '0412 self-assert FAIL: a hull did not grant % once (% then %)', v_hull, v_n, v_m;
    end if;
    if v_l < 2 then
      raise exception '0412 self-assert FAIL: a hull''s % experience crosses no level: the probe proves no crossing', v_hull;
    end if;
    if coalesce((select string_agg((e.payload ->> 'track') || ':' || (e.payload ->> 'level') || ':' || (e.payload ->> 'reputation'), ',' order by (e.payload ->> 'level')::int)
                   from public.events e where e.player_id = v_pl and e.kind = 'LEVEL_UP'), '')
          is distinct from (select string_agg('shipbuilding:' || g || ':' || v_gift * g, ',' order by g) from generate_series(2, v_l) g)
       or (v_gift > 0 and coalesce((select string_agg(k.kind || ':' || k.delta || ':' || k.key, ',' order by k.seq) from public.reputation_book k where k.player_id = v_pl), '')
                          is distinct from (select string_agg('level:' || v_gift * g || ':level:shipbuilding:' || g, ',' order by g) from generate_series(2, v_l) g)) then
      raise exception '0412 self-assert FAIL: a hull that reached Shipbuilding level % did not fire each crossing once with its gift', v_l;
    end if;

    -- (c) THE CAP A DAY: a great sum is granted to the cap and no further; the next writes nothing; a new day opens it again
    v_n := public.level_grant(v_pl, 'share', 1000000000);
    v_m := public.level_grant(v_pl, 'share', 1000000000);
    if v_n <> v_cap or v_m <> 0
       or (select x.xp || ':' || x.seq || ':' || x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'investment') is distinct from v_cap || ':1:' || v_cap then
      raise exception '0412 self-assert FAIL: the cap a day did not hold at % (% then %)', v_cap, v_n, v_m;
    end if;
    update public.level_xp set day = day - 1 where player_id = v_pl and skill = 'investment';   -- the probe's own row: yesterday
    v_n := public.level_grant(v_pl, 'share', 5000);
    if v_n <> floor(5000 / (select t.per from public.level_activity_terms() t where t.code = 'share'))
       or (select x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'investment') <> v_n
       or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'investment') <> v_cap + v_n then
      raise exception '0412 self-assert FAIL: a new day did not open the cap (% granted)', v_n;
    end if;
    -- most_xp: one request's bonus, however large, grants at most the row's most
    v_n := public.level_grant(v_pl, 'request', 1000000);
    if v_n <> (select t.most_xp from public.level_activity_terms() t where t.code = 'request') then
      raise exception '0412 self-assert FAIL: a request granted %, not its most', v_n;
    end if;
    -- less than one point: nothing, and no row
    if public.level_grant(v_pl, 'repair', 1) <> 0 or exists (select 1 from public.level_book b where b.player_id = v_pl and b.activity = 'repair') then
      raise exception '0412 self-assert FAIL: a repair of one ducat granted something';
    end if;

    -- (d) THE BOOK IS APPEND-ONLY AND A CHAIN
    begin
      update public.level_book set xp = xp + 1 where player_id = v_pl and skill = 'shipbuilding' and seq = 1;
      raise exception '0412 self-assert FAIL: a book row was updated';
    exception when sqlstate '42501' then null;
    end;
    begin
      insert into public.level_book (player_id, skill, seq, activity, xp, xp_after) values (v_pl, 'shipbuilding', 2, 'hull', 5, 999);
      raise exception '0412 self-assert FAIL: a book row that does not follow the row before it was written';
    exception when sqlstate '23514' then null;
    end;

    -- (e) AN ARRIVAL: seven days at sea (one a storm, one in shoal water), none hungry, 500 nm into a port
    v_fl := public.form_fleet(v_pl, 'Niveis', v_lis);
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl, '[]', 500, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload)
    select v_voy, g, case g when 3 then 'STORM' when 5 then 'SHOAL_WATER' else 'CLEAR' end, jsonb_build_object('short_rations', false) from generate_series(1, 7) g;
    insert into public.voyage_events (voyage_id, day_index, kind, payload) values (v_voy, 8, 'LANDFALL', '{}');
    v_n := public.level_arrival(v_pl, v_voy);
    v_m := public.level_arrival(v_pl, v_voy);
    if v_n <> floor(7 * v_fed) + v_storm + v_rough or v_m <> 0
       or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'supplies') <> floor(7 * v_fed)
       or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'weather') <> v_storm + v_rough
       or (select string_agg(b.activity || ':' || b.key, ',' order by b.activity) from public.level_book b where b.player_id = v_pl and b.skill in ('supplies', 'weather'))
          is distinct from format('fed:fed:%s,rough:rough:%s,storm:storm:%s', v_voy, v_voy, v_voy) then
      raise exception '0412 self-assert FAIL: an arrival of seven fed days, a storm and a shoal did not grant % + % + % once (% then %)', floor(7 * v_fed), v_storm, v_rough, v_n, v_m;
    end if;
    -- a hungry day, a short voyage, and open water: no days fed
    for v_l in 1 .. 3 loop
      v_voy := gen_random_uuid();
      insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
      values (v_voy, v_fl, v_pl, '[]', case v_l when 2 then 50 else 500 end, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis,
              case v_l when 3 then null else v_lis end);
      insert into public.voyage_events (voyage_id, day_index, kind, payload)
      select v_voy, g, case when v_l = 1 and g = 2 then 'SHORT_RATIONS' else 'CLEAR' end, jsonb_build_object('short_rations', v_l = 1 and g = 2) from generate_series(1, 4) g;
      if public.level_arrival(v_pl, v_voy) <> 0 then
        raise exception '0412 self-assert FAIL: days fed were granted to %', case v_l when 1 then 'a voyage with a hungry day' when 2 then 'a voyage of 50 nm' else 'a voyage that made no port' end;
      end if;
    end loop;

    -- (f) THE READ, as she calls it: ten levels in order, the curve, her points, today against the cap, activities, benefits, recent
    perform cmd.assume_identity(c_uid);
    v_r := world.levels();
    v_s := v_r -> 'level_skills';
    if (v_r ->> 'company')::boolean is not true or (v_s ->> 'on')::boolean is not true
       or (v_s ->> 'top')::int <> jsonb_array_length(v_s -> 'curve')
       or (v_s -> 'curve' ->> 0)::numeric <> 0 or (v_s -> 'curve' ->> 1)::numeric <> public.level_points(2)
       or (v_s -> 'curve' ->> ((v_s ->> 'top')::int - 1))::numeric <> public.level_points((v_s ->> 'top')::int)
       or public.level_from_points(public.level_points((v_s ->> 'top')::int)) <> (v_s ->> 'top')::int
       or (select string_agg(e ->> 'code', ',' order by o) from jsonb_array_elements(v_s -> 'skills') with ordinality x(e, o))
          is distinct from 'trading,exploration,combat,supplies,weather,shipbuilding,requests,craft,routes,investment' then
      raise exception '0412 self-assert FAIL: world.levels() does not serve the ten levels in order with the curve: %', left(v_s::text, 300);
    end if;
    if exists (select 1 from jsonb_array_elements(v_s -> 'skills') e
                where jsonb_array_length(e -> 'activities') = 0 or not (e ? 'benefits') or not (e ? 'level') or not (e ? 'next_at') or not (e ? 'from')
                   or ((e ->> 'kept') = 'book') <> (jsonb_typeof(e -> 'recent') = 'array')
                   or ((e ->> 'kept') = 'book') <> (jsonb_typeof(e -> 'cap') = 'number')
                   or (v_gift > 0 and not exists (select 1 from jsonb_array_elements(e -> 'benefits') b where b ->> 'kind' = 'gift' and (b ->> 'n')::int = v_gift))) then
      raise exception '0412 self-assert FAIL: a served level lacks its activities, its benefits, its line, its cap or its recent grants';
    end if;
    select e into v_s from jsonb_array_elements(v_r -> 'level_skills' -> 'skills') e where e ->> 'code' = 'supplies';
    if (v_s ->> 'points')::numeric <> floor(7 * v_fed) or (v_s ->> 'today')::int <> floor(7 * v_fed) or (v_s ->> 'cap')::int <> 300
       or (v_s -> 'recent' -> 0 ->> 'activity') <> 'fed' or (v_s -> 'recent' -> 0 ->> 'xp')::int <> floor(7 * v_fed)
       or (v_s -> 'activities' -> 0 ->> 'voyage_nm')::numeric <> 100 then
      raise exception '0412 self-assert FAIL: the page does not serve Supplies as the book holds it: %', v_s;
    end if;
    -- a record level is public.player_progress's, to the point, and its figures are the knobs'
    select e into v_s from jsonb_array_elements(v_r -> 'level_skills' -> 'skills') e where e ->> 'code' = 'trading';
    if (v_s - 'code' - 'word' - 'kept' - 'counted' - 'today' - 'cap' - 'activities' - 'benefits' - 'recent') is distinct from ((v_r -> 'tracks' -> 'trading') - 'turnover')
       or (v_s -> 'activities' -> 0 ->> 'per')::numeric <> public.wc_num('fame_ducats_per_point')
       or jsonb_typeof(v_s -> 'recent') <> 'null' or jsonb_typeof(v_s -> 'today') <> 'null'
       or not exists (select 1 from jsonb_array_elements(v_s -> 'benefits') b where b ->> 'kind' = 'captain_cap')
       or (select count(*) from jsonb_array_elements(v_s -> 'benefits') b where b ->> 'kind' = 'promote')
          <> (select count(*) from public.captain_grades g where g.promote_level is not null)
       or (select count(*) from jsonb_array_elements(v_s -> 'benefits') b where b ->> 'kind' = 'title') <> greatest(public.wc_int('title_max') - 1, 0)
       or (public.fleet_room_on() and (select count(*) from jsonb_array_elements(v_s -> 'benefits') b where b ->> 'kind' = 'fleet') <> jsonb_array_length(public.wc('fleet_room_levels'))) then
      raise exception '0412 self-assert FAIL: Trading on the page is not the track world.levels() already serves, or its benefits are not the rules'': %', v_s;
    end if;

    -- (g) THE SWITCH: off, nothing is granted and the page says the book levels are not counted; what was earned stands
    update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl, '[]', 500, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload) values (v_voy, 1, 'CLEAR', '{"short_rations": false}');
    select e into v_s from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') e where e ->> 'code' = 'supplies';
    if public.level_grant(v_pl, 'made', 3) <> 0 or public.level_arrival(v_pl, v_voy) <> 0
       or (v_s ->> 'counted')::boolean is not false or (v_s ->> 'points')::numeric <> floor(7 * v_fed) then
      raise exception '0412 self-assert FAIL: with level_skills_on false something was granted, or the page does not say so';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'level_skills_on';

    -- (h) WHAT IT COSTS (measurements, printed, never a gate; each stops itself after 1.5 s)
    begin
      t1 := clock_timestamp();
      for i in 1 .. 2000 loop
        exit when clock_timestamp() - t1 > interval '1.5 seconds';
        perform public.level_grant(v_npc, 'lap', 1, 'lap:probe');
        v_pairs := i;
      end loop;
      v_npc_us := extract(epoch from clock_timestamp() - t1) * 1000000 / greatest(v_pairs, 1);
      t1 := clock_timestamp();
      v_pairs := 0;
      for i in 1 .. 40 loop
        exit when clock_timestamp() - t1 > interval '1.5 seconds';
        v_voy := gen_random_uuid();
        insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
        values (v_voy, v_fl, v_pl, '[]', 500, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
        insert into public.voyage_events (voyage_id, day_index, kind, payload)
        select v_voy, g, case g when 3 then 'STORM' else 'CLEAR' end, '{"short_rations": false}' from generate_series(1, 6) g;
        t2 := clock_timestamp();
        perform public.level_arrival(v_pl, v_voy);
        v_arr_ms := coalesce(v_arr_ms, 0) + extract(epoch from clock_timestamp() - t2) * 1000;
        v_pairs := i;
      end loop;
      v_arr_ms := v_arr_ms / greatest(v_pairs, 1);
      select p.def into v_old_def from pre_0412 p where p.fn = 'world.levels()';
      execute replace(v_old_def, 'FUNCTION world.levels()', 'FUNCTION pg_temp.levels_old_0412()');
      v_pairs := 0;
      t1 := clock_timestamp();
      for i in 1 .. 30 loop
        exit when clock_timestamp() - t1 > interval '1.5 seconds';
        if i % 2 = 0 then
          t2 := clock_timestamp(); perform pg_temp.levels_old_0412();
          t3 := clock_timestamp(); perform world.levels();
          v_old_ms := v_old_ms + extract(epoch from t3 - t2) * 1000; v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - t3) * 1000;
        else
          t2 := clock_timestamp(); perform world.levels();
          t3 := clock_timestamp(); perform pg_temp.levels_old_0412();
          v_new_ms := v_new_ms + extract(epoch from t3 - t2) * 1000; v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - t3) * 1000;
        end if;
        v_pairs := i;
      end loop;
    exception when others then
      v_note := ' (a measurement stopped: ' || left(sqlerrm, 100) || ')';
    end;
    raise exception using errcode = 'ZX412', message = 'PROBE_ROLLBACK_0412';
  exception when sqlstate 'ZX412' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0412 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0412' or p.auth_uid = c_uid)
     or public.wc('level_skills_on') is distinct from 'true'::jsonb
     or to_regprocedure('pg_temp.levels_old_0412()') is not null
     or exists (select 1 from public.level_xp) or exists (select 1 from public.level_book) then
    raise exception '0412 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0412 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  v_ms_probe := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 7. THE FOREIGN KEYS, LAST: the one lock this file takes on public.players, held from here to the commit ──
  alter table public.level_xp add constraint level_xp_player_id_fkey foreign key (player_id) references public.players(id) on delete cascade;
  alter table public.level_book add constraint level_book_player_id_fkey foreign key (player_id) references public.players(id) on delete cascade;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law), counted by its own key
  perform public.news_update('0412', 'Levels: seven new ones', '레벨: 새로 일곱 가지');
  if (select count(*) from public.world_news w where w.key = 'update:0412') <> 1 then
    raise exception '0412 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0412 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0412 cost: public.level_grant for a merchant (what a merchant''s lap at a gain, repair or share gains): % microseconds a call. public.level_arrival for a probe human (six days, one a storm: two grants): % ms an arrival; a merchant''s arrival does not reach it. world.levels() for a probe human, OLD and NEW interleaved, % pair(s): OLD % ms, NEW % ms a read%. A sale and a buy are not cut.',
    round(v_npc_us, 1), round(v_arr_ms, 2), v_pairs, case when v_pairs > 0 then round(v_old_ms / v_pairs, 2) end, case when v_pairs > 0 then round(v_new_ms / v_pairs, 2) end, v_note;
  raise notice '0412 self-assert ok: LEVELS ARE MANY, AND EACH IS RAISED BY DOING. Four tables no client reads or writes (ten levels, seventeen activities), one knob (level_skills_on true), six functions no client calls; nine hunks over nine bodies, each once and reversing, grants, volatility, definer and search path unmoved; no other function and no existing knob moved; a sale and a buy name nothing of this file and public.level_grant is the one writer. Probe (rolled back): a merchant and nothing asked are granted nothing and write no row; a hull grants its experience once by its key and each level it crosses is ONE LEVEL_UP event with its Reputation gift; the cap a day holds and a new day opens it; the book refuses an update and a row that does not follow; an arrival grants days fed, a storm and a rough day once, and no days fed to a hungry, a short or an open-water voyage; world.levels() serves the ten levels in order with the curve, each with its activities, benefits and recent grants, and Trading there is the track it already served; with the switch off nothing is granted. Tables, functions and hunks % ms; probe % ms; in all % ms.',
    round(v_ms_make), round(v_ms_probe), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
