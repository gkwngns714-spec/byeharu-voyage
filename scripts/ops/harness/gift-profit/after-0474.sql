-- A FAIR GIFT AND ONE PROFIT (0474), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/gift-profit/after-0474.sql
-- Set `since` below to the deploy time (after the deploy) or the lighting time of fair_gift_enabled (the 30-minute after-check).
-- Expect, AS DEPLOYED (dark): head 20260818000474; knob {"fair_gift_enabled": false}; cols both; every hunked function carries its 0474
-- marks (true); fns both. Finding 1 is not switched, so at once: `sold` (the SOLD events since) all carry trip_net (`with_net` = `n`),
-- `bad_net` 0 (trip_net = profit - tax - wages - dock_fee on every one), `with_fee` > 0 once companies arrive and sell; `call_fees` a
-- handful (company fleets lying in port, not yet sold).
-- LIT (the owner lights fair_gift_enabled; read 30 minutes on): `gifts_with_hull` [] (no company gifted while a hull she ordered is on order
-- or launched within the cooldown); `gifts` the other gifts as before (the gift itself is not off); `week_gifted`: companies gifted this
-- week, each `net` (the settled Week) = `trade` (earned - lost - not_trade of the days) once the history job ran (15 minutes).
-- ROLLBACK if `gifts` stops entirely while broke companies without a hull exist, or `bad_net` > 0: fair_gift_enabled false (owner).
-- Reads: the catalog, world_config by key, information_schema; events SOLD since (events_trades_window index: a range of 30 minutes);
-- capital_gifts of a week (a few hundred rows) with hull_orders by player; history_company_day by player for at most 10 players; fleets
-- with a call fee. No game function is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
cool as (select make_interval(hours => (select (c.value #>> '{}')::int from public.world_config c where c.key = 'gift_cooldown_hours')) as v),
wk as (select public.history_bucket((now() at time zone 'UTC')::date, 'week') as d),   -- the Week's one rule (immutable)
sold as (
  select e.payload as p from public.events e
   where e.kind in ('SOLD', 'BOUGHT') and e.created_at > (select t from since) and e.kind = 'SOLD'
), gifted as (
  select g.player_id, g.created_at, g.ducats,
         exists (select 1 from public.hull_orders o where o.player_id = g.player_id and o.ordered_at < g.created_at
                   and (o.launched_at is null or o.launched_at > g.created_at - (select v from cool))) as had_hull
    from public.capital_gifts g join public.players p on p.id = g.player_id
   where not p.is_npc and g.created_at > (select t from since)
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knob', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key = 'fair_gift_enabled'),
  'cols', (select jsonb_object_agg(c.table_name, c.column_name) from information_schema.columns c
            where c.table_schema = 'public' and (c.table_name, c.column_name) in (('fleets', 'call_fee'), ('history_company_day', 'not_trade'))),
  'fns', jsonb_build_object('ledger_is_trade', to_regprocedure('public.ledger_is_trade(text)') is not null,
                            'wages_due', to_regprocedure('public.wages_due(uuid,bigint)') is not null),
  'marks', (select jsonb_object_agg(f.fn, position('0474' in pg_get_functiondef(to_regprocedure(f.fn))) > 0) from (values
              ('public.player_worth(uuid)'), ('world.board_sell(uuid,uuid,jsonb)'), ('public.pay_wages(uuid,uuid,bigint,uuid)'), ('cmd.do_sell(uuid,jsonb)'),
              ('public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)'),
              ('public.history_ledger_add(timestamp with time zone,timestamp with time zone)'),
              ('public.houses_week_settle(timestamp with time zone)'), ('world.houses_week()')) f(fn)),
  'sold', (select jsonb_build_object('n', count(*), 'with_net', count(*) filter (where s.p ? 'trip_net'),
                    'with_fee', count(*) filter (where (s.p ->> 'dock_fee')::bigint > 0),
                    'bad_net', count(*) filter (where s.p ? 'trip_net' and jsonb_typeof(s.p -> 'trip_net') = 'number'
                                 and (s.p ->> 'trip_net')::bigint <> (s.p ->> 'profit')::bigint - (s.p ->> 'tax')::bigint - (s.p ->> 'wages')::bigint - (s.p ->> 'dock_fee')::bigint))
             from sold s),
  'call_fees', (select count(*) from public.fleets f where f.call_fee is not null),
  'gifts', (select count(*) from gifted),
  'gifts_with_hull', (select coalesce(jsonb_agg(jsonb_build_object('player', g.player_id, 'at', g.created_at, 'gift', g.ducats) order by g.created_at), '[]'::jsonb)
                        from gifted g where g.had_hull),
  'week_gifted', (select coalesce(jsonb_agg(x.j), '[]'::jsonb) from (
                    select jsonb_build_object('player', g.player_id,
                             'net', (select w.net from public.houses_week w where w.week = (select d from wk) and w.player_id = g.player_id),
                             'trade', (select sum(h.earned - h.lost - coalesce(h.not_trade, 0)) from public.history_company_day h
                                        where h.player_id = g.player_id and h.day >= (select d from wk) and h.day < (select d from wk) + 7),
                             'all', (select sum(h.earned - h.lost) from public.history_company_day h
                                        where h.player_id = g.player_id and h.day >= (select d from wk) and h.day < (select d from wk) + 7)) as j
                      from (select distinct cg.player_id from public.capital_gifts cg join public.players p on p.id = cg.player_id
                             where not p.is_npc and cg.created_at >= (select d from wk)::timestamp at time zone 'UTC' limit 10) g) x));
rollback;
