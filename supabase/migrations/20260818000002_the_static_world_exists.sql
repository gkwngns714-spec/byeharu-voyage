-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0002 — THE STATIC WORLD EXISTS
--        Nations, seas, regions, ports, legs, goods, ship classes — the tables nobody may write,
--        and the ONE distance authority.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS ESTABLISHES ───────────────────────────────────────────────────────────────────────
--   The eight static-world tables of docs/DESIGN.md Appendix 1, cut to the V0 scope of §K.1, with
--   RLS on and read-only access for signed-in players. They are seeded by 0003, never by a client.
--
--   And `voyage.gc_distance_nm(lat1, lon1, lat2, lon2)` — the haversine of DESIGN §B.3, IMMUTABLE,
--   defined ONCE. §B.3 is explicit about this: "Implemented once, in SQL, ... one authority, never
--   re-derived client-side. The client may compute the same number for display only."
--
-- ── ONE DECISION WORTH STATING ──────────────────────────────────────────────────────────────────
--   `legs` stores each authored edge ONCE, in a canonical direction (from_port_id < to_port_id by
--   code), with a UNIQUE constraint on the unordered pair. The leg graph is UNDIRECTED — a ship
--   sails Lisboa→Cádiz and Cádiz→Lisboa over the same water at the same distance — and storing two
--   rows per edge would be two authorities for one number, which is how they drift. 0006's router
--   walks the table in both directions from these single rows.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * All eight tables exist, RLS is ENABLED on all eight, and each carries exactly one SELECT
--     policy (a table with RLS on and no policy is invisible; a table with two is ambiguous).
--   * `authenticated` holds SELECT on all eight and `client_write_grants()` is still zero.
--   * gc_distance_nm reproduces the DESIGN §B.3 worked figure Lisboa→Cádiz = 188 nm to within
--     0.05 nm, is zero for a point against itself, and is symmetric — plus a NEGATIVE control
--     proving a different pair yields a different number, so "188" cannot be a stuck constant.
--
-- Depends ONLY on: 0001 (schemas, the lockdown, client_write_grants()).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── The ONE distance authority (DESIGN §B.3) ───────────────────────────────────────────────────
create or replace function voyage.gc_distance_nm(
  p_lat1 double precision, p_lon1 double precision,
  p_lat2 double precision, p_lon2 double precision
)
returns double precision
language sql
immutable
parallel safe
as $$
  -- R = 3440.065 nm, the mean Earth radius in nautical miles (DESIGN §B.3).
  select 2 * 3440.065 * asin(sqrt(
      power(sin(radians(p_lat2 - p_lat1) / 2), 2)
    + cos(radians(p_lat1)) * cos(radians(p_lat2))
    * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
  ))
$$;

comment on function voyage.gc_distance_nm(double precision, double precision, double precision, double precision) is
  'THE ONE great-circle distance, in nautical miles (DESIGN B.3). Immutable. Every distance in the '
  'game is this function or an authored leg distance that is asserted to be >= it.';

-- ── The static world ───────────────────────────────────────────────────────────────────────────
create table if not exists public.nations (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name              text not null,
  flag_char         text not null,
  capital_port_code text
);
comment on table public.nations is 'DESIGN B.1. capital_port_code is a code, not an FK: ports do not exist yet at 0002 and a circular FK buys nothing. 0003 asserts every code resolves.';

create table if not exists public.seas (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  hazard_base   numeric(6,4) not null check (hazard_base >= 0 and hazard_base <= 0.05),
  piracy_index  numeric(6,4) not null check (piracy_index >= 0 and piracy_index <= 1)
);
comment on column public.seas.hazard_base is 'DESIGN B.6: typically 0.006-0.020 per voyage-day.';

create table if not exists public.regions (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null
);

create table if not exists public.ports (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[A-Z]{3}$'),
  name          text not null,
  country       text not null,
  nation_id     uuid references public.nations(id),
  lat           numeric(6,2) not null check (lat between -90 and 90),
  lon           numeric(7,2) not null check (lon between -180 and 180),
  sea_id        uuid not null references public.seas(id),
  region_id     uuid not null references public.regions(id),
  culture       text not null,
  size_tier     int  not null check (size_tier between 1 and 5),
  max_draft     int  not null check (max_draft between 1 and 6),
  has_yard      boolean not null default false,
  yard_tier     int  not null default 0 check (yard_tier between 0 and 5),
  has_academy   boolean not null default false,
  is_ice_closed boolean not null default false,
  opened_year   int  not null default 1500,
  dev_industry  int  not null default 0 check (dev_industry between 0 and 20),
  dev_commerce  int  not null default 0 check (dev_commerce between 0 and 20),
  dev_military  int  not null default 0 check (dev_military between 0 and 20),
  tax_rate      numeric(5,4) not null default 0.03 check (tax_rate between 0 and 0.08),
  crew_pool     int  not null default 0 check (crew_pool >= 0),
  constraint ports_yard_tier_agrees check ((has_yard and yard_tier > 0) or (not has_yard and yard_tier = 0))
);
comment on column public.ports.tax_rate is 'DESIGN H.3 bands the Mayor-set market tax to 0-8%. The CHECK is that band, enforced structurally.';

create table if not exists public.legs (
  id           uuid primary key default gen_random_uuid(),
  from_port_id uuid not null references public.ports(id),
  to_port_id   uuid not null references public.ports(id),
  distance_nm  numeric(8,1) not null check (distance_nm > 0),
  hazard_mult  numeric(5,3) not null default 1.000 check (hazard_mult > 0 and hazard_mult <= 5),
  min_year     int not null default 1500,
  notes        text,
  constraint legs_not_a_loop check (from_port_id <> to_port_id),
  constraint legs_unordered_pair_unique unique (from_port_id, to_port_id)
);
comment on table public.legs is
  'DESIGN B.3. An UNDIRECTED authored edge, stored ONCE in canonical (lower code -> higher code) '
  'order. distance_nm may EXCEED the great-circle figure where the sailed route detours around '
  'land; it may never be less, and 0003 asserts that for every row.';

create table if not exists public.goods (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique,
  name               text not null,
  base_value         numeric(10,2) not null check (base_value > 0),
  bulk               numeric(6,3) not null default 1.000 check (bulk > 0),
  perishable_pct_day numeric(5,3) not null default 0 check (perishable_pct_day >= 0 and perishable_pct_day <= 0.2),
  category           text not null,
  culture_mask       text[] not null default '{}'
);
comment on column public.goods.culture_mask is
  'DESIGN B.4/G.3: cultures that will NOT trade this good (wine and pork in Islamic-culture ports). '
  'Empty array = traded everywhere.';

create table if not exists public.port_specialties (
  port_id uuid not null references public.ports(id) on delete cascade,
  good_id uuid not null references public.goods(id) on delete cascade,
  primary key (port_id, good_id)
);
comment on table public.port_specialties is
  'What a harbour is KNOWN FOR — the goods it actually dealt in, from data/ports.json. This is the '
  'authored input to the price gradient: 0005 derives every (port, good) affinity from how far the '
  'port is from the nearest place that produces the good, so ONE editorial fact (who produces what) '
  'decides fifteen thousand prices instead of a matrix nobody could check.';

create table if not exists public.ship_classes (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  family        text not null,
  rig           text not null check (rig in ('square', 'lateen', 'mixed', 'oared')),
  hold          int not null check (hold > 0),
  crew_required int not null check (crew_required > 0),
  crew_max      int not null check (crew_max > 0),
  speed_kn      numeric(4,2) not null check (speed_kn > 0),
  durability    int not null check (durability > 0),
  guns          int not null default 0 check (guns >= 0),
  draft         int not null check (draft between 1 and 6),
  build_hours   numeric(8,2) not null default 0,
  build_cost    numeric(12,2) not null default 0,
  tier          int not null check (tier between 1 and 5),
  constraint ship_classes_crew_band check (crew_max >= crew_required)
);

-- ── RLS: readable by a signed-in player, writable by nobody but the server ─────────────────────
alter table public.nations      enable row level security;
alter table public.seas         enable row level security;
alter table public.regions      enable row level security;
alter table public.ports        enable row level security;
alter table public.legs         enable row level security;
alter table public.goods        enable row level security;
alter table public.port_specialties enable row level security;
alter table public.ship_classes enable row level security;

create policy nations_read      on public.nations      for select to authenticated using (true);
create policy seas_read         on public.seas         for select to authenticated using (true);
create policy regions_read      on public.regions      for select to authenticated using (true);
create policy ports_read        on public.ports        for select to authenticated using (true);
create policy legs_read         on public.legs         for select to authenticated using (true);
create policy goods_read        on public.goods        for select to authenticated using (true);
create policy port_specialties_read on public.port_specialties for select to authenticated using (true);
create policy ship_classes_read on public.ship_classes for select to authenticated using (true);

grant select on public.nations, public.seas, public.regions, public.ports,
                public.legs, public.goods, public.port_specialties, public.ship_classes
  to authenticated;

grant execute on function voyage.gc_distance_nm(double precision, double precision, double precision, double precision)
  to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_tables constant text[] := array['nations','seas','regions','ports','legs','goods','port_specialties','ship_classes'];
  v_count  constant int    := 8;
  v_n        int;
  v_d_lis_cad double precision;
  v_d_self    double precision;
  v_d_rev     double precision;
  v_d_other   double precision;
begin
  -- (a) All seven exist.
  select count(*) into v_n
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and c.relname = any(v_tables);
  if v_n <> v_count then
    raise exception '0002 self-assert FAIL: % of % static-world tables exist', v_n, v_count;
  end if;

  -- (b) RLS is ON on all seven. A table with RLS off is readable and writable by anyone the
  --     GRANTs allow, and the GRANTs are not the row-level story.
  select count(*) into v_n
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname = any(v_tables) and c.relrowsecurity;
  if v_n <> v_count then
    raise exception '0002 self-assert FAIL: RLS is enabled on only % of % static-world tables', v_n, v_count;
  end if;

  -- (c) Exactly one SELECT policy each — no more (ambiguous), no fewer (invisible).
  select count(*) into v_n
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = any(v_tables) and p.cmd = 'SELECT';
  if v_n <> v_count then
    raise exception '0002 self-assert FAIL: % SELECT policies across the % static-world tables, expected exactly one each', v_n, v_count;
  end if;

  -- (d) authenticated can read all seven.
  select count(*) into v_n
    from information_schema.role_table_grants g
   where g.table_schema = 'public' and g.table_name = any(v_tables)
     and g.grantee = 'authenticated' and g.privilege_type = 'SELECT';
  if v_n <> v_count then
    raise exception '0002 self-assert FAIL: authenticated holds SELECT on only % of % static-world tables', v_n, v_count;
  end if;

  -- (e) The 0001 lockdown still holds after seven CREATE TABLEs. This is the exact moment the
  --     predecessor's drift was born: a new table inheriting a default GRANT ALL.
  select count(*) into v_n from public.client_write_grants();
  if v_n <> 0 then
    raise exception '0002 self-assert FAIL: creating the static world minted % client write grant(s): %',
      v_n, (select string_agg(table_name || ' ' || grantee || ':' || privilege, ', ') from public.client_write_grants());
  end if;

  -- (f) The distance authority reproduces DESIGN §B.3's own worked number.
  v_d_lis_cad := voyage.gc_distance_nm(38.71, -9.14, 36.53, -6.29);   -- Lisboa -> Cádiz
  if abs(v_d_lis_cad - 188.40) > 0.05 then
    raise exception '0002 self-assert FAIL: gc_distance_nm(Lisboa, Cádiz) = %, DESIGN B.3 says 188 nm', v_d_lis_cad;
  end if;
  v_d_self := voyage.gc_distance_nm(38.71, -9.14, 38.71, -9.14);
  if v_d_self <> 0 then
    raise exception '0002 self-assert FAIL: a port is % nm from itself', v_d_self;
  end if;
  v_d_rev := voyage.gc_distance_nm(36.53, -6.29, 38.71, -9.14);
  if abs(v_d_rev - v_d_lis_cad) > 0.0001 then
    raise exception '0002 self-assert FAIL: distance is not symmetric (% vs %)', v_d_lis_cad, v_d_rev;
  end if;
  -- NEGATIVE control: a different pair must give a different number, or "188" could be a constant.
  v_d_other := voyage.gc_distance_nm(35.89, -5.32, 36.80, 10.18);     -- Ceuta -> Tunis
  if abs(v_d_other - 750.75) > 0.05 then
    raise exception '0002 self-assert FAIL: gc_distance_nm(Ceuta, Tunis) = %, DESIGN B.3 says 751 nm', v_d_other;
  end if;

  raise notice '0002 self-assert ok: 8 static-world tables, RLS on all 8 with exactly 8 SELECT policies, authenticated reads all 8, 0 client write grants; gc_distance_nm gives Lisboa-Cádiz % nm and Ceuta-Tunis % nm (DESIGN B.3: 188 and 751), is 0 on identity and symmetric',
    round(v_d_lis_cad::numeric, 2), round(v_d_other::numeric, 2);
end $$;
