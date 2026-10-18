-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0174 — SEVERAL ORDERS ARE ONE  (COMMAND DESK slice D4: a plan is queued whole, or not at all)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"buy and sell plans … setting up trade routes for my fleet"*. docs/COMMAND_DESK.md
-- §3.5 and §7.4: the plan builder's "Queue it once" — `SAIL Mocha · BUY coffee 60 AT <= 95 · SAIL Lisbon ·
-- SELL coffee ALL AT >= 140` — must land as ONE act. Four cmd.issue calls would leave half a plan in the
-- queue whenever the third is refused (a typo, a full queue), and a fleet that sails to buy and never
-- sells is the worse outcome than no plan.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- cmd.issue_lines(fleet, lines, expected_version) — NEW, the client's verb (registered; authenticated
-- only). `lines` is [{text, path}] — each a line of the one grammar, a SAIL with the course the chart
-- proposed. It does what cmd.issue does, for all of them at once:
--   * the fleet is the caller's (E_NO_SUCH_FLEET), the version is the fleet's (E_STALE), the fleet is
--     settled first (voyage.settle — DESIGN D.2, as cmd.issue);
--   * EVERY line is parsed by cmd.parse — the one grammar — before ANY is queued; a refusal names the
--     line (`Line 3 (SELL cofee ALL): …`, `line`: 3). A line may not name another fleet, nor be a queue
--     act (CANCEL / CLEAR — they act on the queue, not in it);
--   * the queue's room is checked for the whole plan (E_QUEUE_FULL with the count), then every line is
--     queued through cmd.enqueue — the one enqueuer (0092) — inside one sub-transaction: a refusal from
--     any of them takes all of them back;
--   * cmd.advance once at the end — a docked fleet starts on the first line at once, exactly as it would
--     after N cmd.issue calls.
-- No executor, no grammar, no second enqueuer: it composes the three that exist. No switch: it can do only
-- what N cmd.issue calls already can.
--
-- ── THE PROOF (own probe company at Lisbon, rolled back) ────────────────────────────────────────
-- (a) four lines queue together, in order, each row's verb and args exactly cmd.parse's for its text (the
--     SAIL's carrying its path), the version bumped once a line; (b) a bad third line queues none and is
--     named; (c) a plan larger than the queue's room refuses whole (E_QUEUE_FULL); (d) another company's
--     fleet → E_NO_SUCH_FLEET, a stale version → E_STALE, a CLEAR line and an empty plan refused; (e) a
--     docked fleet's first line runs (cmd.advance), as after cmd.issue; (f) registry +1 (authenticated,
--     not anon); the walls.
-- ROLLBACK: drop the function and reverse the registry's hunk.
-- VERSION: 0174 PROVISIONAL — prod head 0173 when written (2026-10-18). Every pre-image is read live.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0174(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0174 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       to_regprocedure('cmd.issue_lines(uuid, jsonb, integer)') is not null as already,
       replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure) as acl;

do $$
begin
  if (select already from before_0174) then
    raise exception '0174 self-assert FAIL: cmd.issue_lines already exists';
  end if;
end $$;

-- ── 1. THE VERB ───────────────────────────────────────────────────────────────────────────────
create or replace function cmd.issue_lines(p_fleet uuid, p_lines jsonb, p_expected_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0174: SEVERAL ORDERS AS ONE (docs/COMMAND_DESK.md §7.4). Every line parsed (cmd.parse) before any is
-- queued; every line queued (cmd.enqueue, the one enqueuer) or none; cmd.advance once. The refusal shape
-- is cmd.issue's, plus `line` — the 1-based line that refused.
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_n      int;
  v_parsed jsonb[] := '{}';
  v_line   jsonb;
  v_text   text;
  v_p      jsonb;
  v_ref    jsonb;
  v_msg    text;
  v_det    text;
  v_depth  int;
  v_res    jsonb;
  v_ids    uuid[] := '{}';
  v_fail   jsonb;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id <> v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
                              'error_message', 'A plan needs at least one line.', 'fixes', '[]'::jsonb);
  end if;
  if p_expected_version is not null and p_expected_version <> f.version then
    return jsonb_build_object('ok', false, 'error_code', 'E_STALE',
      'error_message', format('This fleet has moved on since you looked (you have version %s, it is at %s).',
                              p_expected_version, f.version),
      'fixes', cmd.fixes('E_STALE', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;

  perform voyage.settle(p_fleet);
  v_n := jsonb_array_length(p_lines);

  -- EVERY LINE PARSED FIRST, by the one grammar; the first refusal names its line
  for i in 1 .. v_n loop
    v_line := p_lines->(i - 1);
    v_text := coalesce(v_line->>'text', '');
    begin
      v_p := cmd.parse(v_player, p_fleet, v_text);
    exception when others then
      v_msg := sqlerrm;
      get stacked diagnostics v_det = pg_exception_detail;
      v_ref := cmd.refusal_caught(v_msg, v_det);
      return jsonb_build_object('ok', false, 'error_code', v_ref->>'code', 'line', i,
        'error_message', format('Line %s (%s): %s', i, btrim(v_text), v_ref->>'sentence'),
        'figures', v_ref->'figures', 'fixes', cmd.fixes(v_ref->>'code', p_fleet), 'queue', cmd.queue(p_fleet));
    end;
    if (v_p->>'fleet_id')::uuid is distinct from p_fleet then
      return jsonb_build_object('ok', false, 'error_code', 'E_PARSE', 'line', i,
        'error_message', format('Line %s (%s): a plan is for one fleet.', i, btrim(v_text)),
        'fixes', '[]'::jsonb, 'queue', cmd.queue(p_fleet));
    end if;
    if v_p->>'verb' in ('CANCEL', 'CLEAR') then
      return jsonb_build_object('ok', false, 'error_code', 'E_PARSE', 'line', i,
        'error_message', format('Line %s (%s): %s acts on the orders, it is not one.', i, btrim(v_text), v_p->>'verb'),
        'fixes', '[]'::jsonb, 'queue', cmd.queue(p_fleet));
    end if;
    v_parsed := v_parsed || v_p;
  end loop;

  -- THE ROOM, for the whole plan (cmd.enqueue checks one line at a time; a plan is refused whole)
  select count(*) into v_depth from public.orders where fleet_id = p_fleet and status in ('pending', 'active');
  if v_depth + v_n > public.wc_int('order_queue_max') then
    return jsonb_build_object('ok', false, 'error_code', 'E_QUEUE_FULL',
      'error_message', format('That fleet has %s orders waiting; %s more would pass the limit of %s.',
                              v_depth, v_n, public.wc_int('order_queue_max')),
      'fixes', cmd.fixes('E_QUEUE_FULL', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;

  -- ALL QUEUED, OR NONE: one sub-transaction; any refusal takes every line back
  begin
    for i in 1 .. v_n loop
      v_res := cmd.enqueue(v_player, v_parsed[i], p_lines->(i - 1)->>'text', p_lines->(i - 1)->'path', null);
      if not coalesce((v_res->>'ok')::boolean, false) then
        v_fail := v_res || jsonb_build_object('line', i);
        raise exception using errcode = 'ZQ174', message = 'a plan line was refused';
      end if;
      v_ids := v_ids || (v_res->>'order_id')::uuid;
    end loop;
  exception when sqlstate 'ZQ174' then
    return v_fail || jsonb_build_object('ok', false,
      'error_message', format('Line %s: %s', v_fail->>'line', v_fail->>'error_message'),
      'fixes', cmd.fixes(v_fail->>'error_code', p_fleet), 'queue', cmd.queue(p_fleet));
  end;

  -- Run whatever the fleet's state now permits, exactly as cmd.issue does after its one line.
  perform cmd.advance(p_fleet);

  return jsonb_build_object(
    'ok', true,
    'orders', (select jsonb_agg(jsonb_build_object('id', o.id, 'seq', o.seq, 'status', o.status, 'text', o.raw_text,
                                                   'error_code', o.error_code, 'error_message', o.error_message)
                                order by o.seq)
                 from public.orders o where o.id = any(v_ids)),
    'queue', cmd.queue(p_fleet),
    'version', (select version from public.fleets where id = p_fleet));
end $$;

revoke all on function cmd.issue_lines(uuid, jsonb, int) from public, anon, authenticated;
grant execute on function cmd.issue_lines(uuid, jsonb, int) to authenticated;

-- ── 2. THE REGISTRY (one hunk, sliced from the live body; reverses; ACL unchanged) ────────────
do $$
declare
  b     record;
  v_old text := $h$      ('world',       'watchlist',             'uuid')
$h$;
  v_new text := $h$      ('world',       'watchlist',             'uuid'),
      -- 0174: a plan's lines, queued together or not at all (docs/COMMAND_DESK.md §7.4, D4).
      ('cmd',         'issue_lines',           'uuid, jsonb, int')
$h$;
  v_rev text;
begin
  select * into b from before_0174;
  if pg_temp.occurs_0174(b.def, v_old) <> 1 then
    raise exception '0174 self-assert FAIL: the registry''s last row occurs % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0174(b.def, v_old);
  end if;
  execute replace(b.def, v_old, v_new);
  v_rev := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if pg_temp.occurs_0174(v_rev, v_new) <> 1 or replace(v_rev, v_new, v_old) <> b.def then
    raise exception '0174 self-assert FAIL: the registry does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') <> b.acl then
    raise exception '0174 self-assert FAIL: the registry''s ACL moved';
  end if;
end $$;

-- ── 3. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0174-4000-8000-000000000001';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_p    uuid;
  v_pf   uuid;
  v_good text;
  v_ver  int;
  v_r    jsonb;
  v_out  jsonb;
  v_lines jsonb;
  v_path jsonb := '[[38.6, -9.3], [38.5, -9.4]]'::jsonb;
  v_n    int;
  v_max  int := public.wc_int('order_queue_max');
  v_state text;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa do Plano 0174', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0174', 1000000);
    perform cmd.assume_identity(c_uid);
    select g.code into v_good from public.goods g
     where public.port_offers((select id from public.ports where code = 'LIS'), g.id) order by g.code limit 1;

    -- (b) a bad third line queues none, and is named
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(
      jsonb_build_object('text', format('BUY %s 10', v_good)),
      jsonb_build_object('text', format('SELL %s ALL AT >= 1', v_good)),
      jsonb_build_object('text', 'SELL nosuchgood ALL'),
      jsonb_build_object('text', 'SAIL CAD', 'path', v_path)));
    if (v_r->>'ok')::boolean or (v_r->>'line')::int <> 3 or v_r->>'error_message' not like 'Line 3 (SELL nosuchgood ALL):%'
       or exists (select 1 from public.orders where fleet_id = v_pf) then
      raise exception '0174 self-assert FAIL: a bad third line was not refused whole, by name: %', v_r;
    end if;

    -- (d) a queue act, an empty plan, a stale version, another company's fleet
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(jsonb_build_object('text', 'CLEAR')));
    if (v_r->>'ok')::boolean or v_r->>'error_code' <> 'E_PARSE' then
      raise exception '0174 self-assert FAIL: a CLEAR line was queued: %', v_r;
    end if;
    v_r := cmd.issue_lines(v_pf, '[]'::jsonb);
    if (v_r->>'ok')::boolean then
      raise exception '0174 self-assert FAIL: an empty plan was accepted';
    end if;
    v_ver := (select version from public.fleets where id = v_pf);
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(jsonb_build_object('text', format('BUY %s 10', v_good))), v_ver + 7);
    if v_r->>'error_code' <> 'E_STALE' then
      raise exception '0174 self-assert FAIL: a stale version was not refused E_STALE: %', v_r;
    end if;
    v_r := cmd.issue_lines((select f.id from public.fleets f where f.player_id <> v_p limit 1),
                           jsonb_build_array(jsonb_build_object('text', format('BUY %s 10', v_good))));
    if v_r->>'error_code' <> 'E_NO_SUCH_FLEET' then
      raise exception '0174 self-assert FAIL: another company''s fleet was not refused: %', v_r;
    end if;

    -- (c) a plan larger than the room refuses whole
    select jsonb_agg(jsonb_build_object('text', format('BUY %s 1', v_good))) into v_lines from generate_series(1, v_max + 1);
    v_r := cmd.issue_lines(v_pf, v_lines);
    if v_r->>'error_code' <> 'E_QUEUE_FULL' or exists (select 1 from public.orders where fleet_id = v_pf) then
      raise exception '0174 self-assert FAIL: an oversized plan was not refused whole: %', v_r;
    end if;

    -- (a) + (e) four lines, together, in order, each exactly cmd.parse's; the docked fleet starts at once
    v_ver := (select version from public.fleets where id = v_pf);
    v_lines := jsonb_build_array(
      jsonb_build_object('text', format('SELL %s ALL AT >= 1', v_good)),
      jsonb_build_object('text', format('BUY %s 10 AT <= 100000', v_good)),
      jsonb_build_object('text', 'SAIL CAD', 'path', v_path),
      jsonb_build_object('text', format('SELL %s ALL AT >= 1', v_good)));
    v_r := cmd.issue_lines(v_pf, v_lines, v_ver);
    if not (v_r->>'ok')::boolean or jsonb_array_length(v_r->'orders') <> 4 then
      raise exception '0174 self-assert FAIL: four lines were not queued: %', v_r;
    end if;
    select count(*) into v_n
      from public.orders o
      join lateral (select (row_number() over ())::int as i, l from jsonb_array_elements(v_lines) l) x
        on o.raw_text = btrim(x.l->>'text')
     where o.fleet_id = v_pf
       and o.verb = cmd.parse(v_p, v_pf, x.l->>'text')->>'verb'
       and o.args = case when x.l ? 'path' then jsonb_set(cmd.parse(v_p, v_pf, x.l->>'text')->'args', '{path}', x.l->'path')
                         else cmd.parse(v_p, v_pf, x.l->>'text')->'args' end;
    if v_n < 4 then
      raise exception '0174 self-assert FAIL: % of the 4 queued rows are not cmd.parse''s own: %', v_n,
        (select jsonb_agg(jsonb_build_object('t', raw_text, 'v', verb, 'a', args) order by seq) from public.orders where fleet_id = v_pf);
    end if;
    if (select array_agg(raw_text order by seq) from public.orders where fleet_id = v_pf)
         <> (select array_agg(btrim(l->>'text') order by i) from jsonb_array_elements(v_lines) with ordinality x(l, i)) then
      raise exception '0174 self-assert FAIL: the lines were not queued in their order';
    end if;
    if (select version from public.fleets where id = v_pf) < v_ver + 4 then
      raise exception '0174 self-assert FAIL: the version did not move once a line';
    end if;
    -- (e) cmd.advance ran: the first line is no longer pending
    if (select status from public.orders where fleet_id = v_pf order by seq limit 1) = 'pending' then
      raise exception '0174 self-assert FAIL: the docked fleet did not start on its first line';
    end if;

    raise exception using errcode = 'ZX174', message = jsonb_build_object('good', v_good,
      'statuses', (select jsonb_agg(status order by seq) from public.orders where fleet_id = v_pf))::text;
  exception when sqlstate 'ZX174' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0174 self-assert FAIL: the probe company survived its rollback';
  end if;

  -- (f) the receipt
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0174) + 1
     or not has_function_privilege('authenticated', 'cmd.issue_lines(uuid, jsonb, integer)', 'execute')
     or has_function_privilege('anon', 'cmd.issue_lines(uuid, jsonb, integer)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0174 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;

  raise notice '0174 self-assert ok: SEVERAL ORDERS ARE ONE. cmd.issue_lines (registered; authenticated only): a bad third line queued none and was named; a CLEAR line, an empty plan, a stale version and another company''s fleet refused; % lines past the room refused whole; four lines (%) queued in order, each cmd.parse''s own verb and args (the SAIL with its path), the version once a line, the docked fleet started at once (%). Registry +1, reverses to its pre-image.',
    v_max + 1, v_out->>'good', v_out->'statuses';
end $$;
