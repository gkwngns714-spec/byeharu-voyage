-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0305 — STATS · CITY · PEOPLE: a city's page shows its population, its trend, its tax, its rank and its day of steps
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-04: "add population info on stats - city."
--
-- ONE NEW READER, nothing else moves:
--   world.stats_city_people(p_port uuid) -> jsonb, STABLE, SECURITY DEFINER, read-only, no volatile call.
--     Everything public.town_hall_people serves (population, baseline, year, per_day, kind, reason, day_change — it is CALLED, not copied,
--     so the hall and the Stats page cannot disagree) plus
--       rank    1 = the most people among all harbours (ties share the best rank),
--       of      the number of harbours with a population row,
--       series  the kept day of steps from public.population_log, oldest first: [{at, population}] (at = the step's UTC instant, slot x 600 s).
--     {} for a harbour with no population row (the client draws nothing).
--   Grants like its sibling stats readers (0214): revoke from public/anon/authenticated, then execute to authenticated.
--   No table, column, knob, cron job or other function is touched (asserted).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: one function, one ACL,
--   catalog reads, a few probe calls (a primary-key lookup, a 246-row rank count, a log read each). Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): drop function world.stats_city_people(uuid); the client then shows no people block.
-- VERSION: 0305 - prod head 0304 (2026-11-04).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn_before  text;
  v_fn_after   text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
  v_port uuid;
  v_r    jsonb;
  v_want jsonb;
  v_n    int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.town_hall_people(uuid)') is null or to_regclass('public.port_population') is null or to_regclass('public.population_log') is null then
    raise exception '0305 refuses: 0304 (the city''s people) is not in this world';
  end if;
  if to_regprocedure('world.stats_city_people(uuid)') is not null then
    raise exception '0305 refuses: it has been applied once';
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;

  -- ── 1. THE READER ──
  execute $f$
create function world.stats_city_people(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0305: the Stats city page's people block. The hall's own block (public.town_hall_people) + rank among all harbours + the kept day of steps.
  select coalesce((
    select (public.town_hall_people(pp.port_id) -> 'people')
           || jsonb_build_object(
                'rank', 1 + (select count(*) from public.port_population o where o.population > pp.population),
                'of', (select count(*) from public.port_population),
                'series', coalesce((select jsonb_agg(jsonb_build_object('at', to_char(to_timestamp(l.slot * 600) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                                                                       'population', round(l.population)::bigint) order by l.slot)
                                      from public.population_log l where l.port_id = pp.port_id), '[]'::jsonb))
      from public.port_population pp where pp.port_id = p_port), '{}'::jsonb)
$body$
  $f$;
  revoke all on function world.stats_city_people(uuid) from public, anon, authenticated;
  grant execute on function world.stats_city_people(uuid) to authenticated;

  -- ── 2. SELF-ASSERT ──
  if not exists (select 1 from pg_proc p where p.oid = 'world.stats_city_people(uuid)'::regprocedure and p.provolatile = 's' and p.prosecdef) then
    raise exception '0305 FAIL: the reader is not STABLE SECURITY DEFINER';
  end if;
  if not has_function_privilege('authenticated', 'world.stats_city_people(uuid)', 'execute')
     or has_function_privilege('anon', 'world.stats_city_people(uuid)', 'execute') then
    raise exception '0305 FAIL: the reader is not granted to authenticated alone';
  end if;
  select id into v_port from public.ports where code = 'LON';
  v_r := world.stats_city_people(v_port);
  v_want := public.town_hall_people(v_port) -> 'people';
  select count(*) into v_n from public.port_population;
  if v_r is null or (v_r - 'rank' - 'of' - 'series') <> v_want
     or (v_r ->> 'rank')::int < 1 or (v_r ->> 'rank')::int > v_n or (v_r ->> 'of')::int <> v_n
     or jsonb_typeof(v_r -> 'series') <> 'array' then
    raise exception '0305 FAIL: the reader served % for London (hall block %)', v_r, v_want;
  end if;
  -- the rank is the count above + 1: the most populous harbour is rank 1
  if not exists (select 1 from public.port_population pp where pp.population = (select max(population) from public.port_population)
                    and (world.stats_city_people(pp.port_id) ->> 'rank') = '1') then
    raise exception '0305 FAIL: the most populous harbour is not rank 1';
  end if;
  if world.stats_city_people('00000000-0000-0000-0000-000000000000') <> '{}'::jsonb then
    raise exception '0305 FAIL: an unknown harbour did not serve {}';
  end if;
  -- nothing else moved
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_after
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'world.stats_city_people(uuid)'::regprocedure;
  if v_fn_after <> v_fn_before then
    raise exception '0305 FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0305 FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0305 FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0305 self-assert ok: world.stats_city_people is STABLE, definer-owned, executable by authenticated alone; serves the hall block, a rank and the kept steps (London rank % of %, % logged steps); an unknown harbour serves {}; nothing else moved. Printed, never asserted: % ms.', v_r ->> 'rank', v_r ->> 'of', jsonb_array_length(v_r -> 'series'), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
