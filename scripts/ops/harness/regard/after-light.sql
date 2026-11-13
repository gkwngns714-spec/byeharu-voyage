-- 0373 PROD CHECK (after the light of regard_enabled), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/regard/after-light.sql
-- Run it once BEFORE the deploy (wanted: lit false, news_rows 0, regard_rows 0, fines 0) and at +5 and +30 minutes after it. The window is the last 30 minutes of city flows.
--   lit, news_rows          the switch and 0373's news row (after: true, 1).
--   tax_reads_regard        whether a profit tax reads the factor at all here: the city purses, the influence race and the closed economy must all be on (world.tax_rate). The dock fee needs only the closed economy.
--   by_band                 the companies' profit taxes (TAX) and dock fees (PORT_FEE) the cities took in the window, by the band the payer stands in NOW with the city's holder: payments, coin,
--                           and the factor. A free city is band `free`. For the eye: Friendly rows at 0.9 and Wary rows at 1.25 from the first minute; nothing at a factor the knob does not hold.
--   regard_rows             rows of earned regard (gifts, stakes; later attacks), how many are below zero, and the events that wrote them in the window. No row for a merchant (merchant_rows 0).
--   fines                   FINE flows in the window: count and coin into the capitals, against the FINE rows of the ledger (wanted: the same coin, give or take a flow on the window's edge).
--                           Nothing lowers regard until attacks are lit, so fines are expected 0.
-- A bounded window on treasury_flows, ledger and events; no table is summed whole. Every function called is STABLE (regard_on, regard_of, regard_band, port_nation, city_treasury_on,
-- influence_on, economy_closed).
begin transaction read only;
with w as (select now() - interval '30 minutes' as a, now() as b),
f as (
  select tf.kind, tf.ducats, tf.player_id, public.port_nation(tf.port_id) as nation_id
    from public.treasury_flows tf join public.players pl on pl.id = tf.player_id, w
   where tf.kind in ('TAX', 'PORT_FEE') and tf.created_at >= w.a and tf.created_at < w.b and not pl.is_npc
), g as (
  select f.kind, f.ducats,
         case when f.nation_id is null then jsonb_build_object('band', 'free', 'factor', 1) else public.regard_band(public.regard_of(f.player_id, f.nation_id)) end as band
    from f
)
select public.regard_on() as lit,
       (select count(*) from public.world_news n where n.key = 'update:0373') as news_rows,
       public.city_treasury_on() and public.influence_on() and public.economy_closed() as tax_reads_regard,
       (select coalesce(jsonb_agg(jsonb_build_object('kind', q.kind, 'band', q.band, 'factor', q.factor, 'payments', q.n, 'coin', q.coin) order by q.kind, q.factor), '[]'::jsonb)
          from (select g.kind, g.band ->> 'band' as band, (g.band ->> 'factor')::numeric as factor, count(*) as n, sum(g.ducats) as coin from g group by 1, 2, 3) q) as by_band,
       jsonb_build_object(
         'rows', (select count(*) from public.house_regard),
         'below_zero', (select count(*) from public.house_regard r where r.points < 0),
         'merchant_rows', (select count(*) from public.house_regard r join public.players pl on pl.id = r.player_id where pl.is_npc),
         'events_30m', (select count(*) from public.events e, w where e.kind = 'REGARD_CHANGED' and e.created_at >= w.a and e.created_at < w.b)) as regard_rows,
       jsonb_build_object(
         'flows', (select count(*) from public.treasury_flows tf, w where tf.kind = 'FINE' and tf.created_at >= w.a and tf.created_at < w.b),
         'coin_to_capitals', (select coalesce(sum(tf.ducats), 0) from public.treasury_flows tf, w where tf.kind = 'FINE' and tf.created_at >= w.a and tf.created_at < w.b),
         'coin_in_ledger', (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l, w where l.kind = 'FINE' and l.created_at >= w.a and l.created_at < w.b),
         'events_30m', (select count(*) from public.events e, w where e.kind = 'FINE_PAID' and e.created_at >= w.a and e.created_at < w.b)) as fines;
commit;
