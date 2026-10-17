-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0144 — A CITY COUNTS WHO GIVES  (docs/INFLUENCE.md slice I2)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-17: "make the city have more influence [for that country] by investing and spending money
-- to that city" — and, approving docs/INFLUENCE.md: "make the game — country region influences and
-- all like uncharted [waters]", with UWO's anti-whale damping (A1): each coin moves a country's
-- influence less as its share in that city rises, and the trailing country gets more per coin.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE BOOK: public.port_influence (port, nation, player) → points (coin given, weighted and
--     later decayed, D6) and day_given (coin DONATED today, D7's cap; reset by the daily count,
--     I4). Keyed by the COUNTRY AT THE MOMENT OF GIVING (A2): a company that changes its country
--     leaves what it gave with the old one.
-- (2) THE ONE POSTING AUTHORITY: public.influence_post(player, port, coin, kind), called from ONE
--     hunk in public.pay_city — the one door into a city's purse — for kind SHARE (0123's Invest)
--     and DONATION (new). D3: trade, wages, supplies, repairs, building, tuition and tax do not
--     count. The weight (A1) is public.influence_weight(share): influence_weight_trailing (1.5) for
--     a country with no influence there, falling in a straight line to influence_weight_leading
--     (0.25) for a country that has all of it — the share read BEFORE this gift. Posting runs lit
--     or dark (docs/INFLUENCE.md §7), so what is given before the switch counts.
-- (3) THE ONE READER OF SHARES: public.influence_shares(port) → (nation, points, share).
-- (4) DONATE (ECONOMY_LOOP §12.2): public.donate_for(player, port, coin) — refuses E_NOT_FOUND,
--     E_NOT_OFFERED ("… is not taking gifts yet" while influence_enabled or the city purses are
--     dark), E_DONATE_MIN, E_DAY_CAP (D7: influence_day_cap a company a city a day; figures: the
--     room left against the gift) and E_INSUFFICIENT_FUNDS — then the DONATED event and pay_city
--     (DONATION), so the coin lands in the city's purse (it is not burned). cmd.donate /
--     cmd.preview_donate (docked there, E_NOT_DOCKED), registered.
-- (5) world.town_hall gains `influence` (world.town_hall_influence): the holder, home, since, the
--     shares per country, whether Donate is open, and your points / given today / cap / min.
-- (6) public.influence_on() — the one reader of influence_enabled (false), 0122's shape.
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * NOT THE OWNER'S — the damping's two numbers, influence_weight_trailing 1.5 and
--   influence_weight_leading 0.25 (the owner set the SHAPE, A1; the values are knobs). One gift is
--   weighted at the share before it, whole — the cap (D7) bounds how large one gift can be.
-- * A sea place (no port_allegiance row) collects no influence.
-- * The town hall's `you.points` are the company's points for the country it sails for now.
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- (a) pay_city / world.town_hall / the registry reverse to their pre-images; ACL unmoved. (b) Every
--     other pay_city kind posts nothing (a BUY on a probe). (c) A probe PRT house's Invest posts
--     cost × weight to (that port, PRT, the house), and the weight at share 0 is the trailing one.
-- (d) Donate dark: E_NOT_OFFERED with "not taking gifts yet". Lit inside the probe: posts; a second
--     gift from the same country weighs less (its share rose); a gift from another country into
--     the same city weighs more than that; the purse + the treasury are conserved to the coin; past
--     the cap E_DAY_CAP with figures; under the minimum E_DONATE_MIN; undocked E_NOT_DOCKED.
-- (e) A change of country: the next gift posts under the new country; the old row stays.
-- (f) The town hall's influence block's keys are exactly the contract. Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE; CREATE OR REPLACE FUNCTION; knob INSERTs. The probes' writes are rolled back.
--
-- ROLLBACK: drop the pay_city hunk (a forward migration restoring its 0122 body); the book can stay.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once: public.pay_city (0122), world.town_hall (0123), public.client_rpc_entry_points (0143).
-- VERSION: 0144. Applies on 0143.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0144(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0144 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('public.pay_city(uuid, uuid, text, bigint, uuid)'),
               ('world.town_hall(uuid)'),
               ('public.client_rpc_entry_points()')) f(fn);

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('influence_enabled', 'false'::jsonb,
   '0144 (docs/INFLUENCE.md): the country race. Read by public.influence_on() alone. Dark: Donate is '
   'refused; the book still counts Invest. public.influence_switch (I4) lights it.'),
  ('influence_day_cap', to_jsonb(20000),
   '0144 (D7): the most a company may DONATE to one city in one real day (reset by the daily count).'),
  ('donate_min_ducats', to_jsonb(100),
   '0144 (ECONOMY_LOOP §12.2): the smallest gift a city takes.'),
  ('influence_weight_trailing', to_jsonb(1.5),
   '0144 (A1, UWO damping): influence per coin for a country with NO influence in that city yet.'),
  ('influence_weight_leading', to_jsonb(0.25),
   '0144 (A1, UWO damping): influence per coin for a country that holds ALL the influence there; '
   'in between, the weight falls in a straight line with the country''s share before the gift.')
on conflict (key) do nothing;

create or replace function public.influence_on()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0144: THE one reader of influence_enabled (0122's city_treasury_on shape).
begin
  return public.wc('influence_enabled') = 'true'::jsonb;
end $$;
revoke all on function public.influence_on() from public, anon, authenticated;

-- ── 3. THE BOOK ────────────────────────────────────────────────────────────────────────────────
create table public.port_influence (
  port_id    uuid not null references public.ports(id) on delete cascade,
  nation_id  uuid not null references public.nations(id),
  player_id  uuid not null references public.players(id) on delete cascade,
  points     numeric not null default 0 check (points >= 0),
  day_given  bigint  not null default 0 check (day_given >= 0),
  updated_at timestamptz not null default now(),
  primary key (port_id, nation_id, player_id)
);
create index port_influence_player on public.port_influence (player_id);
comment on table public.port_influence is
  '0144 (docs/INFLUENCE.md §4.2): coin a company gave a city (Invest, Donate), weighted (A1) and '
  'decayed (D6), by the country it sailed for AT THE MOMENT OF GIVING. Written by '
  'public.influence_post alone (and the daily count, I4); shares read by public.influence_shares.';
alter table public.port_influence enable row level security;
revoke all on table public.port_influence from public, anon, authenticated;

create or replace function public.influence_weight(p_share numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0144 (A1, UWO's anti-whale damping): influence per coin for a country holding p_share (0..1) of a
-- city's influence before the gift — influence_weight_trailing at 0, falling in a straight line to
-- influence_weight_leading at 1. The one place the damping lives.
declare
  v_s numeric := least(1, greatest(0, coalesce(p_share, 0)));
begin
  return public.wc_num('influence_weight_trailing')
       - (public.wc_num('influence_weight_trailing') - public.wc_num('influence_weight_leading')) * v_s;
end $$;
revoke all on function public.influence_weight(numeric) from public, anon, authenticated;

create or replace function public.influence_shares(p_port uuid)
returns table(nation_id uuid, points numeric, share numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0144: THE one reader of a city's influence by country: each country's points there and its share
-- of all the points, most first (ties: the country code). The Town Hall, the daily count (I4), the
-- mayor (I5), the merchants (I3) and Rank (I6) compose it.
begin
  return query
    with t as (
      select i.nation_id, sum(i.points) as points from public.port_influence i
       where i.port_id = p_port group by i.nation_id having sum(i.points) > 0
    )
    select t.nation_id, t.points, t.points / sum(t.points) over () as share
      from t join public.nations n on n.id = t.nation_id
     order by t.points desc, n.code;
end $$;
revoke all on function public.influence_shares(uuid) from public, anon, authenticated;

create or replace function public.influence_post(p_player uuid, p_port uuid, p_coin bigint, p_kind text)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0144: THE ONE POSTING AUTHORITY of influence (docs/INFLUENCE.md §4.2) — called by public.pay_city
-- alone, for SHARE and DONATION. The company's country is read NOW (A2: what it gives counts for
-- the country it sails for today). The points are coin × public.influence_weight(that country's
-- share here before this gift) (A1). A donation also counts toward today's cap (day_given, D7).
-- Returns the points posted (0 at a sea place, for a company with no country, or for nothing).
declare
  v_nation uuid;
  v_total  numeric;
  v_mine   numeric;
  v_pts    numeric;
begin
  if p_port is null or coalesce(p_coin, 0) <= 0 or p_kind not in ('SHARE', 'DONATION') then
    return 0;
  end if;
  if not exists (select 1 from public.port_allegiance a where a.port_id = p_port) then
    return 0;
  end if;
  select pl.nation_id into v_nation from public.players pl where pl.id = p_player;
  if v_nation is null then
    return 0;
  end if;
  select coalesce(sum(i.points), 0), coalesce(sum(i.points) filter (where i.nation_id = v_nation), 0)
    into v_total, v_mine
    from public.port_influence i where i.port_id = p_port;
  v_pts := p_coin * public.influence_weight(case when v_total > 0 then v_mine / v_total else 0 end);
  insert into public.port_influence as x (port_id, nation_id, player_id, points, day_given, updated_at)
  values (p_port, v_nation, p_player, v_pts, case when p_kind = 'DONATION' then p_coin else 0 end, now())
  on conflict (port_id, nation_id, player_id) do update
     set points = x.points + excluded.points,
         day_given = x.day_given + excluded.day_given,
         updated_at = now();
  return v_pts;
end $$;
revoke all on function public.influence_post(uuid, uuid, bigint, text) from public, anon, authenticated;

-- ── 4. DONATE ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.donate_for(p_player uuid, p_port uuid, p_coin bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0144: THE one way a company gives a city coin (ECONOMY_LOOP §12.2) — players (cmd.donate) and
-- merchants (I3) alike. Refuses before anything moves; then the DONATED event and public.pay_city
-- (DONATION): the coin lands in the city's purse and public.influence_post counts it. Server-only.
declare
  p       public.ports%rowtype;
  v_have  bigint;
  v_today bigint;
  v_cap   bigint := public.wc_int('influence_day_cap');
  v_min   bigint := public.wc_int('donate_min_ducats');
  v_event uuid;
  v_after bigint;
  v_pts   numeric;
begin
  select x.* into p from public.ports x where x.id = p_port;
  if p.id is null or p.kind <> 'HARBOUR' then
    perform cmd.refuse('E_NOT_FOUND', 'there is no such harbour');
  end if;
  if not public.city_treasury_on() or not public.influence_on() then
    perform cmd.refuse('E_NOT_OFFERED', format('%s is not taking gifts yet', p.name));
  end if;
  if coalesce(p_coin, 0) < v_min then
    perform cmd.refuse('E_DONATE_MIN', format('the smallest gift is %s coin', v_min),
                       cmd.figures(greatest(coalesce(p_coin, 0), 0), v_min, 'ducats'));
  end if;
  -- 0122's ONE LOCK ORDER: the house's row first, then the city's.
  select pl.ducats into v_have from public.players pl where pl.id = p_player for update;
  select coalesce(sum(i.day_given), 0) into v_today from public.port_influence i
   where i.port_id = p_port and i.player_id = p_player;
  if v_today + p_coin > v_cap then
    perform cmd.refuse('E_DAY_CAP', format('a company gives %s at most %s coin a day; %s more today',
                                           p.name, v_cap, greatest(v_cap - v_today, 0)),
                       cmd.figures(greatest(v_cap - v_today, 0), p_coin, 'ducats'));
  end if;
  if coalesce(v_have, 0) < p_coin then
    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('the gift is %s coin', p_coin),
                       cmd.figures(coalesce(v_have, 0), p_coin, 'ducats'));
  end if;
  v_event := public.emit_event(p_player, 'DONATED', jsonb_build_object(
               'port', p.code, 'port_name', p.name, 'amount', p_coin,
               'nation', (select n.code from public.players pl join public.nations n on n.id = pl.nation_id where pl.id = p_player)));
  v_after := public.pay_city(p_player, p_port, 'DONATION', p_coin, v_event);
  select coalesce(sum(i.points), 0) into v_pts from public.port_influence i
   where i.port_id = p_port and i.player_id = p_player
     and i.nation_id = (select pl.nation_id from public.players pl where pl.id = p_player);
  return jsonb_build_object('ok', true, 'port', p.code, 'amount', p_coin, 'purse', v_after,
                            'points', round(v_pts), 'given_today', v_today + p_coin, 'cap', v_cap);
end $$;
revoke all on function public.donate_for(uuid, uuid, bigint) from public, anon, authenticated;

create or replace function cmd.donate(p_port uuid, p_coin bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0144: the caller's company gives p_port p_coin — only with a fleet of hers lying DOCKED there
-- (the Town Hall's `you.docked`, cmd.invest's test). The core is public.donate_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  perform voyage.settle(f.id) from public.fleets f where f.player_id = v_player and f.status = 'SAILING';
  begin
    if not exists (select 1 from public.fleets f where f.player_id = v_player and f.status = 'DOCKED' and f.port_id = p_port) then
      perform cmd.refuse('E_NOT_DOCKED', 'dock a fleet here to donate');
    end if;
    return public.donate_for(v_player, p_port, p_coin);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;

create or replace function cmd.preview_donate(p_port uuid, p_coin bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0144: cmd.donate's dry run — the real gift, rolled back: {ok, estimate} or the refusal it would give.
declare
  v_out jsonb;
  v_det text;
begin
  begin
    v_out := cmd.donate(p_port, p_coin);
    if coalesce((v_out->>'ok')::boolean, false) then
      v_out := jsonb_build_object('ok', true, 'estimate', v_out);
    end if;
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;
revoke all on function cmd.donate(uuid, bigint) from public, anon;
revoke all on function cmd.preview_donate(uuid, bigint) from public, anon;
grant execute on function cmd.donate(uuid, bigint) to authenticated;
grant execute on function cmd.preview_donate(uuid, bigint) to authenticated;

-- ── 5. THE TOWN HALL'S INFLUENCE BLOCK ─────────────────────────────────────────────────────────
create or replace function world.town_hall_influence(p_port uuid, p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0144: world.town_hall's `influence` — who holds the city (public.port_nation), whether it is a
-- home city and since when, each country's share (public.influence_shares), whether Donate is
-- open, and the viewer's own points (for the country it sails for now), given today, the cap and
-- the minimum. Composed by world.town_hall alone; not a client door.
declare
  v_nation uuid := (select pl.nation_id from public.players pl where pl.id = p_player);
begin
  return jsonb_build_object(
    'holder', (select n.code from public.nations n where n.id = public.port_nation(p_port)),
    'home', coalesce((select a.home from public.port_allegiance a where a.port_id = p_port), false),
    'since', (select a.since from public.port_allegiance a where a.port_id = p_port),
    'open', public.city_treasury_on() and public.influence_on(),
    'shares', coalesce((select jsonb_agg(jsonb_build_object(
                  'nation', n.code, 'points', round(s.points), 'share', round(s.share, 4)) order by s.points desc, n.code)
                  from public.influence_shares(p_port) s join public.nations n on n.id = s.nation_id), '[]'::jsonb),
    'you', case when p_player is null then null else jsonb_build_object(
       'nation', (select n.code from public.nations n where n.id = v_nation),
       'points', round(coalesce((select sum(i.points) from public.port_influence i
                                  where i.port_id = p_port and i.player_id = p_player and i.nation_id = v_nation), 0)),
       'given_today', coalesce((select sum(i.day_given) from public.port_influence i
                                 where i.port_id = p_port and i.player_id = p_player), 0),
       'cap', public.wc_int('influence_day_cap'),
       'min', public.wc_int('donate_min_ducats')) end);
end $$;
revoke all on function world.town_hall_influence(uuid, uuid) from public, anon, authenticated;

-- ── 6. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create temp table hunks_0144 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0144 values
('public.pay_city(uuid, uuid, text, bigint, uuid)', 1,
$h$  perform public.treasury_post(p_port, p_kind, p_amount, p_player, p_event);
  return v_after;$h$,
$h$  perform public.treasury_post(p_port, p_kind, p_amount, p_player, p_event);
  -- 0144 (docs/INFLUENCE.md §4.2): coin given INTO a city — an investment or a gift — counts for
  -- the company's country there (public.influence_post, the one posting authority). Trade does not.
  if p_kind in ('SHARE', 'DONATION') then
    perform public.influence_post(p_player, p_port, p_amount, p_kind);
  end if;
  return v_after;$h$),
('world.town_hall(uuid)', 1,
$h$                       from public.city_shares s where s.port_id = p_port and s.player_id = v_player), '[]'::jsonb)));$h$,
$h$                       from public.city_shares s where s.port_id = p_port and s.player_id = v_player), '[]'::jsonb)),
    -- 0144: who holds the city, each country's influence, Donate, and yours (docs/INFLUENCE.md §6).
    'influence', world.town_hall_influence(p_port, v_player));$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'change_country',        'text')
    ) as t(s, f, a)$h$,
$h$      ('cmd',         'change_country',        'text'),
      -- 0144: a gift to a city, and its dry run (the Town Hall's Donate, docs/INFLUENCE.md I2).
      ('cmd',         'donate',                'uuid, bigint'),
      ('cmd',         'preview_donate',        'uuid, bigint')
    ) as t(s, f, a)$h$);

create or replace function pg_temp.recut_0144(p_fn text)
returns text
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0144 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0144 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0144(v_def, h.old);
    if v_n <> 1 then
      raise exception '0144 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  return v_def;
end $$;

create temp table recut_0144 on commit drop as
select fn, pg_temp.recut_0144(fn) as def from defs_before_0144;

do $$
declare
  r record;
begin
  for r in select * from recut_0144 order by fn loop
    execute r.def;
  end loop;
end $$;

-- ── 7. THE PROOF ───────────────────────────────────────────────────────────────────────────────
create temp table proven_0144 (k text primary key, v text) on commit drop;

do $$
declare
  d record;
  h record;
  v_rev text;
begin
  for d in select * from defs_before_0144 loop
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0144 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0144(v_rev, h.new) <> 1 then
        raise exception '0144 self-assert FAIL: % — the new text of hunk % is not in the live body exactly once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0144 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg
       or (select p.proowner from pg_proc p where p.oid = d.fn::regprocedure) <> d.owner then
      raise exception '0144 self-assert FAIL: % — ACL, volatility, definer, config or owner moved', d.fn;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%influence_post(%'
         and p.proname not in ('influence_post')) <> 1 then
    raise exception '0144 self-assert FAIL: influence_post must have exactly one caller (public.pay_city)';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage')
         and (p.prosrc like '%insert into public.port_influence%' or p.prosrc like '%update public.port_influence%')) <> 1 then
    raise exception '0144 self-assert FAIL: public.port_influence must have exactly one writer (influence_post)';
  end if;
  insert into proven_0144 values ('recut', '3 bodies reverse to their pre-images, attributes unmoved; pay_city is influence_post''s one caller, influence_post the book''s one writer');
end $$;

create or replace function pg_temp.probe_0144()
returns jsonb
language plpgsql
as $$
declare
  c_a      constant uuid := '00000000-0144-4000-8000-00000000000a';
  c_b      constant uuid := '00000000-0144-4000-8000-00000000000b';
  v_base   int := (select count(*) from public.players);
  v_a      uuid;
  v_b      uuid;
  v_prt    uuid := (select id from public.nations where code = 'PRT');
  v_esp    uuid := (select id from public.nations where code = 'ESP');
  v_work   record;
  v_city   uuid;
  v_r      jsonb;
  v_r2     jsonb;
  v_pts1   numeric;
  v_pts2   numeric;
  v_pts3   numeric;
  v_purse  bigint;
  v_bal    bigint;
  v_out    jsonb := '{}'::jsonb;
  v_buy    numeric;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    v_a := public.new_house(c_a, 'Casa da Dádiva 0144', 'PRT');
    v_b := public.new_house(c_b, 'Casa del Don 0144', 'ESP', 'LIS');
    perform public.credit(v_a, 'PROBE_0144', 1000000);
    perform public.credit(v_b, 'PROBE_0144', 1000000);
    -- the probe city: the first harbour (by code) whose works offer a stake the probe can buy, found
    -- in the live world; both probe fleets lie docked there, and its influence is emptied INSIDE the
    -- probe (rolled back) so the weights below are the formula's from share 0, whatever it held
    select w.port_id into v_city
      from public.city_works w join public.ports p on p.id = w.port_id and p.kind = 'HARBOUR'
     where public.city_offered(w.port_id, w.kind) >= 1
       and public.works_share_price(w.level) * least(public.city_offered(w.port_id, w.kind), 10) >= public.wc_int('invest_min_ducats')
     order by p.code, w.kind limit 1;
    if v_city is null then
      raise exception '0144 self-assert FAIL: no harbour offers a stake to invest in';
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_city where player_id in (v_a, v_b);
    delete from public.port_influence where port_id = v_city;

    -- (b) a pay_city of another kind posts nothing
    perform public.pay_city(v_a, v_city, 'BUY', 500, null);
    if exists (select 1 from public.port_influence where port_id = v_city) then
      raise exception '0144 self-assert FAIL: a BUY posted influence';
    end if;

    -- (c) an Invest posts its cost × the trailing weight to (city, PRT, the house)
    select w.kind, public.city_offered(w.port_id, w.kind) as offered, public.works_share_price(w.level) as price
      into v_work
      from public.city_works w
     where w.port_id = v_city and public.city_offered(w.port_id, w.kind) >= 1
       and public.works_share_price(w.level) * least(public.city_offered(w.port_id, w.kind), 10) >= public.wc_int('invest_min_ducats')
     order by w.kind limit 1;
    if v_work.kind is null then
      raise exception '0144 self-assert FAIL: the probe city offers no shares to invest in';
    end if;
    v_r := public.invest_for(v_a, v_city, v_work.kind, least(v_work.offered, 10));
    select points into v_pts1 from public.port_influence where port_id = v_city and nation_id = v_prt and player_id = v_a;
    if v_pts1 is distinct from (v_r->>'cost')::numeric * public.wc_num('influence_weight_trailing') then
      raise exception '0144 self-assert FAIL: an Invest of % posted % points, not cost × the trailing weight', v_r->>'cost', v_pts1;
    end if;
    v_out := v_out || jsonb_build_object('invest', format('%s coin → %s points', v_r->>'cost', v_pts1));

    -- (d) Donate dark
    perform cmd.assume_identity(c_a);
    v_r := cmd.donate(v_city, 1000);
    if v_r->>'error_code' is distinct from 'E_NOT_OFFERED' or strpos(v_r->>'error_message', 'not taking gifts yet') = 0 then
      raise exception '0144 self-assert FAIL: a gift was taken dark: %', v_r;
    end if;
    -- lit (inside the probe)
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    v_r := cmd.donate(v_city, 50);
    if v_r->>'error_code' is distinct from 'E_DONATE_MIN' then
      raise exception '0144 self-assert FAIL: a gift under the minimum was taken: %', v_r;
    end if;
    v_r := cmd.preview_donate(v_city, 1000);
    if not coalesce((v_r->>'ok')::boolean, false)
       or (select points from public.port_influence where port_id = v_city and nation_id = v_prt and player_id = v_a) <> v_pts1 then
      raise exception '0144 self-assert FAIL: the dry run of a gift moved something: %', v_r;
    end if;
    select ducats into v_purse from public.players where id = v_a;
    v_bal := public.treasury_balance(v_city);
    v_r := cmd.donate(v_city, 1000);
    select points into v_pts2 from public.port_influence where port_id = v_city and nation_id = v_prt and player_id = v_a;
    if not coalesce((v_r->>'ok')::boolean, false)
       or (select ducats from public.players where id = v_a) <> v_purse - 1000
       or public.treasury_balance(v_city) <> v_bal + 1000
       or not exists (select 1 from public.events where player_id = v_a and kind = 'DONATED' and (payload->>'amount')::int = 1000) then
      raise exception '0144 self-assert FAIL: a gift did not move purse, treasury and event as one: %', v_r;
    end if;
    -- PRT held all the influence (share 1): the leading weight
    if v_pts2 - v_pts1 <> 1000 * public.wc_num('influence_weight_leading') then
      raise exception '0144 self-assert FAIL: a gift from the only country there weighed %, not the leading weight', (v_pts2 - v_pts1) / 1000;
    end if;
    -- another country's gift into the same city weighs more than the leader's
    perform cmd.assume_identity(c_b);
    v_r2 := cmd.donate(v_city, 1000);
    select points into v_pts3 from public.port_influence where port_id = v_city and nation_id = v_esp and player_id = v_b;
    if not coalesce((v_r2->>'ok')::boolean, false) or v_pts3 is null or v_pts3 <= v_pts2 - v_pts1
       or v_pts3 <> 1000 * public.influence_weight(0) then
      raise exception '0144 self-assert FAIL: the trailing country''s gift weighed % (the leader''s %): %', v_pts3, v_pts2 - v_pts1, v_r2;
    end if;
    -- the shares reader agrees with the book
    if abs((select sum(share) from public.influence_shares(v_city)) - 1) > 1e-9
       or (select nation_id from public.influence_shares(v_city) limit 1) <> v_prt then
      raise exception '0144 self-assert FAIL: influence_shares does not read the book';
    end if;
    -- the cap: what is left today, refused with figures
    v_r := cmd.donate(v_city, public.wc_int('influence_day_cap'));
    if v_r->>'error_code' is distinct from 'E_DAY_CAP' or (v_r->'figures'->>'have')::numeric <> public.wc_int('influence_day_cap') - 1000 then
      raise exception '0144 self-assert FAIL: a gift past the day''s cap was not refused with the room left: %', v_r;
    end if;
    -- (e) a change of country: the next gift counts for the new country; the old row stays
    update public.players set nation_id = (select id from public.nations where code = 'ENG') where id = v_b;
    v_r := cmd.donate(v_city, 500);
    if not coalesce((v_r->>'ok')::boolean, false)
       or not exists (select 1 from public.port_influence where port_id = v_city and player_id = v_b and nation_id = (select id from public.nations where code = 'ENG'))
       or (select points from public.port_influence where port_id = v_city and nation_id = v_esp and player_id = v_b) <> v_pts3 then
      raise exception '0144 self-assert FAIL: after a change of country the gift did not count for the new one, or the old was touched: %', v_r;
    end if;
    -- (d) undocked
    perform cmd.assume_identity(c_a);
    update public.fleets set port_id = (select id from public.ports where kind = 'HARBOUR' and id <> v_city order by code limit 1)
     where player_id = v_a;   -- docked, but elsewhere
    v_r := cmd.donate(v_city, 500);
    if v_r->>'error_code' is distinct from 'E_NOT_DOCKED' then
      raise exception '0144 self-assert FAIL: a company not docked there gave: %', v_r;
    end if;
    update public.fleets set port_id = v_city where player_id = v_a;
    -- (f) the town hall's influence keys
    v_r := world.town_hall(v_city)->'influence';
    if (select array_agg(k order by k) from jsonb_object_keys(v_r) k) <> array['holder', 'home', 'open', 'shares', 'since', 'you']
       or (select array_agg(k order by k) from jsonb_object_keys(v_r->'you') k) <> array['cap', 'given_today', 'min', 'nation', 'points']
       or (select array_agg(k order by k) from jsonb_object_keys(v_r->'shares'->0) k) <> array['nation', 'points', 'share']
       or not (v_r->>'open')::boolean or v_r->'you'->>'nation' <> 'PRT' or (v_r->'you'->>'points')::numeric <> round(v_pts2) then
      raise exception '0144 self-assert FAIL: the town hall''s influence block is not the contract: %', v_r;
    end if;
    perform public.assert_ledger_reconciles(v_a);
    perform public.assert_ledger_reconciles(v_b);
    v_out := v_out || jsonb_build_object('donate', format('PRT leader +%s for 1000, ESP trailing +%s for 1000; cap leaves %s', v_pts2 - v_pts1, v_pts3, public.wc_int('influence_day_cap') - 1000));
    raise exception 'PROBE_ROLLBACK_0144';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0144' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if (select count(*) from public.players) <> v_base
     or (select value from public.world_config where key = 'influence_enabled') <> 'false'::jsonb then
    raise exception '0144 self-assert FAIL: the probe did not leave the world as it found it';
  end if;
  return v_out;
end $$;

do $$
declare
  v jsonb := pg_temp.probe_0144();
begin
  insert into proven_0144 values ('probe', v::text);
end $$;

do $$
begin
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('donate', 'preview_donate')) <> 2
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.function_name in ('donate', 'preview_donate')
                   and (e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')))
     or has_function_privilege('authenticated', 'public.donate_for(uuid, uuid, bigint)', 'execute')
     or has_function_privilege('authenticated', 'world.town_hall_influence(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.influence_post(uuid, uuid, bigint, text)', 'execute') then
    raise exception '0144 self-assert FAIL: the grants are not the contract (cmd.donate / preview_donate registered; the cores server-only)';
  end if;
  raise notice '0144 self-assert ok: A CITY COUNTS WHO GIVES — %',
    (select string_agg(k || ': ' || v, ' | ' order by k) from proven_0144);
end $$;
