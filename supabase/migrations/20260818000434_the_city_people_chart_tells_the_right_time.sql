-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0434 - THE CITY PEOPLE CHART TELLS THE RIGHT TIME  (world.stats_city_people dates each population step by the clock's own authority)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DEFECT (queue note "stats_city_people slot dating (frozen fn, needs a new migration)"):
--   The writer, public.population_tick, stamps each population_log row with the population slot it falls in. Since 0413 (a day lasts an
--   hour) that slot is public.clock_count('population_slot', now): counted on from the anchor public.clock_set wrote, at the NEW length
--   population_slot_seconds (3,000 s; it was the literal 600). The reader, world.stats_city_people (0305, frozen), still turns a slot into a
--   time as `to_timestamp(l.slot * 600)`, the pre-0413 rule. For every step after the seam that instant is wrong:
--     true   = anchor epoch + (slot - anchor count) x 3,000 s     (public.clock_start('population_slot', slot), the counter's one inverse)
--     served = slot x 600 s
--   so the Stats city chart's points are dated 1/5 of the real time past the seam: the newest step reads as many hours old (about 19 h a day
--   after the seam, growing 4 h for every 5 real hours), and the chart's span is squeezed to a fifth. Steps before the seam are unchanged
--   (clock_start gives slot x 600 there: the anchor's `start` + (slot - count) x `was` 600).
--   Only this reader carries the literal: the writer (0413 hunk), public.town_hall_people (counts slots, no instant) and everything else read
--   the slot through clock_count / clock_start.
--
-- WHAT THIS FILE DOES: ONE hunk in world.stats_city_people: `to_timestamp(l.slot * 600)` -> `public.clock_start('population_slot', l.slot)`.
--   clock_start is STABLE and definer-owned; the reader stays STABLE SECURITY DEFINER with its grants (authenticated only). Same JSON shape
--   (`at` is still the UTC instant, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'); the client is untouched. No table, knob, cron job or other function moves.
-- LOAD: none (a read; clock_start is one world_config key lookup a point, over at most population_log_slots = 144 rows).
-- LOCKS: CREATE OR REPLACE of one function. lock_timeout 5 s, statement_timeout 30 s.
-- ROLLBACK (forward, owner only): the hunk reversed (new -> old) in a new migration; the chart goes back to the wrong dates.
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; a probe, rolled
--   back by a raised sentinel: two planted steps for London (its own rows, two slots past London's newest), each point's `at` counts back to
--   its own slot through public.clock_count (the writer's counter), and two neighbouring post-seam steps stand one population_slot_seconds
--   apart. Both fail on the 0305 body in any world where the clock's rate has moved (CI and prod). Its behaviour over the world: proof 135.
-- VERSION: 0434 = prod head + 0429 .. 0433 (pirate-purses, cargo-150, stats-fleet-tabs, pirate-flee, short-server), each queued ahead; none
--   of them touches world.stats_city_people, clock_count, clock_start or population_slot_seconds.
-- news: none (a chart's dates corrected; nothing a player does changes)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  c_fn        constant text := 'world.stats_city_people(uuid)';
  v_pre       text;
  v_meta      text;
  v_fn_before text;
  v_def       text;
  v_old       text;
  v_new       text;
  v_n         int;
  v_port      uuid;
  v_slot      bigint;
  v_r         jsonb;
  v_k         int;
  v_a         timestamptz;
  v_b         timestamptz;
  v_note      text := 'not run';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.clock_start(text,bigint)') is null
     or to_regprocedure('public.clock_count(text,timestamp with time zone)') is null
     or not exists (select 1 from public.world_config where key = 'population_slot_seconds') then
    raise exception '0434 refuses: the people reader (0305) or the clock''s counter (0413) is not in this world';
  end if;
  if position('-- 0434:' in pg_get_functiondef(c_fn::regprocedure)) > 0 then
    raise exception '0434 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;

  -- ── 2. THE HUNK (LF; once in the live body, reversing to its pre-image) ──
  v_old := $h$                'series', coalesce((select jsonb_agg(jsonb_build_object('at', to_char(to_timestamp(l.slot * 600) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
$h$;
  v_new := $h$                -- 0434: a step's instant is the clock's own inverse of its slot (population_slot_seconds, counted on across 0413's seam), not slot x 600
                'series', coalesce((select jsonb_agg(jsonb_build_object('at', to_char(public.clock_start('population_slot', l.slot) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
$h$;
  v_n := (length(v_pre) - length(replace(v_pre, v_old, ''))) / length(v_old);
  if v_n <> 1 then
    raise exception '0434 self-assert FAIL: the hunk occurs % time(s) in %, not once: the deployed body is not what this file was written against', v_n, c_fn;
  end if;
  execute replace(v_pre, v_old, v_new);
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception '0434 self-assert FAIL: the hunk is not in the new body of % once', c_fn;
  end if;
  if replace(v_def, v_new, v_old) <> v_pre then
    raise exception '0434 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0434 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0434 self-assert FAIL: another function moved';
  end if;

  -- ── 3. THE PROBE, rolled back by a raised sentinel: two planted steps for London, two slots past its newest (its own rows only) ──
  select id into v_port from public.ports where code = 'LON';
  if v_port is not null and exists (select 1 from public.port_population where port_id = v_port) then
    select greatest(coalesce(max(l.slot), 0), public.clock_count('population_slot', now())) + 1 into v_slot
      from public.population_log l where l.port_id = v_port;
    begin
      insert into public.population_log (port_id, slot, population, kind, reason)
      values (v_port, v_slot, 434001, 'HOLD', null), (v_port, v_slot + 1, 434002, 'GROW', null);
      v_r := world.stats_city_people(v_port);
      v_k := jsonb_array_length(v_r -> 'series');
      if v_k < 2 or (v_r -> 'series' -> (v_k - 2) ->> 'population')::bigint <> 434001 or (v_r -> 'series' -> (v_k - 1) ->> 'population')::bigint <> 434002 then
        raise exception '0434 self-assert FAIL: the planted steps are not the newest two points: %', v_r -> 'series';
      end if;
      v_a := (v_r -> 'series' -> (v_k - 2) ->> 'at')::timestamptz;
      v_b := (v_r -> 'series' -> (v_k - 1) ->> 'at')::timestamptz;
      -- the writer's counter reads each point's instant back to its own slot (`at` is printed to the whole second, and an anchored start may
      -- carry a fraction: a second later is still inside the 3,000 s step it begins)
      if public.clock_count('population_slot', v_a + interval '1 second') <> v_slot or public.clock_count('population_slot', v_b + interval '1 second') <> v_slot + 1 then
        raise exception '0434 self-assert FAIL: the points are dated % and %, which the clock counts as slots % and %, not % and %',
          v_a, v_b, public.clock_count('population_slot', v_a), public.clock_count('population_slot', v_b), v_slot, v_slot + 1;
      end if;
      -- two neighbouring steps past the seam stand one step's length apart
      if abs(extract(epoch from v_b - v_a) - public.wc_num('population_slot_seconds')) > 1 then
        raise exception '0434 self-assert FAIL: two neighbouring steps stand % s apart, not population_slot_seconds %', extract(epoch from v_b - v_a), public.wc_num('population_slot_seconds');
      end if;
      v_note := 'London: two planted steps dated ' || to_char(v_a at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' and ' || to_char(v_b at time zone 'UTC', 'HH24:MI')
                || ' UTC, counted back to their slots, ' || public.wc_num('population_slot_seconds') || ' s apart';
      raise exception sqlstate 'BV434';
    exception when sqlstate 'BV434' then null;
    end;
    if v_note not like 'London:%' then
      raise exception '0434 self-assert FAIL: the probe did not run to its end';
    end if;
    if exists (select 1 from public.population_log l where l.port_id = v_port and l.slot in (v_slot, v_slot + 1)) then
      raise exception '0434 self-assert FAIL: the probe rows were not rolled back';
    end if;
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0434 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0434 self-assert ok: THE CITY PEOPLE CHART TELLS THE RIGHT TIME. One hunk in world.stats_city_people (slot x 600 -> public.clock_start), once and reversing; grants and volatility unmoved; no other function moved. Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
