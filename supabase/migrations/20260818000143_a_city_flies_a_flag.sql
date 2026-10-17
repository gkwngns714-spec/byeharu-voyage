-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0143 — A CITY FLIES A FLAG  (docs/INFLUENCE.md slice I1)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17: "like uncharted [waters], i want to have influence of major countries, so that each
-- country can compete" — and (O1) "each country will have 3~4 cities around them, and rest of them
-- can be competitive". Then: "make the game — country region influences and all like uncharted
-- [waters]": docs/INFLUENCE.md approved with D1–D14 as written, plus (UW) a company CHOOSES its
-- country at founding (default Portugal) and may change it later, with a cooldown.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) ONE NEW FACT: public.port_allegiance(port_id, nation_id, home, since) — the country that
--     holds a harbour today. Seeded = ports.nation_id (D2: nothing changes hands on day one), with
--     `home` from data/home-ports.json (D1: 82 home cities, 3–4 a country) and the 10 top-up homes
--     (a free harbour today, made its country's home) given their country. ports.nation_id stays
--     as the authored FOUNDING country (the world guard holds it equal to data/ports.json); no game
--     rule reads it any more. A trigger refuses any change to a home row's country or home flag.
-- (2) ONE READER: public.port_nation(p_port) (PL/pgSQL). world.snapshot's port `nation`,
--     world.inn_chance (the inn's officers, 0073), public.yard_wrong_country (the build yard's
--     country rule, 0130) and public.skill_taught_at (the academy's, 0131) are re-cut to read it
--     (D13: one concept, "the country a city belongs to"). world.inn reads an OFFICER's country,
--     not the port's, and is untouched (the plan's §2 listed it; the live body says otherwise).
-- (3) world.allegiance() → {at, ports: [{port, nation, home, since}]} (authenticated, registered):
--     what the city panel's title line and the map (Regions on) print (D14).
-- (4) A COMPANY CHOOSES ITS COUNTRY (owner, 2026-10-17). cmd.found_house already took a nation
--     code (default PRT); the house now starts in its country's CAPITAL (Portugal's is Lisbon, so a
--     Portuguese founding is byte-identical). cmd.change_country(code) changes it, once every
--     nation_change_cooldown_days (7) REAL days, read by public.nation_change_next_at alone (from
--     the NATION_CHANGED events — derived, never a counter, the 0014 rule). It moves no money. What
--     the company leaves behind — its influence counts for the old country, any mayorship — is
--     kept by I2 (the book is keyed by the country at the moment of giving) and I5 (a mayor is a
--     citizen of the holder). world.player serves `nation_change_at`.
-- (5) THE DEFECT behind "city_shares has 0 rows on prod although the city economy is on"
--     (docs/INFLUENCE.md, open item). Read on prod, read-only, 2026-10-17 12:30 UTC: every reconcile
--     run takes 62–71 s; npc_upkeep_budget_seconds is 60; npc_houses.invested_at is null for all 821
--     companies. public.tick_reconcile (0137) sets ONE deadline at the start of the hour and gives
--     it to every step, so by the time the companies' step runs (after ~800 merchant steps) the
--     deadline has passed and public.npc_invest defers EVERY company (npc_upkeep_spent() is true at
--     its first iteration). 0123 meant the investment to run "under the 0114 budget"; 0137 put it
--     behind the routes, where no budget is left. FIX: the companies' step gets its own budget
--     (npc_upkeep_budget_seconds from the moment it starts) — one hunk. Nothing a step decides moves.
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * NOT THE OWNER'S — a house founded under another country starts in that country's capital. The
--   owner asked for the choice; where she starts was not said. Portugal's start is unchanged.
-- * NOT THE OWNER'S — the cooldown is counted from the last change, not from the founding (a new
--   house may change once at once). E_SAME_NATION refuses a change to the country she already has.
-- * The 10 top-up homes (Livorno, Nuuk, Tórshavn, Hội An, Mumbai, Surabaya, Tallinn, Hadibu,
--   Muscat, Manama) are the ONLY visible change: the yard, academy and inn rules now see them as
--   their new country's (asserted: every other answer equals its pre-image).
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- (a) No function in public / cmd / world / voyage mentions nation_id except port_nation and the
--     named company / officer readers (a scan, both directions). (b) Byte parity, pre-image vs new:
--     world.snapshot (every key; ports[].nation differs ONLY at the 10 top-ups, null → its country),
--     world.inn_chance on a spread of (officer, port) pairs, yard_wrong_country for every (hull,
--     yard), skill_taught_at for every skill at a spread of harbours — every difference at a top-up.
--     (c) A home row's country cannot be changed. (d) Every re-cut body reverses to its pre-image;
--     ACL / volatility / definer / config / language / owner unmoved. (e) A probe house (rolled
--     back) founded under Castile starts at Seville; changes to England (event, purse unmoved);
--     is refused E_TOO_SOON, E_SAME_NATION and E_NO_SUCH_NATION; world.player says when. (f) The
--     companies' step's scope is fresh; the merchants' still share the hour's deadline.
-- Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE / INSERT on a new table; CREATE OR REPLACE FUNCTION / PROCEDURE; knob INSERT. The
-- probes' writes are rolled back. No LOCK TABLE, no set role.
--
-- ROLLBACK: a forward migration restoring the re-cut bodies (each is here as the hunks' OLD text);
-- port_allegiance can stay (nothing else reads it until I2).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once: world.snapshot (0135), world.inn_chance (0073), public.yard_wrong_country (0130),
-- public.skill_taught_at (0131), public.tick_reconcile (0137), world.player (0069),
-- cmd.found_house (0011), public.client_rpc_entry_points (0131).
-- VERSION: 0143. Applies on prod head 0140 (0141 / 0142 in flight touch none of these bodies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0143(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES (bodies, attributes, and the answers the parity proof compares) ──────────
create temp table defs_before_0143 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang
  from (values ('world.snapshot()'),
               ('world.inn_chance(uuid, uuid)'),
               ('public.yard_wrong_country(uuid, text)'),
               ('public.skill_taught_at(uuid, uuid)'),
               ('public.tick_reconcile(boolean)'),
               ('world.player()'),
               ('cmd.found_house(text, text)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table pre_0143_snapshot on commit drop as select world.snapshot() as j;

create temp table pre_0143_inn on commit drop as
select o.id as officer_id, p.id as port_id, world.inn_chance(o.id, p.id)::text as v
  from (select id from public.officers order by md5(id::text || '0143') limit 40) o
 cross join (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || '0143i') limit 30) p;

create temp table pre_0143_yard on commit drop as
select p.id as port_id, c.code as class_code, public.yard_wrong_country(p.id, c.code) as v
  from public.ports p
  join public.port_buildings b on b.port_id = p.id and b.kind = 'building_yard'
 cross join public.ship_classes c;

create temp table pre_0143_skill on commit drop as
select s.id as skill_id, p.id as port_id, public.skill_taught_at(s.id, p.id)::text as v
  from public.skills s
 cross join (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || '0143s') limit 40) p;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('nation_change_cooldown_days', to_jsonb(7),
   '0143: a company may change its country once every this many REAL days (owner, 2026-10-17: '
   'like Uncharted Waters, a company belongs to a country and can change it). Read by '
   'public.nation_change_next_at alone.')
on conflict (key) do nothing;

-- ── 3. THE FACT: who holds a harbour ───────────────────────────────────────────────────────────
create table public.port_allegiance (
  port_id   uuid primary key references public.ports(id) on delete cascade,
  nation_id uuid references public.nations(id),
  home      boolean not null default false,
  since     timestamptz not null default now(),
  constraint port_allegiance_home_has_a_country check (not home or nation_id is not null)
);
comment on table public.port_allegiance is
  '0143 (docs/INFLUENCE.md): the country that holds a harbour TODAY. Read through public.port_nation '
  'alone. `home` (authored, data/home-ports.json, rule D1) marks a city that never changes hands. '
  'ports.nation_id is the founding record and is read by no game rule.';
comment on column public.ports.nation_id is
  'The FOUNDING country (authored, data/ports.json; the world guard holds it). Since 0143 no game rule '
  'reads it: the country a harbour belongs to today is public.port_nation(port).';
alter table public.port_allegiance enable row level security;
revoke all on table public.port_allegiance from public, anon, authenticated;

create temp table homes_0143 (nation text, ports text[]) on commit drop;
insert into homes_0143 values
  ('AYU', array['AYU', 'PTT', 'HOI']),
  ('BAN', array['BNT', 'JAK', 'SUR']),
  ('DNK', array['COP', 'BER', 'TRO', 'REY']),
  ('ENG', array['LON', 'PTH', 'KIN', 'PLY']),
  ('ESP', array['SVQ', 'SNL', 'CAD', 'CEU']),
  ('FRA', array['MRS', 'TOU', 'LAR', 'NAN']),
  ('GEN', array['GOA', 'CHS', 'LIV']),
  ('GUJ', array['KHA', 'SRT', 'MUM']),
  ('HAN', array['HAM', 'LUB', 'TOR']),
  ('JOS', array['BUS', 'ULS', 'TON', 'YEO']),
  ('JPN', array['SAK', 'OSA', 'TOK', 'KAG']),
  ('MAR', array['SAF', 'AGA', 'SAL', 'TAN']),
  ('MLB', array['KOZ', 'KAN', 'KOC', 'MNG']),
  ('MNG', array['GUA', 'XIA', 'QUA', 'FUZ']),
  ('MUG', array['KAR', 'CHI', 'HAD']),
  ('NLD', array['AMS', 'HRN', 'ROT', 'MID']),
  ('OTT', array['IST', 'IZM', 'THE', 'RHO']),
  ('PER', array['BAS', 'MUS', 'MAN']),
  ('POL', array['GDA', 'RIG', 'TAL']),
  ('PRT', array['LIS', 'SET', 'OPO', 'FNC']),
  ('RUS', array['ARK', 'KAL', 'NUU']),
  ('SWE', array['STO', 'VIS', 'TUR']),
  ('VEN', array['VEN', 'COR', 'ZAK', 'HER']);

do $$
declare
  v_bad text;
begin
  -- every home is a harbour, home to one country, owned by nobody else; every country has 3 or 4
  select string_agg(x.code, ', ') into v_bad
    from (select unnest(ports) as code from homes_0143) x
   where not exists (select 1 from public.ports p where p.code = x.code and p.kind = 'HARBOUR');
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: home cities that are not harbours: %', v_bad;
  end if;
  if (select count(*) from (select unnest(ports) from homes_0143) x) <> (select count(distinct c) from homes_0143, unnest(ports) c) then
    raise exception '0143 self-assert FAIL: a harbour is home to two countries';
  end if;
  if exists (select 1 from homes_0143 where cardinality(ports) not between 3 and 4)
     or (select count(*) from homes_0143) <> (select count(*) from public.nations)
     or exists (select 1 from public.nations n where not exists (select 1 from homes_0143 h where h.nation = n.code)) then
    raise exception '0143 self-assert FAIL: every country must have 3 or 4 home cities';
  end if;
  select string_agg(format('%s (%s, founded %s)', p.code, h.nation, n.code), ', ') into v_bad
    from homes_0143 h cross join unnest(h.ports) c
    join public.ports p on p.code = c
    join public.nations n on n.id = p.nation_id
   where n.code <> h.nation;
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: a home city was taken from another country: %', v_bad;
  end if;
  if exists (select 1 from public.ports p where p.kind <> 'HARBOUR' and p.nation_id is not null) then
    raise exception '0143 self-assert FAIL: a sea place carries a country; port_allegiance holds harbours only';
  end if;
end $$;

insert into public.port_allegiance (port_id, nation_id, home)
select p.id,
       coalesce(p.nation_id, (select n.id from homes_0143 h join public.nations n on n.code = h.nation where p.code = any(h.ports))),
       exists (select 1 from homes_0143 h where p.code = any(h.ports))
  from public.ports p
 where p.kind = 'HARBOUR';

create or replace function public.port_allegiance_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
-- 0143: A HOME CITY NEVER CHANGES HANDS (OWNER O1). Its country and its home flag are authored
-- (data/home-ports.json); a migration that re-authors the list disables this trigger by name, in
-- the open, for that statement.
begin
  if old.home is distinct from new.home then
    raise exception 'E_HOME_CITY: whether a city is a home city is authored (data/home-ports.json), never played'
      using errcode = 'P0001';
  end if;
  if old.home and new.nation_id is distinct from old.nation_id then
    raise exception 'E_HOME_CITY: % is a home city; it never changes hands',
      (select p.name from public.ports p where p.id = old.port_id) using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.port_allegiance_guard() from public, anon, authenticated;
create trigger port_allegiance_home_never_changes
  before update on public.port_allegiance
  for each row execute function public.port_allegiance_guard();

create or replace function public.port_nation(p_port uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0143: THE ONE READER of the country a harbour belongs to today (docs/INFLUENCE.md D13): the build
-- yard's country rule, the academy's, the inn's officers, the snapshot and the map all follow it.
-- Null for a harbour no country holds, and for a sea place.
begin
  return (select a.nation_id from public.port_allegiance a where a.port_id = p_port);
end $$;
comment on function public.port_nation(uuid) is
  '0143: THE one reader of the country a harbour belongs to today (public.port_allegiance). Server-only.';
revoke all on function public.port_nation(uuid) from public, anon, authenticated;

create or replace function world.allegiance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0143: every harbour's flag — the country that holds it (public.port_nation), whether it is a home
-- city, and since when. The city panel's title line and the map (Regions on) print it (D14).
-- A harbour no country holds is served with nation null.
begin
  return jsonb_build_object('at', now(), 'ports', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'port', p.code, 'nation', n.code, 'home', a.home, 'since', a.since) order by p.code), '[]'::jsonb)
      from public.port_allegiance a
      join public.ports p on p.id = a.port_id
      left join public.nations n on n.id = public.port_nation(p.id)));
end $$;
comment on function world.allegiance() is
  '0143: every harbour''s flag {port, nation, home, since}. Authenticated; registered.';
revoke all on function world.allegiance() from public, anon;
grant execute on function world.allegiance() to authenticated;

-- ── 4. A COMPANY'S COUNTRY ─────────────────────────────────────────────────────────────────────
create or replace function public.nation_change_next_at(p_player uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0143: THE one reading of when a company may next change its country: its last NATION_CHANGED
-- event + nation_change_cooldown_days REAL days, or null when it may change now (never changed, or
-- the cooldown has run). Derived from the events, never stored.
declare
  v_last timestamptz;
  v_next timestamptz;
begin
  select max(e.created_at) into v_last from public.events e
   where e.player_id = p_player and e.kind = 'NATION_CHANGED';
  if v_last is null then
    return null;
  end if;
  v_next := v_last + make_interval(days => public.wc_int('nation_change_cooldown_days'));
  return case when v_next > now() then v_next end;
end $$;
revoke all on function public.nation_change_next_at(uuid) from public, anon, authenticated;

create or replace function cmd.change_country(p_nation_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0143: the caller's company changes its country (owner, 2026-10-17: like Uncharted Waters, a
-- company belongs to a country and may change it), once every nation_change_cooldown_days real days
-- (public.nation_change_next_at). Moves no money. What it leaves behind stays with the old country:
-- the influence it gave (I2 keys the book by the country at the moment of giving) and any mayorship
-- (I5: a mayor is a citizen of the country that holds the city).
declare
  v_player uuid := public.current_player_id();
  v_from   public.nations%rowtype;
  v_to     public.nations%rowtype;
  v_next   timestamptz;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    select n.* into v_to from public.nations n where n.code = upper(btrim(coalesce(p_nation_code, '')));
    if v_to.id is null then
      perform cmd.refuse('E_NO_SUCH_NATION', format('no country answers to "%s"', coalesce(p_nation_code, '')));
    end if;
    perform 1 from public.players where id = v_player for update;
    select n.* into v_from from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = v_player;
    if v_from.id = v_to.id then
      perform cmd.refuse('E_SAME_NATION', format('your company already sails for %s', v_to.name));
    end if;
    v_next := public.nation_change_next_at(v_player);
    if v_next is not null then
      perform cmd.refuse('E_TOO_SOON', format('a company changes its country once every %s days; the next change opens %s UTC',
                                              public.wc_int('nation_change_cooldown_days'),
                                              to_char(v_next at time zone 'UTC', 'YYYY-MM-DD HH24:MI')));
    end if;
    update public.players set nation_id = v_to.id where id = v_player;
    perform public.emit_event(v_player, 'NATION_CHANGED', jsonb_build_object(
      'from', v_from.code, 'from_name', v_from.name, 'to', v_to.code, 'to_name', v_to.name));
    return jsonb_build_object('ok', true, 'nation', v_to.code, 'nation_name', v_to.name,
                              'nation_change_at', public.nation_change_next_at(v_player));
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;
comment on function cmd.change_country(text) is
  '0143: the caller''s company changes its country (cooldown nation_change_cooldown_days). Registered.';
revoke all on function cmd.change_country(text) from public, anon;
grant execute on function cmd.change_country(text) to authenticated;

-- ── 5. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0143 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0143 values
('world.snapshot()', 1,
$h$      left join public.nations n on n.id = p.nation_id
      join public.seas s on s.id = p.sea_id$h$,
$h$      -- 0143: the country that holds it today (public.port_nation), not the founding record.
      left join public.nations n on n.id = public.port_nation(p.id)
      join public.seas s on s.id = p.sea_id$h$),
('world.inn_chance(uuid, uuid)', 1,
$h$           when o.nation_id is not null and o.nation_id = p.nation_id then public.wc_num('inn_weight_nation')$h$,
$h$           when o.nation_id is not null and o.nation_id = public.port_nation(p.id) then public.wc_num('inn_weight_nation')   -- 0143$h$),
('public.yard_wrong_country(uuid, text)', 1,
$h$  left join public.nations n on n.id = p.nation_id
 where c.code = p_class$h$,
$h$  left join public.nations n on n.id = public.port_nation(p.id)   -- 0143: the country that holds it today
 where c.code = p_class$h$),
('public.skill_taught_at(uuid, uuid)', 1,
$h$  left join public.nations n on n.id = p.nation_id
 where s.id = p_skill$h$,
$h$  left join public.nations n on n.id = public.port_nation(p.id)   -- 0143: the country that holds it today
 where s.id = p_skill$h$),
('public.tick_reconcile(boolean)', 1,
$h$  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_step := public.npc_tend_houses(v_now);$h$,
$h$  -- 0143: THE COMPANIES' STEP HAS ITS OWN BUDGET. With one deadline for the whole hour the routes
  -- spent it (prod: 62–71 s against 60) and npc_invest deferred every company, every hour — no
  -- merchant ever invested (city_shares 0 rows, invested_at null for all 821).
  perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
  begin
    v_step := public.npc_tend_houses(v_now);$h$),
('world.player()', 1,
$h$      'levels',        public.player_progress(v_id)));$h$,
$h$      'levels',        public.player_progress(v_id),
      -- 0143: when the company may next change its country (null: it may now).
      'nation_change_at', public.nation_change_next_at(v_id)));$h$),
('cmd.found_house(text, text)', 1,
$h$    v_player := public.new_house(v_uid, v_name, v_nation);$h$,
$h$    -- 0143: a house starts in its country's capital (Portugal's is Lisbon, as it always was).
    v_player := public.new_house(v_uid, v_name, v_nation,
                                 (select n.capital_port_code from public.nations n where n.code = v_nation));$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'npc_fleet_card',        'uuid')
    ) as t(s, f, a)$h$,
$h$      ('world',       'npc_fleet_card',        'uuid'),
      -- 0143: every harbour's flag, and a company's change of country (docs/INFLUENCE.md I1).
      ('world',       'allegiance',            ''),
      ('cmd',         'change_country',        'text')
    ) as t(s, f, a)$h$);

create or replace function pg_temp.recut_0143(p_fn text)
returns text
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0143 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0143 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0143(v_def, h.old);
    if v_n <> 1 then
      raise exception '0143 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  return v_def;
end $$;

-- every hunk is checked against its live body BEFORE anything is replaced
create temp table recut_0143 on commit drop as
select fn, pg_temp.recut_0143(fn) as def from defs_before_0143;

do $$
declare
  r record;
begin
  for r in select * from recut_0143 order by fn loop
    execute r.def;
  end loop;
end $$;

-- ── 6. THE PROOF ───────────────────────────────────────────────────────────────────────────────
create temp table proven_0143 (k text primary key, v text) on commit drop;

-- (d) every re-cut reverses to its pre-image; attributes unmoved
do $$
declare
  d record;
  h record;
  v_now text;
  v_rev text;
begin
  for d in select * from defs_before_0143 loop
    v_now := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_rev := v_now;
    for h in select * from hunks_0143 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0143(v_rev, h.new) <> 1 then
        raise exception '0143 self-assert FAIL: % — the new text of hunk % is not in the live body exactly once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0143 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg
       or (select p.proparallel from pg_proc p where p.oid = d.fn::regprocedure) <> d.par
       or (select p.proowner from pg_proc p where p.oid = d.fn::regprocedure) <> d.owner
       or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = d.fn::regprocedure) <> d.lang then
      raise exception '0143 self-assert FAIL: % — ACL, volatility, definer, config, parallel, owner or language moved', d.fn;
    end if;
  end loop;
  insert into proven_0143 values ('recut', (select count(*) from defs_before_0143)::text || ' bodies reverse to their pre-images, attributes unmoved');
end $$;

-- (a) THE SCAN: who still mentions nation_id
do $$
declare
  v_allowed text[] := array[
    -- the ONE reader of a port's country, the change of a company's country, and the
    -- home-row guard
    'public.port_nation', 'cmd.change_country', 'public.port_allegiance_guard',
    -- a COMPANY's country (players.nation_id)
    'public.new_house', 'world.player', 'world.standings', 'world.npc_fleet_card', 'world.port_merchants',
    'world.route_board', 'world.sea_roster', 'world.sea_traffic',
    -- an OFFICER's country (officers.nation_id) — inn_chance compares it with public.port_nation
    'world.inn', 'world.inn_chance', 'world.officers'];
  v_extra text;
  v_gone  text;
begin
  select string_agg(x.fn, ', ' order by x.fn) into v_extra
    from (select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%nation_id%') x
   where x.fn <> all(v_allowed);
  if v_extra is not null then
    raise exception '0143 self-assert FAIL: these functions read a nation_id and are not a named reader: % — a port''s country is public.port_nation(port) alone', v_extra;
  end if;
  select string_agg(a, ', ') into v_gone
    from unnest(v_allowed) a
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname || '.' || p.proname = a and p.prosrc like '%nation_id%');
  if v_gone is not null then
    raise exception '0143 self-assert FAIL: the allow-list names functions that no longer read a nation_id: % (keep the list exact)', v_gone;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage')
                and (p.prosrc like '%p.nation_id = %' and p.proname in ('inn_chance', 'yard_wrong_country', 'skill_taught_at', 'snapshot'))) then
    raise exception '0143 self-assert FAIL: a re-cut port reader still compares p.nation_id';
  end if;
  insert into proven_0143 values ('scan', format('nation_id is read by %s named functions only; a port''s country by public.port_nation', cardinality(v_allowed)));
end $$;

-- (b) PARITY, except at the 10 top-up homes
create temp table topups_0143 on commit drop as
select p.id as port_id, p.code, n.code as nation
  from homes_0143 h cross join unnest(h.ports) c
  join public.ports p on p.code = c
  join public.nations n on n.code = h.nation
 where p.nation_id is null;

do $$
declare
  v_pre   jsonb := (select j from pre_0143_snapshot);
  v_post  jsonb := world.snapshot();
  v_bad   text;
  v_n     int;
  v_moved int;
begin
  if (select count(*) from topups_0143) <> 10 then
    raise exception '0143 self-assert FAIL: % top-up homes, the plan computes 10', (select count(*) from topups_0143);
  end if;
  if (v_pre - 'ports') <> (v_post - 'ports') then
    raise exception '0143 self-assert FAIL: world.snapshot moved outside ports[]';
  end if;
  if jsonb_array_length(v_pre->'ports') <> jsonb_array_length(v_post->'ports') then
    raise exception '0143 self-assert FAIL: world.snapshot serves a different number of ports';
  end if;
  select string_agg(a.e->>'code', ', '), count(*) into v_bad, v_n
    from jsonb_array_elements(v_pre->'ports') with ordinality a(e, i)
    join jsonb_array_elements(v_post->'ports') with ordinality b(e, i) on b.i = a.i
   where (a.e - 'nation') <> (b.e - 'nation')
      or ((a.e->'nation') is distinct from (b.e->'nation')
          and not exists (select 1 from topups_0143 t where t.code = a.e->>'code'
                            and a.e->>'nation' is null and b.e->>'nation' = t.nation));
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: world.snapshot ports moved outside the top-ups: %', v_bad;
  end if;
  select count(*) into v_moved
    from jsonb_array_elements(v_post->'ports') e join topups_0143 t on t.code = e->>'code'
   where e->>'nation' = t.nation;
  if v_moved <> 10 then
    raise exception '0143 self-assert FAIL: % of the 10 top-up homes fly their country in the snapshot', v_moved;
  end if;

  select string_agg(format('%s@%s', x.officer_id, x.port_id), ', ') into v_bad
    from pre_0143_inn x
   where world.inn_chance(x.officer_id, x.port_id)::text is distinct from x.v
     and x.port_id not in (select port_id from topups_0143);
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: world.inn_chance moved outside the top-ups: %', v_bad;
  end if;
  select string_agg(format('%s@%s', x.class_code, x.port_id), ', ') into v_bad
    from pre_0143_yard x
   where public.yard_wrong_country(x.port_id, x.class_code) is distinct from x.v
     and x.port_id not in (select port_id from topups_0143);
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: public.yard_wrong_country moved outside the top-ups: %', v_bad;
  end if;
  select string_agg(format('%s@%s', x.skill_id, x.port_id), ', ') into v_bad
    from pre_0143_skill x
   where public.skill_taught_at(x.skill_id, x.port_id)::text is distinct from x.v
     and x.port_id not in (select port_id from topups_0143);
  if v_bad is not null then
    raise exception '0143 self-assert FAIL: public.skill_taught_at moved outside the top-ups: %', v_bad;
  end if;
  -- the fact equals the founding record everywhere but the top-ups
  if exists (select 1 from public.ports p
              where p.kind = 'HARBOUR' and p.id not in (select port_id from topups_0143)
                and public.port_nation(p.id) is distinct from p.nation_id)
     or (select count(*) from public.port_allegiance) <> (select count(*) from public.ports where kind = 'HARBOUR')
     or (select count(*) from public.port_allegiance where home) <> (select count(*) from homes_0143, unnest(ports)) then
    raise exception '0143 self-assert FAIL: port_allegiance is not ports.nation_id + the top-ups, or the home count is off';
  end if;
  insert into proven_0143 values ('parity', format('snapshot (%s ports), %s inn chances, %s yard answers, %s skill answers equal their pre-images outside the 10 top-up homes',
    jsonb_array_length(v_post->'ports'), (select count(*) from pre_0143_inn), (select count(*) from pre_0143_yard), (select count(*) from pre_0143_skill)));
end $$;

-- (c) a home row's country cannot be changed; a home flag cannot be played
do $$
declare
  v_port uuid := (select port_id from public.port_allegiance where home order by port_id limit 1);
  v_free uuid := (select port_id from public.port_allegiance where not home order by port_id limit 1);
  v_ok   boolean;
begin
  begin
    update public.port_allegiance set nation_id = (select id from public.nations where id <> (select nation_id from public.port_allegiance where port_id = v_port) order by code limit 1)
     where port_id = v_port;
    v_ok := false;
  exception when others then
    if sqlerrm not like 'E_HOME_CITY:%' then raise; end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '0143 self-assert FAIL: a home city changed hands';
  end if;
  begin
    update public.port_allegiance set home = true where port_id = v_free;
    v_ok := false;
  exception when others then
    if sqlerrm not like 'E_HOME_CITY:%' then raise; end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '0143 self-assert FAIL: a contested city was made a home city by an UPDATE';
  end if;
  insert into proven_0143 values ('home', 'a home city''s country and the home flag refuse an UPDATE (E_HOME_CITY)');
end $$;

-- (e) a company's country: founding under Castile, a change, the three refusals
create or replace function pg_temp.probe_0143()
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0143-4000-8000-000000000001';
  v_base   int := (select count(*) from public.players);
  v_r      jsonb;
  v_player uuid;
  v_ducats bigint;
  v_out    jsonb;
begin
  begin
    perform cmd.assume_identity(c_uid);   -- both JWT shapes: the PGlite shim's and Supabase's
    v_r := cmd.found_house('Casa da Bandeira 0143', 'esp');
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0143 self-assert FAIL: founding under Castile was refused: %', v_r;
    end if;
    v_player := (v_r->>'player_id')::uuid;
    if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.player_id = v_player)
       <> (select capital_port_code from public.nations where code = 'ESP')
       or (select n.code from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = v_player) <> 'ESP' then
      raise exception '0143 self-assert FAIL: a Castilian house did not start at Castile''s capital';
    end if;
    if (world.player()->'player'->>'nation_change_at') is not null then
      raise exception '0143 self-assert FAIL: a new house may not change its country at once';
    end if;
    select ducats into v_ducats from public.players where id = v_player;
    v_r := cmd.change_country('ENG');
    if not coalesce((v_r->>'ok')::boolean, false) or v_r->>'nation' <> 'ENG'
       or (select n.code from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = v_player) <> 'ENG'
       or (select count(*) from public.events where player_id = v_player and kind = 'NATION_CHANGED'
             and payload->>'from' = 'ESP' and payload->>'to' = 'ENG') <> 1
       or (select ducats from public.players where id = v_player) <> v_ducats then
      raise exception '0143 self-assert FAIL: a change of country did not move the country, the event and nothing else: %', v_r;
    end if;
    if (world.player()->'player'->>'nation_change_at')::timestamptz
       is distinct from (select max(created_at) from public.events where player_id = v_player and kind = 'NATION_CHANGED')
                        + make_interval(days => public.wc_int('nation_change_cooldown_days')) then
      raise exception '0143 self-assert FAIL: world.player does not say when the next change opens';
    end if;
    v_out := jsonb_build_object('soon', cmd.change_country('FRA')->>'error_code',
                                'same', cmd.change_country('ENG')->>'error_code',
                                'none', cmd.change_country('XXX')->>'error_code',
                                'start', (select capital_port_code from public.nations where code = 'ESP'));
    perform public.assert_ledger_reconciles(v_player);
    raise exception 'PROBE_ROLLBACK_0143';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0143' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if (select count(*) from public.players) <> v_base then
    raise exception '0143 self-assert FAIL: the probe did not leave the world as it found it';
  end if;
  return v_out;
end $$;

do $$
declare
  v jsonb := pg_temp.probe_0143();
begin
  if v->>'soon' <> 'E_TOO_SOON' or v->>'same' <> 'E_SAME_NATION' or v->>'none' <> 'E_NO_SUCH_NATION' then
    raise exception '0143 self-assert FAIL: the change of country did not refuse as it should: %', v;
  end if;
  insert into proven_0143 values ('country', format('a house founded under Castile starts at %s; ESP → ENG moves the country and the event, not a ducat; then %s / %s / %s',
    v->>'start', v->>'soon', v->>'same', v->>'none'));
end $$;

-- (f) the companies' step has its own budget; the merchants still share the hour's
do $$
declare
  v_def text := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  v_old text := (select def from defs_before_0143 where fn = 'public.tick_reconcile(boolean)');
begin
  if pg_temp.occurs_0143(v_def, 'perform public.npc_upkeep_scope(v_deadline);') <> pg_temp.occurs_0143(v_old, 'perform public.npc_upkeep_scope(v_deadline);') - 1
     or pg_temp.occurs_0143(v_def, 'perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num(''npc_upkeep_budget_seconds'')));') <> 1
     or strpos(v_def, 'perform public.npc_upkeep_scope(clock_timestamp()') > strpos(v_def, 'v_step := public.npc_tend_houses(v_now);') then
    raise exception '0143 self-assert FAIL: the companies'' step does not open its own budget right before npc_tend_houses';
  end if;
  insert into proven_0143 values ('reconcile', 'the companies'' step opens its own npc_upkeep_budget_seconds; every merchant step keeps the hour''s deadline');
end $$;

-- (g) the registry: +2
do $$
begin
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('allegiance', 'change_country')) <> 2
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.function_name in ('allegiance', 'change_country')
                   and (e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))) then
    raise exception '0143 self-assert FAIL: world.allegiance / cmd.change_country are not registered and executable by authenticated';
  end if;
  if has_function_privilege('anon', 'world.allegiance()', 'execute')
     or has_function_privilege('authenticated', 'public.port_nation(uuid)', 'execute') then
    raise exception '0143 self-assert FAIL: a grant is wider than the contract';
  end if;
end $$;

do $$
begin
  raise notice '0143 self-assert ok: A CITY FLIES A FLAG — %',
    (select string_agg(k || ': ' || v, ' | ' order by k) from proven_0143);
end $$;
