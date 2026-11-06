-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0327 — THE LEVELS PAGE READS ONE THING: world.levels(), a read. NO SWITCH, NO KNOB, NO ROW. Nothing a player does changes.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-06: "first create a tab on command - levels. This page will show you all the info." The page needs figures no reader serves yet:
--   * where a company track's next level begins (world.player serves points and level, not where the next starts), and what the next title opens (the region door is gone, 0218: sea zones ask the title);
--   * a hull's EARNED level (world.ship_view serves the level IN FORCE, which is 1 while levels_bite is false, with the xp beside it);
--   * the title and the next title's name; the room earned (fleets, ships to a fleet); Seamanship; and, while regard_enabled, the regard with each great power.
--
-- WHAT THIS FILE ADDS (all read-only, STABLE, no table, no write):
--   public.level_line(points)  THE one cut of a level from points: {points, level, from, next_at}. The same arithmetic as 0127's `next_level_at`, so a company track and a hull read one way.
--   world.levels()             The page's one read. Composes public.player_progress, public.title_level, public.earned_caps, public.skill_level, public.regard_of, public.level_in_force. It computes none of them.
-- THE HUNK (once, reversing): public.client_rpc_entry_points gains the one row.
--
-- DARK IS NOT TOUCHED: levels_bite, regard_enabled, fleet_room_bite are read, never set. The read says which of them is lit, so the page can tell the truth.
-- COST: one read per page open (player_progress scans the ledger once, as world.player already does on every poll), one primary-key read per hull and per great power (ten).
-- ROLLBACK (forward, owner only): a new migration dropping world.levels(uuid-less) and public.level_line(numeric) and reversing the hunk. Nothing else depends on them.
-- SELF-ASSERT: the catalog only, rolled forward in one DO block (statement_timeout 45 s). The live read is proved in CI: scripts/db/proofs/32_levels_page.sql.
-- VERSION: 0327. 0324 (W7), 0325 (W11) and 0326 (HQ) are reserved; this file hunks only the registry, on the world.player row.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_pre         text;
  v_n           int;
  v_moved       text;
  v_cfg_before  text;
  c_old constant text := $h$      ('world',       'player',              ''),
$h$;
  c_new constant text := $h$      ('world',       'player',              ''),
      -- 0327: the Levels page of the Command desk reads one thing.
      ('world',       'levels',                ''),
$h$;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.levels()') is not null or to_regprocedure('public.level_line(numeric)') is not null then
    raise exception '0327 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.player_progress(uuid)') is null or to_regprocedure('public.earned_caps(uuid)') is null
     or to_regprocedure('public.regard_of(uuid,uuid)') is null or to_regprocedure('public.level_in_force(numeric)') is null
     or to_regprocedure('public.fleet_room_on()') is null or to_regprocedure('public.title_level(uuid)') is null then
    raise exception '0327 refuses: a reader it composes is not in this world (0069 / 0107 / 0127 / 0215 / 0319 / 0321)';
  end if;

  create temp table fn_before_0327 on commit drop as
    select p.oid::regprocedure::text as fn, md5(replace(pg_get_functiondef(p.oid), chr(13), '')) as h
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and p.proname <> 'client_rpc_entry_points';
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;

  -- ── 1. THE ONE CUT OF A LEVEL ──
  execute $f$
create function public.level_line(p_points numeric)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0327: THE one cut of points into a level line: the level on the one curve (public.level_from_points), where it began, and where the next begins (null at the cap).
  -- The same expression 0127's world.ship_view uses for `next_level_at`.
  select jsonb_build_object(
    'points', floor(greatest(coalesce(p_points, 0), 0)),
    'level', l.lvl,
    'from', public.level_points(l.lvl),
    'next_at', case when public.level_from_points(public.level_points(l.lvl + 1)) > l.lvl then public.level_points(l.lvl + 1) end)
    from (select public.level_from_points(coalesce(p_points, 0)) as lvl) l
$$
  $f$;

  -- ── 2. THE PAGE'S READ ──
  execute $f$
create function world.levels()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0327: THE LEVELS PAGE — everything about a company's levels, in one read. Nothing is computed here that another reader owns:
--   tracks   public.player_progress (0069) cut by public.level_line
--   skills   Seamanship, public.skill_level (0107), out of skill_max_level
--   title    public.title_level (0215), the next title's name (public.title_names) and the sea zones it opens (public.sea_zones.title_min; they ask it only while sea_conditions_bite)
--   room     public.earned_caps (0107, 0321): fleets and ships to a fleet as they stand NOW, fleets used, and whether the room is counted by level (fleet_room_bite)
--   ships    every hull: her EARNED level (level_line of ship_xp) beside the level IN FORCE (public.level_in_force: 1 while levels_bite is false)
--   regard   only while regard_enabled: public.regard_of and public.regard_band for each great power
-- `bite` is levels_bite: false means a hull's or a captain's level changes no stat, slot or bonus yet. A merchant or a signed-out caller: {company: false}.
declare
  v_id    uuid := public.current_player_id();
  v_pp    jsonb;
  v_title int;
  v_max   int := public.wc_int('title_max');
begin
  if v_id is null then
    return jsonb_build_object('company', false);
  end if;
  v_pp := public.player_progress(v_id);
  v_title := coalesce(public.title_level(v_id), 1);
  return jsonb_build_object(
    'company', true,
    'bite', public.levels_bite_on(),
    'tracks', jsonb_build_object(
      'trading', public.level_line((v_pp -> 'trading' ->> 'points')::numeric)
                 || jsonb_build_object('turnover', v_pp -> 'trading' -> 'turnover'),
      'exploration', public.level_line((v_pp -> 'exploration' ->> 'points')::numeric)
                 || jsonb_build_object('ports_reached', v_pp -> 'exploration' -> 'ports_reached', 'nm_sailed', v_pp -> 'exploration' -> 'nm_sailed'),
      'combat', public.level_line((v_pp -> 'combat' ->> 'points')::numeric)
                 || jsonb_build_object('playable', (v_pp -> 'combat' ->> 'playable')::boolean)),
    'skills', jsonb_build_object('seamanship', jsonb_build_object('level', public.skill_level(v_id, 'SEAMANSHIP'), 'max', public.wc_int('skill_max_level'))),
    'title', jsonb_build_object(
      'level', v_title,
      'name', (select t.name from public.title_names t where t.level = v_title),
      'max', v_max,
      'next', (select jsonb_build_object('level', t.level, 'name', t.name,
                 'opens', (select coalesce(jsonb_agg(z.name order by z.ord), '[]'::jsonb) from public.sea_zones z where z.title_min = t.level))
                 from public.title_names t where t.level = v_title + 1 and t.level <= v_max),
      'seas_bite', public.wc('sea_conditions_bite') = 'true'::jsonb),
    'room', public.earned_caps(v_id)
            || jsonb_build_object('fleets', (select count(*)::int from public.fleets f where f.player_id = v_id), 'counted', public.fleet_room_on()),
    'ships', (select coalesce(jsonb_agg(public.level_line(x.xp) || jsonb_build_object(
                  'id', s.id, 'name', s.name, 'class', c.name, 'fleet', f.name, 'flagship', s.is_flagship,
                  'in_force', public.level_in_force(x.xp))
                order by public.level_from_points(x.xp) desc, s.name), '[]'::jsonb)
                from public.ships s
                join public.fleets f on f.id = s.fleet_id
                join public.ship_classes c on c.id = s.class_id
                left join public.ship_xp sx on sx.ship_id = s.id
               cross join lateral (select coalesce(sx.xp, 0) as xp) x
               where s.player_id = v_id),
    'regard', case when public.regard_on()
                   then (select coalesce(jsonb_agg(jsonb_build_object(
                                'code', n.code, 'name', n.name, 'flag', n.flag_char,
                                'score', round(y.score), 'band', public.regard_band(y.score) ->> 'band') order by y.score desc, n.name), '[]'::jsonb)
                           from public.great_powers g
                           join public.nations n on n.id = g.nation_id
                          cross join lateral (select public.regard_of(v_id, n.id) as score) y) end);
end $$
  $f$;

  revoke all on function public.level_line(numeric) from public, anon, authenticated;
  revoke all on function world.levels() from public, anon;
  grant execute on function world.levels() to authenticated;

  -- ── 3. THE HUNK: the registry row (once, and reversing) ──
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_pre := v_def;
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0327 self-assert FAIL: the registry hunk occurs % time(s), not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_def, c_old, c_new);
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0327 self-assert FAIL: the registry hunk is not in the new body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0327 self-assert FAIL: public.client_rpc_entry_points does not reverse to its pre-image';
  end if;

  -- ── 4. SELF-ASSERT: the catalog only ──
  select x.fn into v_moved
    from (select p.oid::regprocedure::text as fn, md5(replace(pg_get_functiondef(p.oid), chr(13), '')) as h
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
             and p.proname <> 'client_rpc_entry_points'
             and p.proname not in ('level_line', 'levels')) x
    full join fn_before_0327 b on b.fn = x.fn
   where x.h is distinct from b.h limit 1;
  if v_moved is not null then
    raise exception '0327 self-assert FAIL: another function moved: %', v_moved;
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0327 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if exists (select 1 from pg_proc p where p.oid = any (array['public.level_line(numeric)'::regprocedure, 'world.levels()'::regprocedure]) and p.provolatile <> 's') then
    raise exception '0327 self-assert FAIL: a new function is not STABLE';
  end if;
  if has_function_privilege('anon', 'world.levels()', 'execute') or not has_function_privilege('authenticated', 'world.levels()', 'execute')
     or has_function_privilege('authenticated', 'public.level_line(numeric)', 'execute') or has_function_privilege('anon', 'public.level_line(numeric)', 'execute') then
    raise exception '0327 self-assert FAIL: the grants are not the contract: the read to authenticated only, the helper to nobody';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'levels' and e.fn is not null) then
    raise exception '0327 self-assert FAIL: the read is not in the client registry';
  end if;
  if (public.level_line(0) ->> 'level')::int <> 1 or (public.level_line(0) ->> 'next_at')::numeric <> public.level_points(2) then
    raise exception '0327 self-assert FAIL: level_line(0) is not level 1: %', public.level_line(0);
  end if;
  if (public.level_line(public.level_points(7)) ->> 'level')::int <> 7 or (public.level_line(public.level_points(7)) ->> 'from')::numeric <> public.level_points(7)
     or (public.level_line(public.level_points(7)) ->> 'next_at')::numeric <> public.level_points(8) then
    raise exception '0327 self-assert FAIL: level_line does not cut level 7 at its own points: %', public.level_line(public.level_points(7));
  end if;
  if (public.level_line(public.level_points(1000)) ->> 'next_at') is not null then
    raise exception '0327 self-assert FAIL: level_line names a next level above the cap: %', public.level_line(public.level_points(1000));
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0327 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0327 self-assert ok: THE LEVELS PAGE READS ONE THING. One hunk, once and reversing; no other function, no knob, no row; the read is stable and granted to authenticated only. (proof 32 runs it in CI.) % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
