-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0457 - THE LAND KEEPS THE MARKET GUARD  (the land, slice L1b: Mining's 57 jobs re-timed by the guard of design 5.8 rule 2. DARK.)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. 0455 timed each job by its good's price alone (a party-hour worth 4,800 coin at level 1 to 15,000 at 100, never under 40 s).
--   Design 5.8 rule 2 also says a party-hour is no more than ONE HUNDREDTH of the good's target stock at a middling harbour of its
--   region. L1 measured that it was not: at Lisbon one party-hour was sand 133x, quartz 76x, stone 19x, clay 14x the hundredth.
--   docs/dev-log/2026-11-19-land-l1b.md has the figures, before and after, and what this does to a new company's first ten minutes.
--
-- THE RULE (one authority: scripts/build-land-migration.mjs; its rows are this file's block, held to it by tests/land.data.spec.ts).
--   A job's seconds are the most of: the worth's time (0455's rule), the 40-s floor, and THE GUARD: at the FASTEST pace the game
--   allows (Mining 100 at land_level_speed_pct, the best tool of land_tools, land_crowd_max's chance of a second unit a turn,
--   land_yield_pct 100) one party-hour is no more than a hundredth of the least middling-harbour target over every region the good
--   comes from, a harbour's target taken at the least the market's depth rule can hold it at (its base, port_goods.base_target or
--   stock_target, x depth_m0 0.5: production has the depth lit and harbours at 0.5) (data/land-guard.generated.json, read from the
--   world by scripts/db/measure-land-guard.mjs). A march, a passage or
--   fewer packs only slow a party, so the turn is the bound and mules cannot break it. Experience is still the seconds times the pay
--   a minute of the level a job asks: an hour of Mining pays what it paid.
--
-- WHAT THIS FILE DOES: one UPDATE of public.land_actions' seconds and xp (57 rows, the catalogue). No function, table, knob or
--   switch is touched. land_enabled stays FALSE and land_yield_pct 100: lighting the land and the dial are the owner's.
--   A party already out keeps the terms frozen at its Send (prod: none; the land is dark).
-- budget: no table, no job, no cron, no trigger; 0 rows a minute (57 catalogue rows updated once).
-- LOCKS: row locks on the 57 rows of public.land_actions (no client reads it while dark), for well under a second.
-- news: none (the land is dark; the News is told when the owner lights it)
-- SELF-ASSERT: the rows are exactly the generator's and nothing else of them moved; no function or world_config row moved; the land is
--   dark. Then a probe company of Lisbon, rolled back: Mining 100, every tool of land_tools, and for EVERY job public.land_terms' own
--   turn at that pace, with land_crowd_max's second unit, against a hundredth of the middling harbour's least target (base x depth_m0)
--   of EVERY region the good comes from, on the live port_goods rows of the world it is applied to (production's own, at deploy).
--   One job over: FAIL.
-- ROLLBACK: forward only (re-emit the rows from the generator in a later file). Dark, nobody plays these rows.
-- VERSION: 0457 (production head 0456 on 2026-11-19).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_pre  constant text := '038762af620084222a9f7e40cacc95c5';   -- md5 of 0455's rows, code:seconds:xp by ord
  c_uid  constant uuid := '00000000-0457-4000-8000-000000000001';
  v_t0         timestamptz := clock_timestamp();
  v_fn_before  text;
  v_cfg_before text;
  v_n          int;
  v_lived      boolean := false;
  v_note       text := '';
  v_pl         uuid;
  v_lis        uuid;
  v_r          record;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.land_actions') is null or to_regprocedure('public.land_terms(uuid,text)') is null
     or to_regprocedure('public.level_begins(text,integer)') is null or to_regprocedure('public.land_on()') is null then
    raise exception '0457 refuses: the land of 0455 is not in this world';
  end if;
  if obj_description('public.land_actions'::regclass, 'pg_class') like '0457%' then
    raise exception '0457 refuses: it has been applied once';
  end if;
  if (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a) <> c_pre then
    raise exception '0457 refuses: public.land_actions is not as 0455 left it';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE ROWS ──
  create temp table rows_0457 (code text primary key, skill text, kind text, level int, seconds int, xp int, ground text, tool text, ord int) on commit drop;
  insert into rows_0457 (code, skill, kind, level, seconds, xp, ground, tool, ord)
  values
      -- BEGIN generated by scripts/build-land-migration.mjs (do not edit by hand)
      ('coal', 'mining', 'gather', 1, 295, 25, 'mines', 'pick', 1),
      ('iron', 'mining', 'gather', 1, 645, 54, 'mines', 'pick', 2),
      ('clay', 'mining', 'gather', 1, 16970, 1414, 'mines', 'pick', 3),
      ('stone', 'mining', 'gather', 5, 16970, 1414, 'mines', 'pick', 4),
      ('sand', 'mining', 'gather', 7, 16970, 1414, 'mines', 'pick', 5),
      ('copper', 'mining', 'gather', 10, 1700, 170, 'mines', 'pick', 6),
      ('salt', 'mining', 'gather', 13, 1040, 104, 'mines', 'pick', 7),
      ('tin', 'mining', 'gather', 15, 490, 49, 'mines', 'pick', 8),
      ('lead', 'mining', 'gather', 18, 335, 34, 'mines', 'pick', 9),
      ('lime', 'mining', 'gather', 20, 16970, 2263, 'mines', 'pick', 10),
      ('gypsum', 'mining', 'gather', 23, 16970, 2263, 'mines', 'pick', 11),
      ('sulphur', 'mining', 'gather', 25, 500, 67, 'mines', 'pick', 12),
      ('alum', 'mining', 'gather', 28, 450, 60, 'mines', 'pick', 13),
      ('saltpetre', 'mining', 'gather', 30, 445, 74, 'mines', 'pick', 14),
      ('zinc-spelter', 'mining', 'gather', 33, 465, 78, 'mines', 'pick', 15),
      ('ochre', 'mining', 'gather', 36, 445, 74, 'mines', 'pick', 16),
      ('feldspar', 'mining', 'gather', 36, 14975, 2496, 'mines', 'pick', 17),
      ('quartz', 'mining', 'gather', 36, 12270, 2045, 'mines', 'pick', 18),
      ('silver', 'mining', 'gather', 40, 11315, 2263, 'mines', 'pick', 19),
      ('marble', 'mining', 'gather', 43, 450, 90, 'mines', 'pick', 20),
      ('antimony', 'mining', 'gather', 45, 295, 59, 'mines', 'pick', 21),
      ('cobalt', 'mining', 'gather', 48, 345, 69, 'mines', 'pick', 22),
      ('quicksilver', 'mining', 'gather', 50, 1325, 353, 'mines', 'pick', 23),
      ('cinnabar', 'mining', 'gather', 50, 255, 68, 'mines', 'pick', 24),
      ('alum-shale', 'mining', 'gather', 53, 380, 101, 'mines', 'pick', 25),
      ('swedish-iron', 'mining', 'gather', 55, 520, 139, 'mines', 'pick', 26),
      ('osmund-iron', 'mining', 'gather', 55, 505, 135, 'mines', 'pick', 27),
      ('bar-iron', 'mining', 'gather', 55, 290, 77, 'mines', 'pick', 28),
      ('japan-copper', 'mining', 'gather', 58, 305, 81, 'mines', 'pick', 29),
      ('chilean-copper', 'mining', 'gather', 58, 635, 169, 'mines', 'pick', 30),
      ('tin-ingots', 'mining', 'gather', 58, 300, 80, 'mines', 'pick', 31),
      ('gold', 'mining', 'gather', 60, 6930, 2310, 'mines', 'pick', 32),
      ('gold-dust', 'mining', 'gather', 60, 3690, 1230, 'mines', 'pick', 33),
      ('amber', 'mining', 'gather', 65, 300, 100, 'mines', 'pick', 34),
      ('baltic-amber', 'mining', 'gather', 65, 720, 240, 'mines', 'pick', 35),
      ('lodestone', 'mining', 'gather', 68, 305, 102, 'mines', 'pick', 36),
      ('potosi-silver', 'mining', 'gather', 70, 3690, 1476, 'mines', 'pick', 37),
      ('zacatecas-silver', 'mining', 'gather', 70, 3300, 1320, 'mines', 'pick', 38),
      ('turquoise', 'mining', 'gather', 74, 350, 140, 'mines', 'pick', 39),
      ('carnelian', 'mining', 'gather', 74, 380, 152, 'mines', 'pick', 40),
      ('malachite', 'mining', 'gather', 74, 2535, 1014, 'mines', 'pick', 41),
      ('onyx', 'mining', 'gather', 74, 2930, 1172, 'mines', 'pick', 42),
      ('lapis-lazuli', 'mining', 'gather', 78, 2295, 918, 'mines', 'pick', 43),
      ('opals', 'mining', 'gather', 78, 4495, 1798, 'mines', 'pick', 44),
      ('peridot', 'mining', 'gather', 78, 2320, 928, 'mines', 'pick', 45),
      ('jade', 'mining', 'gather', 80, 2025, 1080, 'mines', 'pick', 46),
      ('nephrite', 'mining', 'gather', 80, 2980, 1589, 'mines', 'pick', 47),
      ('pounamu', 'mining', 'gather', 80, 765, 408, 'mines', 'pick', 48),
      ('emeralds', 'mining', 'gather', 84, 2535, 1352, 'mines', 'pick', 49),
      ('emerald-muzo', 'mining', 'gather', 84, 2535, 1352, 'mines', 'pick', 50),
      ('rubies', 'mining', 'gather', 87, 3090, 1648, 'mines', 'pick', 51),
      ('burma-rubies', 'mining', 'gather', 87, 2065, 1101, 'mines', 'pick', 52),
      ('ceylon-sapphires', 'mining', 'gather', 90, 2490, 1660, 'mines', 'pick', 53),
      ('diamonds', 'mining', 'gather', 93, 3380, 2253, 'mines', 'pick', 54),
      ('golconda-diamonds', 'mining', 'gather', 93, 2955, 1970, 'mines', 'pick', 55),
      ('platinum', 'mining', 'gather', 96, 3690, 2460, 'mines', 'pick', 56),
      ('andacollo-gold', 'mining', 'gather', 96, 4220, 2813, 'mines', 'pick', 57)
      -- END generated by scripts/build-land-migration.mjs
  ;
  update public.land_actions a set seconds = x.seconds, xp = x.xp from rows_0457 x where a.code = x.code;
  comment on table public.land_actions is
    '0457: THE LAND''S JOBS (docs/design/land-2026-11.md 4.1, 5.8). One row a job: the skill whose Level it asks and raises, its kind, the level it asks, the seconds one turn takes before level and tool, the experience a turn, the ground it is done on, the good it gives (one job a good, so the code is the good''s), the tool kind that speeds it. Seconds: the most of the worth''s time, 40 s, and the market guard (at the fastest pace, a party-hour is no more than a hundredth of the least middling-harbour target, base x depth_m0, of the regions the good comes from). Generated by scripts/build-land-migration.mjs (tests/land.data.spec.ts). Where a gather job is done is the good''s origin_regions. No FK to goods (asserted instead).';

  -- ── 3. SELF-ASSERT: the catalogue ──
  if (select count(*) from public.land_actions a join rows_0457 x on x.code = a.code
       where (a.skill, a.kind, a.level, a.seconds, a.xp, a.ground, a.tool, a.ord) = (x.skill, x.kind, x.level, x.seconds, x.xp, x.ground, x.tool, x.ord)) <> 57
     or (select count(*) from public.land_actions) <> 57 or (select count(*) from rows_0457) <> 57 then
    raise exception '0457 self-assert FAIL: the jobs are not exactly the generator''s 57 rows';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0457 self-assert FAIL: a function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before or public.land_on() then
    raise exception '0457 self-assert FAIL: a world_config row moved, or the land is not dark';
  end if;

  -- ── 4. THE PROBE: the guard, for every job and every region, at the fastest pace, rolled back ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa Mineira 0457', (select n.id from public.nations n where n.code = 'PRT'), 2000, false) returning id into v_pl;
    insert into public.events (player_id, kind, payload) values (v_pl, 'FOUNDED', jsonb_build_object('port', 'LIS'));
    insert into public.level_xp (player_id, skill, xp, seq) values (v_pl, 'mining', public.level_begins('mining', 100)::int, 0);
    insert into public.land_parties (player_id, port_id, tools) values (v_pl, v_lis, (select coalesce(array_agg(t.code), '{}') from public.land_tools t));

    -- every job: the server's own turn at Mining 100 with the best tool; units an hour with the crowd's full second-unit chance;
    -- against a hundredth of the middling harbour's least target (base x depth_m0; the lower median: a real harbour's figure) of every region
    create temp table guard_0457 on commit drop as
    with j as (
      select a.code, a.good_id, public.land_terms(v_pl, a.code) as t from public.land_actions a where a.kind = 'gather'),
    pace as (
      select j.code, j.good_id, (j.t ->> 'a')::int as a, (j.t ->> 'have')::int as have, (j.t ->> 'tool')::numeric as tool,
             3600.0 / (j.t ->> 'a')::int * (1 + public.wc_num('land_crowd_max') / 100) as per_hour
        from j),
    mid as (
      select g.id as good_id, rg.code as region,
             percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
        from public.goods g
        cross join unnest(g.origin_regions) o(rc)
        join public.regions rg on rg.code = o.rc
        join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
        join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
       where g.id in (select a.good_id from public.land_actions a)
       group by g.id, rg.code)
    select pace.code, pace.a, pace.have, pace.tool, pace.per_hour, mid.region, mid.target, pace.per_hour / (mid.target / 100.0) as share
      from pace join mid on mid.good_id = pace.good_id;

    if (select count(distinct g.code) from guard_0457 g) <> 57
       or exists (select 1 from guard_0457 g where g.have <> 100 or g.tool <> (select max(t.speed_pct) from public.land_tools t) or g.a is null) then
      raise exception '0457 self-assert FAIL: a job has no region with a harbour market, or the probe is not at Mining 100 with the best tool';
    end if;
    select g.code, g.region, g.share, g.per_hour, g.target into v_r from guard_0457 g order by g.share desc, g.code, g.region limit 1;
    if v_r.share > 1 then
      raise exception '0457 self-assert FAIL: THE GUARD: % at % is % units a party-hour at the fastest pace, over a hundredth of its middling target % (%x)',
        v_r.code, v_r.region, round(v_r.per_hour, 2), v_r.target, round(v_r.share, 3);
    end if;
    select count(*) into v_n from guard_0457;
    -- the first job a company of Lisbon sees: Iron at Mining 1, no tool, a 6-pack trip on its home land
    delete from public.level_xp x where x.player_id = v_pl;
    update public.land_parties set tools = '{}' where player_id = v_pl;
    v_note := format('%s job-regions, the tightest %s at %s: %s a party-hour against a hundredth of %s (%s of it); a Lisbon company''s first Iron trip %s s',
                     v_n, v_r.code, v_r.region, round(v_r.per_hour, 2), v_r.target, round(v_r.share, 3),
                     public.land_terms(v_pl, 'iron') ->> 'trip');
    raise exception using errcode = 'ZX457', message = 'PROBE_ROLLBACK_0457';
  exception when sqlstate 'ZX457' then
    v_lived := true;
  end;
  if not v_lived or v_note not like '%job-regions%' then
    raise exception '0457 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid or p.company_name = 'Casa Mineira 0457') or public.land_on() then
    raise exception '0457 self-assert FAIL: the probe left something behind, or the land is lit';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0457 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0457 self-assert ok: THE LAND KEEPS THE MARKET GUARD, DARK. 57 jobs re-timed by the generator''s rule; no function or knob moved; land_enabled false. Probe (rolled back, Mining 100, every tool, the crowd''s full chance): %. In all % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
