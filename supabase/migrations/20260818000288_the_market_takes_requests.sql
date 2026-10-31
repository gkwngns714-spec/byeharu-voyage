-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0288 — THE MARKET TAKES REQUESTS
--        The Market face's third door: the player names a good, a quantity and the price she will
--        pay, puts the money in, and merchants bring it to her home city when the price is good.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-31 (verbatim): "Request i press, a page shows up, where i search trade good -
-- press it, shows up chart, choose price to buy, and then the put the money in it. - the order is
-- made, and merchants will come and sell it to you if the price is reasonable" and "but this
-- feature, request, should only be done in your home country- home city. get it?"
--
-- ── WHAT THIS IS ───────────────────────────────────────────────────────────────────────────────
--   public.market_requests   one standing BUY order: (player, port, good, qty left, unit price,
--                            escrow left, status). The escrow column IS the money set aside — it
--                            left the house's purse through public.credit at placement and is
--                            counted in the world's set-aside figure only while it sits here.
--   public.home_port_of()    THE ONE reading of "home city": the port of the player's earliest
--                            FOUNDED event (new_house writes `port` into its payload). No second
--                            notion of home is minted.
--   world.requests(port)     the caller's own open requests at one port, and whether that port IS
--                            her home city (the client draws the Request door only when it is).
--   cmd.request_place()      the press: home city only (E_NOT_HOME on the SERVER — hiding a door is
--                            not an enforcement), a whole quantity, a price, the escrow through
--                            public.credit as its own REQUEST_ESCROW ledger row.
--   cmd.request_cancel()     the way back: the unfilled part of the escrow returns as
--                            REQUEST_REFUND and the order is closed. Filled parts never return.
--   public.market_request_fill(fleet)
--                            called ONLY by the new trigger when a fleet's status becomes DOCKED.
--                            A merchant house (players.is_npc, 0097's one predicate) sells into the
--                            best-priced open request at her port for a good she carries, at the
--                            request's own price, provided that price is at least the quay's ask
--                            (world.price — the one pricing authority). The goods go ashore
--                            through public.storage_put (the one storage writer), the cargo leaves
--                            through public.fleet_unload (the one unload), the money reaches her
--                            through public.credit as REQUEST_FILL. No second rule is spelt.
--
-- ── WHAT THIS IS NOT, AND DOES NOT MOVE ───────────────────────────────────────────────────────
--   * NO new cron job, NO schedule, NO TTL and NO cadence change (owner: "do not change anything
--     regarding time"). The fill rides the EXISTING arrival path — a trigger on the fleets status
--     update voyage.settle already performs; voyage.settle itself is untouched.
--   * NO knob, NO switch, NO economy flag. NO function body is re-cut: the only existing function
--     this file changes is public.client_rpc_entry_points() — three rows added between its own
--     lines, by the house recut that asserts the pre-image occurs exactly once.
--   * NO client write grants: the table is RLS-on with no policy and no client privilege; the
--     three doors are the only way in.
--   * The market's own prices are READ (world.price) — never re-derived here.
--
-- ── SERVED ─────────────────────────────────────────────────────────────────────────────────────
--   world.requests(port) -> {ok, home, requests:[{id, good_id, code, name, qty, unit_price, escrow,
--   created_at}]} — the caller's own open requests, newest first. `home` is the server's answer to
--   "is this my home city", the same public.home_port_of the verb enforces.
--
-- ── PROOF DISCIPLINE ───────────────────────────────────────────────────────────────────────────
-- The self-assert below plants ONE probe house and ONE probe merchant on 2004 rows, drives the
-- verb refusals, the escrow, a full fill, a partial fill with its cancel-refund, and a price below
-- the ask that must not fill — then rolls the whole probe back on its own sentinel (ZX288) and
-- asserts the probe houses and requests are gone. It never counts or sums a growing table and it
-- touches no row it did not create.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE PRE-IMAGE, and the one recut helper the chain uses ──────────────────────────────────
create temp table pre_0288 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury;

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
      raise exception '0288 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── 1. THE TABLE ───────────────────────────────────────────────────────────────────────────────
create table public.market_requests (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players(id) on delete cascade,
  port_id    uuid not null references public.ports(id),
  good_id    uuid not null references public.goods(id),
  qty        numeric(12,2) not null check (qty >= 0),
  unit_price bigint not null check (unit_price > 0),
  escrow     bigint not null check (escrow >= 0),
  status     text not null default 'open' check (status in ('open', 'filled', 'cancelled')),
  created_at timestamptz not null default now()
);
comment on table public.market_requests is
  '0288: a house''s standing buy order at ONE port (the owner''s Market Request). qty and escrow '
  'are what is LEFT; escrow is money already taken from the purse by public.credit (REQUEST_ESCROW) '
  'and returns only as REQUEST_REFUND for the unfilled part. Written by cmd.request_place, '
  'cmd.request_cancel and public.market_request_fill alone.';

create index market_requests_open_port on public.market_requests (port_id, unit_price desc, created_at)
  where status = 'open';

alter table public.market_requests enable row level security;
revoke all on table public.market_requests from public, anon, authenticated;

-- ── 2. HOME CITY — the one reading ─────────────────────────────────────────────────────────────
create function public.home_port_of(p_player uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0288: the port of the house's EARLIEST FOUNDED event (new_house puts `port` = the port CODE in
  -- the payload). Null when no founding is on record — a house with no home has no requests.
  select p.id
    from public.events e
    join public.ports p on p.code = e.payload->>'port'
   where e.player_id = p_player and e.kind = 'FOUNDED'
   order by e.created_at asc
   limit 1
$$;
comment on function public.home_port_of(uuid) is
  '0288: THE one reading of a house''s home city — its earliest FOUNDED event''s port. Used by the '
  'Request verb''s gate and by world.requests'' `home` flag; no second notion of home exists.';
revoke all on function public.home_port_of(uuid) from public, anon, authenticated;

-- ── 3. THE READ ────────────────────────────────────────────────────────────────────────────────
create function world.requests(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_rows   jsonb;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  select jsonb_agg(jsonb_build_object(
           'id',         r.id,
           'good_id',    r.good_id,
           'code',       g.code,
           'name',       g.name,
           'qty',        r.qty,
           'unit_price', r.unit_price,
           'escrow',     r.escrow,
           'created_at', r.created_at
         ) order by r.created_at desc)
    into v_rows
    from public.market_requests r
    join public.goods g on g.id = r.good_id
   where r.player_id = v_player and r.port_id = p_port and r.status = 'open';
  return jsonb_build_object(
    'ok', true,
    'home', coalesce(public.home_port_of(v_player) = p_port, false),
    'requests', coalesce(v_rows, '[]'::jsonb));
end $$;
comment on function world.requests(uuid) is
  '0288: the caller''s own OPEN market requests at one port, and whether that port is her home '
  'city (public.home_port_of). The client draws the Request door only when `home` is true; the '
  'verb enforces it regardless.';
revoke all on function world.requests(uuid) from public, anon;
grant execute on function world.requests(uuid) to authenticated;

-- ── 4. THE TWO VERBS ──────────────────────────────────────────────────────────────────────────
create function cmd.request_place(p_port uuid, p_good uuid, p_qty numeric, p_price bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_det    text;
  v_esc    bigint;
  v_id     uuid;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    -- THE OWNER'S GATE, ON THE SERVER: requests are made only in the home city.
    if public.home_port_of(v_player) is distinct from p_port then
      perform cmd.refuse('E_NOT_HOME', 'a request is made only in your home city');
    end if;
    if coalesce(p_qty, 0) <= 0 or p_qty <> floor(p_qty) then
      perform cmd.refuse('E_NO_QTY', 'ask for a whole number of units');
    end if;
    if coalesce(p_price, 0) <= 0 then
      perform cmd.refuse('E_NO_PRICE', 'name the price you will pay');
    end if;
    if not exists (select 1 from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good) then
      perform cmd.refuse('E_NO_SUCH_GOOD', 'this city does not trade that good');
    end if;
    v_esc := round(p_qty * p_price)::bigint;
    -- THE MONEY LEAVES THE PURSE HERE — the one ledger mover, its own kind. It raises
    -- E_INSUFFICIENT_FUNDS when the purse will not cover it; the envelope below carries it out.
    perform public.credit(v_player, 'REQUEST_ESCROW', -v_esc);
    insert into public.market_requests (player_id, port_id, good_id, qty, unit_price, escrow)
    values (v_player, p_port, p_good, p_qty, p_price, v_esc)
    returning id into v_id;
    perform public.emit_event(v_player, 'REQUESTED',
      jsonb_build_object('request', v_id, 'port', p_port, 'good', p_good,
                         'qty', p_qty, 'price', p_price, 'escrow', v_esc));
    return jsonb_build_object('ok', true, 'request', jsonb_build_object(
      'id', v_id, 'qty', p_qty, 'unit_price', p_price, 'escrow', v_esc));
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;
comment on function cmd.request_place(uuid, uuid, numeric, bigint) is
  '0288: the Market Request press — home city only (E_NOT_HOME), whole quantity, a price, the '
  'escrow through public.credit as REQUEST_ESCROW. Part of the money set aside.';
revoke all on function cmd.request_place(uuid, uuid, numeric, bigint) from public, anon;
grant execute on function cmd.request_place(uuid, uuid, numeric, bigint) to authenticated;

create function cmd.request_cancel(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_det    text;
  r        public.market_requests%rowtype;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    select * into r from public.market_requests where id = p_request for update;
    if r.id is null or r.player_id is distinct from v_player then
      perform cmd.refuse('E_NO_SUCH_REQUEST', 'no such request of yours');
    end if;
    if r.status <> 'open' then
      perform cmd.refuse('E_REQUEST_DONE', 'that request is already closed');
    end if;
    update public.market_requests
       set status = 'cancelled', qty = 0, escrow = 0
     where id = r.id;
    if r.escrow > 0 then
      perform public.credit(v_player, 'REQUEST_REFUND', r.escrow);
    end if;
    perform public.emit_event(v_player, 'REQUEST_CANCELLED',
      jsonb_build_object('request', r.id, 'refund', r.escrow));
    return jsonb_build_object('ok', true, 'refund', r.escrow);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;
comment on function cmd.request_cancel(uuid) is
  '0288: closes a house''s own open request and returns the UNFILLED part of its escrow as '
  'REQUEST_REFUND. A filled part never returns.';
revoke all on function cmd.request_cancel(uuid) from public, anon;
grant execute on function cmd.request_cancel(uuid) to authenticated;

-- ── 5. THE ARRIVAL FILL — triggered by the status update voyage.settle already performs ───────
create function public.market_request_fill(p_fleet uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r        record;
  v_owner  uuid;
  v_port   uuid;
  v_npc    boolean;
  v_ask    numeric;
  v_room   numeric;
  v_bulk   numeric;
  v_take   numeric;
  v_money  bigint;
  n        int := 0;
begin
  select f.player_id, f.port_id into v_owner, v_port
    from public.fleets f where f.id = p_fleet;
  if v_owner is null or v_port is null then return 0; end if;
  select p.is_npc into v_npc from public.players p where p.id = v_owner;
  if not coalesce(v_npc, false) then return 0; end if;
  if not exists (select 1 from public.market_requests mr
                  where mr.port_id = v_port and mr.status = 'open') then
    return 0;
  end if;

  -- THE MERCHANT'S ORDERS: best price first, then the oldest. One row per open request AT THIS PORT
  -- for a good she carries and the quay actually prices (port_goods — world.price's own guard).
  for r in select mr.id, mr.player_id, mr.good_id, mr.qty, mr.unit_price, mr.escrow,
                  g.code, g.bulk
             from public.market_requests mr
             join public.goods g  on g.id = mr.good_id
             join public.port_goods pg on pg.port_id = mr.port_id and pg.good_id = mr.good_id
            where mr.port_id = v_port and mr.status = 'open'
            order by mr.unit_price desc, mr.created_at asc
  loop
    select w.ask into v_ask from world.price(v_port, r.good_id) w;
    -- "IF THE PRICE IS REASONABLE": she sells at the request's price only when it is at least what
    -- the quay would pay her now (the ask). Below it she has no reason to come.
    if v_ask is null or r.unit_price < v_ask then continue; end if;
    v_bulk := greatest(coalesce(r.bulk, 1), 0.001);
    v_room := public.storage_cap(v_port) - public.storage_used(r.player_id, v_port);
    v_take := least(r.qty, public.fleet_cargo_qty(p_fleet, r.code),
                    floor(greatest(v_room, 0) / v_bulk));
    if v_take <= 0 then continue; end if;
    v_take := public.fleet_unload(p_fleet, r.code, v_take);
    if v_take <= 0 then continue; end if;
    -- the one storage writer, with the price the house paid as the goods' basis
    perform public.storage_put(r.player_id, v_port, r.good_id, v_take, r.unit_price);
    v_money := round(v_take * r.unit_price)::bigint;
    -- the one ledger mover, from the escrow into the merchant's purse
    perform public.credit(v_owner, 'REQUEST_FILL', v_money);
    update public.market_requests
       set qty    = r.qty - v_take,
           escrow = r.escrow - v_money,
           status = case when r.qty - v_take <= 0 then 'filled' else 'open' end
     where id = r.id;
    perform public.emit_event(r.player_id, 'REQUEST_FILLED',
      jsonb_build_object('request', r.id, 'good', r.good_id, 'qty', v_take,
                         'price', r.unit_price, 'merchant', v_owner));
    n := n + 1;
  end loop;
  return n;
end $$;
comment on function public.market_request_fill(uuid) is
  '0288: a merchant house docking at a port sells her carried goods into the best-priced open '
  'request(s) there, at the request''s price, when that price is at least the quay''s ask. Goods go '
  'ashore through public.storage_put; her cargo leaves through public.fleet_unload; money reaches '
  'her through public.credit (REQUEST_FILL). Called only by the fleets status trigger.';
revoke all on function public.market_request_fill(uuid) from public, anon, authenticated;

-- The trigger: AFTER the status update, only on a transition INTO DOCKED. voyage.settle is not
-- touched; its own UPDATE fires this.
create function public.tg_market_request_fill()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.market_request_fill(new.id);
  return new;
end $$;
revoke all on function public.tg_market_request_fill() from public, anon, authenticated;

create trigger fleets_fill_market_requests
  after update of status on public.fleets
  for each row
  when (new.status = 'DOCKED' and new.port_id is not null and old.status is distinct from 'DOCKED')
  execute function public.tg_market_request_fill();

-- ── 6. THE CLIENT MAY CALL THE THREE DOORS ────────────────────────────────────────────────────
select pg_temp.recut('public.client_rpc_entry_points()'::regprocedure, false,
  $e0$      ('world',       'goods_forge',           'uuid'),
      ('cmd',         'forge_good',            'uuid, uuid, int')$e0$,
  $e1$      ('world',       'goods_forge',           'uuid'),
      ('cmd',         'forge_good',            'uuid, uuid, int'),
      -- 0288 (the Market face's Request): the caller's own open requests at a port (with `home`),
      -- and the two verbs. The server refuses outside the home city (E_NOT_HOME).
      ('world',       'requests',              'uuid'),
      ('cmd',         'request_place',         'uuid, uuid, numeric, bigint'),
      ('cmd',         'request_cancel',        'uuid')$e1$);

-- ── 7. SELF-ASSERT — one probe house and one probe merchant, driven and rolled back ───────────
do $probe$
declare
  v_home   uuid;
  v_other  uuid;
  v_good   uuid;
  v_code   text;
  v_ask    numeric;
  v_below  bigint;
  v_p      uuid;
  v_auth   uuid;
  v_m      uuid;
  v_mfleet uuid;
  v_res    jsonb;
  v_req    uuid;
  v_esc    bigint;
  v_pp0    bigint;
  v_pp1    bigint;
  v_mp0    bigint;
  v_mp1    bigint;
begin
  select id into v_home from public.ports where code = 'LIS' and kind = 'HARBOUR';
  select id into v_other from public.ports p
   where p.kind = 'HARBOUR' and p.code <> 'LIS' order by p.code limit 1;
  select pg.good_id, g.code into v_good, v_code
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_home order by g.code limit 1;
  select w.ask into v_ask from world.price(v_home, v_good) w;

  -- (a) A PROBE HOUSE AT LIS, and the home reading. The probe acts AS that house: both JWT shims are
  -- set (Supabase reads `request.jwt.claims`, the local chain `request.jwt.claim.sub` — 0008's own
  -- note), so cmd.request_place's current_player_id() is the probe.
  v_auth := gen_random_uuid();
  v_p := public.new_house(v_auth, 'Probe0288A', 'PRT', 'LIS', 'ProbeFleet0288A',
                          'barca', 'ProbeShip0288A', 100000::bigint, false);
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth)::text, true);
  if public.home_port_of(v_p) is distinct from v_home then
    raise exception '0288 self-assert FAIL: the home city does not resolve to the founding port';
  end if;

  -- (b) THE OWNER'S GATE: refused away from home, by the verb itself
  v_res := cmd.request_place(v_other, v_good, 2, greatest(v_ask::bigint, 1) + 5);
  if coalesce((v_res->>'ok')::boolean, true) or (v_res->>'error_code') is distinct from 'E_NOT_HOME' then
    raise exception '0288 self-assert FAIL: a request outside the home city was not refused E_NOT_HOME: %', v_res;
  end if;

  -- (c) the purse must cover the escrow
  v_res := cmd.request_place(v_home, v_good, 1, 1000000000);
  if coalesce((v_res->>'ok')::boolean, true) or (v_res->>'error_code') is distinct from 'E_INSUFFICIENT_FUNDS' then
    raise exception '0288 self-assert FAIL: an unaffordable request was not refused: %', v_res;
  end if;

  -- (d) PLACEMENT: the escrow leaves the purse, the row stands, the read serves it with home = true
  select p.ducats into v_pp0 from public.players p where p.id = v_p;
  v_res := cmd.request_place(v_home, v_good, 5, greatest(v_ask::bigint, 1) + 10);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception '0288 self-assert FAIL: the placement was refused: %', v_res;
  end if;
  v_req := (v_res->'request'->>'id')::uuid;
  v_esc := (v_res->'request'->>'escrow')::bigint;
  select p.ducats into v_pp1 from public.players p where p.id = v_p;
  if v_pp0 - v_pp1 <> v_esc or v_esc <> 5 * (greatest(v_ask::bigint, 1) + 10) then
    raise exception '0288 self-assert FAIL: the escrow (% vs purse drop %) does not match 5 x price', v_esc, v_pp0 - v_pp1;
  end if;
  if (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'REQUEST_ESCROW') <> 1 then
    raise exception '0288 self-assert FAIL: no REQUEST_ESCROW ledger row';
  end if;
  v_res := world.requests(v_home);
  if not coalesce((v_res->>'home')::boolean, false) or jsonb_array_length(v_res->'requests') <> 1 then
    raise exception '0288 self-assert FAIL: the read does not serve the request with home = true: %', v_res;
  end if;

  -- (e) A MERCHANT COMES: her arrival (a status update INTO DOCKED) fills the request at its price
  v_m := public.new_house(null::uuid, 'Probe0288M', 'PRT', 'LIS', 'ProbeFleet0288M',
                          'barca', 'ProbeShip0288M', 10000::bigint, true);
  select f.id into v_mfleet from public.fleets f where f.player_id = v_m order by f.created_at limit 1;
  perform public.fleet_load(v_mfleet, v_code, 5);
  select p.ducats into v_mp0 from public.players p where p.id = v_m;
  update public.fleets set status = 'SAILING', port_id = null where id = v_mfleet;
  update public.fleets set status = 'DOCKED', port_id = v_home where id = v_mfleet;
  select p.ducats into v_mp1 from public.players p where p.id = v_m;
  if (select mr.status from public.market_requests mr where mr.id = v_req) <> 'filled' then
    raise exception '0288 self-assert FAIL: the arrival did not fill the request';
  end if;
  if v_mp1 - v_mp0 <> v_esc then
    raise exception '0288 self-assert FAIL: the merchant was paid % not the escrow %', v_mp1 - v_mp0, v_esc;
  end if;
  if (select coalesce(ps.qty, 0) from public.player_storage ps
       where ps.player_id = v_p and ps.port_id = v_home and ps.good_id = v_good) < 5 then
    raise exception '0288 self-assert FAIL: the goods did not go ashore';
  end if;

  -- (f) A PARTIAL FILL, then the cancel refunds exactly what is left
  v_res := cmd.request_place(v_home, v_good, 4, greatest(v_ask::bigint, 1) + 10);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception '0288 self-assert FAIL: the second placement was refused: %', v_res;
  end if;
  v_req := (v_res->'request'->>'id')::uuid;
  perform public.fleet_load(v_mfleet, v_code, 2);
  update public.fleets set status = 'SAILING', port_id = null where id = v_mfleet;
  update public.fleets set status = 'DOCKED', port_id = v_home where id = v_mfleet;
  if (select mr.qty from public.market_requests mr where mr.id = v_req) <> 2 then
    raise exception '0288 self-assert FAIL: a partial fill left % not 2 of 4',
      (select mr.qty from public.market_requests mr where mr.id = v_req);
  end if;
  select p.ducats into v_pp0 from public.players p where p.id = v_p;
  v_res := cmd.request_cancel(v_req);
  select p.ducats into v_pp1 from public.players p where p.id = v_p;
  if not coalesce((v_res->>'ok')::boolean, false) or v_pp1 - v_pp0 <> 2 * (greatest(v_ask::bigint, 1) + 10) then
    raise exception '0288 self-assert FAIL: the cancel did not refund the unfilled remainder: %', v_res;
  end if;

  -- (g) A PRICE BELOW THE ASK DOES NOT FILL — "if the price is reasonable"
  v_below := case when ceil(v_ask)::bigint > floor(v_ask)::bigint
                  then floor(v_ask)::bigint else (v_ask::bigint - 1) end;
  if v_below >= 1 then
    v_res := cmd.request_place(v_home, v_good, 1, v_below);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0288 self-assert FAIL: the below-ask placement was refused: %', v_res;
    end if;
    v_req := (v_res->'request'->>'id')::uuid;
    perform public.fleet_load(v_mfleet, v_code, 1);
    update public.fleets set status = 'SAILING', port_id = null where id = v_mfleet;
    update public.fleets set status = 'DOCKED', port_id = v_home where id = v_mfleet;
    if (select mr.status from public.market_requests mr where mr.id = v_req) <> 'open' then
      raise exception '0288 self-assert FAIL: a request below the ask was filled';
    end if;
  end if;

  -- (h) the registry grew by exactly three; no job, no switch, no wall moved
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from pre_0288) + 3 then
    raise exception '0288 self-assert FAIL: the registry grew by % not 3',
      (select count(*) from public.client_rpc_entry_points()) - (select entry_points from pre_0288);
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'world' and e.function_name = 'requests' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'cmd' and e.function_name = 'request_place' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'cmd' and e.function_name = 'request_cancel' and e.fn is not null) then
    raise exception '0288 self-assert FAIL: a new entry point does not resolve';
  end if;
  -- NO JOB IS ADDED (owner: no time changes). pg_cron is absent on PGlite, so the check is dynamic.
  declare
    v_jobs int := 0;
  begin
    if to_regclass('cron.job') is not null then
      execute $q$select count(*) from cron.job where command ilike '%market_request%'$q$ into v_jobs;
    end if;
    if v_jobs <> 0 then
      raise exception '0288 self-assert FAIL: a job names market_request — this file adds no job';
    end if;
  end;
  if (select value from public.world_config where key = 'economy_closed') is distinct from (select economy_closed from pre_0288)
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from (select city_treasury from pre_0288) then
    raise exception '0288 self-assert FAIL: an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0288 self-assert FAIL: a wall moved';
  end if;

  raise exception using errcode = 'ZX288', message = 'rollback';
exception when sqlstate 'ZX288' then
  null;
end $probe$;

-- The probe's own rows are gone with its subtransaction.
do $$
begin
  if exists (select 1 from public.players p where p.company_name like 'Probe0288%') then
    raise exception '0288 self-assert FAIL: a probe house survived its rollback';
  end if;
  if exists (select 1 from public.market_requests r
              join public.players p on p.id = r.player_id
             where p.company_name like 'Probe0288%') then
    raise exception '0288 self-assert FAIL: a probe request survived its rollback';
  end if;
end $$;

do $$
begin
  raise notice '0288 self-assert ok: THE MARKET TAKES REQUESTS. home_port_of resolves the founding FOUNDED event; world.requests serves the caller''s own open rows with `home`; cmd.request_place refuses E_NOT_HOME away from home and E_INSUFFICIENT_FUNDS under the escrow; placement moves exactly qty x price into REQUEST_ESCROW and a cancel returns the unfilled part as REQUEST_REFUND; a merchant docking with goods fills at the request''s price when it is at least the quay ask, through storage_put / fleet_unload / credit (REQUEST_FILL), and a price below the ask does not fill. The probe rolled back; registry +3 (% -> %); jobs, switches and walls as found.',
    (select entry_points from pre_0288),
    (select count(*) from public.client_rpc_entry_points());
end $$;
