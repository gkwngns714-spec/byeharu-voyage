-- A FAIR GIFT AND ONE PROFIT (0474), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/gift-profit/before-0474.sql
-- Expect: head 20260818000473; knob {} (no fair_gift_enabled); cols {} (no fleets.call_fee, no history_company_day.not_trade); each of the
-- sixteen hunks' OLD text once (old 1) in its live body and no 0474 mark in it (new 0); `kept`: merchant_broke_pct 0.2, starting_ducats
-- 40000, gift_cooldown_hours 24, yard_order_enabled true, houses_board_enabled true, economy_closed true.
-- `gifted_with_hull`: the companies (not merchants) a capital gave to in the last 7 days while a hull she had ordered was on order (ordered
-- before the gift, not launched by it) or launched within gift_cooldown_hours before it: the gifts 0474 (lit) would not have made, with the
-- purse she had none of (gift, the hull's price). `would_now`: companies with a hull on order and a purse under the line today.
-- Reads: the catalog (pg_get_functiondef of eight functions: stable), world_config by key, information_schema, capital_gifts of 7 days
-- (a few hundred rows) joined to hull_orders by player (indexed), players by id. No game function is called.
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.player_worth(uuid)', 1, $o$       - public.company_owed(p_player)
$o$),
  ('world.board_sell(uuid,uuid,jsonb)', 1, $o$           (x.e->>'t_days')::numeric as t_days, (x.e->>'t_arrive')::timestamptz as t_arrive
$o$),
  ('world.board_sell(uuid,uuid,jsonb)', 2, $o$           case when w.id is null then r.t_sea else w.t_sea end as t_sea, r.t_pre, r.t_post,   -- 0361
$o$),
  ('public.pay_wages(uuid,uuid,bigint,uuid)', 1, $o$  v_pay := case when p_profit is null then 0
                -- 0210: WHOLE DUCATS, never past what is owed: the fraction of a ducat stays owed for the next sale
                else floor(public.wages_from_profit(w.owed, least(p_profit, w.visit_net - w.visit_paid)))::bigint end;
$o$),
  ('cmd.do_sell(uuid,jsonb)', 1, $o$  v_gift    jsonb;         -- 0241: her capital's help, when still short after the sale
$o$),
  ('cmd.do_sell(uuid,jsonb)', 2, $o$  perform public.city_pays(f.port_id, f.player_id, 'SELL', q.total,
$o$),
  ('cmd.do_sell(uuid,jsonb)', 3, $o$      'basis', v_basis, 'cost', v_cost, 'profit', v_profit, 'tax', v_tax, 'net', q.total - v_tax,
$o$),
  ('public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', 1, $o$  v_fee := public.port_fee(p_port, p_player, public.fleet_stock_at_cost(p_fleet));
$o$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 1, $o$  insert into public.history_company_day as t (player_id, day, earned, lost)
$o$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 2, $o$         coalesce(-sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint
$o$),
  ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)', 3, $o$     set earned = t.earned + excluded.earned, lost = t.lost + excluded.lost;
$o$),
  ('public.houses_week_settle(timestamp with time zone)', 1, $o$  v_gone int;
$o$),
  ('public.houses_week_settle(timestamp with time zone)', 2, $o$  select w.week, b.id, coalesce(sum(h.earned - h.lost), 0)::bigint
$o$),
  ('world.houses_week()', 1, $o$  v_wk    timestamptz;   -- 0473: the week's first instant
$o$),
  ('world.houses_week()', 2, $o$    v_net := coalesce((select sum(h.earned - h.lost) from public.history_company_day h
$o$),
  ('world.houses_week()', 3, $o$                          and public.ledger_is_earning(l.kind)), 0);
$o$)
), d as (
  select h.fn, h.ord, h.old, replace(pg_get_functiondef(to_regprocedure(h.fn)), E'', '') as def from h
), line as (select (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'starting_ducats')
                   * (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'merchant_broke_pct') as v),
cool as (select make_interval(hours => (select (c.value #>> '{}')::int from public.world_config c where c.key = 'gift_cooldown_hours')) as v)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knob', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key = 'fair_gift_enabled'),
  'cols', (select coalesce(jsonb_object_agg(c.table_name, c.column_name), '{}'::jsonb) from information_schema.columns c
            where c.table_schema = 'public' and (c.table_name, c.column_name) in (('fleets', 'call_fee'), ('history_company_day', 'not_trade'))),
  'kept', (select jsonb_object_agg(c.key, c.value) from public.world_config c
            where c.key in ('merchant_broke_pct', 'starting_ducats', 'gift_cooldown_hours', 'yard_order_enabled', 'houses_board_enabled', 'economy_closed')),
  'hunks', (select jsonb_agg(jsonb_build_object('fn', d.fn, 'h', d.ord,
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, '0474', ''))) / 4) order by d.fn, d.ord) from d),
  'gifted_with_hull', (select coalesce(jsonb_agg(jsonb_build_object('player', g.player_id, 'at', g.created_at, 'gift', g.ducats,
                                'hull', (select max(o.price) from public.hull_orders o where o.player_id = g.player_id and o.ordered_at < g.created_at
                                           and (o.launched_at is null or o.launched_at > g.created_at - (select v from cool))))
                              order by g.created_at), '[]'::jsonb)
                         from public.capital_gifts g join public.players p on p.id = g.player_id
                        where not p.is_npc and g.created_at > now() - interval '7 days'
                          and exists (select 1 from public.hull_orders o where o.player_id = g.player_id and o.ordered_at < g.created_at
                                        and (o.launched_at is null or o.launched_at > g.created_at - (select v from cool)))),
  'would_now', (select count(*) from public.players p where not p.is_npc and p.ducats < (select v from line)
                   and exists (select 1 from public.hull_orders o where o.player_id = p.id and o.launched_at is null)));
rollback;
