-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0467 - THE HOUSES' BOARD  (dark: the owner's switch houses_board_enabled, false; lit, Rank ranks a company among the
--        merchant houses by this week's profit, and a test company leaves both boards)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/content-plan-2026-11.md 5.3 item 5 and 5.6 ("Test companies on the Rank board: off the board. They stay in the
--   database."); docs/design/playable-2026-11-22.md P2. docs/dev-log/2026-11-22-houses-board.md.
--
-- WHY: Rank's one board (0025) ranks the companies by fame of all time, and 0097 took the merchant houses off it. On production it holds
--   19 companies; 14 have no login (10 carry a probe's 00000000- id, 4 an id no login matches: read 2026-11-21, before-0467.sql). The 869
--   merchant houses that trade the same seas are nobody's rivals.
--
-- THE MEASURE (one, that both kinds already have served): PROFIT THIS WEEK = sum(earned - lost) of public.history_company_day (0316) over the
--   UTC week (public.history_bucket, Monday to Sunday). 0316 adds a company's AND a merchant's ledger to it every run of byeharu-voyage:history
--   (12, 27, 42, 57), FOUNDING / NPC_REFOUND / NPC_CARRIED / PROBE_ out (public.ledger_is_earning). It is cash in less cash out: a cargo bought
--   on Sunday and sold on Monday is a loss in one week and a gain in the next. Decided by default.
-- WHO IS ON IT: every merchant house (public.npc_houses) and every company with a LOGIN: a players row, not is_npc, whose auth_uid has an
--   auth.users row. A test company (made by a migration or a probe, no login ever) is not. Pirates and the crown are not houses.
--
-- WHAT THIS FILE DOES:
--   1. THE SWITCH houses_board_enabled (false, DARK). Dark, nothing below writes or shows anything; every live body behaves as before (asserted).
--   2. public.houses_week (week, player_id, net): one row a house a week, this week and the last (the week is a key, not a wipe:
--      docs/WEEKLY_ROLLOVER.md). Written only by public.houses_week_settle.
--   3. public.houses_week_settle(now): lit, recounts this week and the last from history_company_day for every house on the board, writes
--      only the rows whose figure moved, removes a house no longer on it, and deletes weeks older than the last. Dark, returns null at once.
--   4. public.tick_history (hunk 1): its run calls the settle after the trim, so the board is counted on the history job's own minute, right
--      after the ledger was added: no new cron, no read pays for it.
--   5. world.houses_week(): the client's one read (registered: public.client_rpc_entry_points, hunk). Stable, reads only houses_week, the
--      history mark and the names of at most standings_board_size + 1 houses: the top of the board, your place ("#37 of 874"), your
--      figure, and the house just ahead of you with the gap. Dark: {"on": false}, and the client shows the board as today.
--   6. public.settle_standings (hunks 2, 3): lit, the Captains board (0025) leaves a test company out too, the same rule.
--   7. A GAP-FILLING SHIM, as 0001's auth.uid(): where auth.users does not exist (PGlite: the local world, the proofs; NEVER on Supabase, where
--      it exists), a one-column auth.users is made holding the local world's one sign-in (src/lib/db/localDb.ts LOCAL_AUTH_UID), so "has a
--      login" is the same question in every world. Nothing else reads it.
-- NOT CHANGED: how fame is counted, world.standings' payload, history_company_day and its job's steps, the Countries board, any price.
-- ROWS: none while dark. Lit: about 1,750 rows in houses_week (2 weeks x ~874 houses), rewritten only where a house's week moved; the merchants
--   trade all day, so about 800 row updates a history run, 4 runs an hour: ABOUT 55 ROW VERSIONS A MINUTE, on a 1,750-row table with no index
--   beside its key (so most updates are HOT). Reads: world.houses_week on a Rank open and on the world's beat while Rank is open: about 1,750
--   rows of one tiny table and up to 11 primary-key lookups, no function per row.
--   -- budget: none (no cron, no reschedule, no fillfactor, no autovacuum setting; the settle rides byeharu-voyage:history).
-- COST: lit, the settle reads ~874 x 2 primary-key ranges of history_company_day (about 14 rows each) once per history run (4 an hour).
-- LOCKS: CREATE OR REPLACE x3 by hunks (tick_history, settle_standings, client_rpc_entry_points); two new functions and one table.
--   TIME: a second. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, houses_board_enabled false (the read answers {"on": false}, the settle writes nothing, both boards are
--   0025's again). Full: a new migration reversing the five hunks (OLD texts below verbatim), dropping world.houses_week,
--   public.houses_week_settle and public.houses_week, deleting the knob.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked functions' grants, volatility, definer, search path, owner
--   unmoved; the knob; world.houses_week registered for authenticated alone; the table unreachable by a client. THE PROBE (rolled back): a
--   probe test company (no login) and a probe merchant, each with a week's figure: DARK the settle writes nothing and the Captains settle keeps
--   the test company (today); LIT the merchant is on the houses' board, the test company on neither board; where the shim was made here, a
--   probe company WITH a login is on both. Proof 170 proves the read's place, the gap, the weeks and the retention.
-- VERSION: 0467 = prod head 0464 + 3 (0465 #778 and 0466 #782 are open and ahead; this file touches none of their bodies: 0465 cuts
--   client_rpc_entry_points at its crew_cost line, this file at land_repeat).
-- news: none (dark: nothing changes for a player until the owner lights houses_board_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.tick_history(timestamp with time zone)', 'public.settle_standings(timestamp with time zone)',
                                    'public.client_rpc_entry_points()'];
  c_local  constant uuid := '00000000-0000-4000-8000-000000000a17';   -- src/lib/db/localDb.ts LOCAL_AUTH_UID: the local world's one sign-in
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_shim      boolean := false;
  v_note      text := '';
  v_nat       uuid;
  v_port      uuid;
  v_test      uuid;
  v_merch     uuid;
  v_live      uuid;
  v_week      date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_r         jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'houses_board_enabled') or to_regclass('public.houses_week') is not null then
    raise exception '0467 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_history(timestamp with time zone)') is null or to_regclass('public.history_company_day') is null
     or to_regprocedure('public.history_bucket(date,text)') is null or to_regclass('public.npc_houses') is null
     or to_regprocedure('public.settle_standings(timestamp with time zone)') is null then
    raise exception '0467 refuses: 0025 (the board), 0097 (the merchant houses) or 0316 (the history) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE SHIM (only where auth.users is absent: never on Supabase) ──
  if to_regclass('auth.users') is null then
    execute 'create schema if not exists auth';
    -- retention: none, bounded by one row (the local world's one sign-in); a gap-filling shim, as 0001's auth.uid()
    execute 'create table auth.users (id uuid primary key)';
    execute 'revoke all on table auth.users from public';
    execute format('insert into auth.users (id) values (%L)', c_local);
    v_shim := true;
  end if;

  -- ── 3. THE KNOB, THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('houses_board_enabled', 'false'::jsonb, '0467: THE SWITCH (the owner''s). true: Rank ranks a company among the merchant houses by this week''s profit (world.houses_week, counted by public.houses_week_settle in each byeharu-voyage:history run), and a company with no login (a test company) leaves the Captains board (public.settle_standings). false: neither; the read answers {"on": false}.');

  -- retention: this week and the last (public.houses_week_settle deletes every older week on each run); about 874 rows a week
  create table public.houses_week (
    week      date   not null,
    player_id uuid   not null,
    net       bigint not null,
    primary key (week, player_id)
  );
  comment on table public.houses_week is
    '0467: THE HOUSES'' BOARD. One row a house (a merchant house, or a company with a login) a UTC week: net = sum(earned - lost) of '
    'public.history_company_day in the week. Written only by public.houses_week_settle, read only by world.houses_week. This week and the last '
    'are kept. No foreign key (as history_company_day: a row outlives nothing it needs, and a key would lock players per row).';
  alter table public.houses_week enable row level security;
  revoke all on table public.houses_week from public, anon, authenticated;

  -- ── 4. THE SETTLE ──
  execute $f$
create function public.houses_week_settle(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0467: THE HOUSES' BOARD, counted. Called by public.tick_history at the end of each run (byeharu-voyage:history), right after the ledger was
-- added to history_company_day. Dark: null at once, nothing read or written. Lit: this week and the last, recounted for every house on the
-- board (every merchant house; every company with a login: a test company has none), only the rows that moved written; a house no longer on
-- the board removed; older weeks deleted.
declare
  v_t0   timestamptz := clock_timestamp();
  v_week date := public.history_bucket((p_now at time zone 'UTC')::date, 'week');
  v_up   int;
  v_gone int;
begin
  if not coalesce(public.wc('houses_board_enabled') = 'true'::jsonb, false) then
    return null;
  end if;

  with b as (
    select nh.player_id as id from public.npc_houses nh
    union
    select p.id from public.players p where not p.is_npc and exists (select 1 from auth.users u where u.id = p.auth_uid)
  )
  insert into public.houses_week as t (week, player_id, net)
  select w.week, b.id, coalesce(sum(h.earned - h.lost), 0)::bigint
    from unnest(array[v_week - 7, v_week]) w(week)
   cross join b
    left join public.history_company_day h on h.player_id = b.id and h.day >= w.week and h.day < w.week + 7
   group by w.week, b.id
  on conflict (week, player_id) do update set net = excluded.net
   where t.net is distinct from excluded.net;
  get diagnostics v_up = row_count;

  with b as (
    select nh.player_id as id from public.npc_houses nh
    union
    select p.id from public.players p where not p.is_npc and exists (select 1 from auth.users u where u.id = p.auth_uid)
  )
  delete from public.houses_week t
   where t.week < v_week - 7
      or not exists (select 1 from b where b.id = t.player_id);
  get diagnostics v_gone = row_count;

  return jsonb_build_object('week', v_week, 'written', v_up, 'removed', v_gone, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end
$body$
  $f$;
  revoke all on function public.houses_week_settle(timestamptz) from public, anon, authenticated;

  -- ── 5. THE READ ──
  execute $f$
create function world.houses_week()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0467: THE HOUSES' BOARD, served. The top of this week's board (standings_board_size rows, competition ranking: two houses level are both
-- 2nd and the next is 4th), how many houses are on it, and YOUR place, figure and the house just ahead with the gap, whether or not you are
-- at the top. A row says a name, a flag, whether it is a company, and the week's profit: nothing else. Dark: {"on": false}.
declare
  v_me    uuid := public.current_player_id();
  v_week  date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_size  int  := greatest(1, public.wc_int('standings_board_size'));
  v_at    timestamptz;
  v_n     int;
  v_net   bigint;
  v_pos   int;
  v_tied  boolean;
  v_you   jsonb;
  v_ahead jsonb;
begin
  if not coalesce(public.wc('houses_board_enabled') = 'true'::jsonb, false) then
    return jsonb_build_object('on', false);
  end if;
  select m.ledger_through into v_at from public.history_mark m;
  select count(*)::int into v_n from public.houses_week w where w.week = v_week;

  select w.net into v_net from public.houses_week w where w.week = v_week and w.player_id = v_me;
  if v_net is not null then
    select (count(*) filter (where w.net > v_net))::int + 1, count(*) filter (where w.net = v_net) > 1
      into v_pos, v_tied
      from public.houses_week w where w.week = v_week;
    select jsonb_build_object('name', pl.company_name, 'gap', a.net - v_net) into v_ahead
      from (select w.player_id, w.net from public.houses_week w
             where w.week = v_week and w.net > v_net order by w.net, w.player_id limit 1) a
      join public.players pl on pl.id = a.player_id;
    v_you := jsonb_build_object('position', v_pos, 'tied', v_tied, 'net', v_net, 'on_board', v_pos <= v_size, 'ahead', v_ahead);
  end if;

  return jsonb_build_object(
    'on',          true,
    'week',        v_week,
    'through',     v_at,
    'age_seconds', case when v_at is null then null else round(extract(epoch from (now() - v_at)))::int end,
    'houses',      v_n,
    'board_size',  v_size,
    'board', (
      select coalesce(jsonb_agg(jsonb_build_object(
                        'position', r.pos, 'tied', r.tied, 'company_name', pl.company_name, 'nation', n.code,
                        'company', not pl.is_npc, 'net', r.net, 'is_you', r.player_id is not distinct from v_me)
                      order by r.pos, pl.company_name), '[]'::jsonb)
        from (select q.player_id, q.net, q.pos, q.tied
                from (select w.player_id, w.net,
                             (rank() over (order by w.net desc))::int as pos,
                             count(*) over (partition by w.net) > 1 as tied
                        from public.houses_week w where w.week = v_week) q
               where q.pos <= v_size
               order by q.pos, q.player_id
               limit v_size) r
        join public.players pl on pl.id = r.player_id
        left join public.nations n on n.id = pl.nation_id),
    'you', v_you);
end
$body$
  $f$;
  revoke all on function world.houses_week() from public, anon;
  grant execute on function world.houses_week() to authenticated;

  -- ── 6. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0467 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0467 values
  ('public.tick_history(timestamp with time zone)', 1,
$h$  v_trim := public.history_trim(p_now);$h$,
$h$  v_trim := public.history_trim(p_now);
  v_ph := v_ph || jsonb_build_object('houses', public.houses_week_settle(p_now));   -- 0467: the houses' board, on this job's minute (null while dark)$h$),
  ('public.settle_standings(timestamp with time zone)', 1,
$h$  v_n    int;$h$,
$h$  v_n    int;
  v_lit  boolean := coalesce(public.wc('houses_board_enabled') = 'true'::jsonb, false);   -- 0467: lit, a test company (no login) is not ranked$h$),
  ('public.settle_standings(timestamp with time zone)', 2,
$h$       where not p.is_npc   -- 0097: merchant companies are not ranked (docs/NPC_TRADERS.md §6)$h$,
$h$       where not p.is_npc   -- 0097: merchant companies are not ranked (docs/NPC_TRADERS.md §6)
         and (not v_lit or exists (select 1 from auth.users u where u.id = p.auth_uid))   -- 0467: lit, only a company with a login$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'land_repeat',           'boolean'),$h$,
$h$      ('cmd',         'land_repeat',           'boolean'),
      -- 0467: Rank's houses' board (dark: {"on": false})
      ('world',       'houses_week',           ''),$h$);

  for v_h in select h.fn from hunks_0467 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0467 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0467 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0467 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0467 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0467 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 7. SELF-ASSERT: the catalog, the knob, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid not in ('public.houses_week_settle(timestamptz)'::regprocedure, 'world.houses_week()'::regprocedure)) <> v_fn_before then
    raise exception '0467 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0467 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if public.wc('houses_board_enabled') <> 'false'::jsonb then
    raise exception '0467 self-assert FAIL: houses_board_enabled is not false';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'houses_week', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.houses_week_settle(timestamptz)', 'execute')
     or has_table_privilege('authenticated', 'public.houses_week', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.houses_week', 'select')
     or (select p.provolatile from pg_proc p where p.oid = 'world.houses_week()'::regprocedure) <> 's'
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0467 self-assert FAIL: world.houses_week is not registered for authenticated alone, or a client reaches the settle or the table';
  end if;

  -- ── 8. THE PROBE, rolled back by a raised sentinel ──
  begin
    select n.id into v_nat from public.nations n where n.code = 'PRT';
    select p.id into v_port from public.ports p where p.code = 'LIS';
    -- a test company: an id no login matches, as the 14 on production
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values ('00000000-0467-4000-8000-0000000000c1', 'Casa Prova 0467', v_nat, 0, false) returning id into v_test;
    -- a merchant house
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values (null, 'Casa Mercante 0467', v_nat, 0, true) returning id into v_merch;
    insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
      values (v_merch, 900467, 'prt', 'A probe of migration 0467.', 'Probe', v_port, 1000, 0.1);
    insert into public.history_company_day (player_id, day, earned, lost) values
      (v_test, v_week, 3000000000000000, 0), (v_merch, v_week, 2000000000000000, 0)
      on conflict (player_id, day) do update set earned = excluded.earned, lost = excluded.lost;
    if v_shim then
      -- a company WITH a login (the shim's one sign-in), where this file made the shim
      select p.id into v_live from public.players p where p.auth_uid = c_local;
      if v_live is null then
        insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
          values (c_local, 'Casa Viva 0467', v_nat, 0, false) returning id into v_live;
      end if;
      insert into public.history_company_day (player_id, day, earned, lost) values (v_live, v_week, 1000000000000000, 0)
        on conflict (player_id, day) do update set earned = excluded.earned, lost = excluded.lost;
    end if;

    -- DARK: the settle writes nothing; the Captains settle (a far slot) keeps the test company, as today
    if public.houses_week_settle(now()) is not null or exists (select 1 from public.houses_week) then
      raise exception '0467 self-assert FAIL: dark, the houses'' settle wrote';
    end if;
    perform public.settle_standings('2099-01-01 00:00:00+00');
    if not exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:00:00+00') and s.player_id = v_test) then
      raise exception '0467 self-assert FAIL: dark, the Captains board left out a company (it must be today''s board)';
    end if;
    if world.houses_week() <> '{"on": false}'::jsonb then
      raise exception '0467 self-assert FAIL: dark, the read served %', world.houses_week();
    end if;

    -- LIT
    update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
    v_r := public.houses_week_settle(now());
    if v_r is null
       or (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_merch) is distinct from 2000000000000000
       or exists (select 1 from public.houses_week w where w.player_id = v_test) then
      raise exception '0467 self-assert FAIL: lit, the merchant is not on the houses'' board at its week, or the test company is: %', v_r;
    end if;
    -- the merchant leads (no real house made 2e15 in a week): place 1
    if (select count(*) from public.houses_week w where w.week = v_week and w.net > 2000000000000000) <> 0 then
      raise exception '0467 self-assert FAIL: lit, a house stands above the probe merchant';
    end if;
    perform public.settle_standings('2099-01-01 00:10:00+00');
    if exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:10:00+00') and s.player_id = v_test) then
      raise exception '0467 self-assert FAIL: lit, the test company is still on the Captains board';
    end if;
    -- a second settle with nothing moved writes nothing
    if (public.houses_week_settle(now())->>'written')::int <> 0 then
      raise exception '0467 self-assert FAIL: lit, a second settle with nothing moved wrote rows';
    end if;
    if v_shim then
      if (select w.net from public.houses_week w where w.week = v_week and w.player_id = v_live) is distinct from 1000000000000000
         or not exists (select 1 from public.standings s where s.board_slot = public.standings_slot_of('2099-01-01 00:10:00+00') and s.player_id = v_live) then
        raise exception '0467 self-assert FAIL: lit, the company with a login is not on both boards';
      end if;
      v_note := '; a company with a login on both boards (the shim was made here)';
    else
      v_note := '; auth.users is the platform''s (no shim)';
    end if;
    raise exception sqlstate 'BV467';
  exception when sqlstate 'BV467' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0467 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0467 self-assert ok: THE HOUSES'' BOARD (dark). % hunks once each and reversing; grants and volatility unmoved; no other function moved; houses_board_enabled false; world.houses_week registered for authenticated alone; probe: dark nothing written and the test company kept on Captains, lit the merchant on the houses'' board and the test company on neither%; % ms.',
    (select count(*) from hunks_0467), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0467;
end $m$;
