-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0186 — A REFUSED ORDER DOES NOT FREEZE THE QUEUE  (plan reach, slice 1)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18 ~14:00 UTC: *"Gaivota stopped at order 29 and will not skip it. that leg is 14015 nm
-- and your navigation carries you 1700 nm — study navigation, what is this?"*. His plan (cmd.issue_lines, 0175)
-- was `SAIL MTY · BUY abalone-shell ALL · SAIL TRI · SELL abalone-shell ALL`. Line 29 (SAIL MTY) was refused
-- E_LEG_TOO_FAR at execution — NAVIGATION 0, so nav_leg_nm_base 1,700 × 2^max(0, 0 − 1) = 1,700 nm of reach,
-- and the leg is 14,015 nm (public.passage_gate, 0107: the rule is right). Then two things froze him:
--   * cmd.advance's halt rule (0007 §F.3): ANY failed order in the queue stops the fleet until it is cleared.
--     So lines 30–32 sat pending behind a passage that can never be sailed.
--   * the ✕ beside a queued line did nothing: the client sends the order's SEQ, cmd.cancel_at reads an INDEX
--     (1-based, over the live rows). `cancel_at(fleet, 30)` looked for the 30th live row and found none. And a
--     failed row had no ✕ at all.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- 1. public.orders.plan_id (uuid, null): the lines cmd.issue_lines queues together are ONE PLAN and carry its
--    id — the id of its first line. One hunk in cmd.issue_lines writes it, before its cmd.advance.
-- 2. cmd.release_failed(order) — NEW, server-only. What hung on a refused ORDER (not a route's line) is
--    cancelled, each row with the reason (`cancelled: the passage to Monterrey was refused — that leg is …`):
--      * the rest of its plan (same plan_id, still pending, behind it);
--      * everything pending behind a refused SAIL — those lines were written for where she would have been.
--    A refused single BUY / SELL / … hangs nothing: the queue moves on. Returns how many it cancelled.
-- 3. cmd.advance, two hunks:
--      A. the halt check reads only a ROUTE's failed line (route_lap_id not null) — exactly the halt 0092/0093
--         keep for a route's refused SAIL (and for a route's trade line while routes are dark). An order's
--         refusal no longer stops the fleet;
--      B. on an order's refusal (no route lap) the executor calls cmd.release_failed and goes on.
--    A route's lines are untouched: a route's refused trade line is still stepped over and written on the lap,
--    a route's refused SAIL still halts and npc_tend_route / CLEAR still releases it.
-- 4. cmd.cancel_at, one hunk: the ✕ by number counts the rows cmd.queue serves — pending, active AND failed —
--    so a refused row can be dismissed. (The client now sends that 1-based position, not the seq.)
-- 5. THE RELEASE, NOW: every fleet whose refused order still holds pending lines behind it is released through
--    cmd.release_failed — the queue's own cancel path, each row with its reason, logged below. Read on prod
--    2026-10-18 (read-only): exactly one such fleet, the owner's Gaivota (51b8f474…), lines 30–32 behind the
--    refused 29. Nothing else of his is written but the fleet's version (+1, as every cancel path bumps it).
--
-- ── THE PROOF (own probe company at Lisbon, rolled back) ────────────────────────────────────────
-- (a) a plan whose first line is refused at execution: the rest of it is cancelled with the reason, every
--     line carries the plan's id; (b) the fleet is then free — a new BUY runs at once; (c) a refused single
--     order hangs nothing — the one behind it runs; (d) a refused single SAIL cancels the line behind it, the
--     reason naming the passage; (e) the ✕ by position dismisses a refused row; CLEAR empties the rest;
--     (f) the release is server-only, the walls hold, every hunk reverses to its pre-image, ACLs unchanged.
-- ROLLBACK: reverse the four hunks (each reverses to its pre-image — asserted), drop cmd.release_failed, drop
-- the column. The cancelled rows of §5 stay cancelled (a plan that cannot be sailed is not restored).
-- VERSION: 0186 PROVISIONAL — main head 0184 when renumbered (2026-10-18; 0185 is in PR #224). Every pre-image
-- is read live.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0186(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table before_0186 on commit drop as
select f.sig, replace(pg_get_functiondef(f.sig::regprocedure), E'\r', '') as def,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = f.sig::regprocedure) as acl
  from (values ('cmd.advance(uuid, timestamp with time zone)'),
               ('cmd.issue_lines(uuid, jsonb, integer)'),
               ('cmd.cancel_at(uuid, integer)')) f(sig);

create temp table clock_0186 on commit drop as select clock_timestamp() as t0;

do $$
begin
  if to_regprocedure('cmd.release_failed(uuid)') is not null
     or exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'orders' and column_name = 'plan_id') then
    raise exception '0186 self-assert FAIL: cmd.release_failed or orders.plan_id already exists';
  end if;
end $$;

-- ── 1. THE PLAN'S ID ON ITS LINES ─────────────────────────────────────────────────────────────
alter table public.orders add column plan_id uuid;
comment on column public.orders.plan_id is
  '0186: the lines cmd.issue_lines queued together carry one plan id (their first line''s id). A refusal at '
  'execution cancels the rest of the plan (cmd.release_failed). Null for a single order and for a route''s lines.';

-- ── 2. THE RELEASE ────────────────────────────────────────────────────────────────────────────
create or replace function cmd.release_failed(p_order uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0186: WHAT HUNG ON A REFUSED ORDER IS CANCELLED, WITH THE REASON; NOTHING ELSE IS. Server-only (cmd.advance).
-- An order's refusal does not freeze the queue (the owner, 2026-10-18). The lines that cannot mean anything
-- after it are cancelled, each carrying why:
--   * the rest of its PLAN (cmd.issue_lines' lines share orders.plan_id);
--   * everything behind a refused SAIL — each was written for the harbour she did not reach.
-- A route's lines are not this function's (route_lap_id): a route keeps its own skip and halt (0092, 0093).
declare
  o     public.orders%rowtype;
  v_why text;
  v_n   int;
begin
  select * into o from public.orders where id = p_order;
  if o.id is null or o.status <> 'failed' or o.route_lap_id is not null then
    return 0;
  end if;
  v_why := case when o.verb = 'SAIL'
                then format('the passage to %s was refused',
                            coalesce((select p.name from public.ports p where p.id::text = o.args->>'dest'), 'that point'))
                else format('%s was refused', o.raw_text) end;
  update public.orders
     set status = 'cancelled',
         error_message = format('cancelled: %s — %s', v_why, coalesce(o.error_message, o.error_code, 'refused'))
   where fleet_id = o.fleet_id and status = 'pending' and route_lap_id is null and seq > o.seq
     and (o.verb = 'SAIL' or (o.plan_id is not null and plan_id = o.plan_id));
  get diagnostics v_n = row_count;
  if v_n > 0 then
    update public.fleets set version = version + 1 where id = o.fleet_id;
  end if;
  return v_n;
end $$;

revoke all on function cmd.release_failed(uuid) from public, anon, authenticated;

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each reverses; ACLs unchanged) ─
create temp table hunks_0186 (sig text, ord int, old_t text, new_t text) on commit drop;
insert into hunks_0186 values
('cmd.advance(uuid, timestamp with time zone)', 1,
$hA$    if exists (select 1 from public.orders
                where fleet_id = p_fleet and status = 'failed') then
      exit;
    end if;
$hA$,
$hA$    -- 0186 (the owner, 2026-10-18: "stopped at order 29 and will not skip it"): only a ROUTE's refused line
    -- halts her now — the halt 0092/0093 keep for a route's SAIL. An ORDER's refusal released what hung on it
    -- (cmd.release_failed, below) and the queue goes on.
    if exists (select 1 from public.orders
                where fleet_id = p_fleet and status = 'failed'
                  and route_lap_id is not null) then
      exit;
    end if;
$hA$),
('cmd.advance(uuid, timestamp with time zone)', 2,
$hB$    if not coalesce((v_res->>'ok')::boolean, false) then
      exit when o.route_lap_id is null or o.verb = 'SAIL' or not public.standing_routes_on();   -- 0093: dark = the ordinary halt
$hB$,
$hB$    if not coalesce((v_res->>'ok')::boolean, false) then
      -- 0186: an ORDER's refusal cancels the rest of its plan and whatever stood behind a refused SAIL, each
      -- with the reason; the rest runs on.
      if o.route_lap_id is null then
        perform cmd.release_failed(o.id);
        continue;
      end if;
      exit when o.verb = 'SAIL' or not public.standing_routes_on();   -- 0093: dark = the ordinary halt
$hB$),
('cmd.issue_lines(uuid, jsonb, integer)', 1,
$hC$  -- Run whatever the fleet's state now permits, exactly as cmd.issue does after its one line.
  perform cmd.advance(p_fleet);
$hC$,
$hC$  -- 0186: the lines are ONE PLAN and carry its id (the first line's): a refusal at execution cancels the rest.
  update public.orders set plan_id = v_ids[1] where id = any(v_ids);

  -- Run whatever the fleet's state now permits, exactly as cmd.issue does after its one line.
  perform cmd.advance(p_fleet);
$hC$),
('cmd.cancel_at(uuid, integer)', 1,
$hD$    select * into o from public.orders where fleet_id = p_fleet and status in ('pending', 'active')
     order by seq offset (p_index - 1) limit 1;
$hD$,
$hD$    -- 0186: the position counts the rows cmd.queue serves, a refused one too, so it can be dismissed.
    select * into o from public.orders where fleet_id = p_fleet and status in ('pending', 'active', 'failed')
     order by seq offset (p_index - 1) limit 1;
$hD$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for b in select * from before_0186 loop
    v_def := b.def;
    for h in select * from hunks_0186 where sig = b.sig order by ord loop
      if pg_temp.occurs_0186(b.def, h.old_t) <> 1 then
        raise exception '0186 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.ord, b.sig, pg_temp.occurs_0186(b.def, h.old_t);
      end if;
      v_def := replace(v_def, h.old_t, h.new_t);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(b.sig::regprocedure), E'\r', '');
    for h in select * from hunks_0186 where sig = b.sig order by ord desc loop
      if pg_temp.occurs_0186(v_rev, h.new_t) <> 1 then
        raise exception '0186 self-assert FAIL: hunk % of % is not in the new body once', h.ord, b.sig;
      end if;
      v_rev := replace(v_rev, h.new_t, h.old_t);
    end loop;
    if v_rev <> b.def then
      raise exception '0186 self-assert FAIL: % does not reverse to its pre-image', b.sig;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = b.sig::regprocedure), '') <> b.acl then
      raise exception '0186 self-assert FAIL: the ACL of % moved', b.sig;
    end if;
  end loop;
end $$;

-- ── 4. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0186-4000-8000-000000000001';
  c_nil  constant uuid := '00000000-0000-0000-0000-000000000000';
  v_t    timestamptz := clock_timestamp();
  v_p    uuid;
  v_pf   uuid;
  v_good text;
  v_far  text;
  v_farn text;
  v_r    jsonb;
  v_out  jsonb;
  v_path jsonb := '[[38.6, -9.3], [38.5, -9.4]]'::jsonb;
  v_ids  uuid[];
  v_st   text[];
  v_seq0 int;
begin
  begin
    v_p := public.new_house(c_uid, 'Casa do Recuo 0186', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0186', 1000000);
    perform cmd.assume_identity(c_uid);
    select g.code into v_good from public.goods g
     where public.port_offers((select id from public.ports where code = 'LIS'), g.id) order by g.code limit 1;
    -- a harbour far past a NAVIGATION-0 captain's reach (nav_leg_nm_base × 2^0), the farthest the chart reaches
    select p.code, p.name into v_far, v_farn
      from voyage.reach_from((select id from public.ports where code = 'LIS')) r
      join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm > 2 * public.wc_num('nav_leg_nm_base')
     order by r.nm desc, p.code limit 1;
    if v_far is null then
      raise exception '0186 self-assert FAIL: no harbour lies beyond a first captain''s reach of Lisbon';
    end if;

    -- (a) a plan whose first line is refused at execution (nothing aboard to sell): the rest is cancelled
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(
      jsonb_build_object('text', format('SELL %s ALL', v_good)),
      jsonb_build_object('text', format('BUY %s 10 AT <= 100000', v_good)),
      jsonb_build_object('text', 'SAIL CAD', 'path', v_path),
      jsonb_build_object('text', format('SELL %s ALL AT >= 1', v_good))));
    if not (v_r->>'ok')::boolean then
      raise exception '0186 self-assert FAIL: the probe plan was not queued: %', v_r;
    end if;
    select array_agg(id order by seq), array_agg(status order by seq) into v_ids, v_st
      from public.orders where fleet_id = v_pf;
    if v_st <> array['failed', 'cancelled', 'cancelled', 'cancelled'] then
      raise exception '0186 self-assert FAIL: the refused plan''s lines read % (want failed, then three cancelled)', v_st;
    end if;
    if (select count(*) from public.orders where fleet_id = v_pf and plan_id = v_ids[1]) <> 4 then
      raise exception '0186 self-assert FAIL: the plan''s four lines do not carry its id';
    end if;
    if exists (select 1 from public.orders where fleet_id = v_pf and status = 'cancelled'
                and error_message not like format('cancelled: SELL %s ALL was refused — %%', v_good)) then
      raise exception '0186 self-assert FAIL: a cancelled line does not carry the reason: %',
        (select jsonb_agg(error_message) from public.orders where fleet_id = v_pf and status = 'cancelled');
    end if;

    -- (b) the fleet is free: a new BUY runs at once
    v_r := cmd.issue(v_pf, format('BUY %s 10 AT <= 100000', v_good));
    if v_r->'order'->>'status' <> 'done' then
      raise exception '0186 self-assert FAIL: the fleet was not free after a refused plan: %', v_r;
    end if;

    -- (c) a refused SINGLE order hangs nothing: the one queued behind it runs
    select coalesce(max(seq), 0) into v_seq0 from public.orders where fleet_id = v_pf;
    perform cmd.enqueue(v_p, cmd.parse(v_p, v_pf, format('BUY %s 1 AT <= 0.01', v_good)), format('BUY %s 1 AT <= 0.01', v_good), null, null);
    perform cmd.enqueue(v_p, cmd.parse(v_p, v_pf, format('SELL %s 5 AT >= 1', v_good)), format('SELL %s 5 AT >= 1', v_good), null, null);
    perform cmd.advance(v_pf);
    select array_agg(status order by seq) into v_st from public.orders where fleet_id = v_pf and seq > v_seq0;
    if v_st <> array['failed', 'done'] then
      raise exception '0186 self-assert FAIL: a refused single order froze or took the next with it: %', v_st;
    end if;

    -- (d) a refused single SAIL cancels the line behind it, naming the passage
    select coalesce(max(seq), 0) into v_seq0 from public.orders where fleet_id = v_pf;
    perform cmd.enqueue(v_p, cmd.parse(v_p, v_pf, format('SAIL %s', v_far)), format('SAIL %s', v_far), null, null);
    perform cmd.enqueue(v_p, cmd.parse(v_p, v_pf, format('SELL %s ALL AT >= 1', v_good)), format('SELL %s ALL AT >= 1', v_good), null, null);
    perform cmd.advance(v_pf);
    select array_agg(status order by seq) into v_st from public.orders where fleet_id = v_pf and seq > v_seq0;
    if v_st <> array['failed', 'cancelled']
       or (select error_message from public.orders where fleet_id = v_pf and seq = v_seq0 + 2)
            not like format('cancelled: the passage to %s was refused — %%', v_farn) then
      raise exception '0186 self-assert FAIL: a refused SAIL did not cancel the line behind it with the reason: % %', v_st,
        (select error_message from public.orders where fleet_id = v_pf and seq = v_seq0 + 2);
    end if;

    -- (e) the ✕ by position dismisses a refused row (the first row cmd.queue serves); CLEAR empties the rest
    if jsonb_array_length(cmd.queue(v_pf)) <> 3 then
      raise exception '0186 self-assert FAIL: cmd.queue should serve the three refused rows: %', cmd.queue(v_pf);
    end if;
    v_r := cmd.cancel_at(v_pf, 1);
    if not (v_r->>'ok')::boolean or (select status from public.orders where id = v_ids[1]) <> 'cancelled'
       or jsonb_array_length(cmd.queue(v_pf)) <> 2 then
      raise exception '0186 self-assert FAIL: the ✕ at position 1 did not dismiss the refused row: %', v_r;
    end if;
    v_r := cmd.clear(v_pf, false);
    if jsonb_array_length(cmd.queue(v_pf)) <> 0 then
      raise exception '0186 self-assert FAIL: CLEAR left rows: %', cmd.queue(v_pf);
    end if;

    raise exception using errcode = 'ZX184', message = jsonb_build_object('good', v_good, 'far', v_far)::text;
  exception when sqlstate 'ZX184' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0186 self-assert FAIL: the probe company survived its rollback';
  end if;

  -- (f) the walls
  if has_function_privilege('authenticated', 'cmd.release_failed(uuid)', 'execute')
     or has_function_privilege('anon', 'cmd.release_failed(uuid)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0186 self-assert FAIL: the release is client-callable, or the grant or read wall moved';
  end if;

  raise notice '0186 self-assert ok: A REFUSED ORDER DOES NOT FREEZE THE QUEUE (% ms). A plan refused at its first line (%) cancelled its three other lines with the reason, all four carrying the plan id, and the fleet then bought at once; a refused single BUY (its limit missed) let the SELL behind it run; a refused SAIL to % cancelled the line behind it, naming the passage; the ✕ at position 1 dismissed a refused row and CLEAR emptied the rest. cmd.advance, cmd.issue_lines and cmd.cancel_at each reverse to their pre-image, ACLs unchanged; cmd.release_failed is server-only.',
    round(extract(epoch from clock_timestamp() - v_t) * 1000), v_out->>'good', v_out->>'far';
end $$;

-- ── 5. THE RELEASE, NOW — every fleet a refused order still holds, through the one cancel path ─
do $$
declare
  v_t   timestamptz := clock_timestamp();
  r     record;
  v_n   int;
  v_all int := 0;
  v_log jsonb := '[]'::jsonb;
begin
  for r in
    select o.id, o.fleet_id, o.seq, o.raw_text, o.error_code
      from public.orders o
     where o.status = 'failed' and o.route_lap_id is null
       and exists (select 1 from public.orders b
                    where b.fleet_id = o.fleet_id and b.status = 'pending' and b.seq > o.seq and b.route_lap_id is null)
     order by o.fleet_id, o.seq
  loop
    v_n := cmd.release_failed(r.id);
    v_all := v_all + v_n;
    v_log := v_log || jsonb_build_object('fleet', r.fleet_id, 'refused', r.seq, 'line', r.raw_text, 'code', r.error_code,
      'cancelled', (select coalesce(jsonb_agg(jsonb_build_object('seq', b.seq, 'line', b.raw_text, 'why', b.error_message) order by b.seq), '[]'::jsonb)
                      from public.orders b where b.fleet_id = r.fleet_id and b.status = 'cancelled' and b.seq > r.seq
                       and b.error_message like 'cancelled: %'));
  end loop;
  raise notice '0186 release (% ms): % line(s) cancelled through cmd.release_failed, behind % refused order(s): %',
    round(extract(epoch from clock_timestamp() - v_t) * 1000), v_all, jsonb_array_length(v_log), v_log;
  raise notice '0186 whole file: % ms', round(extract(epoch from clock_timestamp() - (select t0 from clock_0186)) * 1000);
end $$;
