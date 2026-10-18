-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0176 — WHAT YOU HOLD  (COMMAND DESK slice D6: your shares in every city, in one read)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"… setting up trade routes for my fleet, investing, and all"*. docs/COMMAND_DESK.md §3.7,
-- §7.5, §10 row D6. The Invest face lists what the company holds in EVERY city; world.town_hall(port) answers one
-- city at a time (its `you.holdings`), so a list of N cities would be N reads.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- world.holdings() — NEW, the client's read (registered; authenticated only). For the caller's company:
--   rows    one per (city, work) held — the share register's own row (public.city_shares: shares, paid, owed =
--           accrued coupons the city has set aside), the work's level, and the price of a share there now through
--           public.works_share_price — the leaf world.town_hall prints (null at the top level, as there);
--   held    Σ paid; owed Σ accrued;
--   paid    the dividends the company has collected (ledger kind DIVIDEND, public.ledger — the record) in the
--           current game day and in the last full one (world.game_day, the calendar's one reading);
--   enabled whether city purses are on (public.city_treasury_on), as world.town_hall says.
-- Nothing is re-derived: a share's price is the town hall's leaf, the money is the register's and the ledger's.
--
-- ── THE PROOF (own probe company, rolled back) ──────────────────────────────────────────────────
-- A company with no shares reads an empty list and zero totals; given two rows in the register (Lisbon docks,
-- Cádiz market) and a dividend in the ledger, it reads exactly those rows — shares, paid, owed, level, and the
-- share price = works_share_price(level) — the totals are their sums, and today's dividends the credited amount;
-- the read matches world.town_hall's `you.holdings` city by city. Registry +1 (authenticated, not anon); walls.
-- ROLLBACK: drop the function and reverse the registry's hunk.
-- VERSION: 0176 PROVISIONAL — prod head 0175 when written (2026-10-18).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0176(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0176 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       to_regprocedure('world.holdings()') is not null as already,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as acl;

do $$
begin
  if (select already from before_0176) then
    raise exception '0176 self-assert FAIL: world.holdings already exists';
  end if;
end $$;

-- ── 1. THE READ ───────────────────────────────────────────────────────────────────────────────
create or replace function world.holdings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0176: WHAT YOU HOLD, in every city (docs/COMMAND_DESK.md §3.7, §7.5). The register's rows (public.city_shares),
-- the work's level (public.city_works), a share's price there now (public.works_share_price — world.town_hall's
-- leaf), and the dividends collected (public.ledger, kind DIVIDEND) today and in the last full game day
-- (world.game_day). Reads; writes nothing.
declare
  v_player uuid := public.current_player_id();
  v_today  int := world.game_day();
  v_max    int := public.wc_int('works_level_max');
  v_rows   jsonb;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'port', p.code, 'name', p.name, 'kind', s.kind,
           'shares', s.shares, 'paid', s.paid, 'owed', s.accrued,
           'level', coalesce(w.level, 0), 'level_max', v_max,
           'share_price', case when coalesce(w.level, 0) < v_max then public.works_share_price(coalesce(w.level, 0)) end)
           order by s.paid desc, p.name, s.kind), '[]'::jsonb)
    into v_rows
    from public.city_shares s
    join public.ports p on p.id = s.port_id
    left join public.city_works w on w.port_id = s.port_id and w.kind = s.kind
   where s.player_id = v_player;

  return jsonb_build_object(
    'enabled', public.city_treasury_on(),
    'rows', v_rows,
    'held', (select coalesce(sum(s.paid), 0) from public.city_shares s where s.player_id = v_player),
    'owed', (select coalesce(sum(s.accrued), 0) from public.city_shares s where s.player_id = v_player),
    'paid', (select jsonb_build_object(
                'today', coalesce(sum(l.ducats_delta) filter (where world.game_day(l.created_at) = v_today), 0),
                'yesterday', coalesce(sum(l.ducats_delta) filter (where world.game_day(l.created_at) = v_today - 1), 0))
               from public.ledger l
              where l.player_id = v_player and l.kind = 'DIVIDEND'
                and l.created_at > now() - interval '1 day'),
    'game_day', v_today);
end $$;

revoke all on function world.holdings() from public, anon, authenticated;
grant execute on function world.holdings() to authenticated;

-- ── 2. THE REGISTRY (one hunk, sliced from the live body; reverses; ACL unchanged) ────────────
do $$
declare
  b     record;
  v_old text := $h$      ('cmd',         'issue_lines',           'uuid, jsonb, int')
$h$;
  v_new text := $h$      ('cmd',         'issue_lines',           'uuid, jsonb, int'),
      -- 0176: your shares in every city (docs/COMMAND_DESK.md §3.7, D6).
      ('world',       'holdings',              '')
$h$;
  v_rev text;
begin
  select * into b from before_0176;
  if pg_temp.occurs_0176(b.def, v_old) <> 1 then
    raise exception '0176 self-assert FAIL: the registry''s last row occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0176(b.def, v_old);
  end if;
  execute replace(b.def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0176(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.def then
    raise exception '0176 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.acl then
    raise exception '0176 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 3. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0176-4000-8000-000000000001';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_p    uuid;
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_cad  uuid := (select id from public.ports where code = 'CAD');
  v_h    jsonb;
  v_out  jsonb;
  v_bad  int;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa dos Haveres 0176', 'PRT', 'LIS');
    perform cmd.assume_identity(c_uid);
    v_h := world.holdings();
    if jsonb_array_length(v_h->'rows') <> 0 or (v_h->>'held')::bigint <> 0 or (v_h->>'owed')::bigint <> 0
       or (v_h->'paid'->>'today')::bigint <> 0 then
      raise exception '0176 self-assert FAIL: a company with no shares does not read empty: %', v_h;
    end if;
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
      (v_lis, 'docks', v_p, 3, 600, 17, world.game_day()),
      (v_cad, 'market', v_p, 1, 200, 0, world.game_day());
    perform public.credit(v_p, 'DIVIDEND', 123);
    v_h := world.holdings();
    if jsonb_array_length(v_h->'rows') <> 2 or (v_h->>'held')::bigint <> 800 or (v_h->>'owed')::bigint <> 17
       or (v_h->'paid'->>'today')::bigint <> 123 then
      raise exception '0176 self-assert FAIL: the holdings are not the register''s rows and the ledger''s dividend: %', v_h;
    end if;
    select count(*) into v_bad
      from jsonb_array_elements(v_h->'rows') r
      join public.city_shares s on s.player_id = v_p and s.kind = r->>'kind'
                               and s.port_id = (select id from public.ports where code = r->>'port')
      left join public.city_works w on w.port_id = s.port_id and w.kind = s.kind
     where (r->>'shares')::int <> s.shares or (r->>'paid')::bigint <> s.paid or (r->>'owed')::bigint <> s.accrued
        or (r->>'level')::int <> coalesce(w.level, 0)
        or (r->'share_price') is distinct from
           case when coalesce(w.level, 0) < public.wc_int('works_level_max')
                then to_jsonb(public.works_share_price(coalesce(w.level, 0))) else 'null'::jsonb end;
    if v_bad > 0 then
      raise exception '0176 self-assert FAIL: % holding row(s) differ from the register or the town hall''s share price', v_bad;
    end if;
    -- the same as world.town_hall's own `you.holdings`, city by city
    if (select jsonb_agg(jsonb_build_object('kind', r->>'kind', 'shares', (r->>'shares')::int, 'paid', (r->>'paid')::bigint, 'owed', (r->>'owed')::bigint) order by r->>'kind')
          from jsonb_array_elements(v_h->'rows') r where r->>'port' = 'LIS')
       is distinct from (select jsonb_agg(jsonb_build_object('kind', x->>'kind', 'shares', (x->>'shares')::int, 'paid', (x->>'paid')::bigint, 'owed', (x->>'owed')::bigint) order by x->>'kind')
          from jsonb_array_elements(world.town_hall(v_lis)->'you'->'holdings') x) then
      raise exception '0176 self-assert FAIL: the holdings at Lisbon differ from world.town_hall''s';
    end if;
    raise exception using errcode = 'ZX176', message = v_h::text;
  exception when sqlstate 'ZX176' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0176 self-assert FAIL: the probe company survived its rollback';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0176) + 1
     or not has_function_privilege('authenticated', 'world.holdings()', 'execute')
     or has_function_privilege('anon', 'world.holdings()', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0176 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;
  raise notice '0176 self-assert ok: WHAT YOU HOLD. world.holdings (registered; authenticated only): an empty company reads empty; two register rows read back exactly (shares, paid, owed, level, share price = works_share_price), held % / owed %, today''s dividends % from the ledger; Lisbon''s rows equal world.town_hall''s. Registry +1, reverses to its pre-image.',
    v_out->>'held', v_out->>'owed', v_out->'paid'->>'today';
end $$;
