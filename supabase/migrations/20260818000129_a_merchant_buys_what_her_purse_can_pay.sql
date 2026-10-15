-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0129 — A MERCHANT BUYS WHAT HER PURSE CAN PAY
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS FOUND (prod, read-only, laps closed 2026-10-15 12:00–15:00 UTC, head 0128) ─────────
-- 3,564 merchant laps closed: 333 profit / 3,231 loss — yet the average lap NETTED +378 d. The
-- "bought 2,780 > sold 2,634" reading of the RESUME is not the loss: a lap's net is cost of goods
-- SOLD (0116: sold − bought + stock_out − stock_in − costs), and a parcel bought at the last stop is
-- carried out at cost. Split by what the lap did:
--   * 2,520 laps (71 %) neither bought nor sold a thing. Each lost only its supplies and repairs
--     (net −24 on two stops, −33 on three, −70 on four). They are 78 % of the losing laps.
--     1,940 of them (77 %) had a BUY refused E_INSUFFICIENT_FUNDS: over all 2,575 such refusals the
--     planned parcel cost a median 20,981 d. against a median purse of 3,993 d. — 4.3 times what
--     she held (2,477 of 2,575 cost more than her whole purse). do_buy refuses a line it cannot pay
--     WHOLE, so she sailed in ballast and paid stores for it.
--   * The trading laps made money on the trade itself (no lap sold below cost: 0 of 920). 604 of
--     them closed a few ducats below zero because 0128's wages — owed for every sea-day, ballast
--     days included, up to 30 days — took the whole margin and the stores were left: net ≈ −stores.
--     Fewer ballast passages means fewer such days owed.
-- THE CAUSE: the leg planner (public.npc_leg_lines, 0120) sizes a parcel by the sink, the daily
-- cap and the hold — never by the purse. 327 merchant companies hold under 5,000 d. (founded with
-- ~5,400 of capital) and sail holds a full parcel of which costs 20,000. The planner priced loops
-- on parcels she could never buy, and the quay refused them. Not the 0126 speed, not the cut-loss
-- (no sale below cost), not price drift (the sold-below-cost count is zero).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) ONE READING OF "CARGO AT COST": public.fleet_stock_at_cost(fleet) — Σ cargo × cargo_basis,
--     the expression 0116 wrote inline in cmd.standing_route_close_lap (sliced to call it).
-- (2) HER WORKING CAPITAL: public.npc_buy_budget(fleet) = (purse + cargo aboard at cost) ×
--     npc_buy_purse_pct / 100 (knob, 90). The cargo counts because at every stop her SELLs run
--     before her BUYs, and a merchant SELL is floored at what she paid (0114/0120); the 10 % kept
--     back pays the stop's stores and repairs, which also run before the BUYs.
-- (3) ONE BOUND: public.npc_affordable(port, good, qty, budget) — the most units, at most qty, whose
--     buy quote at that port (world.quote, the one price authority) is within the budget. Buying
--     raises the price, so a smaller parcel never costs more per unit; the bound walks down from
--     qty by budget ÷ quote, at most 12 quotes.
-- (4) THE PLANNER sizes every kept parcel by it (npc_leg_lines, sliced): after the sink-sized
--     quantity, before the keep test, and spends the leg's budget as it keeps — so loops are priced
--     on parcels she can pay for, and a poor merchant picks the trade her purse allows.
-- (5) THE MOMENT OF BUYING asks the same bound again (cmd.standing_route_lines, sliced — the place
--     0114 re-asks the keep test): the rendered BUY carries no more than her working capital covers
--     now, so a parcel the purse moved under since planning is cut, not refused whole.
-- Nothing else moves: the sink-sized quantity, the daily caps, the 5 % keep test, the at-profit
-- floors, the wages rule, players' orders (do_buy is untouched; the bound reads is_npc nowhere —
-- only merchant planning and merchant lines call it).
--
-- BOUNDED: per kept parcel one quote when she can pay (the common case), else a few. No world scan.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once: public.npc_leg_lines (0120 as cut by 0122/0128), cmd.standing_route_lines (0114 as cut by
-- 0120), cmd.standing_route_close_lap (0116 as cut by 0121/0122/0128). Self-asserts hold AS FOUND
-- on a lived-in world: every probe runs on its own founded merchant and rolls back.
-- VERSION: 0129. Applies on prod head 0128.

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- 0127's posture: never queue the arrivals sweep for long
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0129 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
                    'cmd.standing_route_lines(uuid, integer, uuid)',
                    'cmd.standing_route_close_lap(uuid, timestamptz)']) f(fn);

create temp table before_0129 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key = 'npc_buy_purse_pct') as knobs_found;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_buy_purse_pct', to_jsonb(90),
   '0129: the share, in percent, of a merchant''s working capital (purse + cargo aboard at cost) her '
   'parcels at one stop may cost (public.npc_buy_budget). The rest pays the stop''s stores and repairs.')
on conflict (key) do nothing;

-- ── 3. THE ONE READING, THE BUDGET, THE BOUND ──────────────────────────────────────────────────
create or replace function public.fleet_stock_at_cost(p_fleet uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0129: THE cargo aboard at what it cost (ships.cargo × cargo_basis, the basis fleet_cargo_basis
  -- reads). A lap carries it out as stock_out (0116); a merchant's budget counts it.
  select coalesce(round(sum((e.value)::text::numeric * (s.cargo_basis->>e.key)::numeric)), 0)::bigint
    from public.ships s cross join lateral jsonb_each(s.cargo) e
   where s.fleet_id = p_fleet and jsonb_typeof(s.cargo_basis->e.key) = 'number'
     and jsonb_typeof(e.value) = 'number'
$$;

create or replace function public.npc_buy_budget(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0129: what a merchant's parcels at one stop may cost — her working capital (purse + cargo aboard
  -- at cost: her SELLs run first and never below cost) less the npc_buy_purse_pct keep-back that
  -- pays the stop's stores and repairs. 0 for no such fleet.
  select coalesce((select greatest(0, floor((pl.ducats + public.fleet_stock_at_cost(f.id))
                                             * public.wc_num('npc_buy_purse_pct') / 100))
                     from public.fleets f join public.players pl on pl.id = f.player_id
                    where f.id = p_fleet), 0)
$$;

create or replace function public.npc_affordable(p_port uuid, p_good uuid, p_qty numeric, p_budget numeric)
returns table (units numeric, total numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0129: THE BOUND. The most units, at most p_qty, whose buy quote at p_port (world.quote, the one
-- price authority, no purser: never cheaper than she will pay) costs no more than p_budget. Buying
-- raises the price, so a smaller parcel never costs more a unit: the walk goes down by budget ÷
-- quote, and always by at least one, at most 12 quotes. A quote the port cannot fill at p_qty is
-- answered as asked (units p_qty) — the caller's own stock test refuses it, as before.
declare
  v_q numeric := floor(coalesce(p_qty, 0));
  v_b numeric := greatest(coalesce(p_budget, 0), 0);
  q   record;
  i   int := 0;
begin
  while v_q >= 1 and i < 12 loop
    i := i + 1;
    select * into q from world.quote(p_port, p_good, v_q, 'buy', null, null);
    if q.units is null or q.total is null or q.units < v_q then
      units := v_q; total := q.total; return next; return;
    end if;
    if q.total <= v_b then
      units := v_q; total := q.total; return next; return;
    end if;
    v_q := least(v_q - 1, floor(v_q * v_b / q.total));
  end loop;
  units := 0; total := 0; return next;
end $$;

revoke all on function public.fleet_stock_at_cost(uuid) from public, anon, authenticated;
revoke all on function public.npc_buy_budget(uuid) from public, anon, authenticated;
revoke all on function public.npc_affordable(uuid, uuid, numeric, numeric) from public, anon, authenticated;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0129 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0129 values
-- public.npc_leg_lines: a parcel is sized by what her working capital covers
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 1,
$h$--      the probe's cost x (1 + npc_sell_margin), capped by the daily cap at both ends and the hold
$h$,
$h$--      the probe's cost x (1 + npc_sell_margin), capped by the daily cap at both ends, (0129) what
--      her working capital still covers at the source (public.npc_affordable) and the hold
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 2,
$h$  v_net     numeric;   -- 0122: a parcel's margin after the sink's profit tax
$h$,
$h$  v_net     numeric;   -- 0122: a parcel's margin after the sink's profit tax
  v_budget  numeric;   -- 0129: her working capital left for this leg's parcels
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 3,
$h$  v_left  := p_hold;
$h$,
$h$  v_left  := p_hold;
  -- 0129: her fleet's working capital — the route's fleet, or (before the switch assigns it) the
  -- merchant fleet the roster keeps for this route.
  v_budget := public.npc_buy_budget(coalesce(sr.fleet_id,
                (select nf.fleet_id from public.npc_fleets nf where nf.route_id = sr.id limit 1)));
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 4,
$h$      v_q := floor(coalesce(q_size.units, 0));
      continue when v_q < 1;
$h$,
$h$      v_q := floor(coalesce(q_size.units, 0));
      continue when v_q < 1;
      -- 0129: and no more than her working capital covers at the source — the quay refuses a parcel
      -- she cannot pay for WHOLE (E_INSUFFICIENT_FUNDS), and she sails in ballast.
      select a.units into v_q from public.npc_affordable(p_from, v_good, v_q, v_budget) a;
      continue when v_q < 1;
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 5,
$h$      v_left   := v_left - v_q * v_bulk;
$h$,
$h$      v_left   := v_left - v_q * v_bulk;
      v_budget := v_budget - q_buy.total;   -- 0129
$h$),

-- cmd.standing_route_lines: the bound asked again at the moment of buying
('cmd.standing_route_lines(uuid, integer, uuid)', 1,
$h$  q       record;    -- 0114
$h$,
$h$  q       record;    -- 0114
  v_budget numeric;  -- 0129: her working capital left for this stop's BUYs
  v_aff   record;    -- 0129
$h$),
('cmd.standing_route_lines(uuid, integer, uuid)', 2,
$h$      ln.price_limit := least(coalesce(ln.price_limit, v_cap), v_cap);
    end if;
$h$,
$h$      ln.price_limit := least(coalesce(ln.price_limit, v_cap), v_cap);
      -- 0129: THE PLANNER'S PURSE BOUND, ASKED AGAIN NOW: no more of it than her working capital
      -- still covers (public.npc_affordable), so a parcel the purse moved under is cut, not refused.
      v_budget := coalesce(v_budget, public.npc_buy_budget(p_fleet));
      select * into v_aff from public.npc_affordable(st.port_id, ln.good_id, ln.qty, v_budget);
      continue when v_aff.units < 1;
      ln.qty   := v_aff.units;
      v_budget := v_budget - coalesce(v_aff.total, 0);
    end if;
$h$),

-- cmd.standing_route_close_lap: stock_out through the one reading
('cmd.standing_route_close_lap(uuid, timestamptz)', 1,
$h$  select coalesce(round(sum((e.value)::text::numeric * (s.cargo_basis->>e.key)::numeric)), 0)
    into v_out
    from public.ships s cross join lateral jsonb_each(s.cargo) e
   where s.fleet_id = sr.fleet_id and jsonb_typeof(s.cargo_basis->e.key) = 'number'
     and jsonb_typeof(e.value) = 'number';
$h$,
$h$  v_out := public.fleet_stock_at_cost(sr.fleet_id);   -- 0129: the one reading of cargo at cost
$h$);

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0129(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0129 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0129 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0129(fn) from defs_before_0129 order by fn;

-- the probes' cost of a set of BUY lines at a port (pg_temp: dropped with the session).
create or replace function pg_temp.buy_cost_0129(p_port uuid, p_lines jsonb)
returns table (cost numeric, units numeric, n int) language sql
as $$
  select coalesce(sum(q.total), 0), coalesce(sum((x->>'qty')::numeric), 0), count(*)::int
    from jsonb_array_elements(p_lines) x
    join public.goods g on g.code = x->>'good'
    cross join lateral world.quote(p_port, g.id, (x->>'qty')::numeric, 'buy', null, null) q
   where x->>'kind' = 'BUY'
$$;
-- set the probe merchant's purse, through the ledger (the purse reconciles with it).
create or replace function pg_temp.purse_0129(p_player uuid, p_ducats numeric)
returns void language sql
as $$ select public.credit(p_player, 'PROBE_0129',
                           (p_ducats - (select ducats from public.players where id = p_player))::bigint) $$;
-- the same over rendered order lines ('BUY <code> <qty> AT <limit>').
create or replace function pg_temp.rendered_cost_0129(p_port uuid, p_lines text[])
returns table (cost numeric, units numeric, n int) language sql
as $$
  select coalesce(sum(q.total), 0), coalesce(sum(split_part(l, ' ', 3)::numeric), 0), count(*)::int
    from unnest(p_lines) l
    join public.goods g on g.code = split_part(l, ' ', 2)
    cross join lateral world.quote(p_port, g.id, split_part(l, ' ', 3)::numeric, 'buy', null, null) q
   where l like 'BUY %'
$$;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_list     text[];
  v_port     uuid;
  v_good     uuid;
  v_t10      numeric;
  a          record;
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_m        uuid;
  v_mfleet   uuid;
  v_route    uuid;
  v_code     text;
  v_from     uuid;
  v_to       uuid;
  v_rich     jsonb;
  v_poor     jsonb;
  v_none     jsonb;
  c_rich     record;
  c_poor     record;
  v_budget   numeric;
  v_tried    int := 0;
  v_lines    text[];
  r_rich     record;
  r_poor     record;
  v_lap      public.standing_route_laps%rowtype;
  v_notes    text := '';
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0129 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0129 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0129 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0129 where fn = v_fn) or v_def = v_back then
      raise exception '0129 self-assert FAIL: % is not its pre-image plus only 0129''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0129 where fn = v_fn) then
      raise exception '0129 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE AUTHORITY. The planner and the moment of buying both bound by npc_affordable with the
  --     one budget; the lap's stock_out and the budget both read fleet_stock_at_cost; the inline
  --     cargo-at-cost sum lives in fleet_stock_at_cost alone; nothing of it reads is_npc.
  if strpos(pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure),
            'public.npc_affordable(p_from, v_good, v_q, v_budget)') = 0
     or strpos(pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure),
               'public.npc_buy_budget(coalesce(sr.fleet_id,') = 0
     or strpos(pg_get_functiondef('cmd.standing_route_lines(uuid, integer, uuid)'::regprocedure),
               'public.npc_affordable(st.port_id, ln.good_id, ln.qty, v_budget)') = 0
     or strpos(pg_get_functiondef('cmd.standing_route_lines(uuid, integer, uuid)'::regprocedure),
               'public.npc_buy_budget(p_fleet)') = 0
     or strpos(pg_get_functiondef('cmd.standing_route_close_lap(uuid, timestamptz)'::regprocedure),
               'public.fleet_stock_at_cost(sr.fleet_id)') = 0
     or strpos(pg_get_functiondef('public.npc_buy_budget(uuid)'::regprocedure), 'public.fleet_stock_at_cost(f.id)') = 0 then
    raise exception '0129 self-assert FAIL: the planner, the moment of buying or the lap does not compose the one bound / budget / reading';
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc like '%(e.value)::text::numeric * (s.cargo_basis->>e.key)::numeric%';
  if v_list is distinct from array['public.fleet_stock_at_cost'] then
    raise exception '0129 self-assert FAIL: cargo at cost is summed inline in %, not in fleet_stock_at_cost alone', v_list;
  end if;
  if exists (select 1 from pg_proc p where p.proname in ('npc_affordable', 'npc_buy_budget', 'fleet_stock_at_cost')
               and p.pronamespace = 'public'::regnamespace and strpos(p.prosrc, 'is_npc') > 0) then
    raise exception '0129 self-assert FAIL: the bound, the budget or the reading tells a merchant from a player';
  end if;

  -- (c) THE WALL: server-only, no new entry point, no client write.
  if has_function_privilege('authenticated', 'public.npc_affordable(uuid, uuid, numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'public.npc_affordable(uuid, uuid, numeric, numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_buy_budget(uuid)', 'execute')
     or has_function_privilege('anon', 'public.npc_buy_budget(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_stock_at_cost(uuid)', 'execute')
     or has_function_privilege('anon', 'public.fleet_stock_at_cost(uuid)', 'execute') then
    raise exception '0129 self-assert FAIL: the bound, the budget or the reading is client-reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0129)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0129 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;
  if public.wc_num('npc_buy_purse_pct') is null or public.wc_num('npc_buy_purse_pct') <= 0
     or public.wc_num('npc_buy_purse_pct') > 100 then
    raise exception '0129 self-assert FAIL: npc_buy_purse_pct is %, not a share in (0, 100]', public.wc('npc_buy_purse_pct');
  end if;

  -- (d) THE BOUND, on a real quay: ample → as asked; one ducat short of ten → fewer, within; nothing → 0.
  select pg.port_id, pg.good_id into v_port, v_good
    from public.port_goods pg join public.ports pr on pr.id = pg.port_id and pr.code = 'LIS'
    cross join lateral world.quote(pg.port_id, pg.good_id, 10, 'buy', null, null) q
   where pg.stock >= 40 and q.units >= 10 and q.total > 10
   order by pg.good_id limit 1;
  if v_port is null then
    raise exception '0129 self-assert FAIL: no good at LIS quotes ten units to probe the bound with';
  end if;
  select q.total into v_t10 from world.quote(v_port, v_good, 10, 'buy', null, null) q;
  select * into a from public.npc_affordable(v_port, v_good, 10, 1e12);
  if a.units <> 10 or a.total <> v_t10 then
    raise exception '0129 self-assert FAIL: an ample budget did not buy the 10 asked (% for %)', a.units, a.total;
  end if;
  select * into a from public.npc_affordable(v_port, v_good, 10, v_t10 - 1);
  if a.units >= 10 or (a.units >= 1 and a.total > v_t10 - 1) then
    raise exception '0129 self-assert FAIL: a budget one ducat short of ten answered % units for % (budget %)', a.units, a.total, v_t10 - 1;
  end if;
  select * into a from public.npc_affordable(v_port, v_good, 10, 0);
  if a.units <> 0 then
    raise exception '0129 self-assert FAIL: an empty purse could buy % units', a.units;
  end if;

  -- (e) THE PROBES, on a merchant of the probe's own, rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(ra.roadstead_lat, ra.roadstead_lon),
                           jsonb_build_array(rb.roadstead_lat, rb.roadstead_lon))
    into v_leg from public.sea_reaches ra, public.sea_reaches rb
   where ra.port_id = v_lis and rb.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa da Bolsa Curta', 'alt_company', 'Casa do Cofre', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Contado',
      'blurb', 'A probe company founded so its parcels can be seen sized by its purse.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9129,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Contada', 'roster_ord', 9129, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Contada')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select nf.fleet_id, nf.route_id into v_mfleet, v_route from public.npc_fleets nf
     where nf.player_id = v_m order by nf.roster_ord limit 1;
    if v_mfleet is null or v_route is null then
      raise exception '0129 self-assert FAIL: the probe merchant was founded without a fleet and a route';
    end if;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_mfleet;

    -- THE ONE READING AND THE BUDGET: 10 units at 50 aboard are 500 at cost; budget = 90 % of
    -- purse + 500.
    select g.code into v_code from public.goods g where g.id = v_good;
    perform public.fleet_load(v_mfleet, v_code, 10, 50);
    perform pg_temp.purse_0129(v_m, 1000);
    if public.fleet_stock_at_cost(v_mfleet) <> 500
       or public.npc_buy_budget(v_mfleet) <> floor(1500 * public.wc_num('npc_buy_purse_pct') / 100) then
      raise exception '0129 self-assert FAIL: 10 at 50 aboard read % at cost, budget % (purse 1,000)',
        public.fleet_stock_at_cost(v_mfleet), public.npc_buy_budget(v_mfleet);
    end if;
    -- the lap carries it out through the same reading
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900129, now()) returning * into v_lap;
    update public.standing_routes set lap_id = v_lap.id, lap_no = 900129, fleet_id = v_mfleet where id = v_route;
    perform cmd.standing_route_close_lap(v_route, now());
    select * into v_lap from public.standing_route_laps where id = v_lap.id;
    if v_lap.stock_out <> 500 then
      raise exception '0129 self-assert FAIL: the lap carried out % at cost, not the 500 aboard', v_lap.stock_out;
    end if;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_mfleet;
    -- the planner is also run before the switch assigns a route its fleet (npc_traders_switch plans
    -- every route at once): unassigned, she is budgeted by the fleet the roster keeps for the route.
    update public.standing_routes set lap_id = null, fleet_id = null where id = v_route;

    -- THE PLANNER: over real merchant legs, priced for HER (her purse, her caps; her route not yet
    -- assigned its fleet), find one that keeps a parcel when she is rich; then with a third of that parcel's cost in her purse, the
    -- leg's BUYs cost no more than her budget; with nothing, it keeps no BUY.
    for v_from, v_to in
      select s0.port_id, s1.port_id
        from public.npc_fleets nf
        join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
        join public.standing_route_stops s1 on s1.route_id = nf.route_id and s1.ord = 1
       where nf.player_id <> v_m
       order by nf.roster_ord, nf.fleet_id limit 40 loop   -- reads only: the planner locks nothing
      v_tried := v_tried + 1;
      perform pg_temp.purse_0129(v_m, 100000000);
      v_rich := public.npc_leg_lines(v_route, v_from, v_to, 400, 0, 6);
      select * into c_rich from pg_temp.buy_cost_0129(v_from, v_rich->'lines');
      continue when c_rich.n = 0 or c_rich.cost < 30;
      perform pg_temp.purse_0129(v_m, floor(c_rich.cost / 3));
      v_budget := public.npc_buy_budget(v_mfleet);
      v_poor := public.npc_leg_lines(v_route, v_from, v_to, 400, 0, 6);
      select * into c_poor from pg_temp.buy_cost_0129(v_from, v_poor->'lines');
      if c_poor.cost > v_budget then
        raise exception '0129 self-assert FAIL: with % in her purse (budget %) the planner kept parcels costing % (rich: % for %)',
          floor(c_rich.cost / 3), v_budget, c_poor.cost, c_rich.n, c_rich.cost;
      end if;
      perform pg_temp.purse_0129(v_m, 0);
      v_none := public.npc_leg_lines(v_route, v_from, v_to, 400, 0, 6);
      if (select n from pg_temp.buy_cost_0129(v_from, v_none->'lines')) <> 0
         or coalesce((v_none->>'any')::boolean, false) then
        raise exception '0129 self-assert FAIL: an empty purse still planned a parcel: %', v_none->'lines';
      end if;

      -- THE MOMENT OF BUYING: her loop is this leg, its BUYs the rich plan's; rendered rich they are
      -- as planned, rendered poor they cost no more than her budget, rendered empty there are none.
      update public.standing_route_stops set port_id = v_from where route_id = v_route and ord = 0;
      update public.standing_route_stops set port_id = v_to where route_id = v_route and ord = 1;
      update public.voyages set status = 'ARRIVED' where fleet_id = v_mfleet and status = 'SAILING';
      update public.fleets set status = 'DOCKED', port_id = v_from, lat = null, lon = null where id = v_mfleet;
      delete from public.standing_route_lines where route_id = v_route and stop_ord = 0 and kind = 'BUY';
      insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit)
      select v_route, 0, 900 + k, 'BUY', g.id, (x->>'qty')::numeric, (x->>'price_limit')::numeric, false
        from jsonb_array_elements(v_rich->'lines') with ordinality t(x, k)
        join public.goods g on g.code = x->>'good'
       where x->>'kind' = 'BUY';
      perform pg_temp.purse_0129(v_m, 100000000);
      v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
      select * into r_rich from pg_temp.rendered_cost_0129(v_from, v_lines);
      if r_rich.n <> c_rich.n or r_rich.units <> c_rich.units then
        raise exception '0129 self-assert FAIL: rich, the moment of buying cut the plan (% lines / % units, planned % / %): %',
          r_rich.n, r_rich.units, c_rich.n, c_rich.units, v_lines;
      end if;
      perform pg_temp.purse_0129(v_m, floor(c_rich.cost / 3));
      v_budget := public.npc_buy_budget(v_mfleet);
      v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
      select * into r_poor from pg_temp.rendered_cost_0129(v_from, v_lines);
      if r_poor.cost > v_budget or r_poor.units >= r_rich.units then
        raise exception '0129 self-assert FAIL: poor (budget %), the moment of buying rendered % units costing %: %',
          v_budget, r_poor.units, r_poor.cost, v_lines;
      end if;
      perform pg_temp.purse_0129(v_m, 0);
      v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
      if exists (select 1 from unnest(v_lines) l where l like 'BUY %') then
        raise exception '0129 self-assert FAIL: an empty purse still rendered a BUY: %', v_lines;
      end if;
      v_notes := format('leg %s of %s tried: rich %s BUY line(s), %s units for %s d.; with %s d. the plan cost %s '
                        '(budget %s) and the quay lines %s units for %s; with 0 d. none. ',
                        v_tried, 40, c_rich.n, c_rich.units, c_rich.cost, floor(c_rich.cost / 3), c_poor.cost,
                        v_budget, r_poor.units, r_poor.cost);
      exit;
    end loop;
    if v_notes = '' then
      raise exception '0129 self-assert FAIL: no merchant leg of % tried kept a parcel to probe the planner with', v_tried;
    end if;

    raise exception 'ROLLBACK_0129';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0129' then raise; end if;
  end;
  if exists (select 1 from public.npc_houses where roster_ord = 9129)
     or exists (select 1 from public.standing_route_laps where lap_no = 900129) then
    raise exception '0129 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0129 self-assert ok: A MERCHANT BUYS WHAT HER PURSE CAN PAY. npc_leg_lines, standing_route_lines and standing_route_close_lap reverse to their pre-images hunk by hunk, ACLs unmoved; the planner and the moment of buying bound every parcel by public.npc_affordable within public.npc_buy_budget (purse + cargo at cost, x npc_buy_purse_pct %%); cargo at cost is summed in fleet_stock_at_cost alone (the lap and the budget read it); nothing reads is_npc; server-only, no new entry point, no client write. Bound: ample buys 10 for %, one ducat short buys fewer within, empty buys 0. Probes: 10 at 50 aboard read 500 and carried out as stock_out 500; %Rolled back.',
    v_t10, v_notes;
end $$;
