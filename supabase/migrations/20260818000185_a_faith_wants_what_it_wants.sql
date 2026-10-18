-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0185 — A FAITH WANTS WHAT IT WANTS  (PRICE_FACTORS slice P1: faith tastes per good, and "why this price")
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"is there a way for the prices move on many different factors? like relationship
-- with other countries, religion, merchants, any more ideas?"* and *"research on your ideas on different
-- games like uncharted origins, eve, runescape, and come up with a good idea then apply to this game"*.
-- docs/PRICE_FACTORS.md (merged, PR #221) is the design; this is its slice P1, the highest value for the
-- least cost: §3.1 (faith tastes) and §5 (why this price).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) FOUR TABLES, server-only, filled from data/faiths.json and data/faith-demand.json (the world guard
--     holds them equal): world.faiths (4), world.culture_faith (11 cultures → a faith),
--     world.port_faith_override (5 named ports), world.faith_demand (68 rows: a faith, a GOOD, its
--     multiplier 0.60 – 1.35, why). Per good, not per category: coffee and wine are both Drink, and Islam
--     loved one and forbade the other.
-- (2) ONE READER EACH: world.port_faith(port) — the override, else the culture's faith, else null;
--     world.faith_taste(port, good) = 1 + (multiplier − 1) × faith_demand_amplitude (1 where no row);
--     world.region_taste(port, good) — 0066's region × category appetite, MOVED verbatim out of
--     world.demand_for (unrounded).
-- (3) world.demand_for (0066, THE one derivation of port_goods.demand) composes them:
--     round(region_taste × faith_taste, 3). One hunk, sliced from the live body. Where the faith taste is 1
--     the value is exactly what it was (round(region_taste, 3) is 0066's own expression).
-- (4) port_goods.demand is re-derived where it moved. The price reads the same column through
--     world.mid_terms as before: NO pricing function changes (mid_from_terms, mid_terms, quote_priced are
--     untouched), so the quote path and the arrivals sweep cost exactly what they did.
-- (5) world.price_why(port, good) — NEW, the client's read (registered; authenticated only): the market
--     price and each of its terms as a multiplier (haul with its nm, affinity, taste with its region and
--     faith halves, stock, drift, season, development, band) and the quay's fee (spread, tax, bid factor,
--     profit tax). Every number is read from the authorities (world.mid_terms, world.price,
--     world.price_terms, world.tax_rate); the terms multiply back to the market price (asserted on a
--     sample). docs/PRICE_FACTORS.md F8: row 137 (the COMMAND desk serves every city's price) reversed
--     rows 55 / 64 and with them 0066's "never served" — the desk now says WHY a price is what it is.
-- (6) Knob faith_demand_amplitude 1.0 (F3).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change goods.culture_mask (a refusal stays a refusal, 0080), region_demand or its amplitude, any other
-- price term, any fleet, any purse, any grant of an existing function. Name a company in the read (the
-- per-company terms — tariffs, the investor's shave — come with slices P3 / P4).
--
-- ── THE PROOF (in this file; only its OWN rows are counted — production is lived in while it runs) ─
-- (a) the four tables hold exactly the rows this file inserts (a code that names no port or good is a red);
-- (b) every market row's demand = world.demand_for after the re-derive; every row whose faith taste is 1
--     carries the demand it had before this file ran (the pre-image, captured here); the rows that moved
--     are exactly those whose taste changed, and the UPDATE wrote exactly them;
-- (c) world.demand_for reverses to its pre-image; its ACL / owner / volatility / definer / config unmoved;
--     the new leaves and tables are server-only, and no new function is volatile (each only reads);
-- (d) world.price_why on a sample (Islamic coffee, an Islamic sherry, Christian wax, and an md5 sample of
--     60 rows): its mid / ask / bid = world.price; its terms × base = the mid to 0.05 %; its taste =
--     port_goods.demand; its faith = world.port_faith;
-- (e) the registry +1 (authenticated may, anon may not), the grant and read walls.
-- Timings: raise notice only.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE ×4 (new), CREATE FUNCTION, one CREATE OR REPLACE each of world.demand_for and the registry,
-- one UPDATE of the market rows whose demand moved (a few thousand of 132,090; row locks). No LOCK TABLE,
-- no set role, no set local, no begin. Deploy with the clock unwound (DEPLOY_RUNBOOK).
-- ROLLBACK: set faith_demand_amplitude 0 and re-derive (update public.port_goods set demand =
-- world.demand_for(port_id, good_id)) — every demand is 0066's again; or a forward slice restoring
-- world.demand_for's hunk (old text below) and dropping the read, its registry row and the four tables.
-- VERSION: 0185 PROVISIONAL — prod head 0181 when written (2026-10-18; 0182–0184 are open PRs #220, #219, #222); renumbered to head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0185(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table before_0185 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as reg_def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as reg_acl,
       replace(pg_get_functiondef('world.demand_for(uuid, uuid)'::regprocedure), E'\r', '') as dem_def,
       (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
          from pg_proc p where p.oid = 'world.demand_for(uuid, uuid)'::regprocedure) as dem_meta;

create temp table demand_before_0185 on commit drop as
select port_id, good_id, demand from public.port_goods;

do $$
begin
  if to_regclass('world.faiths') is not null or to_regclass('world.faith_demand') is not null
     or to_regclass('world.culture_faith') is not null or to_regclass('world.port_faith_override') is not null
     or to_regprocedure('world.price_why(uuid, uuid)') is not null
     or to_regprocedure('world.port_faith(uuid)') is not null
     or exists (select 1 from public.world_config where key = 'faith_demand_amplitude') then
    raise exception '0185 self-assert FAIL: something this file creates already exists';
  end if;
end $$;

-- ── 1. THE TABLES (server-only; data/faiths.json, data/faith-demand.json) ─────────────────────
create table world.faiths (
  code text primary key check (code ~ '^[a-z]+$'),
  name text not null
);
create table world.culture_faith (
  culture text primary key,
  faith   text not null references world.faiths(code),
  why     text not null check (length(why) > 12)
);
create table world.port_faith_override (
  port_id uuid primary key references public.ports(id) on delete cascade,
  faith   text not null references world.faiths(code),
  why     text not null check (length(why) > 12)
);
create table world.faith_demand (
  faith      text not null references world.faiths(code),
  good_id    uuid not null references public.goods(id) on delete cascade,
  multiplier numeric(6,3) not null check (multiplier between 0.600 and 1.350),
  why        text not null check (length(why) > 12),
  primary key (faith, good_id)
);
comment on table world.faiths is '0185: the four faiths a city can hold (data/faiths.json; docs/PRICE_FACTORS.md §3.1).';
comment on table world.culture_faith is '0185: a culture''s faith (data/faiths.json `cultures`). Read only through world.port_faith.';
comment on table world.port_faith_override is '0185: a port whose faith is not its culture''s (data/faiths.json `ports`). Read only through world.port_faith.';
comment on table world.faith_demand is
  '0185: what a faith''s cities pay for a GOOD, as a multiple (data/faith-demand.json) — the faith half of a city''s '
  'taste beside world.region_demand''s region × category half. Read only through world.faith_taste.';
revoke all on world.faiths, world.culture_faith, world.port_faith_override, world.faith_demand from public, anon, authenticated;

insert into world.faiths (code, name) values
  ('christian', 'Christian'),
  ('islamic', 'Islamic'),
  ('hindu', 'Hindu'),
  ('buddhist', 'Buddhist');

insert into world.culture_faith (culture, faith, why) values
  ('latin', 'christian', 'Catholic Iberia, Italy, France and their colonies'),
  ('anglo', 'christian', 'England and its colonies, Protestant after 1534'),
  ('germanic', 'christian', 'the Hanse and the Low Countries, Lutheran and Reformed'),
  ('nordic', 'christian', 'Lutheran Scandinavia from the 1530s'),
  ('islamic', 'islamic', 'the Ottoman, Persian, Arab and Maghrebi lands'),
  ('swahili', 'islamic', 'the Swahili coast''s towns were Muslim from the twelfth century'),
  ('malay', 'islamic', 'Malacca, Aceh, Banten, Demak and Ternate were sultanates by 1550'),
  ('indic', 'hindu', 'the coasts of India, Hindu in their people under Hindu and Muslim rulers alike'),
  ('sinic', 'buddhist', 'Ming China''s temples, beside Confucian rites'),
  ('korean', 'buddhist', 'Joseon kept its Buddhist temples under a Confucian court'),
  ('japanese', 'buddhist', 'Japan''s temples, beside Shinto shrines');

insert into world.port_faith_override (port_id, faith, why)
select p.id, v.faith, v.why from (values
  ('AYU', 'buddhist', 'Ayutthaya, Theravada Siam'),
  ('HAN', 'buddhist', 'Hanoi, Dai Viet''s Buddhist and Confucian capital'),
  ('HOI', 'buddhist', 'Hoi An, a Vietnamese and Chinese port of temples and clan halls'),
  ('MNL', 'christian', 'Manila, Spanish and Catholic from 1571'),
  ('CEB', 'christian', 'Cebu, where Legazpi founded the first Spanish town in 1565')
) as v(code, faith, why) join public.ports p on p.code = v.code;

insert into world.faith_demand (faith, good_id, multiplier, why)
select v.faith, g.id, v.mult, v.why from (values
  ('christian', 'wax', 1.35, 'altar candles had to be beeswax; tallow was not lit before the sacrament'),
  ('christian', 'frankincense', 1.25, 'the censer swung at every High Mass and every funeral'),
  ('christian', 'myrrh', 1.15, 'blended into church incense and the chrism'),
  ('christian', 'stockfish', 1.25, 'some 150 fast days a year without meat put salt fish on every Christian table'),
  ('christian', 'salt-cod', 1.25, 'some 150 fast days a year without meat put salt fish on every Christian table'),
  ('christian', 'bacalhau', 1.25, 'some 150 fast days a year without meat put salt fish on every Christian table'),
  ('christian', 'herring', 1.25, 'some 150 fast days a year without meat put salt fish on every Christian table'),
  ('christian', 'dried-fish', 1.25, 'some 150 fast days a year without meat put salt fish on every Christian table'),
  ('christian', 'wine', 1.15, 'the Mass needs wine, and every parish bought it'),
  ('islamic', 'coffee', 1.35, 'the drink of the Sufi orders and of the coffee houses of Mecca, Cairo and Istanbul from the 1500s'),
  ('islamic', 'frankincense', 1.30, 'bakhoor and oud perfumed the mosque, the house and the guest'),
  ('islamic', 'aloeswood', 1.30, 'bakhoor and oud perfumed the mosque, the house and the guest'),
  ('islamic', 'attar-of-roses', 1.25, 'the Prophet''s love of scent made rose oil and rosewater a pious luxury'),
  ('islamic', 'rosewater', 1.25, 'the Prophet''s love of scent made rose oil and rosewater a pious luxury'),
  ('islamic', 'ambergris', 1.20, 'burned and worn as a perfume from Baghdad to Malacca'),
  ('islamic', 'dates', 1.20, 'the fast of Ramadan is broken with a date'),
  ('islamic', 'quran-manuscripts', 1.30, 'every mosque and madrasa wanted a fair copy'),
  ('islamic', 'carpets', 1.15, 'the prayer rug and the mosque floor'),
  ('islamic', 'persian-carpet', 1.15, 'the prayer rug and the mosque floor'),
  ('islamic', 'port-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'sherry', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'madeira-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'canary-sack', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'malmsey', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'rhenish-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'claret', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'burgundy', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'chianti', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'retsina', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'commandaria', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'tokay', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'mission-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'chilean-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'palm-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'coconut-wine', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'cider', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'perry', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'mead', 0.60, 'wine is forbidden; only foreign quarters and non-Muslim subjects buy it'),
  ('islamic', 'english-ale', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'porter-beer', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'hamburg-beer', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'kvass', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'chicha', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'pulque', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'toddy', 0.60, 'intoxicating drink is forbidden; only foreigners and minorities buy it'),
  ('islamic', 'vodka', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'whisky', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'gin', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'aquavit', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'cognac', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'grappa', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'rakia', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'ouzo', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'arak-levant', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'baijiu', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'soju', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'shochu', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'cachaca', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'coconut-arrack', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'mezcal', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('islamic', 'pisco', 0.60, 'spirits are forbidden; only foreigners and minorities buy them'),
  ('hindu', 'camphor', 1.30, 'camphor is burned in the aarti before every image'),
  ('hindu', 'sandalwood', 1.30, 'sandal paste marks the brow and anoints the image in puja'),
  ('hindu', 'ghee', 1.20, 'ghee feeds the temple lamps and the fire offering'),
  ('buddhist', 'aloeswood', 1.30, 'the temple''s incense, burned before every altar from Kyoto to Canton'),
  ('buddhist', 'sandalwood', 1.30, 'the temple''s incense, burned before every altar from Kyoto to Canton'),
  ('buddhist', 'benzoin', 1.20, 'an incense resin of the temple censers'),
  ('buddhist', 'sutra-scrolls', 1.25, 'monasteries copied and bought the sutras as acts of merit')
) as v(faith, code, mult, why) join public.goods g on g.code = v.code;

insert into public.world_config (key, value, description) values
  ('faith_demand_amplitude', to_jsonb(1.0),
   '0185: how loudly the authored faith tastes in world.faith_demand are spoken: applied taste is '
   '1 + (multiplier - 1) x amplitude (0 = no faith tastes). docs/PRICE_FACTORS.md F3.');

-- ── 2. THE READERS ────────────────────────────────────────────────────────────────────────────
create function world.port_faith(p_port uuid)
returns text
language sql
stable
parallel safe
as $$
  -- 0185: THE one answer to "what does this city believe": the named port's faith, else its culture's,
  -- else null (guinean, oceanic, the open sea).
  select coalesce((select o.faith from world.port_faith_override o where o.port_id = p_port),
                  (select cf.faith from public.ports p join world.culture_faith cf on cf.culture = p.culture where p.id = p_port))
$$;

create function world.faith_taste(p_port uuid, p_good uuid)
returns numeric
language sql
stable
parallel safe
as $$
  -- 0185: what this city's FAITH pays for this good, as a multiple: 1 + (authored - 1) x amplitude, 1 where
  -- the city holds no faith or its faith has no row for the good. Unrounded; world.demand_for rounds.
  select 1 + (coalesce((select fd.multiplier from world.faith_demand fd
                         where fd.faith = world.port_faith(p_port) and fd.good_id = p_good), 1.000) - 1)
           * public.wc_num('faith_demand_amplitude')
$$;

create function world.region_taste(p_port uuid, p_good uuid)
returns numeric
language sql
stable
parallel safe
as $$
  -- 0185: what this city's REGION pays for this KIND of good — 0066's appetite, moved verbatim out of
  -- world.demand_for (which composed it and rounded it), unrounded.
  select 1 + (coalesce(rd.multiplier, 1.000) - 1) * public.wc_num('demand_amplitude')
    from public.ports p
    join public.goods g on g.id = p_good
    left join world.region_demand rd on rd.region_id = p.region_id and rd.category = g.category
   where p.id = p_port
$$;

revoke all on function world.port_faith(uuid) from public, anon, authenticated;
revoke all on function world.faith_taste(uuid, uuid) from public, anon, authenticated;
revoke all on function world.region_taste(uuid, uuid) from public, anon, authenticated;

-- ── 3. world.demand_for COMPOSES THEM (one hunk, sliced from the live body; reverses) ─────────
create temp table hunks_0185 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0185 values
('world.demand_for(uuid, uuid)', 1,
$h$  select round(1 + (coalesce(rd.multiplier, 1.000) - 1) * public.wc_num('demand_amplitude'), 3)
    from public.ports p
    join public.goods g on g.id = p_good
    left join world.region_demand rd on rd.region_id = p.region_id and rd.category = g.category
   where p.id = p_port
$h$,
$h$  -- 0185: THE TASTE = the region's appetite for the KIND of good (0066, world.region_taste) × the faith's
  -- for the GOOD (world.faith_taste), rounded once. Where the faith taste is 1 this is 0066's value exactly.
  select round(world.region_taste(p_port, p_good) * world.faith_taste(p_port, p_good), 3)
$h$);

do $$
declare
  b     record;
  h     record;
  v_rev text;
begin
  select * into b from before_0185;
  select * into h from hunks_0185 where n = 1;
  if pg_temp.occurs_0185(b.dem_def, h.old) <> 1 then
    raise exception '0185 self-assert FAIL: world.demand_for hunk occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0185(b.dem_def, h.old);
  end if;
  execute replace(b.dem_def, h.old, h.new);
  v_rev := replace(pg_get_functiondef('world.demand_for(uuid, uuid)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0185(v_rev, h.new) <> 1 or replace(v_rev, h.new, h.old) <> b.dem_def then
    raise exception '0185 self-assert FAIL: world.demand_for does not reverse to its pre-image';
  end if;
  if (select row(coalesce(p.proacl::text, ''), p.proowner, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, ''))::text
        from pg_proc p where p.oid = 'world.demand_for(uuid, uuid)'::regprocedure) <> b.dem_meta then
    raise exception '0185 self-assert FAIL: world.demand_for''s ACL, owner, volatility, definer or config moved';
  end if;
end $$;

-- ── 4. THE RE-DERIVE (only the rows whose taste moved) ────────────────────────────────────────
create temp table timing_0185 (phase text, ms numeric, n int) on commit drop;
do $$
declare
  t0  timestamptz := clock_timestamp();
  v_n int;
begin
  update public.port_goods pg set demand = d.want
    from (select x.port_id, x.good_id, world.demand_for(x.port_id, x.good_id) as want
            from public.port_goods x
           where world.faith_taste(x.port_id, x.good_id) <> 1) d
   where d.port_id = pg.port_id and d.good_id = pg.good_id and pg.demand is distinct from d.want;
  get diagnostics v_n = row_count;
  insert into timing_0185 values ('re-derive', extract(epoch from clock_timestamp() - t0) * 1000, v_n);
end $$;

-- ── 5. THE READ — why this price ──────────────────────────────────────────────────────────────
create function world.price_why(p_port uuid, p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0185: WHY THIS PRICE (docs/PRICE_FACTORS.md §5, F8) — the market price at one city and every term it is
-- made of, each as its multiplier, read from the authorities themselves: world.mid_terms (the row's terms),
-- world.price (the mid and its sides), world.price_terms (the quay's fee), world.tax_rate (the profit tax,
-- lit), world.region_taste / world.faith_taste / world.port_faith (the taste's two halves). The terms
-- multiply back to the mid: base × haul × affinity × taste × stock × drift × season × development × band.
-- Reads; writes nothing; settles nothing; names no company.
declare
  t       record;
  pr      record;
  q       record;
  v_stock numeric;
  v_nm    numeric;
  v_stm   numeric;
  v_raw   numeric;
  v_clamp numeric;
  v_faith text;
  v_now   timestamptz := now();
begin
  if p_port is null then
    raise exception 'E_NO_SUCH_PORT: a price needs a port' using errcode = 'P0001';
  end if;
  if p_good is null then
    raise exception 'E_NO_SUCH_GOOD: a price needs a good' using errcode = 'P0001';
  end if;
  select * into t from world.mid_terms(p_port, p_good);   -- refuses a missing market row E_NO_SUCH_GOOD
  select pg.stock, pg.haul_nm into v_stock, v_nm from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;
  select * into pr from world.price(p_port, p_good);
  select * into q from world.price_terms(p_port);
  v_faith := world.port_faith(p_port);

  -- the product world.mid_from_terms takes, term by term (the band clamps the market's own swing; the haul
  -- multiplies the banded product, 0173)
  v_stm   := power(t.m_target / greatest(v_stock, 1), t.m_elasticity);
  v_raw   := t.m_base * t.m_affinity * t.m_demand * v_stm * (1 + t.m_drift) * (1 + t.m_season) * (1 - t.m_dev_discount * t.m_dev);
  v_clamp := least(greatest(v_raw, t.m_band_lo * t.m_base), t.m_band_hi * t.m_base);

  return jsonb_build_object(
    'port', (select p.code from public.ports p where p.id = p_port),
    'good', (select g.code from public.goods g where g.id = p_good),
    'base', t.m_base,
    'mid', pr.mid, 'ask', pr.ask, 'bid', pr.bid,
    'faith', case when v_faith is not null then
               jsonb_build_object('code', v_faith, 'name', (select f.name from world.faiths f where f.code = v_faith)) end,
    'region', (select r.name from public.ports p join public.regions r on r.id = p.region_id where p.id = p_port),
    'terms', jsonb_build_array(
      jsonb_build_object('key', 'haul',        'mult', t.m_haul, 'nm', v_nm),
      jsonb_build_object('key', 'affinity',    'mult', t.m_affinity),
      jsonb_build_object('key', 'taste',       'mult', t.m_demand,
                         'region', round(world.region_taste(p_port, p_good), 3),
                         'faith',  round(world.faith_taste(p_port, p_good), 3)),
      jsonb_build_object('key', 'stock',       'mult', round(v_stm, 4), 'stock', v_stock, 'target', t.m_target),
      jsonb_build_object('key', 'drift',       'mult', 1 + t.m_drift),
      jsonb_build_object('key', 'season',      'mult', 1 + t.m_season),
      jsonb_build_object('key', 'development', 'mult', 1 - t.m_dev_discount * t.m_dev),
      jsonb_build_object('key', 'band',        'mult', case when v_raw > 0 then round(v_clamp / v_raw, 4) else 1 end)),
    'fee', jsonb_build_object('spread', q.spread, 'tax', q.tax, 'bid_factor', q.bid_factor,
                              'profit_tax', case when public.city_treasury_on() then world.tax_rate(p_port) else 0 end),
    'clock', jsonb_build_object('now', v_now, 'next_change_at', public.next_drift_change_at(v_now)));
end $$;

revoke all on function world.price_why(uuid, uuid) from public, anon, authenticated;
grant execute on function world.price_why(uuid, uuid) to authenticated;
comment on function world.price_why(uuid, uuid) is
  '0185 (docs/PRICE_FACTORS.md §5): a good''s market price at one city and each term it is made of, as a multiplier, '
  'plus the quay''s fee. Read from world.mid_terms / world.price / world.price_terms; the terms multiply back to the mid.';

-- ── 6. THE REGISTRY (one hunk, sliced from the live body; reverses; ACL unchanged) ────────────
do $$
declare
  b     record;
  v_old text := $h$      ('world',       'books',                 'int')
$h$;
  v_new text := $h$      ('world',       'books',                 'int'),
      -- 0185: why this price — the market price's terms at one city (docs/PRICE_FACTORS.md §5, P1).
      ('world',       'price_why',             'uuid, uuid')
$h$;
  v_rev text;
begin
  select * into b from before_0185;
  if pg_temp.occurs_0185(b.reg_def, v_old) <> 1 then
    raise exception '0185 self-assert FAIL: the registry''s last row occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0185(b.reg_def, v_old);
  end if;
  execute replace(b.reg_def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0185(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.reg_def then
    raise exception '0185 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.reg_acl then
    raise exception '0185 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 7. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad    int;
  v_moved  int;
  v_want   int;
  v_sample int := 0;
  v_t0     timestamptz;
  v_ms     numeric;
  r        record;
  j        jsonb;
  v_prod   numeric;
  v_ex     text := '';
begin
  -- (a) the tables hold exactly this file's rows
  if (select count(*) from world.faiths) <> 4 or (select count(*) from world.culture_faith) <> 11
     or (select count(*) from world.port_faith_override) <> 5 or (select count(*) from world.faith_demand) <> 68 then
    raise exception '0185 self-assert FAIL: the tables hold % faiths, % cultures, % ports, % tastes — not 4 / 11 / 5 / 68 (a code in the data names no port or good)',
      (select count(*) from world.faiths), (select count(*) from world.culture_faith),
      (select count(*) from world.port_faith_override), (select count(*) from world.faith_demand);
  end if;

  -- (b) every market row is its derivation; a row with no faith taste did not move; the moved rows are
  -- exactly the ones whose taste changed
  select count(*) filter (where pg.demand is distinct from world.demand_for(pg.port_id, pg.good_id)) into v_bad from public.port_goods pg;
  if v_bad <> 0 then
    raise exception '0185 self-assert FAIL: % market row(s) carry a demand world.demand_for does not answer', v_bad;
  end if;
  select count(*) into v_bad
    from public.port_goods pg join demand_before_0185 b on b.port_id = pg.port_id and b.good_id = pg.good_id
   where world.faith_taste(pg.port_id, pg.good_id) = 1 and pg.demand is distinct from b.demand;
  if v_bad <> 0 then
    raise exception '0185 self-assert FAIL: % row(s) with no faith taste changed their demand', v_bad;
  end if;
  select count(*) filter (where pg.demand is distinct from b.demand),
         count(*) filter (where world.faith_taste(pg.port_id, pg.good_id) <> 1
                            and round(world.region_taste(pg.port_id, pg.good_id) * world.faith_taste(pg.port_id, pg.good_id), 3) is distinct from b.demand)
    into v_moved, v_want
    from public.port_goods pg join demand_before_0185 b on b.port_id = pg.port_id and b.good_id = pg.good_id;
  if v_moved <> v_want or v_moved <> (select n from timing_0185 where phase = 're-derive') or v_moved = 0 then
    raise exception '0185 self-assert FAIL: % rows moved, % should have, the update wrote %', v_moved, v_want, (select n from timing_0185 where phase = 're-derive');
  end if;

  -- (c) the leaves and tables are server-only, and no new function is volatile
  if exists (select 1 from unnest(array['world.port_faith(uuid)', 'world.faith_taste(uuid, uuid)', 'world.region_taste(uuid, uuid)',
                                        'world.demand_for(uuid, uuid)']) f(fn),
                    unnest(array['anon', 'authenticated']) rl(role)
              where has_function_privilege(rl.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['world.port_faith(uuid)', 'world.faith_taste(uuid, uuid)', 'world.region_taste(uuid, uuid)',
                                            'world.price_why(uuid, uuid)']) f(fn)
                 join pg_proc p on p.oid = f.fn::regprocedure where p.provolatile <> 's')
     or exists (select 1 from unnest(array['world.faiths', 'world.culture_faith', 'world.port_faith_override', 'world.faith_demand']) t(tb),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_table_privilege(rl.role, t.tb, 'select') or has_table_privilege(rl.role, t.tb, 'insert')
                    or has_table_privilege(rl.role, t.tb, 'update') or has_table_privilege(rl.role, t.tb, 'delete')) then
    raise exception '0185 self-assert FAIL: a client can reach a leaf or a table, or a new function is not STABLE';
  end if;
  if pg_get_functiondef('world.price_why(uuid, uuid)'::regprocedure) ~ '(tick_[a-z_]+|settle)\s*\(' then
    raise exception '0185 self-assert FAIL: world.price_why steps a clock or settles a fleet';
  end if;

  -- (d) the read, on a sample: = world.price; its terms multiply back to the mid; its taste is the row's
  v_t0 := clock_timestamp();
  for r in
    with s as (
      (select pg.port_id, pg.good_id from public.port_goods pg join public.goods g on g.id = pg.good_id
        where g.code = 'coffee' and world.port_faith(pg.port_id) = 'islamic' order by pg.port_id limit 3)
      union all
      (select pg.port_id, pg.good_id from public.port_goods pg join public.goods g on g.id = pg.good_id
        where g.code = 'sherry' and world.port_faith(pg.port_id) = 'islamic' order by pg.port_id limit 3)
      union all
      (select pg.port_id, pg.good_id from public.port_goods pg join public.goods g on g.id = pg.good_id
        where g.code = 'wax' and world.port_faith(pg.port_id) = 'christian' order by pg.port_id limit 3)
      union all
      (select pg.port_id, pg.good_id from public.port_goods pg
        order by md5(pg.port_id::text || pg.good_id::text || '0185') limit 60)
    ) select distinct s.port_id, s.good_id from s
  loop
    v_sample := v_sample + 1;
    j := world.price_why(r.port_id, r.good_id);
    if (j->>'mid')::numeric is distinct from (select p.mid from world.price(r.port_id, r.good_id) p)
       or (j->>'ask')::numeric is distinct from (select p.ask from world.price(r.port_id, r.good_id) p)
       or (j->>'bid')::numeric is distinct from (select p.bid from world.price(r.port_id, r.good_id) p) then
      raise exception '0185 self-assert FAIL: world.price_why at % / % is not world.price: %', r.port_id, r.good_id, j;
    end if;
    select (j->>'base')::numeric * exp(sum(ln((x->>'mult')::numeric))) into v_prod from jsonb_array_elements(j->'terms') x;
    if abs(v_prod - (j->>'mid')::numeric) > greatest(0.0005 * (j->>'mid')::numeric, 0.0002) then
      raise exception '0185 self-assert FAIL: the terms multiply to %, the mid is % (%)', v_prod, j->>'mid', j;
    end if;
    if (select (x->>'mult')::numeric from jsonb_array_elements(j->'terms') x where x->>'key' = 'taste')
         is distinct from (select pg.demand from public.port_goods pg where pg.port_id = r.port_id and pg.good_id = r.good_id)
       or (j->'faith'->>'code') is distinct from world.port_faith(r.port_id) then
      raise exception '0185 self-assert FAIL: the read''s taste or faith is not the row''s: %', j;
    end if;
    if v_ex = '' and (j->'faith'->>'code') = 'islamic' and j->>'good' = 'coffee' then
      v_ex := format('%s coffee: taste %s (region %s × faith %s), mid %s', j->>'port',
        (select x->>'mult' from jsonb_array_elements(j->'terms') x where x->>'key' = 'taste'),
        (select x->>'region' from jsonb_array_elements(j->'terms') x where x->>'key' = 'taste'),
        (select x->>'faith' from jsonb_array_elements(j->'terms') x where x->>'key' = 'taste'), j->>'mid');
    end if;
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / greatest(v_sample, 1), 2);
  if v_sample < 60 then
    raise exception '0185 self-assert FAIL: the sample has % rows', v_sample;
  end if;

  -- (e) the registry +1, the walls
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0185) + 1
     or not exists (select 1 from public.client_rpc_entry_points() where fn = 'world.price_why(uuid, uuid)'::regprocedure)
     or not has_function_privilege('authenticated', 'world.price_why(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'world.price_why(uuid, uuid)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0185 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;

  raise notice '0185 self-assert ok: A FAITH WANTS WHAT IT WANTS. world.faiths 4, culture_faith 11, port_faith_override 5, faith_demand 68; world.demand_for = round(region_taste × faith_taste, 3), reverses to its pre-image; % market rows re-derived (exactly those whose taste moved; % ms), every row = world.demand_for, no row without a faith taste moved. world.price_why (registered; authenticated only) = world.price on % sampled rows, its terms multiply back to the mid, % ms a call. Example: %. Registry +1.',
    v_moved, (select round(ms) from timing_0185 where phase = 're-derive'), v_sample, v_ms, coalesce(nullif(v_ex, ''), 'none');
end $$;
