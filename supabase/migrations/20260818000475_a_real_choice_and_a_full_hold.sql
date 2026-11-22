-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0475 - A REAL CHOICE AND A FULL HOLD  (dark: the owner's switch near_choice_enabled, false; lit, a harbour's Trade cards spread over
--        two or three near harbours, a light load names a second good for the same harbour, and the near-trips rule ends by time
--        played or ships owned, not at Trading 5)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 4 ("A real choice and a full hold"; removal X10); docs/design/playable-2026-11-22.md
--   section 6, findings 7, 8 and 13; docs/dev-log/2026-11-23-near-choice.md (the numbers before and after).
--
-- WHY (the third play-test, after 0472):
--   8   at Lisbon all ten cards sold at Setubal: the hour was Lisbon-Setubal ping-pong, no choice on any trip.
--   13  half her purse bought 10 quicksilver: 8 of 180 tons; nothing offered to fill the rest. The load sailed 96 % empty.
--   7   the near rule (0472 S3) ended at Trading 5, reached at minute 20; by Trading 7 every card at Gibraltar was a 5-7 hour trip.
--       And a good with no near paying sale stood among the one-minute ones with nothing to say it was far.
--
-- WHAT CHANGES WHEN LIT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure a knob):
--   S1  THE SPREAD (world.best_sales): the cards of goods bought here that pay are taken best profit an hour first; a card keeps its
--       harbour while that harbour holds fewer than near_choice_per_harbour (3) cards; past that, it names the good's NEAREST OTHER harbour
--       whose profit an hour is at least near_choice_similar_pct (50 %) of its best, of the same kind (a near sale for a near one, under
--       0472's horizon), with room left; none: it keeps its harbour. PROFIT AN HOUR OF PLAY: each trip's seconds here are its sailing
--       plus near_choice_turn_seconds (300: the press, the load, the arrival card), measured: in the chain's world Lisbon's Setubal sales
--       take about 1 minute and Porto's and Seville's 3 to 7, each paying about as much or more; by the sailing alone a 1-minute trip is
--       always "best an hour" and no other harbour is ever similar (the play-test's ten cards to Setubal). The good's own sale
--       (0351's best per day, 0472's near first) is unchanged: the turn is read only to compare harbours for the spread. The card so moved is the sale's own served row for that harbour (the
--       trip board's row for the same units, to the coin: the same rows 0351 picks from), and carries `spread` (the harbour it left).
--       Her cargo's cards (on_board), a card that does not pay and a card 0433 sized to her purse are not moved. `far` is re-read
--       from the same rows (the richest paying sale, when it is another harbour than the one named).
--   S2  THE TOP-UP (world.best_sales): a card of a good bought here whose load fills under near_choice_topup_below_pct (50 %) of the
--       units its leg's stores leave room for (the row's `supplies.units_fit`) carries `top` {good, units, cost, profit}: a SECOND good
--       bought here for the SAME harbour, for the tons left and at most near_choice_topup_coin_pct (25 %) of her purse (never past what
--       the first load and its stores leave): of the goods this city sells, the one the room and that coin make most of at the two
--       prices (least(tons left / bulk, coin / ask) x (that harbour's bid - this city's ask), world.price; the first
--       near_choice_topup_goods (4) of them quoted), quoted both ways (world.quote here and there, the day's cap, the shelf),
--       its profit the sale less the buy, the profit tax there (public.profit_tax) and the dock fee the larger cargo adds there
--       (public.port_fee). Only when that profit is above nought. The client prints it as one more line and the one press buys both
--       (BUY, BUY, SAIL, SELL, SELL: the lines the grammar has). The crew's wages are not taken off the top-up (they are owed by the
--       voyage, paid from its profit: a larger profit may pay more of what is owed, not more than is owed).
--   S3  THE NEAR RULE'S END (public.first_hour_near_seconds, 0472's one reading of it): lit, a company is offered near trips first while
--       she was founded under near_choice_hours_played (2) hours ago AND owns fewer than near_choice_ships_below (3) ships, whatever her
--       Trading level; dark, under Trading first_hour_trading_below (5) as 0472. "Time played" is real time since the company was
--       founded (players.created_at): the game keeps no clock of time spent in it (decided by default). The rule itself is still
--       first_hour_enabled's.
--   S4  THE MARK (world.best_sales): lit, while she has a near horizon, a paying card of a good bought here carries `near` (true: the sale
--       named is within the horizon; false: no near sale pays, the card names a far one). The far sale is shown and marked, not hidden.
-- ONE AUTHORITY, EXTENDED (no second one made): the card's sale is still world.best_sales; the near horizon still
--   public.first_hour_near_seconds; every knob of the card is read in ONE place, public.near_choice_knobs (new, server only: the card reads
--   no knob of its own, the 0351 rule in tests/rpc.bestSales.spec.ts).
-- THE SWITCH near_choice_enabled (FALSE here). Dark: every hunk is a no-op (asserted on a probe against the pre-images in pg_temp).
-- NOT CHANGED: any existing knob; world.board_sell and world.good_board (0474 hunks board_sell: this file does not touch it); the buy, the
--   sale, voyage.settle; 0472's half-coin load and second-hull floor; a merchant (no cards).
-- ROWS: none, dark or lit; nine world_config rows. -- budget: none (no table, no job, no cron, no index, no fillfactor or autovacuum
--   setting). -- retention: none (no table). COST lit: world.best_sales keeps the rows it already priced (no board read more); the top-up
--   asks world.price twice for each good sold here, once for each harbour a card names (two to five a call), and per card that offers one,
--   at most four times two world.quote, two public.port_fee and one public.profit_tax; inside its 2.5 s budget (past it, no top-up is offered). The near rule:
--   one players row and one count of ships by player (indexed).
-- LOCKS: CREATE OR REPLACE x2 by hunks (world.best_sales, public.first_hour_near_seconds); CREATE x1 (public.near_choice_knobs).
--   TIME: a few seconds. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, near_choice_enabled false (every card and the near rule are their pre-images' at once). Full: a
--   new migration reversing the five hunks (OLD texts below verbatim), dropping the helper and deleting the nine knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; no other world_config row moved; the switch false. THE PROBE (rolled back): a fresh Lisbon company. DARK every card (with
--   first_hour_enabled off and on) and her near horizon equal their pre-images' (copies in pg_temp), read in ONE statement (one snapshot)
--   and compared good by good: a call cut by world.best_sales' own 2.5 s budget (its only clock_timestamp input) compares as a prefix; LIT no harbour holds more cards than
--   the knob where another was within reach, every moved card is one of its good's paying sales within the knob of its best, every top-up
--   is another good with a profit above nought within the coin and the room, and a Trading 5 newcomer still has her horizon while a
--   company founded three hours ago has none. Proof 178 plays the doors.
-- VERSION: 0475 = 0474 + 1 (0474, #799, hunks world.board_sell, cmd.do_sell, world.houses_week and others: none of them here).
-- news: none (dark: nothing changes for a player until the owner lights near_choice_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['world.best_sales(uuid,uuid)', 'public.first_hour_near_seconds(uuid)'];
  c_knobs  constant text[] := array['near_choice_enabled', 'near_choice_per_harbour', 'near_choice_similar_pct', 'near_choice_topup_below_pct',
                                    'near_choice_topup_coin_pct', 'near_choice_hours_played', 'near_choice_ships_below', 'near_choice_topup_goods',
                                    'near_choice_turn_seconds'];
  c_uid    constant uuid := '00000000-0475-4000-8000-000000000001';
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
  v_old       jsonb;
  v_new       jsonb;
  v_purse     numeric;
  v_per       int;
  v_moved     int := 0;
  v_tops      int := 0;
  v_note      text := '';
  v_cut       int := 0;   -- comparisons where a call ran out of its 2.5 s budget (its goods compared as a prefix of the other's)
  v_cmp       int := 0;   -- goods compared dark, both calls answered
  v_hz_new    numeric;
  v_hz_old    numeric;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config c where c.key = any(c_knobs)) or to_regprocedure('public.near_choice_knobs()') is not null then
    raise exception '0475 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or to_regprocedure('world.price(uuid,uuid)') is null
     or to_regprocedure('world.quote(uuid,uuid,numeric,text,numeric,uuid)') is null
     or to_regprocedure('world.daily_cap_remaining(uuid,uuid,uuid)') is null
     or to_regprocedure('public.port_fee(uuid,uuid,numeric)') is null
     or to_regprocedure('public.profit_tax(uuid,numeric,uuid)') is null
     or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null
     or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null
     or public.wc('first_hour_enabled') is null or public.wc('first_hour_trading_below') is null then
    raise exception '0475 refuses: the best sales (0348, 0351, 0433, 0459) or the first hour (0472) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0475 (fn text primary key, def text) on commit drop;
  insert into pre_0475 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SWITCH AND ITS FIGURES ──
  insert into public.world_config (key, value, description) values
    ('near_choice_enabled', 'false'::jsonb,
     '0475: A REAL CHOICE AND A FULL HOLD (the owner''s switch). true: world.best_sales spreads a harbour''s Trade cards over near harbours of similar profit an hour (near_choice_per_harbour, near_choice_similar_pct), names a second good for the same harbour when the load leaves most of the room empty (near_choice_topup_*), and marks whether the sale named is near; the near-trips rule (first_hour_enabled) ends by time played or ships owned (near_choice_hours_played, near_choice_ships_below), not by Trading. false: all as before 0475.'),
    ('near_choice_per_harbour', '3'::jsonb,
     '0475: the most Trade cards of goods bought here that name one harbour, while another of similar profit an hour has room (near_choice_enabled).'),
    ('near_choice_similar_pct', '50'::jsonb,
     '0475: a good''s other harbour may take its card when its profit an hour of play (near_choice_turn_seconds added to each trip) is at least this % of the good''s best (near_choice_enabled).'),
    ('near_choice_turn_seconds', '300'::jsonb,
     '0475: the seconds of play a trip takes besides its sailing (the press, the load, the arrival), added to each trip when the spread compares harbours by profit an hour (near_choice_enabled).'),
    ('near_choice_topup_below_pct', '50'::jsonb,
     '0475: a Trade card names a second good for the same harbour when its load fills under this % of the units its leg leaves room for (near_choice_enabled).'),
    ('near_choice_topup_coin_pct', '25'::jsonb,
     '0475: the most of her purse the second good may cost, in % (never past what the first load and its stores leave) (near_choice_enabled).'),
    ('near_choice_topup_goods', '4'::jsonb,
     '0475: how many of the goods sold here, the most the room and the coin left make first, are quoted for a card''s second good (near_choice_enabled).'),
    ('near_choice_hours_played', '2'::jsonb,
     '0475: lit, a company is offered near trips first (first_hour_enabled) for this many hours after she was founded, while she owns fewer than near_choice_ships_below ships (near_choice_enabled).'),
    ('near_choice_ships_below', '3'::jsonb,
     '0475: lit, a company is offered near trips first (first_hour_enabled) while she owns fewer ships than this, for her first near_choice_hours_played hours (near_choice_enabled).');

  -- THE ONE READING of the card's knobs (S1, S2), so world.best_sales reads no knob of its own (0351: the card has no knob of its own). Null
  -- while dark. Server only.
  create function public.near_choice_knobs() returns jsonb
  language sql stable security definer set search_path = public, pg_temp as $f$
    -- 0475: near_choice_enabled's figures for the Trade cards (world.best_sales): null while dark
    select case when coalesce(public.wc('near_choice_enabled') = 'true'::jsonb, false) then jsonb_build_object(
             'per_harbour', public.wc_int('near_choice_per_harbour'), 'similar', public.wc_num('near_choice_similar_pct'),
             'topup_below', public.wc_num('near_choice_topup_below_pct'), 'topup_coin', public.wc_num('near_choice_topup_coin_pct'),
             'topup_goods', public.wc_int('near_choice_topup_goods'), 'turn', public.wc_num('near_choice_turn_seconds')) end
  $f$;
  revoke all on function public.near_choice_knobs() from public, anon, authenticated;

  -- ── 3. THE HUNKS (each OLD text once in its live body; each reverses) ──
  create temp table hunks_0475 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0475 values
  ('world.best_sales(uuid,uuid)', 1,
$h$  v_near_s  numeric := public.first_hour_near_seconds(public.current_player_id());
$h$,
$h$  v_near_s  numeric := public.first_hour_near_seconds(public.current_player_id());
  -- 0475 (A REAL CHOICE AND A FULL HOLD, near_choice_enabled; public.near_choice_knobs, null while dark): v_alt a good's paying sales within
  -- her purse, the best of each harbour; v_alts every good's; v_cnt the cards a harbour holds; v_topc a harbour's second goods, asked once
  v_nc      jsonb := public.near_choice_knobs();
  v_alt     jsonb;
  v_alts    jsonb := '{}'::jsonb;
  v_cnt     jsonb := '{}'::jsonb;
  v_topc    jsonb := '{}'::jsonb;
  v_card    jsonb;
  v_pick    jsonb;
  v_dp      uuid;
  v_room    numeric;
  v_coin    numeric;
  v_tn      numeric;
  v_tb      record;
  v_ts      record;
  v_base    numeric;
  v_tnet    numeric;
  y         record;
  z         record;
$h$),
  ('world.best_sales(uuid,uuid)', 2,
$h$           v_short or (exists (select 1 from pool) and not exists (select 1 from c))
      into v_best, v_far, v_short;
$h$,
$h$           v_short or (exists (select 1 from pool) and not exists (select 1 from c)),
           -- 0475 (lit): a good bought here: its paying sales within her purse, the best of each harbour, best an hour first (the spread)
           case when v_nc is not null and a.basis <> 'on_board' then
             (select jsonb_agg(s.o order by s.rate desc, s.port) from (
                select distinct on (c.e->>'port') c.e->>'port' as port, c.profit / (c.secs + (v_nc->>'turn')::numeric) as rate,
                       jsonb_build_object('port', c.e->>'port', 'units', (c.e->>'units')::numeric, 'profit', c.profit,
                                          'days', (c.e->>'days')::numeric, 'cost', (c.e->>'cost')::numeric,
                                          'seconds', round(extract(epoch from ((c.e->>'arrive_at')::timestamptz - now()))),
                                          'fit', (c.e->'supplies'->>'units_fit')::numeric, 'rate', c.profit / (c.secs + (v_nc->>'turn')::numeric),
                                          'stores', case when v_credit then 0 else coalesce((c.e->'supplies'->>'cost')::numeric, 0) end,
                                          'near', (v_near_s is null or c.secs <= v_near_s)) as o
                  from c where c.profit > 0
                 order by c.e->>'port', c.profit / (c.secs + (v_nc->>'turn')::numeric) desc) s) end
      into v_best, v_far, v_short, v_alt;
$h$),
  ('world.best_sales(uuid,uuid)', 3,
$h$    v_out := v_out || jsonb_build_array(jsonb_build_object(
$h$,
$h$    -- 0475 (lit): the good's paying sales are kept for the spread, when the answer is one of them (a sale 0433 sized to her purse is not)
    if v_alt is not null and v_best is not null
       and exists (select 1 from jsonb_array_elements(v_alt) e
                    where e->>'port' = v_best->>'port' and (e->>'units')::numeric = (v_best->>'units')::numeric) then
      v_alts := v_alts || jsonb_build_object(gd.code, v_alt);
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
$h$),
  ('world.best_sales(uuid,uuid)', 4,
$h$  return jsonb_build_object('port', v_port.code, 'goods', v_out, 'cut', v_cut,
$h$,
$h$  -- 0475 (near_choice_enabled): A REAL CHOICE AND A FULL HOLD. The cards of goods bought here that pay, best profit an hour first:
  --   THE SPREAD: a card keeps its harbour while it holds fewer than per_harbour cards; else it names the NEAREST other harbour of the good
  --     within `similar` % of its best an hour of play, of the same kind (near for near), with room; none: it stays. Moved: `spread` names the harbour left.
  --   THE MARK: with a newcomer's horizon, `near` says whether the sale named is within it.
  --   THE TOP-UP: a load filling under topup_below % of the units its leg has room for names `top`, a second good bought here for the same
  --     harbour, for the tons left and at most topup_coin % of her purse (never past what the load and its stores leave), quoted both ways;
  --     its profit is the sale less the buy, the profit tax there and the dock fee the larger cargo adds there; only above nought.
  if v_nc is not null then
    for y in
      select o.i - 1 as i, o.e as card, v_alts -> (o.e->>'good') as alts
        from jsonb_array_elements(v_out) with ordinality o(e, i)
       where v_alts ? (o.e->>'good')
       order by (select (x.e->>'rate')::numeric from jsonb_array_elements(v_alts -> (o.e->>'good')) x(e) where x.e->>'port' = o.e->>'port') desc,
                o.e->>'good'
    loop
      select x.e into v_pick from jsonb_array_elements(y.alts) x(e) where x.e->>'port' = y.card->>'port';
      if coalesce((v_cnt->>(v_pick->>'port'))::int, 0) >= (v_nc->>'per_harbour')::int then
        select x.e into v_alt
          from jsonb_array_elements(y.alts) with ordinality x(e, k)
         where x.e->>'port' <> v_pick->>'port' and (x.e->>'near')::boolean = (v_pick->>'near')::boolean
           and (x.e->>'rate')::numeric >= (v_pick->>'rate')::numeric * (v_nc->>'similar')::numeric / 100
           and coalesce((v_cnt->>(x.e->>'port'))::int, 0) < (v_nc->>'per_harbour')::int
         order by (x.e->>'seconds')::numeric, x.k limit 1;   -- the nearest of them: a near choice
        if v_alt is not null then
          v_pick := v_alt;
        end if;
      end if;
      v_cnt := v_cnt || jsonb_build_object(v_pick->>'port', coalesce((v_cnt->>(v_pick->>'port'))::int, 0) + 1);
      v_card := y.card;
      if v_pick->>'port' <> v_card->>'port' then
        select x.e into v_alt from jsonb_array_elements(y.alts) x(e)
         order by (x.e->>'profit')::numeric desc, (x.e->>'days')::numeric nulls last, x.e->>'port' limit 1;
        v_card := v_card || jsonb_build_object(
                    'port', v_pick->>'port', 'units', v_pick->'units', 'profit', v_pick->'profit', 'days', v_pick->'days',
                    'cost', v_pick->'cost', 'seconds', v_pick->'seconds', 'spread', v_card->>'port',
                    'far', case when v_alt->>'port' is distinct from v_pick->>'port' then jsonb_build_object(
                             'port', v_alt->>'port', 'units', v_alt->'units', 'profit', v_alt->'profit', 'days', v_alt->'days',
                             'cost', v_alt->'cost', 'seconds', v_alt->'seconds') end);
      end if;
      if v_near_s is not null then
        v_card := v_card || jsonb_build_object('near', (v_pick->>'near')::boolean);
      end if;
      -- THE TOP-UP (past the call's budget: none)
      if clock_timestamp() - v_t0 <= c_budget and (v_pick->>'fit')::numeric > 0
         and (v_pick->>'units')::numeric < (v_pick->>'fit')::numeric * (v_nc->>'topup_below')::numeric / 100 then
        v_room := ((v_pick->>'fit')::numeric - (v_pick->>'units')::numeric) * (select g.bulk from public.goods g where g.code = v_card->>'good');
        v_coin := least(v_purse * (v_nc->>'topup_coin')::numeric / 100,
                        v_purse - coalesce((v_pick->>'cost')::numeric, 0) - coalesce((v_pick->>'stores')::numeric, 0));
        v_dp := (select pt.id from public.ports pt where pt.code = v_pick->>'port' and pt.kind = 'HARBOUR');
        if not v_topc ? (v_pick->>'port') then
          -- that harbour's goods sold here that it bids more for than this city asks (world.price both ways), asked once a harbour
          v_topc := v_topc || jsonb_build_object(v_pick->>'port', (
            select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'good', g.code, 'bulk', g.bulk, 'ask', h.ask, 'bid', s.bid) order by g.code), '[]'::jsonb)
              from jsonb_array_elements(v_out) o(e)
              join public.goods g on g.code = o.e->>'good'
              cross join lateral world.price(p_port, g.id) h
              cross join lateral world.price(v_dp, g.id) s
             where o.e->>'basis' <> 'on_board' and h.ask > 0 and g.bulk > 0 and s.bid > h.ask));
        end if;
        -- the best of them for THIS load: the most the room and the coin left let her make at those prices, the first topup_goods quoted
        for z in
          select t.id, t.code, t.bulk, t.ask
            from (select (x.e->>'id')::uuid as id, x.e->>'good' as code, (x.e->>'bulk')::numeric as bulk, (x.e->>'ask')::numeric as ask,
                         floor(least(v_room / (x.e->>'bulk')::numeric, v_coin / (x.e->>'ask')::numeric))
                           * ((x.e->>'bid')::numeric - (x.e->>'ask')::numeric) as est
                    from jsonb_array_elements(v_topc -> (v_pick->>'port')) x(e)
                   where x.e->>'good' <> v_card->>'good') t
           where t.est > 0
           order by t.est desc, t.code
           limit (v_nc->>'topup_goods')::int
        loop
          v_tn := floor(least(v_room / z.bulk, v_coin / z.ask, coalesce(world.daily_cap_remaining(v_player, p_port, z.id), 0)));
          continue when v_tn is null or v_tn < 1;
          select q.units, q.total into v_tb from world.quote(p_port, z.id, v_tn, 'buy', null, p_fleet) q;
          if v_tb.total > v_coin then
            -- the shelf walks dearer than the ask: once narrowed to the coin
            v_tn := floor(v_tb.units * v_coin / v_tb.total);
            continue when v_tn < 1;
            select q.units, q.total into v_tb from world.quote(p_port, z.id, v_tn, 'buy', null, p_fleet) q;
          end if;
          continue when coalesce(v_tb.units, 0) < 1 or v_tb.total > v_coin;
          select q.units, q.total into v_ts from world.quote(v_dp, z.id, v_tb.units, 'sell', null, p_fleet) q;
          continue when coalesce(v_ts.units, 0) < v_tb.units;
          v_base := coalesce(public.fleet_stock_at_cost(p_fleet), 0) + coalesce((v_pick->>'cost')::numeric, 0);
          v_tnet := v_ts.total - v_tb.total - coalesce(public.profit_tax(v_dp, v_ts.total - v_tb.total, v_player), 0)
                    - (coalesce(public.port_fee(v_dp, v_player, v_base + v_tb.total), 0) - coalesce(public.port_fee(v_dp, v_player, v_base), 0));
          continue when v_tnet <= 0;
          v_card := v_card || jsonb_build_object('top', jsonb_build_object('good', z.code, 'units', v_tb.units, 'cost', v_tb.total, 'profit', round(v_tnet)));
          exit;
        end loop;
      end if;
      v_out := jsonb_set(v_out, array[y.i::text], v_card);
    end loop;
  end if;
  return jsonb_build_object('port', v_port.code, 'goods', v_out, 'cut', v_cut,
$h$),
  ('public.first_hour_near_seconds(uuid)', 1,
$h$                     and coalesce((select m.level from public.house_level_marks m where m.player_id = p_player and m.track = 'trading'), 1)
                         < public.wc_num('first_hour_trading_below')
$h$,
$h$                     and case when coalesce(public.wc('near_choice_enabled') = 'true'::jsonb, false)
                              -- 0475 (near_choice_enabled): the rule ends by time played (since she was founded) or ships owned, not Trading
                              then coalesce((select p.created_at > now() - make_interval(secs => public.wc_num('near_choice_hours_played') * 3600)
                                               from public.players p where p.id = p_player), false)
                                   and (select count(*) from public.ships s where s.player_id = p_player) < public.wc_num('near_choice_ships_below')
                              else coalesce((select m.level from public.house_level_marks m where m.player_id = p_player and m.track = 'trading'), 1)
                                   < public.wc_num('first_hour_trading_below') end
$h$);

  for v_h in select h.fn from hunks_0475 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0475 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0475 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0475 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0475 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0475 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> 'public.near_choice_knobs()'::regprocedure) <> v_fn_before then
    raise exception '0475 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0475 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all(c_knobs)) <> v_cfg_before
     or public.wc('near_choice_enabled') is distinct from 'false'::jsonb
     or (select count(*) from public.world_config c where c.key = any(c_knobs)) <> array_length(c_knobs, 1)
     or public.near_choice_knobs() is not null then
    raise exception '0475 self-assert FAIL: an existing world_config row moved, a knob is missing, or near_choice_enabled is not false';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or has_function_privilege('authenticated', 'public.near_choice_knobs()', 'execute')
     or has_function_privilege('anon', 'public.near_choice_knobs()', 'execute') then
    raise exception '0475 self-assert FAIL: a client can write a table or read the card''s knobs';
  end if;
  if (select prosrc from pg_proc where oid = 'world.best_sales(uuid,uuid)'::regprocedure) like '%wc_num(%' then
    raise exception '0475 self-assert FAIL: the card reads a knob of its own';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel ──
  begin
    -- the pre-images, callable as pg_temp.*_old_0475 (their definer dropped: a copy in pg_temp runs as the migration)
    for x in select p.fn, p.def from pre_0475 p loop
      execute replace(replace(replace(x.def,
        'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_old_0475('),
        'FUNCTION public.first_hour_near_seconds(', 'FUNCTION pg_temp.near_old_0475('),
        'SECURITY DEFINER', '');
    end loop;
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pl := public.new_house(c_uid, 'Casa da Escolha 0475', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_pl limit 1;
    perform cmd.assume_identity(c_uid);
    select p.ducats into v_purse from public.players p where p.id = v_pl;

    -- (a) DARK: every card and her horizon are their pre-images', with the first hour off and on.
    -- DETERMINISTIC (the deploy of 2026-11-23 was refused here on prod, not on any local world): every function the card read runs is
    -- STABLE and reads now(), so two calls in ONE statement see one snapshot and one time; the one input that is not is world.best_sales'
    -- own 2.5 s budget (clock_timestamp: `cut`, the goods after it not answered). So both answers are read in one statement, the read is
    -- warmed first, and the goods BOTH calls answered are compared in order, to the byte; a cut answer must be a prefix of the other;
    -- with neither cut, the whole answer is compared.
    perform world.best_sales(v_fl, v_lis);   -- warm (its answer is not read)
    for v_n in 0 .. 1 loop
      update public.world_config set value = to_jsonb(v_n = 1) where key = 'first_hour_enabled';
      select world.best_sales(v_fl, v_lis), pg_temp.best_sales_old_0475(v_fl, v_lis), public.first_hour_near_seconds(v_pl), pg_temp.near_old_0475(v_pl)
        into v_new, v_old, v_hz_new, v_hz_old;
      if v_hz_new is distinct from v_hz_old then
        raise exception '0475 self-assert FAIL: dark (first hour %), her horizon moved: % against %', v_n = 1, v_hz_new, v_hz_old;
      end if;
      if not (v_new ->> 'cut')::boolean and not (v_old ->> 'cut')::boolean then
        if v_new - 'clock' is distinct from v_old - 'clock' then
          raise exception '0475 self-assert FAIL: dark (first hour %), a card moved: % against %', v_n = 1, v_new - 'clock', v_old - 'clock';
        end if;
      else
        v_cut := v_cut + 1;
        if v_new - 'clock' - 'goods' - 'cut' is distinct from v_old - 'clock' - 'goods' - 'cut'
           or ((v_new ->> 'cut')::boolean and not (v_old ->> 'cut')::boolean and jsonb_array_length(v_new -> 'goods') > jsonb_array_length(v_old -> 'goods'))
           or ((v_old ->> 'cut')::boolean and not (v_new ->> 'cut')::boolean and jsonb_array_length(v_old -> 'goods') > jsonb_array_length(v_new -> 'goods')) then
          raise exception '0475 self-assert FAIL: dark (first hour %), cut answers that are not one another''s prefix: % against %', v_n = 1, v_new - 'clock', v_old - 'clock';
        end if;
      end if;
      for x in
        select a.e as now, b.e as was, a.i
          from jsonb_array_elements(v_new -> 'goods') with ordinality a(e, i)
          join jsonb_array_elements(v_old -> 'goods') with ordinality b(e, i) on b.i = a.i
      loop
        v_cmp := v_cmp + 1;
        if x.now is distinct from x.was then
          raise exception '0475 self-assert FAIL: dark (first hour %), card % moved: % against %', v_n = 1, x.i, x.now, x.was;
        end if;
      end loop;
    end loop;

    -- (b) LIT (the first hour on): the spread, the top-up, the mark
    update public.world_config set value = 'true'::jsonb where key = 'near_choice_enabled';
    v_per := public.wc_int('near_choice_per_harbour');
    -- both in ONE statement: one snapshot (a beat's write between two statements would move an unmoved card)
    select pg_temp.best_sales_old_0475(v_fl, v_lis), world.best_sales(v_fl, v_lis) into v_old, v_new;
    if not (v_old ->> 'cut')::boolean and not (v_new ->> 'cut')::boolean then
      for x in
        select o.e as was, n.e as now
          from jsonb_array_elements(v_old -> 'goods') o(e)
          join jsonb_array_elements(v_new -> 'goods') n(e) on n.e ->> 'good' = o.e ->> 'good'
      loop
        -- a card moved only to another paying harbour of its good, for the same units, from a harbour that held the knob's count
        if x.now ->> 'port' is distinct from x.was ->> 'port' then
          v_moved := v_moved + 1;
          if x.now ->> 'spread' is distinct from x.was ->> 'port' or not (x.now ->> 'pays')::boolean or (x.now ->> 'profit')::numeric <= 0
             or (x.now ->> 'units')::numeric is distinct from (x.was ->> 'units')::numeric
             or x.was ->> 'basis' = 'on_board'
             or (select count(*) from jsonb_array_elements(v_new -> 'goods') e where e ->> 'port' = x.was ->> 'port') < v_per then
            raise exception '0475 self-assert FAIL: lit, % moved from % to % (%)', x.was ->> 'good', x.was ->> 'port', x.now ->> 'port', x.now;
          end if;
        elsif (x.now - 'top' - 'near') is distinct from x.was then
          raise exception '0475 self-assert FAIL: lit, the card of % changed where it did not move: % against %', x.was ->> 'good', x.now, x.was;
        end if;
        -- a top-up: another good, a whole count, within the coin, paying
        if x.now ? 'top' then
          v_tops := v_tops + 1;
          if x.now -> 'top' ->> 'good' = x.now ->> 'good' or (x.now -> 'top' ->> 'units')::numeric < 1
             or (x.now -> 'top' ->> 'profit')::numeric <= 0
             or (x.now -> 'top' ->> 'cost')::numeric > v_purse * public.wc_num('near_choice_topup_coin_pct') / 100 then
            raise exception '0475 self-assert FAIL: lit, the top-up of % is %', x.now ->> 'good', x.now -> 'top';
          end if;
        end if;
        -- the mark: her horizon is set (a new company), so a paying card bought here says near or not
        if x.now ->> 'basis' <> 'on_board' and (x.now ->> 'pays')::boolean and x.now ->> 'port' is not null
           and (x.now ->> 'have') is null and not (x.now ? 'near') then
          raise exception '0475 self-assert FAIL: lit, the card of % is not marked near or far: %', x.now ->> 'good', x.now;
        end if;
      end loop;
      -- no harbour holds more than the knob's cards unless no card on it had another within reach (asserted per move above); report
      v_note := format('%s cards, %s moved, %s with a second good, harbours %s -> %s', jsonb_array_length(v_new -> 'goods'), v_moved, v_tops,
                       (select count(distinct e ->> 'port') from jsonb_array_elements(v_old -> 'goods') e where e ->> 'port' is not null),
                       (select count(distinct e ->> 'port') from jsonb_array_elements(v_new -> 'goods') e where e ->> 'port' is not null));
    else
      v_note := 'the lit cards were NOT COMPARED HERE (the 2.5 s budget ran out; proof 178 holds them)';
    end if;

    -- (c) LIT, the near rule's end: a Trading 5 newcomer keeps her horizon; founded three hours ago, none
    insert into public.house_level_marks (player_id, track, level) values (v_pl, 'trading', 5)
      on conflict (player_id, track) do update set level = excluded.level;
    if public.first_hour_near_seconds(v_pl) is distinct from public.wc_num('first_hour_trip_hours') * 3600
       or pg_temp.near_old_0475(v_pl) is not null then
      raise exception '0475 self-assert FAIL: lit, a Trading 5 company founded now has horizon % (before: %)', public.first_hour_near_seconds(v_pl), pg_temp.near_old_0475(v_pl);
    end if;
    update public.players set created_at = now() - interval '3 hours' where id = v_pl;
    if public.first_hour_near_seconds(v_pl) is not null then
      raise exception '0475 self-assert FAIL: lit, a company founded three hours ago still has a near horizon';
    end if;
    raise exception using errcode = 'ZX475', message = 'PROBE_ROLLBACK_0475';
  exception when sqlstate 'ZX475' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0475 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0475' or p.auth_uid = c_uid)
     or public.wc('near_choice_enabled') is distinct from 'false'::jsonb
     or to_regprocedure('pg_temp.best_sales_old_0475(uuid,uuid)') is not null
     or public.current_player_id() is not null then
    raise exception '0475 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0475 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0475 self-assert ok: A REAL CHOICE AND A FULL HOLD (dark). % hunks once each and reversing; grants and volatility unmoved; no other function or knob moved; near_choice_enabled false. Probe (rolled back), a fresh Lisbon company: dark % cards and her horizon their pre-image''s to the byte (first hour off and on; % of 2 comparisons cut by the 2.5 s budget, compared as a prefix); lit %; a Trading 5 newcomer keeps her horizon, one founded three hours ago has none. % ms.',
    (select count(*) from hunks_0475), v_cmp, v_cut, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
