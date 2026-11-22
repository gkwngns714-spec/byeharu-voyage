-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0473 - A JOB SAYS WHERE TO BUY, AND YOUR WEEK IS COUNTED LIVE  (two fixes to lit features: hold_requests_enabled and
--        houses_board_enabled are on in production; with either off, what it hunks behaves as before)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE PLAY-TEST: docs/design/playable-2026-11-22.md section 5, rows 6 and 10 (S4 and S6 for the lead). docs/dev-log/2026-11-22-requests-source.md.
--
-- S4, WHY: public.hold_request_post (0466) picks a good that "some other harbour sells", anywhere in the world: Lisbon asked for Honeybush Leaf (a
--   Cape good) with a 4 h deadline, and the row did not say where to buy it. On production (before-0473.sql, 2026-11-22) the nearest harbour that
--   sells a standing hold job's good lies up to 280 sailing minutes away one way for a Barca (Algiers asking Korean movable type: 13,435 nm).
-- S4, WHAT: the job's deadline is drawn FIRST (its own draw, keyed as before, so it moves no other draw), then the good is one SOLD AT A HARBOUR
--   A BARCA CAN SAIL TO AND BACK in hold_request_trip_share (0.5) of the real time the job stands (public.clock_start of its expires_day, less now):
--   one way at most that share / 2 x the time left, at hold_request_speed_kn (15: the Barca, a new company's hull, 5 kn x speed_scale 3), by the
--   reach table (voyage.reach_from: the miles a fleet sails). THE SOURCE, the nearest such harbour, is kept on the row (trade_contracts.
--   source_port_id, new, null on a city's request) and world.contracts serves it on a hold job as `from`: code, name, nm and sail_seconds (a
--   Barca's real seconds from the poster), so the client says "Buy at Setubal · 4 min". The open hold jobs already standing get their
--   nearest seller written once (the backfill below), however far: the row says the truth about them until they expire (6 h at most).
--   A harbour where no good meets the rule posts nothing that minute (the wind tries the next); everything else in the draw is 0466's.
-- S6, WHY: world.houses_week (0467) serves YOUR week from public.houses_week, which the history job settles four times an hour: after a +1,485
--   sale the board said "Profit 0" for up to 15 minutes, and "Updated 10 min ago" beside the page's own "Updated just now" (the Captains'
--   photograph, another clock).
-- S6, WHAT: YOUR figure is counted in the read: what the history job has added for your days this week (history_company_day, at most 7 rows by
--   its key) plus your ledger since the job's mark (ledger_player_created: one index range of one player's rows, public.ledger_is_earning's
--   kinds), the same sum the settle will write. Your place, tie, the house ahead and the gap are taken against the other houses' settled rows,
--   your own board row carries the live figure, a company not settled yet (new this week) is counted in "of N", and `you.live` says so. The other
--   rows stay the settle's; `through` / `age_seconds` are theirs, and the client's word says so ("Others counted 10 min ago").
--
-- THE HUNKS (each once in the live body, and reversing):
--   public.hold_request_post   H1 declare; H2 the deadline drawn first and the reach; the sellers within it; H3 the source picked; H4 the old
--                              deadline draw removed; H5-H6 the insert carries the source.
--   world.contracts            H1 `from` on a hold job; H2 the source's join.
--   world.houses_week          H1 declare; H2 your live figure, place and the house ahead; H3 your row live on the board; H4 `live` on your line.
-- NOT CHANGED: a city-sized request, the delivery and its pay, the lot, the bonus, the purse rule, the settle, the board's other rows, the Captains'.
-- ROWS: none new a minute. S4: the open hold jobs (about 500) get one UPDATE each, once. S6: a read reads at most 7 + (one player's ledger rows of
--   the last 15 minutes) rows more; measured in proof 176 and in after-0473.sql.
--   -- budget: none (no table, no job, no index, no cron; one nullable column with no default on trade_contracts, about 2,000 rows).
--   -- retention: none new (source_port_id lives and dies with its row: 0466's H9 prunes a hold job a real day after its deadline).
-- LOCKS: ALTER TABLE trade_contracts ADD COLUMN (nullable, no default: catalog only); UPDATE of the open hold rows; CREATE OR REPLACE x3 by hunks.
-- TIME: a few seconds. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, hold_requests_enabled false (no new job) / houses_board_enabled false (the board as dark). Full: a new
--   migration reversing the nine hunks (their OLD texts are below verbatim), dropping the column and the two knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner unmoved;
--   the knobs; DARK IS TODAY (rolled back, both switches off): one harbour's board the same (ids and `from` aside), the writer posts nothing, the
--   week read {"on": false}; THE PROBES (rolled back): lit, a harbour given room posts two jobs, each sold at its source and its source a Barca's
--   there-and-back within the share of its time left, and the read serves it; lit, a probe company's sale shows in its week at once, its row on
--   the board live, its place counted against the others. Proof 176 proves the rest and measures the read.
-- VERSION: 0473 = prod head 0471 + 2 (0472 is another builder's, world.best_sales / hull_order_price / cmd.order_hull and the yard; this file
--   touches none of its bodies).
-- news: none (two fixes to lit features: a job names its harbour; your week shows your last sale)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.hold_request_post(uuid,timestamp with time zone)', 'world.contracts(uuid)', 'world.houses_week()'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  c           public.trade_contracts%rowtype;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_port      uuid;
  v_board0    jsonb;
  v_board1    jsonb;
  v_a         jsonb;
  v_note      text;
  v_back      int;
  v_open      int;
  v_ids       uuid[];
  v_now       timestamptz;
  v_nm        numeric;
  v_left      numeric;
  v_nat       uuid;
  v_me        uuid;
  v_week      date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_mark      timestamptz;
  v_exp       bigint;
  v_r         jsonb;
  v_settled   int;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'trade_contracts' and column_name = 'source_port_id')
     or exists (select 1 from public.world_config where key in ('hold_request_speed_kn', 'hold_request_trip_share')) then
    raise exception '0473 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.hold_request_post(uuid,timestamp with time zone)') is null or to_regprocedure('world.houses_week()') is null
     or to_regprocedure('voyage.reach_from(uuid)') is null or to_regprocedure('public.ledger_is_earning(text)') is null
     or not exists (select 1 from public.world_config where key = 'time_compression') then
    raise exception '0473 refuses: 0466 (hold jobs), 0467 (the houses'' board), 0316 (the history) or 0047 (the reach table) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE, and the board one real harbour serves with both switches off (rolled back: the read winds) ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' and p.code = 'LIS';
  if v_port is null then
    select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  end if;
  begin
    update public.world_config set value = 'false'::jsonb where key in ('hold_requests_enabled', 'houses_board_enabled');
    select coalesce(jsonb_agg(e - 'id' order by e ->> 'good', e ->> 'expires_day'), '[]'::jsonb) into v_board0 from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e;
    raise exception sqlstate 'BV473';
  exception when sqlstate 'BV473' then null;
  end;

  -- ── 2. THE COLUMN, THE KNOBS ──
  alter table public.trade_contracts add column source_port_id uuid;
  comment on column public.trade_contracts.source_port_id is
    '0473: a hold job''s harbour that sells its good (public.hold_request_post''s pick: the nearest a Barca sails to and back in hold_request_trip_share of the time the job stands). Null on a city''s request. No foreign key on purpose: adding one would lock public.ports, and a port is never deleted.';
  insert into public.world_config (key, value, description) values
    ('hold_request_speed_kn', to_jsonb(coalesce((select sc.speed_kn from public.ship_classes sc where sc.code = 'barca'), 15)),
     '0473: the speed (knots) a hold job''s sailing is measured at: the Barca''s, a new company''s hull (5 kn x speed_scale 3 = 15). public.hold_request_post''s reach and world.contracts'' from.sail_seconds.'),
    ('hold_request_trip_share', to_jsonb(0.5),
     '0473: a hold job''s good is sold at a harbour a Barca sails to and back (twice the one way) in this share of the real time the job stands; the rest is room to buy, wait and be slow.');

  -- ── 3. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0473 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0473 values
  ('public.hold_request_post(uuid,timestamp with time zone)', 1,
$h$  v_base  numeric;$h$,
$h$  v_base  numeric;
  v_left  numeric;   -- 0473: the real seconds the job stands
  v_reach numeric;   -- 0473: the farthest a source may lie, one way, in sailed nm
  v_src   uuid;      -- 0473: the nearest harbour within it that sells the good$h$),
  ('public.hold_request_post(uuid,timestamp with time zone)', 2,
$h$  -- THE GOOD: an index into the ordered candidates, as public.contract_draw
  v_u := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':good');
  with sold_elsewhere as (
    select distinct s.good_id from public.port_specialties s join public.ports p2 on p2.id = s.port_id and p2.kind = 'HARBOUR' where s.port_id <> p_port
  ), cand as ($h$,
$h$  -- 0473: THE DEADLINE FIRST (its own draw, keyed as before: drawing it here moves no other), and THE REACH it leaves: a Barca
  -- (hold_request_speed_kn) sails to the harbour that sells the good and back in hold_request_trip_share of the real time the job stands
  v_u    := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':hours');
  v_days := greatest(1, round((public.wc_num('hold_request_hours_min') + v_u * (public.wc_num('hold_request_hours_max') - public.wc_num('hold_request_hours_min')))
                              * 3600 / public.wc_num('game_day_seconds'))::int);
  v_left  := extract(epoch from public.clock_start('game_day', v_day + v_days) - p_now);
  v_reach := greatest(0, v_left) * public.wc_num('hold_request_trip_share') / 2 * public.wc_num('hold_request_speed_kn') * public.wc_num('time_compression') / 3600;

  -- THE GOOD: an index into the ordered candidates, as public.contract_draw
  v_u := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':good');
  with sold_elsewhere as (
    -- 0473: sold at a harbour within the reach (the reach table's sailed miles), not merely somewhere in the world
    select distinct s.good_id
      from voyage.reach_from(p_port) r
      join public.ports p2 on p2.id = r.port_id and p2.kind = 'HARBOUR'
      join public.port_specialties s on s.port_id = r.port_id
     where r.port_id <> p_port and r.nm <= v_reach
  ), cand as ($h$),
  ('public.hold_request_post(uuid,timestamp with time zone)', 3,
$h$  if v_good is null then
    return 0;
  end if;
$h$,
$h$  if v_good is null then
    return 0;
  end if;
  -- 0473: THE SOURCE, kept on the row: the nearest harbour within the reach that sells it
  select r.port_id into v_src
    from voyage.reach_from(p_port) r
    join public.ports p2 on p2.id = r.port_id and p2.kind = 'HARBOUR'
    join public.port_specialties s on s.port_id = r.port_id and s.good_id = v_good
   where r.port_id <> p_port and r.nm <= v_reach
   order by r.nm, r.code
   limit 1;
$h$),
  ('public.hold_request_post(uuid,timestamp with time zone)', 4,
$h$  v_u    := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':hours');
  v_days := greatest(1, round((public.wc_num('hold_request_hours_min') + v_u * (public.wc_num('hold_request_hours_max') - public.wc_num('hold_request_hours_min')))
                              * 3600 / public.wc_num('game_day_seconds'))::int);
  if v_lit$h$,
$h$  -- 0473: the deadline (v_days) is drawn above, before the good: the good's harbour must lie within it
  if v_lit$h$),
  ('public.hold_request_post(uuid,timestamp with time zone)', 5,
$h$premium_ducats, expires_day, status, escrow, size)$h$,
$h$premium_ducats, expires_day, status, escrow, size, source_port_id)$h$),
  ('public.hold_request_post(uuid,timestamp with time zone)', 6,
$h$'open', case when v_lit then v_bud else 0 end, 'hold')$h$,
$h$'open', case when v_lit then v_bud else 0 end, 'hold', v_src)$h$),
  ('world.contracts(uuid)', 1,
$h$        'total', case when c.size = 'hold' then round(floor(c.premium_ducats / c.premium_per_unit) * (q.bid + c.premium_per_unit))::bigint end,$h$,
$h$        'total', case when c.size = 'hold' then round(floor(c.premium_ducats / c.premium_per_unit) * (q.bid + c.premium_per_unit))::bigint end,
        -- 0473: a hold job's harbour that sells the good (public.hold_request_post's pick), and a Barca's real sailing seconds to it from here
        'from', case when sp.id is not null then jsonb_build_object('code', sp.code, 'name', sp.name, 'nm', round(sn.nm),
                  'sail_seconds', round(sn.nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression'))::int) end,$h$),
  ('world.contracts(uuid)', 2,
$h$       cross join lateral world.price(c.port_id, c.good_id) q   -- 0311$h$,
$h$       cross join lateral world.price(c.port_id, c.good_id) q   -- 0311
        left join public.ports sp on sp.id = c.source_port_id   -- 0473: a hold job's source
        left join lateral (select (r.reaches ->> sp.code)::numeric as nm from public.sea_reaches r where r.port_id = c.port_id) sn on true$h$),
  ('world.houses_week()', 1,
$h$  v_ahead jsonb;$h$,
$h$  v_ahead jsonb;
  v_wk    timestamptz;   -- 0473: the week's first instant$h$),
  ('world.houses_week()', 2,
$h$  select w.net into v_net from public.houses_week w where w.week = v_week and w.player_id = v_me;
  if v_net is not null then
    select (count(*) filter (where w.net > v_net))::int + 1, count(*) filter (where w.net = v_net) > 1
      into v_pos, v_tied
      from public.houses_week w where w.week = v_week;
    select jsonb_build_object('name', pl.company_name, 'gap', a.net - v_net) into v_ahead
      from (select w.player_id, w.net from public.houses_week w
             where w.week = v_week and w.net > v_net order by w.net, w.player_id limit 1) a$h$,
$h$  -- 0473: YOUR figure, counted in this read (the other houses' rows stay the settle's): what the history job has added for your days this week
  -- (history_company_day by its key, at most 7 rows) and your ledger since its mark (ledger_player_created, one range of one player's rows):
  -- the sum the settle will write. A company only (a merchant house never calls); the caller is signed in, so she is on the board (0467's rule).
  if v_me is not null and exists (select 1 from public.players p where p.id = v_me and not p.is_npc) then
    v_wk  := v_week::timestamp at time zone 'UTC';
    v_net := coalesce((select sum(h.earned - h.lost) from public.history_company_day h
                        where h.player_id = v_me and h.day >= v_week and h.day < v_week + 7), 0)
           + coalesce((select sum(l.ducats_delta) from public.ledger l
                        where l.player_id = v_me and l.created_at > greatest(coalesce(v_at, v_wk), v_wk) and l.created_at < v_wk + interval '7 days'
                          and public.ledger_is_earning(l.kind)), 0);
    if not exists (select 1 from public.houses_week w where w.week = v_week and w.player_id = v_me) then
      v_n := v_n + 1;   -- not settled yet (new this week): on the board all the same
    end if;
  end if;
  if v_net is not null then
    select (count(*) filter (where w.net > v_net))::int + 1, count(*) filter (where w.net = v_net) > 0
      into v_pos, v_tied
      from public.houses_week w where w.week = v_week and w.player_id <> v_me;
    select jsonb_build_object('name', pl.company_name, 'gap', a.net - v_net) into v_ahead
      from (select w.player_id, w.net from public.houses_week w
             where w.week = v_week and w.net > v_net and w.player_id <> v_me order by w.net, w.player_id limit 1) a$h$),
  ('world.houses_week()', 3,
$h$                        from public.houses_week w where w.week = v_week) q$h$,
$h$                        from (select w.player_id, w.net from public.houses_week w
                               where w.week = v_week and (v_net is null or w.player_id is distinct from v_me)
                              union all
                              select v_me, v_net where v_net is not null) w) q   -- 0473: your row at your live figure$h$),
  ('world.houses_week()', 4,
$h$'on_board', v_pos <= v_size, 'ahead', v_ahead);$h$,
$h$'on_board', v_pos <= v_size, 'ahead', v_ahead, 'live', true);   -- 0473: live: counted in this read$h$);

  for v_h in select h.fn from hunks_0473 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0473 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0473 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0473 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0473 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0473 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. THE BACKFILL: an open hold job standing now gets its nearest seller, however far (it says the truth until it expires) ──
  update public.trade_contracts t
     set source_port_id = (select r.port_id
                             from voyage.reach_from(t.port_id) r
                             join public.ports p2 on p2.id = r.port_id and p2.kind = 'HARBOUR'
                             join public.port_specialties s on s.port_id = r.port_id and s.good_id = t.good_id
                            where r.port_id <> t.port_id
                            order by r.nm, r.code
                            limit 1)
   where t.size = 'hold' and t.status = 'open' and t.source_port_id is null;
  get diagnostics v_back = row_count;

  -- ── 5. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_fn_before then
    raise exception '0473 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0473 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if public.wc_num('hold_request_speed_kn') <= 0 or public.wc_num('hold_request_trip_share') <> 0.5
     or (exists (select 1 from public.ship_classes sc where sc.code = 'barca')
         and public.wc_num('hold_request_speed_kn') <> (select sc.speed_kn from public.ship_classes sc where sc.code = 'barca')) then
    raise exception '0473 self-assert FAIL: the knobs are not this file''s (speed %, share %)', public.wc('hold_request_speed_kn'), public.wc('hold_request_trip_share');
  end if;

  -- ── 6. DARK IS TODAY (rolled back, both switches off): the same board, no hold job from the writer, the week read dark ──
  begin
    update public.world_config set value = 'false'::jsonb where key in ('hold_requests_enabled', 'houses_board_enabled');
    select coalesce(jsonb_agg(e - 'id' - 'from' order by e ->> 'good', e ->> 'expires_day'), '[]'::jsonb) into v_board1 from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e;
    if v_board1 is distinct from v_board0 then
      raise exception '0473 self-assert FAIL: dark, the board of the probe harbour moved: % / %', v_board0, v_board1;
    end if;
    if public.hold_request_post(v_port, now()) <> 0 then
      raise exception '0473 self-assert FAIL: dark, the writer posted';
    end if;
    if world.houses_week() <> '{"on": false}'::jsonb then
      raise exception '0473 self-assert FAIL: dark, the week read served %', world.houses_week();
    end if;
    v_note := format('dark: the board of %s the same (%s requests), no hold job, the week read dark', (select p.code from public.ports p where p.id = v_port), jsonb_array_length(v_board0));
    raise exception sqlstate 'BV473';
  exception when sqlstate 'BV473' then null;
  end;

  -- ── 7. THE PROBE, S4 (rolled back): lit, purses dark, the harbour given room for two more jobs, at the first second of today's game day ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'hold_requests_enabled';
    v_open := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'hold');
    update public.world_config set value = to_jsonb(v_open + 2) where key = 'hold_request_open_max';
    v_ids := array(select t.id from public.trade_contracts t where t.port_id = v_port);
    v_now := public.clock_start('game_day', world.game_day()) + interval '1 second';   -- a whole game day ahead: the reach is not cut by the hour
    if public.hold_request_post(v_port, v_now) <> 1 or public.hold_request_post(v_port, v_now) <> 1 then
      raise exception '0473 self-assert FAIL: lit, the probe harbour did not post two hold jobs within reach';
    end if;
    for c in select * from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' and t.id <> all (v_ids) loop
      v_nm := (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = v_port and sp.id = c.source_port_id);
      v_left := extract(epoch from public.clock_start('game_day', c.expires_day) - v_now);
      if c.source_port_id is null or c.source_port_id = v_port or v_nm is null
         or not exists (select 1 from public.port_specialties s where s.port_id = c.source_port_id and s.good_id = c.good_id)
         or 2 * v_nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression') > public.wc_num('hold_request_trip_share') * v_left + 0.5
         or exists (select 1 from public.port_offered_goods(v_port) o where o.good_id = c.good_id) then
        raise exception '0473 self-assert FAIL: a hold job''s source is not a seller within reach: % (% nm, % s left)', to_jsonb(c), v_nm, v_left;
      end if;
    end loop;
    select e into v_a from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e
     where e ->> 'size' = 'hold' and (e ->> 'id')::uuid <> all (v_ids) limit 1;
    select * into c from public.trade_contracts t where t.id = (v_a ->> 'id')::uuid;
    v_nm := (select (r.reaches ->> sp.code)::numeric from public.sea_reaches r, public.ports sp where r.port_id = v_port and sp.id = c.source_port_id);
    if v_a is null or v_a -> 'from' ->> 'code' is distinct from (select p.code from public.ports p where p.id = c.source_port_id)
       or (v_a -> 'from' ->> 'sail_seconds')::int is distinct from round(v_nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression'))::int
       or (select count(*) from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e where e ->> 'size' = 'city' and e -> 'from' <> 'null'::jsonb) <> 0 then
      raise exception '0473 self-assert FAIL: the read does not serve a hold job''s source (or serves one on a city''s request): %', v_a;
    end if;
    v_note := v_note || format('; lit: 2 hold jobs within reach (%s, buy at %s, %s nm, %s s a Barca); %s open hold jobs backfilled',
                               v_a ->> 'good', v_a -> 'from' ->> 'code', v_a -> 'from' ->> 'nm', v_a -> 'from' ->> 'sail_seconds', v_back);
    raise exception sqlstate 'BV473';
  exception when sqlstate 'BV473' then null;
  end;

  -- ── 8. THE PROBE, S6 (rolled back): lit, a probe company's sale is in its week at once ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
    select n.id into v_nat from public.nations n where n.code = 'PRT';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values ('00000000-0473-4000-8000-0000000000c1', 'Casa Prova 0473', v_nat, 100000, false) returning id into v_me;
    perform cmd.assume_identity('00000000-0473-4000-8000-0000000000c1');
    -- far above any real house, so its place is 1 whatever the board holds
    insert into public.history_company_day (player_id, day, earned, lost) values (v_me, v_week, 3000000000000000, 0)
      on conflict (player_id, day) do update set earned = excluded.earned, lost = excluded.lost;
    perform public.credit(v_me, 'SELL', 1485);
    perform public.credit(v_me, 'BUY', -200);
    select m.ledger_through into v_mark from public.history_mark m;
    -- the two rows count live when they are after the job's mark (they are, unless the mark stands past this transaction's start)
    v_exp := 3000000000000000 + coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and l.created_at > coalesce(v_mark, '-infinity')), 0);
    v_settled := (select count(*) from public.houses_week w where w.week = v_week);
    v_r := world.houses_week();
    if (v_r -> 'you' ->> 'net')::bigint is distinct from v_exp or (v_r -> 'you' ->> 'position')::int <> 1 or not (v_r -> 'you' ->> 'live')::boolean
       or (v_r ->> 'houses')::int <> v_settled + 1
       or (select count(*) from jsonb_array_elements(v_r -> 'board') e where (e ->> 'is_you')::boolean and (e ->> 'net')::bigint = v_exp) <> 1 then
      raise exception '0473 self-assert FAIL: lit, the probe company''s week is not live: % (want % of %)', v_r -> 'you', v_exp, v_settled + 1;
    end if;
    -- settled at a stale figure: the read still serves the live one, once, and counts the company once
    insert into public.houses_week (week, player_id, net) values (v_week, v_me, 5);
    v_r := world.houses_week();
    if (v_r -> 'you' ->> 'net')::bigint is distinct from v_exp or (v_r ->> 'houses')::int <> v_settled + 1
       or (select count(*) from jsonb_array_elements(v_r -> 'board') e where (e ->> 'is_you')::boolean) <> 1 then
      raise exception '0473 self-assert FAIL: lit, a stale settled row shows: %', v_r -> 'you';
    end if;
    v_note := v_note || format('; week: a probe company''s +1,485 / -200 counted live (%s after the mark), #1 of %s', v_exp - 3000000000000000, v_r ->> 'houses');
    raise exception sqlstate 'BV473';
  exception when sqlstate 'BV473' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0473 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0473 self-assert ok: A JOB SAYS WHERE TO BUY, YOUR WEEK LIVE. % hunks once each and reversing; grants and volatility unmoved; no other function moved; the column and 2 knobs (speed %, share %). %; % ms.',
    (select count(*) from hunks_0473), public.wc('hold_request_speed_kn'), public.wc('hold_request_trip_share'), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0473;
end $m$;
