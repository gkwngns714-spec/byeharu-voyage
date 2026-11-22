-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0474 - A FAIR GIFT AND ONE PROFIT  (the gift and the Week: dark behind the owner's switch fair_gift_enabled, false; one trip's profit
--        is one number on the card, the sheet and the arrival: a display fix, not switched)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE PLAY-TEST: docs/design/playable-2026-11-22.md section 6 (third play-test), findings 2, 28 and 1.
--
-- FINDING 2, WHY: at minute 22 a company with 53,655 ordered her second hull (48,557, 0465's yard order) and kept 5,098; on the next
--   arrival "Gift from Lisbon: 40,000". The capital's gift (0234 / 0241, public.capital_gift_roster) pays a company whose purse AND worth
--   are under merchant_broke_pct x her starting money (0.2 x 40,000 = 8,000); her worth (public.player_worth: purse + cargo at cost - debts)
--   did not count the hull she had just paid for, so the order made her "broke" and the 52,000 floor (0472) cost her about 12,000.
-- FINDING 2, WHAT (lit): public.player_worth (the gift's own worth, read by nothing else) adds what she PAID for every hull ON ORDER
--   (public.hull_orders, launched_at null) and for every ordered hull LAUNCHED within the last gift_cooldown_hours that is still hers (the
--   ship exists and is hers): so the order does not make her broke, and the launch does not make her broke the minute after. The starting
--   Barca and a hull built from materials are not counted (decided by default: counting every hull would end the gift for every broke
--   company, which all own their first ship). Narrow on purpose: the second-hull price and the working purse it leaves are the owner's
--   (section 6 row 2's "deposit or refuse under 20,000"), not decided here.
-- FINDING 28, WHY: Rank Week (world.houses_week, 0467; your row live since 0473) sums every "earning" ledger row (public.ledger_is_earning),
--   so the gift (+40,000) and the hull order (-48,557) were "profit": "Profit 14,414" for about 23,000 of trading.
-- FINDING 28, WHAT (lit): THE ONE DEFINITION of trade profit, public.ledger_is_trade(kind): BUY, SELL, TAX (the profit tax), WAGES,
--   PORT_FEE (the dock fee), PROVISION (a trip's stores), REQUEST_FILL (a request's pay). The history job keeps, beside a day's earned and
--   lost, its earning rows that are NOT trade (history_company_day.not_trade, new, written by public.history_ledger_add dark or lit: the
--   same upsert, no row more). Lit, the settled week (public.houses_week_settle) is sum(earned - lost - not_trade) and YOUR live figure
--   (world.houses_week) is the same days so counted plus your ledger since the mark filtered by public.ledger_is_trade: one figure, two
--   paths, one rule. Backfill (once, here): this week's and last week's days already settled get the gifts (public.capital_gifts) and the
--   hull orders (public.hull_orders) of those days in not_trade; other non-trade rows of days settled before this file (insurance, a
--   repair, a hire...) stay counted until the week turns (stated, not hidden).
-- FINDING 1, WHY: one trip, three profits. Iron Lisbon to Setubal: card +2,987, Buy & sell sheet +2,918, arrival card "Profit +3,100", purse
--   +2,918. (a) THE CARD: world.best_sales hands world.board_sell legs walked with nothing (0459 `only` []), and board_sell walks a bought
--   good's rows again (`walks`) for their time, wages and stores but kept the unwalked legs' t_pre / t_post (null), so the card's dock fee
--   was 0: 2,987 = 3,100 - tax 105 - wages 8, the 69 fee left out. (b) THE ARRIVAL: ArrivalCard.tsx prints the SOLD event's `profit`
--   (0081: the sale's total less what the goods cost), before the profit tax, the wages and the dock fee.
-- FINDING 1, WHAT (not switched: no coin moves differently, a figure is told right): (a) world.board_sell's `walks` carries the walked
--   t_pre / t_post and a walked row uses them, so the card's dock fee is the sheet's (the card = the sheet's row for its units, to the
--   coin, as 0351 / 0472 promised). (b) THE ONE SERVER AUTHORITY for what a trip left is the sale: cmd.do_sell's SOLD event carries
--   `wages` (what this sale pays the crew: public.wages_due, new, THE rule public.pay_wages now pays by, so the two cannot differ), `dock_fee`
--   (the fee charged when she made this harbour, kept on the fleet by public.port_call in fleets.call_fee, new, for a company only, and
--   taken by her first sale there) and `trip_net` = profit - tax - wages - dock_fee: what her purse moved for the trip, the sheet's
--   figure. The arrival card prints `trip_net` (client, same PR). Supplies are not in `trip_net` (bought at the sail, on another day): the
--   sheet shows them on their own row; on a trip whose casks were already full (the first hour's one-minute trips) the two agree to the coin.
--
-- THE HUNKS (each once in the live body, and reversing):
--   public.player_worth          H1 the hulls she paid for (lit).
--   world.board_sell             H1 `walks` carries t_pre / t_post; H2 a walked row uses them.
--   public.pay_wages             H1 the pay is public.wages_due's.
--   cmd.do_sell                  H1 declare; H2 the wages and the dock fee read before the SOLD event; H3 the event's three keys.
--   public.port_call             H1 the fee kept on a company's fleet.
--   public.history_ledger_add    H1 the column; H2 not_trade summed; H3 not_trade added on conflict.
--   public.houses_week_settle    H1 declare; H2 the week less not_trade (lit).
--   world.houses_week            H1 declare; H2 your settled days less not_trade (lit); H3 your ledger since the mark, trade only (lit).
-- NEW: public.ledger_is_trade(text) (immutable), public.wages_due(uuid,bigint) (stable, server only), fleets.call_fee and
--   history_company_day.not_trade (nullable, no default: catalog only), the knob fair_gift_enabled (false).
-- NOT CHANGED: the gift's line, cooldown and weekly cap; who is on the roster otherwise; a merchant's worth (public.npc_worth); the price
--   of a hull; the sale, its tax, its wages and its debts (the same coin moves: wages_due is pay_wages' own expression, moved); the Buy &
--   sell sheet (world.good_board's rows are unchanged: they were walked with their units already); the company graph (earned and lost).
-- ROWS: none new. A company's arrival writes fleets.call_fee (one row update, merged with nothing: about one an arrival of a company; a
--   merchant's never), her first sale after it clears it (one update). The history upsert writes one column more. Backfill: the days of two
--   weeks with a gift or a hull order (hundreds of rows, once).
--   -- budget: none (no table, no job, no index, no cron, no fillfactor or autovacuum; two nullable columns with no default).
--   -- retention: none new (call_fee lives on its fleet; not_trade on its day row, kept as the day row is).
-- LOCKS: ALTER TABLE fleets / history_company_day ADD COLUMN (catalog only, a moment's exclusive lock each: lock_timeout 5 s, the file fails
--   rather than wait); the backfill UPDATE; CREATE OR REPLACE x8 by hunks; CREATE x2. TIME: a few seconds. BUDGET: statement_timeout 45 s;
--   fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, fair_gift_enabled false (the gift's worth and the Week as before 0474 at once). Finding 1 has no
--   switch: a new migration reversing its six hunks (OLD texts below verbatim). Full: that, the other hunks, dropping the two columns and
--   the two functions, deleting the knob.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; no other world_config row moved; the switch false. THE PROBE (rolled back): a fresh company with a hull on order and 5,000
--   coins: DARK her worth and her Week are their pre-images' (copies in pg_temp); LIT her worth counts the order, her Week counts a sale and
--   not a gift or the order; public.wages_due is what public.pay_wages pays. Proof 177 plays the doors (the gift, the card, the sale, the Week).
-- VERSION: 0474 = prod head 0473 + 1.
-- news: none (dark: the gift and the Week change only when the owner lights fair_gift_enabled; the card and the arrival tell the same profit)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.player_worth(uuid)', 'world.board_sell(uuid,uuid,jsonb)', 'public.pay_wages(uuid,uuid,bigint,uuid)',
                                    'cmd.do_sell(uuid,jsonb)', 'public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)',
                                    'public.history_ledger_add(timestamp with time zone,timestamp with time zone)',
                                    'public.houses_week_settle(timestamp with time zone)', 'world.houses_week()'];
  c_uid    constant uuid := '00000000-0474-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_pl        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_week      date := public.history_bucket((now() at time zone 'UTC')::date, 'week');
  v_mark      timestamptz;
  v_back      int;
  v_w0        bigint;
  v_w1        bigint;
  v_r0        jsonb;
  v_r1        jsonb;
  v_due       bigint;
  v_paid      bigint;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config c where c.key = 'fair_gift_enabled') or to_regprocedure('public.ledger_is_trade(text)') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'fleets' and column_name = 'call_fee') then
    raise exception '0474 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or to_regclass('public.hull_orders') is null or to_regclass('public.capital_gifts') is null or to_regclass('public.houses_week') is null
     or to_regclass('public.history_company_day') is null or to_regclass('public.history_mark') is null
     or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null
     or public.wc('gift_cooldown_hours') is null or public.wc('houses_board_enabled') is null then
    raise exception '0474 refuses: the gift (0234/0241), the yard order (0465), the houses'' board (0467/0473) or the history (0316) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0474 (fn text primary key, def text) on commit drop;
  insert into pre_0474 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SWITCH, THE COLUMNS, THE TWO FUNCTIONS ──
  insert into public.world_config (key, value, description) values
    ('fair_gift_enabled', 'false'::jsonb,
     '0474: A FAIR GIFT AND A TRADE WEEK (the owner''s switch). true: the capital''s gift reads a company''s worth with what she paid for a hull on order, or launched within gift_cooldown_hours and still hers (public.player_worth), so ordering a hull does not make her broke; Rank Week counts trade profit only (public.ledger_is_trade: buys, sales, the profit tax, wages, dock fees, stores, a request''s pay), not a gift or a hull order. false: both as before 0474.');

  alter table public.fleets add column call_fee bigint;
  comment on column public.fleets.call_fee is
    '0474: the dock fee charged when this company''s fleet made the harbour she lies in (public.port_call), until her first sale there takes it into that sale''s SOLD event (`dock_fee`, `trip_net`). Null: none, or a merchant''s fleet (never written).';
  alter table public.history_company_day add column not_trade bigint;
  comment on column public.history_company_day.not_trade is
    '0474: of the day''s earning rows (public.ledger_is_earning), the sum of those that are not trade (not public.ledger_is_trade: a gift, a hull order, insurance...). earned - lost - not_trade is the day''s trade profit (Rank Week, lit). Null: a day settled before 0474 (counted as 0).';

  create function public.ledger_is_trade(p_kind text) returns boolean
  language sql immutable as $f$
    -- 0474: THE ONE DEFINITION of a trade row (Rank Week's profit, lit: world.houses_week, public.houses_week_settle through
    -- history_company_day.not_trade): a buy, a sale, the profit tax, a crew's wages, a dock fee, a trip's stores, a request's pay.
    select p_kind in ('BUY', 'SELL', 'TAX', 'WAGES', 'PORT_FEE', 'PROVISION', 'REQUEST_FILL')
  $f$;

  create function public.wages_due(p_fleet uuid, p_profit bigint) returns bigint
  language sql stable security definer set search_path = public, pg_temp as $f$
    -- 0474: THE RULE of what a sale pays her crew (0128 / 0210, moved here from public.pay_wages, which now pays by it): of what she owes,
    -- whole ducats, at most this sale's profit after the tax and at most the visit's net so far (this sale's included). 0 when she has never
    -- owed a wage or the profit is unknown. cmd.do_sell reads it before the sale's SOLD event, so the event says the wages the sale then pays.
    select coalesce((select case when p_profit is null then 0
                                 else floor(public.wages_from_profit(w.owed, least(p_profit, w.visit_net + p_profit - w.visit_paid)))::bigint end
                       from public.fleet_wages w where w.fleet_id = p_fleet), 0)
  $f$;
  revoke all on function public.wages_due(uuid, bigint) from public, anon, authenticated;

  -- ── 3. THE HUNKS (each OLD text once in its live body; each reverses) ──
  create temp table hunks_0474 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0474 values
  ('public.player_worth(uuid)', 1,
$h$       - public.company_owed(p_player)
$h$,
$h$       - public.company_owed(p_player)
       -- 0474 (fair_gift_enabled): and what she PAID for a hull on order, or for an ordered hull launched within gift_cooldown_hours that is
       -- still hers: an order does not make her broke (the starting ship and a hull built from materials are not counted)
       + (case when coalesce(public.wc('fair_gift_enabled') = 'true'::jsonb, false)
               then coalesce((select sum(o.price) from public.hull_orders o
                               where o.player_id = p_player
                                 and (o.launched_at is null
                                      or (o.launched_at > now() - make_interval(hours => public.wc_int('gift_cooldown_hours'))
                                          and exists (select 1 from public.ships s where s.id = o.ship_id and s.player_id = p_player)))), 0)
               else 0 end)::bigint
$h$),
  ('world.board_sell(uuid,uuid,jsonb)', 1,
$h$           (x.e->>'t_days')::numeric as t_days, (x.e->>'t_arrive')::timestamptz as t_arrive
$h$,
$h$           (x.e->>'t_days')::numeric as t_days, (x.e->>'t_arrive')::timestamptz as t_arrive,
           -- 0474: and the harbours called at on the walk (the dock fees are asked of these, as of an unwalked row's)
           case when jsonb_typeof(x.e->'t_pre') = 'array' then array(select jsonb_array_elements_text(x.e->'t_pre')) end as t_pre,
           case when jsonb_typeof(x.e->'t_post') = 'array' then array(select jsonb_array_elements_text(x.e->'t_post')) end as t_post
$h$),
  ('world.board_sell(uuid,uuid,jsonb)', 2,
$h$           case when w.id is null then r.t_sea else w.t_sea end as t_sea, r.t_pre, r.t_post,   -- 0361
$h$,
$h$           case when w.id is null then r.t_sea else w.t_sea end as t_sea,   -- 0361
           -- 0474: a walked row's harbours are the walk's (world.best_sales hands legs walked with nothing: their t_pre / t_post are null, and
           -- the card's dock fee was 0 where the sheet's was not)
           case when w.id is null then r.t_pre else w.t_pre end as t_pre, case when w.id is null then r.t_post else w.t_post end as t_post,
$h$),
  ('public.pay_wages(uuid,uuid,bigint,uuid)', 1,
$h$  v_pay := case when p_profit is null then 0
                -- 0210: WHOLE DUCATS, never past what is owed: the fraction of a ducat stays owed for the next sale
                else floor(public.wages_from_profit(w.owed, least(p_profit, w.visit_net - w.visit_paid)))::bigint end;
$h$,
$h$  -- 0474: THE RULE is public.wages_due's (0210's whole ducats, moved there whole), read before this row's update as it was
  v_pay := public.wages_due(p_fleet, p_profit);
$h$),
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$  v_gift    jsonb;         -- 0241: her capital's help, when still short after the sale
$h$,
$h$  v_gift    jsonb;         -- 0241: her capital's help, when still short after the sale
  v_due     bigint;        -- 0474: the wages this sale will pay (public.wages_due: public.pay_wages' rule)
  v_call    bigint;        -- 0474: the dock fee charged when she made this harbour (fleets.call_fee), taken by her first sale here
$h$),
  ('cmd.do_sell(uuid,jsonb)', 2,
$h$  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,
$h$,
$h$  -- 0474: WHAT THE TRIP LEFT, told on the sale's own event: the wages it will pay (the rule pay_wages pays by, below) and the dock fee of
  -- this call (a company's; her first sale here takes it), so the event's trip_net is what her purse moved for the trip
  v_due  := public.wages_due(p_fleet, v_profit - v_tax);
  v_call := f.call_fee;
  if v_call is not null then
    update public.fleets set call_fee = null where id = p_fleet;
  end if;
  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,
$h$),
  ('cmd.do_sell(uuid,jsonb)', 3,
$h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax,
$h$,
$h$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax,
      'wages', v_due, 'dock_fee', coalesce(v_call, 0), 'trip_net', v_profit - v_tax - v_due - coalesce(v_call, 0),   -- 0474
$h$),
  ('public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', 1,
$h$  v_fee := public.port_fee(p_port, p_player, public.fleet_stock_at_cost(p_fleet));
$h$,
$h$  v_fee := public.port_fee(p_port, p_player, public.fleet_stock_at_cost(p_fleet));
  -- 0474: a company's fleet keeps the fee of this call until her first sale here tells it (cmd.do_sell's SOLD `dock_fee`); a merchant's never
  update public.fleets x set call_fee = nullif(v_fee, 0)
   where x.id = p_fleet and x.call_fee is distinct from nullif(v_fee, 0)
     and exists (select 1 from public.players pl where pl.id = p_player and not pl.is_npc);
$h$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 1,
$h$  insert into public.history_company_day as t (player_id, day, earned, lost)
$h$,
$h$  insert into public.history_company_day as t (player_id, day, earned, lost, not_trade)
$h$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 2,
$h$         coalesce(-sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint
$h$,
$h$         coalesce(-sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint,
         coalesce(sum(l.ducats_delta) filter (where not public.ledger_is_trade(l.kind)), 0)::bigint   -- 0474: the rows that are not trade
$h$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 3,
$h$     set earned = t.earned + excluded.earned, lost = t.lost + excluded.lost;
$h$,
$h$     set earned = t.earned + excluded.earned, lost = t.lost + excluded.lost,
         not_trade = coalesce(t.not_trade, 0) + excluded.not_trade;   -- 0474
$h$),
  ('public.houses_week_settle(timestamp with time zone)', 1,
$h$  v_gone int;
$h$,
$h$  v_gone int;
  v_fair boolean := coalesce(public.wc('fair_gift_enabled') = 'true'::jsonb, false);   -- 0474: lit, the week is trade profit only
$h$),
  ('public.houses_week_settle(timestamp with time zone)', 2,
$h$  select w.week, b.id, coalesce(sum(h.earned - h.lost), 0)::bigint
$h$,
$h$  select w.week, b.id, coalesce(sum(h.earned - h.lost - case when v_fair then coalesce(h.not_trade, 0) else 0 end), 0)::bigint   -- 0474
$h$),
  ('world.houses_week()', 1,
$h$  v_wk    timestamptz;   -- 0473: the week's first instant
$h$,
$h$  v_wk    timestamptz;   -- 0473: the week's first instant
  v_fair  boolean := coalesce(public.wc('fair_gift_enabled') = 'true'::jsonb, false);   -- 0474: lit, the week is trade profit only
$h$),
  ('world.houses_week()', 2,
$h$    v_net := coalesce((select sum(h.earned - h.lost) from public.history_company_day h
$h$,
$h$    v_net := coalesce((select sum(h.earned - h.lost - case when v_fair then coalesce(h.not_trade, 0) else 0 end) from public.history_company_day h   -- 0474
$h$),
  ('world.houses_week()', 3,
$h$                          and public.ledger_is_earning(l.kind)), 0);
$h$,
$h$                          and public.ledger_is_earning(l.kind) and (not v_fair or public.ledger_is_trade(l.kind))), 0);   -- 0474: the settle's rule
$h$);

  for v_h in select h.fn from hunks_0474 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0474 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0474 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0474 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0474 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0474 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. THE BACKFILL: the two weeks' days already settled (up to the history mark) get their gifts and hull orders as not trade ──
  select m.ledger_through into v_mark from public.history_mark m;
  with ev as (
    select g.player_id, (g.created_at at time zone 'UTC')::date as day, g.ducats::bigint as d
      from public.capital_gifts g
     where g.created_at >= (v_week - 7)::timestamp at time zone 'UTC' and g.created_at <= v_mark
    union all
    select o.player_id, (o.ordered_at at time zone 'UTC')::date, -o.price
      from public.hull_orders o
     where o.ordered_at >= (v_week - 7)::timestamp at time zone 'UTC' and o.ordered_at <= v_mark
  ), s as (select ev.player_id, ev.day, sum(ev.d)::bigint as d from ev group by 1, 2)
  update public.history_company_day h set not_trade = coalesce(h.not_trade, 0) + s.d
    from s where h.player_id = s.player_id and h.day = s.day;
  get diagnostics v_back = row_count;

  -- ── 5. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid not in ('public.ledger_is_trade(text)'::regprocedure, 'public.wages_due(uuid,bigint)'::regprocedure)) <> v_fn_before then
    raise exception '0474 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0474 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'fair_gift_enabled') <> v_cfg_before
     or public.wc('fair_gift_enabled') is distinct from 'false'::jsonb then
    raise exception '0474 self-assert FAIL: an existing world_config row moved, or fair_gift_enabled is not false';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or has_function_privilege('authenticated', 'public.wages_due(uuid,bigint)', 'execute')
     or has_function_privilege('anon', 'public.wages_due(uuid,bigint)', 'execute') then
    raise exception '0474 self-assert FAIL: a client can write a table or read the wages rule';
  end if;
  if not public.ledger_is_trade('SELL') or public.ledger_is_trade('CAPITAL_GIFT') or public.ledger_is_trade('BUILD')
     or exists (select 1 from unnest(array['BUY', 'SELL', 'TAX', 'WAGES', 'PORT_FEE', 'PROVISION', 'REQUEST_FILL']) k where not public.ledger_is_earning(k)) then
    raise exception '0474 self-assert FAIL: the trade kinds are not trade, or not earning';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel ──
  begin
    for x in select p.fn, p.def from pre_0474 p where p.fn in ('public.player_worth(uuid)', 'world.houses_week()') loop
      execute replace(replace(replace(x.def,
        'FUNCTION public.player_worth(', 'FUNCTION pg_temp.worth_old_0474('),
        'FUNCTION world.houses_week(', 'FUNCTION pg_temp.week_old_0474('),
        'SECURITY DEFINER', '');
    end loop;
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pl := public.new_house(c_uid, 'Casa da Dadiva 0474', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_pl limit 1;
    perform cmd.assume_identity(c_uid);
    update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
    -- her hull on order (0465's row, as public.hull_order_for writes it), and a sale and a gift in her ledger this week
    insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
    values (v_pl, v_lis, 'barca', 15000, 2566, 30991, 48557, now(), now() + interval '30 minutes');
    perform public.credit(v_pl, 'SELL', 3000, null);
    perform public.credit(v_pl, 'CAPITAL_GIFT', 40000, null);

    -- (a) DARK: her worth and her Week are the pre-images'
    v_w0 := pg_temp.worth_old_0474(v_pl);
    v_r0 := pg_temp.week_old_0474();
    if public.player_worth(v_pl) is distinct from v_w0 or world.houses_week() is distinct from v_r0 then
      raise exception '0474 self-assert FAIL: dark, her worth (% vs %) or her Week moved', public.player_worth(v_pl), v_w0;
    end if;
    -- (b) LIT: her worth counts the order; her Week counts the sale, not the gift
    update public.world_config set value = 'true'::jsonb where key = 'fair_gift_enabled';
    v_w1 := public.player_worth(v_pl);
    v_r1 := world.houses_week();
    if v_w1 <> v_w0 + 48557 then
      raise exception '0474 self-assert FAIL: lit, her worth % is not % + the order 48,557', v_w1, v_w0;
    end if;
    if (v_r1 -> 'you' ->> 'net')::bigint <> (v_r0 -> 'you' ->> 'net')::bigint - 40000 then
      raise exception '0474 self-assert FAIL: lit, her Week % is not % less the gift', v_r1 -> 'you', v_r0 -> 'you';
    end if;
    -- (c) the wages rule: what wages_due says is what pay_wages pays (owed 100, a profit of 60, then 70)
    insert into public.fleet_wages (fleet_id, owed, visit_net, visit_paid) values (v_fl, 100, 0, 0)
      on conflict (fleet_id) do update set owed = 100, visit_net = 0, visit_paid = 0;
    v_due  := public.wages_due(v_fl, 60);
    v_paid := public.pay_wages(v_fl, v_lis, 60, null);
    if v_due <> 60 or v_paid <> v_due then
      raise exception '0474 self-assert FAIL: wages_due % against pay_wages % (owed 100, profit 60)', v_due, v_paid;
    end if;
    v_due  := public.wages_due(v_fl, 70);
    v_paid := public.pay_wages(v_fl, v_lis, 70, null);
    if v_due <> 40 or v_paid <> v_due then
      raise exception '0474 self-assert FAIL: wages_due % against pay_wages % (owed 40 left, profit 70)', v_due, v_paid;
    end if;
    v_note := format('worth %s -> %s with the order; Week %s -> %s without the gift; wages 60, 40', v_w0, v_w1, v_r0 -> 'you' ->> 'net', v_r1 -> 'you' ->> 'net');
    raise exception using errcode = 'ZX474', message = 'PROBE_ROLLBACK_0474';
  exception when sqlstate 'ZX474' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0474 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0474' or p.auth_uid = c_uid)
     or public.wc('fair_gift_enabled') is distinct from 'false'::jsonb
     or to_regprocedure('pg_temp.worth_old_0474(uuid)') is not null
     or public.current_player_id() is not null then
    raise exception '0474 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0474 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0474 self-assert ok: A FAIR GIFT AND ONE PROFIT (gift and Week dark). % hunks once each and reversing; grants and volatility unmoved; no other function or knob moved; fair_gift_enabled false; backfill % day rows. Probe (rolled back): %. % ms.',
    (select count(*) from hunks_0474), v_back, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
