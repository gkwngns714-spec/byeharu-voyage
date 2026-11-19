-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 160 - THE LAND KEEPS THE MARKET GUARD  (migration 0457; docs/design/land-2026-11.md 5.8 rule 2, 6.1; docs/dev-log/2026-11-19-land-l1b.md)
--   One party-hour of a land job is no more than a hundredth of its good's target stock at a middling harbour of every region it comes
--   from, at the fastest pace the game allows. Read through the server's own public.land_terms. Everything rolls back (proof.mjs).
--
-- @pass GUARD_EVERY    every gather job, every region it comes from: at Mining 100 with the best tool and the crowd's full chance, a party-hour is at most a hundredth of the middling harbour's least target (base x depth_m0)
-- @pass GUARD_BITES    the check can fail: with 0455's 40-s sand put back, the same check finds sand over the hundredth
-- @pass GUARD_PACKS    bigger packs cannot break it: with land_pack_base 30 a home trip's units an hour stay under the turn's bound
-- @pass GUARD_XP       experience a turn is the seconds times the pay a minute of the level a job asks (to the unit): an hour of Mining pays what the rule says
-- @pass GUARD_FIRST    a Lisbon company at Mining 1, no tool: Iron a 3,900-s trip, Sea Coal by Plymouth 3,700 s, Clay 101,850 s (over the 12-hour cap)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.guard_160(p_player uuid)
returns table (code text, region text, per_hour numeric, target numeric, share numeric)
language sql
as $f$
  with pace as (
    select a.code, a.good_id, 3600.0 / (public.land_terms(p_player, a.code) ->> 'a')::int * (1 + public.wc_num('land_crowd_max') / 100) as per_hour
      from public.land_actions a where a.kind = 'gather'),
  mid as (
    select g.id as good_id, rg.code as region, percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
      from public.goods g
      cross join unnest(g.origin_regions) o(rc)
      join public.regions rg on rg.code = o.rc
      join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
     where g.id in (select a.good_id from public.land_actions a)
     group by g.id, rg.code)
  select pace.code, mid.region, pace.per_hour, mid.target, pace.per_hour / (mid.target / 100.0)
    from pace join mid on mid.good_id = pace.good_id
$f$;

do $p$
declare
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_pl   uuid;
  v_new  uuid;
  v_r    record;
  v_n    int;
  v_t    jsonb;
  v_x    numeric;
begin
  update public.world_config set value = to_jsonb('0457-fixed-dice-of-proof-160-the-land-keeps-the-market-guard-0000000000'::text) where key = 'world_secret';
  v_pl := public.new_house('00000000-0457-4000-8000-0000000160c1', 'Casa Guarda 160', 'PRT', 'LIS', 'Guarda 160', 'carlat', 'Guarda 160', null, false);
  v_new := public.new_house('00000000-0457-4000-8000-0000000160c2', 'Casa Nova 160', 'PRT', 'LIS', 'Nova 160', 'carlat', 'Nova 160', null, false);
  if public.home_port_of(v_pl) <> v_lis or public.home_port_of(v_new) <> v_lis or public.land_on() then
    raise exception 'proof 160: the probe companies are not of Lisbon, or the land is lit as shipped';
  end if;
  insert into public.level_xp (player_id, skill, xp, seq) values (v_pl, 'mining', public.level_begins('mining', 100)::int, 0)
    on conflict (player_id, skill) do update set xp = excluded.xp;
  insert into public.land_parties (player_id, port_id, tools) values (v_pl, v_lis, (select array_agg(t.code) from public.land_tools t));

  -- ── EVERY JOB, EVERY REGION ──
  select count(*), count(distinct g.code) into v_n, v_x from pg_temp.guard_160(v_pl) g;
  select g.* into v_r from pg_temp.guard_160(v_pl) g order by g.share desc, g.code, g.region limit 1;
  if v_x <> (select count(*) from public.land_actions a where a.kind = 'gather') or v_r.share > 1
     or (public.land_terms(v_pl, 'iron') ->> 'have')::int <> 100
     or (public.land_terms(v_pl, 'iron') ->> 'tool')::numeric <> (select max(t.speed_pct) from public.land_tools t) then
    raise exception 'proof 160 GUARD_EVERY: % at % is % a party-hour against a hundredth of % (% x), or a job has no region', v_r.code, v_r.region, round(v_r.per_hour, 2), v_r.target, round(v_r.share, 3);
  end if;
  raise notice 'PASS: GUARD_EVERY - % job-regions over % jobs; the tightest % at %: % a party-hour, % of the hundredth of %', v_n, v_x, v_r.code, v_r.region, round(v_r.per_hour, 2), round(v_r.share, 3), v_r.target;

  -- ── THE CHECK BITES: 0455's sand ──
  v_x := (select a.seconds from public.land_actions a where a.code = 'sand');
  update public.land_actions set seconds = 40 where code = 'sand';
  select g.* into v_r from pg_temp.guard_160(v_pl) g where g.code = 'sand' order by g.share desc limit 1;
  if v_r.share <= 1 then
    raise exception 'proof 160 GUARD_BITES: 0455''s 40-s sand passed the guard (% x)', round(v_r.share, 2);
  end if;
  raise notice 'PASS: GUARD_BITES - 0455''s 40-s sand at the fastest pace: % a party-hour at %, % x the hundredth of %', round(v_r.per_hour, 1), v_r.region, round(v_r.share, 1), v_r.target;
  update public.land_actions a set seconds = v_x where a.code = 'sand';

  -- ── BIGGER PACKS ──
  update public.world_config set value = '30'::jsonb where key = 'land_pack_base';
  v_t := public.land_terms(v_pl, 'iron');
  if (v_t ->> 'p')::int <> 30 or 3600.0 * 30 / (v_t ->> 'trip')::int > 3600.0 / (v_t ->> 'a')::int then
    raise exception 'proof 160 GUARD_PACKS: 30 packs beat the turn''s bound: %', v_t;
  end if;
  raise notice 'PASS: GUARD_PACKS - iron, 30 packs: % s a trip, % an hour, under the turn''s %', v_t ->> 'trip',
    round(3600.0 * 30 / (v_t ->> 'trip')::int, 2), round(3600.0 / (v_t ->> 'a')::int, 2);
  update public.world_config set value = '6'::jsonb where key = 'land_pack_base';

  -- ── EXPERIENCE ──
  if exists (select 1 from public.land_actions a
              where abs(a.xp - a.seconds / 60.0 * (array[5, 6, 8, 10, 12, 16, 20, 24, 32, 40])[least(9, a.level / 10) + 1]) > 0.500001) then
    raise exception 'proof 160 GUARD_XP: a job''s experience is not its seconds times the pay a minute of its level: %',
      (select string_agg(a.code || ' ' || a.level || ' ' || a.seconds || ' ' || a.xp, ', ') from public.land_actions a
        where abs(a.xp - a.seconds / 60.0 * (array[5, 6, 8, 10, 12, 16, 20, 24, 32, 40])[least(9, a.level / 10) + 1]) > 0.500001);
  end if;
  raise notice 'PASS: GUARD_XP - every job: experience = seconds x the pay a minute, to the unit (clay % xp a turn of % s)',
    (select a.xp from public.land_actions a where a.code = 'clay'), (select a.seconds from public.land_actions a where a.code = 'clay');

  -- ── THE FIRST MINUTES, at Lisbon, Mining 1 ──
  if (public.land_terms(v_new, 'iron') ->> 'trip')::int <> 3900 or (public.land_terms(v_new, 'iron') ->> 'have')::int <> 1
     or (public.land_terms(v_new, 'coal') ->> 'trip')::int <> 3700 or public.land_terms(v_new, 'coal') ->> 'via' <> 'PLY'
     or (public.land_terms(v_new, 'clay') ->> 'trip')::int <> 101850 or (public.land_terms(v_new, 'clay') ->> 'over_cap')::boolean is not true then
    raise exception 'proof 160 GUARD_FIRST: the first trips are not the dev-log''s: iron % coal % clay %', public.land_terms(v_new, 'iron') ->> 'trip',
      public.land_terms(v_new, 'coal') ->> 'trip', public.land_terms(v_new, 'clay') ->> 'trip';
  end if;
  raise notice 'PASS: GUARD_FIRST - Lisbon, Mining 1: iron 3,900 s a trip, coal by Plymouth 3,700 s, clay 101,850 s (over the cap)';
end
$p$;
