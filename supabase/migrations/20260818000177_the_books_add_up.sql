-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0177 — THE BOOKS ADD UP  (COMMAND DESK slice D7: the running profit, day by day, from the record)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"… for max profit"*. docs/COMMAND_DESK.md §3.8, §7.5, §10 row D7. The Profit face prints
-- what the company made — today, and day by day — and the record of every coin is the ledger (public.ledger,
-- append-only since 0004; the purse is its sum). Nothing new is stored: the books are DERIVED per read (the 0014
-- rule — a counter can drift from the record it counts).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- world.books(days) — NEW, the client's read (registered; authenticated only). For the caller's company, the last
-- `days` game days (default 7, at most 30; world.game_day is the calendar), newest first: per day the ledger summed
-- by kind, each kind under its ONE player word (mapped here, once: Sold · Bought · Supplies · Wages · Repairs ·
-- Profit tax · Invested · Dividends · Hired · Tuition · Donations · Tows; any other kind under its own name, so
-- nothing is dropped), and the day's net = the sum of every line. The starting money (FOUNDING) is capital, not profit:
-- it is left out (a new company's first day read "+8,000" on the first local drive). Plus the head figures: today's net and the
-- window's. The ledger is read through its (player_id, created_at) index over a coarse time bound, then cut to
-- whole game days by world.game_day. Per fleet is not here: the ledger names no fleet (world.fleet_trades does,
-- lap by lap).
--
-- ── THE PROOF (own probe company, rolled back) ──────────────────────────────────────────────────
-- A fresh company's today is nothing (its starting money is capital); then a sale (+500), a purchase (−200) and wages (−30) through
-- public.credit — the one money mover: today's net moves by exactly the purse's change (+270), each under its word;
-- the window's net is the sum of its days; `days` is capped at 30 and floored at 1. Registry +1 (authenticated, not
-- anon); walls.
-- ROLLBACK: drop the function and reverse the registry's hunk.
-- VERSION: 0177 PROVISIONAL — prod head 0176 when written (2026-10-18).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0177(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0177 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       to_regprocedure('world.books(integer)') is not null as already,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as acl;

do $$
begin
  if (select already from before_0177) then
    raise exception '0177 self-assert FAIL: world.books already exists';
  end if;
end $$;

-- ── 1. THE READ ───────────────────────────────────────────────────────────────────────────────
create or replace function world.books(p_days int default 7)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0177: THE BOOKS (docs/COMMAND_DESK.md §3.8, §7.5) — the caller's ledger, by game day and kind, each kind under its
-- one player word, the day's net the sum of its lines. Derived per read; writes nothing.
declare
  v_player uuid := public.current_player_id();
  v_days   int := least(greatest(coalesce(p_days, 7), 1), 30);
  v_today  int := world.game_day();
  v_out    jsonb;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  with words(kind, word, ord) as (values
    ('SELL', 'Sold', 1), ('BUY', 'Bought', 2), ('PROVISION', 'Supplies', 3), ('WAGES', 'Wages', 4),
    ('REPAIR', 'Repairs', 5), ('TAX', 'Profit tax', 6), ('SHARE', 'Invested', 7), ('DIVIDEND', 'Dividends', 8),
    ('HIRE', 'Hired', 9), ('TUITION', 'Tuition', 10), ('DONATION', 'Donations', 11), ('TOW', 'Tows', 12)
  ), lines as (
    select world.game_day(l.created_at) as day, l.kind, sum(l.ducats_delta) as ducats
      from public.ledger l
     where l.player_id = v_player
       and l.kind <> 'FOUNDING'   -- a company's starting money is its capital, not something it made
       and l.created_at > now() - make_interval(secs => ((v_days + 1) * public.wc_num('game_day_seconds'))::double precision)
     group by 1, 2
  ), kept as (
    select * from lines where day > v_today - v_days
  ), days as (
    select d.day,
           jsonb_agg(jsonb_build_object('kind', d.kind, 'word', coalesce(w.word, initcap(lower(d.kind))), 'ducats', d.ducats)
                     order by coalesce(w.ord, 99), d.kind) as lines,
           sum(d.ducats) as net
      from kept d left join words w on w.kind = d.kind
     group by d.day
  )
  select jsonb_build_object(
           'game_day', v_today,
           'days', v_days,
           'today', coalesce((select net from days where day = v_today), 0),
           'window', coalesce((select sum(net) from days), 0),
           'books', coalesce((select jsonb_agg(jsonb_build_object('game_day', day, 'net', net, 'lines', lines) order by day desc) from days), '[]'::jsonb))
    into v_out;
  return v_out;
end $$;

revoke all on function world.books(int) from public, anon, authenticated;
grant execute on function world.books(int) to authenticated;

-- ── 2. THE REGISTRY (one hunk, sliced from the live body; reverses; ACL unchanged) ────────────
do $$
declare
  b     record;
  v_old text := $h$      ('world',       'holdings',              '')
$h$;
  v_new text := $h$      ('world',       'holdings',              ''),
      -- 0177: the books — the ledger by game day and kind (docs/COMMAND_DESK.md §3.8, D7).
      ('world',       'books',                 'int')
$h$;
  v_rev text;
begin
  select * into b from before_0177;
  if pg_temp.occurs_0177(b.def, v_old) <> 1 then
    raise exception '0177 self-assert FAIL: the registry''s last row occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0177(b.def, v_old);
  end if;
  execute replace(b.def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0177(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.def then
    raise exception '0177 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.acl then
    raise exception '0177 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 3. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0177-4000-8000-000000000001';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_p    uuid;
  v_b0   jsonb;
  v_b1   jsonb;
  v_d0   bigint;
  v_d1   bigint;
  v_out  jsonb;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa dos Livros 0177', 'PRT', 'LIS');
    perform cmd.assume_identity(c_uid);
    v_b0 := world.books();
    v_d0 := (select ducats from public.players where id = v_p);
    perform public.credit(v_p, 'SELL', 500);
    perform public.credit(v_p, 'BUY', -200);
    perform public.credit(v_p, 'WAGES', -30);
    v_b1 := world.books();
    v_d1 := (select ducats from public.players where id = v_p);
    if (v_b1->>'today')::bigint - (v_b0->>'today')::bigint <> v_d1 - v_d0 or v_d1 - v_d0 <> 270 then
      raise exception '0177 self-assert FAIL: today''s net moved by %, the purse by %', (v_b1->>'today')::bigint - (v_b0->>'today')::bigint, v_d1 - v_d0;
    end if;
    if (v_b0->>'today')::bigint <> 0 then
      raise exception '0177 self-assert FAIL: a new company''s starting money was counted as profit: %', v_b0;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_b1->'books'->0->'lines') x where x->>'word' = 'Sold' and (x->>'ducats')::bigint = 500)
       or not exists (select 1 from jsonb_array_elements(v_b1->'books'->0->'lines') x where x->>'word' = 'Bought' and (x->>'ducats')::bigint = -200)
       or not exists (select 1 from jsonb_array_elements(v_b1->'books'->0->'lines') x where x->>'word' = 'Wages' and (x->>'ducats')::bigint = -30) then
      raise exception '0177 self-assert FAIL: the day''s lines are not under their words: %', v_b1->'books'->0;
    end if;
    if (v_b1->>'window')::bigint <> (select sum((d->>'net')::bigint) from jsonb_array_elements(v_b1->'books') d)
       or (v_b1->'books'->0->>'net')::bigint <> (select sum((x->>'ducats')::bigint) from jsonb_array_elements(v_b1->'books'->0->'lines') x) then
      raise exception '0177 self-assert FAIL: a net is not the sum of its lines';
    end if;
    if (world.books(1000)->>'days')::int <> 30 or (world.books(0)->>'days')::int <> 1 then
      raise exception '0177 self-assert FAIL: the window is not held to 1..30 days';
    end if;
    raise exception using errcode = 'ZX177', message = v_b1::text;
  exception when sqlstate 'ZX177' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0177 self-assert FAIL: the probe company survived its rollback';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0177) + 1
     or not has_function_privilege('authenticated', 'world.books(integer)', 'execute')
     or has_function_privilege('anon', 'world.books(integer)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0177 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;
  raise notice '0177 self-assert ok: THE BOOKS ADD UP. world.books (registered; authenticated only): a sale, a purchase and wages through public.credit moved today''s net by exactly the purse''s change (+270), each under its word; every net is the sum of its lines; the window is held to 1..30 days. Today % / window %. Registry +1, reverses to its pre-image.',
    v_out->>'today', v_out->>'window';
end $$;
