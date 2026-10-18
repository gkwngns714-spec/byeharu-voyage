-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0196 — A RIVAL PAYS THE TARIFF  (PRICE_FACTORS slice P4: the profit tax by relation between powers)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"is there a way for the prices move on many different factors? like relationship
-- with other countries, religion, merchants, any more ideas?"*. docs/PRICE_FACTORS.md §3.2 / F4–F5: relations
-- between powers are a TARIFF on the trader's profit tax, through the one per-company tax authority
-- (world.tax_rate, 0147). Grounding (§1.1): Uncharted Waters Online's tariffs differ by nation (about 14 % for
-- the top three, 12 → 6 % below) and bad relations raise them; Origin's base tariff is 20 – 30 % and an allied
-- port charges its friends none; the Ottoman capitulations (France 1536, England 1580) gave friendly merchants
-- lower customs than others paid. It waited on the ten great powers (0187, docs/GREAT_POWERS.md) — LIVE.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.power_relations(a, b, stance, why) — NEW FACT, the smallest data authority the doc needs: one
--     row per UNORDERED pair of great powers that is not at peace (a < b), from data/relations.json; the
--     world guard holds the table equal to the file, both directions. 13 rows: 5 allies, 6 rivals, 2 wars.
-- (2) public.power_stance(a, b) — NEW leaf, THE one reader of it: 'home' (one power), 'ally' / 'rival' /
--     'war' (a row), else 'peace' — a free city (no flag) or a company of no power is at peace with all.
-- (3) public.stance_mult(stance) — NEW leaf: the knob tariff_stance_mult's entry (ally 0.5, rival 1.5,
--     war 2.0); peace 1; any other stance RAISES (a stance nobody priced is a defect, not a 1).
-- (4) world.tax_rate (THE one tax authority, 0122 / 0147) — with a company and the race on, a company in a
--     city its own power holds keeps 0147's citizen cut (unchanged), and anywhere else pays
--         least(base × stance_mult, greatest(base, tariff_rate_max 0.35))
--     — the cap never lowers a city's own rate. Without a company, dark, or with the race off: unchanged.
--     Two hunks, sliced from the live body. Every caller already passes the company — cmd.do_sell (the
--     charge), public.npc_leg_lines (the merchants' planner, so a hostile port really moves their laps),
--     world.good_board (the desk's net), world.town_hall_influence (your rate) — via public.profit_tax.
-- (5) world.price_why serves `tariff: {base, rate, stance, holder}` for the caller — the city's rate, the
--     caller's (world.tax_rate itself), the stance and the city's flag; null with no company signed in or
--     while the purse is dark. One hunk.
--
-- ── DECISIONS TAKEN HERE — NOT THE OWNER'S, CONFIRM ─────────────────────────────────────────────
-- * The thirteen stances of data/relations.json (1580 – 1640), each defended in a line there.
-- * The tariff rides the race (influence_on), as 0147's citizen cut does: with the race off no tax is per
--   company, so neither is the tariff.
-- * The tariff keys on the city's HOLDER (public.port_nation), not its local ruler (port_ruler, 0187).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Touch the market price (everyone's), the spread, the turnover tax a dark quay charges, the mayor's rate,
-- the citizen cut, the influence book or any grant. Refuse a trade (an embargo is a later candidate, §7).
--
-- ── THE PROOF (ten probe companies, one of each power, in a sub-block rolled back whole) ────────
-- With the purse and the race lit IN the block: every harbour × every power — world.tax_rate equals its
-- pre-image (a pg_temp copy) at home, at peace and in a free city, × 0.5 for an ally, and
-- least(× 1.5 / × 2, greatest(base, 0.35)) for a rival / at war, every stance seen; without a company
-- every harbour's rate is its pre-image; with the race off, or dark, every answer is its pre-image;
-- price_why's tariff names the caller's stance and rate, and is null with no company signed in.
-- Timings: raise notice only.
-- ROLLBACK: set tariff_stance_mult to {"ally": 1, "rival": 1, "war": 1} (every tariff 1), or a forward slice
-- reversing the hunks.
-- VERSION: 0196 — prod head 0194 when re-read (2026-10-19, after 0193 queue 48 and 0194 glut landed); neither
-- touches world.tax_rate, and 0194's one world.price_why hunk (the band term) is disjoint from this file's (the
-- fee). All three hunks were asserted to occur exactly once on prod's live bodies at 0192 and again at 0194,
-- read-only. Renumber to head + 1 if anything lands first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0196(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0196 on commit drop as
select f.ord, f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = f.fn::regprocedure) as meta
  from (values (1, 'world.tax_rate(uuid, uuid)'),
               (2, 'world.price_why(uuid, uuid)')) f(ord, fn);
create temp table count_0196 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
begin
  if to_regclass('public.power_relations') is not null
     or to_regprocedure('public.power_stance(uuid, uuid)') is not null
     or to_regprocedure('public.stance_mult(text)') is not null
     or exists (select 1 from public.world_config where key in ('tariff_stance_mult', 'tariff_rate_max')) then
    raise exception '0196 self-assert FAIL: something this file creates already exists';
  end if;
  if (select count(*) from public.great_powers) <> 10 then
    raise exception '0196 self-assert FAIL: % great powers, not the ten 0187 seeded', (select count(*) from public.great_powers);
  end if;
end $$;

-- the stance pre-image of every company: the old body, under another name, for the proof
do $$
declare
  v_def text := (select def from before_0196 where ord = 1);
begin
  if pg_temp.occurs_0196(v_def, 'FUNCTION world.tax_rate(') <> 1 then
    raise exception '0196 self-assert FAIL: world.tax_rate''s definition does not name itself once';
  end if;
  execute replace(v_def, 'FUNCTION world.tax_rate(', 'FUNCTION pg_temp.tax_rate_old_0196(');
end $$;

-- ── 1. THE FACT: HOW THE POWERS STAND (data/relations.json) ─────────────────────────────────────
create temp table plan_0196 (a text, b text, stance text, why text) on commit drop;
insert into plan_0196 values
  ('ENG', 'PRT', 'ally',  'the Treaty of Windsor (1386), the oldest alliance in Europe, held through the century'),
  ('ESP', 'PRT', 'ally',  'the Iberian Union (1580-1640): one king in Madrid and Lisbon'),
  ('ENG', 'NLD', 'ally',  'the Treaty of Nonsuch (1585): England sent an army to the Dutch revolt against Spain'),
  ('FRA', 'OTT', 'ally',  'the Franco-Ottoman alliance and the capitulations of 1536 lowered French customs in the Levant'),
  ('JOS', 'MNG', 'ally',  'Joseon was Ming''s tributary, and Ming armies fought for it in the Imjin War (1592-98)'),
  ('ENG', 'ESP', 'rival', 'the Anglo-Spanish War (1585-1604) and the Armada of 1588'),
  ('ESP', 'FRA', 'rival', 'Habsburg against Valois and Bourbon, from the Italian Wars to the war of 1635'),
  ('ESP', 'OTT', 'rival', 'the Habsburg-Ottoman wars for the Mediterranean: Tunis, Malta, Lepanto (1571)'),
  ('OTT', 'PRT', 'rival', 'the Ottoman-Portuguese wars for the Indian Ocean, Diu (1538) to Hormuz'),
  ('JPN', 'MNG', 'rival', 'the wokou raids and Ming''s ban on trade with Japan; Ming fought Japan in Korea'),
  ('JOS', 'JPN', 'rival', 'the Imjin War (1592-98); trade reopened only by the Treaty of Giyu (1609)'),
  ('ESP', 'NLD', 'war',   'the Eighty Years'' War (1568-1648), the Dutch revolt against the Spanish crown'),
  ('NLD', 'PRT', 'war',   'the Dutch-Portuguese War (1602-1663) for the spice trade, from Malacca to Brazil');

create table public.power_relations (
  a      uuid not null references public.great_powers(nation_id),
  b      uuid not null references public.great_powers(nation_id),
  stance text not null check (stance in ('ally', 'rival', 'war')),
  why    text not null check (length(why) > 12),
  primary key (a, b),
  check (a < b)
);
comment on table public.power_relations is
  '0196 (docs/PRICE_FACTORS.md §3.2, P4): how two great powers stand, one row per unordered pair (a < b) that is '
  'NOT at peace. Authored in data/relations.json; the world guard holds it. Read through public.power_stance.';
alter table public.power_relations enable row level security;
revoke all on table public.power_relations from public, anon, authenticated;

insert into public.power_relations (a, b, stance, why)
select least(na.id, nb.id), greatest(na.id, nb.id), p.stance, p.why
  from plan_0196 p
  join public.nations na on na.code = p.a
  join public.nations nb on nb.code = p.b;

insert into public.world_config (key, value, description) values
  ('tariff_stance_mult', '{"ally": 0.5, "rival": 1.5, "war": 2.0}'::jsonb,
   '0196: what a relation does to the profit tax a company pays in a city another great power holds '
   '(public.power_relations): × this. Peace × 1; a company''s own power keeps the citizen cut (0147). '
   'Uncharted Waters Online (tariffs by nation), Origin (allied ports free). docs/PRICE_FACTORS.md §3.2, F4.'),
  ('tariff_rate_max', '0.35'::jsonb,
   '0196: a tariff never takes the profit tax above this (35 %), and never lowers a city''s own rate. '
   'docs/PRICE_FACTORS.md §3.2 / §4: a hostile port takes at most a third of the profit, never the trade.');

-- ── 2. THE LEAVES ──────────────────────────────────────────────────────────────────────────────
create function public.power_stance(p_a uuid, p_b uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0196: THE one reader of public.power_relations — how a company's power (p_a) stands with a city's holder
-- (p_b): 'home' when they are one, the authored row's stance, else 'peace'. A free city (no holder) and a
-- company of no power are at peace with everyone. On the profit tax's path: one primary-key read at most.
begin
  if p_a is null or p_b is null then
    return 'peace';
  end if;
  if p_a = p_b then
    return 'home';
  end if;
  return coalesce((select r.stance from public.power_relations r
                    where r.a = least(p_a, p_b) and r.b = greatest(p_a, p_b)), 'peace');
end $$;

create function public.stance_mult(p_stance text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0196: what a stance does to the profit tax (the knob tariff_stance_mult); peace 1. A stance the knob
-- does not price RAISES — 'home' never reaches here (world.tax_rate gives a citizen 0147's cut).
declare
  v numeric;
begin
  if p_stance = 'peace' then
    return 1;
  end if;
  v := (public.wc('tariff_stance_mult') ->> p_stance)::numeric;
  if v is null or v <= 0 then
    raise exception 'E_NO_STANCE_MULT: tariff_stance_mult does not price the stance "%"', coalesce(p_stance, '') using errcode = 'P0001';
  end if;
  return v;
end $$;

revoke all on function public.power_stance(uuid, uuid) from public, anon, authenticated;
revoke all on function public.stance_mult(text) from public, anon, authenticated;

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses) ──────────
create temp table hunks_0196 (ord int, n int, old text, new text) on commit drop;
insert into hunks_0196 values
(1, 1,
$h$  v_base numeric;
$h$,
$h$  v_base numeric;
  v_stance text;   -- 0196: how the company's power stands with the city's holder
$h$),
(1, 2,
$h$  if p_player is not null
     and (select pl.nation_id from public.players pl where pl.id = p_player) = public.port_nation(p_port) then
    return v_base * (1 - public.wc_num('influence_citizen_tax_cut'));
  end if;
  return v_base;$h$,
$h$  if p_player is null then
    return v_base;
  end if;
  -- 0196: THE TARIFF (docs/PRICE_FACTORS.md §3.2) — how the company's power stands with the city's holder
  -- (public.power_stance): at home 0147's citizen cut; else × public.stance_mult (ally 0.5, peace 1, rival
  -- 1.5, war 2), never above tariff_rate_max and never capping the city's own rate below itself.
  v_stance := public.power_stance((select pl.nation_id from public.players pl where pl.id = p_player),
                                  public.port_nation(p_port));
  if v_stance = 'home' then
    return v_base * (1 - public.wc_num('influence_citizen_tax_cut'));
  end if;
  return least(v_base * public.stance_mult(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));$h$),
(2, 1,
$h$                              'profit_tax', case when public.city_treasury_on() then world.tax_rate(p_port) else 0 end),
$h$,
$h$                              'profit_tax', case when public.city_treasury_on() then world.tax_rate(p_port) else 0 end),
    -- 0196: the caller's own profit tax here and the relation that moves it — the city's rate and the caller's,
    -- both from world.tax_rate; the stance (public.power_stance) and the flag. Null with no company or dark.
    'tariff', (select case when s.pid is not null and public.city_treasury_on() then
                       jsonb_build_object('base', world.tax_rate(p_port), 'rate', world.tax_rate(p_port, s.pid),
                                          'stance', public.power_stance(s.nat, s.hold),
                                          'holder', (select jsonb_build_object('code', n.code, 'name', n.name)
                                                       from public.nations n where n.id = s.hold)) end
                 from (select pl.id as pid, pl.nation_id as nat, public.port_nation(p_port) as hold
                         from (select public.current_player_id() as id) c
                         left join public.players pl on pl.id = c.id) s),
$h$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for b in select * from before_0196 order by ord loop
    v_def := b.def;
    for h in select * from hunks_0196 where ord = b.ord order by n loop
      if pg_temp.occurs_0196(v_def, h.old) <> 1 then
        raise exception '0196 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          b.fn, h.n, pg_temp.occurs_0196(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(b.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0196 where ord = b.ord order by n desc loop
      if pg_temp.occurs_0196(v_rev, h.new) <> 1 then
        raise exception '0196 self-assert FAIL: % hunk % does not occur once in the new body', b.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> b.def then
      raise exception '0196 self-assert FAIL: % does not reverse to its pre-image', b.fn;
    end if;
    if (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = b.fn::regprocedure) <> b.meta then
      raise exception '0196 self-assert FAIL: %''s ACL, owner, volatility, definer or config moved', b.fn;
    end if;
  end loop;
end $$;

-- ── 4. THE PROOF (ten probe companies, one of each power; rolled back whole) ──────────────────
do $$
declare
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_cap   numeric := public.wc_num('tariff_rate_max');
  v_free  uuid;
  v_free_nat uuid;
  v_ist   uuid;
  v_prt   uuid;
  v_bad   int;
  v_seen  text;
  v_n     int;
  v_t0    timestamptz;
  v_old_ms numeric;
  v_new_ms numeric;
  j       jsonb;
  v_out   text;
begin
  if (select count(*) from public.power_relations) <> (select count(*) from plan_0196)
     or exists (select 1 from plan_0196 p
                 where public.power_stance((select id from public.nations where code = p.a), (select id from public.nations where code = p.b)) <> p.stance
                    or public.power_stance((select id from public.nations where code = p.b), (select id from public.nations where code = p.a)) <> p.stance) then
    raise exception '0196 self-assert FAIL: public.power_relations is not the plan, or a stance is not symmetric';
  end if;
  select a.port_id, a.nation_id into v_free, v_free_nat from public.port_allegiance a join public.ports p on p.id = a.port_id
   where not a.home and p.kind = 'HARBOUR' order by p.code limit 1;
  begin
    -- the precondition is set here, never read from the world: the purse and the race lit, and one
    -- harbour that is nobody's home flying no flag
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    update public.port_allegiance set nation_id = null where port_id = v_free;
    create temp table probe_0196 on commit drop as
    select u.code, u.uid, public.new_house(u.uid, 'Casa ' || u.code || ' 0196', u.code, 'LIS') as player_id
      from (select n.code, ('00000000-0196-4000-8000-0000000000' || lpad(row_number() over (order by n.code)::text, 2, '0'))::uuid as uid
              from public.great_powers gp join public.nations n on n.id = gp.nation_id) u;
    create temp table grid_0196 on commit drop as
    select p.id as port_id, pr.code, pr.player_id,
           (select hn.code from public.nations hn where hn.id = public.port_nation(p.id)) as holder,
           pg_temp.tax_rate_old_0196(p.id, pr.player_id) as old_rate,
           world.tax_rate(p.id, pr.player_id) as new_rate,
           pg_temp.tax_rate_old_0196(p.id) as old_base,
           world.tax_rate(p.id) as new_base
      from public.ports p cross join probe_0196 pr
     where p.kind = 'HARBOUR';
    alter table grid_0196 add column stance text;
    update grid_0196 g set stance = case when g.holder is null then 'free' when g.holder = g.code then 'home'
                                         else coalesce((select pl.stance from plan_0196 pl
                                                         where (pl.a, pl.b) = (least(g.code, g.holder), greatest(g.code, g.holder))), 'peace') end;
    select count(*) into v_bad from grid_0196 g
     where g.new_base is distinct from g.old_base
        or g.new_rate is distinct from case g.stance
             when 'ally'  then least(g.old_rate * 0.5, greatest(g.old_rate, v_cap))
             when 'rival' then least(g.old_rate * 1.5, greatest(g.old_rate, v_cap))
             when 'war'   then least(g.old_rate * 2.0, greatest(g.old_rate, v_cap))
             else g.old_rate end;
    select string_agg(s.stance || ' ' || s.n || ' (' || s.lo || '–' || s.hi || ')', ', ' order by s.stance) into v_seen
      from (select stance, count(*) as n, round(min(new_rate), 4) as lo, round(max(new_rate), 4) as hi from grid_0196 group by stance) s;
    if v_bad <> 0 then
      raise exception '0196 self-assert FAIL: % of % (harbour, power) rates are not the tariff on their pre-image; seen %',
        v_bad, (select count(*) from grid_0196), v_seen;
    end if;
    if (select count(distinct stance) from grid_0196) <> 6 then
      raise exception '0196 self-assert FAIL: the grid saw only %, not home, ally, peace, rival, war and a free city', v_seen;
    end if;
    if exists (select 1 from grid_0196 where new_rate > greatest(old_rate, v_cap)) then
      raise exception '0196 self-assert FAIL: a tariff passed tariff_rate_max';
    end if;
    -- the read: a Portuguese company at Istanbul (an Ottoman home: rival) and with no company signed in
    select id into v_ist from public.ports where code = 'IST';
    select player_id into v_prt from probe_0196 where code = 'PRT';
    perform cmd.assume_identity((select uid from probe_0196 where code = 'PRT'));
    j := world.price_why(v_ist, (select g2.id from public.goods g2 order by g2.code limit 1));
    if j->'tariff'->>'stance' is distinct from 'rival' or (j->'tariff'->'holder'->>'code') is distinct from 'OTT'
       or (j->'tariff'->>'rate')::numeric is distinct from world.tax_rate(v_ist, v_prt)
       or (j->'tariff'->>'base')::numeric is distinct from world.tax_rate(v_ist)
       or (j->'tariff'->>'rate')::numeric <= (j->'tariff'->>'base')::numeric then
      raise exception '0196 self-assert FAIL: price_why''s tariff at Istanbul for a Portuguese company is %', j->'tariff';
    end if;
    perform cmd.assume_identity(c_nil);
    if world.price_why(v_ist, (select g2.id from public.goods g2 order by g2.code limit 1))->'tariff' <> 'null'::jsonb then
      raise exception '0196 self-assert FAIL: with no company signed in the tariff is not null';
    end if;
    -- the cost: one more read a call (the stance's primary key), timed on the grid both ways
    select count(*) into v_n from grid_0196;
    v_t0 := clock_timestamp();
    perform pg_temp.tax_rate_old_0196(g2.port_id, g2.player_id) from grid_0196 g2;
    v_old_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / v_n, 4);
    v_t0 := clock_timestamp();
    perform world.tax_rate(g2.port_id, g2.player_id) from grid_0196 g2;
    v_new_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / v_n, 4);
    -- dark race: every answer is its pre-image
    update public.world_config set value = 'false'::jsonb where key = 'influence_enabled';
    if exists (select 1 from grid_0196 g2 where world.tax_rate(g2.port_id, g2.player_id) is distinct from pg_temp.tax_rate_old_0196(g2.port_id, g2.player_id)) then
      raise exception '0196 self-assert FAIL: with the race off a rate moved';
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    if exists (select 1 from grid_0196 g2 where world.tax_rate(g2.port_id, g2.player_id) is distinct from pg_temp.tax_rate_old_0196(g2.port_id, g2.player_id)) then
      raise exception '0196 self-assert FAIL: with the purse dark a rate moved';
    end if;
    v_out := format('%s (harbour, power) rates: %s; world.tax_rate %s ms a call (was %s)', v_n, v_seen, v_new_ms, v_old_ms);
    raise exception using errcode = 'ZX195', message = v_out;
  exception when sqlstate 'ZX195' then
    v_out := sqlerrm;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where auth_uid::text like '00000000-0196-%')
     or (select a.nation_id from public.port_allegiance a where a.port_id = v_free) is distinct from v_free_nat then
    raise exception '0196 self-assert FAIL: a probe company or the free city''s flag survived its rollback';
  end if;
  if exists (select 1 from unnest(array['public.power_stance(uuid, uuid)', 'public.stance_mult(text)']) f(fn),
                    unnest(array['anon', 'authenticated']) rl(role)
              where has_function_privilege(rl.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['public.power_stance(uuid, uuid)', 'public.stance_mult(text)']) f(fn)
                 join pg_proc p on p.oid = f.fn::regprocedure where p.provolatile <> 's')
     or exists (select 1 from unnest(array['anon', 'authenticated']) rl(role)
                 where has_table_privilege(rl.role, 'public.power_relations', 'select, insert, update, delete'))
     or (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from count_0196)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0196 self-assert FAIL: a leaf or the table is reachable, a leaf is not STABLE, or the registry or a wall moved';
  end if;
  raise notice '0196 self-assert ok: A RIVAL PAYS THE TARIFF. public.power_relations (13 pairs = data/relations.json, server-only); public.power_stance / stance_mult (server-only, STABLE); world.tax_rate × stance beside the citizen cut, capped at tariff_rate_max (2 hunks, reverses); world.price_why serves the caller''s tariff (1 hunk). Probes, one company of each power: %.', v_out;
end $$;
