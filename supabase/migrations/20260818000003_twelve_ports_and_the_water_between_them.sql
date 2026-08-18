-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0003 — TWELVE PORTS AND THE WATER BETWEEN THEM
--        The V0 world, seeded: 4 nations, 8 seas, 4 regions, 12 ports, 22 legs, 12 goods,
--        3 ship classes — exactly the scope table of DESIGN §K.1.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHERE THE NUMBERS COME FROM ─────────────────────────────────────────────────────────────────
--   Coordinates: DESIGN §B.2, the twelve-port table, decimal degrees WGS84 to 0.01°, transcribed
--   unchanged. Nothing here is recalled or invented.
--
--   Leg distances: computed from those coordinates with the haversine of §B.3, then multiplied by
--   an authored DETOUR factor where the sailed route goes round land. §B.3 licenses exactly this:
--   "A leg is a curated edge ... with a distance_nm that MAY EXCEED the great-circle figure where
--   the real route detours. ... The router never draws a line through land because it only ever
--   composes authored legs." The detour is written into each leg's `notes`, so a later reader can
--   see why Cádiz→Sevilla is 86 nm and not 54.
--
--   FIVE legs are PINNED BY THE DESIGN ITSELF — §B.3's worked-distances table publishes them, and
--   §K.1's ten-minute first session quotes "188 nm, 1.6 voyage-days" out loud. Those five are
--   seeded at exactly the published figure and asserted to equal it:
--       Lisboa→Cádiz 188 · Cádiz→Ceuta 61 · Lisboa→Funchal 525 · Lisboa→Las Palmas 709 ·
--       Ceuta→Tunis 751
--
-- ── THE INVARIANT ON EVERY LEG ──────────────────────────────────────────────────────────────────
--   distance_nm >= round(great-circle). A leg may detour; it may never be a shortcut through the
--   Earth. Asserted below for all 22, with the actual worst detour ratio printed.
--
-- ── ONE DELIBERATE SIMPLIFICATION, NAMED ────────────────────────────────────────────────────────
--   §B.2 gives Ceuta the culture "Latin/Maghrebi". `ports.culture` is a single token because
--   `goods.culture_mask` tests it by equality, and a compound token would silently match neither
--   half. Ceuta is seeded `latin` (it was a Portuguese garrison town in 1550) and its Maghrebi
--   character lives in the port's `country` field. Saying so here rather than letting a reader
--   discover the divergence in six months.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   Counts against §K.1 · every leg's endpoints resolve to real ports · canonical ordering with no
--   duplicate unordered pair · the >= great-circle invariant on all 22 · the five DESIGN-pinned
--   distances exactly · the leg graph is CONNECTED (all 12 reachable from Lisboa) · every nation's
--   capital resolves · the culture mask both blocks (2 Maghrebi ports refuse wine) and permits
--   (10 Latin ports do not) · the 0001 lockdown still holds after seven seeded tables.
--
-- Depends ONLY on: 0001 (lockdown), 0002 (the tables, voyage.gc_distance_nm).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── Nations (DESIGN §B.1; the four that own a V0 port) ─────────────────────────────────────────
insert into public.nations (code, name, flag_char, capital_port_code) values
  ('PRT', 'Portugal',       '⚓', 'LIS'),
  ('ESP', 'Castile-Spain',  '⚔', 'SVQ'),
  ('FRA', 'France',         '⚜', 'MRS'),
  ('OTT', 'Ottoman Empire', '☾', 'TUN')
on conflict (code) do nothing;

-- ── Seas (DESIGN §B.2 sea column; hazard_base within §B.6's stated 0.006-0.020 band) ───────────
insert into public.seas (code, name, hazard_base, piracy_index) values
  ('ATI', 'Atlântico Ibérico',   0.0100, 0.15),
  ('GIB', 'Strait of Gibraltar', 0.0080, 0.35),
  ('ATM', 'Atlantic Morocco',    0.0120, 0.40),
  ('ATL', 'Atlantic Islands',    0.0140, 0.20),
  ('GDL', 'Golfe du Lion',       0.0110, 0.30),
  ('LIG', 'Ligurian Sea',        0.0080, 0.25),
  ('SIC', 'Sicily Channel',      0.0160, 0.55),
  ('TYR', 'Tyrrhenian Sea',      0.0100, 0.30)
on conflict (code) do nothing;

-- ── Regions (the price-affinity unit, DESIGN §B.1) ─────────────────────────────────────────────
insert into public.regions (code, name) values
  ('IBE', 'Iberia'),
  ('ISL', 'Atlantic Isles'),
  ('MAG', 'Maghreb'),
  ('WMD', 'Western Mediterranean')
on conflict (code) do nothing;

-- ── The twelve ports (DESIGN §B.2, verbatim coordinates) ───────────────────────────────────────
insert into public.ports (
  code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
  size_tier, max_draft, has_yard, yard_tier, has_academy,
  dev_industry, dev_commerce, dev_military, tax_rate, crew_pool
)
select v.code, v.name, v.country,
       n.id, v.lat, v.lon, s.id, r.id, v.culture,
       v.size_tier, v.max_draft, v.yard_tier > 0, v.yard_tier, v.academy,
       v.dev_i, v.dev_c, v.dev_m, 0.03, v.crew_pool
  from (values
    -- code  name          country               nation lat      lon      sea    region culture     tier draft yard acad  dev_i dev_c dev_m crew
    ('LIS', 'Lisboa',      'Portugal',           'PRT',  38.71,  -9.14, 'ATI', 'IBE', 'latin',    5, 4, 3, true,  12, 17,  8, 400),
    ('OPO', 'Porto',       'Portugal',           'PRT',  41.15,  -8.61, 'ATI', 'IBE', 'latin',    3, 3, 2, false,  9,  9,  4, 200),
    ('SVQ', 'Sevilla',     'Castile',            'ESP',  37.39,  -5.99, 'ATI', 'IBE', 'latin',    5, 2, 2, true,  11, 14,  7, 320),
    ('CAD', 'Cádiz',       'Castile',            'ESP',  36.53,  -6.29, 'ATI', 'IBE', 'latin',    4, 4, 2, false,  7,  9,  9, 260),
    ('CEU', 'Ceuta',       'Portugal (to 1580)', 'PRT',  35.89,  -5.32, 'GIB', 'MAG', 'latin',    2, 3, 0, false,  4,  5, 11,  90),
    ('SAF', 'Safi',        'Morocco',             null,  32.30,  -9.24, 'ATM', 'MAG', 'maghrebi', 2, 2, 0, false,  5,  3,  3,  70),
    ('FNC', 'Funchal',     'Madeira, Portugal',  'PRT',  32.65, -16.91, 'ATL', 'ISL', 'latin',    2, 3, 0, false,  6,  6,  2,  80),
    ('LPA', 'Las Palmas',  'Canarias, Castile',  'ESP',  28.13, -15.43, 'ATL', 'ISL', 'latin',    2, 3, 0, false,  4,  5,  3,  75),
    ('MRS', 'Marseille',   'France',             'FRA',  43.30,   5.37, 'GDL', 'WMD', 'latin',    4, 4, 2, true,  10, 12,  6, 240),
    ('GOA', 'Genova',      'Republic of Genoa',   null,  44.41,   8.93, 'LIG', 'WMD', 'latin',    4, 4, 3, true,  13, 15,  6, 250),
    ('TUN', 'Tunis',       'Hafsid/Ottoman',     'OTT',  36.80,  10.18, 'SIC', 'MAG', 'maghrebi', 3, 3, 0, false,  6,  8, 10, 150),
    ('NAP', 'Napoli',      'Spanish Naples',     'ESP',  40.85,  14.27, 'TYR', 'WMD', 'latin',    4, 4, 2, false,  9, 11,  7, 230)
  ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture,
         size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
  join public.seas    s on s.code = v.sea_code
  join public.regions r on r.code = v.region_code
  left join public.nations n on n.code = v.nation_code
on conflict (code) do nothing;

-- ── The 22 legs (DESIGN §B.3; canonical from.code < to.code, undirected) ───────────────────────
insert into public.legs (from_port_id, to_port_id, distance_nm, hazard_mult, notes)
select pf.id, pt.id, v.nm, v.hz, v.note
  from (values
    -- pair          nm    haz   note (great-circle, and the detour if any)
    ('CAD','CEU',   61.0, 0.80, 'gc 60.7 nm — the Strait crossing, no detour. DESIGN B.3 pins 61.'),
    ('CAD','LIS',  188.0, 0.90, 'gc 188.4 nm. DESIGN B.3 and the K.1 first session both pin 188.'),
    ('CAD','LPA',  684.0, 1.20, 'gc 684.4 nm — open Atlantic, no land to round.'),
    ('CAD','OPO',  313.0, 1.00, 'gc 297.8 nm ×1.05 — the Atlantic coast round Cabo de São Vicente.'),
    ('CAD','SAF',  299.0, 1.00, 'gc 293.0 nm ×1.02 — standing off the Moroccan shoals.'),
    ('CAD','SVQ',   86.0, 0.60, 'gc 53.6 nm ×1.60 — up the Guadalquivir. The river is why SVQ draft is 2.'),
    ('CEU','GOA',  870.0, 1.20, 'gc 828.2 nm ×1.05 — south of the Balearics, then north to Liguria.'),
    ('CEU','MRS',  704.0, 1.10, 'gc 664.2 nm ×1.06 — the Alboran and Balearic passage.'),
    ('CEU','SAF',  299.0, 1.00, 'gc 290.5 nm ×1.03 — down the Atlantic coast of Morocco.'),
    ('CEU','TUN',  751.0, 1.30, 'gc 750.7 nm. DESIGN B.3 pins 751. The Barbary run — highest piracy.'),
    ('FNC','LIS',  525.0, 1.10, 'gc 524.9 nm. DESIGN B.3 pins 525.'),
    ('FNC','LPA',  282.0, 1.00, 'gc 282.0 nm — between the island groups.'),
    ('FNC','OPO',  647.0, 1.20, 'gc 646.8 nm — open Atlantic.'),
    ('FNC','SAF',  389.0, 1.10, 'gc 389.0 nm — Madeira to the Moroccan coast.'),
    ('GOA','MRS',  176.0, 0.90, 'gc 167.9 nm ×1.05 — the Ligurian coastal run.'),
    ('GOA','NAP',  344.0, 1.00, 'gc 318.2 nm ×1.08 — outside Elba and the Tuscan islands.'),
    ('LIS','LPA',  709.0, 1.20, 'gc 708.7 nm. DESIGN B.3 pins 709.'),
    ('LIS','OPO',  153.0, 0.90, 'gc 148.5 nm ×1.03 — the Portuguese coastal hop.'),
    ('LPA','SAF',  407.0, 1.00, 'gc 407.1 nm — the Canaries to the Maghreb.'),
    ('MRS','NAP',  473.0, 1.10, 'gc 422.8 nm ×1.12 — through the Strait of Bonifacio; a straight line crosses Corsica.'),
    ('MRS','TUN',  493.0, 1.20, 'gc 448.3 nm ×1.10 — west of Sardinia.'),
    ('NAP','TUN',  334.0, 1.20, 'gc 309.3 nm ×1.08 — the Sicily Channel, west of Sicily.')
  ) as v(f, t, nm, hz, note)
  join public.ports pf on pf.code = v.f
  join public.ports pt on pt.code = v.t
on conflict do nothing;

-- ── The twelve goods (DESIGN §K.1's exact list) ────────────────────────────────────────────────
insert into public.goods (code, name, base_value, bulk, perishable_pct_day, category, culture_mask) values
  ('sal',     'sal',      13.00, 1.000, 0.000, 'staple',       '{}'),
  ('vinho',   'vinho',    48.00, 1.000, 0.000, 'staple',       '{maghrebi}'),
  ('azeite',  'azeite',   36.00, 1.000, 0.001, 'staple',       '{}'),
  ('cortica', 'cortiça',  30.00, 1.600, 0.000, 'naval_stores', '{}'),
  ('trigo',   'trigo',     9.00, 1.000, 0.002, 'staple',       '{}'),
  ('la',      'lã',       42.00, 1.200, 0.000, 'textile',      '{}'),
  ('cobre',   'cobre',    34.00, 0.800, 0.000, 'metal',        '{}'),
  ('ferro',   'ferro',    26.00, 0.900, 0.000, 'metal',        '{}'),
  ('acucar',  'açúcar',   88.00, 0.900, 0.001, 'colonial',     '{}'),
  ('couro',   'couro',    55.00, 1.100, 0.001, 'colonial',     '{}'),
  ('tamaras', 'tâmaras',  40.00, 1.000, 0.004, 'colonial',     '{}'),
  ('coral',   'coral',   210.00, 0.300, 0.000, 'luxury',       '{}')
on conflict (code) do nothing;

-- ── The three V0 hulls (DESIGN §C.2, the rows marked "V0") ─────────────────────────────────────
insert into public.ship_classes
  (code, name, family, rig, hold, crew_required, crew_max, speed_kn, durability, guns, draft,
   build_hours, build_cost, tier) values
  ('barca',  'Barca',            'Western', 'lateen',  60,  8,  20, 5.00,  400,  0, 1,  24.0,  12000, 1),
  ('carlat', 'Caravela latina',  'Western', 'lateen',  90, 12,  30, 6.00,  550,  2, 1,  40.0,  26000, 2),
  ('nau',    'Nau / Carrack',    'Western', 'square', 400, 60, 140, 4.40, 1800, 12, 3,  96.0, 120000, 3)
on conflict (code) do nothing;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_nations   int;
  v_seas      int;
  v_regions   int;
  v_ports     int;
  v_legs      int;
  v_goods     int;
  v_classes   int;
  v_orphan    int;
  v_mis_order int;
  v_dupe      int;
  v_short     int;
  v_pinned    int;
  v_reach     int;
  v_cap       int;
  v_blocked   int;
  v_open      int;
  v_max_ratio numeric;
  v_grants    int;
begin
  -- (a) The V0 scope table of §K.1, counted back out of the database.
  select count(*) into v_nations from public.nations;
  select count(*) into v_seas    from public.seas;
  select count(*) into v_regions from public.regions;
  select count(*) into v_ports   from public.ports;
  select count(*) into v_legs    from public.legs;
  select count(*) into v_goods   from public.goods;
  select count(*) into v_classes from public.ship_classes;

  if v_ports <> 12 then raise exception '0003 self-assert FAIL: % ports seeded, DESIGN K.1 says 12', v_ports; end if;
  if v_legs  <> 22 then raise exception '0003 self-assert FAIL: % legs seeded, DESIGN K.1 says 22',  v_legs;  end if;
  if v_goods <> 12 then raise exception '0003 self-assert FAIL: % goods seeded, DESIGN K.1 says 12', v_goods; end if;
  if v_classes <> 3 then raise exception '0003 self-assert FAIL: % ship classes seeded, DESIGN K.1 says 3', v_classes; end if;
  if v_seas <> 8 then raise exception '0003 self-assert FAIL: % seas seeded, expected 8', v_seas; end if;
  if v_regions <> 4 then raise exception '0003 self-assert FAIL: % regions seeded, expected 4', v_regions; end if;
  if v_nations <> 4 then raise exception '0003 self-assert FAIL: % nations seeded, expected 4', v_nations; end if;

  -- (b) EVERY leg's endpoints resolve to a real port. The FKs make this structurally true; it is
  --     asserted anyway because the assert is what proves the seed JOINED, rather than silently
  --     dropping rows whose port code was misspelt — which would show up as 21 legs, not as an error.
  select count(*) into v_orphan
    from public.legs l
    left join public.ports pf on pf.id = l.from_port_id
    left join public.ports pt on pt.id = l.to_port_id
   where pf.id is null or pt.id is null;
  if v_orphan <> 0 then
    raise exception '0003 self-assert FAIL: % leg(s) point at a port that does not exist', v_orphan;
  end if;

  -- (c) Canonical ordering, and no unordered pair authored twice under two ids.
  select count(*) into v_mis_order
    from public.legs l
    join public.ports pf on pf.id = l.from_port_id
    join public.ports pt on pt.id = l.to_port_id
   where pf.code >= pt.code;
  if v_mis_order <> 0 then
    raise exception '0003 self-assert FAIL: % leg(s) are not stored in canonical (lower code -> higher code) order', v_mis_order;
  end if;

  select count(*) into v_dupe from (
    select least(pf.code, pt.code) a, greatest(pf.code, pt.code) b
      from public.legs l
      join public.ports pf on pf.id = l.from_port_id
      join public.ports pt on pt.id = l.to_port_id
     group by 1, 2 having count(*) > 1
  ) d;
  if v_dupe <> 0 then
    raise exception '0003 self-assert FAIL: % port pair(s) carry more than one leg — two authorities for one distance', v_dupe;
  end if;

  -- (d) THE INVARIANT: no leg is a shortcut through the Earth.
  select count(*) into v_short
    from public.legs l
    join public.ports pf on pf.id = l.from_port_id
    join public.ports pt on pt.id = l.to_port_id
   where l.distance_nm < round(voyage.gc_distance_nm(pf.lat::float8, pf.lon::float8, pt.lat::float8, pt.lon::float8)::numeric);
  if v_short <> 0 then
    raise exception '0003 self-assert FAIL: % leg(s) are SHORTER than the great-circle distance between their ports', v_short;
  end if;

  select max(round((l.distance_nm / voyage.gc_distance_nm(pf.lat::float8, pf.lon::float8, pt.lat::float8, pt.lon::float8)::numeric), 3))
    into v_max_ratio
    from public.legs l
    join public.ports pf on pf.id = l.from_port_id
    join public.ports pt on pt.id = l.to_port_id;
  -- Positive control on the ratio probe: if it came back 1.000 the detours were never seeded.
  if v_max_ratio is null or v_max_ratio <= 1.000 then
    raise exception '0003 self-assert FAIL: worst detour ratio is % — no leg detours around land, so the detour data never landed', v_max_ratio;
  end if;

  -- (e) The five distances DESIGN §B.3 publishes, at exactly the published figure.
  select count(*) into v_pinned from (
    select 1 from public.legs l
      join public.ports pf on pf.id = l.from_port_id
      join public.ports pt on pt.id = l.to_port_id
     where (pf.code, pt.code, l.distance_nm) in (
        ('CAD', 'LIS', 188.0), ('CAD', 'CEU', 61.0), ('FNC', 'LIS', 525.0),
        ('LIS', 'LPA', 709.0), ('CEU', 'TUN', 751.0))
  ) p;
  if v_pinned <> 5 then
    raise exception '0003 self-assert FAIL: only % of the 5 DESIGN B.3 published leg distances match', v_pinned;
  end if;

  -- (f) The leg graph is CONNECTED. A disconnected world is a world where SAIL can fail with
  --     E_NO_ROUTE for a reason no player could have anticipated.
  with recursive reach(id) as (
      select p.id from public.ports p where p.code = 'LIS'
    union
      select case when l.from_port_id = r.id then l.to_port_id else l.from_port_id end
        from public.legs l
        join reach r on r.id = l.from_port_id or r.id = l.to_port_id
  )
  select count(*) into v_reach from reach;
  if v_reach <> 12 then
    raise exception '0003 self-assert FAIL: only % of 12 ports are reachable from Lisboa through the leg graph', v_reach;
  end if;

  -- (g) Every nation's declared capital is a port that exists.
  select count(*) into v_cap
    from public.nations n
   where n.capital_port_code is not null
     and not exists (select 1 from public.ports p where p.code = n.capital_port_code);
  if v_cap <> 0 then
    raise exception '0003 self-assert FAIL: % nation(s) name a capital port that does not exist', v_cap;
  end if;

  -- (h) The culture mask BLOCKS and PERMITS — both halves, so neither is assumed.
  select count(*) into v_blocked
    from public.ports p, public.goods g
   where g.code = 'vinho' and p.culture = any(g.culture_mask);
  select count(*) into v_open
    from public.ports p, public.goods g
   where g.code = 'vinho' and not (p.culture = any(g.culture_mask));
  if v_blocked <> 2 then
    raise exception '0003 self-assert FAIL: wine is refused by % port(s); the 2 Maghrebi ports (Safi, Tunis) were expected', v_blocked;
  end if;
  if v_open <> 10 then
    raise exception '0003 self-assert FAIL: wine is permitted at % port(s); 10 Latin ports were expected — a mask that blocks everything is not a mask', v_open;
  end if;

  -- (i) The lockdown survived a seed of seven tables.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0003 self-assert FAIL: seeding minted % client write grant(s)', v_grants;
  end if;

  raise notice '0003 self-assert ok: % ports / % legs / % goods / % ship classes (DESIGN K.1: 12/22/12/3); all leg endpoints resolve, canonical order with no duplicate pair, 0 legs shorter than great-circle with worst detour ×%, all 5 DESIGN B.3 published distances exact, all 12 ports reachable from Lisboa, % nation capitals resolve, wine refused at 2 Maghrebi ports and open at 10 Latin ones, 0 client write grants',
    v_ports, v_legs, v_goods, v_classes, v_max_ratio, v_nations;
end $$;
