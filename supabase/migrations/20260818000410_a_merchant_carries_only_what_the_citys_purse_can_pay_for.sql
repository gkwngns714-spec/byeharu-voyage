-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0410 - A MERCHANT CARRIES ONLY WHAT THE CITY'S PURSE CAN PAY FOR  (the leg planner sizes a parcel by the sink's purse, as the sale door will)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14 07:30 to 08:30 UTC, head 0407; docs/dev-log/2026-11-14-under-water.md):
--   About 30 % of the merchant houses that close a lap in an hour end that hour under water, before and after 0406. 0406 could not move it: the
--   loss is not in the plan's net. Of the losing laps of that hour (4.52 M d.), 4.17 M (92 %) is SALES BELOW COST: the cut-loss (0142) letting go,
--   at about 22 % under what she paid, of a parcel her at-profit SELL was refused for at the harbour it was bought for. 26 % of the parcels
--   bought (1,021 of 3,907 in the kept laps) are not sold at their first arrival.
--   ONE CAUSE OF THOSE REFUSALS IS IN THE PLANNER. The sale door (cmd.do_sell, 0122) sells a city only what its purse can pay: the lot shrinks
--   to what public.treasury_balance covers, and a purse that covers none refuses E_CITY_BROKE; a purse under its reserve also bids less
--   (public.city_bid_factor), which is an E_PRICE_LIMIT to her. public.npc_leg_lines sizes a parcel by the sink's price, her daily cap, her
--   purse and her hold, and NEVER BY THE SINK'S PURSE. Read at 08:35: of the 918 BUY lines standing on sailing merchants' routes, 232 (25 %;
--   32.9 M of 71.9 M d. at their limits) are bound for a city whose purse is smaller than the parcel's cost (Luanda: 2,170 d. in its purse, 13
--   lines worth 2.96 M bound for it). Where the sink's purse is under a quarter of the parcel's cost, 76 % of parcels are not sold whole on
--   arriving; under the cost 64 %; above five times the cost 30 %. 62 % of the loss on sales below cost (3.1 M of 5.0 M in the kept laps) is on
--   the 22 % of parcels bought for such a city.
--
-- WHAT THIS FILE DOES (three bodies re-cut by six hunks, one column, one table):
--   1. THE PLANNER (public.npc_leg_lines, four hunks).
--   public.npc_leg_lines reads the sink's purse once a leg (public.treasury_balance(p_to), THE live balance the door reads) and sizes every
--   parcel so that what the purse pays of its sale (round(total / haul), haul 1 while the economy is closed: the door's own line) is within
--   what the purse has left after the parcels already kept on this leg. A parcel that does not fit is shrunk until it does; one that cannot is
--   not kept, and the ranking's next good is tried. The keep test (a parcel pays 5 % on its outlay) then judges the parcel at the size the city
--   can pay for, and the loop's net (public.npc_plan, with 0406's fees) follows: a loop whose city cannot pay is no longer "a loop that pays".
--   While the purses are dark the purse is not read and every plan is what it was. With every purse rich the plan is the pre-image's (asserted).
--   A parcel that fits spends no extra quote: the size quote already taken (q_size) bounds its sale.
--   2. THE LAP'S BOOK COUNTS THE DOCK FEE (0406 left it out and said so). standing_route_laps.fees (new, 0): public.port_call, THE one writer
--      of a port call, adds the fee it charges (paid or owed) to the open lap of the fleet's route (one hunk), and
--      cmd.standing_route_close_lap takes the lap's fees from its net (one hunk). Everything that reads a lap's net follows: the Stats' merchant
--      profit and losing count, a route's earnings, the month's book, "stop after losing laps", the reputation of a lap closed at a gain. For a
--      player's route too: her lap's net is now after the dock fees she paid, which is what her purse saw. Laps already closed are not rewritten.
--   3. THE ONE LIST OF WHAT A LAP COSTS: public.lap_costs, a row per ledger kind a house's purse can be charged by: whether a lap of a route
--      pays it, the column of the lap's book that keeps it, and the function the planner prices it by (or why it does not). Proof 105 runs real
--      laps and fails on a charge that is not in the list, on a listed column the book's net does not take, and on a listed price the planner
--      does not call: a cost added later must be entered here, and the entry says in the open whether the planner counts it.
--
-- NOT DONE HERE (said, for the owner): two merchants bound for the same city each see its whole purse (the purse is not reserved between
--   plans); the price still walks between the plan and the arrival (drift_sigma 0.03 a 60-second slot: a mean 7 % in ten minutes with no trade),
--   which is the other part of the refusals and is the owner's knob; the cut-loss itself is untouched.
-- LOCKS: ALTER TABLE standing_route_laps ADD COLUMN (a constant default: no rewrite; ACCESS EXCLUSIVE for an instant, lock_timeout 5 s),
--   CREATE TABLE, CREATE OR REPLACE FUNCTION x3 by hunks. TIME: the cut is milliseconds; the probe plans ONE merchant three times in
--   sub-transactions rolled back (0.3 to 1.5 s a plan on prod), each after one UPDATE of the purses' rows that is rolled back with it, and
--   makes one port call and closes one empty lap for her, rolled back: expected under 10 s.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/under-water/rollback-0410.sql, a draft: the six hunks reversed (the column and the list stay: nothing reads them then).
-- NOT DONE HERE too: no screen shows the new column; the invest rule and the gift are untouched.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0410 (built on head 0408; 0409, the pirates' file, lands first and cuts none of these three bodies; this file touches nothing of the gift).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
                                 'public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)',
                                 'cmd.standing_route_close_lap(uuid,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_fleet     uuid;
  v_route     uuid;
  v_old       jsonb;
  v_new       jsonb;
  v_poor      jsonb;
  v_fee       jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if position('0410' in pg_get_functiondef('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'::regprocedure)) > 0 then
    raise exception '0410 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.treasury_balance(uuid)') is null or to_regprocedure('public.cargo_haul(uuid,uuid)') is null
     or to_regprocedure('public.city_treasury_on()') is null or to_regprocedure('public.economy_closed()') is null then
    raise exception '0410 refuses: the city''s purse (0122, 0174, 0228) is not in this world';
  end if;
  if exists (select 1 from pg_proc p where p.oid in ('public.treasury_balance(uuid)'::regprocedure, 'public.cargo_haul(uuid,uuid)'::regprocedure,
                                                     'public.city_treasury_on()'::regprocedure, 'public.economy_closed()'::regprocedure)
                and p.provolatile not in ('s', 'i')) then
    raise exception '0410 refuses: a reader of the city''s purse is not STABLE';
  end if;

  -- ── 0b. THE COLUMN AND THE LIST ──
  alter table public.standing_route_laps add column fees bigint not null default 0;
  comment on column public.standing_route_laps.fees is
    '0410: the dock fees charged (paid or owed) at the harbours this lap made. Written by public.port_call alone; cmd.standing_route_close_lap takes it from net.';
  create table public.lap_costs (
    kind     text primary key,
    of_a_lap boolean not null,
    book     text,
    planned  text,
    note     text not null check (note <> '')
  );
  comment on table public.lap_costs is
    '0410: THE one list of what a lap costs. A row per ledger kind a house''s purse can be charged by: of_a_lap (a lap of a route pays it), book (the standing_route_laps column that keeps it), planned (the function public.npc_plan or public.npc_leg_lines prices it by; null = the planner does not count it, and note says why). Proof 105 holds the planner and the lap''s book to it.';
  alter table public.lap_costs enable row level security;
  revoke all on table public.lap_costs from public, anon, authenticated;
  insert into public.lap_costs (kind, of_a_lap, book, planned, note) values
    ('BUY',            true,  'bought',    'world.quote_priced',       'the parcels she buys; the leg planner prices each at the source quay'),
    ('TAX',            true,  'taxes',     'public.profit_tax',        'the profit tax of a sale, paid to the city of the sale'),
    ('WAGES',          true,  'wages',     'public.wages_from_profit', 'the wages her sea-days owe, paid out of a sale''s profit'),
    ('PROVISION',      true,  'supplies',  'public.stores_cost',       'the water and food the loop eats'),
    ('PORT_FEE',       true,  'fees',      'public.port_fee',          'the dock fee of every harbour she makes (0237); planned since 0406, in the book since 0410'),
    ('REPAIR',         true,  'repairs',   null,                       'NOT PLANNED: a repair rides on wear, not on the loop''s length (0142)'),
    ('INSURANCE',      true,  'insurance', null,                       'NOT PLANNED: the premium of an insured cargo; the book keeps it less what the insurance paid back'),
    ('HIRE',           true,  null,        null,                       'NOT PLANNED AND NOT IN THE BOOK: crew hired when she is short'),
    ('SELL',           false, 'sold',      'world.quote_priced',       'what her sales bring: the income the costs are set against'),
    ('INSURANCE_PAID', false, 'insurance', null,                       'the insurance paying back: income, netted in the book''s insurance'),
    ('DONATION',       false, null,        null,                       'the invest rule''s gift to a city: of the house, not of a lap'),
    ('SHARE',          false, null,        null,                       'a share bought in a city: of the house, not of a lap'),
    ('DIVIDEND',       false, null,        null,                       'a share''s dividend: income of the house'),
    ('CAPITAL_GIFT',   false, null,        null,                       'the capital gift to a broke house: income of the house'),
    ('PREMIUM',        false, null,        null,                       'an insurer''s premium received: income of the house'),
    ('OFFICER_WAGE',   false, null,        null,                       'an officer''s wage: of the house by the calendar, not of a lap (found by proof 105''s soak; none charged to a merchant on prod in six hours, 2026-11-14)'),
    ('TUITION',        false, null,        null,                       'a skill''s tuition: of the house, not of a lap (found by proof 105''s soak; none charged to a merchant on prod in six hours, 2026-11-14)');

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0410 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0410
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE PROBE'S HAND (pg_temp, gone at commit): ONE merchant planned alone at her lap start by the live planner, the economy closed and the
  --      purses lit, every city's rolled purse set to p_purse. It WRITES; every caller rolls it back. Answers her plan's receipt, what the plan
  --      wrote, and `over`: the stops whose BUY lines' sales the next harbour's purse cannot pay (the door's own measure).
  execute $f$
create function pg_temp.plan_0410(p_fleet uuid, p_route uuid, p_purse bigint) returns jsonb language plpgsql as $b$
declare
  v_r jsonb;
  v_n int;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
  update public.port_treasury set ducats = p_purse;
  update public.standing_routes set fleet_id = p_fleet, lap_id = null, paused_reason = null, hold_until = null where id = p_route;
  v_r := public.npc_plan(now(), p_route);
  select count(*) into v_n from public.standing_route_stops s where s.route_id = p_route;
  return jsonb_build_object(
    'receipt', jsonb_build_object('planned', v_r->'planned', 'waiting', v_r->'waiting', 'ballast', v_r->'ballast', 'failed', v_r->'failed'),
    'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = p_route),
    'wrote', (select md5(coalesce(string_agg(s.ord || ':' || s.port_id || ':' || s.repair || ':' ||
                       coalesce((select string_agg(l.ord || l.kind || coalesce(l.good_id::text, '') || coalesce(l.qty::text, '') || coalesce(l.price_limit::text, '') || l.at_profit, ','
                                                   order by l.ord)
                                   from public.standing_route_lines l where l.route_id = s.route_id and l.stop_ord = s.ord), ''), '|' order by s.ord), ''))
                from public.standing_route_stops s where s.route_id = p_route),
    'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
    'over', (select count(*) from (
               select s2.port_id,
                      sum(round((select q.total from world.quote(s2.port_id, l.good_id, l.qty, 'sell', null, null) q)
                                / case when public.economy_closed() then 1 else public.cargo_haul(s2.port_id, l.good_id) end)) as due
                 from public.standing_route_lines l
                 join public.standing_route_stops s2 on s2.route_id = l.route_id and s2.ord = (l.stop_ord + 1) % v_n
                where l.route_id = p_route and l.kind = 'BUY'
                group by l.stop_ord, s2.port_id) z
              where z.due > greatest(public.treasury_balance(z.port_id), 0)));
end $b$
  $f$;
  execute $f$
create function pg_temp.fee_0410(p_fleet uuid, p_route uuid) returns jsonb language plpgsql as $b$
declare
  v_player uuid;
  v_port   uuid;
  v_no     int;
  v_lap    uuid;
  v_in     bigint;
  v_call   jsonb;
  v_kept   bigint;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
  select f.player_id, f.port_id into v_player, v_port from public.fleets f where f.id = p_fleet;
  select coalesce(max(x.lap_no), 0) + 1 into v_no from public.standing_route_laps x where x.route_id = p_route;
  select coalesce((select x.stock_out from public.standing_route_laps x where x.route_id = p_route and x.closed_at is not null order by x.lap_no desc limit 1), 0) into v_in;
  insert into public.standing_route_laps (route_id, lap_no, started_at) values (p_route, v_no, now()) returning id into v_lap;
  update public.standing_routes set fleet_id = p_fleet, lap_id = v_lap, lap_no = v_no, paused_reason = null, hold_until = null where id = p_route;
  v_call := public.port_call(p_fleet, v_player, v_port, now(), now(), null);
  select x.fees into v_kept from public.standing_route_laps x where x.id = v_lap;
  perform cmd.standing_route_close_lap(p_route, now());
  return jsonb_build_object('fee', v_call->'fee', 'kept', v_kept,
                            'net', (select x.net from public.standing_route_laps x where x.id = v_lap),
                            'expect', public.fleet_stock_at_cost(p_fleet) - v_in - v_kept);
end $b$
  $f$;
  -- the probe merchant: in port at her loop's first stop, nothing aboard, nothing queued, no lap open, not of the pirates
  select nf.fleet_id, nf.route_id into v_fleet, v_route
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id and sr.lap_id is null and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id)
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where nf.roster_ord <= public.wc_int('npc_fleet_max')
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
   order by (sr.paused_reason = 'laid_up') desc nulls last, nf.roster_ord
   limit 1;
  -- a harbour with no purse row pays nothing while the purses are lit: the "every purse rich" arm below cannot be staged for it
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.port_treasury t where t.port_id = p.id)) then
    v_fleet := null;
  end if;
  -- BEFORE THE CUT: her plan by the pre-image, every purse rich
  if v_fleet is not null then
    begin
      v_old := pg_temp.plan_0410(v_fleet, v_route, 1000000000000);
      raise exception sqlstate 'BV410';
    exception when sqlstate 'BV410' then null;
    end;
  end if;

  -- ── 3. THE HUNKS ──
  create temp table hunk_0410 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0410 values
  (1, c_cut[1],
$h$  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
$h$,
$h$  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
  v_room    numeric;        -- 0410: what the sink's purse can still pay for this leg's parcels (null while the purses are dark)
  v_haul    numeric;        -- 0410: the haul the purse's part of a sale is cut by (the door's: 1 while the economy is closed)
  v_due     numeric;        -- 0410: what the sink's purse pays of this parcel's sale
  v_shrunk  int;            -- 0410: the times this parcel was shrunk to fit
$h$),
  (2, c_cut[1],
$h$  select * into k_to   from world.quote_terms(p_to, null, null);
$h$,
$h$  select * into k_to   from world.quote_terms(p_to, null, null);
  -- 0410: THE SINK'S PURSE, read once a leg: THE live balance the sale door reads (public.treasury_balance, cmd.do_sell 0122). The door sells
  -- a city only what its purse can pay and refuses E_CITY_BROKE past it; a parcel sized past it was bought, refused there and let go at a loss.
  if public.city_treasury_on() then
    v_room := greatest(public.treasury_balance(p_to), 0);
  end if;
$h$),
  (3, c_cut[1],
$h$      continue when v_q < 1;
      select * into q_buy from world.quote_priced(p_from, v_good, v_q, 'buy', null, null,
$h$,
$h$      continue when v_q < 1;
      -- 0410: AND NO MORE THAN THE SINK'S PURSE CAN PAY FOR, by the door's own measure: the purse pays round(total / haul) of a sale (0174),
      -- the whole total while the economy is closed (0233). q_size is the sale of at least v_q units, so a parcel it shows to fit spends no
      -- quote; one that does not is shrunk by what it is over (the price rises as the lot shrinks, so again, six times at most) and is
      -- not kept when it still does not fit. What the purse has left falls by every parcel kept on this leg (below).
      if v_room is not null then
        continue when v_room < 1;
        v_haul   := case when public.economy_closed() then 1 else public.cargo_haul(p_to, v_good) end;
        v_due    := round(q_size.total / v_haul);
        v_shrunk := 0;
        while v_due > v_room and v_q >= 1 and v_shrunk < 6 loop
          select * into q_sell from world.quote_priced(p_to, v_good, v_q, 'sell', null, null,
                                                       k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);
          v_due := round(q_sell.total / v_haul);
          exit when v_due <= v_room;
          v_q := least(v_q - 1, floor(v_q * v_room / v_due));
          v_shrunk := v_shrunk + 1;
        end loop;
        continue when v_q < 1 or v_due > v_room;
      end if;
      select * into q_buy from world.quote_priced(p_from, v_good, v_q, 'buy', null, null,
$h$),
  (4, c_cut[1],
$h$      v_cost   := v_cost + q_buy.total;     -- 0406
$h$,
$h$      v_cost   := v_cost + q_buy.total;     -- 0406
      if v_room is not null then   -- 0410: the purse pays this parcel first
        v_room := v_room - round(q_sell.total / v_haul);
      end if;
$h$),
  (5, c_cut[2],
$h$  if v_fee > 0 then
    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;
$h$,
$h$  if v_fee > 0 then
    -- 0410: THE LAP'S BOOK KEEPS THE FEE (standing_route_laps.fees; written here and nowhere else): the open lap of this fleet's route, when
    -- she sails one. The fee charged, paid or owed. A lap closes after its last arrival's call, so every call of the lap is in it.
    update public.standing_route_laps x set fees = x.fees + v_fee
     where x.id = (select sr.lap_id from public.standing_routes sr where sr.fleet_id = p_fleet and sr.lap_id is not null);
    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;
$h$),
  (6, c_cut[3],
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure,
$h$,
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure
               - l.fees,   -- 0410: the dock fees of the lap's calls (public.port_call wrote them; public.lap_costs is the list)
$h$);
  for h in select * from hunk_0410 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0410 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0410 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0410 p where p.fn = h.fn) then
      raise exception '0410 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0410 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0410 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0410 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0410 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE PROBE, AFTER THE CUT ──
  if v_fleet is null then
    raise notice '0410 self-assert: no merchant lies in port at her first stop with an empty hold in this world (or a city keeps no purse row); the probe is proof 104''s';
  else
    -- (a) every purse rich: her plan is the pre-image's, row for row
    begin
      v_new := pg_temp.plan_0410(v_fleet, v_route, 1000000000000);
      raise exception sqlstate 'BV410';
    exception when sqlstate 'BV410' then null;
    end;
    if v_new is distinct from v_old then
      raise exception '0410 self-assert FAIL: with every purse rich her plan is not the pre-image''s: before %, after %', v_old, v_new;
    end if;
    -- (b) every rolled purse at nothing: she is planned, and no BUY she wrote is past what the harbour it is bound for can pay
    begin
      v_poor := pg_temp.plan_0410(v_fleet, v_route, 0);
      raise exception sqlstate 'BV410';
    exception when sqlstate 'BV410' then null;
    end;
    if (v_poor->'receipt'->>'planned')::int <> 1 or (v_poor->'receipt'->>'failed')::int <> 0 then
      raise exception '0410 self-assert FAIL: with every purse at nothing her plan failed: %', v_poor;
    end if;
    if (v_poor->>'over')::int <> 0 then
      raise exception '0410 self-assert FAIL: with every purse at nothing she wrote a BUY its harbour cannot pay for: %', v_poor;
    end if;
  end if;
  -- (c) THE BOOK: one port call of hers on an open lap with nothing traded, then the lap closed: the lap keeps the fee the call charged and its
  --     net is less by it (rolled back: the lap, the fee, the event)
  if v_fleet is not null then
    begin
      v_fee := pg_temp.fee_0410(v_fleet, v_route);
      raise exception sqlstate 'BV410';
    exception when sqlstate 'BV410' then null;
    end;
    if (v_fee->>'kept')::numeric is distinct from coalesce((v_fee->>'fee')::numeric, 0) or (v_fee->>'net')::numeric is distinct from (v_fee->>'expect')::numeric then
      raise exception '0410 self-assert FAIL: the lap''s book does not keep the dock fee of her call: %', v_fee;
    end if;
  end if;
  if exists (select 1 from public.lap_costs c where c.book is not null
                and not exists (select 1 from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'standing_route_laps' and k.column_name = c.book)) then
    raise exception '0410 self-assert FAIL: the list names a column the lap''s book does not have';
  end if;
  if (select count(*) from unnest(c_cut) f where position('0410' in pg_get_functiondef(f::regprocedure)) > 0) <> 3 then
    raise exception '0410 self-assert FAIL: the three bodies are not this file''s';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0410 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0410 self-assert ok: A MERCHANT CARRIES ONLY WHAT THE CITY''S PURSE CAN PAY FOR. Six hunks over three bodies, each once and reversing; grants and volatility unmoved; no other function moved; the lap''s book has its fees and public.lap_costs % rows. %; % ms.',
    (select count(*) from public.lap_costs),
    case when v_fleet is null then 'No probe merchant in this world'
         else 'One merchant planned by the live planner: every purse rich, her plan is the pre-image''s (' || (v_new->'receipt')::text || ', ' || (v_new->>'buys') || ' BUY lines); every rolled purse at nothing, '
              || (v_poor->>'buys') || ' BUY lines, none past its harbour''s purse (' || (v_poor->'receipt')::text || '); one port call on an open lap charged ' || coalesce(v_fee->>'fee', '0') || ' and the lap kept ' || (v_fee->>'kept') || ', its net ' || (v_fee->>'net') end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
