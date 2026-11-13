-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0401 - A COAST SAILS AS A COAST  (the Doldrums no longer wall Guinea; the Guianas, the Philippines' Pacific side and the way out of the Seto too)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the sea conditions were lit for companies on 2026-11-14 (0398). The design (docs/SEA_CONDITIONS_AND_REGIONS.md section 2) means every coastal sea for
--   any hull of the game and lays the whole weight on the crossings. Four coasts were drawn inside a crossing, so a coastal passage between two harbours
--   of one rank met an ocean's ask. Found on the remembered courses (public.npc_courses: real sailed lines), 2026-11-14:
--     * THE GUINEA COAST. The North Atlantic below 10 N is one box, The Doldrums (asks wave 24), from Brazil to Africa. Every one of the 21 remembered
--       courses from Europe and Macaronesia to the Gulf of Guinea crosses it along the coast of Sierra Leone and Liberia: no barca reaches Guinea at
--       any title, though the Gulf itself asks 12. Accra to Soyo and Elmina to Luanda cross it too.
--     * THE GUIANAS. The same box on the American side: Belem to Willemstad, to Cumana and to Santo Domingo cross it, and Paramaribo lies in it.
--     * THE PHILIPPINES' PACIFIC SIDE. The Philippine Sea (asks 50) reaches the shore of Luzon, Samar and Taiwan: Tainan to Cebu, Manila to Naha,
--       Macau to Tidore and Ternate to Guangzhou cross it.
--     * THE WAY OUT OF THE SETO INLAND SEA. Osaka and Sakai (their sea asks 8) reach Kyushu, Korea and China only through the Kuroshio strip off Shikoku
--       and Kyushu, a coastal zone the design set at 16: a barca (12) of Sakai, Japan's capital, cannot leave her home sea.
--
-- WHAT THIS FILE DOES (data, and the derivations that follow it; no function is written, no rule moves):
--   1. THREE COASTAL BOXES in public.sea_zone_boxes, each a strip along a shore, tried before the ocean's box of its raster sea:
--        North Atlantic, south of 10 N and east of 20 W   ->  Gulf of Guinea (title 3, wave 12)
--        North Atlantic, south of 10 N and west of 45 W   ->  Caribbean Sea (title 4, wave 12)
--        Philippine Sea, west of 128 E (where the Kuroshio box does not already speak)   ->  Visayan Sea (title 7, wave 12)
--      The ocean stays a wall: The Doldrums keeps the Atlantic between 45 W and 20 W, the Philippine Sea everything east of 128 E.
--   1b. ONE OCEAN BOX, so that opening Guinea does not open the Atlantic: the South Atlantic was cut in two COASTAL zones at 20 W (Angola to the east,
--      Brazil to the west, each asking 12) with no ocean between them. Until today that did not matter: no hull under 24 reached Guinea or Angola.
--      With the Guinea coast open a barca could have sailed Angola to Recife on wave 12. The middle of the South Atlantic, between 30 W and the
--      meridian of Greenwich and north of 30 S, is now The Doldrums (asks 24, what the way there asked before): a strip of five degrees is left to
--      Brazil's shore and nine to thirteen to Africa's.
--   2. ONE ASK in public.sea_zones: The Kuroshio off Shikoku and Kyushu asks wave 12 (it asked 16). Its title (7) does not move.
--   3. THE DERIVATIONS, re-run as their own files ran them: public.sea_zone_cells (0215's build, the same statement), public.sea_leg_asks
--      (public.sea_leg_asks_derive, 0222), the merchants' remembered seas (public.npc_course_zones_fill, 0397).
--   world.sea_zone_map and world.sea_conditions read those tables: the map's shade and the Seas face follow with no client change (a client keeps the
--   map for its session; a reload reads the new one).
--
-- WHAT DOES NOT MOVE, ASSERTED BELOW: no harbour's own sea changes its title rank; no zone is added or removed (64); every cell that was water in a zone
--   is still in a zone; the crossings ask what they asked (Lisbon to Recife, Cape Verde to Recife, Lisbon to Havana, Manila to Guam).
-- LOCKS: row writes on three small tables and two derived ones (720 and about 62,000 rows, replaced). No function, no knob.
-- COST: the pair table's derivation is the long step (2.3 s on PostgreSQL 16 by 0222's measure; tens of seconds on PGlite).
-- NEWS: this file posts its own UPDATE row, public.news_update('0401', ...) (0347's law).
-- ROLLBACK (forward, owner only): scripts/ops/harness/sea-coast/rollback-0401.sql, a draft: the three boxes out, the ask back to 16, the derivations re-run.
-- SELF-ASSERT: at the end of this file, one DO block. BUDGET: statement_timeout 120 s, lock_timeout 5 s; the assert fails above 120 s in all.
-- VERSION: 0401 = 0400 + 1. data/sea-zones.json is changed with it; scripts/db/world-guard.mjs holds the tables equal to that file.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '120s';
set local lock_timeout = '5s';

do $g$
begin
  if exists (select 1 from public.sea_zone_boxes b join public.sea_zones z on z.code = b.zone_code join public.seas s on s.id = b.sea_id where s.code = 'NOR' and z.code = 'GUL') then
    raise exception '0401 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.sea_leg_asks_derive(uuid)') is null or to_regprocedure('public.npc_course_zones_fill()') is null
     or (select count(*) from public.sea_zones) <> 64
     or (select z.wave_min from public.sea_zones z where z.code = 'PHI-JP') <> 16
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR') <> 8
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'PHI') <> 2
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'SOU') <> 4 then
    raise exception '0401 refuses: the sea table is not the one this file was written against (64 zones, 8 boxes on NOR, 2 on PHI, the Kuroshio at 16)';
  end if;
end
$g$;

-- ── THE PRE-IMAGES ──
create temp table pre_0401_harbour on commit drop as
select p.id, p.code, z.code as zone, z.title_min, z.wave_min
  from public.ports p join public.sea_zones z on z.code = public.harbour_zone(p.id) where p.kind = 'HARBOUR';
create temp table pre_0401_cells on commit drop as select row_idx, zones from public.sea_zone_cells;
create temp table pre_0401_pair on commit drop as
select a.code as a, b.code as b, s.wave_min, s.title_min
  from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port
 where (a.code, b.code) in (('LIS', 'REC'), ('CID', 'REC'), ('LIS', 'HAV'), ('MNL', 'HAG'), ('LIS', 'FNC'), ('ACA', 'MNL'));
create temp table pre_0401_course on commit drop as
select a.code as a, b.code as b, c.course,
       (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(c.course))) as asks
  from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port;

-- ── 1. THE DATA ──
update public.sea_zones set wave_min = 12 where code = 'PHI-JP';
-- room before the ocean's boxes of each raster sea (a box's ord is its turn; the rest box keeps the last)
update public.sea_zone_boxes b set ord = b.ord + 2 from public.seas s where s.id = b.sea_id and s.code = 'NOR' and b.ord >= 7;
update public.sea_zone_boxes b set ord = b.ord + 1 from public.seas s where s.id = b.sea_id and s.code = 'PHI' and b.ord >= 2;
update public.sea_zone_boxes b set ord = b.ord + 10 from public.seas s where s.id = b.sea_id and s.code = 'SOU';
update public.sea_zone_boxes b set ord = b.ord - 9 from public.seas s where s.id = b.sea_id and s.code = 'SOU';
insert into public.sea_zone_boxes (zone_code, sea_id, ord, lat_min, lat_max, lon_min, lon_max)
select v.zone, s.id, v.ord, v.lat_min, v.lat_max, v.lon_min, v.lon_max
  from (values ('GUL', 'NOR', 7, null::numeric, 10::numeric, -20::numeric, null::numeric),
               ('CAR', 'NOR', 8, null, 10, null, -45),
               ('VIS', 'PHI', 2, null, null, null, 128),
               ('NOR-DOL', 'SOU', 1, -30, null, -30, 0)) v(zone, sea, ord, lat_min, lat_max, lon_min, lon_max)
  join public.seas s on s.code = v.sea;

-- ── 2. THE ZONE RASTER, rebuilt by 0215's own statement (copied, its two temp tables renamed) ──
delete from public.sea_zone_cells;
create temp table boxes_0401 on commit drop as
select s.raster_ordinal as sea_ord, b.ord, z.ord as zone_ord,
       b.lat_min::float8 as lat_min, b.lat_max::float8 as lat_max, b.lon_min::float8 as lon_min, b.lon_max::float8 as lon_max
  from public.sea_zone_boxes b
  join public.seas s on s.id = b.sea_id
  join public.sea_zones z on z.code = b.zone_code;
create index on boxes_0401 (sea_ord, ord);
create temp table bands_0401 on commit drop as
with cut as (
  select 'row' as axis, floor((90 - v) * 4 - 0.5)::int + 1 + d as at
    from boxes_0401 b cross join lateral (values (b.lat_min), (b.lat_max)) t(v) cross join (values (-1), (0), (1)) dd(d)
   where v is not null
  union
  select 'col', ceil((v + 180) * 4 - 0.5)::int + d
    from boxes_0401 b cross join lateral (values (b.lon_min), (b.lon_max)) t(v) cross join (values (-1), (0), (1)) dd(d)
   where v is not null)
select x.axis, row_number() over (partition by x.axis order by x.at)::int - 1 as i, x.at as first
  from (select 'row' as axis, 0 as at union select 'col', 0
        union select c.axis, c.at from cut c where c.at > 0 and c.at < case c.axis when 'row' then 720 else 1440 end) x;

insert into public.sea_zone_cells (row_idx, zones)
with rband as (select i as ri, first as r0 from bands_0401 where axis = 'row'),
cband as (select i as ci, first as c0 from bands_0401 where axis = 'col'),
answer as (   -- every (row band, column band, sea of a box) asked of the boxes once, at the band's first cell
  select r.ri, c.ci, s.sea_ord,
         (select b.zone_ord from boxes_0401 b
           where b.sea_ord = s.sea_ord
             and (b.lat_min is null or 90 - (r.r0 + 0.5) * 0.25 >= b.lat_min) and (b.lat_max is null or 90 - (r.r0 + 0.5) * 0.25 < b.lat_max)
             and (b.lon_min is null or (c.c0 + 0.5) * 0.25 - 180 >= b.lon_min) and (b.lon_max is null or (c.c0 + 0.5) * 0.25 - 180 < b.lon_max)
           order by b.ord limit 1) as zone_ord
    from rband r cross join cband c cross join (select distinct sea_ord from boxes_0401) s),
zmap as materialized (   -- one dense lookup per row band
  select r.ri, array_agg(coalesce(a.zone_ord, 0) order by c.ci, g.s) as zm
    from rband r cross join cband c cross join generate_series(0, 255) g(s)
    left join answer a on a.ri = r.ri and a.ci = c.ci and a.sea_ord = g.s
   group by r.ri),
colmap as materialized (select g.col, (select max(c.ci) from cband c where c.c0 <= g.col) * 256 + 1 as base from generate_series(0, 1439) g(col))
select c.row_idx,
       (select decode(string_agg(lpad(to_hex(z.zm[k.base + get_byte(c.seas, k.col)]), 2, '0'), '' order by k.col), 'hex') from colmap k)
  from public.sea_cells c
  join zmap z on z.ri = (select max(r.ri) from rband r where r.r0 <= c.row_idx);

-- ── 3. THE PAIR TABLE (0222's derivation) AND THE MERCHANTS' REMEMBERED SEAS (0397) ──
delete from public.sea_leg_asks;
insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min, zones)
select d.from_port, d.to_port, d.wave_min, d.title_min, d.zones from public.sea_leg_asks_derive() d;
select public.npc_course_zones_fill();

-- ── 4. THE SELF-ASSERT ──
do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_bad  text;
  v_n    int;
  v_moved text;
  v_open int;
begin
  -- the table: 64 zones, three more boxes, one rest box a sea, the Kuroshio at 12
  if (select count(*) from public.sea_zones) <> 64 or (select z.wave_min from public.sea_zones z where z.code = 'PHI-JP') <> 12
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR') <> 10
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'PHI') <> 3
     or (select count(*) from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'SOU') <> 5
     or exists (select 1 from public.sea_zone_boxes b group by b.sea_id
                having count(*) filter (where b.lat_min is null and b.lat_max is null and b.lon_min is null and b.lon_max is null) <> 1
                    or max(b.ord) filter (where b.lat_min is null and b.lat_max is null and b.lon_min is null and b.lon_max is null) <> max(b.ord)) then
    raise exception '0401 self-assert FAIL: the boxes are not as written (a sea''s rest box must be its one unbounded box and its last)';
  end if;
  -- the raster: 720 rows of 1,440; a cell is water in a zone exactly where it was; cells changed only inside the three strips
  if (select count(*) from public.sea_zone_cells) <> 720 or exists (select 1 from public.sea_zone_cells c where length(c.zones) <> 1440) then
    raise exception '0401 self-assert FAIL: the zone raster is not 720 rows of 1,440 cells';
  end if;
  select min(o.row_idx)::text into v_bad
    from pre_0401_cells o join public.sea_zone_cells n on n.row_idx = o.row_idx
   where exists (select 1 from generate_series(0, 1439) g where (get_byte(o.zones, g) = 0) <> (get_byte(n.zones, g) = 0));
  if v_bad is not null then
    raise exception '0401 self-assert FAIL: row % of the raster gained or lost water', v_bad;
  end if;
  select count(*) into v_n
    from pre_0401_cells o join public.sea_zone_cells n on n.row_idx = o.row_idx cross join generate_series(0, 1439) g
   where get_byte(o.zones, g) <> get_byte(n.zones, g)
     and not (   (90 - (o.row_idx + 0.5) * 0.25 < 10 and ((g + 0.5) * 0.25 - 180 >= -20 or (g + 0.5) * 0.25 - 180 < -45)
                  and get_byte(o.zones, g) = (select z.ord from public.sea_zones z where z.code = 'NOR-DOL')
                  and get_byte(n.zones, g) in (select z.ord from public.sea_zones z where z.code in ('GUL', 'CAR')))
              or ((g + 0.5) * 0.25 - 180 < 128 and (g + 0.5) * 0.25 - 180 > 100
                  and get_byte(o.zones, g) = (select z.ord from public.sea_zones z where z.code = 'PHI')
                  and get_byte(n.zones, g) = (select z.ord from public.sea_zones z where z.code = 'VIS'))
              or (90 - (o.row_idx + 0.5) * 0.25 >= -30 and (g + 0.5) * 0.25 - 180 >= -30 and (g + 0.5) * 0.25 - 180 < 0
                  and get_byte(o.zones, g) in (select z.ord from public.sea_zones z where z.code in ('SOU-ANG', 'SOU-BRA'))
                  and get_byte(n.zones, g) = (select z.ord from public.sea_zones z where z.code = 'NOR-DOL')));
  if v_n <> 0 then
    raise exception '0401 self-assert FAIL: % cell(s) changed zone outside the three coastal strips and the one ocean box', v_n;
  end if;
  -- the ocean is still a wall: mid-Atlantic at 5 N 30 W is The Doldrums, the open Philippine Sea at 15 N 135 E is the Philippine Sea
  if public.sea_zone_at(5, -30) is distinct from 'NOR-DOL' or public.sea_zone_at(15, 135) is distinct from 'PHI'
     or public.sea_zone_at(6, -12) is distinct from 'GUL' or public.sea_zone_at(8, -55) is distinct from 'CAR' or public.sea_zone_at(16, 124) is distinct from 'VIS'
     or public.sea_zone_at(-10, -15) is distinct from 'NOR-DOL' or public.sea_zone_at(-10, 5) is distinct from 'SOU-ANG' or public.sea_zone_at(-10, -33) is distinct from 'SOU-BRA' then
    raise exception '0401 self-assert FAIL: a strip or an ocean is not where it was drawn: % % % % %',
      public.sea_zone_at(5, -30), public.sea_zone_at(15, 135), public.sea_zone_at(6, -12), public.sea_zone_at(8, -55), public.sea_zone_at(16, 124);
  end if;
  -- no harbour's own sea changes its title rank
  select string_agg(o.code || ' ' || o.zone || '>' || z.code, ', ' order by o.code),
         string_agg(o.code, ' ' order by o.code) filter (where z.title_min <> o.title_min)
    into v_moved, v_bad
    from pre_0401_harbour o join public.sea_zones z on z.code = public.harbour_zone(o.id)
   where z.code <> o.zone;
  if v_bad is not null then
    raise exception '0401 self-assert FAIL: a harbour''s own sea changed its title rank: %', v_bad;
  end if;
  -- the pair table is the derivation's, whole, and a harbour's self row is its own sea
  if (select count(*) from public.sea_leg_asks) <> (select count(*) from public.ports p where p.kind = 'HARBOUR') ^ 2
     or exists (select 1 from public.sea_leg_asks s where s.from_port = s.to_port and s.zones[1] is distinct from public.harbour_zone(s.from_port)) then
    raise exception '0401 self-assert FAIL: the pair table is not one row a pair of harbours, or a self row is not the harbour''s own sea';
  end if;
  -- the crossings ask what they asked
  select string_agg(o.a || '-' || o.b, ' ') into v_bad
    from pre_0401_pair o join public.ports a on a.code = o.a join public.ports b on b.code = o.b
    join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id
   where s.wave_min <> o.wave_min or s.title_min <> o.title_min;
  if v_bad is not null or (select count(*) from pre_0401_pair) < 5 then
    raise exception '0401 self-assert FAIL: a crossing asks something else now: %', v_bad;
  end if;
  -- THE COASTS: every remembered course that only a coast's wrong box closed now asks no more than a barca holds; none asks more than it did
  select string_agg(o.a || '-' || o.b, ' ') into v_bad
    from pre_0401_course o
   where (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(o.course))) > o.asks
     -- but for the crossings of the South Atlantic, which asked 12 by a hole and ask The Doldrums' 24 now
     and not (o.asks < 24 and (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(o.course))) = 24
              and public.course_zones(o.course) @> array['NOR-DOL']);
  if v_bad is not null then
    raise exception '0401 self-assert FAIL: a remembered course asks MORE than it did: %', v_bad;
  end if;
  -- THE ATLANTIC IS STILL A WALL: no remembered course between the old world's Atlantic shore and the Americas can be sailed on a barca's 12
  select string_agg(o.a || '-' || o.b, ' ') into v_bad
    from pre_0401_course o join pre_0401_harbour ha on ha.code = o.a join pre_0401_harbour hb on hb.code = o.b
   where ((ha.title_min <= 3 and hb.zone in ('SOU-BRA', 'CAR', 'GCO', 'NOR-AM', 'GCE', 'NOR-DOL'))
       or (hb.title_min <= 3 and ha.zone in ('SOU-BRA', 'CAR', 'GCO', 'NOR-AM', 'GCE', 'NOR-DOL')))
     and (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(o.course))) <= 12;
  if v_bad is not null then
    raise exception '0401 self-assert FAIL: a remembered course crosses the Atlantic on a barca''s wave: %', v_bad;
  end if;
  select string_agg(o.a || '-' || o.b, ' ') into v_bad
    from pre_0401_course o
   where (o.a, o.b) in (('LIS', 'ELM'), ('LPA', 'OUI'), ('ACC', 'SOY'), ('ELM', 'LUA'), ('BEL', 'WIL'), ('CUM', 'BEL'), ('HIR', 'SAK'), ('OSA', 'BUS'), ('TAI', 'CEB'), ('MNL', 'NAH'))
     and (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(o.course))) > 12;
  select count(*) into v_open from pre_0401_course o
   where o.asks > 12 and (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(o.course))) <= 12;
  if v_bad is not null or v_open < 10 then
    raise exception '0401 self-assert FAIL: a coastal course is still closed to a barca: % (% remembered courses opened)', v_bad, v_open;
  end if;
  -- the merchants' memo is whole
  if exists (select 1 from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
              where not exists (select 1 from public.npc_course_zones_memo mm where mm.course_md5 = md5(st.course::text))) then
    raise exception '0401 self-assert FAIL: a merchant course is not remembered after the refill';
  end if;
  perform public.news_update('0401', 'Coasts sail as coasts: Guinea opens', '연안은 연안답게: 기니 항로 열림');
  if clock_timestamp() - v_t0 > interval '120 seconds' then
    raise exception '0401 self-assert FAIL: over its budget';
  end if;
  raise notice '0401 self-assert ok: A COAST SAILS AS A COAST. Three coastal boxes, one ocean box and one ask; 64 zones; the raster holds water where it did and changed only inside the strips; no harbour changed rank (own sea moved: %); the crossings ask what they asked; % remembered courses that asked more than 12 now ask 12 or less, none asks more; the pair table and the merchants'' memo re-derived. % ms.',
    coalesce(v_moved, 'none'), v_open, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
