-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0092 — A ROUTE IS A STANDING ORDER THAT SAILS
--        The owner, 2026-09-30: "i want this game to be a simulating based - meaning i set up
--        route, trade routes - going back and forth, afk, running all the time".
--        docs/TRADE_ROUTES.md is the plan (NO_SPAGHETTI §7B); this file is its SLICE 1, server side.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE CONCEPT, IN ONE NOUN PHRASE (docs/NO_SPAGHETTI.md §7B) ─────────────────────────────────
-- A STANDING ROUTE: an ordered loop of harbours, each with a short list of trade lines, that
-- writes a fleet's next orders into ITS OWN QUEUE whenever that queue runs dry in port. It is
-- 0034's standing provision order one level up. It never executes anything itself.
--
-- ── WHAT IT COMPOSES, AND WHAT IT DOES NOT FORK ────────────────────────────────────────────────
--   * ONE EXECUTOR. cmd.advance -> cmd.execute_order -> do_sell / do_provision / do_repair /
--     do_buy / do_sail run every route line, exactly as they run a line the player typed. There
--     is no second trade path, no second movement path, no second price rule.
--   * ONE GRAMMAR. Every stop is RENDERED TO TEXT (cmd.standing_route_lines) and parsed by
--     cmd.parse, the one parser; a line that does not parse is a broken route, never a guess.
--   * ONE ENQUEUER. cmd.issue's inline enqueue (depth check, seq, insert, version) is SLICED
--     OUT into cmd.enqueue and both the player's door and the route call it (§4.1 of the plan).
--   * ONE CLOCK. No cron job is added. The existing byeharu-voyage:arrivals job (tick_arrivals,
--     every minute) settles voyages -> the arrival arm -> cmd.advance -> the refill. The only
--     clock change is one loop in tick_arrivals that wakes a route held for pacing.
--   * ONE KEEP LEVEL. The 0034 preset stays the only author of "how many days of supplies";
--     the route only PLACES that order at the right moment — after its sales, before its buys.
--
-- ── WHAT THIS FILE SUPERSEDES (every re-cut is SLICED from pg_get_functiondef, each hunk
--    asserted to occur exactly once, LF-normalised, parity proven by reverse substitution) ──────
--   cmd.issue(uuid, text, int, jsonb)         0008:453, re-cut 0047:825 / 0050:551 — two hunks:
--                                             the SAIL-course attach and the enqueue block move
--                                             into cmd.enqueue; the refusal shape is unchanged.
--                                             Byte parity of 18 responses (incl. E_QUEUE_FULL at
--                                             13 and E_STALE) is proven against the pre-image.
--   cmd.advance(uuid, timestamptz)            0007:812, re-cut 0047:725 — three hunks: a flag,
--                                             HUNK A (the queue-dry exit refills ONCE from the
--                                             route), HUNK B (a refused ROUTE TRADE line is
--                                             stepped over and noted; a refused route SAIL, and
--                                             every ordinary order, still halts by 0007:839).
--                                             With no route standing, behaviour is unchanged.
--   cmd.run_standing_provision(uuid)          0034:195, re-cut 0050 — two hunks: an early return
--                                             when a RUNNING route stands on the fleet (the route
--                                             places the keep order itself, after its sales), and
--                                             the satisfaction test moved into public.keep_level_met
--                                             so the route and the arrival order share ONE judge.
--   public.tick_arrivals(timestamptz)         0010:54 — one hunk: the held-route wake loop.
--   public.client_rpc_entry_points()          last cut 0087 — five rows sliced in after the
--                                             `preview_fulfil` row.
--
-- ── DARK FIRST ─────────────────────────────────────────────────────────────────────────────────
-- world_config.standing_routes_enabled is FALSE. While false: the four verbs refuse E_UNAVAILABLE
-- ("Routes are not open yet."), the refill and the wake loop are inert, the read serves
-- enabled:false. Turning it on is a separate, owner-approved production write AFTER the clock is
-- wound (docs/DEPLOY_RUNBOOK.md step 4): with the clock stopped a route moves one stop per read.
-- This file cannot and does not start the clock (0078's rule).
--
-- ── WHAT IT DELIBERATELY DOES NOT TOUCH ────────────────────────────────────────────────────────
--   * `fleets` gains no column: the route points at its fleet (unique fleet_id), 1:1.
--   * do_sell / do_buy / do_sail / do_provision / do_repair / cmd.parse / cmd.execute_order /
--     voyage.settle — CALLED, never retyped.
--   * 0010's header says the cron is "an optimisation, not a correctness requirement". For a
--     ROUTE fleet that no longer holds (docs/TRADE_ROUTES.md §4.4); the migration cannot edit
--     0010, so the note is in docs/DESIGN.md §D.2 and the runbook.
--   * D3 (SELL ALL sized to the day's allowance), D4 (rank), per-fleet sub-transactions in the
--     tick, deadlock retry — slice 2 / 4, not here.
--
-- ── SECOND CALLERS, NAMED NOW (§7B) ────────────────────────────────────────────────────────────
--   cmd.enqueue: cmd.issue and cmd.run_standing_route. world.standing_routes: COMMAND's RouteFold,
--   FLEETS' caption word, and (slice 3) the MAP's route line — all read the one served shape.
--
-- Depends on: 0001 (wc, lockdown), 0004 (players, fleets, credit, emit_event, current_player_id,
-- ledger), 0005 (game_day), 0007 (orders, advance, execute_order), 0008 (issue, parse, queue,
-- assume_identity), 0010 (tick_arrivals), 0034 (provision_presets, run_standing_provision),
-- 0047 (courses), 0050 (refusal_caught, fixes), 0081 (fleet_cargo_basis), 0086 (wages in the
-- day payload), 0087 (client_rpc_entry_points' last cut).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool (its own copy, by necessity — tests/duplication.spec.ts:365-380) ─────────
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0092 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0092 as
  select f.fn, pg_get_functiondef(f.fn::regprocedure) as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (values ('cmd.issue(uuid, text, integer, jsonb)'),
                 ('cmd.advance(uuid, timestamptz)'),
                 ('cmd.run_standing_provision(uuid)'),
                 ('public.tick_arrivals(timestamptz)'),
                 ('public.client_rpc_entry_points()')) as f(fn);

-- The PRE-IMAGE of cmd.issue, kept alive for this transaction only, so the parity probe can run
-- the very same orders through the old door and the new one and compare the answers.
do $$
declare v_def text := (select def from defs_before_0092 where fn = 'cmd.issue(uuid, text, integer, jsonb)');
begin
  if position('FUNCTION cmd.issue(' in v_def) = 0 then
    raise exception '0092 self-assert FAIL: the cmd.issue pre-image does not open as expected';
  end if;
  execute replace(v_def, 'FUNCTION cmd.issue(', 'FUNCTION pg_temp.issue_before_0092(');
end $$;

-- ── 1. THE KNOBS — the switch is OFF ───────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('standing_routes_enabled', 'false'::jsonb,
   '0092: the dark-first switch for standing routes. false = the four route verbs refuse '
   'E_UNAVAILABLE, the refill in cmd.advance and the wake loop in tick_arrivals are inert, and '
   'world.standing_routes serves enabled:false. Turn on only after wind_the_clock() (routes need '
   'the arrivals job; docs/TRADE_ROUTES.md §4.4).'),
  ('standing_route_max', to_jsonb(3),
   '0092: how many routes one company may keep (D7). Read by the standing_routes_cap trigger.'),
  ('standing_route_stop_max', to_jsonb(6),
   '0092: how many stops one route may have (D7). Read by the standing_route_stops_cap trigger.'),
  ('standing_route_laps_per_game_day', to_jsonb(1),
   '0092: pacing (D2). How many laps a route may START per game-day (world.game_day); a route '
   'that has started that many waits at its first stop until the next game-day, when the '
   'arrivals job wakes it. 0 = unpaced (as fast as the ship sails).'),
  ('standing_route_lap_keep', to_jsonb(30),
   '0092: how many lap rows are kept per route; older laps are pruned at each lap close.'),
  ('standing_route_losing_laps', to_jsonb(3),
   '0092: the default for a new route''s stop_after_losing_laps guard: after this many losing '
   'laps in a row the route pauses itself.');

-- ── 2. THE TABLES ──────────────────────────────────────────────────────────────────────────────
create table public.standing_routes (
  id                     uuid primary key default gen_random_uuid(),
  player_id              uuid not null references public.players(id) on delete cascade,
  name                   text not null,
  -- ONE fleet per route, ONE route per fleet. The route points at the fleet (not the fleet at the
  -- route, as a SHARED 0034 preset must) so `fleets` gains no column. Deleting the fleet detaches.
  fleet_id               uuid unique references public.fleets(id) on delete set null,
  -- the stop the fleet is AT (queue dry) or HEADING TO / WORKING (after its orders were written)
  stop_cursor            int  not null default 0 check (stop_cursor >= 0),
  lap_no                 int  not null default 0 check (lap_no >= 0),
  lap_id                 uuid,
  paused_reason          text check (paused_reason in ('player', 'reserve', 'losing', 'off_route', 'error', 'edited')),
  hold_until             timestamptz,
  reserve                bigint not null default 0 check (reserve >= 0),
  stop_after_losing_laps int  not null default 3 check (stop_after_losing_laps between 1 and 20),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint standing_routes_name_length check (length(btrim(name)) between 2 and 24)
);
create unique index standing_routes_player_name_unique on public.standing_routes (player_id, lower(name));
comment on table public.standing_routes is
  '0092: a company''s standing routes. A route never executes anything: when its fleet''s queue '
  'runs dry in port, cmd.run_standing_route writes the next stop''s orders into that queue in the '
  'player''s own grammar, and the ONE executor runs them.';

create table public.standing_route_stops (
  route_id uuid not null references public.standing_routes(id) on delete cascade,
  ord      int  not null check (ord >= 0),
  port_id  uuid not null references public.ports(id),
  -- the PROPOSED course for the leg FROM this stop TO the next, authored by the client's one
  -- course author (proposeCourse) and re-verified by do_sail at every departure.
  course   jsonb not null check (jsonb_typeof(course) = 'array' and jsonb_array_length(course) >= 2),
  repair   boolean not null default false,
  primary key (route_id, ord)
);

create table public.standing_route_lines (
  route_id    uuid not null,
  stop_ord    int  not null,
  ord         int  not null check (ord >= 0),
  kind        text not null check (kind in ('SELL', 'BUY')),
  good_id     uuid references public.goods(id),   -- null on SELL = everything on board
  qty         numeric check (qty is null or qty > 0),          -- null = ALL
  price_limit numeric check (price_limit is null or price_limit > 0),
  at_profit   boolean not null default false,
  primary key (route_id, stop_ord, ord),
  foreign key (route_id, stop_ord) references public.standing_route_stops (route_id, ord) on delete cascade,
  constraint standing_route_lines_buy_names_a_good check (kind <> 'BUY' or good_id is not null),
  constraint standing_route_lines_profit_is_a_sell check (not at_profit or kind = 'SELL')
);

create table public.standing_route_laps (
  id         uuid primary key default gen_random_uuid(),
  route_id   uuid not null references public.standing_routes(id) on delete cascade,
  lap_no     int  not null,
  started_at timestamptz not null,
  closed_at  timestamptz,
  stops_done int    not null default 0,
  sold       bigint not null default 0,
  bought     bigint not null default 0,
  supplies   bigint not null default 0,
  repairs    bigint not null default 0,
  wages      bigint not null default 0,
  net        bigint not null default 0,
  skipped    jsonb  not null default '[]'::jsonb,
  constraint standing_route_laps_one_per_number unique (route_id, lap_no)
);
comment on table public.standing_route_laps is
  '0092: one row per lap, bounded to the newest standing_route_lap_keep per route. Every figure '
  'is summed from the executors'' own results and the settled voyage days — nothing is re-priced.';

alter table public.standing_routes
  add constraint standing_routes_open_lap_fk foreign key (lap_id)
  references public.standing_route_laps(id) on delete set null;

-- A route's order is an ORDINARY order with one more fact: which lap wrote it.
alter table public.orders add column route_lap_id uuid
  references public.standing_route_laps(id) on delete set null;
create index orders_route_lap on public.orders (route_lap_id) where route_lap_id is not null;

-- ── 2b. THE CAPS ARE RULES ON THE TABLES (0034's shape), so any future writer inherits them ────
create or replace function public.standing_routes_cap()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_max int := public.wc_int('standing_route_max');
begin
  if (select count(*) from public.standing_routes where player_id = new.player_id) >= v_max then
    raise exception 'E_ROUTE_CAP: you keep % routes already, which is all you may keep', v_max using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger standing_routes_cap before insert on public.standing_routes
  for each row execute function public.standing_routes_cap();

create or replace function public.standing_route_stops_cap()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_max int := public.wc_int('standing_route_stop_max');
begin
  if (select count(*) from public.standing_route_stops where route_id = new.route_id) >= v_max then
    raise exception 'E_ROUTE_CAP: a route has at most % stops', v_max using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger standing_route_stops_cap before insert on public.standing_route_stops
  for each row execute function public.standing_route_stops_cap();

-- A stop's own lines plus PROVISION, REPAIR and SAIL must fit one queue (order_queue_max). Only the
-- "sell everything" expansion can overflow at refill time; the generator trims that and notes it.
create or replace function public.standing_route_lines_cap()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_max int := public.wc_int('order_queue_max') - 3;
begin
  if (select count(*) from public.standing_route_lines
       where route_id = new.route_id and stop_ord = new.stop_ord) >= v_max then
    raise exception 'E_ROUTE_CAP: a stop has at most % lines', v_max using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger standing_route_lines_cap before insert on public.standing_route_lines
  for each row execute function public.standing_route_lines_cap();

-- ── 2c. READ-OWN, NO CLIENT WRITE (0034's posture; the grant-drift law) ────────────────────────
alter table public.standing_routes      enable row level security;
alter table public.standing_route_stops enable row level security;
alter table public.standing_route_lines enable row level security;
alter table public.standing_route_laps  enable row level security;
create policy standing_routes_read_own on public.standing_routes for select to authenticated
  using (player_id = public.current_player_id());
create policy standing_route_stops_read_own on public.standing_route_stops for select to authenticated
  using (exists (select 1 from public.standing_routes r
                  where r.id = route_id and r.player_id = public.current_player_id()));
create policy standing_route_lines_read_own on public.standing_route_lines for select to authenticated
  using (exists (select 1 from public.standing_routes r
                  where r.id = route_id and r.player_id = public.current_player_id()));
create policy standing_route_laps_read_own on public.standing_route_laps for select to authenticated
  using (exists (select 1 from public.standing_routes r
                  where r.id = route_id and r.player_id = public.current_player_id()));
revoke all on public.standing_routes, public.standing_route_stops,
              public.standing_route_lines, public.standing_route_laps from public, anon, authenticated;
grant select on public.standing_routes, public.standing_route_stops,
                public.standing_route_lines, public.standing_route_laps to authenticated;

revoke all on function public.standing_routes_cap()      from public, anon, authenticated;
revoke all on function public.standing_route_stops_cap() from public, anon, authenticated;
revoke all on function public.standing_route_lines_cap() from public, anon, authenticated;

-- ── 3. THE SMALL AUTHORITIES ───────────────────────────────────────────────────────────────────
create or replace function public.standing_routes_on()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.wc('standing_routes_enabled') = 'true'::jsonb
$$;
comment on function public.standing_routes_on() is
  '0092: THE one reading of the dark-first switch. Every route path asks this and nothing else.';

-- "Is the keep level met?" — ONE judge, read by 0034's arrival order (sliced below) and by the
-- route's renderer. Judged on THE served range figure (0016's authority) with 0034's 0.01-day
-- dust tolerance (0034 header, CREW paragraph), moved here verbatim, not restated.
create or replace function public.keep_level_met(p_fleet uuid, p_days numeric)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select voyage.endurance_days(p_fleet) >= p_days - 0.01
$$;

revoke all on function public.standing_routes_on()             from public, anon, authenticated;
revoke all on function public.keep_level_met(uuid, numeric)    from public, anon, authenticated;

-- ── 4. THE ONE ENQUEUER ────────────────────────────────────────────────────────────────────────
create or replace function cmd.enqueue(p_player uuid, p_parsed jsonb, p_text text, p_path jsonb, p_lap uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fleet uuid := (p_parsed->>'fleet_id')::uuid;
  v_depth int;
  v_seq   int;
  v_order uuid;
begin
  -- 0047: a SAIL may carry the proposed course. It rides in the ARGS — the order may execute
  -- later, from the queue — and the server verifies it at EXECUTION, against its own raster,
  -- never at issue: what matters is the water at the moment she sails. (Moved here from
  -- cmd.issue by 0092, unchanged.)
  if p_parsed->>'verb' = 'SAIL' and p_path is not null and jsonb_typeof(p_path) = 'array' then
    p_parsed := jsonb_set(p_parsed, '{args,path}', p_path);
  end if;

  select count(*) into v_depth from public.orders
   where fleet_id = v_fleet and status in ('pending', 'active');
  if v_depth >= public.wc_int('order_queue_max') then
    return jsonb_build_object('ok', false, 'error_code', 'E_QUEUE_FULL',
      'error_message', format('That fleet already has %s orders waiting; the limit is %s.',
                              v_depth, public.wc_int('order_queue_max')));
  end if;

  select coalesce(max(seq), 0) + 1 into v_seq from public.orders where fleet_id = v_fleet;

  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, route_lap_id)
  values (v_fleet, p_player, v_seq, btrim(p_text), p_parsed->>'verb', p_parsed->'args', p_lap)
  returning id into v_order;

  update public.fleets set version = version + 1 where id = v_fleet;

  return jsonb_build_object('ok', true, 'order_id', v_order);
end $$;
comment on function cmd.enqueue(uuid, jsonb, text, jsonb, uuid) is
  '0092: THE one enqueuer — depth, seq, insert, version. Callers: cmd.issue (the player''s door) '
  'and cmd.run_standing_route (a route''s refill). Does not execute: the caller runs cmd.advance. '
  'Server-only.';
revoke all on function cmd.enqueue(uuid, jsonb, text, jsonb, uuid) from public, anon, authenticated;

select pg_temp.recut('cmd.issue(uuid, text, integer, jsonb)'::regprocedure, false,
  $i1o$  -- 0047: a SAIL may carry the proposed course. It rides in the ARGS — the order may execute
  -- later, from the queue — and the server verifies it at EXECUTION, against its own raster,
  -- never at issue: what matters is the water at the moment she sails.
  if v_parsed->>'verb' = 'SAIL' and p_path is not null and jsonb_typeof(p_path) = 'array' then
    v_parsed := jsonb_set(v_parsed, '{args,path}', p_path);
  end if;

$i1o$,
  $i1n$  -- 0092: the proposed course is attached by cmd.enqueue, the one enqueuer (below).

$i1n$,
  $i2o$  select count(*) into v_depth from public.orders
   where fleet_id = (v_parsed->>'fleet_id')::uuid and status in ('pending', 'active');
  if v_depth >= public.wc_int('order_queue_max') then
    return jsonb_build_object('ok', false, 'error_code', 'E_QUEUE_FULL',
      'error_message', format('That fleet already has %s orders waiting; the limit is %s.',
                              v_depth, public.wc_int('order_queue_max')),
      'fixes', cmd.fixes('E_QUEUE_FULL', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;

  select coalesce(max(seq), 0) + 1 into v_seq from public.orders
   where fleet_id = (v_parsed->>'fleet_id')::uuid;

  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args)
  values ((v_parsed->>'fleet_id')::uuid, v_player, v_seq, btrim(p_text),
          v_parsed->>'verb', v_parsed->'args')
  returning id into v_order;

  update public.fleets set version = version + 1 where id = (v_parsed->>'fleet_id')::uuid;$i2o$,
  $i2n$  -- 0092: THE ONE ENQUEUER. Depth, seq, the insert and the version bump live in cmd.enqueue,
  -- which a standing route (cmd.run_standing_route) calls too; this door keeps its refusal shape.
  v_res := cmd.enqueue(v_player, v_parsed, p_text, p_path, null);
  if not coalesce((v_res->>'ok')::boolean, false) then
    return v_res || jsonb_build_object('fixes', cmd.fixes(v_res->>'error_code', p_fleet), 'queue', cmd.queue(p_fleet));
  end if;
  v_order := (v_res->>'order_id')::uuid;$i2n$);

-- ── 5. THE RENDERER — one stop, in the player's own grammar ────────────────────────────────────
-- Fixed order (docs/TRADE_ROUTES.md §3.3): SELL lines -> PROVISION (the 0034 keep level, only
-- when not met) -> REPAIR -> BUY lines -> SAIL TO the next stop. It READS what it renders from
-- (cargo on board, fleet_cargo_basis, the preset's days) and never predicts an executor's answer.
create or replace function cmd.standing_route_lines(p_route uuid, p_stop int, p_fleet uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  st      record;
  ln      record;
  c       record;
  v_out   text[] := '{}';
  v_floor numeric;
  v_days  int;
  v_n     int;
  v_next  text;
begin
  select s.*, p.code as port_code into st
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = p_stop;
  if st.route_id is null then
    raise exception 'E_ROUTE_BROKEN: the route has no stop %', p_stop using errcode = 'P0001';
  end if;
  select count(*) into v_n from public.standing_route_stops where route_id = p_route;

  -- 1. SELL — a named good, or one line per good on board ("sell everything"), each with its
  --    floor: the line's own, or what it cost (fleet_cargo_basis, the one basis authority).
  for ln in select l.*, g.code as good_code
              from public.standing_route_lines l left join public.goods g on g.id = l.good_id
             where l.route_id = p_route and l.stop_ord = p_stop and l.kind = 'SELL'
             order by l.ord loop
    for c in select x.code from (
               select ln.good_code as code where ln.good_id is not null
               union
               select e.key
                 from public.ships s cross join lateral jsonb_each(s.cargo) e
                where ln.good_id is null and s.fleet_id = p_fleet and (e.value)::text::numeric > 0
                  and e.key not in (select g2.code from public.standing_route_lines l2
                                      join public.goods g2 on g2.id = l2.good_id
                                     where l2.route_id = p_route and l2.stop_ord = p_stop
                                       and l2.kind = 'SELL')) x
             order by x.code loop
      v_floor := case when ln.at_profit then public.fleet_cargo_basis(p_fleet, c.code) else ln.price_limit end;
      v_out := v_out || (format('SELL %s %s', c.code, coalesce(trim_scale(ln.qty)::text, 'ALL'))
                         || case when v_floor is null then ''
                                 else ' AT >= ' || trim_scale(round(ceil(v_floor * 100) / 100, 2))::text end);
    end loop;
  end loop;

  -- 2. RESUPPLY to the 0034 keep level — a REFERENCE to the preset, read now, never a copy.
  select pr.days into v_days
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id
   where f.id = p_fleet;
  if v_days is not null and not public.keep_level_met(p_fleet, v_days) then
    v_out := v_out || format('PROVISION DAYS %s', v_days);
  end if;

  -- 3. REPAIR (to 100%, the grammar's default).
  if st.repair then
    v_out := v_out || 'REPAIR'::text;
  end if;

  -- 4. BUY.
  for ln in select l.*, g.code as good_code
              from public.standing_route_lines l join public.goods g on g.id = l.good_id
             where l.route_id = p_route and l.stop_ord = p_stop and l.kind = 'BUY'
             order by l.ord loop
    v_out := v_out || (format('BUY %s %s', ln.good_code, coalesce(trim_scale(ln.qty)::text, 'ALL'))
                       || case when ln.price_limit is null then ''
                               else ' AT ' || trim_scale(ln.price_limit)::text end);
  end loop;

  -- 5. SAIL to the next stop. Its course rides as args.path (the generator attaches it).
  select p.code into v_next
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = (p_stop + 1) % v_n;
  v_out := v_out || format('SAIL TO %s', v_next);
  return v_out;
end $$;
revoke all on function cmd.standing_route_lines(uuid, int, uuid) from public, anon, authenticated;

-- ── 6. PAUSE, NOTE, CLOSE — the route's own bookkeeping ────────────────────────────────────────
create or replace function cmd.standing_route_set_paused(p_route uuid, p_reason text, p_code text, p_sentence text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare sr public.standing_routes%rowtype;
begin
  update public.standing_routes set paused_reason = p_reason, updated_at = now()
   where id = p_route returning * into sr;
  -- WRITTEN, never silent: a route that stopped itself while you were away says so in History.
  perform public.emit_event(sr.player_id, 'ROUTE_PAUSED', jsonb_strip_nulls(jsonb_build_object(
    'route', sr.name,
    'fleet', (select name from public.fleets where id = sr.fleet_id),
    'reason', p_reason, 'code', p_code, 'sentence', p_sentence)));
end $$;
revoke all on function cmd.standing_route_set_paused(uuid, text, text, text) from public, anon, authenticated;

create or replace function cmd.standing_route_note_skip(p_order uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare o public.orders%rowtype;
begin
  select * into o from public.orders where id = p_order;
  if o.route_lap_id is null then return; end if;
  update public.standing_route_laps
     set skipped = skipped || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
           'port', (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = o.fleet_id),
           'line', o.raw_text, 'verb', o.verb, 'code', o.error_code, 'sentence', o.error_message)))
   where id = o.route_lap_id;
end $$;
revoke all on function cmd.standing_route_note_skip(uuid) from public, anon, authenticated;

-- LAP CLOSE: figures from the EXECUTORS' OWN RESULTS and the SETTLED DAYS; one ROUTE_LAP event;
-- then the bounded prune (docs/TRADE_ROUTES.md §6).
create or replace function cmd.standing_route_close_lap(p_route uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sr       public.standing_routes%rowtype;
  l        public.standing_route_laps%rowtype;
  v_sold   bigint;
  v_bought bigint;
  v_supp   bigint;
  v_rep    bigint;
  v_wages  bigint;
begin
  select * into sr from public.standing_routes where id = p_route;
  select * into l from public.standing_route_laps where id = sr.lap_id;
  if l.id is null then return; end if;

  select coalesce(round(sum((o.result->>'total')::numeric) filter (where o.verb = 'SELL')), 0),
         coalesce(round(sum((o.result->>'total')::numeric) filter (where o.verb = 'BUY')), 0),
         coalesce(round(sum((o.result->>'cost')::numeric)  filter (where o.verb = 'PROVISION')), 0),
         coalesce(round(sum((o.result->>'cost')::numeric)  filter (where o.verb = 'REPAIR')), 0)
    into v_sold, v_bought, v_supp, v_rep
    from public.orders o
   where o.route_lap_id = l.id and o.status = 'done';
  -- The wage OWED per settled sea-day (0086 writes it into every day's payload). The purse floor
  -- may have charged less; the lap reports what the crew earned.
  select coalesce(round(sum((ve.payload->>'wages')::numeric)), 0) into v_wages
    from public.voyage_events ve
   where ve.voyage_id in (select (o.result->>'voyage_id')::uuid from public.orders o
                           where o.route_lap_id = l.id and o.status = 'done' and o.verb = 'SAIL')
     and ve.payload ? 'wages';

  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, net = v_sold - v_bought - v_supp - v_rep - v_wages
   where id = l.id
  returning * into l;
  update public.standing_routes set lap_id = null, updated_at = now() where id = p_route;

  perform public.emit_event(sr.player_id, 'ROUTE_LAP', jsonb_build_object(
    'route', sr.name, 'fleet', (select name from public.fleets where id = sr.fleet_id),
    'lap', l.lap_no, 'stops', l.stops_done,
    'sold', l.sold, 'bought', l.bought, 'supplies', l.supplies, 'repairs', l.repairs,
    'wages', l.wages, 'net', l.net,
    'skipped', jsonb_array_length(l.skipped), 'skipped_lines', l.skipped));

  -- BOUNDED: route-born orders of every lap but this newest closed one, and laps past the keep.
  delete from public.orders o
   where o.status in ('done', 'skipped')
     and o.route_lap_id in (select x.id from public.standing_route_laps x
                             where x.route_id = p_route and x.id <> l.id);
  delete from public.standing_route_laps x
   where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int('standing_route_lap_keep');
end $$;
revoke all on function cmd.standing_route_close_lap(uuid, timestamptz) from public, anon, authenticated;

-- ── 7. THE GENERATOR — the refill, called ONLY from cmd.advance's queue-dry exit ───────────────
create or replace function cmd.run_standing_route(p_fleet uuid, p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sr       public.standing_routes%rowtype;
  f        public.fleets%rowtype;
  v_n      int;
  cur      record;
  prv      record;
  v_lines  text[];
  v_parsed jsonb;
  v_res    jsonb;
  v_max    int;
  v_sells  int;
  v_per    int;
  v_day    int;
  v_lap    uuid;
  v_written int := 0;
  v_msg    text;
  v_det    text;
  v_ref    jsonb;
  i        int;
begin
  if not public.standing_routes_on() then return 0; end if;
  select * into sr from public.standing_routes where fleet_id = p_fleet for update;
  if sr.id is null or sr.paused_reason is not null then return 0; end if;
  if sr.hold_until is not null and sr.hold_until > p_now then return 0; end if;
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then return 0; end if;

  -- CONTAINED. tick_arrivals settles every player's arrivals in ONE transaction; a bug in here
  -- must pause THIS route, never abort that tick (docs/TRADE_ROUTES.md §4.3).
  begin
    select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
    if v_n < 2 then
      raise exception 'E_ROUTE_BROKEN: the route has % stop(s) and needs two', v_n using errcode = 'P0001';
    end if;
    select s.*, p.code, p.kind into cur
      from public.standing_route_stops s join public.ports p on p.id = s.port_id
     where s.route_id = sr.id and s.ord = sr.stop_cursor % v_n;
    if cur.kind <> 'HARBOUR' then
      raise exception 'E_ROUTE_BROKEN: stop % (%) is not a harbour', cur.ord, cur.code using errcode = 'P0001';
    end if;

    if f.port_id is distinct from cur.port_id then
      select s.*, p.code into prv
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id and s.ord = (sr.stop_cursor - 1 + v_n) % v_n;
      if f.port_id = prv.port_id then
        -- The last SAIL was refused and the player CLEARed it: sail on, and nothing else.
        v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, format('SAIL TO %s', cur.code)),
                              '{fleet_id}', to_jsonb(p_fleet::text));
        v_res := cmd.enqueue(sr.player_id, v_parsed, format('SAIL TO %s', cur.code), prv.course, sr.lap_id);
        if not coalesce((v_res->>'ok')::boolean, false) then
          raise exception 'E_ROUTE_BROKEN: the onward SAIL could not be queued (%)', v_res->>'error_code' using errcode = 'P0001';
        end if;
        return 1;
      end if;
      perform cmd.standing_route_set_paused(sr.id, 'off_route', null,
        format('%s is not at %s or %s.', f.name, cur.code, prv.code));
      return 0;
    end if;

    -- LAP BOUNDARY — the first stop.
    if sr.stop_cursor % v_n = 0 then
      if sr.lap_id is not null then
        perform cmd.standing_route_close_lap(sr.id, p_now);
        sr.lap_id := null;
      end if;
      -- LOSS GUARD: the last N closed laps all lost money.
      if (select count(*) from (select x.net from public.standing_route_laps x
                                 where x.route_id = sr.id and x.closed_at is not null
                                 order by x.lap_no desc limit sr.stop_after_losing_laps) y
           where y.net < 0) >= sr.stop_after_losing_laps then
        perform cmd.standing_route_set_paused(sr.id, 'losing', null,
          format('The last %s laps lost money.', sr.stop_after_losing_laps));
        return 0;
      end if;
      -- PACING (D2): at most N laps START per game-day; then wait for the next one.
      v_per := public.wc_int('standing_route_laps_per_game_day');
      if v_per > 0 then
        v_day := world.game_day(p_now);
        if (select count(*) from public.standing_route_laps x
             where x.route_id = sr.id and world.game_day(x.started_at) = v_day) >= v_per then
          update public.standing_routes
             set hold_until = to_timestamp(((v_day + 1) * public.wc_num('game_day_seconds'))::double precision),
                 updated_at = now()
           where id = sr.id;
          return 0;
        end if;
      end if;
    end if;

    -- RESERVE GUARD: never spend below what the player keeps back.
    if (select ducats from public.players where id = sr.player_id) < sr.reserve then
      perform cmd.standing_route_set_paused(sr.id, 'reserve', null,
        format('The company has less than %s kept back.', sr.reserve));
      return 0;
    end if;

    if sr.lap_id is null then
      insert into public.standing_route_laps (route_id, lap_no, started_at)
      values (sr.id, sr.lap_no + 1, p_now) returning id into v_lap;
      update public.standing_routes set lap_id = v_lap, lap_no = lap_no + 1, hold_until = null
       where id = sr.id;
      sr.lap_id := v_lap;
    end if;

    v_lines := cmd.standing_route_lines(sr.id, cur.ord, p_fleet);
    -- Only the "sell everything" expansion can outgrow one queue (the lines cap bounds the rest):
    -- drop the trailing SELL lines and note them, so the SAIL always fits.
    v_max := public.wc_int('order_queue_max');
    select count(*) into v_sells from unnest(v_lines) x where x like 'SELL %';
    while array_length(v_lines, 1) > v_max and v_sells > 0 loop
      update public.standing_route_laps
         set skipped = skipped || jsonb_build_array(jsonb_build_object(
               'port', cur.code, 'line', v_lines[v_sells], 'verb', 'SELL', 'code', 'E_QUEUE_FULL'))
       where id = sr.lap_id;
      v_lines := v_lines[1:v_sells - 1] || v_lines[v_sells + 1:];
      v_sells := v_sells - 1;
    end loop;

    for i in 1 .. array_length(v_lines, 1) loop
      -- THE ONE GRAMMAR decides what the line means; the fleet is the route's, always.
      v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, v_lines[i]), '{fleet_id}', to_jsonb(p_fleet::text));
      v_res := cmd.enqueue(sr.player_id, v_parsed, v_lines[i],
                           case when v_parsed->>'verb' = 'SAIL' then cur.course end, sr.lap_id);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'E_ROUTE_BROKEN: "%" could not be queued (%)', v_lines[i], v_res->>'error_code' using errcode = 'P0001';
      end if;
      v_written := v_written + 1;
    end loop;

    update public.standing_route_laps set stops_done = stops_done + 1 where id = sr.lap_id;
    update public.standing_routes set stop_cursor = (cur.ord + 1) % v_n, updated_at = now() where id = sr.id;
    return v_written;
  exception when others then
    v_msg := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref := cmd.refusal_caught(v_msg, v_det);
    perform cmd.standing_route_set_paused(sr.id, 'error', v_ref->>'code', v_ref->>'sentence');
    return 0;
  end;
end $$;
comment on function cmd.run_standing_route(uuid, timestamptz) is
  '0092: THE route refill. One caller: cmd.advance''s queue-dry exit (at most once per call). '
  'Writes the next stop''s orders through cmd.parse and cmd.enqueue; executes nothing. Contained: '
  'an error pauses this route (ROUTE_PAUSED) and returns 0. Server-only.';
revoke all on function cmd.run_standing_route(uuid, timestamptz) from public, anon, authenticated;

-- ── 8. THE RE-CUTS: the queue runner, the arrival order, the clock ─────────────────────────────
select pg_temp.recut('cmd.advance(uuid, timestamptz)'::regprocedure, false,
  $a0o$  guard  int := 0;$a0o$,
  $a0n$  guard  int := 0;
  v_refilled boolean := false;   -- 0092: a standing route refills at most ONCE per call$a0n$,
  $a1o$    exit when o.id is null;$a1o$,
  $a1n$    -- 0092 HUNK A: the queue ran dry in port. If a standing route stands on this fleet it
    -- writes the next stop's orders ONCE (cmd.run_standing_route), and they run like any other.
    if o.id is null then
      exit when v_refilled;
      v_refilled := true;
      exit when coalesce(cmd.run_standing_route(p_fleet, p_now), 0) = 0;
      continue;
    end if;$a1n$,
  $a2o$    exit when not coalesce((v_res->>'ok')::boolean, false);$a2o$,
  $a2n$    -- 0092 HUNK B (D1): a ROUTE's refused trade line is stepped over and written on the lap;
    -- a route's refused SAIL — and every ordinary order — halts the fleet exactly as before.
    if not coalesce((v_res->>'ok')::boolean, false) then
      exit when o.route_lap_id is null or o.verb = 'SAIL';
      update public.orders set status = 'skipped' where id = o.id;
      perform cmd.standing_route_note_skip(o.id);
    end if;$a2n$);

select pg_temp.recut('cmd.run_standing_provision(uuid)'::regprocedure, false,
  $p0o$  if f.id is null or f.provision_preset_id is null or f.status <> 'DOCKED' then
    return null;
  end if;$p0o$,
  $p0n$  if f.id is null or f.provision_preset_id is null or f.status <> 'DOCKED' then
    return null;
  end if;
  -- 0092: a RUNNING standing route places the keep order itself, after its sales and before its
  -- buys (docs/TRADE_ROUTES.md §3.4). The keep level keeps ONE author, the preset.
  if public.standing_routes_on()
     and exists (select 1 from public.standing_routes sr
                  where sr.fleet_id = p_fleet and sr.paused_reason is null) then
    return null;
  end if;$p0n$,
  $p1o$  v_before := voyage.endurance_days(p_fleet);
  if v_before >= pr.days - 0.01 then$p1o$,
  $p1n$  v_before := voyage.endurance_days(p_fleet);
  if public.keep_level_met(p_fleet, pr.days) then   -- 0092: the ONE judge, shared with the route$p1n$);

select pg_temp.recut('public.tick_arrivals(timestamptz)'::regprocedure, false,
  $t0o$  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now);$t0o$,
  $t0n$  -- 0092: A ROUTE HELD FOR PACING WAKES HERE — the same shape as the yard release above, on
  -- the same job. No new job, no new schedule (docs/TRADE_ROUTES.md §4.3).
  for r in select f.id from public.fleets f
             join public.standing_routes sr on sr.fleet_id = f.id
            where public.standing_routes_on()
              and sr.paused_reason is null and sr.hold_until is not null and sr.hold_until <= p_now
              and f.status = 'DOCKED'
              for update of f skip locked loop
    update public.standing_routes set hold_until = null where fleet_id = r.id;
    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;

  return jsonb_build_object('fleets_touched', v_fleets, 'days_resolved', v_days, 'at', p_now);$t0n$);

-- ── 9. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.standing_routes()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_on     boolean := public.standing_routes_on();
  r        record;
begin
  if v_player is not null then
    -- DESIGN D.2: the read is the catch-up — every route fleet is settled before a figure is served.
    for r in select fleet_id from public.standing_routes
              where player_id = v_player and fleet_id is not null loop
      perform voyage.settle(r.fleet_id);
    end loop;
  end if;

  return jsonb_build_object(
    'enabled',           v_on,
    'max',               public.wc_int('standing_route_max'),
    'stop_max',          public.wc_int('standing_route_stop_max'),
    'line_max',          public.wc_int('order_queue_max') - 3,
    'laps_per_game_day', public.wc_int('standing_route_laps_per_game_day'),
    'routes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', sr.id, 'name', sr.name, 'reserve', sr.reserve,
        'stop_after_losing_laps', sr.stop_after_losing_laps,
        'fleet', case when f.id is not null then jsonb_build_object('id', f.id, 'name', f.name) end,
        'cursor', sr.stop_cursor, 'lap_no', sr.lap_no,
        -- STATE IS DERIVED, never stored: a failed order in her queue IS "stopped".
        'state', case when not v_on then 'off'
                      when f.id is null then 'unassigned'
                      when sr.paused_reason is not null then 'paused'
                      when fo.id is not null then 'stopped'
                      when sr.hold_until is not null and sr.hold_until > now() then 'waiting'
                      when f.status = 'SAILING' then 'sailing'
                      else 'in_port' end,
        'paused_reason', sr.paused_reason,
        'next_lap_at', case when sr.hold_until > now() then sr.hold_until end,
        'stopped', case when fo.id is not null then jsonb_strip_nulls(jsonb_build_object(
                     'seq', fo.seq, 'line', fo.raw_text, 'code', fo.error_code,
                     'sentence', fo.error_message, 'figures', fo.error_figures)) end,
        'heading_to', (select p.code from public.standing_route_stops s join public.ports p on p.id = s.port_id
                        where s.route_id = sr.id
                          and s.ord = sr.stop_cursor % greatest(1, (select count(*) from public.standing_route_stops s2 where s2.route_id = sr.id))),
        'stops', (select coalesce(jsonb_agg(jsonb_build_object(
                    'ord', s.ord, 'port', p.code, 'course', s.course, 'repair', s.repair,
                    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                                'ord', l.ord, 'kind', l.kind, 'good', g.code, 'qty', l.qty,
                                'price_limit', l.price_limit, 'at_profit', l.at_profit) order by l.ord), '[]'::jsonb)
                                from public.standing_route_lines l left join public.goods g on g.id = l.good_id
                               where l.route_id = s.route_id and l.stop_ord = s.ord)) order by s.ord), '[]'::jsonb)
                    from public.standing_route_stops s join public.ports p on p.id = s.port_id
                   where s.route_id = sr.id),
        'lap', (select jsonb_build_object('lap_no', x.lap_no, 'started_at', x.started_at, 'stops_done', x.stops_done,
                                          'skipped', jsonb_array_length(x.skipped))
                  from public.standing_route_laps x where x.id = sr.lap_id),
        'laps', (select coalesce(jsonb_agg(jsonb_build_object(
                   'lap_no', x.lap_no, 'started_at', x.started_at, 'closed_at', x.closed_at,
                   'stops_done', x.stops_done, 'sold', x.sold, 'bought', x.bought,
                   'supplies', x.supplies, 'repairs', x.repairs, 'wages', x.wages, 'net', x.net,
                   'skipped', x.skipped) order by x.lap_no desc), '[]'::jsonb)
                   from (select * from public.standing_route_laps x0
                          where x0.route_id = sr.id and x0.closed_at is not null
                          order by x0.lap_no desc limit 10) x)
      ) order by sr.created_at, sr.id), '[]'::jsonb)
        from public.standing_routes sr
        left join public.fleets f on f.id = sr.fleet_id
        left join lateral (select o.* from public.orders o
                            where o.fleet_id = sr.fleet_id and o.status = 'failed'
                            order by o.seq limit 1) fo on true
       where sr.player_id = v_player));
end $$;
comment on function world.standing_routes() is
  '0092: the company''s standing routes — stops, lines, derived state, the open lap and the last '
  'ten closed laps with every figure — and the knobs. Settles each route fleet first. No player id.';

-- ── 10. THE VERBS — none takes a player id; all refuse E_UNAVAILABLE while the switch is off ──
create or replace function cmd.standing_route_refusal(p_code text, p_sentence text, p_fix text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error_code', p_code, 'error_message', p_sentence,
                            'fixes', jsonb_build_array(p_fix))
$$;
revoke all on function cmd.standing_route_refusal(text, text, text) from public, anon, authenticated;

create or replace function cmd.standing_route_save(p_route uuid, p_name text, p_stops jsonb,
                                                   p_reserve bigint, p_losing int)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_n      int;
  s        jsonb;
  ln       jsonb;
  pt       jsonb;
  k        int;
  j        int;
  v_port   record;
  v_prev   uuid;
  v_first  uuid;
  v_good   uuid;
  v_kind   text;
  f        public.fleets%rowtype;
  v_at     uuid;
  v_anchor int;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  v_n := case when jsonb_typeof(p_stops) = 'array' then jsonb_array_length(p_stops) else 0 end;
  if v_n < 2 or v_n > public.wc_int('standing_route_stop_max') then
    return cmd.standing_route_refusal('E_PARSE',
      format('A route needs 2 to %s stops.', public.wc_int('standing_route_stop_max')), '(add or remove a stop)');
  end if;

  begin
    if p_route is null then
      if v_name is null then
        return cmd.standing_route_refusal('E_PARSE', 'A route needs a name.', '(name it)');
      end if;
      insert into public.standing_routes (player_id, name, reserve, stop_after_losing_laps)
      values (v_player, v_name, coalesce(p_reserve, 0),
              coalesce(p_losing, public.wc_int('standing_route_losing_laps')))
      returning * into sr;
    else
      select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
      if sr.id is null then
        return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
      end if;
      update public.standing_routes
         set name = coalesce(v_name, name), reserve = coalesce(p_reserve, reserve),
             stop_after_losing_laps = coalesce(p_losing, stop_after_losing_laps), updated_at = now()
       where id = sr.id returning * into sr;
      delete from public.standing_route_stops where route_id = sr.id;
    end if;

    for k in 0 .. v_n - 1 loop
      s := p_stops->k;
      select p.id, p.kind, p.code into v_port from public.ports p
       where p.code = upper(btrim(coalesce(s->>'port', '')));
      if v_port.id is null then
        raise exception 'E_NO_SUCH_PORT: there is no port "%"', coalesce(s->>'port', '') using errcode = 'P0001';
      end if;
      if v_port.kind <> 'HARBOUR' then
        raise exception 'E_UNAVAILABLE: % is open water; a route stops only where there is a market', v_port.code using errcode = 'P0001';
      end if;
      if v_port.id = v_prev or (k = v_n - 1 and v_port.id = v_first) then
        raise exception 'E_SAME_DEST: two stops in a row are both %', v_port.code using errcode = 'P0001';
      end if;
      if jsonb_typeof(s->'course') <> 'array' or jsonb_array_length(s->'course') < 2 then
        raise exception 'E_BAD_PATH: the leg from % has no course', v_port.code using errcode = 'P0001';
      end if;
      for pt in select * from jsonb_array_elements(s->'course') loop
        if jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
           or jsonb_typeof(pt->0) <> 'number' or jsonb_typeof(pt->1) <> 'number'
           or abs((pt->>0)::numeric) > 90 or abs((pt->>1)::numeric) > 180 then
          raise exception 'E_BAD_PATH: the leg from % is not a list of points on the sphere', v_port.code using errcode = 'P0001';
        end if;
      end loop;
      insert into public.standing_route_stops (route_id, ord, port_id, course, repair)
      values (sr.id, k, v_port.id, s->'course', coalesce((s->>'repair')::boolean, false));
      if k = 0 then v_first := v_port.id; end if;
      v_prev := v_port.id;

      j := 0;
      for ln in select * from jsonb_array_elements(coalesce(s->'lines', '[]'::jsonb)) loop
        v_kind := upper(btrim(coalesce(ln->>'kind', '')));
        if v_kind not in ('SELL', 'BUY') then
          raise exception 'E_PARSE: a stop''s line is SELL or BUY, not "%"', coalesce(ln->>'kind', '') using errcode = 'P0001';
        end if;
        v_good := null;
        if nullif(btrim(coalesce(ln->>'good', '')), '') is not null then
          select id into v_good from public.goods where code = btrim(ln->>'good');
          if v_good is null then
            raise exception 'E_NO_SUCH_GOOD: there is no good "%"', ln->>'good' using errcode = 'P0001';
          end if;
        elsif v_kind = 'BUY' then
          raise exception 'E_PARSE: a BUY line names a good' using errcode = 'P0001';
        end if;
        insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit)
        values (sr.id, k, j, v_kind, v_good,
                nullif(ln->>'qty', '')::numeric, nullif(ln->>'price_limit', '')::numeric,
                coalesce((ln->>'at_profit')::boolean, false));
        j := j + 1;
      end loop;
    end loop;
  exception
    when unique_violation then
      return cmd.standing_route_refusal('E_NAME_TAKEN', format('You already keep a route named "%s".', v_name), '(pick another name)');
    when check_violation then
      if sqlerrm like '%name_length%' then
        return cmd.standing_route_refusal('E_PARSE', 'A name is 2 to 24 characters.', '(shorten or lengthen the name)');
      end if;
      return cmd.standing_route_refusal('E_PARSE', 'A quantity, a price and a keep-back figure are positive numbers.', '(check the numbers)');
    when invalid_text_representation then
      return cmd.standing_route_refusal('E_PARSE', 'A quantity or a price is not a number.', '(check the numbers)');
    when others then
      if sqlerrm ~ '^E_[A-Z_]+:' then
        return cmd.standing_route_refusal(split_part(sqlerrm, ':', 1),
          btrim(substr(sqlerrm, length(split_part(sqlerrm, ':', 1)) + 2)), '(change the route and save again)');
      end if;
      raise;
  end;

  -- An EDIT of an assigned route re-anchors on where its fleet is now; if the fleet is at no stop
  -- of the edited route, the route pauses rather than guess (docs/TRADE_ROUTES.md §5).
  if sr.fleet_id is not null then
    select * into f from public.fleets where id = sr.fleet_id;
    v_at := case when f.status = 'SAILING'
                 then (select dest_port_id from public.voyages where fleet_id = f.id and status = 'SAILING')
                 else f.port_id end;
    select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = v_at;
    if v_anchor is null then
      perform cmd.standing_route_set_paused(sr.id, 'edited', null,
        format('%s is not at or bound for a stop of the edited route.', f.name));
    else
      update public.standing_routes
         set stop_cursor = case when f.status <> 'SAILING'
                                 and exists (select 1 from public.orders o where o.fleet_id = f.id
                                              and o.status = 'pending' and o.route_lap_id is not null)
                                then (v_anchor + 1) % v_n else v_anchor end,
             paused_reason = case when paused_reason = 'edited' then null else paused_reason end
       where id = sr.id;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', sr.id, 'name', sr.name, 'stops', v_n);
end $$;

create or replace function cmd.standing_route_delete(p_route uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  -- Orders already queued stay, as ORDINARY orders under the ordinary halt law: the laps cascade
  -- away and orders.route_lap_id goes null with them (the FK's on delete set null).
  delete from public.standing_routes where id = sr.id;
  return jsonb_build_object('ok', true, 'deleted', sr.name);
end $$;

create or replace function cmd.standing_route_assign(p_route uuid, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
  f        public.fleets%rowtype;
  v_other  text;
  v_anchor int;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;

  -- Whatever fleet held it is released: its pending route orders become ordinary orders.
  if sr.fleet_id is not null and sr.fleet_id is distinct from p_fleet then
    update public.orders set route_lap_id = null
     where fleet_id = sr.fleet_id and status = 'pending' and route_lap_id is not null;
  end if;

  if p_fleet is null then
    update public.standing_routes
       set fleet_id = null, lap_id = null, hold_until = null, paused_reason = null, updated_at = now()
     where id = sr.id;
    return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', null);
  end if;

  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id <> v_player then
    return cmd.standing_route_refusal('E_NO_SUCH_FLEET', 'That fleet is not yours.', '(pick one of your own fleets)');
  end if;
  select name into v_other from public.standing_routes where fleet_id = p_fleet and id <> sr.id;
  if v_other is not null then
    return cmd.standing_route_refusal('E_ROUTE_TAKEN', format('%s already runs the route "%s".', f.name, v_other),
      '(stop that route first)');
  end if;
  if f.status <> 'DOCKED' then
    return cmd.standing_route_refusal('E_NOT_DOCKED', format('%s must be in port at one of the route''s stops to start it.', f.name),
      '(start it when the fleet is in port)');
  end if;
  select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = f.port_id;
  if v_anchor is null then
    return cmd.standing_route_refusal('E_NOT_ON_ROUTE',
      format('%s is in %s, which is not a stop on this route.', f.name, (select name from public.ports where id = f.port_id)),
      '(sail to one of the stops first)');
  end if;
  if f.provision_preset_id is null then
    return cmd.standing_route_refusal('E_NO_KEEP', 'Set how many days of supplies to keep first.',
      '(set the supplies to keep for this fleet)');
  end if;

  update public.standing_routes
     set fleet_id = p_fleet, stop_cursor = v_anchor, paused_reason = null, hold_until = null,
         lap_id = null, updated_at = now()
   where id = sr.id;
  -- The route starts NOW: the one queue runner, which refills when the queue is dry.
  perform cmd.advance(p_fleet, now());
  return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', f.name,
    'queue', cmd.queue(p_fleet), 'version', (select version from public.fleets where id = p_fleet));
end $$;

create or replace function cmd.standing_route_pause(p_route uuid, p_paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  sr       public.standing_routes%rowtype;
begin
  if v_player is null then
    return cmd.standing_route_refusal('E_NOT_SIGNED_IN', 'Nobody is signed in.', '(sign in first)');
  end if;
  if not public.standing_routes_on() then
    return cmd.standing_route_refusal('E_UNAVAILABLE', 'Routes are not open yet.', '(wait for routes to open)');
  end if;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if coalesce(p_paused, true) then
    update public.standing_routes set paused_reason = 'player', updated_at = now() where id = sr.id;
    return jsonb_build_object('ok', true, 'route', sr.name, 'paused', true);
  end if;
  update public.standing_routes set paused_reason = null, hold_until = null, updated_at = now() where id = sr.id;
  if sr.fleet_id is not null then
    perform cmd.advance(sr.fleet_id, now());
  end if;
  return jsonb_build_object('ok', true, 'route', sr.name, 'paused', false);
end $$;

revoke all on function world.standing_routes()                                   from public, anon;
grant execute on function world.standing_routes()                                to authenticated;
revoke all on function cmd.standing_route_save(uuid, text, jsonb, bigint, int)   from public, anon;
grant execute on function cmd.standing_route_save(uuid, text, jsonb, bigint, int) to authenticated;
revoke all on function cmd.standing_route_delete(uuid)                           from public, anon;
grant execute on function cmd.standing_route_delete(uuid)                        to authenticated;
revoke all on function cmd.standing_route_assign(uuid, uuid)                     from public, anon;
grant execute on function cmd.standing_route_assign(uuid, uuid)                  to authenticated;
revoke all on function cmd.standing_route_pause(uuid, boolean)                   from public, anon;
grant execute on function cmd.standing_route_pause(uuid, boolean)                to authenticated;

-- ── 11. THE CATALOGUE — five rows, sliced in after 0087's last row ─────────────────────────────
select pg_temp.recut('public.client_rpc_entry_points()'::regprocedure, false,
  $c0$      ('cmd',         'preview_fulfil',      'uuid, uuid')
    ) as t(s, f, a)$c0$,
  $c1$      ('cmd',         'preview_fulfil',      'uuid, uuid'),
      -- 0092: standing routes — the read and the four verbs. None takes a player id.
      ('world',       'standing_routes',       ''),
      ('cmd',         'standing_route_save',   'uuid, text, jsonb, bigint, int'),
      ('cmd',         'standing_route_delete', 'uuid'),
      ('cmd',         'standing_route_assign', 'uuid, uuid'),
      ('cmd',         'standing_route_pause',  'uuid, boolean')
    ) as t(s, f, a)$c1$);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0092-4000-8000-000000000001';
  c_auth2   constant uuid := '00000000-0092-4000-8000-000000000002';
  c_uuid    constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  v_def     text;
  v_back    text;
  v_base    int;
  v_player  uuid;
  v_player2 uuid;
  v_fleet   uuid;
  v_fleet2  uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_cad     uuid;
  v_good    text;
  v_good_id uuid;
  v_out     jsonb;
  v_back_c  jsonb;
  v_res     jsonb;
  v_read    jsonb;
  v_route   uuid;
  v_r2      uuid;
  v_r3      uuid;
  v_old     text := '';
  v_new     text := '';
  v_p0      bigint;
  v_p1      bigint;
  v_n       int;
  v_n2      int;
  v_net     bigint;
  v_lap     public.standing_route_laps%rowtype;
  v_sr      public.standing_routes%rowtype;
  v_lines   text[];
  v_parsed  jsonb;
  v_hold    timestamptz;
  v_skip    text;
  v_line    text;
  v_stop    text;
  v_orders0 int;
  v_ev      int;
  v_fn      text;
  v_mkt_l   jsonb;
  k         int;
  j         int;
  -- receipts
  r_laps    int;
  r_net     bigint;
  r_sold    bigint;
  r_wages   bigint;
  r_orders  int;
begin
  -- (a) PARITY BY CONSTRUCTION: substituting 0092's hunks back OUT of every re-cut body must
  --     reproduce its pre-image to the character, with its ACL unmoved.
  v_def := pg_get_functiondef('cmd.advance(uuid, timestamptz)'::regprocedure);
  v_back := replace(replace(replace(v_def,
    E'  guard  int := 0;\n  v_refilled boolean := false;   -- 0092: a standing route refills at most ONCE per call',
    '  guard  int := 0;'),
    $a1n$    -- 0092 HUNK A: the queue ran dry in port. If a standing route stands on this fleet it
    -- writes the next stop's orders ONCE (cmd.run_standing_route), and they run like any other.
    if o.id is null then
      exit when v_refilled;
      v_refilled := true;
      exit when coalesce(cmd.run_standing_route(p_fleet, p_now), 0) = 0;
      continue;
    end if;$a1n$, '    exit when o.id is null;'),
    $a2n$    -- 0092 HUNK B (D1): a ROUTE's refused trade line is stepped over and written on the lap;
    -- a route's refused SAIL — and every ordinary order — halts the fleet exactly as before.
    if not coalesce((v_res->>'ok')::boolean, false) then
      exit when o.route_lap_id is null or o.verb = 'SAIL';
      update public.orders set status = 'skipped' where id = o.id;
      perform cmd.standing_route_note_skip(o.id);
    end if;$a2n$, '    exit when not coalesce((v_res->>''ok'')::boolean, false);');
  if v_back <> (select def from defs_before_0092 where fn = 'cmd.advance(uuid, timestamptz)') or v_def = v_back then
    raise exception '0092 self-assert FAIL: cmd.advance is not its pre-image plus only the refill, the flag and the skip rule';
  end if;

  v_def := pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure);
  v_back := regexp_replace(v_def,
    '  -- 0092: A ROUTE HELD FOR PACING WAKES HERE.*?  end loop;\n\n(  return jsonb_build_object\(''fleets_touched'')', '\1');
  if v_back <> (select def from defs_before_0092 where fn = 'public.tick_arrivals(timestamptz)') or v_def = v_back then
    raise exception '0092 self-assert FAIL: public.tick_arrivals is not its pre-image plus only the wake loop';
  end if;

  v_def := pg_get_functiondef('cmd.run_standing_provision(uuid)'::regprocedure);
  v_back := replace(regexp_replace(v_def,
      '\n  -- 0092: a RUNNING standing route places.*?    return null;\n  end if;', ''),
    '  if public.keep_level_met(p_fleet, pr.days) then   -- 0092: the ONE judge, shared with the route',
    '  if v_before >= pr.days - 0.01 then');
  if v_back <> (select def from defs_before_0092 where fn = 'cmd.run_standing_provision(uuid)') or v_def = v_back then
    raise exception '0092 self-assert FAIL: cmd.run_standing_provision is not its pre-image plus only the route return and the shared judge';
  end if;

  v_def := pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure);
  v_back := regexp_replace(v_def,
    E',\n      -- 0092: standing routes.*?(\n    \\) as t\\(s, f, a\\))', E'\\1');
  if v_back <> (select def from defs_before_0092 where fn = 'public.client_rpc_entry_points()') or v_def = v_back then
    raise exception '0092 self-assert FAIL: client_rpc_entry_points is not its pre-image with the five route rows added';
  end if;

  for v_fn in select fn from defs_before_0092 loop
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0092 where fn = v_fn) then
      raise exception '0092 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE PROBE — real houses, a real route, the tick and nothing else; then rolled back.
  --     The BASELINE is taken first: the rollback check is a DELTA, never a world count (0034's
  --     production lesson, 2026-08-23).
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    update public.world_config set value = to_jsonb(0) where key = 'standing_route_laps_per_game_day';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    select id into v_cad from public.ports where code = 'CAD';
    v_player  := public.new_house(c_auth,  'Casa da Rota', 'PRT');
    v_player2 := public.new_house(c_auth2, 'Casa Vizinha', 'PRT');
    select id into v_fleet  from public.fleets where player_id = v_player;
    select id into v_fleet2 from public.fleets where player_id = v_player2;
    -- The legs are the served roadsteads (0086's probe passage: open Atlantic both ways).
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_out from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
    v_back_c := jsonb_build_array(v_out->1, v_out->0);

    -- The good: offered and in stock at Lisbon (the served market), not refused at Funchal, and the
    -- one Funchal bids most for over Lisbon's ask (world.price, the one price authority).
    perform cmd.assume_identity(c_auth);
    v_mkt_l := world.market(v_lis);
    select gl->>'code' into v_good
      from jsonb_array_elements(v_mkt_l->'goods') gl
      join public.goods g on g.code = gl->>'code'
      cross join lateral world.price(v_fnc, g.id) pf
     where (gl->>'offered')::boolean and (gl->>'available')::boolean and (gl->>'stock')::numeric >= 60
       and (gl->>'buy')::numeric between 5 and 60
       and not public.culture_refuses((select culture from public.ports where id = v_fnc), g.culture_mask)
     order by pf.bid - (gl->>'buy')::numeric desc, g.code
     limit 1;
    if v_good is null then
      raise exception '0092 self-assert FAIL: no good is bought at Lisbon and sold at Funchal for the probe';
    end if;
    select id into v_good_id from public.goods where code = v_good;

    -- ── PARITY: the same eighteen orders through the OLD door and the NEW, answers compared ──
    for j in 1 .. 2 loop
      begin
        perform cmd.assume_identity(c_auth2);
        v_res := '[]'::jsonb;
        for k in 1 .. 18 loop
          v_res := v_res || jsonb_build_array(case j
            when 1 then pg_temp.issue_before_0092(v_fleet2,
                     case when k = 1 then format('BUY %s 10', v_good) when k = 2 then format('SELL %s 5', v_good)
                          when k = 3 then 'FLY away' when k = 4 then format('BUY %s 10', v_good)
                          when k = 5 then 'SAIL TO FNC' else format('BUY %s 1', v_good) end,
                     case when k = 4 then 999999 end, case when k = 5 then v_out end)
            else cmd.issue(v_fleet2,
                     case when k = 1 then format('BUY %s 10', v_good) when k = 2 then format('SELL %s 5', v_good)
                          when k = 3 then 'FLY away' when k = 4 then format('BUY %s 10', v_good)
                          when k = 5 then 'SAIL TO FNC' else format('BUY %s 1', v_good) end,
                     case when k = 4 then 999999 end, case when k = 5 then v_out end) end);
        end loop;
        if j = 1 then v_old := regexp_replace(v_res::text, c_uuid, 'U', 'g');
        else v_new := regexp_replace(v_res::text, c_uuid, 'U', 'g'); end if;
        raise exception using errcode = 'P0921', message = '0092 parity rollback';
      exception when sqlstate 'P0921' then null;
      end;
    end loop;
    if v_old <> v_new or v_new not like '%E_QUEUE_FULL%' or v_new not like '%E_STALE%'
       or v_new not like '%E_PARSE%' then
      raise exception '0092 self-assert FAIL: cmd.issue answers differ from its pre-image (or the probe never reached E_QUEUE_FULL / E_STALE / E_PARSE): old % / new %',
        left(v_old, 400), left(v_new, 400);
    end if;

    -- ── THE HALT LAW, UNCHANGED FOR AN ORDINARY FLEET: [failed, pending] stays put ─────────────
    perform cmd.assume_identity(c_auth2);   -- the parity blocks rolled their identity back with them
    perform cmd.issue(v_fleet2, format('SELL %s 10', v_good));   -- nothing on board: fails
    perform cmd.issue(v_fleet2, format('BUY %s 10', v_good));    -- queued behind it
    perform cmd.advance(v_fleet2, now());
    if (select count(*) from public.orders where fleet_id = v_fleet2 and status = 'failed') <> 1
       or (select count(*) from public.orders where fleet_id = v_fleet2 and status = 'pending') <> 1 then
      raise exception '0092 self-assert FAIL: a route-less fleet with [failed, pending] did not stay halted';
    end if;
    perform cmd.clear(v_fleet2, false);

    -- ── DARK: switch off, every verb refuses and nothing is written ───────────────────────────
    perform cmd.assume_identity(c_auth);
    update public.world_config set value = 'false'::jsonb where key = 'standing_routes_enabled';
    if cmd.standing_route_save(null, 'Dark', '[]'::jsonb, null, null)->>'error_code' <> 'E_UNAVAILABLE'
       or cmd.standing_route_delete(gen_random_uuid())->>'error_code' <> 'E_UNAVAILABLE'
       or cmd.standing_route_assign(gen_random_uuid(), v_fleet)->>'error_code' <> 'E_UNAVAILABLE'
       or cmd.standing_route_pause(gen_random_uuid(), true)->>'error_code' <> 'E_UNAVAILABLE'
       or (world.standing_routes()->>'enabled')::boolean then
      raise exception '0092 self-assert FAIL: with the switch off a verb answered, or the read says enabled';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';

    -- ── THE ROUTE: Lisbon (sell everything, buy 20 of the good) ⇄ Funchal (sell everything) ─────
    v_res := cmd.standing_route_save(null, 'Probe run', jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_out, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL'),
        jsonb_build_object('kind', 'BUY', 'good', v_good, 'qty', 20))),
      jsonb_build_object('port', 'FNC', 'course', v_back_c, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL')))), 0, 20);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0092 self-assert FAIL: the probe route was refused: %', v_res;
    end if;
    v_route := (v_res->>'id')::uuid;

    -- No keep level yet: refused E_NO_KEEP, or the first SAIL would fail E_ENDURANCE while away.
    if cmd.standing_route_assign(v_route, v_fleet)->>'error_code' <> 'E_NO_KEEP' then
      raise exception '0092 self-assert FAIL: a fleet with no keep level was given a route';
    end if;
    v_res := cmd.provision_preset_save(null, 'Route keep', 12);
    perform cmd.provision_preset_apply(v_fleet, (v_res->>'id')::uuid);

    select ducats into v_p0 from public.players where id = v_player;
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    if not coalesce((v_res->>'ok')::boolean, false)
       or (select status from public.fleets where id = v_fleet) <> 'SAILING'
       or (select count(*) from public.orders where fleet_id = v_fleet and route_lap_id is not null
            and verb in ('BUY', 'SAIL') and status = 'done') <> 2 then
      raise exception '0092 self-assert FAIL: assign at Lisbon did not buy and sail through the queue: % / orders %',
        v_res, (select jsonb_agg(jsonb_build_array(verb, status, error_code, raw_text)) from public.orders where fleet_id = v_fleet);
    end if;

    -- ── AFK: three laps, driven by tick_arrivals ALONE (no read, no issue) ─────────────────────
    for k in 1 .. 6 loop
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute',
             eta         = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform public.tick_arrivals(now());
      if (select status from public.fleets where id = v_fleet) <> 'SAILING' then
        raise exception '0092 self-assert FAIL: after tick % the route fleet is % (route %), not sailing on: orders %',
          k, (select status from public.fleets where id = v_fleet),
          (select to_jsonb(sr) from public.standing_routes sr where id = v_route),
          (select jsonb_agg(jsonb_build_array(verb, status, error_code, raw_text) order by seq) from public.orders where fleet_id = v_fleet);
      end if;
      if k = 2 then
        -- ONE EXECUTOR: every BOUGHT / SOLD of this house so far is a done route order (before
        -- any prune): the route traded through the queue and nowhere else.
        select count(*) into v_ev from public.events where player_id = v_player and kind in ('BOUGHT', 'SOLD');
        select count(*) into v_n from public.orders
         where fleet_id = v_fleet and route_lap_id is not null and status = 'done' and verb in ('BUY', 'SELL');
        if v_ev <> v_n or v_ev < 2 then
          raise exception '0092 self-assert FAIL: % BOUGHT/SOLD events but % done route trade orders — a second executor', v_ev, v_n;
        end if;
      end if;
    end loop;

    select count(*), sum(net), sum(sold), sum(wages) into r_laps, r_net, r_sold, r_wages
      from public.standing_route_laps where route_id = v_route and closed_at is not null;
    select * into v_lap from public.standing_route_laps where route_id = v_route and lap_no = 1;
    if r_laps <> 3 or r_sold <= 0 or r_wages <= 0
       or v_lap.net <> v_lap.sold - v_lap.bought - v_lap.supplies - v_lap.repairs - v_lap.wages then
      raise exception '0092 self-assert FAIL: after six ticks: % closed laps (want 3), sold %, wages %, lap 1 %',
        r_laps, r_sold, r_wages, to_jsonb(v_lap);
    end if;
    select count(*) into v_ev from public.events where player_id = v_player and kind = 'ROUTE_LAP';
    perform cmd.assume_identity(c_auth);
    if v_ev <> 3 or (select count(*) from jsonb_array_elements(world.ledger(null, 200)->'events') e
                      where e->>'kind' = 'ROUTE_LAP') <> 3 then
      raise exception '0092 self-assert FAIL: % ROUTE_LAP event(s), or world.ledger does not serve them', v_ev;
    end if;
    -- BOUNDED: laps 1 and 2's route orders are pruned; lap 3 (newest closed) and lap 4 (open) stay.
    if exists (select 1 from public.orders o join public.standing_route_laps x on x.id = o.route_lap_id
                where x.route_id = v_route and x.lap_no in (1, 2)) then
      raise exception '0092 self-assert FAIL: the route orders of laps 1-2 were not pruned';
    end if;
    select count(*) into r_orders from public.orders where fleet_id = v_fleet;

    -- RESUPPLY: the route placed the keep order itself — no standing top-up, no refusal.
    if exists (select 1 from public.events where player_id = v_player and kind = 'PROVISION_REFUSED')
       or exists (select 1 from public.events where player_id = v_player and kind = 'PROVISIONED'
                   and (payload->>'standing')::boolean)
       or not exists (select 1 from public.events where player_id = v_player and kind = 'PROVISIONED') then
      raise exception '0092 self-assert FAIL: a route fleet was resupplied by the arrival order, refused, or never resupplied';
    end if;

    -- ── PACING: one lap per game-day. The next arrival at Lisbon closes lap 4 and HOLDS ────────
    update public.world_config set value = to_jsonb(1) where key = 'standing_route_laps_per_game_day';
    for k in 1 .. 2 loop
      update public.voyages
         set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform public.tick_arrivals(now());
    end loop;
    select * into v_sr from public.standing_routes where id = v_route;
    v_hold := to_timestamp(((world.game_day(now()) + 1) * public.wc_num('game_day_seconds'))::double precision);
    select ducats into v_p1 from public.players where id = v_player;
    select sum(net) into v_net from public.standing_route_laps where route_id = v_route and closed_at is not null;
    if (select status from public.fleets where id = v_fleet) <> 'DOCKED'
       or (select port_id from public.fleets where id = v_fleet) <> v_lis
       or v_sr.hold_until is distinct from v_hold or v_sr.lap_id is not null
       or exists (select 1 from public.orders where fleet_id = v_fleet and status = 'pending') then
      raise exception '0092 self-assert FAIL: the paced route did not wait at Lisbon until % (route %)', v_hold, to_jsonb(v_sr);
    end if;
    -- THE BOOKS BALANCE: four closed laps' nets are, to the ducat, what the purse moved.
    if v_p1 - v_p0 <> v_net then
      raise exception '0092 self-assert FAIL: the purse moved % but the four laps say %', v_p1 - v_p0, v_net;
    end if;

    -- ── SKIP (D1): Lisbon has none of the good; the tick WAKES the route at the next game-day,
    --    the BUY is stepped over and noted, and the SAIL departs anyway ───────────────────────────
    update public.port_goods set stock = 0 where port_id = v_lis and good_id = v_good_id;
    perform public.tick_arrivals(v_hold + interval '1 second');
    select * into v_sr from public.standing_routes where id = v_route;
    select * into v_lap from public.standing_route_laps where id = v_sr.lap_id;
    select o.error_code into v_skip from public.orders o
     where o.route_lap_id = v_lap.id and o.verb = 'BUY' and o.status = 'skipped';
    if (select status from public.fleets where id = v_fleet) <> 'SAILING' or v_sr.hold_until is not null
       or v_lap.lap_no <> 5 or v_skip is null
       or jsonb_array_length(v_lap.skipped) <> 1 or v_lap.skipped->0->>'code' <> v_skip then
      raise exception '0092 self-assert FAIL: the woken lap did not step over the empty BUY and sail (lap %, code %)', to_jsonb(v_lap), v_skip;
    end if;

    -- ── PAUSED writes nothing; STOPPED is the halt law; CLEAR resumes ─────────────────────────
    perform cmd.standing_route_pause(v_route, true);
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform public.tick_arrivals(now());
    if (select status from public.fleets where id = v_fleet) <> 'DOCKED'
       or exists (select 1 from public.orders where fleet_id = v_fleet and status = 'pending') then
      raise exception '0092 self-assert FAIL: a paused route wrote orders at Funchal';
    end if;
    update public.ships set durability = 0 where fleet_id = v_fleet and is_flagship;
    perform cmd.standing_route_pause(v_route, false);
    select count(*) into v_orders0 from public.orders where fleet_id = v_fleet;
    select error_code into v_stop from public.orders
     where fleet_id = v_fleet and status = 'failed' and verb = 'SAIL' and route_lap_id is not null;
    v_read := world.standing_routes();
    if v_stop is null or (select status from public.fleets where id = v_fleet) <> 'DOCKED'
       or v_read->'routes'->0->>'state' <> 'stopped' or v_read->'routes'->0->'stopped'->>'code' <> v_stop then
      raise exception '0092 self-assert FAIL: an unfit flagship did not stop the route by the halt law (%, %)', v_stop, v_read->'routes'->0;
    end if;
    perform cmd.advance(v_fleet, now());
    if (select count(*) from public.orders where fleet_id = v_fleet) <> v_orders0 then
      raise exception '0092 self-assert FAIL: a stopped route wrote more orders';
    end if;
    update public.ships s set durability = c.durability from public.ship_classes c
     where c.id = s.class_id and s.fleet_id = v_fleet;
    perform cmd.clear(v_fleet, false);
    perform cmd.advance(v_fleet, now());
    if (select status from public.fleets where id = v_fleet) <> 'SAILING'
       or (select dest_port_id from public.voyages where fleet_id = v_fleet and status = 'SAILING') <> v_lis then
      raise exception '0092 self-assert FAIL: CLEAR did not release the stopped route onward to Lisbon';
    end if;

    -- ── GUARDS ────────────────────────────────────────────────────────────────────────────────
    update public.world_config set value = to_jsonb(0) where key = 'standing_route_laps_per_game_day';
    -- reserve: keep back more than the purse holds -> paused at the next stop.
    update public.standing_routes set reserve = (select ducats from public.players where id = v_player) + 1
     where id = v_route;
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform public.tick_arrivals(now());
    if (select paused_reason from public.standing_routes where id = v_route) is distinct from 'reserve'
       or not exists (select 1 from public.events where player_id = v_player and kind = 'ROUTE_PAUSED'
                       and payload->>'reason' = 'reserve') then
      raise exception '0092 self-assert FAIL: the reserve guard did not pause the route';
    end if;
    -- losing: N losing laps in a row -> paused at the lap boundary.
    update public.standing_routes set reserve = 0, stop_after_losing_laps = 3 where id = v_route;
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net)
    select v_route, 100 + g.n, now(), now(), -1 from generate_series(1, 3) as g(n);
    perform cmd.standing_route_pause(v_route, false);
    if (select paused_reason from public.standing_routes where id = v_route) is distinct from 'losing' then
      raise exception '0092 self-assert FAIL: three losing laps did not pause the route';
    end if;
    delete from public.standing_route_laps where route_id = v_route and lap_no > 100;
    -- off_route: the fleet was moved by hand to a port on no stop -> paused, never guessed.
    update public.fleets set port_id = v_cad where id = v_fleet;
    perform cmd.standing_route_pause(v_route, false);
    if (select paused_reason from public.standing_routes where id = v_route) is distinct from 'off_route' then
      raise exception '0092 self-assert FAIL: a fleet off its route was not paused';
    end if;
    update public.fleets set port_id = v_lis where id = v_fleet;
    -- cap: a fourth route is refused by the table's own trigger, through the verb.
    v_r2 := (cmd.standing_route_save(null, 'Second', jsonb_build_array(
               jsonb_build_object('port', 'LIS', 'course', v_out), jsonb_build_object('port', 'FNC', 'course', v_back_c)), 0, null)->>'id')::uuid;
    v_r3 := (cmd.standing_route_save(null, 'Third', jsonb_build_array(
               jsonb_build_object('port', 'LIS', 'course', v_out), jsonb_build_object('port', 'FNC', 'course', v_back_c)), 0, null)->>'id')::uuid;
    if v_r2 is null or v_r3 is null
       or cmd.standing_route_save(null, 'Fourth', jsonb_build_array(
            jsonb_build_object('port', 'LIS', 'course', v_out), jsonb_build_object('port', 'FNC', 'course', v_back_c)), 0, null)->>'error_code'
          <> 'E_ROUTE_CAP' then
      raise exception '0092 self-assert FAIL: the route cap did not bite at %', public.wc_int('standing_route_max') + 1;
    end if;

    -- ── GRAMMAR: every line kind renders and round-trips through cmd.parse ─────────────────────
    v_res := cmd.standing_route_save(v_r2, null, jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_out, 'repair', true, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL', 'good', v_good, 'qty', 5, 'price_limit', 12.5),
        jsonb_build_object('kind', 'SELL'),
        jsonb_build_object('kind', 'BUY', 'good', v_good, 'qty', 30, 'price_limit', 44),
        jsonb_build_object('kind', 'BUY', 'good', v_good))),
      jsonb_build_object('port', 'FNC', 'course', v_back_c, 'lines', jsonb_build_array(
        jsonb_build_object('kind', 'SELL', 'good', v_good, 'at_profit', true))),
      jsonb_build_object('port', 'CAD', 'course', v_out)), 0, null);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0092 self-assert FAIL: the grammar route was refused: %', v_res;
    end if;
    update public.ships set cargo = cargo || jsonb_build_object(v_good, 10, 'salt', 5),
                            cargo_basis = cargo_basis || jsonb_build_object(v_good, 50.123, 'salt', 7)
     where fleet_id = v_fleet and is_flagship;
    update public.provision_presets set days = 999 where player_id = v_player;
    v_lines := cmd.standing_route_lines(v_r2, 0, v_fleet)
            || cmd.standing_route_lines(v_r2, 1, v_fleet);
    if v_lines[1] <> format('SELL %s 5 AT >= 12.5', v_good) or v_lines[2] <> 'SELL salt ALL'
       or v_lines[3] <> 'PROVISION DAYS 999' or v_lines[4] <> 'REPAIR'
       or v_lines[5] <> format('BUY %s 30 AT 44', v_good) or v_lines[6] <> format('BUY %s ALL', v_good)
       or v_lines[7] <> 'SAIL TO FNC'
       or v_lines[8] <> format('SELL %s ALL AT >= 50.13', v_good) or v_lines[10] <> 'SAIL TO CAD' then
      raise exception '0092 self-assert FAIL: the renderer wrote %', v_lines;
    end if;
    foreach v_line in array v_lines loop
      v_parsed := cmd.parse(v_player, v_fleet, v_line);
      if v_parsed->>'verb' <> split_part(v_line, ' ', 1)
         or (v_line like '% ALL%' and v_parsed->'args'->>'qty_mode' <> 'ALL')
         or (v_line like '% 5 AT >= 12.5' and ((v_parsed->'args'->>'qty')::numeric <> 5 or (v_parsed->'args'->>'limit')::numeric <> 12.5))
         or (v_line like '% AT >= 50.13' and (v_parsed->'args'->>'limit')::numeric <> 50.13)
         or (v_line like 'BUY % 30 AT 44' and ((v_parsed->'args'->>'qty')::numeric <> 30 or (v_parsed->'args'->>'limit')::numeric <> 44))
         or (v_line like 'PROVISION%' and ((v_parsed->'args'->>'days')::numeric <> 999 or v_parsed->'args'->>'mode' <> 'DAYS'))
         or (v_line = 'REPAIR' and (v_parsed->'args'->>'to_pct')::numeric <> 100)
         or (v_line like 'SAIL%' and v_parsed->'args'->>'dest' is null)
         or (v_line like '% ' || v_good || ' %' and v_parsed->'args'->>'good' <> v_good_id::text) then
        raise exception '0092 self-assert FAIL: "%" does not round-trip through cmd.parse: %', v_line, v_parsed;
      end if;
    end loop;
    update public.provision_presets set days = 12 where player_id = v_player;

    -- ── CONTAINMENT: a broken route pauses ITSELF; the same tick still settles another fleet ───
    update public.standing_routes set paused_reason = null, stop_after_losing_laps = 20 where id = v_route;
    perform cmd.assume_identity(c_auth);
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    perform cmd.advance(v_fleet, now());   -- works Lisbon, sails for Funchal
    perform cmd.assume_identity(c_auth2);
    v_res := cmd.issue(v_fleet2, 'SAIL TO FNC', null, v_out);
    if (select status from public.fleets where id = v_fleet) <> 'SAILING'
       or (select status from public.fleets where id = v_fleet2) <> 'SAILING' then
      raise exception '0092 self-assert FAIL: the containment probe could not put both fleets to sea: %', v_res;
    end if;
    update public.ports set kind = 'SEA_PLACE', approach = '0092 probe' where id = v_fnc;
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id in (v_fleet, v_fleet2) and status = 'SAILING';
    v_res := public.tick_arrivals(now());
    if (v_res->>'fleets_touched')::int < 2
       or (select paused_reason from public.standing_routes where id = v_route) is distinct from 'error'
       or not exists (select 1 from public.events where player_id = v_player and kind = 'ROUTE_PAUSED'
                       and payload->>'code' = 'E_ROUTE_BROKEN')
       or exists (select 1 from public.voyages where fleet_id = v_fleet2 and status = 'SAILING') then
      raise exception '0092 self-assert FAIL: a broken route was not contained: tick %, route %', v_res,
        (select to_jsonb(sr) from public.standing_routes sr where id = v_route);
    end if;
    update public.ports set kind = 'HARBOUR', approach = null where id = v_fnc;

    -- ── DOORS ─────────────────────────────────────────────────────────────────────────────────
    foreach v_fn in array array['world.standing_routes()', 'cmd.standing_route_save(uuid, text, jsonb, bigint, integer)',
        'cmd.standing_route_delete(uuid)', 'cmd.standing_route_assign(uuid, uuid)', 'cmd.standing_route_pause(uuid, boolean)'] loop
      if not has_function_privilege('authenticated', v_fn, 'execute') or has_function_privilege('anon', v_fn, 'execute') then
        raise exception '0092 self-assert FAIL: % is not open to authenticated and closed to anon', v_fn;
      end if;
    end loop;
    foreach v_fn in array array['cmd.enqueue(uuid, jsonb, text, jsonb, uuid)', 'cmd.run_standing_route(uuid, timestamptz)',
        'cmd.standing_route_lines(uuid, integer, uuid)', 'cmd.standing_route_note_skip(uuid)',
        'cmd.standing_route_close_lap(uuid, timestamptz)', 'cmd.standing_route_set_paused(uuid, text, text, text)',
        'cmd.standing_route_refusal(text, text, text)', 'public.standing_routes_on()', 'public.keep_level_met(uuid, numeric)',
        'public.standing_routes_cap()', 'public.standing_route_stops_cap()', 'public.standing_route_lines_cap()'] loop
      if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
        raise exception '0092 self-assert FAIL: a client role may execute %', v_fn;
      end if;
    end loop;
    if (select count(*) from public.client_rpc_entry_points() e
         where e.fn is not null and e.function_name in ('standing_routes', 'standing_route_save', 'standing_route_delete',
                                                         'standing_route_assign', 'standing_route_pause')) <> 5
       or (select count(*) from public.client_rpc_entry_points() where fn is null) <> 0 then
      raise exception '0092 self-assert FAIL: client_rpc_entry_points does not resolve the five route doors';
    end if;
    if (select count(*) from public.client_write_grants()) <> 0 then
      raise exception '0092 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
    end if;
    if (select count(*) from public.client_executable_writers()) <> 0 then
      raise exception '0092 self-assert FAIL: client-executable writer(s): %',
        (select string_agg(schema_name || '.' || function_name || ' ' || grantee, ', ') from public.client_executable_writers());
    end if;
    if (select count(*) from public.caller_evaluated_functions()) <> 0 then
      raise exception '0092 self-assert FAIL: % read-wall gap(s)', (select count(*) from public.caller_evaluated_functions());
    end if;

    raise exception using errcode = 'P0920', message = '0092 probe rollback';
  exception when sqlstate 'P0920' then
    null;
  end;

  -- THE ROLLBACK REALLY ROLLED BACK, and the switch is still OFF.
  if (select count(*) from public.players) <> v_base
     or exists (select 1 from public.players where auth_uid in (c_auth, c_auth2))
     or exists (select 1 from public.standing_routes) then
    raise exception '0092 self-assert FAIL: the probe leaked a house or a route';
  end if;
  if public.standing_routes_on() then
    raise exception '0092 self-assert FAIL: the switch is on after the probe — this file ships DARK';
  end if;

  raise notice '0092 self-assert ok: A ROUTE IS A STANDING ORDER THAT SAILS. The re-cuts of cmd.advance (flag, refill, skip rule), cmd.run_standing_provision (route return, shared judge), tick_arrivals (wake loop) and the catalogue (five rows) are each their pre-image plus only those hunks, ACLs unmoved; cmd.issue answered 18 orders (incl. E_PARSE, E_STALE, E_QUEUE_FULL at 13) byte-identically to its pre-image after the enqueue moved into cmd.enqueue; a route-less [failed, pending] queue stayed halted. On a thrown-away house with the switch on: dark refused all four verbs; no keep level was E_NO_KEEP; assign at Lisbon bought % and sailed through the queue; SIX TICKS OF tick_arrivals ALONE ran % laps (sold % 🪙, wages %, net %), every BOUGHT/SOLD a done route order, % ROUTE_LAP rows served by world.ledger, laps 1-2''s orders pruned (% rows left on the fleet); the arrival order stood aside and the route resupplied itself; paced at 1/game-day the route waited at Lisbon until the next game-day and the purse had moved exactly the four laps'' net %; the tick woke it, an empty BUY was stepped over (%) and it sailed; paused wrote nothing; an unfit flagship stopped it (%) and CLEAR sent it on; reserve, losing and off-route guards paused it; the fourth route was E_ROUTE_CAP; every line kind round-tripped cmd.parse; a broken stop paused its route as error while the same tick settled another fleet; doors: five open to authenticated only, the rest closed, 0 client write grants, 0 client-executable writers, 0 read-wall gaps. Rolled back; the switch ships OFF.',
    v_good, r_laps, r_sold, r_wages, r_net, r_laps, r_orders, v_net, v_skip, v_stop;
end $$;
