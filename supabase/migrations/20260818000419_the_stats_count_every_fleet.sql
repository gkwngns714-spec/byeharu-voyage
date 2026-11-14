-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0419 - THE STATS COUNT EVERY FLEET  (merchants, the navy, the pirates and the cargo ships on one Stats face, from one small row a count)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15, verbatim: "in stats, show like merchants navy, pirates, anad cargo" (on the Stats screen: the merchants, the navy, the
--   pirates and the cargo ships). docs/dev-log/2026-11-15-stats-fleets.md has the reasoning and the measurements.
--
-- WHAT THIS FILE DOES:
--   1. public.stats_fleets (NEW, one row a count, kept 26 hours): what the Stats count saw of the four kinds of ship, as one jsonb `figures`:
--        merchants {ships}                       (the rest of the merchants is the count's own public.stats_merchants row, already there)
--        navy      {fleets, ships, sea, port, laid_up, wrecked, nations: [[code, fleets, ships]]}
--        pirates   {fleets, ships, sea, port, laid_up, wrecked, wrecked_rows, roster, homes: [[code, name, fleets, ships]]}
--        cargo     {fleets, ships, sea, port, laid_up, wrecked, tuns, tuns_at_sea, funds}
--        win       {since, navy_fights, pirates_sunk, pirate_wrecks, pirate_reborn, plunder, raids_paid}: what happened in the count's window
--      Each fleet is in ONE state: laid up, else wrecked (no hull above 0; a pirate also while her wreck lies at home), else at sea (SAILING), else in port.
--   2. public.stats_fleets_count(since, now) (NEW, STABLE, server only): the row's figures. It reads the three small ship tables (prod 2026-11-15:
--      43 navy, ~10 pirate, 372 cargo rows; the pirate roster grows to 108 fleets), their fleets and ships by key, the merchants' ships through
--      npc_fleets (~943), and the window's LOOT / RANSOM rows of treasury_flows into the pirates' cities (public.port_nation; the created_at index; a few rows). The
--      window's fights: a navy ship fights at most once an hour (public.navy_hunt_pass), so her `fought_at` inside a 30-minute window is one fight,
--      and its `fought.result` SUNK is a pirate sunk. A pirate wreck is her `wrecked_at` inside the window; reborn = wrecks lying at the last count +
--      wrecks since - wrecks lying now (pirate_respawn_minutes is 60: no wreck is born and reborn between two counts). Plunder is what the pirate
--      cities took as RANSOM and LOOT (public.pirate_ransom, public.raid_ransom, public.pirate_loot_book: one flow each).
--      NOT COUNTED (said plainly): every raid. A raid is settled inside voyage.settle and written only to voyage_events (304,000 rows, 35 MB, no
--      time index); counting it would read that table each count. `raids_paid` counts the raids that paid the pirates (a ransom or a cargo
--      ship's gold); a raid driven off, or one that took only goods, is not in it.
--   3. public.tick_stats: three hunks. After the merchants it writes the row (`fleets` in its phases and its return) and lets rows older than
--      26 hours go.
--   4. world.stats_fleets() (NEW, STABLE, a client READ, granted to authenticated, one registry row): the newest row, the newest stats_merchants row
--      (its fleets in the same four states, its 24 h earnings and laps), and the windows of the last 24 hours summed. Three index probes and at most
--      ~52 rows: it scans nothing live, so the face may ask it every second as every Stats face does.
--
-- LOAD: nothing in any beat or minute job. The Stats count (twice an hour) gains one phase: 28 to 35 ms on the local world at production's size
--   (370 cargo, 40 navy and 7 pirate fleets, 916 merchant ships, every cargo ship with a hold; scripts/ops/harness/stats-fleets/cost.sql), beside a
--   whole count of 23 to 36 s on prod; ~1,400 small rows read by key. It writes 1 row and deletes about 1. No cron change. The read: 0.05 ms.
-- LOCKS: CREATE TABLE, CREATE FUNCTION x2, CREATE OR REPLACE x2 by hunks. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then a probe in a
--   rolled-back sub-transaction: the count's figures read once (timed, under 3 s) and two planted rows read back through world.stats_fleets.
--   Nothing counts or sums a growing table.
-- ROLLBACK (forward, owner only): scripts/ops/harness/stats-fleets/rollback-0419.sql, a draft (the hunks reversed, the read and the table dropped).
-- VERSION: 0419 = 0418 + 1 (production head 0418 on 2026-11-15).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.tick_stats(timestamp with time zone)', 'public.client_rpc_entry_points()'];
  v_t0        timestamptz := clock_timestamp();
  v_tp        timestamptz;
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_r         jsonb;
  v_ms        numeric;
  v_note      text := 'not run';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.stats_fleets') is not null or to_regprocedure('world.stats_fleets()') is not null then
    raise exception '0419 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_stats(timestamp with time zone)') is null or to_regclass('public.stats_merchants') is null
     or to_regclass('public.navy_ships') is null or to_regclass('public.pirate_ships') is null or to_regclass('public.cargo_ships') is null
     or to_regprocedure('public.pirate_nation()') is null or to_regprocedure('public.funds_aboard()') is null
     or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0419 refuses: the Stats count, the ships or the news are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0419 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0419
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE TABLE ──
  -- retention: rows older than 26 hours are deleted by public.tick_stats at each count (one row a count: about 52 rows at two counts an hour)
  create table public.stats_fleets (
    slot    bigint primary key,
    at      timestamptz not null,
    figures jsonb not null
  );
  comment on table public.stats_fleets is
    '0419: one row a Stats count (public.tick_stats, its `fleets` phase): the merchants'' ships, the navy, the pirates and the cargo ships as the count saw them, and what happened in its window (`figures.win`). Written by public.tick_stats alone, read by world.stats_fleets alone. Kept 26 hours (tick_stats deletes older rows).';
  alter table public.stats_fleets enable row level security;
  revoke all on table public.stats_fleets from public, anon, authenticated;

  -- ── 3. THE COUNT'S FIGURES ──
  execute $f$
create function public.stats_fleets_count(p_since timestamptz, p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0419: what the Stats count sees of the four kinds of ship (public.stats_fleets, its header). Each fleet in ONE state: laid up, else wrecked,
  -- else at sea, else in port. The window (p_since, p_now]: navy fights and pirates sunk (a navy ship fights at most once an hour), pirate wrecks
  -- and rebirths, and the ransom and loot the pirate cities took. Reads the three small ship tables, their fleets and ships by key, and the window's
  -- flows by created_at. Writes nothing.
  with
  nv as (select n.nation_id, n.fought_at, n.fought, f.status, s.ships,
                case when n.laid_up_at is not null then 'laid_up' when not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
           from public.navy_ships n
           join public.fleets f on f.id = n.fleet_id
           cross join lateral (select count(*)::int as ships, coalesce(bool_or(x.durability > 0), false) as alive from public.ships x where x.fleet_id = n.fleet_id) s),
  pr as (select n.home_port, n.wrecked_at, s.ships,
                case when n.laid_up_at is not null then 'laid_up' when n.wrecked_at is not null or not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
           from public.pirate_ships n
           join public.fleets f on f.id = n.fleet_id
           cross join lateral (select count(*)::int as ships, coalesce(bool_or(x.durability > 0), false) as alive from public.ships x where x.fleet_id = n.fleet_id) s),
  cg as (select s.ships, s.tuns,
                case when c.laid_up_at is not null then 'laid_up' when not s.alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end as state
           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id
           cross join lateral (select count(*)::int as ships, coalesce(bool_or(x.durability > 0), false) as alive,
                                      coalesce(sum((select sum((e.value)::text::numeric * g.bulk) from jsonb_each(x.cargo) e join public.goods g on g.code = e.key)), 0) as tuns   -- public.ship_cargo_tuns' own sum
                                 from public.ships x where x.fleet_id = c.fleet_id) s),
  prev as (select (x.figures -> 'pirates' ->> 'wrecked_rows')::int as wrecked_rows from public.stats_fleets x where x.at < p_now order by x.slot desc limit 1),
  loot as (select count(*)::int as n, coalesce(sum(t.ducats), 0)::bigint as ducats
             from public.treasury_flows t
            where t.created_at > p_since and t.created_at <= p_now and t.kind in ('RANSOM', 'LOOT') and t.ducats > 0
              and public.port_nation(t.port_id) = public.pirate_nation())   -- the city's country today (0143's one reader)
  select jsonb_build_object(
    'merchants', jsonb_build_object('ships', (select count(*) from public.npc_fleets nf join public.ships x on x.fleet_id = nf.fleet_id)),
    'navy', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(nv.ships), 0),
                                       'sea', count(*) filter (where nv.state = 'sea'), 'port', count(*) filter (where nv.state = 'port'),
                                       'laid_up', count(*) filter (where nv.state = 'laid_up'), 'wrecked', count(*) filter (where nv.state = 'wrecked'),
                                       'nations', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.fleets, z.ships) order by z.ships desc, z.code)
                                                              from (select na.code, count(*) as fleets, sum(y.ships) as ships
                                                                      from nv y join public.nations na on na.id = y.nation_id group by na.code) z), '[]'::jsonb))
               from nv),
    'pirates', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(pr.ships), 0),
                                          'sea', count(*) filter (where pr.state = 'sea'), 'port', count(*) filter (where pr.state = 'port'),
                                          'laid_up', count(*) filter (where pr.state = 'laid_up'), 'wrecked', count(*) filter (where pr.state = 'wrecked'),
                                          'wrecked_rows', count(*) filter (where pr.wrecked_at <= p_now),
                                          'roster', (select count(*) from public.pirate_roster),
                                          'homes', coalesce((select jsonb_agg(jsonb_build_array(z.code, z.name, z.fleets, z.ships) order by z.ships desc, z.code)
                                                               from (select po.code, po.name, count(*) as fleets, sum(y.ships) as ships
                                                                       from pr y join public.ports po on po.id = y.home_port group by po.code, po.name) z), '[]'::jsonb))
                  from pr),
    'cargo', (select jsonb_build_object('fleets', count(*), 'ships', coalesce(sum(cg.ships), 0),
                                        'sea', count(*) filter (where cg.state = 'sea'), 'port', count(*) filter (where cg.state = 'port'),
                                        'laid_up', count(*) filter (where cg.state = 'laid_up'), 'wrecked', count(*) filter (where cg.state = 'wrecked'),
                                        'tuns', round(coalesce(sum(cg.tuns), 0)), 'tuns_at_sea', round(coalesce(sum(cg.tuns) filter (where cg.state = 'sea'), 0)),
                                        'funds', public.funds_aboard())
                from cg),
    'win', jsonb_build_object(
      'since', p_since,
      'navy_fights', (select count(*) from nv where nv.fought_at > p_since and nv.fought_at <= p_now),
      'pirates_sunk', (select count(*) from nv where nv.fought_at > p_since and nv.fought_at <= p_now and nv.fought ->> 'result' = 'SUNK'),
      'pirate_wrecks', (select count(*) from pr where pr.wrecked_at > p_since and pr.wrecked_at <= p_now),
      'pirate_reborn', greatest(0, coalesce((select prev.wrecked_rows from prev), 0)
                                   + (select count(*) from pr where pr.wrecked_at > p_since and pr.wrecked_at <= p_now)
                                   - (select count(*) from pr where pr.wrecked_at <= p_now)),
      'plunder', (select loot.ducats from loot),
      'raids_paid', (select loot.n from loot)))
$body$
  $f$;
  revoke all on function public.stats_fleets_count(timestamptz, timestamptz) from public, anon, authenticated;
  comment on function public.stats_fleets_count(timestamptz, timestamptz) is
    '0419: the figures of one public.stats_fleets row: the merchants'' ships, the navy, the pirates and the cargo ships now (each fleet in one state: laid up, wrecked, at sea, in port), and the window (p_since, p_now]: navy fights, pirates sunk, pirate wrecks and rebirths, the ransom and loot the pirate cities took. Called by public.tick_stats alone. Writes nothing.';

  -- ── 4. THE READ ──
  execute $f$
create function world.stats_fleets()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0419 (the owner, 2026-11-15: "in stats, show like merchants navy, pirates, anad cargo"): the Stats face of the four kinds of ship. The newest
  -- public.stats_fleets row, the newest public.stats_merchants row (its fleets in the same four states: in port is what is neither at sea, laid up
  -- nor unable to sail), and the windows of the last 24 hours summed (`day_from` is where they start). Three index probes and at most ~52 rows. Public.
  select case when f.slot is null then jsonb_build_object('at', now(), 'counted_at', null)
         else jsonb_build_object(
           'at', now(), 'counted_at', f.at, 'day_from', d.day_from,
           'merchants', case when m.slot is null then null else jsonb_build_object(
                          'houses', m.houses, 'fleets', m.fleets, 'ships', (f.figures -> 'merchants' ->> 'ships')::int,
                          'sea', m.sailing, 'port', greatest(0, m.fleets - m.sailing - m.laid_up - m.unable), 'laid_up', m.laid_up, 'wrecked', m.unable,
                          'profit_day', m.profit_day, 'laps_day', m.laps_day) end,
           'navy', (f.figures -> 'navy') || jsonb_build_object('fights_day', d.fights, 'sunk_day', d.sunk),
           'pirates', (f.figures -> 'pirates') - 'wrecked_rows' || jsonb_build_object('wrecks_day', d.wrecks, 'reborn_day', d.reborn, 'plunder_day', d.plunder, 'raids_paid_day', d.raids),
           'cargo', f.figures -> 'cargo') end
    from (select 1) one
    left join lateral (select x.slot, x.at, x.figures from public.stats_fleets x order by x.slot desc limit 1) f on true
    left join lateral (select x.slot, x.houses, x.fleets, x.sailing, x.laid_up, x.unable, x.profit_day, x.laps_day from public.stats_merchants x order by x.slot desc limit 1) m on true
    left join lateral (select min((x.figures -> 'win' ->> 'since')::timestamptz) as day_from,
                              coalesce(sum((x.figures -> 'win' ->> 'navy_fights')::int), 0) as fights,
                              coalesce(sum((x.figures -> 'win' ->> 'pirates_sunk')::int), 0) as sunk,
                              coalesce(sum((x.figures -> 'win' ->> 'pirate_wrecks')::int), 0) as wrecks,
                              coalesce(sum((x.figures -> 'win' ->> 'pirate_reborn')::int), 0) as reborn,
                              coalesce(sum((x.figures -> 'win' ->> 'plunder')::bigint), 0) as plunder,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_paid')::int), 0) as raids
                         from public.stats_fleets x where x.at > f.at - interval '24 hours') d on true
$body$
  $f$;
  revoke all on function world.stats_fleets() from public, anon;
  grant execute on function world.stats_fleets() to authenticated;
  comment on function world.stats_fleets() is
    '0419: the Stats face of the merchants, the navy, the pirates and the cargo ships: the newest count''s row (public.stats_fleets) and merchants'' row (public.stats_merchants), and the last 24 hours of its windows summed. A read.';

  -- ── 5. THE HUNKS ──
  create temp table hunk_0419 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0419 values
  (1, c_cut[1],
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
$h$,
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
  v_fl int := 0;   -- 0419: the fleets' row (public.stats_fleets)
$h$),
  (2, c_cut[1],
$h$  get diagnostics v_m = row_count;
  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$,
$h$  get diagnostics v_m = row_count;
  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269

  -- 0419: EVERY FLEET (the owner, 2026-11-15: "in stats, show like merchants navy, pirates, anad cargo"): the merchants' ships, the navy, the
  -- pirates and the cargo ships as this count sees them, and what happened in its window (public.stats_fleets_count); kept 26 hours.
  -- budget: 1 row written and about 1 row deleted a count (twice an hour); ~1,400 small rows read by key (the three ship tables, their fleets and ships)
  insert into public.stats_fleets (slot, at, figures)
  values (v_slot, p_now, public.stats_fleets_count(v_prev_at, p_now))
  on conflict (slot) do nothing;
  get diagnostics v_fl = row_count;
  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
  v_ph := v_ph || jsonb_build_object('fleets', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0419
$h$),
  (3, c_cut[1],
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
$h$,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'fleets', v_fl, 'compacted', v_x, 'fold', v_fold,   -- 0419: fleets
$h$),
  (4, c_cut[2],
$h$      ('world',       'stats_me',              ''),
$h$,
$h$      ('world',       'stats_me',              ''),
      -- 0419: the merchants, the navy, the pirates and the cargo ships (the Stats face "Ships").
      ('world',       'stats_fleets',          ''),
$h$);
  for h in select * from hunk_0419 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0419 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0419 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0419 p where p.fn = h.fn) then
      raise exception '0419 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0419 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0419 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0419 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)
         and p.oid not in ('public.stats_fleets_count(timestamptz,timestamptz)'::regprocedure, 'world.stats_fleets()'::regprocedure)) <> v_fn_before then
    raise exception '0419 self-assert FAIL: another function moved';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name = 'stats_fleets' and e.arg_types = '' and e.fn is not null)
     or not has_function_privilege('authenticated', 'world.stats_fleets()', 'execute') or has_function_privilege('anon', 'world.stats_fleets()', 'execute')
     or has_function_privilege('authenticated', 'public.stats_fleets_count(timestamptz,timestamptz)', 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'world.stats_fleets()'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'public.stats_fleets_count(timestamptz,timestamptz)'::regprocedure) <> 's' then
    raise exception '0419 self-assert FAIL: the read is not in the registry, not granted to authenticated alone, or a new function is not STABLE';
  end if;

  -- ── 6. THE PROBE, rolled back: the count's figures read once (timed), then two planted rows and one too old, read back through the face's read ──
  begin
    v_tp := clock_timestamp();
    v_r := public.stats_fleets_count(now() - interval '30 minutes', now());
    v_ms := round(extract(epoch from clock_timestamp() - v_tp) * 1000);
    if v_ms > 3000 then
      raise exception '0419 self-assert FAIL: the count''s figures took % ms (budget 3,000)', v_ms;
    end if;
    if jsonb_typeof(v_r -> 'navy' -> 'nations') <> 'array' or jsonb_typeof(v_r -> 'pirates' -> 'homes') <> 'array' or (v_r -> 'merchants' ->> 'ships') is null
       or (v_r -> 'cargo' ->> 'tuns') is null or (v_r -> 'win' ->> 'navy_fights') is null or (v_r -> 'win' ->> 'plunder') is null
       or (v_r -> 'navy' ->> 'fleets')::int <> (v_r -> 'navy' ->> 'sea')::int + (v_r -> 'navy' ->> 'port')::int + (v_r -> 'navy' ->> 'laid_up')::int + (v_r -> 'navy' ->> 'wrecked')::int
       or (v_r -> 'pirates' ->> 'fleets')::int <> (v_r -> 'pirates' ->> 'sea')::int + (v_r -> 'pirates' ->> 'port')::int + (v_r -> 'pirates' ->> 'laid_up')::int + (v_r -> 'pirates' ->> 'wrecked')::int
       or (v_r -> 'cargo' ->> 'fleets')::int <> (v_r -> 'cargo' ->> 'sea')::int + (v_r -> 'cargo' ->> 'port')::int + (v_r -> 'cargo' ->> 'laid_up')::int + (v_r -> 'cargo' ->> 'wrecked')::int then
      raise exception '0419 self-assert FAIL: the count''s figures are not whole: %', v_r;
    end if;
    if (world.stats_fleets() ->> 'counted_at') is not null then
      raise exception '0419 self-assert FAIL: an empty table read a count';
    end if;
    insert into public.stats_fleets (slot, at, figures) values
      (1, now() - interval '25 hours', v_r || jsonb_build_object('win', jsonb_build_object('since', now() - interval '26 hours', 'navy_fights', 100, 'pirates_sunk', 100, 'pirate_wrecks', 100, 'pirate_reborn', 100, 'plunder', 100, 'raids_paid', 100))),
      (2, now() - interval '1 hour', v_r || jsonb_build_object('win', jsonb_build_object('since', now() - interval '2 hours', 'navy_fights', 3, 'pirates_sunk', 1, 'pirate_wrecks', 2, 'pirate_reborn', 1, 'plunder', 5000, 'raids_paid', 2))),
      (3, now(), v_r || jsonb_build_object('win', jsonb_build_object('since', now() - interval '1 hour', 'navy_fights', 4, 'pirates_sunk', 2, 'pirate_wrecks', 0, 'pirate_reborn', 1, 'plunder', 700, 'raids_paid', 1)));
    v_r := world.stats_fleets();
    if (v_r ->> 'counted_at')::timestamptz <> now() or (v_r ->> 'day_from')::timestamptz <> now() - interval '2 hours'
       or (v_r -> 'navy' ->> 'fights_day')::int <> 7 or (v_r -> 'navy' ->> 'sunk_day')::int <> 3
       or (v_r -> 'pirates' ->> 'wrecks_day')::int <> 2 or (v_r -> 'pirates' ->> 'reborn_day')::int <> 2
       or (v_r -> 'pirates' ->> 'plunder_day')::bigint <> 5700 or (v_r -> 'pirates' ->> 'raids_paid_day')::int <> 3
       or (v_r -> 'pirates') ? 'wrecked_rows' or jsonb_typeof(v_r -> 'navy' -> 'nations') <> 'array' or (v_r -> 'cargo' ->> 'funds') is null then
      raise exception '0419 self-assert FAIL: the read did not sum the last 24 hours of the planted rows: %', v_r - 'merchants';
    end if;
    v_note := format('the count''s figures in %s ms (navy %s, pirates %s, cargo %s fleets); three planted rows read back, the one 25 h old left out',
                     v_ms, v_r -> 'navy' ->> 'fleets', v_r -> 'pirates' ->> 'fleets', v_r -> 'cargo' ->> 'fleets');
    raise exception sqlstate 'BV419';
  exception when sqlstate 'BV419' then null;
  end;
  if exists (select 1 from public.stats_fleets) then
    raise exception '0419 self-assert FAIL: the probe was not rolled back';
  end if;
  if v_note not like 'the count%' then
    raise exception '0419 self-assert FAIL: the probe did not run to its end';
  end if;

  perform public.news_update('0419', 'Stats show every fleet', '통계에서 모든 선단을 봅니다');
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0419 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0419 self-assert ok: THE STATS COUNT EVERY FLEET. Four hunks over two bodies, each once and reversing; grants and volatility unmoved; no other function moved; public.stats_fleets, public.stats_fleets_count, world.stats_fleets (registry, authenticated). Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
