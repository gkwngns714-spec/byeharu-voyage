-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0185 — THE GREAT POWERS  (docs/GREAT_POWERS.md, slice GP1)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-18: "make it 7 big power like uncharted island, spread mainly on europe and asia, as well
-- as islamic region" — "like uncharted island but different if it can" — and, after Uncharted
-- Waters Origin's eight were sourced (App Store: "8 national powers"; namu.wiki: Ming, Joseon and
-- Japan by immigration): "in asia add korea, in europe add more." Still binding (docs/INFLUENCE.md
-- O1): "each country will have 3~4 cities around them, and rest of them can be competitive".
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) ONE NEW FACT: public.great_powers(nation_id) — the TEN that race for cities: PRT ESP ENG NLD
--     FRA (Europe) · OTT MUG (the Islamic world) · MNG JOS JPN (Asia). Authored in
--     scripts/lib/world-derive.mjs GREAT_POWERS; the world guard holds it. ONE reader,
--     public.great_power(nation).
-- (2) THE INVARIANT IS DECLARED: players.nation_id, port_allegiance.nation_id and
--     port_influence.nation_id now reference great_powers. A company, a city's flag and a point of
--     influence belong to a great power or to nobody — so the citizen's tax cut, the coupons, the
--     mayors, the crown's tax and aid (public.city_capital reads public.port_nation) and the daily
--     count are right for ten without a line of their code changing.
-- (3) THE MOVE OF EXISTING STATE, conserved (docs/GREAT_POWERS.md §3):
--     * every company of one of the thirteen others sails for the NEAREST great power by its home
--       port (a player, who has none, by its old country's capital): the fewest sailed miles
--       (public.sea_reaches) to any of that power's four homes, ties by code. Its ink follows (0145's
--       table); one NATION_CHANGED {reason: 'great_powers'} each. Ducats, ships, cargo, route and
--       HOME PORT untouched (asserted);
--     * every influence row kept for a minor is re-keyed to its giver's country after the move,
--       merged where the giver already has a row there (Σ points asserted unchanged);
--     * the mayor of a city that goes to No country stands down (the daily count's own answer);
--     * port_allegiance: a city a minor holds goes to No country (D2 keeps every great power's); the
--       42 homes not in the ten's list come off (the 41 left of the minors' 43, and Hadibu); Surat
--       and Khambhat become Mughal homes. The home trigger is disabled BY NAME for those statements
--       and enabled again, in the open, as its own comment prescribes (0143).
-- (4) THE THIRTEEN ARE LOCAL RULERS. public.port_ruler(port): the minor power that founded a city
--     (ports.nation_id, the authored founding record), else null. public.port_countries(port): the
--     holder's code plus the ruler's. The build yard (public.yard_wrong_country), the line academy
--     (public.skill_taught_at) and the inn's countrywomen (world.inn_chance) compose it, one hunk
--     each — a ruler's hulls, line skills and captains stay in its own cities whoever holds the flag
--     (the Italian and the Arabia & India lines have no great-power builder at all). world.allegiance
--     serves `ruler`; world.snapshot's nations serve `great`.
-- (5) THE TEN ONLY: cmd.found_house and cmd.change_country refuse E_MINOR_POWER (naming the ten);
--     world.nation_standings lists the ten; public.nation_change_next_at does not count a move the
--     world made (reason 'great_powers') as the company's change, so it starts no cooldown.
--
-- ── DECISIONS TAKEN HERE — NOT THE OWNER'S, CONFIRM (docs/GREAT_POWERS.md §8) ──────────────────
-- * G0 the ten. G1 a minor's cities start at No country; its influence is credited to the givers'
--   new countries and the 00:47 count claims by D5. G2 companies by nearest home port, no weight
--   rebalance yet. G3 regional designs kept. G4 Mughal homes Karachi, Chittagong, Surat, Khambhat.
--   G5 a demoted capital keeps its standing purse (public.city_standing is not touched).
--
-- ── THE PROOF (in this file; each counts its own plan, never an ambient constant) ──────────────
-- (a) every re-cut reverses to its pre-image; ACL / volatility / definer / config / owner unmoved;
-- (b) W (Σ ducats + Σ purses) and Σ influence points unchanged; every company's ducats, ships,
--     fleets' places, home port and route unchanged; every company of a minor sits at its planned
--     power; no company, flag or point belongs to a minor; the foreign keys refuse one;
-- (c) yard / academy / inn answers equal their pre-images wherever a city's countries did not
--     change, and at every minor-ruled yard the ruler's line hulls are buildable;
-- (d) a probe house (rolled back) founded under Venice is refused E_MINOR_POWER; under Joseon starts
--     at Busan and is refused E_MINOR_POWER on a change to Venice; a world move starts no cooldown;
-- (e) world.nation_standings lists exactly the ten; world.allegiance serves Venice's ruler;
--     world.snapshot marks exactly ten nations great.
-- Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE great_powers; UPDATE players (the moved companies), npc_houses (their ink),
-- port_influence (re-key), port_mayor (delete), port_allegiance (the flags); ALTER TABLE … DROP / ADD
-- CONSTRAINT on players, port_allegiance, port_influence (ACCESS EXCLUSIVE for the validation scan,
-- ~1,100 / 238 / ~1,000 rows); ALTER TABLE port_allegiance DISABLE / ENABLE TRIGGER (named).
-- CREATE OR REPLACE FUNCTION. No LOCK TABLE, no set role, no set local, no begin. Deploy with the
-- clock unwound (docs/DEPLOY_RUNBOOK.md): the reconcile writes players and the daily count writes
-- the books.
--
-- ROLLBACK: the move is data — every company's NATION_CHANGED {reason: 'great_powers'} event records
-- from / to; a forward slice restores the bodies (each hunk's OLD text is here verbatim) and the three
-- foreign keys to public.nations. The flags and the books are the race's state from then on.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (read on prod at head 0181, LF-normalised, each asserted to
-- occur exactly once): world.snapshot (0135/0143), world.inn_chance (0166), public.yard_wrong_country
-- (0143), public.skill_taught_at (0151), world.nation_standings (0148), world.allegiance (0143),
-- cmd.found_house (0143), cmd.change_country (0143), public.nation_change_next_at (0143).
-- VERSION: 0185 = prod head + 1 (prod 0184, 2026-10-18 ~23:50 UTC; renumber if another lands first).
-- 0182–0184 touch none of these bodies or tables.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_gp1(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table gp1_t (step text primary key, at timestamptz not null default clock_timestamp()) on commit drop;
insert into gp1_t (step) values ('start');

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
do $$
begin
  if to_regclass('public.great_powers') is not null
     or to_regprocedure('public.great_power(uuid)') is not null
     or to_regprocedure('public.port_ruler(uuid)') is not null
     or to_regprocedure('public.port_countries(uuid)') is not null then
    raise exception 'GP1 self-assert FAIL: great_powers / great_power / port_ruler / port_countries already exist';
  end if;
end $$;

create temp table defs_before_gp1 on commit drop as
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
               ('world.nation_standings()'),
               ('world.allegiance()'),
               ('cmd.found_house(text, text)'),
               ('cmd.change_country(text)'),
               ('public.nation_change_next_at(uuid)')) f(fn);

-- what the conservation proof compares
create temp table pre_gp1_house on commit drop as
select pl.id as player_id, pl.is_npc, pl.ducats, pl.nation_id,
       (select n.code from public.nations n where n.id = pl.nation_id) as nation,
       h.home_port_id, h.ink,
       (select count(*) from public.ships s where s.player_id = pl.id) as ships,
       (select coalesce(string_agg(f.id::text || '@' || coalesce(f.port_id::text, '-'), ',' order by f.id), '')
          from public.fleets f where f.player_id = pl.id) as fleets,
       (select coalesce(string_agg(nf.fleet_id::text || '>' || coalesce(nf.route_id::text, '-'), ',' order by nf.fleet_id), '')
          from public.npc_fleets nf where nf.player_id = pl.id) as routes
  from public.players pl
  left join public.npc_houses h on h.player_id = pl.id;

create temp table pre_gp1_sums on commit drop as
select (select coalesce(sum(ducats), 0) from public.players)::numeric as ducats,
       (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric as purses,
       (select coalesce(sum(points), 0) from public.port_influence)::numeric as points,
       (select coalesce(sum(day_given), 0) from public.port_influence)::numeric as day_given,
       (select count(*) from public.port_mayor)::int as mayors;

-- the countries a city answered to before (its holder alone), and the answers parity compares
create temp table pre_gp1_holder on commit drop as
select a.port_id, a.nation_id, a.home, (select n.code from public.nations n where n.id = a.nation_id) as code
  from public.port_allegiance a;

create temp table pre_gp1_yard on commit drop as
select p.id as port_id, c.code as class_code, public.yard_wrong_country(p.id, c.code) as v
  from public.ports p
  join public.port_buildings b on b.port_id = p.id and b.kind = 'building_yard'
 cross join public.ship_classes c;

create temp table pre_gp1_skill on commit drop as
select s.id as skill_id, p.id as port_id, public.skill_taught_at(s.id, p.id)::text as v
  from public.skills s
 cross join (select distinct b.port_id as id from public.port_buildings b where b.kind = 'building_yard'
             union
             select id from (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || 'gp1s') limit 20) x) p;

create temp table pre_gp1_inn on commit drop as
select o.id as officer_id, p.id as port_id, world.inn_chance(o.id, p.id)::text as v
  from (select id from public.officers order by md5(id::text || 'gp1') limit 60) o
 cross join (select id from (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || 'gp1i') limit 30) x
             union
             select p.id from public.ports p join public.nations n on n.id = p.nation_id
              where n.code in ('DNK', 'SWE', 'POL', 'RUS', 'HAN', 'VEN', 'GEN', 'PER', 'MAR', 'AYU', 'GUJ', 'MLB', 'BAN')) p;

insert into gp1_t (step) values ('pre-images');

-- ── 2. THE FACT: the ten great powers ──────────────────────────────────────────────────────────
create table public.great_powers (
  nation_id uuid primary key references public.nations(id)
);
comment on table public.great_powers is
  'GP1 (docs/GREAT_POWERS.md): the ten countries that race for cities. Authored in '
  'scripts/lib/world-derive.mjs GREAT_POWERS; the world guard holds it. players.nation_id, '
  'port_allegiance.nation_id and port_influence.nation_id reference it. Read through public.great_power.';
alter table public.great_powers enable row level security;
revoke all on table public.great_powers from public, anon, authenticated;

insert into public.great_powers (nation_id)
select n.id from public.nations n
 where n.code in ('PRT', 'ESP', 'ENG', 'NLD', 'FRA', 'OTT', 'MUG', 'MNG', 'JOS', 'JPN');

do $$
begin
  if (select count(*) from public.great_powers) <> 10 then
    raise exception 'GP1 self-assert FAIL: % great powers seeded, the plan names 10', (select count(*) from public.great_powers);
  end if;
  if exists (select 1 from public.great_powers g join public.nations n on n.id = g.nation_id
              where n.capital_port_code is null
                 or not exists (select 1 from public.ports p where p.code = n.capital_port_code and p.kind = 'HARBOUR')) then
    raise exception 'GP1 self-assert FAIL: a great power has no capital harbour';
  end if;
end $$;

create or replace function public.great_power(p_nation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- GP1: THE one reader of "is this country one of the great powers" (public.great_powers).
  select exists (select 1 from public.great_powers g where g.nation_id = p_nation)
$$;
comment on function public.great_power(uuid) is
  'GP1: THE one reader of whether a country is a great power (public.great_powers). Server-only.';
revoke all on function public.great_power(uuid) from public, anon, authenticated;

create or replace function public.port_ruler(p_port uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- GP1: THE one reader of a city's LOCAL RULER — the minor power that founded it (ports.nation_id,
  -- the authored founding record), or null where its founder is a great power or nobody. It holds no
  -- influence and no flag; it is who the city's own people are (docs/GREAT_POWERS.md §4).
  select p.nation_id from public.ports p
   where p.id = p_port and p.nation_id is not null and not public.great_power(p.nation_id)
$$;
comment on function public.port_ruler(uuid) is
  'GP1: a city''s local ruler — the minor power that founded it, else null. Server-only.';
revoke all on function public.port_ruler(uuid) from public, anon, authenticated;

create or replace function public.port_countries(p_port uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- GP1: THE COUNTRIES WHOSE PEOPLE BUILD AND SAIL FROM A CITY: the country that holds it today
  -- (public.port_nation) and its local ruler (public.port_ruler). Composed by the build yard
  -- (public.yard_wrong_country), the line academy (public.skill_taught_at) and the inn's
  -- countrywomen (world.inn_chance) — a ruler's designs stay in its own cities whoever holds the
  -- flag (docs/GREAT_POWERS.md §5). Empty for a city nobody holds or rules.
  select coalesce(array_agg(n.code order by n.code), '{}'::text[])
    from public.nations n
   where n.id = public.port_nation(p_port) or n.id = public.port_ruler(p_port)
$$;
comment on function public.port_countries(uuid) is
  'GP1: the codes of the country holding a city and of its local ruler. Server-only.';
revoke all on function public.port_countries(uuid) from public, anon, authenticated;

-- ── 3. THE PLAN: the ten's homes, and where every company of a minor goes ──────────────────────
create temp table gp1_homes (nation text, ports text[]) on commit drop;
insert into gp1_homes values
  ('ENG', array['LON', 'PTH', 'KIN', 'PLY']),
  ('ESP', array['SVQ', 'SNL', 'CAD', 'CEU']),
  ('FRA', array['MRS', 'TOU', 'LAR', 'NAN']),
  ('JOS', array['BUS', 'ULS', 'TON', 'YEO']),
  ('JPN', array['SAK', 'OSA', 'TOK', 'KAG']),
  ('MNG', array['GUA', 'XIA', 'QUA', 'FUZ']),
  ('MUG', array['KAR', 'CHI', 'SRT', 'KHA']),
  ('NLD', array['AMS', 'HRN', 'ROT', 'MID']),
  ('OTT', array['IST', 'IZM', 'THE', 'RHO']),
  ('PRT', array['LIS', 'SET', 'OPO', 'FNC']);

do $$
declare
  v_bad text;
begin
  if (select count(*) from gp1_homes) <> 10
     or exists (select 1 from gp1_homes h where not exists (
                  select 1 from public.nations n join public.great_powers g on g.nation_id = n.id where n.code = h.nation))
     or exists (select 1 from gp1_homes where cardinality(ports) <> 4) then
    raise exception 'GP1 self-assert FAIL: the homes plan is not four homes for each of the ten';
  end if;
  if (select count(*) from gp1_homes, unnest(ports)) <> (select count(distinct c) from gp1_homes, unnest(ports) c) then
    raise exception 'GP1 self-assert FAIL: a harbour is home to two powers';
  end if;
  select string_agg(c, ', ') into v_bad from gp1_homes, unnest(ports) c
   where not exists (select 1 from public.ports p where p.code = c and p.kind = 'HARBOUR');
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: homes that are not harbours: %', v_bad;
  end if;
  -- a home is never taken from another GREAT power, and its capital is its first
  select string_agg(format('%s (%s, founded by %s)', p.code, h.nation, n.code), ', ') into v_bad
    from gp1_homes h cross join unnest(h.ports) c
    join public.ports p on p.code = c join public.nations n on n.id = p.nation_id
   where n.code <> h.nation and public.great_power(n.id);
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: a home would be taken from another great power: %', v_bad;
  end if;
  if exists (select 1 from gp1_homes h join public.nations n on n.code = h.nation where h.ports[1] <> n.capital_port_code) then
    raise exception 'GP1 self-assert FAIL: a power''s first home is not its capital';
  end if;
end $$;

create temp table gp1_moves on commit drop as
with movers as (
  select pl.id as player_id, pl.is_npc, pl.nation_id as from_nation,
         coalesce(hp.code, (select n.capital_port_code from public.nations n where n.id = pl.nation_id)) as origin
    from public.players pl
    left join public.npc_houses h on h.player_id = pl.id
    left join public.ports hp on hp.id = h.home_port_id
   where pl.nation_id is not null and not public.great_power(pl.nation_id)
), cand as (
  select m.player_id, g.nation as to_code,
         min(case when hc = m.origin then 0 else (sr.reaches->>hc)::numeric end) as nm
    from movers m
   cross join gp1_homes g
   cross join unnest(g.ports) hc
    left join public.sea_reaches sr on sr.code = m.origin
   group by m.player_id, g.nation
)
select distinct on (m.player_id) m.player_id, m.is_npc, m.from_nation, m.origin, n.id as to_nation, c.to_code, c.nm
  from movers m
  join cand c on c.player_id = m.player_id and c.nm is not null
  join public.nations n on n.code = c.to_code
 order by m.player_id, c.nm, c.to_code;

do $$
begin
  if (select count(*) from gp1_moves)
     <> (select count(*) from public.players pl where pl.nation_id is not null and not public.great_power(pl.nation_id)) then
    raise exception 'GP1 self-assert FAIL: % companies of a minor have no sailed distance to any great power''s home',
      (select count(*) from public.players pl where pl.nation_id is not null and not public.great_power(pl.nation_id))
      - (select count(*) from gp1_moves);
  end if;
  if exists (select 1 from public.players where nation_id is null) then
    raise exception 'GP1 self-assert FAIL: a company sails for no country; every company must sail for one before the foreign key';
  end if;
end $$;

-- ── 4. THE MOVE ────────────────────────────────────────────────────────────────────────────────
-- 4a. the companies: country, ink, one event each. Money, ships, routes and home ports: untouched.
create temp table gp1_ink (nation text primary key, ink text not null) on commit drop;
insert into gp1_ink values   -- 0145's nation → ink table, for the ten
  ('PRT', 'prt'), ('ESP', 'esp'), ('NLD', 'nld'), ('ENG', 'eng'), ('FRA', 'eng'),
  ('OTT', 'ott'), ('MUG', 'ott'), ('MNG', 'east'), ('JPN', 'east'), ('JOS', 'east');

update public.players pl set nation_id = m.to_nation from gp1_moves m where pl.id = m.player_id;
update public.npc_houses h set ink = i.ink
  from gp1_moves m join gp1_ink i on i.nation = m.to_code
 where h.player_id = m.player_id;
select count(public.emit_event(m.player_id, 'NATION_CHANGED', jsonb_build_object(
         'from', fn.code, 'from_name', fn.name, 'to', tn.code, 'to_name', tn.name, 'reason', 'great_powers',
         'port', m.origin, 'nm', round(m.nm))))
  from gp1_moves m join public.nations fn on fn.id = m.from_nation join public.nations tn on tn.id = m.to_nation;

-- 4b. the books: a point kept for a minor counts for the country its giver sails for now
create temp table gp1_rekey on commit drop as
select i.port_id, pl.nation_id as nation_id, i.player_id, sum(i.points) as points, sum(i.day_given) as day_given,
       min(i.updated_at) as updated_at, count(*) as rows_in,
       (select n.code from public.nations n where n.id = i.nation_id) as from_code
  from public.port_influence i
  join public.players pl on pl.id = i.player_id
 where not public.great_power(i.nation_id)
 group by i.port_id, pl.nation_id, i.player_id, i.nation_id;

delete from public.port_influence i where not public.great_power(i.nation_id);
insert into public.port_influence as x (port_id, nation_id, player_id, points, day_given, updated_at)
select r.port_id, r.nation_id, r.player_id, sum(r.points), sum(r.day_given), min(r.updated_at)
  from gp1_rekey r group by r.port_id, r.nation_id, r.player_id
on conflict (port_id, nation_id, player_id) do update
   set points = x.points + excluded.points,
       day_given = x.day_given + excluded.day_given,
       updated_at = least(x.updated_at, excluded.updated_at);

-- 4c. the flags. A home city never changes hands (0143's trigger); re-authoring the list is the one
--     case its own comment names, so it is disabled BY NAME for exactly these statements.
alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
--   the homes that are not the ten's come off …
update public.port_allegiance a set home = false
 where a.home
   and not exists (select 1 from gp1_homes h cross join unnest(h.ports) c join public.ports p on p.code = c where p.id = a.port_id);
--   … the ten's homes fly their power (Surat and Khambhat become Mughal) …
update public.port_allegiance a
   set home = true,
       nation_id = n.id,
       since = case when a.nation_id is distinct from n.id then now() else a.since end
  from gp1_homes h cross join unnest(h.ports) c
  join public.ports p on p.code = c
  join public.nations n on n.code = h.nation
 where p.id = a.port_id and (not a.home or a.nation_id is distinct from n.id);
--   … and a city a minor holds goes to No country (D2: a great power's are kept)
update public.port_allegiance a set nation_id = null, since = now()
 where a.nation_id is not null and not public.great_power(a.nation_id);
alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;

-- 4d. a mayor stands only for the country that holds the city (D8): the mayor of a city that went to
--     No country — or (generally) whose holder is no longer the mayor's country — stands down, which
--     is the daily count's own answer.
create temp table gp1_mayors_gone on commit drop as
select m.port_id, m.player_id from public.port_mayor m
  join public.port_allegiance a on a.port_id = m.port_id
  join public.players pl on pl.id = m.player_id
 where a.nation_id is null or pl.nation_id is distinct from a.nation_id;
delete from public.port_mayor m using gp1_mayors_gone g where m.port_id = g.port_id;

insert into gp1_t (step) values ('move');

-- ── 5. THE INVARIANT, DECLARED ─────────────────────────────────────────────────────────────────
alter table public.players drop constraint players_nation_id_fkey;
alter table public.players add constraint players_nation_is_a_great_power
  foreign key (nation_id) references public.great_powers(nation_id);
alter table public.port_allegiance drop constraint port_allegiance_nation_id_fkey;
alter table public.port_allegiance add constraint port_allegiance_nation_is_a_great_power
  foreign key (nation_id) references public.great_powers(nation_id);
alter table public.port_influence drop constraint port_influence_nation_id_fkey;
alter table public.port_influence add constraint port_influence_nation_is_a_great_power
  foreign key (nation_id) references public.great_powers(nation_id);

insert into gp1_t (step) values ('keys');

-- ── 6. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_gp1 (fn text, n int, old text, new text) on commit drop;

insert into hunks_gp1 values
('world.snapshot()', 1,
$h$        'capital', n.capital_port_code) order by n.code), '[]'::jsonb)                 -- 0028 WIND$h$,
$h$        'capital', n.capital_port_code,
        'great', public.great_power(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the ten great powers$h$),
('world.inn_chance(uuid, uuid)', 1,
$h$           when o.nation_id is not null and o.nation_id = public.port_nation(p.id) then public.wc_num('inn_weight_nation')   -- 0143$h$,
$h$           -- GP1: her country holds the city, or rules it (public.port_countries)
           when o.nation_id is not null
                and (select n.code from public.nations n where n.id = o.nation_id) = any(public.port_countries(p.id))
                then public.wc_num('inn_weight_nation')   -- 0143$h$),
('public.yard_wrong_country(uuid, text)', 1,
$h$    when n.code = any(sl.builder_nations) then null$h$,
$h$    -- GP1: the holder's line, or its local ruler's (a regional design, public.port_countries)
    when public.port_countries(p.id) && sl.builder_nations then null$h$),
('public.skill_taught_at(uuid, uuid)', 1,
$h$                and n.code = any(sl.builder_nations) then null$h$,
$h$                and public.port_countries(p.id) && sl.builder_nations then null   -- GP1: the holder's, or its ruler's$h$),
('world.nation_standings()', 1,
$h$          from public.nations n
          cross join lateral ($h$,
$h$          from public.nations n
          join public.great_powers g on g.nation_id = n.id   -- GP1: the ten race; a local ruler holds nothing
          cross join lateral ($h$),
('world.allegiance()', 1,
$h$             'port', p.code, 'nation', n.code, 'home', a.home, 'since', a.since) order by p.code), '[]'::jsonb)$h$,
$h$             'port', p.code, 'nation', n.code, 'home', a.home, 'since', a.since,
             -- GP1: the city's local ruler — the minor power that founded it (public.port_ruler)
             'ruler', (select r.code from public.nations r where r.id = public.port_ruler(p.id))) order by p.code), '[]'::jsonb)$h$),
('cmd.found_house(text, text)', 1,
$h$                  from public.nations));
  end if;$h$,
$h$                  from public.nations where public.great_power(id)));   -- GP1: the ten
  end if;

  -- GP1: a company sails for one of the ten great powers; the thirteen others rule their own cities.
  if not public.great_power((select id from public.nations where code = v_nation)) then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_MINOR_POWER',
      'error_message', format('%s rules its own cities, but a company sails for one of the ten great powers.',
                              (select name from public.nations where code = v_nation)),
      'fixes', (select jsonb_agg(format('(sail under %s — %s)', code, name) order by code)
                  from public.nations where public.great_power(id)));
  end if;$h$),
('cmd.change_country(text)', 1,
$h$      perform cmd.refuse('E_NO_SUCH_NATION', format('no country answers to "%s"', coalesce(p_nation_code, '')));
    end if;$h$,
$h$      perform cmd.refuse('E_NO_SUCH_NATION', format('no country answers to "%s"', coalesce(p_nation_code, '')));
    end if;
    -- GP1: a company sails for one of the ten great powers; the thirteen others rule their own cities.
    if not public.great_power(v_to.id) then
      perform cmd.refuse('E_MINOR_POWER', format('%s rules its own cities, but a company sails for one of the ten great powers',
                                                 v_to.name));
    end if;$h$),
('public.nation_change_next_at(uuid)', 1,
$h$   where e.player_id = p_player and e.kind = 'NATION_CHANGED';$h$,
$h$   where e.player_id = p_player and e.kind = 'NATION_CHANGED'
     and e.payload->>'reason' is distinct from 'great_powers';   -- GP1: a move the world made is not the company's change$h$);

create or replace function pg_temp.recut_gp1(p_fn text)
returns text
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_gp1 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_gp1 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_gp1(v_def, h.old);
    if v_n <> 1 then
      raise exception 'GP1 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  return v_def;
end $$;

-- every hunk is checked against its live body BEFORE anything is replaced
create temp table recut_gp1 on commit drop as
select fn, pg_temp.recut_gp1(fn) as def from defs_before_gp1;

do $$
declare
  r record;
begin
  if (select count(distinct fn) from hunks_gp1) <> (select count(*) from defs_before_gp1) then
    raise exception 'GP1 self-assert FAIL: a pre-imaged body has no hunk, or a hunk names a body not pre-imaged';
  end if;
  for r in select * from recut_gp1 order by fn loop
    execute r.def;
  end loop;
end $$;

insert into gp1_t (step) values ('recut');

-- ── 7. THE PROOF ───────────────────────────────────────────────────────────────────────────────
create temp table proven_gp1 (k text primary key, v text) on commit drop;

-- (a) every re-cut reverses to its pre-image; attributes unmoved
do $$
declare
  d record;
  h record;
  v_now text;
  v_rev text;
begin
  for d in select * from defs_before_gp1 loop
    v_now := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_rev := v_now;
    for h in select * from hunks_gp1 where fn = d.fn order by n desc loop
      if pg_temp.occurs_gp1(v_rev, h.new) <> 1 then
        raise exception 'GP1 self-assert FAIL: % — the new text of hunk % is not in the live body exactly once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception 'GP1 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg
       or (select p.proparallel from pg_proc p where p.oid = d.fn::regprocedure) <> d.par
       or (select p.proowner from pg_proc p where p.oid = d.fn::regprocedure) <> d.owner
       or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = d.fn::regprocedure) <> d.lang then
      raise exception 'GP1 self-assert FAIL: % — ACL, volatility, definer, config, parallel, owner or language moved', d.fn;
    end if;
  end loop;
  insert into proven_gp1 values ('recut', (select count(*) from defs_before_gp1)::text || ' bodies reverse to their pre-images, attributes unmoved');
end $$;

-- (b) CONSERVATION and the move as planned
do $$
declare
  v_s     record;
  v_bad   text;
  v_purse numeric := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t);
begin
  select * into v_s from pre_gp1_sums;
  if (select coalesce(sum(ducats), 0) from public.players) <> v_s.ducats or v_purse <> v_s.purses then
    raise exception 'GP1 self-assert FAIL: the world''s money moved (ducats % → %, purses % → %)',
      v_s.ducats, (select sum(ducats) from public.players), v_s.purses, v_purse;
  end if;
  if (select coalesce(sum(points), 0) from public.port_influence) <> v_s.points
     or (select coalesce(sum(day_given), 0) from public.port_influence) <> v_s.day_given then
    raise exception 'GP1 self-assert FAIL: influence was lost or made in the re-key (% → %)',
      v_s.points, (select sum(points) from public.port_influence);
  end if;
  -- every company: purse, ships, fleets' places, routes and home unmoved; ink moved only for the moved
  select string_agg(b.player_id::text, ', ') into v_bad
    from pre_gp1_house b
    join public.players pl on pl.id = b.player_id
    left join public.npc_houses h on h.player_id = pl.id
   where pl.ducats <> b.ducats
      or (select count(*) from public.ships s where s.player_id = pl.id) <> b.ships
      or (select coalesce(string_agg(f.id::text || '@' || coalesce(f.port_id::text, '-'), ',' order by f.id), '')
            from public.fleets f where f.player_id = pl.id) <> b.fleets
      or (select coalesce(string_agg(nf.fleet_id::text || '>' || coalesce(nf.route_id::text, '-'), ',' order by nf.fleet_id), '')
            from public.npc_fleets nf where nf.player_id = pl.id) <> b.routes
      or h.home_port_id is distinct from b.home_port_id
      or (h.ink is distinct from b.ink and not exists (select 1 from gp1_moves m where m.player_id = b.player_id));
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: a company''s purse, ships, fleets, route, home or ink moved: %', left(v_bad, 400);
  end if;
  if (select count(*) from public.players) <> (select count(*) from pre_gp1_house) then
    raise exception 'GP1 self-assert FAIL: the number of companies moved';
  end if;
  -- every company of a minor at its planned power; nobody else's country moved
  if exists (select 1 from gp1_moves m join public.players pl on pl.id = m.player_id where pl.nation_id <> m.to_nation)
     or exists (select 1 from pre_gp1_house b join public.players pl on pl.id = b.player_id
                 where pl.nation_id is distinct from b.nation_id
                   and not exists (select 1 from gp1_moves m where m.player_id = b.player_id)) then
    raise exception 'GP1 self-assert FAIL: a company is not at its planned country, or one that was not to move moved';
  end if;
  if exists (select 1 from gp1_moves m join public.npc_houses h on h.player_id = m.player_id
              join gp1_ink i on i.nation = m.to_code where h.ink <> i.ink) then
    raise exception 'GP1 self-assert FAIL: a moved company''s ink is not its new country''s';
  end if;
  if (select count(*) from public.events e join gp1_moves m on m.player_id = e.player_id
       where e.kind = 'NATION_CHANGED' and e.payload->>'reason' = 'great_powers') <> (select count(*) from gp1_moves) then
    raise exception 'GP1 self-assert FAIL: not one NATION_CHANGED event per moved company';
  end if;
  -- nothing belongs to a minor any more
  if exists (select 1 from public.players where nation_id is not null and not public.great_power(nation_id))
     or exists (select 1 from public.port_allegiance where nation_id is not null and not public.great_power(nation_id))
     or exists (select 1 from public.port_influence where not public.great_power(nation_id)) then
    raise exception 'GP1 self-assert FAIL: a company, a flag or a point still belongs to a minor power';
  end if;
  -- the flags: the ten's homes exactly, each flying its power; a great power's other cities kept
  if (select count(*) from public.port_allegiance where home) <> (select count(*) from gp1_homes, unnest(ports))
     or exists (select 1 from gp1_homes h cross join unnest(h.ports) c join public.ports p on p.code = c
                  join public.port_allegiance a on a.port_id = p.id join public.nations n on n.code = h.nation
                 where not a.home or a.nation_id <> n.id)
     or exists (select 1 from pre_gp1_holder b join public.port_allegiance a on a.port_id = b.port_id
                 where b.nation_id is not null and public.great_power(b.nation_id)
                   and a.nation_id is distinct from b.nation_id) then
    raise exception 'GP1 self-assert FAIL: the homes are not the ten''s four each, or a great power lost a city';
  end if;
  -- the mayors: none in a city of no country; every one a citizen of the holder
  if exists (select 1 from public.port_mayor m join public.port_allegiance a on a.port_id = m.port_id where a.nation_id is null)
     or exists (select 1 from public.port_mayor m join public.port_allegiance a on a.port_id = m.port_id
                  join public.players pl on pl.id = m.player_id where pl.nation_id <> a.nation_id)
     or (select count(*) from public.port_mayor) <> v_s.mayors - (select count(*) from gp1_mayors_gone) then
    raise exception 'GP1 self-assert FAIL: a mayor stands in a city of no country, or is not the holder''s citizen';
  end if;
  insert into proven_gp1 values ('conserved', format(
    'W unchanged (%s ducats + %s in purses); %s points unchanged; %s companies moved (%s players), purses / ships / fleets / routes / homes unmoved; %s influence rows re-keyed; %s mayors stood down',
    v_s.ducats, v_s.purses, round(v_s.points), (select count(*) from gp1_moves), (select count(*) from gp1_moves where not is_npc),
    (select coalesce(sum(rows_in), 0) from gp1_rekey), (select count(*) from gp1_mayors_gone)));
end $$;

-- (b2) the foreign keys refuse a minor
do $$
declare
  v_ven uuid := (select id from public.nations where code = 'VEN');
  v_n   int := 0;
begin
  begin
    update public.players set nation_id = v_ven where id = (select id from public.players order by id limit 1);
  exception when foreign_key_violation then v_n := v_n + 1;
  end;
  begin
    update public.port_allegiance set nation_id = v_ven where port_id = (select port_id from public.port_allegiance where not home order by port_id limit 1);
  exception when foreign_key_violation then v_n := v_n + 1;
  end;
  begin
    update public.port_influence set nation_id = v_ven where port_id = (select port_id from public.port_influence order by port_id, player_id limit 1)
       and player_id = (select player_id from public.port_influence order by port_id, player_id limit 1);
    if not found then v_n := v_n + 1; end if;   -- an empty book has nothing to refuse
  exception when foreign_key_violation then v_n := v_n + 1;
  end;
  if v_n <> 3 then
    raise exception 'GP1 self-assert FAIL: a foreign key let a minor power own a company, a flag or a point (% of 3 refused)', v_n;
  end if;
  insert into proven_gp1 values ('keys', 'players / port_allegiance / port_influence refuse a minor power (foreign keys to great_powers)');
end $$;

-- (c) REGIONAL DESIGNS: parity wherever a city's countries did not change; a ruler's yard builds its line
create temp table gp1_changed_ports on commit drop as
select b.port_id from pre_gp1_holder b
 where b.nation_id is distinct from public.port_nation(b.port_id)                       -- its flag changed
    or (case when b.code is null then '{}'::text[] else array[b.code] end)
       is distinct from public.port_countries(b.port_id);                               -- or its countries did

do $$
declare
  v_bad text;
  v_ruled int;
begin
  select string_agg(format('%s@%s', x.class_code, x.port_id), ', ') into v_bad
    from pre_gp1_yard x
   where public.yard_wrong_country(x.port_id, x.class_code) is distinct from x.v
     and x.port_id not in (select port_id from gp1_changed_ports);
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: public.yard_wrong_country moved where a city''s countries did not: %', left(v_bad, 400);
  end if;
  select string_agg(format('%s@%s', x.skill_id, x.port_id), ', ') into v_bad
    from pre_gp1_skill x
   where public.skill_taught_at(x.skill_id, x.port_id)::text is distinct from x.v
     and x.port_id not in (select port_id from gp1_changed_ports);
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: public.skill_taught_at moved where a city''s countries did not: %', left(v_bad, 400);
  end if;
  select string_agg(format('%s@%s', x.officer_id, x.port_id), ', ') into v_bad
    from pre_gp1_inn x
   where world.inn_chance(x.officer_id, x.port_id)::text is distinct from x.v
     and x.port_id not in (select port_id from gp1_changed_ports);
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: world.inn_chance moved where a city''s countries did not: %', left(v_bad, 400);
  end if;
  -- at every yard a minor rules, every hull of a line that ruler builds is buildable (no country refusal)
  select string_agg(format('%s@%s', c.code, p.code), ', '), count(distinct p.id) into v_bad, v_ruled
    from public.ports p
    join public.port_buildings b on b.port_id = p.id and b.kind = 'building_yard'
    join public.nations r on r.id = public.port_ruler(p.id)
    join public.ship_lines sl on r.code = any(sl.builder_nations)
    join public.class_profile cp on cp.line_code = sl.code
    join public.ship_classes c on c.code = cp.class_code
   where public.yard_wrong_country(p.id, c.code) is not null;
  if v_bad is not null then
    raise exception 'GP1 self-assert FAIL: a ruler''s own yard refuses its own line: %', left(v_bad, 400);
  end if;
  select count(distinct p.id) into v_ruled
    from public.ports p join public.port_buildings b on b.port_id = p.id and b.kind = 'building_yard'
   where public.port_ruler(p.id) is not null;
  insert into proven_gp1 values ('regional', format(
    '%s yard answers, %s academy answers, %s inn chances equal their pre-images outside the %s cities whose countries changed; at all %s minor-ruled yards the ruler''s line builds',
    (select count(*) from pre_gp1_yard), (select count(*) from pre_gp1_skill), (select count(*) from pre_gp1_inn),
    (select count(*) from gp1_changed_ports), v_ruled));
end $$;

-- (d) THE DOORS: founding and changing country offer the ten only; a world move starts no cooldown
create or replace function pg_temp.probe_gp1()
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0185-4000-8000-000000000001';
  v_base   int := (select count(*) from public.players);
  v_r      jsonb;
  v_player uuid;
  v_out    jsonb := '{}'::jsonb;
begin
  begin
    perform cmd.assume_identity(c_uid);   -- both JWT shapes: the PGlite shim's and Supabase's
    v_r := cmd.found_house('Casa do Leao 0185', 'VEN');
    v_out := v_out || jsonb_build_object('found_minor', v_r->>'error_code',
                                         'found_minor_fixes', jsonb_array_length(coalesce(v_r->'fixes', '[]'::jsonb)));
    v_r := cmd.found_house('Casa do Leao 0185', 'jos');
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception 'GP1 self-assert FAIL: founding under Joseon was refused: %', v_r;
    end if;
    v_player := (v_r->>'player_id')::uuid;
    v_out := v_out || jsonb_build_object(
      'start', (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.player_id = v_player),
      'nation', (select n.code from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = v_player));
    v_r := cmd.change_country('VEN');
    v_out := v_out || jsonb_build_object('change_minor', v_r->>'error_code');
    -- a move the world made (reason great_powers) is not the company's change: no cooldown
    perform public.emit_event(v_player, 'NATION_CHANGED', jsonb_build_object('from', 'VEN', 'to', 'JOS', 'reason', 'great_powers'));
    v_out := v_out || jsonb_build_object('cooldown_after_world_move', public.nation_change_next_at(v_player));
    v_r := cmd.change_country('JPN');
    v_out := v_out || jsonb_build_object('change_great', coalesce(v_r->>'nation', v_r->>'error_code'),
                                         'cooldown_after_own_move', public.nation_change_next_at(v_player) is not null);
    perform public.assert_ledger_reconciles(v_player);
    raise exception 'PROBE_ROLLBACK_GP1';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_GP1' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if (select count(*) from public.players) <> v_base then
    raise exception 'GP1 self-assert FAIL: the probe did not leave the world as it found it';
  end if;
  return v_out;
end $$;

do $$
declare
  v jsonb := pg_temp.probe_gp1();
begin
  if v->>'found_minor' <> 'E_MINOR_POWER' or (v->>'found_minor_fixes')::int <> 10
     or v->>'start' <> 'BUS' or v->>'nation' <> 'JOS'
     or v->>'change_minor' <> 'E_MINOR_POWER'
     or (v->'cooldown_after_world_move') <> 'null'::jsonb
     or v->>'change_great' <> 'JPN' or not (v->>'cooldown_after_own_move')::boolean then
    raise exception 'GP1 self-assert FAIL: the doors do not offer the ten only, or a world move starts a cooldown: %', v;
  end if;
  insert into proven_gp1 values ('doors', format(
    'found under VEN → %s (fixes name %s); under JOS → starts at %s; change to VEN → %s; a world move leaves no cooldown, the company''s own change to %s starts one',
    v->>'found_minor', v->>'found_minor_fixes', v->>'start', v->>'change_minor', v->>'change_great'));
end $$;

-- (e) THE READS: the ten on the board, the ruler on the flag, great in the catalogue
do $$
declare
  v_board jsonb := world.nation_standings();
  v_alleg jsonb := world.allegiance();
  v_snap  jsonb := world.snapshot();
begin
  if jsonb_array_length(v_board->'countries') <> 10
     or exists (select 1 from jsonb_array_elements(v_board->'countries') c
                 where not public.great_power((select n.id from public.nations n where n.code = c->>'nation'))) then
    raise exception 'GP1 self-assert FAIL: world.nation_standings does not list exactly the ten';
  end if;
  if (select e->>'ruler' from jsonb_array_elements(v_alleg->'ports') e where e->>'port' = 'VEN') is distinct from 'VEN'
     or (select e->>'ruler' from jsonb_array_elements(v_alleg->'ports') e where e->>'port' = 'LIS') is not null
     or (select count(*) from jsonb_array_elements(v_alleg->'ports') e where e->>'ruler' is not null)
        <> (select count(*) from public.ports p join public.port_allegiance a on a.port_id = p.id where public.port_ruler(p.id) is not null) then
    raise exception 'GP1 self-assert FAIL: world.allegiance does not serve each city''s ruler';
  end if;
  if (select count(*) from jsonb_array_elements(v_snap->'nations') n where (n->>'great')::boolean) <> 10
     or jsonb_array_length(v_snap->'nations') <> (select count(*) from public.nations) then
    raise exception 'GP1 self-assert FAIL: world.snapshot does not mark exactly the ten great among every nation';
  end if;
  insert into proven_gp1 values ('reads', format('Countries board lists the ten; %s cities serve a ruler; the catalogue marks 10 of %s nations great',
    (select count(*) from jsonb_array_elements(v_alleg->'ports') e where e->>'ruler' is not null), jsonb_array_length(v_snap->'nations')));
end $$;

-- ── 8. RECEIPT ─────────────────────────────────────────────────────────────────────────────────
insert into gp1_t (step) values ('proof');

do $$
begin
  raise notice 'GP1 moved companies: %',
    (select string_agg(format('%s→%s %s', fc, tc, k), ' · ' order by fc, tc)
       from (select fn.code fc, m.to_code tc, count(*) k from gp1_moves m join public.nations fn on fn.id = m.from_nation group by 1, 2) x);
  raise notice 'GP1 companies per power: %',
    (select string_agg(format('%s %s', n.code, (select count(*) from public.players pl where pl.nation_id = n.id)), ' · ' order by n.code)
       from public.great_powers g join public.nations n on n.id = g.nation_id);
  raise notice 'GP1 cities held (home / contested): %; no country %',
    (select string_agg(format('%s %s/%s', n.code,
              (select count(*) from public.port_allegiance a where a.nation_id = n.id and a.home),
              (select count(*) from public.port_allegiance a where a.nation_id = n.id and not a.home)), ' · ' order by n.code)
       from public.great_powers g join public.nations n on n.id = g.nation_id),
    (select count(*) from public.port_allegiance where nation_id is null);
  raise notice 'GP1 influence re-keyed: %',
    (select string_agg(format('%s→%s %s', from_code, (select code from public.nations where id = nation_id), round(p)), ' · ' order by from_code)
       from (select from_code, nation_id, sum(points) p from gp1_rekey group by 1, 2) x);
  raise notice 'GP1 timings ms: %',
    (select string_agg(format('%s %s', b.step, round(extract(epoch from b.at - a.at) * 1000)), ' · ' order by b.at)
       from gp1_t b join lateral (select at from gp1_t x where x.at < b.at order by x.at desc limit 1) a on true);
  raise notice 'GP1 self-assert ok: THE GREAT POWERS — %',
    (select string_agg(k || ': ' || v, ' | ' order by k) from proven_gp1);
end $$;
