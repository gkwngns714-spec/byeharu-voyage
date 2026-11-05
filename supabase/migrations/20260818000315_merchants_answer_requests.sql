-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0315 — MERCHANTS ANSWER REQUESTS: a merchant docking with what a harbour asks for delivers it through the players' door, the plan counts the bonus, and a small job keeps every board wound
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: "merchants should also look for request to be fulfilled - more profit."
--
-- WHAT WAS MEASURED ON PROD (docs/dev-log/2026-11-05-merchants-requests.md): requests post only when a harbour is read, and 2 harbours were read in 24 h; 270 of 274 open rows were past their deadline, holding
--   6.56 M d. until read. A draw costs about 1 s. 2,493 merchant laps an hour, 1,700 sold lines, 1,004 of them of a good the harbour does not offer (the only goods a request can name).
--
-- THE RULES (decided by default and told to the owner; knobs below):
--   PLAYERS FIRST: a request is open to merchants once it has stood contract_npc_after_hours (6). 0 = merchants compete from the start; a high value = off. public.contract_asks is the ONE reading of what merchants may answer.
--   ONE DOOR: a merchant's route SELL (no quantity: every one she writes) goes through cmd.do_sell_answering, which delivers through cmd.run_fulfil: partial delivery, the budget, the flows, the FULFILLED event and the PREMIUM ledger row are
--     the players'. What the budget does not pay for goes through the normal cmd.do_sell, at the line's own floor. A player's order, an ordered SELL and a quantity SELL are cmd.do_sell, untouched.
--   ONLY REAL EXTRA PROFIT: she delivers when the sale price plus the bonus meets her line's floor (what she paid plus npc_sell_margin), so she never sells below it for a bonus, and a sale the floor would have refused can land when the bonus lifts it.
--     A refused delivery (a broke purse, the allowance) is not an order failed: she goes on to the normal sale, which refuses in its own words.
--   THE LAP'S BOOKS: the SELL order's `total` carries the bonus, `tax` and `wages` both parts, so standing_route_close_lap, lap_trades, the month book and Stats need no change. cmd.run_manifest's lines now carry tax and wages (they were dropped).
--   THE PLAN (bounded): public.npc_leg_lines reads the asks at the leg's far end once a leg, one indexed read, always outside the quay (0266/0270: a plan never runs under it). A good asked for there passes her house's wares filter, and its bonus joins
--     the leg's profit. A parcel must still pay ON ITS OWN to be kept, because another merchant may spend the budget first: a good that pays only by the bonus is never bought. Her loop changes only by npc_route_switch_pct or a tier, so she never leaves a route for a small bonus.
--   NO WIND UNDER THE QUAY: cmd.run_fulfil wound the board first, a draw of about 1 s, and a merchant's delivery runs under the quay. It no longer winds: it judges the row's own deadline. The read still winds. A player's delivery loses the same second.
--   A BONUS IS PAID ON WHAT LANDED: a short purse shrinks a sale (0122), and 0311 paid the bonus on what she offered, not what sold. Merchants sell into poor cities all day, so this is fixed here.
--   THE BOOK OF DELIVERIES: public.contract_deliveries, one row a delivery, kept 2 days. A merchant's ledger is compacted after npc_retention_hours (6), so `paid` read from the ledger would lose her bonuses inside the 24 h it reports; public.bonus_figures reads this book.
--     ledger_premium_at served only that read and goes. The one report that still reads PREMIUM from the ledger is a player's own.
--   THE WIND JOB, A NEW CRON JOB THE OWNER'S ORDER REQUIRES: byeharu-voyage:contract-wind, every minute, its own job, not in the beat. contract_wind_ms of work a minute (0 = off): overdue requests expire and go home first, then the harbours with the fewest open
--     requests are topped up, one post at a time, up to contract_open_max. Each step is its own transaction, and expiry is split from the draw (public.contracts_expire), so the draw of about 1 s holds no lock a sale needs. A harbour that could not post is not asked again for contract_wind_retry_minutes.
--     A city under treasury_reserve_floor is left alone (decided by default): one route sale in six is already refused E_CITY_BROKE, and escrow is money its purse cannot spend. One receipt a minute: public.contract_wind_runs. NOT in the quay: the read door already posts without it.
--   WHAT THE JOB COSTS THE CITIES: boards fill, so escrow rises well above today's. The dev-log has the figure and what to watch. contract_wind_ms 0 stops it at once.
--
-- SELF-ASSERT: hunks, reversal, grants, nothing else moved, the job; then on one merchant and one player at a real harbour, every row rolled back: too young, answered, spent, the rest sold, the floor kept, the floor lifted, not a player, not an ordered sale,
--   the knob both ways, a short purse, the allowance, the lap's books, the wind (overdue, top-up, cap, no surplus, retry, off, budget), the plan. It steps nothing real: the job runs on the probe harbour alone. Mutation controls: scripts/ops/harness/city-requests/proof-0315.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 60 s, lock_timeout 5 s first. Work: six bodies, three tables, one job, about 8 draws at about 1 s. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): docs/dev-log/2026-11-05-merchants-requests.md. To stop it at once: contract_wind_ms 0 and contract_npc_after_hours 1000000.
-- VERSION: 0315 - follows 0311 (#494), and 0312, 0313 and 0314, which are other slices' numbers. It does not read them.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_p1    constant uuid := '00000000-0315-4000-8000-000000000315';
  c_p2    constant uuid := '00000000-0315-4000-8000-000000000316';
  v_fn    text[];
  v_old   text[];
  v_new   text[];
  v_oids  oid[];
  v_def0  jsonb := '{}'::jsonb;
  v_acl0  jsonb := '{}'::jsonb;
  v_cur   jsonb := '{}'::jsonb;
  v_def   text;
  v_i     int;
  v_n     int;
  v_fn_before   text;
  v_cfg_after   text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_t0    timestamptz := clock_timestamp();
  v_day   int := world.game_day();
  v_p1    uuid;
  v_p2    uuid;
  v_f1    uuid;
  v_f2    uuid;
  v_r1    uuid;
  v_r2    uuid;
  v_l1    uuid;
  v_l2    uuid;
  v_port  uuid;
  v_to    uuid;
  v_draw  record;
  v_good  uuid;
  v_code  text;
  v_bid   numeric;
  v_pu    bigint;
  v_id    uuid;
  v_a     jsonb;
  v_b     jsonb;
  v_was   bigint;
  v_sold  numeric;
  v_mark  timestamptz;
  v_lap   public.standing_route_laps%rowtype;
  v_rows  jsonb;
  v_since timestamptz := now() - interval '1 second';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.bonus_figures(uuid, timestamptz)') is null or not exists (select 1 from public.world_config where key = 'contract_open_max') then
    raise exception '0315 refuses: 0311 is not in this world';
  end if;
  if to_regclass('public.contract_deliveries') is not null or to_regprocedure('public.contract_asks(uuid)') is not null then
    raise exception '0315 refuses: it has been applied once';
  end if;

  v_fn := array[
    'cmd.execute_order(uuid)',
    'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)',
    'cmd.run_manifest(uuid,jsonb)',
    'public.tick_contracts(uuid,timestamp with time zone)', 'public.tick_contracts(uuid,timestamp with time zone)',
    'public.bonus_figures(uuid,timestamp with time zone)',
    'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
    'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'];

  select array_agg(p.oid) into v_oids
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in (select f::regprocedure::oid from unnest(v_fn) f);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before from pg_proc p where p.oid = any (v_oids);
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def0 := v_def0 || jsonb_build_object(v_fn[v_i], replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', ''));
    v_acl0 := v_acl0 || jsonb_build_object(v_fn[v_i], (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
                                                         from pg_proc p where p.oid = v_fn[v_i]::regprocedure));
  end loop;
  v_cur := v_def0;

  -- ── 1. THE KNOBS AND THE TABLES ──
  insert into public.world_config (key, value, description) values
    ('contract_npc_after_hours', to_jsonb(6), '0315: how many real hours a request stands before merchants may answer it, so players get the first go. 0 = merchants compete from the start; a high value = off.'),
    ('contract_wind_ms', to_jsonb(4000), '0315: how many milliseconds of work a minute the byeharu-voyage:contract-wind job may spend expiring overdue requests and topping harbours up. A draw costs about 1,000. 0 = off.'),
    ('contract_wind_retry_minutes', to_jsonb(60), '0315: how long the wind job leaves a harbour that could not post before asking it again.');

  create table public.contract_deliveries (
    id          bigint generated always as identity primary key,
    at          timestamptz not null default now(),
    port_id     uuid not null references public.ports (id),
    player_id   uuid not null,
    contract_id uuid,
    bonus       bigint not null check (bonus > 0)
  );
  comment on table public.contract_deliveries is '0315: one row a delivery to a request, written by cmd.run_fulfil, kept 2 days (the wind job prunes it). `paid` in Stats reads this: a merchant''s ledger is compacted after npc_retention_hours. contract_id is null only on rows carried over from the ledger.';
  create index contract_deliveries_at on public.contract_deliveries (at);
  create index contract_deliveries_port_at on public.contract_deliveries (port_id, at);
  alter table public.contract_deliveries enable row level security;
  revoke all on table public.contract_deliveries from public, anon, authenticated;
  insert into public.contract_deliveries (at, port_id, player_id, bonus)
  select l.created_at, l.port_id, l.player_id, l.ducats_delta from public.ledger l where l.kind = 'PREMIUM' and l.port_id is not null and l.ducats_delta > 0;
  drop index public.ledger_premium_at;

  create table public.contract_wind (
    port_id  uuid primary key references public.ports (id),
    next_try timestamptz not null
  );
  comment on table public.contract_wind is '0315: a harbour that could not post is not asked again before next_try (contract_wind_retry_minutes). A harbour with no row is asked.';
  alter table public.contract_wind enable row level security;
  revoke all on table public.contract_wind from public, anon, authenticated;

  create table public.contract_wind_runs (
    slot    integer primary key,
    at      timestamptz not null,
    ms      numeric not null,
    receipt jsonb not null
  );
  comment on table public.contract_wind_runs is '0315: the wind job''s receipt, one a minute of the day (as public.lap_start_runs): how many expired, how much went home, how many tried and posted.';
  alter table public.contract_wind_runs enable row level security;
  revoke all on table public.contract_wind_runs from public, anon, authenticated;

  select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) into v_cfg_after from public.world_config x;

  -- ── 2. THE NEW FUNCTIONS ──
  execute $f$
create function public.contract_asks(p_port uuid)
returns table (id uuid, good_id uuid, per_unit numeric, units numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0315: THE ONE READING of what a merchant may answer at one harbour: open, inside its deadline, standing contract_npc_after_hours, and able to pay one more unit. trade_contracts_port_open answers it from at most contract_open_max rows.
  select c.id, c.good_id, c.premium_per_unit, floor(c.premium_ducats / c.premium_per_unit)
    from public.trade_contracts c
   where c.port_id = p_port and c.status = 'open' and c.expires_day > world.game_day()
     and c.created_at <= now() - make_interval(secs => (public.wc_num('contract_npc_after_hours') * 3600)::double precision)
     and c.premium_per_unit > 0 and c.premium_ducats >= c.premium_per_unit
$body$
  $f$;
  revoke all on function public.contract_asks(uuid) from public, anon, authenticated;

  execute $f$
create function public.contracts_expire(p_port uuid, p_now timestamptz)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0315: EXPIRE what has passed, then PRUNE what is a whole window past its expiry, fulfilled or expired; the ledger's FULFILLED events keep the deliveries. Moved whole out of public.tick_contracts, so the wind job can do it
-- in its own transaction: the treasury row this takes must not stay locked through a draw of about 1 s. Answers what went home.
declare
  v_day      int := world.game_day(p_now);
  v_deadline int := public.wc_int('contract_deadline_days');
  v_lapsed   bigint;
begin
  with x as (
    update public.trade_contracts
       set status = 'expired'
     where port_id = p_port and status = 'open' and expires_day <= v_day
    returning escrow)
  select coalesce(sum(x.escrow), 0) into v_lapsed from x;
  -- 0122: what the city set aside for a request nobody delivered comes back to it.
  if v_lapsed > 0 then
    -- (whether or not the purses are still lit: an escrow is the city's money either way)
    perform public.treasury_post(p_port, 'BOUNTY_LAPSED', v_lapsed, null, null, true);
  end if;
  delete from public.trade_contracts
   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;
  return v_lapsed;
end
$body$
  $f$;
  revoke all on function public.contracts_expire(uuid, timestamptz) from public, anon, authenticated;

  execute $f$
create function cmd.do_sell_answering(p_fleet uuid, p_args jsonb, p_lap uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0315: A QUEUED SELL. A merchant's route SELL with no quantity answers what this harbour asks for that good through THE delivery door, cmd.run_fulfil, and what the budget does not pay for goes through
-- cmd.do_sell at the line's own floor. Everything else is cmd.do_sell. She delivers only where the sale price plus the bonus meets her floor. The answer is the shape standing_route_close_lap and lap_trades read:
-- `total` holds the bonus, `tax` and `wages` both parts, `bonus` the bonus alone. A refusal of the delivery is not the order's: the normal sale runs and refuses in its own words. Only an E_ refusal is caught here.
declare
  f        public.fleets%rowtype;
  v_good   uuid := (p_args->>'good')::uuid;
  v_code   text;
  v_limit  numeric := nullif(p_args->>'limit', '')::numeric;
  a        record;
  q        record;
  v_n      numeric;
  v_r      jsonb;
  v_rest   jsonb;
  v_qty    numeric := 0;
  v_total  numeric := 0;
  v_tax    numeric := 0;
  v_wages  numeric := 0;
  v_bonus  bigint := 0;
  v_ids    jsonb := '[]'::jsonb;
begin
  if p_lap is null or p_args->>'qty' is not null then
    return cmd.do_sell(p_fleet, p_args);
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' or not exists (select 1 from public.players p where p.id = f.player_id and p.is_npc) then
    return cmd.do_sell(p_fleet, p_args);
  end if;
  select g.code into v_code from public.goods g where g.id = v_good;
  for a in select x.* from public.contract_asks(f.port_id) x where x.good_id = v_good order by x.per_unit desc, x.id loop
    v_n := least(floor(public.fleet_cargo_qty(p_fleet, v_code)), a.units);
    exit when v_n < 1;
    select * into q from world.quote(f.port_id, v_good, v_n, 'sell', null, p_fleet);
    continue when v_limit is not null and coalesce(q.avg_price, 0) + a.per_unit < v_limit;
    begin
      v_r := cmd.run_fulfil(p_fleet, a.id);
    exception when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      exit;
    end;
    v_qty   := v_qty + (v_r->'lines'->0->>'qty')::numeric;
    v_total := v_total + (v_r->'lines'->0->>'total')::numeric;
    v_tax   := v_tax + coalesce((v_r->'lines'->0->>'tax')::numeric, 0);
    v_wages := v_wages + coalesce((v_r->'lines'->0->>'wages')::numeric, 0);
    v_bonus := v_bonus + (v_r->'contract'->>'premium')::bigint;
    v_ids   := v_ids || to_jsonb(a.id);
  end loop;
  if v_bonus = 0 then
    return cmd.do_sell(p_fleet, p_args);
  end if;
  -- THE REST. Delivered is already done, so a refusal of the rest leaves it aboard and the order stands.
  if public.fleet_cargo_qty(p_fleet, v_code) > 0 then
    begin
      v_rest := cmd.do_sell(p_fleet, p_args);
    exception when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    end;
  end if;
  return jsonb_build_object('good', v_code,
    'qty', v_qty + coalesce((v_rest->>'qty')::numeric, 0),
    'total', v_total + v_bonus + coalesce((v_rest->>'total')::numeric, 0),
    'tax', v_tax + coalesce((v_rest->>'tax')::numeric, 0),
    'wages', v_wages + coalesce((v_rest->>'wages')::numeric, 0),
    'bonus', v_bonus, 'requests', v_ids);
end
$body$
  $f$;
  revoke all on function cmd.do_sell_answering(uuid, jsonb, uuid) from public, anon, authenticated;

  execute $f$
create procedure public.tick_contract_wind(p_commit boolean default true, p_only uuid default null)
language plpgsql
as $body$
-- 0315: THE WIND JOB (pg_cron byeharu-voyage:contract-wind, every minute, CALL). contract_wind_ms of work: first the overdue requests, each harbour's expiry its own short transaction; then the harbours under contract_open_max, the
-- fewest open first, one post at a time, each its own expiry and its own post, so a draw of about 1 s runs with no lock a sale needs. What was not reached stays for the next minute. A harbour that posted nothing rests contract_wind_retry_minutes.
-- A city under treasury_reserve_floor is left alone: it is already short (0306), and its purse is what pays for cargo. Its own read may still post.
-- p_commit = false: one pass in the caller's transaction; p_only: that harbour alone (the self-assert). No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  v_ms     int := public.wc_int('contract_wind_ms');
  v_t0     timestamptz := clock_timestamp();
  v_now0   timestamptz := now();
  v_by     timestamptz := clock_timestamp() + make_interval(secs => public.wc_int('contract_wind_ms') / 1000.0);
  v_max    int := public.wc_int('contract_open_max');
  v_floor  bigint := public.wc_int('treasury_reserve_floor');
  v_retry  interval := make_interval(mins => public.wc_int('contract_wind_retry_minutes'));
  v_ports  uuid[];
  v_p      uuid;
  v_n      int;
  v_due    int := 0;
  v_back   bigint := 0;
  v_tried  int := 0;
  v_posted int := 0;
  v_failed int := 0;
  v_note   text;
begin
  if v_ms <= 0 then return; end if;
  -- (A) WHAT IS OVERDUE GOES HOME
  v_ports := array(select distinct c.port_id from public.trade_contracts c
                    where c.status = 'open' and c.expires_day <= world.game_day() and (p_only is null or c.port_id = p_only));
  foreach v_p in array v_ports loop
    exit when clock_timestamp() >= v_by;
    begin
      v_back := v_back + public.contracts_expire(v_p, now());
      v_due := v_due + 1;
    exception when others then
      v_failed := v_failed + 1;
      v_note := coalesce(v_note, 'expire ' || v_p || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
  end loop;
  -- (B) THE HARBOURS ARE TOPPED UP
  loop
    exit when clock_timestamp() >= v_by;
    v_p := null;
    select p.id into v_p
      from public.ports p
      left join public.contract_wind w on w.port_id = p.id
     cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open') o
     where p.kind = 'HARBOUR' and o.n < v_max and (w.next_try is null or w.next_try <= now())
       and public.treasury_balance(p.id) >= v_floor
       and (p_only is null or p.id = p_only)
     order by o.n, w.next_try nulls first, p.id
     limit 1;
    exit when v_p is null;
    begin
      perform public.contracts_expire(v_p, now());
    exception when others then
      v_note := coalesce(v_note, 'expire ' || v_p || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
    v_tried := v_tried + 1;
    begin
      v_n := public.tick_contracts(v_p, now());
    exception when others then
      v_n := 0;
      v_failed := v_failed + 1;
      v_note := coalesce(v_note, 'post ' || v_p || ': ' || sqlerrm);
    end;
    v_posted := v_posted + v_n;
    if v_n = 0 then
      insert into public.contract_wind (port_id, next_try) values (v_p, now() + v_retry)
      on conflict (port_id) do update set next_try = excluded.next_try;
    end if;
    if p_commit then commit; end if;
  end loop;
  delete from public.contract_deliveries d where d.at < now() - interval '2 days';
  insert into public.contract_wind_runs (slot, at, ms, receipt)
  values ((floor(extract(epoch from v_now0) / 60)::bigint % 1440)::int, v_now0,
          round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
          jsonb_build_object('expired_ports', v_due, 'home', v_back, 'tried', v_tried, 'posted', v_posted, 'failed', v_failed, 'note', v_note))
  on conflict (slot) do update set at = excluded.at, ms = excluded.ms, receipt = excluded.receipt;
  if p_commit then commit; end if;
end
$body$
  $f$;
  revoke all on procedure public.tick_contract_wind(boolean, uuid) from public, anon, authenticated;

  -- ── 3. THE HUNKS: each occurs once ──
  v_old := array[
$h$               when 'SELL'      then cmd.do_sell(o.fleet_id, o.args)
$h$,
$h$  -- The board is current before it is judged (the same wind the read makes).
  perform public.tick_contracts(f.port_id, now());
$h$,
$h$  if c.status = 'expired' then
$h$,
$h$  v_pay  := ceil(c.premium_per_unit * v_qty)::bigint;
$h$,
$h$  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);
$h$,
$h$        'basis', v_r->'basis', 'cost', v_r->'cost', 'profit', v_r->'profit');
$h$,
$h$  v_posted   int := 0;
  v_lapsed   bigint;                                           -- 0122
$h$,
$h$  -- EXPIRE what has passed, then PRUNE what is a whole window past its expiry — fulfilled or
  -- expired; the ledger's FULFILLED events keep the deliveries.
  with x as (
    update public.trade_contracts
       set status = 'expired'
     where port_id = p_port and status = 'open' and expires_day <= v_day
    returning escrow)
  select coalesce(sum(x.escrow), 0) into v_lapsed from x;
  -- 0122: what the city set aside for a request nobody delivered comes back to it.
  if v_lapsed > 0 then
    -- (whether or not the purses are still lit: an escrow is the city's money either way)
    perform public.treasury_post(p_port, 'BOUNTY_LAPSED', v_lapsed, null, null, true);
  end if;
  delete from public.trade_contracts
   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;
$h$,
$h$  -- 0311: what the flow lines cannot say: `held`, the money open requests hold now, and `paid`, the bonus paid to houses since p_since (ledger PREMIUM), for one city or, with no port, the world.
$h$ || $h$  select jsonb_build_object(
           'held', (select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open' and (p_port is null or c.port_id = p_port)),
           'paid', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.kind = 'PREMIUM' and l.created_at > p_since and (p_port is null or l.port_id = p_port)))
$h$,
$h$  v_bid     numeric;  -- 0272: one good's whole stack at this quay's bid
$h$,
$h$  -- RANK, FILTER, SIZE, KEEP.
$h$,
$h$      continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
$h$,
$h$      v_profit := v_profit + v_net;   -- 0122: after tax
$h$];
  v_new := array[
$h$               when 'SELL'      then cmd.do_sell_answering(o.fleet_id, o.args, o.route_lap_id)   -- 0315: a merchant's route SELL answers requests first
$h$,
$h$  -- 0315: NO WIND HERE. A wind may draw, about 1 s, and a merchant's delivery runs under the quay. The read and the wind job keep the board; the row's own deadline is judged below.
$h$,
$h$  if c.status = 'expired' or (c.status = 'open' and c.expires_day <= world.game_day()) then   -- 0315
$h$,
$h$  v_qty := (v_rcpt->'lines'->0->>'qty')::numeric;   -- 0315: what landed: a short purse shrinks a sale (0122)
  v_pay  := ceil(c.premium_per_unit * v_qty)::bigint;
$h$,
$h$  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);
  insert into public.contract_deliveries (port_id, player_id, contract_id, bonus) values (c.port_id, f.player_id, c.id, v_pay);   -- 0315
$h$,
$h$        'basis', v_r->'basis', 'cost', v_r->'cost', 'profit', v_r->'profit',
        'tax', v_r->'tax', 'wages', v_r->'wages');   -- 0315: a merchant's lap books them
$h$,
$h$  v_posted   int := 0;
$h$,
$h$  -- 0315: expiry and pruning are public.contracts_expire, so the wind job can run them apart from the draw.
  perform public.contracts_expire(p_port, p_now);
$h$,
$h$  -- 0315: what the flow lines cannot say: `held`, the money open requests hold now, and `paid`, the bonus paid to houses since p_since (public.contract_deliveries: a merchant's ledger is compacted), for one city or, with no port, the world.
$h$ || $h$  select jsonb_build_object(
           'held', (select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open' and (p_port is null or c.port_id = p_port)),
           'paid', (select coalesce(sum(d.bonus), 0) from public.contract_deliveries d where d.at > p_since and (p_port is null or d.port_id = p_port)))
$h$,
$h$  v_bid     numeric;  -- 0272: one good's whole stack at this quay's bid
  v_asks    jsonb;    -- 0315: what p_to asks of merchants, good -> {u: units, p: bonus each} (public.contract_asks)
$h$,
$h$  -- 0315: WHAT THE FAR END ASKS, once a leg. A parcel must still pay on its own below; the bonus only joins the profit of one that does.
  select coalesce(jsonb_object_agg(z.good_id::text, jsonb_build_object('u', z.units, 'p', z.per_unit)), '{}'::jsonb) into v_asks
    from (select distinct on (a.good_id) a.good_id, a.units, a.per_unit from public.contract_asks(p_to) a order by a.good_id, a.per_unit desc) z;

  -- RANK, FILTER, SIZE, KEEP.
$h$,
$h$      continue when v_pass = 1 and not ((e->>'code') = any(h.wares)) and not v_asks ? (e->>'good_id');   -- 0315: a good asked for is looked at too
$h$,
$h$      v_profit := v_profit + v_net;   -- 0122: after tax
      if v_asks ? v_good::text then   -- 0315: the bonus on what the budget pays for
        v_profit := v_profit + least(v_q, (v_asks->v_good::text->>'u')::numeric) * (v_asks->v_good::text->>'p')::numeric;
      end if;
$h$];
  for v_i in 1 .. array_length(v_old, 1) loop
    v_def := v_cur ->> v_fn[v_i];
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0315 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fn[v_i], v_n;
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_old[v_i], v_new[v_i]));
  end loop;
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i > 1 and v_fn[v_i] = v_fn[v_i - 1];   -- several hunks to a body: one write of each
    execute v_cur ->> v_fn[v_i];
  end loop;

  -- ── 4. THE JOB: its own, not in the beat ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:contract-wind', '* * * * *', 'call public.tick_contract_wind()')$q$;
  end if;

  -- ── 5. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def := replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', '');
    if v_def <> v_cur ->> v_fn[v_i] then
      raise exception '0315 self-assert FAIL: % is not the body this file wrote', v_fn[v_i];
    end if;
  end loop;
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    v_def := v_cur ->> v_fn[v_i];
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0315 self-assert FAIL: hunk % is not in the new body of % exactly once', v_i, v_fn[v_i];
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_new[v_i], v_old[v_i]));
  end loop;
  if v_cur <> v_def0 then
    raise exception '0315 self-assert FAIL: a body does not reverse to its pre-image';
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fn[v_i]::regprocedure) <> v_acl0 ->> v_fn[v_i] then
      raise exception '0315 self-assert FAIL: the grants or settings of % moved', v_fn[v_i];
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (v_oids)) <> v_fn_before then
    raise exception '0315 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0315 self-assert FAIL: a trigger moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:contract-wind'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0315 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:contract-wind' and j.schedule = '* * * * *' and j.command = 'call public.tick_contract_wind()'$q$ into v_n;
    if v_n <> 1 then
      raise exception '0315 self-assert FAIL: the job is not scheduled';
    end if;
  end if;
  if has_function_privilege('anon', 'public.contract_asks(uuid)', 'execute') or has_function_privilege('authenticated', 'public.contract_asks(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.contracts_expire(uuid, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'cmd.do_sell_answering(uuid, jsonb, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.tick_contract_wind(boolean, uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.contract_deliveries', 'select')
     or has_table_privilege('authenticated', 'public.contract_wind', 'select')
     or has_table_privilege('authenticated', 'public.contract_wind_runs', 'select') then
    raise exception '0315 self-assert FAIL: a client can reach a helper or a book';
  end if;
  if public.wc_int('contract_npc_after_hours') <> 6 or public.wc_int('contract_wind_ms') <> 4000 or public.wc_int('contract_wind_retry_minutes') <> 60 then
    raise exception '0315 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 6. THE WORKED EXAMPLE, ON ONE MERCHANT AND ONE PLAYER AT ONE REAL HARBOUR, EVERY ROW ROLLED BACK ──
  execute $f$
create function pg_temp.purse_0315(p_port uuid, p_surplus bigint) returns void language plpgsql as $b$
begin
  perform public.treasury_post(p_port, 'CROWN_CALL', p_surplus - public.city_surplus(p_port), null, null, true);
end $b$
  $f$;
  -- an open request of a set bonus and budget, standing p_hours, its money out of the purse as a posting takes it
  execute $f$
create function pg_temp.ask_0315(p_port uuid, p_good uuid, p_per numeric, p_budget bigint, p_hours numeric, p_days int default 1440) returns uuid language plpgsql as $b$
declare
  v_id uuid;
begin
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, created_at)
  values (p_port, p_good, world.game_day() + p_days - 1440, 100 + (select count(*) from public.trade_contracts c where c.port_id = p_port), floor(p_budget / p_per), 0.1, p_per * 10, p_per, p_budget,
          world.game_day() + p_days, 'open', p_budget, now() - make_interval(secs => (p_hours * 3600)::double precision))
  returning id into v_id;
  perform public.treasury_post(p_port, 'BOUNTY', -p_budget, null, null);
  return v_id;
end $b$
  $f$;
  -- a SELL as her queue runs it: the one grammar, the one queue, the one executor
  execute $f$
create function pg_temp.sell_0315(p_player uuid, p_fleet uuid, p_code text, p_limit numeric, p_lap uuid, p_qty text default 'ALL') returns jsonb language plpgsql as $b$
declare
  v_line text := format('SELL %s %s', p_code, p_qty) || case when p_limit is null then '' else ' AT >= ' || trim_scale(round(p_limit, 2))::text end;
  v_res  jsonb;
begin
  v_res := cmd.enqueue(p_player, jsonb_set(cmd.parse(p_player, p_fleet, v_line), '{fleet_id}', to_jsonb(p_fleet::text)), v_line, null, p_lap);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception '0315 self-assert FAIL: the queue refused the probe: %', v_res;
  end if;
  return cmd.execute_order((v_res->>'order_id')::uuid);
end $b$
  $f$;
  execute $f$
create function pg_temp.worth_0315(p_port uuid, p_house uuid) returns bigint language sql as $b$
  select (select p.ducats from public.players p where p.id = p_house) + public.treasury_balance(p_port)
         + (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = p_port and t.status = 'open')
$b$
  $f$;
  begin
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';   -- a founding is refused on a closed economy; the two probe houses are rolled back with the rest
    v_p1 := public.new_house(c_p1, 'Casa do Mercador Um', 'PRT');
    v_p2 := public.new_house(c_p2, 'Casa do Mercador Dois', 'PRT');
    v_f1 := (select f.id from public.fleets f where f.player_id = v_p1);
    v_f2 := (select f.id from public.fleets f where f.player_id = v_p2);
    v_port := (select f.port_id from public.fleets f where f.id = v_f1);
    update public.fleets set port_id = v_port where id = v_f2;
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) values (v_port, 0, 0, v_day) on conflict (port_id) do update set reserve = 0;
    delete from public.trade_contracts where port_id = v_port;
    perform pg_temp.purse_0315(v_port, 1000000000);

    -- THE MERCHANT: a house of her own with a route and an open lap; the player keeps one too
    update public.players set is_npc = true, auth_uid = null, ducats = 100000000 where id = v_p1;
    insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
    values (v_p1, 1000315, 'prt', 'A probe company that exists for one transaction.', 'Capitão Probo', v_port, 1, 0.3, '{}');
    v_rows := world.trade_routes(v_port, null, null, 12, null) -> 'routes';
    if jsonb_array_length(v_rows) < 1 then
      raise exception '0315 self-assert FAIL: the probe harbour has no trade to plan';
    end if;
    v_to := (v_rows -> 0 -> 'to' ->> 'id')::uuid;
    insert into public.standing_routes (player_id, name, fleet_id) values (v_p1, 'probe 0315', v_f1) returning id into v_r1;
    insert into public.standing_routes (player_id, name, fleet_id) values (v_p2, 'probe 0315', v_f2) returning id into v_r2;
    insert into public.standing_route_stops (route_id, ord, port_id, course) values (v_r1, 0, v_port, '[[0,0],[1,1]]'), (v_r1, 1, v_to, '[[1,1],[0,0]]'), (v_r2, 0, v_port, '[[0,0],[1,1]]'), (v_r2, 1, v_to, '[[1,1],[0,0]]');
    insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_r1, 1, now()) returning id into v_l1;
    insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_r2, 1, now()) returning id into v_l2;
    update public.standing_routes set lap_id = v_l1, lap_no = 1 where id = v_r1;
    update public.standing_routes set lap_id = v_l2, lap_no = 1 where id = v_r2;

    select * into v_draw from public.contract_draw(v_port, v_day, 1);
    if v_draw.good_id is null then
      raise exception '0315 self-assert FAIL: the probe harbour draws nothing';
    end if;
    v_good := v_draw.good_id;
    update public.goods set bulk = 0.01 where id = v_good;   -- any lot fits the probe's hold
    v_code := (select g.code from public.goods g where g.id = v_good);
    v_bid := (select q.bid from world.price(v_port, v_good) q);
    v_pu := ceil(v_bid * 0.2)::bigint + 10;

    -- (a) TOO YOUNG: she sells at the quay and the request stands
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 5);
    perform public.fleet_load(v_f1, v_code, 3);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    if not coalesce((v_a ->> 'ok')::boolean, false) or v_a #> '{result,bonus}' is not null or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: a request younger than the knob was answered: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;

    -- (b) ANSWERED, THE BUDGET SPENT, THE REST SOLD AT THE QUAY, NOTHING MADE, THE BOOKS TOGETHER
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    perform public.fleet_load(v_f1, v_code, 5);
    v_was := pg_temp.worth_0315(v_port, v_p1);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    v_b := v_a -> 'result';
    if not coalesce((v_a ->> 'ok')::boolean, false) or (v_b ->> 'bonus')::bigint is distinct from v_pu * 3 or (v_b ->> 'qty')::numeric <> 5 or public.fleet_cargo_qty(v_f1, v_code) <> 0
       or v_b -> 'requests' <> jsonb_build_array(v_id) then
      raise exception '0315 self-assert FAIL: she did not deliver what the budget pays for and sell the rest: %', v_a;
    end if;
    if (select t.status from public.trade_contracts t where t.id = v_id) <> 'spent' or (select t.escrow from public.trade_contracts t where t.id = v_id) <> 0 then
      raise exception '0315 self-assert FAIL: the budget did not run down the players'' way';
    end if;
    if pg_temp.worth_0315(v_port, v_p1) <> v_was then
      raise exception '0315 self-assert FAIL: a merchant''s delivery made or lost money: %', pg_temp.worth_0315(v_port, v_p1) - v_was;
    end if;
    if (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_p1 and l.kind = 'PREMIUM') <> v_pu * 3
       or (select sum(d.bonus) from public.contract_deliveries d where d.player_id = v_p1 and d.contract_id = v_id and d.port_id = v_port) <> v_pu * 3
       or not exists (select 1 from public.events e where e.player_id = v_p1 and e.kind = 'FULFILLED') then
      raise exception '0315 self-assert FAIL: the ledger, the book or the event of a delivery is missing';
    end if;
    -- `paid` is the book, not the ledger: a merchant's ledger is compacted inside the 24 h it reports
    if (public.bonus_figures(v_port, v_since) ->> 'paid')::bigint <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: Stats does not see the delivery: %', public.bonus_figures(v_port, v_since);
    end if;
    insert into public.contract_deliveries (port_id, player_id, bonus) values (v_port, v_p2, 7);
    if (public.bonus_figures(v_port, v_since) ->> 'paid')::bigint <> v_pu * 3 + 7 then
      raise exception '0315 self-assert FAIL: paid does not read the book';
    end if;
    delete from public.trade_contracts where port_id = v_port;

    -- (c) THE FLOOR IS KEPT: sale price plus bonus under her floor, no delivery, the line refused as it always was
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    perform public.fleet_load(v_f1, v_code, 5);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, v_bid + v_pu + 100, v_l1);
    if v_a ->> 'error_code' is distinct from 'E_PRICE_LIMIT' or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_pu * 3 or public.fleet_cargo_qty(v_f1, v_code) <> 5 then
      raise exception '0315 self-assert FAIL: she sold under her floor for a bonus: %', v_a;
    end if;

    -- (d) THE BONUS LIFTS A SALE THE FLOOR REFUSED: what the budget pays for lands, the rest stays aboard, the order stands
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, v_bid + v_pu / 2.0, v_l1);
    if not coalesce((v_a ->> 'ok')::boolean, false) or (v_a #>> '{result,bonus}')::bigint is distinct from v_pu * 3 or public.fleet_cargo_qty(v_f1, v_code) <> 2 then
      raise exception '0315 self-assert FAIL: the bonus did not lift the sale over her floor: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;

    -- (e) NOT A PLAYER'S ROUTE, NOT AN ORDERED SALE, NOT A SALE OF A SET QUANTITY
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    perform public.fleet_load(v_f2, v_code, 1);
    v_a := pg_temp.sell_0315(v_p2, v_f2, v_code, null, v_l2);
    if not coalesce((v_a ->> 'ok')::boolean, false) or v_a #> '{result,bonus}' is not null then
      raise exception '0315 self-assert FAIL: a player''s route answered a request: %', v_a;
    end if;
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, null);
    if not coalesce((v_a ->> 'ok')::boolean, false) or v_a #> '{result,bonus}' is not null then
      raise exception '0315 self-assert FAIL: an ordered sale answered a request: %', v_a;
    end if;
    perform public.fleet_load(v_f1, v_code, 2);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1, '1');
    if not coalesce((v_a ->> 'ok')::boolean, false) or v_a #> '{result,bonus}' is not null or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: a sale of a set quantity answered a request: %', v_a;
    end if;

    -- (f) THE KNOB, BOTH WAYS: high is off; 0 answers from the start
    update public.world_config set value = to_jsonb(1000000) where key = 'contract_npc_after_hours';
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    if v_a #> '{result,bonus}' is not null or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: a high knob did not turn it off: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;
    update public.world_config set value = to_jsonb(0) where key = 'contract_npc_after_hours';
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 0);
    perform public.fleet_load(v_f1, v_code, 1);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    if (v_a #>> '{result,bonus}')::bigint is distinct from v_pu then
      raise exception '0315 self-assert FAIL: knob 0 did not answer from the start: %', v_a;
    end if;
    update public.world_config set value = to_jsonb(6) where key = 'contract_npc_after_hours';
    delete from public.trade_contracts where port_id = v_port;

    -- (g) A SHORT PURSE: the bonus is paid on what landed; what was not bought stays aboard and the order stands
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 100, 7);
    perform public.fleet_load(v_f1, v_code, 30);
    perform pg_temp.purse_0315(v_port, ceil(v_bid * 15)::bigint);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    if not coalesce((v_a ->> 'ok')::boolean, false) or (v_a #>> '{result,qty}')::numeric >= 30 or (v_a #>> '{result,bonus}')::bigint is distinct from v_pu * (30 - public.fleet_cargo_qty(v_f1, v_code)) then
      raise exception '0315 self-assert FAIL: a short purse: the bonus is not on what landed: %, % left aboard', v_a, public.fleet_cargo_qty(v_f1, v_code);
    end if;
    perform pg_temp.purse_0315(v_port, 1000000000);
    delete from public.trade_contracts where port_id = v_port;
    perform public.fleet_unload(v_f1, v_code, public.fleet_cargo_qty(v_f1, v_code));

    -- (h) TODAY'S ALLOWANCE SPENT: no delivery, the sale refuses in its own words, the request stands
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    perform public.fleet_load(v_f1, v_code, 5);
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values (v_p1, v_port, v_good, world.game_day(), 100000000)
    on conflict (player_id, port_id, good_id, game_day) do update set qty = excluded.qty;
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    if v_a ->> 'error_code' is distinct from 'E_DAILY_CAP' or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: a spent allowance: %', v_a;
    end if;
    delete from public.trade_daily where player_id = v_p1 and port_id = v_port and good_id = v_good;
    delete from public.trade_contracts where port_id = v_port;
    perform public.fleet_unload(v_f1, v_code, public.fleet_cargo_qty(v_f1, v_code));

    -- (i) A DELIVERY PAST ITS DEADLINE IS REFUSED, THOUGH NOTHING HAS WOUND THE BOARD: the door judges the row, and a delivery draws nothing
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7, 0);
    perform public.fleet_load(v_f2, v_code, 1);
    perform cmd.assume_identity(c_p2);
    v_a := cmd.fulfil(v_f2, v_id, null);
    if v_a ->> 'error_code' is distinct from 'E_CONTRACT_EXPIRED' then
      raise exception '0315 self-assert FAIL: an overdue row took a delivery: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    v_a := cmd.fulfil(v_f2, v_id, null);
    if not coalesce((v_a ->> 'ok')::boolean, false) or exists (select 1 from public.trade_contracts t where t.port_id = v_port and t.id <> v_id) then
      raise exception '0315 self-assert FAIL: a delivery wound the board: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;

    -- (j) THE LAP'S BOOKS: a fresh lap, a parcel with a cost: sold holds the bonus; tax and wages are both parts', and the ledger's
    insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_r1, 2, now()) returning id into v_l1;
    update public.standing_routes set lap_id = v_l1, lap_no = 2 where id = v_r1;
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7);
    perform public.fleet_load(v_f1, v_code, 5, 1);
    v_was := (select p.ducats from public.players p where p.id = v_p1);
    v_a := pg_temp.sell_0315(v_p1, v_f1, v_code, null, v_l1);
    v_b := v_a -> 'result';
    perform cmd.standing_route_close_lap(v_r1, now());
    select * into v_lap from public.standing_route_laps l where l.id = v_l1;
    -- what the lap says she was paid, less tax and wages, is what her purse moved
    if v_lap.sold <> round((v_b ->> 'total')::numeric) or v_lap.taxes <> round((v_b ->> 'tax')::numeric) or v_lap.wages <> round((v_b ->> 'wages')::numeric)
       or v_lap.net <> v_lap.sold - v_lap.wages + v_lap.stock_out - v_lap.taxes
       or v_lap.sold - v_lap.taxes - v_lap.wages <> (select p.ducats from public.players p where p.id = v_p1) - v_was then
      raise exception '0315 self-assert FAIL: the lap''s books do not hold the delivery: %, %', to_jsonb(v_lap), v_b;
    end if;
    if v_lap.taxes <> (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p1 and l.kind = 'TAX') then
      raise exception '0315 self-assert FAIL: the lap''s tax is not what the ledger paid: % against %', v_lap.taxes, (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p1 and l.kind = 'TAX');
    end if;
    delete from public.trade_contracts where port_id = v_port;

    -- (k) THE WIND, ON THE PROBE HARBOUR ALONE: what is overdue goes home, the board is topped up to the cap, one post a step
    update public.world_config set value = to_jsonb(30000) where key = 'contract_wind_ms';
    v_id := pg_temp.ask_0315(v_port, v_good, v_pu, v_pu * 3, 7, 0);
    v_was := coalesce((select max(f.id) from public.treasury_flows f), 0);
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (select t.status from public.trade_contracts t where t.id = v_id) <> 'expired' or (v_a ->> 'home')::bigint <> v_pu * 3 or (v_a ->> 'expired_ports')::int <> 1
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_was and f.kind = 'BOUNTY_LAPSED' and f.port_id = v_port) <> v_pu * 3 then
      raise exception '0315 self-assert FAIL: the wind did not send the overdue budget home: %', v_a;
    end if;
    if (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open') <> public.wc_int('contract_open_max')
       or (v_a ->> 'posted')::int <> public.wc_int('contract_open_max') or (v_a ->> 'tried')::int <> public.wc_int('contract_open_max') or (v_a ->> 'failed')::int <> 0 then
      raise exception '0315 self-assert FAIL: the wind did not top the harbour up to the cap: %', v_a;
    end if;
    -- at the cap, no try and no draw
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 0 then
      raise exception '0315 self-assert FAIL: a full board was asked again: %', v_a;
    end if;
    -- a city under the floor is left alone: no try, no rest
    delete from public.trade_contracts where port_id = v_port;
    update public.world_config set value = to_jsonb(1000) where key = 'treasury_reserve_floor';
    perform pg_temp.purse_0315(v_port, 999);
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 0 or exists (select 1 from public.contract_wind w where w.port_id = v_port) then
      raise exception '0315 self-assert FAIL: a city under the floor was asked: %', v_a;
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';
    -- a harbour that cannot post rests
    perform pg_temp.purse_0315(v_port, 0);
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 1 or (v_a ->> 'posted')::int <> 0 or not exists (select 1 from public.contract_wind w where w.port_id = v_port and w.next_try > now()) then
      raise exception '0315 self-assert FAIL: a harbour that cannot post does not rest: %', v_a;
    end if;
    perform pg_temp.purse_0315(v_port, 1000000000);
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int <> 0 then
      raise exception '0315 self-assert FAIL: a resting harbour was asked: %', v_a;
    end if;
    delete from public.contract_wind where port_id = v_port;
    -- the budget stops it, and 0 is off
    update public.world_config set value = to_jsonb(1) where key = 'contract_wind_ms';
    call public.tick_contract_wind(false, v_port);
    v_a := (select r.receipt from public.contract_wind_runs r where r.at = now());
    if (v_a ->> 'tried')::int > 1 then
      raise exception '0315 self-assert FAIL: the wind ran past its budget: %', v_a;
    end if;
    delete from public.trade_contracts where port_id = v_port;
    update public.world_config set value = to_jsonb(0) where key = 'contract_wind_ms';
    call public.tick_contract_wind(false, v_port);
    if exists (select 1 from public.trade_contracts t where t.port_id = v_port and t.status = 'open') then
      raise exception '0315 self-assert FAIL: contract_wind_ms 0 is not off';
    end if;

    -- (l) THE PLAN: on the leg to v_to, a good of her wares and a good that is not, both paying on their own
    update public.world_config set value = to_jsonb(1000000) where key = 'npc_buyers_per_good';   -- the real merchants' places are not under test
    v_rows := world.trade_routes(v_port, null, null, 12, v_to) -> 'routes';
    if jsonb_array_length(v_rows) < 2 then
      raise exception '0315 self-assert FAIL: the probe leg carries one good: %', v_rows;
    end if;
    update public.npc_houses set wares = array[v_rows -> 0 ->> 'code'] where player_id = v_p1;
    delete from public.trade_contracts where port_id = v_to;
    perform pg_temp.purse_0315(v_to, 1000000000);
    v_a := public.npc_leg_lines(v_r1, v_port, v_to, 100000, 20, 5);
    if not coalesce((v_a ->> 'any')::boolean, false) or not (v_a -> 'lines' @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', v_rows -> 0 ->> 'code')))
       or v_a -> 'lines' @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', v_rows -> 1 ->> 'code')) then
      raise exception '0315 self-assert FAIL: the probe leg is not one ware: %', v_a;
    end if;
    -- a young request is not counted
    v_id := pg_temp.ask_0315(v_to, (v_rows -> 0 ->> 'good_id')::uuid, 50, 100000000, 5);
    v_b := public.npc_leg_lines(v_r1, v_port, v_to, 100000, 20, 5);
    if (v_b ->> 'profit')::numeric <> (v_a ->> 'profit')::numeric then
      raise exception '0315 self-assert FAIL: the plan counted a young request: %, %', v_a, v_b;
    end if;
    -- the bonus joins the leg's profit, on what the parcel carries
    update public.trade_contracts set created_at = now() - interval '7 hours' where id = v_id;
    v_b := public.npc_leg_lines(v_r1, v_port, v_to, 100000, 20, 5);
    if (v_b ->> 'profit')::numeric - (v_a ->> 'profit')::numeric <> 50 * (select (e ->> 'qty')::numeric from jsonb_array_elements(v_a -> 'lines') e where e ->> 'kind' = 'BUY' limit 1) then
      raise exception '0315 self-assert FAIL: the bonus is not in the leg''s profit: %, %', v_a, v_b;
    end if;
    -- a good asked for is looked at though it is not of her wares
    delete from public.trade_contracts where port_id = v_to;
    perform pg_temp.ask_0315(v_to, (v_rows -> 1 ->> 'good_id')::uuid, 50, 100000000, 7);
    v_b := public.npc_leg_lines(v_r1, v_port, v_to, 100000, 20, 5);
    if not (v_b -> 'lines' @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', v_rows -> 1 ->> 'code'))) then
      raise exception '0315 self-assert FAIL: a good asked for was not looked at: %', v_b;
    end if;

    raise exception using errcode = 'ZX315', message = 'rolled back';
  exception when sqlstate 'ZX315' then
    null;
  end;
  drop function pg_temp.purse_0315(uuid, bigint);
  drop function pg_temp.ask_0315(uuid, uuid, numeric, bigint, numeric, int);
  drop function pg_temp.sell_0315(uuid, uuid, text, numeric, uuid, text);
  drop function pg_temp.worth_0315(uuid, uuid);

  if (select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) from public.world_config x) <> v_cfg_after then
    raise exception '0315 self-assert FAIL: a world_config row moved';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa do Mercador %') then
    raise exception '0315 self-assert FAIL: a probe house stayed';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0315 self-assert FAIL: over budget, %', clock_timestamp() - v_t0;
  end if;
  raise notice '0315 self-assert ok: a merchant answered, spent a budget, sold the rest, kept her floor, closed her lap; the wind expired and topped up; the plan counted the bonus; in %', clock_timestamp() - v_t0;
end
$m$;
