-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0235 — EVERY COIN THAT MOVES IS TOLD
--        (ONE read lists the world's money moves, newest first: who, what for, how much, gained or lost —
--         the Stats tab's live log beside World money)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 219, 2026-10-26) ────────────────────────────
--   "beside the stat, world money, i want to see the live log of each happenings that cause money - drop and
--    gain, at the right side. possible?"
--
-- ── WHAT EXISTS (docs/dev-log/2026-10-26-money-feed.md) ─────────────────────────────────────────
--   Money moves in exactly two books, each with ONE writer (prod 2026-10-26: the only bodies that insert into
--   them are public.credit and public.treasury_post; npc_compact folds a merchant's old rows into NPC_CARRIED):
--   * public.ledger (0004): a company's purse — players' and merchants' alike (players.is_npc). Every kind:
--     SELL, BUY, TAX, WAGES, PROVISION, INSURANCE, DIVIDEND, FOUNDING, CAPITAL_GIFT (0234) …
--   * public.treasury_flows (0122): a city's purse — the other end of a company's move (a sale is SELL +x on
--     the company and SELL −x on the city) and the city's own (EARNINGS, IMPORT_DEMAND, WORKS_IN / OUT,
--     CROWN_AID / CROWN_TAX, CROWN_CALL (0234)). tick_city rolls them into the daybook hourly (:37).
--   The words and sides of every kind are public.stats_flow_words (0214; re-sided by 0228).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   1. ONE READ, world.money_feed(p_after timestamptz default null, p_limit int default 50): the moves of both
--      books written after p_after (null = no bound), newest first, at most p_limit (1…200). Each row:
--      key ('L' + ledger id / 'F' + flow id — the client's dedupe key), at, who (a company's name — players'
--      and merchants' by name, the owner's rule since 0227 — or a city's name), holder (company / merchant /
--      city), own (the caller's), kind, word (stats_flow_words.word, else the kind), side (minted / moved /
--      removed, stats_flow_words; null for a kind it does not name), delta (signed, the holder's purse).
--      DECIDED BY DEFAULT: both ends of a move are TWO rows ("Casa X −1,200 · Bought" and "Lisbon +1,200 ·
--      Sold"): each row is one purse's gain or loss, which is what the owner asked to see, and the books
--      already keep them apart. A zero move and NPC_CARRIED (a compaction's carried balance, not a move) are
--      not rows. No purse, no fleet, no position.
--   2. ONE INDEX, treasury_flows (created_at): the read's newest-first scan. Measured on prod read-only
--      2026-10-26: the flows half is a seq scan + top-N sort of the whole table — 3,421–3,512 rows ten minutes
--      after the :37 roll (2.6–12.8 ms of an 8.6–23 ms read), 11,249–11,376 rows thirty-five minutes after it
--      (6–15 ms of a 17.6–35.9 ms read, the first, unbounded ask); before the next roll the table holds about an
--      hour (~22,000 rows), so that half doubles again. The table is 3.2 MB (10,838 rows at 05:11 UTC); a plain
--      build (a migration is one transaction; no CONCURRENTLY) reads that once and holds treasury_post inserts
--      for milliseconds.
--      The ledger half already rides ledger_created_at (an index-backward scan, 0.1 ms).
--   3. The registry (client_rpc_entry_points) gains the read: one hunk, sliced from the live body.
--
-- ── RE-CUTS (each hunk occurs once in the live body, each reverses; ACL / volatility / definer /
--    config asserted unmoved) ────────────────────────────────────────────────────────────────────
--   * public.client_rpc_entry_points() — 1 hunk: + ('world', 'money_feed', 'timestamptz, int').
--
-- ── WHAT IT SELF-ASSERTS (own probe rows only; the probe is rolled back whole; nothing is deleted) ─
--   (a) the re-cut reverses to its pre-image; nothing else about it moved.
--   (b) the registry is the old one + 1, every row executable by authenticated; anon cannot run the read;
--       it is stable, security definer, with its search_path; the walls are 0; the index exists and is valid.
--   (c) POSITIVE CONTROL: a probe company founded at Lisbon buys 1 of a good through cmd.do_buy. Read as the
--       probe with p_after just before this transaction's now(): EVERY ledger row of the probe and EVERY flow
--       row naming the probe (non-zero) is a row of the feed, with its delta, its kind, its word and side from
--       stats_flow_words, the probe's own as `own` company rows and the city's as Lisbon's; among them a BUY
--       of the probe < 0 and a BUY of Lisbon > 0 (the city purses lit inside the probe where a chain has them
--       dark — prod's are on; rolled back with it). Only those rows are counted.
--       NEGATIVE CONTROLS: p_after a day ahead → no rows; limit 1 → one row; the list is newest first.
--       Timings ×6, notice only.
--   (d) nothing of the probe survives.
--
-- Depends on: 0004 (ledger, players), 0018 (current_player_id, the registry), 0122 (treasury_flows, ports),
-- 0214 / 0228 (stats_flow_words), 0227 (the registry as it stands, the probe idiom).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.occurs_0235(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE of the body this file re-cuts (LF-normalised), with its ACL / volatility /
--       definer / config ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0235 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0235 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE INDEX — a city's moves, newest first ─────────────────────────────────────────────────
create index treasury_flows_created_at on public.treasury_flows (created_at);
comment on index public.treasury_flows_created_at is
  '0235: world.money_feed — the cities'' money moves, newest first.';

-- ── 2. THE READ ─────────────────────────────────────────────────────────────────────────────────
create function world.money_feed(p_after timestamptz default null, p_limit int default 50)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0235 (owner row 219): the live log of every money move — both books, newest first. Reads; decides nothing.
-- Each half takes its own newest `n` (an index-backward scan each), the union keeps the newest `n` of both.
-- The key is the row's book + id; with `at` it orders the list the same way on every ask ("C" collation).
with a as (select least(greatest(coalesce(p_limit, 50), 1), 200) as n, public.current_player_id() as me),
l as (select ('L' || l.id::text) collate "C" as key, l.created_at as at, l.player_id, null::uuid as port_id,
             l.kind, l.ducats_delta as delta
        from public.ledger l
       where (p_after is null or l.created_at > p_after)
         and l.ducats_delta <> 0 and l.kind <> 'NPC_CARRIED'
       order by l.created_at desc, l.id desc
       limit (select n from a)),
f as (select ('F' || f.id::text) collate "C" as key, f.created_at as at, null::uuid as player_id, f.port_id,
             f.kind, f.ducats as delta
        from public.treasury_flows f
       where (p_after is null or f.created_at > p_after)
         and f.ducats <> 0
       order by f.created_at desc, f.id desc
       limit (select n from a)),
m as (select * from l union all select * from f order by at desc, key desc limit (select n from a))
select jsonb_build_object(
         'now', now(),
         'moves', coalesce(jsonb_agg(jsonb_build_object(
             'key',    m.key,
             'at',     m.at,
             'who',    case when m.port_id is not null then po.name else pl.company_name end,
             'holder', case when m.port_id is not null then 'city' when pl.is_npc then 'merchant' else 'company' end,
             'own',    coalesce(m.player_id = (select me from a), false),
             'kind',   m.kind,
             'word',   coalesce(w.word, m.kind),
             'side',   w.side,
             'delta',  m.delta)
           order by m.at desc, m.key desc), '[]'::jsonb))
  from m
  left join public.players pl on pl.id = m.player_id
  left join public.ports po on po.id = m.port_id
  left join public.stats_flow_words w on w.kind = m.kind
$$;
comment on function world.money_feed(timestamptz, int) is
  '0235: every money move of both books (ledger, treasury_flows) after p_after, newest first, ≤ p_limit (1…200): who (company or city, by name), holder, own, kind, word and side (stats_flow_words), signed delta. Both ends of a move are two rows (owner row 219).';
revoke all on function world.money_feed(timestamptz, int) from public, anon, authenticated;
grant execute on function world.money_feed(timestamptz, int) to authenticated;

-- ── 3. THE RE-CUT (a hunk sliced from the live body; occurs once; reverses) ─────────────────────
create temp table hunks_0235 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0235 values
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'city_good_trades',      'uuid, uuid, int')
    ) as t(s, f, a)$h$,
$h$      ('world',       'city_good_trades',      'uuid, uuid, int'),
      -- 0235: the live log of every money move, beside World money (owner row 219).
      ('world',       'money_feed',            'timestamptz, int')
    ) as t(s, f, a)$h$);

create or replace function pg_temp.recut_0235(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0235 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0235 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0235(v_def, h.old);
    if v_n <> 1 then
      raise exception '0235 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0235(fn) from defs_before_0235 order by fn;

-- ── 4. THE SELF-ASSERT (own probe rows; the probe is rolled back whole) ─────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0235-4000-8000-000000000001';
  c_name   constant text := 'Casa do Livro 0235';
  v_d      record; v_h record; v_pp record; v_def text;
  v_before record;
  v_p      uuid; v_f uuid; v_g uuid; v_port uuid; v_lis text;
  v_r      jsonb; v_moves jsonb; v_x jsonb; v_row jsonb;
  v_prev   timestamptz;
  v_after  timestamptz;
  v_want   int := 0; v_got int := 0;
  v_buy_me bigint; v_buy_city bigint;
  v_t      timestamptz;
  v_ms     numeric[] := '{}';
  v_out    jsonb;
  i        int;
begin
  select * into v_before from before_0235;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0235 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0235 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0235(v_def, v_h.new) <> 1 then
        raise exception '0235 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0235 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0235 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;

  -- (b) THE REGISTRY, THE GRANTS, THE WALLS, THE INDEX
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points + 1
     or not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'money_feed' and e.fn = 'world.money_feed(timestamptz, int)'::regprocedure)
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0235 self-assert FAIL: the registry is not the old one + money_feed, every row executable by authenticated';
  end if;
  select p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg into v_pp
    from pg_proc p where p.oid = 'world.money_feed(timestamptz, int)'::regprocedure;
  if has_function_privilege('anon', 'world.money_feed(timestamptz, int)', 'execute')
     or v_pp.vol <> 's' or not v_pp.secdef or v_pp.cfg not like '%search_path=public, pg_temp%' then
    raise exception '0235 self-assert FAIL: anon can run the read, or it is not stable / security definer / pinned: % % %', v_pp.vol, v_pp.secdef, v_pp.cfg;
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0235 self-assert FAIL: a wall moved';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('public.treasury_flows_created_at') and i.indisvalid) then
    raise exception '0235 self-assert FAIL: the index treasury_flows_created_at is missing or not valid';
  end if;

  -- (c) THE PROBE, rolled back whole
  begin
    if exists (select 1 from public.players p where p.auth_uid = c_uid) then
      raise exception '0235 self-assert FAIL: the probe house already exists';
    end if;
    v_p := public.new_house(c_uid, c_name, 'PRT', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p order by f.id limit 1;
    select pg.port_id, pg.good_id, p.name into v_port, v_g, v_lis
      from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
     where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
       and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
     order by g.code limit 1;
    if v_g is null or v_f is null then
      raise exception '0235 self-assert FAIL: no probe fleet, or Lisbon offers no good with stock over 50';
    end if;

    -- the city purses on for the probe (prod: on since its switch; a fresh chain: dark) — rolled back with it
    if not public.city_treasury_on() then
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    end if;
    if not public.city_treasury_on() then
      raise exception '0235 self-assert FAIL: the city purses could not be lit for the probe';
    end if;

    -- THE POSITIVE CONTROL: she buys one
    perform cmd.do_buy(v_f, jsonb_build_object('good', v_g, 'qty', 1));
    select sum(l.ducats_delta) into v_buy_me from public.ledger l where l.player_id = v_p and l.kind = 'BUY';
    select sum(f.ducats) into v_buy_city from public.treasury_flows f where f.player_id = v_p and f.kind = 'BUY' and f.port_id = v_port;
    if coalesce(v_buy_me, 0) >= 0 or coalesce(v_buy_city, 0) <= 0 then
      raise exception '0235 self-assert FAIL: the probe''s buy wrote no BUY < 0 in her ledger (%) or no BUY > 0 in Lisbon''s flows (%)', v_buy_me, v_buy_city;
    end if;

    -- read as the probe, everything after just before this transaction's instant (the probe's rows are at now())
    perform cmd.assume_identity(c_uid);
    v_after := now() - interval '1 microsecond';
    v_r := world.money_feed(v_after, 200);
    v_moves := v_r->'moves';

    -- every ledger row of the probe is a row: her company, own, its delta, kind, word and side
    for v_x in
      select jsonb_build_object('key', 'L' || l.id::text, 'kind', l.kind, 'delta', l.ducats_delta,
                                'word', coalesce(w.word, l.kind), 'side', w.side)
        from public.ledger l left join public.stats_flow_words w on w.kind = l.kind
       where l.player_id = v_p and l.ducats_delta <> 0
    loop
      v_want := v_want + 1;
      select x into v_row from jsonb_array_elements(v_moves) x where x->>'key' = v_x->>'key';
      if v_row is null or v_row->>'who' <> c_name or v_row->>'holder' <> 'company' or not (v_row->>'own')::boolean
         or (v_row->>'delta')::bigint <> (v_x->>'delta')::bigint or v_row->>'kind' <> v_x->>'kind'
         or v_row->>'word' <> v_x->>'word' or (v_row->>'side') is distinct from (v_x->>'side') then
        raise exception '0235 self-assert FAIL: the probe''s ledger row % is not served as hers: %', v_x, v_row;
      end if;
      v_got := v_got + 1;
    end loop;
    -- every flow row naming the probe is a row: the city's name, not own, its delta, kind, word and side
    for v_x in
      select jsonb_build_object('key', 'F' || f.id::text, 'kind', f.kind, 'delta', f.ducats, 'city', p.name,
                                'word', coalesce(w.word, f.kind), 'side', w.side)
        from public.treasury_flows f join public.ports p on p.id = f.port_id
        left join public.stats_flow_words w on w.kind = f.kind
       where f.player_id = v_p and f.ducats <> 0
    loop
      v_want := v_want + 1;
      select x into v_row from jsonb_array_elements(v_moves) x where x->>'key' = v_x->>'key';
      if v_row is null or v_row->>'who' <> v_x->>'city' or v_row->>'holder' <> 'city' or (v_row->>'own')::boolean
         or (v_row->>'delta')::bigint <> (v_x->>'delta')::bigint or v_row->>'kind' <> v_x->>'kind'
         or v_row->>'word' <> v_x->>'word' or (v_row->>'side') is distinct from (v_x->>'side') then
        raise exception '0235 self-assert FAIL: the probe''s flow row % is not served as the city''s: %', v_x, v_row;
      end if;
      v_got := v_got + 1;
    end loop;
    -- among them: her BUY < 0, and (purses on) Lisbon's BUY > 0
    if not exists (select 1 from jsonb_array_elements(v_moves) x
                    where x->>'who' = c_name and x->>'kind' = 'BUY' and (x->>'delta')::bigint = v_buy_me)
       or not exists (select 1 from jsonb_array_elements(v_moves) x
                    where x->>'holder' = 'city' and x->>'who' = v_lis and x->>'kind' = 'BUY' and (x->>'delta')::bigint = v_buy_city
                      and (x->>'at')::timestamptz = now()) then
      raise exception '0235 self-assert FAIL: the feed does not carry the probe''s buy (%) and Lisbon''s side of it (%)', v_buy_me, v_buy_city;
    end if;

    -- newest first, on (at, key)
    v_prev := null;
    for v_x in select x from jsonb_array_elements(v_moves) x loop
      if v_prev is not null and (v_x->>'at')::timestamptz > v_prev then
        raise exception '0235 self-assert FAIL: the list is not newest first: %', v_moves;
      end if;
      v_prev := (v_x->>'at')::timestamptz;
    end loop;
    -- NEGATIVE CONTROLS: a day ahead → nothing; limit 1 → one row
    if jsonb_array_length(world.money_feed(now() + interval '1 day', 50)->'moves') <> 0 then
      raise exception '0235 self-assert FAIL: a bound a day ahead still served rows';
    end if;
    if jsonb_array_length(world.money_feed(v_after, 1)->'moves') <> 1 then
      raise exception '0235 self-assert FAIL: limit 1 did not give one row';
    end if;

    for i in 1..6 loop
      v_t := clock_timestamp();
      perform world.money_feed(null, 100);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;

    raise exception using errcode = 'ZX235', message = jsonb_build_object(
      'want', v_want, 'got', v_got, 'buy_me', v_buy_me, 'buy_city', v_buy_city, 'ms', to_jsonb(v_ms))::text;
  exception when sqlstate 'ZX235' then
    v_out := sqlerrm::jsonb;
  end;

  -- (d) nothing of the probe survives
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0235 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0235 self-assert ok: EVERY COIN THAT MOVES IS TOLD. The registry re-cut by one hunk, reversed; registry +1; anon refused; stable, definer, pinned; walls 0; index valid. Probe at Lisbon bought 1: her BUY %, Lisbon''s BUY %; % of % probe rows served, each with its holder, delta, word and side; newest first; a day ahead → 0 rows; limit 1 → 1 row. world.money_feed(null, 100) × 6 = % ms. Rolled back.',
    v_out->>'buy_me', v_out->>'buy_city', v_out->>'got', v_out->>'want', v_out->'ms';
end $$;
