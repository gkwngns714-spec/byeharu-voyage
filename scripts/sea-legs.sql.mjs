// The SQL of a migration that re-ships the pair table (public.sea_leg_asks) from data/sea-legs.json, as scripts/build-sea-legs.mjs --migration
// fills it in (0442 is the first; 0403 was written by hand to the same steps). A template only: the builder owns every figure in it.

/** The one step that keeps the pair table true to the world it stands on. Created by 0442; every later migration that re-sails a stored course or
 *  moves a roadstead calls it (scripts/land-channels.sql.mjs, scripts/isthmus.sql.mjs), and tests/sea.noLandCrossing.spec.ts holds its three laws. */
export const KEEP_FN = `create or replace function public.sea_leg_asks_keep()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $keep$
-- 0442 THE PAIR TABLE KEEPS STEP WITH THE WORLD. public.sea_leg_asks is built from plotted courses (scripts/build-sea-legs.mjs), so a migration that
-- moves a roadstead or re-sails a remembered course can leave it behind: 0440 did (18 lanes crossed a sea their row did not hold; Galle's own row
-- named the sea its roadstead had left). This restores the three laws that can be restored without plotting, and says how many rows each moved:
--   own      a harbour's own row names the sea its roadstead lies in (public.harbour_zone)
--   lanes    a pair's row holds every sea of the course the world remembers on it (public.npc_courses, read through the merchants' memo)
--   asks     wave_min and title_min are the most the row's seas and the destination's own sea ask
-- It adds seas and never takes one away: the seas of the course plotted today are the build's to write (data/sea-legs.json, held by the world guard).
declare
  v_own   int;
  v_lanes int;
  v_asks  int;
begin
  update public.sea_leg_asks s
     set zones = array[public.harbour_zone(s.from_port)]
   where s.from_port = s.to_port and s.zones is distinct from array[public.harbour_zone(s.from_port)];
  get diagnostics v_own = row_count;

  update public.sea_leg_asks s
     set zones = (select array_agg(z.code order by z.code) from public.sea_zones z where z.code = any (s.zones || r.zones))
    from (select n.from_port, n.to_port, public.npc_course_zones(n.course) as zones from public.npc_courses n) r
   where r.from_port = s.from_port and r.to_port = s.to_port and not s.zones @> r.zones;
  get diagnostics v_lanes = row_count;

  update public.sea_leg_asks s
     set wave_min = q.w, title_min = q.t
    from (select s2.from_port, s2.to_port,
                 (select max(z.wave_min) from public.sea_zones z where z.code = any (s2.zones || own.zones))::int as w,
                 (select max(z.title_min) from public.sea_zones z where z.code = any (s2.zones || own.zones))::int as t
            from public.sea_leg_asks s2 join public.sea_leg_asks own on own.from_port = s2.to_port and own.to_port = s2.to_port) q
   where q.from_port = s.from_port and q.to_port = s.to_port and (s.wave_min, s.title_min) is distinct from (q.w, q.t);
  get diagnostics v_asks = row_count;

  return jsonb_build_object('own', v_own, 'lanes', v_lanes, 'asks', v_asks);
end
$keep$;

revoke all on function public.sea_leg_asks_keep() from public, anon, authenticated;
comment on function public.sea_leg_asks_keep() is
  '0442: keeps public.sea_leg_asks true to the world after a roadstead moves or a remembered course is re-sailed: own rows name their roadstead''s sea, '
  'a row holds every sea of its remembered course, wave_min and title_min are the most its seas and the destination''s sea ask. Called by migrations only.';
`

/** Where PART B begins in a migration that re-sails courses first (PART A: scripts/build-straits.mjs, 0446) and then re-ships the pair table and
 *  the quoted distances on the world PART A leaves. scripts/build-sea-legs-migration.mjs --append cuts the file here and writes PART B after it. */
export const PART_B_MARK =
  '-- ═══ PART B: THE PAIR TABLE AND THE QUOTED DISTANCES, ON THE WORLD PART A LEAVES (appended by scripts/build-sea-legs-migration.mjs --append) ═══'

/** What the three laws find broken, as one select (the self-assert, the proof and the guard spec read the same three). */
export const LAWS_SQL = `select
  (select string_agg(p.code, ' ' order by p.code) from public.ports p join public.sea_leg_asks s on s.from_port = p.id and s.to_port = p.id
    where p.kind = 'HARBOUR' and s.zones is distinct from array[public.harbour_zone(p.id)]) as own,
  (select string_agg(a.code || '-' || b.code, ' ' order by a.code, b.code)
     from public.npc_courses n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
     join public.ports a on a.id = n.from_port join public.ports b on b.id = n.to_port
    where not s.zones @> public.npc_course_zones(n.course)) as lanes,
  (select count(*)::int from public.sea_leg_asks s join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port
    where (s.wave_min, s.title_min) is distinct from
          ((select max(z.wave_min) from public.sea_zones z where z.code = any (s.zones || own.zones))::int,
           (select max(z.title_min) from public.sea_zones z where z.code = any (s.zones || own.zones))::int)) as asks`

export function migrationSql(x) {
  const T = x.tag // '0442'
  const intro = x.append
    ? `-- PART B of ${T} - THE PAIR TABLE AND THE QUOTED DISTANCES KEEP STEP WITH THE STRAITS  (owner row 352; 0442's procedure, run again)
--
-- GENERATED by scripts/build-sea-legs.mjs --before=${x.next} and scripts/build-sea-legs-migration.mjs --append (template scripts/sea-legs.sql.mjs) on the
-- cached world with PART A applied (${x.head}). Do not hand-edit: re-run the build and cut a NEW migration.
--
-- WHY: PART A opened four straits, put Messina's roadstead in its strait and re-sailed the stored courses the straits shorten. The course the
--   browser's course author plots between two harbours now runs through a strait wherever that is shorter, so the two things it is the author of move.
--
-- THE SEAS OF EVERY PAIR (public.sea_leg_asks; 0403, 0442): re-shipped from data/sea-legs.json, built again on this world (${x.harbours} harbours,
--   ${x.sets} sets); scripts/db/world-guard.mjs holds the table equal to the file. On the chain's world ${x.changed.zones} of ${x.harbours * x.harbours} rows change their seas and
--   ${x.changed.asks} what they ask (${x.changed.more} ask more, ${x.changed.less} less). Then public.sea_leg_asks_keep() (0442's function, not redefined here) adds the seas of
--   the courses THIS world remembers and sets what every row asks. The merchants are not touched: they read their own courses. No knob, no switch,
--   no cron job, no table.
${x.reach ? `--
-- THE DISTANCE THE QUAY QUOTES (public.sea_reaches.reaches; 0442 made it the length of the course a fleet really sails): measured again on this world
--   (scripts/ops/harness/seas-memo/measure-reaches.mjs: one flood a place, then refineCourse), one figure both ways. ${x.reach.moved.toLocaleString('en-US')} of ${x.reach.pairs.toLocaleString('en-US')} pairs
--   move: median ${x.reach.median} %, 95 in 100 under ${x.reach.p95} %, ${x.reach.over5} by more than 5 %; the largest is ${x.reach.worst.k} ${x.reach.worst.was} -> ${x.reach.worst.now}. Seven in eight
--   of them are SHORTER, through a strait. Messina's own courses north and west are 5 to 26 nm longer (its roadstead is off the town now, in the
--   strait), and 109 other pairs are up to 37 nm longer where the search takes a strait that is the longer way once straightened (the dev-log lists it).
--   THE PRICES FOLLOW: public.port_goods.haul (0173) is derived from these distances by world.haul_rows(), and the world guard holds the rows equal to
--   it. They are refilled from it, as 0208, 0212 and 0442 did. Measured on the chain's world: ${x.reach.haulRows.toLocaleString('en-US')} of ${x.reach.marketRows.toLocaleString('en-US')} market rows change their
--   multiplier; on those the price moves by ${x.reach.priceMedian} % at the median, under ${x.reach.priceP95} % for 95 in 100 and under ${x.reach.priceP99} % for 99 in 100;
--   ${x.reach.priceOver2} rows by more than 2 %, the largest ${x.reach.priceMax} %. No knob moves. public.price_history is not rescaled (as 0442).` : ''}
`
    : `-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ${T} - THE PAIR TABLE KEEPS STEP WITH THE COURSES  (owner row 352; the repair of what 0440 left behind in public.sea_leg_asks)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-sea-legs.mjs --before=${T} --migration (template scripts/sea-legs.sql.mjs) on the cached world at ${x.head}. Do not
-- hand-edit: re-run the build and cut a NEW migration.
--
-- WHY: public.sea_leg_asks (0215, 0222, 0403) says which seas lie between two harbours, and so what title and wave a leg asks. Trade's board
--   (public.sea_routes), the server's pathfinder (voyage.reach_passage) and public.sea_floor read it. 0403 made its author the build: the seas of
--   the course the browser plots between the two roadsteads, and of any course the world remembers on the pair. 0440 then moved 69 roadsteads, opened
--   three straits and re-sailed the remembered courses off the drawn land; 0441 changed the search's rule. Neither re-ran the build. Found on main
--   (proofs 97 and 98 red) and on production (read only, ${x.prodNote}):
--     * ${x.before.lanes} remembered courses on the chain's world (24 on production) cross a sea their pair's row does not hold, so the row asks less than
--       the lane a merchant sails: ${x.before.lanesList};
--     * Galle's roadstead moved from the Laccadive Sea (LAC) into the East Indian Ocean (IND-E) and its own row still says LAC, so every leg to
--       Galle asks what the wrong sea asks (proof 97: the board's tag for Galle is not the plain rule's reading);
--     * the rows still name the seas of the courses the search plotted before both migrations.
--   Both proofs' expectations are right; the table was stale. Which migration: 0440 for all of it (the 18 lanes and Galle are the same on the
--   chain at 0440 and at 0441); 0441 moved no row's law but changed what the browser plots, which the seed below now is.
--
-- WHAT THIS FILE DOES:
--   1. public.sea_leg_asks_keep(), a new function, called here and by every later migration that re-sails a course or moves a roadstead: own rows
--      name their roadstead's sea; a row holds every sea of its remembered course; wave_min and title_min are the most the row's seas and the
--      destination's sea ask. It adds seas and never removes one.
--   2. Every row takes the seas of the course the browser's course author plots today (src/domain/passage proposeCourse: the search, then since
--      0440 the re-sailing off the coast mask), roadstead to roadstead, sampled by the door's sampler (public.course_zones), with the seas of the
--      chain's remembered courses. The seed is data/sea-legs.json to the letter (${x.harbours} harbours, ${x.sets} sets); scripts/db/world-guard.mjs holds the
--      table equal to it. On the chain's world ${x.changed.zones} of ${x.harbours * x.harbours} rows change their seas and ${x.changed.asks} what they ask (${x.changed.more} ask more, ${x.changed.less} less).
--   3. public.sea_leg_asks_keep() then adds the seas of the courses THIS world remembers (production holds lanes the chain does not) and sets what
--      every row asks.
--   The merchants are not touched: they read their own courses (public.npc_course_zones), not this table. No knob, no switch, no cron job, no table.
${x.reach ? `--
-- THE DISTANCE THE QUAY QUOTES (public.sea_reaches.reaches), MEASURED AGAIN: it was the search's distance between the roadsteads as both stood before
--   0440. Since 0440 a fleet sails the course author's course (the search, then the re-sailing off the drawn land) between roadsteads 0440 moved,
--   and 0441 changed the search's rule: the voyage was no longer the distance quoted (proof 4: 508.35 nm sailed, 505 quoted; Messina to Zakynthos
--   291.3 quoted, ${x.reach.worst.now} sailed). Every pair is now the length of the course a fleet really sails (scripts/ops/harness/seas-memo/measure-reaches.mjs:
--   one flood a place, then refineCourse), one figure both ways. ${x.reach.moved.toLocaleString('en-US')} of ${x.reach.pairs.toLocaleString('en-US')} pairs move: median ${x.reach.median} %, 95 in 100 under ${x.reach.p95} %, ${x.reach.over5} by more than 5 %.
--   THE PRICES FOLLOW: public.port_goods.haul (a multiplier on a good's price for the sea between a city and its nearest maker, 0173) is derived from
--   these distances by world.haul_rows(), and the world guard holds the rows equal to it. They are refilled from it, as 0208 and 0212 did.
--   Measured on the chain's world: ${x.reach.haulRows.toLocaleString('en-US')} of ${x.reach.marketRows.toLocaleString('en-US')} market rows change their multiplier; on those the price moves by ${x.reach.priceMedian} % at the median,
--   under ${x.reach.priceP95} % for 95 in 100 and under ${x.reach.priceP99} % for 99 in 100; ${x.reach.priceOver2} rows by more than 2 %, the largest ${x.reach.priceMax} %. No knob moves.
--   public.price_history is not rescaled (0212 did, for a change of hundreds of times; here a chart steps by a fraction of a per cent).` : ''}
`
  return `${intro}-- LOCKS: row writes on public.sea_leg_asks (about ${x.changed.zones + x.changed.asks} of ${x.harbours * x.harbours} rows). TIME: ${x.ms} ms for the whole file on the cached world (PGlite).
-- ROLLBACK (forward, owner only): ${x.append ? `scripts/ops/harness/straits/rollback-pairs-${T}.sql: the rows as they were, after rollback-${T}.sql` : `scripts/ops/harness/seas-memo/rollback-${T}.sql: the rows as they were (and the function dropped)`}.
-- SELF-ASSERT: properties only (the three laws hold for every row; the seed is the file; a rolled-back probe breaks a row three ways and the
--   function mends each). It does not count rows the live world can add.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '120s';
set local lock_timeout = '5s';

-- ── 0. THE GUARD: refuse at once a world that is not the one the courses were plotted on ──
do $g$
begin
  if to_regprocedure('public.course_zones(jsonb)') is null or to_regprocedure('public.npc_course_zones(jsonb)') is null
     or to_regprocedure('public.harbour_zone(uuid)') is null or to_regclass('public.npc_courses') is null or to_regclass('voyage.drawn_roadsteads') is null then
    raise exception '${T} refuses: the sea conditions (0215), the merchants'' memo (0397), the remembered courses (0203) or the drawn roadsteads (0440) are not in this world';
  end if;
  if (select string_agg(p.code, ' ' order by p.code collate "C") from public.ports p where p.kind = 'HARBOUR') is distinct from '${x.harbourList}'
     or md5((select string_agg(p.code || ':' || sr.roadstead_lat || ',' || sr.roadstead_lon, ' ' order by p.code collate "C")
               from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR')) <> '${x.roadsMd5}'
     or md5((select encode(r.cells, 'hex') from public.sea_raster r where r.id = 1)) <> '${x.rasterMd5}'
     or md5((select string_agg(encode(c.zones, 'hex'), '' order by c.row_idx) from public.sea_zone_cells c)) <> '${x.zonesMd5}' then
    raise exception '${T} refuses: the harbours, the roadsteads, the sea raster or the sea boxes are not the ones its courses were plotted on (re-run scripts/build-sea-legs.mjs)';
  end if;
end
$g$;

-- ── 1. THE FUNCTION ──
${x.append ? '-- public.sea_leg_asks_keep() is 0442\'s: PART A has already called it, and it is not redefined here.' : KEEP_FN}
create function pg_temp.laws_${T}() returns table (own text, lanes text, asks int) language sql stable as $l$
${LAWS_SQL}
$l$;

-- ── 2. THE ROWS, from the seed (data/sea-legs.json, to the letter) ──
create temp table seed_${T} on commit drop as select $seed$${x.seed}$seed$::jsonb as j;

do $s$
begin
  if (select md5((s.j -> 'harbours')::text || (s.j -> 'sets')::text || (s.j -> 'legs')::text) from seed_${T} s) <> '${x.seedMd5}' then
    raise exception '${T} refuses: its seed is not data/sea-legs.json as built';
  end if;
end
$s$;

create temp table pre_${T} on commit drop as
select s.from_port, s.to_port, s.wave_min, s.title_min, s.zones from public.sea_leg_asks s;
alter table pre_${T} add primary key (from_port, to_port);
analyze pre_${T};

create temp table h_${T} on commit drop as
select c.i::int as i, p.id
  from seed_${T} s cross join lateral jsonb_array_elements_text(s.j -> 'harbours') with ordinality c(code, i)
  join public.ports p on p.code = c.code and p.kind = 'HARBOUR';
alter table h_${T} add primary key (i);
analyze h_${T};

create temp table st_${T} on commit drop as
select (t.i - 1)::int as k, q.zones, q.n = cardinality(string_to_array(t.s, ' ')) as known
  from seed_${T} s cross join lateral jsonb_array_elements_text(s.j -> 'sets') with ordinality t(s, i)
 cross join lateral (select array_agg(z.code order by z.code) as zones, count(*) as n
                       from public.sea_zones z where z.code = any (string_to_array(t.s, ' '))) q;
alter table st_${T} add primary key (k);
analyze st_${T};

create temp table new_${T} on commit drop as
select hf.id as from_port, ht.id as to_port, st.zones, st.known
  from (select r.i::int as fi, e.j::int as ti, e.k::int as k
          from seed_${T} s cross join lateral jsonb_array_elements(s.j -> 'legs') with ordinality r(leg, i)
         cross join lateral jsonb_array_elements_text(r.leg) with ordinality e(k, j)) lg
  join h_${T} hf on hf.i = lg.fi join h_${T} ht on ht.i = lg.ti join st_${T} st on st.k = lg.k;
alter table new_${T} add primary key (from_port, to_port);
analyze new_${T};

update public.sea_leg_asks s
   set zones = n.zones
  from new_${T} n
 where n.from_port = s.from_port and n.to_port = s.to_port and n.known and s.zones is distinct from n.zones;

${x.reach ? `-- ── 2b. THE DISTANCES THE QUAY QUOTES, measured again; and the prices that are derived from them ──
create temp table reach_${T} on commit drop as
select e.key as code, e.value as reaches from jsonb_each($reach$${x.reach.json}$reach$::jsonb) e;
alter table reach_${T} add primary key (code);

do $r$
declare
  v_bad text;
  v_n   int;
begin
  if (select string_agg(sr.code, ' ' order by sr.code collate "C") from public.sea_reaches sr) is distinct from (select string_agg(r.code, ' ' order by r.code collate "C") from reach_${T} r) then
    raise exception '${T} refuses: the places of public.sea_reaches are not the ones the distances were measured for';
  end if;
  update public.sea_reaches sr set reaches = r.reaches from reach_${T} r where r.code = sr.code and sr.reaches is distinct from r.reaches;
  -- one answer both ways round, every place reaches every other, and no figure is shorter than the straight line between the two roadsteads
  select string_agg(a.code || '-' || b.code, ' '), count(*) into v_bad, v_n
    from public.sea_reaches a join public.sea_reaches b on b.code <> a.code
   where (a.reaches ->> b.code) is null or (a.reaches ->> b.code)::numeric <> (b.reaches ->> a.code)::numeric
      or (a.reaches ->> b.code)::numeric < voyage.gc_distance_nm(a.roadstead_lat::float8, a.roadstead_lon::float8, b.roadstead_lat::float8, b.roadstead_lon::float8) - 0.1;
  if v_n > 0 then
    raise exception '${T} self-assert FAIL: % pair(s) are not one distance both ways, or are shorter than the straight line: %', v_n, left(v_bad, 400);
  end if;
  -- THE PRICES: every market row's haul is the one derivation's answer again (0173, 0208, 0212's refill)
  update public.port_goods pg set haul_nm = h.haul_nm, haul = h.haul
    from world.haul_rows() h
   where h.port_id = pg.port_id and h.good_id = pg.good_id and (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
  get diagnostics v_n = row_count;
  if exists (select 1 from public.port_goods pg join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
              where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul)) then
    raise exception '${T} self-assert FAIL: a market row''s haul is not world.haul_rows()''s answer after the refill';
  end if;
  raise notice '${T}: the quoted distances measured again; % market row(s) refilled from world.haul_rows()', v_n;
end
$r$;

` : ''}-- ── 3. SELF-ASSERT, with a probe that is rolled back; then the step for real ──
do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    int;
  v_res  jsonb;
  v_law  record;
  v_lane record;
  v_port uuid;
  v_zone text;
  v_other text;
  v_moved jsonb;
begin
  select count(*) into v_h from public.ports p where p.kind = 'HARBOUR';
  if (select count(*) from public.sea_leg_asks) <> v_h * v_h or (select count(*) from new_${T} n where n.known) <> v_h * v_h then
    raise exception '${T} self-assert FAIL: the pair table is not one row a pair of % harbours from the seed (% rows, % seed rows read)',
      v_h, (select count(*) from public.sea_leg_asks), (select count(*) from new_${T} n where n.known);
  end if;

  -- THE PROBE (rolled back): a row broken three ways is mended by the function, and nothing else moves.
  begin
    perform public.sea_leg_asks_keep();   -- the table in step first, so what the probe sees moved is the probe's
    select n.from_port, n.to_port, public.npc_course_zones(n.course) as zones into v_lane
      from public.npc_courses n where cardinality(public.npc_course_zones(n.course)) >= 2 order by n.from_port, n.to_port limit 1;
    select p.id, public.harbour_zone(p.id) into v_port, v_zone from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
    select z.code into v_other from public.sea_zones z where z.code <> v_zone order by z.code limit 1;
    if v_lane.from_port is null or v_port is null or v_other is null then
      raise exception '${T} self-assert FAIL: the world holds no lane of two seas, no harbour or one sea only: the probe has nothing to break';
    end if;
    update public.sea_leg_asks s set zones = v_lane.zones[1:1], wave_min = 0, title_min = 0 where s.from_port = v_lane.from_port and s.to_port = v_lane.to_port;
    update public.sea_leg_asks s set zones = array[v_other] where s.from_port = v_port and s.to_port = v_port;
    select * into v_law from pg_temp.laws_${T}();
    if v_law.own is null or v_law.lanes is null or v_law.asks < 1 then
      raise exception '${T} self-assert FAIL: the three laws do not see a row broken on purpose (own %, lanes %, asks %)', v_law.own, v_law.lanes, v_law.asks;
    end if;
    v_res := public.sea_leg_asks_keep();
    select * into v_law from pg_temp.laws_${T}();
    if v_law.own is not null or v_law.lanes is not null or v_law.asks <> 0 or (v_res ->> 'own')::int <> 1 or (v_res ->> 'lanes')::int <> 1 or (v_res ->> 'asks')::int < 1
       or not (select s.zones @> v_lane.zones from public.sea_leg_asks s where s.from_port = v_lane.from_port and s.to_port = v_lane.to_port)
       or (select s.zones from public.sea_leg_asks s where s.from_port = v_port and s.to_port = v_port) is distinct from array[v_zone] then
      raise exception '${T} self-assert FAIL: the function did not mend the probe (%; own %, lanes %, asks %)', v_res, v_law.own, v_law.lanes, v_law.asks;
    end if;
    raise exception using errcode = 'ZX${T.slice(1)}', message = v_res::text;
  exception when sqlstate 'ZX${T.slice(1)}' then
    raise notice '${T} probe (rolled back): a lane row cut to one sea, a harbour''s own row given another sea: mended %', sqlerrm;
  end;

  -- THE STEP, for real
  v_res := public.sea_leg_asks_keep();
  select * into v_law from pg_temp.laws_${T}();
  if v_law.own is not null or v_law.lanes is not null or v_law.asks <> 0 then
    raise exception '${T} self-assert FAIL: after the step, own rows off: %; lanes off their row: %; rows asking other than their seas: %', v_law.own, left(v_law.lanes, 600), v_law.asks;
  end if;
  -- ${x.append ? 'Messina' : 'Galle'}, by name: its own row is the sea its roadstead lies in${x.append ? ' (its roadstead moved into the strait)' : ', and it is not the sea it held'}
  if not exists (select 1 from public.ports p join public.sea_leg_asks s on s.from_port = p.id and s.to_port = p.id
                   join pre_${T} o on o.from_port = p.id and o.to_port = p.id
                  where p.code = '${x.append ? 'MES' : 'GAL'}' and s.zones = array[public.harbour_zone(p.id)]) then
    raise exception '${T} self-assert FAIL: ${x.append ? 'Messina' : 'Galle'}''s own row is not its roadstead''s sea';
  end if;
  -- every row still holds every sea the seed gave it (the function only adds)
  if exists (select 1 from new_${T} n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
              where n.known and n.from_port <> n.to_port and not s.zones @> n.zones) then
    raise exception '${T} self-assert FAIL: a row lost a sea of its plotted course';
  end if;
  select jsonb_build_object(
           'seas', count(*) filter (where s.zones <> o.zones),
           'asks', count(*) filter (where s.wave_min <> o.wave_min or s.title_min <> o.title_min),
           'more', count(*) filter (where s.wave_min > o.wave_min or s.title_min > o.title_min),
           'less', count(*) filter (where s.wave_min < o.wave_min or s.title_min < o.title_min)) into v_moved
    from public.sea_leg_asks s join pre_${T} o on o.from_port = s.from_port and o.to_port = s.to_port;

  comment on table public.sea_leg_asks is
    '0215, 0222, 0403, ${T}: what a leg between two harbours asks. zones = the seas of the course the browser''s course author plots from the first '
    'roadstead to the second (scripts/build-sea-legs.mjs, data/sea-legs.json: the search, then the re-sailing off the coast mask), sampled by '
    'public.course_zones, with the seas of any course the world remembers on the pair (public.npc_courses); wave_min, title_min = the most those seas '
    'and the destination''s own sea ask. A harbour''s own row is its roadstead''s sea. Not hand-edited: a slice that moves a sea box, the raster, a '
    'roadstead or a harbour, or re-sails a remembered course, calls public.sea_leg_asks_keep() and re-runs the build. Read by public.sea_routes (Trade), '
    'voyage.reach_passage and public.sea_floor.';

  raise notice '${T} self-assert ok: THE PAIR TABLE KEEPS STEP WITH THE COURSES. % rows for % harbours from the plotted courses; the step: %; moved against the table as it was: %; own rows, lanes and asks all in step; ${x.append ? 'Messina' : 'Galle'}''s own row is its roadstead''s sea; the probe mended and rolled back. % ms',
    v_h * v_h, v_h, v_res, v_moved, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
`
}
