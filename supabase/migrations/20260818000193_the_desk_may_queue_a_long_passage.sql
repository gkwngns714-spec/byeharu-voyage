-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0193 — THE DESK MAY QUEUE A LONG PASSAGE  (order_queue_max 12 → 48)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Since 0188 the desk plans a long passage as a CHAIN of legs, each within the captain's Navigation
-- reach (1,700 nm at Navigation 0): every hop is a SAIL line, and some carry a PROVISION. A passage
-- the owner wants to sail — Korea → London, ~14,000 nm — is more than twelve lines, and
-- cmd.issue_lines (0175) refuses a plan WHOLE when it does not fit the queue (E_QUEUE_FULL). So the
-- desk could plan the passage and then could not queue it.
--
-- The cap, 12, is `order_queue_max` from 0001 ("DESIGN F.3: maximum orders in one fleet queue"). It
-- was never the owner's number. It is raised to 48 — four times the old queue, room for a dozen legs
-- with a PROVISION between them and the trade lines at both ends — by the coordinator's decision of
-- 2026-10-19, in the open, through the one knob every reader already composes.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- ONE UPDATE: `public.world_config` `order_queue_max` 12 → 48, and its description says why.
-- Nothing else moves. Every reader of the cap reads the knob through public.wc_int at call time, so
-- no function is re-cut. Read on prod (pg_proc.prosrc, read-only, 2026-10-19) the readers are, and
-- each was checked to carry no copy of the number:
--   * cmd.enqueue           — `v_depth >= wc_int(…)` per line (0092; the one enqueuer)
--   * cmd.issue_lines       — `v_depth + v_n > wc_int(…)` for the whole plan (0175; the room check)
--   * cmd.run_standing_route — trims a route's trailing SELLs to the cap (0092:689)
--   * public.standing_route_lines_cap — a stop's lines ≤ cap − 3 (0092:254; a table trigger — 9 → 45)
--   * world.standing_routes — serves `line_max` = cap − 3 to the client (0092:811; 9 → 45)
--   * world.snapshot        — serves `config.order_queue_max` to the client; the desk shows "n/48"
-- Not a reader, but looked at: cmd.advance's runaway guard `exit when guard > 64` (0007). It runs
-- one order per pass, so a queue of 48 that empties in port is 48 passes plus a route refill and
-- a handful of `continue`s — inside 64. Its comment says "the queue is capped at 12"; that comment
-- is now stale and the guard is the first thing to re-cut if the cap is ever raised past ~56.
-- The client has no copy of the number (src/ was grepped): `config.order_queue_max` is read off the
-- snapshot. tests/rpc.surface.spec.ts pinned 12 and now pins 48. The docs that stated 12 as the
-- current cap (TRADE_ROUTES, COMMAND_DESK, UI_DIRECTION, NPC_TRADERS) say 48 since 0193.
--
-- ── THE GUARD ───────────────────────────────────────────────────────────────────────────────────
-- This file raises the cap FROM 12. If the row holds anything else when it runs, somebody moved it
-- already and this file REFUSES rather than overwrite a value it did not expect.
--
-- ── THE PROOF (own probe company at Lisbon, rolled back) ────────────────────────────────────────
-- (a) the knob reads 48 through public.wc_int; (b) the probe's fleet is put to sea on one SAIL, so
--     her lines stay pending; (c) a 49-line plan is refused E_QUEUE_FULL and queues nothing;
-- (d) a 30-line plan queues whole — 30 rows, in order (the old cap refused the 13th line);
-- (e) the queue fills to exactly 48 and the 49th line is refused naming "the limit of 48";
-- (f) the probe left no row behind; the grant wall, the read wall and the registry did not move.
-- ROLLBACK: `update public.world_config set value = to_jsonb(12) where key = 'order_queue_max'`
--           (a superseding migration, never a hand edit). A fleet holding more than 12 lines at that
--           moment keeps them; cmd.enqueue only refuses the NEXT line.
-- VERSION: 0193 — prod head 0189 when written (2026-10-19); 0190–0192 are in flight and land first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. THE GUARD: from 12, or not at all ──────────────────────────────────────────────────────
do $$
declare
  v_now text;
begin
  select value::text into v_now from public.world_config where key = 'order_queue_max';
  if v_now is distinct from '12' then
    raise exception '0193 refused: order_queue_max is % — this file raises the cap from 12 to 48 and does not overwrite a value it did not expect',
      coalesce(v_now, '<no row>');
  end if;
end $$;

-- ── 1. THE KNOB ───────────────────────────────────────────────────────────────────────────────
update public.world_config
   set value = to_jsonb(48),
       description = 'DESIGN F.3: maximum orders in one fleet queue. 48 since 0193 (was 12): the desk plans a '
                     'long passage as a chain of legs within the captain''s reach (0188), each a SAIL and '
                     'sometimes a PROVISION, and a plan is queued whole or not at all (0175). Read by every '
                     'enqueuer through public.wc_int at call time; cmd.advance''s runaway guard (64) must stay '
                     'above it.'
 where key = 'order_queue_max';

-- ── 2. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0193-4000-8000-000000000001';
  c_nil    constant uuid := '00000000-0000-0000-0000-000000000000';
  c_max    constant int  := 48;
  -- The Lisbon → Cádiz course: the two open-sea waypoints 0047 proves are water (0047:1221, off Cape
  -- St Vincent), joined to the roadsteads where she lies and where she is bound (0076: a harbour is
  -- reached from its roads — cmd.do_sail reads sea_reaches.roadstead_lat/lon for both ends). Never a
  -- course typed fresh: without one do_sail synthesises the straight line and refuses it E_NO_COURSE.
  v_course jsonb;
  v_p      uuid;
  v_pf     uuid;
  v_good   text;
  v_r      jsonb;
  v_lines  jsonb;
  v_depth  int;
  v_rows   int;
  v_status text;
  v_out    jsonb;
  v_grants int;
  v_writers int;
  v_evald  int;
begin
  -- (a) the knob, through the one reader every enqueuer uses
  if public.wc_int('order_queue_max') <> c_max then
    raise exception '0193 self-assert FAIL: wc_int(order_queue_max) is %, expected %', public.wc_int('order_queue_max'), c_max;
  end if;

  begin
    v_p := public.new_house(c_uid, 'Casa da Longa Rota 0193', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0193', 1000000);
    perform cmd.assume_identity(c_uid);
    select g.code into v_good from public.goods g
     where public.port_offers((select id from public.ports where code = 'LIS'), g.id) order by g.code limit 1;

    -- (b) to sea on one SAIL (Lisbon → Cádiz is inside any captain's reach), so the lines that follow
    --     stay PENDING: cmd.advance runs nothing while she is SAILING, and voyage time is now(), which
    --     does not move inside this transaction. Asserted, not assumed — the counts below rest on it.
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(36.875, -9.125), jsonb_build_array(36.625, -8.875),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_course
      from public.sea_reaches a, public.sea_reaches b
     where a.code = 'LIS' and b.code = 'CAD';
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(jsonb_build_object('text', 'SAIL CAD', 'path', v_course)));
    select status into v_status from public.fleets where id = v_pf;
    if not coalesce((v_r->>'ok')::boolean, false) or v_status <> 'SAILING' then
      raise exception '0193 self-assert FAIL: the probe fleet did not put to sea on SAIL CAD (status %): %', v_status, v_r;
    end if;
    select count(*) into v_depth from public.orders where fleet_id = v_pf and status in ('pending', 'active');
    if v_depth > 1 then
      raise exception '0193 self-assert FAIL: one SAIL left % live orders', v_depth;
    end if;

    -- (c) a 49-line plan is refused whole, and queues nothing
    select count(*) into v_rows from public.orders where fleet_id = v_pf;
    select jsonb_agg(jsonb_build_object('text', format('BUY %s 1 AT <= 100000', v_good))) into v_lines
      from generate_series(1, c_max + 1);
    v_r := cmd.issue_lines(v_pf, v_lines);
    if coalesce((v_r->>'ok')::boolean, false) or v_r->>'error_code' <> 'E_QUEUE_FULL'
       or (select count(*) from public.orders where fleet_id = v_pf) <> v_rows then
      raise exception '0193 self-assert FAIL: a %-line plan was not refused whole: %', c_max + 1, v_r;
    end if;

    -- (d) a 30-line plan queues whole, in order — the plan the old cap refused at its 13th line
    select jsonb_agg(jsonb_build_object('text', format('BUY %s 1 AT <= 100000', v_good))) into v_lines
      from generate_series(1, 30);
    v_r := cmd.issue_lines(v_pf, v_lines);
    if not coalesce((v_r->>'ok')::boolean, false) or jsonb_array_length(v_r->'orders') <> 30 then
      raise exception '0193 self-assert FAIL: a 30-line plan did not queue whole: %', v_r;
    end if;
    select count(*) into v_rows from public.orders where fleet_id = v_pf and status = 'pending';
    if v_rows < 30 then
      raise exception '0193 self-assert FAIL: % of the 30 lines are pending', v_rows;
    end if;
    select count(*) into v_depth from public.orders where fleet_id = v_pf and status in ('pending', 'active');

    -- (e) the queue fills to exactly the cap; the next line is refused, naming the limit
    select jsonb_agg(jsonb_build_object('text', format('BUY %s 1 AT <= 100000', v_good))) into v_lines
      from generate_series(1, c_max - v_depth);
    v_r := cmd.issue_lines(v_pf, v_lines);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0193 self-assert FAIL: the queue would not fill from % to %: %', v_depth, c_max, v_r;
    end if;
    select count(*) into v_depth from public.orders where fleet_id = v_pf and status in ('pending', 'active');
    if v_depth <> c_max then
      raise exception '0193 self-assert FAIL: the queue holds % live orders, expected exactly %', v_depth, c_max;
    end if;
    v_r := cmd.issue_lines(v_pf, jsonb_build_array(jsonb_build_object('text', format('BUY %s 1 AT <= 100000', v_good))));
    if coalesce((v_r->>'ok')::boolean, false) or v_r->>'error_code' <> 'E_QUEUE_FULL'
       or v_r->>'error_message' not like format('%%the limit of %s.%%', c_max)
       or (select count(*) from public.orders where fleet_id = v_pf and status in ('pending', 'active')) <> c_max then
      raise exception '0193 self-assert FAIL: the %th line was not refused E_QUEUE_FULL naming the limit: %', c_max + 1, v_r;
    end if;

    raise exception using errcode = 'ZX193', message = jsonb_build_object('good', v_good, 'depth', v_depth,
      'message', v_r->>'error_message')::text;
  exception when sqlstate 'ZX193' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);

  -- (f) nothing left behind; nothing else moved
  if exists (select 1 from public.players where id = v_p) or exists (select 1 from public.orders where fleet_id = v_pf) then
    raise exception '0193 self-assert FAIL: the probe company survived its rollback';
  end if;
  select count(*) into v_grants  from public.client_write_grants();
  select count(*) into v_writers from public.client_executable_writers();
  select count(*) into v_evald   from public.caller_evaluated_functions();
  if v_grants <> 0 or v_writers <> 0 or v_evald <> 0 then
    raise exception '0193 self-assert FAIL: the grant wall or the read wall moved (% / % / %)', v_grants, v_writers, v_evald;
  end if;

  raise notice '0193 self-assert ok: THE DESK MAY QUEUE A LONG PASSAGE. order_queue_max is % (was 12), read through public.wc_int by every enqueuer; on a probe fleet put to sea at Lisbon (%): a %-line plan refused E_QUEUE_FULL and queued nothing, a 30-line plan queued whole and in order, the queue filled to exactly % live orders and the next line was refused ("%"); the probe left no row; grant wall, read wall and registry unmoved. Rolled back.',
    c_max, v_out->>'good', c_max + 1, v_out->>'depth', v_out->>'message';
end $$;
